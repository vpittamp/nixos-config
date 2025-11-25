# Feature Specification: Real-Time Event Log and Activity Stream

**Feature Branch**: `092-logs-events-tab`
**Created**: 2025-11-23
**Status**: Draft
**Input**: User description: "review @docs/i3-ipc.txt to understand the sway ipc and our custom python module that managess windows/workspaces/projects. then create an additional tab in our eww monitoring widget that streams the relevant logs for sway related actions. either we simply show the events enable by sway, or if it make sense, then perhaps we can add additional events and/or metadata from our own daemon process that related"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Real-Time Window Activity (Priority: P1)

Users need to observe window management activity in real-time to understand and debug workspace behavior, project switching operations, and window state changes.

**Why this priority**: This is the core value proposition - providing visibility into the black box of window management that users currently lack. Essential for debugging unexpected behavior and understanding system state changes.

**Independent Test**: Can be fully tested by opening the monitoring panel, switching to the Logs tab, and verifying that window-related events (window creation, focus changes, workspace switches) appear in real-time as they occur. Delivers immediate value even without other features.

**Acceptance Scenarios**:

1. **Given** the monitoring panel is open with the Logs tab selected, **When** the user opens a new window, **Then** a new log entry appears showing the window creation event with window ID, app name, and workspace
2. **Given** the user is viewing the Logs tab, **When** they switch focus between windows, **Then** focus change events appear with the previous and new focused window details
3. **Given** logs are streaming, **When** the user switches workspaces, **Then** a workspace change event appears showing the workspace number transition
4. **Given** multiple events occur rapidly (e.g., opening 3 windows in quick succession), **When** viewing the log stream, **Then** all events appear in chronological order with accurate timestamps
5. **Given** the log stream is active, **When** the user performs a project switch operation, **Then** multiple related events appear (window hiding, workspace switch, window showing) grouped by timestamp

---

### User Story 2 - Filter and Search Event History (Priority: P2)

Users need to filter and search through event history to diagnose specific issues or understand past activity patterns without being overwhelmed by irrelevant events.

**Why this priority**: While real-time viewing (P1) is essential for immediate understanding, historical filtering enables deep investigation of issues. This becomes critical once users start accumulating event history.

**Independent Test**: Can be tested by accumulating some event history, then using filter controls to narrow down to specific event types (e.g., only "window_new" events) or search for specific text (e.g., "firefox"). Delivers value independently by making large log volumes manageable.

**Acceptance Scenarios**:

1. **Given** the Logs tab has 50+ events in history, **When** the user applies a filter to show only "window" events, **Then** only window-related events are displayed (hiding workspace, output, and other event types)
2. **Given** event history contains multiple window names, **When** the user searches for "firefox", **Then** only events involving Firefox windows are shown
3. **Given** filters are applied, **When** new events arrive that don't match the filter, **Then** they do not appear in the view (filtering applies to live stream)
4. **Given** a filter is active, **When** the user clears the filter, **Then** all events become visible again
5. **Given** multiple filters are active (e.g., event type "window" AND search text "code"), **When** viewing results, **Then** only events matching all criteria are shown

---

### User Story 3 - View Enriched Event Metadata (Priority: P3)

Users need to see detailed contextual information (project associations, window registry metadata, state changes) alongside raw events to understand the full impact of window management operations.

**Why this priority**: Raw Sway events provide minimal context (just IDs and state). Enrichment from our i3pm daemon adds significant diagnostic value, but is less critical than basic event visibility.

**Independent Test**: Can be tested by triggering a scoped window operation (e.g., launching a terminal in a project), then viewing the event detail and verifying it shows enriched metadata (project name, scope classification, registry app name) beyond what Sway IPC provides. Delivers independent value as enhanced debugging context.

**Acceptance Scenarios**:

1. **Given** a scoped window is created (e.g., project terminal), **When** viewing its creation event, **Then** event details show project name, scope ("scoped"), and app registry name
2. **Given** a window focus event occurs, **When** viewing the event detail, **Then** both previous and new window contexts are shown (app names, projects, workspaces)
3. **Given** a workspace switch involves moving windows between projects, **When** viewing the event, **Then** project transition information is included (from project X to project Y)
4. **Given** a window state change occurs (e.g., window goes from visible to hidden), **When** viewing the event, **Then** the state diff is shown (previous state → new state)
5. **Given** an event involves a PWA window, **When** viewing event details, **Then** the PWA badge indicator and workspace 50+ classification are shown

