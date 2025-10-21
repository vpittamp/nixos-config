# Feature Specification: i3 Project Management System Validation & Enhancement

**Feature Branch**: `019-re-explore-and`
**Created**: 2025-10-20
**Status**: Draft
**Input**: User description: "Re-explore and validate i3 project management workflow including CRUD operations, window associations, monitor assignments, application launching via rofi/desktop files, event-based subscriptions, PWA/terminal app isolation, automated project restoration, and closing capabilities"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Project Context Switching (Priority: P1)

A developer works on multiple projects (NixOS configuration, web application, personal tools) throughout the day. They need to instantly switch between project contexts where each project shows only its relevant windows (VS Code, terminals, file managers) while keeping global tools (browser, communication apps) always visible.

**Why this priority**: Core workflow that delivers immediate value. Without reliable project switching, the entire system fails its primary purpose.

**Independent Test**: Can be fully tested by creating 2 projects, opening 2 windows in each project, then switching between them and verifying windows show/hide correctly within 200ms.

**Acceptance Scenarios**:

1. **Given** user has active project "nixos" with 3 VS Code windows and 2 terminals, **When** user switches to project "webapp" via Win+P keystroke, **Then** all nixos windows become hidden and webapp windows become visible in under 200ms
2. **Given** user is in "global mode" (no active project), **When** user launches Firefox browser, **Then** Firefox remains visible when switching to any project
3. **Given** user has 3 projects with varying numbers of windows (0-50), **When** user cycles through projects using rofi selector, **Then** each switch completes within 200ms regardless of window count
4. **Given** user switches from project A to project B, **When** user returns to project A, **Then** all previously visible windows are restored to their exact workspaces and monitors

---

### User Story 2 - Automated Window Association (Priority: P1)

When a developer launches an application (VS Code, terminal, file manager) while a project is active, the window should automatically associate with that project context without manual intervention. When the project switches, these windows should hide. Global applications (browsers, PWAs) should remain visible across all projects.

**Why this priority**: Manual window tagging is tedious and error-prone. Automatic association is essential for usability.

**Independent Test**: Activate project "nixos", launch VS Code via Win+C, verify window gets mark "project:nixos" within 100ms, switch to different project, verify VS Code window is hidden.

**Acceptance Scenarios**:

1. **Given** user activates project "stacks", **When** user launches VS Code via keybinding or rofi, **Then** VS Code window receives mark "project:stacks" within 100ms of window creation
2. **Given** user has active project "nixos", **When** user launches Firefox browser, **Then** Firefox does NOT receive a project mark and remains visible when switching projects
3. **Given** user launches Ghostty terminal with project "webapp" active, **When** user opens multiple terminal tabs/windows, **Then** all terminal instances receive "project:webapp" mark
4. **Given** user has multiple instances of same application (VS Code) across different projects, **When** viewing window list, **Then** each instance clearly shows which project it belongs to via marks

---

### User Story 3 - Project Creation and Configuration (Priority: P1)

A developer starts working on a new project and needs to create a project configuration that defines the project name, working directory, icon, and which applications should auto-launch when the project opens. The system should validate configuration and provide clear feedback.

**Why this priority**: Creating projects is the entry point to the system. Must be intuitive and reliable.

**Independent Test**: Run `i3-project-create --name=test --dir=/tmp/test`, verify project config file created at `~/.config/i3/projects/test.json`, verify project appears in `i3-project-list`, verify can switch to project.

**Acceptance Scenarios**:

1. **Given** user runs `i3-project-create` with name, directory, display-name, and icon, **When** command completes, **Then** valid JSON config file exists at `~/.config/i3/projects/{name}.json` and project appears in project list immediately
2. **Given** user creates project with non-existent directory path, **When** project creation runs, **Then** system creates directory or warns user clearly about missing directory
3. **Given** user attempts to create project with duplicate name, **When** creation command runs, **Then** system prevents duplicate and suggests using `--update` flag to modify existing project
4. **Given** user creates new project, **When** user activates project without launching any apps, **Then** project becomes active immediately even with zero windows

---

### User Story 4 - Multi-Monitor Workspace Assignment (Priority: P2)

A developer connects/disconnects external monitors throughout the day. Workspaces should automatically distribute across available monitors based on predefined rules (WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary). Project windows should appear on their designated monitors when the project activates.

