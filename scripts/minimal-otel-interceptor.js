/**
 * minimal-otel-interceptor.js
 *
 * Injects into Claude Code to capture full request/response payloads
 * and exports them as OpenInference-compliant OTLP Spans to Grafana Alloy.
 *
 * Enhanced with:
 * - Session ID tracking for session correlation
 * - Token usage metrics (input, output, cache)
 * - Stop reason tracking
 * - Request parameter capture (temperature, max_tokens)
 */

const http = require('node:http');
const os = require('node:os');
const { Buffer } = require('node:buffer');

// Configuration (with environment variable fallbacks)
// OTEL_EXPORTER_OTLP_TRACES_ENDPOINT is full URL, OTEL_EXPORTER_OTLP_ENDPOINT needs /v1/traces appended
const TRACE_ENDPOINT = process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
  || (process.env.OTEL_EXPORTER_OTLP_ENDPOINT
    ? process.env.OTEL_EXPORTER_OTLP_ENDPOINT.replace(/\/$/, '') + '/v1/traces'
    : 'http://127.0.0.1:4318/v1/traces');
const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'claude-code';

// ID generator (must be defined before use in constants)
function generateId(bytes) {
  let result = '';
  const hex = '0123456789abcdef';
  for (let i = 0; i < bytes * 2; i++) {
    result += hex.charAt(Math.floor(Math.random() * hex.length));
  }
  return result;
}

// Session tracking - stable ID per Claude Code instance
const SESSION_START_TIME = Date.now();
const SESSION_ID = `claude-${process.pid}-${SESSION_START_TIME}`;

// Session-level trace context for multi-span correlation
const SESSION_TRACE_ID = generateId(16);  // 32 hex chars
const SESSION_ROOT_SPAN_ID = generateId(8);  // 16 hex chars
let sessionSpanExported = false;
let apiCallCount = 0;

console.error(`[OTEL-Payload-Interceptor] Active`);
console.error(`[OTEL-Payload-Interceptor]   Endpoint: ${TRACE_ENDPOINT}`);
console.error(`[OTEL-Payload-Interceptor]   Session: ${SESSION_ID}`);
console.error(`[OTEL-Payload-Interceptor]   TraceID: ${SESSION_TRACE_ID}`);

const originalFetch = globalThis.fetch;

globalThis.fetch = async (input, init) => {
  const url = typeof input === 'string' ? input : input.url;
  if (!url.includes('api.anthropic.com') || !init || !init.body) {
    return originalFetch(input, init);
  }

  // Extract trace context for merging
  let parentTraceId = null;
  let parentSpanId = null;
  if (init.headers) {
    const tp = init.headers['traceparent'] || init.headers['Traceparent'];
    if (tp && typeof tp === 'string') {
      const parts = tp.split('-');
      if (parts.length >= 3) {
        parentTraceId = parts[1];
        parentSpanId = parts[2];
      }
    }
  }

  const startTime = Date.now();
  let requestBody = {};
  try {
    requestBody = JSON.parse(init.body);
  } catch (e) {
    requestBody = { raw: init.body };
  }

  try {
    const response = await originalFetch(input, init);
    const endTime = Date.now();
    const clonedResponse = response.clone();

    clonedResponse.text().then(text => {
      let responseBody = {};
      try {
        responseBody = JSON.parse(text);
      } catch (e) {
        responseBody = { raw: text.substring(0, 5000) };
      }
      exportToAlloy(requestBody, responseBody, url, startTime, endTime, parentTraceId, parentSpanId);
    }).catch(() => {});

    return response;
  } catch (err) {
    throw err;
  }
};

// Helper to send OTLP data to Alloy
function sendToAlloy(spanRecord) {
  try {
    const data = JSON.stringify(spanRecord);
    const alloyUrl = new URL(TRACE_ENDPOINT);

    const postReq = http.request({
      hostname: alloyUrl.hostname,
      port: alloyUrl.port,
      path: alloyUrl.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.from(data).length
      }
    }, (res) => {
      res.on('data', () => {});
    });

    postReq.on('error', () => {});
    postReq.write(data);
    postReq.end();
  } catch (e) {
    // Silent failure
  }
}

