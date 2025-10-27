# Feature Specification: IPC Launch Context for Multi-Instance App Tracking

**Feature Branch**: `041-ipc-launch-context`
**Created**: 2025-10-27
**Status**: Draft
**Input**: User description: "create a new feature for ipc launch context. don't worry about backwards compatibility. we want to replace the current logic if it doesn't align with ipc launch context approach. we also don't want any fallbacks so that we can test when the process works and when it fails. create thorough tests and make sure it works across scenarios."

## Overview

This feature implements a launch notification system where the application launcher notifies the window manager daemon immediately before launching applications. The daemon maintains a registry of pending launches and correlates new windows to their originating launch events using multiple signals (application class, timing, workspace location). This replaces the current process environment-based tracking which fails for multi-instance applications like VS Code that share a single process across multiple windows.

## User Scenarios & Testing

### User Story 1 - Sequential Application Launches (Priority: P1)

A user switches to the "nixos" project context and launches VS Code, works for a while, then switches to the "stacks" project context and launches VS Code again. The system correctly assigns each VS Code window to its respective project based on launch context rather than process environment.

**Why this priority**: This is the core functionality - correctly tracking which window belongs to which project for applications launched sequentially. This represents 90% of normal user workflow.

**Independent Test**: Can be fully tested by launching two instances of VS Code with different project contexts 2+ seconds apart and verifying each window receives the correct project assignment. Delivers immediate value by solving the multi-instance tracking problem.

**Acceptance Scenarios**:

1. **Given** active project is "nixos", **When** user launches VS Code via launcher, **Then** daemon records pending launch for vscode+nixos and new window gets marked with project "nixos"
2. **Given** user switches active project to "stacks", **When** user launches VS Code via launcher, **Then** daemon records pending launch for vscode+stacks and new window gets marked with project "stacks" (not "nixos" from shared process)
3. **Given** two VS Code windows exist with different project marks, **When** user switches project context, **Then** only windows matching the active project remain visible, others hide to scratchpad

---

### User Story 2 - Rapid Application Launches (Priority: P2)

A user rapidly launches multiple application windows in quick succession (within 0.5 seconds) from different project contexts. The system correctly disambiguates which window corresponds to which launch using correlation signals like workspace assignment and temporal ordering.

**Why this priority**: Handles power-user workflows where multiple windows are launched rapidly. Less common than sequential launches but critical for reliability and user confidence in the system.

**Independent Test**: Can be tested independently by launching VS Code for "nixos" and "stacks" within 0.2 seconds of each other, then verifying both windows receive correct project assignments. Demonstrates robust correlation algorithm.

**Acceptance Scenarios**:

1. **Given** active project is "nixos", **When** user launches VS Code, immediately switches to "stacks", and launches VS Code again within 0.2s, **Then** both windows appear and each is marked with its respective launch project (first=nixos, second=stacks)
2. **Given** multiple pending launches exist, **When** a new window appears, **Then** daemon matches it to the most likely launch based on application class, timestamp proximity (within 5 seconds), and workspace location
3. **Given** two identical application launches 0.1s apart, **When** windows appear in reverse order, **Then** daemon uses first-match-wins strategy to assign projects correctly

---

### User Story 3 - Launch Timeout Handling (Priority: P2)

A user launches an application but the window takes longer than expected to appear (>5 seconds due to system load). The system expires the pending launch and the window assignment fails clearly, allowing diagnosis rather than silent incorrect assignment.

**Why this priority**: Ensures system fails explicitly rather than silently when correlation fails, making debugging and reliability validation possible. Critical for testing phase.

**Independent Test**: Can be tested by launching an application, artificially delaying window creation beyond 5 seconds, and verifying the pending launch expires and the window is not assigned to any project.

**Acceptance Scenarios**:

1. **Given** pending launch exists, **When** 5 seconds elapse without matching window, **Then** pending launch is removed from registry and logged as expired
2. **Given** pending launch has expired, **When** window finally appears, **Then** window receives no project assignment and error is logged indicating correlation failure
3. **Given** expired launch, **When** user checks system status, **Then** daemon reports statistics showing expired launches for debugging

---

### User Story 4 - Multiple Application Types (Priority: P3)

A user launches different application types (VS Code, terminal, browser) simultaneously from different project contexts. The system correctly matches each window to its launch based on application class matching, regardless of timing.

**Why this priority**: Validates that correlation works across different application types, not just VS Code. Lower priority because the correlation algorithm naturally handles this, but important for comprehensive testing.

