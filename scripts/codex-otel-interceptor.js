#!/usr/bin/env node
/**
 * codex-otel-interceptor.js
 *
 * Codex CLI emits OpenTelemetry *log events* (not traces). This interceptor:
 *   1) Receives Codex OTLP/HTTP log exports (JSON) on a local port
 *   2) Forwards the logs to Grafana Alloy (or any OTLP receiver)
 *   3) Synthesizes OpenInference-style traces (Session → Turn → LLM/Tool) and exports
 *      them to the OTLP traces endpoint.
 *
 * Turn boundaries:
 * - Start: `codex.user_prompt` log event
 * - End: Codex `notify` hook ("agent-turn-complete") posted to `/notify`
 * - Fallback: idle timer after last Codex event
 */

'use strict';

const http = require('node:http');
const https = require('node:https');
const os = require('node:os');
const crypto = require('node:crypto');
const zlib = require('node:zlib');

// =============================================================================
// Config
// =============================================================================

const INTERCEPTOR_VERSION = '0.1.0';

const LISTEN_HOST = process.env.CODEX_OTEL_INTERCEPTOR_HOST || '127.0.0.1';
const LISTEN_PORT = Number.parseInt(process.env.CODEX_OTEL_INTERCEPTOR_PORT || '4319', 10);

const FORWARD_BASE =
  process.env.CODEX_OTEL_INTERCEPTOR_FORWARD_BASE
  || process.env.OTEL_EXPORTER_OTLP_ENDPOINT
  || 'http://127.0.0.1:4318';

const FORWARD_LOGS_ENDPOINT =
  process.env.CODEX_OTEL_INTERCEPTOR_FORWARD_LOGS_ENDPOINT
  || `${FORWARD_BASE.replace(/\/$/, '')}/v1/logs`;

const TRACES_ENDPOINT =
  process.env.CODEX_OTEL_INTERCEPTOR_TRACES_ENDPOINT
  || process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
  || `${FORWARD_BASE.replace(/\/$/, '')}/v1/traces`;

const SESSION_IDLE_END_MS = Number.parseInt(
  process.env.CODEX_OTEL_INTERCEPTOR_SESSION_IDLE_END_MS || `${10 * 60 * 1000}`,
  10
); // default: 10 minutes

const TURN_IDLE_END_MS = Number.parseInt(
  process.env.CODEX_OTEL_INTERCEPTOR_TURN_IDLE_END_MS || '15000',
  10
); // default: 15 seconds (fallback only; prefer notify hook)

const DEBUG = process.env.CODEX_OTEL_INTERCEPTOR_DEBUG === '1';

// =============================================================================
// Utilities
// =============================================================================

function logDebug(...args) {
  if (!DEBUG) return;
  // eslint-disable-next-line no-console
  console.error('[codex-otel-interceptor]', ...args);
}

function msToNanos(ms) {
  return (Math.max(0, Math.floor(ms)) * 1_000_000).toString();
}

function randomHex(bytes) {
  return crypto.randomBytes(bytes).toString('hex');
}

function getPreview(text, maxLen = 80) {
  if (!text || typeof text !== 'string') return '';
  const clean = text.replace(/[\r\n]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (clean.length <= maxLen) return clean;
  return clean.slice(0, Math.max(0, maxLen - 3)) + '...';
}

function anyValueToJs(value) {
  if (!value || typeof value !== 'object') return null;
  if (Object.prototype.hasOwnProperty.call(value, 'stringValue')) return value.stringValue;
  if (Object.prototype.hasOwnProperty.call(value, 'intValue')) {
    const n = Number.parseInt(value.intValue, 10);
    return Number.isFinite(n) ? n : null;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'doubleValue')) return Number(value.doubleValue);
  if (Object.prototype.hasOwnProperty.call(value, 'boolValue')) return Boolean(value.boolValue);
  return null;
}

