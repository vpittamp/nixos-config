# Feature Specification: Project-Scoped Application Workspace Management

**Feature Branch**: `011-project-scoped-application`
**Created**: 2025-10-19
**Status**: Draft
**Input**: User description: "Project-scoped application workspace management with dynamic window reassignment"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switch Project Context and See Relevant Applications (Priority: P1)

A developer is working on multiple projects throughout the day. When they switch from the "NixOS Configuration" project to the "Stacks Platform" project, they want to immediately see only the VS Code instance editing the Stacks codebase and the terminal session in the Stacks directory. The VS Code instance for NixOS configuration and its terminals should be automatically hidden.

**Why this priority**: This is the core value proposition - enabling focused, context-aware work by automatically managing application visibility based on project context. Without this, users must manually hunt for the right windows across workspaces.

**Independent Test**: Can be fully tested by activating a project (e.g., "Stacks"), launching VS Code and terminal, then switching to another project (e.g., "NixOS") and verifying the first project's applications are hidden while the second project's applications become visible in their designated workspaces.

**Acceptance Scenarios**:

1. **Given** user is working on "NixOS" project with VS Code open on workspace 2, **When** user switches to "Stacks" project via project switcher, **Then** NixOS VS Code is hidden and Stacks VS Code (if exists) appears on workspace 2
2. **Given** user has "Stacks" project active and VS Code is open, **When** user switches to "NixOS" project, **Then** workspace 2 shows NixOS VS Code instance and Stacks VS Code is hidden
3. **Given** no VS Code instance exists for the newly selected project, **When** user switches to that project, **Then** workspace 2 is empty (previous project's VS Code is hidden)
4. **Given** user is on workspace 2 with active project's VS Code visible, **When** user switches to workspace 1, **Then** active project's terminal applications are visible on workspace 1

---

### User Story 2 - Launch Applications in Project Context (Priority: P1)

A developer activates the "NixOS Configuration" project and presses the VS Code quick launch keybinding. The system launches VS Code opening the /etc/nixos directory and automatically assigns it to workspace 2. When they press the terminal keybinding, Ghostty opens using sesh to connect to the NixOS project session in /etc/nixos. When they press the lazygit keybinding, it opens connected to the /etc/nixos repository. When they press the yazi keybinding, it opens with /etc/nixos as the starting directory.

**Why this priority**: Project-aware launching is essential for the feature to be useful. Without it, users would manually need to configure each application launch, defeating the purpose of project management.

**Independent Test**: Can be tested by activating a project, using quick launch keybindings, and verifying applications open with correct project context (directory, session) and appear on expected workspaces.

**Acceptance Scenarios**:

1. **Given** "NixOS" project is active, **When** user presses Mod+c (VS Code quick launch), **Then** VS Code opens with /etc/nixos directory and appears on workspace 2
2. **Given** "Stacks" project is active, **When** user presses Mod+Return (terminal quick launch), **Then** Ghostty launches with sesh connecting to Stacks project session in /home/vpittamp/stacks and appears on workspace 1
3. **Given** "Personal" project is active, **When** user presses Mod+g (lazygit quick launch), **Then** lazygit opens in the /home/vpittamp/projects repository and appears on workspace 7
4. **Given** "NixOS" project is active, **When** user presses Mod+y (yazi quick launch), **Then** yazi opens with /etc/nixos as the starting directory and appears on workspace 5

---

### User Story 3 - Access Global Applications Across Projects (Priority: P2)

A developer needs to reference documentation in Firefox or watch a video on YouTube PWA while working on any project. These global applications should remain accessible regardless of which project is active and should not be hidden when switching projects.

**Why this priority**: While project-scoped applications are the primary focus, maintaining access to global tools prevents the system from being overly restrictive. This is P2 because the feature is still valuable without it (users could manually manage global apps).

**Independent Test**: Can be tested by opening Firefox, YouTube PWA, or other global applications, then switching between projects multiple times and verifying these applications remain visible and accessible throughout.

**Acceptance Scenarios**:

1. **Given** Firefox is open on workspace 3 and "NixOS" project is active, **When** user switches to "Stacks" project, **Then** Firefox remains visible on workspace 3
2. **Given** YouTube PWA is open on workspace 4, **When** user switches between any projects, **Then** YouTube PWA remains accessible on workspace 4
3. **Given** user launches Firefox while "Stacks" project is active, **When** user switches to "NixOS" project, **Then** Firefox remains open and accessible

---

### User Story 4 - See Current Project in Status Bar (Priority: P2)

A developer wants to quickly see which project context they're currently in without having to check window titles or directory paths. The status bar displays the active project name with an icon, allowing instant visual confirmation of the current context.

**Why this priority**: Visual feedback is important for context awareness but not critical for core functionality. The feature works without it, but user experience is significantly improved with clear project indication.

**Independent Test**: Can be tested by activating different projects and verifying the status bar (polybar) displays the correct project name and icon, and clicking the project indicator opens the project switcher.

**Acceptance Scenarios**:

1. **Given** "NixOS" project is active, **When** user looks at polybar, **Then** polybar displays " NixOS Configuration"
2. **Given** no project is active (global mode), **When** user looks at polybar, **Then** polybar displays "No Project"
3. **Given** "Stacks" project is displayed in polybar, **When** user clicks the project indicator, **Then** project switcher menu opens
4. **Given** "Personal" project is displayed in polybar, **When** user right-clicks the project indicator, **Then** project is cleared and polybar shows "No Project"

---

### User Story 5 - Adaptive Monitor Assignment (Priority: P2)

A developer works with different monitor setups throughout the day: single monitor at home, dual monitors at the office, and triple monitors at their desk. When workspaces are created or accessed, the system automatically assigns them to appropriate monitors based on workspace priority and the number of available monitors. Workspace 1 (terminal) and workspace 2 (code) always appear on the primary monitor, while other workspaces distribute across secondary monitors when available.

**Why this priority**: Multi-monitor support is essential for productivity but should adapt to different configurations without manual reconfiguration. This is P2 because the feature works on single monitors but significantly enhances multi-monitor workflows.

**Independent Test**: Can be tested by configuring 1, 2, or 3 monitors and verifying workspaces are distributed appropriately, with high-priority workspaces on primary monitor and others distributed across available monitors.

**Acceptance Scenarios**:

1. **Given** single monitor setup, **When** user accesses any workspace, **Then** all workspaces appear on the single monitor
2. **Given** dual monitor setup, **When** user accesses workspace 1 or 2, **Then** workspace appears on primary monitor, **When** user accesses workspaces 3-9, **Then** workspaces distribute to secondary monitor based on priority
3. **Given** triple monitor setup, **When** user accesses workspaces, **Then** workspaces 1-2 appear on primary monitor, workspaces 3-5 on second monitor, workspaces 6-9 on third monitor
4. **Given** user has configured workspace monitor priorities in project definition, **When** workspaces are created, **Then** workspaces respect priority ordering when assigning to available monitors

---

### User Story 6 - Clear Project Context for Global Work (Priority: P3)

A developer finishes project-specific work and wants to return to "global mode" where all applications follow standard workspace assignments without project filtering. They trigger the "clear project" action and all hidden applications become visible again.

**Why this priority**: This provides an escape hatch from project mode but is not essential since users can simply ignore the project system or switch to a different project. It's nice-to-have for flexibility.

**Independent Test**: Can be tested by activating a project with multiple applications open, clearing the project, and verifying all previously hidden applications become visible and workspace assignments return to default behavior.

**Acceptance Scenarios**:

1. **Given** "NixOS" project is active with some applications hidden, **When** user presses Mod+Shift+p (clear project), **Then** all previously hidden applications become visible and polybar shows "No Project"
2. **Given** "Stacks" project is active, **When** user clears the project, **Then** subsequent application launches follow global workspace assignments instead of project-specific rules

---

### Edge Cases

- What happens when a project is switched but no applications are currently open for the newly selected project? (Empty workspaces should be shown, previous project's apps hidden)
- How does the system handle launching a project-scoped application when no project is active? (Falls back to global workspace assignment)
- What happens when a user manually moves a project-scoped application to a different workspace? (Application remains on the manually chosen workspace until project is switched or application is relaunched)
- How does the system handle multiple instances of the same project-scoped application within one project? (All instances for that project are shown/hidden together, assigned to the same workspace)
- What happens when switching projects while an application is launching? (Application assignment is based on project context at launch time)
- How does the system handle existing windows when switching from global mode to a project? (Existing windows that match the project context become visible in designated workspaces, others are hidden)
- What happens when a monitor is disconnected while workspaces are displayed on it? (Workspaces reassign to remaining monitors based on priority)
- How does the system handle hotplugging a new monitor? (Workspaces redistribute according to priority assignments for the new monitor count)
- What happens when workspace monitor priority conflicts with current monitor availability? (System uses fallback logic to assign to next available monitor)

## Requirements *(mandatory)*

### Functional Requirements

#### Application Classification

- **FR-001**: System MUST distinguish between two classes of applications: project-scoped (VS Code, Ghostty terminals, lazygit, yazi) and non-project-scoped (Firefox, YouTube PWA, K9s, etc.)
- **FR-002**: System MUST allow configuration to specify which applications are project-scoped vs. global in the project definition schema

#### Project Context Management

- **FR-003**: System MUST maintain a single active project state in ~/.config/i3/current-project
- **FR-004**: System MUST provide an interactive project switcher accessible via keybinding (Mod+p)
- **FR-005**: System MUST allow clearing the active project to return to global mode via keybinding (Mod+Shift+p)
- **FR-006**: System MUST display the current active project in the status bar with project name and icon
- **FR-007**: System MUST support clicking the status bar project indicator to open the project switcher
- **FR-008**: System MUST support right-clicking the status bar project indicator to clear the active project

#### Project-Scoped Application Launching

- **FR-009**: System MUST launch VS Code instances opening the project directory (without --user-data-dir flag)
- **FR-010**: System MUST launch Ghostty terminal applications using sesh to connect to project session in the project's directory
- **FR-011**: System MUST launch lazygit connecting to the project's repository directory
- **FR-012**: System MUST launch yazi with the project directory as the starting directory for file navigation
- **FR-013**: System MUST embed project identification in window properties (title, WM_CLASS, or marks) for project-scoped applications
- **FR-014**: System MUST provide project-aware launcher scripts for VS Code, Ghostty, lazygit, and yazi
- **FR-015**: Quick launch keybindings (Mod+c for VS Code, Mod+Return for Ghostty, Mod+g for lazygit, Mod+y for yazi) MUST respect active project context

#### Dynamic Workspace Assignment

- **FR-016**: System MUST assign project-scoped applications to fixed workspaces regardless of project (workspace 2 for VS Code, workspace 1 for Ghostty, workspace 7 for lazygit, workspace 5 for yazi)
- **FR-017**: System MUST move project-scoped applications to their designated workspace when project context changes
- **FR-018**: System MUST hide (move to scratchpad or high-numbered workspace) project-scoped applications not associated with the active project
- **FR-019**: System MUST show (move to designated workspace) project-scoped applications associated with the newly activated project
- **FR-020**: System MUST maintain global applications in their assigned workspaces regardless of project changes

#### Project-to-Window Matching

- **FR-021**: System MUST identify which project a VS Code instance belongs to by reading window properties (title or custom property)
- **FR-022**: System MUST identify which project a Ghostty terminal instance belongs to by reading window properties or sesh session information
- **FR-023**: System MUST identify which project a lazygit instance belongs to by reading window properties or repository path
- **FR-024**: System MUST identify which project a yazi instance belongs to by reading window properties or working directory
- **FR-025**: System MUST handle cases where application window properties cannot be read (fallback to assuming current project context)

#### Workspace Range Elimination

- **FR-026**: System MUST NOT use workspace number ranges (10-19, 20-29, 30-39) for project separation
- **FR-027**: System MUST use single fixed workspaces (1-9) with dynamic content based on active project
- **FR-028**: Project definitions MUST NOT include workspace_offset or workspace_range fields

#### Multi-Monitor Support

- **FR-029**: System MUST support workspace assignment to monitors based on workspace priority or monitor number configuration
- **FR-030**: System MUST detect available monitors and adapt workspace distribution dynamically
- **FR-031**: System MUST handle 1-monitor, 2-monitor, and 3-monitor configurations
- **FR-032**: Workspaces 1 and 2 (high priority) MUST always be assigned to the primary monitor
- **FR-033**: System MUST distribute remaining workspaces (3-9) across secondary monitors when available
- **FR-034**: System MUST reassign workspaces when monitors are added or removed (hotplug support)
- **FR-035**: System MUST allow workspace-to-monitor assignment configuration in project definitions with fallback logic for unavailable monitors

### Key Entities *(mandatory for features involving data)*

- **Project**: Represents a development context with a name, directory path, icon, and list of project-scoped applications. Examples: "NixOS Configuration", "Stacks Platform", "Personal Projects"
- **Application Class**: Classification of an application as either project-scoped (isolated per project) or global (accessible across all projects). Attributes: application name, wmClass pattern, projectScoped boolean flag, workspace assignment
- **Active Project State**: Current project context stored in ~/.config/i3/current-project, includes project ID, name, directory, icon, and activation timestamp
- **Window-Project Association**: Mapping between open windows and their associated project, derived from window properties (title, WM_CLASS, or custom marks)
- **Workspace**: Numbered workspace (1-9) with a priority level and optional monitor assignment. Contains applications that may be project-scoped or global
- **Monitor Configuration**: Detected monitor setup with primary monitor designation and available outputs. Determines workspace distribution across physical displays

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can switch between projects and see only relevant application instances in under 2 seconds (including window show/hide animations)
- **SC-002**: 100% of project-scoped applications (VS Code, Ghostty, lazygit, yazi) launched via quick launch keybindings open in the correct project context (directory, session, repository)
- **SC-003**: When switching projects, 100% of inactive project applications are hidden and 100% of active project applications are visible in their designated workspaces
- **SC-004**: Global applications (Firefox, YouTube PWA, etc.) remain accessible 100% of the time regardless of project switches
- **SC-005**: Status bar displays correct project name within 1 second of project activation or switching
- **SC-006**: User can complete the workflow "activate project → launch VS Code → launch Ghostty → launch lazygit → switch to different project → verify first project apps are hidden" in under 20 seconds
- **SC-007**: Zero instances of applications appearing in incorrect workspaces after project switching (workspace 2 for VS Code, workspace 1 for Ghostty, workspace 7 for lazygit, workspace 5 for yazi)
- **SC-008**: Workspaces correctly distribute across available monitors in 1-monitor, 2-monitor, and 3-monitor setups within 2 seconds of monitor configuration change
- **SC-009**: High-priority workspaces (1 and 2) always appear on primary monitor 100% of the time across all monitor configurations
- **SC-010**: When monitors are added or removed, workspaces reassign to available monitors within 3 seconds with zero application crashes or workspace content loss

## Assumptions

- i3 window manager supports moving windows between workspaces via i3-msg commands
- i3 IPC (Inter-Process Communication) API is available for querying window properties and executing dynamic commands
- i3 supports assigning workspaces to specific monitors and handles monitor hotplug events
- Polybar can execute scripts and update displayed text based on file changes or script output
- VS Code can open directories directly without requiring --user-data-dir flag for project isolation
- Ghostty terminal supports launching with commands (e.g., sesh session manager)
- Sesh (tmux session manager) is available and can create/connect to project-specific sessions
- Terminal applications (Ghostty) can set window titles via ANSI escape sequences or command-line arguments
- Lazygit can be launched with a specific repository directory
- Yazi can be launched with a starting directory
- Project state file (~/.config/i3/current-project) persists across i3 restarts
- System has i3-msg, jq, xrandr (for monitor detection), and standard Unix utilities available
- Project switching operations are triggered manually by user action (keybinding or polybar click), not automatically by directory changes
- Current project definitions in ~/.config/i3/projects.json are maintained and extended with application classification metadata
- Monitor detection via xrandr or i3 IPC provides reliable information about connected outputs and primary monitor

## Out of Scope

- Automatic project detection based on active window's working directory (PWD)
- Integration with version control systems (Git) for automatic project detection
- Project-specific keybindings or configuration beyond application context
- Workspace layouts or tiling arrangements within projects
- Per-monitor workspace ranges (e.g., monitor 1 has workspaces 1-5, monitor 2 has workspaces 6-10)
- Project session persistence and restoration across system reboots (beyond sesh session management)
- Browser tab or profile management per project (Firefox profiles)
- Application state synchronization between project contexts
- Project templates or scaffolding for creating new projects
- Advanced monitor profiles (saving/restoring specific monitor arrangements)
- Per-application monitor preferences within projects
