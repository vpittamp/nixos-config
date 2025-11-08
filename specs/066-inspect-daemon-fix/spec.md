# Feature Specification: Tree Monitor Inspect Command - Daemon Backend Fix

**Feature Branch**: `066-inspect-daemon-fix`
**Created**: 2025-11-08
**Status**: Draft
**Input**: User description: "create a new feature that implements the functionality that we need to get inspect working and create an awesome experience using deno cli"

**Prerequisite**: Feature 065 (i3pm Tree Monitor Integration) - TypeScript/Deno CLI client 100% complete

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Inspect Individual Events (Priority: P1) 🎯 MVP

Users can drill down into individual window state events to understand exactly what changed, why it happened, and what system context was involved - enabling effective debugging and understanding of window manager behavior.

**Why this priority**: This is the core missing functionality that blocks the complete i3pm tree-monitor experience. Without inspect, users cannot investigate specific events in detail, making the entire monitoring system less useful for debugging window management issues.

**Independent Test**: Can be fully tested by running `i3pm tree-monitor inspect <event_id>` and verifying that detailed event information displays correctly with all sections (metadata, correlation, diff, enrichment). Delivers immediate value for debugging window behavior.

**Acceptance Scenarios**:

1. **Given** the daemon has captured events, **When** user runs `i3pm tree-monitor inspect <event_id>`, **Then** system displays event metadata (ID, timestamp, type, significance level)
2. **Given** an event with user action correlation, **When** user inspects the event, **Then** system displays which user action triggered the event (keyboard binding, mouse click, etc.) with confidence indicator
3. **Given** an event with field-level changes, **When** user inspects the event, **Then** system displays old → new values for each changed field, grouped by change type (modified, added, removed)
4. **Given** a window-related event with enrichment data, **When** user inspects the event, **Then** system displays I3PM context (PID, environment variables, marks, launch context)
5. **Given** a non-existent event ID, **When** user attempts to inspect it, **Then** system displays clear error message "Event not found" with suggestion to query recent events
6. **Given** daemon is not running, **When** user attempts inspect command, **Then** system displays actionable error with daemon startup instructions

---

### User Story 2 - JSON Output for Automation (Priority: P2)

Users can output event details as JSON for programmatic analysis, enabling integration with scripts, monitoring systems, and automated diagnostics.

**Why this priority**: Extends inspect functionality for power users and automation scenarios. Valuable but not essential for core debugging workflow.

**Independent Test**: Can be tested by running `i3pm tree-monitor inspect <event_id> --json` and verifying valid JSON output that matches the RPC response schema. Enables scripting and automation use cases.

**Acceptance Scenarios**:

1. **Given** an event exists, **When** user runs `i3pm tree-monitor inspect <event_id> --json`, **Then** system outputs complete event data as valid JSON
2. **Given** JSON output is requested, **When** parsing the output, **Then** all event fields are present and correctly structured (metadata, diff, correlations, enrichment)

---

### User Story 3 - Performance & Reliability (Priority: P3)

Inspect operations complete within 500ms and handle all edge cases gracefully, providing a smooth and reliable user experience.

**Why this priority**: Quality of life improvements that enhance but don't fundamentally enable the inspect feature.

**Independent Test**: Can be measured with timing tests and edge case scenarios (timeouts, connection errors, malformed responses).

**Acceptance Scenarios**:

1. **Given** daemon is responsive, **When** user requests event details, **Then** response displays within 500ms
2. **Given** daemon experiences a timeout, **When** user requests event details, **Then** system displays timeout error after 5 seconds with retry suggestion
3. **Given** daemon returns malformed JSON, **When** parsing response, **Then** system displays friendly error message with raw response for debugging

---

### Edge Cases

- What happens when the event ID is valid but the event has no correlation data? (Display "No correlation" message)
- What happens when the event has no diff changes? (Display "No changes detected" - valid for some event types)
- What happens when enrichment data is incomplete or missing? (Display only available fields, gracefully handle missing data)
- What happens when the daemon is restarted and event IDs change? (Error "Event not found", suggest querying recent events)
- What happens when multiple clients request the same event simultaneously? (No impact - read-only operation, daemon handles concurrency)

## Requirements *(mandatory)*

