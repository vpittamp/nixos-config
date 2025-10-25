# Feature Specification: Registry-Centric Project & Workspace Management

**Feature Branch**: `035-now-that-we`
**Created**: 2025-10-25
**Status**: Draft
**Input**: User description: "now that we created a new way to launch apps using walker/elephant with our @home-modules/desktop/app-registry.nix, i want to update/replace our i3 project/workspace management to align with our new app launching protocol.  i want to centralize as much configuration via the app-registry such as workspace assignment and consider replacing our current mapping proccess.  we also need to make sure our window matching logic aligns with our new app launching, and we should build out our project management and layout functionalities.  ideally, our projects would point to our custom applications, and our layouts as well so that when we restore layout, we launch using the same methodology.  projects, should provide the ability to switch across application sets that we tag for the project.  we should rethink our logic for how we maintain applications that are associated with a project (how we launch, restore, etc).  all of our new functionality needs to inform our deno cli, and we should replace/update our cli to expose all the user related functions to view config, update, and monitor.  one key principle for our spec:  don't worry about backwards compatibility.  we only want the optimal solution (which will now use walker/elephant).  as we udpate/replace current logic/code, we should discard legacy approaches, instead of attempting two maintain two sets."

## User Scenarios & Testing

### User Story 1 - Launch Project Applications from Registry (Priority: P1)

As a developer, I want to launch applications for my current project using the centralized registry, so that all my project-scoped apps open in the correct workspace with proper context automatically.

**Why this priority**: This is the foundational capability that replaces the current ad-hoc launching system. Without this, none of the other features can work properly. It delivers immediate value by simplifying how users launch applications with project context.

**Independent Test**: Can be fully tested by switching to a project and launching any registered application (e.g., VS Code, terminal, file manager). Success means the app opens with the correct project directory and lands on the expected workspace.

**Acceptance Scenarios**:

1. **Given** a user has switched to the "nixos" project, **When** they launch VS Code from the registry, **Then** VS Code opens in workspace 1 with `/etc/nixos` as the working directory
2. **Given** a user has switched to the "stacks" project, **When** they launch a terminal from the registry, **Then** the terminal opens with a sesh session connected to the stacks project directory
3. **Given** no active project is set, **When** a scoped application is launched, **Then** the system uses the fallback behavior defined in the registry (skip, use_home, or error)
4. **Given** a user launches a global application (browser, Slack), **When** the app opens, **Then** it appears on its designated workspace regardless of active project

---

### User Story 2 - Environment-Based Window Filtering (Priority: P2)

As a developer, I want windows to automatically show/hide when I switch projects based on their launched environment, so that only relevant application instances are visible without manual window management or tag configuration.

**Why this priority**: This builds on P1 by automatically filtering windows based on which project they were launched with. Uses process environment variables to determine window ownership, eliminating the need for application tags and complex filtering logic.

**Independent Test**: Can be tested by launching applications in one project, switching to another project, and verifying that windows from the first project are automatically hidden while windows from the second project remain visible.

**Acceptance Scenarios**:

1. **Given** a user launches VS Code in the "nixos" project, **When** they switch to the "stacks" project, **Then** the nixos VS Code window is automatically hidden (moved to scratchpad)
2. **Given** a user has terminals open in multiple projects, **When** they switch between projects, **Then** only terminals belonging to the active project are visible
3. **Given** a global application (browser) is open, **When** the user switches projects, **Then** the global application remains visible regardless of project
4. **Given** a user switches to a project, **When** they view the workspace, **Then** only windows launched with that project's environment are shown

---

### User Story 3 - Deterministic Window Matching via Application IDs (Priority: P1)

As a developer, I want each application instance to have a unique identifier so that windows can be deterministically matched even when multiple instances of the same application are running, enabling accurate layout restore and window management.

**Why this priority**: This eliminates ambiguity in window matching. Traditional window class matching fails with multiple instances (e.g., multiple VS Code windows all have class="Code"). Application instance IDs injected at launch time enable exact window identification. This must work in parallel with P1.

**Independent Test**: Can be tested by launching multiple instances of the same application across different projects, then using /proc/<pid>/environ to verify each window has a unique I3PM_APP_ID and correct project association.

**Acceptance Scenarios**:

1. **Given** VS Code is launched for the "nixos" project, **When** the window appears, **Then** the daemon can read I3PM_APP_ID and I3PM_PROJECT_NAME from the process environment to uniquely identify it
2. **Given** multiple terminal instances are open, **When** querying window identities via /proc, **Then** each terminal has a distinct I3PM_APP_ID enabling exact identification
3. **Given** a layout restore operation launches VS Code, **When** the window appears, **Then** the daemon matches it to the expected application instance by comparing I3PM_APP_ID values
4. **Given** a user launches the same application in different projects, **When** switching projects, **Then** each window can be filtered based on its I3PM_PROJECT_NAME from the process environment

---

### User Story 4 - Save and Restore Project Layouts (Priority: P3)

As a developer, I want to save my current window arrangement as a project layout and restore it later, so I can quickly resume work with my preferred workspace setup.

