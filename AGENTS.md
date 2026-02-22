# Window Management System Summary (Sway + i3pm)

Last updated: 2026-02-22

## Objective

Provide reliable project-scoped window management on Sway with:
- deterministic project/worktree context switching
- local vs SSH execution context awareness
- per-context scratchpad terminal behavior
- workspace/output reassignment and monitoring
- stable daemon-backed CLI operations

## Core Components

- `home-modules/desktop/i3-project-event-daemon/`
  - Python user-session daemon listening to Sway IPC and serving JSON-RPC.
  - Owns project/window state, filtering, monitor/profile logic, scratchpad lifecycle, launch registry, and event buffer.
- `home-modules/tools/i3pm/`
  - Deno CLI (`i3pm`) that talks to daemon over Unix socket:
    - default socket: `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
  - Commands: `worktree`, `project`, `scratchpad`, `windows`, `daemon`, `monitors`, etc.
- `home-modules/services/i3-project-daemon.nix`
  - Home-manager user service definition (`i3-project-daemon.service`) with Sway-bound lifecycle.
- `home-modules/tools/sway-tree-monitor/`
  - Separate tree-diff monitor service for detailed tree events (`sway-tree-monitor.service`).

## State + Identity Model

- Active context is persisted in `~/.config/i3/active-worktree.json`.
- Context identity is explicit and mode-aware:
  - `execution_mode`: `local` or `ssh`
  - `connection_key`: e.g. `local@thinkpad`, `vpittamp@ryzen:22`
  - `context_key`: `<qualified_worktree>::<mode>::<connection>`
- Scratchpad terminals are keyed by `context_key`, not only project name.
  - This allows independent local and SSH scratchpad terminals for the same worktree.

## Project/Worktree Switching Flow

1. `i3pm worktree switch ...` calls daemon `worktree.switch`.
2. Daemon resolves target worktree + optional remote profile.
3. Active context is updated (`active-worktree.json`).
4. Window filtering/reassignment runs using project + context identity.
5. Subsequent launches/scratchpad operations use the active context.

Notes:
- `--local` on switch forces local context even if remote profile exists.
- Remote profiles are read from `~/.config/i3/worktree-remote-profiles.json`.

## Scratchpad Flow

- CLI routes to daemon methods:
  - `scratchpad.toggle`
  - `scratchpad.launch`
  - `scratchpad.status`
  - `scratchpad.close`
  - `scratchpad.cleanup`
- Daemon launches terminal via Sway with I3PM env vars and marks it as scoped scratchpad terminal.
- Toggle behavior:
  - launch if missing for active context
  - show if hidden
  - hide if visible
- Status returns per-context terminal metadata (pid, window_id, state, working dir, tmux session, etc.).

## Monitor/Profile Management

- Monitor profile files live in `~/.config/sway/monitor-profiles/*.json`.
- Daemon monitor profile loader now supports files without explicit `name`:
  - filename stem is used as profile name fallback.
- This supports existing profile files like:
  - `laptop-only.json`
  - `mirror.json`
  - `extended.json`

## Recent System Updates (this cycle)

- Unified and cleaned i3pm TypeScript surface:
  - full `deno check` pass
  - removed stale/unreferenced legacy modules
  - tightened response typing and command arg normalization
- Fixed daemon CLI reliability:
  - `i3pm daemon status --json` now returns JSON and exits normally
  - status fields aligned with daemon payload (`connected`, `event_count`, `window_count`, etc.)
  - `i3pm daemon ping` now health-checks through `get_status`
  - daemon command exit codes now propagate from CLI entrypoint
- Fixed daemon startup/logging issues:
  - monitor profile load errors removed (name fallback)
  - implemented `AutoRestoreManager` in `layout/auto_restore.py`
  - daemon now initializes auto-restore manager instead of failing import

## Current Behavior Validation

Validated in live Sway session after rebuild/restart:
- `sudo nixos-rebuild switch --flake .#thinkpad`
- `systemctl --user restart i3-project-daemon.service sway-tree-monitor.service`
- `i3pm daemon ping` => healthy
- `i3pm daemon status --json` => valid JSON
- `i3pm worktree switch --local ...` and SSH switch => both work
- `i3pm scratchpad toggle` in local and SSH modes => both work with isolated context keys

## Operational Commands

- Service status:
  - `systemctl --user status i3-project-daemon.service`
  - `systemctl --user status sway-tree-monitor.service`
- Daemon checks:
  - `i3pm daemon ping`
  - `i3pm daemon status`
  - `i3pm daemon status --json`
- Context checks:
  - `cat ~/.config/i3/active-worktree.json`
  - `i3pm worktree switch [--local] <account/repo:branch>`
- Scratchpad checks:
  - `i3pm scratchpad status --json`
  - `i3pm scratchpad toggle --json`

## Known Constraints

- This repository intentionally removed stale legacy i3pm modules; backward compatibility with those deleted internals is not a goal.
- If a regression appears, rollback should use git history/commit rollback rather than preserving old parallel codepaths.
