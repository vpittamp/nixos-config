# Tasks: Visual Window State Management with Layout Integration

**Feature Branch**: `025-visual-window-state`
**Input**: Design documents from `/etc/nixos/specs/025-visual-window-state/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Tests are NOT explicitly requested in this feature specification. Following speckit convention, test tasks are excluded from this implementation plan.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Python package: `home-modules/tools/i3_project_manager/`
- Tests: `tests/i3_project_manager/`
- Configuration: `~/.config/i3pm/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and module structure

- [ ] T001 Create visualization package directory `home-modules/tools/i3_project_manager/visualization/` with `__init__.py`
- [ ] T002 [P] Create schemas package directory `home-modules/tools/i3_project_manager/schemas/` with `__init__.py`
- [ ] T003 [P] Copy JSON schemas from `specs/025-visual-window-state/contracts/` to `home-modules/tools/i3_project_manager/schemas/` (rule-action-schema.json, window-rule-schema.json)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Pydantic models and validation infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Data Models (Pydantic)

- [ ] T004 Extend `WindowGeometry` model in `home-modules/tools/i3_project_manager/models/layout.py` with Pydantic validation (x, y, width >0, height >0)
- [ ] T005 [P] Create `SwallowCriteria` model in `home-modules/tools/i3_project_manager/models/layout.py` with regex validation, matches() method, to_i3_swallow() method
- [ ] T006 [P] Create `WindowState` model in `home-modules/tools/i3_project_manager/models/layout.py` with i3 IPC contract validation (id, class, instance, title, workspace, output, marks, geometry, project, classification, hidden)
- [ ] T007 [P] Create `MonitorInfo` model in `home-modules/tools/i3_project_manager/models/layout.py` (name, active, width, height, x, y)
- [ ] T008 Create `LayoutWindow` model in `home-modules/tools/i3_project_manager/models/layout.py` with swallows, launch_command validation (shell safety), working_directory validation (exists), environment filtering (secrets), geometry, floating, border, layout, percent validation
- [ ] T009 Create `WorkspaceLayout` model in `home-modules/tools/i3_project_manager/models/layout.py` (number 1-10, output, layout enum, windows list, saved_at, window_count validation matches list length)
- [ ] T010 Create `SavedLayout` model in `home-modules/tools/i3_project_manager/models/layout.py` with version validation ("1.0"), project, layout_name (filesystem-safe regex), saved_at, monitor_count matches config length, monitor_config, workspaces, total_windows matches sum, metadata, get_workspace() method, export_i3_json() method
- [ ] T011 Create `WindowDiff` model in `home-modules/tools/i3_project_manager/models/layout.py` with layout_name, current_windows, saved_windows, added/removed/moved/kept lists, computed_at, count validation, has_changes() method, summary() method
- [ ] T012 Create `LaunchCommand` model in `home-modules/tools/i3_project_manager/models/layout.py` (command, working_directory, environment, source validation ["discovered" or "configured"])
- [ ] T013 Update `home-modules/tools/i3_project_manager/models/__init__.py` to export all new models (SwallowCriteria, WindowState, LayoutWindow, WorkspaceLayout, SavedLayout, WindowDiff, LaunchCommand, MonitorInfo)

**Checkpoint**: Foundation models ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Real-Time Window State Monitoring (Priority: P1) 🎯 MVP

**Goal**: Enable users to visualize current window state across monitors/workspaces with real-time updates

**Independent Test**: Launch `i3pm windows --live`, verify all windows shown in tree view with monitor → workspace → window hierarchy, create/destroy/move windows and verify updates appear within 100ms

### Core Infrastructure for User Story 1

- [ ] T014 [P] [US1] Extend `DaemonClient` in `home-modules/tools/i3_project_manager/core/daemon_client.py` with `get_window_tree()` JSON-RPC method returning hierarchical window state
- [ ] T015 [P] [US1] Extend `DaemonClient` in `home-modules/tools/i3_project_manager/core/daemon_client.py` with `subscribe_window_events()` method returning async iterator for real-time updates
- [ ] T016 [P] [US1] Add window state query handler to `home-modules/desktop/i3-project-event-daemon/ipc_server.py` for `get_window_tree` RPC method (queries i3 IPC GET_TREE, GET_WORKSPACES, GET_OUTPUTS)
- [ ] T017 [P] [US1] Extend event handlers in `home-modules/desktop/i3-project-event-daemon/handlers.py` to broadcast window state changes to subscribed IPC clients

