# Feature Specification: i3 Project System Monitor

**Feature Branch**: `017-now-lets-create`
**Created**: 2025-10-20
**Status**: Draft
**Input**: User description: "now, lets create a new feature that will help with testing/debugging/user experience. i want a system that shows the user (or developer) what's happening with the key elements of our system. some of these include: current project state, what windows exist, applications, monitors (if available), events (what changed), how the script handles events, etc. this may be as simple as streaming logs that we can run in a dedicated terminal, but if possible without significant complexity/work, we would want a simple ui that shows these items, dependencies, i3 tree related items, etc. this could be connected to our i3 bar, connected to our cli perhaps, or a separate application, but the key is that this should be a minimal implementation focused on exposing the underlying system. we should also consider other opensource projects that may already do this, or aspects of what we're trying to accomplish, and use them completely or aspects of their code."

## Clarifications

### Session 2025-10-20

- Q: What terminal UI implementation approach should be used for the monitor tool? → A: Rich library with live display updates
- Q: How should users switch between different monitor modes (live, events, history, tree)? → A: Command-line flags: --mode=live|events|history|tree
- Q: What IPC protocol should the monitor use to communicate with the daemon? → A: JSON-RPC over Unix socket, matching existing daemon IPC
- Q: What auto-reconnection strategy should be used when connection to daemon is lost? → A: Automatic reconnection with exponential backoff, 5 retries max
- Q: How should the monitor obtain daemon state and events? → A: Extend daemon with new JSON-RPC methods: get_state, list_windows, subscribe_events

## User Scenarios & Testing

### User Story 1 - Real-time System State Visibility (Priority: P1)

As a developer debugging the i3 project system, I need to see the current state of all system components in real-time so I can understand what the system is doing and identify issues quickly.

**Why this priority**: Core debugging capability - without visibility into system state, debugging is impossible. This is the foundation that all other monitoring features build upon.

**Independent Test**: Can be fully tested by running the monitor tool, viewing the current state display, and verifying it shows accurate information for active project, tracked windows, and monitors. Delivers immediate value for debugging current system state.

**Acceptance Scenarios**:

1. **Given** the i3 project daemon is running, **When** I launch the monitor tool, **Then** I see the currently active project name (or "None" if in global mode)
2. **Given** multiple windows are marked with projects, **When** I view the monitor, **Then** I see a list of all tracked windows with their project assignments, window classes, and workspace locations
3. **Given** multiple monitors are connected, **When** I view the monitor, **Then** I see all detected monitors with their names and current workspace assignments
4. **Given** the daemon is not running, **When** I launch the monitor tool, **Then** I see a clear "Daemon not running" status message

---

### User Story 2 - Event Stream Monitoring (Priority: P2)

As a developer troubleshooting event handling, I need to see a live stream of events as they occur (window open/close, project switches, marks applied) so I can verify the daemon is processing events correctly and identify timing or sequencing issues.

**Why this priority**: Essential for debugging event-driven behavior - allows developers to see exactly what events fire and when, which is critical for troubleshooting race conditions or missed events.

**Independent Test**: Can be tested by opening the event monitor, performing actions (opening windows, switching projects), and verifying each action generates visible events with timestamps and details.

**Acceptance Scenarios**:

1. **Given** the event monitor is running, **When** I open a new terminal window, **Then** I see a "window::new" event appear with the window ID and class
2. **Given** the event monitor is running, **When** I switch projects using the CLI, **Then** I see a "tick" event followed by project state change events
3. **Given** the event monitor is running, **When** I close a window, **Then** I see a "window::close" event with the window ID
4. **Given** the event monitor is displaying 100+ events, **When** new events arrive, **Then** old events scroll off the display and performance remains responsive

---

### User Story 3 - Historical Event Log Review (Priority: P3)

As a developer investigating an issue that occurred in the past, I need to review a timestamped log of recent events (last N events or last X minutes) so I can understand what led to the current state or identify patterns over time.

**Why this priority**: Useful for post-mortem debugging and pattern analysis, but less critical than real-time monitoring. Can be partially addressed by saving terminal output from P2.

**Independent Test**: Can be tested by running the monitor in history mode, performing several actions, then reviewing the displayed historical events with accurate timestamps and being able to filter/search the log.

**Acceptance Scenarios**:

1. **Given** the system has been running for 10 minutes, **When** I launch the monitor in history mode, **Then** I see the last 50 events with timestamps in chronological order
2. **Given** I'm viewing the event history, **When** I filter by event type (e.g., only window events), **Then** I see only events matching that type
3. **Given** I'm viewing the event history, **When** I search for a specific window ID, **Then** I see all events related to that window

---

### User Story 4 - i3 Tree Inspection (Priority: P4)

As a developer debugging window management issues, I need to inspect the current i3 window tree structure with marks and properties so I can verify windows are marked correctly and understand the hierarchy.

**Why this priority**: Advanced debugging feature - most issues can be diagnosed with P1-P3. This provides deep inspection capabilities for complex scenarios involving window hierarchy or mark application.

**Independent Test**: Can be tested by opening several windows, marking them with projects, then viewing the tree inspector and verifying it shows the correct hierarchy, marks, and window properties.

**Acceptance Scenarios**:

1. **Given** several windows are open across multiple workspaces, **When** I view the tree inspector, **Then** I see a hierarchical display of workspaces, containers, and windows
2. **Given** windows have project marks applied, **When** I view a window in the tree inspector, **Then** I see all marks including project marks displayed
3. **Given** I'm viewing the tree inspector, **When** I select a specific window, **Then** I see detailed properties (window ID, class, title, workspace, marks, floating status)

---

### Edge Cases

