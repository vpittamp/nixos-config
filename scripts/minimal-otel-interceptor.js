/**
 * minimal-otel-interceptor.js (v3.9.0)
 *
 * Multi-span trace hierarchy for Claude Code sessions.
 * Creates proper hierarchical trace structure: Session -> Turns -> LLM/Tool spans
 *
 * Features:
 * - Session span (CHAIN) - root span for entire Claude Code process
 * - Turn spans (AGENT) - one per user prompt with semantic descriptions
 * - LLM spans (CLIENT) - individual Claude API calls with model/token details
 * - Tool spans (TOOL) - file operations, bash commands, with timing and status
 * - Permission spans (PERMISSION) - time spent waiting for user approval
 * - Notification spans (NOTIFICATION) - Claude Code notification events
 * - Compaction spans (COMPACTION) - context window compaction events
 * - Subagent correlation via span links, SubagentStop hook, and OTEL_TRACE_PARENT propagation
 * - Token aggregation at turn and session level for cost attribution
 * - Cost metrics (gen_ai.usage.cost_usd) at LLM, turn, and session levels
 * - Correlation with Claude Code's native telemetry via session.id
 *
 * Following OpenTelemetry GenAI semantic conventions (2025 edition).
 *
 * v3.9.0 Changes (Phase 3):
 * - Add PostToolUse hook integration: exit_code, output_summary, output_lines, error_type
 * - Add SubagentStop hook integration: explicit subagent completion with subagent.session_id
 * - Add NOTIFICATION spans for permission_prompt, auth_success events
 * - Add COMPACTION spans for manual/auto context compaction events
 *
 * v3.8.0 Changes:
 * - Add permission wait visibility: PERMISSION spans track time awaiting user approval
 * - Poll for permission request files from PermissionRequest hook
 * - Complete permission spans as "approved" when tool_result arrives, "denied" on turn end
 * - Add permission.tool, permission.result, permission.wait_ms attributes
 *
 * v3.7.0 Changes:
 * - Add cost metrics: MODEL_PRICING table with configurable overrides via env var
 * - Calculate USD cost per LLM call using model-specific pricing
 * - Aggregate cost to turn and session spans (gen_ai.usage.cost_usd attribute)
 * - Add error classification: error.type attribute (rate_limit, auth, timeout, validation, server)
 * - Track error count per turn (turn.error_count attribute)
 *
 * v3.6.0 Changes:
 * - Hook-driven Turn boundaries (UserPromptSubmit + Stop) when available; fallback to heuristics when not
 * - Session-id buffering to avoid mixed `session.id` spans when hooks hydrate mid-run
 * - Heuristic improvements: idle-based turn end + prompt preview scoring to reduce spurious turns
 * - Export LLM spans even outside a Turn (turn.number=0) to retain visibility of background calls
 *
 * v3.5.0 Changes:
 * - Fix turn boundary detection: do not treat `tool_result` messages as new user turns
 * - Hydrate `session.id` from Claude Code SessionStart hook (UUID) for correlation with native metrics/logs
 * - Add causal links: Tool spans link to producing LLM span; LLM spans link to consumed tool results
 * - Robust Task/subagent linking: per-Task context files with best-effort matching (avoids “last Task wins”)
 * - Export session root span once (on shutdown) to avoid duplicate span updates
 *
 * v3.4.0 Changes:
 * - Hybrid trace context propagation for robust subagent linking:
 *   1. Environment variable (if inherited)
 *   2. Working directory file (same-project subagents)
 *   3. Process tree walking (handles intermediate shells)
 *   4. Most recent context fallback (concurrent sessions)
 * - Writes trace context to both runtime dir and working directory
 * - Linux /proc filesystem support for process tree traversal
 *
 * v3.3.0 Changes:
 * - Added filesystem-based trace context for environment isolation workaround
 * - Automatic cleanup of state files on process exit
 *
 * v3.2.0 Changes:
 * - Fixed race condition in subagent span linking by awaiting response body parsing
 * - Improved reliability of OTEL_TRACE_PARENT propagation
 *
 * v3.1.0 Changes:
 * - Enhanced span names with semantic context (prompt previews, tool details)
 * - Improved subagent correlation with TRACEPARENT in resource attributes
 * - Added working_directory tracking
 * - Better error span semantics
 */

const http = require('node:http');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const { Buffer } = require('node:buffer');

// =============================================================================
// Configuration
// =============================================================================

const TRACE_ENDPOINT = process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
  || (process.env.OTEL_EXPORTER_OTLP_ENDPOINT
    ? process.env.OTEL_EXPORTER_OTLP_ENDPOINT.replace(/\/$/, '') + '/v1/traces'
    : 'http://127.0.0.1:4318/v1/traces');
const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'claude-code';
const INTERCEPTOR_VERSION = '3.9.0';
const WORKING_DIRECTORY = process.cwd();
const RUNTIME_DIR = process.env.XDG_RUNTIME_DIR || os.tmpdir();
const SESSION_META_FILE = path.join(RUNTIME_DIR, `claude-session-${process.pid}.json`);
const PROMPT_META_FILE = path.join(RUNTIME_DIR, `claude-user-prompt-${process.pid}.json`);
const STOP_META_FILE = path.join(RUNTIME_DIR, `claude-stop-${process.pid}.json`);
const TASK_CONTEXT_PREFIX = 'claude-task-context-';
const PERMISSION_FILE_PREFIX = 'claude-permission-';
const POSTTOOL_FILE_PREFIX = 'claude-posttool-';
const SUBAGENT_STOP_FILE_PREFIX = 'claude-subagent-stop-';
const NOTIFICATION_FILE_PREFIX = 'claude-notification-';
const PRECOMPACT_FILE_PREFIX = 'claude-precompact-';
const TURN_BOUNDARY_MODE = process.env.OTEL_INTERCEPTOR_TURN_BOUNDARY_MODE || 'auto'; // auto|hooks|heuristic
const SESSION_ID_POLICY = process.env.OTEL_INTERCEPTOR_SESSION_ID_POLICY || 'buffer'; // buffer|eager
const SESSION_ID_BUFFER_MAX_MS = Number.parseInt(process.env.OTEL_INTERCEPTOR_SESSION_ID_BUFFER_MAX_MS || '5000', 10);
const SESSION_ID_BUFFER_MAX_SPANS = Number.parseInt(process.env.OTEL_INTERCEPTOR_SESSION_ID_BUFFER_MAX_SPANS || '200', 10);
const HOOK_POLL_INTERVAL_MS = Number.parseInt(process.env.OTEL_INTERCEPTOR_HOOK_POLL_INTERVAL_MS || '200', 10);
const TURN_IDLE_END_MS = Number.parseInt(process.env.OTEL_INTERCEPTOR_TURN_IDLE_END_MS || '1500', 10);
const PROC_AVAILABLE = fs.existsSync('/proc');

// Feature 132: Langfuse Integration Configuration
// When enabled, spans include OpenInference attributes for proper Langfuse categorization
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

const CLAUDE_CODE_VERSION = (() => {
  const fromEnv = process.env.CLAUDE_CODE_VERSION;
  if (fromEnv && typeof fromEnv === 'string') return fromEnv;

  const joined = (process.argv || []).join(' ');
  const m = joined.match(/claude-code-([0-9]+\.[0-9]+\.[0-9]+)/);
  return m ? m[1] : 'unknown';
})();

// Tool name mappings for better semantic descriptions
const TOOL_DESCRIPTIONS = {
  Read: 'Read file',
  Write: 'Write file',
  Edit: 'Edit file',
  Bash: 'Execute command',
  Glob: 'Find files',
  Grep: 'Search code',
  Task: 'Spawn subagent',
  WebSearch: 'Web search',
  WebFetch: 'Fetch URL',
  AskUserQuestion: 'Ask user',
  TodoWrite: 'Update todos',
  NotebookEdit: 'Edit notebook'
};

// =============================================================================
// Model Pricing (USD per 1M tokens, as of 2025)
// =============================================================================

/**
 * Anthropic model pricing table.
 * Configurable via OTEL_INTERCEPTOR_MODEL_PRICING_JSON env var for overrides.
 * Keys are normalized model name patterns (matched via includes()).
 */
const DEFAULT_MODEL_PRICING = {
  'claude-opus-4-5': { input: 15.00, output: 75.00, cacheRead: 1.50, cacheWrite: 18.75 },
  'claude-sonnet-4': { input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75 },
  'claude-3-5-sonnet': { input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75 },
  'claude-3-5-haiku': { input: 0.80, output: 4.00, cacheRead: 0.08, cacheWrite: 1.00 },
  'claude-3-opus': { input: 15.00, output: 75.00, cacheRead: 1.50, cacheWrite: 18.75 },
  'claude-3-sonnet': { input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75 },
  'claude-3-haiku': { input: 0.25, output: 1.25, cacheRead: 0.03, cacheWrite: 0.30 }
};

const MODEL_PRICING = (() => {
  const override = process.env.OTEL_INTERCEPTOR_MODEL_PRICING_JSON;
  if (override) {
    try {
      return { ...DEFAULT_MODEL_PRICING, ...JSON.parse(override) };
    } catch (e) {
      console.error('[OTEL-Interceptor] Failed to parse MODEL_PRICING_JSON:', e.message);
    }
  }
  return DEFAULT_MODEL_PRICING;
})();

/**
 * Calculate USD cost for an LLM API call based on token usage.
 * @param {string} model - Model name from API response
 * @param {{input: number, output: number, cacheRead: number, cacheWrite: number}} tokens - Token counts
 * @returns {number} Cost in USD (0 if model not found)
 */
function calculateCostUsd(model, tokens) {
  if (!model || !tokens) return 0;

  // Normalize model name and find matching pricing
  const modelLower = model.toLowerCase();
  let pricing = null;

  for (const [pattern, p] of Object.entries(MODEL_PRICING)) {
    if (modelLower.includes(pattern)) {
      pricing = p;
      break;
    }
  }

  if (!pricing) return 0;

  // Calculate cost: (tokens / 1M) * price_per_1M
  const inputCost = (tokens.input || 0) / 1_000_000 * pricing.input;
  const outputCost = (tokens.output || 0) / 1_000_000 * pricing.output;
  const cacheReadCost = (tokens.cacheRead || 0) / 1_000_000 * pricing.cacheRead;
  const cacheWriteCost = (tokens.cacheWrite || 0) / 1_000_000 * pricing.cacheWrite;

  return inputCost + outputCost + cacheReadCost + cacheWriteCost;
}

// =============================================================================
// Error Classification
// =============================================================================

/**
 * Classify error type based on HTTP status code and response body.
 * @param {number|undefined} statusCode - HTTP response status code
 * @param {object|undefined} responseBody - API response body
 * @returns {string|null} Error type or null if no error
 */
function classifyErrorType(statusCode, responseBody) {
  // Check for HTTP-level errors
  if (statusCode && statusCode >= 400) {
    if (statusCode === 401 || statusCode === 403) return 'auth';
    if (statusCode === 429) return 'rate_limit';
    if (statusCode === 408 || statusCode === 504) return 'timeout';
    if (statusCode >= 400 && statusCode < 500) return 'validation';
    if (statusCode >= 500) return 'server';
    return 'unknown';
  }

  // Check for API-level errors in response body
  if (responseBody && responseBody.type === 'error') {
    const errType = responseBody.error?.type || '';
    if (errType.includes('authentication') || errType.includes('permission')) return 'auth';
    if (errType.includes('rate_limit') || errType.includes('overloaded')) return 'rate_limit';
    if (errType.includes('invalid') || errType.includes('validation')) return 'validation';
    return 'api_error';
  }

  return null;
}

// =============================================================================
// Feature 132: Langfuse Attribute Helpers
// =============================================================================

/**
 * Add Langfuse-specific attributes to a span attributes array.
 * These attributes enable proper categorization and display in Langfuse UI.
 *
 * @param {Array} attributes - OTEL span attributes array
 * @param {object} options - Langfuse options
 * @param {string} options.spanKind - OpenInference span kind (CHAIN, LLM, TOOL, AGENT)
 * @param {string} [options.sessionId] - Session ID for trace grouping
 * @param {string} [options.observationName] - Human-readable observation name
 * @param {object} [options.usageDetails] - Token usage breakdown
 * @param {object} [options.costDetails] - Cost breakdown
 * @returns {Array} The modified attributes array
 */