### Tree View Visualization

- [ ] T018 [US1] Create `WindowTreeView` widget in `home-modules/tools/i3_project_manager/visualization/tree_view.py` extending Textual Tree with monitor → workspace → window hierarchy rendering
- [ ] T019 [US1] Add keyboard navigation to `WindowTreeView` (arrows to navigate, Enter to focus window via i3 IPC, 'c' to collapse/expand nodes, 'f' to filter)
- [ ] T020 [US1] Add real-time update handling to `WindowTreeView` by subscribing to daemon window events with debouncing (100ms window)
- [ ] T021 [US1] Add search/filter capability to `WindowTreeView` (filter by project, monitor, workspace, window class, visible/hidden status)
- [ ] T022 [US1] Add window property display to tree nodes (class, title, workspace, monitor, project, marks, floating, focused, hidden status)

### Table View Visualization

- [ ] T023 [P] [US1] Create `WindowTableView` widget in `home-modules/tools/i3_project_manager/visualization/table_view.py` extending Textual DataTable with columns (ID, Class, Instance, Title, Workspace, Output, Project, Hidden)
- [ ] T024 [US1] Add sorting capability to `WindowTableView` (click column headers to sort ascending/descending)
- [ ] T025 [US1] Add filtering to `WindowTableView` (filter by project, workspace, output, visible/hidden status)
- [ ] T026 [US1] Add real-time update handling to `WindowTableView` by subscribing to daemon window events

### TUI Integration

- [ ] T027 [US1] Extend `MonitorScreen` in `home-modules/tools/i3_project_manager/tui/screens/monitor.py` with "Window Tree" tab showing WindowTreeView widget
- [ ] T028 [US1] Add "Window Table" tab to `MonitorScreen` showing WindowTableView widget
- [ ] T029 [US1] Add tab switching keybindings to `MonitorScreen` (Tab to switch between tree/table views)

### CLI Commands

- [ ] T030 [P] [US1] Add `windows` command to `home-modules/tools/i3_project_manager/cli/commands.py` with `--tree` flag printing ASCII tree to stdout
- [ ] T031 [P] [US1] Add `--table` flag to `windows` command printing formatted table to stdout
- [ ] T032 [P] [US1] Add `--live` flag to `windows` command launching TUI with MonitorScreen showing tree/table views
- [ ] T033 [P] [US1] Add `--json` flag to `windows` command exporting window state as JSON to stdout
- [ ] T034 [US1] Create tree formatter in `home-modules/tools/i3_project_manager/cli/formatters.py` for ASCII tree rendering (uses Rich Tree)
- [ ] T035 [US1] Create table formatter in `home-modules/tools/i3_project_manager/cli/formatters.py` for table rendering (uses Rich Table)

**Checkpoint**: User Story 1 complete - users can view current window state in real-time via CLI or TUI

---

## Phase 4: User Story 2 - Visual Layout Save and Restore (Priority: P2)

**Goal**: Enable users to save current window arrangements and restore them later with visual feedback

**Independent Test**: Arrange windows in desired layout, run `i3pm layout save dev-setup`, close all windows, run `i3pm layout restore dev-setup`, verify all windows relaunch in original positions without visual flicker

### Launch Command Discovery

