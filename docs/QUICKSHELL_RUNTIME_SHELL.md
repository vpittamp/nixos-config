# QuickShell Runtime Shell

Last updated: 2026-03-13

## Purpose

This document describes the current QuickShell-based runtime shell that replaces the older Eww top bar, workspace bar, and monitoring-panel path.

For the AI session tracking and lifecycle model itself, see:
- `docs/AI_SESSION_SYSTEM.md`

The goals of the QuickShell runtime shell are:
- render one native top bar and one native bottom bar per active monitor
- keep a single AI/session detail panel on the configured primary monitor
- use the i3pm daemon as the authority for context, launch, session, and display mutations
- reduce polling and duplicate work in the AI session dashboard path
- keep host behavior declarative across `thinkpad` and `ryzen`

## Components

- `home-modules/desktop/quickshell-runtime-shell/default.nix`
  - Home Manager module that installs QuickShell, generates `ShellConfig.qml`, wires keybindings/helper scripts, and defines the `quickshell-runtime-shell.service`.
- `home-modules/desktop/quickshell-runtime-shell/shell.qml`
  - QuickShell UI implementation.
  - Owns per-monitor top/bottom bars, the single right-side AI panel, shell-local view state, native system-status modules, and daemon-driven actions.
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

The shell is split into three UI surfaces:
- one `PanelWindow` per screen for the top bar
- one `PanelWindow` per screen for the bottom bar
- one `PanelWindow` for the right-side AI/session panel

Each per-monitor top bar now renders:
- top-level display and monitoring-panel controls
- native QuickShell system status where available:
  - `Bluetooth`
  - `Networking`
  - `SystemClock`
  - `Pipewire`
  - `UPower`
  - `SystemTray`
- a small helper process only for non-native system resources such as memory/load/temperature

Design rule:
- only use native QuickShell services that are also present declaratively on the host
- we explicitly backed out `PowerProfiles` for now because the DBus service was not enabled uniformly and only added runtime warnings/drift

Each per-monitor bottom bar now renders:
- current context + output identity
- workspace chips for that output
- output-local window icons/counts inside those workspace chips
- layout/session controls shared across monitors

The right-side panel is now context-oriented rather than project-group-oriented:
- a `Global` row clears scoped context while leaving shared windows visible
- a recency-sorted worktree switcher comes from `dashboard.worktrees`
- Local / SSH variant actions call daemon-owned `context.ensure`
- the window list only shows the current context plus shared/global windows
- clicking an already-active worktree row focuses an existing visible window in that context instead of reissuing the same switch
- the panel header shows the active mode/host summary and exposes direct `Focus` / `Global` actions for the current context
- the full worktree list now lives behind a compact `Browse` popup so the normal panel state does not spend permanent vertical space on switching UI

Per-monitor bars are instantiated with:
- `Variants { model: Quickshell.screens }`
- `screen: modelData`

The bar uses native QuickShell/i3 integration for workspace rendering:
- `I3.monitorFor(screen)`
- `I3.workspaces`
- `workspace.activate()`

Per-monitor workspace chips are hydrated from daemon dashboard payloads:
- workspace icons/counts come from `dashboard.outputs[*].workspaces[*].windows`
- icons only represent windows that belong to that output/workspace
- hidden/scratchpad-only windows are excluded from the visible workspace summary

The AI panel is intentionally singular:
- it is anchored to the preferred primary output
- it does not follow focus between monitors
- fallback order is:
  1. live Sway/display state marked `primary`
  2. configured `primaryOutputs`
  3. currently focused i3 monitor
  4. first available QuickShell screen

### 2. State ownership

State is intentionally split by authority:

- daemon-owned:
  - active worktree/context
  - window/runtime snapshot
  - AI session list and current-session selection
  - launch/session/window actions
  - display layout snapshot and layout apply/cycle
  - worktree ranking and shell-ready worktree metadata

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
- the dashboard payload includes a shell-oriented `worktrees` list with:
  - `qualified_name`
  - `remote_available`
  - `is_active`
  - `active_execution_mode`
  - `visible_window_count`
  - `scoped_window_count`
  - usage/ranking metadata

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
- top-bar layout pill
- shell layout-cycle button
- `cycle-display-layout`
- `i3pm display cycle`
- Walker monitor/layout picker
- compatibility wrappers:
  - `set-monitor-profile`
  - `cycle-monitor-profile`
  - `monitor-profile-menu`