function addLangfuseAttributes(attributes, options) {
  if (!LANGFUSE_ENABLED) return attributes;

  const { spanKind, sessionId, observationName, usageDetails, costDetails } = options;

  // Add OpenInference span kind (required for Langfuse type detection)
  if (spanKind) {
    attributes.push({ key: 'openinference.span.kind', value: { stringValue: spanKind } });
  }

  // Add Langfuse session ID for trace grouping
  if (sessionId) {
    attributes.push({ key: 'langfuse.session.id', value: { stringValue: sessionId } });
  }

  // Add user ID if configured
  if (LANGFUSE_USER_ID) {
    attributes.push({ key: 'langfuse.user.id', value: { stringValue: LANGFUSE_USER_ID } });
  }

  // Add observation name
  if (observationName) {
    attributes.push({ key: 'langfuse.observation.name', value: { stringValue: observationName } });
  }

  // Add tags if configured
  if (LANGFUSE_TAGS && Array.isArray(LANGFUSE_TAGS)) {
    attributes.push({ key: 'langfuse.tags', value: { stringValue: JSON.stringify(LANGFUSE_TAGS) } });
  }

  // Add usage details (JSON serialized for Langfuse)
  if (usageDetails) {
    attributes.push({ key: 'langfuse.observation.usage_details', value: { stringValue: JSON.stringify(usageDetails) } });
  }

  // Add cost details (JSON serialized for Langfuse)
  if (costDetails) {
    attributes.push({ key: 'langfuse.observation.cost_details', value: { stringValue: JSON.stringify(costDetails) } });
  }

  return attributes;
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
  if (tokens.cacheRead > 0) details.cache_read = tokens.cacheRead;
  if (tokens.cacheWrite > 0) details.cache_creation = tokens.cacheWrite;
  return details;
}

/**
 * Build Langfuse-compatible cost details object.
 * @param {number} costUsd - Total cost in USD
 * @param {object} tokens - Token counts for cost breakdown
 * @returns {object} Cost details for Langfuse
 */
function buildLangfuseCostDetails(costUsd, tokens) {
  // We only have total cost from calculateCostUsd, not per-category
  return {
    total: costUsd,
  };
}

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Generate random hex ID of specified byte length
 * @param {number} bytes - Number of bytes (16 for traceId, 8 for spanId)
 * @returns {string} Hex string of length bytes*2
 */
function generateId(bytes) {
  let result = '';
  const hex = '0123456789abcdef';
  for (let i = 0; i < bytes * 2; i++) {
    result += hex.charAt(Math.floor(Math.random() * hex.length));
  }
  return result;
}

/**
 * Convert milliseconds to nanoseconds string (OTLP format)
 * @param {number} ms - Milliseconds timestamp
 * @returns {string} Nanoseconds as string
 */
function msToNanos(ms) {
  return (ms * 1000000).toString();
}

/**
 * Extract a meaningful preview from text content (for span names)
 * @param {string} text - Input text
 * @param {number} maxLen - Maximum length
 * @returns {string} Truncated preview
 */
function getPreview(text, maxLen = 50) {
  if (!text || typeof text !== 'string') return '';
  // Remove newlines and excess whitespace
  const clean = text.replace(/[\r\n]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (clean.length <= maxLen) return clean;
  return clean.substring(0, maxLen - 3) + '...';
}

/**
 * Create semantic tool span name with context
 * @param {string} toolName - Tool name
 * @param {object} input - Tool input
 * @returns {string} Semantic span name
 */
function getToolSpanName(toolName, input) {
  const baseName = TOOL_DESCRIPTIONS[toolName] || toolName;

  if (!input) return `Tool: ${toolName}`;

  // Add context based on tool type
  if (toolName === 'Read' || toolName === 'Write' || toolName === 'Edit') {
    const path = input.file_path || input.path || '';
    const fileName = path.split('/').pop() || path;
    return fileName ? `${baseName}: ${fileName}` : `Tool: ${toolName}`;
  }

  if (toolName === 'Bash') {
    const cmd = input.command || '';
    const cmdPreview = cmd.split(' ')[0] || cmd; // First word
    return cmdPreview ? `${baseName}: ${cmdPreview}` : `Tool: ${toolName}`;
  }

  if (toolName === 'Grep') {
    const pattern = input.pattern || '';
    return pattern ? `${baseName}: "${getPreview(pattern, 30)}"` : `Tool: ${toolName}`;
  }

  if (toolName === 'Glob') {
    const pattern = input.pattern || '';
    return pattern ? `${baseName}: ${pattern}` : `Tool: ${toolName}`;
  }

  if (toolName === 'Task') {
    const desc = input.description || input.prompt || '';
    return desc ? `${baseName}: ${getPreview(desc, 40)}` : `Tool: ${toolName}`;
  }

  if (toolName === 'WebSearch') {
    const query = input.query || '';
    return query ? `${baseName}: "${getPreview(query, 40)}"` : `Tool: ${toolName}`;
  }

  if (toolName === 'WebFetch') {
    const url = input.url || '';
    try {
      const host = new URL(url).hostname;
      return `${baseName}: ${host}`;
    } catch {
      return `Tool: ${toolName}`;
    }
  }

  return `Tool: ${toolName}`;
}

/**
 * Best-effort injection of W3C trace context into outgoing HTTP headers.
 *
 * This is OFF by default because it sends trace IDs to third-party endpoints.
 * Enable only when you explicitly want correlation with eBPF agents (e.g. Beyla)
 * that extract `traceparent` from HTTP traffic.
 */
function maybeInjectTraceparentHeader(init, parentSpanId) {
  if (process.env.OTEL_INTERCEPTOR_INJECT_TRACEPARENT !== '1') return;
  if (!init || !parentSpanId) return;

  const traceparentValue = `00-${state.session.traceId}-${parentSpanId}-01`;

  const hasTraceparent = (headers) => {
    if (!headers) return false;
    if (typeof headers.get === 'function') {
      return headers.get('traceparent') != null;
    }
    if (Array.isArray(headers)) {
      return headers.some(([k]) => typeof k === 'string' && k.toLowerCase() === 'traceparent');
    }
    if (typeof headers === 'object') {
      return Object.keys(headers).some(k => k.toLowerCase() === 'traceparent');
    }
    return false;
  };

  if (hasTraceparent(init.headers)) return;

  // Mutate in place (lowest-overhead), but handle all header shapes.
  if (init.headers && typeof init.headers.set === 'function') {
    init.headers.set('traceparent', traceparentValue);
    return;
  }

  if (Array.isArray(init.headers)) {
    init.headers.push(['traceparent', traceparentValue]);
    return;
  }

  if (init.headers && typeof init.headers === 'object') {
    init.headers.traceparent = traceparentValue;
    return;
  }

  init.headers = { traceparent: traceparentValue };
}

// =============================================================================
// Token Counts Structure
// =============================================================================

/**
 * Create empty token counts object (includes cost tracking)
 * @returns {{input: number, output: number, cacheRead: number, cacheWrite: number, costUsd: number}}
 */
function createTokenCounts() {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, costUsd: 0 };
}

/**
 * Extract token usage from Anthropic API response
 * @param {object} response - API response body
 * @returns {{input: number, output: number, cacheRead: number, cacheWrite: number}}
 */
function extractTokenUsage(response) {
  const usage = response.usage || {};
  return {
    input: usage.input_tokens || 0,
    output: usage.output_tokens || 0,
    cacheRead: usage.cache_read_input_tokens || 0,
    cacheWrite: usage.cache_creation_input_tokens || 0
  };
}

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function mergeUsageMax(base, next) {
  const merged = { ...(base || {}) };
  if (!next || typeof next !== 'object') return merged;
  for (const [k, v] of Object.entries(next)) {
    if (typeof v !== 'number') continue;
    if (typeof merged[k] !== 'number') merged[k] = v;
    else merged[k] = Math.max(merged[k], v);
  }
  return merged;
}

/**
 * Parse Anthropic streaming responses (text/event-stream) into a message-like object.
 *
 * Claude Code frequently uses streaming mode for /v1/messages which returns SSE events.
 * We reconstruct a best-effort message shape so downstream logic can:
 * - extract token usage
 * - detect tool_use blocks and create tool spans
 * - detect stop_reason for turn completion heuristics
 *
 * @param {string} text - full response body text
 * @returns {object|null}
 */
function parseAnthropicEventStream(text) {
  if (!text || typeof text !== 'string') return null;

  const events = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line.startsWith('data:')) continue;
    const data = line.slice(5).trimStart();
    if (!data || data === '[DONE]') continue;
    const parsed = tryParseJson(data);
    if (parsed && typeof parsed === 'object') events.push(parsed);
  }

  if (events.length === 0) return null;

  let message = null;
  let usage = {};
  let stopReason = null;
  const blocksByIndex = new Map();

  for (const evt of events) {
    if (!evt || typeof evt !== 'object') continue;

    if (evt.type === 'message_start' && evt.message && typeof evt.message === 'object') {
      message = { ...evt.message };
      usage = mergeUsageMax(usage, evt.message.usage);
      continue;
    }

    if (evt.type === 'content_block_start' && Number.isInteger(evt.index) && evt.content_block && typeof evt.content_block === 'object') {
      const block = { ...evt.content_block };
      if (block.type === 'text') {
        if (typeof block.text !== 'string') block.text = '';
      }
      if (block.type === 'tool_use') {
        // Tool inputs may arrive as incremental JSON deltas; accumulate and parse at the end.
        if (!block.input || typeof block.input !== 'object') block.input = {};
        block._input_json = '';
      }
      blocksByIndex.set(evt.index, block);
      continue;
    }

    if (evt.type === 'content_block_delta' && Number.isInteger(evt.index) && evt.delta && typeof evt.delta === 'object') {
      const block = blocksByIndex.get(evt.index);
      if (!block) continue;
      if (evt.delta.type === 'text_delta' && typeof evt.delta.text === 'string') {
        block.text = (block.text || '') + evt.delta.text;
      } else if (evt.delta.type === 'input_json_delta' && typeof evt.delta.partial_json === 'string') {
        block._input_json = (block._input_json || '') + evt.delta.partial_json;
      }
      continue;
    }

    if (evt.type === 'content_block_stop' && Number.isInteger(evt.index)) {
      const block = blocksByIndex.get(evt.index);
      if (!block) continue;
      if (block.type === 'tool_use') {
        const raw = block._input_json;
        delete block._input_json;
        if (raw && typeof raw === 'string') {
          const parsed = tryParseJson(raw);
          if (parsed && typeof parsed === 'object') block.input = parsed;
          else block.input = { _raw: raw.substring(0, 5000) };
        }
        if (!block.input || typeof block.input !== 'object') block.input = {};
      }
      continue;
    }

    if (evt.type === 'message_delta') {
      if (evt.delta && typeof evt.delta === 'object' && typeof evt.delta.stop_reason === 'string') {
        stopReason = evt.delta.stop_reason;
      }
      usage = mergeUsageMax(usage, evt.usage);
      continue;
    }
  }

  const content = Array.from(blocksByIndex.entries())
    .sort((a, b) => a[0] - b[0])
    .map(([, block]) => {
      const copy = { ...block };
      delete copy._input_json;
      if (copy.type === 'tool_use') {
        if (!copy.input || typeof copy.input !== 'object') copy.input = {};
      }
      if (copy.type === 'text') {
        if (typeof copy.text !== 'string') copy.text = '';
      }
      return copy;
    });

  const response = message ? { ...message } : {};
  if (content.length > 0) response.content = content;
  if (!response.usage || typeof response.usage !== 'object') response.usage = usage;
  else response.usage = mergeUsageMax(response.usage, usage);
  if (!response.stop_reason && stopReason) response.stop_reason = stopReason;

  return response;
}

function parseAnthropicResponseBody(text, contentType) {
  const trimmed = (text || '').trim();
  if (!trimmed) return {};

  // Try parsing as JSON first (non-streaming responses)
  const json = tryParseJson(trimmed);
  if (json && typeof json === 'object') return json;

  // Try parsing as SSE event-stream (streaming responses)
  const isEventStream = (contentType && contentType.includes('text/event-stream'))
    || trimmed.startsWith('event:')
    || trimmed.startsWith('data:');
  if (isEventStream) {
    const parsed = parseAnthropicEventStream(trimmed);
    if (parsed) return parsed;
  }

  // Fallback: return raw text (truncated)
  return { raw: trimmed.substring(0, 5000) };
}

// =============================================================================
// Claude Code Session Metadata (from hooks)
// =============================================================================

/**
 * Best-effort read of Claude Code's native session UUID (from SessionStart hook).
 * Hook writes: $XDG_RUNTIME_DIR/claude-session-${process.pid}.json
 *
 * This enables correlation between:
 * - Claude Code native OTEL metrics/logs (session.id UUID)
 * - Interceptor-generated traces (session.id + gen_ai.conversation.id)
 */
function maybeHydrateClaudeSessionId() {
  // Only upgrade from fallback → hook-derived. Never downgrade.
  if (state.session.sessionIdSource !== 'fallback') return;

  try {
    if (!fs.existsSync(SESSION_META_FILE)) return;
    const raw = fs.readFileSync(SESSION_META_FILE, 'utf8');
    const meta = JSON.parse(raw);
    const sessionId = meta.sessionId;
    if (!sessionId || typeof sessionId !== 'string') return;

    state.session.sessionId = sessionId;
    state.session.sessionIdSource = 'hook';
    flushSpanBuffer();
  } catch (e) {
    // Silent failure to avoid disrupting Claude Code
  }
}