- [ ] T036 [P] [US2] Create `discover_launch_command()` function in `home-modules/tools/i3_project_manager/core/layout.py` using psutil to walk process tree from window PID, extract cmdline/cwd/env, return LaunchCommand model
- [ ] T037 [P] [US2] Create `filter_environment()` function in `home-modules/tools/i3_project_manager/core/layout.py` to remove secret patterns (TOKEN, PASSWORD, KEY, AWS_*, API_*) from environment variables
- [ ] T038 [P] [US2] Create `validate_launch_command()` function in `home-modules/tools/i3_project_manager/core/layout.py` checking for shell injection characters (|, &, ;, `, $, >, <, newline) and validating executable exists
- [ ] T039 [US2] Create launch command override configuration schema in `~/.config/i3pm/launch_commands.json` with per-app command mappings (class → instance → command)
- [ ] T040 [US2] Create `load_launch_overrides()` function in `home-modules/tools/i3_project_manager/core/layout.py` loading configuration from `~/.config/i3pm/launch_commands.json`

### Layout Save

- [ ] T041 [US2] Extend `save_layout()` in `home-modules/tools/i3_project_manager/core/layout.py` to query i3 IPC (GET_TREE, GET_WORKSPACES, GET_OUTPUTS) for complete window state
- [ ] T042 [US2] Add window property extraction to `save_layout()` creating WindowState instances from i3 tree nodes
- [ ] T043 [US2] Add launch command discovery to `save_layout()` calling `discover_launch_command()` for each window with fallback to overrides
- [ ] T044 [US2] Add SwallowCriteria generation to `save_layout()` creating default criteria (class + instance) or using overrides from swallow_criteria.json
- [ ] T045 [US2] Add WorkspaceLayout creation to `save_layout()` grouping LayoutWindows by workspace with layout mode preservation
- [ ] T046 [US2] Add SavedLayout creation to `save_layout()` with monitor config snapshot, metadata, and validation
- [ ] T047 [US2] Add layout file writing to `save_layout()` serializing SavedLayout to `~/.config/i3pm/projects/<project>/layouts/<name>.json` with atomic write (temp file + rename)

### Window Unmapping/Remapping

- [ ] T048 [P] [US2] Create `unmap_windows()` function in `home-modules/tools/i3_project_manager/core/layout.py` using xdotool to hide windows by ID list
- [ ] T049 [P] [US2] Create `remap_windows()` function in `home-modules/tools/i3_project_manager/core/layout.py` using xdotool to show windows by ID list
- [ ] T050 [P] [US2] Create `get_workspace_window_ids()` function in `home-modules/tools/i3_project_manager/core/layout.py` querying i3 IPC GET_TREE for window IDs on specific workspace

### Layout Restore

- [ ] T051 [US2] Extend `restore_layout()` in `home-modules/tools/i3_project_manager/core/layout.py` to load and validate SavedLayout from JSON file
- [ ] T052 [US2] Add monitor configuration validation to `restore_layout()` comparing saved monitor_count vs current outputs, warn if mismatch
- [ ] T053 [US2] Add workspace-by-workspace restore loop to `restore_layout()` iterating WorkspaceLayouts
- [ ] T054 [US2] Add window unmapping to restore loop calling `unmap_windows()` for existing workspace windows before layout application
- [ ] T055 [US2] Add append_layout JSON generation to restore loop creating i3-compatible JSON with swallow placeholders from WorkspaceLayout
- [ ] T056 [US2] Add i3 command execution to restore loop calling `append_layout <temp-file>` via i3 IPC
- [ ] T057 [US2] Add application launching to restore loop executing LaunchCommand for each LayoutWindow (check existing windows first via swallow match)
- [ ] T058 [US2] Add swallow wait with timeout to restore loop polling i3 tree for placeholder consumption (30s timeout configurable)
- [ ] T059 [US2] Add window remapping in try/finally block to restore loop ensuring `remap_windows()` called even on errors (FR-036 compliance)
- [ ] T060 [US2] Add restore result reporting showing counts (restored, launched, failed) with detailed error messages

### CLI Commands

- [ ] T061 [P] [US2] Add `layout save` command to `home-modules/tools/i3_project_manager/cli/commands.py` with `<layout-name>` argument calling save_layout()
- [ ] T062 [P] [US2] Add `layout restore` command to `home-modules/tools/i3_project_manager/cli/commands.py` with `<layout-name>` argument calling restore_layout()
- [ ] T063 [P] [US2] Add `layout list` command showing all saved layouts for current project with metadata (window count, saved date)
- [ ] T064 [P] [US2] Add `layout delete` command removing layout file with confirmation prompt

### TUI Integration

- [ ] T065 [US2] Extend `MonitorScreen` in `home-modules/tools/i3_project_manager/tui/screens/monitor.py` with 's' keybinding to save layout (prompts for name)
- [ ] T066 [US2] Add 'r' keybinding to `MonitorScreen` to restore layout (shows layout picker)
- [ ] T067 [US2] Add layout picker widget to `MonitorScreen` showing saved layouts with preview (window count, saved date)

**Checkpoint**: User Story 2 complete - users can save and restore layouts without visual flicker

---

## Phase 5: User Story 4 - Enhanced Window Matching and Launch (Priority: P2)

**Goal**: Improve layout restore reliability with flexible swallow criteria and per-app launch customization

**Independent Test**: Save layout with terminal showing directory in title, close terminal, restore layout, verify terminal reopens in correct directory despite title mismatch

### Swallow Matcher

- [ ] T068 [P] [US4] Create `SwallowMatcher` class in `home-modules/tools/i3_project_manager/core/swallow_matcher.py` with configuration loading, regex pattern caching
- [ ] T069 [US4] Add `load_swallow_config()` method to `SwallowMatcher` reading `~/.config/i3pm/swallow_criteria.json` with default criteria and per-app overrides
- [ ] T070 [US4] Add `match_window()` method to `SwallowMatcher` taking WindowState and SwallowCriteria list, returning best match with priority logic (class+instance+title > class+instance > class)
- [ ] T071 [US4] Add `generate_criteria()` method to `SwallowMatcher` creating SwallowCriteria from WindowState applying per-app overrides (title patterns for terminals, window_role for browsers)
- [ ] T072 [US4] Create swallow criteria configuration schema in `~/.config/i3pm/swallow_criteria.json` with default criteria ["class", "instance"] and app_overrides for Alacritty, Ghostty, Firefox, Google-chrome

### Enhanced Matching Integration

- [ ] T073 [US4] Update `save_layout()` in `home-modules/tools/i3_project_manager/core/layout.py` to use `SwallowMatcher.generate_criteria()` instead of hardcoded class+instance
- [ ] T074 [US4] Update `restore_layout()` in `home-modules/tools/i3_project_manager/core/layout.py` to use `SwallowMatcher.match_window()` for checking existing windows before launching duplicates
- [ ] T075 [US4] Add reposition existing window logic to `restore_layout()` moving matched windows to correct workspace/geometry instead of relaunching

### Advanced Launch Command Handling

- [ ] T076 [P] [US4] Add terminal detection to `discover_launch_command()` in `home-modules/tools/i3_project_manager/core/layout.py` extracting working directory from title pattern for Alacritty/Ghostty
- [ ] T077 [P] [US4] Add PWA detection to `discover_launch_command()` detecting Firefox PWAs by window instance and generating correct launch command
- [ ] T078 [US4] Add user prompt for missing launch commands in `restore_layout()` when window appears in saved layout but command not discovered (stores override for future)

**Checkpoint**: User Story 4 complete - layout restore handles edge cases (terminals, browsers, PWAs) reliably

---

## Phase 6: User Story 3 - Layout Diff and Comparison (Priority: P3)

**Goal**: Enable users to compare current state with saved layouts and make informed decisions

**Independent Test**: Modify current layout (add/remove/move windows), run `i3pm layout diff default`, verify diff shows added, removed, moved, and kept windows with clear categorization

### Diff Computation

- [ ] T079 [P] [US3] Create `compute_layout_diff()` function in `home-modules/tools/i3_project_manager/core/layout_diff.py` taking SavedLayout and current WindowState list
- [ ] T080 [US3] Add window matching loop to `compute_layout_diff()` using SwallowMatcher to find current windows matching saved LayoutWindows
- [ ] T081 [US3] Add categorization logic to `compute_layout_diff()` splitting matched windows into moved (workspace/output changed) vs kept (unchanged)
- [ ] T082 [US3] Add added/removed detection to `compute_layout_diff()` finding unmatched current windows (added) and unmatched saved windows (removed)
- [ ] T083 [US3] Create WindowDiff instance with all categories and return

### Diff Visualization

- [ ] T084 [P] [US3] Create `DiffView` widget in `home-modules/tools/i3_project_manager/visualization/diff_view.py` with side-by-side layout (saved vs current)
- [ ] T085 [US3] Add color coding to `DiffView` (green for added, red for removed, yellow for moved, white for kept)
- [ ] T086 [US3] Add workspace assignment display to `DiffView` for moved windows showing "WS2 → WS1" format
- [ ] T087 [US3] Add interactive actions to `DiffView` ('r' to restore missing, 'u' to update saved layout, 'd' to discard changes)

### Partial Restore

- [ ] T088 [US3] Create `restore_partial()` function in `home-modules/tools/i3_project_manager/core/layout.py` taking WindowDiff and restoring only removed windows (missing from current state)
- [ ] T089 [US3] Add missing window filtering to `restore_partial()` extracting LayoutWindows from WindowDiff.removed
- [ ] T090 [US3] Add targeted launch to `restore_partial()` launching only missing windows without unmapping existing (skip unmapping step from full restore)

### Layout Update

- [ ] T091 [US3] Create `update_layout()` function in `home-modules/tools/i3_project_manager/core/layout.py` taking current state and layout name, overwriting saved layout with current state
- [ ] T092 [US3] Add confirmation prompt to `update_layout()` showing diff summary before overwriting

### CLI Commands

- [ ] T093 [P] [US3] Add `layout diff` command to `home-modules/tools/i3_project_manager/cli/commands.py` with `<layout-name>` argument showing diff in formatted output
- [ ] T094 [P] [US3] Add `--restore-missing` flag to `layout diff` command calling restore_partial()
- [ ] T095 [P] [US3] Add `--update` flag to `layout diff` command calling update_layout()
- [ ] T096 [US3] Create diff formatter in `home-modules/tools/i3_project_manager/cli/formatters.py` rendering WindowDiff with color coding (uses Rich Panel and Table)

### TUI Integration

- [ ] T097 [US3] Extend `MonitorScreen` in `home-modules/tools/i3_project_manager/tui/screens/monitor.py` with 'd' keybinding showing diff view for current project's saved layouts
- [ ] T098 [US3] Add layout selection to diff view showing all saved layouts with window count
- [ ] T099 [US3] Add diff display to selected layout showing DiffView widget with interactive actions

**Checkpoint**: User Story 3 complete - users can diff layouts and make informed save/update/restore decisions

---

## Phase 7: User Story 5 - i3-resurrect Layout Migration (Priority: P3)

**Goal**: Enable users to import existing i3-resurrect layouts and export i3pm layouts for vanilla i3 compatibility

**Independent Test**: Export i3pm layout to i3-resurrect format, import into vanilla i3 using `i3-msg "append_layout <file>"`, verify layout restores correctly

### Import from i3-resurrect

- [ ] T100 [P] [US5] Create `import_i3_resurrect()` function in `home-modules/tools/i3_project_manager/core/layout.py` taking i3-resurrect JSON file path
- [ ] T101 [US5] Add i3-resurrect JSON parsing to `import_i3_resurrect()` reading vanilla i3 append_layout format
- [ ] T102 [US5] Add swallow pattern conversion to `import_i3_resurrect()` converting i3 swallows to SwallowCriteria instances
- [ ] T103 [US5] Add launch command detection to `import_i3_resurrect()` prompting user for command mappings (window class → launch command)
- [ ] T104 [US5] Add SavedLayout creation to `import_i3_resurrect()` converting i3-resurrect workspace layouts to i3pm WorkspaceLayouts with i3pm namespace
- [ ] T105 [US5] Add layout file writing to `import_i3_resurrect()` saving converted layout to `~/.config/i3pm/projects/<project>/layouts/<name>.json`

### Export to i3-resurrect

- [ ] T106 [P] [US5] Create `export_i3_resurrect()` function in `home-modules/tools/i3_project_manager/core/layout.py` taking SavedLayout and output file path
- [ ] T107 [US5] Add i3pm namespace stripping to `export_i3_resurrect()` removing all `i3pm` fields from layout JSON
- [ ] T108 [US5] Add vanilla i3 JSON generation to `export_i3_resurrect()` creating pure i3 append_layout format with swallows, geometry, floating, border, layout
- [ ] T109 [US5] Add JSON schema validation to `export_i3_resurrect()` validating exported JSON against i3 append_layout schema (no i3pm-specific fields)
- [ ] T110 [US5] Add layout file writing to `export_i3_resurrect()` writing vanilla i3 JSON to specified path

### CLI Commands

- [ ] T111 [P] [US5] Add `layout import` command to `home-modules/tools/i3_project_manager/cli/commands.py` with `<i3-resurrect-file>` and `--project=<name>` arguments calling import_i3_resurrect()
- [ ] T112 [P] [US5] Add `layout export` command with `<layout-name>` and `--format=i3-resurrect` arguments calling export_i3_resurrect()
- [ ] T113 [P] [US5] Add `--output=<file>` flag to `layout export` command specifying output file path (default stdout)

**Checkpoint**: User Story 5 complete - users can migrate from i3-resurrect and export for vanilla i3 compatibility

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

### Documentation

- [ ] T114 [P] Update `CLAUDE.md` with new commands (`i3pm windows`, `i3pm layout save/restore/diff/import/export`) including all flags and examples
- [ ] T115 [P] Add troubleshooting section to `CLAUDE.md` for layout issues (windows not swallowed, visual flicker, launch command not discovered)
- [ ] T116 [P] Add performance metrics section to `CLAUDE.md` with benchmarks from Success Criteria (SC-001 to SC-012)
- [ ] T117 [P] Create user guide `docs/I3PM_LAYOUTS.md` with getting started, common workflows, customizing swallow criteria, migrating from i3-resurrect
- [ ] T118 [P] Create example layouts in `docs/examples/layouts/` with sample JSON files for dev-setup, minimal, full-screen
- [ ] T119 [P] Create example swallow criteria in `docs/examples/swallow_criteria.json` with overrides for common apps

### Code Quality

- [ ] T120 [P] Add type hints to all new functions in visualization/, core/swallow_matcher.py, core/layout_diff.py
- [ ] T121 [P] Add docstrings to all public classes and methods following Python standards
- [ ] T122 [P] Add error handling to all i3 IPC calls with meaningful error messages (FR-035 compliance)
- [ ] T123 [P] Add logging to layout operations (save/restore/diff) with DEBUG level for troubleshooting

### Performance Optimization

- [ ] T124 [P] Add regex pattern caching to SwallowMatcher (compile once, reuse)
- [ ] T125 [P] Add debouncing to tree view updates (100ms window for batching events)
- [ ] T126 [P] Add virtualization to tree view for large window counts (only render visible nodes)
- [ ] T127 [P] Profile layout operations and optimize bottlenecks (target: SC-003 <2s save, SC-004 <30s restore, SC-007 <500ms diff)

### Security Hardening

- [ ] T128 [P] Add environment variable filtering audit to LayoutWindow model (block AWS_*, TOKEN, SECRET, PASSWORD, KEY, API_*)
- [ ] T129 [P] Add launch command validation to all restore operations (no shell metacharacters |, &, ;, `, $, >, <)
- [ ] T130 [P] Set layout file permissions to 600 (user-only read/write) on save operations
- [ ] T131 [P] Add import confirmation prompt for external layout files (warn about untrusted sources)

