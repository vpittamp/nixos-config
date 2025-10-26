# Feature Specification: i3 Window Management System Diagnostic & Optimization

**Feature Branch**: `039-create-a-new`
**Created**: 2025-10-26
**Status**: Draft
**Input**: User description: "create a new feature that methodically debugs the functionality that isn't working, and creates an optimal solution. we may consider whether our overall logic around workspace assignment, window rules, project filtering are working as expected. we should also consider how we're distinguishing terminal based apps from each other and pwa apps from each other. also consider this project that attempts to overcome the nuances/quirks of the i3wm system"

## User Scenarios & Testing

### User Story 1 - Workspace Assignment Validation (Priority: P1)

As a developer using the i3 project management system, I need applications to open on their configured workspaces so that my workflow organization matches my intentions and I don't have to manually move windows after launching them.

**Why this priority**: This is the core functionality that enables organized multi-workspace workflows. Without reliable workspace assignment, the entire window management system loses its primary value proposition.

**Independent Test**: Can be fully tested by configuring an application with a specific workspace number, launching it from any workspace, and verifying it appears on the target workspace. Delivers immediate value by ensuring proper workspace organization.

**Acceptance Scenarios**:

1. **Given** lazygit is configured with `preferred_workspace: 3`, **When** user launches lazygit from workspace 1, **Then** lazygit window opens on workspace 3
2. **Given** terminal is configured with `preferred_workspace: 2`, **When** user launches terminal from workspace 5, **Then** terminal window opens on workspace 2
3. **Given** VSCode is configured with `preferred_workspace: 2`, **When** user launches VSCode from workspace 1, **Then** VSCode window opens on workspace 2
4. **Given** multiple applications with different workspace assignments, **When** launched simultaneously, **Then** each appears on its designated workspace
5. **Given** application has no workspace configuration, **When** launched, **Then** opens on current workspace (fallback behavior)

---

### User Story 2 - Window Event Detection & Processing (Priority: P1)

As a system using event-driven architecture, I need to reliably detect and process window creation events so that workspace assignment, project tagging, and other automatic behaviors execute when windows are created.

**Why this priority**: This is foundational infrastructure that all other features depend on. Without event detection, no automatic window management can occur.

**Independent Test**: Can be tested by monitoring daemon logs during window creation, verifying window::new events are logged with window details. Delivers value by enabling all event-driven automation.

**Acceptance Scenarios**:

1. **Given** daemon is running and subscribed to window events, **When** new window is created, **Then** daemon logs show window::new event with window ID, class, and title
2. **Given** daemon processes window::new event, **When** window has I3PM environment variables, **Then** daemon applies project mark within 100ms
3. **Given** daemon processes window::new event, **When** window matches workspace assignment rule, **Then** workspace move command executes within 100ms
4. **Given** multiple windows created rapidly (5+ within 1 second), **When** processing events, **Then** all window::new events are captured and processed in order
5. **Given** daemon restarts, **When** windows already exist, **Then** daemon reconstructs state from existing marks and environment variables

---

### User Story 3 - Window Class Normalization (Priority: P2)

As a user configuring window rules, I need consistent window class identification so that my configuration works regardless of how the application reports its window class to the window manager.

**Why this priority**: Without this, users must discover actual window classes through trial and error, leading to configuration mismatches and broken rules.

**Independent Test**: Can be tested by configuring a rule with simplified class name (e.g., "ghostty"), launching the application with actual class "com.mitchellh.ghostty", and verifying the rule applies. Delivers value by making configuration more intuitive.

**Acceptance Scenarios**:

1. **Given** application reports class "com.mitchellh.ghostty", **When** rule configured for "ghostty", **Then** rule matches successfully
2. **Given** application reports class "Google-chrome" with instance "crx_abc123", **When** rule configured for PWA app name, **Then** rule matches the PWA instance
3. **Given** multiple Firefox PWA instances running, **When** each has unique app ID, **Then** system distinguishes between different PWA instances
4. **Given** window class lookup fails, **When** fallback strategies exist (window title, instance), **Then** system tries fallback methods before failing
5. **Given** new application with unknown class, **When** user queries class, **Then** system reports both raw class and normalized class for configuration

---

### User Story 4 - Terminal Instance Differentiation (Priority: P2)

As a user with multiple terminal windows across projects, I need each terminal instance to be properly associated with its project context so that project switching shows/hides the correct terminal windows.

