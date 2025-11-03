# Feature Specification: Reliable Event-Driven Workspace Assignment

**Feature Branch**: `053-workspace-assignment-enhancement`
**Created**: 2025-11-02
**Status**: Draft
**Input**: User description: "create a new feature that investigates the above and enhances our logic around workspace assignment, mapping applications to workspaces, etc."

**Design Principle**: Identify and fix root causes within the event-based subscription system. No polling workarounds. No backwards compatibility with legacy approaches - consolidate to the best single solution.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - PWA Reliable Workspace Placement (Priority: P1)

When a user launches a Progressive Web App (PWA) like YouTube, Google AI, ChatGPT, or GitHub Codespaces from the Walker launcher, the application should automatically appear on its designated workspace through the event-driven subscription system, with 100% reliability.

**Why this priority**: This is the core user-facing issue. The root cause is that window creation events aren't being received by the workspace management service for PWA windows. Fixing this at the root ensures reliability without workarounds.

**Independent Test**: Can be fully tested by launching any PWA from Walker and verifying it appears on the correct workspace within 1 second. System must use event-driven assignment, not fallback mechanisms.

**Acceptance Scenarios**:

1. **Given** user has YouTube PWA configured for workspace 4, **When** user launches YouTube from Walker, **Then** YouTube window appears on workspace 4 via event-driven assignment within 1 second
2. **Given** user has Google AI PWA configured for workspace 10, **When** user launches Google AI from Walker, **Then** Google AI window appears on workspace 10 via event notification
3. **Given** window creation event is emitted by window manager, **When** workspace assignment service receives event, **Then** PWA window is assigned before becoming visible to user
4. **Given** a PWA window is already open, **When** user launches the same PWA again, **Then** system focuses existing window or creates new window on correct workspace based on multi-instance configuration

---

### User Story 2 - Root Cause Investigation and Event System Reliability (Priority: P1)

When investigating why PWA windows don't trigger assignment events, the system should identify the specific root cause (window manager configuration, event subscription issues, timing problems, or window property mismatches) and fix it so events are reliably emitted and received.

**Why this priority**: Without understanding and fixing the root cause, we'll continue to have reliability issues. This is critical infrastructure that affects all window types, not just PWAs.

**Independent Test**: Can be tested by verifying that window creation events are emitted and received for all window types (PWAs, native apps, floating windows). Success means 100% event delivery, not 99% with workarounds.

**Acceptance Scenarios**:

1. **Given** investigation reveals window manager configuration conflicts (e.g., native assignment rules blocking events), **When** conflicts are removed, **Then** window creation events are emitted for all window types
2. **Given** investigation reveals event subscription timing issues, **When** subscription timing is corrected, **Then** all window creation events are received by service
3. **Given** investigation reveals specific window properties prevent event emission, **When** window property handling is fixed, **Then** events are emitted regardless of window properties
4. **Given** root cause is identified, **When** fix is implemented, **Then** diagnostic logs confirm 100% event delivery rate for all window types

---

### User Story 3 - Event System Diagnostics (Priority: P2)

When investigating event delivery issues, users should have diagnostic tools that show which events are emitted by the window manager, which are received by the subscription service, and where the event flow breaks down.

**Why this priority**: Essential for identifying root causes of event delivery failures. Without this visibility, we're debugging blind.

**Independent Test**: Can be tested by launching windows and verifying diagnostic tools show complete event flow from window manager emission to service receipt.

**Acceptance Scenarios**:

1. **Given** user runs event trace diagnostic, **When** command executes, **Then** output shows all emitted window events from window manager with timestamps
2. **Given** user requests event subscription status, **When** command executes, **Then** output shows which event types are subscribed, subscription health, and any missed events
3. **Given** window creation event is emitted but not received, **When** user checks event flow diagnostic, **Then** output identifies where in the event pipeline the failure occurred
4. **Given** workspace assignment succeeds, **When** user checks assignment log, **Then** log shows complete event chain from emission → subscription → processing → assignment

---

### User Story 4 - Consolidated Single Assignment Mechanism (Priority: P1)

When workspace assignment is configured, there should be exactly ONE mechanism responsible for assigning windows to workspaces, with no overlapping or duplicate approaches that could conflict or create race conditions.

**Why this priority**: Multiple overlapping assignment mechanisms (window manager native rules + external service) create complexity, race conditions, and debugging difficulties. Consolidating to a single approach eliminates conflicts and simplifies troubleshooting.

**Independent Test**: Can be tested by verifying that all workspace assignment configuration exists in one location, and only one code path handles window assignment for any given window.

**Acceptance Scenarios**:

1. **Given** system uses event-driven service for workspace assignment, **When** window manager native assignment rules are found, **Then** they are removed and migrated to service configuration
2. **Given** duplicate assignment logic exists in multiple code paths, **When** consolidation is complete, **Then** only one assignment handler processes each window creation event
3. **Given** legacy assignment files or configurations exist, **When** they are identified, **Then** they are deleted and functionality migrated to consolidated approach
4. **Given** workspace assignment configuration is updated, **When** user checks configuration files, **Then** only one assignment configuration file exists with all rules

---

### Edge Cases

- What happens when a window creation event is emitted before the assignment service subscribes to events?
- How does system handle window creation events emitted during service restart?
- What happens when window manager emits events in non-standard order (e.g., focus before creation)?
- How does system handle rapid successive window launches that generate events faster than processing?
- What happens when window creation event contains incomplete or malformed window properties?
- How does system identify which assignment mechanism "wins" if multiple mechanisms exist during migration?
- What happens when window manager native assignment rules conflict with service-based assignment?
- How does system handle windows that change their application identifier after creation?
- What happens when event subscription fails or loses connection to window manager?
- How does system handle windows created via non-standard methods (e.g., window manager scripting)?

