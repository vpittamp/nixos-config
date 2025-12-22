#!/usr/bin/env node
/**
 * Lightweight local harness to validate Codex + Gemini trace synthesis.
 *
 * This starts:
 * - A tiny OTLP/HTTP JSON receiver (collector stub) for /v1/{traces,logs,metrics}
 * - The interceptor as a child process on a random high port
 * - Sends a minimal set of log events to produce: Turn → LLM → Tool → LLM
 *
 * Usage:
 *   `node scripts/test-codex-gemini-otel-interceptors.js`
 */
/* eslint-disable no-console */

'use strict';

const http = require('node:http');
const { spawn } = require('node:child_process');
const { once } = require('node:events');

function anyValue(v) {
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'number' && Number.isFinite(v)) return { intValue: String(Math.trunc(v)) };
  if (typeof v === 'boolean') return { boolValue: v };
  // Fallback: stringify (keep the schema simple for this harness)
  return { stringValue: JSON.stringify(v) };
}

function attrs(obj) {
  return Object.entries(obj).map(([key, value]) => ({ key, value: anyValue(value) }));
}

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
    if (typeof v.boolValue === 'boolean') return v.boolValue;
    return undefined;
  }
  return undefined;
}

async function getFreePort() {
  const server = http.createServer((_, res) => res.end(''));
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const port = server.address().port;
  await new Promise((r) => server.close(r));
  return port;
}

async function httpJson({ hostname, port, path, body }) {
  return await new Promise((resolve, reject) => {
    const data = Buffer.from(JSON.stringify(body));
    const req = http.request(
      {
        hostname,
        port,
        path,
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': data.length },
      },
      (res) => {
        res.resume();
        res.on('end', resolve);
      }
    );
    req.on('error', reject);
    req.end(data);
  });
}

async function waitForHealth(port, { path = '/health', timeoutMs = 2000 } = {}) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      await new Promise((resolve, reject) => {
        const req = http.request({ hostname: '127.0.0.1', port, path, method: 'GET' }, (res) => {
          res.resume();
          res.statusCode === 200 ? resolve() : reject(new Error(`status=${res.statusCode}`));
        });
        req.on('error', reject);
        req.end();
      });
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 25));
    }
  }
  throw new Error(`health check timeout on :${port}${path}`);
}

async function withCollector(fn) {
  const received = [];
  const collector = http.createServer((req, res) => {
    if (req.method !== 'POST') {
      res.statusCode = 404;
      res.end('');
      return;
    }
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      try { received.push(JSON.parse(body)); } catch {}
      res.statusCode = 200;
      res.setHeader('Content-Type', 'application/json');
      res.end('{"partialSuccess":{}}');
    });
  });

  collector.listen(0, '127.0.0.1');
  await once(collector, 'listening');
  const port = collector.address().port;
  const base = `http://127.0.0.1:${port}`;

  try {
    await fn({
      base,
      received,
      getSpans: () => received.flatMap(getSpansFromOtlpJson),
    });
  } finally {
    await new Promise((r) => collector.close(r));
  }
}