Those older wrapper scripts now defer to daemon-backed display actions when available.

### 5. Application and workspace registry model

The runtime shell no longer depends on launcher-specific ownership logic.

The declarative application registry now has five explicit partitions in:
- `home-modules/desktop/app-registry-data.nix`

Those are:
- `workspaceOwningApplications`
- `workspaceUtilityApplications`
- `floatingUtilityApplications`
- `nonOwningLaunchables`
- `applications`

Runtime consequences:
- `workspace-assignments.json` is generated only from `workspaceOwningApplications`
- `application-registry.json` is generated from the combined `applications` list
- PWAs are normal registry entries and participate in workspace ownership through the same path as native apps
- `workspaceUtilityApplications` are global management surfaces that intentionally own a dedicated workspace
- `floatingUtilityApplications` are a documented subset of non-owning launchables for tools like search pickers and standalone QuickShell surfaces
- floating utilities intentionally omit `preferred_workspace`, so launcher-visible floating tools open in the current workspace instead of being treated like workspace-owned apps
- scratchpad and floating utilities remain launchable without polluting workspace ownership
- the standalone worktree manager is now a workspace utility on workspace `23`, not a floating utility

### 6. Terminal and SSH launch path

Managed terminal launches are daemon-owned.

Current model:
- scoped terminal launches flow through daemon `launch.open`
- local terminals use the managed project terminal flow
- SSH terminals use `project-terminal-launch.sh`
- remote helper scripts are installed into the user profile so the remote host can resolve them on `PATH`
- remote shell execution uses `bash -c`, not `bash -lc`

Managed project terminal contract:
- every managed terminal launch gets a persisted `launch_id`, `.spec.json`, and `.status.json` under `$XDG_RUNTIME_DIR/i3-project-daemon/launches`
- the canonical tmux session is versioned and must carry `@i3pm_managed=1`, `@i3pm_schema_version`, `@i3pm_context_key`, `@i3pm_terminal_role`, and `@i3pm_tmux_server_key`
- drifted deterministic tmux session names are quarantined by rename, not killed and not silently reused
- launch status advances through explicit states: `queued`, `starting_terminal`, `session_validating`, `waiting_window`, `running`, `reusable_headless`, or `failed`
- `running` requires a healthy managed tmux session plus a bound terminal window
- `reusable_headless` means the canonical managed session is healthy but currently has no attached local window client
- window close reconciles back into the managed session state instead of assuming terminal death from window death alone

Important runtime consequence:
- helper lookup is deterministic across `thinkpad` and `ryzen`
- remote SSH terminal startup no longer depends on login-shell side effects

## AI Session Improvements

### Reliability

The daemon now invalidates session state when OTEL-derived runtime files change:
- local sessions file:
  - `$XDG_RUNTIME_DIR/otel-ai-sessions.json`
- remote sink file:
  - `$XDG_RUNTIME_DIR/eww-monitoring-panel/remote-otel-sink.json`

This means the shell no longer depends only on sway/window events to notice AI session updates.

### Pane-first session model

The active AI session list is now pane-oriented where tmux pane identity exists.

The intended identity boundary is:
- one tracked AI session surface per tmux pane

The dashboard/session payloads now carry pane-oriented fields such as:
- `surface_kind`
- `surface_key`
- tmux session/window/pane identity
- pane/process-tree metrics

This allows:
- separate AI session rows for multiple panes in the same terminal window
- deterministic session focus through daemon `session.focus`
- deterministic remote attach for `remote_bridge_attachable` sessions without requiring a local mirror worktree
- per-session CPU and RSS metrics in QuickShell without guessing from a whole window

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
- top-bar surfaces are created from live `Quickshell.screens`, not hardcoded output windows

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

Current verification path:
- run `i3pm health` after rebuilds
- treat core failures or QuickShell/Home Manager path mismatches as deployment issues before debugging QML

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

### 3. Eww top-bar parity was the wrong goal