function attrFind(attributes, key) {
  if (!Array.isArray(attributes)) return null;
  return attributes.find((a) => a && a.key === key) || null;
}

function attrGet(attributes, key) {
  const a = attrFind(attributes, key);
  return a ? anyValueToJs(a.value) : null;
}

function attrGetString(attributes, key) {
  const a = attrFind(attributes, key);
  if (!a || !a.value) return null;
  if (Object.prototype.hasOwnProperty.call(a.value, 'stringValue')) return a.value.stringValue;
  if (Object.prototype.hasOwnProperty.call(a.value, 'intValue')) return String(a.value.intValue);
  return null;
}

function attrUpsert(attributes, key, value) {
  if (!Array.isArray(attributes)) return;
  const existing = attrFind(attributes, key);
  if (existing) {
    existing.value = value;
    return;
  }
  attributes.push({ key, value });
}

function parseIsoToMs(iso) {
  if (!iso || typeof iso !== 'string') return null;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : null;
}

function parseDurationMs(value) {
  if (value == null) return null;
  if (typeof value === 'number' && Number.isFinite(value)) return Math.max(0, Math.floor(value));
  if (typeof value === 'string') {
    const n = Number.parseInt(value, 10);
    return Number.isFinite(n) ? Math.max(0, n) : null;
  }
  return null;
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function maybeGunzip(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 2) return buf;
  if (buf[0] === 0x1f && buf[1] === 0x8b) {
    try {
      return zlib.gunzipSync(buf);
    } catch {
      return buf;
    }
  }
  return buf;
}

function httpPostJson(urlStr, obj, { timeoutMs = 2000 } = {}) {
  try {
    const data = Buffer.from(JSON.stringify(obj));
    const u = new URL(urlStr);
    const mod = u.protocol === 'https:' ? https : http;
    const req = mod.request(
      {
        hostname: u.hostname,
        port: u.port || (u.protocol === 'https:' ? 443 : 80),
        path: u.pathname + (u.search || ''),
        method: 'POST',
        agent: false,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': data.length,
        },
      },
      (res) => res.resume()
    );
    req.on('error', () => {});
    req.setTimeout(timeoutMs, () => req.destroy());
    req.end(data);
  } catch {
    // best-effort
  }
}

function jsonOk(res) {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  res.end('{}');
}

// =============================================================================
// Trace synthesis state
// =============================================================================

function newSession(conversationId, meta) {
  return {
    conversationId,
    traceId: randomHex(16),
    rootSpanId: randomHex(8),
    startTimeMs: meta.timestampMs || Date.now(),
    lastEventTimeMs: meta.timestampMs || Date.now(),
    serviceName: meta.serviceName || 'codex',
    serviceVersion: meta.serviceVersion || meta.appVersion || 'unknown',
    env: meta.env || 'dev',
    terminalType: meta.terminalType || null,
    model: meta.model || null,
    providerName: meta.providerName || 'openai',
    reasoningEffort: meta.reasoningEffort || null,
    approvalPolicy: meta.approvalPolicy || null,
    sandboxPolicy: meta.sandboxPolicy || null,
    mcpServers: meta.mcpServers || null,
    cwd: meta.cwd || null,

    turnCount: 0,
    apiCallCount: 0,
    llmRequestSeq: 0,

    tokens: {
      input: 0,
      output: 0,
      cached: 0,
      reasoning: 0,
      tool: 0,
    },

    currentTurn: null,
    pendingLlmCalls: [],
    pendingToolDecisions: new Map(),

    timers: {
      sessionIdle: null,
      turnIdle: null,
    },
  };
}

const state = {
  sessions: new Map(), // conversationId -> session
};

function scheduleSessionIdleFlush(session) {
  if (session.timers.sessionIdle) clearTimeout(session.timers.sessionIdle);
  session.timers.sessionIdle = setTimeout(() => {
    finalizeSession(session.conversationId, 'idle_timeout');
  }, SESSION_IDLE_END_MS);
}