**Why this priority**: Multi-monitor support is common but not essential for single-monitor users. Important for professional setups.

**Independent Test**: Connect 2 monitors, verify WS 1-2 assigned to primary and WS 3-9 to secondary, disconnect secondary monitor, verify all workspaces move to primary.

**Acceptance Scenarios**:

1. **Given** user has single monitor setup, **When** user connects second monitor, **Then** within 2 seconds workspaces 3-9 automatically move to secondary monitor
2. **Given** user has project "nixos" with windows configured for specific workspaces (WS1 for terminal, WS4 for editor), **When** user activates project, **Then** windows appear on correct workspaces which map to correct physical monitors
3. **Given** user disconnects secondary monitor, **When** monitor disconnection detected, **Then** all windows from secondary monitor workspaces move to primary monitor within 2 seconds
4. **Given** user has project with workspace-to-monitor preferences saved, **When** user reconnects monitors in different configuration, **Then** system adapts workspace assignments to new monitor layout

---

### User Story 5 - Project Restoration and Automated Launching (Priority: P2)

A developer wants to define a "startup layout" for each project that specifies which applications to launch, on which workspaces/monitors, when the project activates. When switching to the project for the first time in a session, the system should automatically launch all configured applications.

**Why this priority**: Automation improves productivity but manual launching is acceptable initially. Enhances user experience significantly.

**Independent Test**: Configure project "nixos" with auto-launch rules (VS Code on WS1, 2 terminals on WS2), activate project, verify all applications launch automatically in designated workspaces.

**Acceptance Scenarios**:

1. **Given** project "webapp" configured with auto-launch apps (VS Code, 2 terminals, browser), **When** user activates project for first time in session, **Then** all configured applications launch automatically within 5 seconds
2. **Given** project already has running windows, **When** user activates project again, **Then** system does NOT launch duplicate applications, only shows existing windows
3. **Given** project configured to launch VS Code on WS1 and terminals on WS4, **When** auto-launch triggers, **Then** applications appear on their designated workspaces which map to correct monitors
4. **Given** auto-launch application fails to start, **When** launch timeout (10s) expires, **Then** system logs error, shows notification, and continues launching remaining apps

---

### User Story 6 - Project Closing and Cleanup (Priority: P3)

A developer finishes working on a project for the day and wants to close all project-associated windows in one command while preserving global applications. The system should optionally save window state for next session.

**Why this priority**: Nice-to-have convenience feature. Users can manually close windows if needed.

**Independent Test**: Activate project "stacks" with 5 windows, run `i3-project-close stacks`, verify all stacks windows close while global apps remain open.

**Acceptance Scenarios**:

1. **Given** user has project "nixos" active with 10 windows, **When** user runs `i3-project-close nixos`, **Then** all 10 project windows close gracefully and global windows remain open
2. **Given** user has unsaved work in VS Code window, **When** `i3-project-close` runs, **Then** VS Code prompts user to save before closing (graceful shutdown via window manager close signal)
3. **Given** user closes project with `--save-layout` flag, **When** project closes, **Then** system saves current window positions/workspaces to project config for next restoration
4. **Given** user runs `i3-project-close --all`, **When** command executes, **Then** all project-scoped windows across ALL projects close, leaving only global applications

---

### User Story 7 - Real-Time Validation and Monitoring (Priority: P2)

A developer or system administrator needs to validate that the i3 project management system is functioning correctly, diagnose issues when windows don't auto-mark, understand event flow, and monitor daemon health. The system should provide comprehensive diagnostics.

**Why this priority**: Essential for troubleshooting and confidence in the system, but not needed for basic operation.

**Independent Test**: Run `i3-project-monitor --mode=events`, create new window, verify event appears in monitor within 100ms showing window creation and marking.

**Acceptance Scenarios**:

1. **Given** user runs `i3-project-monitor` in live dashboard mode, **When** user switches projects and creates windows, **Then** monitor displays current state (active project, window count, recent events) updating in real-time
2. **Given** user runs `i3-project-monitor --mode=events`, **When** any i3 window/workspace event occurs, **Then** event appears in monitor output within 100ms with timestamp, event type, and details
3. **Given** user runs `i3-project-test suite`, **When** automated tests execute, **Then** all core scenarios (project switching, window marking, multi-monitor) run and report pass/fail with detailed diagnostics
4. **Given** daemon encounters error marking window, **When** error occurs, **Then** `i3-project-daemon-status` shows error count and recent error details for debugging

