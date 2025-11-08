# Feature Specification: i3pm Tree Monitor Integration

**Feature Branch**: `065-i3pm-tree-monitor`
**Created**: 2025-11-08
**Status**: Draft
**Input**: User description: "create a new feature on a new branch (use sequence number 064) that replicates the functionality of our sway-tree-monitor commands into our i3pm deno cli.  use deno std library where possible, and keep  all backend/api logic in python..  use the i3pm windows --live ui experience as an example of a real-time interface that has a great user experience that we can mirror (and make better)"

## User Scenarios & Testing

### User Story 1 - Real-Time Event Streaming (Priority: P1)

Users need to monitor window state changes as they happen to understand system behavior and debug window management issues in real-time.

**Why this priority**: This is the core value proposition - seeing live changes with minimal latency. Without this, users would have to manually query historical data repeatedly, missing transient events.

**Independent Test**: Can be fully tested by launching the live view, performing window operations (open, close, move, focus), and verifying events appear instantly (<100ms) with complete information (timestamp, type, changes, correlations).

**Acceptance Scenarios**:

1. **Given** the daemon is running, **When** user runs `i3pm tree-monitor live`, **Then** a full-screen interface displays showing a header, empty event list, and legend
2. **Given** live view is active, **When** user opens a new window, **Then** a new event appears at the top showing "window::new", timestamp, change count, and correlation
3. **Given** live view is showing events, **When** user presses 'q', **Then** interface exits cleanly and returns to shell
4. **Given** live view is active, **When** user resizes terminal, **Then** interface adapts to new dimensions without crashing
5. **Given** live view has 100+ events, **When** user scrolls up/down, **Then** navigation is smooth and shows all events

---

### User Story 2 - Historical Event Query (Priority: P2)

Users need to query past window state changes with flexible filtering to analyze patterns, debug issues that occurred earlier, and generate reports.

**Why this priority**: Complements live view by enabling post-hoc analysis. Less critical than live monitoring but essential for troubleshooting.

**Independent Test**: Can be fully tested by running various query commands (`--last 50`, `--since 5m`, `--filter window::new`) and verifying the returned results match the query criteria with accurate data.

**Acceptance Scenarios**:

1. **Given** daemon has 100 events in buffer, **When** user runs `i3pm tree-monitor history --last 10`, **Then** exactly 10 most recent events are displayed in a table
2. **Given** events exist from the past hour, **When** user runs `i3pm tree-monitor history --since 30m`, **Then** only events from the last 30 minutes are shown
3. **Given** mixed event types in history, **When** user runs `i3pm tree-monitor history --filter window::new`, **Then** only "window::new" events are displayed
4. **Given** query matches 0 events, **When** user runs any query, **Then** message displays "No events found" with suggestion to check filters
5. **Given** user wants to script analysis, **When** user runs `i3pm tree-monitor history --json`, **Then** output is valid JSON array with complete event data

---

### User Story 3 - Detailed Event Inspection (Priority: P3)

Users need to inspect individual events in detail to understand field-level changes, enriched context (I3PM variables), and correlation reasoning.

**Why this priority**: Valuable for deep debugging but not needed for everyday monitoring. Users can start with live/history views and drill down only when needed.

**Independent Test**: Can be fully tested by displaying an event's detailed view and verifying all sections render correctly: metadata, correlation, field-level diff, and enriched context (I3PM variables, marks).

**Acceptance Scenarios**:

1. **Given** user has an event ID, **When** user runs `i3pm tree-monitor inspect <id>`, **Then** a formatted view shows event metadata, correlation, diff details, and enrichment
2. **Given** inspection view is open, **When** user presses 'b', **Then** view returns to previous screen (history or live)
3. **Given** event has I3PM enrichment, **When** inspection loads, **Then** I3PM variables (APP_ID, PROJECT_NAME, etc.) are clearly displayed
4. **Given** event has field changes, **When** inspection loads, **Then** each field change shows old value, new value, and significance score
5. **Given** user wants machine-readable output, **When** user runs `i3pm tree-monitor inspect <id> --json`, **Then** complete event data is returned as JSON

---

### User Story 4 - Performance Statistics (Priority: P4)

Users need to monitor the daemon's performance metrics to ensure it's running efficiently and troubleshoot resource issues.

**Why this priority**: Operational concern, not user-facing feature. Important for system health but doesn't directly impact monitoring workflow.

**Independent Test**: Can be fully tested by querying stats and verifying all metrics are present and accurate: memory usage, CPU, event counts, buffer size, diff computation times.

**Acceptance Scenarios**:

1. **Given** daemon has been running for 1 hour, **When** user runs `i3pm tree-monitor stats`, **Then** current memory, CPU, buffer utilization, and event distribution are displayed
2. **Given** user wants historical performance, **When** user runs `i3pm tree-monitor stats --since 1h`, **Then** aggregated stats for the past hour are shown
3. **Given** user wants to monitor over time, **When** user runs `i3pm tree-monitor stats --watch`, **Then** stats refresh every 5 seconds with updated values
4. **Given** memory exceeds 40MB, **When** stats display, **Then** memory usage is highlighted in yellow/red as a warning

---

### Edge Cases

