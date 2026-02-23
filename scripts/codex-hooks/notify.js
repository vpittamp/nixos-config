#!/usr/bin/env node
/**
 * Codex `notify` hook handler.
 *
 * Codex calls: notify = ["node", "/path/to/notify.js"]
 * and passes a single JSON argument (string) describing the event.
 *
 * We forward that JSON to the local `codex-otel-interceptor` so it can end Turn spans.
 *
 * On `agent-turn-complete` events, we also spawn the unified
 * ai-finished-notification.sh to send a desktop notification.
 *
 * This script must never fail Codex runs, so all errors are swallowed.
 */

'use strict';

const http = require('node:http');
const { spawn } = require('node:child_process');
const path = require('node:path');

const payload = process.argv[2];
if (!payload || typeof payload !== 'string') {
  process.exit(0);
}

const host = process.env.CODEX_OTEL_INTERCEPTOR_HOST || '127.0.0.1';
const port = Number.parseInt(process.env.CODEX_OTEL_INTERCEPTOR_PORT || '4319', 10);

// Forward to OTEL interceptor (existing behavior)
try {
  const req = http.request(
    {
      hostname: host,
      port,
      path: '/notify',
      method: 'POST',
      agent: false,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    },
    (res) => res.resume()
  );
  req.on('error', () => {});
  req.setTimeout(1000, () => req.destroy());
  req.end(payload);
} catch {
  // best-effort only
}

// Send desktop notification on agent-turn-complete
try {
  const event = JSON.parse(payload);
  if (event.type === 'agent-turn-complete') {
    // Extract a useful message from the payload
    let message = 'Task complete';
    if (event['last-assistant-message']) {
      // Truncate to 150 chars for notification
      const raw = String(event['last-assistant-message']).replace(/\n/g, ' ');
      message = raw.length > 150 ? raw.slice(0, 150) + '...' : raw;
    } else if (event.message) {
      const raw = String(event.message).replace(/\n/g, ' ');
      message = raw.length > 150 ? raw.slice(0, 150) + '...' : raw;
    }

    const notifScript = path.resolve(__dirname, '..', 'ai-finished-notification.sh');
    const child = spawn(notifScript, ['Codex', message], {
      detached: true,
      stdio: 'ignore',
      env: { ...process.env },
    });
    child.unref();
  }
} catch {
  // best-effort only - never fail Codex runs
}
