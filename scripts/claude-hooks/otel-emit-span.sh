#!/usr/bin/env bash
# otel-emit-span.sh - Emit a synthetic OTLP trace span for claude-code lifecycle events.
#
# Why this exists:
# claude-code is a Node.js Single Executable Application (SEA, a 240MB ELF
# binary), and SEAs DON'T honor NODE_OPTIONS=--require. So the
# minimal-otel-interceptor.js that's supposed to patch globalThis.fetch and
# emit hierarchical spans never loads inside the actual claude-code process.
# claude-code's built-in OTEL pipeline emits LOGS but not TRACES, and the
# cross-host panel SQL queries otel_traces only. Result: claude-code sessions
# never appear in the panel.
#
# Workaround: have the lifecycle HOOKS (which fire as separate bash processes,
# OUTSIDE the SEA, so they see the right env) POST synthetic OTLP spans
# directly to localhost:4318/v1/traces. This gives the panel a span to find
# for every active session.
#
# Args:
#   $1 - session_id (UUID, from claude-code's hook input)
#   $2 - span_name (e.g. "claude_code.session_start" or "claude_code.user_prompt")
#
# Best-effort: never fails the calling hook.

set -u

SESSION_ID="${1:-}"
SPAN_NAME="${2:-claude_code.event}"

[[ -z "$SESSION_ID" ]] && exit 0

ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"
SERVICE="${OTEL_SERVICE_NAME:-claude-code}"
HOST_NAME="${HOSTNAME:-$(hostname 2>/dev/null || echo unknown)}"
TMUX_SESSION="${TMUX_SESSION:-}"
TMUX_WINDOW="${TMUX_WINDOW:-}"
TMUX_PANE="${TMUX_PANE:-}"
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"
PROJECT_PATH="${I3PM_PROJECT_PATH:-}"

# Bail out early if we don't have enough context for the panel SQL filter
# (HAVING tmux_session != '' AND tmux_pane != '').
[[ -z "$TMUX_SESSION" || -z "$TMUX_PANE" ]] && exit 0

# Random 16-byte trace_id and 8-byte span_id (hex)
TRACE_ID="$(head -c 16 /dev/urandom | od -An -vtx1 | tr -d ' \n')"
SPAN_ID="$(head -c 8 /dev/urandom | od -An -vtx1 | tr -d ' \n')"

# Nanosecond timestamps. GNU date supports %N; busybox doesn't, fall back to seconds*1e9.
if NOW_NS="$(date +%s%N 2>/dev/null)" && [[ "$NOW_NS" != *N ]]; then :; else
  NOW_NS="$(($(date +%s) * 1000000000))"
fi
END_NS="$((NOW_NS + 1000000))"  # 1ms span

# Build OTLP/JSON payload. The panel SQL needs ServiceName, host.name,
# terminal.tmux.session, terminal.tmux.window, terminal.tmux.pane,
# i3pm.project_name in ResourceAttributes, and session.id in SpanAttributes.
PAYLOAD="$(jq -nc \
  --arg trace "$TRACE_ID" \
  --arg span "$SPAN_ID" \
  --arg name "$SPAN_NAME" \
  --arg start "$NOW_NS" \
  --arg end "$END_NS" \
  --arg service "$SERVICE" \
  --arg sid "$SESSION_ID" \
  --arg host "$HOST_NAME" \
  --arg tmux_s "$TMUX_SESSION" \
  --arg tmux_w "$TMUX_WINDOW" \
  --arg tmux_p "$TMUX_PANE" \
  --arg proj "$PROJECT_NAME" \
  --arg ppath "$PROJECT_PATH" \
  '{
    resourceSpans: [{
      resource: {
        attributes: [
          {key: "service.name", value: {stringValue: $service}},
          {key: "host.name", value: {stringValue: $host}},
          {key: "terminal.tmux.session", value: {stringValue: $tmux_s}},
          {key: "terminal.tmux.window", value: {stringValue: $tmux_w}},
          {key: "terminal.tmux.pane", value: {stringValue: $tmux_p}},
          {key: "i3pm.project_name", value: {stringValue: $proj}},
          {key: "i3pm.project_path", value: {stringValue: $ppath}},
          {key: "claude.hook.emitter", value: {stringValue: "otel-emit-span.sh"}}
        ]
      },
      scopeSpans: [{
        spans: [{
          traceId: $trace,
          spanId: $span,
          name: $name,
          kind: 1,
          startTimeUnixNano: $start,
          endTimeUnixNano: $end,
          attributes: [
            {key: "session.id", value: {stringValue: $sid}},
            {key: "claude_code.hook_event", value: {stringValue: $name}}
          ]
        }]
      }]
    }]
  }' 2>/dev/null)"

[[ -z "$PAYLOAD" ]] && exit 0

# Fire-and-forget. Never block claude-code lifecycle on telemetry.
curl -sm 2 -X POST -H "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "${ENDPOINT%/}/v1/traces" >/dev/null 2>&1 || true

exit 0
