/**
 * minimal-otel-interceptor.js (v3.4.0)
 *
 * Multi-span trace hierarchy for Claude Code sessions.
 * Creates proper hierarchical trace structure: Session -> Turns -> LLM/Tool spans
 *
 * Features:
 * - Session span (CHAIN) - root span for entire Claude Code process
 * - Turn spans (AGENT) - one per user prompt with semantic descriptions
 * - LLM spans (CLIENT) - individual Claude API calls with model/token details
 * - Tool spans (TOOL) - file operations, bash commands, with timing and status
 * - Subagent correlation via span links and OTEL_TRACE_PARENT propagation
 * - Token aggregation at turn and session level for cost attribution
 * - Correlation with Claude Code's native telemetry via session.id
 *
 * Following OpenTelemetry GenAI semantic conventions (2025 edition).
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
const INTERCEPTOR_VERSION = '3.4.0';
const WORKING_DIRECTORY = process.cwd();
const RUNTIME_DIR = process.env.XDG_RUNTIME_DIR || os.tmpdir();
const CWD_TRACE_FILE = path.join(WORKING_DIRECTORY, '.claude-trace-context.json');
const PROC_AVAILABLE = fs.existsSync('/proc');

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

// =============================================================================
// Token Counts Structure
// =============================================================================

/**
 * Create empty token counts object
 * @returns {{input: number, output: number, cacheRead: number, cacheWrite: number}}
 */
function createTokenCounts() {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
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
 * Hybrid trace context lookup - tries multiple methods for maximum reliability
 *
 * Methods (in order of preference):
 * 1. Environment variable (fastest, if inherited)
 * 2. Working directory file (same-project subagents)
 * 3. Process tree walking (handles intermediate shells)
 * 4. Most recent context file (fallback for complex hierarchies)
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

  // 2. Try working directory file (same-project subagents)
  try {
    if (fs.existsSync(CWD_TRACE_FILE)) {
      const content = fs.readFileSync(CWD_TRACE_FILE, 'utf8');
      const ctx = JSON.parse(content);
      // Verify it's from a different, running process
      if (ctx.pid !== process.pid && isProcessRunning(ctx.pid)) {
        return { traceId: ctx.traceId, spanId: ctx.spanId };
      }
    }
  } catch (e) {
    // Continue to next method
  }

  // 3. Walk up process tree (handles intermediate shells like bash, systemd)
  const treeResult = walkProcessTree();
  if (treeResult) return treeResult;

  // 4. Find most recent context file from running process
  const recentResult = findMostRecentContext();
  if (recentResult) return recentResult;

  return null;
}

/**
 * Set trace context for subagent processes
 * Writes to multiple locations for maximum reliability:
 * - Environment variable (for inherited environments)
 * - Runtime directory file (for process tree lookup)
 * - Working directory file (for same-project subagents)
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
    fs.writeFileSync(stateFile, JSON.stringify(context));
  } catch (e) {
    // Silent failure
  }

  // 3. Write to working directory (for same-project subagents)
  try {
    fs.writeFileSync(CWD_TRACE_FILE, JSON.stringify(context));
  } catch (e) {
    // Silent failure - may not have write access
  }
}

/**
 * Clean up trace context state files on process exit
 */
function cleanupTraceContext() {
  // Clean runtime directory file
  try {
    const stateFile = path.join(RUNTIME_DIR, `claude-otel-${process.pid}.json`);
    if (fs.existsSync(stateFile)) {
      fs.unlinkSync(stateFile);
    }
  } catch (e) {
    // Silent failure
  }

  // Clean working directory file (only if we created it)
  try {
    if (fs.existsSync(CWD_TRACE_FILE)) {
      const content = fs.readFileSync(CWD_TRACE_FILE, 'utf8');
      const ctx = JSON.parse(content);
      // Only delete if it's ours
      if (ctx.pid === process.pid) {
        fs.unlinkSync(CWD_TRACE_FILE);
      }
    }
  } catch (e) {
    // Silent failure
  }
}

// =============================================================================
// Session State (Singleton)
// =============================================================================

