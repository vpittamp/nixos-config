# Feature Specification: i3-Native Dynamic Project Workspace Management

**Feature Branch**: `012-review-project-scoped`
**Created**: 2025-10-19
**Status**: Draft
**Input**: User description: "Review project-scoped workspace specification for i3 native alignment and dynamic runtime configuration"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create and Switch Project at Runtime Without Rebuild (Priority: P1)

A developer wants to start a new project called "API Gateway" without having to edit NixOS configuration files and rebuild the system. They run a command like `i3-project-create --name "API Gateway" --dir ~/code/api-gateway --icon ""` which creates a new project configuration file in `~/.config/i3/projects/api-gateway.json`. They can immediately switch to this project using the project switcher (Mod+p) and the system uses i3's native workspace and window management commands to show/hide relevant windows.

**Why this priority**: Dynamic project creation is the core differentiator from the current static NixOS configuration approach. Without this, every project requires a system rebuild, making the feature impractical for users who frequently work on different codebases.

**Independent Test**: Can be fully tested by running the project creation command, verifying the JSON configuration file exists, then using the project switcher to activate it and confirming VS Code opens in the specified directory using native i3 workspace assignments.

**Acceptance Scenarios**:

1. **Given** no project named "API Gateway" exists, **When** user runs `i3-project-create --name "API Gateway" --dir ~/code/api-gateway`, **Then** a configuration file `~/.config/i3/projects/api-gateway.json` is created
2. **Given** project configuration file exists, **When** user opens project switcher (Mod+p), **Then** "API Gateway" appears in the project list
3. **Given** user selects "API Gateway" from switcher, **When** project is activated, **Then** i3 marks file `~/.config/i3/active-project` is created with project name
4. **Given** "API Gateway" project is active, **When** user launches VS Code (Mod+c), **Then** VS Code opens ~/code/api-gateway using native i3 workspace assignment to workspace 2

---

### User Story 2 - Use i3 Marks for Window-Project Association (Priority: P1)

A developer has multiple VS Code windows open for different projects. Each window is tagged with an i3 mark like `project:nixos` or `project:stacks` when launched in a project context. When they switch from "nixos" to "stacks" project, the system uses i3's native `[con_mark="project:nixos"]` criteria to move all nixos-marked windows to the scratchpad, and `[con_mark="project:stacks"]` criteria to bring stacks windows back to their designated workspaces. This leverages i3's built-in marking system without custom window tracking logic.

**Why this priority**: i3 marks are the native mechanism for identifying and selecting groups of windows. Using marks eliminates the need for custom window-to-project association logic and enables direct use of i3 commands like `[con_mark="project:X"] move scratchpad`.

**Independent Test**: Can be tested by launching VS Code with different projects, inspecting window marks using `i3-msg -t get_tree`, then switching projects and verifying marked windows move to/from scratchpad using native i3 commands.

**Acceptance Scenarios**:

1. **Given** "nixos" project is active, **When** user launches VS Code, **Then** VS Code window receives i3 mark "project:nixos" (verifiable via `i3-msg -t get_tree`)
2. **Given** VS Code window has mark "project:nixos", **When** user switches to "stacks" project, **Then** system executes `i3-msg '[con_mark="project:nixos"] move scratchpad'`
3. **Given** windows with mark "project:stacks" are in scratchpad, **When** user activates "stacks" project, **Then** system executes `i3-msg '[con_mark="project:stacks"] scratchpad show; move to workspace 2'`
4. **Given** window has no project mark (global application), **When** user switches projects, **Then** window remains visible on its current workspace

---

### User Story 3 - Leverage i3 Workspace Events for Project Synchronization (Priority: P2)

A developer wants the polybar status indicator to automatically update when the project context changes. The project switching script sends an i3 tick event with the project name as payload using `i3-msg -t send_tick -m '{"project":"nixos"}'`. The polybar module subscribes to i3 tick events via IPC and updates its display text without polling files or running periodic checks. This uses i3's native event system for real-time synchronization.

