# Feature Specification: Convert i3pm Project Daemon to User-Level Service

**Feature Branch**: `117-convert-project-daemon`
**Created**: 2025-12-14
**Status**: Draft
**Input**: User description: "create a new feature to refactor i3pm project daemon from a system level daemon into a user level daemon"

## Background & Context

The i3pm project daemon (i3-project-event-daemon) manages project-scoped window filtering, workspace persistence, and real-time Sway/i3 IPC event handling. It was converted from a user-level service to a system-level service in Feature 037 based on a **misdiagnosed concern** about namespace isolation preventing `/proc/{pid}/environ` access.

### Original Rationale (Feature 037)
The daemon was moved to a system service due to a belief that user processes couldn't read `/proc/{pid}/environ` of other user processes. This was incorrect - user processes CAN read `/proc/{pid}/environ` of processes owned by the same user.

### Problems with Current System Service Architecture

1. **No Access to Session Environment Variables**: System services don't inherit SWAYSOCK, WAYLAND_DISPLAY, or XDG_RUNTIME_DIR. A complex wrapper script was added to scan `/run/user/{uid}` for socket files.

2. **Socket Lifecycle Mismatch**: When Sway restarts, the daemon keeps running with a stale socket reference. Workarounds were needed:
   - Socket cleanup logic to remove stale sway-ipc sockets by checking if PID exists
   - Mtime-based socket selection to pick the newest socket

3. **No Automatic Session Binding**: System services can't use `PartOf=graphical-session.target` to restart with the user's graphical session.

4. **Unnecessary Complexity**: The socket discovery wrapper (55+ lines) and cleanup logic exist solely to compensate for the unnatural fit of a system service managing user session resources.

5. **Hardcoded Socket Path**: Multiple files (18+) reference `/run/i3-project-daemon/ipc.sock` instead of using XDG_RUNTIME_DIR.

### Benefits of User-Level Service

1. **Direct environment access**: SWAYSOCK, WAYLAND_DISPLAY, XDG_RUNTIME_DIR available natively
2. **Lifecycle alignment**: Restarts automatically with `graphical-session.target`
3. **Simpler code**: No socket discovery wrapper needed
4. **Follows systemd best practices**: User session daemons belong in user services
5. **Consistent with other user services**: eww-monitoring-panel, eww-top-bar, elephant, etc. all run as user services

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Seamless Session Integration (Priority: P1)

When the user logs into their graphical session, the i3pm daemon automatically starts with full access to session environment variables, eliminating manual intervention and socket discovery logic.

**Why this priority**: Core functionality - the daemon must connect to Sway/i3 reliably for all other features to work. This is the foundation that enables project switching, window filtering, and workspace management.

**Independent Test**: Start a new graphical session and verify the daemon starts automatically with correct SWAYSOCK, connects to Sway IPC, and processes events.

**Acceptance Scenarios**:

1. **Given** a fresh login to graphical session, **When** the session starts, **Then** the i3pm daemon starts automatically and connects to Sway within 5 seconds
2. **Given** the daemon is running, **When** checking `journalctl --user -u i3-project-daemon`, **Then** logs show SWAYSOCK environment variable from session (not discovered via wrapper script)
3. **Given** the daemon is running, **When** Sway restarts, **Then** the daemon restarts automatically and reconnects without manual intervention

---

### User Story 2 - Socket Path Migration (Priority: P2)

All client tools and scripts that communicate with the daemon use the new user-level socket path via XDG_RUNTIME_DIR, maintaining backward compatibility during transition.

**Why this priority**: Without socket path migration, existing tools would fail to communicate with the daemon. This enables the ecosystem to function.

**Independent Test**: Run `i3pm project current` and verify it successfully queries the daemon at the new socket location.

**Acceptance Scenarios**:

1. **Given** the user service is running, **When** executing `i3pm project switch nixos`, **Then** the command succeeds using the user-level socket path
2. **Given** the user service is running, **When** the monitoring panel queries daemon state, **Then** it receives window/project data without errors
3. **Given** both old and new socket paths configured, **When** a client attempts connection, **Then** it tries the user socket first, falling back to system socket for compatibility

---

### User Story 3 - Clean Wrapper Removal (Priority: P3)

The complex socket discovery wrapper script is removed, with environment variables inherited naturally from the user session.

**Why this priority**: Technical debt reduction - removes ~55 lines of workaround code that compensates for the system service architecture.

**Independent Test**: Inspect the deployed service unit and verify ExecStart directly invokes the Python daemon without a wrapper script.

**Acceptance Scenarios**:

1. **Given** the refactored service, **When** inspecting `systemctl --user cat i3-project-daemon`, **Then** ExecStart shows direct Python invocation (no wrapper script)
2. **Given** the refactored service, **When** checking daemon logs, **Then** no "Cleaning up stale Sway sockets" messages appear
3. **Given** the service definition, **When** reviewing the Nix module, **Then** the daemonWrapper script is removed and ExecStart uses pythonEnv directly

---

### User Story 4 - Service Dependencies Updated (Priority: P4)

The service configuration properly declares dependencies on graphical session targets, ensuring correct startup ordering and session lifecycle binding.

**Why this priority**: Ensures daemon starts at the right time and restarts appropriately with session changes.

**Independent Test**: Check systemd unit dependencies and verify `PartOf=graphical-session.target` is present.

**Acceptance Scenarios**:

1. **Given** the service unit, **When** checking with `systemctl --user show i3-project-daemon`, **Then** PartOf includes `graphical-session.target`
2. **Given** a running session, **When** the graphical session stops, **Then** the daemon stops automatically
3. **Given** the service unit, **When** checking After= dependencies, **Then** it lists `graphical-session.target`

---

### Edge Cases

- **What happens when** the daemon is already running as a system service during migration?
  - Migration documentation guides user to stop system service before enabling user service
  - System service should be disabled in configuration before rebuild

- **What happens when** multiple sessions exist for the same user?
  - User services run in the first graphical session
  - Subsequent sessions would need separate daemon instances (out of scope for initial implementation)

- **How does the system handle** clients that still reference the old socket path?
  - Daemon clients implement fallback: try user socket first, then system socket
  - Provides transition period for any overlooked references

- **What happens when** the socket file already exists on service start?
  - Socket unit configuration includes `RemoveOnStop=yes`
  - Service ExecStartPre removes any stale socket file

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST run i3pm daemon as a user-level systemd service (not system-level)
- **FR-002**: Service MUST inherit SWAYSOCK, WAYLAND_DISPLAY, and XDG_RUNTIME_DIR from user session
- **FR-003**: Service MUST use socket activation with socket at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
- **FR-004**: Service MUST declare PartOf relationship to `graphical-session.target` for session lifecycle binding
- **FR-005**: All daemon client libraries MUST prefer user socket path (`$XDG_RUNTIME_DIR/...`) over system socket path
- **FR-006**: Daemon clients MUST fall back to system socket path (`/run/i3-project-daemon/ipc.sock`) for backward compatibility during transition
- **FR-007**: System MUST remove the socket discovery wrapper script (`daemonWrapper`)
- **FR-008**: System MUST update the 18+ files that hardcode `/run/i3-project-daemon/ipc.sock` to use configurable paths
- **FR-009**: Service configuration MUST preserve existing functionality: watchdog, resource limits, security hardening
- **FR-010**: Migration MUST include steps to disable the system-level service before enabling user service

### Key Entities

- **Service Unit**: The systemd user service (`i3-project-daemon.service`) and socket (`i3-project-daemon.socket`) definitions
- **Socket Path**: Location of the IPC socket; changes from `/run/i3-project-daemon/ipc.sock` to `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
- **Daemon Clients**: 18+ files/modules that communicate with the daemon via IPC socket
- **Session Environment**: SWAYSOCK, WAYLAND_DISPLAY, XDG_RUNTIME_DIR variables provided by graphical session

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Daemon starts and connects to Sway within 5 seconds of graphical session start
- **SC-002**: Zero instances of socket discovery wrapper code remain in the codebase after migration
- **SC-003**: All 18+ daemon client references updated to support user socket path
- **SC-004**: Daemon automatically restarts when Sway/graphical session restarts (no manual intervention required)
- **SC-005**: Project switching operations complete within the same time bounds as before migration (<200ms for typical workloads)
- **SC-006**: Memory and CPU usage remain within existing limits (100M max memory, 50% CPU quota)
- **SC-007**: All existing integration tests pass with user-level service
- **SC-008**: Migration documentation enables users to transition without data loss or service disruption

## Files Requiring Modification

The following files reference `/run/i3-project-daemon` or related system service configuration:

### Primary Changes (Service Definition)
1. `modules/services/i3-project-daemon.nix` - Convert from systemd.services to home-manager user service

### Socket Path References (18+ files)
2. `home-modules/tools/app-launcher.nix` - daemonSocketPath constant
3. `home-modules/tools/i3_project_monitor/daemon_client.py` - system_socket path
4. `home-modules/tools/scripts/i3pm-workspace-mode.sh` - SOCK variable
5. `home-modules/desktop/eww-monitoring-panel.nix` - I3PM_DAEMON_SOCKET and hardcoded paths (5 locations)
6. `home-modules/tools/sway-workspace-panel/daemon_client.py` - DAEMON_IPC_SOCKET
7. `home-modules/tools/sway-workspace-panel/workspace_panel.py` - _daemon_ipc_socket
8. `home-modules/tools/sway-workspace-panel/workspace-preview-daemon` - DAEMON_IPC_SOCKET
9. `home-modules/tools/i3pm/src/services/daemon-client.ts` - socketPath default
10. `home-modules/tools/i3pm/src/utils/socket.ts` - getI3pmSocketPath function
11. `home-modules/desktop/i3bar/workspace_mode_block.py` - DAEMON_SOCKET
12. `home-modules/tools/i3pm-diagnostic/i3pm_diagnostic_pkg/i3pm_diagnostic/__main__.py` - socket_path default
13. `home-modules/desktop/swaybar/blocks/system.py` - socket_path
14. `home-modules/tools/i3_project_manager/cli/monitoring_data.py` - I3PM_DAEMON_SOCKET (2 locations)
15. `home-modules/tools/i3_project_manager/core/daemon_client.py` - system_socket path

### Configuration Files
16. `configurations/hetzner.nix` - service enablement
17. `configurations/thinkpad.nix` - service enablement
18. `configurations/ryzen.nix` - service enablement

## Assumptions

1. **Single graphical session per user**: The user runs one graphical session. Multi-session scenarios are out of scope.
2. **Home-manager available**: The target systems use home-manager for user service management.
3. **XDG_RUNTIME_DIR standard**: All target systems provide XDG_RUNTIME_DIR (standard on NixOS with systemd).
4. **Backward compatibility period**: A transition period where both socket paths are supported allows gradual migration.
5. **No breaking changes to IPC protocol**: The JSON-RPC protocol over the socket remains unchanged; only the socket location changes.
