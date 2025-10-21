# Feature Specification: Enhanced i3pm TUI with Comprehensive Management & Automated Testing

**Feature Branch**: `022-create-a-new`
**Created**: 2025-10-21
**Status**: Draft
**Input**: User description: "create a new feature that enhances the user experience and functionality of our tui application.  currently the tui has some of the functionality, but we have more foundational functionality that we need to manage the lifecycle of projects, configure workspaces, layouts, etc.  that currently is not in the tui.  we also need to make the user experience better.  it's not intuitive for navigation, the look can be improved, etc.  also consider other areas for improvement.  then create a framework to test fully using simulated user interaction.  you should take action as though you are the user that navigates the tui, and then we should assert whether it resulted in the correct behavior relative to whether our state changed in the correct ways, whether we triggered the events we expect, etc.  one key area to expand for our tui is our windows detection matching, workspace to application mapping, and monitor detection and monitor to workspace mapping.  for all these items, deeply understand what fucntionality we already have in place before we implement new functionality."

## Clarifications

### Session 2025-10-21

- Q: When restoring a layout, should the system relaunch closed applications or only reposition existing windows? → A: Relaunch if missing - System should attempt to relaunch applications that aren't running, then reposition all windows. Layout restoration is fundamentally about application lifecycle management (launch/close/reposition), not just window repositioning. Projects require customized application launching (e.g., ghostty terminal opened in project directory with sesh, environment variable injection). This aligns with using i3's native RUN_COMMAND for launching and window matching for repositioning.

- Q: Should the "default application set" be the same as "auto-launch entries", or are they separate concepts? → A: Same concept - The default application set IS the auto-launch configuration. "Restore All" uses auto-launch entries to launch apps. This simplifies the mental model, reduces duplicate configuration, and provides a single source of truth for project applications.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete Layout Management Workflow (Priority: P1)

Users can save, restore, delete, and export window layouts entirely through the TUI without needing CLI commands. Currently, the Layout Manager screen exists but all operations show "not yet implemented" warnings.

**Why this priority**: Layout management is fundamental to project workflow optimization. Users switch between different window arrangements frequently (coding layout, debugging layout, review layout) and need quick, visual access to these operations. This is the most commonly requested missing feature.

**Independent Test**: Can be fully tested by launching TUI, navigating to a project's layout manager, and verifying that all save/restore/delete/export operations complete successfully with proper state persistence and UI feedback.

**Acceptance Scenarios**:

1. **Given** user has i3pm TUI open on a project with 3 windows arranged across 2 workspaces, **When** user presses 'l' to open Layout Manager and presses 's' to save with name "coding-layout", **Then** layout is saved to disk and appears in layouts table with correct window count and workspace count
2. **Given** user has saved layout "coding-layout", **When** user changes window arrangement and presses 'r' to restore "coding-layout", **Then** all windows return to their saved positions, workspaces, and sizes within 2 seconds
3. **Given** user has multiple saved layouts, **When** user selects a layout and presses 'd' to delete, **Then** confirmation dialog appears, and upon confirmation, layout is removed from disk and table
4. **Given** user has saved layout "coding-layout", **When** user presses 'e' to export, **Then** layout is exported as JSON file to user-specified location with all window configurations preserved

---

### User Story 2 - Workspace-to-Monitor Assignment Configuration (Priority: P1)

Users can configure which workspaces should appear on which monitor roles (primary/secondary/tertiary) directly from the TUI. Currently, workspace preferences exist in Project model but have no TUI interface.

**Why this priority**: Multi-monitor users need different workspace distributions for different projects. Development projects might want terminals on secondary monitor, while design projects might want tools on primary. This configuration is critical for productivity but currently requires manual JSON editing.

**Independent Test**: Can be fully tested by opening TUI, creating/editing a project, and verifying that workspace-to-monitor assignments persist and are correctly applied when switching projects on a multi-monitor setup.

**Acceptance Scenarios**:

1. **Given** user is editing a project in TUI, **When** user navigates to "Workspace Configuration" section and assigns WS1→primary, WS2→primary, WS3→secondary, **Then** preferences are saved to project JSON and daemon applies them on next project switch
2. **Given** user has 2 monitors connected, **When** user assigns workspace preferences and switches to that project, **Then** workspaces appear on correct monitors according to preferences within 500ms
3. **Given** user has workspace preferences configured, **When** user connects/disconnects monitors changing monitor count, **Then** TUI shows warning about preference conflicts and offers to auto-adjust or keep existing preferences
4. **Given** user is configuring workspace preferences, **When** user attempts to assign workspace to non-existent monitor role (e.g., tertiary with only 2 monitors), **Then** TUI shows validation error with current monitor count and available roles

---

### User Story 3 - Window Classification Wizard in TUI (Priority: P2)

Users can classify discovered applications as scoped/global using an interactive TUI wizard with live window inspection. Currently, CLI has `i3pm app-classes wizard` but lacks TUI integration.

**Why this priority**: Window classification is the foundation of project-scoped visibility. New users struggle with CLI-based classification and need visual feedback showing which windows are currently open and how they'll behave. This wizard reduces configuration friction significantly.

**Independent Test**: Can be fully tested by launching TUI, opening classification wizard, and verifying that classifications are applied immediately to running windows and persisted to configuration files.

**Acceptance Scenarios**:

1. **Given** user has 5 unclassified application windows open, **When** user opens classification wizard from TUI main menu, **Then** wizard displays table of all windows with class, title, workspace, and current classification status
2. **Given** user is in classification wizard, **When** user selects "VSCode" window and presses 's' for scoped, **Then** window class is added to scoped list, window immediately gets marked with project context, and change is persisted
3. **Given** user is in classification wizard, **When** user selects "Firefox" window and presses 'g' for global, **Then** window class is added to global list, window mark is removed, and browser remains visible across all projects
4. **Given** user has classified 10 applications, **When** user presses 'x' to export classification report, **Then** report is saved showing all classifications with window counts and pattern matches

---

### User Story 4 - Auto-Launch Configuration Interface (Priority: P2)

Users can configure which applications auto-launch when switching to a project, including workspace assignments and environment variables. Currently, auto-launch exists in Project model but has no TUI editor.

**Why this priority**: Auto-launch eliminates repetitive manual window opening when switching projects. Users want terminals, editors, and tools to automatically open in correct workspaces. This is a high-value convenience feature that improves daily workflow.

**Independent Test**: Can be fully tested by configuring auto-launch entries in TUI, switching to the project, and verifying that all specified applications launch on correct workspaces with proper environment.

**Acceptance Scenarios**:

1. **Given** user is editing a project, **When** user adds auto-launch entry "ghostty --working-directory $PROJECT_DIR" on WS1, **Then** entry is saved and terminal auto-launches on WS1 when switching to project
2. **Given** user has auto-launch entry configured, **When** user edits entry to add environment variable "DEBUG=1", **Then** launched application receives DEBUG=1 in addition to standard PROJECT_DIR and PROJECT_NAME variables
3. **Given** user has 3 auto-launch entries, **When** user reorders them using up/down keys, **Then** launch order is persisted and applications launch in new order on next project switch
4. **Given** user has auto-launch entry with wait_for_mark="project:nixos", **When** application launches but doesn't get marked within timeout, **Then** TUI shows notification with failure reason and remediation steps

---

### User Story 5 - Enhanced Navigation and Visual Design (Priority: P3)

Users can navigate the TUI intuitively using vim-style keybindings, mouse clicks, and visual indicators showing current location and available actions. Currently, navigation is keyboard-only with limited visual feedback.

**Why this priority**: Poor UX creates friction and discourages TUI adoption. Many users prefer CLI because the TUI is hard to navigate. Improved navigation and design will increase TUI usage and reduce support requests.

**Independent Test**: Can be fully tested by performing common navigation tasks (switching screens, selecting items, invoking actions) and measuring time-to-completion and error rates compared to current implementation.

