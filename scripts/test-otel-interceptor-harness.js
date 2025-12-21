#!/usr/bin/env node
/**
 * Local harness for validating `scripts/minimal-otel-interceptor.js` behavior
 * without hitting the real Anthropic API or requiring Alloy to be running.
 *
 * Runs:
 * 1) A tiny OTLP/HTTP "collector" that accepts JSON OTLP spans at /v1/traces
 * 2) A fake Anthropic endpoint that returns configurable responses
 *
 * Test Suites:
 * - Basic: Turn boundaries, tool loops, session.id hydration
 * - Streaming: SSE event stream parsing
 * - Concurrent Tasks: Multiple Task tool_use blocks in one response
 * - Error Scenarios: 429 rate limit, 500 server error, error.type classification
 * - Permission Flow: PERMISSION spans for user approval wait time
 * - Cost Metrics: gen_ai.usage.cost_usd calculation
 * - PostToolUse: Tool spans with exit_code, output_summary from PostToolUse hook (Phase 3)
 * - SubagentStop: SUBAGENT_COMPLETION spans from SubagentStop hook (Phase 3)
 * - Notification: NOTIFICATION spans for permission_prompt, auth_success (Phase 3)
 * - Compaction: COMPACTION spans for manual/auto context compaction (Phase 3)
 *
 * Usage:
 *   `node scripts/test-otel-interceptor-harness.js`
 *   `node scripts/test-otel-interceptor-harness.js --test=streaming`
 */

'use strict';

const http = require('node:http');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const { once } = require('node:events');

// =============================================================================
// Helpers
// =============================================================================

function getSpansFromOtlpJson(payload) {
  const out = [];
  for (const rs of payload?.resourceSpans || []) {
    for (const ss of rs?.scopeSpans || []) {
      for (const span of ss?.spans || []) out.push(span);
    }
  }
  return out;
}

function getAttr(span, key) {
  for (const a of span?.attributes || []) {
    if (a?.key !== key) continue;
    const v = a?.value || {};
    if (typeof v.stringValue === 'string') return v.stringValue;
    if (typeof v.intValue === 'string') return Number(v.intValue);
    if (typeof v.doubleValue === 'number') return v.doubleValue;
    if (typeof v.boolValue === 'boolean') return v.boolValue;
    return undefined;
  }
  return undefined;
}

function getLinkType(link) {
  for (const a of link?.attributes || []) {
    if (a?.key === 'link.type') return a?.value?.stringValue;
  }
  return undefined;
}

function fail(msg) {
  console.error(`  FAIL: ${msg}`);
  return false;
}

function pass(msg) {
  console.log(`  PASS: ${msg}`);
  return true;
}

// =============================================================================
// Test Infrastructure
// =============================================================================

class TestHarness {
  constructor() {
    this.runtimeDir = null;
    this.otlpServer = null;
    this.otlpPort = 0;
    this.anthropicServer = null;
    this.anthropicPort = 0;
    this.received = [];
    this.requestHandler = null;
    this.sessionId = '00000000-0000-4000-8000-000000000000';
  }