---

### User Story 8 - Application Launcher Integration (Priority: P2)

A developer uses rofi (application launcher) and desktop files to launch applications. When a project is active, applications should launch with project context automatically set via environment variables. Launcher should optionally show project-filtered application list.

**Why this priority**: Smooth integration with existing launcher workflows improves UX but isn't required for core functionality.

**Independent Test**: Activate project "nixos", launch VS Code via rofi, verify `PROJECT_CONTEXT=nixos` environment variable set and window marked correctly.

**Acceptance Scenarios**:

1. **Given** user activates project "webapp", **When** user launches VS Code via rofi (Win+D), **Then** VS Code starts with environment variables `I3_PROJECT=webapp` and `PROJECT_DIR=/path/to/webapp` set
2. **Given** user has custom `.desktop` file for project-specific launcher, **When** user launches via rofi, **Then** desktop file's `Exec=` command receives project context variables
3. **Given** user configures rofi to show project-filtered apps, **When** user opens launcher, **Then** rofi displays only applications relevant to active project plus global apps
4. **Given** user launches terminal application, **When** terminal starts, **Then** shell changes to project directory automatically (via shell profile hooks)

---

### User Story 9 - Unified Project Management Interface (Priority: P1)

A developer wants an intuitive way to manage projects without manually editing JSON files. They need a visual interface to create projects, configure auto-launch applications, save/restore layouts, and monitor system state all from a unified tool that works both interactively and from the command line.

**Why this priority**: Current system requires manual JSON editing which is error-prone and has steep learning curve. A unified interface dramatically improves usability and discovery.

**Independent Test**: Run `i3pm` (no args) to open interactive TUI, create new project via wizard, configure auto-launch apps, save layout, verify all operations work without touching JSON files.

**Acceptance Scenarios**:

1. **Given** user runs `i3pm` with no arguments, **When** terminal displays interactive UI, **Then** user sees project browser with all projects, can navigate with arrow keys, and can access all features via keyboard shortcuts
2. **Given** user presses `n` in project browser, **When** project creation wizard starts, **Then** user fills in basic info (name, directory, icon) with visual feedback and validation errors shown inline
3. **Given** user configures auto-launch apps in editor screen, **When** user adds VS Code and 2 terminals with workspace assignments, **Then** UI shows table of apps with workspace/monitor columns and allows editing without understanding JSON schema
4. **Given** user saves current window layout, **When** layout manager captures 5 windows across 3 workspaces, **Then** system creates portable JSON file and allows user to restore exact layout later including window positions
5. **Given** user runs `i3pm switch webapp`, **When** command executes from CLI, **Then** project switches in <200ms and rich-formatted output confirms switch with color-coded status
6. **Given** user has monitoring screen open in TUI, **When** window events occur, **Then** event stream updates in real-time showing window::new, window::mark events with syntax highlighting
7. **Given** user runs `i3pm edit nixos` from CLI, **When** command executes, **Then** TUI opens directly to project editor screen pre-loaded with nixos config
8. **Given** user has unsaved changes in project editor, **When** user presses `s` to save, **Then** system validates config, shows validation results, and only saves if all checks pass

---

### Edge Cases

- **What happens when daemon crashes during project switch?** System should recover gracefully on restart, reading last active project from state file, re-marking windows based on existing i3 marks, no data loss
- **What happens when user manually removes project mark from window?** Daemon detects mark removal via `mark` event, removes window from project tracking, window becomes global
- **What happens when project directory is deleted?** System continues functioning but warns user when trying to launch project-specific apps; project list shows warning indicator
- **What happens when 100+ windows exist across 5 projects?** System maintains sub-200ms switch times by using efficient mark-based queries instead of iterating all windows
- **What happens when user creates circular dependencies in auto-launch config?** System detects cycles during validation, refuses to save config, shows error explaining the cycle
- **What happens when two windows have same class but should belong to different projects?** System uses mark-based association rather than class-based, so same-class windows can have different project marks
- **What happens when monitor gets disconnected during window auto-launch?** System adapts workspace assignments to remaining monitors, launches apps on equivalent workspace on remaining monitor
- **What happens when PWA and native browser window have similar titles?** System distinguishes via window class (PWA has unique class like `youtube-music`, browser is `firefox`)
- **What happens during i3 restart?** Daemon reconnects to new i3 IPC socket automatically, rebuilds state from persisted marks, restores active project from state file