**Acceptance Scenarios**:

1. **Given** user is on any TUI screen, **When** user looks at screen, **Then** breadcrumb navigation shows current location (e.g., "Projects > NixOS > Layouts") and footer shows contextual keybindings
2. **Given** user is browsing projects table, **When** user clicks on a project row with mouse, **Then** row is selected and Enter key or double-click switches to that project
3. **Given** user is in any input field, **When** user presses Tab, **Then** focus moves to next field with visual highlight, and Shift+Tab moves to previous field
4. **Given** user is viewing a data table, **When** user presses '/' for search, **Then** search box appears with placeholder text showing searchable fields and Escape clears search

---

### User Story 6 - Pattern-Based Window Matching Configuration (Priority: P3)

Users can create, test, and manage window class pattern rules through TUI. Currently, patterns exist (`i3pm app-classes add-pattern`) but lack TUI interface with live testing.

**Why this priority**: Pattern matching enables advanced window classification without listing every variation of window classes. Users with complex applications (Electron apps with changing classes, browser PWAs) need pattern rules but find CLI regex testing difficult.

**Independent Test**: Can be fully tested by creating pattern rules in TUI, testing them against live windows, and verifying that matching windows are correctly classified when patterns are saved.

**Acceptance Scenarios**:

1. **Given** user is in pattern configuration screen, **When** user creates pattern rule "^Code.*" → scoped and tests it, **Then** TUI shows list of all matching window classes currently open (e.g., "Code", "Code - Insiders")
2. **Given** user has pattern rule created, **When** user enables "Auto-apply" toggle, **Then** pattern is saved and daemon immediately reclassifies all matching windows without restart
3. **Given** user has multiple pattern rules, **When** user reorders them by priority, **Then** higher priority patterns match first and TUI shows which rule matched each window in test view
4. **Given** user creates conflicting pattern rules, **When** user tests patterns, **Then** TUI highlights conflicts showing which windows match multiple rules and suggests resolution

---

### User Story 7 - Automated TUI Testing Framework (Priority: P1)

Developers can run automated tests that simulate user interactions with TUI and verify state changes, event triggers, and UI behavior. Currently, no testing framework exists for TUI code.

**Why this priority**: Without automated testing, TUI changes risk breaking existing functionality. Manual testing is time-consuming and inconsistent. This framework enables confident iteration and prevents regressions.

**Independent Test**: Can be fully tested by writing a sample test case (e.g., "create project via wizard"), running it, and verifying that test passes with correct assertions on final state and events triggered.

**Acceptance Scenarios**:

1. **Given** developer writes test "test_create_project_wizard", **When** test runs, **Then** framework simulates key presses (n → fill fields → Enter), captures events, and asserts project file was created with correct data
2. **Given** test suite exists for all TUI screens, **When** developer runs `i3pm-test suite`, **Then** all tests execute in isolated environments (no interference between tests) and generate coverage report showing which UI paths were tested
3. **Given** test is running, **When** unexpected state occurs (e.g., daemon disconnected), **Then** test framework captures screenshots, state dumps, and logs for debugging before failing test with clear error message
4. **Given** developer writes test with timing assertions (e.g., "layout restore completes within 2 seconds"), **When** test runs, **Then** framework measures actual time and fails if threshold exceeded, providing performance regression detection

---

### User Story 8 - Monitor Detection and Workspace Redistribution (Priority: P2)

Users can see current monitor configuration in TUI and manually trigger workspace redistribution when monitors are connected/disconnected. Currently, monitor info is shown in daemon status but lacks interactive controls.

**Why this priority**: Laptop users frequently dock/undock, changing monitor count. Automatic workspace redistribution (Win+Shift+M) works but users want to see monitor status before/after and manually control redistribution timing.

**Independent Test**: Can be fully tested by opening TUI with 1 monitor, simulating monitor connection via xrandr, viewing updated monitor status, and triggering redistribution to verify workspaces move to correct monitors.