// =============================================================================
// Hook-driven Turn Boundaries (UserPromptSubmit + Stop)
// =============================================================================

function shouldUseHookTurnBoundaries() {
  if (TURN_BOUNDARY_MODE === 'hooks') return true;
  if (TURN_BOUNDARY_MODE === 'heuristic') return false;
  // auto: enable hook boundaries once we observe hook metadata files.
  return state.hooks.turnBoundariesEnabled
    || fs.existsSync(PROMPT_META_FILE)
    || fs.existsSync(STOP_META_FILE);
}

function readJsonFileSafe(filePath) {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function maybeUpgradeSessionIdFromHook(meta) {
  if (!meta || typeof meta !== 'object') return;
  const sessionId = meta.sessionId;
  if (!sessionId || typeof sessionId !== 'string') return;
  if (state.session.sessionIdSource !== 'fallback') return;

  state.session.sessionId = sessionId;
  state.session.sessionIdSource = 'hook';
  flushSpanBuffer();
}

function startNewTurnFromHookPrompt(promptMeta) {
  if (!promptMeta || typeof promptMeta !== 'object') return;

  state.hooks.turnBoundariesEnabled = true;
  maybeUpgradeSessionIdFromHook(promptMeta);

  const prompt = typeof promptMeta.prompt === 'string' ? promptMeta.prompt : '';
  const ts = typeof promptMeta.timestampMs === 'number' ? promptMeta.timestampMs : Date.now();

  if (ts <= state.hooks.lastPromptTimestampMs) return;
  state.hooks.lastPromptTimestampMs = ts;

  // If a prior turn is still active, close it at the new prompt timestamp.
  if (state.currentTurn) {
    endCurrentTurn(ts, 'new_prompt');
  }

  state.session.turnCount++;

  const promptPreview = getPreview(prompt, 60);
  state.currentTurn = {
    spanId: generateId(8),
    turnNumber: state.session.turnCount,
    startTime: ts,
    endTime: null,
    endReason: null,
    startSource: 'hook',
    tokens: createTokenCounts(),
    llmCallCount: 0,
    toolCallCount: 0,
    errorCount: 0,
    activeTools: new Set(),
    promptPreview: promptPreview
  };
}

function endTurnFromHookStop(stopMeta) {
  if (!stopMeta || typeof stopMeta !== 'object') return;

  state.hooks.turnBoundariesEnabled = true;
  maybeUpgradeSessionIdFromHook(stopMeta);

  const ts = typeof stopMeta.timestampMs === 'number' ? stopMeta.timestampMs : Date.now();
  if (ts <= state.hooks.lastStopTimestampMs) return;
  state.hooks.lastStopTimestampMs = ts;

  if (!state.currentTurn) return;
  if (ts < state.currentTurn.startTime) return;
  endCurrentTurn(ts, 'stop_hook');
}

function pollTurnHookFiles() {
  if (!shouldUseHookTurnBoundaries()) return;

  // Always try to hydrate from SessionStart runtime file too.
  maybeHydrateClaudeSessionId();

  try {
    // Prompt
    if (fs.existsSync(PROMPT_META_FILE)) {
      const stat = fs.statSync(PROMPT_META_FILE);
      const mtimeMs = stat.mtimeMs;
      if (mtimeMs > state.hooks.promptMtimeMs) {
        state.hooks.promptMtimeMs = mtimeMs;
        const meta = readJsonFileSafe(PROMPT_META_FILE);
        startNewTurnFromHookPrompt(meta);
      }
    }

    // Stop
    if (fs.existsSync(STOP_META_FILE)) {
      const stat = fs.statSync(STOP_META_FILE);
      const mtimeMs = stat.mtimeMs;
      if (mtimeMs > state.hooks.stopMtimeMs) {
        state.hooks.stopMtimeMs = mtimeMs;
        const meta = readJsonFileSafe(STOP_META_FILE);
        endTurnFromHookStop(meta);
      }
    }
  } catch {
    // Silent failure
  }
}

function startTurnHookPoller() {
  if (state.hooks.pollerStarted) return;
  if (TURN_BOUNDARY_MODE === 'heuristic') return;

  state.hooks.pollerStarted = true;
  const interval = setInterval(() => {
    pollTurnHookFiles();
    pollPermissionFiles();
    pollPostToolFiles();
    pollSubagentStopFiles();
    pollNotificationFiles();
    pollCompactionFiles();
  }, Number.isFinite(HOOK_POLL_INTERVAL_MS) ? HOOK_POLL_INTERVAL_MS : 200);
  interval.unref();
}

// =============================================================================
// Permission Wait Visibility (Phase C)
// =============================================================================

/**
 * Poll for permission request files written by PermissionRequest hook.
 * Permission files are created at: $RUNTIME_DIR/claude-permission-${pid}-${toolUseId}.json
 */
function pollPermissionFiles() {
  try {
    const files = fs.readdirSync(RUNTIME_DIR);
    const prefix = `${PERMISSION_FILE_PREFIX}${process.pid}-`;

    for (const file of files) {
      if (!file.startsWith(prefix)) continue;
      if (!file.endsWith('.json')) continue;

      // Extract toolUseId from filename
      const toolUseId = file.slice(prefix.length, -5);  // Remove prefix and .json

      // Skip if already tracking this permission
      if (state.pendingPermissions.has(toolUseId)) continue;

      const filePath = path.join(RUNTIME_DIR, file);
      const meta = readJsonFileSafe(filePath);
      if (!meta || typeof meta !== 'object') continue;

      // Validate schema version
      if (meta.version !== 1) continue;

      // Create pending permission entry
      const spanId = generateId(8);
      state.pendingPermissions.set(toolUseId, {
        spanId,
        toolName: meta.toolName || 'unknown',
        toolUseId: meta.toolUseId || toolUseId,
        toolDescription: meta.toolDescription || null,
        startTime: meta.startTimestampMs || Date.now(),
        filePath
      });
    }
  } catch {
    // Silent failure - permission polling is best-effort
  }
}

/**
 * Complete a permission span when tool_result arrives (approval) or turn ends (denied/timeout).
 * @param {string} toolUseId - Tool use ID to complete
 * @param {'approved'|'denied'|'timeout'} result - Permission result
 */
function completePermissionSpan(toolUseId, result) {
  const pending = state.pendingPermissions.get(toolUseId);
  if (!pending) return;

  state.pendingPermissions.delete(toolUseId);

  const endTime = Date.now();
  const durationMs = endTime - pending.startTime;

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'PERMISSION' } },
    { key: 'permission.tool', value: { stringValue: pending.toolName } },
    { key: 'permission.result', value: { stringValue: result } },
    { key: 'permission.wait_ms', value: { intValue: durationMs.toString() } },
    { key: 'gen_ai.tool.call.id', value: { stringValue: pending.toolUseId } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } }
  ];

  // Add tool description if available
  if (pending.toolDescription) {
    attributes.push({ key: 'permission.prompt', value: { stringValue: pending.toolDescription } });
  }

  // Get parent span ID - use turn span if available, otherwise session
  const parentSpanId = state.currentTurn ? state.currentTurn.spanId : state.session.spanId;

  const spanName = `Permission: ${pending.toolName} (${result})`;

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: pending.spanId,
    parentSpanId: parentSpanId,
    name: spanName,
    kind: 'SPAN_KIND_INTERNAL',
    startTime: pending.startTime,
    endTime: endTime,
    attributes: attributes,
    status: result === 'approved'
      ? { code: 'STATUS_CODE_OK' }
      : { code: 'STATUS_CODE_ERROR', message: `Permission ${result}` }
  });

  sendToAlloy(spanRecord);

  // Clean up the permission file
  try {
    if (pending.filePath && fs.existsSync(pending.filePath)) {
      fs.unlinkSync(pending.filePath);
    }
  } catch {
    // Silent failure
  }
}

// =============================================================================
// PostToolUse Hook Integration (Phase 3)
// =============================================================================

/**
 * Poll for posttool files written by PostToolUse hook.
 * Caches tool completion metadata for enriching Tool spans in completeToolSpan().
 * PostToolUse files are created at: $RUNTIME_DIR/claude-posttool-${pid}-${toolUseId}.json
 */
function pollPostToolFiles() {
  try {
    const files = fs.readdirSync(RUNTIME_DIR);
    const prefix = `${POSTTOOL_FILE_PREFIX}${process.pid}-`;

    for (const file of files) {
      if (!file.startsWith(prefix)) continue;
      if (!file.endsWith('.json')) continue;

      // Extract toolUseId from filename
      const toolUseId = file.slice(prefix.length, -5);  // Remove prefix and .json

      // Skip if already cached
      if (state.postToolCache.has(toolUseId)) continue;

      const filePath = path.join(RUNTIME_DIR, file);
      const meta = readJsonFileSafe(filePath);
      if (!meta || typeof meta !== 'object') continue;

      // Validate schema version
      if (meta.version !== 1) continue;

      // Cache posttool metadata for use in completeToolSpan()
      state.postToolCache.set(toolUseId, {
        exitCode: meta.exitCode,
        outputSummary: meta.outputSummary,
        outputLines: meta.outputLines,
        isError: meta.isError || false,
        errorType: meta.errorType,
        completedAtMs: meta.completedAtMs,
        filePath
      });
    }
  } catch {
    // Silent failure - posttool polling is best-effort
  }
}

/**
 * Get and consume cached posttool metadata for a tool.
 * @param {string} toolUseId - Tool use ID
 * @returns {object|null} Posttool metadata or null if not found
 */
function consumePostToolMeta(toolUseId) {
  const meta = state.postToolCache.get(toolUseId);
  if (!meta) return null;

  state.postToolCache.delete(toolUseId);

  // Clean up the file
  try {
    if (meta.filePath && fs.existsSync(meta.filePath)) {
      fs.unlinkSync(meta.filePath);
    }
  } catch {
    // Silent failure
  }

  return meta;
}

// =============================================================================
// SubagentStop Hook Integration (Phase 3)
// =============================================================================

/**
 * Poll for subagent-stop files written by SubagentStop hook.
 * Creates a completion annotation span when Task subagents finish.
 * SubagentStop files are created at: $RUNTIME_DIR/claude-subagent-stop-${pid}-${toolUseId}.json
 */
function pollSubagentStopFiles() {
  try {
    const files = fs.readdirSync(RUNTIME_DIR);
    const prefix = `${SUBAGENT_STOP_FILE_PREFIX}${process.pid}-`;

    for (const file of files) {
      if (!file.startsWith(prefix)) continue;
      if (!file.endsWith('.json')) continue;

      // Extract toolUseId from filename
      const toolUseId = file.slice(prefix.length, -5);  // Remove prefix and .json

      // Skip if already processed
      if (state.processedSubagentStops.has(toolUseId)) continue;

      const filePath = path.join(RUNTIME_DIR, file);
      const meta = readJsonFileSafe(filePath);
      if (!meta || typeof meta !== 'object') continue;

      // Validate schema version
      if (meta.version !== 1) continue;

      // Mark as processed
      state.processedSubagentStops.add(toolUseId);

      // Create subagent completion span (links to Task tool span)
      createSubagentCompletionSpan(toolUseId, meta);

      // Clean up the file
      try {
        fs.unlinkSync(filePath);
      } catch {
        // Silent failure
      }
    }
  } catch {
    // Silent failure - subagent stop polling is best-effort
  }
}

/**
 * Create a subagent completion span when SubagentStop hook fires.
 * This is a separate span that links to the original Task tool span.
 * @param {string} toolUseId - The Task tool_use_id
 * @param {object} meta - SubagentStop metadata from hook file
 */
function createSubagentCompletionSpan(toolUseId, meta) {
  const spanId = generateId(8);
  const timestamp = meta.completedAtMs || Date.now();

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'SUBAGENT_COMPLETION' } },
    { key: 'gen_ai.tool.call.id', value: { stringValue: toolUseId } },
    { key: 'subagent.completed', value: { boolValue: true } },
    { key: 'subagent.completion_source', value: { stringValue: 'hook' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } }
  ];

  // Add subagent session ID if available
  if (meta.subagentSessionId) {
    attributes.push({ key: 'subagent.session_id', value: { stringValue: meta.subagentSessionId } });
  }

  const parentSpanId = state.currentTurn ? state.currentTurn.spanId : state.session.spanId;
  const spanName = `Subagent Complete: ${toolUseId.substring(0, 8)}`;

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: spanId,
    parentSpanId: parentSpanId,
    name: spanName,
    kind: 'SPAN_KIND_INTERNAL',
    startTime: timestamp,
    endTime: timestamp + 1,  // Zero-duration event span
    attributes: attributes,
    status: { code: 'STATUS_CODE_OK' }
  });

  sendToAlloy(spanRecord);
}

// =============================================================================
// Notification Spans (Phase 3)
// =============================================================================

/**
 * Poll for notification files written by Notification hook.
 * Creates NOTIFICATION spans for permission_prompt, auth_success, etc.
 * Notification files are created at: $RUNTIME_DIR/claude-notification-${pid}-${timestamp}.json
 */
