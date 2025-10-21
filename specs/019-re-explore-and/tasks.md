# Implementation Tasks: i3pm (i3 Project Manager)

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20 | **Phase**: Phase 2 Tasks
**Plan**: [plan.md](./plan.md) | **Spec**: [spec.md](./spec.md) | **Data Model**: [data-model.md](./data-model.md)

## Overview

This document breaks down the implementation of the unified i3 project management system (`i3pm`) into executable tasks organized by user story. Each user story represents an independently testable increment that delivers value.

**Implementation Strategy**: Incremental delivery starting with MVP (User Stories P1), then enhanced features (P2), then polish (P3).

---

## Task Organization

Tasks are grouped into phases:
1. **Phase 1**: Setup - Project initialization and shared infrastructure
2. **Phase 2**: Foundational - Prerequisites for all user stories
3. **Phase 3-8**: User Stories P1 (critical path, MVP scope)
4. **Phase 9-11**: User Stories P2 (enhanced features)
5. **Phase 12**: User Story P3 (nice-to-have)
6. **Phase 13**: Polish & Integration

**Parallelizable tasks** are marked with `[P]` when they work on different files.

**User story labels** like `[US1]`, `[US2]` show which story each task serves.

---

## Phase 1: Setup (Project Initialization)

### T001: Create Python package structure [P] - ✅ COMPLETED

**File**: `home-modules/tools/i3_project_manager/`

**Description**: Initialize the unified Python package with proper structure for core, CLI, and TUI modules.

**Tasks**:
- Create directory structure:
  ```
  i3_project_manager/
  ├── __init__.py
  ├── __main__.py
  ├── core/
  │   └── __init__.py
  ├── cli/
  │   └── __init__.py
  ├── tui/
  │   ├── __init__.py
  │   ├── screens/
  │   │   └── __init__.py
  │   └── widgets/
  │       └── __init__.py
  └── validators/
      └── __init__.py
  ```
- Create `pyproject.toml` with dependencies:
  - textual >= 0.47.0
  - rich >= 13.7.0
  - i3ipc >= 2.2.0
  - argcomplete
  - pytest
  - pytest-asyncio
  - pytest-textual
- Create `__init__.py` with version info

**Acceptance**: Directory structure exists, package is pip-installable

**Story**: Setup

---

### T002: Create test infrastructure [P] - ✅ COMPLETED

**File**: `tests/i3_project_manager/`

**Description**: Set up pytest structure with fixtures for mocking i3 IPC and daemon.

**Tasks**:
- Create test directory structure:
  ```
  tests/i3_project_manager/
  ├── conftest.py
  ├── test_core/
  │   └── __init__.py
  ├── test_cli/
  │   └── __init__.py
  └── test_tui/
      └── __init__.py
  ```
- Create `conftest.py` with fixtures:
  - `mock_i3_connection` - Mock i3ipc.aio.Connection
  - `mock_daemon_client` - Mock daemon IPC
  - `temp_config_dir` - Temporary config directory
  - `sample_project` - Sample project fixture
- Configure pytest.ini with async settings

**Acceptance**: `pytest` runs successfully with no tests

**Story**: Setup

---

### T003: Create NixOS module configuration [P] - ✅ COMPLETED

**File**: `home-modules/tools/i3-project-manager.nix`

**Description**: Create NixOS home-manager module for installing i3pm.

**Tasks**:
- Create module file with `programs.i3pm.enable` option
- Add Python package dependencies to buildInputs
- Install i3pm executable to bin/
- Add shell completions for bash/zsh
- Add systemd service dependency on i3-project-event-listener

**Acceptance**: Module can be imported and enabled in NixOS config

**Story**: Setup

---

## Phase 2: Foundational (Prerequisites for All User Stories)

### T004: Implement core data models - ✅ COMPLETED

**File**: `home-modules/tools/i3_project_manager/core/models.py`

**Description**: Create Python dataclasses for all entities from data-model.md.

**Tasks**:
- Implement `Project` dataclass with:
  - Fields: name, directory, display_name, icon, scoped_classes, workspace_preferences, auto_launch, saved_layouts, created_at, modified_at
  - Validation in `__post_init__`
  - `to_json()` / `from_json()` methods
  - `save()` / `load()` / `list_all()` / `delete()` methods
- Implement `AutoLaunchApp` dataclass
- Implement `SavedLayout` dataclass
- Implement `WorkspaceLayout` dataclass
- Implement `LayoutWindow` dataclass
- Implement `AppClassification` dataclass
- Implement `TUIState` dataclass (runtime only)
- Add type hints to all public methods

**Acceptance**: All models serialize/deserialize correctly, validation works

**Story**: Foundational (required by US1, US3, US9)

---

### T005: Write unit tests for core models [P] - ✅ COMPLETED

**File**: `tests/i3_project_manager/test_core/test_models.py`

**Description**: Test all dataclass validation, serialization, and file operations.

**Tasks**:
- Test `Project` validation (invalid name, missing directory, etc.)
- Test `Project.to_json()` / `from_json()` round-trip
- Test `Project.save()` creates file at correct path
- Test `Project.load()` reads file correctly
- Test `Project.list_all()` returns all projects
- Test `AutoLaunchApp.get_full_env()` merges environment variables
- Test `SavedLayout` save/load/list operations
- Test `AppClassification.is_scoped()` logic

**Acceptance**: 100% test coverage for models.py, all tests pass

**Story**: Foundational

---

### T006: Implement daemon client - ✅ COMPLETED

**File**: `home-modules/tools/i3_project_manager/core/daemon_client.py`

**Description**: Migrate and enhance DaemonClient from i3-project-monitor for JSON-RPC communication.

**Tasks**:
- Copy `DaemonClient` class from i3_project_monitor
- Add methods:
  - `async def connect()` - Connect to Unix socket
  - `async def call(method, params)` - Send JSON-RPC request
  - `async def get_status()` - Get daemon status
  - `async def get_events(limit, event_type)` - Get recent events
  - `async def get_windows()` - Get tracked windows
  - `async def close()` - Close connection
- Add connection pooling for CLI commands (reuse connection)
- Add timeout handling (5s default)
- Add retry logic for transient failures

**Acceptance**: Can connect to daemon and query status

**Story**: Foundational (required by US1, US2, US7, US9)

---

### T007: Implement i3 IPC client - ✅ COMPLETED

**File**: `home-modules/tools/i3_project_manager/core/i3_client.py`

**Description**: Create async wrapper for i3ipc queries following Principle XI.

**Tasks**:
- Create `I3Client` class wrapping i3ipc.aio.Connection
- Add methods:
  - `async def get_tree()` - GET_TREE for window hierarchy
  - `async def get_workspaces()` - GET_WORKSPACES for monitor assignments
  - `async def get_outputs()` - GET_OUTPUTS for monitor config
  - `async def get_marks()` - GET_MARKS for all window marks
  - `async def command(cmd)` - RUN_COMMAND for i3 operations
- Add helper methods:
  - `async def get_windows_by_mark(mark)` - Filter tree by mark
  - `async def get_workspace_to_output_map()` - WS→monitor mapping
  - `async def assign_logical_outputs()` - Map primary/secondary/tertiary

**Acceptance**: All i3 IPC queries work correctly, returns typed data

**Story**: Foundational (required by US1, US4, US5, US9)

---

### T008: Write unit tests for daemon and i3 clients [P] - ✅ COMPLETED

**File**: `tests/i3_project_manager/test_core/test_clients.py`

**Description**: Test daemon and i3 clients with mocked connections.