**Acceptance Scenarios**:

1. **Given** user is viewing Monitor Dashboard, **When** monitor configuration changes (connect/disconnect), **Then** monitor table updates within 1 second showing active outputs with name, resolution, role, and assigned workspaces
2. **Given** user sees monitor change notification, **When** user presses 'r' to redistribute workspaces, **Then** daemon triggers workspace reassignment and TUI shows progress (moving WS1→primary, WS3→secondary) with success confirmation
3. **Given** user has custom workspace preferences for active project, **When** user triggers redistribution, **Then** TUI shows dialog asking "Use project preferences or default distribution?" with preview of both options
4. **Given** user has 3 monitors and disconnects one, **When** redistribution triggers, **Then** workspaces from disconnected monitor migrate to remaining monitors and TUI shows migration summary (e.g., "WS6-9: tertiary → secondary")

---

### Edge Cases

- **What happens when user tries to save layout with no windows open?** TUI shows error: "Cannot save empty layout. Open at least one window in project context."
- **What happens when user tries to restore layout but required applications aren't installed?** TUI shows warning listing missing applications with their launch commands, offers to restore partial layout with available windows only, and allows user to edit launch commands or skip missing applications.
- **What happens when auto-launch command fails to execute?** TUI notification shows failure with stderr output and remediation steps (check command, verify PATH).
- **What happens when user configures workspace on monitor that doesn't exist?** TUI validates against current monitor count and shows error with available roles.
- **What happens when pattern rule has invalid regex syntax?** TUI shows syntax error inline with cursor position and example of valid pattern.
- **What happens when test framework can't connect to daemon?** Test fails immediately with clear error and remediation (start daemon, check socket permissions).
- **What happens when user has 10+ saved layouts?** Layout table scrolls with pagination controls and search filter to find layouts by name.
- **What happens when two users edit same project simultaneously?** TUI detects modification time mismatch on save and offers options: reload, merge changes, force overwrite.
- **What happens when monitor role changes during redistribution?** Operation completes with original roles and TUI shows warning suggesting retry with updated configuration.
- **What happens when auto-launch reaches max retry attempts?** TUI shows persistent notification with option to "Try Again" or "Disable Auto-Launch" for failing entry.

## Requirements *(mandatory)*

### Functional Requirements

#### Layout Management
- **FR-001**: System MUST allow users to save current window layout with user-provided name via TUI Layout Manager, capturing application identifiers, launch commands, environment variables, workspace assignments, and window geometries
- **FR-002**: System MUST restore saved layouts by relaunching missing applications with saved environment variables and project-specific configurations (e.g., ghostty with sesh in project directory), then repositioning all windows to saved workspaces and geometries within 2 seconds
- **FR-003**: System MUST provide "Restore All" action that launches all project applications if not running and positions them according to layout
- **FR-004**: System MUST provide "Close All" action that closes all project-scoped application windows
- **FR-005**: System MUST allow users to delete saved layouts with confirmation dialog
- **FR-006**: System MUST export layouts as JSON files to user-specified location
- **FR-007**: System MUST display layout metadata in table: name, window count, workspace count, saved date
- **FR-008**: System MUST allow users to configure project auto-launch entries (the default application set) with select/deselect capability in TUI, where "Restore All" launches all enabled entries

#### Workspace & Monitor Configuration
- **FR-009**: System MUST allow users to assign workspaces (1-10) to monitor roles (primary/secondary/tertiary) via TUI
- **FR-010**: System MUST validate workspace-to-monitor assignments against current monitor count
- **FR-011**: System MUST persist workspace preferences in project JSON configuration
- **FR-012**: System MUST display current monitor configuration with name, resolution, role, and assigned workspaces
- **FR-013**: System MUST allow manual triggering of workspace redistribution via TUI

