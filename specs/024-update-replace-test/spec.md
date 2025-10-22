# Feature Specification: Dynamic Window Management System

**Feature Branch**: `024-update-replace-test`
**Created**: 2025-10-22
**Status**: Draft
**Input**: User description: "update/replace/test our application launching logic, window detection logic, and assigning launched applications to workspaces dynamically.  in the past, we've used static configuration in home-modules/desktop/i3.nix, but we've installed much more dynamic window event/subscription based system in our i3pm python module.  we want to see if we can centralize our logic in our i3pm python module that will be more dynamic and can be responsible for assigning launched applications to the corrct workspace.  we may consider changing how we launch applications to be consistent with docs/i3-ipc.txt , making sure our logic integrates with our detection logic and moving to workspaces logic.  review ikings and related modules in  docs/budlabs-i3ass-81e224f956d0eab9.txt which represents some of the logic we may want to incorporate relative to our detection logic, and how we intercept window events and assining to the correct /workspace and monitors.  start with simple tests to determine if our logic is already working, and then make adjustments as needed."

## Clarifications

### Session 2025-10-22

- Q: When a window matches multiple rules with conflicting actions (e.g., Rule A says "workspace 2", Rule B says "workspace 5"), how should the system resolve this? → A: First matching rule wins (stop evaluation at first match)
- Q: When the daemon automatically restarts after a failure, how should it restore its state regarding active projects and window management? → A: Restore from filesystem state (read active project file + i3 window tree marks)
- Q: When a window is moved to a different workspace (not the currently visible one), should the system automatically switch focus to show that workspace? → A: Configurable per rule (rule specifies "focus: true/false")

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic Application Launch and Window Detection (Priority: P1)

As a user, when I launch an application (e.g., terminal, browser, editor), the system should automatically detect the new window and place it on the correct workspace based on configured rules, without requiring manual window movement or static configuration changes.

**Why this priority**: This is the core functionality that enables all other features. Without reliable window detection and workspace assignment, the entire dynamic system fails. This represents the minimum viable product.

**Independent Test**: Can be fully tested by launching any application and verifying it appears on the expected workspace. Delivers immediate value by eliminating manual window management.

**Acceptance Scenarios**:

1. **Given** no applications are running, **When** user launches a terminal application, **Then** the window appears on workspace 1 (terminal workspace) within 500ms, with focus behavior determined by the terminal's rule configuration
2. **Given** user is on workspace 3 and VS Code rule has focus=true, **When** user launches VS Code, **Then** the window appears on workspace 2 (code workspace) and workspace automatically switches to show it
3. **Given** multiple windows of the same application exist, **When** user launches a new instance, **Then** the new window appears on the appropriate workspace based on project context or application type
4. **Given** a window is launched, **When** system detects the window class and instance, **Then** the window is automatically marked with appropriate project context markers

---

### User Story 2 - Project-Scoped Window Management (Priority: P2)

As a user working on multiple projects, when I switch project contexts, the system should automatically show/hide relevant application windows and launch new applications in the correct project context, so I can maintain clean separation between different work contexts.

**Why this priority**: This builds on P1 to add project-aware behavior. It significantly enhances productivity for users juggling multiple projects but depends on the basic window detection working first.

**Independent Test**: Can be tested by creating two projects, switching between them, and verifying that project-scoped applications (terminal, editor) are hidden/shown appropriately while global applications (browser) remain visible. Delivers value by reducing cognitive load and workspace clutter.

**Acceptance Scenarios**:

1. **Given** user has active project "NixOS" with terminal and editor windows open, **When** user switches to project "Stacks", **Then** NixOS windows are hidden and Stacks-related windows become visible
2. **Given** user is in project "NixOS" context, **When** user launches a terminal, **Then** the terminal opens in the NixOS project directory with appropriate session context
3. **Given** user has multiple project-scoped applications open, **When** user clears project context (returns to global mode), **Then** all project-scoped windows are hidden and only global applications remain visible
4. **Given** a new window is launched in a project context, **When** system assigns the window, **Then** the window is marked with the project identifier for future management

---

### User Story 3 - Multi-Monitor Workspace Distribution (Priority: P3)

As a user with multiple monitors, when I connect or disconnect displays, the system should automatically redistribute workspaces across available monitors according to configured rules, ensuring optimal use of screen real estate without manual workspace reassignment.

**Why this priority**: This enhances the multi-monitor experience but is not critical for single-monitor users. It depends on P1 working correctly and provides incremental value for users with multiple displays.

**Independent Test**: Can be tested by connecting/disconnecting a second monitor and verifying workspaces are redistributed according to rules (e.g., workspaces 1-2 on primary, 3-9 on secondary). Delivers value by automating monitor configuration.