### Validation

- [ ] T132 Run quickstart.md validation workflow (manual testing of all commands with sample layouts)
- [ ] T133 Verify all Success Criteria metrics (SC-001 to SC-012) with benchmarks

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - User Story 1 (Phase 3): Independent - no dependencies on other stories
  - User Story 2 (Phase 4): Independent but benefits from US1 tree view for debugging
  - User Story 4 (Phase 5): Depends on US2 (extends save/restore with enhanced matching)
  - User Story 3 (Phase 6): Depends on US2 and US4 (uses save/restore and matching)
  - User Story 5 (Phase 7): Depends on US2 (uses save/restore infrastructure)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1) - Window State Monitoring**: Can start after Foundational (Phase 2) - Independent
- **User Story 2 (P2) - Layout Save/Restore**: Can start after Foundational (Phase 2) - Independent
- **User Story 4 (P2) - Enhanced Matching**: Requires US2 complete (extends restore logic)
- **User Story 3 (P3) - Layout Diff**: Requires US2 and US4 complete (uses matching and restore)
- **User Story 5 (P3) - i3-resurrect Compatibility**: Requires US2 complete (uses save/restore)

### Critical Path

**Foundational → US2 (Save/Restore) → US4 (Enhanced Matching) → US3 (Diff)**

US1 (Window State) can be developed in parallel with US2-US5.