## Requirements *(mandatory)*

### Functional Requirements

**Core Project Management**:

- **FR-001**: System MUST support creating projects with required fields (name, directory, display-name, icon) and optional fields (auto-launch apps, workspace assignments)
- **FR-002**: System MUST prevent duplicate project names and validate directory paths exist before allowing project creation
- **FR-003**: System MUST persist project configurations to individual JSON files in `~/.config/i3/projects/{name}.json`
- **FR-004**: System MUST allow listing all projects with status indicators (active, window count, last used timestamp)
- **FR-005**: System MUST allow editing existing project configurations via CLI command that opens $EDITOR
- **FR-006**: System MUST allow deleting projects with confirmation prompt to prevent accidental deletion
- **FR-007**: System MUST validate project JSON schema on load and reject invalid configurations with clear error messages

**Window Association**:

- **FR-008**: System MUST automatically mark windows with `project:{name}` mark within 100ms of window creation when project is active
- **FR-009**: System MUST distinguish between project-scoped window classes (VS Code, terminals) and global classes (browsers, PWAs) via configurable classification file
- **FR-010**: System MUST support manual window marking via i3-msg commands and update internal tracking automatically
- **FR-011**: System MUST handle multiple instances of same application class across different projects by using marks instead of class matching
- **FR-012**: System MUST persist window marks in i3's layout state across i3 restarts
- **FR-013**: System MUST detect window close events and remove from project tracking

**Project Switching**:

- **FR-014**: System MUST switch active project context within 200ms for up to 50 windows
- **FR-015**: System MUST hide all windows from previous project when switching projects
- **FR-016**: System MUST show all windows from newly activated project
- **FR-017**: System MUST never hide global-class windows when switching projects
- **FR-018**: System MUST support clearing active project to enter "global mode" where all windows are visible
- **FR-019**: System MUST provide visual feedback (rofi notification, status bar update) confirming project switch
- **FR-020**: System MUST persist active project state to file for daemon restart recovery

**Event-Based Daemon**:

- **FR-021**: System MUST use i3's IPC event subscription for window, workspace, tick, and shutdown events (no polling)
- **FR-022**: System MUST run as systemd user service with auto-restart on failure
- **FR-023**: System MUST expose IPC socket for CLI tool communication using JSON-RPC protocol
- **FR-024**: System MUST process tick events with payload `project:{name}` to trigger project switches
- **FR-025**: System MUST handle i3 restart by reconnecting IPC socket and rebuilding state from marks
- **FR-026**: System MUST log all events and errors to systemd journal for debugging
- **FR-027**: System MUST report daemon health status (uptime, event count, errors) via status command

**Multi-Monitor Support**:

- **FR-028**: System MUST query i3 for current output (monitor) configuration using GET_OUTPUTS IPC message
- **FR-029**: System MUST assign workspaces to monitors based on configurable rules (default: WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary)
- **FR-030**: System MUST detect monitor connection/disconnection via output events
- **FR-031**: System MUST reassign workspaces automatically when monitor configuration changes
- **FR-032**: System MUST support manual workspace reassignment via keybinding (Win+Shift+M)

**Application Launching**:

- **FR-033**: System MUST support auto-launching configured applications when project first activated in session
- **FR-034**: System MUST prevent duplicate application launches if windows already exist for project
- **FR-035**: System MUST launch applications with environment variables `I3_PROJECT={name}` and `PROJECT_DIR={directory}`
- **FR-036**: System MUST support launching applications on specific workspaces via workspace move commands
- **FR-037**: System MUST handle application launch failures gracefully (log error, notify user, continue with remaining apps)
- **FR-038**: System MUST support launching applications via desktop files (.desktop) with project context injected

**Project Restoration**:

- **FR-039**: System MUST optionally save window layout (workspaces, positions, sizes) when project deactivates
- **FR-040**: System MUST restore saved window layout when project reactivates if layout save exists
- **FR-041**: System MUST handle missing applications during restoration (log warning, skip missing apps)

