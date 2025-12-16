# Implementation Plan: Improve Socket Discovery and Service Reliability

**Branch**: `121-improve-socket-discovery` | **Date**: 2025-12-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/121-improve-socket-discovery/spec.md`

## Summary

Standardize systemd service targets, add socket health monitoring, and implement stale socket cleanup to improve reliability of Sway IPC connectivity across all services.

## Technical Context

**Language/Version**: Bash (cleanup script), Python 3.11 (daemon health endpoint), Nix (service configuration)
**Primary Dependencies**: systemd, i3ipc.aio, bash coreutils
**Storage**: N/A (runtime state only)
**Testing**: Manual verification via `systemctl --user`, `i3pm diagnose socket-health`
**Target Platform**: NixOS with Sway compositor (Hetzner reference platform)
**Project Type**: Single (NixOS configuration)
**Performance Goals**: Health endpoint <100ms response, cleanup script <1s execution
**Constraints**: No false positives in socket cleanup, services reconnect within 30s
**Scale/Scope**: 10+ user services, 1 daemon process

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Changes are localized to existing service modules |
| II. Reference Implementation | ✅ PASS | Targets Hetzner Sway reference platform |
| III. Test-Before-Apply | ✅ PASS | Will use `nixos-rebuild dry-build` before applying |
| VI. Declarative Configuration | ✅ PASS | All changes in Nix modules, no imperative scripts |
| X. Python Development Standards | ✅ PASS | Health endpoint follows async patterns |
| XI. i3 IPC Alignment | ✅ PASS | Uses Sway IPC as authoritative source |
| XII. Forward-Only Development | ✅ PASS | No backwards compatibility needed |

## Project Structure

### Documentation (this feature)

```text
specs/121-improve-socket-discovery/
├── plan.md              # This file
├── research.md          # Phase 0 output - completed
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (N/A - no API contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
home-modules/
├── services/
│   └── i3-project-daemon.nix      # Update target → sway-session.target, add health IPC
├── desktop/
│   ├── eww-monitoring-panel.nix   # Update target → sway-session.target
│   ├── sway-config-manager.nix    # Update target → sway-session.target
│   ├── i3wsr.nix                  # Update target → sway-session.target
│   └── i3-project-event-daemon/
│       ├── ipc_handler.py         # Add get_socket_health message handler
│       └── connection.py          # Add health status export method
└── tools/
    └── sway-socket-cleanup/       # New: cleanup timer + script
        └── default.nix
```

**Structure Decision**: Modifications to existing modules in `home-modules/services/` and `home-modules/desktop/`. New cleanup timer module in `home-modules/tools/`.

## Implementation Phases

### Phase 1: Target Standardization (P1 - Highest Priority)

Migrate Sway-specific services from `graphical-session.target` to `sway-session.target`:

1. **i3-project-daemon.nix** (lines 109-178)
   - Change `After`, `PartOf`, `WantedBy` from `graphical-session.target` to `sway-session.target`

2. **eww-monitoring-panel.nix** (lines 12981-13008)
   - Change `After`, `PartOf`, `WantedBy` from `graphical-session.target` to `sway-session.target`

3. **sway-config-manager.nix** (lines 327-391)
   - Change `After`, `PartOf`, `WantedBy` from `graphical-session.target` to `sway-session.target`

4. **i3wsr.nix** (lines 159-171)
   - Change `After`, `PartOf`, `WantedBy` from `graphical-session.target` to `sway-session.target`

**Verification**: `systemctl --user list-dependencies sway-session.target` should show all migrated services.

### Phase 2: Health Endpoint (P2)

Add socket health status to daemon IPC:

1. **connection.py**: Add `get_health_status()` method returning:
   ```python
   {
       "status": "healthy" | "stale" | "disconnected",
       "socket_path": "/run/user/1000/sway-ipc.1000.12345.sock",
       "last_validated": "2025-12-16T10:30:00Z",
       "latency_ms": 5,
       "reconnection_count": 0,
       "uptime_seconds": 3600
   }
   ```

2. **ipc_handler.py**: Add `get_socket_health` message type handler

3. **i3pm CLI**: Add `diagnose socket-health` subcommand (if not already present)

### Phase 3: Stale Socket Cleanup Timer (P3)

Create new module `home-modules/tools/sway-socket-cleanup/default.nix`:

1. **Cleanup script**: Iterate sway-ipc.*.sock files, validate PID, remove orphans
2. **Systemd timer**: Run every 5 minutes via OnUnitActiveSec
3. **Logging**: Journal output for removed sockets

## Complexity Tracking

> No violations requiring justification - all changes are minimal and focused.

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Single cleanup mechanism | Timer-based | Simpler than inotify, sufficient for 5-min granularity |
| Health via daemon IPC | Reuse existing socket | No new dependencies, consistent with architecture |
| 4 services migrated | Sway-specific only | Keep generic services on graphical-session.target |