### Parallel Opportunities

- All Setup tasks (T001-T003) can run in parallel
- All Foundational model creation tasks (T005-T012) marked [P] can run in parallel after T004
- Within US1: Infrastructure tasks (T014-T017), table view (T023-T026), CLI commands (T030-T033) can run in parallel
- Within US2: Launch discovery functions (T036-T038), unmapping functions (T048-T050), CLI commands (T061-T064) can run in parallel
- Within US4: SwallowMatcher creation (T068), terminal/PWA detection (T076-T077) can run in parallel
- Within US3: Diff visualization (T084), CLI commands (T093-T095) can run in parallel
- Within US5: Import (T100), export (T106), CLI commands (T111-T113) can run in parallel
- All Polish tasks (T114-T131) can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# Launch all Pydantic model creation tasks together:
Task: "Create SwallowCriteria model in models/layout.py"
Task: "Create WindowState model in models/layout.py"
Task: "Create MonitorInfo model in models/layout.py"
Task: "Create LaunchCommand model in models/layout.py"
```

## Parallel Example: User Story 1

```bash
# Launch infrastructure and table view together:
Task: "Extend DaemonClient with get_window_tree() in core/daemon_client.py"
Task: "Extend DaemonClient with subscribe_window_events() in core/daemon_client.py"
Task: "Create WindowTableView widget in visualization/table_view.py"