function pollNotificationFiles() {
  try {
    const files = fs.readdirSync(RUNTIME_DIR);
    const prefix = `${NOTIFICATION_FILE_PREFIX}${process.pid}-`;

    for (const file of files) {
      if (!file.startsWith(prefix)) continue;
      if (!file.endsWith('.json')) continue;

      // Extract timestamp from filename
      const timestampStr = file.slice(prefix.length, -5);  // Remove prefix and .json

      // Skip if already processed
      if (state.processedNotifications.has(timestampStr)) continue;

      const filePath = path.join(RUNTIME_DIR, file);
      const meta = readJsonFileSafe(filePath);
      if (!meta || typeof meta !== 'object') continue;

      // Validate schema version
      if (meta.version !== 1) continue;

      // Mark as processed
      state.processedNotifications.add(timestampStr);

      // Create notification span
      createNotificationSpan(meta);

      // Clean up the file
      try {
        fs.unlinkSync(filePath);
      } catch {
        // Silent failure
      }
    }
  } catch {
    // Silent failure - notification polling is best-effort
  }
}

/**
 * Create a NOTIFICATION span for Claude Code notification events.
 * @param {object} meta - Notification metadata from hook file
 */
function createNotificationSpan(meta) {
  const spanId = generateId(8);
  const timestamp = meta.timestampMs || Date.now();

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'NOTIFICATION' } },
    { key: 'notification.type', value: { stringValue: meta.notificationType || 'unknown' } },
    { key: 'notification.timestamp_ms', value: { intValue: timestamp.toString() } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } }
  ];

  // Add message if available
  if (meta.message) {
    attributes.push({ key: 'notification.message', value: { stringValue: meta.message } });
  }

  const parentSpanId = state.currentTurn ? state.currentTurn.spanId : state.session.spanId;
  const spanName = `Notification: ${meta.notificationType || 'unknown'}`;

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: spanId,
    parentSpanId: parentSpanId,
    name: spanName,
    kind: 'SPAN_KIND_INTERNAL',
    startTime: timestamp,
    endTime: timestamp + 1,  // Zero-duration event span
    attributes: attributes,
    status: { code: 'STATUS_CODE_OK' }
  });

  sendToAlloy(spanRecord);
}

// =============================================================================
// Compaction Spans (Phase 3)
// =============================================================================

/**
 * Poll for precompact files written by PreCompact hook.
 * Creates COMPACTION spans when context window is compacted.
 * PreCompact files are created at: $RUNTIME_DIR/claude-precompact-${pid}-${timestamp}.json
 */
function pollCompactionFiles() {
  try {
    const files = fs.readdirSync(RUNTIME_DIR);
    const prefix = `${PRECOMPACT_FILE_PREFIX}${process.pid}-`;

    for (const file of files) {
      if (!file.startsWith(prefix)) continue;
      if (!file.endsWith('.json')) continue;

      // Extract timestamp from filename
      const timestampStr = file.slice(prefix.length, -5);  // Remove prefix and .json

      // Skip if already processed
      if (state.processedCompactions.has(timestampStr)) continue;

      const filePath = path.join(RUNTIME_DIR, file);
      const meta = readJsonFileSafe(filePath);
      if (!meta || typeof meta !== 'object') continue;

      // Validate schema version
      if (meta.version !== 1) continue;

      // Mark as processed
      state.processedCompactions.add(timestampStr);

      // Create compaction span
      createCompactionSpan(meta);

      // Clean up the file
      try {
        fs.unlinkSync(filePath);
      } catch {
        // Silent failure
      }
    }
  } catch {
    // Silent failure - compaction polling is best-effort
  }
}

/**
 * Create a COMPACTION span when context window is compacted.
 * @param {object} meta - Compaction metadata from hook file
 */
function createCompactionSpan(meta) {
  const spanId = generateId(8);
  const timestamp = meta.timestampMs || Date.now();

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'COMPACTION' } },
    { key: 'compaction.reason', value: { stringValue: meta.compactType || 'unknown' } },
    { key: 'compaction.trigger', value: { stringValue: meta.trigger || 'unknown' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } }
  ];

  // Add messages_before if available
  if (meta.messagesBefore !== undefined && meta.messagesBefore !== null) {
    attributes.push({ key: 'compaction.messages_before', value: { intValue: meta.messagesBefore.toString() } });
  }

  const parentSpanId = state.currentTurn ? state.currentTurn.spanId : state.session.spanId;
  const spanName = `Compaction: ${meta.compactType || 'unknown'}`;

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: spanId,
    parentSpanId: parentSpanId,
    name: spanName,
    kind: 'SPAN_KIND_INTERNAL',
    startTime: timestamp,
    endTime: timestamp + 1,  // Zero-duration event span
    attributes: attributes,
    status: { code: 'STATUS_CODE_OK' }
  });

  sendToAlloy(spanRecord);
}

// =============================================================================
// Parent Trace Context (for subagent correlation)
// =============================================================================

/**
 * Check if a process is still running
 * @param {number} pid - Process ID to check
 * @returns {boolean} True if process exists
 */
function isProcessRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return false;
  }
}

/**
 * Get parent PID of a process using /proc filesystem
 * @param {number} pid - Process ID
 * @returns {number|null} Parent PID or null if not found
 */
function getParentPid(pid) {
  if (!PROC_AVAILABLE) return null;
  try {
    const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
    const fields = stat.split(' ');
    // Field 4 (0-indexed: 3) is the parent PID
    return parseInt(fields[3], 10);
  } catch (e) {
    return null;
  }
}

/**
 * Check whether a PID is in our ancestor chain (best-effort).
 * This prevents subagents from accidentally linking to unrelated sessions.
 *
 * @param {number} targetPid
 * @returns {boolean}
 */
function isAncestorPid(targetPid) {
  if (!PROC_AVAILABLE) return false;

  let currentPid = process.ppid;
  const checked = new Set();
  const maxDepth = 25;
  let depth = 0;

  while (currentPid > 1 && !checked.has(currentPid) && depth < maxDepth) {
    if (currentPid === targetPid) return true;
    checked.add(currentPid);
    depth++;

    const nextPid = getParentPid(currentPid);
    if (!nextPid || nextPid === currentPid) break;
    currentPid = nextPid;
  }

  return false;
}

/**
 * Walk up the process tree looking for a trace context file
 * @returns {{traceId: string, spanId: string} | null}
 */
function walkProcessTree() {
  if (!PROC_AVAILABLE) return null;

  let currentPid = process.ppid;
  const checked = new Set();
  const maxDepth = 10; // Prevent infinite loops
  let depth = 0;

  while (currentPid > 1 && !checked.has(currentPid) && depth < maxDepth) {
    checked.add(currentPid);
    depth++;

    // Check for trace context file at this level
    const stateFile = path.join(RUNTIME_DIR, `claude-otel-${currentPid}.json`);
    try {
      if (fs.existsSync(stateFile)) {
        const content = fs.readFileSync(stateFile, 'utf8');
        const ctx = JSON.parse(content);
        if (ctx.traceId && ctx.spanId) {
          return ctx;
        }
      }
    } catch (e) {
      // Continue walking
    }

    // Get parent's parent
    const nextPid = getParentPid(currentPid);
    if (!nextPid || nextPid === currentPid) break;
    currentPid = nextPid;
  }

  return null;
}

/**
 * Find the most recently created trace context file from a running process
 * @returns {{traceId: string, spanId: string} | null}
 */
function findMostRecentContext() {
  try {
    const files = fs.readdirSync(RUNTIME_DIR)
      .filter(f => f.startsWith('claude-otel-') && f.endsWith('.json'));

    if (files.length === 0) return null;

    const ourPid = process.pid;
    const ourStartTime = SESSION_START_TIME;
    let bestMatch = null;
    let bestMtime = 0;

    for (const file of files) {
      const filePath = path.join(RUNTIME_DIR, file);
      const pidMatch = file.match(/claude-otel-(\d+)\.json/);
      if (!pidMatch) continue;

      const filePid = parseInt(pidMatch[1], 10);
      // Skip our own file
      if (filePid === ourPid) continue;

      try {
        const stats = fs.statSync(filePath);
        // Must be from before we started (parent wrote it before spawning us)
        // and must be from a running process
        if (stats.mtimeMs < ourStartTime && stats.mtimeMs > bestMtime) {
          if (isProcessRunning(filePid)) {
            const content = fs.readFileSync(filePath, 'utf8');
            const ctx = JSON.parse(content);
            if (ctx.traceId && ctx.spanId) {
              bestMatch = ctx;
              bestMtime = stats.mtimeMs;
            }
          }
        }
      } catch (e) {
        // Skip this file
      }
    }

    return bestMatch;
  } catch (e) {
    return null;
  }
}

/**
 * Normalize arbitrary prompt/description text for heuristic matching.
 * @param {string} text
 * @returns {string}
 */
function normalizeForMatch(text) {
  if (!text || typeof text !== 'string') return '';
  return text
    .toLowerCase()
    .replace(/[\r\n]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 400);
}

/**
 * Very small tokenization for matching (kept intentionally simple/fast).
 * @param {string} text
 * @returns {Set<string>}
 */
function tokenSet(text) {
  const out = new Set();
  const norm = normalizeForMatch(text);
  for (const tok of norm.split(/[^a-z0-9_]+/g)) {
    if (tok.length < 3) continue;
    out.add(tok);
    if (out.size >= 64) break;
  }
  return out;
}

/**
 * Jaccard similarity between two sets.
 * @param {Set<string>} a
 * @param {Set<string>} b
 * @returns {number}
 */
