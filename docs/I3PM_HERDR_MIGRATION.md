# i3pm Herdr Migration Notes

Last updated: 2026-06-11

## Authority Model

- i3-project-daemon owns desktop/session truth for dashboard clients.
- Herdr owns AI workspace/tab/pane/agent truth.
- QuickShell renders daemon payloads and sends explicit daemon actions.
- OTEL remains telemetry-only.
- tmux remains terminal launch infrastructure only.

Current focus is authoritative only through `dashboard.snapshot.focus_state`:
- `current_session_key`
- `current_window_id`
- `current_workspace_name`
- `current_herdr_pane_id`
- `current_herdr_host`
- `pending_intent_id`

Raw row fields such as `focused`, `window_active`, and `pane_active` are row metadata. They are not QuickShell highlight authority.

## Dashboard Contract

Cold start and recovery use `dashboard.snapshot`.

Steady-state updates use `i3pm dashboard watch`:
- one initial snapshot
- typed delta events: `focus.changed`, `window.changed`, `workspace.changed`, `session.changed`, `herdr.changed`, `display.changed`, `dashboard.invalidated`
- snapshot refetch only after invalidation, missed generation, parse failure, or watcher reconnect

Dashboard payloads must include schema/generation markers:
- `schema_version = "i3pm.dashboard.v2"`
- `generation`
- `snapshot_version`
- `session_generation`
- `display_generation`
- `focus_generation`

Dashboard event payloads must include:
- `schema_version = "i3pm.dashboard.event.v1"`
- `event_type`
- `generation`
- `changed_keys`
- minimal changed-model `payload`

Retired public fields must stay absent:
- `current_ai_session_key`
- `focus_state.current_ai_session_key`
- `focus_state.focused_window_id`

## Herdr Proxy Model

ThinkPad consumes ryzen Herdr state through the ryzen-side `i3pm herdr-proxy` endpoint.

The proxy boundary provides:
- compact local Herdr snapshot
- typed Herdr event stream
- pane focus command endpoint

ThinkPad remote rows are focus-only:
- `focus_target.method = "herdr.remote.pane.focus"`
- no remote `close_target`
- no tmux preview fallback
- no SSH fanout over multiple direct `herdr list` commands

Health checks verify the proxy path:
- proxy reachable
- protocol version compatible
- remote Herdr generation visible
- remote focus command round trip within budget
- Tailscale peer state when a remote target is configured

## QuickShell Renderer Contract

QuickShell must not infer current AI session, current window, or current workspace from raw rows.

Allowed QuickShell state:
- local panel visibility and selection
- collapsed/expanded UI state
- presentational labels, colors, grouping, and sorting

Daemon-owned state:
- current session/window/workspace
- Herdr remote/local precedence
- focus intent pending/confirmed/failed state
- display layout mutation
- launch/reuse status

QuickShell action flow:
- row clicks call the row's daemon-provided `focus_target` or `close_target`
- window/workspace clicks use daemon fast-focus actions
- current highlights come from `focus_state`
- parse failures or missed generations call `resetDashboard(...)`

## Retired AI UI Paths

These paths must not participate in AI session identity, current-row selection, previews, or notifications:
- `otel-ai-monitor.service`
- `$XDG_RUNTIME_DIR/otel-ai-sessions.json`
- remote OTEL sink/push state
- ClickHouse AI-session aggregation
- tmux pane/session/window identity
- tmux live preview subprocesses
- custom lifecycle fields such as `session_phase`, `turn_owner`, `activity_substate`, and `status_reason`
- Eww monitoring panel state and `monitoring_data.py` as UI authority

The daemon strips legacy tmux and lifecycle fields from `active_ai_sessions` and `session.list`.

## Post-Rebuild Smoke

Run these after changes that affect daemon, QuickShell, Herdr, or i3pm:

```bash
i3pm health --json
i3pm perf smoke --json
i3pm daemon call dashboard.snapshot --json
```

On ThinkPad, also verify the remote ryzen Herdr path:

```bash
i3pm health --json | jq '.herdr_remotes'
i3pm perf smoke --json | jq '.checks[] | select(.name == "herdr.remote.pane.focus")'
```