#### Window Classification
- **FR-014**: System MUST provide TUI wizard showing all unclassified windows with class, title, workspace
- **FR-015**: System MUST allow users to mark windows as scoped or global with immediate effect
- **FR-016**: System MUST support pattern-based window matching with regex or glob syntax
- **FR-017**: System MUST allow users to test pattern rules against live windows before saving
- **FR-018**: System MUST persist all classifications to app-classes.json and pattern-rules.json

#### Auto-Launch Configuration
- **FR-019**: System MUST allow users to add/edit/delete/reorder auto-launch entries via TUI
- **FR-020**: System MUST validate auto-launch commands, workspace numbers, and timeout values
- **FR-021**: System MUST support environment variable configuration for auto-launch entries
- **FR-022**: System MUST display auto-launch status during project switch (launching/success/failed)
- **FR-023**: System MUST retry failed auto-launch entries up to 3 times with exponential backoff

#### Navigation & UX
- **FR-024**: System MUST support vim-style navigation (hjkl) in addition to arrow keys
- **FR-025**: System MUST support mouse click for row selection and button activation
- **FR-026**: System MUST display breadcrumb navigation showing current screen hierarchy
- **FR-027**: System MUST show contextual keybindings in footer based on active screen
- **FR-028**: System MUST provide inline validation with error messages for all input fields

#### Testing Framework
- **FR-029**: Framework MUST simulate user key presses, mouse events, and screen transitions
- **FR-030**: Framework MUST capture state changes, daemon events, and file modifications during tests
- **FR-031**: Framework MUST provide assertions for state verification, timing, and event sequences
- **FR-032**: Framework MUST execute tests in isolation preventing cross-test interference
- **FR-033**: Framework MUST generate test coverage reports showing tested UI paths and scenarios

### Key Entities

- **SavedLayout**: Represents a saved window arrangement with name, creation date, workspace configurations, window geometries, application identifiers, launch commands with arguments, environment variables, and working directories for application relaunching
- **WorkspacePreference**: Maps workspace number (1-10) to monitor role (primary/secondary/tertiary) for a specific project
- **MonitorConfig**: Describes physical monitor with output name, resolution, active status, primary flag, and assigned role
- **AutoLaunchEntry**: Configuration for automatic application launch with command, workspace, environment variables, timing parameters, and retry policy
- **PatternRule**: Window class matching rule with regex pattern, classification type (scoped/global), priority, and auto-apply flag
- **TestScenario**: Automated test definition with sequence of user actions, expected state changes, event assertions, and timing constraints
- **WindowClassification**: Classification state for a window class including type (scoped/global), source (manual/pattern/auto), and match history

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete full layout save/restore workflow in TUI without CLI commands in under 30 seconds
- **SC-002**: Workspace redistribution completes and windows appear on correct monitors within 2 seconds of monitor connection
- **SC-003**: Window classification wizard reduces classification time by 60% compared to manual CLI editing (measured for 20 application set)
- **SC-004**: 95% of TUI navigation tasks can be completed using only keyboard with no mouse required
- **SC-005**: Auto-launch entries execute successfully with 98% reliability (failed launches include clear error messages and remediation)
- **SC-006**: Pattern rule testing shows live matching results within 500ms of rule modification
- **SC-007**: Test framework executes full test suite (covering all user stories) in under 5 minutes
- **SC-008**: Test framework detects UI regressions with 100% accuracy (no false negatives for broken workflows)
- **SC-009**: New users can configure first project including classifications, workspace preferences, and auto-launch in under 5 minutes using only TUI
- **SC-010**: Monitor configuration display updates within 1 second of physical monitor connection/disconnection events

## Assumptions