function jaccard(a, b) {
  if (a.size === 0 || b.size === 0) return 0;
  let intersection = 0;
  for (const x of a) {
    if (b.has(x)) intersection++;
  }
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

/**
 * Score how well a Task tool description matches a subagent prompt.
 * @param {string} taskPreview
 * @param {string} promptPreview
 * @returns {number} 0..1
 */
function scoreTaskMatch(taskPreview, promptPreview) {
  const a = normalizeForMatch(taskPreview);
  const b = normalizeForMatch(promptPreview);
  if (!a || !b) return 0;
  if (a === b) return 1;
  if (a.length >= 12 && b.includes(a)) return 0.95;
  if (b.length >= 12 && a.includes(b)) return 0.9;
  return jaccard(tokenSet(a), tokenSet(b));
}

/**
 * Write a Task context file so the spawned subagent can link to the correct parent.
 * This avoids the "last Task wins" race when multiple Tasks are spawned from one LLM response.
 *
 * @param {string} traceId
 * @param {string} spanId
 * @param {{id: string, name: string, input: object}} toolUse
 * @param {string|null} parentSessionId
 */
function writeTaskContextFile(traceId, spanId, toolUse, parentSessionId = null) {
  try {
    const taskDesc = toolUse?.input?.description || toolUse?.input?.prompt || '';
    const payload = {
      version: 1,
      traceId,
      spanId,
      parentPid: process.pid,
      parentSessionId: parentSessionId || null,
      toolUseId: toolUse?.id || null,
      createdAtMs: Date.now(),
      taskDescriptionPreview: getPreview(taskDesc, 120)
    };

    const fileName = `${TASK_CONTEXT_PREFIX}${process.pid}-${toolUse.id}.json`;
    const filePath = path.join(RUNTIME_DIR, fileName);
    fs.writeFileSync(filePath, JSON.stringify(payload));
  } catch (e) {
    // Silent failure
  }
}

/**
 * Attempt to claim a Task context file for this process (subagent) and return the parent span context.
 * Claiming is done via atomic rename to avoid double-claims.
 *
 * @param {string} subagentPromptPreview
 * @returns {{traceId: string, spanId: string, toolUseId?: string, parentSessionId?: string} | null}
 */
function claimTaskContextFile(subagentPromptPreview) {
  try {
    const files = fs.readdirSync(RUNTIME_DIR)
      .filter(f => f.startsWith(TASK_CONTEXT_PREFIX) && f.endsWith('.json'));

    if (files.length === 0) return null;

    const candidates = [];
    for (const file of files) {
      const filePath = path.join(RUNTIME_DIR, file);
      try {
        const raw = fs.readFileSync(filePath, 'utf8');
        const ctx = JSON.parse(raw);
        if (!ctx || !ctx.traceId || !ctx.spanId || !ctx.parentPid) continue;

        const parentPid = Number(ctx.parentPid);
        if (!Number.isFinite(parentPid)) continue;
        if (!isProcessRunning(parentPid)) continue;
        if (!isAncestorPid(parentPid)) continue;

        // Basic age bound to avoid claiming stale contexts.
        const createdAt = Number(ctx.createdAtMs || 0);
        if (Number.isFinite(createdAt) && createdAt > 0) {
          const ageMs = Date.now() - createdAt;
          if (ageMs < 0 || ageMs > 10 * 60 * 1000) continue; // 10 minutes
        }

        const score = scoreTaskMatch(ctx.taskDescriptionPreview || '', subagentPromptPreview);
        candidates.push({ file, filePath, ctx, score });
      } catch (e) {
        // Skip
      }
    }

    if (candidates.length === 0) return null;

    candidates.sort((a, b) => {
      // Prefer higher match score; tie-breaker: newest first.
      if (b.score !== a.score) return b.score - a.score;
      return (Number(b.ctx.createdAtMs || 0) - Number(a.ctx.createdAtMs || 0));
    });

    for (const cand of candidates) {
      const claimedPath = `${cand.filePath}.claimed-${process.pid}`;
      try {
        fs.renameSync(cand.filePath, claimedPath);
        // Best-effort cleanup after claim
        try { fs.unlinkSync(claimedPath); } catch {}
        return {
          traceId: cand.ctx.traceId,
          spanId: cand.ctx.spanId,
          toolUseId: cand.ctx.toolUseId || undefined,
          parentSessionId: cand.ctx.parentSessionId || undefined
        };
      } catch (e) {
        // Likely claimed by someone else; try next
      }
    }

    return null;
  } catch (e) {
    return null;
  }
}

/**
 * Fallback parent context lookup (used when Task context files are unavailable).
 *
 * Methods (in order of preference):
 * 1. Environment variable (W3C trace context)
 * 2. Process tree walking (handles intermediate shells like bash, systemd)
 * 3. Most recent context file (best-effort fallback)
 *
 * @returns {{traceId: string, spanId: string} | null}
 */
function parseTraceParentEnv() {
  // 1. Try environment variable (standard W3C trace context)
  const traceparent = process.env.OTEL_TRACE_PARENT;
  if (traceparent) {
    const parts = traceparent.split('-');
    if (parts.length >= 3) {
      return { traceId: parts[1], spanId: parts[2] };
    }
  }

  // 2. Walk up process tree (handles intermediate shells like bash, systemd)
  const treeResult = walkProcessTree();
  if (treeResult) return treeResult;

  // 3. Find most recent context file from running process
  const recentResult = findMostRecentContext();
  if (recentResult) return recentResult;

  return null;
}

/**
 * Resolve (once) the parent Task span context for subagent processes.
 * Prefers per-Task context files to avoid ambiguity when multiple Tasks are spawned.
 *
 * @param {object} requestBody
 */
function maybeResolveParentContext(requestBody) {
  if (state.session.parentContext) return;

  // Prefer Task context files first (most reliable when multiple Tasks are spawned).
  try {
    const promptText = extractUserPrompt(requestBody || {});
    const promptPreview = getPreview(promptText, 120);
    const claimed = claimTaskContextFile(promptPreview);
    if (claimed) {
      state.session.parentContext = { traceId: claimed.traceId, spanId: claimed.spanId };
      state.session.parentContextSource = 'task_context_file';
      if (claimed.parentSessionId) {
        state.session.parentSessionId = claimed.parentSessionId;
      }
      return;
    }
  } catch (e) {
    // Continue to fallback
  }

  const fallback = parseTraceParentEnv();
  if (fallback) {
    state.session.parentContext = fallback;
    state.session.parentContextSource = 'env_or_proc';
  }
}

/**
 * Set trace context for subagent processes
 * Writes to multiple locations for maximum reliability:
 * - Environment variable (for inherited environments)
 * - Runtime directory file (for process tree lookup)
 *
 * @param {string} traceId - Current trace ID
 * @param {string} spanId - Current span ID (Task tool span)
 */
function setTraceParentEnv(traceId, spanId) {
  const context = { traceId, spanId, pid: process.pid, timestamp: Date.now() };

  // 1. Set environment variable (standard W3C trace context)
  process.env.OTEL_TRACE_PARENT = `00-${traceId}-${spanId}-01`;

  // 2. Write to runtime directory (for process tree lookup)
  try {
    const stateFile = path.join(RUNTIME_DIR, `claude-otel-${process.pid}.json`);
    // Merge to preserve any metadata written by hooks (e.g., sessionId).
    let merged = context;
    try {
      if (fs.existsSync(stateFile)) {
        const existing = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
        merged = { ...existing, ...context };
      }
    } catch {}
    fs.writeFileSync(stateFile, JSON.stringify(merged));
  } catch (e) {
    // Silent failure
  }
}

/**
 * Clean up trace context state files on process exit
 */
function cleanupTraceContext() {
  // Clean runtime directory context file (best-effort)
  try {
    const stateFile = path.join(RUNTIME_DIR, `claude-otel-${process.pid}.json`);
    if (fs.existsSync(stateFile)) {
      fs.unlinkSync(stateFile);
    }
  } catch (e) {
    // Silent failure
  }

  // Clean any unclaimed Task context files created by this process
  try {
    const files = fs.readdirSync(RUNTIME_DIR)
      .filter(f => f.startsWith(`${TASK_CONTEXT_PREFIX}${process.pid}-`) && f.endsWith('.json'));
    for (const f of files) {
      try { fs.unlinkSync(path.join(RUNTIME_DIR, f)); } catch {}
    }
  } catch (e) {
    // Silent failure
  }

  // Clean session metadata file (hook also attempts cleanup)
  try {
    if (fs.existsSync(SESSION_META_FILE)) {
      fs.unlinkSync(SESSION_META_FILE);
    }
  } catch (e) {
    // Silent failure
  }

  // Clean turn boundary metadata files (written by hooks)
  try {
    if (fs.existsSync(PROMPT_META_FILE)) {
      fs.unlinkSync(PROMPT_META_FILE);
    }
  } catch {}
  try {
    if (fs.existsSync(STOP_META_FILE)) {
      fs.unlinkSync(STOP_META_FILE);
    }
  } catch {}
}

// =============================================================================
// Session State (Singleton)
// =============================================================================

const SESSION_START_TIME = Date.now();
const FALLBACK_SESSION_ID = `claude-${process.pid}-${SESSION_START_TIME}`;
const SESSION_TRACE_ID = generateId(16);
const SESSION_ROOT_SPAN_ID = generateId(8);

const state = {
  session: {
    traceId: SESSION_TRACE_ID,
    spanId: SESSION_ROOT_SPAN_ID,
    sessionId: FALLBACK_SESSION_ID,
    sessionIdSource: 'fallback',
    startTime: SESSION_START_TIME,
    tokens: createTokenCounts(),
    turnCount: 0,
    apiCallCount: 0,
    hasAnySpans: false,
    finalized: false,
    parentContext: null,           // For subagent span links (resolved lazily)
    parentContextSource: null,     // Where we got parentContext (debugging)
    parentSessionId: null          // Parent Claude Code session.id (UUID), if known
  },
  currentTurn: null,
  turnEndTimer: null,
  pendingTools: new Map(),  // toolCallId -> PendingToolSpan
  pendingPermissions: new Map(),  // toolUseId -> { spanId, toolName, startTime, toolDescription }
  postToolCache: new Map(),       // toolUseId -> { exitCode, outputSummary, outputLines, errorType }
  processedSubagentStops: new Set(),  // toolUseId set (to avoid duplicate processing)
  processedNotifications: new Set(),  // timestamp set (to avoid duplicate notification spans)
  processedCompactions: new Set(),    // timestamp set (to avoid duplicate compaction spans)
  hooks: {
    pollerStarted: false,
    turnBoundariesEnabled: false,
    promptMtimeMs: 0,
    stopMtimeMs: 0,
    lastPromptTimestampMs: 0,
    lastStopTimestampMs: 0
  },
  exportBuffer: {
    firstBufferedAt: null,
    spans: []
  }
};

// =============================================================================
// OTLP Export Functions
// =============================================================================

/**
 * Low-level OTLP exporter (no buffering)
 * @param {object} spanRecord - Full OTLP resourceSpans structure
 */
function postToAlloy(spanRecord) {
  try {
    const data = JSON.stringify(spanRecord);
    const alloyUrl = new URL(TRACE_ENDPOINT);

    const postReq = http.request({
      hostname: alloyUrl.hostname,
      port: alloyUrl.port,
      path: alloyUrl.pathname,
      method: 'POST',
      // Avoid keeping sockets open (important for short-lived `claude "<prompt>"` runs).
      agent: false,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.from(data).length
      }
    }, (res) => {
      res.resume();
    });

    postReq.on('error', () => {});
    postReq.setTimeout(2000, () => postReq.destroy());
    postReq.write(data);
    postReq.end();
  } catch (e) {
    // Silent failure to avoid disrupting Claude Code
  }
}

function setSpanAttribute(attributes, key, value) {
  if (!Array.isArray(attributes)) return;
  const existing = attributes.find(a => a && a.key === key);
  if (existing) {
    existing.value = value;
    return;
  }
  attributes.push({ key, value });
}

function applySessionIdToSpanRecord(spanRecord) {
  try {
    const span = spanRecord?.resourceSpans?.[0]?.scopeSpans?.[0]?.spans?.[0];
    if (!span) return;
    if (!Array.isArray(span.attributes)) span.attributes = [];

    setSpanAttribute(span.attributes, 'gen_ai.conversation.id', { stringValue: state.session.sessionId });
    setSpanAttribute(span.attributes, 'session.id', { stringValue: state.session.sessionId });
    setSpanAttribute(span.attributes, 'claude.session_id_source', { stringValue: state.session.sessionIdSource });
  } catch (e) {
    // Silent failure
  }
}

function flushSpanBuffer({ force = false } = {}) {
  const buf = state.exportBuffer;
  if (!buf || buf.spans.length === 0) return;

  if (!force && state.session.sessionIdSource === 'fallback') return;

  for (const rec of buf.spans) {
    applySessionIdToSpanRecord(rec);
    postToAlloy(rec);
  }

  buf.spans = [];
  buf.firstBufferedAt = null;
}

function maybeExpireSpanBuffer() {
  const buf = state.exportBuffer;
  if (!buf || buf.spans.length === 0) return;
  if (!buf.firstBufferedAt) return;
  if (!Number.isFinite(SESSION_ID_BUFFER_MAX_MS) || SESSION_ID_BUFFER_MAX_MS <= 0) return;

  const ageMs = Date.now() - buf.firstBufferedAt;
  if (ageMs >= SESSION_ID_BUFFER_MAX_MS) {
    flushSpanBuffer({ force: true });
  }
}

function bufferSpanRecord(spanRecord) {
  const buf = state.exportBuffer;
  if (!buf) return;

  if (buf.spans.length === 0) {
    buf.firstBufferedAt = Date.now();
  }
  buf.spans.push(spanRecord);

  if (Number.isFinite(SESSION_ID_BUFFER_MAX_SPANS) && SESSION_ID_BUFFER_MAX_SPANS > 0) {
    if (buf.spans.length >= SESSION_ID_BUFFER_MAX_SPANS) {
      flushSpanBuffer({ force: true });
    }
  }
}

/**
 * Send OTLP span record to Alloy (session.id buffering + canonicalization)
 * @param {object} spanRecord - Full OTLP resourceSpans structure
 */
function sendToAlloy(spanRecord) {
  try {
    // Best-effort upgrade from fallback session.id → Claude UUID (flush buffered spans on success).
    maybeHydrateClaudeSessionId();
    if (state.session.sessionIdSource === 'hook') {
      flushSpanBuffer();
    } else {
      maybeExpireSpanBuffer();
    }

    if (SESSION_ID_POLICY === 'buffer' && state.session.sessionIdSource === 'fallback') {
      bufferSpanRecord(spanRecord);
      return;
    }

    applySessionIdToSpanRecord(spanRecord);
    postToAlloy(spanRecord);
  } catch (e) {
    // Silent failure to avoid disrupting Claude Code
  }
}

/**
 * Create OTLP span structure with enhanced resource attributes
 * @param {object} spanData - Span data object
 * @returns {object} Full OTLP resourceSpans structure
 */
function createOTLPSpan(spanData) {
  const span = {
    traceId: spanData.traceId,
    spanId: spanData.spanId,
    name: spanData.name,
    kind: spanData.kind || 'SPAN_KIND_INTERNAL',
    startTimeUnixNano: msToNanos(spanData.startTime),
    endTimeUnixNano: msToNanos(spanData.endTime || Date.now()),
    attributes: spanData.attributes || [],
    status: spanData.status || { code: 'STATUS_CODE_OK' }
  };

  if (spanData.parentSpanId) {
    span.parentSpanId = spanData.parentSpanId;
  }

  if (spanData.links && spanData.links.length > 0) {
    span.links = spanData.links;
  }

  // Build resource attributes
  const resourceAttrs = [
    { key: 'service.name', value: { stringValue: SERVICE_NAME } },
    { key: 'service.version', value: { stringValue: CLAUDE_CODE_VERSION } },
    { key: 'claude.interceptor.version', value: { stringValue: INTERCEPTOR_VERSION } },
    { key: 'host.name', value: { stringValue: os.hostname() } },
    { key: 'os.type', value: { stringValue: os.platform() } },
    { key: 'process.pid', value: { intValue: process.pid.toString() } },
    { key: 'working_directory', value: { stringValue: WORKING_DIRECTORY } }
  ];

  // Add parent trace context as resource attribute for debugging (subagents)
  if (state.session.parentContext) {
    resourceAttrs.push({
      key: 'parent.trace_id',
      value: { stringValue: state.session.parentContext.traceId }
    });
    resourceAttrs.push({
      key: 'parent.span_id',
      value: { stringValue: state.session.parentContext.spanId }
    });
    if (state.session.parentContextSource) {
      resourceAttrs.push({
        key: 'parent.context_source',
        value: { stringValue: state.session.parentContextSource }
      });
    }
  }

  return {
    resourceSpans: [{
      resource: {
        attributes: resourceAttrs
      },
      scopeSpans: [{
        scope: { name: 'claude-interceptor', version: INTERCEPTOR_VERSION },
        spans: [span]
      }]
    }]
  };
}