**Tasks**:
- Test `DaemonClient.connect()` with mock socket
- Test `DaemonClient.call()` JSON-RPC protocol
- Test `DaemonClient.get_status()` response parsing
- Test `I3Client.get_tree()` with mock i3ipc response
- Test `I3Client.get_windows_by_mark()` filtering logic
- Test `I3Client.assign_logical_outputs()` monitor role assignment
- Test connection error handling and retries

**Acceptance**: All client tests pass with mocked connections

**Story**: Foundational

---

### T009: Implement configuration validation - ✅ COMPLETED

**File**: `home-modules/tools/i3_project_manager/validators/project_validator.py`

**Description**: Create JSON schema validator for project configurations.

**Tasks**:
- Load JSON schema from `contracts/config-schema.json`
- Create `ProjectValidator` class:
  - `validate_project(project_dict)` - Validate against schema
  - `validate_file(config_file)` - Validate file on disk
  - Return list of validation errors with paths (e.g., "auto_launch[0].command: required")
- Add filesystem validation:
  - Check directory exists
  - Check name uniqueness
  - Check workspace numbers (1-10)
- Target validation time <500ms (SC-017)

**Acceptance**: Invalid configs rejected with clear error messages

**Story**: Foundational (required by US3, US9)

---

### T010: Write tests for configuration validation [P] - ✅ COMPLETED

**File**: `tests/i3_project_manager/test_validators/test_project_validator.py`

**Description**: Test all validation rules from data-model.md.

**Tasks**:
- Test valid project passes validation
- Test invalid project name (non-alphanumeric)
- Test missing required fields
- Test non-existent directory
- Test duplicate project name
- Test invalid workspace numbers (0, 11, etc.)
- Test invalid output roles (not primary/secondary/tertiary)
- Test invalid auto_launch command (empty string)
- Verify validation completes <500ms

**Acceptance**: All validation edge cases covered, tests pass

**Story**: Foundational

---

## Phase 3: User Story 1 - Project Context Switching (P1)

**Goal**: Enable users to switch between projects with automatic window show/hide in <200ms.

**Independent Test**: Create 2 projects, open 2 windows in each, switch between them, verify windows hide/show correctly within 200ms.

---

### T011: Implement project switching logic [US1]

**File**: `home-modules/tools/i3_project_manager/core/project.py`

**Description**: Core project switching algorithm that interacts with daemon and i3.

**Tasks**:
- Create `ProjectManager` class:
  - `async def switch_to_project(name)` - Switch active project
  - `async def clear_project()` - Enter global mode
  - `async def get_current_project()` - Query daemon for active project
- Switching algorithm:
  1. Send tick event to daemon: `i3.command('nop project:{name}')`
  2. Wait for daemon to process (query status until active_project changes)
  3. Verify windows marked correctly (query i3 for marks)
  4. Return success/failure + timing metrics
- Add timeout protection (max 500ms for switch)
- Target <200ms for 50 windows (SC-001)

**Acceptance**: Can switch projects programmatically in <200ms

**Story**: US1 (Project Context Switching)

---

### T012: Write unit tests for project switching [US1] [P]

**File**: `tests/i3_project_manager/test_core/test_project.py`

**Description**: Test project switching with mocked daemon and i3.

**Tasks**:
- Test successful project switch
- Test switch with no windows
- Test switch with 50 windows (measure timing)
- Test switch timeout handling
- Test clear project (return to global)
- Test switch to non-existent project (error handling)
- Verify <200ms timing for 50 windows

**Acceptance**: All switching scenarios tested, timing requirement met

**Story**: US1

---

### T013: Implement CLI switch command [US1]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm switch` CLI command.

**Tasks**:
- Create argparse subcommand parser for `switch`
- Add arguments:
  - `project_name` (positional, with argcomplete for project names)
  - `--no-launch` (skip auto-launch)
  - `--json` (JSON output format)
- Implement command handler:
  - Load project from disk
  - Call `ProjectManager.switch_to_project()`
  - Output rich-formatted success message or error
- Add timing measurement and display
- Integrate with daemon client

**Acceptance**: `i3pm switch nixos` switches to project and shows confirmation

**Story**: US1

---

### T014: Implement CLI current command [US1] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm current` CLI command to show active project.

**Tasks**:
- Create argparse subcommand parser for `current`
- Add options:
  - `--quiet` (output only project name)
  - `--json` (JSON output)
- Implement command handler:
  - Query daemon for active project
  - Query daemon for window count
  - Output formatted status
- Handle no active project case

**Acceptance**: `i3pm current` shows active project, `i3pm current --quiet` outputs just name

**Story**: US1

---

### T015: Implement CLI clear command [US1] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm clear` command to exit project mode.

**Tasks**:
- Create argparse subcommand parser for `clear`
- Implement command handler:
  - Call `ProjectManager.clear_project()`
  - Send tick event: `nop project:clear`
  - Verify daemon cleared active project
  - Output confirmation

**Acceptance**: `i3pm clear` clears active project and shows all windows

**Story**: US1

---

### T016: Write integration tests for switching workflow [US1]

**File**: `tests/i3_project_manager/test_cli/test_commands.py`

**Description**: End-to-end test of CLI switching commands.

**Tasks**:
- Test `i3pm switch nixos` with mocked daemon
- Test `i3pm current` returns correct project
- Test `i3pm clear` clears project
- Test switching between multiple projects
- Test switch with `--json` output format
- Test error cases (project not found, daemon down)
- Measure timing for full workflow

**Acceptance**: All CLI commands work end-to-end, timing <200ms

**Story**: US1

---

**Checkpoint**: After T016, users can switch projects via CLI with <200ms response time. This completes User Story 1 (P1).

---

## Phase 4: User Story 2 - Automated Window Association (P1)

**Goal**: Automatically mark new windows with project context within 100ms.

**Independent Test**: Activate project "nixos", launch VS Code, verify window gets mark "project:nixos" within 100ms.

**Note**: Most of this functionality already exists in the daemon (Feature 015). These tasks validate and integrate with existing daemon behavior.

---

### T017: Validate daemon window marking [US2]

**File**: `tests/i3_project_manager/test_integration/test_daemon_integration.py`

**Description**: Integration test verifying daemon marks windows automatically.

**Tasks**:
- Create test that:
  1. Starts daemon (or connects to running daemon)
  2. Switches to project "test"
  3. Launches window with scoped class (mock or real)
  4. Queries i3 for window marks
  5. Verifies mark "project:test" exists within 100ms
- Test with multiple window classes
- Test with global class (verify NO mark applied)
- Test mark removal when project clears

**Acceptance**: Daemon marks windows within 100ms (SC-002: 99% reliability)

**Story**: US2 (Automated Window Association)

---

### T018: Implement app classification management [US2]

**File**: `home-modules/tools/i3_project_manager/core/config.py`

**Description**: Utilities for managing global app classification config.

**Tasks**:
- Create `AppClassConfig` class:
  - `load()` - Load from `~/.config/i3/app-classes.json`
  - `save()` - Save to disk
  - `add_scoped_class(class_name)` - Add to scoped list
  - `add_global_class(class_name)` - Add to global list
  - `remove_class(class_name)` - Remove from both lists
  - `is_scoped(class_name, project)` - Check if class is scoped
- Handle missing config file (create with defaults)

**Acceptance**: Can load/modify app classifications programmatically

**Story**: US2

---

### T019: Implement CLI app-classes commands [US2] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm app-classes` subcommand for managing classifications.

**Tasks**:
- Create argparse subcommand parser for `app-classes`
- Add subcommands:
  - `list` - Show all classifications
  - `add-scoped CLASS` - Add scoped class
  - `add-global CLASS` - Add global class
  - `remove CLASS` - Remove class
  - `check CLASS` - Check if class is scoped or global