**Why this priority**: Terminals are among the most frequently used project-scoped applications. Poor terminal management breaks the project isolation model.

**Independent Test**: Can be tested by launching terminals in different projects (via project-scoped launcher), switching projects, and verifying correct terminals show/hide. Delivers value by enabling proper terminal-based workflows.

**Acceptance Scenarios**:

1. **Given** terminal launched with `I3PM_PROJECT_NAME=nixos`, **When** project switches to "stacks", **Then** nixos terminal is hidden
2. **Given** terminal launched with `I3PM_PROJECT_NAME=stacks`, **When** project switches to "stacks", **Then** stacks terminal remains visible
3. **Given** two terminals with same class "com.mitchellh.ghostty", **When** each has different I3PM environment, **Then** system distinguishes them by environment variables
4. **Given** terminal has child process (e.g., lazygit running inside), **When** querying window properties, **Then** system reads parent process environment, not child
5. **Given** terminal instance closed and reopened in same project, **When** reopened, **Then** inherits project context from launcher environment

---

### User Story 5 - PWA Instance Identification (Priority: P3)

As a user running multiple PWA instances (e.g., multiple Google Chat accounts), I need each PWA window to be distinguishable so that window rules and project scoping work correctly for each instance.

**Why this priority**: PWAs are becoming more common as application delivery mechanism. Proper support enables use of web-based tools in project workflows.

**Independent Test**: Can be tested by launching two PWA instances of same app, applying different rules to each, and verifying rules apply to correct instances. Delivers value by enabling PWA-based workflows.

**Acceptance Scenarios**:

1. **Given** two Google Chat PWAs with different profiles, **When** launched, **Then** system distinguishes them by unique window properties (instance, title pattern)
2. **Given** PWA configured with specific workspace, **When** launched, **Then** opens on designated workspace like native applications
3. **Given** PWA has project association, **When** project switches, **Then** PWA shows/hides according to project scope rules
4. **Given** PWA window class is generic "Google-chrome", **When** matching against rules, **Then** system uses instance or app ID for disambiguation
5. **Given** new PWA installed, **When** user configures it, **Then** system provides clear identification properties for rule configuration

---

### User Story 6 - Diagnostic Tooling & Introspection (Priority: P2)

As a user troubleshooting window management issues, I need diagnostic commands that show me why windows aren't behaving as expected so that I can identify misconfigurations or system bugs quickly.

**Why this priority**: Debugging complex event-driven systems is extremely difficult without proper tooling. This drastically reduces time to resolution for issues.

**Independent Test**: Can be tested by creating a misconfiguration (e.g., wrong window class), running diagnostic command, and verifying it identifies the mismatch. Delivers value by enabling self-service troubleshooting.

**Acceptance Scenarios**:

1. **Given** window not moving to configured workspace, **When** running diagnostic command with window ID, **Then** shows workspace rule, actual window class, environment variables, and processing log
2. **Given** daemon not processing events, **When** running diagnostic health check, **Then** reports event subscription status, connection state, and recent event count
3. **Given** window class mismatch in configuration, **When** running class discovery tool, **Then** reports actual window class, instance, and suggested config values
4. **Given** project filter not working, **When** running filter diagnostic, **Then** shows window's I3PM environment, expected project, actual project, and filter decision log
5. **Given** user needs to understand current system state, **When** running comprehensive diagnostic, **Then** reports all daemon subscriptions, tracked windows, project states, and configuration health

---

### User Story 7 - Code Consolidation & Deduplication (Priority: P1)

As a maintainer of the i3 project management system, I need to eliminate duplicate and conflicting implementations so that the codebase is maintainable, testable, and follows a consistent event-driven architecture.

**Why this priority**: Duplicate and conflicting implementations lead to bugs, inconsistent behavior, and maintenance burden. This is foundational cleanup that enables reliable future development.

**Independent Test**: Can be tested by running code analysis tools to identify duplicate functions, measuring test coverage before/after consolidation, and verifying all features work after cleanup. Delivers value by simplifying the codebase and reducing bugs.

**Acceptance Scenarios**:

1. **Given** codebase has duplicate window event handlers, **When** running code audit, **Then** identifies all duplicate implementations with file locations and line numbers
2. **Given** multiple implementations of workspace assignment logic exist, **When** consolidating to best implementation, **Then** all consumers use the new event-driven implementation and legacy code is removed
3. **Given** conflicting APIs for window filtering exist, **When** consolidating APIs, **Then** single unified API remains and all callers are updated
4. **Given** legacy polling-based code exists alongside event-driven code, **When** consolidating, **Then** only event-driven implementation remains and all polling code is removed
5. **Given** code consolidation is complete, **When** running full test suite, **Then** all tests pass and no functionality is broken

---

### Edge Cases

- What happens when window class changes during window lifetime (e.g., terminal running different programs)?
- How does system handle race conditions when window closes immediately after creation?
- What occurs when daemon restarts mid-operation and misses window creation events?
- How are windows handled when i3 workspace numbering has gaps (e.g., workspaces 1, 5, 9)?
- What happens when preferred workspace doesn't exist yet?
- How does system behave when window creates multiple sub-windows rapidly?
- What occurs when I3PM environment variables are malformed or incomplete?
- How are windows handled when application reports multiple window classes during startup?

## Requirements

### Functional Requirements

#### Core Event Processing

- **FR-001**: System MUST detect all window::new events from i3 within 50ms of window creation
- **FR-002**: System MUST apply workspace assignment rules before window becomes visible to user
- **FR-003**: System MUST normalize window class names by matching against both full class string and common abbreviations
- **FR-004**: System MUST distinguish terminal instances using I3PM environment variables from parent process
- **FR-005**: System MUST distinguish PWA instances using window instance property or app-specific identifiers
- **FR-006**: System MUST provide diagnostic command showing why window didn't match expected workspace
- **FR-007**: System MUST log all window event processing decisions with timestamp, window ID, and rule matched
- **FR-008**: System MUST validate window event subscription is active on daemon startup and log subscription status
- **FR-009**: System MUST fall back to current workspace when preferred workspace assignment fails
- **FR-010**: System MUST query actual window properties (class, instance, title) and log them when rule matching fails
- **FR-011**: System MUST support window class aliases in configuration (e.g., "ghostty" → "com.mitchellh.ghostty")
- **FR-012**: System MUST read I3PM environment variables from window PID's /proc/{pid}/environ at window creation time
- **FR-013**: System MUST handle window::new events that occur before daemon is fully initialized by queuing them
- **FR-014**: System MUST provide health check command that validates all event subscriptions and IPC connections
- **FR-015**: System MUST track window event processing metrics (events received, processed, failed) and expose via diagnostic API

#### Code Quality & Integration

- **FR-016**: System MUST identify and eliminate all duplicate implementations of window management functions
- **FR-017**: System MUST identify and eliminate all conflicting APIs that provide overlapping functionality
- **FR-018**: When multiple implementations exist, system MUST retain only the best implementation based on: event-driven architecture compliance, performance, maintainability, and test coverage
- **FR-019**: All replaced functionality MUST have equivalent test coverage in the new implementation before removal of legacy code
- **FR-020**: System MUST provide migration path documentation for any deprecated APIs or functions
- **FR-021**: Integration tests MUST validate that new implementations work correctly with all existing features
- **FR-022**: System MUST verify no broken dependencies remain after removing legacy implementations

### Key Entities

- **Window Event**: Represents i3 window creation/modification event with window ID, class, instance, title, PID, timestamp
- **Workspace Rule**: Defines application-to-workspace mapping with application identifier, target workspace number, matching criteria
- **Window Identity**: Composite identifier for window including class (with aliases), instance, I3PM environment, process hierarchy
- **Diagnostic Report**: Structured troubleshooting output showing rule evaluation, environment variables, event processing log, system health
- **Event Subscription**: Active registration for window/workspace events with subscription type, connection state, event count

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of window::new events are detected and logged when daemon is running
- **SC-002**: 95% of applications configured with workspace assignments open on correct workspace within 200ms
- **SC-003**: Window class matching succeeds with both exact matches and common aliases (reduces config errors by 80%)
- **SC-004**: Diagnostic command identifies root cause of workspace assignment failures in under 5 seconds
- **SC-005**: Terminal instances from different projects are correctly distinguished in 100% of cases
- **SC-006**: PWA instances with unique identifiers are correctly distinguished in 100% of cases
- **SC-007**: Daemon startup validates all event subscriptions and logs success/failure status within 2 seconds
- **SC-008**: Users can troubleshoot window management issues without reading daemon source code (reduces support requests by 70%)
- **SC-009**: Event processing latency remains under 100ms even with 20+ windows opening simultaneously
- **SC-010**: System maintains 99.9% uptime for event processing during normal operation