const SESSION_START_TIME = Date.now();
const SESSION_ID = `claude-${process.pid}-${SESSION_START_TIME}`;
const SESSION_TRACE_ID = generateId(16);
const SESSION_ROOT_SPAN_ID = generateId(8);
const PARENT_CONTEXT = parseTraceParentEnv();

const state = {
  session: {
    traceId: SESSION_TRACE_ID,
    spanId: SESSION_ROOT_SPAN_ID,
    sessionId: SESSION_ID,
    startTime: SESSION_START_TIME,
    tokens: createTokenCounts(),
    turnCount: 0,
    apiCallCount: 0,
    exported: false,
    parentContext: PARENT_CONTEXT  // For subagent span links
  },
  currentTurn: null,
  pendingTools: new Map()  // toolCallId -> PendingToolSpan
};

// =============================================================================
// OTLP Export Functions
// =============================================================================

/**
 * Send OTLP span record to Alloy
 * @param {object} spanRecord - Full OTLP resourceSpans structure
 */
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
    { key: 'service.version', value: { stringValue: INTERCEPTOR_VERSION } },
    { key: 'host.name', value: { stringValue: os.hostname() } },
    { key: 'os.type', value: { stringValue: os.platform() } },
    { key: 'process.pid', value: { intValue: process.pid.toString() } },
    { key: 'working_directory', value: { stringValue: WORKING_DIRECTORY } }
  ];

  // Add parent trace context as resource attribute for subagent discovery
  if (PARENT_CONTEXT) {
    resourceAttrs.push({
      key: 'parent.trace_id',
      value: { stringValue: PARENT_CONTEXT.traceId }
    });
    resourceAttrs.push({
      key: 'parent.span_id',
      value: { stringValue: PARENT_CONTEXT.spanId }
    });
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
 * Export session root span (called on first API call)
 */
function exportSessionSpan() {
  if (state.session.exported) return;
  state.session.exported = true;

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'CHAIN' } },
    { key: 'gen_ai.system', value: { stringValue: 'anthropic' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } }
  ];

  // Add subagent.type if this is a spawned subagent
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

/**
 * Finalize and re-export session span with aggregated metrics
 */