  async setup() {
    this.runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'otel-interceptor-harness-'));
    this.received = [];

    // OTLP receiver
    this.otlpServer = http.createServer((req, res) => {
      if (req.method !== 'POST' || req.url !== '/v1/traces') {
        res.statusCode = 404;
        res.end('not found');
        return;
      }
      let body = '';
      req.setEncoding('utf8');
      req.on('data', chunk => { body += chunk; });
      req.on('end', () => {
        try { this.received.push(JSON.parse(body)); } catch {}
        res.statusCode = 200;
        res.end('ok');
      });
    });
    this.otlpServer.listen(0, '127.0.0.1');
    await once(this.otlpServer, 'listening');
    this.otlpPort = this.otlpServer.address().port;

    // Anthropic API mock
    this.anthropicServer = http.createServer((req, res) => {
      if (req.method !== 'POST' || req.url !== '/api.anthropic.com/v1/messages') {
        res.statusCode = 404;
        res.end('not found');
        return;
      }
      let body = '';
      req.setEncoding('utf8');
      req.on('data', chunk => { body += chunk; });
      req.on('end', () => {
        if (this.requestHandler) {
          this.requestHandler(req, res, body);
        } else {
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ type: 'message', content: [] }));
        }
      });
    });
    this.anthropicServer.listen(0, '127.0.0.1');
    await once(this.anthropicServer, 'listening');
    this.anthropicPort = this.anthropicServer.address().port;

    // Configure interceptor environment
    process.env.XDG_RUNTIME_DIR = this.runtimeDir;
    process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = `http://127.0.0.1:${this.otlpPort}/v1/traces`;
    process.env.OTEL_SERVICE_NAME = 'claude-code-harness';

    // Write session metadata
    fs.writeFileSync(
      path.join(this.runtimeDir, `claude-session-${process.pid}.json`),
      JSON.stringify({ version: 1, sessionId: this.sessionId })
    );
  }

  async teardown() {
    await new Promise(r => this.anthropicServer.close(r));
    await new Promise(r => this.otlpServer.close(r));
    try { fs.rmSync(this.runtimeDir, { recursive: true, force: true }); } catch {}
  }

  getUrl() {
    return `http://127.0.0.1:${this.anthropicPort}/api.anthropic.com/v1/messages`;
  }

  getSpans() {
    return this.received.flatMap(getSpansFromOtlpJson);
  }

  writePromptHook(prompt) {
    fs.writeFileSync(
      path.join(this.runtimeDir, `claude-user-prompt-${process.pid}.json`),
      JSON.stringify({
        version: 1,
        sessionId: this.sessionId,
        prompt,
        pid: process.pid,
        timestampMs: Date.now()
      })
    );
  }

  writeStopHook() {
    fs.writeFileSync(
      path.join(this.runtimeDir, `claude-stop-${process.pid}.json`),
      JSON.stringify({
        version: 1,
        sessionId: this.sessionId,
        pid: process.pid,
        timestampMs: Date.now()
      })
    );
  }

  writePermissionHook(toolUseId, toolName, toolDescription = null) {
    const filename = `claude-permission-${process.pid}-${toolUseId}.json`;
    fs.writeFileSync(
      path.join(this.runtimeDir, filename),
      JSON.stringify({
        version: 1,
        sessionId: this.sessionId,
        toolName,
        toolUseId,
        toolDescription,
        pid: process.pid,
        startTimestampMs: Date.now()
      })
    );
  }

  writePostToolHook(toolUseId, toolName, opts = {}) {
    const filename = `claude-posttool-${process.pid}-${toolUseId}.json`;
    fs.writeFileSync(
      path.join(this.runtimeDir, filename),
      JSON.stringify({
        version: 1,
        sessionId: this.sessionId,
        toolName,
        toolUseId,
        exitCode: opts.exitCode ?? null,
        outputSummary: opts.outputSummary ?? null,
        outputLines: opts.outputLines ?? null,
        isError: opts.isError ?? false,
        errorType: opts.errorType ?? null,
        pid: process.pid,
        completedAtMs: Date.now()
      })
    );
  }

  writeSubagentStopHook(toolUseId, subagentSessionId = null) {
    const filename = `claude-subagent-stop-${process.pid}-${toolUseId}.json`;
    fs.writeFileSync(
      path.join(this.runtimeDir, filename),
      JSON.stringify({
        version: 1,
        sessionId: this.sessionId,
        toolUseId,
        subagentSessionId,
        pid: process.pid,
        completedAtMs: Date.now()
      })
    );
  }

  writeNotificationHook(notificationType, message = null) {
    const timestamp = Date.now();
    const filename = `claude-notification-${process.pid}-${timestamp}.json`;
    fs.writeFileSync(
      path.join(this.runtimeDir, filename),
      JSON.stringify({
        version: 1,
        sessionId: this.sessionId,
        notificationType,
        message,
        pid: process.pid,
        timestampMs: timestamp
      })
    );
  }

  writePreCompactHook(compactType, trigger = null, messagesBefore = null) {
    const timestamp = Date.now();
    const filename = `claude-precompact-${process.pid}-${timestamp}.json`;
    fs.writeFileSync(
      path.join(this.runtimeDir, filename),
      JSON.stringify({
        version: 1,
        sessionId: this.sessionId,
        compactType,
        trigger,
        messagesBefore,
        pid: process.pid,
        timestampMs: timestamp
      })
    );
  }

  async wait(ms = 500) {
    await new Promise(r => setTimeout(r, ms));
  }
}