// =============================================================================
// Session Span Management
// =============================================================================

/**
 * Mark the session as active (at least one Anthropic API call observed).
 */
function markSessionActive() {
  state.session.hasAnySpans = true;
}

/**
 * Export session root span with aggregated metrics (called on shutdown).
 */
function finalizeSessionSpan() {
  if (!state.session.hasAnySpans) return;
  if (state.session.finalized) return;
  state.session.finalized = true;

  // End any active turn first
  if (state.currentTurn) {
    // If Stop hook already fired, prefer that timestamp.
    pollTurnHookFiles();
    if (state.currentTurn) endCurrentTurn(Date.now(), 'session_finalize');
  }

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'CHAIN' } },
    { key: 'gen_ai.system', value: { stringValue: 'anthropic' } },
    { key: 'gen_ai.provider.name', value: { stringValue: 'anthropic' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } },
    { key: 'claude.session_id_source', value: { stringValue: state.session.sessionIdSource } },
    { key: 'session.turn_count', value: { intValue: state.session.turnCount.toString() } },
    { key: 'session.api_call_count', value: { intValue: state.session.apiCallCount.toString() } },
    { key: 'gen_ai.usage.input_tokens', value: { intValue: state.session.tokens.input.toString() } },
    { key: 'gen_ai.usage.output_tokens', value: { intValue: state.session.tokens.output.toString() } },
    { key: 'gen_ai.usage.cost_usd', value: { doubleValue: state.session.tokens.costUsd } }
  ];

  // Feature 132: Add Langfuse-specific attributes for session/trace grouping
  if (LANGFUSE_ENABLED) {
    attributes.push({ key: 'langfuse.session.id', value: { stringValue: state.session.sessionId } });
    if (LANGFUSE_USER_ID) {
      attributes.push({ key: 'langfuse.user.id', value: { stringValue: LANGFUSE_USER_ID } });
    }
    attributes.push({ key: 'langfuse.trace.name', value: { stringValue: 'Claude Code Session' } });
    if (LANGFUSE_TAGS && Array.isArray(LANGFUSE_TAGS)) {
      attributes.push({ key: 'langfuse.tags', value: { stringValue: JSON.stringify(LANGFUSE_TAGS) } });
    }
    // Add usage details for Langfuse cost tracking
    const usageDetails = buildLangfuseUsageDetails(state.session.tokens);
    attributes.push({ key: 'langfuse.observation.usage_details', value: { stringValue: JSON.stringify(usageDetails) } });
    if (state.session.tokens.costUsd > 0) {
      const costDetails = buildLangfuseCostDetails(state.session.tokens.costUsd, state.session.tokens);
      attributes.push({ key: 'langfuse.observation.cost_details', value: { stringValue: JSON.stringify(costDetails) } });
    }
  }

  if (state.session.parentSessionId) {
    attributes.push({ key: 'claude.parent_session_id', value: { stringValue: state.session.parentSessionId } });
  }

  if (state.session.parentContext) {
    attributes.push({ key: 'subagent.type', value: { stringValue: 'Task' } });
  }

  const links = [];
  if (state.session.parentContext) {
    links.push({
      traceId: state.session.parentContext.traceId,
      spanId: state.session.parentContext.spanId,
      attributes: [
        { key: 'link.type', value: { stringValue: 'parent_task' } }
      ]
    });
  }

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: state.session.spanId,
    name: 'Claude Code Session',
    kind: 'SPAN_KIND_INTERNAL',
    startTime: state.session.startTime,
    endTime: Date.now(),
    attributes: attributes,
    links: links.length > 0 ? links : undefined
  });

  sendToAlloy(spanRecord);
}

// =============================================================================
// Turn Management
// =============================================================================

/**
 * Check if this request starts a new user turn
 * New turn: last message is a user prompt (NOT a tool_result payload)
 * @param {object} requestBody - API request body
 * @returns {boolean}
 */
function isNewTurn(requestBody) {
  const messages = requestBody.messages || [];
  if (messages.length === 0) return true;

  const lastMessage = messages[messages.length - 1];
  if (!lastMessage || lastMessage.role !== 'user') return false;

  // Anthropic "tool_result" messages are also role=user; they should NOT start a new turn.
  const content = lastMessage.content;
  if (Array.isArray(content) && content.some(b => b && b.type === 'tool_result')) {
    return false;
  }

  return true;
}

/**
 * Extract user prompt text from request body
 * @param {object} requestBody - API request body
 * @returns {string} User prompt text
 */
function extractUserPrompt(requestBody) {
  const messages = requestBody.messages || [];
  if (messages.length === 0) return '';

  const lastMessage = messages[messages.length - 1];
  if (lastMessage.role !== 'user') return '';

  const content = lastMessage.content;
  if (typeof content === 'string') return content;

  // Handle array of content blocks
  if (Array.isArray(content)) {
    const textBlocks = content
      .filter(b => b.type === 'text')
      .map(b => b.text);
    return textBlocks.join(' ');
  }

  return '';
}

function promptPreviewScore(preview) {
  const text = (preview || '').trim();
  if (!text) return 0;
  if (text === 'foo') return 1;
  if (text === 'quota') return 1;
  if (text.startsWith('<system-reminder>')) return 1;
  if (text.includes('system-reminder')) return 1;
  return Math.min(100, text.length);
}

function maybeUpdateActiveTurnPromptPreview(requestBody) {
  if (!state.currentTurn) return;
  const promptText = extractUserPrompt(requestBody || {});
  const nextPreview = getPreview(promptText, 60);
  if (!nextPreview) return;

  const currentScore = promptPreviewScore(state.currentTurn.promptPreview || '');
  const nextScore = promptPreviewScore(nextPreview);
  if (nextScore > currentScore) {
    state.currentTurn.promptPreview = nextPreview;
  }
}

function cancelScheduledTurnEnd() {
  if (!state.turnEndTimer) return;
  try { clearTimeout(state.turnEndTimer); } catch {}
  state.turnEndTimer = null;
}

function scheduleTurnEnd(endReason = 'idle_timeout') {
  cancelScheduledTurnEnd();
  if (!state.currentTurn) return;

  if (!Number.isFinite(TURN_IDLE_END_MS) || TURN_IDLE_END_MS <= 0) {
    endCurrentTurn(Date.now(), endReason);
    return;
  }

  const t = setTimeout(() => {
    state.turnEndTimer = null;
    if (!state.currentTurn) return;
    endCurrentTurn(Date.now(), endReason);
  }, TURN_IDLE_END_MS);
  t.unref();
  state.turnEndTimer = t;
}

/**
 * Start a new user turn with prompt context
 * @param {object} requestBody - API request body for prompt extraction
 */
function startNewTurn(requestBody) {
  cancelScheduledTurnEnd();

  // End previous turn if exists
  if (state.currentTurn) {
    endCurrentTurn(Date.now(), 'new_turn');
  }

  state.session.turnCount++;

  const promptText = extractUserPrompt(requestBody || {});
  const promptPreview = getPreview(promptText, 60);

  state.currentTurn = {
    spanId: generateId(8),
    turnNumber: state.session.turnCount,
    startTime: Date.now(),
    endTime: null,
    endReason: null,
    startSource: 'heuristic',
    tokens: createTokenCounts(),
    llmCallCount: 0,
    toolCallCount: 0,
    errorCount: 0,
    activeTools: new Set(),
    promptPreview: promptPreview  // Store for span name
  };
}

/**
 * End current turn and export span
 */
function endCurrentTurn(endTime = Date.now(), endReason = 'unknown') {
  if (!state.currentTurn) return;

  cancelScheduledTurnEnd();

  const turn = state.currentTurn;
  turn.endTime = endTime;
  turn.endReason = endReason;

  // Clean up orphaned tools (mark as error)
  for (const [toolCallId, pendingTool] of state.pendingTools) {
    if (turn.activeTools.has(toolCallId)) {
      completeToolSpan(toolCallId, {
        is_error: true,
        error_message: 'Tool execution incomplete - turn ended'
      });
    }
  }

  // Clean up orphaned permissions (mark as denied - user didn't approve before turn ended)
  for (const [toolUseId] of state.pendingPermissions) {
    completePermissionSpan(toolUseId, 'denied');
  }

  // Aggregate tokens and cost to session
  state.session.tokens.input += turn.tokens.input;
  state.session.tokens.output += turn.tokens.output;
  state.session.tokens.cacheRead += turn.tokens.cacheRead;
  state.session.tokens.cacheWrite += turn.tokens.cacheWrite;
  state.session.tokens.costUsd += turn.tokens.costUsd;

  // Build semantic span name with prompt preview
  let spanName = `Turn #${turn.turnNumber}`;
  if (turn.promptPreview) {
    spanName = `Turn #${turn.turnNumber}: ${turn.promptPreview}`;
  }

  // Export turn span
  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'AGENT' } },
    { key: 'gen_ai.operation.name', value: { stringValue: 'chat' } },
    { key: 'gen_ai.provider.name', value: { stringValue: 'anthropic' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } },
    { key: 'turn.number', value: { intValue: turn.turnNumber.toString() } },
    { key: 'turn.start.source', value: { stringValue: turn.startSource || 'unknown' } },
    { key: 'turn.end.reason', value: { stringValue: turn.endReason || 'unknown' } },
    { key: 'turn.llm_call_count', value: { intValue: turn.llmCallCount.toString() } },
    { key: 'turn.tool_call_count', value: { intValue: turn.toolCallCount.toString() } },
    { key: 'turn.error_count', value: { intValue: turn.errorCount.toString() } },
    { key: 'gen_ai.usage.input_tokens', value: { intValue: turn.tokens.input.toString() } },
    { key: 'gen_ai.usage.output_tokens', value: { intValue: turn.tokens.output.toString() } },
    { key: 'gen_ai.usage.cost_usd', value: { doubleValue: turn.tokens.costUsd } },
    { key: 'turn.duration_ms', value: { intValue: (turn.endTime - turn.startTime).toString() } }
  ];

  // Add prompt preview as attribute too
  if (turn.promptPreview) {
    attributes.push({ key: 'input.value', value: { stringValue: turn.promptPreview } });
  }

  // Feature 132: Add Langfuse-specific attributes for turn tracking
  if (LANGFUSE_ENABLED) {
    attributes.push({ key: 'langfuse.session.id', value: { stringValue: state.session.sessionId } });
    attributes.push({ key: 'langfuse.trace.name', value: { stringValue: 'Claude Code Session' } });
    if (LANGFUSE_USER_ID) {
      attributes.push({ key: 'langfuse.user.id', value: { stringValue: LANGFUSE_USER_ID } });
    }
    // Add usage details for the turn
    const usageDetails = buildLangfuseUsageDetails(turn.tokens);
    attributes.push({ key: 'langfuse.observation.usage_details', value: { stringValue: JSON.stringify(usageDetails) } });
    if (turn.tokens.costUsd > 0) {
      const costDetails = buildLangfuseCostDetails(turn.tokens.costUsd, turn.tokens);
      attributes.push({ key: 'langfuse.observation.cost_details', value: { stringValue: JSON.stringify(costDetails) } });
    }
  }

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: turn.spanId,
    parentSpanId: state.session.spanId,
    name: spanName,
    kind: 'SPAN_KIND_INTERNAL',
    startTime: turn.startTime,
    endTime: turn.endTime,
    attributes: attributes
  });

  sendToAlloy(spanRecord);

  state.currentTurn = null;
}

// =============================================================================
// LLM Span Management
// =============================================================================

/**
 * Create and export LLM span for an API call
 * @param {object} requestBody - API request body
 * @param {object} responseBody - API response body
 * @param {number} startTime - Request start time (ms)
 * @param {number} endTime - Response end time (ms)
 */