- Implement handlers using `AppClassConfig`
- Output rich-formatted tables

**Acceptance**: `i3pm app-classes list` shows current classifications

**Story**: US2

---

### T020: Write tests for app classification [US2] [P]

**File**: `tests/i3_project_manager/test_core/test_config.py`

**Description**: Test app classification logic.

**Tasks**:
- Test `AppClassConfig.load()` with missing file (creates defaults)
- Test `add_scoped_class()` adds to list
- Test `is_scoped()` with scoped class returns True
- Test `is_scoped()` with global class returns False
- Test pattern matching (e.g., "pwa-*" matches "pwa-youtube")
- Test project-specific overrides

**Acceptance**: All classification tests pass

**Story**: US2

---

**Checkpoint**: After T020, windows automatically associate with projects. This completes User Story 2 (P1).

---

## Phase 5: User Story 3 - Project Creation and Configuration (P1)

**Goal**: Allow users to create projects with validation and clear feedback.

**Independent Test**: Run `i3pm create --name=test --dir=/tmp/test`, verify config file created, project appears in list.

---

### T021: Implement project CRUD operations [US3]

**File**: `home-modules/tools/i3_project_manager/core/project.py`

**Description**: Complete project creation, update, and deletion logic.

**Tasks**:
- Extend `ProjectManager` class:
  - `async def create_project(name, directory, **kwargs)` - Create new project
  - `async def update_project(name, **updates)` - Update existing project
  - `async def delete_project(name, force=False)` - Delete project and layouts
  - `async def list_projects(sort_by='modified')` - List all projects
  - `async def get_project(name)` - Get single project
- Validation:
  - Check duplicate names before create
  - Validate directory exists
  - Validate all fields via ProjectValidator
- Notify daemon of config changes (reload via IPC if supported)

**Acceptance**: Can create/update/delete projects programmatically

**Story**: US3 (Project Creation and Configuration)

---

### T022: Implement CLI create command [US3]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm create` CLI command with validation.

**Tasks**:
- Create argparse subcommand parser for `create`
- Add arguments:
  - `--name NAME` (required)
  - `--directory DIR` (required)
  - `--display-name NAME` (optional)
  - `--icon EMOJI` (optional)
  - `--scoped-classes CLASS...` (optional, space-separated)
  - `--interactive` (launch TUI wizard - deferred to Phase 8)
  - `--json` (JSON output)
- Implement command handler:
  - Validate inputs using ProjectValidator
  - Call `ProjectManager.create_project()`
  - Output success message with config file path
- Handle errors (duplicate name, missing directory)

**Acceptance**: `i3pm create --name=test --directory=/tmp` creates project

**Story**: US3

---

### T023: Implement CLI edit command [US3] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm edit` CLI command for modifying projects.

**Tasks**:
- Create argparse subcommand parser for `edit`
- Add arguments:
  - `project_name` (positional)
  - `--directory DIR` (update directory)
  - `--display-name NAME` (update display name)
  - `--icon EMOJI` (update icon)
  - `--add-class CLASS` (add scoped class)
  - `--remove-class CLASS` (remove scoped class)
  - `--set-classes CLASS...` (replace all scoped classes)
  - `--interactive` (launch TUI editor - deferred to Phase 8)
  - `--json` (JSON output)
- Implement command handler using `ProjectManager.update_project()`

**Acceptance**: `i3pm edit nixos --add-class firefox` updates project

**Story**: US3

---

### T024: Implement CLI delete command [US3] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm delete` CLI command with confirmation.

**Tasks**:
- Create argparse subcommand parser for `delete`
- Add arguments:
  - `project_name` (positional)
  - `--force` (skip confirmation)
  - `--json` (JSON output)
- Implement command handler:
  - Prompt for confirmation (unless --force)
  - Call `ProjectManager.delete_project()`
  - Delete all associated layouts
  - Output confirmation

**Acceptance**: `i3pm delete test` prompts and deletes project

**Story**: US3

---

### T025: Implement CLI list command [US3] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm list` CLI command with sorting.

**Tasks**:
- Create argparse subcommand parser for `list`
- Add options:
  - `--sort FIELD` (name, modified, directory)
  - `--reverse` (reverse sort order)
  - `--json` (JSON output)
- Implement command handler:
  - Call `ProjectManager.list_projects()`
  - Format as rich table with columns: Name, Icon, Directory, Apps, Layouts, Modified
  - Handle empty project list

**Acceptance**: `i3pm list` shows formatted table of projects

**Story**: US3

---

### T026: Implement CLI show command [US3] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm show` CLI command for project details.

**Tasks**:
- Create argparse subcommand parser for `show`
- Add arguments:
  - `project_name` (positional)
  - `--json` (JSON output)
- Implement command handler:
  - Load project from disk
  - Query daemon for window count if active
  - Format as rich panel with all project details
- Display:
  - Basic info (name, directory, icon)
  - Scoped classes (list)
  - Workspace preferences (table)
  - Auto-launch apps (table)
  - Saved layouts (list)
  - Metadata (created, modified)

**Acceptance**: `i3pm show nixos` displays full project details

**Story**: US3

---

### T027: Implement CLI validate command [US3] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm validate` CLI command for config validation.

**Tasks**:
- Create argparse subcommand parser for `validate`
- Add arguments:
  - `project_name` (optional, validates all if omitted)
  - `--json` (JSON output)
- Implement command handler:
  - Validate specified project or all projects
  - Use ProjectValidator for validation
  - Report errors with file paths and line numbers
  - Return exit code 1 if validation fails

**Acceptance**: `i3pm validate` validates all projects and reports errors

**Story**: US3

---

### T028: Write tests for project CRUD [US3]

**File**: `tests/i3_project_manager/test_core/test_project.py`

**Description**: Test all project CRUD operations.

**Tasks**:
- Test `create_project()` with valid inputs
- Test `create_project()` with duplicate name (error)
- Test `create_project()` with non-existent directory (error)
- Test `update_project()` modifying fields
- Test `delete_project()` removes file and layouts
- Test `list_projects()` returns all projects sorted
- Test `get_project()` loads project from disk
- Verify validation completes <500ms (SC-017)

**Acceptance**: All CRUD tests pass, timing requirements met

**Story**: US3

---

### T029: Write integration tests for CLI CRUD commands [US3]

**File**: `tests/i3_project_manager/test_cli/test_commands.py`

**Description**: End-to-end tests for all CRUD CLI commands.

**Tasks**:
- Test `i3pm create` creates project file
- Test `i3pm edit` modifies project
- Test `i3pm delete` removes project
- Test `i3pm list` shows all projects
- Test `i3pm show` displays project details
- Test `i3pm validate` reports errors
- Test error handling (project not found, invalid inputs)
- Test JSON output format for all commands

**Acceptance**: All CLI CRUD commands work end-to-end

**Story**: US3

---

**Checkpoint**: After T029, users can create/edit/delete projects with full validation. This completes User Story 3 (P1).

---

## Phase 6: User Story 9 - Unified Project Management Interface (P1)

**Goal**: Provide TUI for managing projects without JSON editing.

**Independent Test**: Run `i3pm` (no args), navigate TUI, create project via wizard, verify works without touching JSON.

**Note**: This is the most complex user story, implementing the full TUI.

---

### T030: Implement TUI application skeleton [US9]

**File**: `home-modules/tools/i3_project_manager/tui/app.py`

**Description**: Create main Textual application with mode detection.

**Tasks**:
- Create `I3PMApp(App)` class:
  - Configure CSS theme (colors from UNIFIED_UX_DESIGN.md)
  - Set up screen navigation
  - Add keybindings (Ctrl+C to quit, etc.)