**Why this priority**: This is a productivity enhancement that builds on P1-P3. It's valuable but not essential for the core registry-centric workflow. Users can still launch apps manually even without saved layouts.

**Independent Test**: Can be tested by arranging windows across workspaces, saving the layout for a project, closing all windows, then restoring the layout. Success means all applications reopen in their original positions using the registry launch protocol.

**Acceptance Scenarios**:

1. **Given** a user has VS Code on WS1, terminals on WS3, and browsers on WS2, **When** they save the project layout, **Then** the system captures window positions, sizes, and which registry applications are open
2. **Given** a saved project layout exists, **When** the user restores it, **Then** all applications launch using the registry protocol and windows appear in their saved positions
3. **Given** a layout references an application no longer in the registry, **When** the user restores the layout, **Then** the system skips that application and logs a warning

---

### User Story 5 - CLI for Config Management and Monitoring (Priority: P2)

As a developer, I want command-line tools to view, update, and monitor my registry configuration and projects, so I can manage my workspace setup efficiently from the terminal.

**Why this priority**: This provides essential visibility and control over the new registry-centric system. Users need to be able to inspect config, troubleshoot issues, and make changes without editing Nix files directly.

**Independent Test**: Can be tested by running CLI commands to list applications, show project details, view current workspace assignments, and update project settings. Success means users can perform all common tasks via the CLI.

**Acceptance Scenarios**:

1. **Given** the registry is configured with 21 applications, **When** the user runs `i3pm apps list`, **Then** the CLI displays all applications with their names, workspaces, scopes, and tags
2. **Given** a project is active, **When** the user runs `i3pm project show`, **Then** the CLI displays the project name, directory, active application tags, and current layout status
3. **Given** the user wants to update a project, **When** they run `i3pm project update <name> --tags "dev,terminal"`, **Then** the project configuration is updated and changes take effect immediately
4. **Given** the user wants to monitor workspace assignments, **When** they run `i3pm windows --live`, **Then** the CLI displays real-time updates as windows open and move across workspaces

---

### Edge Cases

- What happens when a registry application is launched but the window PID cannot be obtained via xprop? (fallback to window class matching)
- How does the system handle applications that spawn multiple windows with different classes but same parent process?
- What happens when a user manually moves a project-scoped window to a different workspace?
- How does the system handle workspace assignment conflicts when multiple applications target the same workspace?
- What happens when restoring a layout and some applications fail to launch?
- What happens when the system cannot read /proc/<pid>/environ due to permission errors? (fallback to assuming global scope)
- What happens when the registry is updated while applications are running?
- How does the system handle fallback behavior when a scoped application is launched without an active project?
- What happens when I3PM_APP_ID from layout restore doesn't match any running window? (timeout and warn user)

## Requirements

### Functional Requirements