function scheduleTurnIdleFallback(session) {
  if (session.timers.turnIdle) {
    clearTimeout(session.timers.turnIdle);
    session.timers.turnIdle = null;
  }

  // Only apply idle fallback when there's an active turn and no in-flight activity
  // that would otherwise make the turn look "idle" (e.g., a long-running tool).
  if (!session.currentTurn) return;
  if (session.pendingLlmCalls.length > 0) return;
  for (const v of session.pendingToolDecisions.values()) {
    if (v && v.blocksTurnEnd) return;
  }

  session.timers.turnIdle = setTimeout(() => {
    finalizeTurn(session.conversationId, Date.now(), 'idle_timeout');
  }, TURN_IDLE_END_MS);
}

function baseSpanAttrs(session) {
  return [
    { key: 'gen_ai.system', value: { stringValue: session.providerName || 'openai' } },
    { key: 'gen_ai.provider.name', value: { stringValue: session.providerName || 'openai' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: session.conversationId } },
    { key: 'conversation.id', value: { stringValue: session.conversationId } },
    { key: 'session.id', value: { stringValue: session.conversationId } },
  ];
}

function spanStatusOk() {
  return { code: 'STATUS_CODE_OK' };
}

function spanStatusError(message = '') {
  return { code: 'STATUS_CODE_ERROR', message };
}

function makeSpanRecord(session, span) {
  const resourceAttrs = [
    { key: 'service.name', value: { stringValue: session.serviceName || 'codex' } },
    { key: 'service.version', value: { stringValue: session.serviceVersion || 'unknown' } },
    { key: 'codex.interceptor.version', value: { stringValue: INTERCEPTOR_VERSION } },
    { key: 'host.name', value: { stringValue: os.hostname() } },
    { key: 'os.type', value: { stringValue: os.platform() } },
    { key: 'process.pid', value: { intValue: process.pid.toString() } },
    { key: 'service.instance.id', value: { stringValue: os.hostname() } },
    { key: 'env', value: { stringValue: session.env || 'dev' } },
    { key: 'deployment.environment', value: { stringValue: session.env || 'dev' } },
  ];

  if (session.cwd) {
    resourceAttrs.push({ key: 'working_directory', value: { stringValue: session.cwd } });
  }
  if (session.terminalType) {
    resourceAttrs.push({ key: 'terminal.type', value: { stringValue: session.terminalType } });
  }

  return {
    resourceSpans: [
      {
        resource: { attributes: resourceAttrs },
        scopeSpans: [
          {
            scope: { name: 'codex-otel-interceptor', version: INTERCEPTOR_VERSION },
            spans: [span],
          },
        ],
      },
    ],
  };
}

function exportSpan(session, span) {
  const record = makeSpanRecord(session, span);
  httpPostJson(TRACES_ENDPOINT, record);
}

function endTurnIfOpen(session, endTimeMs, reason) {
  if (!session.currentTurn) return;
  const turn = session.currentTurn;
  session.currentTurn = null;

  const attrs = [
    { key: 'openinference.span.kind', value: { stringValue: 'AGENT' } },
    ...baseSpanAttrs(session),
    { key: 'turn.number', value: { intValue: String(turn.turnNumber) } },
    { key: 'turn.end_reason', value: { stringValue: reason } },
    { key: 'prompt.length', value: { intValue: String(turn.promptLength || 0) } },
  ];

  if (turn.promptPreview) {
    attrs.push({ key: 'input.value', value: { stringValue: turn.promptPreview } });
  }
  if (turn.lastAssistantMessage) {
    attrs.push({ key: 'output.value', value: { stringValue: turn.lastAssistantMessage } });
  }

  if (turn.tokens) {
    attrs.push({ key: 'gen_ai.usage.input_tokens', value: { intValue: String(turn.tokens.input || 0) } });
    attrs.push({ key: 'gen_ai.usage.output_tokens', value: { intValue: String(turn.tokens.output || 0) } });
  }

  const name = turn.name || `Turn #${turn.turnNumber}`;
  exportSpan(session, {
    traceId: session.traceId,
    spanId: turn.spanId,
    parentSpanId: session.rootSpanId,
    name,
    kind: 'SPAN_KIND_INTERNAL',
    startTimeUnixNano: msToNanos(turn.startTimeMs),
    endTimeUnixNano: msToNanos(endTimeMs),
    attributes: attrs,
    status: spanStatusOk(),
  });
}