**Acceptance Scenarios**:

1. **Given** user has one monitor active, **When** user connects a second monitor, **Then** workspaces 3-9 are automatically assigned to the second monitor within 2 seconds
2. **Given** user has two monitors with distributed workspaces, **When** user disconnects the second monitor, **Then** all workspaces consolidate to the primary monitor without losing window placement
3. **Given** user has three monitors, **When** system detects monitors, **Then** workspaces distribute as: 1-2 on primary, 3-5 on secondary, 6-9 on tertiary
4. **Given** windows exist on a workspace that moves monitors, **When** workspace is reassigned, **Then** windows remain on their workspace and move with it to the new monitor

---

### User Story 4 - Application Rule Configuration (Priority: P3)

As a user, I should be able to define rules for how specific applications behave (which workspace, project-scoped vs global, floating vs tiled) through configuration files, so the system adapts to my personal workflow preferences without modifying static configuration files.

**Why this priority**: This provides customization and flexibility but depends on P1 and P2 working. Users can get value from the system with default rules before needing custom configuration.

**Independent Test**: Can be tested by adding a rule for a new application type and verifying it's applied when the application launches. Delivers value by making the system adaptable to individual workflows.

**Acceptance Scenarios**:

1. **Given** user defines a rule "assign class=Firefox to workspace 3", **When** user launches Firefox, **Then** Firefox appears on workspace 3 regardless of current workspace
2. **Given** user defines a rule "mark class=Ghostty as project-scoped", **When** user launches Ghostty in a project context, **Then** the window is tagged with the project identifier and hidden when switching projects
3. **Given** user defines a rule with window property patterns (class, instance, title regex) and focus=false, **When** a matching window appears, **Then** the system applies all configured actions (workspace assignment, marking, layout) without switching the user's current workspace view
4. **Given** user updates a rule configuration, **When** the configuration is reloaded, **Then** new windows follow updated rules within 1 second without requiring system restart

---

### Edge Cases

- What happens when a window matches multiple conflicting rules (e.g., both project-scoped and global rules)?
  - System evaluates rules in order (project-specific, global, default) and applies the first matching rule, stopping evaluation to ensure predictable behavior
- How does system handle rapidly launched windows (10+ windows in 1 second)?
  - Event queue processes windows sequentially with 100ms max latency per window
- What happens when a window changes its class/title after initial detection?
  - System subscribes to property change events and re-evaluates rules
- How does system handle windows that appear before the event daemon starts?
  - On daemon startup, system scans existing windows and applies rules retroactively
- What happens when monitor configuration changes while windows are being launched?
  - System queues workspace reassignment until monitor changes complete, then processes pending windows
- How does system handle orphaned windows when a project is deleted?
  - Windows lose project markers but remain on their current workspace until manually managed