// =============================================================================
// Test: Basic Turn Boundaries
// =============================================================================

async function testBasicTurnBoundaries(harness) {
  console.log('\n[Test] Basic Turn Boundaries');

  let reqCount = 0;
  harness.requestHandler = (req, res, body) => {
    reqCount++;
    const response = reqCount === 1
      ? {
          id: 'msg_1', type: 'message', role: 'assistant',
          model: 'claude-3-5-sonnet-20241022', stop_reason: 'tool_use',
          usage: { input_tokens: 100, output_tokens: 50 },
          content: [{ type: 'tool_use', id: 'toolu_1', name: 'Read', input: { file_path: '/tmp/test.txt' } }]
        }
      : {
          id: 'msg_2', type: 'message', role: 'assistant',
          model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
          usage: { input_tokens: 50, output_tokens: 100 },
          content: [{ type: 'text', text: 'Done.' }]
        };
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(response));
  };

  harness.writePromptHook('Read the file.');

  const url = harness.getUrl();
  const headers = { 'content-type': 'application/json' };

  // First request: user prompt
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Read the file.' }] })
  });

  // Second request: tool_result (NOT a new turn)
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-20241022',
      messages: [{ role: 'user', content: [{ type: 'tool_result', tool_use_id: 'toolu_1', content: 'ok' }] }]
    })
  });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const turns = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'AGENT');
  const llms = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'LLM');
  const tools = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'TOOL');

  let passed = true;
  if (turns.length !== 1) passed = fail(`expected 1 Turn span, got ${turns.length}`);
  else passed = pass('Single turn span for tool loop') && passed;

  if (llms.length !== 2) passed = fail(`expected 2 LLM spans, got ${llms.length}`);
  else passed = pass('Two LLM spans for tool_use + end_turn') && passed;

  if (tools.length !== 1) passed = fail(`expected 1 Tool span, got ${tools.length}`);
  else passed = pass('One Tool span for Read') && passed;

  // Verify session.id
  for (const s of [...turns, ...llms, ...tools]) {
    const sid = getAttr(s, 'session.id');
    if (sid !== harness.sessionId) {
      passed = fail(`span ${s.name} has session.id=${sid}`);
      break;
    }
  }
  if (passed) passed = pass('All spans have correct session.id') && passed;

  return passed;
}

// =============================================================================
// Test: Streaming Response
// =============================================================================

async function testStreamingResponse(harness) {
  console.log('\n[Test] Streaming Response (SSE)');

  harness.requestHandler = (req, res, body) => {
    res.statusCode = 200;
    res.setHeader('content-type', 'text/event-stream');
    res.setHeader('cache-control', 'no-cache');

    // Simulate SSE events
    const events = [
      { type: 'message_start', message: { id: 'msg_stream', type: 'message', role: 'assistant', model: 'claude-3-5-sonnet-20241022', usage: { input_tokens: 50, output_tokens: 0 } } },
      { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
      { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'Hello ' } },
      { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'world!' } },
      { type: 'content_block_stop', index: 0 },
      { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 10 } },
      { type: 'message_stop' }
    ];

    for (const event of events) {
      res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
    }
    res.end();
  };

  harness.writePromptHook('Say hello');

  await fetch(harness.getUrl(), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', stream: true, messages: [{ role: 'user', content: 'Say hello' }] })
  });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const llms = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'LLM');

  let passed = true;
  if (llms.length < 1) passed = fail(`expected at least 1 LLM span, got ${llms.length}`);
  else passed = pass('LLM span created for streaming response') && passed;

  // Check token aggregation from streaming
  const llm = llms[0];
  const inputTokens = getAttr(llm, 'gen_ai.usage.input_tokens');
  const outputTokens = getAttr(llm, 'gen_ai.usage.output_tokens');
  if (inputTokens === 50 && outputTokens === 10) {
    passed = pass('Token counts extracted from streaming events') && passed;
  } else {
    passed = fail(`expected tokens (50, 10), got (${inputTokens}, ${outputTokens})`);
  }

  return passed;
}

// =============================================================================
// Test: Concurrent Tasks
// =============================================================================