- Implement mode detection in `__main__.py`:
  - No args → Launch TUI (`I3PMApp().run()`)
  - Args present → Parse CLI commands
- Add reactive attributes:
  - `active_project: reactive[Optional[str]]`
  - `daemon_connected: reactive[bool]`
- Start daemon connection on mount
- Poll daemon status every 5 seconds

**Acceptance**: `i3pm` launches TUI, `i3pm switch nixos` runs CLI

**Story**: US9 (Unified Project Management Interface)

---

### T031: Implement project browser screen [US9]

**File**: `home-modules/tools/i3_project_manager/tui/screens/browser.py`

**Description**: Create default TUI screen for browsing projects.

**Tasks**:
- Create `ProjectBrowserScreen(Screen)`:
  - Header with app title and active project indicator
  - Search input field
  - DataTable with columns: Icon, Name, Directory, Apps, Layouts, Modified
  - Footer with keyboard shortcuts
- Add reactive attributes:
  - `filter_text: reactive[str]` (auto-filters table)
  - `sort_by: reactive[str]` (auto-sorts table)
- Implement keyboard handlers:
  - `↑/↓` - Navigate table
  - `Enter` - Switch to project
  - `e` - Edit project (push EditorScreen)
  - `l` - Layout manager (push LayoutScreen)
  - `m` - Monitor dashboard (push MonitorScreen)
  - `n` - New project wizard (push WizardScreen)
  - `d` - Delete project (show confirmation dialog)
  - `/` - Focus search input
  - `s` - Cycle sort order
  - `q` - Quit
- Load projects on mount
- Refresh every 5 seconds

**Acceptance**: Browser screen displays projects, navigation works

**Story**: US9

---

### T032: Implement project table widget [US9] [P]

**File**: `home-modules/tools/i3_project_manager/tui/widgets/project_table.py`

**Description**: Custom DataTable widget for project list with formatting.

**Tasks**:
- Create `ProjectTable(DataTable)`:
  - Add columns with correct widths
  - Format cells (icon, truncated directory, relative time for modified)
  - Highlight active project row
  - Support filtering by search text
  - Support sorting by column
- Add methods:
  - `load_projects(projects)` - Populate table
  - `filter_by_text(text)` - Filter rows
  - `sort_by_column(column)` - Sort rows
  - `get_selected_project()` - Get selected project name
- Style with CSS (alternating row colors, hover effects)

**Acceptance**: Table displays projects with proper formatting

**Story**: US9

---

### T033: Implement project editor screen [US9]

**File**: `home-modules/tools/i3_project_manager/tui/screens/editor.py`

**Description**: Create TUI screen for editing project configuration.

**Tasks**:
- Create `ProjectEditorScreen(Screen)`:
  - Input fields for: name, display_name, icon, directory
  - Checkbox list for scoped classes
  - Select dropdowns for workspace preferences (WS 1-10 → primary/secondary/tertiary)
  - DataTable for auto-launch apps (with Edit/Delete buttons)
  - Save/Cancel buttons
- Add reactive attributes:
  - `unsaved_changes: reactive[bool]` (enables save button)
- Implement validation:
  - Real-time validation on field change
  - Display errors inline (red text below field)
  - Disable save if validation fails
- Implement keyboard handlers:
  - `Tab/Shift+Tab` - Navigate fields
  - `Ctrl+S` - Save changes
  - `Esc` - Cancel (show confirmation if unsaved)
- On save:
  - Validate all fields
  - Call `ProjectManager.update_project()`
  - Dismiss screen with success message

**Acceptance**: Can edit project fields and save changes

**Story**: US9

---

### T034: Implement project wizard screen [US9]

**File**: `home-modules/tools/i3_project_manager/tui/screens/wizard.py`

**Description**: Create 4-step wizard for project creation.

**Tasks**:
- Create `ProjectWizardScreen(Screen)` with 4 steps:
  - **Step 1**: Basic info (name, display_name, icon, directory)
  - **Step 2**: Application selection (checkbox list of scoped classes)
  - **Step 3**: Auto-launch configuration (optional, can skip)
  - **Step 4**: Review and create
- Add reactive attributes:
  - `current_step: reactive[int]` (updates UI)
  - `wizard_data: dict` (accumulates inputs)
- Implement navigation:
  - `Enter` - Next step (with validation)
  - `Esc` - Previous step or cancel
- Implement validation:
  - Each step validates before advancing
  - Step 1: name must be unique, directory must exist
  - Step 2: at least one scoped class required
- On finish:
  - Validate all collected data
  - Call `ProjectManager.create_project()`
  - Dismiss screen and return to browser
- Target <2 min for full wizard (SC-015)

**Acceptance**: Wizard completes project creation in <2 min

**Story**: US9

---

### T035: Implement layout manager screen [US9] [P]

**File**: `home-modules/tools/i3_project_manager/tui/screens/layout_manager.py`

**Description**: Create TUI screen for saving/restoring layouts (deferred details to Phase 10).

**Tasks**:
- Create `LayoutManagerScreen(Screen)`:
  - DataTable showing saved layouts for project
  - Buttons: Save Current, Restore Selected, Delete, Export
- Add keyboard handlers:
  - `s` - Save current layout
  - `r` - Restore selected layout
  - `d` - Delete layout
  - `e` - Export layout
  - `Esc` - Return to browser
- Implement save layout:
  - Prompt for layout name
  - Call `LayoutManager.save_layout()` (implemented in Phase 10)
  - Refresh table
- Implement restore layout:
  - Call `LayoutManager.restore_layout()` (implemented in Phase 10)
  - Show progress indicator

**Acceptance**: Layout manager screen displays and navigates (full functionality in Phase 10)

**Story**: US9 (partial - full layout features in US5)

---

### T036: Implement monitor dashboard screen [US9]

**File**: `home-modules/tools/i3_project_manager/tui/screens/monitor.py`

**Description**: Migrate i3-project-monitor displays into unified TUI screen.

**Tasks**:
- Create `MonitorScreen(Screen)` with tabbed interface:
  - Tab 1: **Live** - Current daemon status (from live_display.py)
  - Tab 2: **Events** - Event stream (from event_stream.py)
  - Tab 3: **History** - Event history table (from history_view.py)
  - Tab 4: **Tree** - i3 window tree inspector (from tree_inspector.py)
- Migrate logic from i3_project_monitor/displays/:
  - `live_display.py` → Live tab (DataTable with status)
  - `event_stream.py` → Events tab (RichLog with scrolling)
  - `history_view.py` → History tab (DataTable with filters)
  - `tree_inspector.py` → Tree tab (RichLog with JSON)
- Add keyboard handlers:
  - `Tab` - Switch between tabs
  - `r` - Force refresh
  - `Esc` - Return to browser
- Update live tab every 1 second
- Stream events to events tab in real-time

**Acceptance**: Monitor screen shows live daemon state and events

**Story**: US9 (also serves US7)

---

### T037: Implement CLI formatters for rich output [US9] [P]

**File**: `home-modules/tools/i3_project_manager/cli/formatters.py`

**Description**: Create Rich formatters for CLI output to meet SC-019 (95% terminals).

**Tasks**:
- Create formatter functions:
  - `format_project_list(projects)` → Rich table
  - `format_project_details(project)` → Rich panel
  - `format_status(status)` → Rich table
  - `format_success(message)` → Green checkmark + message
  - `format_error(message)` → Red X + message
  - `format_warning(message)` → Yellow warning + message
- Use Rich's terminal detection for color support
- Fallback to plain text if colors unsupported
- Add JSON formatter for `--json` flag:
  - `format_json(data)` → Pretty-printed JSON

