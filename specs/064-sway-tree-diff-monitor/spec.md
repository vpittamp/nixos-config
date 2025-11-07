# Feature Specification: Sway Tree Diff Monitor

**Feature Branch**: `052-sway-tree-diff-monitor`
**Created**: 2025-11-07
**Status**: Draft
**Input**: User description: "create a new feature that builds this command out. i want a full, comprehensive, full featured implementation. do research on the most performant way to do this, as well as the best user experience to help them understand what is happening, perhaps with ability to drill down into events. consider whether we can use our notification server that tracks keypresses to also log keypresses / user interactions that result in changes to our tree. also consider whether we have the ability to either add to our tree (via marks or another means) our data that's not part of sway, but that might be helpful to track context. for instance we use injected environment variables to our process during launch which would be helpful to associate to our tree."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-time Window State Change Monitoring (Priority: P1)

A developer debugging why windows are being hidden unexpectedly wants to see exactly what changes are happening to the Sway tree in real-time as they interact with their windows.

**Why this priority**: This is the core value proposition - providing visibility into Sway tree changes that are currently invisible. Without this, all other features are useless.

**Independent Test**: Can be fully tested by launching the monitor, opening/closing a window, and verifying that the state changes are displayed in real-time. Delivers immediate debugging value.

**Acceptance Scenarios**:

1. **Given** the monitor is running, **When** a user opens a new window, **Then** the monitor displays the window addition with all changed tree paths and values
2. **Given** the monitor is running, **When** a user moves a window to a different workspace, **Then** the monitor shows workspace membership changes and geometry updates
3. **Given** the monitor is running, **When** a user focuses a different window, **Then** the monitor displays the focus state changes for both windows
4. **Given** the monitor is running, **When** no changes occur for 5 seconds, **Then** the monitor shows "No changes" or remains at last event
5. **Given** multiple rapid changes occur, **When** viewing the monitor, **Then** all changes are captured and displayed without missing events

---

### User Story 2 - Historical Event Timeline with User Action Correlation (Priority: P2)

A developer investigating a window management bug that occurred 30 seconds ago wants to review the sequence of tree changes and understand what user actions triggered each change.

**Why this priority**: Debugging often requires looking at past events, not just real-time. Correlating user actions (keypresses) with tree changes is critical for understanding causation.

**Independent Test**: Can be tested by performing a sequence of window operations, then querying the history to verify all events are captured with timestamps and user action context.

**Acceptance Scenarios**:

1. **Given** the monitor has been running for 2 minutes, **When** user requests event history, **Then** all events from the past 2 minutes are displayed in chronological order
2. **Given** a user pressed "Mod+2" at 15:30:45, **When** viewing event history around that time, **Then** the monitor shows the keypress event correlated with subsequent workspace change events
3. **Given** 500 events are in the buffer, **When** user filters for "window::focus" events, **Then** only focus-related changes are displayed
4. **Given** event history exists, **When** user requests events "since 30 seconds ago", **Then** only events from the last 30 seconds are shown
5. **Given** user action correlation is enabled, **When** viewing events, **Then** each tree change shows what user action (if any) triggered it

---

### User Story 3 - Detailed Event Inspection with Context Enrichment (Priority: P2)

A developer sees a window state change event and wants to drill down into the exact tree diff, including custom context like environment variables and project associations that aren't native to Sway.

**Why this priority**: Understanding the full context (including i3pm-specific data like project names, environment variables) is essential for debugging complex issues. This builds on P1's real-time monitoring.

**Independent Test**: Can be tested by selecting any event and verifying that detailed diff view shows native Sway fields plus enriched context data.

**Acceptance Scenarios**:

1. **Given** an event is displayed in the monitor, **When** user selects it for inspection, **Then** a detailed diff view shows before/after values for all changed fields
2. **Given** a window has I3PM_PROJECT_NAME environment variable, **When** inspecting that window's event, **Then** the project name is displayed alongside native Sway data
3. **Given** a window was launched with custom environment variables, **When** inspecting window creation event, **Then** relevant environment variables are shown in context section
4. **Given** a window has project marks, **When** viewing its state changes, **Then** project association is clearly labeled
5. **Given** viewing a diff, **When** a field contains a complex object (like geometry), **Then** nested fields are expandable/collapsible for readability

---

### User Story 4 - Performance-Optimized Continuous Monitoring (Priority: P2)

A developer wants to run the tree diff monitor continuously throughout their workday without experiencing system slowdown or excessive memory usage, even with hundreds of window operations.

**Why this priority**: If the monitor impacts system performance, users won't use it. This ensures the tool is practical for daily use, not just occasional debugging.

**Independent Test**: Can be tested by running the monitor for 1 hour with typical window operations and verifying CPU usage stays under 2% and memory under 25MB.

**Acceptance Scenarios**:

1. **Given** the monitor is running, **When** 1000 events have been captured, **Then** CPU usage remains below 2% and memory below 25MB
2. **Given** the monitor is running, **When** event buffer reaches maximum size (500 events), **Then** oldest events are automatically evicted and performance remains stable
3. **Given** monitoring is active, **When** computing a tree diff, **Then** diff computation completes in under 10ms for typical tree sizes (50 windows)
4. **Given** the monitor is displaying updates, **When** 10 events occur within 1 second, **Then** the UI remains responsive without lag or dropped frames
5. **Given** long-running monitoring session, **When** checking memory usage after 8 hours, **Then** memory usage has not grown beyond configured limits (bounded by circular buffer)

---

### User Story 5 - Filtered and Searchable Event Stream (Priority: P3)

A developer investigating workspace assignment issues wants to filter the event stream to show only workspace-related changes while hiding irrelevant window geometry updates.

**Why this priority**: Reduces noise and improves signal-to-noise ratio when debugging specific issues. Not essential for basic monitoring but greatly improves usability for targeted debugging.

**Independent Test**: Can be tested by applying filters and verifying that only matching events are displayed, with filter state persisting across updates.

**Acceptance Scenarios**:

1. **Given** the monitor is displaying all events, **When** user applies filter "workspace", **Then** only workspace-related events are shown
2. **Given** a filter is active, **When** new events arrive, **Then** filtering is applied in real-time
3. **Given** multiple filters are desired, **When** user specifies "workspace OR window::focus", **Then** events matching either filter are shown
4. **Given** viewing noisy geometry updates, **When** user filters out changes smaller than 10 pixels, **Then** minor geometry adjustments are hidden
5. **Given** filtering is active, **When** user searches for "firefox", **Then** only events related to Firefox windows are displayed

---

### User Story 6 - Export and Persistence for Post-Mortem Analysis (Priority: P3)

A developer experienced a window management bug but the monitor wasn't running at the time. They want to enable persistent event logging so that future issues can be analyzed post-mortem.

**Why this priority**: Enables debugging of issues that occur when developer isn't actively monitoring. Lower priority because it's a nice-to-have for infrequent debugging scenarios.

**Independent Test**: Can be tested by enabling persistence, generating events, restarting the monitor, and verifying historical events are available.

**Acceptance Scenarios**:

1. **Given** persistence is enabled, **When** events are captured, **Then** events are written to disk in addition to memory buffer
2. **Given** the monitor is restarted, **When** requesting historical events, **Then** persisted events from before restart are available
3. **Given** 7 days of event history exists, **When** retention policy runs, **Then** events older than 7 days are automatically purged
4. **Given** viewing event history, **When** user exports to JSON file, **Then** all visible events are exported in structured format
5. **Given** exported event data, **When** user imports it for analysis, **Then** the monitor can replay and visualize the imported events

---

### Edge Cases

- What happens when the Sway tree contains 200+ windows and the diff computation needs to complete in under 10ms? (May need incremental diffing or heuristics to skip irrelevant subtrees)
- How does the system handle tree changes that occur faster than they can be displayed (>20 events/second)? (Needs rate limiting or batching strategy)
- What if environment variable enrichment requires reading /proc/<pid>/environ for 50 processes simultaneously? (May need async I/O or caching)
- How are circular references or duplicate nodes in the Sway tree handled during diff computation?
- What happens when event buffer is full and persistence is disabled - are oldest events silently dropped with user notification?
- How does the system handle corrupted persisted event data when reloading history?
- What if a user action (keypress) triggers multiple cascading tree changes - how are they correlated and grouped?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST capture the complete Sway tree state on every relevant Sway event (window, workspace, output events)
- **FR-002**: System MUST compute diffs between consecutive tree snapshots, identifying all added, removed, and modified nodes and fields
- **FR-003**: System MUST display tree changes in real-time with latency under 100ms from event occurrence to display
- **FR-004**: System MUST maintain a circular buffer of at least 500 recent events in memory
- **FR-005**: System MUST enrich tree data with context not native to Sway, including:
  - Environment variables from window processes (I3PM_PROJECT_NAME, I3PM_APP_NAME, etc.)
  - Project associations from window marks
  - Application launch context
- **FR-006**: System MUST provide historical event query with filtering by:
  - Event type (window, workspace, output)
  - Time range (since timestamp, last N seconds)
  - Window ID or workspace name
  - User-defined search terms
- **FR-007**: System MUST correlate user input events (keypresses from Sway event stream) with subsequent tree changes
- **FR-008**: System MUST provide detailed inspection view for individual events showing:
  - Complete before/after diff in structured format
  - Timestamp and event type
  - User action that triggered the change (if identifiable)
  - Enriched context (env vars, project data)
- **FR-009**: System MUST support multiple output modes:
  - Live streaming mode (real-time updates)
  - Historical query mode (browse past events)
  - Diff view mode (detailed before/after comparison)
  - Statistical summary mode (event counts, change frequency)
- **FR-010**: System MUST perform diff computation in under 10ms for trees containing up to 100 windows
- **FR-011**: System MUST limit memory usage to under 25MB with 500-event buffer
- **FR-012**: System MUST support filtering to reduce noise:
  - Exclude events by type
  - Exclude minor geometry changes (threshold-based)
  - Exclude specific tree paths (e.g., timestamps)