### Functional Requirements

**Daemon Backend (Python)**:

- **FR-001**: System MUST accept both integer and string event IDs in `get_event` RPC method
- **FR-002**: System MUST convert string event IDs to integers before lookup
- **FR-003**: System MUST return RPC error code -32000 with message "Event not found" when event ID does not exist in buffer
- **FR-004**: System MUST return complete event data including metadata, diff details, correlations, and enrichment
- **FR-005**: System MUST handle malformed event ID parameters gracefully with appropriate error codes

**CLI Client (TypeScript/Deno - Already Implemented in Feature 065)**:

- **FR-006**: CLI MUST display event metadata in human-readable format (ID, timestamp in HH:MM:SS.mmm, event type with color coding, significance label)
- **FR-007**: CLI MUST display user action correlation when present (action type, binding command, time delta, confidence indicator as emoji)
- **FR-008**: CLI MUST display field-level diff grouped by change type (modified, added, removed) with old → new value formatting
- **FR-009**: CLI MUST display I3PM enrichment data when available (PID, environment variables, window marks, launch context)
- **FR-010**: CLI MUST support JSON output mode via --json flag
- **FR-011**: CLI MUST display actionable error messages for all failure scenarios (event not found, daemon not running, timeout, parse error)

### Key Entities

- **Event**: Represents a captured window/workspace state change with ID, timestamp, type, significance score, optional correlation, diff, and enrichment
- **Correlation**: Links an event to a user action (binding, mouse click, external command) with confidence score and reasoning
- **Diff**: Field-level change record showing path, change type (modified/added/removed), old/new values, and significance
- **Enrichment**: I3PM-specific context for window events including PID, environment variables, marks, and launch metadata

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can inspect any event and see detailed information within 500ms
- **SC-002**: Inspect command displays all event sections (metadata, correlation, diff, enrichment) with clear formatting and no data loss
- **SC-003**: Error messages provide actionable next steps (e.g., "Event not found: Try 'i3pm tree-monitor history --last 10' to see recent events")
- **SC-004**: JSON output mode produces valid, parsable JSON that matches the daemon's RPC schema
- **SC-005**: 100% of events returned by `query_events` can be successfully inspected via `get_event`
- **SC-006**: System handles all error scenarios gracefully without crashes or unhandled exceptions

## Assumptions

- **A-001**: The Python daemon package can be overridden or patched in the NixOS configuration (may require system-level package management)
- **A-002**: The TypeScript client implementation from Feature 065 is correct and only needs the daemon fix to work
- **A-003**: Event IDs remain stable within a single daemon session (daemon restart may reset IDs)
- **A-004**: The circular buffer size (500 events) is sufficient for typical use cases
- **A-005**: Users have basic terminal proficiency and can read structured command output

## Dependencies

- **Feature 065**: i3pm Tree Monitor Integration (TypeScript/Deno CLI client) - COMPLETE
- **Python daemon**: sway-tree-monitor package with event buffer and RPC server
- **NixOS system**: Ability to override or patch Python packages in system configuration
- **Unix socket**: Communication channel between CLI client and daemon at `$XDG_RUNTIME_DIR/sway-tree-monitor.sock`

## Scope

### In Scope

- Fix Python daemon's `get_event` RPC method to handle string event IDs
- Implement proper error handling for event-not-found scenarios
- Package and deploy updated daemon via NixOS configuration
- Verify inspect command works end-to-end with real events
- Ensure JSON output mode functions correctly

### Out of Scope

- Changes to TypeScript/Deno CLI client (already complete in Feature 065)
- Performance optimization of event buffer lookups (acceptable for 500-event buffer)
- New event types or correlation algorithms (daemon functionality unchanged)
- Multi-daemon support or distributed event storage
- Historical event persistence beyond circular buffer
- Web UI or graphical event inspection interface

## Constraints

- **C-001**: Must maintain backwards compatibility with existing daemon RPC protocol
- **C-002**: Cannot change event ID format or buffer structure (breaking change)
- **C-003**: Fix must work with NixOS package management system
- **C-004**: No changes to Feature 065 TypeScript client code
- **C-005**: Must preserve all existing daemon functionality (query_events, get_statistics, etc.)