**Acceptance**: CLI output renders correctly in 95% of terminals

**Story**: US9

---

### T038: Implement shell completions [US9] [P]

**File**: `home-modules/tools/i3_project_manager/cli/completions.py`

**Description**: Create argcomplete completers for dynamic project/layout names.

**Tasks**:
- Create completer functions:
  - `complete_project_names(prefix, parsed_args)` → List[str]
  - `complete_layout_names(prefix, parsed_args)` → List[str]
- Implement caching for performance:
  - Cache project names in `~/.cache/i3pm/project-list.txt`
  - Refresh cache if >60s old
  - Target <50ms completion time
- Integrate completers into argparse:
  - Attach to `project_name` arguments
  - Attach to `layout_name` arguments
- Create `i3pm completions` command:
  - `i3pm completions bash` → Generate bash completions
  - `i3pm completions zsh` → Generate zsh completions

**Acceptance**: Tab completion works for project/layout names in <50ms

**Story**: US9

---

### T039: Write TUI snapshot tests [US9]

**File**: `tests/i3_project_manager/test_tui/test_browser.py`, etc.

**Description**: Create pytest-textual snapshot tests for all TUI screens.

**Tasks**:
- Test `ProjectBrowserScreen`:
  - Initial render (empty project list)
  - Render with 3 projects
  - Render with search filter active
  - Render with active project highlighted
- Test `ProjectEditorScreen`:
  - Initial render with project loaded
  - Render with validation errors
  - Render with unsaved changes indicator
- Test `ProjectWizardScreen`:
  - Each of 4 steps rendered
  - Navigation between steps
- Test `LayoutManagerScreen`:
  - Render with 0 layouts
  - Render with 3 layouts
- Test `MonitorScreen`:
  - Each of 4 tabs rendered
- Use Textual snapshot testing (`snap_compare`)

**Acceptance**: All TUI screens have snapshot tests for visual regression

**Story**: US9

---

### T040: Write TUI integration tests [US9]

**File**: `tests/i3_project_manager/test_tui/test_workflows.py`

**Description**: End-to-end workflow tests using Textual pilot.

**Tasks**:
- Test project creation workflow:
  - Launch TUI → Press `n` → Complete wizard → Verify project created
- Test project editing workflow:
  - Select project → Press `e` → Modify fields → Save → Verify changes
- Test project switching workflow:
  - Select project → Press `Enter` → Verify daemon switched
- Test navigation workflow:
  - Navigate between all screens → Verify back navigation works
- Verify keyboard response time <50ms (SC-016)

**Acceptance**: All TUI workflows work end-to-end, timing requirements met

**Story**: US9

---

**Checkpoint**: After T040, users have a fully functional TUI for project management. This completes User Story 9 (P1) and MVP scope.

---

## Phase 7: User Story 7 - Real-Time Validation and Monitoring (P2)

**Goal**: Provide diagnostic tools for troubleshooting.

**Independent Test**: Run `i3pm monitor --mode=events`, create window, verify event appears within 100ms.

**Note**: Most monitoring was implemented in T036. These tasks add CLI commands.

---

### T041: Implement CLI status command [US7]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm status` command for daemon diagnostics.

**Tasks**:
- Create argparse subcommand parser for `status`
- Add option: `--json` (JSON output)
- Implement command handler:
  - Query daemon via `DaemonClient.get_status()`
  - Format as rich panel with:
    - Daemon status (running/stopped)
    - Uptime
    - Active project
    - Window counts (total, tracked)
    - Event count and rate
    - Error count
  - Handle daemon not running case

**Acceptance**: `i3pm status` shows daemon health

**Story**: US7 (Real-Time Validation and Monitoring)

---

### T042: Implement CLI events command [US7] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm events` command for viewing daemon events.

**Tasks**:
- Create argparse subcommand parser for `events`
- Add options:
  - `--limit N` (number of events, default 20)
  - `--type TYPE` (filter: window, workspace, tick, output)
  - `--follow, -f` (stream events continuously)
  - `--json` (JSON output)
- Implement command handler:
  - Query daemon via `DaemonClient.get_events()`
  - Format as rich table with: Timestamp, Type, Details
  - If `--follow`, poll every 100ms for new events

**Acceptance**: `i3pm events` shows recent events, `i3pm events -f` streams

**Story**: US7

---

### T043: Implement CLI windows command [US7] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm windows` command for listing tracked windows.

**Tasks**:
- Create argparse subcommand parser for `windows`
- Add options:
  - `--project NAME` (filter by project)
  - `--all` (show all windows, not just tracked)
  - `--json` (JSON output)
- Implement command handler:
  - Query daemon via `DaemonClient.get_windows()`
  - Or query i3 via `I3Client.get_tree()` for `--all`
  - Format as rich table with: ID, Class, Title, Workspace, Marks
  - Highlight project-marked windows

**Acceptance**: `i3pm windows` shows tracked windows with marks

**Story**: US7

---

### T044: Implement CLI monitor command [US7] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm monitor` command to launch TUI monitor.

**Tasks**:
- Create argparse subcommand parser for `monitor`
- Add argument: `mode` (optional: live, events, history, tree)
- Implement command handler:
  - Launch TUI with MonitorScreen
  - If mode specified, navigate to that tab
  - Exit TUI on Esc

**Acceptance**: `i3pm monitor` launches monitor dashboard TUI

**Story**: US7

---

### T045: Write tests for monitoring commands [US7]

**File**: `tests/i3_project_manager/test_cli/test_monitoring.py`

**Description**: Test all monitoring CLI commands.

**Tasks**:
- Test `i3pm status` with running daemon
- Test `i3pm status` with stopped daemon (error handling)
- Test `i3pm events` returns events
- Test `i3pm events --type=window` filters correctly
- Test `i3pm windows` shows tracked windows
- Test `i3pm windows --all` shows all windows
- Test JSON output for all commands
- Verify event display latency <100ms (SC-001)

**Acceptance**: All monitoring commands work correctly

**Story**: US7

---

**Checkpoint**: After T045, users have comprehensive diagnostic tools. This completes User Story 7 (P2).

---

## Phase 8: User Story 4 - Multi-Monitor Workspace Assignment (P2)

**Goal**: Automatically distribute workspaces across monitors.

**Independent Test**: Connect 2 monitors, verify WS 1-2 on primary, WS 3-9 on secondary.

**Note**: This feature primarily relies on existing daemon behavior. These tasks add CLI visibility.

---

### T046: Implement monitor query utilities [US4]

**File**: `home-modules/tools/i3_project_manager/core/i3_client.py`

**Description**: Add helper methods for monitor/workspace queries.

**Tasks**:
- Add to `I3Client`:
  - `async def get_monitor_config()` - Returns list of outputs with names, active status, position
  - `async def get_workspace_assignments()` - Returns dict {ws_num: output_name}
  - `async def assign_workspace_to_output(ws_num, output_name)` - Move workspace
- Implement logical output assignment:
  - `assign_logical_outputs(outputs)` - Map outputs to primary/secondary/tertiary based on position
- Handle monitor changes:
  - Detect when outputs change (count or names)
  - Trigger workspace reassignment

**Acceptance**: Can query monitor config and workspace assignments

**Story**: US4 (Multi-Monitor Workspace Assignment)

---

### T047: Implement CLI config command [US4] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm config` command to show configuration paths and monitor status.

**Tasks**:
- Create argparse subcommand parser for `config`
- Add options:
  - `--monitors` (show monitor configuration)
  - `--workspaces` (show workspace assignments)
  - `--paths` (show config file paths)
  - `--json` (JSON output)