- What happens when daemon is not running? → Error message: "Cannot connect to daemon. Start with: systemctl --user start sway-tree-monitor"
- How does system handle very rapid events (100+ per second)? → CLI displays updates but throttles rendering to 10 FPS to prevent flickering
- What if event buffer is full (500 events)? → Oldest events are evicted (FIFO), user sees warning if querying beyond buffer capacity
- How does live view handle terminal resize during operation? → Interface re-renders immediately to fit new dimensions
- What if RPC call times out? → After 5 seconds, show error and offer to retry
- How does system handle malformed JSON from daemon? → Parse error caught, display friendly error with raw response for debugging

## Requirements

### Functional Requirements

- **FR-001**: System MUST provide real-time event streaming interface that updates within 100ms of daemon event capture
- **FR-002**: System MUST support querying historical events with filters: time range (`--since`, `--until`, `--last`), event type (`--filter`)
- **FR-003**: System MUST display detailed event inspection showing: metadata, user action correlation, field-level diff, enriched I3PM context
- **FR-004**: System MUST show performance statistics: memory usage, CPU percentage, buffer utilization, event distribution, diff computation times
- **FR-005**: System MUST connect to daemon via Unix socket at standard path or user-specified `--socket-path`
- **FR-006**: System MUST handle daemon connection failures gracefully with actionable error messages
- **FR-007**: System MUST support JSON output mode for all commands to enable scripting and automation
- **FR-008**: System MUST use Deno standard library for all CLI operations (no external dependencies where std lib suffices)
- **FR-009**: System MUST maintain backwards compatibility with existing Python daemon RPC protocol (JSON-RPC 2.0)
- **FR-010**: System MUST provide keyboard shortcuts mirroring i3pm windows --live UX: 'q' quit, arrow keys navigate, 'd' drill-down, 'r' refresh
- **FR-011**: System MUST format time-based filters using human-friendly syntax: `5m`, `1h`, `30s`, `2d`
- **FR-012**: System MUST display correlation confidence with visual indicators (emoji/colors): 🟢 >90%, 🟡 >70%, 🟠 >50%, 🔴 >30%, ⚫ <30%

### Key Entities

- **Event**: Represents a window/workspace state change with: unique ID, timestamp, event type, change count, significance score, optional correlations
- **Correlation**: Links event to user action with: action type, binding command, time delta, confidence score, reasoning
- **Diff**: Field-level changes within event: node path, change type (modified/added/removed), old value, new value, significance
- **Enrichment**: I3PM context for window: PID, I3PM variables (APP_ID, APP_NAME, PROJECT_NAME, SCOPE), project marks, launch context
- **Stats**: Daemon performance metrics: memory (MB), CPU (%), buffer size/capacity, event counts by type, computation times

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users see live events appear within 100ms of window operations (measured from Sway event to CLI display)
- **SC-002**: Historical queries return results within 500ms for buffers containing 500 events
- **SC-003**: CLI startup time is under 50ms (10x faster than Python Textual TUI's 200-500ms)
- **SC-004**: Live view handles 50+ events per second without visible lag or dropped events
- **SC-005**: 90% of users can navigate the interface without reading documentation (keyboard shortcuts follow i3pm windows conventions)
- **SC-006**: JSON output mode enables users to build custom scripts/dashboards without parsing formatted text
- **SC-007**: Terminal resize handling works smoothly across all views without crashes or artifacts
- **SC-008**: System works identically whether daemon is local or accessed remotely via custom socket path

## Assumptions

1. **Python Daemon Unchanged**: All RPC server logic, event capture, diff computation, and correlation remain in Python. Deno CLI is purely a client.
2. **RPC Protocol Stability**: Existing JSON-RPC 2.0 protocol (`query_events`, `get_event`, `get_stats`, `ping`) is sufficient and won't require changes.
3. **Socket Path Convention**: Daemon runs at `$XDG_RUNTIME_DIR/sway-tree-monitor.sock` unless overridden by `--socket-path`.
4. **Terminal Environment**: Users run CLI in modern terminal emulator supporting ANSI escape codes, Unicode, and 24-bit color.
5. **Buffer Size Limit**: Daemon circular buffer holds 500 events (as designed in Feature 064). CLI queries respect this limit.
6. **i3pm Integration**: New commands integrate into existing `i3pm` CLI structure (e.g., `i3pm tree-monitor <subcommand>`) rather than standalone binary.
7. **Deno Version**: Deno 2.0+ is available with standard library modules for CLI argument parsing, Unix sockets, JSON encoding, table rendering.
8. **UX Patterns**: Keyboard shortcuts, table formatting, and real-time update patterns follow established conventions from `i3pm windows --live`.

## Dependencies

- **Dependency-001**: Python daemon (sway-tree-monitor) must be running with RPC server active
- **Dependency-002**: Deno 2.0+ runtime must be installed and available in PATH
- **Dependency-003**: Unix socket support required (Linux/macOS - not Windows WSL1)
- **Dependency-004**: Existing i3pm CLI codebase and project structure (for integration)
- **Dependency-005**: Terminal emulator with ANSI support for colors and cursor positioning

## Out of Scope

- Modifying Python daemon backend or RPC protocol
- Adding new RPC methods or changing existing signatures
- Creating standalone binary (remains part of i3pm CLI)
- Windows native support (Unix sockets only)
- Historical data persistence beyond daemon's in-memory buffer
- Event filtering/correlation logic (handled by Python daemon)
- Mouse interaction in TUI (keyboard-only navigation)
- Export to formats other than JSON (e.g., CSV, HTML)
