# Feature Specification: Unified Project-Scoped Window Management

**Feature Branch**: `037-given-our-top`
**Created**: 2025-10-25
**Status**: Draft
**Input**: User description: "given our top-level change in how we window match / launch apps, injecting I3PM_* variables, add a new feature to strengthen/enhance project management capabilities, switching projects should hide apps that are not related to active project, window managment, making sure that applications are mapped to workspaces, and workpsaces are correctly mapped to correct monitors, etc. one key principle for our spec: don't worry about backwards compatibility. we only want the optimal solution (which will now use walker/elephant). as we udpate/replace current logic/code, we should discard legacy approaches, instead of attempting two maintain two sets."

## User Scenarios & Testing

### User Story 1 - Automatic Window Filtering on Project Switch (Priority: P1) 🎯 MVP

When I switch from one project to another, all windows belonging to the previous project automatically hide (move to scratchpad), leaving only windows relevant to the new project and global applications visible. This eliminates visual clutter and prevents me from accidentally working in the wrong project context.

**Why this priority**: Core value proposition. Enables focused, context-aware work environment. Without this, multi-project workflows remain chaotic and error-prone.

**Independent Test**: Launch VS Code and terminal in "nixos" project. Switch to "stacks" project. Verify VS Code and terminal disappear (hidden in scratchpad). Global apps like Firefox remain visible. Switch back to "nixos" and verify windows reappear on their original workspaces.

**Acceptance Scenarios**:

1. **Given** I'm in project "nixos" with VS Code (WS2), terminal (WS1), and Firefox (WS3) open, **When** I switch to project "stacks", **Then** VS Code and terminal move to scratchpad (hidden), Firefox remains visible on WS3
2. **Given** I'm in project "stacks" with 5 scoped windows, **When** I clear active project (enter global mode), **Then** all 5 windows hide, only global apps remain visible
3. **Given** I have VS Code open in both "nixos" and "stacks" projects (two instances), **When** I switch from "nixos" to "stacks", **Then** only the "nixos" VS Code hides, "stacks" VS Code remains visible
4. **Given** I switch to a project with no currently running applications, **When** the switch completes, **Then** I see only global applications and empty workspaces for scoped apps

---

### User Story 2 - Workspace Persistence Across Switches (Priority: P1) 🎯 MVP

When I return to a previously active project, all windows restore to the exact workspaces where they were running, preserving my workspace organization. This maintains my mental model and eliminates the need to reorganize windows after every project switch.

**Why this priority**: Critical for efficiency. Users develop muscle memory for workspace layouts. Breaking this creates frustration and wastes time reorganizing.

**Independent Test**: In "nixos" project, move VS Code from WS2 to WS5. Switch to "stacks". Switch back to "nixos". Verify VS Code returns to WS5 (not default WS2).

**Acceptance Scenarios**:

1. **Given** I manually moved VS Code to WS5 in project "nixos", **When** I switch away and return to "nixos", **Then** VS Code restores to WS5
2. **Given** a window is floating (not tiled) when I leave a project, **When** I return to that project, **Then** the window restores as floating
3. **Given** I have terminal on WS1 and lazygit on WS7 in "nixos", **When** I switch to "stacks" then back, **Then** terminal returns to WS1 and lazygit to WS7

---

### User Story 3 - Guaranteed Workspace Assignment on Launch (Priority: P2)

When I launch an application using Walker/Elephant, it automatically opens on its configured workspace regardless of which workspace I'm currently viewing. This ensures my workspace organization remains consistent and applications always appear where I expect them.

**Why this priority**: Prevents workspace chaos. Users shouldn't need to move windows after launching them. Particularly important for applications with specific workspace purposes (code editors, terminals, browsers).

**Independent Test**: Be on workspace 5. Launch VS Code via Walker (configured for WS2). Verify VS Code opens on WS2, not WS5.

**Acceptance Scenarios**:

1. **Given** I'm viewing workspace 7, **When** I launch VS Code (preferred_workspace=2) via Walker, **Then** VS Code opens on workspace 2
2. **Given** I'm on workspace 3, **When** I launch terminal (preferred_workspace=1), **Then** terminal opens on workspace 1
3. **Given** an application's preferred workspace is on a different monitor, **When** I launch it, **Then** it appears on the correct workspace on the correct monitor

---

### User Story 4 - Automatic Monitor-Workspace Redistribution (Priority: P2)

