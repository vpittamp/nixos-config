# QuickShell Runtime Shell

Last updated: 2026-03-12

## Purpose

This document describes the current QuickShell-based runtime shell that replaces the older Eww workspace bar and monitoring-panel path.

The goals of the QuickShell runtime shell are:
- render one native bar per active monitor
- keep a single AI/session detail panel on the configured primary monitor
- use the i3pm daemon as the authority for context, launch, session, and display mutations
- reduce polling and duplicate work in the AI session dashboard path
- keep host behavior declarative across `thinkpad` and `ryzen`

## Components

- `home-modules/desktop/quickshell-runtime-shell/default.nix`
  - Home Manager module that installs QuickShell, generates `ShellConfig.qml`, wires keybindings/scripts, and defines the `quickshell-runtime-shell.service`.
- `home-modules/desktop/quickshell-runtime-shell/shell.qml`
  - QuickShell UI implementation.
  - Owns per-monitor bars, the single right-side AI panel, shell-local view state, and daemon-driven actions.
- `home-modules/desktop/i3-project-event-daemon/ipc_server.py`
  - Exposes the daemon dashboard and display APIs consumed by the shell.
- `home-modules/desktop/i3-project-event-daemon/daemon.py`
  - Wires filesystem watchers and state invalidation so the shell can react to AI session and display changes.
- `home-modules/tools/i3pm/src/commands/dashboard.ts`
  - Event-driven `i3pm dashboard watch` client used by QuickShell.
- `home-modules/tools/i3pm/src/commands/display.ts`
  - CLI surface for `display snapshot|apply|cycle`.

## Runtime Architecture

### 1. UI structure

The shell is split into two UI surfaces:
- one `PanelWindow` per screen for the bottom bar
- one `PanelWindow` for the right-side AI/session panel

Per-monitor bars are instantiated with:
- `Variants { model: Quickshell.screens }`
- `screen: modelData`

The bar uses native QuickShell/i3 integration for workspace rendering:
- `I3.monitorFor(screen)`
- `I3.workspaces`
- `workspace.activate()`

The AI panel is intentionally singular:
- it is anchored to the preferred primary output
- it does not follow focus between monitors
- fallback order is:
  1. configured `primaryOutputs`
  2. currently focused i3 monitor
  3. first available QuickShell screen

### 2. State ownership

State is intentionally split by authority:

- daemon-owned:
  - active worktree/context
  - window/runtime snapshot
  - AI session list and current-session selection
  - launch/session/window actions
  - display layout snapshot and layout apply/cycle

- QuickShell-owned:
  - panel visibility
  - docked vs floating mode
  - transient selected-session state used for UI focus

Important declarative note:
- we briefly experimented with QuickShell `FileView` / `JsonAdapter` persistence for panel state
- that created machine-local drift and violated the principle that identical config should converge to identical behavior
- the intended steady state is config-driven shell behavior, not local persisted UI state

### 3. Dashboard flow

Current shell process model:
- QuickShell runs one long-lived `Process`
- that process executes:
  - `i3pm dashboard watch --interval 5000`

Current CLI/daemon model:
- `i3pm dashboard watch` performs an initial snapshot fetch
- then subscribes to daemon `state_changed` notifications
- then refetches only on invalidation events
- a slower heartbeat remains as a fallback recovery path

This replaced the earlier fixed polling loop:
- old behavior: `i3pm dashboard watch --interval 750`
- new behavior: event-driven invalidation with 5s fallback heartbeat

### 4. Display flow

The shell uses the daemon as the mutation authority for display/layout actions.

Current daemon display methods:
- `display.snapshot`
- `display.apply`
- `display.cycle`

Current user entrypoints:
- shell layout-cycle button
- `cycle-display-layout`
- `i3pm display cycle`
- Walker monitor/layout picker
- compatibility wrappers:
  - `set-monitor-profile`
  - `cycle-monitor-profile`
  - `monitor-profile-menu`

Those older wrapper scripts now defer to daemon-backed display actions when available.

## AI Session Improvements

### Reliability

The daemon now invalidates session state when OTEL-derived runtime files change:
- local sessions file:
  - `$XDG_RUNTIME_DIR/otel-ai-sessions.json`
- remote sink file:
  - `$XDG_RUNTIME_DIR/eww-monitoring-panel/remote-otel-sink.json`

This means the shell no longer depends only on sway/window events to notice AI session updates.

### Performance

The dashboard path previously duplicated expensive work:
- `_dashboard_snapshot()` called `_runtime_snapshot()`
- `_session_list()` also called `_runtime_snapshot()`

That was reduced so the runtime snapshot is computed once per dashboard build and then reused for session normalization.