# Launch CLI commands together:
Task: "Add windows command with --tree flag in cli/commands.py"
Task: "Add --table flag to windows command in cli/commands.py"
Task: "Add --live flag to windows command in cli/commands.py"
Task: "Add --json flag to windows command in cli/commands.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational models (T004-T013) - CRITICAL
3. Complete Phase 3: User Story 1 (T014-T035)
4. **STOP and VALIDATE**: Test `i3pm windows --live`, verify real-time updates
5. Deploy/demo if ready

### Incremental Delivery (Recommended)

1. Setup + Foundational → Foundation ready
2. Add User Story 1 (Window Monitoring) → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 (Save/Restore) → Test independently → Deploy/Demo
4. Add User Story 4 (Enhanced Matching) → Test with terminals/PWAs → Deploy/Demo
5. Add User Story 3 (Diff) → Test diff workflow → Deploy/Demo
6. Add User Story 5 (i3-resurrect) → Test import/export → Deploy/Demo
7. Polish phase → Final release

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T013)
2. Once Foundational is done:
   - Developer A: User Story 1 (T014-T035) - Window Monitoring
   - Developer B: User Story 2 (T036-T067) - Save/Restore
3. After US2 complete:
   - Developer A continues: User Story 4 (T068-T078) - Enhanced Matching
   - Developer B starts: User Story 3 (T079-T099) - Layout Diff
   - Developer C starts: User Story 5 (T100-T113) - i3-resurrect
