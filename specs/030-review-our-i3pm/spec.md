# Feature Specification: i3pm Production Readiness

**Feature Branch**: `030-review-our-i3pm`
**Created**: 2025-10-23
**Status**: Draft
**Input**: User description: "review our i3pm python module and deno cli. determine the current functionality and what features have not been implemented. then create a specification to bring our tooling around managing i3wm functionality such as project management, monitor / window automation, project switching, etc. to a production ready state."

## Executive Summary

The i3pm (i3 Project Manager) system is a sophisticated event-driven project management and window automation tool for the i3 window manager. It has evolved through 7 features (010-015, 025, 029) from a polling-based system to a comprehensive event-driven architecture with real-time monitoring, multi-source log integration, and visual window state management.

**Current Status**: 80-85% production ready with core functionality working well. This specification addresses the remaining gaps to achieve full production readiness.

**System Components**:
- **Python Event Daemon** (6,699 LOC): Core event-driven system with systemd integration
- **Deno CLI v2.0** (4,439 LOC): Type-safe command-line interface
- **Supporting Tools**: Testing framework, monitoring dashboard, and diagnostic utilities

**Key Achievements**:
- Event-driven architecture (<100ms latency, <1% CPU)
- Project-scoped window visibility management
- Real-time window state visualization (tree/table/TUI)
- Multi-source event correlation (i3/systemd/proc)
- systemd integration with watchdog monitoring

**Remaining Gaps**:
- Layout persistence and restoration
- Production-scale validation (>500 windows)
- Error recovery and resilience
- Documentation and user onboarding
- Performance monitoring and metrics
- Security audit of IPC communication

## User Scenarios & Testing

### User Story 1 - Reliable Multi-Project Development Workflow (Priority: P1)

A developer switches between multiple projects (NixOS, Stacks, Personal) throughout the day. Each project has specific applications (terminals, editors, browsers) that should only be visible when working on that project. The system must reliably hide/show windows without lag, maintain state across i3 restarts, and handle errors gracefully.

**Why this priority**: Core value proposition of i3pm. Without reliable project switching, the entire system is unusable.

**Independent Test**: Can be fully tested by switching between 3 projects with 10+ windows each and verifying instant visibility changes without errors. Delivers immediate value for multi-project workflows.

**Acceptance Scenarios**:

1. **Given** I'm working on NixOS project with 5 terminal windows and 2 VS Code instances, **When** I switch to Stacks project, **Then** all NixOS windows become hidden and Stacks windows become visible within 200ms
2. **Given** the daemon crashes while switching projects, **When** the daemon restarts, **Then** the correct project state is restored and window visibility is correct
3. **Given** I create a new window in project A, **When** I switch to project B and back to A, **Then** the new window is still visible and properly marked
4. **Given** multiple monitors are connected/disconnected, **When** workspaces reassign to new monitor layout, **Then** project-scoped windows remain in correct workspaces and visibility states
5. **Given** 100+ windows are open across 5 projects, **When** I switch projects, **Then** the system responds within 500ms without hanging or freezing

---

### User Story 2 - Workspace Layout Persistence Across Sessions (Priority: P2)

A developer has carefully arranged their development environment: terminals on workspace 1, VS Code on workspace 2, browsers on workspace 3. When they restart i3 or reboot their system, they want their layout to be restored exactly as they left it, including window positions, sizes, and project associations.

**Why this priority**: Critical for productivity. Without layout persistence, users spend 10-15 minutes manually recreating their workspace after each restart.

**Independent Test**: Can be tested by saving a complex layout (3 workspaces, 15 windows), restarting i3, and restoring. Delivers value even without project switching by enabling session persistence.

**Acceptance Scenarios**:

1. **Given** I have a working layout with 15 windows across 3 workspaces, **When** I run `i3pm layout save --name=daily-dev`, **Then** all window positions, sizes, workspace assignments, and project marks are captured
2. **Given** I have saved a layout, **When** I restart i3 and run `i3pm layout restore --name=daily-dev`, **Then** all applications launch automatically and windows appear in their exact positions without visual flicker
3. **Given** an application in my saved layout is not installed, **When** I restore the layout, **Then** I receive a clear warning about missing applications and the rest of the layout restores successfully
4. **Given** I have multiple monitor configurations saved, **When** I connect to a different monitor setup, **Then** the system detects the change and offers to restore the appropriate layout for that configuration
5. **Given** two saved layouts have conflicting workspace assignments, **When** I attempt to restore the second layout, **Then** I see a diff showing what will change and can choose to merge or replace