- Implement command handler:
  - Query i3 for monitor/workspace info
  - Show config file locations:
    - Projects dir: `~/.config/i3/projects/`
    - Layouts dir: `~/.config/i3/layouts/`
    - App classes: `~/.config/i3/app-classes.json`
    - Daemon socket: `~/.cache/i3-project/daemon.sock`
  - Format as rich table

**Acceptance**: `i3pm config --monitors` shows monitor configuration

**Story**: US4

---

### T048: Write tests for monitor queries [US4]

**File**: `tests/i3_project_manager/test_core/test_i3_client.py`

**Description**: Test monitor and workspace query functions.

**Tasks**:
- Test `get_monitor_config()` with 1, 2, 3 monitors
- Test `get_workspace_assignments()` returns correct mapping
- Test `assign_logical_outputs()` with various monitor configs:
  - 1 monitor: all workspaces on primary
  - 2 monitors: WS 1-2 primary, WS 3-9 secondary
  - 3 monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary
- Test monitor disconnection handling
- Verify workspace reassignment completes <2s (SC-005)

**Acceptance**: All monitor query tests pass, timing requirements met

**Story**: US4

---

**Checkpoint**: After T048, multi-monitor workspace assignment works correctly. This completes User Story 4 (P2).

---

## Phase 9: User Story 8 - Application Launcher Integration (P2)

**Goal**: Launch applications with project context via environment variables.

**Independent Test**: Activate project "nixos", launch VS Code via rofi, verify `PROJECT_CONTEXT=nixos` env var set.

---

### T049: Implement project-scoped launcher wrapper [US8]

**File**: `scripts/i3-project-launch`

**Description**: Create wrapper script for launching apps with project context.

**Tasks**:
- Create bash script `i3-project-launch`:
  - Query active project via `i3pm current --quiet`
  - If project active:
    - Get project directory via `i3pm show $PROJECT --json | jq -r .directory`
    - Set environment variables:
      - `I3_PROJECT=$project_name`
      - `PROJECT_DIR=$project_directory`
      - `PROJECT_NAME=$project_name`
  - Execute command with modified environment
- Add to NixOS module as executable

**Acceptance**: Launching app via `i3-project-launch code` sets env vars

**Story**: US8 (Application Launcher Integration)

---

### T050: Document rofi integration [US8] [P]

**File**: `specs/019-re-explore-and/quickstart.md` (update)

**Description**: Add rofi integration examples to quickstart guide.

**Tasks**:
- Add section "Application Launcher Integration"
- Document keybinding setup:
  ```bash
  # ~/.config/i3/config
  bindsym $mod+Return exec --no-startup-id i3-project-launch ghostty
  bindsym $mod+c exec --no-startup-id i3-project-launch code
  ```
- Document rofi launcher modification:
  ```bash
  # Use i3-project-launch as wrapper
  rofi -show run -run-command 'i3-project-launch {cmd}'
  ```
- Document environment variable usage in shell:
  ```bash
  # ~/.bashrc
  if [ -n "$I3_PROJECT" ]; then
    cd "$PROJECT_DIR"
  fi
  ```

**Acceptance**: Quickstart guide has rofi integration section

**Story**: US8

---

### T051: Write tests for launcher wrapper [US8]

**File**: `tests/i3_project_manager/test_integration/test_launcher.py`

**Description**: Test launcher wrapper sets environment correctly.

**Tasks**:
- Test `i3-project-launch` with active project:
  - Verify `I3_PROJECT` env var set
  - Verify `PROJECT_DIR` env var set
  - Verify command executes with env
- Test `i3-project-launch` with no active project:
  - Verify env vars NOT set
  - Verify command executes normally
- Test with multiple project switches
- Test command with arguments (e.g., `code /path/to/file`)

**Acceptance**: Launcher wrapper tests pass

**Story**: US8

---

**Checkpoint**: After T051, applications launch with project context. This completes User Story 8 (P2).

---

## Phase 10: User Story 5 - Project Restoration and Automated Launching (P2)

**Goal**: Auto-launch configured applications when activating project.

**Independent Test**: Configure project "nixos" with auto-launch (VS Code on WS1, 2 terminals on WS2), activate project, verify apps launch automatically.

---

### T052: Implement layout save logic [US5]

**File**: `home-modules/tools/i3_project_manager/core/layout.py`

**Description**: Create layout capture using i3 IPC queries (custom format, not i3 native).

**Tasks**:
- Create `LayoutManager` class:
  - `async def save_layout(project_name, layout_name)` - Capture current layout
- Capture algorithm:
  1. Query i3 for tree: `i3.get_tree()`
  2. Filter windows by project mark: `project:{project_name}`
  3. For each workspace with project windows:
     - Capture workspace number
     - Determine output role (primary/secondary/tertiary)
     - For each window:
       - Capture class, title, geometry
       - Infer launch command from class (best effort)
       - Store expected marks
  4. Create `SavedLayout` object
  5. Save to `~/.config/i3/layouts/{project_name}/{layout_name}.json`
- Target <5s for 10 windows (SC-018)

**Acceptance**: Can save current window layout to JSON file

**Story**: US5 (Project Restoration and Automated Launching)

---

### T053: Implement layout restore logic [US5]

**File**: `home-modules/tools/i3_project_manager/core/layout.py`

**Description**: Restore layout by sequentially launching applications.

**Tasks**:
- Add to `LayoutManager`:
  - `async def restore_layout(project_name, layout_name)` - Restore saved layout
- Restore algorithm:
  1. Load `SavedLayout` from disk
  2. Switch to project (to enable auto-marking)
  3. Query i3 for current outputs
  4. Map logical outputs (primary/secondary/tertiary)
  5. For each workspace in layout:
     - Focus workspace on target output
     - For each window:
       - Set environment variables (PROJECT_DIR, PROJECT_NAME, + window env)
       - Launch command via `subprocess.Popen()`
       - Wait for window with project mark (max 5s timeout)
       - If timeout, log warning and continue
  6. Return to first workspace
- Handle launch failures gracefully (SC-037)
- Target <5s total for 10 windows (SC-018)

**Acceptance**: Can restore layout by launching apps sequentially

**Story**: US5

---

### T054: Implement auto-launch on project switch [US5]

**File**: `home-modules/tools/i3_project_manager/core/project.py`

**Description**: Automatically launch configured apps when switching to project.

**Tasks**:
- Extend `ProjectManager.switch_to_project()`:
  - After switching, check if project has `auto_launch` configured
  - Check if windows for project already exist (query i3 for marks)
  - If no existing windows, launch apps:
    - For each `AutoLaunchApp` in `project.auto_launch`:
      - Set environment via `AutoLaunchApp.get_full_env(project)`
      - If workspace specified, focus workspace first
      - Launch command via `subprocess.Popen()`
      - Wait for window with mark (timeout from `wait_timeout`)
      - Apply `launch_delay` before next app
  - Log any launch failures
  - Continue with remaining apps even if one fails (SC-037)
- Prevent duplicate launches (SC-034)
- Target <5s for 5 apps (SC-006)

**Acceptance**: Switching to project auto-launches configured apps

**Story**: US5

---

### T055: Implement CLI save-layout command [US5] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm save-layout` command.

**Tasks**:
- Create argparse subcommand parser for `save-layout`
- Add arguments:
  - `project_name` (positional)
  - `layout_name` (positional)
  - `--overwrite` (overwrite existing layout)
  - `--json` (JSON output)
- Implement command handler:
  - Verify project exists
  - Call `LayoutManager.save_layout()`
  - Output success with window count and workspace count
  - Handle errors (project not active, no windows, etc.)

