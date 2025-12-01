# Feature Specification: Unified Event Tracing System

**Feature Branch**: `102-unified-event-tracing`
**Created**: 2025-11-30
**Status**: Draft
**Input**: Comprehensive improvements to window tracing including: unified trace events with log tab, window blur logging, output event distinction, cross-reference traces with log events, command execution in log tab, causality chain visualization, event performance metrics, and trace templates.

## Clarifications

### Session 2025-11-30

- Q: How should the system determine output event types when Sway IPC provides limited information? → A: Compare output state before/after change via swaymsg -t get_outputs diffing
- Q: How should correlation_id be generated and propagated for causality tracking? → A: UUID generated at root event, propagated via async context to all child events
- Q: What should happen to events when the buffer is full and traces are active? → A: Copy-on-evict: copy event to trace storage before evicting from main buffer
- Q: What is the target UI update latency for the Log tab during normal event flow? → A: <100ms (consistent with monitoring panel)
- Q: Which async context mechanism should be used for correlation_id propagation? → A: `contextvars.ContextVar` (standard Python async context, auto-propagates through await and create_task)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View i3pm Internal Events in Log Tab (Priority: P1)

As a developer debugging window management issues, I want to see i3pm's internal events (project switches, visibility changes, command executions) in the Log tab alongside raw Sway events, so I can understand the full picture of what's happening without needing to start a separate trace.

**Why this priority**: This is the most critical gap - currently 30+ trace event types are invisible in the Log tab. Users cannot see project::switch, visibility::hidden, command::queued events which are essential for debugging i3pm-specific behavior. This single change would dramatically improve debugging capability.

**Independent Test**: Can be fully tested by switching projects and verifying that project::switch, visibility::hidden, and command::executed events appear in the Log tab with appropriate filtering.

**Acceptance Scenarios**:

1. **Given** the Log tab is visible and i3pm daemon is running, **When** I switch projects using `i3pm project switch`, **Then** I see a `project::switch` event in the Log tab with the old and new project names
2. **Given** a scoped window is visible, **When** I switch to a different project, **Then** I see `visibility::hidden` events for each scoped window that was hidden
3. **Given** the Log tab filter panel is visible, **When** I look at the filter categories, **Then** I see a new "i3pm Events" category with toggles for project, visibility, command, launch, and trace events
4. **Given** only "i3pm Events" filter is enabled, **When** I perform window operations, **Then** I only see i3pm-generated events (not raw Sway events)

---

### User Story 2 - Command Execution Visibility (Priority: P1)

As a developer troubleshooting why windows aren't moving or hiding correctly, I want to see command execution events in the Log tab, so I can verify that commands are being queued, executed, and whether they succeeded or failed.

**Why this priority**: Command execution is the action layer - understanding why windows don't behave as expected requires seeing what commands were issued. This is critical for debugging the most common issues users encounter.

**Independent Test**: Can be tested by triggering window operations (hide, restore, move) and verifying command::queued, command::executed, and command::result events appear with timing information.

**Acceptance Scenarios**:

1. **Given** the Log tab is open with command events enabled, **When** a window is moved to scratchpad via project switch, **Then** I see `command::queued` with the Sway command text
2. **Given** a command has been queued, **When** it executes, **Then** I see `command::executed` with the execution duration in milliseconds
3. **Given** a command has executed, **When** the result is received, **Then** I see `command::result` showing success/failure status
4. **Given** multiple commands are batched together, **When** they execute, **Then** I see `command::batch` with the count and total duration

---

### User Story 3 - Cross-Reference Traces with Log Events (Priority: P2)

As a developer analyzing a trace, I want to see which raw Sway events correspond to trace events, and vice versa, so I can correlate high-level i3pm operations with low-level window manager events.

**Why this priority**: This bridges the gap between the Trace view (focused debugging) and Log view (stream of all events), enabling developers to understand causality across both views.

**Independent Test**: Can be tested by starting a trace, performing operations, then clicking on a trace event to highlight corresponding log events (and vice versa).

**Acceptance Scenarios**:

1. **Given** a trace is active and expanded in the Traces tab, **When** I click on a trace event, **Then** the Log tab scrolls to and highlights the corresponding raw Sway event(s)
2. **Given** the Log tab is showing events, **When** I see an event that has an active trace covering that window, **Then** I see a trace indicator icon on the event row
3. **Given** a Log event has a trace indicator, **When** I click the indicator, **Then** I am taken to the Traces tab with that trace expanded and the corresponding event highlighted
4. **Given** a trace event has a correlation_id, **When** viewing in expanded mode, **Then** I can see all related events grouped together

---

### User Story 4 - Causality Chain Visualization (Priority: P2)

As a developer trying to understand why a sequence of events occurred, I want to see the causal relationships between events (which event triggered which), so I can trace problems back to their root cause.

**Why this priority**: Understanding causality is essential for debugging complex multi-step operations like project switches that trigger cascading window operations.