function finalizeTurn(conversationId, endTimeMs, reason) {
  const session = state.sessions.get(conversationId);
  if (!session) return;
  endTurnIfOpen(session, endTimeMs, reason);
}

function flushPendingLlmCalls(session) {
  for (const call of session.pendingLlmCalls.splice(0)) {
    if (call.timer) clearTimeout(call.timer);
    exportSpan(session, call.span);
  }
}

function finalizeSession(conversationId, reason) {
  const session = state.sessions.get(conversationId);
  if (!session) return;

  if (session.timers.sessionIdle) clearTimeout(session.timers.sessionIdle);
  if (session.timers.turnIdle) clearTimeout(session.timers.turnIdle);

  // End any active turn.
  endTurnIfOpen(session, session.lastEventTimeMs || Date.now(), `session_${reason}`);

  // Export any pending LLM spans without token attachment.
  flushPendingLlmCalls(session);

  const endTimeMs = session.lastEventTimeMs || Date.now();

  const attrs = [
    { key: 'openinference.span.kind', value: { stringValue: 'CHAIN' } },
    ...baseSpanAttrs(session),
    { key: 'session.turn_count', value: { intValue: String(session.turnCount) } },
    { key: 'session.api_call_count', value: { intValue: String(session.apiCallCount) } },
    { key: 'gen_ai.usage.input_tokens', value: { intValue: String(session.tokens.input) } },
    { key: 'gen_ai.usage.output_tokens', value: { intValue: String(session.tokens.output) } },
    { key: 'codex.session_end_reason', value: { stringValue: reason } },
  ];

  if (session.model) attrs.push({ key: 'gen_ai.request.model', value: { stringValue: session.model } });
  if (session.reasoningEffort) attrs.push({ key: 'codex.reasoning_effort', value: { stringValue: session.reasoningEffort } });
  if (session.approvalPolicy) attrs.push({ key: 'codex.approval_policy', value: { stringValue: session.approvalPolicy } });
  if (session.sandboxPolicy) attrs.push({ key: 'codex.sandbox_policy', value: { stringValue: session.sandboxPolicy } });
  if (session.mcpServers) attrs.push({ key: 'codex.mcp_servers', value: { stringValue: session.mcpServers } });

  exportSpan(session, {
    traceId: session.traceId,
    spanId: session.rootSpanId,
    name: 'Codex Session',
    kind: 'SPAN_KIND_INTERNAL',
    startTimeUnixNano: msToNanos(session.startTimeMs),
    endTimeUnixNano: msToNanos(endTimeMs),
    attributes: attrs,
    status: spanStatusOk(),
  });

  state.sessions.delete(conversationId);
}

function getOrCreateSession(conversationId, meta) {
  const existing = state.sessions.get(conversationId);
  if (existing) return existing;
  const created = newSession(conversationId, meta);
  state.sessions.set(conversationId, created);
  return created;
}