async function testConcurrentTasks(harness) {
  console.log('\n[Test] Concurrent Tasks (multiple tool_use blocks)');

  harness.requestHandler = (req, res, body) => {
    const response = {
      id: 'msg_tasks', type: 'message', role: 'assistant',
      model: 'claude-3-5-sonnet-20241022', stop_reason: 'tool_use',
      usage: { input_tokens: 200, output_tokens: 100 },
      content: [
        { type: 'tool_use', id: 'toolu_task1', name: 'Task', input: { description: 'Research topic A', prompt: 'Find info about A' } },
        { type: 'tool_use', id: 'toolu_task2', name: 'Task', input: { description: 'Research topic B', prompt: 'Find info about B' } },
        { type: 'tool_use', id: 'toolu_task3', name: 'Task', input: { description: 'Research topic C', prompt: 'Find info about C' } }
      ]
    };
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(response));
  };

  harness.writePromptHook('Research three topics');

  await fetch(harness.getUrl(), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Research three topics' }] })
  });

  await harness.wait(300);

  const spans = harness.getSpans();
  const llms = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'LLM');

  let passed = true;
  if (llms.length < 1) passed = fail(`expected at least 1 LLM span, got ${llms.length}`);
  else passed = pass('LLM span created with concurrent Tasks') && passed;

  // Check for Task context files (3 files should be written)
  const taskFiles = fs.readdirSync(harness.runtimeDir)
    .filter(f => f.startsWith('claude-task-context-'));

  if (taskFiles.length >= 3) {
    passed = pass(`${taskFiles.length} Task context files written`) && passed;
  } else {
    passed = fail(`expected 3+ Task context files, got ${taskFiles.length}`);
  }

  return passed;
}

// =============================================================================
// Test: Error Scenarios
// =============================================================================

async function testErrorScenarios(harness) {
  console.log('\n[Test] Error Scenarios (rate limit, server error)');

  let reqCount = 0;
  harness.requestHandler = (req, res, body) => {
    reqCount++;
    if (reqCount === 1) {
      // 429 rate limit
      res.statusCode = 429;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ type: 'error', error: { type: 'rate_limit_error', message: 'Too many requests' } }));
    } else if (reqCount === 2) {
      // 500 server error
      res.statusCode = 500;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ type: 'error', error: { type: 'server_error', message: 'Internal error' } }));
    } else {
      // Success
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({
        id: 'msg_success', type: 'message', role: 'assistant',
        model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
        usage: { input_tokens: 10, output_tokens: 5 },
        content: [{ type: 'text', text: 'OK' }]
      }));
    }
  };

  harness.writePromptHook('Test errors');
  const url = harness.getUrl();
  const headers = { 'content-type': 'application/json' };
  const body = JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Test' }] });

  // Make 3 requests: 429, 500, then success
  await fetch(url, { method: 'POST', headers, body });
  await fetch(url, { method: 'POST', headers, body });
  await fetch(url, { method: 'POST', headers, body });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const llms = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'LLM');

  let passed = true;
  if (llms.length < 3) passed = fail(`expected 3 LLM spans, got ${llms.length}`);
  else passed = pass('LLM spans created for error scenarios') && passed;

  // Check error.type attributes
  const errorTypes = llms.map(s => getAttr(s, 'error.type')).filter(Boolean);
  if (errorTypes.includes('rate_limit')) {
    passed = pass('rate_limit error type detected') && passed;
  } else {
    passed = fail('rate_limit error type not found');
  }

  if (errorTypes.includes('server')) {
    passed = pass('server error type detected') && passed;
  } else {
    passed = fail('server error type not found');
  }

  // Check turn.error_count
  const turns = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'AGENT');
  if (turns.length > 0) {
    const errorCount = getAttr(turns[0], 'turn.error_count');
    if (errorCount >= 2) {
      passed = pass(`turn.error_count=${errorCount}`) && passed;
    } else {
      passed = fail(`expected turn.error_count >= 2, got ${errorCount}`);
    }
  }

  return passed;
}

// =============================================================================
// Test: Permission Flow
// =============================================================================