When I connect or disconnect monitors, workspaces automatically redistribute according to my configuration without manual intervention. This ensures my workspace layout adapts seamlessly to changing hardware configurations (docking/undocking laptop, conference room projector, etc.).

**Why this priority**: Quality-of-life enhancement for mobile workers and multi-monitor setups. Eliminates manual workspace juggling when hardware changes.

**Independent Test**: Configure 2-monitor layout (WS1-2 on primary, WS3-9 on secondary). Disconnect secondary monitor. Verify all workspaces move to primary. Reconnect. Verify WS3-9 move back to secondary.

**Acceptance Scenarios**:

1. **Given** I have 2 monitors with WS1-2 on primary, WS3-9 on secondary, **When** I disconnect secondary monitor, **Then** all workspaces consolidate to primary monitor
2. **Given** I'm using laptop undocked (1 monitor), **When** I dock it (3 monitors), **Then** workspaces redistribute according to my 3-monitor configuration within 1 second
3. **Given** I have active applications on affected workspaces, **When** monitor configuration changes, **Then** no windows are lost or become inaccessible

---

### User Story 5 - Visual Status Indicators (Priority: P3)

When windows are hidden due to project switching, I can see which project each hidden window belongs to and how many windows are hidden per project. This provides transparency into system state and helps me understand what's happening behind the scenes.

**Why this priority**: Nice-to-have for debugging and confidence. Not critical for core functionality but improves user understanding and troubleshooting.

**Independent Test**: Switch from "nixos" (3 windows) to "stacks". Use status command to list hidden windows. Verify it shows: "3 windows hidden for project 'nixos': VS Code (WS2), Terminal (WS1), Lazygit (WS7)".

**Acceptance Scenarios**:

1. **Given** I switched from "nixos" to "stacks" hiding 3 windows, **When** I check window status, **Then** I see "3 windows hidden from 'nixos': VS Code (WS2), Terminal (WS1), Lazygit (WS7)"
2. **Given** I'm in global mode with all scoped windows hidden, **When** I check status, **Then** I see per-project hidden window counts
3. **Given** multiple projects with hidden windows, **When** I view status, **Then** hidden windows are grouped by project name

---

### Edge Cases

- **Rapid project switching**: If user switches projects quickly (< 1 second apart), queue switch requests and process sequentially to prevent race conditions
- **Orphaned windows**: If a window's process dies but window persists, and `/proc/<pid>/environ` becomes unreadable, classify as global scope (always visible)
- **Manual workspace moves**: If user manually drags a scoped window to a different workspace, persist that custom location (respect user override)
- **Missing environment variables**: Windows launched before I3PM_* support (legacy windows) default to global scope
- **Invalid workspace assignments**: If registry specifies workspace that doesn't exist or is invalid, fall back to workspace 1
- **Monitor configuration errors**: If workspace-monitor mapping file is missing or corrupted, fall back to single-monitor mode (all workspaces on primary)
- **Maximum window limits**: System handles up to 30 windows per project before performance may degrade
- **Scratchpad conflicts**: If user manually places windows in scratchpad, don't interfere with them during project switches

## Requirements

### Functional Requirements

- **FR-001**: System MUST hide scoped windows by moving them to scratchpad when switching away from their project
- **FR-002**: System MUST determine window project association by reading `I3PM_PROJECT_NAME` from `/proc/<pid>/environ`
- **FR-003**: System MUST keep global applications (I3PM_SCOPE=global) visible across all project switches
- **FR-004**: System MUST restore hidden windows to their last-known workspace when returning to a project
- **FR-005**: System MUST preserve floating/tiled state of windows across project switches
- **FR-006**: System MUST handle multiple instances of the same application independently (each with unique I3PM_APP_ID)
- **FR-007**: System MUST launch applications on their configured workspace (preferred_workspace from registry) regardless of current focus
- **FR-008**: System MUST automatically redistribute workspaces across monitors when monitor count changes
- **FR-009**: System MUST apply workspace-monitor configuration within 1 second of monitor hotplug event
- **FR-010**: System MUST queue concurrent project switch requests and process them sequentially
- **FR-011**: System MUST complete window filtering for project switches within 2 seconds for up to 30 windows
- **FR-012**: System MUST treat windows without I3PM_* variables as global scope (backward compatibility with non-registry apps)
- **FR-013**: System MUST persist custom workspace locations when user manually moves windows
- **FR-014**: System MUST provide CLI command to list all hidden windows grouped by project
- **FR-015**: System MUST fall back to single-monitor mode if workspace-monitor configuration is invalid