### Testing Validation

- **SC-011**: Automated tests verify workspace assignment for 10 different application types
- **SC-012**: Stress tests confirm system handles 50 rapid window creations without dropping events
- **SC-013**: Integration tests validate window class normalization for 20+ common applications
- **SC-014**: Diagnostic tooling identifies all 10 documented misconfiguration scenarios
- **SC-015**: System recovery tests confirm daemon can rebuild state after unexpected restart

### Code Quality & Consolidation

- **SC-016**: Code audit identifies 100% of duplicate function implementations
- **SC-017**: Code audit identifies 100% of conflicting or overlapping APIs
- **SC-018**: After consolidation, zero duplicate implementations remain in codebase
- **SC-019**: After consolidation, zero conflicting APIs remain in codebase
- **SC-020**: All consolidated functionality maintains or improves performance compared to legacy implementations
- **SC-021**: Test coverage for new consolidated implementations reaches 90% or higher
- **SC-022**: Migration from legacy to new implementations completes without breaking existing functionality

## Out of Scope

- Automatic configuration generation from observed window behavior
- GUI-based diagnostic dashboard
- Historical event replay or time-travel debugging
- Integration with window managers other than i3
- Automatic conflict resolution when multiple rules match same window
- Machine learning-based window classification

## Assumptions

1. Users have i3 window manager installed and running with IPC enabled
2. Daemon has permission to read /proc/{pid}/environ for all window processes
3. Window PID is reliably reported by i3 or obtainable via xprop
4. Applications set window class within 50ms of window creation
5. I3PM environment variables are set before application launch (via launcher wrapper)
6. Users have basic understanding of i3 workspace numbering and window properties
7. Window class, instance, and title are available through i3 IPC or X11 properties
8. Diagnostic output can be text-based (terminal output)
9. Event subscription to i3 IPC is synchronous and confirms subscription before returning
10. Window workspace assignment can be done via i3 IPC move command at any time before user sees window
11. Codebase analysis tools (e.g., grep, AST parsers) are available to identify duplicate implementations
12. All existing functionality has documented behavior that can be verified through tests
13. Breaking changes to APIs are acceptable as long as all internal consumers are updated
14. Legacy code can be removed completely (no need for deprecation period or compatibility shims)

## Dependencies

- i3 window manager with IPC protocol support
- i3ipc library for event subscription and window queries
- /proc filesystem access for reading process environment variables
- xprop utility for X11 window property queries (fallback method)
- Existing I3PM project management infrastructure (app-launcher-wrapper, project registry)

## Design Principles

### Optimal Solutions Over Backward Compatibility

**Core Philosophy**: This feature prioritizes optimal architecture over backward compatibility. When updating or replacing current logic/code, we will discard legacy approaches rather than maintaining two sets of implementations.

**Event-Based Subscription Model**: The system architecture is built on an event-driven, subscription-based model using the i3 IPC API:
- Subscribe to i3 window events (window::new, window::focus, window::close)
- Subscribe to workspace events (workspace::focus, workspace::init)
- Process events asynchronously with minimal latency
- Maintain state through event subscriptions, not polling
- Rebuild state from i3 tree and marks on daemon restart

**No Polling or Legacy Patterns**: The system must not use:
- Polling-based state synchronization
- File watchers for detecting window changes
- Periodic state scans (except one-time startup scan)
- Hybrid approaches mixing polling and events

**State Management**: All state is derived from:
- i3 IPC subscriptions (real-time events)
- i3 tree queries (current window/workspace state)
- Window marks (persistent window metadata)
- Process environment variables (/proc/{pid}/environ)

This ensures a clean, maintainable architecture optimized for the i3 window manager's event model.

## Notes

This feature focuses on systematic diagnosis and repair of the window management pipeline. The priority is understanding *why* things fail before implementing fixes. Key insight from i3ass project: i3's window event system has quirks and timing issues that require defensive programming and multiple fallback strategies.

The diagnostic approach ensures we can validate each component of the pipeline independently:
1. Event detection (are events firing?)
2. Event subscription (is daemon listening?)
3. Window identification (what class/properties does window actually have?)
4. Rule matching (why didn't rule apply?)
5. Command execution (did workspace move succeed?)

This systematic approach will reveal which component is failing and guide the optimal solution, which will be implemented using the event-driven subscription model described in Design Principles.