function handleCodexLogEvent(meta, attrsObj) {
  const eventName = attrsObj['event.name'];
  if (!eventName || typeof eventName !== 'string') return;

  const conversationId = attrsObj['conversation.id'];
  if (!conversationId || typeof conversationId !== 'string') return;

  const timestampMs = parseIsoToMs(attrsObj['event.timestamp']) || meta.timestampMs || Date.now();
  meta.timestampMs = timestampMs;
  meta.model = attrsObj.model || attrsObj.slug || meta.model;
  meta.terminalType = attrsObj['terminal.type'] || meta.terminalType;

  const session = getOrCreateSession(conversationId, meta);
  session.lastEventTimeMs = timestampMs;
  if (meta.cwd) session.cwd = meta.cwd;

  // Fallback turn completion if notify isn't configured.
  scheduleTurnIdleFallback(session);
  scheduleSessionIdleFlush(session);

  if (eventName === 'codex.conversation_starts') {
    session.providerName = attrsObj.provider_name || session.providerName;
    session.reasoningEffort = attrsObj.reasoning_effort || session.reasoningEffort;
    session.approvalPolicy = attrsObj.approval_policy || session.approvalPolicy;
    session.sandboxPolicy = attrsObj.sandbox_policy || session.sandboxPolicy;
    session.mcpServers = attrsObj.mcp_servers || session.mcpServers;
    session.model = attrsObj.model || attrsObj.slug || session.model;
    logDebug('conversation_starts', conversationId, session.serviceName);
    return;
  }

  if (eventName === 'codex.user_prompt') {
    // Close any prior active turn (shouldn't usually happen, but keep trace consistent).
    if (session.currentTurn) endTurnIfOpen(session, timestampMs, 'new_prompt');

    session.turnCount += 1;
    const turnNumber = session.turnCount;
    const prompt = attrsObj.prompt || null;
    const promptPreview = prompt ? getPreview(prompt, 400) : null;
    const promptLength = parseDurationMs(attrsObj.prompt_length) || (prompt ? prompt.length : 0);

    const turnSpanId = randomHex(8);
    const name = promptPreview ? `Turn #${turnNumber}: ${getPreview(promptPreview, 60)}` : `Turn #${turnNumber}`;
    session.currentTurn = {
      spanId: turnSpanId,
      turnNumber,
      startTimeMs: timestampMs,
      name,
      promptLength,
      promptPreview,
      lastAssistantMessage: null,
      tokens: { input: 0, output: 0 },
    };
    logDebug('user_prompt', conversationId, `turn=${turnNumber}`);
    return;
  }

  if (eventName === 'codex.api_request') {
    session.apiCallCount += 1;
    session.llmRequestSeq += 1;

    const duration = parseDurationMs(attrsObj.duration_ms) || 0;
    const startTimeMs = Math.max(0, timestampMs - duration);
    const endTimeMs = timestampMs;
    const httpStatus = attrsObj['http.response.status_code'];
    const attempt = attrsObj.attempt;
    const errorMessage = attrsObj['error.message'] || null;

    const model = attrsObj.model || attrsObj.slug || session.model || 'unknown';
    const inTurn = Boolean(session.currentTurn);
    const turnNumber = session.currentTurn ? session.currentTurn.turnNumber : 0;
    const parentSpanId = session.currentTurn ? session.currentTurn.spanId : session.rootSpanId;

    const spanId = randomHex(8);
    const base = [
      { key: 'openinference.span.kind', value: { stringValue: 'LLM' } },
      ...baseSpanAttrs(session),
      { key: 'gen_ai.operation.name', value: { stringValue: 'chat' } },
      { key: 'gen_ai.request.model', value: { stringValue: model } },
      { key: 'llm.latency.total_ms', value: { intValue: String(duration) } },
      { key: 'llm.request.sequence', value: { intValue: String(session.llmRequestSeq) } },
      { key: 'turn.number', value: { intValue: String(turnNumber) } },
    ];
    if (typeof httpStatus === 'number') {
      base.push({ key: 'http.response.status_code', value: { intValue: String(httpStatus) } });
    }
    if (typeof attempt === 'number') {
      base.push({ key: 'codex.request.attempt', value: { intValue: String(attempt) } });
    }
    if (errorMessage) {
      base.push({ key: 'error.message', value: { stringValue: String(errorMessage) } });
    }

    const span = {
      traceId: session.traceId,
      spanId,
      parentSpanId,
      name: `LLM Call: ${model}`,
      kind: 'SPAN_KIND_CLIENT',
      startTimeUnixNano: msToNanos(startTimeMs),
      endTimeUnixNano: msToNanos(endTimeMs),
      attributes: base,
      status: errorMessage || (typeof httpStatus === 'number' && httpStatus >= 400) ? spanStatusError(errorMessage || '') : spanStatusOk(),
    };

    const pending = { span, timer: null, inTurn, turnNumber };
    pending.timer = setTimeout(() => {
      // If no tokens arrive (no response.completed sse_event), export anyway.
      exportSpan(session, span);
    }, 10_000);
    session.pendingLlmCalls.push(pending);
    logDebug('api_request', conversationId, `turn=${turnNumber}`, `seq=${session.llmRequestSeq}`);
    return;
  }

  if (eventName === 'codex.sse_event') {
    const kind = attrsObj['event.kind'];
    if (kind === 'response.completed') {
      const inputTokensParsed = parseDurationMs(attrsObj.input_token_count);
      const outputTokensParsed = parseDurationMs(attrsObj.output_token_count);
      const cachedTokensParsed = parseDurationMs(attrsObj.cached_token_count);
      const reasoningTokensParsed = parseDurationMs(attrsObj.reasoning_token_count);
      const toolTokensParsed = parseDurationMs(attrsObj.tool_token_count);

      // Codex can emit multiple `response.completed` events; some may omit usage.
      // Only consume a pending api_request when token usage is actually present.
      const hasUsage = [
        inputTokensParsed,
        outputTokensParsed,
        cachedTokensParsed,
        reasoningTokensParsed,
        toolTokensParsed,
      ].some((v) => v != null);

      if (!hasUsage) return;

      const inputTokens = inputTokensParsed || 0;
      const outputTokens = outputTokensParsed || 0;
      const cachedTokens = cachedTokensParsed || 0;
      const reasoningTokens = reasoningTokensParsed || 0;
      const toolTokens = toolTokensParsed || 0;

      const pending = session.pendingLlmCalls.shift();
      if (pending) {
        if (pending.timer) clearTimeout(pending.timer);
        const span = pending.span;
        span.name = `LLM Call: ${attrGetString(span.attributes, 'gen_ai.request.model') || 'model'} (${inputTokens}→${outputTokens} tokens)`;

        attrUpsert(span.attributes, 'gen_ai.usage.input_tokens', { intValue: String(inputTokens) });
        attrUpsert(span.attributes, 'gen_ai.usage.output_tokens', { intValue: String(outputTokens) });
        if (cachedTokensParsed != null) attrUpsert(span.attributes, 'codex.usage.cached_token_count', { intValue: String(cachedTokens) });
        if (reasoningTokensParsed != null) attrUpsert(span.attributes, 'codex.usage.reasoning_token_count', { intValue: String(reasoningTokens) });
        if (toolTokensParsed != null) attrUpsert(span.attributes, 'codex.usage.tool_token_count', { intValue: String(toolTokens) });

        exportSpan(session, span);

        // Aggregate counts at session + current turn levels.
        session.tokens.input += inputTokens;
        session.tokens.output += outputTokens;
        session.tokens.cached += cachedTokens;
        session.tokens.reasoning += reasoningTokens;
        session.tokens.tool += toolTokens;

        if (session.currentTurn) {
          session.currentTurn.tokens.input += inputTokens;
          session.currentTurn.tokens.output += outputTokens;
        }
      }
    }
    return;
  }

  if (eventName === 'codex.tool_decision') {
    const callId = attrsObj.call_id;
    const toolName = attrsObj.tool_name;
    if (callId && toolName) {
      const decision = attrsObj.decision || null;
      const blocksTurnEnd = Boolean(decision) && !['denied', 'abort'].includes(String(decision));
      session.pendingToolDecisions.set(String(callId), {
        toolName: String(toolName),
        decision,
        source: attrsObj.source || null,
        timestampMs,
        blocksTurnEnd,
      });
    }
    return;
  }

  if (eventName === 'codex.tool_result') {
    const toolName = attrsObj.tool_name || 'tool';
    const duration = parseDurationMs(attrsObj.duration_ms) || 0;
    const startTimeMs = Math.max(0, timestampMs - duration);
    const endTimeMs = timestampMs;
    const callId = attrsObj.call_id ? String(attrsObj.call_id) : null;
    const success = String(attrsObj.success || 'true').toLowerCase() === 'true';

    const parentSpanId = session.currentTurn ? session.currentTurn.spanId : session.rootSpanId;
    const turnNumber = session.currentTurn ? session.currentTurn.turnNumber : 0;

    const spanAttrs = [
      { key: 'openinference.span.kind', value: { stringValue: 'TOOL' } },
      ...baseSpanAttrs(session),
      { key: 'gen_ai.tool.name', value: { stringValue: String(toolName) } },
      { key: 'turn.number', value: { intValue: String(turnNumber) } },
      { key: 'tool.success', value: { boolValue: success } },
      { key: 'tool.duration_ms', value: { intValue: String(duration) } },
    ];

    if (callId) spanAttrs.push({ key: 'tool.call_id', value: { stringValue: callId } });

    const decision = callId ? session.pendingToolDecisions.get(callId) : null;
    if (decision) {
      if (decision.decision) spanAttrs.push({ key: 'tool.decision', value: { stringValue: String(decision.decision) } });
      if (decision.source) spanAttrs.push({ key: 'tool.decision_source', value: { stringValue: String(decision.source) } });
      session.pendingToolDecisions.delete(callId);
    }

    // Avoid high-volume outputs; keep only a short preview.
    if (attrsObj.output && typeof attrsObj.output === 'string') {
      spanAttrs.push({ key: 'tool.output_preview', value: { stringValue: getPreview(attrsObj.output, 400) } });
      spanAttrs.push({ key: 'tool.output_length', value: { intValue: String(attrsObj.output.length) } });
    }

    exportSpan(session, {
      traceId: session.traceId,
      spanId: randomHex(8),
      parentSpanId,
      name: `Tool: ${toolName}`,
      kind: 'SPAN_KIND_INTERNAL',
      startTimeUnixNano: msToNanos(startTimeMs),
      endTimeUnixNano: msToNanos(endTimeMs),
      attributes: spanAttrs,
      status: success ? spanStatusOk() : spanStatusError('tool_failed'),
    });

    return;
  }
}