The daemon also now tracks:
- `snapshot_version`
- `session_generation`
- `display_generation`

These are included in both invalidation notifications and dashboard payloads.

### Efficiency

Worktree/dashboard submodels were given lightweight caching and explicit invalidation rather than being rebuilt on every shell tick.

## Multi-Monitor Strategy

### Historical approach

Historically, multi-monitor behavior depended on:
- `monitor-profile.current`
- `output-states.json`
- Eww-specific monitor widgets and scripts
- profile menus and shell wrappers

That model worked, but it mixed:
- runtime UI concerns
- file-based mutation state
- daemon logic
- Eww-specific assumptions

### Current QuickShell direction

The intended runtime model is:
- QuickShell owns screen-aware rendering
- i3pm daemon owns display/layout mutation
- host Nix config defines preferred primary outputs
- compatibility scripts remain only as thin adapters

Current host configuration:
- `thinkpad`
  - `primaryOutputs = [ "eDP-1" "HDMI-A-1" "DP-1" "DP-2" ]`
- `ryzen`
  - `primaryOutputs = [ "DP-1" "HDMI-A-1" "DP-2" "DP-3" ]`

## Issues Encountered

### 1. Home Manager / system generation mismatch on `ryzen`

Observed issue:
- the repository was updated
- the new QuickShell store output existed
- but `~/.config/quickshell/i3pm-shell/*.qml` still pointed at an older Home Manager generation
- restarting the user service alone kept launching the old shell config

Symptoms:
- bars only appeared on one monitor
- QuickShell still launched old config paths
- child process still used `dashboard watch --interval 750`

Root cause:
- `ryzen` had not actually switched to the newest system generation during the first rebuild attempt
- the system-level `home-manager-vpittamp.service` was still activating an older HM generation

How it was verified:
- compare active system:
  - `readlink -f /run/current-system`
- compare activated HM generation:
  - `systemctl status home-manager-vpittamp.service`
- compare live QuickShell links:
  - `readlink -f ~/.config/quickshell/i3pm-shell/ShellConfig.qml`
- compare running QuickShell config path:
  - `journalctl --user -u quickshell-runtime-shell`

Corrective action:
- rerun `sudo nixos-rebuild switch --flake .#ryzen`
- ensure the machine lands on the new system generation
- ensure `home-manager-vpittamp.service` is restarted by the switch
- then restart `quickshell-runtime-shell` once so it reads the new linked config

Operational lesson:
- if QuickShell behavior on one host does not match source, verify generation convergence before debugging QML

### 2. Local UI persistence was a bad fit for declarative parity

Observed issue:
- persistent panel state can make two machines with identical config present different UI state

Conclusion:
- shell-local persistence is acceptable only for explicitly non-declarative preferences
- the default architecture should remain declarative and reproducible

### 3. Dashboard stream parse failures

Observed logs included:
- broken pipe
- JSON parse failures
- reconnect messages from `dashboard watch`

Interpretation:
- the event-driven watch path is an improvement over constant polling, but the stream/reconnect behavior still needs hardening
- the shell currently tolerates restart/reconnect, but malformed or truncated payload handling should be tightened further

## Operational Commands

### Verify current shell generation

```bash
readlink -f ~/.config/quickshell/i3pm-shell/shell.qml
readlink -f ~/.config/quickshell/i3pm-shell/ShellConfig.qml
journalctl --user -u quickshell-runtime-shell -n 50 --no-pager
```

### Verify daemon/dashboard state

```bash
i3pm daemon ping
i3pm dashboard snapshot | jq
i3pm display snapshot | jq
```

### Restart runtime path cleanly

```bash
systemctl --user restart i3-project-daemon.service
systemctl --user restart quickshell-runtime-shell.service
```

### Verify host convergence after rebuild

```bash
readlink -f /run/current-system
systemctl status home-manager-vpittamp.service --no-pager -l
git -C ~/repos/vpittamp/nixos-config/main rev-parse HEAD
```

## Known Gaps

- The historical monitor-profile and `output-states.json` subsystem still exists as a compatibility layer.
- The shell now renders per-monitor bars, but deeper display-layout unification is still incomplete.
- Dashboard stream error handling still needs another pass.
- A live automated QuickShell multi-monitor smoke test does not yet exist.

## Design Rules Going Forward

- identical Nix config should converge to identical activated state on `thinkpad` and `ryzen`
- QuickShell should use native screen/output primitives for rendering, not custom file-derived monitor mappings
- the daemon should remain the authority for state mutation
- legacy monitor/profile wrappers should only remain as adapters, not parallel state owners
- machine-local persisted UI state should be treated as suspect unless there is a strong reason to keep it