## Requirements *(mandatory)*

### Functional Requirements

**Event System Reliability:**
- **FR-001**: System MUST receive window creation events for 100% of windows, including PWAs, native apps, and floating windows
- **FR-002**: System MUST subscribe to window manager events before any windows are created (service startup ordering)
- **FR-003**: System MUST log all window creation events received with window identifier, timestamp, and properties
- **FR-004**: System MUST identify and log when window creation events are emitted by window manager but not received by service
- **FR-005**: System MUST detect event subscription failures and reconnect automatically within 1 second

**Root Cause Investigation:**
- **FR-006**: System MUST provide diagnostic tool showing which window manager events are emitted vs received
- **FR-007**: System MUST identify conflicting configuration that prevents event emission (e.g., native assignment rules blocking events)
- **FR-008**: System MUST detect timing issues where events are emitted before service subscribes
- **FR-009**: System MUST identify window properties or types that correlate with missing events

**Workspace Assignment:**
- **FR-010**: System MUST assign windows to workspaces via event-driven mechanism ONLY (no polling fallback)
- **FR-011**: System MUST match PWA windows using unique application identifiers specific to each PWA installation
- **FR-012**: System MUST correlate launch notifications with window creation events to improve assignment accuracy
- **FR-013**: System MUST assign windows before they become visible to user (sub-second latency)
- **FR-014**: System MUST log all workspace assignments with window identifier, target workspace, and assignment latency

**Consolidation:**
- **FR-015**: System MUST use exactly ONE assignment mechanism (event-driven service assignment)
- **FR-016**: System MUST remove all window manager native assignment rules and migrate to service configuration
- **FR-017**: System MUST delete all legacy assignment configuration files and code paths
- **FR-018**: System MUST have exactly ONE workspace assignment configuration file

### Key Entities

- **Window Creation Event**: Event emitted by window manager when a new window is created, containing window identifier and properties
- **Event Subscription**: Service registration with window manager to receive specific event types (window creation, focus, close, etc.)
- **PWA Window**: Progressive Web App window with unique application identifier pattern specific to the PWA browser implementation
- **Launch Notification**: Message sent before PWA launch containing expected application identifier and target workspace
- **Assignment Record**: Historical record of workspace assignment containing window identifier, timestamp, event receipt time, and assignment latency
- **Event Gap**: Difference between events emitted by window manager and events received by service, indicating subscription or delivery issues
- **Assignment Configuration**: Single source of truth defining which applications should appear on which workspaces

## Success Criteria *(mandatory)*

### Measurable Outcomes

**Event Delivery Reliability:**
- **SC-001**: 100% of window creation events emitted by window manager are received by assignment service
- **SC-002**: PWAs launched from Walker appear on their designated workspace within 1 second, 100% of the time
- **SC-003**: Zero window creation events are missed due to subscription timing, connection issues, or configuration conflicts

**Root Cause Resolution:**
- **SC-004**: Root cause of PWA event delivery failure is identified and documented
- **SC-005**: After root cause fix, event delivery rate increases from current ~0% (for PWAs) to 100% for all window types
- **SC-006**: Event gap diagnostic shows zero difference between emitted and received events

**Assignment Performance:**
- **SC-007**: Window assignment latency is under 100ms from event receipt to workspace assignment
- **SC-008**: System handles 50+ concurrent window creations without event loss or assignment delays

**Consolidation:**
- **SC-009**: Exactly one workspace assignment mechanism exists (event-driven service)
- **SC-010**: Zero window manager native assignment rules remain in configuration
- **SC-011**: Exactly one workspace assignment configuration file exists across entire system

## Assumptions

- Window manager emits window creation events for all window types when events are not blocked by configuration conflicts
- PWA application identifier patterns remain stable across minor browser updates
- Launch notifications arrive before or within 1 second of window creation event
- Users expect PWAs to behave identically to native applications regarding workspace placement
- Workspace numbers exist before windows are assigned to them (workspace creation is implicit on assignment)
- Maximum acceptable latency for workspace assignment is 1 second from window creation
- Event-driven architecture is more reliable than polling-based approaches when properly configured
- Removing conflicting assignment mechanisms will not break existing user workflows

## Constraints

- Must work within window manager's protocol capabilities (cannot modify window manager source code)
- Diagnostic output must be human-readable and actionable, not just debug logs
- Must not interfere with user's manual window placement (e.g., floating windows, scratchpad)
- Event subscription must complete before window manager allows window creation (startup ordering)
- Assignment service must process events faster than they are emitted to avoid event queue backup
- Root cause investigation must not require modifying or rebuilding window manager
- Must consolidate to single assignment mechanism even if this breaks compatibility with legacy configuration

## Dependencies

- Window manager protocol support for event subscription and emission
- Window manager protocol support for querying emitted events (for diagnostic comparison)
- Existing event subscription infrastructure for window, workspace, and output events
- Application registry with PWA definitions and workspace assignments
- Launch notification system for pre-launch communication
- Diagnostic tooling framework for event flow inspection
- Service startup ordering mechanism to ensure event subscription before window creation

## Out of Scope

- Modifying window manager source code to add new event types
- Building a polling-based fallback mechanism for missing events
- Supporting window managers that don't provide event subscription APIs
- Automatic workspace creation when configured workspace doesn't exist
- Multi-instance PWA management (handled by existing configuration)
- PWA icon management or launcher integration (separate concern)
- Window state preservation during workspace reassignment (covered by existing features)
- Monitor configuration management (covered by existing features)
- Maintaining backwards compatibility with multiple overlapping assignment mechanisms