**Why this priority**: i3's event system provides efficient, real-time notifications without polling. Using native events eliminates custom inter-process communication and leverages i3's built-in pub/sub mechanism. This is P2 because polybar updates are valuable but not critical for core functionality.

**Independent Test**: Can be tested by subscribing to i3 tick events using the IPC protocol, switching projects, and verifying the tick event payload contains the correct project name.

**Acceptance Scenarios**:

1. **Given** polybar module is running, **When** polybar initializes, **Then** it subscribes to i3 tick events with payload filter for project changes
2. **Given** user switches to "nixos" project, **When** project switch script executes, **Then** script sends `i3-msg -t send_tick -m 'project:nixos'`
3. **Given** polybar is subscribed to tick events, **When** tick event with payload "project:nixos" is received, **Then** polybar updates display to show " NixOS"
4. **Given** project is cleared, **When** clear script sends tick event with empty project, **Then** polybar displays "No Project"

---

### User Story 4 - Store Project Config as i3-Compatible JSON (Priority: P1)

A developer wants to define project workspace layouts using i3's native JSON layout format. They create a file `~/.config/i3/projects/nixos.json` with structure compatible with i3's `layout` command output, including workspace numbers, window marks, and application commands. The project activation script loads this JSON and uses i3's native `append_layout` command to restore the workspace structure, leveraging i3's built-in layout restoration without custom parsing logic.

**Why this priority**: Aligning project configuration with i3's native JSON format ensures compatibility with existing i3 tools and reduces custom logic. Users familiar with i3 layouts can directly edit project files using standard i3 knowledge.

**Independent Test**: Can be tested by creating a project JSON file that matches i3 layout schema, running `i3-msg 'workspace 2; append_layout ~/.config/i3/projects/nixos.json'`, and verifying windows are created with correct marks and properties.

**Acceptance Scenarios**:

1. **Given** project JSON file follows i3 layout schema, **When** user activates project, **Then** system executes `i3-msg 'append_layout ~/.config/i3/projects/PROJECT.json'` for designated workspaces
2. **Given** i3 layout specifies swallows criteria with marks, **When** applications launch after layout is appended, **Then** i3 automatically assigns windows to placeholders based on marks
3. **Given** project JSON includes custom application launch commands, **When** project is activated, **Then** launcher script executes commands in sequence with appropriate delays
4. **Given** project JSON is edited manually to add new workspace, **When** project is reactivated, **Then** new workspace appears without system rebuild

---

### User Story 5 - Use i3 Workspace Output Assignment (Priority: P2)

A developer works with dual monitors and wants VS Code workspace (workspace 2) to always appear on the secondary monitor while terminal workspace (workspace 1) stays on primary. They configure this in their project JSON using i3's native workspace output syntax: `workspace 2 output HDMI-1`. When the project activates, the script sends these commands via `i3-msg` and i3 natively handles workspace positioning without custom monitor detection logic.

**Why this priority**: i3 provides built-in `workspace <number> output <name>` commands for workspace-to-monitor assignment. Using this native feature eliminates the need for custom monitor detection and workspace distribution logic. This is P2 because single-monitor setups work fine without it.

**Independent Test**: Can be tested by configuring workspace output assignments in project JSON, activating the project on a multi-monitor setup, and verifying workspaces appear on specified monitors using `i3-msg -t get_workspaces`.

**Acceptance Scenarios**:

1. **Given** project JSON specifies `"workspace_2_output": "HDMI-1"`, **When** project is activated, **Then** system executes `i3-msg 'workspace 2 output HDMI-1'`
2. **Given** workspace output is assigned to disconnected monitor, **When** project is activated, **Then** i3 falls back to default output assignment (i3 native behavior)
3. **Given** user manually moves workspace to different monitor, **When** project is deactivated and reactivated, **Then** workspace returns to configured output
4. **Given** no output assignment is specified in project JSON, **When** project is activated, **Then** i3 uses default workspace distribution