async function runCodexTest(collector) {
  const interceptorPort = await getFreePort();

  const child = spawn('node', ['scripts/codex-otel-interceptor.js'], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      CODEX_OTEL_INTERCEPTOR_HOST: '127.0.0.1',
      CODEX_OTEL_INTERCEPTOR_PORT: String(interceptorPort),
      CODEX_OTEL_INTERCEPTOR_FORWARD_BASE: collector.base,
      CODEX_OTEL_INTERCEPTOR_TRACES_ENDPOINT: `${collector.base}/v1/traces`,
      CODEX_OTEL_INTERCEPTOR_SESSION_IDLE_END_MS: '100',
      CODEX_OTEL_INTERCEPTOR_TURN_IDLE_END_MS: '50',
      CODEX_OTEL_INTERCEPTOR_DEBUG: '0',
    },
  });

  try {
    await waitForHealth(interceptorPort);

    const conversationId = 'conv-test-0001';
    const baseTs = Date.now();
    const iso = (t) => new Date(t).toISOString();

    const logsPayload = {
      resourceLogs: [
        {
          resource: {
            attributes: attrs({
              'service.name': 'codex_cli_rs',
              'service.version': '0.0-test',
              env: 'test',
            }),
          },
          scopeLogs: [
            {
              scope: { name: 'codex', version: 'test' },
              logRecords: [
                {
                  timeUnixNano: String(baseTs * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.conversation_starts',
                    'event.timestamp': iso(baseTs),
                    'conversation.id': conversationId,
                    model: 'gpt-5-codex',
                    provider_name: 'OpenAI',
                    approval_policy: 'never',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 10) * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.user_prompt',
                    'event.timestamp': iso(baseTs + 10),
                    'conversation.id': conversationId,
                    prompt: 'list files, then read README',
                    prompt_length: 28,
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 30) * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.api_request',
                    'event.timestamp': iso(baseTs + 30),
                    'conversation.id': conversationId,
                    duration_ms: 20,
                    'http.response.status_code': 200,
                    attempt: 0,
                    model: 'gpt-5-codex',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 35) * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.sse_event',
                    'event.timestamp': iso(baseTs + 35),
                    'conversation.id': conversationId,
                    'event.kind': 'response.completed',
                    input_token_count: 100,
                    output_token_count: 10,
                    cached_token_count: 0,
                    reasoning_token_count: 0,
                    tool_token_count: 0,
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 40) * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.tool_decision',
                    'event.timestamp': iso(baseTs + 40),
                    'conversation.id': conversationId,
                    tool_name: 'shell_command',
                    call_id: 'call_1',
                    decision: 'approved',
                    source: 'Config',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 60) * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.tool_result',
                    'event.timestamp': iso(baseTs + 60),
                    'conversation.id': conversationId,
                    tool_name: 'shell_command',
                    call_id: 'call_1',
                    duration_ms: 10,
                    success: true,
                    arguments: JSON.stringify({ command: 'ls -la', workdir: '/tmp' }),
                    output: 'Exit code: 0 Wall time: 0.01 seconds Output: README.md\\n',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 90) * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.api_request',
                    'event.timestamp': iso(baseTs + 90),
                    'conversation.id': conversationId,
                    duration_ms: 15,
                    'http.response.status_code': 200,
                    attempt: 0,
                    model: 'gpt-5-codex',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 95) * 1e6),
                  attributes: attrs({
                    'event.name': 'codex.sse_event',
                    'event.timestamp': iso(baseTs + 95),
                    'conversation.id': conversationId,
                    'event.kind': 'response.completed',
                    input_token_count: 120,
                    output_token_count: 12,
                    cached_token_count: 0,
                    reasoning_token_count: 0,
                    tool_token_count: 0,
                  }),
                },
              ],
            },
          ],
        },
      ],
    };

    await httpJson({
      hostname: '127.0.0.1',
      port: interceptorPort,
      path: '/v1/logs',
      body: logsPayload,
    });

    await httpJson({
      hostname: '127.0.0.1',
      port: interceptorPort,
      path: '/notify',
      body: {
        type: 'agent-turn-complete',
        'thread-id': conversationId,
        cwd: '/tmp',
        'last-assistant-message': 'done',
      },
    });

    // Wait for spans to flow through the async timers (session flush).
    await new Promise((r) => setTimeout(r, 250));

    const spans = collector.getSpans();
    const tool = spans.find((s) => (s.name || '').includes('Tool: shell_command (ls -la)'));
    if (!tool) throw new Error('codex: missing semantic tool span name (expected "(ls -la)")');

    const producedBy = tool.links?.find((l) => (l.attributes || []).some((a) => a?.key === 'link.type' && a?.value?.stringValue === 'produced_by_llm'));
    if (!producedBy) throw new Error('codex: tool span missing produced_by_llm link');

    const llms = spans.filter((s) => (s.name || '').startsWith('LLM Call: gpt-5-codex'));
    const consumes = llms.find((s) => (s.links || []).some((l) => l?.spanId === tool.spanId));
    if (!consumes) throw new Error('codex: missing consumes_tool_result link from subsequent LLM span');

    const argsPreview = getAttr(tool, 'tool.args_preview');
    if (typeof argsPreview !== 'string' || !argsPreview.includes('ls -la')) {
      throw new Error('codex: missing tool.args_preview');
    }

    console.log('PASS codex');
  } finally {
    child.kill('SIGTERM');
  }
}