// Export root span on first API call (session start)
function exportRootSpan() {
  if (sessionSpanExported) return;
  sessionSpanExported = true;

  const rootSpan = {
    resourceSpans: [{
      resource: {
        attributes: [
          { key: 'service.name', value: { stringValue: SERVICE_NAME } },
          { key: 'host.name', value: { stringValue: os.hostname() } }
        ]
      },
      scopeSpans: [{
        scope: { name: 'claude-interceptor', version: '2.1.0' },
        spans: [{
          traceId: SESSION_TRACE_ID,
          spanId: SESSION_ROOT_SPAN_ID,
          name: 'Claude Session',
          kind: 'SPAN_KIND_INTERNAL',
          startTimeUnixNano: (SESSION_START_TIME * 1000000).toString(),
          endTimeUnixNano: (Date.now() * 1000000).toString(),
          attributes: [
            { key: 'openinference.span.kind', value: { stringValue: 'CHAIN' } },
            { key: 'session.id', value: { stringValue: SESSION_ID } },
            { key: 'session.trace_id', value: { stringValue: SESSION_TRACE_ID } }
          ],
          status: { code: 'STATUS_CODE_OK' }
        }]
      }]
    }]
  };

  sendToAlloy(rootSpan);
}

// Update root span on session end with final end time and API call count
function updateRootSpanEndTime() {
  const endTime = Date.now();
  const rootSpan = {
    resourceSpans: [{
      resource: {
        attributes: [
          { key: 'service.name', value: { stringValue: SERVICE_NAME } },
          { key: 'host.name', value: { stringValue: os.hostname() } }
        ]
      },
      scopeSpans: [{
        scope: { name: 'claude-interceptor', version: '2.1.0' },
        spans: [{
          traceId: SESSION_TRACE_ID,
          spanId: SESSION_ROOT_SPAN_ID,
          name: 'Claude Session',
          kind: 'SPAN_KIND_INTERNAL',
          startTimeUnixNano: (SESSION_START_TIME * 1000000).toString(),
          endTimeUnixNano: (endTime * 1000000).toString(),
          attributes: [
            { key: 'openinference.span.kind', value: { stringValue: 'CHAIN' } },
            { key: 'session.id', value: { stringValue: SESSION_ID } },
            { key: 'session.api_call_count', value: { intValue: apiCallCount.toString() } }
          ],
          status: { code: 'STATUS_CODE_OK' }
        }]
      }]
    }]
  };

  sendToAlloy(rootSpan);
}

// Handle graceful shutdown - update root span end time
process.on('beforeExit', () => {
  if (sessionSpanExported && apiCallCount > 0) {
    updateRootSpanEndTime();
  }
});