---

### User Story 6 - Define Application Classes in Simple Config File (Priority: P3)

A developer wants to configure which applications are project-scoped vs global without NixOS rebuild. They edit `~/.config/i3/app-classes.json` to add `{"class": "obsidian", "scoped": true}`, marking Obsidian as project-scoped. When they launch Obsidian in a project context, it receives the project mark. If they later decide it should be global, they change `"scoped": false` and the change takes effect on next application launch without any rebuild.

**Why this priority**: Runtime configuration of application classes makes the system flexible and user-friendly. This is P3 because a reasonable default set of project-scoped apps (VS Code, terminals, lazygit, yazi) covers most use cases, and adding new apps is less frequent than creating projects.

**Independent Test**: Can be tested by editing the app-classes JSON file, launching the application, and verifying it receives or doesn't receive a project mark based on the configuration.

**Acceptance Scenarios**:

1. **Given** app-classes.json contains `{"class": "Code", "scoped": true}`, **When** user launches VS Code with active project, **Then** window receives project mark
2. **Given** app-classes.json contains `{"class": "Firefox", "scoped": false}`, **When** user launches Firefox with active project, **Then** window does not receive project mark
3. **Given** user edits app-classes.json to change application from scoped to global, **When** application is launched, **Then** new window uses updated classification without rebuild
4. **Given** application class is not defined in app-classes.json, **When** application launches, **Then** system uses default heuristic (terminals and IDEs are scoped, browsers are global)

---

### Edge Cases

- What happens when a project JSON file is malformed or doesn't match i3 layout schema? (System logs error, falls back to simple workspace assignment without layout restoration)
- How does the system handle launching an application when active-project file exists but referenced project JSON is missing? (System clears active project and launches application in global mode)
- What happens when user creates two projects with the same name? (Project switcher shows both with path disambiguation: "nixos (/etc/nixos)" vs "nixos (~/projects/nixos)")
- How does the system handle i3 restart or reload while project is active? (Active project file persists, project state is restored by checking marks on existing windows after i3 restart)
- What happens when a window loses its mark due to application restart or manual removal? (Window behaves as global application until re-marked; user can manually re-mark using `i3-project-mark-window`)
- How does the system handle applications that don't support setting window properties? (Falls back to WM_CLASS matching or treat as global; document which applications require special handling)
- What happens when i3 IPC socket is unavailable or unresponsive? (Command-line tools report error, polybar shows "i3 IPC Error", no project switching occurs)
- How does the system handle rapidly switching between projects? (Queue switch requests or cancel pending operations; prevent race conditions in mark/scratchpad commands)

## Requirements *(mandatory)*

### Functional Requirements

#### Runtime Project Management

- **FR-001**: System MUST support creating new projects at runtime using a command-line tool without NixOS/home-manager rebuild
- **FR-002**: System MUST store project configurations as individual JSON files in `~/.config/i3/projects/` directory
- **FR-003**: System MUST support deleting projects by removing their JSON configuration files (no rebuild required)
- **FR-004**: System MUST support editing project configuration files directly and applying changes on next project activation
- **FR-005**: Active project state MUST be stored in `~/.config/i3/active-project` file containing project name
- **FR-006**: System MUST list all available projects by scanning `~/.config/i3/projects/` directory at runtime

#### i3-Native Window Association

- **FR-007**: System MUST use i3 marks (not custom window tracking) to associate windows with projects
- **FR-008**: Project-scoped windows MUST receive mark in format `project:PROJECT_NAME` when launched in project context
- **FR-009**: System MUST use i3 criteria syntax `[con_mark="project:X"]` to select windows by project
- **FR-010**: System MUST move inactive project windows using native command: `i3-msg '[con_mark="project:X"] move scratchpad'`
- **FR-011**: System MUST restore active project windows using native command: `i3-msg '[con_mark="project:X"] scratchpad show; move to workspace N'`
- **FR-012**: Windows without project marks MUST remain visible on their current workspace (global application behavior)