async function testPermissionFlow(harness) {
  console.log('\n[Test] Permission Flow (PERMISSION spans)');

  let reqCount = 0;
  harness.requestHandler = (req, res, body) => {
    reqCount++;
    if (reqCount === 1) {
      // Request that triggers tool_use requiring permission
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({
        id: 'msg_perm', type: 'message', role: 'assistant',
        model: 'claude-3-5-sonnet-20241022', stop_reason: 'tool_use',
        usage: { input_tokens: 50, output_tokens: 20 },
        content: [{ type: 'tool_use', id: 'toolu_perm', name: 'Write', input: { file_path: '/tmp/important.txt', content: 'data' } }]
      }));
    } else {
      // Tool result after permission granted
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({
        id: 'msg_done', type: 'message', role: 'assistant',
        model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
        usage: { input_tokens: 30, output_tokens: 10 },
        content: [{ type: 'text', text: 'File written.' }]
      }));
    }
  };

  harness.writePromptHook('Write a file');

  const url = harness.getUrl();
  const headers = { 'content-type': 'application/json' };

  // First request triggers Write tool
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Write a file' }] })
  });

  // Simulate permission hook (user sees dialog)
  harness.writePermissionHook('toolu_perm', 'Write', '/tmp/important.txt');

  // Wait a bit to simulate user thinking
  await harness.wait(200);

  // Second request: tool_result (permission granted)
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-20241022',
      messages: [{ role: 'user', content: [{ type: 'tool_result', tool_use_id: 'toolu_perm', content: 'success' }] }]
    })
  });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const permissions = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'PERMISSION');

  let passed = true;
  if (permissions.length < 1) {
    passed = fail(`expected at least 1 PERMISSION span, got ${permissions.length}`);
  } else {
    passed = pass('PERMISSION span created') && passed;

    const perm = permissions[0];
    const result = getAttr(perm, 'permission.result');
    const tool = getAttr(perm, 'permission.tool');
    const waitMs = getAttr(perm, 'permission.wait_ms');

    if (result === 'approved') {
      passed = pass('permission.result=approved') && passed;
    } else {
      passed = fail(`expected permission.result=approved, got ${result}`);
    }

    if (tool === 'Write') {
      passed = pass('permission.tool=Write') && passed;
    } else {
      passed = fail(`expected permission.tool=Write, got ${tool}`);
    }

    if (typeof waitMs === 'number' && waitMs > 0) {
      passed = pass(`permission.wait_ms=${waitMs}`) && passed;
    } else {
      passed = fail(`expected permission.wait_ms > 0, got ${waitMs}`);
    }
  }

  return passed;
}

// =============================================================================
// Test: Cost Metrics
// =============================================================================

async function testCostMetrics(harness) {
  console.log('\n[Test] Cost Metrics (gen_ai.usage.cost_usd)');

  harness.requestHandler = (req, res, body) => {
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({
      id: 'msg_cost', type: 'message', role: 'assistant',
      model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
      usage: { input_tokens: 1000, output_tokens: 500 },
      content: [{ type: 'text', text: 'Response' }]
    }));
  };

  harness.writePromptHook('Calculate cost');

  await fetch(harness.getUrl(), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Calculate cost' }] })
  });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const llms = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'LLM');

  let passed = true;
  if (llms.length < 1) {
    passed = fail(`expected at least 1 LLM span, got ${llms.length}`);
  } else {
    const llm = llms[0];
    const costUsd = getAttr(llm, 'gen_ai.usage.cost_usd');

    // Expected cost: (1000/1M * 3.00) + (500/1M * 15.00) = 0.003 + 0.0075 = 0.0105
    if (typeof costUsd === 'number' && costUsd > 0) {
      passed = pass(`gen_ai.usage.cost_usd=${costUsd.toFixed(6)}`) && passed;

      // Verify approximate expected cost for claude-3-5-sonnet
      // Input: $3.00/1M, Output: $15.00/1M
      const expectedCost = (1000 / 1_000_000 * 3.00) + (500 / 1_000_000 * 15.00);
      if (Math.abs(costUsd - expectedCost) < 0.001) {
        passed = pass(`cost calculation correct (expected ~${expectedCost.toFixed(6)})`) && passed;
      } else {
        passed = fail(`cost mismatch: got ${costUsd}, expected ${expectedCost}`);
      }
    } else {
      passed = fail(`expected gen_ai.usage.cost_usd > 0, got ${costUsd}`);
    }
  }

  // Check turn/session aggregation
  const turns = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'AGENT');
  if (turns.length > 0) {
    const turnCost = getAttr(turns[0], 'gen_ai.usage.cost_usd');
    if (typeof turnCost === 'number' && turnCost > 0) {
      passed = pass(`turn span has gen_ai.usage.cost_usd=${turnCost.toFixed(6)}`) && passed;
    }
  }

  return passed;
}