function handleNotify(notification) {
  if (!notification || typeof notification !== 'object') return;
  if (notification.type !== 'agent-turn-complete') return;

  const conversationId = notification['thread-id'];
  if (!conversationId || typeof conversationId !== 'string') return;

  const session = state.sessions.get(conversationId);
  if (!session) return;

  if (notification.cwd && typeof notification.cwd === 'string') {
    session.cwd = notification.cwd;
  }

  const msg = notification['last-assistant-message'];
  if (session.currentTurn && typeof msg === 'string') {
    session.currentTurn.lastAssistantMessage = getPreview(msg, 400);
  }

  finalizeTurn(conversationId, Date.now(), 'notify.agent-turn-complete');
}

// =============================================================================
// HTTP server
// =============================================================================

async function handleLogsRequest(req, res) {
  const raw = await readRequestBody(req);
  const bodyBuf = maybeGunzip(raw);

  let otlp;
  try {
    otlp = JSON.parse(bodyBuf.toString('utf8'));
  } catch (e) {
    logDebug('failed to parse logs json; forwarding raw only', e?.message);
    // Forward as-is, best-effort.
    try {
      httpPostJson(FORWARD_LOGS_ENDPOINT, JSON.parse(bodyBuf.toString('utf8')));
    } catch {}
    return jsonOk(res);
  }

  const events = [];
  const resourceLogs = Array.isArray(otlp.resourceLogs) ? otlp.resourceLogs : [];
  for (const rl of resourceLogs) {
    const resourceAttrs = Array.isArray(rl?.resource?.attributes) ? rl.resource.attributes : [];
    const serviceName = attrGetString(resourceAttrs, 'service.name') || 'codex';
    const serviceVersion = attrGetString(resourceAttrs, 'service.version') || 'unknown';
    const env = attrGetString(resourceAttrs, 'env') || 'dev';

    const scopeLogs = Array.isArray(rl?.scopeLogs) ? rl.scopeLogs : [];
    for (const sl of scopeLogs) {
      const logRecords = Array.isArray(sl?.logRecords) ? sl.logRecords : [];
      for (const lr of logRecords) {
        const attrs = Array.isArray(lr?.attributes) ? lr.attributes : [];
        const conversationId = attrGetString(attrs, 'conversation.id');
        if (conversationId) {
          // Normalize join key with Claude traces: use session.id everywhere.
          attrUpsert(attrs, 'session.id', { stringValue: conversationId });
        }

        const attrsObj = {};
        for (const a of attrs) {
          if (!a || typeof a.key !== 'string') continue;
          attrsObj[a.key] = anyValueToJs(a.value);
        }

        const meta = {
          serviceName,
          serviceVersion,
          env,
          appVersion: attrsObj['app.version'] || null,
          terminalType: attrsObj['terminal.type'] || null,
          providerName: attrsObj.provider_name || null,
          reasoningEffort: attrsObj.reasoning_effort || null,
          approvalPolicy: attrsObj.approval_policy || null,
          sandboxPolicy: attrsObj.sandbox_policy || null,
          mcpServers: attrsObj.mcp_servers || null,
          model: attrsObj.model || attrsObj.slug || null,
          timestampMs: parseIsoToMs(attrsObj['event.timestamp']),
          cwd: null,
        };

        events.push({ meta, attrsObj });
      }
    }
  }

  // Codex exports can batch log records; ordering within a batch is not guaranteed.
  // Sort by `event.timestamp` so response.completed attaches to the correct api_request.
  events.sort((a, b) => (a.meta.timestampMs || 0) - (b.meta.timestampMs || 0));
  for (const e of events) {
    handleCodexLogEvent(e.meta, e.attrsObj);
  }

  // Forward (mutated) logs to Alloy.
  httpPostJson(FORWARD_LOGS_ENDPOINT, otlp, { timeoutMs: 2000 });
  return jsonOk(res);
}

