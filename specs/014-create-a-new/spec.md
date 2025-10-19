# Feature Specification: Consolidate and Validate i3 Project Management System

**Feature Branch**: `014-create-a-new`
**Created**: 2025-10-19
**Status**: Draft
**Input**: User description: "create a new feature that codifies our full functionality and working i3 project system. go back to our feature, 012, where we built out our project based system that integrates with i3. now that we've completed our migration to i3blocks from polybar, i want to review our overall logic, and make sure it's sound and confirm the functionality is working. review 013. keep in mind we did change our scripting to work with i3blocks in 013; then determine how to create a full working system using the combined functionality, and merging the code/files as needed. review i3_man.txt and docs/i3-ipc.txt to make sure we're using as native of functionality as possible, and not creating custom logic where pre-defined functions/logic already exists. then thoroughly test each piece of functionality as you go. test as though you are a user using the functionality and use xdotool where needed to simulate key presses. be careful to not close the existing terminal though which would close our session."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete Project Lifecycle Management (Priority: P1)

A developer needs to create a new project for working on an API Gateway codebase, activate it to see only relevant windows, launch project-scoped applications, then switch to a different project for work on a different codebase. They should be able to create the project, see it in the project switcher, activate it with a keyboard shortcut, and have the status bar reflect the current project context.

**Why this priority**: This represents the end-to-end core functionality that combines project creation (feature 012) with visual feedback (feature 013). Without this complete workflow, users cannot effectively use the project management system.

**Independent Test**: Can be fully tested by running through the complete cycle: create project → list projects → switch to project → launch apps → verify status bar → switch to different project → verify windows hidden → verify status bar updated.

**Acceptance Scenarios**:

1. **Given** no projects exist, **When** user runs `project-create --name "api-gateway" --dir ~/code/api-gateway --icon ""`, **Then** project is created and appears in `~/.config/i3/projects/` directory
2. **Given** project exists, **When** user presses Win+P, **Then** rofi project switcher displays the project with icon and name
3. **Given** user selects project from switcher, **When** project activates, **Then** status bar (i3blocks) shows project name and icon within 1 second
4. **Given** project is active, **When** user launches VS Code with Win+C, **Then** VS Code opens in project directory and receives project mark
5. **Given** two projects exist with windows, **When** user switches from project A to project B, **Then** project A windows move to scratchpad and project B windows return to workspaces

---

### User Story 2 - i3 JSON Schema Alignment for Project State (Priority: P1)

A developer wants to define and manage project configurations as metadata while using i3's native JSON schema for runtime state queries. When they create a project configuration, it stores project-specific metadata (directory, icon, workspace layouts) in JSON files. Runtime state (which windows are visible, their marks, workspace assignments) is queried directly from i3's tree using `i3-msg -t get_tree`. This allows them to inspect runtime state using standard i3 tools while keeping project metadata separate, ensuring compatibility with future i3 versions.