---

### User Story 4 - Control Event Stream Performance (Priority: P3)

Users need to pause, resume, and limit event stream buffering to prevent performance degradation when the panel is left open for extended periods or during high-activity scenarios.

**Why this priority**: Nice-to-have for long-running monitoring sessions, but not essential for initial value delivery. Becomes important only if users experience performance issues with unbounded log growth.

**Independent Test**: Can be tested by pausing the stream, performing multiple window operations, then resuming and verifying that events were buffered during pause. Performance control delivers independent value for power users who leave panels open for hours.

**Acceptance Scenarios**:

1. **Given** the event stream is active, **When** the user clicks the "Pause" button, **Then** no new events appear in the view (but continue to be received in background)
2. **Given** the stream is paused, **When** the user clicks "Resume", **Then** events that occurred during pause appear immediately
3. **Given** the event buffer reaches its limit (e.g., 500 events), **When** new events arrive, **Then** the oldest events are automatically removed (FIFO eviction)
4. **Given** high event volume (e.g., 10 events/second), **When** viewing the stream, **Then** the UI remains responsive and scrolling is smooth
5. **Given** the panel has been open for hours with 1000+ events, **When** the user clicks "Clear", **Then** all events are removed and memory usage decreases

---

### Edge Cases

- What happens when Sway IPC connection is lost? (Stream should reconnect automatically with exponential backoff, showing reconnection status to user)
- How does system handle rapid event bursts (100+ events in 1 second)? (Event batching with configurable batch size, UI should debounce rendering)
- What happens when user switches away from Logs tab while stream is active? (Stream continues in background but rendering pauses to save CPU)
- How are very long event payloads displayed? (Truncate with expand/collapse UI, full payload available in detail view)
- What happens when i3pm daemon is not running? (Show warning message, fall back to raw Sway events without enrichment)
- How are duplicate events handled? (System should deduplicate based on event ID/timestamp)
- What happens when user opens panel immediately after boot? (Show loading state while initial events populate)
- How does filtering interact with event limits? (Buffer limit applies to filtered view, not total events received)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a new "Logs" tab in the monitoring panel alongside existing Windows/Projects/Apps/Health tabs
- **FR-002**: System MUST stream window-related events in real-time with visible timestamps (format: HH:MM:SS or relative time like "5s ago")
- **FR-003**: System MUST display workspace change events showing workspace number transitions and affected windows
- **FR-004**: System MUST show window focus change events with previous and new focused window identification
- **FR-005**: System MUST display window creation and close events with window metadata (ID, app name, workspace)
- **FR-006**: System MUST present events in chronological order with most recent at the top or bottom (user preference)
- **FR-007**: Users MUST be able to filter events by type (window, workspace, output, binding, mode) via checkboxes or dropdown
- **FR-008**: Users MUST be able to search event history by text string (matches event type, window names, workspace numbers)
- **FR-009**: System MUST enrich Sway IPC events with i3pm daemon metadata when available (project associations, scope, registry app names)
- **FR-010**: System MUST display project context for scoped windows in event details (project name, scope classification)
- **FR-011**: System MUST highlight events involving project switches with distinct visual styling (e.g., different background color)
- **FR-012**: System MUST show window state transitions (visible→hidden, floating→tiled, etc.) in event payloads
- **FR-013**: Users MUST be able to pause and resume the event stream without losing buffered events
- **FR-014**: System MUST limit event buffer to a maximum number (e.g., 500 events) with FIFO eviction
- **FR-015**: Users MUST be able to clear all event history with a single action (button or keyboard shortcut)
- **FR-016**: System MUST handle Sway IPC disconnection gracefully with automatic reconnection and status indication
- **FR-017**: System MUST display each event type with a distinct icon (e.g., 󰖲 for windows, 󱂬 for workspaces, 󰍹 for outputs)
- **FR-018**: Users MUST be able to expand event entries to view full event payload (JSON structure)
- **FR-019**: System MUST maintain scroll position when new events arrive if user has scrolled up (sticky scroll at bottom only when at bottom)
- **FR-020**: System MUST show event count indicator (e.g., "127 events" or "15 filtered / 200 total")