- **Assumption 1**: i3 window manager IPC is accessible and responsive (consistent with existing daemon implementation)
- **Assumption 2**: Users have systemd user services enabled for daemon management (required for existing i3pm functionality)
- **Assumption 3**: Application launching uses i3's native RUN_COMMAND IPC for execution and GET_TREE for window matching (leveraging i3ipc-python library patterns)
- **Assumption 4**: Window identification for repositioning uses i3 window properties (class, instance, title, role) available via GET_TREE
- **Assumption 5**: Multi-monitor configuration uses xrandr or equivalent (consistent with i3 output detection via GET_OUTPUTS)
- **Assumption 6**: Test framework runs in headless environment using Xvfb or similar virtual display (standard for Python TUI testing)
- **Assumption 7**: Mouse support requires terminal emulator with mouse event passthrough (xterm-compatible terminals)
- **Assumption 8**: Saved layouts remain compatible across i3 version updates (based on stable i3 IPC command format)
- **Assumption 9**: Pattern matching uses Python regex syntax (consistent with existing pattern implementation)
- **Assumption 10**: Auto-launch and layout restoration commands execute in user's default shell environment with project context variables (PROJECT_DIR, PROJECT_NAME, I3_PROJECT)
- **Assumption 11**: TUI testing framework can intercept and simulate Textual framework events (leveraging Textual's Pilot API for testing)

## Out of Scope

- **Remote window management**: Managing windows on remote i3 instances or SSH sessions
- **Cross-platform support**: Windows or macOS desktop environment integration (NixOS/Linux only)
- **Layout templates repository**: Sharing layouts between users or syncing via cloud
- **Advanced pattern DSL**: Complex pattern language beyond regex (glob is sufficient)
- **Real-time collaboration**: Multiple users editing same project configuration simultaneously
- **Layout versioning**: Git-like diff/merge for layout changes
- **Performance profiling**: Built-in profiling tools for window operations
- **Plugin system**: Third-party extensions for TUI screens or custom actions
- **Voice control**: Speech recognition for TUI navigation
- **Accessibility features**: Screen reader integration, high-contrast themes (may be future enhancement)

## Dependencies

- **i3 Window Manager IPC**: Native i3 IPC protocol for RUN_COMMAND (application launching), GET_TREE (window queries), GET_OUTPUTS (monitor detection), and GET_WORKSPACES (workspace state)
- **i3ipc.aio**: Async Python library for i3 IPC communication (already in use, provides Connection, event subscriptions, and command execution)
- **Textual Framework**: Python TUI framework powering all UI screens (already in use)
- **Event-based Daemon**: i3-project-event-listener systemd service for real-time window marking (already implemented)
- **Pydantic or Dataclasses**: Data validation for all configuration models (already in use via dataclasses)
- **pytest & pytest-asyncio**: Testing framework for test suite execution (standard Python testing)
- **Textual Pilot API**: Built-in testing utilities for simulating TUI interactions (part of Textual framework)

## Constraints

- **Performance**: All TUI operations must complete within 2 seconds to maintain responsive feel
- **Backward Compatibility**: Existing project JSON files must continue to work without migration
- **Daemon Uptime**: Layout/workspace operations depend on daemon being running and connected to i3
- **Terminal Requirements**: Mouse support requires xterm-compatible terminal emulator
- **Monitor Limit**: Workspace redistribution supports up to 10 monitors (i3 has 10 workspaces)
- **Layout Size**: Saved layouts limited to 100 windows per layout (practical maximum for usability)
- **Test Isolation**: Each test must run in isolated environment to prevent state pollution
- **Configuration Atomicity**: All configuration saves must be atomic to prevent corruption on crashes

## Related Documentation

- **Existing CLI Audit**: All CLI commands documented in `/etc/nixos/CLAUDE.md` under "Project Management Workflow"
- **Current TUI Screens**: Browser, Monitor, Editor, Layout Manager, Wizard screens implemented in `/etc/nixos/home-modules/tools/i3_project_manager/tui/screens/`
- **Data Models**: Project, AutoLaunchApp, SavedLayout defined in `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py`
- **Daemon IPC**: Event-driven daemon with JSON-RPC server in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/`
- **Window Classification**: Pattern matching and app discovery in `/etc/nixos/home-modules/tools/i3_project_manager/core/pattern_matcher.py`
- **Workspace Manager**: Monitor detection and workspace assignment in `/etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