#### i3-Compatible Project Configuration Schema

- **FR-013**: Project JSON files MUST follow i3 layout format compatible with `append_layout` command
- **FR-014**: Project JSON MUST support i3 layout properties: workspace number, swallows criteria, geometry, marks
- **FR-015**: Project JSON MUST support custom properties: name, displayName, icon, directory, workspaceOutputs
- **FR-016**: System MUST use `i3-msg 'append_layout FILE'` to restore workspace layouts from project JSON
- **FR-017**: Project JSON MUST support specifying application launch commands with mark assignment
- **FR-018**: System MUST validate project JSON against schema and report errors without crashing

#### i3 Event-Based Synchronization

- **FR-019**: System MUST send i3 tick events when project state changes using `i3-msg -t send_tick`
- **FR-020**: Tick event payload MUST contain project name in format `project:PROJECT_NAME` or `project:none` for cleared state
- **FR-021**: Polybar module MUST subscribe to i3 tick events via IPC to receive project updates
- **FR-022**: Polybar MUST update project indicator within 1 second of receiving tick event (no file polling)

#### Native Workspace Output Assignment

- **FR-023**: Project JSON MAY specify workspace-to-output assignments using i3 output names (e.g., "HDMI-1", "eDP-1")
- **FR-024**: System MUST use `i3-msg 'workspace N output OUTPUT_NAME'` to assign workspaces to monitors
- **FR-025**: System MUST allow omitting output assignments to use i3 default workspace distribution
- **FR-026**: System MUST handle disconnected outputs gracefully by relying on i3's native fallback behavior

#### Application Classification Configuration

- **FR-027**: System MUST support runtime application classification in `~/.config/i3/app-classes.json`
- **FR-028**: Application classes MUST specify: WM_CLASS pattern, scoped boolean, default workspace number
- **FR-029**: System MUST read app-classes.json at application launch time (no caching)
- **FR-030**: System MUST provide default classifications for common applications (Code, Ghostty, Firefox, etc.) if app-classes.json is missing
- **FR-031**: Users MUST be able to override default classifications by editing app-classes.json without rebuild

#### Project Launcher Integration

- **FR-032**: System MUST provide wrapper scripts for common applications (code, ghostty, lazygit, yazi) that check active project
- **FR-033**: Wrapper scripts MUST launch applications with project directory as working directory when project is active
- **FR-034**: Wrapper scripts MUST mark launched windows with project mark using `i3-msg '[id=WINDOW_ID] mark project:NAME'`
- **FR-035**: Wrapper scripts MUST move windows to designated workspace using `i3-msg '[id=WINDOW_ID] move to workspace N'`
- **FR-036**: Keybindings MUST call wrapper scripts instead of directly calling application binaries

#### Elimination of Static NixOS Configuration

- **FR-037**: System MUST NOT require defining projects in home-manager or NixOS configuration files
- **FR-038**: System MUST NOT require NixOS rebuild to add, remove, or modify projects
- **FR-039**: System MUST provide migration tool to convert existing static project definitions to runtime JSON files
- **FR-040**: NixOS configuration MAY provide default project JSON files for initial setup (optional convenience)

### Key Entities

- **Project Configuration File**: JSON file stored in `~/.config/i3/projects/PROJECT_NAME.json` following i3 layout schema with custom extensions. Attributes: name, displayName, icon, directory, workspaces (array with layout definitions), workspaceOutputs (map of workspace number to output name), launchCommands (array of commands to execute on activation)

- **i3 Window Mark**: Native i3 mark in format `project:PROJECT_NAME` applied to windows to associate them with a project. Queryable via i3 IPC GET_TREE and selectable via criteria syntax `[con_mark="mark_name"]`