Observed issue:
- the old top bar bundled system metrics, overlay menus, device controls, and monitor widgets into one Eww-specific surface
- carrying those features forward verbatim would keep too much polling and too many Eww-era assumptions

Conclusion:
- the QuickShell top bar should use native services first
- Eww-only overlay behaviors should be dropped unless they remain clearly worth the complexity

### 4. Dashboard stream parse failures

Observed logs included:
- broken pipe
- JSON parse failures
- reconnect messages from `dashboard watch`

Interpretation:
- the event-driven watch path is an improvement over constant polling, but the stream/reconnect behavior still needs hardening
- the shell now ignores empty, `null`, `undefined`, and non-JSON lines before attempting to parse dashboard frames
- malformed JSON payloads should still be treated as warnings because they indicate a real watch-path defect

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

### QuickShell development mode with live reload

QuickShell supports live reload during development:
- `Quickshell.watchFiles` watches config files and reloads on save by default
- `Quickshell.reload(hard)` can be used to force a manual reload

In this Nix/Home Manager setup, the normal activated shell points at:
- `~/.config/quickshell/i3pm-shell/shell.qml`
- `~/.config/quickshell/i3pm-shell/ShellConfig.qml`

Those files are usually symlinked into the active Nix store generation, so editing the repository alone does **not** trigger live reload in the running shell.

The practical development-mode workflow is:
- keep the declarative module/service exactly as-is
- temporarily repoint `shell.qml` from the store-backed link to the repository checkout
- let QuickShell auto-reload on file save
- return to the declarative/store-backed path once the iteration is finished

Recommended local workflow:

```bash
CONFIG_DIR="$HOME/.config/quickshell/i3pm-shell"
REPO_DIR="$HOME/repos/vpittamp/nixos-config/main/home-modules/desktop/quickshell-runtime-shell"

rm -f "$CONFIG_DIR/shell.qml"
ln -s "$REPO_DIR/shell.qml" "$CONFIG_DIR/shell.qml"

systemctl --user restart quickshell-runtime-shell.service
```

At that point:
- editing `home-modules/desktop/quickshell-runtime-shell/shell.qml` in the repo should live-reload in the running shell
- `qmlls` support still works because the config directory remains writable

Important limitations:
- `ShellConfig.qml` is generated by Nix in `default.nix`, so changes there still require rebuild unless you also replace that link with a writable/generated development copy
- asset path changes that depend on a rebuilt Nix store output still require rebuild
- this mode is for iterative UI/QML work, not for validating declarative activation behavior

To return to normal declarative mode:

```bash
git -C ~/repos/vpittamp/nixos-config/main checkout -- \
  home-modules/desktop/quickshell-runtime-shell/shell.qml
sudo nixos-rebuild switch --flake ~/repos/vpittamp/nixos-config/main#<target>
```

Or, if you only changed the symlink locally and want Home Manager to restore the managed links:

```bash
sudo nixos-rebuild switch --flake ~/repos/vpittamp/nixos-config/main#<target>
```

Operational note:
- if live reload appears broken, verify the active config path first:

```bash
readlink -f ~/.config/quickshell/i3pm-shell/shell.qml
journalctl --user -u quickshell-runtime-shell -n 50 --no-pager
```

### Verify host convergence after rebuild

```bash
readlink -f /run/current-system
systemctl status home-manager-vpittamp.service --no-pager -l
git -C ~/repos/vpittamp/nixos-config/main rev-parse HEAD
```

## Known Gaps

- The historical monitor-profile and `output-states.json` subsystem still exists as a compatibility layer.
- The shell now renders per-monitor top and bottom bars with output-local workspace icons/counts, but deeper display-layout unification is still incomplete.
- Dashboard stream error handling still needs another pass.
- A live automated QuickShell multi-monitor smoke test does not yet exist.

## Design Rules Going Forward

- identical Nix config should converge to identical activated state on `thinkpad` and `ryzen`
- QuickShell should use native screen/output primitives for rendering, not custom file-derived monitor mappings
- the daemon should remain the authority for state mutation
- legacy monitor/profile wrappers should only remain as adapters, not parallel state owners
- machine-local persisted UI state should be treated as suspect unless there is a strong reason to keep it
