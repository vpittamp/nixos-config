#!/usr/bin/env node
/**
 * gemini-otel-interceptor.js
 *
 * Gemini CLI emits OTLP/HTTP **JSON** payloads for logs/metrics/traces, but posts them to `/`
 * (not to `/v1/logs`, `/v1/metrics`, `/v1/traces`). The native spans are currently low-signal
 * (generic HTTP client spans), so we synthesize Claude/Codex-style logical traces from the
 * structured log events:
 *
 * Session → Turn → LLM/Tool
 *
 * - Start turn: `gemini_cli.user_prompt`
 * - LLM call: `gemini_cli.api_request` + `gemini_cli.api_response`/`gemini_cli.api_error`
 * - Tool: `gemini_cli.tool_call`
 * - End turn: idle debounce (no official hook available)
 */

'use strict';

const http = require('node:http');
const os = require('node:os');
const fs = require('node:fs');
const {
  anyValueToJs,
  attrGet,
  attrGetInt,
  attrGetString,
  attrUpsert,
  getPreview,
  getToolSpanName,
  httpPostJson,
  maybeGunzip,
  msToNanos,
  parseDurationMs,
  parseIsoToMs,
  randomHex,
  readRequestBody,
  toSafeString,
  tryParseJson,
} = require('./otel-interceptor-common');

// =============================================================================
// Config
// =============================================================================

const INTERCEPTOR_VERSION = '0.1.3';  // Native session + pane-aware correlation metadata

const LISTEN_HOST = process.env.GEMINI_OTEL_INTERCEPTOR_HOST || '127.0.0.1';
const LISTEN_PORT = Number.parseInt(process.env.GEMINI_OTEL_INTERCEPTOR_PORT || '4322', 10);

const FORWARD_BASE =
  process.env.GEMINI_OTEL_INTERCEPTOR_FORWARD_BASE
  || process.env.OTEL_EXPORTER_OTLP_ENDPOINT
  || 'http://127.0.0.1:4318';

const FORWARD_LOGS_ENDPOINT =
  process.env.GEMINI_OTEL_INTERCEPTOR_FORWARD_LOGS_ENDPOINT
  || `${FORWARD_BASE.replace(/\/$/, '')}/v1/logs`;

const FORWARD_METRICS_ENDPOINT =
  process.env.GEMINI_OTEL_INTERCEPTOR_FORWARD_METRICS_ENDPOINT
  || `${FORWARD_BASE.replace(/\/$/, '')}/v1/metrics`;

const TRACES_ENDPOINT =
  process.env.GEMINI_OTEL_INTERCEPTOR_TRACES_ENDPOINT
  || process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
  || `${FORWARD_BASE.replace(/\/$/, '')}/v1/traces`;

// Gemini emits low-signal auto-instrumentation HTTP spans; drop by default to reduce noise.
const FORWARD_NATIVE_TRACES = process.env.GEMINI_OTEL_INTERCEPTOR_FORWARD_NATIVE_TRACES === '1';

const SESSION_IDLE_END_MS = Number.parseInt(
  process.env.GEMINI_OTEL_INTERCEPTOR_SESSION_IDLE_END_MS || `${10 * 60 * 1000}`,
  10
); // default: 10 minutes

const TURN_IDLE_END_MS = Number.parseInt(
  process.env.GEMINI_OTEL_INTERCEPTOR_TURN_IDLE_END_MS || '15000',
  10
); // default: 15 seconds

// For one-shot commands (non-interactive), export the Session/root span as soon as the Turn completes
// so Tempo doesn't show "<root span not yet received>" for minutes.
const ONESHOT_SESSION_FINALIZE_MS = Number.parseInt(
  process.env.GEMINI_OTEL_INTERCEPTOR_ONESHOT_SESSION_FINALIZE_MS || '0',
  10
); // default: immediate

const DEBUG = process.env.GEMINI_OTEL_INTERCEPTOR_DEBUG === '1';

// Feature 132: Langfuse Integration Configuration
const LANGFUSE_ENABLED = process.env.LANGFUSE_ENABLED === '1';
const LANGFUSE_USER_ID = process.env.LANGFUSE_USER_ID || null;
const LANGFUSE_TAGS = (() => {
  const tags = process.env.LANGFUSE_TAGS;
  if (!tags) return null;
  try {
    return JSON.parse(tags);
  } catch {
    return null;
  }
})();

// =============================================================================
// Utilities
// =============================================================================

function logDebug(...args) {
  if (!DEBUG) return;
  // eslint-disable-next-line no-console
  console.error('[gemini-otel-interceptor]', ...args);
}

function readProcessEnvByPid(pid) {
  if (!pid || !Number.isFinite(pid)) return {};
  try {
    const raw = fs.readFileSync(`/proc/${pid}/environ`);
    const out = {};
    for (const entry of raw.toString('utf8').split('\u0000')) {
      if (!entry) continue;
      const idx = entry.indexOf('=');
      if (idx <= 0) continue;
      out[entry.slice(0, idx)] = entry.slice(idx + 1);
    }
    return out;
  } catch {
    return {};
  }
}