- What happens when a window fails to match any rules?
  - Window is assigned to the currently active workspace (i3's default behavior)
- How does system handle applications that spawn multiple windows (e.g., popup dialogs)?
  - Transient windows follow their parent window's workspace assignment

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect new windows within 100ms of window creation event via i3 IPC subscription
- **FR-002**: System MUST identify window properties (class, instance, title, window role, window type) using i3 IPC GET_TREE command
- **FR-003**: System MUST evaluate window properties against configured rules to determine workspace assignment
- **FR-004**: System MUST move windows to assigned workspaces using i3-msg commands
- **FR-005**: System MUST mark windows with project context identifiers when launched in project scope
- **FR-006**: System MUST hide/show project-scoped windows when project context changes
- **FR-007**: System MUST maintain global application visibility across all project contexts
- **FR-008**: System MUST detect monitor connection/disconnection events via i3 IPC output event subscription
- **FR-009**: System MUST redistribute workspaces across monitors according to monitor count rules
- **FR-010**: System MUST load application rules from JSON configuration files
- **FR-011**: System MUST support rule patterns including: exact match, regex match, and wildcard match for window properties
- **FR-011a**: System MUST support per-rule focus configuration to control whether workspace assignment triggers automatic workspace switching
- **FR-012**: System MUST evaluate rules in order (project-specific first, then global, then default) and apply the first matching rule, stopping evaluation once a match is found
- **FR-013**: System MUST persist project configuration (name, directory, scoped applications) in JSON format
- **FR-014**: System MUST re-evaluate windows when their properties change (title, class, etc.)
- **FR-015**: System MUST provide event logging for debugging window detection and rule application
- **FR-016**: System MUST run as a long-lived daemon process with automatic restart on failure, restoring state from filesystem (active project configuration) and i3 IPC (window marks and workspace state)
- **FR-017**: System MUST expose status endpoint for monitoring daemon health
- **FR-018**: System MUST queue window processing events during system transitions (monitor changes, i3 restarts)
- **FR-019**: System MUST scan and process existing windows when daemon starts
- **FR-020**: System MUST support configuration reload without daemon restart
- **FR-021**: System MUST validate rule syntax when loading configuration and report errors
- **FR-022**: System MUST distinguish between project-scoped and global applications in configuration
- **FR-023**: System MUST support workspace-to-monitor assignment rules based on monitor count (1, 2, 3+)
- **FR-024**: System MUST handle window transient relationships (dialog windows follow parent)
- **FR-025**: System MUST integrate with existing i3pm Python module architecture

### Key Entities *(include if feature involves data)*

- **Window**: Represents an application window with properties (id, class, instance, title, workspace, marks, parent). Tracked via i3 IPC events.
- **Workspace**: Represents an i3 workspace with properties (number, name, visible, focused, output/monitor). Managed via i3 IPC commands.
- **Project**: Represents a work context with properties (name, directory, icon, display name, scoped application classes). Persisted in JSON configuration.
- **Application Rule**: Defines window behavior with properties (match criteria, target workspace, project scope, focus behavior, actions). Loaded from JSON configuration. The focus property determines whether moving a window to its assigned workspace should switch the user's view to that workspace.
- **Monitor/Output**: Represents a physical display with properties (name, active, primary, current workspace, dimensions). Detected via i3 IPC output events.
- **Event**: Represents an i3 IPC event (window created, property changed, workspace focus, output changed) with timestamp and payload. Processed by daemon.

## Technical Research & Integration Decisions

### i3-resurrect Analysis

**Decision Date**: 2025-10-22

After comprehensive analysis of i3-resurrect (see `i3-resurrect-analysis.md`), we determined:

**❌ DO NOT USE as external dependency or fork**

**Rationale**:
- **Different Problem Domain**: i3-resurrect solves workspace layout persistence (save/restore on reboot), while Feature 024 solves dynamic window routing (real-time workspace assignment)
- **Architectural Mismatch**: i3-resurrect uses synchronous i3ipc with Click CLI for manual operations, while we need async i3ipc.aio with event-driven daemon for automatic operations
- **Unnecessary Dependencies**: Would add Click, xdotool, psutil without delivering value for our use case
- **GPL v3 License**: Strong copyleft could constrain future licensing choices

**✅ EXTRACT PATTERNS ONLY**

**What We Learn and Adopt**:
1. **Window Property Extraction**: Comprehensive coverage (class, instance, title, window_role, window_type) from i3-resurrect/treeutils.py
2. **Swallow Criteria Matching**: Regex pattern matching with proper escaping for special characters
3. **Configuration Structure**: Per-window override capability in JSON configuration
4. **Testing Patterns**: Unit test structure for tree traversal and property extraction

**What We Reimpleme nt in Our Architecture**:
- `models/window_properties.py`: Pydantic model with async extraction from i3ipc.aio containers
- `core/window_rules.py`: First-match rule engine with regex/wildcard/exact match support
- `core/workspace_manager.py`: Window assignment using i3-msg commands (not xdotool unmap/remap)

**Key Difference**: i3-resurrect saves layouts to JSON files for manual restore; we apply rules to live windows in real-time via event subscriptions. These are complementary systems solving orthogonal problems.

**Future Consideration**: If users request layout persistence (survive reboots), we can add i3-resurrect as a separate, complementary tool without code coupling. Out of scope for Feature 024.

See detailed analysis: `specs/024-update-replace-test/i3-resurrect-analysis.md`

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Windows are detected and assigned to correct workspace within 500ms of application launch for 99% of cases
- **SC-002**: Project context switches complete (hiding/showing all relevant windows) within 1 second for projects with up to 20 windows
- **SC-003**: System processes 50+ window events per second without dropping events or exceeding 2-second latency
- **SC-004**: Monitor configuration changes trigger workspace redistribution within 2 seconds
- **SC-005**: Daemon achieves 99.9% uptime over 30-day periods with automatic restart on failure
- **SC-006**: Configuration reload completes within 1 second and applies new rules to subsequent windows
- **SC-007**: Users can configure rules for 100+ distinct application patterns without performance degradation
- **SC-008**: System memory usage remains under 50MB during normal operation with 50 active windows
- **SC-009**: Zero windows are lost or orphaned during monitor changes or daemon restarts
- **SC-010**: Users can validate their rule configuration and receive actionable error messages within 5 seconds
- **SC-011**: Event logs provide sufficient detail to diagnose 95% of window management issues without code inspection
- **SC-012**: Existing i3pm functionality (project switching, CLI commands) continues working without modification
- **SC-013**: Daemon restarts restore active project context and window associations within 2 seconds, maintaining 100% window mark accuracy