async function runGeminiTest(collector) {
  const interceptorPort = await getFreePort();

  const child = spawn('node', ['scripts/gemini-otel-interceptor.js'], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      GEMINI_OTEL_INTERCEPTOR_HOST: '127.0.0.1',
      GEMINI_OTEL_INTERCEPTOR_PORT: String(interceptorPort),
      GEMINI_OTEL_INTERCEPTOR_FORWARD_BASE: collector.base,
      GEMINI_OTEL_INTERCEPTOR_TRACES_ENDPOINT: `${collector.base}/v1/traces`,
      GEMINI_OTEL_INTERCEPTOR_SESSION_IDLE_END_MS: '100',
      GEMINI_OTEL_INTERCEPTOR_TURN_IDLE_END_MS: '80',
      GEMINI_OTEL_INTERCEPTOR_DEBUG: '0',
    },
  });

  try {
    await waitForHealth(interceptorPort);

    const sessionId = 'sess-test-0001';
    const baseTs = Date.now();
    const iso = (t) => new Date(t).toISOString();

    const responseChunk = [
      {
        candidates: [
          {
            content: {
              role: 'model',
              parts: [{ text: 'Hello from Gemini.' }],
            },
          },
        ],
      },
    ];

    const envelopes = {
      resourceLogs: [
        {
          resource: {
            attributes: attrs({
              'service.name': 'gemini-cli',
              'service.version': '0.0-test',
              env: 'test',
            }),
          },
          scopeLogs: [
            {
              scope: { name: 'gemini', version: 'test' },
              logRecords: [
                {
                  timeUnixNano: String(baseTs * 1e6),
                  attributes: attrs({
                    'event.name': 'gemini_cli.user_prompt',
                    'event.timestamp': iso(baseTs),
                    'session.id': sessionId,
                    prompt: 'say hello and list directory',
                    prompt_length: 27,
                    prompt_id: 'p1',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 10) * 1e6),
                  attributes: attrs({
                    'event.name': 'gemini_cli.api_request',
                    'event.timestamp': iso(baseTs + 10),
                    'session.id': sessionId,
                    model: 'gemini-3-flash-preview',
                    prompt_id: 'p1',
                    request_text: "I'm currently working in the directory: /tmp\n",
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 40) * 1e6),
                  attributes: attrs({
                    'event.name': 'gemini_cli.api_response',
                    'event.timestamp': iso(baseTs + 40),
                    'session.id': sessionId,
                    model: 'gemini-3-flash-preview',
                    prompt_id: 'p1',
                    duration_ms: 30,
                    status_code: 200,
                    input_token_count: 10,
                    output_token_count: 3,
                    cached_content_token_count: 0,
                    thoughts_token_count: 0,
                    tool_token_count: 0,
                    total_token_count: 13,
                    response_text: JSON.stringify(responseChunk),
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 70) * 1e6),
                  attributes: attrs({
                    'event.name': 'gemini_cli.tool_call',
                    'event.timestamp': iso(baseTs + 70),
                    'session.id': sessionId,
                    function_name: 'list_directory',
                    function_args: JSON.stringify({ path: '/tmp' }),
                    duration_ms: 10,
                    status: 'success',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 100) * 1e6),
                  attributes: attrs({
                    'event.name': 'gemini_cli.api_request',
                    'event.timestamp': iso(baseTs + 100),
                    'session.id': sessionId,
                    model: 'gemini-3-flash-preview',
                    prompt_id: 'p1',
                    request_text: 'tool results here',
                  }),
                },
                {
                  timeUnixNano: String((baseTs + 130) * 1e6),
                  attributes: attrs({
                    'event.name': 'gemini_cli.api_response',
                    'event.timestamp': iso(baseTs + 130),
                    'session.id': sessionId,
                    model: 'gemini-3-flash-preview',
                    prompt_id: 'p1',
                    duration_ms: 20,
                    status_code: 200,
                    input_token_count: 5,
                    output_token_count: 2,
                    cached_content_token_count: 0,
                    thoughts_token_count: 0,
                    tool_token_count: 0,
                    total_token_count: 7,
                    response_text: JSON.stringify(responseChunk),
                  }),
                },
              ],
            },
          ],
        },
      ],
    };

    await httpJson({
      hostname: '127.0.0.1',
      port: interceptorPort,
      path: '/',
      body: envelopes,
    });

    await new Promise((r) => setTimeout(r, 250));

    const spans = collector.getSpans();
    const tool = spans.find((s) => (s.name || '').includes('Tool: list_directory (/tmp)'));
    if (!tool) throw new Error('gemini: missing semantic tool span name (expected "(/tmp)")');

    const llms = spans.filter((s) => (s.name || '').startsWith('LLM Call: gemini-3-flash-preview'));
    const consumes = llms.find((s) => (s.links || []).some((l) => l?.spanId === tool.spanId));
    if (!consumes) throw new Error('gemini: missing consumes_tool_result link on subsequent LLM span');

    const out = getAttr(consumes, 'output.value');
    if (typeof out !== 'string' || out.startsWith('[') || !out.includes('Hello from Gemini')) {
      throw new Error('gemini: output.value should be extracted text (not raw JSON)');
    }

    console.log('PASS gemini');
  } finally {
    child.kill('SIGTERM');
  }
}

async function main() {
  await withCollector(async (collector) => {
    await runCodexTest(collector);
    await runGeminiTest(collector);
  });
  console.log('OK');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