function extractGeminiTextsFromResponseChunk(chunk) {
  const candidates = Array.isArray(chunk?.candidates) ? chunk.candidates : [];
  const visibleParts = [];
  const thoughtParts = [];

  for (const c of candidates) {
    const parts = Array.isArray(c?.content?.parts) ? c.content.parts : [];
    for (const p of parts) {
      if (!p || typeof p.text !== 'string') continue;
      if (p.thought === true) thoughtParts.push(p.text);
      else visibleParts.push(p.text);
    }
  }

  return {
    visibleText: visibleParts.length > 0 ? visibleParts.join('\n') : null,
    thoughtText: thoughtParts.length > 0 ? thoughtParts.join('\n') : null,
  };
}

function extractGeminiResponseText(responseText) {
  if (!responseText || typeof responseText !== 'string') return { text: null, thoughts: null };

  const parsed = tryParseJson(responseText);
  if (!parsed) return { text: responseText, thoughts: null };

  const chunks = Array.isArray(parsed) ? parsed : [parsed];
  const visible = [];
  const thoughts = [];

  for (const chunk of chunks) {
    const out = extractGeminiTextsFromResponseChunk(chunk);
    if (out.visibleText) visible.push(out.visibleText);
    if (out.thoughtText) thoughts.push(out.thoughtText);
  }

  return {
    text: visible.length > 0 ? visible.join('\n') : (thoughts.length > 0 ? thoughts.join('\n') : null),
    thoughts: thoughts.length > 0 ? thoughts.join('\n') : null,
  };
}

function jsonOk(res) {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  // OTLP/HTTP JSON responses usually return `partialSuccess`; Gemini accepts this shape.
  res.end('{"partialSuccess":{}}');
}

// =============================================================================
// Feature 132: Langfuse Attribute Helpers
// =============================================================================

/**
 * Add Langfuse-specific attributes to a span attributes array.
 * @param {Array} attributes - OTEL span attributes array
 * @param {object} options - Langfuse options
 */
function addLangfuseAttributes(attributes, options) {
  if (!LANGFUSE_ENABLED) return;

  const { spanKind, sessionId } = options;

  // Add OpenInference span kind
  if (spanKind) {
    attributes.push({ key: 'openinference.span.kind', value: { stringValue: spanKind } });
  }

  // Add Langfuse session ID
  if (sessionId) {
    attributes.push({ key: 'langfuse.session.id', value: { stringValue: sessionId } });
  }

  // Add user ID if configured
  if (LANGFUSE_USER_ID) {
    attributes.push({ key: 'langfuse.user.id', value: { stringValue: LANGFUSE_USER_ID } });
  }

  // Add tags if configured
  if (LANGFUSE_TAGS && Array.isArray(LANGFUSE_TAGS)) {
    attributes.push({ key: 'langfuse.tags', value: { stringValue: JSON.stringify(LANGFUSE_TAGS) } });
  }
}

/**
 * Build Langfuse-compatible usage details object.
 * @param {object} tokens - Token counts object
 * @returns {object} Usage details for Langfuse
 */
function buildLangfuseUsageDetails(tokens) {
  const details = {
    input: tokens.input || 0,
    output: tokens.output || 0,
    total: (tokens.input || 0) + (tokens.output || 0),
  };
  if (tokens.cached > 0) details.cached = tokens.cached;
  if (tokens.thoughts > 0) details.thoughts = tokens.thoughts;
  return details;
}

// =============================================================================
// Trace synthesis state
// =============================================================================

const state = {
  sessions: new Map(), // session.id -> session state
};

function newSession(sessionId, meta) {
  return {
    sessionId,
    traceId: randomHex(16),
    rootSpanId: randomHex(8),
    startTimeMs: meta.timestampMs || Date.now(),
    lastEventTimeMs: meta.timestampMs || Date.now(),
    serviceName: meta.serviceName || 'gemini-cli',
    serviceVersion: meta.serviceVersion || meta.appVersion || 'unknown',
    env: meta.env || 'dev',
    interactive: meta.interactive ?? null,

    providerName: meta.providerName || 'Google',
    model: meta.model || null,
    approvalMode: meta.approvalMode || null,
    sandboxEnabled: meta.sandboxEnabled ?? null,
    mcpServers: meta.mcpServers || null,
    cwd: meta.cwd || null,
    projectName: meta.projectName || null,
    projectPath: meta.projectPath || null,
    tmuxSession: meta.tmuxSession || null,
    tmuxWindow: meta.tmuxWindow || null,
    tmuxPane: meta.tmuxPane || null,
    pty: meta.pty || null,
    // Feature 135: Store client PID for window correlation
    clientPid: meta.clientPid || null,

    turnCount: 0,
    apiCallCount: 0,
    llmRequestSeq: 0,
    tokens: { input: 0, output: 0, cached: 0, thoughts: 0, tool: 0, total: 0 },

    // Linkage + summary counters (mirrors Claude Code conventions where possible)
    lastLlmSpanId: null,
    pendingToolSpanRefs: [],
    toolCallCount: 0,
    toolErrorCount: 0,

    currentTurn: null,

    // prompt_id -> queue of pending api requests
    pendingApiRequests: new Map(),

    timers: { sessionIdle: null, turnIdle: null },
  };
}