**Project Closing**:

- **FR-042**: System MUST close all windows for specified project using graceful window close signals
- **FR-043**: System MUST preserve application state (allow save prompts) when closing windows
- **FR-044**: System MUST support closing all projects at once while preserving global windows
- **FR-045**: System MUST optionally save layout before closing windows for next restoration

**Testing and Validation**:

- **FR-046**: System MUST provide automated test suite covering project lifecycle, window marking, switching, multi-monitor, and edge cases
- **FR-047**: System MUST provide real-time monitoring tool showing daemon state, active project, events, and window tracking
- **FR-048**: System MUST provide test runner that executes scenarios and reports pass/fail with detailed diagnostics
- **FR-049**: System MUST support diagnostic mode that captures complete system state (daemon status, marks, windows, configs) for bug reports

**Rofi Integration**:

- **FR-050**: System MUST provide rofi project switcher accessible via keybinding (Win+P by default)
- **FR-051**: System MUST display projects in rofi with icons, display names, and window counts
- **FR-052**: System MUST support filtering rofi project list by typing partial project name
- **FR-053**: System MUST optionally integrate with rofi application launcher to inject project context

**PWA and Terminal Isolation**:

- **FR-054**: System MUST distinguish Progressive Web Apps (PWAs) from native browser windows using unique window class names
- **FR-055**: System MUST support marking individual PWA windows with project context (e.g., `youtube-music` can be project-scoped or global)
- **FR-056**: System MUST support marking individual terminal instances with project context even when using terminal multiplexers (tmux, sesh)
- **FR-057**: System MUST handle terminal title changes without losing project mark

**Unified Interface (TUI + CLI)**:

- **FR-058**: System MUST provide unified command (`i3pm` or `i3-project`) that works both interactively (TUI) and via CLI subcommands
- **FR-059**: System MUST launch interactive TUI when command run without arguments, CLI mode when arguments provided
- **FR-060**: System MUST provide TUI project browser showing all projects with window counts, active status, and keyboard navigation
- **FR-061**: System MUST provide TUI project editor allowing visual configuration of auto-launch apps, workspace assignments, without editing JSON
- **FR-062**: System MUST provide project creation wizard with 4 steps (basic info, app selection, auto-launch setup, review) with inline validation
- **FR-063**: System MUST integrate monitoring dashboard into TUI accessible via mode switching (live, events, history, tree, diagnose)
- **FR-064**: System MUST provide layout manager screen showing current window arrangement, saved layouts, and restore/export options
- **FR-065**: System MUST validate configuration changes in real-time before saving, showing clear error messages for invalid configs
- **FR-066**: System MUST support keyboard-only navigation in TUI with visible shortcuts (displayed in footer)
- **FR-067**: System MUST provide CLI subcommands for all operations (create, edit, delete, switch, save-layout, restore-layout, monitor, test)
- **FR-068**: System MUST output rich-formatted tables and status messages in CLI mode using consistent color scheme
- **FR-069**: System MUST maintain backward compatibility with existing CLI commands via symlinks or wrapper scripts
- **FR-070**: System MUST allow launching TUI directly to specific screen (e.g., `i3pm edit nixos` opens TUI to editor for nixos project)
- **FR-071**: System MUST support exporting/importing project configurations including layouts in portable JSON format
- **FR-072**: System MUST provide shell completion scripts (bash, zsh, fish) for CLI subcommands and project names

### Key Entities *(include if feature involves data)*

- **Project**: Represents a work context with name (unique identifier), display_name (human-readable), directory (filesystem path), icon (Unicode emoji/character), created timestamp, last_active timestamp, and optional auto_launch configuration (list of apps with workspace assignments)

- **Window**: Represents an X11 window managed by i3 with window_id (i3 container ID), window_class (X11 WM_CLASS), title (X11 _NET_WM_NAME), marks (list including project mark), workspace (i3 workspace name/number), visible (boolean based on active project)

- **Application Classification**: Defines window class categorization with scoped_classes (list of classes marked with project context), global_classes (list of classes never marked with projects), configurable in `app-classes.json`

- **Daemon State**: In-memory state maintained by daemon including active_project (current project name or null), window_to_project (map of window_id to project_name), project_to_windows (map of project_name to list of window_ids), event_count (total events processed), error_count (total errors encountered)

