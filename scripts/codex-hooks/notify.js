#!/usr/bin/env node
/**
 * Codex `notify` hook handler.
 *
 * Codex calls: notify = ["node", "/path/to/notify.js"]
 * and passes a single JSON argument (string) describing the event.
 *
 * We forward that JSON to the local `codex-otel-interceptor` so it can end Turn spans.
 *
 * Desktop notifications are emitted centrally from the dashboard notifier, so
 * this hook only forwards stop metadata and never sends a toast directly.
 *
 * This script must never fail Codex runs, so all errors are swallowed.
 */

'use strict';

const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
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

// Persist session metadata for explicit stop handling.
try {
  const event = JSON.parse(payload);

  // Persist session metadata for deterministic PID/window correlation in otel-ai-monitor.
  // Codex native OTEL events may omit process.pid; this sidecar bridges thread-id -> PID.
  try {
    const threadId = typeof event['thread-id'] === 'string' ? event['thread-id'].trim() : '';
    const parentPid = Number.isInteger(process.ppid) ? process.ppid : 0;
    if (threadId && parentPid > 1) {
      const runtimeDir = process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid ? process.getuid() : ''}` || '/tmp';
      const metadataPath = path.join(runtimeDir, `codex-session-${parentPid}.json`);
      const tempPath = `${metadataPath}.tmp-${process.pid}`;
      const metadata = {
        version: 1,
        tool: 'codex',
        sessionId: threadId,
        pid: parentPid,
        projectName: process.env.I3PM_PROJECT_NAME || null,
        projectPath: process.env.I3PM_PROJECT_PATH || process.cwd(),
        terminalAnchorId: process.env.I3PM_TERMINAL_ANCHOR_ID || null,
        tmuxSession: process.env.TMUX_SESSION || null,
        tmuxWindow: process.env.TMUX_WINDOW || null,
        tmuxPane: process.env.TMUX_PANE || null,
        pty: process.env.TTY || null,
        hostName: os.hostname(),
        updatedAt: new Date().toISOString(),
      };
      fs.mkdirSync(runtimeDir, { recursive: true });
      fs.writeFileSync(tempPath, `${JSON.stringify(metadata)}\n`, { encoding: 'utf8', mode: 0o600 });
      fs.renameSync(tempPath, metadataPath);
    }
  } catch {
    // best-effort only
  }

} catch {
  // best-effort only - never fail Codex runs
}