function getOrCreateSession(sessionId, meta) {
  const existing = state.sessions.get(sessionId);
  if (existing) return existing;
  const created = newSession(sessionId, meta);
  state.sessions.set(sessionId, created);
  return created;
}

function scheduleSessionIdleFlush(session) {
  if (session.timers.sessionIdle) clearTimeout(session.timers.sessionIdle);
  session.timers.sessionIdle = setTimeout(() => {
    finalizeSession(session.sessionId, 'idle_timeout');
  }, SESSION_IDLE_END_MS);
}

function scheduleTurnIdleFallback(session) {
  if (session.timers.turnIdle) clearTimeout(session.timers.turnIdle);
  if (!session.currentTurn) return;
  session.timers.turnIdle = setTimeout(() => {
    finalizeTurn(session.sessionId, Date.now(), 'idle_timeout');
  }, TURN_IDLE_END_MS);
}

function baseSpanAttrs(session) {
  return [
    { key: 'gen_ai.system', value: { stringValue: session.providerName || 'Google' } },
    { key: 'gen_ai.provider.name', value: { stringValue: session.providerName || 'Google' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: session.sessionId } },
    { key: 'conversation.id', value: { stringValue: session.sessionId } },
    { key: 'session.id', value: { stringValue: session.sessionId } },
  ];
}

function spanStatusOk() {
  return { code: 'STATUS_CODE_OK' };
}

function spanStatusError(message = '') {
  return { code: 'STATUS_CODE_ERROR', message };
}

function makeSpanRecord(session, span) {
  // Feature 137: Only include process.pid if we have the real client PID
  // Don't fall back to interceptor's PID as that would cause incorrect window correlation
  const resourceAttrs = [
    { key: 'service.name', value: { stringValue: session.serviceName || 'gemini-cli' } },
    { key: 'service.version', value: { stringValue: session.serviceVersion || 'unknown' } },
    { key: 'gemini.interceptor.version', value: { stringValue: INTERCEPTOR_VERSION } },
    { key: 'host.name', value: { stringValue: os.hostname() } },
    { key: 'os.type', value: { stringValue: os.platform() } },
    { key: 'service.instance.id', value: { stringValue: os.hostname() } },
    { key: 'env', value: { stringValue: session.env || 'dev' } },
    { key: 'deployment.environment', value: { stringValue: session.env || 'dev' } },
  ];
  // Only add PID if we have the real client PID from incoming telemetry
  if (session.clientPid) {
    resourceAttrs.push({ key: 'process.pid', value: { intValue: session.clientPid.toString() } });
  }

  if (session.cwd) resourceAttrs.push({ key: 'working_directory', value: { stringValue: session.cwd } });
  if (session.projectPath) {
    resourceAttrs.push({ key: 'project_path', value: { stringValue: session.projectPath } });
    resourceAttrs.push({ key: 'i3pm.project_path', value: { stringValue: session.projectPath } });
  }
  if (session.projectName) {
    resourceAttrs.push({ key: 'i3pm.project_name', value: { stringValue: session.projectName } });
  }
  if (session.tmuxSession) {
    resourceAttrs.push({ key: 'terminal.tmux.session', value: { stringValue: session.tmuxSession } });
  }
  if (session.tmuxWindow) {
    resourceAttrs.push({ key: 'terminal.tmux.window', value: { stringValue: session.tmuxWindow } });
  }
  if (session.tmuxPane) {
    resourceAttrs.push({ key: 'terminal.tmux.pane', value: { stringValue: session.tmuxPane } });
  }
  if (session.pty) {
    resourceAttrs.push({ key: 'terminal.pty', value: { stringValue: session.pty } });
  }

  return {
    resourceSpans: [
      {
        resource: { attributes: resourceAttrs },
        scopeSpans: [
          {
            scope: { name: 'gemini-otel-interceptor', version: INTERCEPTOR_VERSION },
            spans: [span],
          },
        ],
      },
    ],
  };
}

function exportSpan(session, span) {
  httpPostJson(TRACES_ENDPOINT, makeSpanRecord(session, span));
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
    { key: 'turn.tool_call_count', value: { intValue: String(turn.toolCallCount || 0) } },
    { key: 'turn.tool_error_count', value: { intValue: String(turn.toolErrorCount || 0) } },
  ];

  if (turn.promptId) attrs.push({ key: 'gemini.prompt_id', value: { stringValue: String(turn.promptId) } });
  if (turn.promptPreview) attrs.push({ key: 'input.value', value: { stringValue: turn.promptPreview } });
  if (turn.lastAssistantMessage) attrs.push({ key: 'output.value', value: { stringValue: turn.lastAssistantMessage } });

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