4. All developers: Polish phase (T114-T133)

---

## Task Summary

**Total Tasks**: 133

### By Phase
- Phase 1 (Setup): 3 tasks
- Phase 2 (Foundational): 10 tasks
- Phase 3 (US1 - Window Monitoring): 22 tasks
- Phase 4 (US2 - Save/Restore): 31 tasks
- Phase 5 (US4 - Enhanced Matching): 11 tasks
- Phase 6 (US3 - Diff): 21 tasks
- Phase 7 (US5 - i3-resurrect): 14 tasks
- Phase 8 (Polish): 21 tasks

### By User Story
- US1 (Real-Time Window State): 22 tasks
- US2 (Layout Save/Restore): 31 tasks
- US3 (Layout Diff): 21 tasks
- US4 (Enhanced Matching): 11 tasks
- US5 (i3-resurrect Migration): 14 tasks
- Foundational (Blocking): 10 tasks
- Setup/Polish: 24 tasks

### Parallel Opportunities
- 45 tasks marked [P] can run in parallel within their phase
- All user stories (except US4, US3, US5 dependencies on US2) can start in parallel after Foundational
- Estimated 30-40% time savings with parallel execution

### MVP Scope (User Story 1 Only)
- 35 tasks (Setup + Foundational + US1)
- Estimated completion time: 10-14 hours
- Delivers real-time window state visualization

### Recommended First Delivery (US1 + US2)
- 66 tasks (Setup + Foundational + US1 + US2)
- Estimated completion time: 25-35 hours
- Delivers window monitoring + layout save/restore (core value)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label (US1-US5) maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Tests are excluded per speckit convention (not requested in spec)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Success Criteria validation in Phase 8 (T132-T133)