// =============================================================================
// Test: PostToolUse Flow (Phase 3)
// =============================================================================

async function testPostToolUseFlow(harness) {
  console.log('\n[Test] PostToolUse Flow (exit_code, output_summary)');

  let reqCount = 0;
  harness.requestHandler = (req, res, body) => {
    reqCount++;
    if (reqCount === 1) {
      // Request that triggers Bash tool
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({
        id: 'msg_bash', type: 'message', role: 'assistant',
        model: 'claude-3-5-sonnet-20241022', stop_reason: 'tool_use',
        usage: { input_tokens: 50, output_tokens: 20 },
        content: [{ type: 'tool_use', id: 'toolu_bash', name: 'Bash', input: { command: 'ls -la' } }]
      }));
    } else {
      // Tool result
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({
        id: 'msg_done', type: 'message', role: 'assistant',
        model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
        usage: { input_tokens: 30, output_tokens: 10 },
        content: [{ type: 'text', text: 'Done listing files.' }]
      }));
    }
  };

  harness.writePromptHook('List files');

  const url = harness.getUrl();
  const headers = { 'content-type': 'application/json' };

  // First request triggers Bash tool
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'List files' }] })
  });

  // Simulate PostToolUse hook (writes metadata before tool_result)
  harness.writePostToolHook('toolu_bash', 'Bash', {
    exitCode: 0,
    outputSummary: 'total 12 files listed',
    outputLines: 15
  });

  await harness.wait(300);

  // Second request: tool_result
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-20241022',
      messages: [{ role: 'user', content: [{ type: 'tool_result', tool_use_id: 'toolu_bash', content: 'file1.txt\nfile2.txt' }] }]
    })
  });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const tools = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'TOOL');

  let passed = true;
  if (tools.length < 1) {
    passed = fail(`expected at least 1 TOOL span, got ${tools.length}`);
  } else {
    passed = pass('TOOL span created') && passed;

    const tool = tools[0];
    const exitCode = getAttr(tool, 'tool.execution.exit_code');
    const outputSummary = getAttr(tool, 'tool.output.summary');
    const outputLines = getAttr(tool, 'tool.output.lines');

    if (exitCode === 0) {
      passed = pass('tool.execution.exit_code=0') && passed;
    } else {
      passed = fail(`expected tool.execution.exit_code=0, got ${exitCode}`);
    }

    if (outputSummary === 'total 12 files listed') {
      passed = pass('tool.output.summary present') && passed;
    } else {
      passed = fail(`expected tool.output.summary, got ${outputSummary}`);
    }

    if (outputLines === 15) {
      passed = pass('tool.output.lines=15') && passed;
    } else {
      passed = fail(`expected tool.output.lines=15, got ${outputLines}`);
    }

    // Verify span links (Tool → LLM causality)
    const llms = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'LLM');
    const toolLinks = tool.links || [];
    if (toolLinks.length > 0) {
      const producedByLlmLink = toolLinks.find(l =>
        l.attributes?.some(a => a.key === 'link.type' && a.value?.stringValue === 'produced_by_llm')
      );
      if (producedByLlmLink) {
        // Verify the link points to an LLM span
        const linkedLlmSpan = llms.find(l => l.spanId === producedByLlmLink.spanId);
        if (linkedLlmSpan) {
          passed = pass('Tool span has produced_by_llm link to LLM span') && passed;
        } else {
          passed = fail(`Tool span link spanId ${producedByLlmLink.spanId} not found in LLM spans`);
        }
      } else {
        passed = fail('Tool span has links but no produced_by_llm link');
      }
    } else {
      passed = fail(`expected Tool span to have produced_by_llm link, got ${toolLinks.length} links`);
    }
  }

  return passed;
}

// =============================================================================
// Test: SubagentStop (Phase 3)
// =============================================================================