**Independent Test**: Can be tested by performing a project switch and viewing the causality chain showing: project::switch → visibility::hidden (×N) → command::batch → command::result.

**Acceptance Scenarios**:

1. **Given** a trace with multiple events, **When** I view the expanded timeline, **Then** events with the same correlation_id are visually grouped together
2. **Given** a parent event that triggered child events, **When** viewing the timeline, **Then** child events are indented under their parent to show hierarchy
3. **Given** a causality chain exists, **When** I hover over any event in the chain, **Then** all related events in the chain are highlighted
4. **Given** a complex operation completes, **When** viewing the trace summary, **Then** I see a "Causality Chains" section showing each chain with its duration

---

### User Story 5 - Output Event Distinction (Priority: P2)

As a developer debugging multi-monitor issues, I want output events to distinguish between connected, disconnected, and resolution-changed states, so I can understand exactly what changed when monitors are reconfigured.

**Why this priority**: Currently all output changes collapse to `output::unspecified`, making multi-monitor debugging difficult. This is especially important for the headless VNC setup.

**Independent Test**: Can be tested by connecting/disconnecting a monitor (or changing profile on headless) and verifying distinct event types appear.

**Acceptance Scenarios**:

1. **Given** a monitor is connected, **When** I view the Log tab, **Then** I see an `output::connected` event with the output name
2. **Given** a monitor is disconnected, **When** I view the Log tab, **Then** I see an `output::disconnected` event with the output name
3. **Given** a monitor profile changes, **When** I view the Log tab, **Then** I see an `output::profile_changed` event with old and new profile names
4. **Given** the Log tab filter panel is visible, **When** I look at the "Other" category, **Then** I see separate toggles for connected, disconnected, and profile_changed events

---

### User Story 6 - Window Blur Event Logging (Priority: P3)

As a developer debugging focus issues, I want window::blur events to appear in the Log tab, so I can understand the complete focus chain (which window lost focus when another gained it).

**Why this priority**: Focus issues are common but blur events are currently traced but not logged, making focus chain debugging incomplete.

**Independent Test**: Can be tested by clicking between windows and verifying both window::focus and window::blur events appear with matching window IDs.

**Acceptance Scenarios**:

1. **Given** window A has focus, **When** I click on window B, **Then** I see `window::blur` for window A followed by `window::focus` for window B
2. **Given** the Log tab filter for window events is enabled, **When** I look at sub-filters, **Then** I see a separate toggle for `blur` events
3. **Given** blur logging is enabled, **When** rapid focus changes occur, **Then** blur/focus pairs are logged in correct order with sub-millisecond timestamps

---

### User Story 7 - Event Performance Metrics (Priority: P3)

As a developer optimizing window management performance, I want to see execution time for each event type in the Log tab, so I can identify slow operations without starting a dedicated trace.

**Why this priority**: Performance visibility in the Log tab enables passive monitoring without the overhead of active tracing, catching issues opportunistically.

**Independent Test**: Can be tested by performing operations and verifying timing badges appear on slow events (>100ms) in the Log tab.

**Acceptance Scenarios**:

1. **Given** an event takes longer than 100ms to process, **When** viewing in the Log tab, **Then** I see a duration badge showing the time in milliseconds
2. **Given** multiple events are visible, **When** sorting by duration, **Then** slowest events appear first
3. **Given** the Log tab header, **When** viewing statistics, **Then** I see average event processing time and count of slow events (>100ms)

---

### User Story 8 - Trace Templates (Priority: P3)

As a developer starting a debugging session, I want pre-configured trace templates for common scenarios, so I can quickly start the right kind of trace without remembering complex options.

**Why this priority**: Reduces friction in starting debugging sessions and ensures comprehensive capture for common issues.

**Independent Test**: Can be tested by selecting a template from the UI and verifying the trace starts with appropriate matchers and event type filters.

**Acceptance Scenarios**:

1. **Given** I want to debug an app launch, **When** I select "Debug App Launch" template, **Then** a pre-launch trace starts with lifecycle events enabled and 60-second timeout
2. **Given** I want to debug a project switch, **When** I select "Debug Project Switch" template, **Then** traces start for all currently-scoped windows with visibility and command events enabled
3. **Given** I want to debug focus issues, **When** I select "Debug Focus Chain" template, **Then** a trace starts capturing only focus and blur events for the focused window
4. **Given** the Traces tab header, **When** I click the "+" button, **Then** I see a dropdown with template options and a "Custom" option for manual configuration

---

### Edge Cases