- **Active Project State File**: Simple text file `~/.config/i3/active-project` containing the name of the currently active project or empty if no project is active. Persists across i3 restarts

- **Application Class Configuration**: JSON file `~/.config/i3/app-classes.json` mapping WM_CLASS patterns to classification (scoped/global) and default workspace assignments. Attributes per entry: class (string pattern), instance (optional pattern), scoped (boolean), workspace (number), description

- **i3 Tick Event**: Native i3 IPC event sent via SEND_TICK message type with custom payload. Used to notify polybar and other subscribers about project state changes. Payload format: `project:PROJECT_NAME` or `project:none`

- **Workspace Layout**: i3-native JSON structure describing window placeholders, swallows criteria, geometry, and marks. Loaded via `append_layout` command to pre-define workspace structure before launching applications

- **Project Launcher Wrapper**: Shell script that wraps application binaries to inject project context (working directory, window marks, workspace assignment). Stored in `~/.config/i3/launchers/` and called by keybindings

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can create a new project and activate it within 10 seconds without running any Nix build commands
- **SC-002**: 100% of window-to-project associations use i3 native marks (verifiable via `i3-msg -t get_tree` showing `marks: ["project:NAME"]`)
- **SC-003**: 100% of project-scoped window visibility changes use native i3 commands (`move scratchpad`, `scratchpad show`)
- **SC-004**: Project configuration files validate against i3 layout JSON schema and successfully load with `append_layout` command
- **SC-005**: Polybar project indicator updates within 1 second of project switch without polling files (event-driven only)
- **SC-006**: User can edit `~/.config/i3/app-classes.json` and see changes take effect on next application launch (0 seconds rebuild time)
- **SC-007**: Workspace-to-monitor assignments specified in project JSON use native `workspace X output Y` commands 100% of the time
- **SC-008**: System works correctly when i3 configuration contains zero project-related static definitions (pure runtime mode)
- **SC-009**: Migration tool successfully converts existing static project definitions to runtime JSON files with 100% data preservation
- **SC-010**: User completes workflow "create project → activate → launch apps → switch project → verify marks" in under 30 seconds using only CLI commands and keybindings

## Assumptions

- i3 window manager is installed and running with IPC enabled
- i3 supports marks and criteria-based window selection (available since i3 v4.1+)
- i3 supports `append_layout` command for loading JSON workspace layouts (available since i3 v4.8+)
- i3 supports tick events via IPC SEND_TICK message type (available since i3 v4.15+)
- i3-msg command-line tool is available for sending IPC commands
- jq is available for JSON parsing in shell scripts
- Applications launched via wrappers can have their window IDs retrieved immediately after launch (or detected via window events)
- Polybar or alternative status bar supports custom IPC-based modules (or can execute scripts on i3 events)
- User has write access to `~/.config/i3/` directory for storing project configurations
- Project JSON files are small enough (<1MB) to load and parse quickly at runtime
- Window managers other than i3 are out of scope (sway may work with minor modifications but is not explicitly supported)

## Out of Scope

- Supporting window managers other than i3 (sway, Hyprland, etc.)
- Automatic project detection based on current working directory or Git repository
- Project templates or scaffolding for generating boilerplate project configurations
- Graphical UI for project creation/editing (CLI-only in initial version)
- Syncing project configurations across machines (user may use dotfiles managers separately)
- Project-specific keybindings or i3 configuration modes (only affects window visibility/workspace assignment)
- Integration with external project management tools (JIRA, Trello, etc.)
- Session persistence beyond sesh/tmux (saving and restoring full application state)
- Browser profile management per project (Firefox containers, Chrome profiles)
- Versioning or history of project configuration changes
- Multi-user project definitions (shared projects on same system)
- Project dependencies or hierarchical projects (parent/child relationships)
