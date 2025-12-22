#!/usr/bin/env node
/**
 * Codex `notify` hook handler.
 *
 * Codex calls: notify = ["node", "/path/to/notify.js"]
 * and passes a single JSON argument (string) describing the event.
 *
 * We forward that JSON to the local `codex-otel-interceptor` so it can end Turn spans.
 *
 * This script must never fail Codex runs, so all errors are swallowed.
 */

'use strict';

const http = require('node:http');

const payload = process.argv[2];
if (!payload || typeof payload !== 'string') {
  process.exit(0);
}

const host = process.env.CODEX_OTEL_INTERCEPTOR_HOST || '127.0.0.1';
const port = Number.parseInt(process.env.CODEX_OTEL_INTERCEPTOR_PORT || '4319', 10);

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