**Clarification**: Runtime state uses i3 native queries (marks, tree, workspaces). Configuration files (~/. config/i3/projects/*.json) are metadata, not i3 tree state.

**Why this priority**: Aligning with i3's JSON schema is fundamental to creating a truly native integration. It eliminates custom data structures, ensures compatibility with i3 tools, and makes the system more maintainable and debuggable.

**Independent Test**: Can be tested by creating a project configuration, verifying it matches i3's JSON structure (with allowed extensions), querying active project state via i3 IPC, and confirming no custom schemas are used.

**Acceptance Scenarios**:

1. **Given** user creates a project, **When** project configuration is saved, **Then** the JSON structure extends i3's tree/workspace schema rather than using a custom format
2. **Given** project is active, **When** querying `i3-msg -t get_tree`, **Then** project metadata appears as i3 marks and properties (not external state)
3. **Given** project configuration exists, **When** user inspects it manually, **Then** they recognize standard i3 fields (name, rect, layout, marks) with minimal extensions (project_dir, project_icon)
4. **Given** i3 workspace state exists, **When** project system queries it, **Then** system uses i3's JSON response directly without transformation or mapping
5. **Given** user exports i3 layout with `i3-save-tree`, **When** comparing to project config, **Then** project config uses compatible structure that could be used with `append_layout`

---

### User Story 3 - Native i3 Integration Validation (Priority: P1)

A system administrator needs to ensure that all project management functionality uses i3's native features rather than custom logic. They should be able to inspect window marks using i3-msg, verify that workspace state comes from i3 IPC, and confirm that all window movements use native i3 commands.

**Why this priority**: Using i3 native features ensures reliability, maintainability, and compatibility with future i3 versions. Custom logic increases complexity and the risk of bugs.

**Independent Test**: Can be tested by inspecting the implementation to verify that marks are used for window association, i3-msg commands are used for window movement, and i3 IPC is used for workspace and event synchronization.

**Acceptance Scenarios**:

1. **Given** a project is active, **When** applications launch, **Then** `i3-msg -t get_tree` shows windows with marks in format `project:PROJECT_NAME`
2. **Given** project windows exist, **When** project is switched, **Then** window movement uses commands like `i3-msg '[con_mark="project:X"] move scratchpad'`
3. **Given** status bar is running, **When** project changes, **Then** i3blocks receives update signal and reads project state from file (not via polling)
4. **Given** workspace information is needed, **When** scripts query workspaces, **Then** they use `i3-msg -t get_workspaces` for current state

---

### User Story 4 - Status Bar Project Indicator Integration (Priority: P1)

A developer wants to always know which project they're currently working in by looking at the status bar. When they switch projects, the status bar should immediately update to show the new project name and icon. When no project is active, it should show a clear "No Project" indicator.

**Why this priority**: Visual feedback is critical for context awareness. Without it, users must manually check their current project, defeating the purpose of seamless project switching.

**Independent Test**: Can be tested by activating different projects and verifying the status bar updates correctly, including handling edge cases like invalid project files or missing icons.

**Acceptance Scenarios**:

1. **Given** no project is active, **When** user looks at status bar, **Then** status bar shows "∅ No Project" in dimmed color
2. **Given** project "NixOS" with icon "" is active, **When** status bar refreshes, **Then** status bar shows " NixOS" in highlighted color
3. **Given** project is active, **When** user clears project with Win+Shift+P, **Then** status bar updates to show "∅ No Project" within 1 second
4. **Given** project file exists but is malformed JSON, **When** status bar script runs, **Then** status bar shows "∅ No Project" and doesn't crash

---

### User Story 5 - Application Window Tracking and Scratchpad Management (Priority: P2)

A power user with many windows open across multiple projects needs windows to automatically show/hide when switching projects. Project-scoped applications (VS Code, terminals, lazygit) should disappear when switching away from their project, while global applications (Firefox, K9s) should remain visible at all times.

**Why this priority**: Automatic window management is what makes the project system practical for daily use. This is P2 because the core functionality of creating/switching projects (P1) must work first.

**Independent Test**: Can be tested by opening multiple windows in different projects, switching between projects, and verifying which windows remain visible and which move to scratchpad.

**Acceptance Scenarios**:

1. **Given** VS Code is open in project A, **When** user switches to project B, **Then** VS Code window moves to scratchpad (not visible)
2. **Given** project B is active with VS Code in scratchpad, **When** user switches back to project A, **Then** VS Code window returns to its original workspace
3. **Given** Firefox is open (global app), **When** user switches between projects, **Then** Firefox remains visible on its workspace
4. **Given** terminal with project mark exists, **When** terminal is closed and reopened, **Then** new terminal gets project mark based on active project

---

### User Story 6 - Real-Time Event Logging and Debugging (Priority: P2)

A developer troubleshooting project switching issues needs to see a live stream of events showing what's happening in the system. They open a dedicated log viewer terminal that displays i3 events (workspace changes, window events, binding events), project system commands being executed, i3-msg command outputs, and timing information. This helps them understand the sequence of events when windows don't switch correctly or the status bar doesn't update.

**Why this priority**: Debugging support is essential for maintaining the system and diagnosing issues. Without it, troubleshooting becomes guesswork. This is P2 because the core functionality (P1) must exist first before debugging it matters.

**Independent Test**: Can be tested by opening log viewer, triggering project operations, and verifying that all events appear in the log stream with timestamps and relevant details.

**Acceptance Scenarios**:

1. **Given** log viewer is running, **When** user switches projects, **Then** log shows sequence: project switch command → i3 mark queries → window movements → status bar signal → completion timestamp
2. **Given** log viewer is running, **When** i3 workspace event fires, **Then** log shows event type, affected workspace, and timestamp within 100ms
3. **Given** log viewer is running, **When** project script executes i3-msg command, **Then** log shows command, arguments, response, and execution time
4. **Given** log viewer is running, **When** error occurs (invalid JSON, missing project), **Then** log shows error with context (which file, what operation, error details)
5. **Given** developer wants historical logs, **When** they query log file, **Then** logs persist across sessions with rotation to prevent disk filling
6. **Given** multiple terminals running, **When** log viewer opens, **Then** it subscribes to i3 events via IPC and displays them in real-time

---

### User Story 7 - Multi-Monitor Workspace Management (Priority: P3)

A developer with multiple monitors wants their project workspaces to distribute intelligently across monitors. When they activate a project, workspaces should appear on the appropriate monitors, and when monitors are added/removed, the system should adapt gracefully.

**Why this priority**: Multi-monitor support enhances productivity but is not essential for core functionality. Single-monitor usage must work perfectly first (P1).

**Independent Test**: Can be tested by configuring workspace-to-output assignments in project configuration, connecting/disconnecting monitors, and verifying workspace distribution.

**Acceptance Scenarios**:

1. **Given** project specifies workspace 2 on HDMI-1, **When** project activates, **Then** workspace 2 appears on HDMI-1 monitor
2. **Given** workspace is assigned to disconnected monitor, **When** project activates, **Then** i3 automatically assigns workspace to available monitor
3. **Given** user manually moves workspace to different monitor, **When** project is deactivated and reactivated, **Then** workspace returns to configured monitor
4. **Given** no output assignments specified, **When** project activates, **Then** i3 uses default workspace distribution

---

### Edge Cases

- What happens when `~/.config/i3/active-project` file exists but contains invalid JSON? (System treats as no active project, shows "No Project" in status bar, logs ERROR with file path and JSON parse error)
- How does the system handle launching applications when i3 IPC socket is unavailable? (Commands fail gracefully with error message, logs ERROR with socket path and connection details, no crashes, user can retry)
- What happens when user creates two projects with the same name? (Project creation should fail with error message logged at WARN level, or auto-disambiguate with directory path and log INFO)
- How does the system handle rapid project switching (multiple switches within 1 second)? (Scripts should either queue or debounce to prevent race conditions, log WARN for queued/dropped switches)
- What happens when window loses its mark due to application restart? (Window behaves as global until re-marked, log WARN with window ID and lost mark; user can manually re-mark or relaunch in project context)
- How does the system handle i3 restart while project is active? (Active project file persists, state should restore based on existing window marks after restart, log INFO on restart detection and restoration)
- What happens when project directory doesn't exist when launching applications? (Applications should handle gracefully, log WARN with missing directory path, possibly creating directory or falling back to home directory)
- How does status bar handle very long project names? (Text should truncate or wrap appropriately to fit in status bar space, log DEBUG with full name and truncated version)
- What happens when log file reaches rotation size during active logging? (System rotates file atomically, continues logging to new file, logs INFO about rotation with old/new file names)
- How does log viewer handle log file being deleted or moved while tailing? (Viewer detects file absence, logs WARN, attempts to reconnect to new file or waits for file recreation)
- What happens when multiple project operations run concurrently? (System logs all operations with unique operation IDs, timestamps show execution order, concurrent i3-msg calls are serialized by i3 IPC)
- How does debug mode affect system performance? (Debug mode logs are verbose but non-blocking, log level filtering happens at write time, acceptable overhead documented in logs)

## Requirements *(mandatory)*

### Functional Requirements

#### Consolidated System Validation

- **FR-001**: System MUST successfully integrate functionality from feature 012 (project management) and feature 013 (i3blocks status bar)
- **FR-002**: All project management scripts MUST work correctly with i3blocks project indicator
- **FR-003**: System MUST eliminate any duplicate or conflicting code between the two features
- **FR-004**: All scripts MUST be verified against i3 IPC documentation to ensure use of native features
- **FR-005**: System MUST pass end-to-end testing of complete project lifecycle

#### i3 JSON Schema Alignment

- **FR-006**: Project configurations MUST use i3's JSON schema as the base structure (compatible with `i3-msg -t get_tree` output)
- **FR-007**: Project extensions to i3 schema MUST be minimal and additive (e.g., `project_dir`, `project_icon` as additional fields)
- **FR-008**: System MUST be able to consume i3's native JSON responses without transformation or custom mapping
- **FR-009**: Project state stored in i3 (marks, workspace names, container properties) MUST be the primary source of truth
- **FR-010**: Active project metadata file (`~/.config/i3/active-project`) MUST only store minimal extensions not available in i3 state
- **FR-011**: Project configurations MUST be compatible with i3's `append_layout` command format
- **FR-012**: System MUST handle missing or malformed project state file gracefully
- **FR-013**: Project state MUST persist across i3 restarts and system reboots via i3's native persistence mechanisms

#### Native i3 Integration

- **FR-014**: All window-to-project associations MUST use i3 marks in format `project:PROJECT_NAME`
- **FR-015**: All window queries MUST use `i3-msg -t get_tree` and parse JSON response
- **FR-016**: All window movements MUST use `i3-msg` commands with criteria syntax `[con_mark="..."]`
- **FR-017**: All workspace queries MUST use `i3-msg -t get_workspaces` for current state
- **FR-018**: Status bar updates MUST use i3blocks signal mechanism (SIGRTMIN+N) not file polling
- **FR-019**: System MUST NOT implement custom window tracking beyond i3 marks
- **FR-020**: System MUST query i3 state directly via IPC rather than maintaining separate state files where possible

#### Status Bar Integration

- **FR-021**: i3blocks configuration MUST include project indicator block
- **FR-022**: Project indicator script MUST read project metadata from minimal extension file only for fields not in i3 state
- **FR-023**: Project indicator MUST display project icon and name when project is active
- **FR-024**: Project indicator MUST display "∅ No Project" when no project is active
- **FR-025**: Project indicator MUST use appropriate colors from Catppuccin Mocha theme
- **FR-026**: Project switching scripts MUST signal i3blocks to update project indicator

#### Window Management

- **FR-027**: System MUST mark all project-scoped application windows with project mark on launch
- **FR-028**: System MUST move inactive project windows to scratchpad when switching projects
- **FR-029**: System MUST restore active project windows from scratchpad to designated workspaces
- **FR-030**: System MUST leave unmarked (global) windows visible across all project switches
- **FR-031**: System MUST handle windows that don't support marks gracefully

#### Logging and Debugging

- **FR-032**: System MUST provide centralized logging to a structured log file at `~/.config/i3/project-system.log`
- **FR-033**: All project management scripts MUST log operations with timestamp, operation type, and outcome
- **FR-034**: System MUST log all i3-msg commands with their arguments and responses
- **FR-035**: System MUST subscribe to i3 events (workspace, window, binding) via IPC and log them
- **FR-036**: Log entries MUST include: ISO timestamp, log level (DEBUG/INFO/WARN/ERROR), component name, message, execution time
- **FR-037**: System MUST provide log viewer command that tails log file and formats output for readability
- **FR-038**: Log viewer MUST support filtering by log level, component, or time range
- **FR-039**: Logs MUST rotate when exceeding size limit (default 10MB) keeping last 5 rotated files
- **FR-040**: System MUST provide debug mode that increases verbosity and logs i3 IPC responses in full
- **FR-041**: Errors MUST log full context including stack trace, relevant state (active project, window IDs), and actionable remediation hints

#### Testing and Validation

- **FR-042**: System MUST provide test commands to verify mark assignment
- **FR-043**: System MUST provide test commands to verify workspace state
- **FR-044**: System MUST provide test commands to validate JSON schema alignment with i3
- **FR-045**: System MUST provide test commands to simulate project switching workflow
- **FR-046**: All automated tests MUST use xdotool to simulate user interactions
- **FR-047**: Tests MUST NOT close the active terminal session
- **FR-048**: Tests MUST verify visual feedback in status bar
- **FR-049**: Tests MUST verify logging output contains expected events and commands

### Key Entities

- **Project Configuration**: JSON file in `~/.config/i3/projects/PROJECT_NAME.json` that extends i3's layout/workspace schema. Uses i3-compatible fields (name, rect, layout, nodes, marks, swallows) plus minimal extensions (project_dir, project_icon). Compatible with `i3-msg 'append_layout'` command.

- **i3 Tree State**: The authoritative source of truth for all window and workspace state, queried via `i3-msg -t get_tree`. Contains all containers, windows, marks, workspaces, and their relationships in i3's native JSON format.

- **Active Project Metadata**: Minimal JSON file at `~/.config/i3/active-project` containing only project extensions not available in i3 state (project_dir, project_icon). Fields like active project name are determined by querying i3 marks.

- **i3 Window Mark**: Native i3 mark in format `project:PROJECT_NAME` attached to windows for project association. Queryable via i3 tree state, selectable via criteria syntax `[con_mark="project:X"]`.

- **i3 Workspace State**: Native i3 workspace information from `i3-msg -t get_workspaces` containing workspace properties (num, name, visible, focused, urgent, rect, output). Used directly without transformation.

- **i3blocks Status Block**: Configuration block in i3blocks config that runs project indicator script and displays project context.

- **Project Indicator Script**: Bash script at `~/.config/i3blocks/scripts/project.sh` that queries i3 state via IPC for active project marks and reads minimal metadata file for display information.

- **Project Switch Script**: Bash script that activates a project by setting i3 marks, moving windows via native i3 commands, updating minimal metadata file, and signaling status bar.

- **Rofi Project Switcher**: Interactive menu that lists available projects from `~/.config/i3/projects/` and calls switch script when user selects one.

- **Project System Log File**: Structured log at `~/.config/i3/project-system.log` containing timestamped entries from all project management components. Format: `[TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE`. Rotates at 10MB, keeps 5 historical files.

- **i3 Event Subscriber**: Background process or integration that subscribes to i3 IPC events (workspace, window, binding) and logs them to project system log. Provides real-time event stream for debugging.

- **Log Viewer Tool**: Command-line utility (e.g., `project-logs`) that tails log file, formats output with color coding by log level, and supports filtering by level/component/time.

- **Debug Mode**: Environment variable or flag that enables verbose logging, includes full i3 IPC responses, timing information for each operation, and detailed state snapshots.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can complete full project lifecycle (create → list → switch → launch apps → switch again → verify state) in under 60 seconds
- **SC-002**: 100% of project configuration files validate as valid i3 layout JSON (compatible with `append_layout`)
- **SC-003**: Project metadata file contains fewer than 5 extension fields beyond i3 schema (project_dir, project_icon, etc.)
- **SC-004**: 100% of window associations use i3 marks (verified via `i3-msg -t get_tree` inspection)
- **SC-005**: 100% of window movements use native `i3-msg` commands (verified via script review)
- **SC-006**: 100% of workspace queries use `i3-msg -t get_workspaces` without transformation (verified via script review)
- **SC-007**: System can determine active project by querying i3 marks alone, without reading external state files
- **SC-008**: Status bar updates within 1 second of project switch (measured via visual observation)
- **SC-009**: Status bar correctly displays project state in all edge cases (no project, invalid JSON, missing icon)
- **SC-010**: System handles at least 3 concurrent projects with 5+ windows each without errors
- **SC-011**: All automated tests pass without closing active terminal session
- **SC-012**: System survives i3 restart with active project state correctly restored from i3 native persistence (marks, workspace names)
- **SC-013**: No code duplication exists between project management scripts and status bar integration
- **SC-014**: Project configuration exported with `i3-save-tree` requires zero manual edits to be used as project config
- **SC-015**: Log viewer displays i3 events within 100ms of occurrence (measured via event subscription latency)
- **SC-016**: 100% of project operations (create, switch, delete) produce log entries with timestamp and outcome
- **SC-017**: 100% of i3-msg commands executed by system appear in logs with arguments and response status
- **SC-018**: Debug mode produces logs containing full i3 IPC responses and timing information for all operations
- **SC-019**: Log files rotate automatically when exceeding 10MB, maintaining last 5 rotations without manual intervention
- **SC-020**: User can diagnose failed project switch by reading log sequence showing which step failed and why

## Assumptions

- i3 window manager version 4.15+ is installed with IPC enabled
- i3blocks version 1.5+ is configured as the status command for i3bar
- jq JSON processor is available for parsing JSON in shell scripts
- rofi application launcher is installed for project switcher UI
- xdotool is available for automated testing via simulated key presses
- User has write permissions to `~/.config/i3/` directory
- Projects are stored as individual JSON files in `~/.config/i3/projects/`
- System uses Catppuccin Mocha color scheme for consistent theming
- NixOS with home-manager manages declarative configuration
- User works on a single workstation (not syncing projects across machines)
- Window manager is i3 on X11 (not sway/Wayland or other alternatives)

## Out of Scope

- Porting to window managers other than i3 (sway, Hyprland, etc.)
- Graphical UI for project creation and management (CLI-only)
- Automatic project detection based on git repository or current directory
- Project templates or scaffolding for new projects
- Syncing project configurations across multiple machines
- Session state persistence beyond active project file (full tmux/sesh session restoration is separate)
- Browser profile management per project (Firefox containers, Chrome profiles)
- Project-specific environment variables or shell configuration
- Multi-user project sharing on same system
- Project history or version control of project configurations
- Integration with external project management tools (JIRA, Asana, etc.)
- Performance optimization beyond current i3 native capabilities
- Support for more than 20 projects per user (reasonable limit for interactive switcher)

## Dependencies

- i3 window manager with IPC support (feature 012 dependency)
- i3blocks status command (feature 013 dependency)
- jq for JSON parsing in shell scripts
- rofi for interactive project switcher
- xdotool for automated testing
- bash 5.x for shell script compatibility
- NixOS with home-manager for declarative configuration management

## Migration Notes

This feature consolidates two previously implemented features:
- Feature 012: i3-Native Dynamic Project Workspace Management
- Feature 013: Migrate from Polybar to i3 Native Status Bar

The consolidation must:
1. Ensure project switching scripts correctly signal i3blocks (not polybar)
2. Verify i3blocks project indicator script reads the correct state file format
3. Remove any polybar-specific code or configuration
4. Validate that all i3 IPC usage follows official documentation
5. Test the complete integrated system end-to-end

## Testing Strategy

### Manual Testing Protocol

1. **Project Creation Test**: Create new project, verify JSON file exists, verify appears in switcher
2. **Project Activation Test**: Activate project, verify state file updated, verify status bar updated
3. **Application Launch Test**: Launch project-scoped app, verify mark assigned, verify workspace placement
4. **Project Switch Test**: Switch between projects, verify windows hidden/shown, verify status bar updated
5. **Global Application Test**: Launch global app, switch projects, verify app remains visible
6. **Edge Case Tests**: Test with invalid JSON, missing files, rapid switching, i3 restart

### Automated Testing with xdotool

Tests will simulate user interactions but must avoid closing the terminal:
- Use `xdotool key --window $(xdotool getactivewindow) Super_L+p` for project switcher
- Use `xdotool type --delay 100 "project-name"` to select project
- Use `xdotool key Return` to confirm selection
- Verify results using `i3-msg` commands and file system checks
- Always target specific window IDs, never rely on active window being terminal