async function testSubagentStop(harness) {
  console.log('\n[Test] SubagentStop (subagent.session_id)');

  let reqCount = 0;
  harness.requestHandler = (req, res, body) => {
    reqCount++;
    if (reqCount === 1) {
      // Request that triggers Task tool
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({
        id: 'msg_task', type: 'message', role: 'assistant',
        model: 'claude-3-5-sonnet-20241022', stop_reason: 'tool_use',
        usage: { input_tokens: 100, output_tokens: 50 },
        content: [{ type: 'tool_use', id: 'toolu_task1', name: 'Task', input: { description: 'Explore the codebase', subagent_type: 'Explore' } }]
      }));
    } else {
      // Tool result after subagent completes
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({
        id: 'msg_done', type: 'message', role: 'assistant',
        model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
        usage: { input_tokens: 30, output_tokens: 10 },
        content: [{ type: 'text', text: 'Exploration complete.' }]
      }));
    }
  };

  harness.writePromptHook('Explore the codebase');

  const url = harness.getUrl();
  const headers = { 'content-type': 'application/json' };

  // First request triggers Task tool
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Explore the codebase' }] })
  });

  await harness.wait(200);

  // Tool result arrives
  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-20241022',
      messages: [{ role: 'user', content: [{ type: 'tool_result', tool_use_id: 'toolu_task1', content: 'Found 50 files' }] }]
    })
  });

  // SubagentStop hook fires after tool_result (simulates subagent completion)
  const childSessionId = 'child-00000000-0000-4000-8000-000000000001';
  harness.writeSubagentStopHook('toolu_task1', childSessionId);

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const subagentCompletions = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'SUBAGENT_COMPLETION');

  let passed = true;
  if (subagentCompletions.length < 1) {
    passed = fail(`expected at least 1 SUBAGENT_COMPLETION span, got ${subagentCompletions.length}`);
  } else {
    passed = pass('SUBAGENT_COMPLETION span created') && passed;

    const sc = subagentCompletions[0];
    const completed = getAttr(sc, 'subagent.completed');
    const source = getAttr(sc, 'subagent.completion_source');
    const sessionId = getAttr(sc, 'subagent.session_id');

    if (completed === true || completed === 'true') {
      passed = pass('subagent.completed=true') && passed;
    } else {
      passed = fail(`expected subagent.completed=true, got ${completed}`);
    }

    if (source === 'hook') {
      passed = pass('subagent.completion_source=hook') && passed;
    } else {
      passed = fail(`expected subagent.completion_source=hook, got ${source}`);
    }

    if (sessionId === childSessionId) {
      passed = pass(`subagent.session_id=${childSessionId}`) && passed;
    } else {
      passed = fail(`expected subagent.session_id=${childSessionId}, got ${sessionId}`);
    }
  }

  return passed;
}

// =============================================================================
// Test: Notification Spans (Phase 3)
// =============================================================================

async function testNotificationSpans(harness) {
  console.log('\n[Test] Notification Spans (NOTIFICATION)');

  harness.requestHandler = (req, res, body) => {
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({
      id: 'msg_simple', type: 'message', role: 'assistant',
      model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
      usage: { input_tokens: 50, output_tokens: 20 },
      content: [{ type: 'text', text: 'Hello!' }]
    }));
  };

  harness.writePromptHook('Hello');

  // Write notification hooks
  harness.writeNotificationHook('permission_prompt', 'Claude wants to edit file.txt');
  await harness.wait(100);
  harness.writeNotificationHook('auth_success', 'Authentication completed');

  const url = harness.getUrl();
  const headers = { 'content-type': 'application/json' };

  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Hello' }] })
  });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const notifications = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'NOTIFICATION');

  let passed = true;
  if (notifications.length < 2) {
    passed = fail(`expected at least 2 NOTIFICATION spans, got ${notifications.length}`);
  } else {
    passed = pass(`${notifications.length} NOTIFICATION spans created`) && passed;

    const types = notifications.map(n => getAttr(n, 'notification.type'));
    if (types.includes('permission_prompt')) {
      passed = pass('notification.type=permission_prompt found') && passed;
    } else {
      passed = fail('expected notification.type=permission_prompt');
    }

    if (types.includes('auth_success')) {
      passed = pass('notification.type=auth_success found') && passed;
    } else {
      passed = fail('expected notification.type=auth_success');
    }

    // Check message attribute
    const permNotif = notifications.find(n => getAttr(n, 'notification.type') === 'permission_prompt');
    if (permNotif) {
      const msg = getAttr(permNotif, 'notification.message');
      if (msg && msg.includes('edit file')) {
        passed = pass('notification.message present') && passed;
      }
    }
  }

  return passed;
}