function exportLLMSpan(requestBody, responseBody, startTime, endTime, consumedToolSpans = [], llmSpanId = null, responseInfo = null) {
  if (state.currentTurn) {
    state.currentTurn.llmCallCount++;
  }

  const model = requestBody.model || 'unknown';
  const tokens = extractTokenUsage(responseBody);
  const stopReason = responseBody.stop_reason || 'unknown';
  const durationMs = endTime - startTime;

  // Calculate cost for this LLM call
  const costUsd = calculateCostUsd(model, tokens);

  // Aggregate tokens and cost to turn (preferred) or session (background calls)
  if (state.currentTurn) {
    state.currentTurn.tokens.input += tokens.input;
    state.currentTurn.tokens.output += tokens.output;
    state.currentTurn.tokens.cacheRead += tokens.cacheRead;
    state.currentTurn.tokens.cacheWrite += tokens.cacheWrite;
    state.currentTurn.tokens.costUsd += costUsd;
  } else {
    state.session.tokens.input += tokens.input;
    state.session.tokens.output += tokens.output;
    state.session.tokens.cacheRead += tokens.cacheRead;
    state.session.tokens.cacheWrite += tokens.cacheWrite;
    state.session.tokens.costUsd += costUsd;
  }

  // Extract input value for attribute
  let inputValue = '';
  if (requestBody.messages && Array.isArray(requestBody.messages)) {
    // Prefer the most recent *prompt* (skip tool_result "user" messages, which can be huge).
    for (let i = requestBody.messages.length - 1; i >= 0; i--) {
      const msg = requestBody.messages[i];
      if (!msg || msg.role !== 'user') continue;

      const content = msg.content;
      if (Array.isArray(content) && content.some(b => b && b.type === 'tool_result')) {
        continue;
      }

      if (typeof content === 'string') {
        inputValue = content;
        break;
      }

      if (Array.isArray(content)) {
        const textBlocks = content
          .filter(b => b && b.type === 'text' && typeof b.text === 'string')
          .map(b => b.text);
        inputValue = textBlocks.join(' ');
        break;
      }
    }
  }

  // Extract output value
  let outputValue = '';
  if (responseBody.content && Array.isArray(responseBody.content)) {
    outputValue = responseBody.content.map(c => c.text || '').join('');
  }

  // Create friendly model name for span
  const modelShort = model.includes('sonnet') ? 'Sonnet' :
                     model.includes('opus') ? 'Opus' :
                     model.includes('haiku') ? 'Haiku' : model;

		  const attributes = [
		    { key: 'openinference.span.kind', value: { stringValue: 'LLM' } },
		    { key: 'gen_ai.system', value: { stringValue: 'anthropic' } },
		    { key: 'gen_ai.provider.name', value: { stringValue: 'anthropic' } },
		    { key: 'gen_ai.operation.name', value: { stringValue: 'chat' } },
		    { key: 'gen_ai.request.model', value: { stringValue: model } },
		    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
		    { key: 'session.id', value: { stringValue: state.session.sessionId } },
		    { key: 'gen_ai.usage.input_tokens', value: { intValue: tokens.input.toString() } },
		    { key: 'gen_ai.usage.output_tokens', value: { intValue: tokens.output.toString() } },
		    { key: 'gen_ai.usage.cost_usd', value: { doubleValue: costUsd } },
		    { key: 'gen_ai.response.finish_reasons', value: { stringValue: stopReason } },
		    { key: 'llm.latency.total_ms', value: { intValue: durationMs.toString() } },
		    { key: 'llm.request.sequence', value: { intValue: (responseInfo && typeof responseInfo.sequence === 'number' ? responseInfo.sequence : state.session.apiCallCount).toString() } },
		    { key: 'input.value', value: { stringValue: inputValue.substring(0, 5000) } },
		    { key: 'output.value', value: { stringValue: outputValue.substring(0, 5000) } }
		  ];

      // High-cardinality correlation helpers (traces-only; safe with spanmetrics exclude_dimensions)
      if (responseInfo && responseInfo.requestId) {
        attributes.push({ key: 'anthropic.request_id', value: { stringValue: responseInfo.requestId } });
      }
      if (responseInfo && typeof responseInfo.statusCode === 'number') {
        attributes.push({ key: 'http.response.status_code', value: { intValue: responseInfo.statusCode.toString() } });
      }
      if (responseBody && typeof responseBody.id === 'string' && responseBody.id) {
        attributes.push({ key: 'anthropic.message_id', value: { stringValue: responseBody.id } });
      }

      // Error classification based on HTTP status and response body
      const statusCode = responseInfo && typeof responseInfo.statusCode === 'number' ? responseInfo.statusCode : undefined;
      const errorType = classifyErrorType(statusCode, responseBody);
      if (errorType) {
        attributes.push({ key: 'error.type', value: { stringValue: errorType } });
        // Increment turn error count
        if (state.currentTurn) {
          state.currentTurn.errorCount++;
        }
      }

	  // Attach turn number for easier grouping (0 = background/non-turn)
	  attributes.push({
	    key: 'turn.number',
	    value: { intValue: (state.currentTurn ? state.currentTurn.turnNumber : 0).toString() }
	  });

  // Cache tokens
  if (tokens.cacheRead > 0) {
    attributes.push({ key: 'llm.token_count.prompt_details.cache_read', value: { intValue: tokens.cacheRead.toString() } });
  }
  if (tokens.cacheWrite > 0) {
    attributes.push({ key: 'llm.token_count.prompt_details.cache_write', value: { intValue: tokens.cacheWrite.toString() } });
  }

  // Feature 132: Add Langfuse-specific attributes for LLM generation tracking
  if (LANGFUSE_ENABLED) {
    attributes.push({ key: 'langfuse.session.id', value: { stringValue: state.session.sessionId } });
    attributes.push({ key: 'langfuse.trace.name', value: { stringValue: 'Claude Code Session' } });
    if (LANGFUSE_USER_ID) {
      attributes.push({ key: 'langfuse.user.id', value: { stringValue: LANGFUSE_USER_ID } });
    }
    // Add usage details for Langfuse
    const usageDetails = buildLangfuseUsageDetails(tokens);
    attributes.push({ key: 'langfuse.observation.usage_details', value: { stringValue: JSON.stringify(usageDetails) } });
    if (costUsd > 0) {
      const costDetails = buildLangfuseCostDetails(costUsd, tokens);
      attributes.push({ key: 'langfuse.observation.cost_details', value: { stringValue: JSON.stringify(costDetails) } });
    }
  }

  // Optional request parameters
  if (requestBody.temperature !== undefined) {
    attributes.push({ key: 'llm.request.temperature', value: { doubleValue: requestBody.temperature } });
  }
  if (requestBody.max_tokens !== undefined) {
    attributes.push({ key: 'llm.request.max_tokens', value: { intValue: requestBody.max_tokens.toString() } });
  }

	  const hasUsage = responseBody && typeof responseBody === 'object'
      && responseBody.usage && typeof responseBody.usage === 'object'
      && (typeof responseBody.usage.input_tokens === 'number' || typeof responseBody.usage.output_tokens === 'number');

	  // Create semantic span name with model and stop reason
	  const spanName = stopReason === 'tool_use'
	    ? `LLM Call: ${modelShort} → tools`
	    : hasUsage
        ? `LLM Call: ${modelShort} (${tokens.input}→${tokens.output} tokens)`
        : `LLM Call: ${modelShort} (?→? tokens)`;

  const links = [];
  for (const toolSpan of consumedToolSpans) {
    if (!toolSpan || !toolSpan.spanId) continue;
    links.push({
      traceId: state.session.traceId,
      spanId: toolSpan.spanId,
      attributes: [
        { key: 'link.type', value: { stringValue: 'consumes_tool_result' } },
        ...(toolSpan.toolCallId ? [{ key: 'gen_ai.tool.call.id', value: { stringValue: toolSpan.toolCallId } }] : [])
      ]
    });
  }

  const spanId = llmSpanId || generateId(8);
	  const spanRecord = createOTLPSpan({
	    traceId: state.session.traceId,
	    spanId: spanId,
	    parentSpanId: state.currentTurn ? state.currentTurn.spanId : state.session.spanId,
	    name: spanName,
	    kind: 'SPAN_KIND_CLIENT',
	    startTime: startTime,
	    endTime: endTime,
    attributes: attributes,
    links: links.length > 0 ? links : undefined
  });

  sendToAlloy(spanRecord);
  return spanId;
}

// =============================================================================
// Tool Span Management
// =============================================================================

/**
 * Check if tool is the Task tool (subagent)
 * @param {string} toolName - Tool name
 * @returns {boolean}
 */
function isTaskTool(toolName) {
  return toolName === 'Task';
}

/**
 * Extract tool_use blocks from API response content
 * @param {object} responseBody - API response body
 * @returns {Array<{id: string, name: string, input: object}>}
 */
function extractToolUseBlocks(responseBody) {
  if (!responseBody.content || !Array.isArray(responseBody.content)) {
    return [];
  }
  return responseBody.content
    .filter(block => block.type === 'tool_use')
    .map(block => ({
      id: block.id,
      name: block.name,
      input: block.input || {}
    }));
}

/**
 * Extract tool_result blocks from API request messages
 * @param {object} requestBody - API request body
 * @returns {Array<{tool_use_id: string, content: any, is_error: boolean}>}
 */
function extractToolResults(requestBody) {
  const results = [];
  const messages = requestBody.messages || [];

  for (const msg of messages) {
    if (msg.role === 'user' && Array.isArray(msg.content)) {
      for (const block of msg.content) {
        if (block.type === 'tool_result') {
          results.push({
            tool_use_id: block.tool_use_id,
            content: block.content,
            is_error: block.is_error || false
          });
        }
      }
    }
  }

  return results;
}

/**
 * Create tool span for a tool_use block (tool execution started)
 * @param {object} toolUse - Tool use block from response
 * @param {string|null} producedByLlmSpanId - LLM span that produced this tool_use
 */
function createToolSpan(toolUse, producedByLlmSpanId = null) {
  if (!state.currentTurn) return;

  const spanId = generateId(8);
  const startTime = Date.now();

  state.currentTurn.toolCallCount++;
  state.currentTurn.activeTools.add(toolUse.id);

  // Store pending tool for completion later
  state.pendingTools.set(toolUse.id, {
    toolCallId: toolUse.id,
    toolName: toolUse.name,
    spanId: spanId,
    startTime: startTime,
    input: toolUse.input,
    producedByLlmSpanId: producedByLlmSpanId || null
  });

  // If this is a Task tool, set env var for subagent correlation
  if (isTaskTool(toolUse.name)) {
    // Write a per-Task context file so the subagent can link to the correct Task span.
    writeTaskContextFile(state.session.traceId, spanId, toolUse, state.session.sessionId);
    // Best-effort fallback mechanisms (env var + per-process runtime context)
    setTraceParentEnv(state.session.traceId, spanId);
  }
}

/**
 * Complete a tool span when tool_result is received
 * @param {string} toolCallId - Tool call ID to complete
 * @param {object} result - Tool result data
 */