- **FR-001**: System MUST use the app-registry.nix as the single source of truth for application metadata (command, parameters, workspace assignment, window class, scope, fallback behavior)
- **FR-002**: System MUST launch all applications through the registry protocol, replacing legacy direct command execution
- **FR-003**: System MUST inject environment variables at application launch time containing project context (I3PM_PROJECT_NAME, I3PM_PROJECT_DIR, I3PM_APP_ID, I3PM_APP_NAME, I3PM_SCOPE)
- **FR-004**: System MUST generate unique application instance IDs for each launched application to enable deterministic window matching
- **FR-005**: System MUST perform variable substitution for project-scoped applications (e.g., `$PROJECT_DIR` replaced with actual project path)
- **FR-006**: System MUST generate i3 window rules automatically from registry metadata (expected_class, preferred_workspace) for global applications only
- **FR-007**: Window matching logic MUST use /proc/<pid>/environ to read I3PM_APP_ID and I3PM_PROJECT_NAME for deterministic identification
- **FR-008**: System MUST support three application scopes: "scoped" (project-aware), "global" (project-independent), and custom fallback behaviors
- **FR-009**: System MUST implement fallback behaviors when no project is active: "skip" (don't launch), "use_home" (use $HOME), "error" (show error message)
- **FR-010**: System MUST support saving current window layout (positions, sizes, workspace assignments) linked to a project
- **FR-011**: System MUST restore layouts by launching applications through the registry protocol with matching I3PM_APP_ID values for exact window identification
- **FR-012**: Layout restoration MUST close all existing project-scoped windows before restoring the saved layout to provide a clean slate
- **FR-013**: Layout restoration MUST handle missing or unavailable applications gracefully (skip with warning, don't block other apps)
- **FR-014**: Projects MUST store configuration including: name, directory path, icon, and one saved layout (window positions, sizes, applications with instance IDs)
- **FR-015**: System MUST provide CLI commands to list all registry applications with metadata (name, workspace, scope)
- **FR-016**: System MUST provide CLI commands to view, create, update, and delete projects
- **FR-017**: System MUST provide CLI commands to view current workspace assignments and window states in real-time
- **FR-018**: System MUST provide CLI commands to save and restore project layouts
- **FR-019**: System MUST remove all legacy application launching code paths (no dual maintenance)
- **FR-020**: System MUST update the i3pm Deno CLI to expose all new registry-centric functionality
- **FR-021**: System MUST persist project configurations in a format that survives NixOS rebuilds
- **FR-022**: System MUST validate project configurations on load (check for missing directories)
- **FR-023**: System MUST filter windows on project switch by reading I3PM_PROJECT_NAME from /proc/<pid>/environ
- **FR-024**: System MUST support multi-instance applications (e.g., multiple terminals per project) with each instance having a unique I3PM_APP_ID
- **FR-025**: System MUST use xprop or wmctrl to obtain window PIDs when i3ipc library doesn't expose them
- **FR-026**: System MUST handle permission errors gracefully when reading /proc/<pid>/environ for processes owned by different users

### Key Entities

- **Application Registry**: Central configuration defining all launchable applications with metadata (command, parameters with variable placeholders, expected window class, preferred workspace, scope type, fallback behavior, multi-instance support)
- **Project**: Named workspace context with a root directory path, display name, icon, and optional saved layout reference
- **Layout**: Snapshot of window positions, sizes, and workspace assignments for a project, storing application instance IDs and registry references for exact window restoration
- **Application Instance**: Each launched application with a unique I3PM_APP_ID, enabling deterministic window matching even with multiple instances of the same application
- **Process Environment**: Set of I3PM_* environment variables injected at launch time (I3PM_APP_ID, I3PM_APP_NAME, I3PM_PROJECT_NAME, I3PM_PROJECT_DIR, I3PM_SCOPE, I3PM_ACTIVE) readable via /proc/<pid>/environ
- **Window Rule**: i3 configuration directive auto-generated from registry metadata to assign windows to workspaces based on expected_class

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can launch any registered application with a single command that automatically applies project context and workspace assignment within 1 second
- **SC-002**: 100% of workspace assignments are defined in the registry, with zero manual i3 window rules required for registered applications
- **SC-003**: Users can switch between projects and see only relevant applications (filtered by tags) appear in their launcher within 500ms
- **SC-004**: Users can save a workspace layout and restore it with all applications reopening in their original positions with 95% accuracy
- **SC-005**: All legacy application launching code is removed, with the registry protocol handling 100% of application launches
- **SC-006**: CLI commands provide complete visibility into registry configuration, projects, and window states without requiring users to edit Nix files
- **SC-007**: Layout restoration handles missing applications gracefully, with 100% of available applications launching successfully and clear warnings for unavailable ones
- **SC-008**: Project switching completes in under 2 seconds with all application visibility updates and workspace changes applied
- **SC-009**: Users can create and configure new projects entirely through CLI commands without manual file editing
- **SC-010**: Window matching succeeds for 100% of registered applications, with windows appearing on their designated workspaces within 1 second of opening

## Assumptions

- The app-registry.nix format from Feature 034 is stable and supports all required metadata fields
- The Walker/Elephant launcher is fully operational and integrated with the registry
- The i3pm daemon has event subscription capabilities for real-time window monitoring
- Projects are user-specific and stored in `~/.config/i3/projects/` rather than system-wide
- **Application tags are flat single-level strings** (e.g., "development", "terminal", "git") without hierarchical structure or inheritance
- Window class matching uses i3's standard `class` and `instance` properties
- Layouts store window geometry as absolute coordinates, not relative percentages (can be enhanced later)
- The system has a single active project at a time (no multi-project workspaces)
- Users manually trigger layout save/restore (no automatic snapshotting on project switch)
- **Each project supports one saved layout** (not multiple named layouts like "coding", "debugging")
- **Layout restoration closes existing project-scoped windows before restoring** to provide a clean slate
- Registry applications define a single `expected_class`; if an app spawns multiple window classes, only the primary one is managed

## Out of Scope

- Automatic layout snapshotting (users must explicitly save layouts)
- Multiple named layouts per project (only one layout per project in this phase)
- Hierarchical or namespaced application tags (flat single-level tags only)
- Merging restored layout with existing windows (restoration always closes existing project windows first)
- Cross-project window sharing (windows belong to one project or are global)
- Backward compatibility with pre-registry launch mechanisms
- Dynamic workspace creation beyond the standard 1-9 workspace range
- GUI-based project and registry configuration (CLI-only in this phase)
- Integration with desktop file standards outside of the registry (no external .desktop files)
- Window tiling layout algorithms (i3 manages tiling, we manage workspace assignment)
- Application dependency management (if app A requires app B, users handle that)

## Dependencies

- Feature 034 (Walker/Elephant registry integration) must be complete and stable
- i3pm daemon event subscription system must support window lifecycle events
- Deno CLI infrastructure must be functional for adding new commands
- NixOS home-manager configuration must support the registry format
- i3 window manager must be configured to read auto-generated window rules

## Non-Functional Requirements

- Configuration changes (project updates, tag changes) must take effect within 2 seconds without requiring system restart
- CLI commands must provide clear, actionable error messages when validation fails
- Layout save/restore operations must be idempotent (multiple restores produce the same result)
- Registry validation must occur at NixOS build time to catch configuration errors before deployment
- Window matching must be deterministic (same application always matches to same workspace)
- CLI output must be parseable by scripts (support `--json` flag for structured output)
