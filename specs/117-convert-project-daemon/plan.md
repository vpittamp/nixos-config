# Implementation Plan: Convert i3pm Project Daemon to User-Level Service

**Branch**: `117-convert-project-daemon` | **Date**: 2025-12-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/117-convert-project-daemon/spec.md`

## Summary

Convert the i3pm project daemon from a system-level systemd service to a user-level home-manager service. This eliminates the need for the 55-line socket discovery wrapper by inheriting session environment variables directly (SWAYSOCK, WAYLAND_DISPLAY, XDG_RUNTIME_DIR), enables proper lifecycle binding with graphical-session.target, and updates 18+ daemon clients to use the new socket path at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`.

## Technical Context

**Language/Version**: Nix (NixOS 25.11), Python 3.11+ (daemon), Bash 5.0+ (scripts), TypeScript/Deno 1.40+ (CLI)
**Primary Dependencies**: home-manager (user service definition), systemd (socket activation), i3ipc.aio (Sway IPC), Pydantic (data validation)
**Storage**: Socket file at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`, JSON config files in `~/.config/i3/`
**Testing**: Manual verification via systemctl --user, journalctl logs, i3pm daemon status
**Target Platform**: NixOS with Sway/Wayland (Hetzner, M1, Ryzen)
**Project Type**: Configuration refactor (Nix modules, shell scripts, socket path updates)
**Performance Goals**: Daemon starts within 5 seconds of graphical session, project switch <200ms (unchanged)
**Constraints**: Backward compatibility during transition (fallback to system socket), no IPC protocol changes
**Scale/Scope**: 18+ files requiring socket path updates, 3 configuration targets (Hetzner, M1, Ryzen)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | Converting from modules/services to home-modules maintains modularity |
| II. Reference Implementation Flexibility | PASS | Hetzner-sway remains reference, user services align with eww-* pattern |
| III. Test-Before-Apply | PASS | Will use dry-build before switch |
| IV. Override Priority Discipline | PASS | Using standard home-manager patterns |
| V. Platform Flexibility | PASS | User service works on all graphical platforms |
| VI. Declarative Configuration | PASS | All changes via Nix expressions |
| X. Python Standards | PASS | Python daemon unchanged, only service wrapper changes |
| XI. i3 IPC Alignment | PASS | Daemon still uses i3ipc.aio as authoritative source |
| XII. Forward-Only Development | PASS | Removing daemonWrapper entirely, not preserving legacy code |

## Project Structure

### Documentation (this feature)

```text
specs/117-convert-project-daemon/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (minimal - config changes only)
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (N/A - no API changes)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Primary conversion (system → user service)
modules/services/i3-project-daemon.nix          # TO BE REMOVED
home-modules/services/i3-project-daemon.nix     # NEW - user service definition

# Configuration targets (service enablement)
configurations/hetzner.nix      # Update service enablement
configurations/thinkpad.nix     # Update service enablement (if applicable)
configurations/ryzen.nix        # Update service enablement

# Socket path updates (18+ files)
home-modules/tools/app-launcher.nix
home-modules/tools/i3_project_monitor/daemon_client.py
home-modules/tools/scripts/i3pm-workspace-mode.sh
home-modules/desktop/eww-monitoring-panel.nix
home-modules/tools/sway-workspace-panel/daemon_client.py
home-modules/tools/sway-workspace-panel/workspace_panel.py
home-modules/tools/sway-workspace-panel/workspace-preview-daemon
home-modules/tools/i3pm/src/services/daemon-client.ts
home-modules/tools/i3pm/src/utils/socket.ts
home-modules/desktop/i3bar/workspace_mode_block.py
home-modules/tools/i3pm-diagnostic/i3pm_diagnostic_pkg/i3pm_diagnostic/__main__.py
home-modules/desktop/swaybar/blocks/system.py
home-modules/tools/i3_project_manager/cli/monitoring_data.py
home-modules/tools/i3_project_manager/core/daemon_client.py
```

**Structure Decision**: This is a configuration refactor, not a new application. Changes are distributed across existing Nix modules and daemon client files. The new user service module follows the same pattern as existing user services (eww-monitoring-panel, eww-top-bar, elephant).

## Complexity Tracking

> No violations - this simplifies the architecture by removing the daemonWrapper complexity.

| Simplification | Benefit |
|----------------|---------|
| Remove daemonWrapper (55 lines) | No socket discovery logic needed |
| Direct environment inheritance | SWAYSOCK, WAYLAND_DISPLAY, XDG_RUNTIME_DIR available natively |
| PartOf=graphical-session.target | Daemon lifecycle matches session lifecycle |
| Consistent with other user services | Follows eww-*, elephant patterns |

---

## Phase 0: Research (Complete)

**Output**: [research.md](./research.md)

Key decisions:
1. **Socket activation**: Removed - daemon creates its own socket
2. **Socket path resolution**: User socket first, system socket fallback
3. **Service type**: `Type=notify` with sd_notify (preserves watchdog)
4. **Directory creation**: `ExecStartPre` with `mkdir -p %t/i3-project-daemon`

---

## Phase 1: Design (Complete)

**Outputs**:
- [data-model.md](./data-model.md) - Socket path migration details
- [quickstart.md](./quickstart.md) - User documentation
- [contracts/README.md](./contracts/README.md) - Socket path contract (no API changes)

### Post-Design Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | New home-modules/services/i3-project-daemon.nix follows existing patterns |
| II. Reference Implementation | PASS | Follows eww-monitoring-panel, eww-top-bar patterns |
| III. Test-Before-Apply | PASS | Plan includes dry-build verification |
| IV. Override Priority | PASS | Standard home-manager option patterns |
| V. Platform Flexibility | PASS | Works on all graphical targets (Hetzner, M1, Ryzen) |
| VI. Declarative Config | PASS | All config via Nix expressions |
| X. Python Standards | PASS | No Python code changes to daemon itself |
| XI. i3 IPC Alignment | PASS | Socket path is transport, IPC protocol unchanged |
| XII. Forward-Only | PASS | System service removed, not maintained |

### Implementation Phases

**Phase 1: Create user service module**
- Create `home-modules/services/i3-project-daemon.nix`
- Follow eww-monitoring-panel pattern for service structure
- Direct Python invocation (no wrapper)
- ExecStartPre for directory creation

**Phase 2: Update daemon clients (18+ files)**
- Python: Update `get_default_socket_path()` with new priority
- Bash: Update socket path with XDG_RUNTIME_DIR
- TypeScript: Update `getSocketPath()` function

**Phase 3: Update configuration targets**
- Replace system service enablement with user service
- Remove system service from configurations

**Phase 4: Remove system service module**
- Delete `modules/services/i3-project-daemon.nix`
- Clean up any orphaned references

**Phase 5: Testing and validation**
- dry-build on all targets
- Manual verification of daemon functionality
- Verify socket path resolution

---

## Next Step

Run `/speckit.tasks` to generate the implementation tasks.