function exportToAlloy(req, res, url, startTime, endTime, parentTraceId, parentSpanId) {
  try {
    // Export root span on first API call (before any child spans)
    exportRootSpan();
    apiCallCount++;

    // Model info
    const model = req.model || 'unknown';

    // Token usage extraction (Anthropic API format)
    const usage = res.usage || {};
    const inputTokens = usage.input_tokens || 0;
    const outputTokens = usage.output_tokens || 0;
    const cacheCreationTokens = usage.cache_creation_input_tokens || 0;
    const cacheReadTokens = usage.cache_read_input_tokens || 0;
    const totalTokens = inputTokens + outputTokens;

    // Response metadata
    const stopReason = res.stop_reason || 'unknown';
    const responseId = res.id || null;

    // Request parameters
    const temperature = req.temperature;
    const maxTokens = req.max_tokens;
    const systemPrompt = req.system;

    // Input extraction - last user message for primary value
    let inputValue = '';
    const messageCount = req.messages?.length || 0;
    if (req.messages && Array.isArray(req.messages)) {
      const userMsgs = req.messages.filter(m => m.role === 'user');
      if (userMsgs.length > 0) {
        const last = userMsgs[userMsgs.length - 1];
        inputValue = typeof last.content === 'string' ? last.content : JSON.stringify(last.content);
      }
    } else if (req.prompt) {
      inputValue = req.prompt;
    }

    // Output extraction
    let completion = '';
    if (res.content && Array.isArray(res.content)) {
      completion = res.content.map(c => c.text || '').join('');
    } else if (res.raw) {
      completion = res.raw;
    } else if (res.completion) {
      completion = res.completion;
    }

    // Duration calculation
    const durationMs = endTime - startTime;

    // Build attributes array
    const attributes = [
      // OpenInference required
      { key: 'openinference.span.kind', value: { stringValue: 'LLM' } },

      // Session tracking (CRITICAL for otel-ai-monitor)
      { key: 'session.id', value: { stringValue: SESSION_ID } },

      // Model info
      { key: 'llm.model_name', value: { stringValue: model } },
      { key: 'llm.provider', value: { stringValue: 'anthropic' } },
      { key: 'llm.system', value: { stringValue: 'anthropic' } },

      // Input/Output
      { key: 'input.value', value: { stringValue: (inputValue || JSON.stringify(req)).substring(0, 5000) } },
      { key: 'output.value', value: { stringValue: (completion || JSON.stringify(res)).substring(0, 5000) } },
      { key: 'input.mime_type', value: { stringValue: 'text/plain' } },
      { key: 'output.mime_type', value: { stringValue: 'text/plain' } },
      { key: 'llm.input_messages.count', value: { intValue: messageCount.toString() } },

      // Token counts (OpenInference conventions)
      { key: 'llm.token_count.prompt', value: { intValue: inputTokens.toString() } },
      { key: 'llm.token_count.completion', value: { intValue: outputTokens.toString() } },
      { key: 'llm.token_count.total', value: { intValue: totalTokens.toString() } },

      // Anthropic cache stats
      { key: 'llm.token_count.prompt_details.cache_read', value: { intValue: cacheReadTokens.toString() } },
      { key: 'llm.token_count.prompt_details.cache_write', value: { intValue: cacheCreationTokens.toString() } },

      // Response info
      { key: 'llm.response.stop_reason', value: { stringValue: stopReason } },

      // Timing
      { key: 'llm.latency.total_ms', value: { intValue: durationMs.toString() } },

      // Sequence tracking for multi-span correlation
      { key: 'llm.request.sequence', value: { intValue: apiCallCount.toString() } },
    ];

    // Optional attributes (only add if present)
    if (responseId) {
      attributes.push({ key: 'llm.response.id', value: { stringValue: responseId } });
    }
    if (temperature !== undefined) {
      attributes.push({ key: 'llm.request.temperature', value: { doubleValue: temperature } });
    }
    if (maxTokens !== undefined) {
      attributes.push({ key: 'llm.request.max_tokens', value: { intValue: maxTokens.toString() } });
    }
    if (systemPrompt) {
      const systemStr = typeof systemPrompt === 'string' ? systemPrompt : JSON.stringify(systemPrompt);
      attributes.push({ key: 'llm.request.system', value: { stringValue: systemStr.substring(0, 1000) } });
    }

    // OTLP JSON Enum mapping requires string names, not integers
    // Ref: https://github.com/opentelemetry/opentelemetry-specification/blob/main/specification/protocol/otlp.md#json-mapping
    const spanRecord = {
      resourceSpans: [{
        resource: {
          attributes: [
            { key: 'service.name', value: { stringValue: SERVICE_NAME } },
            { key: 'host.name', value: { stringValue: os.hostname() } }
          ]
        },
        scopeSpans: [{
          scope: {
            name: 'claude-interceptor',
            version: '2.1.0'
          },
          spans: [{
            traceId: SESSION_TRACE_ID,
            spanId: generateId(8),
            parentSpanId: SESSION_ROOT_SPAN_ID,  // Link all LLM calls to root session span
            name: 'LLM',  // OpenInference standard span name
            kind: 'SPAN_KIND_CLIENT',
            startTimeUnixNano: (startTime * 1000000).toString(),
            endTimeUnixNano: (endTime * 1000000).toString(),
            attributes: attributes,
            status: { code: 'STATUS_CODE_OK' }
          }]
        }]
      }]
    };

    sendToAlloy(spanRecord);
  } catch (e) {
    // Silent failure to avoid disrupting Claude Code
  }
}