- **Auto-Launch Rule**: Defines application to launch for project with app_desktop_file (path to .desktop file or command string), workspace (target workspace number/name or null for current), monitor (target monitor name or null for current workspace's monitor), environment (additional env vars beyond I3_PROJECT and PROJECT_DIR)

- **Workspace Assignment**: Defines workspace-to-monitor mapping with workspace_number (1-9 or named workspace), output_name (monitor name from xrandr), monitor_priority (primary/secondary/tertiary for auto-assignment)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can switch between projects with all windows showing/hiding correctly in under 200ms for workloads up to 50 windows
- **SC-002**: New windows automatically receive project marks within 100ms of creation with 99% reliability
- **SC-003**: Daemon runs continuously for 30+ days without crashes or memory leaks (memory usage stays under 50MB)
- **SC-004**: Project creation completes in under 1 second including validation and daemon notification
- **SC-005**: Multi-monitor workspace reassignment completes within 2 seconds of monitor connection/disconnection
- **SC-006**: Auto-launch of 5 applications completes within 5 seconds with all apps starting on correct workspaces
- **SC-007**: Automated test suite runs in under 60 seconds and reports pass/fail for all 20+ test scenarios
- **SC-008**: System recovers from daemon crash within 3 seconds, restoring full functionality without user intervention
- **SC-009**: Users can diagnose 90% of issues using provided monitoring and diagnostic tools without reading source code
- **SC-010**: Project switcher (rofi) responds to keypresses within 50ms showing project list with correct window counts

### User Satisfaction Metrics

- **SC-011**: Users complete common tasks (create project, switch project, launch apps) on first attempt without consulting documentation
- **SC-012**: 95% of project switches complete without visible windows from old project remaining or wrong windows showing
- **SC-013**: System provides clear, actionable error messages when operations fail (e.g., "Project 'foo' not found. Available projects: bar, baz")
- **SC-014**: Zero manual window marking required for standard workflows (VS Code, terminals, file managers auto-mark correctly)

### UX/Interface Metrics

- **SC-015**: New users can create first project using TUI wizard in under 2 minutes without documentation
- **SC-016**: TUI responds to all keyboard inputs within 50ms providing immediate visual feedback
- **SC-017**: Project configuration changes validate and save in under 500ms
- **SC-018**: Layout save/restore completes in under 5 seconds for 10 windows across 3 workspaces
- **SC-019**: CLI commands provide formatted output with colors/tables that render correctly in 95% of terminals
- **SC-020**: 90% of users discover key features through TUI exploration without reading docs (via visible shortcuts, tooltips, wizard)

## Assumptions

1. **i3 version compatibility**: Assumes i3 window manager version 4.20 or later with stable IPC protocol supporting SUBSCRIBE, GET_TREE, GET_MARKS, GET_OUTPUTS, and RUN_COMMAND messages
2. **Event subscription reliability**: Assumes i3's IPC event system reliably delivers window::new, window::close, window::mark, workspace::focus, output::unspecified, and tick events without drops
3. **Environment variable propagation**: Assumes applications launched via `i3-msg exec` or rofi inherit environment variables set by parent process
4. **Desktop file standards**: Assumes .desktop files follow freedesktop.org Desktop Entry Specification with standard Exec, Name, and Icon fields
5. **Window class stability**: Assumes applications use consistent WM_CLASS values that don't change between launches or versions
6. **Terminal multiplexer compatibility**: Assumes terminal multiplexers (tmux, sesh) preserve window class while allowing title changes
7. **PWA window classes**: Assumes Firefox PWAs use unique window class names (e.g., `youtube-music`) distinct from main browser (`firefox`)
8. **Monitor naming consistency**: Assumes xrandr output names remain stable across sessions (e.g., `HDMI-1` doesn't become `HDMI-2` on reconnect)
9. **Filesystem accessibility**: Assumes project directories are always accessible (local filesystem, not network mounts that may disconnect)
10. **JSON-RPC over UNIX socket**: Assumes UNIX domain sockets provide reliable IPC between daemon and CLI tools with <10ms latency
11. **Systemd user session**: Assumes systemd user session is available for managing daemon service with auto-restart capabilities
12. **Single i3 instance**: Assumes single i3 instance per user session (not nested i3 sessions or multiple displays with separate i3 instances)