- **FR-013**: System SHOULD support optional persistence of events to disk with:
  - Configurable retention period (default 7 days)
  - Automatic cleanup of expired events
  - Event replay from persisted data
- **FR-014**: System MUST provide export functionality to save event streams as structured data (JSON format)
- **FR-015**: System MUST handle event bursts (>20 events/second) without data loss through buffering or rate-limiting display updates
- **FR-016**: System MUST gracefully handle errors reading environment variables from /proc (process may exit before read completes)
- **FR-017**: System MUST provide user-friendly output formatting with:
  - Syntax-highlighted JSON for diffs
  - Human-readable timestamps
  - Color-coded change indicators (additions, deletions, modifications)
  - Tree path notation (e.g., "outputs[0].workspaces[2].windows[5].focused")

### Key Entities

- **TreeSnapshot**: Represents complete Sway tree state at a specific point in time
  - Timestamp of capture
  - Raw Sway tree JSON
  - Enriched context data (environment variables, project associations)
  - Triggering event type and metadata

- **TreeDiff**: Represents changes between two tree snapshots
  - Before and after snapshot references
  - List of changed paths with old/new values
  - Change type (added, removed, modified)
  - Computed significance score (for filtering noise)

- **EventRecord**: Extends existing EventEntry model to include tree snapshot
  - Event metadata (type, source, timestamp, sequence ID)
  - Before/after tree snapshots (or reference to snapshots)
  - Computed diff
  - Correlated user action (if any)
  - Enrichment data (env vars, project context)

- **UserAction**: Represents user input that may trigger tree changes
  - Action type (keypress, mouse click, IPC command)
  - Timestamp
  - Action details (key combination, window target)
  - Correlation to subsequent events (within time window)

- **FilterCriteria**: Defines rules for filtering event stream
  - Event type patterns (include/exclude)
  - Tree path patterns (focus on specific subtrees)
  - Significance thresholds (minimum change magnitude)
  - Time range constraints

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can identify the root cause of a window management bug in under 2 minutes by reviewing event history (compared to 10+ minutes of manual tree inspection)
- **SC-002**: Tree diff computation completes in under 10ms for 95% of events in typical usage (50-100 windows)
- **SC-003**: System memory usage remains under 25MB with 500-event circular buffer during 8-hour monitoring session
- **SC-004**: System CPU usage averages under 1% during active monitoring with typical event frequency (5-10 events/minute)
- **SC-005**: Real-time event display latency is under 100ms from Sway event to screen update in 99% of cases
- **SC-006**: Users can successfully correlate user actions (keypresses) with tree changes in 90% of cases where correlation is expected
- **SC-007**: Event filtering reduces displayed noise by at least 70% when debugging specific issue types (e.g., workspace assignment)
- **SC-008**: Context enrichment (environment variables, project data) is available for 95% of windows that have the relevant data
- **SC-009**: Historical event queries return results in under 200ms for queries spanning last 1000 events
- **SC-010**: Zero data loss occurs during event bursts of up to 50 events/second for bursts lasting under 5 seconds
- **SC-011**: Exported event data can be successfully imported and replayed in analysis tools with 100% fidelity
- **SC-012**: Developers report 80% reduction in time spent debugging window management issues (measured via survey)

## Assumptions

1. **Event Frequency**: Typical usage generates 5-10 Sway events per minute during active window management; bursts may reach 50 events/second for under 5 seconds
2. **Tree Size**: Most users have 10-100 windows open; power users may have up to 200 windows
3. **Retention**: 500-event in-memory buffer covers approximately 1-2 hours of typical usage
4. **Performance**: Reading environment variables from /proc is fast enough (<5ms) to not block event processing
5. **User Actions**: Sway provides sufficient event metadata to correlate keypresses with tree changes (based on timestamps and event sequencing)
6. **Enrichment**: Environment variables I3PM_* are consistently set for all i3pm-managed windows
7. **Diff Algorithm**: Structural diffing of JSON trees can be optimized to meet 10ms target through intelligent caching and incremental comparison
8. **Display Technology**: Terminal-based UI (TUI) is acceptable for this debugging tool; graphical UI is not required for MVP
9. **Persistence**: File-based event persistence is sufficient; database is not required
10. **Integration**: Can reuse existing EventBuffer infrastructure (circular buffer, event broadcasting) from Feature 017

## Dependencies

**Internal Dependencies**:
- Existing i3pm daemon event infrastructure (EventBuffer, event subscription)
- Sway IPC connection for tree queries
- Window environment bridge for reading I3PM_* variables
- Existing ChangeTracker patterns from live TUI (home-modules/tools/i3pm/src/ui/table.ts)

**External Dependencies**:
- Sway compositor and IPC protocol
- Python asyncio for concurrent operations
- /proc filesystem access for process environment variables

## Out of Scope

- Graphical (GUI) visualization of tree diffs (terminal-based only)
- Automatic bug detection or anomaly detection beyond basic change tracking
- Integration with external monitoring/observability platforms
- Real-time modification of tree state (read-only monitoring)
- Distributed monitoring across multiple machines
- Video/screen recording correlation with events
- Automated performance regression detection
- Machine learning-based event pattern recognition
