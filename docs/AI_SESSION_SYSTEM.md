# AI Session System

Last updated: 2026-06-08

## Purpose

AI session state in the Sway/i3pm/QuickShell stack is Herdr-native.

The panel answers:
- which Herdr-managed AI sessions exist now
- which Herdr pane is focused
- which sessions are `working`, `blocked`, `done`, `idle`, or `unknown`
- how to focus or close a Herdr pane from QuickShell

## Runtime Data Flow

1. Claude or Codex starts through Herdr.
2. Herdr records workspace, tab, pane, terminal, cwd, foreground cwd, focus, and `agent_status`.
3. `i3-project-daemon` exposes `herdr.snapshot` and places Herdr-shaped rows in `dashboard.snapshot.active_ai_sessions`.
4. QuickShell renders those rows directly.

The daemon keeps the historical dashboard field name during migration, but the row shape is Herdr-native.

## Row Contract

Each AI row uses Herdr identifiers:
- `herdr_session`
- `workspace_id`
- `tab_id`
- `pane_id`
- `terminal_id`

State comes directly from Herdr:
- `agent_status`: `working`, `blocked`, `done`, `idle`, or `unknown`
- `focused`: current-row marker
- `cwd` and `foreground_cwd`: labels and worktree matching

Rows also carry daemon action targets:
- `focus_target`: `{ method: "herdr.pane.focus", params: { pane_id } }`
- `close_target`: `{ method: "herdr.pane.close", params: { pane_id } }`
- optional `workspace_focus_target`
- optional `tab_focus_target`

## Daemon Methods

- `herdr.snapshot`
- `herdr.pane.focus`
- `herdr.pane.close`
- `herdr.workspace.focus`
- `herdr.tab.focus`

`session.list` remains as a compatibility endpoint, but it returns the Herdr rows already present in `runtime.snapshot`.

## Health

`i3pm health` checks:
- Herdr server is running
- client/server protocol is compatible
- `herdr agent list` and `herdr pane list` return valid JSON
- Claude and Codex Herdr integrations are installed

Useful commands:

```bash
herdr status --json
herdr agent list
herdr pane list
herdr workspace list
herdr tab list
herdr integration status
i3pm health
```

## Retired

The QuickShell AI session panel no longer reads or depends on:
- `otel-ai-monitor.service`
- `$XDG_RUNTIME_DIR/otel-ai-sessions.json`
- remote OTEL sink/push state
- ClickHouse AI-session aggregation
- tmux identity as a display requirement
- custom `session_phase`, `stage`, `turn_owner`, or trace metadata for AI row rendering
