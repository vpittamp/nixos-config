# AI Session System

Last updated: 2026-03-14

## Purpose

This document describes how AI CLI sessions are detected, normalized, retained, and rendered in the Sway/i3pm/QuickShell stack.

The system exists to answer four product questions reliably:
- which AI sessions exist right now
- which session is the current one
- whether a session is actively working
- whether a completed session now needs user attention

## Goals

- deterministic session identity across tmux panes, hosts, and tool wrappers
- semantic session state based on telemetry, not CPU heuristics
- one authoritative current session per focused window
- stable ordering in the side panel
- multi-host visibility without merging away host identity

## Main Components

- `scripts/otel-ai-monitor/receiver.py`
  - Ingests OTEL/log-derived activity and normalizes timestamps.
- `scripts/otel-ai-monitor/session_tracker.py`
  - Tracks per-session lifecycle and writes runtime session snapshots.
- `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
  - Normalizes session state, derives phase/stage fields, and maintains review retention for the monitoring path.
- `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - Merges local and remote sessions into the daemon-owned dashboard payload used by QuickShell.
- `home-modules/desktop/quickshell-runtime-shell/shell.qml`
  - Renders the right-side AI session panel and applies visual state.
- `home-modules/ai-assistants/*.nix`
  - Wrap Codex, Claude Code, and Gemini with common launch metadata and OTEL plumbing.

## Runtime Data Flow

1. A managed AI CLI starts inside a tracked terminal/tmux pane.
2. The wrapper and OTEL pipeline attach identity metadata such as tool, project, host, and tmux pane.
3. `otel-ai-monitor` receives activity and updates the session snapshot.
4. The daemon reads local snapshots plus remote sink snapshots and normalizes them into dashboard session items.
5. QuickShell consumes `i3pm dashboard watch` and renders the host-grouped AI session panel.

Important runtime files:
- local session snapshot:
  - `$XDG_RUNTIME_DIR/otel-ai-sessions.json`
- remote sink snapshot:
  - `$XDG_RUNTIME_DIR/eww-monitoring-panel/remote-otel-sink.json`
- retained review state:
  - `$XDG_RUNTIME_DIR/eww-monitoring-panel/ai-session-review.json`

## Identity Model

The intended identity boundary is one tracked AI surface per tmux pane.

Primary identity fields:
- `tool`
- `connection_key`
- `context_key`
- `terminal_anchor_id`
- `tmux_session`
- `tmux_window`
- `tmux_pane`

Additional identity/debug fields:
- `session_key`
- `surface_key`
- `pid`
- `pane_pid`
- `pane_label`

Rules:
- `pid` is the preferred process identity for the actual AI process.
- `pane_pid` is only the tmux pane shell anchor and is diagnostic.
- sessions without tmux/anchor identity are intentionally not first-class in the panel model.

## Host Model

The daemon is host-aware.

Each session carries:
- `host_name`
- `connection_key`
- `is_current_host`
- `focus_mode`

Host behavior:
- local sessions on the current machine are locally focusable
- sessions from another machine remain visible in the panel
- remote sessions use daemon-mediated handoff instead of pretending to be local windows

The panel groups sessions by host first, then by project inside each host section.

## State Model

The visible panel model intentionally prioritizes three states:
- `working`
- `needs_attention`
- `done`

Internal fallback states such as `idle`, `stale`, and `inactive` still exist, but they are not the primary UX language.

### Working

A session is `working` when telemetry indicates active model/tool work, for example:
- explicit stream/tool events
- `pulse_working`
- `is_streaming`
- `pending_tools > 0`
- fresh non-heartbeat working-stage activity

The important rule is:
- process existence alone does not mean `working`

### Needs Attention

`needs_attention` means the session finished useful output and the user has not acknowledged it yet.

This is a retained completion state. It exists so a session can stop animating and still remain visually actionable.

### Done

`done` means the session completed and has already been acknowledged, usually by focusing that session.

After acknowledgement, the session may eventually settle to `idle` if nothing else is happening.

## Why CPU Is Not the Primary Activity Signal