function finalizeSessionSpan() {
  if (!state.session.exported) return;

  // End any active turn first
  if (state.currentTurn) {
    endCurrentTurn();
  }

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'CHAIN' } },
    { key: 'gen_ai.system', value: { stringValue: 'anthropic' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.turn_count', value: { intValue: state.session.turnCount.toString() } },
    { key: 'session.api_call_count', value: { intValue: state.session.apiCallCount.toString() } },
    { key: 'gen_ai.usage.input_tokens', value: { intValue: state.session.tokens.input.toString() } },
    { key: 'gen_ai.usage.output_tokens', value: { intValue: state.session.tokens.output.toString() } }
  ];

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
 * New turn: last message in messages array has role: user
 * @param {object} requestBody - API request body
 * @returns {boolean}
 */
function isNewTurn(requestBody) {
  const messages = requestBody.messages || [];
  if (messages.length === 0) return true;

  const lastMessage = messages[messages.length - 1];
  return lastMessage.role === 'user';
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

/**
 * Start a new user turn with prompt context
 * @param {object} requestBody - API request body for prompt extraction
 */
function startNewTurn(requestBody) {
  // End previous turn if exists
  if (state.currentTurn) {
    endCurrentTurn();
  }

  state.session.turnCount++;

  const promptText = extractUserPrompt(requestBody || {});
  const promptPreview = getPreview(promptText, 60);

  state.currentTurn = {
    spanId: generateId(8),
    turnNumber: state.session.turnCount,
    startTime: Date.now(),
    endTime: null,
    tokens: createTokenCounts(),
    llmCallCount: 0,
    toolCallCount: 0,
    activeTools: new Set(),
    promptPreview: promptPreview  // Store for span name
  };
}

/**
 * End current turn and export span
 */
function endCurrentTurn() {
  if (!state.currentTurn) return;

  const turn = state.currentTurn;
  turn.endTime = Date.now();

  // Clean up orphaned tools (mark as error)
  for (const [toolCallId, pendingTool] of state.pendingTools) {
    if (turn.activeTools.has(toolCallId)) {
      completeToolSpan(toolCallId, {
        is_error: true,
        error_message: 'Tool execution incomplete - turn ended'
      });
    }
  }

  // Aggregate tokens to session
  state.session.tokens.input += turn.tokens.input;
  state.session.tokens.output += turn.tokens.output;
  state.session.tokens.cacheRead += turn.tokens.cacheRead;
  state.session.tokens.cacheWrite += turn.tokens.cacheWrite;

  // Build semantic span name with prompt preview
  let spanName = `Turn #${turn.turnNumber}`;
  if (turn.promptPreview) {
    spanName = `Turn #${turn.turnNumber}: ${turn.promptPreview}`;
  }

  // Export turn span
  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'AGENT' } },
    { key: 'gen_ai.operation.name', value: { stringValue: 'chat' } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } },
    { key: 'turn.number', value: { intValue: turn.turnNumber.toString() } },
    { key: 'turn.llm_call_count', value: { intValue: turn.llmCallCount.toString() } },
    { key: 'turn.tool_call_count', value: { intValue: turn.toolCallCount.toString() } },
    { key: 'gen_ai.usage.input_tokens', value: { intValue: turn.tokens.input.toString() } },
    { key: 'gen_ai.usage.output_tokens', value: { intValue: turn.tokens.output.toString() } },
    { key: 'turn.duration_ms', value: { intValue: (turn.endTime - turn.startTime).toString() } }
  ];

  // Add prompt preview as attribute too
  if (turn.promptPreview) {
    attributes.push({ key: 'input.value', value: { stringValue: turn.promptPreview } });
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
function exportLLMSpan(requestBody, responseBody, startTime, endTime) {
  if (!state.currentTurn) return;

  state.currentTurn.llmCallCount++;
  state.session.apiCallCount++;

  const model = requestBody.model || 'unknown';
  const tokens = extractTokenUsage(responseBody);
  const stopReason = responseBody.stop_reason || 'unknown';
  const durationMs = endTime - startTime;

  // Aggregate tokens to turn
  state.currentTurn.tokens.input += tokens.input;
  state.currentTurn.tokens.output += tokens.output;
  state.currentTurn.tokens.cacheRead += tokens.cacheRead;
  state.currentTurn.tokens.cacheWrite += tokens.cacheWrite;

  // Extract input value for attribute
  let inputValue = '';
  if (requestBody.messages && Array.isArray(requestBody.messages)) {
    const userMsgs = requestBody.messages.filter(m => m.role === 'user');
    if (userMsgs.length > 0) {
      const last = userMsgs[userMsgs.length - 1];
      inputValue = typeof last.content === 'string' ? last.content : JSON.stringify(last.content);
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
    { key: 'gen_ai.request.model', value: { stringValue: model } },
    { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
    { key: 'session.id', value: { stringValue: state.session.sessionId } },
    { key: 'gen_ai.usage.input_tokens', value: { intValue: tokens.input.toString() } },
    { key: 'gen_ai.usage.output_tokens', value: { intValue: tokens.output.toString() } },
    { key: 'gen_ai.response.finish_reasons', value: { stringValue: stopReason } },
    { key: 'llm.latency.total_ms', value: { intValue: durationMs.toString() } },
    { key: 'llm.request.sequence', value: { intValue: state.session.apiCallCount.toString() } },
    { key: 'input.value', value: { stringValue: inputValue.substring(0, 5000) } },
    { key: 'output.value', value: { stringValue: outputValue.substring(0, 5000) } }
  ];

  // Cache tokens
  if (tokens.cacheRead > 0) {
    attributes.push({ key: 'llm.token_count.prompt_details.cache_read', value: { intValue: tokens.cacheRead.toString() } });
  }
  if (tokens.cacheWrite > 0) {
    attributes.push({ key: 'llm.token_count.prompt_details.cache_write', value: { intValue: tokens.cacheWrite.toString() } });
  }

  // Optional request parameters
  if (requestBody.temperature !== undefined) {
    attributes.push({ key: 'llm.request.temperature', value: { doubleValue: requestBody.temperature } });
  }
  if (requestBody.max_tokens !== undefined) {
    attributes.push({ key: 'llm.request.max_tokens', value: { intValue: requestBody.max_tokens.toString() } });
  }

  // Create semantic span name with model and stop reason
  const spanName = stopReason === 'tool_use'
    ? `LLM Call: ${modelShort} → tools`
    : `LLM Call: ${modelShort} (${tokens.input}→${tokens.output} tokens)`;

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: generateId(8),
    parentSpanId: state.currentTurn.spanId,
    name: spanName,
    kind: 'SPAN_KIND_CLIENT',
    startTime: startTime,
    endTime: endTime,
    attributes: attributes
  });

  sendToAlloy(spanRecord);
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
 */
function createToolSpan(toolUse) {
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
    input: toolUse.input
  });

  // If this is a Task tool, set env var for subagent correlation
  if (isTaskTool(toolUse.name)) {
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
  if (!pendingTool) return;

  state.pendingTools.delete(toolCallId);
  if (state.currentTurn) {
    state.currentTurn.activeTools.delete(toolCallId);
  }

  const endTime = Date.now();
  const isError = result.is_error || false;

  const attributes = [
    { key: 'openinference.span.kind', value: { stringValue: 'TOOL' } },
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

  // Get parent span ID - use turn span if available, otherwise session
  const parentSpanId = state.currentTurn ? state.currentTurn.spanId : state.session.spanId;

  // Create semantic span name
  const spanName = getToolSpanName(pendingTool.toolName, pendingTool.input);

  const spanRecord = createOTLPSpan({
    traceId: state.session.traceId,
    spanId: pendingTool.spanId,
    parentSpanId: parentSpanId,
    name: spanName,
    kind: 'SPAN_KIND_INTERNAL',
    startTime: pendingTool.startTime,
    endTime: endTime,
    attributes: attributes,
    status: isError ? { code: 'STATUS_CODE_ERROR', message: result.error_message } : { code: 'STATUS_CODE_OK' }
  });

  sendToAlloy(spanRecord);
}

/**
 * Check if response indicates turn is complete (no pending tool calls)
 * @param {object} responseBody - API response body
 * @returns {boolean}
 */
function isTurnComplete(responseBody) {
  const toolUseBlocks = extractToolUseBlocks(responseBody);
  return toolUseBlocks.length === 0;
}

// =============================================================================
// Fetch Interceptor
// =============================================================================

const originalFetch = globalThis.fetch;

globalThis.fetch = async (input, init) => {
  const url = typeof input === 'string' ? input : input.url;

  // Only intercept Anthropic API calls
  if (!url.includes('api.anthropic.com') || !init || !init.body) {
    return originalFetch(input, init);
  }

  const startTime = Date.now();
  let requestBody = {};
  try {
    requestBody = JSON.parse(init.body);
  } catch (e) {
    requestBody = { raw: init.body };
  }

  // Export session span on first API call
  exportSessionSpan();

  // Process tool results from this request (complete pending tools)
  const toolResults = extractToolResults(requestBody);
  for (const result of toolResults) {
    completeToolSpan(result.tool_use_id, result);
  }

  // Check if this starts a new turn
  if (isNewTurn(requestBody)) {
    startNewTurn(requestBody);
  }

  try {
    const response = await originalFetch(input, init);
    const endTime = Date.now();

    // Create a clone to parse the body for span metadata.
    // We MUST await this to ensure OTEL_TRACE_PARENT is set BEFORE returning
    // the response to Claude Code, preventing race conditions with subagent spawning.
    const clonedResponse = response.clone();
    let responseBody = {};
    try {
      const text = await clonedResponse.text();
      try {
        responseBody = JSON.parse(text);
      } catch (e) {
        responseBody = { raw: text.substring(0, 5000) };
      }
    } catch (e) {
      responseBody = { error: 'Failed to read response body' };
    }

    // Export LLM span
    exportLLMSpan(requestBody, responseBody, startTime, endTime);

    // Create tool spans for any tool_use blocks in response
    const toolUseBlocks = extractToolUseBlocks(responseBody);
    // DEBUG: Log tool detection
    if (toolUseBlocks.length > 0) {
      console.error(`[OTEL-Debug] Found ${toolUseBlocks.length} tool_use blocks: ${toolUseBlocks.map(t => t.name).join(', ')}`);
      console.error(`[OTEL-Debug] currentTurn: ${state.currentTurn ? 'SET' : 'NULL'}`);
    }
    for (const toolUse of toolUseBlocks) {
      createToolSpan(toolUse);
      // DEBUG: Log Task tool handling
      if (toolUse.name === 'Task') {
        console.error(`[OTEL-Debug] Task tool detected, trace files should be created`);
        console.error(`[OTEL-Debug] Runtime: ${path.join(RUNTIME_DIR, 'claude-otel-' + process.pid + '.json')}`);
        console.error(`[OTEL-Debug] CWD: ${CWD_TRACE_FILE}`);
      }
    }

    // Check if turn is complete
    if (isTurnComplete(responseBody) && state.currentTurn) {
      endCurrentTurn();
    }

    return response;
  } catch (err) {
    // Export error span if we have an active turn
    if (state.currentTurn) {
      state.currentTurn.llmCallCount++;
      state.session.apiCallCount++;

      const errorSpan = createOTLPSpan({
        traceId: state.session.traceId,
        spanId: generateId(8),
        parentSpanId: state.currentTurn.spanId,
        name: `LLM Call: ERROR - ${(err.message || 'Unknown error').substring(0, 50)}`,
        kind: 'SPAN_KIND_CLIENT',
        startTime: startTime,
        endTime: Date.now(),
        attributes: [
          { key: 'openinference.span.kind', value: { stringValue: 'LLM' } },
          { key: 'gen_ai.system', value: { stringValue: 'anthropic' } },
          { key: 'gen_ai.conversation.id', value: { stringValue: state.session.sessionId } },
          { key: 'session.id', value: { stringValue: state.session.sessionId } },
          { key: 'error.message', value: { stringValue: err.message || 'Unknown error' } },
          { key: 'error.type', value: { stringValue: err.name || 'Error' } }
        ],
        status: { code: 'STATUS_CODE_ERROR', message: err.message }
      });
      sendToAlloy(errorSpan);
    }
    throw err;
  }
};

// =============================================================================
// Process Exit Handling
// =============================================================================

process.on('beforeExit', () => {
  if (state.session.exported && state.session.apiCallCount > 0) {
    finalizeSessionSpan();
  }
  cleanupTraceContext();
});

// Handle SIGINT/SIGTERM for graceful shutdown
process.on('SIGINT', () => {
  if (state.session.exported) {
    finalizeSessionSpan();
  }
  cleanupTraceContext();
  process.exit(0);
});

process.on('SIGTERM', () => {
  if (state.session.exported) {
    finalizeSessionSpan();
  }
  cleanupTraceContext();
  process.exit(0);
});

// =============================================================================
// Startup Logging
// =============================================================================

console.error(`[OTEL-Interceptor v${INTERCEPTOR_VERSION}] Active`);
console.error(`[OTEL-Interceptor]   Endpoint: ${TRACE_ENDPOINT}`);
console.error(`[OTEL-Interceptor]   Session: ${SESSION_ID}`);
console.error(`[OTEL-Interceptor]   TraceID: ${SESSION_TRACE_ID}`);
console.error(`[OTEL-Interceptor]   WorkDir: ${WORKING_DIRECTORY}`);
console.error(`[OTEL-Interceptor]   ProcFS: ${PROC_AVAILABLE ? 'available' : 'unavailable'}`);
if (PARENT_CONTEXT) {
  console.error(`[OTEL-Interceptor]   Subagent: yes (linked)`);
  console.error(`[OTEL-Interceptor]   Parent TraceID: ${PARENT_CONTEXT.traceId}`);
  console.error(`[OTEL-Interceptor]   Parent SpanID: ${PARENT_CONTEXT.spanId}`);
}