- What happens when the event buffer fills up while traces are active? (Copy-on-evict: before evicting an event from the main buffer, check if any active trace covers that window_id and copy the event to the trace's dedicated storage)
- How does the system handle rapid event bursts exceeding 100 events/second? (Should batch updates and show "N events collapsed" indicator)
- What happens when viewing cross-references to events that have been evicted from the buffer? (Show "Event no longer in buffer" message with timestamp)
- How does causality tracking handle orphaned events (child without parent)? (Show with "unknown parent" indicator)
- What happens to trace templates when the traced window closes? (Template-based trace should auto-stop and show completion summary)

## Requirements *(mandatory)*

### Functional Requirements

**i3pm Event Integration (P1)**
- **FR-001**: System MUST publish i3pm internal events (project::switch, visibility::hidden/shown, command::*, launch::*) to the event buffer
- **FR-002**: System MUST add "i3pm Events" filter category to Log tab with sub-filters for each event type
- **FR-003**: System MUST display i3pm events with distinct visual styling (different color/icon) from raw Sway events
- **FR-004**: System MUST include event source indicator (i3pm vs Sway) on each event row

**Command Execution Visibility (P1)**
- **FR-005**: System MUST log command::queued events with the full Sway command text
- **FR-006**: System MUST log command::executed events with execution duration
- **FR-007**: System MUST log command::result events with success/failure status and any error message
- **FR-008**: System MUST log command::batch events for batched operations with count and total duration

**Cross-Reference System (P2)**
- **FR-009**: System MUST display trace indicator icon on Log events that have active traces covering that window
- **FR-010**: System MUST support click-to-navigate from trace events to corresponding Log events
- **FR-011**: System MUST support click-to-navigate from Log events to corresponding trace (via indicator)
- **FR-012**: System MUST scroll and highlight target events when navigating between views

**Causality Visualization (P2)**
- **FR-013**: System MUST visually group events with matching correlation_id
- **FR-014**: System MUST indent child events under parent events to show hierarchy
- **FR-015**: System MUST highlight all events in a causality chain on hover
- **FR-016**: System MUST display causality chain summary in trace overview with chain duration

**Output Event Enhancement (P2)**
- **FR-017**: System MUST distinguish output::connected, output::disconnected, and output::profile_changed events
- **FR-018**: System MUST include output name and relevant details in output event display
- **FR-019**: System MUST provide separate filter toggles for each output event type

**Window Blur Logging (P3)**
- **FR-020**: System MUST log window::blur events to the event buffer
- **FR-021**: System MUST provide separate filter toggle for blur events
- **FR-022**: System MUST maintain correct ordering of blur/focus pairs at sub-millisecond precision

**Performance Metrics (P3)**
- **FR-023**: System MUST display duration badge on events exceeding 100ms processing time
- **FR-024**: System MUST support sorting Log events by duration
- **FR-025**: System MUST display aggregate statistics (average time, slow event count) in Log tab header

**Trace Templates (P3)**
- **FR-026**: System MUST provide "Debug App Launch" template that starts pre-launch trace with 60s timeout
- **FR-027**: System MUST provide "Debug Project Switch" template that traces all scoped windows
- **FR-028**: System MUST provide "Debug Focus Chain" template that captures focus/blur events only
- **FR-029**: System MUST display template selector in Traces tab header with dropdown menu

### Non-Functional Requirements

**Performance**
- **NFR-001**: Log tab UI updates MUST complete within 100ms of event receipt during normal operation
- **NFR-002**: System MUST handle event bursts of 100+ events/second without losing events or degrading UI responsiveness (batch updates with "N events collapsed" indicator)

### Key Entities

- **TraceEvent**: Individual event captured during tracing, with timestamp, type, correlation_id (UUID generated at root event, propagated via `contextvars.ContextVar`), causality_depth, and window state
- **EventBufferEntry**: Event in the Log tab buffer, with source (i3pm/Sway), timestamp, type, window_id, and optional trace_id reference
- **CausalityChain**: Group of events linked by correlation_id, with parent event, child events, and total chain duration
- **TraceTemplate**: Pre-configured trace settings with name, matchers, event type filters, timeout, and description
- **OutputEvent**: Enhanced output event with specific type (connected/disconnected/profile_changed), output name, and relevant metadata

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can view all i3pm internal events (project switches, visibility changes, commands) in the Log tab without starting a trace
- **SC-002**: Users can identify the root cause of window behavior issues by following causality chains from effect back to trigger
- **SC-003**: Users can navigate between Trace view and Log view with single clicks, maintaining context
- **SC-004**: Users can start debugging common scenarios (app launch, project switch, focus issues) in under 5 seconds using templates
- **SC-005**: Users can identify slow operations (>100ms) at a glance via visual indicators in the Log tab
- **SC-006**: Multi-monitor debugging is possible by distinguishing output event types (connected/disconnected/profile_changed)
- **SC-007**: Focus chain debugging shows complete picture with both focus and blur events logged
- **SC-008**: Event buffer handles bursts of 100+ events/second without losing events or degrading UI responsiveness

## Assumptions

- The existing event buffer (500 events) is sufficient for most debugging sessions
- Users have already adopted the monitoring panel (Feature 085) and are familiar with the Traces tab (Feature 101)
- The daemon's trace storage can handle the additional event types without significant memory increase
- Output event type detection uses state diffing: cache output state via `swaymsg -t get_outputs` and compare before/after on output events to determine connected/disconnected/profile_changed
- Performance metrics are captured at handler entry/exit points in the existing daemon architecture