---

### User Story 3 - Real-Time System Monitoring and Debugging (Priority: P2)

A developer notices windows not appearing in the correct project or workspaces behaving unexpectedly. They need to quickly diagnose the issue by viewing real-time events, window states, and daemon status without reading log files or restarting services.

**Why this priority**: Essential for troubleshooting. Without good debugging tools, users get frustrated and abandon the system. This enables self-service problem resolution.

**Independent Test**: Can be tested by triggering common issues (window not marking, project not switching) and using monitoring tools to identify the root cause. Delivers value independently as a diagnostic system.

**Acceptance Scenarios**:

1. **Given** I suspect a window is not being marked correctly, **When** I run `i3pm windows --live` and create a new window, **Then** I see the window appear in real-time with its classification and marks displayed
2. **Given** the daemon seems unresponsive, **When** I run `i3pm daemon status`, **Then** I see clear health indicators (uptime, event counts, memory usage, last successful operation) and any error conditions
3. **Given** I need to understand why a project switch didn't work, **When** I run `i3pm daemon events --limit=50 --type=tick`, **Then** I see all recent tick events with timestamps and their outcomes
4. **Given** I want to see the relationship between application launches and windows, **When** I run `i3pm daemon events --source=all --correlate`, **Then** I see a unified timeline showing systemd launches, process spawns, and window creation events with confidence scores
5. **Given** I need to report a bug, **When** I run `i3pm daemon diagnose --output=report.json`, **Then** a complete diagnostic snapshot is saved including daemon state, window tree, events, and configuration

---

### User Story 4 - Production-Scale Performance and Stability (Priority: P1)

A power user has 500+ windows open across 10 projects with complex workspace arrangements on 3 monitors. The system must maintain sub-second response times, never crash or lose state, and recover gracefully from any errors without requiring manual intervention.

**Why this priority**: Defines production readiness. System must work reliably at scale, not just for toy examples. Power users are the most likely to adopt and evangelize the tool.

**Independent Test**: Can be tested with synthetic load (spawn 500 windows, switch projects 100 times, restart daemon, disconnect monitors). Delivers confidence for production deployment.

**Acceptance Scenarios**:

1. **Given** 500 windows are open across 10 projects, **When** I switch between projects, **Then** the system responds within 1 second and maintains <5% CPU usage
2. **Given** the daemon has been running for 7 days with 100,000 events processed, **When** I check memory usage, **Then** it has not grown beyond 50MB (no memory leaks)
3. **Given** i3 crashes and restarts, **When** the daemon reconnects, **Then** it automatically restores connection within 5 seconds and rebuilds state from i3 without manual intervention
4. **Given** an error occurs during project switching (e.g., i3 IPC timeout), **When** I retry the operation, **Then** the system has cleaned up partial state and the retry succeeds
5. **Given** the event history buffer is full (500 events), **When** new events arrive, **Then** old events are pruned automatically and the system continues functioning without performance degradation

---

### User Story 5 - Secure Multi-User Deployment (Priority: P3)

An organization deploys i3pm to 50+ workstations with different users and security requirements. Administrators need to enforce policies (allowed projects, window classification rules) while users need isolated configurations and secure IPC communication.

**Why this priority**: Enables enterprise adoption. Not critical for individual users but necessary for organizational deployment.

**Independent Test**: Can be tested by deploying to test systems with different user accounts and verifying isolation, policy enforcement, and security boundaries. Delivers value for enterprise/team adoption.

**Acceptance Scenarios**:

1. **Given** multiple users share a workstation, **When** user A switches projects, **Then** user B's daemon and windows are not affected (process isolation)
2. **Given** an administrator defines system-wide classification rules in `/etc/i3pm/rules.json`, **When** users create projects, **Then** system rules take precedence over user rules
3. **Given** a malicious process attempts to connect to the daemon IPC socket, **When** it sends commands, **Then** the daemon validates the connecting process UID matches the daemon UID and rejects unauthorized commands
4. **Given** sensitive project directories contain credentials, **When** layout snapshots are saved, **Then** directory paths are sanitized and no file contents are included
5. **Given** the daemon logs events, **When** reviewing logs, **Then** no sensitive information (passwords, tokens, API keys) appears in command lines or window titles