function finalizeTurn(sessionId, endTimeMs, reason) {
  const session = state.sessions.get(sessionId);
  if (!session) return;
  endTurnIfOpen(session, endTimeMs, reason);

  // In one-shot mode (non-interactive), close the session promptly once the turn is done so
  // Tempo receives the root span and can display the correct root service name.
  if (session.interactive === false && reason === 'idle_timeout') {
    const delay = Number.isFinite(ONESHOT_SESSION_FINALIZE_MS) && ONESHOT_SESSION_FINALIZE_MS > 0
      ? ONESHOT_SESSION_FINALIZE_MS
      : 0;
    setTimeout(() => finalizeSession(sessionId, 'oneshot_turn_complete'), delay);
  }
}

function finalizeSession(sessionId, reason) {
  const session = state.sessions.get(sessionId);
  if (!session) return;

  if (session.timers.sessionIdle) clearTimeout(session.timers.sessionIdle);
  if (session.timers.turnIdle) clearTimeout(session.timers.turnIdle);

  // End any active turn.
  endTurnIfOpen(session, session.lastEventTimeMs || Date.now(), `session_${reason}`);

  const endTimeMs = session.lastEventTimeMs || Date.now();

  const attrs = [
    { key: 'openinference.span.kind', value: { stringValue: 'CHAIN' } },
    ...baseSpanAttrs(session),
    { key: 'session.turn_count', value: { intValue: String(session.turnCount) } },
    { key: 'session.api_call_count', value: { intValue: String(session.apiCallCount) } },
    { key: 'session.tool_call_count', value: { intValue: String(session.toolCallCount) } },
    { key: 'session.tool_error_count', value: { intValue: String(session.toolErrorCount) } },
    { key: 'gen_ai.usage.input_tokens', value: { intValue: String(session.tokens.input) } },
    { key: 'gen_ai.usage.output_tokens', value: { intValue: String(session.tokens.output) } },
    { key: 'gemini.usage.cached_content_token_count', value: { intValue: String(session.tokens.cached) } },
    { key: 'gemini.usage.thoughts_token_count', value: { intValue: String(session.tokens.thoughts) } },
    { key: 'gemini.usage.tool_token_count', value: { intValue: String(session.tokens.tool) } },
    { key: 'gemini.usage.total_token_count', value: { intValue: String(session.tokens.total) } },
    { key: 'gemini.session_end_reason', value: { stringValue: reason } },
  ];

  if (session.model) attrs.push({ key: 'gen_ai.request.model', value: { stringValue: session.model } });
  if (session.approvalMode) attrs.push({ key: 'gemini.approval_mode', value: { stringValue: String(session.approvalMode) } });
  if (session.sandboxEnabled != null) attrs.push({ key: 'gemini.sandbox_enabled', value: { boolValue: Boolean(session.sandboxEnabled) } });
  if (session.mcpServers) attrs.push({ key: 'gemini.mcp_servers', value: { stringValue: String(session.mcpServers) } });

  // Feature 132: Add Langfuse-specific attributes
  addLangfuseAttributes(attrs, { spanKind: 'CHAIN', sessionId: sessionId });
  if (LANGFUSE_ENABLED) {
    attrs.push({ key: 'langfuse.trace.name', value: { stringValue: 'Gemini Session' } });
    const usageDetails = buildLangfuseUsageDetails(session.tokens);
    attrs.push({ key: 'langfuse.observation.usage_details', value: { stringValue: JSON.stringify(usageDetails) } });
  }

  exportSpan(session, {
    traceId: session.traceId,
    spanId: session.rootSpanId,
    name: 'Gemini Session',
    kind: 'SPAN_KIND_INTERNAL',
    startTimeUnixNano: msToNanos(session.startTimeMs),
    endTimeUnixNano: msToNanos(endTimeMs),
    attributes: attrs,
    status: spanStatusOk(),
  });

  state.sessions.delete(sessionId);
}