**Acceptance**: `i3pm save-layout nixos default` saves current layout

**Story**: US5

---

### T056: Implement CLI restore-layout command [US5] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm restore-layout` command.

**Tasks**:
- Create argparse subcommand parser for `restore-layout`
- Add arguments:
  - `project_name` (positional)
  - `layout_name` (positional)
  - `--close-existing` (close existing project windows before restore)
  - `--json` (JSON output)
- Implement command handler:
  - Load layout from disk
  - If `--close-existing`, close project windows first
  - Call `LayoutManager.restore_layout()`
  - Show progress for each window launched
  - Output summary (X/Y windows launched, failures if any)

**Acceptance**: `i3pm restore-layout nixos default` restores layout

**Story**: US5

---

### T057: Implement CLI list-layouts command [US5] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm list-layouts` command.

**Tasks**:
- Create argparse subcommand parser for `list-layouts`
- Add arguments:
  - `project_name` (positional)
  - `--json` (JSON output)
- Implement command handler:
  - List all layouts for project via `SavedLayout.list_for_project()`
  - For each layout, load and show:
    - Layout name
    - Saved date
    - Workspace count
    - Window count
    - Monitor config (single/dual/triple)
  - Format as rich table

**Acceptance**: `i3pm list-layouts nixos` shows saved layouts

**Story**: US5

---

### T058: Implement CLI delete-layout command [US5] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm delete-layout` command.

**Tasks**:
- Create argparse subcommand parser for `delete-layout`
- Add arguments:
  - `project_name` (positional)
  - `layout_name` (positional)
  - `--force` (skip confirmation)
  - `--json` (JSON output)
- Implement command handler:
  - Verify layout exists
  - Prompt for confirmation (unless --force)
  - Delete layout file
  - Output confirmation

**Acceptance**: `i3pm delete-layout nixos default` deletes layout

**Story**: US5

---

### T059: Implement CLI export/import-layout commands [US5] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm export-layout` and `i3pm import-layout` for portability.

**Tasks**:
- Create subcommand parser for `export-layout`:
  - Arguments: `project_name`, `layout_name`, `--output FILE`
  - Copy layout JSON to specified file (or stdout if no file)
- Create subcommand parser for `import-layout`:
  - Arguments: `project_name`, `layout_name`, `FILE`
  - Copy layout JSON to `~/.config/i3/layouts/{project}/`
  - Validate JSON schema before import
  - Add `--overwrite` option

**Acceptance**: Can export/import layouts for portability

**Story**: US5

---

### T060: Write tests for layout save/restore [US5]

**File**: `tests/i3_project_manager/test_core/test_layout.py`

**Description**: Test layout capture and restoration logic.

**Tasks**:
- Test `save_layout()` captures current windows:
  - Mock i3 tree with 5 windows across 2 workspaces
  - Verify SavedLayout created with correct structure
  - Verify file saved to correct path