Local CPU was explicitly demoted from the main state model.

Reasons:
- a remote LLM call can be actively in progress while local CPU is near zero
- shell/process heartbeats can keep timestamps fresh even when no real work is happening
- process existence tells us liveness, not semantic progress

CPU and PID remain useful as diagnostics, but the panel state is driven by telemetry-derived lifecycle signals.

## Heartbeat vs Real Activity

The system distinguishes real activity from keepalive noise.

Examples of heartbeat-like reasons:
- `process_detected`
- `process_keepalive`
- `metrics_heartbeat_created`

These signals can keep a session alive, but they should not by themselves animate the panel or promote a session to `working`.

## Current Session Selection

The system uses a single authoritative current session key.

Rules:
- there should be exactly one current session for the focused AI window
- `current_ai_session_key` is the authority used by QuickShell
- `is_current_window` must match that key exactly, not every session in the focused window

This matters for:
- highlighting
- `done -> needs_attention` transitions
- stable ordering
- focus handoff

## Ordering Rules

The panel now prefers stable identity ordering instead of recency-driven churn.

Stable ordering uses identity-oriented fields such as:
- host
- connection key
- project
- tmux session
- tmux window number
- tmux pane number
- pane label
- tool

Current/active state is expressed through styling, not item promotion.

## Review Retention

The review ledger retains completed-but-unseen work so the user can switch away and still return to it.

The review path is especially important when:
- a session finishes and becomes unfocused
- the live runtime session would otherwise fall back to idle quickly
- the UI still needs to show `needs_attention`

Focusing a session records it as seen and clears the retained attention state.

## QuickShell Rendering Model

QuickShell is presentation-only for session state.

It should:
- trust the daemon/dashboard payload
- use `current_ai_session_key` as the current-session authority
- animate only `working`
- render retained completion as `needs_attention`
- keep ordering stable

It should not:
- infer active work from CPU
- infer current-ness from pane/window booleans when a canonical current key is present
- own process discovery

## Tool Integration Contract

Codex, Claude Code, and Gemini are expected to emit a common metadata envelope so the rest of the system can treat them uniformly.

Examples of the shared metadata shape:
- `i3pm.ai.tool`
- `i3pm.ai.host_alias`
- `i3pm.ai.connection_key`
- `i3pm.ai.context_key`
- `i3pm.ai.terminal_anchor_id`
- `i3pm.ai.tmux_session`
- `i3pm.ai.tmux_window`
- `i3pm.ai.tmux_pane`
- `i3pm.ai.pane_key`

The wrappers are the right place to establish this contract because they are declarative and host-managed through Nix/Home Manager.

## Services

Relevant user services:
- `otel-ai-monitor.service`
- `i3-project-daemon.service`
- `quickshell-runtime-shell.service`

Useful checks:

```bash
systemctl --user status otel-ai-monitor.service
systemctl --user status i3-project-daemon.service
systemctl --user status quickshell-runtime-shell.service
i3pm dashboard snapshot --json | jq '.current_ai_session_key'
i3pm session list --json
```

## Troubleshooting

### Multiple current sessions in one window

Check:
- `i3pm dashboard snapshot --json`

Expected:
- one `current_ai_session_key`
- one `active_ai_sessions[]` item with `is_current_window = true`

If more than one session is marked current, the daemon emit path is wrong and QuickShell will show incorrect highlighting.

### A session is animating even though nothing is happening

Check:
- `status_reason`
- `last_activity_at`
- `pulse_working`
- `is_streaming`
- `pending_tools`

If the reason is heartbeat-like and there is no real activity timestamp, the session should not be considered `working`.

### A finished session never becomes `needs_attention`

Check whether the session ever reached retained completion:
- `output_ready`
- `review_pending`
- `session_phase`

If a session is immediately treated as seen, the review retention path or focus acknowledgement logic is too aggressive.

### The panel order keeps changing

Check whether ordering is being driven by:
- recency timestamps
- current-session promotion
- project/activity priority

The intended panel order is stable identity order, not MRU order.