### Key Entities

- **Project**: Named workspace context with directory and metadata
  - Attributes: name, directory, display_name, icon
  - Relationships: Has many Windows (via I3PM_PROJECT_NAME)

- **Window**: i3-managed application instance with project association
  - Attributes: window_id, class, title, pid, workspace_number, floating_state, I3PM_PROJECT_NAME
  - Relationships: Belongs to Project, Resides on Workspace
  - State: visible (on workspace) or hidden (in scratchpad)

- **Application**: Launchable program defined in registry
  - Attributes: name, scope (scoped/global), preferred_workspace, expected_class
  - Relationships: Launched instances become Windows

- **Workspace**: i3 workspace container
  - Attributes: number (1-70), name, monitor_assignment
  - Relationships: Assigned to Monitor, Contains Windows

- **Monitor**: Physical display output
  - Attributes: name, role (primary/secondary/tertiary), active_state
  - Relationships: Hosts Workspaces
  - Events: connect, disconnect (triggers redistribution)

## Success Criteria

### Measurable Outcomes

- **SC-001**: Project switches complete in under 2 seconds for workspaces with up to 30 windows
- **SC-002**: 100% of scoped windows correctly hide when switching away from their project (measured via window state checks)
- **SC-003**: 100% of windows restore to correct workspace when returning to their project
- **SC-004**: Global applications remain visible 100% of the time across all project switches
- **SC-005**: Applications launched via Walker/Elephant appear on correct workspace 100% of the time
- **SC-006**: Monitor configuration changes trigger workspace redistribution within 1 second
- **SC-007**: Zero window losses or crashes during project switching operations
- **SC-008**: Custom workspace positions persist across project switches with 100% accuracy
- **SC-009**: Users can identify all hidden windows and their projects via single CLI command
- **SC-010**: Users report improved focus and reduced errors when working across multiple projects (qualitative feedback)

## Assumptions

- Feature 035 (I3PM_* environment injection) is fully implemented and operational
- Feature 033 (workspace-monitor mapping) configuration exists and is valid
- Walker/Elephant launcher is the primary application launch mechanism (legacy launchers removed)
- i3 window manager is the target environment
- i3pm daemon runs as systemd user service with proper permissions
- `/proc/<pid>/environ` is readable for all application processes
- xprop utility is available for window PID lookup
- Application registry (app-registry.nix) contains scope and preferred_workspace for all apps
- Users have defined workspace-monitor mapping configuration
- Maximum expected load: 30 windows per project, 10-15 projects total
- Single user per system (no multi-user/multi-seat considerations)
- Monitor changes are infrequent (not happening during mid-switch)

## Scope

### In Scope

- Automatic window hiding/showing based on project context
- Window workspace persistence across switches
- Registry-based workspace assignment on app launch
- Automatic workspace-monitor redistribution on hardware changes
- CLI visibility into hidden windows and their project associations
- Graceful handling of legacy windows (no I3PM_* variables)
- Performance optimization for up to 30 windows per project
- Queue management for rapid project switches
- Floating window state preservation

### Out of Scope

- Creating new project management UI (reuses existing `i3pm project switch`)
- Modifying I3PM_* environment variable injection (Feature 035 handles this)
- Adding new registry fields or schema changes
- Layout save/restore functionality (Feature 035 covers this)
- Multi-user or multi-seat configurations
- Custom workspace-monitor configuration UI (uses existing config from Feature 033)
- Performance beyond 30 windows per project
- Integration with non-Walker/Elephant launchers (no backward compatibility)
- Window positioning within workspaces (only workspace assignment)
- Automatic workspace cleanup (empty workspace removal)

## Dependencies

- **Feature 035**: Registry-Centric Project & Workspace Management (I3PM_* variables, must be complete)
- **Feature 033**: Declarative Workspace-to-Monitor Configuration (must be available)
- **Feature 034**: Walker/Elephant unified launcher (must be primary launcher)
- **Feature 025**: Visual Window State Management (for `i3pm windows` command)
- **i3 window manager**: Core window management and scratchpad functionality
- **systemd**: i3pm daemon service management and restart handling
- **xprop**: Window PID extraction from X11 properties
- **/proc filesystem**: Reading process environment variables
- **Application registry**: Complete definitions with scope and workspace assignments

## Open Questions

None - specification is complete based on existing Feature 035 implementation and clear user requirements. The principle of "no backward compatibility" simplifies design decisions significantly.