---

### User Story 6 - Guided Onboarding for New Users (Priority: P3)

A new user installs i3pm for the first time. They need to understand what it does, create their first project, configure application classification, and start using it productively within 15 minutes without reading extensive documentation.

**Why this priority**: Adoption barrier. Complex systems need good onboarding to prevent users from giving up early.

**Independent Test**: Can be tested by timing a new user going from installation to successfully switching between 2 projects. Delivers immediate value by reducing time-to-productivity.

**Acceptance Scenarios**:

1. **Given** I just installed i3pm, **When** I run `i3pm --help`, **Then** I see a clear explanation of what i3pm does and a "Getting Started" section with a link to quickstart
2. **Given** I want to create my first project, **When** I run `i3pm project create --interactive`, **Then** I'm guided through a wizard asking for project name, directory, and which applications to scope
3. **Given** I don't know which applications should be scoped vs global, **When** I run `i3pm rules suggest`, **Then** the system analyzes my currently open windows and suggests a classification scheme
4. **Given** I've created two projects, **When** I run `i3pm tutorial`, **Then** I'm walked through switching projects, launching scoped applications, and viewing window state in an interactive tutorial
5. **Given** something goes wrong during setup, **When** I run `i3pm doctor`, **Then** the system checks common configuration issues and provides specific fix instructions

---

### Edge Cases