- What happens when the monitor tool launches before the daemon starts? (Should show clear "waiting for daemon" status)
- How does the event stream handle extremely high event rates (100+ events/second)? (Should buffer/throttle display to prevent UI freezing)
- What happens if the monitor tool loses connection to the daemon's IPC socket? (Should show connection lost status, display retry attempts with exponential backoff delays, and exit after 5 failed reconnection attempts)
- How are very long window titles or class names displayed? (Should truncate with ellipsis to prevent layout breaking)
- What happens when monitoring on a system with no monitors detected? (Should show "No monitors detected" gracefully)

## Requirements

### Functional Requirements

- **FR-001**: System MUST display the current active project name or "None" for global mode
- **FR-002**: System MUST display a list of all tracked windows showing window ID, class, title, project assignment, and workspace
- **FR-003**: System MUST display all detected monitors with their names and assigned workspaces
- **FR-004**: System MUST stream live events from the daemon via JSON-RPC notifications including event type, timestamp, and relevant details
- **FR-005**: System MUST support filtering the event stream by event type (window, workspace, tick)
- **FR-006**: System MUST retain the last 500 events in memory for historical review
- **FR-007**: System MUST indicate daemon connection status (connected, disconnected, connecting, retrying)
- **FR-008**: System MUST auto-reconnect to the daemon if connection is lost using exponential backoff (1s, 2s, 4s, 8s, 16s) with maximum 5 retry attempts
- **FR-009**: System MUST display reconnection attempt count and next retry delay to the user during reconnection
- **FR-010**: System MUST exit with a clear error message if reconnection fails after 5 attempts
- **FR-011**: System MUST provide a tree view of the i3 window hierarchy showing containers, workspaces, and windows
- **FR-012**: System MUST display window marks in the tree view
- **FR-013**: System MUST refresh state displays when events indicate changes occurred
- **FR-014**: System MUST run as a standalone terminal application using the Rich library for formatting, tables, and live display updates
- **FR-015**: System MUST gracefully handle daemon not running with clear error messaging
- **FR-016**: System MUST support running in different modes via command-line flags: --mode=live (default), --mode=events, --mode=history, --mode=tree
- **FR-017**: System MUST allow multiple instances to run simultaneously with different modes for comprehensive debugging

### Key Entities

- **Monitor State**: Current active project, daemon connection status, system uptime
- **Window Entry**: Window ID, window class, window title, project assignment, workspace, marks, floating status
- **Monitor Entry**: Monitor name/ID, assigned workspace numbers, resolution, primary flag
- **Event Entry**: Event type, timestamp, window ID (if applicable), project name (if applicable), event-specific payload
- **Tree Node**: Node type (workspace/container/window), node ID, parent node, child nodes, properties

## Success Criteria

### Measurable Outcomes

- **SC-001**: Developers can identify the current project and all tracked windows in under 5 seconds by viewing the monitor
- **SC-002**: Event stream displays new events within 100ms of them occurring in the daemon
- **SC-003**: Monitor tool can handle 1000+ events without noticeable performance degradation
- **SC-004**: 90% of common debugging questions (what project am I in? is my window tracked? did the event fire?) can be answered by viewing the monitor without reading logs
- **SC-005**: Historical event review allows finding specific events from the last 5 minutes in under 10 seconds
- **SC-006**: Monitor tool startup time is under 1 second on a typical system

### User Experience Goals

- **UX-001**: Terminal UI is clean and readable with clear section headers and formatting
- **UX-002**: Information density is appropriate - shows necessary details without overwhelming the user
- **UX-003**: Each monitor mode can be launched directly via command-line flags without additional navigation steps
- **UX-004**: Error states (daemon not running, connection lost) are immediately obvious and provide actionable guidance

## Assumptions

- The daemon will be extended with new JSON-RPC methods:
  - `get_state`: Returns current active project, daemon uptime, connection count
  - `list_windows`: Returns all tracked windows with ID, class, title, project, workspace, marks
  - `list_monitors`: Returns detected monitors with names, workspace assignments, resolution
  - `subscribe_events`: Enables event streaming via JSON-RPC notifications for window/workspace/tick events
- Event streaming will be implemented via JSON-RPC notifications over the existing Unix socket connection
- The i3 window tree can be queried via the existing i3ipc library for tree inspection mode
- The Rich Python library will be used for all terminal UI rendering, providing automatic table formatting, syntax highlighting, and live display updates
- The monitor tool can reuse connection handling and error recovery patterns from existing daemon CLI tools (i3-project-current, i3-project-daemon-status)
- Developers running the monitor will have basic terminal literacy (can interpret timestamps, understand window IDs)
- The monitor tool will run on the same machine as the i3 daemon (no remote monitoring required initially)

## Open Source Considerations

Potential projects to evaluate for code reuse:
- **i3-py** or **i3ipc-python**: May already provide tree inspection utilities
- **py3status** / **i3status**: May have monitoring/debug modules we can adapt
- **rich** (Python library): Excellent terminal UI library for formatting, tables, live displays
- **textual** (Python library): Full TUI framework if we want interactive UI
- **htop** / **btop**: Reference for well-designed terminal monitoring UIs
- **lazydocker** / **lazygit**: Modern TUI applications with good UX patterns

The implementation should prioritize using existing well-tested libraries for terminal UI (like rich) rather than building custom formatting from scratch.

## Out of Scope

- Remote monitoring (connecting to daemon on another machine)
- Historical event persistence to disk (only in-memory buffer)
- Graphical UI (web interface or native GUI)
- Performance profiling or resource monitoring (CPU/memory usage of daemon)
- Automated alerting or notifications
- Event replay or state reconstruction from logs