function completeToolSpan(toolCallId, result) {
  const pendingTool = state.pendingTools.get(toolCallId);
  if (!pendingTool) return null;

  // Check for pending permission and complete it as approved (tool_result arrived)
  if (state.pendingPermissions.has(toolCallId)) {
    completePermissionSpan(toolCallId, 'approved');
  }

  state.pendingTools.delete(toolCallId);
  if (state.currentTurn) {
    state.currentTurn.activeTools.delete(toolCallId);
  }

  const endTime = Date.now();
  const isError = result.is_error || false;

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'TOOL' } },
    { key: 'gen_ai.provider.name', value: { stringValue: 'anthropic' } },
    { key: 'gen_ai.tool.name', value: { stringValue: pendingTool.toolName } },
    { key: 'gen_ai.tool.call.id', value: { stringValue: pendingTool.toolCallId } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'tool.status', value: { stringValue: isError ? 'error' : 'success' } }
  ];

  // Add session.id for correlation
  attributes.push({ key: 'session.id', value: { stringValue: state.session.sessionId } });

  // Add duration
  const durationMs = endTime - pendingTool.startTime;
  attributes.push({ key: 'tool.duration_ms', value: { intValue: durationMs.toString() } });

  // Add tool-specific attributes
  if (pendingTool.input) {
    // Add file path for Read/Write tools
    if (pendingTool.input.file_path) {
      attributes.push({ key: 'tool.file_path', value: { stringValue: pendingTool.input.file_path } });
    }
    // Add command for Bash tool (truncated for security)
    if (pendingTool.input.command) {
      const cmd = pendingTool.input.command.substring(0, 200);
      attributes.push({ key: 'tool.command', value: { stringValue: cmd } });
    }
    // Add pattern for Grep/Glob
    if (pendingTool.input.pattern) {
      attributes.push({ key: 'tool.pattern', value: { stringValue: pendingTool.input.pattern } });
    }
    // Add URL for WebFetch
    if (pendingTool.input.url) {
      attributes.push({ key: 'tool.url', value: { stringValue: pendingTool.input.url } });
    }
    // Add query for WebSearch
    if (pendingTool.input.query) {
      attributes.push({ key: 'tool.query', value: { stringValue: pendingTool.input.query } });
    }
    // Add description for Task tool
    if (pendingTool.input.description) {
      attributes.push({ key: 'tool.description', value: { stringValue: getPreview(pendingTool.input.description, 100) } });
    }
  }

  if (isError && result.error_message) {
    attributes.push({ key: 'tool.error_message', value: { stringValue: result.error_message } });
  }

  // Phase 3: Integrate PostToolUse hook metadata for enhanced tool visibility
  const postToolMeta = consumePostToolMeta(toolCallId);
  if (postToolMeta) {
    // Add exit code (primarily for Bash tools)
    if (postToolMeta.exitCode !== undefined && postToolMeta.exitCode !== null) {
      attributes.push({ key: 'tool.execution.exit_code', value: { intValue: postToolMeta.exitCode.toString() } });
    }
    // Add output summary
    if (postToolMeta.outputSummary) {
      attributes.push({ key: 'tool.output.summary', value: { stringValue: postToolMeta.outputSummary } });
    }
    // Add output line count
    if (postToolMeta.outputLines !== undefined && postToolMeta.outputLines !== null) {
      attributes.push({ key: 'tool.output.lines', value: { intValue: postToolMeta.outputLines.toString() } });
    }
    // Add error type from PostToolUse hook (may differ from LLM-inferred error)
    if (postToolMeta.errorType) {
      attributes.push({ key: 'tool.error.type', value: { stringValue: postToolMeta.errorType } });
    }
  }

  // Feature 132: Add Langfuse-specific attributes for tool tracking
  if (LANGFUSE_ENABLED) {
    attributes.push({ key: 'langfuse.session.id', value: { stringValue: state.session.sessionId } });
    if (LANGFUSE_USER_ID) {
      attributes.push({ key: 'langfuse.user.id', value: { stringValue: LANGFUSE_USER_ID } });
    }
    // Set observation type for Langfuse
    attributes.push({ key: 'langfuse.observation.type', value: { stringValue: 'span' } });
    // Add error level for failed tools
    if (isError) {
      attributes.push({ key: 'langfuse.observation.level', value: { stringValue: 'ERROR' } });
    }
    // Add tool input as input.value for Langfuse (truncated)
    if (pendingTool.input) {
      try {
        const inputStr = JSON.stringify(pendingTool.input).substring(0, 5000);
        attributes.push({ key: 'input.value', value: { stringValue: inputStr } });
        attributes.push({ key: 'langfuse.observation.input', value: { stringValue: inputStr } });
      } catch {}
    }
  }

  // Get parent span ID - use turn span if available, otherwise session
  const parentSpanId = state.currentTurn ? state.currentTurn.spanId : state.session.spanId;

  // Create semantic span name
  const spanName = getToolSpanName(pendingTool.toolName, pendingTool.input);

  const links = [];
  if (pendingTool.producedByLlmSpanId) {
    links.push({
      traceId: state.session.traceId,
      spanId: pendingTool.producedByLlmSpanId,
      attributes: [
        { key: 'link.type', value: { stringValue: 'produced_by_llm' } }
      ]
    });
  }

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: pendingTool.spanId,
    parentSpanId: parentSpanId,
    name: spanName,
    kind: 'SPAN_KIND_INTERNAL',
    startTime: pendingTool.startTime,
    endTime: endTime,
    attributes: attributes,
    links: links.length > 0 ? links : undefined,
    status: isError ? { code: 'STATUS_CODE_ERROR', message: result.error_message } : { code: 'STATUS_CODE_OK' }
  });

  sendToAlloy(spanRecord);
  return { spanId: pendingTool.spanId, toolCallId: pendingTool.toolCallId, toolName: pendingTool.toolName };
}

/**
 * Check if response indicates turn is complete (no pending tool calls)
 * @param {object} responseBody - API response body
 * @returns {boolean}
 */
function isTurnComplete(responseBody) {
  const stopReason = responseBody && typeof responseBody === 'object' ? responseBody.stop_reason : null;
  if (typeof stopReason === 'string' && stopReason.length > 0) {
    return stopReason !== 'tool_use';
  }

  // Fallback: if we can't see stop_reason, infer from presence of tool_use blocks.
  const toolUseBlocks = extractToolUseBlocks(responseBody);
  return toolUseBlocks.length === 0;
}

// =============================================================================
// Fetch Interceptor
// =============================================================================

const originalFetch = globalThis.fetch;

globalThis.fetch = async (input, init) => {
  const url = typeof input === 'string' ? input : input.url;

  // Only intercept Anthropic messages API calls (not count_tokens, eval, etc.)
  // The URL pattern we want: api.anthropic.com/v1/messages (with optional ?beta=true)
  // We DON'T want: /v1/messages/count_tokens, /api/eval/*, etc.
  const isMessagesEndpoint = url.includes('api.anthropic.com/v1/messages') &&
                             !url.includes('/count_tokens') &&
                             !url.includes('/v1/messages/');  // Exclude sub-paths like /batches

  // Debug: log all fetch calls to understand what's being intercepted
  if (process.env.OTEL_INTERCEPTOR_DEBUG === '1') {
    const hasBody = !!(init && init.body);
    console.error(`[OTEL-Diag] fetch called: url=${url.substring(0, 80)}, hasBody=${hasBody}, isMessagesEndpoint=${isMessagesEndpoint}`);
  }

  // Only intercept Anthropic messages API calls
  if (!isMessagesEndpoint || !init || !init.body) {
    return originalFetch(input, init);
  }

  const startTime = Date.now();
  // Pre-generate the LLM span ID so we can optionally propagate trace context via HTTP headers.
  const llmSpanId = generateId(8);
  let requestBody = {};
  try {
    requestBody = JSON.parse(init.body);
  } catch (e) {
    requestBody = { raw: init.body };
  }

  // Hook-driven turn boundary updates (does not rely on request/response heuristics).
  pollTurnHookFiles();
  // Any API activity cancels a pending heuristic "idle end" for the current turn.
  cancelScheduledTurnEnd();

  // Hydrate Claude Code's native session.id (UUID) for correlation with metrics/logs.
  maybeHydrateClaudeSessionId();
  // Resolve parent Task span context for subagent linking (best-effort).
  maybeResolveParentContext(requestBody);
  // Mark session active (so we export the session root span on shutdown).
  markSessionActive();

  // Count every Anthropic API call (including background calls/errors).
  state.session.apiCallCount++;
  const apiCallIndex = state.session.apiCallCount;

  // Process tool results from this request (complete pending tools)
  const toolResults = extractToolResults(requestBody);
  // Poll for PostToolUse hook files before completing tools (ensures exit_code/output metadata is cached)
  if (toolResults.length > 0) {
    pollPostToolFiles();
  }
  const consumedToolSpans = [];
  for (const result of toolResults) {
    const completed = completeToolSpan(result.tool_use_id, result);
    if (completed) consumedToolSpans.push(completed);
  }

  // Check if this starts a new turn
  if (!shouldUseHookTurnBoundaries() && !state.currentTurn && isNewTurn(requestBody)) {
    startNewTurn(requestBody);
  }
  // In heuristic mode, later calls may reveal the real user prompt; prefer the best prompt preview.
  if (!shouldUseHookTurnBoundaries() && state.currentTurn && isNewTurn(requestBody)) {
    maybeUpdateActiveTurnPromptPreview(requestBody);
  }

  try {
    // Optional: propagate W3C trace context to enable eBPF agents (e.g. Beyla) to
    // correlate low-level HTTP spans with our logical LLM spans.
    maybeInjectTraceparentHeader(init, llmSpanId);

    const response = await originalFetch(input, init);
    const endTime = Date.now();

    // Create a clone to parse the body for span metadata.
    // We MUST await this to ensure OTEL_TRACE_PARENT is set BEFORE returning
    // the response to Claude Code, preventing race conditions with subagent spawning.
	    const clonedResponse = response.clone();
	    let responseBody = {};
	    try {
	      const contentType = (clonedResponse.headers && typeof clonedResponse.headers.get === 'function')
	        ? (clonedResponse.headers.get('content-type') || '')
	        : '';
	      const text = await clonedResponse.text();

	      responseBody = parseAnthropicResponseBody(text, contentType);

	      // Compact diagnostic logging (enabled via OTEL_INTERCEPTOR_DEBUG=1)
	      if (process.env.OTEL_INTERCEPTOR_DEBUG === '1') {
	        const hasUsage = !!(responseBody.usage && (responseBody.usage.input_tokens || responseBody.usage.output_tokens));
	        const hasContent = !!(responseBody.content && responseBody.content.length > 0);
	        const isStream = contentType.includes('event-stream');
	        console.error(`[OTEL-Diag] Response: len=${text.length}, stream=${isStream}, usage=${hasUsage}, content=${hasContent}, model=${responseBody.model || 'none'}`);
	      }
	    } catch (e) {
	      if (process.env.OTEL_INTERCEPTOR_DEBUG === '1') {
	        console.error(`[OTEL-Diag] Failed to read response: ${e.message}`);
	      }
	      responseBody = { error: 'Failed to read response body' };
	    }

    // Prompt hooks can race with the first API call; re-poll before exporting spans.
    pollTurnHookFiles();

	    // Export LLM span (link to tool results consumed by this request)
	    const requestId = (response.headers && typeof response.headers.get === 'function')
	      ? (response.headers.get('request-id') || response.headers.get('x-request-id') || null)
	      : null;
		    exportLLMSpan(requestBody, responseBody, startTime, endTime, consumedToolSpans, llmSpanId, {
		      requestId: requestId,
		      statusCode: typeof response.status === 'number' ? response.status : null,
		      sequence: apiCallIndex
		    });

    // Create tool spans for any tool_use blocks in response
    const toolUseBlocks = extractToolUseBlocks(responseBody);
    for (const toolUse of toolUseBlocks) {
      createToolSpan(toolUse, llmSpanId);
    }

    // Check if turn is complete
    if (!shouldUseHookTurnBoundaries() && isTurnComplete(responseBody) && state.currentTurn) {
      if (!state.currentTurn.activeTools || state.currentTurn.activeTools.size === 0) {
        scheduleTurnEnd('idle_after_stop_reason');
      }
    }

    return response;
  } catch (err) {
    if (state.currentTurn) state.currentTurn.llmCallCount++;

    const errorSpan = createOTLPSpan({
      traceId: state.session.traceId,
      spanId: llmSpanId,
      parentSpanId: state.currentTurn ? state.currentTurn.spanId : state.session.spanId,
      name: `LLM Call: ERROR - ${(err.message || 'Unknown error').substring(0, 50)}`,
      kind: 'SPAN_KIND_CLIENT',
      startTime: startTime,
      endTime: Date.now(),
      attributes: [
        { key: 'openinference.span.kind', value: { stringValue: 'LLM' } },
        { key: 'gen_ai.system', value: { stringValue: 'anthropic' } },
        { key: 'gen_ai.provider.name', value: { stringValue: 'anthropic' } },
        { key: 'gen_ai.operation.name', value: { stringValue: 'chat' } },
        { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
        { key: 'session.id', value: { stringValue: state.session.sessionId } },
        { key: 'llm.request.sequence', value: { intValue: apiCallIndex.toString() } },
        { key: 'turn.number', value: { intValue: (state.currentTurn ? state.currentTurn.turnNumber : 0).toString() } },
        { key: 'error.message', value: { stringValue: err.message || 'Unknown error' } },
        { key: 'error.type', value: { stringValue: err.name || 'Error' } }
      ],
      status: { code: 'STATUS_CODE_ERROR', message: err.message }
    });
    sendToAlloy(errorSpan);

    throw err;
  }
};

// =============================================================================
// Process Exit Handling
// =============================================================================

process.on('beforeExit', () => {
  if (state.session.hasAnySpans && state.session.apiCallCount > 0) {
    finalizeSessionSpan();
  }
  flushSpanBuffer({ force: true });
  cleanupTraceContext();
});

// Handle SIGINT/SIGTERM for graceful shutdown
process.on('SIGINT', () => {
  if (state.session.hasAnySpans) {
    finalizeSessionSpan();
  }
  flushSpanBuffer({ force: true });
  cleanupTraceContext();
  process.exit(0);
});

process.on('SIGTERM', () => {
  if (state.session.hasAnySpans) {
    finalizeSessionSpan();
  }
  flushSpanBuffer({ force: true });
  cleanupTraceContext();
  process.exit(0);
});

// =============================================================================
// Startup Logging
// =============================================================================

// Enable hook-driven Turn boundaries (unref'd poller; won't keep process alive).
startTurnHookPoller();
pollTurnHookFiles();

console.error(`[OTEL-Interceptor v${INTERCEPTOR_VERSION}] Active`);
console.error(`[OTEL-Interceptor]   Endpoint: ${TRACE_ENDPOINT}`);
console.error(`[OTEL-Interceptor]   Session: ${state.session.sessionId} (${state.session.sessionIdSource})`);
console.error(`[OTEL-Interceptor]   TraceID: ${SESSION_TRACE_ID}`);
console.error(`[OTEL-Interceptor]   WorkDir: ${WORKING_DIRECTORY}`);
console.error(`[OTEL-Interceptor]   ProcFS: ${PROC_AVAILABLE ? 'available' : 'unavailable'}`);
