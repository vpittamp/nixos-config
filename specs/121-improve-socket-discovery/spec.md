# Feature Specification: Improve Socket Discovery and Service Reliability

**Feature Branch**: `121-improve-socket-discovery`
**Created**: 2025-12-16
**Status**: Draft
**Input**: User description: "Optional improvements identified during architecture review: standardize service targets, add health endpoint for socket validation, implement stale socket cleanup timer"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Standardize Service Targets (Priority: P1)

As a system administrator, I want all Sway-specific services to use consistent systemd targets so that service lifecycle management is predictable and reliable.

**Why this priority**: Currently, some services use `graphical-session.target` while others use `sway-session.target`. This inconsistency can cause race conditions during startup and makes debugging harder. This is foundational for the other improvements.

**Independent Test**: Can be fully tested by checking all Sway-related services start correctly after reboot with `systemctl --user list-dependencies sway-session.target` and verifying no services fail to start.

**Acceptance Scenarios**:

1. **Given** a fresh system boot with Sway starting, **When** all Sway-specific services are examined, **Then** they should all depend on `sway-session.target` (not `graphical-session.target`)
2. **Given** Sway restarts via `swaymsg reload` or crash recovery, **When** services are restarted, **Then** all services should reconnect within 30 seconds without manual intervention
3. **Given** the service dependency tree, **When** `sway-session.target` is stopped, **Then** all dependent services should stop cleanly without orphaned processes

---

### User Story 2 - Health Endpoint for Socket Validation (Priority: P2)

As a system operator, I want to query socket health status via an IPC endpoint so that I can monitor and diagnose connection issues proactively.

**Why this priority**: Currently, socket validation happens internally but isn't exposed for external monitoring. This would enable better observability and integration with monitoring tools.

**Independent Test**: Can be fully tested by calling `i3pm diagnose socket-health` and receiving a JSON response with socket status, validation time, and any errors.

**Acceptance Scenarios**:

1. **Given** the i3-project-daemon is running with a valid socket connection, **When** `i3pm diagnose socket-health` is called, **Then** return JSON showing `{"status": "healthy", "socket_path": "...", "last_validated": "...", "latency_ms": N}`
2. **Given** the i3-project-daemon has a stale socket connection, **When** `i3pm diagnose socket-health` is called, **Then** return JSON showing `{"status": "stale", "error": "...", "reconnecting": true}`
3. **Given** monitoring panel integration, **When** socket health changes from healthy to stale, **Then** a visual indicator should appear in the eww panel

---

### User Story 3 - Stale Socket Cleanup Timer (Priority: P3)

As a system administrator, I want old/orphaned Sway IPC socket files to be automatically cleaned up so that socket discovery doesn't accidentally connect to stale sockets.

**Why this priority**: While the daemon handles reconnection well, orphaned socket files from crashed Sway sessions can accumulate. This is a nice-to-have optimization that reduces edge cases.

**Independent Test**: Can be fully tested by creating a fake stale socket file, waiting for the cleanup timer, and verifying it gets removed.

**Acceptance Scenarios**:

1. **Given** orphaned `sway-ipc.*.sock` files exist in `/run/user/$UID/`, **When** the cleanup timer runs (every 5 minutes), **Then** socket files without a corresponding Sway process should be removed
2. **Given** a valid Sway IPC socket is in use, **When** the cleanup timer runs, **Then** the active socket should NOT be removed
3. **Given** socket cleanup runs, **When** sockets are removed, **Then** log entries should indicate which sockets were cleaned and why

---

### Edge Cases

- What happens when multiple Sway sessions exist (unlikely but possible)?
  - Discovery should prefer the most recently modified socket
- How does the system handle rapid Sway restarts?
  - Exponential backoff in reconnection should prevent thundering herd
- What if cleanup timer removes a socket just as daemon tries to use it?
  - Daemon should fall back to socket discovery and reconnect

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST use `sway-session.target` as the dependency for all Sway-specific services (i3-project-daemon, eww panels, swaync)
- **FR-002**: System MUST expose socket health status via the existing `i3pm diagnose` CLI interface
- **FR-003**: System MUST provide health status including: connection state, socket path, last validation time, and latency
- **FR-004**: System MUST implement a systemd timer that runs every 5 minutes to check for stale sockets
- **FR-005**: System MUST NOT remove socket files that have an active Sway process
- **FR-006**: System MUST log all socket cleanup actions with socket path and reason for removal
- **FR-007**: Services MUST reconnect automatically within 30 seconds of socket becoming available after Sway restart

### Key Entities

- **Sway IPC Socket**: The Unix domain socket at `/run/user/$UID/sway-ipc.$UID.$PID.sock` used for Sway IPC communication
- **Health Status**: A data structure containing connection state, socket path, validation timestamp, and latency metrics
- **Cleanup Timer**: A systemd timer unit that periodically validates and cleans orphaned socket files

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All Sway-specific services (≥5 services) depend on `sway-session.target` instead of mixed targets
- **SC-002**: `i3pm diagnose socket-health` returns valid JSON response within 100ms
- **SC-003**: After Sway restart, all services reconnect within 30 seconds without manual intervention
- **SC-004**: Stale socket files are cleaned within 10 minutes of the associated Sway process terminating
- **SC-005**: Zero false positives in socket cleanup (active sockets never removed)