### Key Entities

- **Event**: Represents a single activity occurrence in the window management system
  - Type: Category of event (window::new, window::focus, window::close, workspace::focus, workspace::init, output::unspecified, binding::run, mode::change)
  - Timestamp: Unix timestamp or ISO 8601 datetime when event occurred
  - Payload: Event-specific data structure (window ID, workspace number, mode name, etc.)
  - Enrichment: Optional i3pm daemon metadata (project name, scope, app registry match)

- **Event Filter**: User-defined criteria for narrowing event stream
  - Event Types: Set of enabled event categories (window, workspace, output, mode, binding)
  - Search Text: String pattern to match against event content
  - Active Status: Whether filter is currently applied or disabled

- **Event Stream State**: Current state of the live event feed
  - Paused/Resumed: Whether new events are displayed in real-time
  - Buffer Size: Current count of stored events
  - Buffer Limit: Maximum events to retain (e.g., 500)
  - Scroll Position: Whether user is viewing latest events (sticky) or historical events

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Events appear in the log view within 100ms of occurrence (measured from Sway IPC event emission to UI rendering)
- **SC-002**: Users can filter a log of 500 events to a specific event type in under 200ms (measured from filter selection to UI update)
- **SC-003**: Event stream remains responsive with 50+ events per second (measured by frame rate staying above 30fps during high activity)
- **SC-004**: Users can pause, perform 20+ window operations, resume, and see all buffered events appear within 500ms
- **SC-005**: Event buffer eviction maintains constant memory usage once limit is reached (no unbounded growth)
- **SC-006**: Panel startup time increases by less than 200ms when Logs tab implementation is added (measured against baseline)
- **SC-007**: Users can successfully locate a specific window event from 30 minutes ago using search in under 10 seconds
- **SC-008**: Event enrichment from i3pm daemon adds less than 20ms latency per event (measured end-to-end)
- **SC-009**: System recovers from Sway IPC disconnection within 5 seconds with no data loss
- **SC-010**: Users report improved ability to diagnose window management issues (measured via user feedback or support ticket reduction)

### Assumptions

1. **Event Volume**: Typical desktop usage generates 50-200 events per minute (based on window focus, workspace switches, app launches). Edge case is 1000+ events per minute during automation or testing.

2. **Daemon Availability**: i3pm daemon is running and reachable in 95%+ of use cases. When unavailable, falling back to raw Sway events provides degraded but functional experience.

3. **Performance**: Users care more about real-time responsiveness than comprehensive historical logs. 500-event buffer is sufficient for typical debugging sessions (represents ~5-10 minutes of activity).

4. **Event Enrichment**: The value of enriched metadata (project associations, scope classification) justifies the complexity of querying i3pm daemon. Users need this context to understand "why" events occurred, not just "what" happened.

5. **UI Patterns**: Users familiar with existing monitoring panel tabs (Windows, Projects, Apps, Health) will naturally understand how to navigate to and use the Logs tab.

6. **Tab Switching**: Adding a 5th tab does not significantly degrade the tab selection UX. If it does, we may need to introduce tab grouping or overflow handling (but starting with 5 tabs is reasonable).

7. **Event Types**: Sway IPC provides sufficient event granularity for debugging (window::new, window::close, window::focus, workspace::focus, etc.). We don't need to create entirely custom event types, just enrich existing ones.

8. **Filtering Needs**: Users primarily filter by event type (e.g., show only window events) and text search (e.g., find events involving "firefox"). More advanced filtering (date ranges, combined boolean filters) can be deferred to future iterations.

9. **Stream Control**: Pause/Resume is more important than playback speed control. Users want to freeze the view to read details, not replay events at different speeds.

10. **Event Persistence**: Events are ephemeral (in-memory only, cleared on panel restart). Users do not need persistent event logs saved to disk. For long-term auditing, system journal or sway-tree-monitor fills that role.
