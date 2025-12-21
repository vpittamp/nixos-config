#!/usr/bin/env node
/**
 * Local harness for validating `scripts/minimal-otel-interceptor.js` behavior
 * without hitting the real Anthropic API or requiring Alloy to be running.
 *
 * Runs:
 * 1) A tiny OTLP/HTTP "collector" that accepts JSON OTLP spans at /v1/traces
 * 2) A fake Anthropic endpoint that returns a tool_use → tool_result loop
 *
 * Validates:
 * - Exactly one Turn span across a tool loop (tool_result is role=user but NOT a new turn)
 * - `session.id` is hydrated from `$XDG_RUNTIME_DIR/claude-session-${pid}.json`
 * - Tool spans link to producing LLM span, and LLM spans link to consumed tool spans
 *
 * Usage:
 *   `node scripts/test-otel-interceptor-harness.js`
 */

'use strict';

const http = require('node:http');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const { once } = require('node:events');

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
  console.error(`FAIL: ${msg}`);
  process.exitCode = 1;
}

async function main() {
  const runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'otel-interceptor-harness-'));

  // 1) Minimal OTLP/HTTP receiver (JSON OTLP spans only)
  const received = [];
  const otlpServer = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/v1/traces') {
      res.statusCode = 404;
      res.end('not found');
      return;
    }

    let body = '';
    req.setEncoding('utf8');
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        received.push(JSON.parse(body));
      } catch {
        // ignore
      }
      res.statusCode = 200;
      res.end('ok');
    });
  });
  otlpServer.listen(0, '127.0.0.1');
  await once(otlpServer, 'listening');
  const otlpPort = otlpServer.address().port;

  // 2) Fake Anthropic API (tool_use then end_turn)
  let reqCount = 0;
  const anthropicServer = http.createServer((req, res) => {
    // We route through a local URL that *contains* "api.anthropic.com" in the path
    // so the interceptor matches it without using URL userinfo (which undici forbids).
    if (req.method !== 'POST' || req.url !== '/api.anthropic.com/v1/messages') {
      res.statusCode = 404;
      res.end('not found');
      return;
    }

    let body = '';
    req.setEncoding('utf8');
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      reqCount++;
      const responseBody = reqCount === 1
        ? {
            id: 'msg_1',
            type: 'message',
            role: 'assistant',
            model: 'claude-3-5-sonnet-test',
            stop_reason: 'tool_use',
            usage: { input_tokens: 10, output_tokens: 3 },
            content: [
              {
                type: 'tool_use',
                id: 'toolu_1',
                name: 'Read',
                input: { file_path: '/tmp/example.txt' }
              }
            ]
          }
        : {
            id: 'msg_2',
            type: 'message',
            role: 'assistant',
            model: 'claude-3-5-sonnet-test',
            stop_reason: 'end_turn',
            usage: { input_tokens: 5, output_tokens: 12 },
            content: [{ type: 'text', text: 'Done.' }]
          };

      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify(responseBody));
    });
  });
  anthropicServer.listen(0, '127.0.0.1');
  await once(anthropicServer, 'listening');
  const anthropicPort = anthropicServer.address().port;

  // Configure the interceptor to export to our local OTLP receiver.
  process.env.XDG_RUNTIME_DIR = runtimeDir;
  process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = `http://127.0.0.1:${otlpPort}/v1/traces`;
  process.env.OTEL_SERVICE_NAME = 'claude-code-harness';

  // Simulate the SessionStart hook writing a native session UUID.
  const sessionId = '00000000-0000-4000-8000-000000000000';
  fs.writeFileSync(
    path.join(runtimeDir, `claude-session-${process.pid}.json`),
    JSON.stringify({ version: 1, sessionId })
  );

  // Simulate UserPromptSubmit hook writing prompt metadata (hook-driven turn boundaries).
  fs.writeFileSync(
    path.join(runtimeDir, `claude-user-prompt-${process.pid}.json`),
    JSON.stringify({
      version: 1,
      sessionId,
      prompt: 'Read the file.',
      pid: process.pid,
      timestampMs: Date.now()
    })
  );

  // Load the interceptor (patches global fetch).
  require('./minimal-otel-interceptor.js');

  const url = `http://127.0.0.1:${anthropicPort}/api.anthropic.com/v1/messages`;
  const headers = { 'content-type': 'application/json' };

  // First request: user prompt (new turn)
  await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-test',
      messages: [{ role: 'user', content: 'Read the file.' }]
    })
  });

  // Second request: tool_result (must NOT start a new turn)
  await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-test',
      messages: [
        {
          role: 'user',
          content: [
            { type: 'tool_result', tool_use_id: 'toolu_1', content: 'ok', is_error: false }
          ]
        }
      ]
    })
  });

  // Simulate Stop hook marking the end of the turn (so the Turn span is exported).
  fs.writeFileSync(
    path.join(runtimeDir, `claude-stop-${process.pid}.json`),
    JSON.stringify({
      version: 1,
      sessionId,
      pid: process.pid,
      timestampMs: Date.now()
    })
  );

  // Give exporter time to POST spans.
  await new Promise(r => setTimeout(r, 500));

  const spans = received.flatMap(getSpansFromOtlpJson);

  const turns = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'AGENT');
  const llms = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'LLM');
  const tools = spans.filter(s => getAttr(s, 'openinference.span.kind') === 'TOOL');

  if (turns.length !== 1) fail(`expected 1 Turn span, got ${turns.length}`);
  if (llms.length !== 2) fail(`expected 2 LLM spans, got ${llms.length}`);
  if (tools.length !== 1) fail(`expected 1 Tool span, got ${tools.length}`);

  for (const s of [...turns, ...llms, ...tools]) {
    const sid = getAttr(s, 'session.id');
    if (sid !== sessionId) fail(`span ${s.name} has session.id=${sid}, expected ${sessionId}`);
  }

  // Validate tool → producing LLM link
  const toolLinks = tools[0]?.links || [];
  const produced = toolLinks.find(l => getLinkType(l) === 'produced_by_llm');
  if (!produced) fail('tool span missing produced_by_llm link');
  const llmSpanIds = new Set(llms.map(s => s.spanId));
  if (produced && !llmSpanIds.has(produced.spanId)) {
    fail('tool span produced_by_llm link does not reference an LLM spanId');
  }

  // Validate LLM (2nd) → consumed tool link
  const llmConsumes = llms.flatMap(s => (s.links || []).map(l => ({ llm: s, link: l })))
    .find(x => getLinkType(x.link) === 'consumes_tool_result');
  if (!llmConsumes) fail('no LLM span has consumes_tool_result link');
  if (llmConsumes && llmConsumes.link.spanId !== tools[0].spanId) {
    fail('LLM consumes_tool_result link does not reference the tool spanId');
  }

  if (process.exitCode === 1) {
    console.error('--- Received spans (debug) ---');
    for (const s of spans) console.error(`- ${s.name} (${getAttr(s, 'openinference.span.kind')})`);
  } else {
    console.log('PASS: interceptor semantics look correct');
    console.log(`- spans: turn=${turns.length}, llm=${llms.length}, tool=${tools.length}`);
    console.log(`- session.id hydrated: ${sessionId}`);
  }

  // Cleanup
  await new Promise(r => anthropicServer.close(r));
  await new Promise(r => otlpServer.close(r));
  try { fs.rmSync(runtimeDir, { recursive: true, force: true }); } catch {}
}

main().catch(err => {
  console.error(err);
  process.exitCode = 1;
});