- What happens when a scoped application is already open before creating a new project? (Should be retroactively marked)
- How does the system handle window class detection for applications that change their class after launch? (Re-evaluate on property changes)
- What if a user manually removes project marks from windows? (Daemon should detect and re-mark based on current rules)
- How are floating windows handled during project switches? (Maintain float state, move to scratchpad if scoped)
- What happens if two projects have the same directory? (Allow but warn about potential conflicts)
- How does the system behave if the event buffer fills up during a network partition? (Drop old events, maintain recent history)
- What if systemd journal queries take >10 seconds due to large log volumes? (Timeout and provide degraded results)
- How are windows handled that have no WM_CLASS or WM_NAME? (Fall back to instance, then mark as unclassified)
- What happens if a window is manually moved to a different workspace during a project switch? (Honor user's manual action, update marks)
- How does layout restoration handle windows that are on workspaces that don't exist in current monitor config? (Create missing workspaces or adapt to available monitors)

## Requirements

### Functional Requirements

#### Core Stability and Reliability

- **FR-001**: System MUST maintain stable operation with 500+ windows open across 10 projects without crashes or memory leaks
- **FR-002**: System MUST recover automatically from i3 restarts within 5 seconds without manual intervention
- **FR-003**: System MUST handle daemon crashes by preserving state in i3 marks and rebuilding in-memory state on restart
- **FR-004**: System MUST respond to project switches within 200ms for <50 windows, 500ms for <100 windows, 1s for 500+ windows
- **FR-005**: System MUST maintain CPU usage below 5% during active operations and below 1% when idle
- **FR-006**: System MUST detect and report errors clearly with actionable recovery steps rather than silent failures

#### Layout Persistence and Restoration

- **FR-007**: System MUST capture complete workspace layouts including window positions, sizes, workspace assignments, monitor assignments, and project marks
- **FR-008**: System MUST discover launch commands for applications by inspecting desktop files, process command lines, and window properties
- **FR-009**: System MUST restore layouts without visual flicker by using i3's append_layout and window swallow criteria
- **FR-010**: System MUST detect when applications in a saved layout are unavailable and provide clear warnings
- **FR-011**: System MUST support multiple saved layouts per project and allow switching between layout configurations
- **FR-012**: System MUST compute and display diffs between current window state and saved layouts before restoration
- **FR-013**: System MUST support partial layout restoration (e.g., "restore only workspace 1")
- **FR-014**: System MUST adapt layouts to different monitor configurations by reassigning workspaces intelligently

#### Monitor and Workspace Management

- **FR-014a**: System MUST provide 1:1 workspace-to-application mapping for all configured applications, assigning each unique application to a dedicated workspace (implemented: 26 apps with WM classes, 44 deferred)
- **FR-015**: System MUST detect monitor connection/disconnection events and trigger workspace reassignment within 2 seconds
- **FR-016**: System MUST persist workspace-to-monitor assignments per monitor configuration profile
- **FR-017**: System MUST support manual workspace reassignment via interactive mode showing current layout and offering assignment options
- **FR-018**: System MUST handle monitor configuration changes during active project sessions without losing window visibility state
- **FR-019**: System MUST validate workspace assignments are physically possible (e.g., don't assign workspace to non-existent monitor)

#### Monitoring and Diagnostics

- **FR-020**: System MUST provide real-time daemon health metrics including uptime, memory usage, event counts, error rate, and last successful operation
- **FR-021**: System MUST capture complete diagnostic snapshots including daemon state, window tree, event history, configuration, and system logs
- **FR-022**: System MUST expose metrics in JSON format for integration with external monitoring systems
- **FR-023**: System MUST maintain event history buffer with configurable size (default 500 events) and automatic pruning
- **FR-024**: System MUST provide event filtering by source, type, time range, and project
- **FR-025**: System MUST display correlation between systemd launches, process spawns, and window creation with confidence scores

#### Testing and Validation

- **FR-026**: System MUST include automated test suite covering project lifecycle, window visibility, monitor reassignment, and error recovery
- **FR-027**: System MUST support synthetic load generation for performance testing (spawn N windows, switch M times)
- **FR-028**: System MUST validate configuration files against schemas and report specific validation errors
- **FR-029**: System MUST provide integration tests that exercise the full stack (daemon + CLI + i3) without mocking

#### Security and Multi-User Support

- **FR-030**: System MUST validate IPC clients by checking process UID matches daemon UID
- **FR-031**: System MUST sanitize command lines and window titles to remove sensitive patterns (passwords, tokens, API keys) from logs and events
- **FR-032**: System MUST isolate user configurations so one user cannot access another user's projects or daemon state
- **FR-033**: System MUST support system-wide policy enforcement via `/etc/i3pm/` configuration that overrides user settings
- **FR-034**: System MUST document security boundaries and threat model for IPC communication

#### User Experience and Onboarding

- **FR-035**: System MUST provide interactive project creation wizard that guides users through setup steps
- **FR-036**: System MUST include `i3pm doctor` command that validates configuration and suggests fixes for common issues
- **FR-037**: System MUST offer application classification suggestions based on currently open windows
- **FR-038**: System MUST provide interactive tutorial covering basic workflows (create project, switch projects, restore layout)
- **FR-039**: System MUST include quick-reference documentation accessible via `i3pm help <topic>`

#### Forward-Only Development and Legacy Elimination

- **FR-040**: Legacy Python TUI (15,445 LOC) MUST be completely removed when new features are production-ready
- **FR-041**: All legacy configuration formats MUST be replaced with optimal new formats in single migration
- **FR-042**: No compatibility layers or feature flags MUST be added to support old code patterns
- **FR-043**: Existing keybindings and shell aliases MUST be preserved ONLY if they represent optimal UX (not for backwards compatibility)

### Key Entities

- **Project**: A named development context with associated directory, applications, and workspace layout. Attributes: name, display_name, icon, directory, created_at, scoped_classes, layout_snapshots
- **Window**: An X11/Wayland window managed by i3. Attributes: id, class, instance, title, workspace, output, marks (including project marks), floating state, position, size
- **Workspace**: An i3 workspace containing windows. Attributes: num, name, visible, focused, urgent, output, layout_mode
- **Monitor**: A physical or virtual display output. Attributes: name, active, primary, current_workspace, resolution, position
- **Layout Snapshot**: A saved workspace configuration. Attributes: name, project, created_at, monitor_config, workspace_layouts (tree of containers and windows with swallow criteria)
- **Event**: A timestamped occurrence from i3, systemd, or /proc. Attributes: source, type, timestamp, data, correlation_id, confidence_score
- **Classification Rule**: Defines whether an application is scoped or global. Attributes: pattern (class/instance/title regex), scope_type (scoped/global), priority
- **Monitor Configuration**: A named set of monitor arrangements. Attributes: name, monitors (list of monitor names and positions), workspace_assignments

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can switch between projects with 50 windows in under 300ms, 95% of the time
- **SC-002**: System runs continuously for 30 days without restart while handling 10,000+ window events without memory leaks (memory stays below 50MB)
- **SC-003**: Users can save and restore complex layouts (15+ windows, 3 workspaces) with 95% accuracy (correct positions and sizes)
- **SC-004**: Layout restoration completes without visible window flicker in 90% of cases
- **SC-005**: New users complete their first project setup and successful project switch within 15 minutes using guided tools
- **SC-006**: 90% of user-reported bugs can be diagnosed using built-in diagnostic tools without examining raw logs
- **SC-007**: Automated test suite achieves 80%+ code coverage and catches regressions before release
- **SC-008**: System maintains <1% CPU usage during 95% of runtime (idle monitoring) and <5% during active operations
- **SC-009**: Monitor reconfiguration events (connect/disconnect) trigger workspace reassignment within 2 seconds in 95% of cases
- **SC-010**: Daemon recovery after i3 restart completes within 5 seconds with full state restoration in 99% of cases
- **SC-011**: Error scenarios (IPC timeout, missing config, invalid window) include clear error messages and recovery suggestions in 100% of cases
- **SC-012**: Event correlation correctly identifies window-to-process relationships with >80% confidence in 75% of cases

## Assumptions

1. **i3 window manager version**: Targeting i3 v4.20+ with modern IPC features (marks, events, tree queries)
2. **Single user per system**: While multi-user isolation is specified, primary use case is single user workstations
3. **systemd environment**: Daemon lifecycle management via systemd user services is available
4. **Desktop file availability**: Most applications have .desktop files for launch command discovery
5. **Event buffer size**: 500 events is sufficient for typical debugging scenarios (represents ~1 hour of active use)
6. **Monitor stability**: Monitor reconfigurations happen infrequently (a few times per day at most)
7. **Network reliability**: IPC communication over UNIX sockets has low latency (<10ms) and high reliability
8. **Application cooperation**: Applications set WM_CLASS and WM_NAME properties correctly for classification
9. **No external modification**: Users don't manually modify i3 marks or configuration files while daemon is running (or daemon detects changes)
10. **Development tools available**: Python 3.11+, Deno runtime, systemd, i3ipc libraries are installed

## Dependencies

### Technical Dependencies

- **i3 window manager**: Core dependency providing IPC interface, window management, marks, and events
- **Python 3.11+**: Runtime for event daemon with async/await support
- **Deno runtime**: JavaScript/TypeScript runtime for CLI tools
- **systemd**: Service management, socket activation, watchdog monitoring
- **i3ipc-python**: Python library for i3 IPC communication
- **systemd Python bindings**: For journal queries (python-systemd or equivalent)
- **Rich library**: Terminal UI rendering for live monitoring
- **pytest + pytest-asyncio**: Testing framework for Python daemon
- **jq**: JSON processing for shell scripts and testing
- **rofi**: Project switcher UI (existing keybinding dependency)

### Feature Dependencies

This feature builds upon and completes:

- **Feature 010**: Project workspace management system (foundation)
- **Feature 011**: Project-scoped application management (core behavior)
- **Feature 012**: i3-native dynamic management (marks, JSON configs)
- **Feature 013**: i3bar migration (status display)
- **Feature 015**: Event-based synchronization (daemon architecture) - COMPLETE
- **Feature 025**: Visual window state management (monitoring tools) - MVP COMPLETE
- **Feature 029**: Linux system log integration (event correlation) - COMPLETE

### External Dependencies

- **NixOS/home-manager**: Deployment and configuration management
- **Git repositories**: Project directory associations
- **Desktop files**: Application launch command discovery
- **X11/XCB**: Window property queries (via i3)

## Open Questions

*Note: Most technical decisions have been made through iterative feature development. The following questions remain for production deployment:*

1. **Layout storage format**: Should layouts be stored in i3's native JSON format or a custom format that's more human-readable? (Recommendation: i3 JSON for compatibility, provide human-readable export option)

2. **Event buffer persistence**: Should the event history buffer be persisted to disk on shutdown for debugging historical issues? (Recommendation: Yes, with configurable retention and automatic pruning)

3. **Monitor detection mechanism**: Should we rely solely on i3 output events or also integrate xrandr/wayland output monitoring? (Recommendation: i3 events primary, fallback to xrandr for edge cases)

4. **Classification precedence**: When system-wide and user rules conflict, should there be a way for users to override system rules? (Recommendation: System rules win by default, add explicit user override flag)

## Out of Scope

The following capabilities are intentionally excluded from this production readiness effort:

1. **Browser profile management**: Automatically switching Firefox/Chrome profiles per project (complex, browser-specific)
2. **Custom keybindings per project**: Dynamic i3 config reloading (requires i3 restart, high risk)
3. **Project templates marketplace**: Sharing project configurations between users (requires backend infrastructure)
4. **AI-powered project detection**: Automatically detecting project boundaries from git repos and file activity (future enhancement)
5. **Wayland native support**: Currently assumes X11 through i3 (wait for i3 Wayland release)
6. **Remote workspace management**: Managing i3 sessions on remote machines (requires different architecture)
7. **Integration with other window managers**: Supporting Sway, bspwm, etc. (fundamentally different IPC)
8. **Window content awareness**: Inspecting window contents to determine project (security/privacy concerns)
9. **Automatic workspace organization**: AI-driven window placement suggestions (complex, subjective)
10. **Mobile companion app**: Remote project switching from phone/tablet (infrastructure required)

## Implementation Strategy: Forward-Only

### Legacy Code Elimination

**Immediate Removal** (same commit as new features):
1. **Legacy Python TUI** (15,445 LOC in `home-modules/tools/i3-project-manager/`): DELETE entirely
2. **Old monitoring tools**: Replace with new monitoring module, delete old implementations
3. **Polling-based code**: Already removed in Feature 015, ensure no remnants exist
4. **Deprecated command aliases**: Keep only if optimal, remove if maintained for backwards compat

**Optimal Solution First**:
- Design layout persistence using i3 native format (not legacy format + conversion)
- Implement security hardening without "legacy unsafe mode" fallback
- Build onboarding tools for optimal workflow (not to ease migration from old tools)
- Create diagnostic tools that work with current architecture (not legacy state)

### Migration: One-Time, Complete

**Single Migration Event** (not gradual):
1. User runs: `i3pm migrate-from-legacy` (one-time command)
2. Tool converts old project definitions to new format
3. Tool validates new configuration works
4. Tool **deletes** old configuration files
5. Migration command removes itself after successful run

**No Dual Support Period**:
- New features deployed immediately as primary implementation
- Old code removed in same commit/PR
- No feature flags, no compatibility modes
- Documentation shows only new optimal approach

## Success Metrics Tracking

The following metrics should be collected during production deployment:

1. **Performance Metrics**:
   - Project switch latency (p50, p95, p99)
   - Daemon memory usage over time
   - CPU usage during idle and active operations
   - Event processing latency

2. **Reliability Metrics**:
   - Daemon uptime (mean time between restarts)
   - Error rate by error type
   - Recovery success rate after failures
   - State consistency checks (marks vs in-memory state)

3. **Usage Metrics**:
   - Number of projects per user
   - Number of windows per project
   - Project switch frequency
   - Monitor reconfiguration frequency
   - Layout save/restore usage

4. **User Experience Metrics**:
   - Time to first project creation
   - Tutorial completion rate
   - Support ticket volume (before/after improvements)
   - User-reported bug reproducibility with diagnostic tools

## Documentation Requirements

The following documentation must be created or updated:

1. **Quickstart Guide**: Updated with new features (layout persistence, monitoring improvements)
2. **Architecture Documentation**: Complete system design documentation in `/etc/nixos/docs/I3PM_ARCHITECTURE.md`
3. **Troubleshooting Guide**: Updated `/etc/nixos/docs/I3_PROJECT_EVENTS.md` with new diagnostic procedures
4. **API Documentation**: Document JSON-RPC IPC protocol for external integrations
5. **Security Documentation**: Threat model and security boundaries for multi-user deployments
6. **Migration Guide**: Instructions for updating from Feature 015/025/029 to production release
7. **Testing Guide**: How to run test suite and interpret results
8. **Performance Tuning Guide**: Configuration options for different scales (10 windows vs 500 windows)

## Related Features

- **Feature 010**: Foundation - Project workspace management system
- **Feature 011**: Core - Project-scoped application management
- **Feature 012**: Core - i3-native dynamic management
- **Feature 013**: Integration - i3bar status display
- **Feature 015**: Complete - Event-based synchronization daemon
- **Feature 025**: MVP Complete - Visual window state management
- **Feature 029**: Complete - Linux system log integration

This feature completes the i3pm production readiness journey by addressing remaining gaps in stability, monitoring, layout persistence, and user experience.