async function handleNotifyRequest(req, res) {
  const raw = await readRequestBody(req);
  const bodyBuf = maybeGunzip(raw);
  let obj;
  try {
    obj = JSON.parse(bodyBuf.toString('utf8'));
  } catch {
    return jsonOk(res);
  }
  try {
    handleNotify(obj);
  } catch (e) {
    logDebug('notify handler error', e?.message);
  }
  return jsonOk(res);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      res.statusCode = 200;
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }

    if (req.method === 'POST' && url.pathname === '/v1/logs') {
      return await handleLogsRequest(req, res);
    }

    if (req.method === 'POST' && url.pathname === '/notify') {
      return await handleNotifyRequest(req, res);
    }

    res.statusCode = 404;
    res.end('');
  } catch {
    res.statusCode = 500;
    res.end('');
  }
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  // eslint-disable-next-line no-console
  console.error(`[codex-otel-interceptor v${INTERCEPTOR_VERSION}] listening on http://${LISTEN_HOST}:${LISTEN_PORT}`);
  // eslint-disable-next-line no-console
  console.error(`[codex-otel-interceptor] forward logs  -> ${FORWARD_LOGS_ENDPOINT}`);
  // eslint-disable-next-line no-console
  console.error(`[codex-otel-interceptor] export traces -> ${TRACES_ENDPOINT}`);
});