- Test `restore_layout()` launches apps:
  - Mock layout with 3 apps
  - Verify apps launched with correct env vars
  - Verify apps launched on correct workspaces
  - Test timeout handling (app doesn't start)
  - Test partial failure (1 app fails, others succeed)
- Test auto-launch on project switch:
  - Verify apps launch only on first switch
  - Verify no duplicate launches
- Measure timing for 10 windows <5s (SC-018)

**Acceptance**: All layout tests pass, timing requirements met

**Story**: US5

---

### T061: Write integration tests for layout commands [US5]

**File**: `tests/i3_project_manager/test_cli/test_layout_commands.py`

**Description**: End-to-end tests for all layout CLI commands.

**Tasks**:
- Test `i3pm save-layout` saves layout file
- Test `i3pm restore-layout` launches apps
- Test `i3pm list-layouts` shows layouts
- Test `i3pm delete-layout` removes layout
- Test `i3pm export-layout` exports JSON
- Test `i3pm import-layout` imports JSON
- Test error cases (layout not found, invalid JSON)
- Test JSON output format

**Acceptance**: All layout CLI commands work end-to-end

**Story**: US5

---

**Checkpoint**: After T061, users can save/restore layouts and auto-launch apps. This completes User Story 5 (P2).

---

## Phase 11: User Story 6 - Project Closing and Cleanup (P3)

**Goal**: Close all project windows with one command.

**Independent Test**: Activate project "stacks" with 5 windows, run `i3pm close stacks`, verify all windows close.

---

### T062: Implement project close logic [US6]

**File**: `home-modules/tools/i3_project_manager/core/project.py`

**Description**: Close all windows for a project gracefully.

**Tasks**:
- Add to `ProjectManager`:
  - `async def close_project(name, save_layout=False, layout_name='auto-save')` - Close project windows
- Close algorithm:
  1. If `save_layout`, call `LayoutManager.save_layout()` first
  2. Query i3 for windows with mark `project:{name}`
  3. For each window:
     - Send graceful close signal: `i3.command(f'[id={window_id}] kill')`
     - Wait 100ms for window to close
  4. After all close signals sent, verify windows closed
  5. If any windows remain after 5s, force kill
- Handle applications with save prompts (SC-043)
- Preserve global windows (SC-044)

**Acceptance**: Can close all project windows gracefully

**Story**: US6 (Project Closing and Cleanup)

---

### T063: Implement CLI close command [US6] [P]

**File**: `home-modules/tools/i3_project_manager/cli/commands.py`

**Description**: Create `i3pm close` command.

**Tasks**:
- Create argparse subcommand parser for `close`
- Add arguments:
  - `project_name` (positional, or `--all` for all projects)
  - `--save-layout` (save layout before closing)
  - `--force` (force close without save prompts)
  - `--json` (JSON output)
- Implement command handler:
  - If `project_name` specified, close that project
  - If `--all`, iterate all projects and close
  - Show progress for each window closed
  - Output summary (X windows closed, Y failed)

**Acceptance**: `i3pm close stacks` closes all stacks windows

**Story**: US6

---

### T064: Write tests for project closing [US6]

**File**: `tests/i3_project_manager/test_core/test_project.py`

**Description**: Test project close logic.

**Tasks**:
- Test `close_project()` with 5 windows:
  - Verify all windows receive close signal
  - Verify windows disappear from i3 tree
- Test with `save_layout=True`:
  - Verify layout saved before closing
- Test with stuck window (doesn't close):
  - Verify force kill after timeout
- Test `--all` closes all projects
- Verify global windows NOT closed (SC-044)

**Acceptance**: All close tests pass

**Story**: US6

---

**Checkpoint**: After T064, users can close project windows in one command. This completes User Story 6 (P3).

---

## Phase 12: Polish & Integration

### T065: Update CLAUDE.md with i3pm commands [P]

**File**: `/etc/nixos/CLAUDE.md`

**Description**: Update project documentation with i3pm usage.

**Tasks**:
- Replace old i3-project-* command references with `i3pm` equivalents
- Add "i3pm Quick Reference" section with common commands
- Update keybinding examples to use i3pm
- Add troubleshooting section for i3pm

**Acceptance**: CLAUDE.md accurately documents i3pm

**Story**: Polish

---

### T066: Create migration script for existing projects [P]

**File**: `scripts/migrate-projects-to-v2`

**Description**: Migrate existing project configs to new format (if needed).

**Tasks**:
- Create bash script that:
  - Backs up existing `~/.config/i3/projects/` to `~/.config/i3/projects.backup/`
  - For each project JSON:
    - Add new fields with defaults (auto_launch, workspace_preferences, saved_layouts)
    - Add timestamps (created_at, modified_at)
    - Validate migrated config
  - Report migration results
- Run migration automatically on first i3pm launch (if old format detected)

**Acceptance**: Existing projects migrate cleanly to new format

**Story**: Polish

---

### T067: Add comprehensive error messages [P]

**File**: All CLI command files

**Description**: Ensure all errors have clear, actionable messages (SC-013).

**Tasks**:
- Audit all error messages in CLI commands
- Improve error messages to include:
  - What went wrong
  - Why it went wrong
  - How to fix it (if applicable)
  - Available alternatives (e.g., "Project 'foo' not found. Available: bar, baz")
- Add color coding (red for errors, yellow for warnings)
- Add help hints (e.g., "Run 'i3pm list' to see all projects")

**Acceptance**: 95% of errors have clear, actionable messages

**Story**: Polish

---

### T068: Performance optimization pass

**File**: All core modules

**Description**: Optimize for performance requirements (SC-001, SC-016, SC-017, SC-018).

**Tasks**:
- Profile TUI keyboard response time (target <50ms):
  - Use Textual DevTools to measure render time
  - Optimize reactive updates
  - Add debouncing to search input
- Profile project switching time (target <200ms for 50 windows):
  - Measure end-to-end switch time
  - Optimize i3 IPC queries (batch if possible)
- Profile config validation time (target <500ms):
  - Cache JSON schema
  - Optimize filesystem checks
- Profile layout restore time (target <5s for 10 windows):
  - Parallelize window launches where possible
  - Optimize wait-for-mark polling
- Add performance metrics to `i3pm status` output

**Acceptance**: All performance requirements met (SC-001, SC-016, SC-017, SC-018)

**Story**: Polish

---

### T069: Create demo video and screenshots [P]

**File**: `specs/019-re-explore-and/demo/`

**Description**: Create visual documentation for feature showcase.

**Tasks**:
- Record demo video (2-3 minutes) showing:
  - TUI project browser
  - Creating project via wizard
  - Switching projects
  - Saving/restoring layout
  - Monitoring dashboard
- Take screenshots of all TUI screens for documentation
- Add to feature spec and quickstart guide

**Acceptance**: Demo video and screenshots available

**Story**: Polish

---

### T070: Final integration testing

**File**: `tests/i3_project_manager/test_integration/test_full_system.py`

**Description**: End-to-end system tests covering all user stories.

**Tasks**:
- Test full workflow:
  1. Install i3pm (NixOS module)
  2. Create 3 projects via TUI wizard
  3. Configure auto-launch for each
  4. Switch between projects
  5. Save layouts
  6. Restore layouts
  7. Monitor daemon status
  8. Close projects
  9. Delete projects
- Test with real i3 instance (not mocked)
- Test daemon integration (verify events processed)
- Test multi-monitor scenarios (if possible)
- Run automated test suite (i3-project-test if applicable)
- Verify all success criteria met

**Acceptance**: Full system works end-to-end, all success criteria pass

**Story**: Polish

---

## Dependencies and Parallel Execution

### Dependency Graph (User Story Completion Order)

```
Phase 1 (Setup) → Phase 2 (Foundational)
                      ↓
      ┌───────────────┼───────────────┬──────────────┐
      ▼               ▼               ▼              ▼
   Phase 3 (US1)   Phase 4 (US2)  Phase 5 (US3)  Phase 6 (US9)
   Switching       Auto-mark      CRUD Ops       TUI Interface
      │               │               │              │
      └───────────────┴───────────────┴──────────────┘
                      │
      ┌───────────────┼───────────────┐
      ▼               ▼               ▼
   Phase 7 (US7)  Phase 8 (US4)  Phase 9 (US8)
   Monitoring     Multi-Monitor  Launcher
      │               │               │
      └───────────────┴───────────────┘
                      │
                   Phase 10 (US5)
                   Layout/Auto-Launch
                      │
                   Phase 11 (US6)
                   Close Projects
                      │
                   Phase 12
                   Polish
```

### Parallelizable Task Groups

**Can be done in parallel** (marked with `[P]` in tasks):

**Phase 1 (Setup)**: T001, T002, T003 (all parallel)

**Phase 2 (Foundational)**:
- Group A: T004 (models)
- Group B (after T004): T005, T006, T007, T009 (all parallel)
- Group C (after Group B): T008, T010 (parallel)

**Phase 3 (US1)**:
- Group A: T011 (switching logic)
- Group B (after T011): T012, T013, T014, T015 (all parallel)
- Group C (after T012-T015): T016

**Phase 4 (US2)**: T018, T019, T020 (all parallel after T017)

**Phase 5 (US3)**:
- Group A: T021 (CRUD logic)
- Group B (after T021): T022, T023, T024, T025, T026, T027 (all parallel)
- Group C (after Group B): T028, T029 (parallel)

**Phase 6 (US9)**:
- Sequential: T030 → T031 → T034 (app skeleton → browser → wizard)
- Parallel after T031: T032, T033, T035, T036, T037, T038
- Final: T039, T040 (parallel tests)

**Phase 7-11**: Most CLI commands within each phase can be done in parallel

**Phase 12**: T065, T066, T067, T069 (all parallel)

### Recommended MVP Scope (Phases 1-6)

For fastest time-to-value, implement in this order:
1. **Phase 1-2**: Setup + Foundational (required infrastructure)
2. **Phase 3**: User Story 1 (project switching - core value)
3. **Phase 5**: User Story 3 (project creation - necessary for US1)
4. **Phase 6**: User Story 9 (TUI interface - dramatically improves UX)

After MVP, add enhanced features:
5. **Phase 4**: User Story 2 (auto-marking - already in daemon, just validate)
6. **Phase 10**: User Story 5 (layouts - high value)
7. **Phase 7**: User Story 7 (monitoring - debugging)
8. **Phases 8, 9, 11**: Nice-to-have features

## Summary

**Total Tasks**: 70
**Phases**: 12
**User Stories**: 9 (6 in MVP)

**Task Distribution by User Story**:
- Setup: 3 tasks
- Foundational: 7 tasks
- US1 (Project Switching - P1): 6 tasks
- US2 (Auto-marking - P1): 4 tasks
- US3 (CRUD - P1): 9 tasks
- US9 (TUI - P1): 11 tasks
- US7 (Monitoring - P2): 5 tasks
- US4 (Multi-monitor - P2): 3 tasks
- US8 (Launcher - P2): 3 tasks
- US5 (Layouts - P2): 10 tasks
- US6 (Closing - P3): 3 tasks
- Polish: 6 tasks

**MVP Scope** (Phases 1-6): 40 tasks
**Enhanced Features** (Phases 7-11): 24 tasks
**Polish** (Phase 12): 6 tasks

**Estimated Timeline** (with full-time development):
- Week 1: Setup + Foundational (Phases 1-2)
- Week 2: US1 + US3 (Phases 3, 5)
- Week 3-4: US9 TUI (Phase 6)
- Week 5: US2, US7 (Phases 4, 7)
- Week 6: US4, US8, US5 (Phases 8-10)
- Week 7: US6 + Polish (Phases 11-12)

**Parallel Execution Opportunities**: 35 tasks can be parallelized (50% of total)

**Independent Test Criteria**:
- US1: Switch between 2 projects with 2 windows each (<200ms)
- US2: Launch window, verify mark applied (<100ms)
- US3: Create project via CLI, verify config file
- US4: Connect monitor, verify workspace distribution
- US5: Auto-launch 2 apps on project switch
- US6: Close 5 project windows with one command
- US7: Monitor shows events within 100ms
- US8: Launch app, verify env vars set
- US9: Complete TUI wizard in <2 minutes

**Success**: Each phase delivers working, testable functionality. MVP (Phases 1-6) provides core value without layout/monitoring features.