function extractCwdFromRequestText(requestText) {
  if (!requestText || typeof requestText !== 'string') return null;
  // The CLI injects a system message containing this line.
  const m = requestText.match(/I'm currently working in the directory:\\s*([^\\r\\n]+)/);
  if (m && m[1]) return m[1].trim();
  return null;
}

function handleGeminiLogEvent(meta, attrsObj) {
  const eventName = attrsObj['event.name'];
  if (!eventName || typeof eventName !== 'string') return;

  const sessionId =
    (typeof attrsObj['session.id'] === 'string' && attrsObj['session.id'])
    || (typeof attrsObj.sessionId === 'string' && attrsObj.sessionId)
    || null;
  if (!sessionId || typeof sessionId !== 'string') return;

  const timestampMs = parseIsoToMs(attrsObj['event.timestamp']) || meta.timestampMs || Date.now();
  meta.timestampMs = timestampMs;
  meta.model = attrsObj.model || meta.model;

  const session = getOrCreateSession(sessionId, meta);
  session.lastEventTimeMs = timestampMs;
  if (meta.cwd) session.cwd = meta.cwd;
  if (meta.projectName) session.projectName = meta.projectName;
  if (meta.projectPath) session.projectPath = meta.projectPath;
  if (meta.tmuxSession) session.tmuxSession = meta.tmuxSession;
  if (meta.tmuxWindow) session.tmuxWindow = meta.tmuxWindow;
  if (meta.tmuxPane) session.tmuxPane = meta.tmuxPane;
  if (meta.pty) session.pty = meta.pty;

  scheduleSessionIdleFlush(session);
  scheduleTurnIdleFallback(session);

  if (eventName === 'gemini_cli.config') {
    session.model = attrsObj.model || session.model;
    session.approvalMode = attrsObj.approval_mode || session.approvalMode;
    if (typeof attrsObj.interactive === 'boolean') session.interactive = attrsObj.interactive;
    else if (attrsObj.interactive != null) session.interactive = String(attrsObj.interactive).toLowerCase() === 'true';
    if (attrsObj.sandbox_enabled != null) session.sandboxEnabled = Boolean(attrsObj.sandbox_enabled);
    if (attrsObj.mcp_servers) session.mcpServers = String(attrsObj.mcp_servers);
    return;
  }

  if (eventName === 'gemini_cli.user_prompt') {
    // Close any prior active turn.
    if (session.currentTurn) endTurnIfOpen(session, timestampMs, 'new_prompt');

    session.turnCount += 1;
    const turnNumber = session.turnCount;
    const prompt = attrsObj.prompt || null;
    const promptPreview = prompt ? getPreview(prompt, 400) : null;
    const promptLength = parseDurationMs(attrsObj.prompt_length) || (prompt ? prompt.length : 0);
    const promptId = attrsObj.prompt_id || null;

    const turnSpanId = randomHex(8);
    const name = promptPreview ? `Turn #${turnNumber}: ${getPreview(promptPreview, 60)}` : `Turn #${turnNumber}`;
    session.currentTurn = {
      spanId: turnSpanId,
      turnNumber,
      startTimeMs: timestampMs,
      name,
      promptLength,
      promptPreview,
      promptId,
      lastAssistantMessage: null,
      tokens: { input: 0, output: 0 },
      lastLlmSpanId: null,
      pendingToolSpanRefs: [],
      toolCallCount: 0,
      toolErrorCount: 0,
    };
    return;
  }

  if (eventName === 'gemini_cli.api_request') {
    session.apiCallCount += 1;
    session.llmRequestSeq += 1;

    const promptId = attrsObj.prompt_id ? String(attrsObj.prompt_id) : null;
    const model = attrsObj.model || session.model || 'unknown';
    const requestText = attrsObj.request_text || null;

    const cwd = extractCwdFromRequestText(requestText);
    if (cwd) session.cwd = cwd;

    if (promptId) {
      const q = session.pendingApiRequests.get(promptId) || [];
      q.push({
        timestampMs,
        sequence: session.llmRequestSeq,
        model,
        requestTextPreview: requestText ? getPreview(requestText, 400) : null,
        requestTextLength: requestText && typeof requestText === 'string' ? requestText.length : 0,
      });
      session.pendingApiRequests.set(promptId, q);
    }
    return;
  }

  if (eventName === 'gemini_cli.api_response' || eventName === 'gemini_cli.api_error') {
    const promptId = attrsObj.prompt_id ? String(attrsObj.prompt_id) : null;
    const model = attrsObj.model || session.model || 'unknown';

    const statusCode = attrsObj.status_code;
    const duration = parseDurationMs(attrsObj.duration_ms ?? attrsObj.latency_ms) || 0;
    const startTimeMs = Math.max(0, timestampMs - duration);
    const endTimeMs = timestampMs;

    const inputTokens = parseDurationMs(attrsObj.input_token_count) || 0;
    const outputTokens = parseDurationMs(attrsObj.output_token_count) || 0;
    const cachedTokens = parseDurationMs(attrsObj.cached_content_token_count) || 0;
    const thoughtsTokens = parseDurationMs(attrsObj.thoughts_token_count) || 0;
    const toolTokens = parseDurationMs(attrsObj.tool_token_count) || 0;
    const totalTokens = parseDurationMs(attrsObj.total_token_count) || (inputTokens + outputTokens);

    const rawResponseText = typeof attrsObj.response_text === 'string' ? attrsObj.response_text : null;
    const extracted = rawResponseText ? extractGeminiResponseText(rawResponseText) : { text: null, thoughts: null };
    const assistantPreview = extracted.text ? getPreview(extracted.text, 400) : null;

    // Attach a short response preview to the current turn (prefer extracted model text over raw JSON).
    if (session.currentTurn && assistantPreview) {
      session.currentTurn.lastAssistantMessage = assistantPreview;
    }

    const pending = promptId ? (session.pendingApiRequests.get(promptId) || []).shift() : null;
    if (promptId && pending) {
      const q = session.pendingApiRequests.get(promptId) || [];
      if (q.length === 0) session.pendingApiRequests.delete(promptId);
      else session.pendingApiRequests.set(promptId, q);
    }

    const inTurn = Boolean(session.currentTurn);
    const turnNumber = session.currentTurn ? session.currentTurn.turnNumber : 0;
    const parentSpanId = session.currentTurn ? session.currentTurn.spanId : session.rootSpanId;
    const ctx = session.currentTurn || session;

    const consumedToolRefs = Array.isArray(ctx.pendingToolSpanRefs) ? ctx.pendingToolSpanRefs.splice(0) : [];
    const links = [];
    for (const t of consumedToolRefs) {
      if (!t || typeof t.spanId !== 'string') continue;
      const linkAttrs = [{ key: 'link.type', value: { stringValue: 'consumes_tool_result' } }];
      if (t.callId) linkAttrs.push({ key: 'gen_ai.tool.call.id', value: { stringValue: String(t.callId) } });
      links.push({ traceId: session.traceId, spanId: t.spanId, attributes: linkAttrs });
    }

    const llmSpanId = randomHex(8);
    ctx.lastLlmSpanId = llmSpanId;
    const sequence = pending && typeof pending.sequence === 'number' ? pending.sequence : session.llmRequestSeq;

    const spanAttrs = [
      { key: 'openinference.span.kind', value: { stringValue: 'LLM' } },
      ...baseSpanAttrs(session),
      { key: 'gen_ai.operation.name', value: { stringValue: 'chat' } },
      { key: 'gen_ai.request.model', value: { stringValue: model } },
      { key: 'llm.latency.total_ms', value: { intValue: String(duration) } },
      { key: 'llm.request.sequence', value: { intValue: String(sequence) } },
      { key: 'turn.number', value: { intValue: String(turnNumber) } },
    ];

    if (promptId) spanAttrs.push({ key: 'gemini.prompt_id', value: { stringValue: promptId } });
    if (typeof statusCode === 'number') spanAttrs.push({ key: 'http.response.status_code', value: { intValue: String(statusCode) } });

    if (pending?.requestTextPreview) spanAttrs.push({ key: 'llm.request_text_preview', value: { stringValue: pending.requestTextPreview } });
    if (pending?.requestTextLength) spanAttrs.push({ key: 'llm.request_text_length', value: { intValue: String(pending.requestTextLength) } });

    if (session.currentTurn?.promptPreview) spanAttrs.push({ key: 'input.value', value: { stringValue: session.currentTurn.promptPreview } });
    if (assistantPreview) spanAttrs.push({ key: 'output.value', value: { stringValue: assistantPreview } });
    if (extracted.thoughts) spanAttrs.push({ key: 'gemini.output.thoughts_preview', value: { stringValue: getPreview(extracted.thoughts, 400) } });

    // Usage (Gemini naming differs slightly; normalize to GenAI conventions + keep raw fields).
    spanAttrs.push({ key: 'gen_ai.usage.input_tokens', value: { intValue: String(inputTokens) } });
    spanAttrs.push({ key: 'gen_ai.usage.output_tokens', value: { intValue: String(outputTokens) } });
    spanAttrs.push({ key: 'gemini.usage.cached_content_token_count', value: { intValue: String(cachedTokens) } });
    spanAttrs.push({ key: 'gemini.usage.thoughts_token_count', value: { intValue: String(thoughtsTokens) } });
    spanAttrs.push({ key: 'gemini.usage.tool_token_count', value: { intValue: String(toolTokens) } });
    spanAttrs.push({ key: 'gemini.usage.total_token_count', value: { intValue: String(totalTokens) } });

    // Feature 132: Add Langfuse-specific attributes for LLM span
    addLangfuseAttributes(spanAttrs, { spanKind: 'LLM', sessionId: session.sessionId });
    if (LANGFUSE_ENABLED) {
      spanAttrs.push({ key: 'langfuse.trace.name', value: { stringValue: 'Gemini Session' } });
    }

    const isError = eventName === 'gemini_cli.api_error' || (typeof statusCode === 'number' && statusCode >= 400);
    const errMsg = typeof attrsObj.error === 'string' ? attrsObj.error : '';

    exportSpan(session, {
      traceId: session.traceId,
      spanId: llmSpanId,
      parentSpanId,
      name: `LLM Call: ${model} (${inputTokens}→${outputTokens} tokens)`,
      kind: 'SPAN_KIND_CLIENT',
      startTimeUnixNano: msToNanos(startTimeMs),
      endTimeUnixNano: msToNanos(endTimeMs),
      attributes: spanAttrs,
      ...(links.length > 0 ? { links } : {}),
      status: isError ? spanStatusError(errMsg) : spanStatusOk(),
    });

    // Aggregate counts at session + current turn levels.
    session.tokens.input += inputTokens;
    session.tokens.output += outputTokens;
    session.tokens.cached += cachedTokens;
    session.tokens.thoughts += thoughtsTokens;
    session.tokens.tool += toolTokens;
    session.tokens.total += totalTokens;

    if (session.currentTurn) {
      session.currentTurn.tokens.input += inputTokens;
      session.currentTurn.tokens.output += outputTokens;
    }

    // For one-shot mode, end the turn promptly once we have a response.
    // (We still keep the idle fallback as a safety net for tool loops.)
    if (!inTurn) return;
    scheduleTurnIdleFallback(session);
    return;
  }

  if (eventName === 'gemini_cli.tool_call') {
    const fn = attrsObj.function_name || attrsObj.tool_name || 'tool';
    const duration = parseDurationMs(attrsObj.duration_ms) || 0;
    const startTimeMs = Math.max(0, timestampMs - duration);
    const endTimeMs = timestampMs;
    const status = attrsObj.status || null;
    const decision = attrsObj.decision || null;
    const successRaw = attrsObj.success;

    const parentSpanId = session.currentTurn ? session.currentTurn.spanId : session.rootSpanId;
    const turnNumber = session.currentTurn ? session.currentTurn.turnNumber : 0;
    const ctx = session.currentTurn || session;

    const spanAttrs = [
      { key: 'openinference.span.kind', value: { stringValue: 'TOOL' } },
      ...baseSpanAttrs(session),
      { key: 'gen_ai.tool.name', value: { stringValue: String(fn) } },
      { key: 'turn.number', value: { intValue: String(turnNumber) } },
      { key: 'tool.duration_ms', value: { intValue: String(duration) } },
    ];

    if (status) spanAttrs.push({ key: 'tool.status', value: { stringValue: String(status) } });
    if (decision) spanAttrs.push({ key: 'tool.decision', value: { stringValue: String(decision) } });

    if (attrsObj.error_type) spanAttrs.push({ key: 'tool.error_type', value: { stringValue: String(attrsObj.error_type) } });
    if (attrsObj.error && typeof attrsObj.error === 'string') spanAttrs.push({ key: 'tool.error', value: { stringValue: getPreview(attrsObj.error, 400) } });

    // Avoid high-volume args; keep only a preview.
    if (attrsObj.function_args && typeof attrsObj.function_args === 'string') {
      spanAttrs.push({ key: 'tool.args_preview', value: { stringValue: getPreview(attrsObj.function_args, 400) } });
      spanAttrs.push({ key: 'tool.args_length', value: { intValue: String(attrsObj.function_args.length) } });
    }

    let success = null;
    if (typeof successRaw === 'boolean') success = successRaw;
    else if (successRaw != null) {
      const s = String(successRaw).toLowerCase();
      if (s === 'true') success = true;
      else if (s === 'false') success = false;
      else if (s === 'success') success = true;
      else if (['error', 'failed', 'failure'].includes(s)) success = false;
    }
    if (success == null && status != null) success = String(status).toLowerCase() === 'success';
    if (success == null) success = !(attrsObj.error || attrsObj.error_type);

    spanAttrs.push({ key: 'tool.success', value: { boolValue: Boolean(success) } });

    session.toolCallCount += 1;
    if (!success) session.toolErrorCount += 1;
    if (session.currentTurn) {
      session.currentTurn.toolCallCount += 1;
      if (!success) session.currentTurn.toolErrorCount += 1;
    }

    const toolSpanId = randomHex(8);
    const links = [];
    if (ctx.lastLlmSpanId) {
      links.push({
        traceId: session.traceId,
        spanId: ctx.lastLlmSpanId,
        attributes: [{ key: 'link.type', value: { stringValue: 'produced_by_llm' } }],
      });
    }

    const spanName = getToolSpanName(fn, attrsObj.function_args);

    // Feature 132: Add Langfuse-specific attributes for tool span
    if (LANGFUSE_ENABLED) {
      spanAttrs.push({ key: 'langfuse.session.id', value: { stringValue: session.sessionId } });
      spanAttrs.push({ key: 'langfuse.trace.name', value: { stringValue: 'Gemini Session' } });
      if (LANGFUSE_USER_ID) {
        spanAttrs.push({ key: 'langfuse.user.id', value: { stringValue: LANGFUSE_USER_ID } });
      }
    }

    exportSpan(session, {
      traceId: session.traceId,
      spanId: toolSpanId,
      parentSpanId,
      name: spanName,
      kind: 'SPAN_KIND_INTERNAL',
      startTimeUnixNano: msToNanos(startTimeMs),
      endTimeUnixNano: msToNanos(endTimeMs),
      attributes: spanAttrs,
      ...(links.length > 0 ? { links } : {}),
      status: success ? spanStatusOk() : spanStatusError(String(attrsObj.error || '')),
    });

    if (Array.isArray(ctx.pendingToolSpanRefs)) {
      ctx.pendingToolSpanRefs.push({
        spanId: toolSpanId,
        toolName: String(fn),
      });
    }

    return;
  }
}

// =============================================================================
// HTTP server
// =============================================================================

async function handleGeminiOtlpEnvelope(req, res) {
  const raw = await readRequestBody(req);
  const bodyBuf = maybeGunzip(raw);

  let otlp;
  try {
    otlp = JSON.parse(bodyBuf.toString('utf8'));
  } catch (e) {
    logDebug('failed to parse json', e?.message);
    return jsonOk(res);
  }

  if (otlp && typeof otlp === 'object' && Array.isArray(otlp.resourceLogs)) {
    // Mutate logs for correlation (optional but useful): copy session.id -> conversation.id.
    const events = [];
    for (const rl of otlp.resourceLogs) {
      const resourceAttrs = Array.isArray(rl?.resource?.attributes) ? rl.resource.attributes : [];
      const serviceName = attrGetString(resourceAttrs, 'service.name') || 'gemini-cli';
      const serviceVersion = attrGetString(resourceAttrs, 'service.version') || 'unknown';
      const env = attrGetString(resourceAttrs, 'env') || 'dev';
      const resourceProjectName = attrGetString(resourceAttrs, 'i3pm.project_name');
      const resourceProjectPath =
        attrGetString(resourceAttrs, 'project_path')
        || attrGetString(resourceAttrs, 'i3pm.project_path')
        || attrGetString(resourceAttrs, 'working_directory');
      const resourceTmuxSession = attrGetString(resourceAttrs, 'terminal.tmux.session');
      const resourceTmuxWindow = attrGetString(resourceAttrs, 'terminal.tmux.window');
      const resourceTmuxPane = attrGetString(resourceAttrs, 'terminal.tmux.pane');
      const resourcePty = attrGetString(resourceAttrs, 'terminal.pty');
      // Feature 135: Extract client PID for window correlation
      const clientPid = attrGetInt(resourceAttrs, 'process.pid');
      const pidEnv = readProcessEnvByPid(clientPid);

      const scopeLogs = Array.isArray(rl?.scopeLogs) ? rl.scopeLogs : [];
      for (const sl of scopeLogs) {
        const logRecords = Array.isArray(sl?.logRecords) ? sl.logRecords : [];
        for (const lr of logRecords) {
          const attrs = Array.isArray(lr?.attributes) ? lr.attributes : [];

          const sid = attrGetString(attrs, 'session.id') || attrGetString(attrs, 'sessionId');
          if (sid) {
            // Normalize join keys with Codex/Claude: use session.id everywhere.
            attrUpsert(attrs, 'session.id', { stringValue: sid });
            attrUpsert(attrs, 'conversation.id', { stringValue: sid });
            attrUpsert(attrs, 'gen_ai.conversation.id', { stringValue: sid });
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
            model: attrsObj.model || null,
            timestampMs: parseIsoToMs(attrsObj['event.timestamp']),
            interactive: typeof attrsObj.interactive === 'boolean' ? attrsObj.interactive : null,
            providerName: 'Google',
            cwd: attrsObj.cwd || attrsObj.working_directory || null,
            projectPath:
              attrsObj.project_path
              || attrsObj['i3pm.project_path']
              || attrsObj.cwd
              || attrsObj.working_directory
              || resourceProjectPath
              || pidEnv.I3PM_PROJECT_PATH
              || null,
            tmuxSession: attrsObj['terminal.tmux.session'] || resourceTmuxSession || pidEnv.TMUX_SESSION || null,
            tmuxWindow: attrsObj['terminal.tmux.window'] || resourceTmuxWindow || pidEnv.TMUX_WINDOW || null,
            tmuxPane: attrsObj['terminal.tmux.pane'] || resourceTmuxPane || pidEnv.TMUX_PANE || null,
            pty: attrsObj['terminal.pty'] || resourcePty || pidEnv.TTY || null,
            projectName:
              attrsObj['i3pm.project_name']
              || resourceProjectName
              || pidEnv.I3PM_PROJECT_NAME
              || null,
            // Feature 135: Pass client PID for window correlation
            clientPid,
          };

          events.push({ meta, attrsObj });
        }
      }
    }

    // Ordering within a batch isn't guaranteed; sort by `event.timestamp`.
    events.sort((a, b) => (a.meta.timestampMs || 0) - (b.meta.timestampMs || 0));
    for (const e of events) handleGeminiLogEvent(e.meta, e.attrsObj);

    httpPostJson(FORWARD_LOGS_ENDPOINT, otlp, { timeoutMs: 2000 });
    return jsonOk(res);
  }

  if (otlp && typeof otlp === 'object' && Array.isArray(otlp.resourceMetrics)) {
    httpPostJson(FORWARD_METRICS_ENDPOINT, otlp, { timeoutMs: 2000 });
    return jsonOk(res);
  }

  if (otlp && typeof otlp === 'object' && Array.isArray(otlp.resourceSpans)) {
    if (FORWARD_NATIVE_TRACES) httpPostJson(TRACES_ENDPOINT, otlp, { timeoutMs: 2000 });
    return jsonOk(res);
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

    if (req.method === 'POST') {
      // Gemini posts OTLP envelopes to `/`.
      return await handleGeminiOtlpEnvelope(req, res);
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
  console.error(`[gemini-otel-interceptor v${INTERCEPTOR_VERSION}] listening on http://${LISTEN_HOST}:${LISTEN_PORT}`);
  // eslint-disable-next-line no-console
  console.error(`[gemini-otel-interceptor] forward logs    -> ${FORWARD_LOGS_ENDPOINT}`);
  // eslint-disable-next-line no-console
  console.error(`[gemini-otel-interceptor] forward metrics -> ${FORWARD_METRICS_ENDPOINT}`);
  // eslint-disable-next-line no-console
  console.error(`[gemini-otel-interceptor] export traces   -> ${TRACES_ENDPOINT}`);
  // eslint-disable-next-line no-console
  console.error(`[gemini-otel-interceptor] forward native traces = ${FORWARD_NATIVE_TRACES ? 'on' : 'off'}`);
});