// =============================================================================
// Test: Compaction Spans (Phase 3)
// =============================================================================

async function testCompactionSpans(harness) {
  console.log('\n[Test] Compaction Spans (COMPACTION)');

  harness.requestHandler = (req, res, body) => {
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({
      id: 'msg_simple', type: 'message', role: 'assistant',
      model: 'claude-3-5-sonnet-20241022', stop_reason: 'end_turn',
      usage: { input_tokens: 50, output_tokens: 20 },
      content: [{ type: 'text', text: 'Compacted!' }]
    }));
  };

  harness.writePromptHook('Compact the context');

  // Write PreCompact hook
  harness.writePreCompactHook('manual', '/compact command', 150);

  const url = harness.getUrl();
  const headers = { 'content-type': 'application/json' };

  await fetch(url, {
    method: 'POST', headers,
    body: JSON.stringify({ model: 'claude-3-5-sonnet-20241022', messages: [{ role: 'user', content: 'Compact the context' }] })
  });

  harness.writeStopHook();
  await harness.wait(500);

  const spans = harness.getSpans();
  const compactions = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'COMPACTION');

  let passed = true;
  if (compactions.length < 1) {
    passed = fail(`expected at least 1 COMPACTION span, got ${compactions.length}`);
  } else {
    passed = pass('COMPACTION span created') && passed;

    const c = compactions[0];
    const reason = getAttr(c, 'compaction.reason');
    const trigger = getAttr(c, 'compaction.trigger');
    const messagesBefore = getAttr(c, 'compaction.messages_before');

    if (reason === 'manual') {
      passed = pass('compaction.reason=manual') && passed;
    } else {
      passed = fail(`expected compaction.reason=manual, got ${reason}`);
    }

    if (trigger === '/compact command') {
      passed = pass('compaction.trigger=/compact command') && passed;
    } else {
      passed = fail(`expected compaction.trigger=/compact command, got ${trigger}`);
    }

    if (messagesBefore === 150) {
      passed = pass('compaction.messages_before=150') && passed;
    } else {
      passed = fail(`expected compaction.messages_before=150, got ${messagesBefore}`);
    }
  }

  return passed;
}

// =============================================================================
// Main
// =============================================================================

async function main() {
  const args = process.argv.slice(2);
  const testFilter = args.find(a => a.startsWith('--test='))?.split('=')[1];

  const tests = {
    basic: testBasicTurnBoundaries,
    streaming: testStreamingResponse,
    concurrent: testConcurrentTasks,
    error: testErrorScenarios,
    permission: testPermissionFlow,
    cost: testCostMetrics,
    posttool: testPostToolUseFlow,
    subagent: testSubagentStop,
    notification: testNotificationSpans,
    compaction: testCompactionSpans
  };

  const selectedTests = testFilter
    ? { [testFilter]: tests[testFilter] }
    : tests;

  if (testFilter && !tests[testFilter]) {
    console.error(`Unknown test: ${testFilter}`);
    console.error(`Available tests: ${Object.keys(tests).join(', ')}`);
    process.exitCode = 1;
    return;
  }

  let allPassed = true;
  let testCount = 0;
  let passCount = 0;

  for (const [name, testFn] of Object.entries(selectedTests)) {
    const harness = new TestHarness();
    await harness.setup();

    // Re-require interceptor for each test (fresh state)
    // Note: This won't work perfectly due to module caching, but tests are designed to be independent
    delete require.cache[require.resolve('./minimal-otel-interceptor.js')];
    require('./minimal-otel-interceptor.js');

    try {
      const passed = await testFn(harness);
      testCount++;
      if (passed) passCount++;
      else allPassed = false;
    } catch (err) {
      console.error(`  ERROR in ${name}:`, err.message);
      allPassed = false;
      testCount++;
    } finally {
      await harness.teardown();
    }
  }

  console.log('\n' + '='.repeat(60));
  console.log(`Results: ${passCount}/${testCount} tests passed`);

  if (!allPassed) {
    process.exitCode = 1;
  }
}

main().catch(err => {
  console.error(err);
  process.exitCode = 1;
});