**Independent Test**: Can be tested by launching VS Code for "nixos" and Alacritty terminal for "stacks" within 0.1s of each other, then verifying each window matches its correct project based on application class.

**Acceptance Scenarios**:

1. **Given** user launches VS Code for "nixos" and terminal for "stacks" simultaneously, **When** both windows appear, **Then** VS Code window gets nixos mark and terminal gets stacks mark based on class matching
2. **Given** pending launches for multiple app types exist, **When** a terminal window appears, **Then** it only matches against terminal launches, not VS Code launches
3. **Given** mixed application launches, **When** windows appear in any order, **Then** each matches its correct launch regardless of sequence

---

### User Story 5 - Workspace-Based Disambiguation (Priority: P3)

A user launches applications that appear on specific workspaces as configured in the application registry. The system uses workspace location as an additional correlation signal to improve matching confidence when multiple launches of the same app type exist.

**Why this priority**: Workspace matching provides additional correlation signal for disambiguation, but is optional - timing and class are sufficient for most cases. Included for completeness.

**Independent Test**: Can be tested by configuring VS Code to always open on workspace 2, launching two instances, and verifying workspace location increases correlation confidence for the correct match.

**Acceptance Scenarios**:

1. **Given** VS Code configured to open on workspace 2, **When** user launches VS Code and window appears on workspace 2, **Then** correlation confidence increases for launches targeting workspace 2
2. **Given** two VS Code launches 0.5s apart, **When** first window appears on workspace 2, **Then** it matches the first launch with HIGH confidence due to workspace+timing alignment
3. **Given** window appears on unexpected workspace, **When** correlation runs, **Then** workspace mismatch reduces confidence but doesn't prevent matching if other signals align

---

### Edge Cases

- What happens when user launches application directly from terminal (bypassing launcher wrapper)?
  - Pending launch is never created, window appears without launch context
  - System has no correlation data, window receives no project assignment
  - Error logged indicating window appeared without launch notification

- What happens when two identical applications are launched <0.1 seconds apart?
  - Both launches recorded with distinct timestamps
  - First window matches first launch (FIFO ordering)
  - Second window matches remaining launch
  - If windows appear in reverse order, first-appearing window still matches oldest unmatched launch

- What happens when system is under heavy load and window creation is delayed?
  - Pending launches remain valid for 5 seconds
  - If window appears after 5s, launch has expired
  - Window receives no project assignment and error is logged
  - User can diagnose via daemon statistics showing expired launches

- What happens when an application spawns multiple windows from single launch?
  - Only first window matches the pending launch
  - Subsequent windows from same process have no launch context
  - System explicitly does not handle multi-window-per-launch (out of scope)

- What happens when daemon restarts while pending launches exist?
  - Pending launches are in-memory only, lost on restart
  - Next window appearances have no launch context to match against
  - System recovers gracefully - future launches work normally

- What happens when user launches same app multiple times before any windows appear?
  - Multiple pending launches accumulate in registry
  - Each window matches in FIFO order (oldest launch first)
  - All matches complete within 5-second window

- What happens when workspace configuration changes mid-launch?
  - Launch records workspace at notification time
  - Window workspace checked at appearance time
  - Mismatch reduces confidence but doesn't prevent matching

- What happens when application class doesn't match expected class in registry?
  - Window cannot match any pending launches (class is required signal)
  - Window receives no project assignment
  - Error logged indicating unexpected window class

## Requirements

### Functional Requirements

- **FR-001**: Launcher wrapper MUST send launch notification to daemon immediately before executing application command
- **FR-002**: Launch notification MUST include: application name, project name, project directory, launcher process ID, target workspace number, and timestamp
- **FR-003**: Daemon MUST maintain registry of pending launches with 5-second expiration window
- **FR-004**: Daemon MUST remove expired launches (age > 5 seconds) from registry automatically
- **FR-005**: Daemon MUST correlate new window events to pending launches using application class matching as required baseline
- **FR-006**: Daemon MUST calculate correlation confidence using multiple signals: application class (required), time delta (<5s required, <1s = high confidence), workspace match (optional boost)
- **FR-007**: Daemon MUST assign window to project only when correlation confidence meets minimum threshold (MEDIUM or higher)
- **FR-008**: System MUST NOT use fallback mechanisms (no title parsing, no process environment reading, no active project default)
- **FR-009**: System MUST log correlation failures explicitly when window appears without matching launch
- **FR-010**: System MUST mark matched launch as consumed to prevent duplicate matching
- **FR-011**: System MUST use first-match-wins strategy when multiple valid matches exist
- **FR-012**: Daemon MUST provide statistics API reporting: pending launches count, matched launches count, expired launches count, failed correlations count
- **FR-013**: System MUST support CLI command for manual launch notification (for testing and debugging)
- **FR-014**: System MUST clean up pending launches older than 5 seconds on each new launch notification
- **FR-015**: Correlation confidence levels MUST be: EXACT (1.0), HIGH (0.8), MEDIUM (0.6), LOW (0.3), NONE (0.0)
- **FR-016**: MEDIUM confidence threshold (0.6) MUST require: app class match + time delta <5s
- **FR-017**: HIGH confidence threshold (0.8) MUST require: app class match + time delta <2s + workspace match
- **FR-018**: System MUST reject matches with confidence below MEDIUM (0.6)

### Key Entities

- **Launch Notification**: Represents an imminent application launch
  - Attributes: app_name, project_name, project_directory, launcher_pid, workspace_number, timestamp, matched_flag
  - Lifecycle: Created on notification → Matched to window → Removed after 5s if unmatched
  - Relationships: One-to-one with Window (if matched within timeout)

- **Window Info**: Represents a newly created window requiring correlation
  - Attributes: window_id, window_class, window_pid, workspace_number, creation_timestamp
  - Relationships: One-to-one with Launch Notification (if correlation succeeds)

- **Correlation Result**: Outcome of matching window to launch
  - Attributes: project_name (if matched), confidence_level, match_signals_used
  - Used for: Project assignment and diagnostics

- **Launch Registry**: In-memory collection of pending launches
  - Operations: Add, Remove, Match, Cleanup, GetStats
  - Constraints: 5-second timeout, first-match-wins, no duplicates

## Success Criteria

### Measurable Outcomes

- **SC-001**: Sequential application launches (>2s apart) achieve 100% correct project assignment with HIGH confidence (0.8+)
- **SC-002**: Rapid application launches (<0.5s apart) achieve 95% correct project assignment with MEDIUM or HIGH confidence
- **SC-003**: Window-to-launch correlation completes in under 100ms for 95% of launches
- **SC-004**: System handles 10 simultaneous pending launches without degradation
- **SC-005**: Launch timeout mechanism expires pending launches within 5±0.5 seconds with 100% accuracy
- **SC-006**: Correlation failure rate is <1% for launches where window appears within 5 seconds
- **SC-007**: All correlation failures are explicitly logged with detailed signal information for debugging
- **SC-008**: Daemon maintains correlation statistics with <5MB memory overhead
- **SC-009**: System operates with zero fallback mechanism usage (100% pure IPC correlation)
- **SC-010**: Test suite achieves 100% coverage of edge cases defined in specification

### Performance Targets

- Correlation algorithm execution time: <10ms per window
- Pending launch registry size: <1000 entries (auto-cleanup prevents unbounded growth)
- Memory per pending launch: <200 bytes
- Statistics query response time: <5ms

## Assumptions

1. **Application Class Stability**: Window class names are stable and match registry definitions (e.g., VS Code always reports class "Code")
2. **Launcher Wrapper Usage**: All application launches go through the wrapper that sends launch notifications (direct terminal launches explicitly unsupported in testing phase)
3. **Single Window Per Launch**: Each launch produces exactly one window (multi-window applications like browsers are out of scope)
4. **Workspace Assignment**: Application registry correctly specifies target workspaces for workspace-based correlation
5. **Daemon Availability**: Daemon is running and IPC is functional when launches occur (no offline queueing)
6. **5-Second Window Sufficient**: All applications create windows within 5 seconds of launch under normal system load
7. **Clock Synchronization**: System clock provides monotonic timestamps for correlation timing
8. **No Concurrent Launches**: Application launcher serializes launches (systemd-run completes before next launch)

## Out of Scope

- Backward compatibility with existing title-based detection or process environment tracking
- Fallback mechanisms for correlation failures (explicit failure is desired for testing)
- Multi-window-per-launch handling (e.g., browser opening multiple tabs)
- Manual window project reassignment (user cannot override incorrect assignments)
- Persistent launch history across daemon restarts
- Launch notification queueing when daemon is unavailable
- PID tree correlation (checking if window PID is child of launcher PID)
- Correlation for applications launched outside wrapper (terminal, file manager, etc.)
- Project auto-detection from window title or directory paths
- Launch notification retry mechanism for IPC failures

## Dependencies

- Existing i3 IPC connection for window event subscription
- Existing IPC server infrastructure for launch notification RPC
- Existing project registry with application definitions
- Existing workspace configuration system
- Systemd user session for launcher wrapper execution

## Open Questions

None - specification is complete and ready for implementation without clarification.
