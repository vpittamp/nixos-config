# Implementation Tasks: Enhanced i3pm TUI with Comprehensive Management & Automated Testing

**Feature Branch**: `022-create-a-new`
**Created**: 2025-10-21
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Data Model**: [data-model.md](./data-model.md)

## Overview

This document provides actionable implementation tasks organized by user story priority. Each user story represents an independently testable increment of functionality.

**Total User Stories**: 8 (3× P1, 3× P2, 2× P3)
**Implementation Strategy**: Incremental delivery by priority, with User Story 1 + 7 as MVP

**User Story Priorities**:
- **P1 (Must Have)**: US1 (Layout Management), US2 (Workspace Config), US7 (Testing Framework)
- **P2 (Should Have)**: US3 (Window Classification), US4 (Auto-Launch Config), US8 (Monitor Detection)
- **P3 (Nice to Have)**: US5 (Navigation/UX), US6 (Pattern Matching)

---

## Phase 1: Project Setup & Infrastructure

**Goal**: Prepare development environment and shared infrastructure needed by all user stories.

**Duration**: 1-2 hours
**Blocking**: All subsequent phases depend on this

### T001: Extend LayoutWindow data model with application relaunching fields [Story: Setup]

**File**: `home-modules/tools/i3_project_manager/core/models.py` (lines 284-312)

**Action**: Add 4 new fields to LayoutWindow dataclass with default values for backward compatibility:
```python
cwd: Optional[str] = None              # Working directory for launch
launch_timeout: float = 5.0            # Timeout for window appearance (seconds)
max_retries: int = 3                   # Retry attempts if launch fails
retry_delay: float = 1.0               # Delay between retries (seconds)
```

**Validation**: Update `to_json()` and `from_json()` methods to handle new fields. Load existing layout JSON to verify backward compatibility.

**Dependencies**: None
**Estimated Time**: 15 minutes

---

### T002: Create test infrastructure and fixtures [Story: Setup]

**Files**:
- `tests/i3pm/__init__.py`
- `tests/i3pm/fixtures/__init__.py`
- `tests/i3pm/fixtures/mock_daemon.py`
- `tests/i3pm/fixtures/mock_i3.py`
- `tests/i3pm/fixtures/sample_projects.py`

**Action**: Create mock implementations for isolated testing:

1. **Mock Daemon Client** (`mock_daemon.py`):
   - Implement mock JSON-RPC client
   - Capture all IPC calls for verification
   - Return mock responses for switch_project, save_layout, etc.

2. **Mock i3 IPC** (`mock_i3.py`):
   - Mock i3ipc.aio.Connection
   - Implement mock GET_TREE, GET_OUTPUTS, GET_WORKSPACES responses
   - Track command() calls for verification

3. **Sample Projects** (`sample_projects.py`):
   - Create test project fixtures with various configurations
   - Include projects with layouts, auto-launch entries, workspace preferences

**Validation**: Import mock modules successfully, verify mock responses match real API structure.

**Dependencies**: None
**Estimated Time**: 2 hours

---

### T003: Create BreadcrumbWidget for navigation display [Story: Setup]

**File**: `home-modules/tools/i3_project_manager/tui/widgets/breadcrumb.py` (new file)

**Action**: Implement custom Textual widget for breadcrumb navigation:
```python
class BreadcrumbWidget(Static):
    def __init__(self, path: List[str]):
        self.path = path
        self.separator = " > "

    def render(self) -> str:
        return self.separator.join(self.path)

    def update_path(self, path: List[str]):
        self.path = path
        self.refresh()
```

**Validation**: Create widget with test path, verify rendering, test update_path() method.

**Dependencies**: None
**Estimated Time**: 30 minutes

---

## Phase 2: Foundational - Testing Framework (US7 - P1)

**Goal**: Implement automated TUI testing framework before implementing features to enable TDD workflow.

**Why First**: Testing framework enables validation of all subsequent user stories. Implements User Story 7 (P1 priority).

**Independent Test Criteria**: Framework can simulate key presses, evaluate assertions, and generate test reports with pass/fail status.

**Duration**: 8-12 hours

### T004: Implement TestAction and TestAssertion data models [Story: US7]

**File**: `tests/i3pm/fixtures/assertions.py` (new file)

**Action**: Create test framework data structures from contracts/test_framework.py:
- TestAction enum and factory methods (press_key, type_text, click, select_row, wait)
- TestAssertion enum and factory methods (file_exists, state_equals, timing, table_row_count)
- AssertionResult dataclass for evaluation results

**Validation**: Create test actions and assertions, verify serialization to JSON.

**Dependencies**: T002
**Estimated Time**: 1 hour

---

### T005: Implement TestScenario data model [Story: US7] [P]

**File**: `tests/i3pm/fixtures/test_scenario.py` (new file)

**Action**: Implement TestScenario dataclass with validation:
- Fields: name, description, preconditions, actions, assertions, timeout, cleanup, tags
- validate() method checking name format, required fields
- to_json() for test report serialization

**Validation**: Create test scenario with valid/invalid data, verify validation catches errors.

**Dependencies**: T004
**Estimated Time**: 45 minutes
**Parallel**: Can work on T004 and T005 simultaneously (different files)

---

### T006: Implement Pilot action simulation [Story: US7]

**File**: `tests/i3pm/test_framework.py` (new file)

**Action**: Implement ITestFramework.simulate_action() method:
- Handle PRESS_KEY: `await pilot.press(key)`
- Handle TYPE_TEXT: `await pilot.press(*list(text))`
- Handle CLICK: `await pilot.click(selector=widget_id)`
- Handle SELECT_ROW: Navigate table cursor and select
- Handle WAIT: `await asyncio.sleep(seconds)`
- Handle WAIT_FOR_CONDITION: Poll until condition met or timeout

**Validation**: Create pilot instance, simulate each action type, verify Textual receives events.

**Dependencies**: T004, T005
**Estimated Time**: 2 hours

---

### T007: Implement assertion evaluation [Story: US7]

**File**: `tests/i3pm/test_framework.py` (extending T006 file)

**Action**: Implement ITestFramework.evaluate_assertion() method:
- FILE_EXISTS: Check Path.exists()
- STATE_EQUALS: Query widget property via app.query_one(), compare value
- EVENT_TRIGGERED: Check mock daemon captured events
- TIMING: Measure operation duration, compare against threshold
- TABLE_ROW_COUNT: Query DataTable.row_count
- INPUT_VALUE: Query Input.value
- SCREEN_ACTIVE: Check app.screen.name
- WIDGET_VISIBLE: Check widget visibility

**Validation**: Create assertions of each type, evaluate against known state, verify pass/fail correctly.

**Dependencies**: T006
**Estimated Time**: 2 hours

---

### T008: Implement test scenario execution [Story: US7]

**File**: `tests/i3pm/test_framework.py` (extending T006/T007 file)

**Action**: Implement ITestFramework.execute_scenario() method:
1. Validate scenario
2. Check preconditions
3. Initialize Textual app with run_test()
4. For each action: simulate_action()
5. For each assertion: evaluate_assertion()
6. Execute cleanup actions
7. Generate TestResult with pass/fail status

**Validation**: Execute simple test scenario (press key, assert state), verify TestResult accuracy.

**Dependencies**: T007
**Estimated Time**: 2 hours

---

### T009: Implement state dump capture [Story: US7] [P]

**File**: `tests/i3pm/test_framework.py` (extending T006-T008 file)

**Action**: Implement ITestFramework.capture_state_dump() method:
- Query all widgets via app.query()
- Extract DataTable contents, Input values, visible screens
- Query project configuration files
- Capture mock daemon recent events
- Return structured dict with complete state

**Validation**: Capture state during test, verify dump contains expected widgets and data.

**Dependencies**: T006
**Estimated Time**: 1.5 hours
**Parallel**: Can work on T008 and T009 simultaneously (independent methods)

---

### T010: Implement test suite execution and coverage report [Story: US7]

**File**: `tests/i3pm/test_framework.py` (extending T006-T009 file)

**Action**: Implement:
- ITestFramework.execute_suite(): Run multiple scenarios in isolation, aggregate results
- ITestFramework.generate_coverage_report(): Analyze results, determine screens tested, actions tested, coverage percentage

**Validation**: Execute suite of 3 test scenarios, verify isolation (no cross-test interference), check coverage report accuracy.

**Dependencies**: T008, T009
**Estimated Time**: 2 hours

---

**CHECKPOINT**: Testing framework complete. Can now write tests for all subsequent user stories.

---

## Phase 3: User Story 1 - Layout Management Workflow (P1)

**Goal**: Implement complete layout save/restore/delete/export operations with application relaunching.

**Independent Test Criteria**: User can save a layout with 3 windows, close all windows, restore layout (apps relaunch), and verify all windows positioned correctly within 2 seconds.

**Duration**: 12-16 hours

### T011: Write test scenario for layout save workflow [Story: US1]

**File**: `tests/i3pm/scenarios/test_layout_workflow.py` (new file)

**Action**: Create test scenario using framework from Phase 2:
- Preconditions: 3 windows open (Ghostty, Code, Firefox)
- Actions: Open Layout Manager (press 'l'), save layout (press 's'), enter name, confirm
- Assertions: Layout file exists, appears in table, has correct window count

**Validation**: Run test (will fail until T012-T016 implemented), verify test structure correct.

**Dependencies**: T010
**Estimated Time**: 1 hour

---

### T012: Implement LayoutManager.save_layout() [Story: US1]

**File**: `home-modules/tools/i3_project_manager/core/layout_manager.py` (new file)

**Action**: Implement layout save operation per contracts/layout_manager.py:
1. Query i3 GET_TREE to get all windows with project mark
2. For each window: extract window_class, window_title, geometry, workspace
3. Infer launch_command from window_class (use existing app-classes.json mappings)
4. Query process environment variables and working directory (via /proc/{pid})
5. Group windows by workspace into WorkspaceLayout objects
6. Create SavedLayout with all WorkspaceLayouts
7. Serialize to JSON at ~/.config/i3/layouts/{project}/{layout_name}.json
8. Update Project.saved_layouts list

**Validation**: Call save_layout() with mock i3, verify JSON file created with correct structure.

**Dependencies**: T001
**Estimated Time**: 3 hours

---

### T013: Implement WindowLauncher.launch_and_wait() [Story: US1] [P]

**File**: `home-modules/tools/i3_project_manager/core/layout_manager.py` (extending T012 file)

**Action**: Implement window launching with polling per contracts/layout_manager.py:
1. Construct bash command with environment variables: `export VAR=val; cd $CWD; $COMMAND`
2. Send i3 exec command via IPC: `await i3.command(f'exec bash -c "{cmd}"')`
3. Poll GET_TREE every 100ms for window with matching window_class
4. If timeout: retry up to max_retries times with exponential backoff (retry_delay * 2^attempt)
5. Return window container if found, None if all retries exhausted

**Validation**: Launch test application, verify window appears in i3 tree, measure timing.

**Dependencies**: T001
**Estimated Time**: 2 hours
**Parallel**: Can work on T012 and T013 simultaneously (independent methods in same file)

---

### T014: Implement LayoutManager.restore_layout() [Story: US1]

**File**: `home-modules/tools/i3_project_manager/core/layout_manager.py` (extending T012-T013 file)

**Action**: Implement layout restore operation:
1. Load SavedLayout from JSON
2. Query i3 GET_TREE for current windows
3. For each LayoutWindow in layout:
   - Check if window exists by window_class
   - If missing: call launch_and_wait() with launch_command, env, cwd
   - If exists: move to correct workspace, apply geometry
4. Track timing (must complete within 2 seconds per FR-002)
5. Return LayoutRestoreResponse with statistics (windows_restored, windows_launched, windows_failed)

**Validation**: Restore layout with mix of existing/missing windows, verify all positioned correctly, check timing constraint.

**Dependencies**: T012, T013
**Estimated Time**: 3 hours

---

### T015: Implement LayoutManager.delete_layout() and export_layout() [Story: US1] [P]

**File**: `home-modules/tools/i3_project_manager/core/layout_manager.py` (extending T012-T014 file)

**Action**: Implement:
- delete_layout(): Check confirmation flag, remove layout file, update Project.saved_layouts
- export_layout(): Copy layout JSON to user-specified path with optional metadata enrichment

**Validation**: Delete layout, verify file removed. Export layout, verify copy created at target path.

**Dependencies**: T012
**Estimated Time**: 1 hour
**Parallel**: Can work on T014 and T015 simultaneously (independent methods)

---

### T016: Implement LayoutManager.restore_all() and close_all() [Story: US1] [P]

**File**: `home-modules/tools/i3_project_manager/core/layout_manager.py` (extending T012-T015 file)

**Action**: Implement:
- restore_all(): Iterate Project.auto_launch entries, launch if missing using launch_and_wait()
- close_all(): Query i3 GET_TREE for windows with project mark, send kill command to each

**Validation**: Configure auto-launch entries, call restore_all(), verify apps launched. Call close_all(), verify project windows closed.

**Dependencies**: T013
**Estimated Time**: 1.5 hours
**Parallel**: Can work on T015 and T016 simultaneously (independent methods)

---

### T017: Enhance Layout Manager TUI screen with save/restore/delete/export actions [Story: US1]

**File**: `home-modules/tools/i3_project_manager/tui/screens/layout_manager.py` (existing, enhance)

**Action**: Replace "not yet implemented" placeholders with actual operations:
- action_save_layout(): Show input dialog, call LayoutManager.save_layout(), refresh table
- action_restore_layout(): Get selected layout, call LayoutManager.restore_layout(), show progress
- action_delete_layout(): Show confirmation dialog, call LayoutManager.delete_layout(), refresh table
- action_export_layout(): Show file picker, call LayoutManager.export_layout()
- action_restore_all(): Call LayoutManager.restore_all(), show progress notifications
- action_close_all(): Call LayoutManager.close_all(), confirm completion

**Validation**: Open Layout Manager in TUI, perform each operation, verify UI updates and backend operations complete.

**Dependencies**: T012-T016
**Estimated Time**: 3 hours

---

### T018: Run layout workflow test and fix issues [Story: US1]

**File**: Tests from T011

**Action**: Execute test_layout_workflow.py test scenario:
1. Run test
2. If failures: Review assertion failures, fix implementation bugs
3. Re-run test until all assertions pass
4. Verify test completes within timeout

**Validation**: Test passes with all assertions green.

**Dependencies**: T017
**Estimated Time**: 1-2 hours (debugging/fixes)

---

**CHECKPOINT**: User Story 1 complete. Users can save/restore/delete/export layouts with application relaunching.

**Independent Test**: Run `pytest tests/i3pm/scenarios/test_layout_workflow.py -v`

---

## Phase 4: User Story 2 - Workspace Configuration (P1)

**Goal**: Implement workspace-to-monitor assignment configuration interface in TUI.

**Independent Test Criteria**: User can assign WS1-2 to primary, WS3-5 to secondary, save configuration, switch projects, and verify workspaces appear on correct monitors.

**Duration**: 8-10 hours

### T019: Write test scenario for workspace configuration [Story: US2]

**File**: `tests/i3pm/scenarios/test_workspace_config.py` (new file)

**Action**: Create test scenario:
- Preconditions: Project exists, 2 monitors connected
- Actions: Open project, navigate to workspace config, assign WS1→primary, WS2→secondary, save
- Assertions: Project JSON updated with workspace_preferences, redistribution triggered

**Validation**: Run test (will fail until T020-T023 implemented), verify test structure.

**Dependencies**: T010
**Estimated Time**: 45 minutes

---

### T020: Implement WorkspaceConfigManager.get_monitor_configuration() [Story: US2]

**File**: `home-modules/tools/i3_project_manager/core/workspace_config.py` (new file)

**Action**: Implement monitor configuration query per contracts/workspace_config.py:
1. Query i3 GET_OUTPUTS
2. Filter active outputs
3. Reuse existing workspace_manager.py get_monitor_configs() function
4. Return MonitorConfiguration with list of MonitorInfo objects

**Validation**: Query with mock i3 responses, verify MonitorInfo objects have correct roles assigned.

**Dependencies**: None (reuses existing workspace_manager.py)
**Estimated Time**: 1 hour

---

### T021: Implement WorkspaceConfigManager.update_workspace_config() [Story: US2]

**File**: `home-modules/tools/i3_project_manager/core/workspace_config.py` (extending T020 file)

**Action**: Implement workspace assignment update:
1. Load Project configuration
2. Validate each WorkspaceAssignment against current monitor count
3. Update Project.workspace_preferences dict
4. Save Project to disk (atomic write)
5. Return WorkspaceConfigUpdateResponse with validation warnings

**Validation**: Update workspace config, verify Project JSON updated, check validation catches invalid assignments.

**Dependencies**: T020
**Estimated Time**: 2 hours

---

### T022: Implement WorkspaceConfigManager.redistribute_workspaces() [Story: US2]

**File**: `home-modules/tools/i3_project_manager/core/workspace_config.py` (extending T020-T021 file)

**Action**: Implement workspace redistribution:
1. Get current monitor configuration
2. If use_project_preferences: load active project's workspace preferences
3. Else: apply default distribution (1 monitor: all WS on primary, 2 monitors: WS1-2 primary, WS3-9 secondary, etc.)
4. For each workspace: send i3 command to move to target output
5. Return WorkspaceRedistributionResponse with summary

**Validation**: Trigger redistribution, verify i3 commands sent to move workspaces.

**Dependencies**: T020, T021
**Estimated Time**: 2 hours

---

### T023: Create Workspace Config TUI screen [Story: US2]

**File**: `home-modules/tools/i3_project_manager/tui/screens/workspace_config.py` (new file)

**Action**: Create new Textual screen for workspace configuration:
- Display current monitor configuration in table (name, resolution, role, assigned workspaces)
- Display workspace assignment form with dropdowns for each workspace (1-10) to select role
- action_save_assignments(): Call WorkspaceConfigManager.update_workspace_config()
- action_redistribute(): Call WorkspaceConfigManager.redistribute_workspaces()
- Validation error display for invalid assignments

**Validation**: Open workspace config screen, assign workspaces, save, verify project JSON updated.

**Dependencies**: T020-T022
**Estimated Time**: 3 hours

---

### T024: Add workspace config navigation from project editor [Story: US2]

**File**: `home-modules/tools/i3_project_manager/tui/screens/editor.py` (existing, enhance)

**Action**: Add keybinding and action to open workspace config:
- Binding("w", "workspace_config", "Workspace Config")
- action_workspace_config(): Push WorkspaceConfigScreen

**Validation**: Open project editor, press 'w', verify workspace config screen opens.

**Dependencies**: T023
**Estimated Time**: 15 minutes

---

### T025: Run workspace config test and fix issues [Story: US2]

**File**: Tests from T019

**Action**: Execute test_workspace_config.py test scenario, fix any failures, re-run until pass.

**Validation**: Test passes with all assertions green.

**Dependencies**: T024
**Estimated Time**: 1 hour

---

**CHECKPOINT**: User Story 2 complete. Users can configure workspace-to-monitor assignments via TUI.

**Independent Test**: Run `pytest tests/i3pm/scenarios/test_workspace_config.py -v`

---

## Phase 5: User Story 7 Unit & Integration Tests (P1 Continuation)

**Goal**: Add comprehensive unit and integration tests for LayoutManager and WorkspaceConfigManager.

**Independent Test Criteria**: Test suite covers all layout and workspace operations with >80% code coverage.

**Duration**: 6-8 hours

### T026: Write unit tests for LayoutWindow model extensions [Story: US7]

**File**: `tests/i3pm/unit/test_models.py` (new file)

**Action**: Test LayoutWindow model changes from T001:
- Test backward compatibility: Load old layout JSON without new fields, verify defaults applied
- Test new fields serialization: Create LayoutWindow with all fields, to_json(), from_json(), verify roundtrip
- Test validation: Invalid cwd, negative timeout, etc.

**Validation**: All model tests pass.

**Dependencies**: T001
**Estimated Time**: 1 hour

---

### T027: Write unit tests for LayoutManager operations [Story: US7] [P]

**File**: `tests/i3pm/unit/test_layout_manager.py` (new file)

**Action**: Test LayoutManager with mock i3:
- test_save_layout(): Mock GET_TREE with 3 windows, verify SavedLayout JSON structure
- test_restore_layout_existing_windows(): Windows already open, verify repositioning only
- test_restore_layout_missing_windows(): Mock launch_and_wait(), verify apps launched
- test_restore_layout_timing(): Verify completes within 2 seconds
- test_delete_layout(): Verify file removed
- test_export_layout(): Verify copy created

**Validation**: All unit tests pass.

**Dependencies**: T012-T016
**Estimated Time**: 3 hours
**Parallel**: Can work on T026 and T027 simultaneously (different files)

---

### T028: Write integration tests for layout restore with i3 IPC [Story: US7]

**File**: `tests/i3pm/integration/test_layout_restore.py` (new file)

**Action**: Integration test with real i3 IPC (or comprehensive mock):
- Setup: Create test project, open test windows, save layout
- Action: Close windows, restore layout
- Assertions: Windows appear in correct workspaces, geometries match, timing <2s

**Validation**: Integration test passes end-to-end.

**Dependencies**: T014
**Estimated Time**: 2 hours

---

### T029: Write unit tests for WorkspaceConfigManager [Story: US7] [P]

**File**: `tests/i3pm/unit/test_workspace_config.py` (new file)

**Action**: Test WorkspaceConfigManager with mock i3:
- test_get_monitor_configuration(): Mock GET_OUTPUTS, verify MonitorInfo objects
- test_update_workspace_config(): Verify Project.workspace_preferences updated
- test_validate_against_monitor_count(): Invalid assignments caught
- test_redistribute_workspaces(): Verify i3 commands sent

**Validation**: All unit tests pass.

**Dependencies**: T020-T022
**Estimated Time**: 2 hours
**Parallel**: Can work on T028 and T029 simultaneously (different files)

---

**CHECKPOINT**: User Story 7 unit/integration tests complete for US1 and US2.

---

## Phase 6: User Story 3 - Window Classification Wizard (P2)

**Goal**: Implement interactive TUI wizard for classifying applications as scoped/global with live window inspection.

**Independent Test Criteria**: User can open wizard, see 5 unclassified windows, mark 2 as scoped and 3 as global, verify classifications persisted and windows immediately marked/unmarked.

**Duration**: 6-8 hours

### T030: Write test scenario for window classification workflow [Story: US3]

**File**: `tests/i3pm/scenarios/test_window_classification.py` (new file)

**Action**: Create test scenario:
- Preconditions: 5 unclassified windows open
- Actions: Open classification wizard, select VSCode, press 's' for scoped, select Firefox, press 'g' for global
- Assertions: app-classes.json updated, windows marked/unmarked via daemon

**Validation**: Run test (will fail until T031-T033 implemented).

**Dependencies**: T010
**Estimated Time**: 45 minutes

---

### T031: Create Classification Wizard TUI screen [Story: US3]

**File**: `home-modules/tools/i3_project_manager/tui/screens/classification_wizard.py` (new file)

**Action**: Create new Textual screen:
- Query i3 GET_TREE to get all windows
- Display DataTable with columns: Window Class, Title, Workspace, Current Classification
- Keybindings: 's' for scoped, 'g' for global, 'x' for export report
- action_mark_scoped(): Add window_class to AppClassification.scoped_classes, save, notify daemon
- action_mark_global(): Add to AppClassification.global_classes, save, notify daemon
- Real-time classification status updates

**Validation**: Open wizard, classify windows, verify app-classes.json updated.

**Dependencies**: None (uses existing AppClassification model)
**Estimated Time**: 4 hours

---

### T032: Add classification wizard navigation from main menu [Story: US3]

**File**: `home-modules/tools/i3_project_manager/tui/screens/browser.py` (existing, enhance)

**Action**: Add keybinding:
- Binding("shift+c", "classification_wizard", "Window Classification")
- action_classification_wizard(): Push ClassificationWizardScreen

**Validation**: Press Shift+C from browser, verify wizard opens.

**Dependencies**: T031
**Estimated Time**: 10 minutes

---

### T033: Run window classification test and fix issues [Story: US3]

**File**: Tests from T030

**Action**: Execute test_window_classification.py, fix failures, re-run.

**Validation**: Test passes.

**Dependencies**: T032
**Estimated Time**: 1 hour

---

**CHECKPOINT**: User Story 3 complete. Users can classify windows via interactive TUI wizard.

**Independent Test**: Run `pytest tests/i3pm/scenarios/test_window_classification.py -v`

---

## Phase 7: User Story 4 - Auto-Launch Configuration (P2)

**Goal**: Implement TUI interface for configuring auto-launch entries with workspace assignments and environment variables.

**Independent Test Criteria**: User can add auto-launch entry for "ghostty --working-directory $PROJECT_DIR" on WS1, save, switch projects, verify terminal launches on WS1.

**Duration**: 8-10 hours

### T034: Write test scenario for auto-launch configuration [Story: US4]

**File**: `tests/i3pm/scenarios/test_auto_launch_config.py` (new file)

**Action**: Create test scenario:
- Preconditions: Project exists
- Actions: Open auto-launch config, add entry with command/workspace/env vars, save
- Assertions: Project.auto_launch updated, application launches on project switch

**Validation**: Run test (will fail until T035-T037 implemented).

**Dependencies**: T010
**Estimated Time**: 45 minutes

---

### T035: Create Auto-Launch Config TUI screen [Story: US4]

**File**: `home-modules/tools/i3_project_manager/tui/screens/auto_launch_config.py` (new file)

**Action**: Create new Textual screen:
- Display DataTable with auto-launch entries: Command, Workspace, Env Vars, Status
- action_add_entry(): Push modal edit screen with form fields
- action_edit_entry(): Push modal edit screen with pre-filled data
- action_delete_entry(): Remove from Project.auto_launch, save
- action_reorder_up/down(): Move entry in list, save (changes launch order)
- action_toggle_enabled(): Add enabled/disabled flag (extend AutoLaunchApp model)

**Validation**: Open auto-launch config, add/edit/delete/reorder entries, verify Project JSON updated.

**Dependencies**: None (uses existing AutoLaunchApp model, may need to add 'enabled' field)
**Estimated Time**: 5 hours

---

### T036: Create Auto-Launch Edit modal screen [Story: US4]

**File**: `home-modules/tools/i3_project_manager/tui/screens/auto_launch_edit.py` (new file)

**Action**: Create modal screen for editing auto-launch entry:
- Input fields: Command, Workspace (1-10 or blank), Environment Variables (multiline KEY=VALUE)
- Input fields: Working Directory (optional), Wait Timeout, Launch Delay
- Validation: Command non-empty, workspace 1-10, timeout positive
- Return AutoLaunchApp on save, None on cancel

**Validation**: Open edit modal, fill form, verify data validation and return value.

**Dependencies**: None
**Estimated Time**: 2 hours

---

### T037: Add auto-launch config navigation from project editor [Story: US4]

**File**: `home-modules/tools/i3_project_manager/tui/screens/editor.py` (existing, enhance)

**Action**: Add keybinding:
- Binding("a", "auto_launch_config", "Auto-Launch")
- action_auto_launch_config(): Push AutoLaunchConfigScreen

**Validation**: Press 'a' from editor, verify auto-launch screen opens.

**Dependencies**: T035, T036
**Estimated Time**: 10 minutes

---

### T038: Run auto-launch config test and fix issues [Story: US4]

**File**: Tests from T034

**Action**: Execute test_auto_launch_config.py, fix failures, re-run.

**Validation**: Test passes.

**Dependencies**: T037
**Estimated Time**: 1 hour

---

**CHECKPOINT**: User Story 4 complete. Users can configure auto-launch entries via TUI.

**Independent Test**: Run `pytest tests/i3pm/scenarios/test_auto_launch_config.py -v`

---

## Phase 8: User Story 8 - Monitor Detection & Redistribution (P2)

**Goal**: Enhance Monitor Dashboard with real-time monitor configuration display and manual redistribution trigger.

**Independent Test Criteria**: User connects second monitor, opens Monitor Dashboard, sees both monitors listed, triggers redistribution, verifies workspaces moved to correct monitors.

**Duration**: 4-6 hours

### T039: Write test scenario for monitor redistribution [Story: US8]

**File**: `tests/i3pm/scenarios/test_monitor_redistribution.py` (new file)

**Action**: Create test scenario:
- Preconditions: 1 monitor initially, mock monitor connection event
- Actions: Open Monitor Dashboard, trigger redistribution
- Assertions: Workspaces redistributed according to default rules

**Validation**: Run test (will fail until T040-T041 implemented).

**Dependencies**: T010
**Estimated Time**: 45 minutes

---

### T040: Enhance Monitor Dashboard with redistribution action [Story: US8]

**File**: `home-modules/tools/i3_project_manager/tui/screens/monitor.py` (existing, enhance)

**Action**: Add redistribution functionality:
- Subscribe to i3 "output" events for real-time monitor updates
- action_redistribute(): Call WorkspaceConfigManager.redistribute_workspaces(), show progress dialog
- Display preview dialog: "Use project preferences or default distribution?" if active project has preferences
- Show redistribution summary notification after completion

**Validation**: Open Monitor Dashboard, trigger redistribution, verify workspaces moved.

**Dependencies**: T022 (WorkspaceConfigManager.redistribute_workspaces)
**Estimated Time**: 3 hours

---

### T041: Run monitor redistribution test and fix issues [Story: US8]

**File**: Tests from T039

**Action**: Execute test_monitor_redistribution.py, fix failures, re-run.

**Validation**: Test passes.

**Dependencies**: T040
**Estimated Time**: 1 hour

---

**CHECKPOINT**: User Story 8 complete. Users can view monitor config and manually trigger redistribution.

**Independent Test**: Run `pytest tests/i3pm/scenarios/test_monitor_redistribution.py -v`

---

## Phase 9: User Story 6 - Pattern-Based Window Matching (P3)

**Goal**: Implement TUI interface for creating, testing, and managing pattern rules for window classification.

**Independent Test Criteria**: User creates pattern rule "^Code.*" → scoped, tests against live windows, sees matching windows, saves pattern.

**Duration**: 6-8 hours

### T042: Write test scenario for pattern configuration [Story: US6]

**File**: `tests/i3pm/scenarios/test_pattern_config.py` (new file)

**Action**: Create test scenario:
- Preconditions: Multiple windows with varying class names open
- Actions: Open pattern config, create pattern "^Code.*" → scoped, test pattern, save
- Assertions: Pattern saved to app-classes.json, matching windows reclassified

**Validation**: Run test (will fail until T043-T044 implemented).

**Dependencies**: T010
**Estimated Time**: 45 minutes

---

### T043: Create Pattern Config TUI screen [Story: US6]

**File**: `home-modules/tools/i3_project_manager/tui/screens/pattern_config.py` (new file)

**Action**: Create new Textual screen:
- Display DataTable with pattern rules: Pattern, Scope, Priority, Matched Windows (count)
- action_add_pattern(): Push modal edit screen for pattern entry
- action_edit_pattern(): Push modal edit screen with pre-filled data
- action_delete_pattern(): Remove from AppClassification.class_patterns, save
- action_test_pattern(): Query i3 GET_TREE, apply pattern to all windows, show matches in table
- action_reorder_priority(): Move pattern up/down in priority list
- Real-time conflict detection: Highlight patterns that match same windows

**Validation**: Open pattern config, create/test/save patterns, verify app-classes.json updated.

**Dependencies**: None (uses existing PatternRule model)
**Estimated Time**: 5 hours

---

### T044: Add pattern config navigation from classification wizard [Story: US6]

**File**: `home-modules/tools/i3_project_manager/tui/screens/classification_wizard.py` (enhance from T031)

**Action**: Add keybinding:
- Binding("p", "pattern_config", "Pattern Config")
- action_pattern_config(): Push PatternConfigScreen

**Validation**: Press 'p' from classification wizard, verify pattern config opens.

**Dependencies**: T043
**Estimated Time**: 10 minutes

---

### T045: Run pattern config test and fix issues [Story: US6]

**File**: Tests from T042

**Action**: Execute test_pattern_config.py, fix failures, re-run.

**Validation**: Test passes.

**Dependencies**: T044
**Estimated Time**: 1 hour

---

**CHECKPOINT**: User Story 6 complete. Users can create and test pattern rules via TUI.

**Independent Test**: Run `pytest tests/i3pm/scenarios/test_pattern_config.py -v`

---

## Phase 10: User Story 5 - Enhanced Navigation & Visual Design (P3)

**Goal**: Improve TUI navigation with breadcrumbs, mouse support, vim keybindings, and visual polish.

**Independent Test Criteria**: User navigates through all screens using hjkl keys, clicks table rows with mouse, sees breadcrumb showing location, all contextual keybindings work.

**Duration**: 6-8 hours

### T046: Add breadcrumb navigation to all screens [Story: US5]

**Files**: All TUI screens (browser.py, editor.py, layout_manager.py, etc.)

**Action**: For each screen, add BreadcrumbWidget from T003:
- Browser: ["Projects"]
- Editor: ["Projects", "{project_name}", "Edit"]
- Layout Manager: ["Projects", "{project_name}", "Layouts"]
- Workspace Config: ["Projects", "{project_name}", "Workspaces"]
- Classification Wizard: ["Tools", "Window Classification"]
- Auto-Launch Config: ["Projects", "{project_name}", "Auto-Launch"]
- Pattern Config: ["Tools", "Pattern Matching"]
- Monitor Dashboard: ["Monitor", "Dashboard"]

**Validation**: Navigate to each screen, verify breadcrumb displays correct path.

**Dependencies**: T003
**Estimated Time**: 2 hours

---

### T047: Add vim-style keybindings to all screens [Story: US5] [P]

**Files**: All TUI screens

**Action**: For each screen with DataTable, add bindings:
- Binding("j", "cursor_down", show=False)
- Binding("k", "cursor_up", show=False)
- Binding("h", "cursor_left", show=False)
- Binding("l", "cursor_right", show=False)

Ensure these don't conflict with existing single-letter actions (like 'l' for layout manager).

**Validation**: Navigate tables with hjkl keys, verify cursor moves correctly.

**Dependencies**: None
**Estimated Time**: 1 hour
**Parallel**: Can work on T046 and T047 simultaneously (independent changes)

---

### T048: Enable mouse support for table row selection [Story: US5]

**Files**: All TUI screens with DataTable

**Action**: For each DataTable:
- Ensure cursor_type="row" enabled
- Add on_data_table_row_selected() event handler
- Double-click row triggers default action (e.g., switch project, restore layout)

**Validation**: Click table rows with mouse, verify selection. Double-click, verify action triggered.

**Dependencies**: None
**Estimated Time**: 2 hours

---

### T049: Add Tab/Shift+Tab navigation for input fields [Story: US5] [P]

**Files**: All TUI screens with Input widgets (editor, wizard, auto-launch edit, etc.)

**Action**: Implement Tab key focus management:
- Override on_key() to handle Tab and Shift+Tab
- Maintain list of focusable widgets
- Tab moves focus to next widget, Shift+Tab to previous
- Add visual highlight to focused widget

**Validation**: Press Tab in forms, verify focus moves between inputs correctly.

**Dependencies**: None
**Estimated Time**: 2 hours
**Parallel**: Can work on T048 and T049 simultaneously (independent features)

---

### T050: Add search functionality to all data tables [Story: US5]

**Files**: All TUI screens with DataTable (browser, layout_manager, classification_wizard, etc.)

**Action**: For each screen:
- Add Input widget for search (initially hidden)
- Binding("/", "focus_search", "Search")
- Binding("escape", "clear_search", "Clear Search")
- Filter table rows based on search text (any column contains search text)
- Show placeholder text indicating searchable fields

**Validation**: Press '/' in any table screen, type search text, verify table filters.

**Dependencies**: None
**Estimated Time**: 2 hours

---

**CHECKPOINT**: User Story 5 complete. TUI navigation and visual design improved.

**Independent Test**: Manual testing of navigation features across all screens.

---

## Phase 11: Polish & Integration

**Goal**: Final integration testing, performance optimization, documentation updates, and bug fixes.

**Duration**: 4-6 hours

### T051: Write comprehensive end-to-end integration test [Story: Integration]

**File**: `tests/i3pm/scenarios/test_full_workflow.py` (new file)

**Action**: Create comprehensive test covering complete user workflow:
1. Create project via wizard
2. Configure workspace preferences
3. Classify windows (scoped/global)
4. Configure auto-launch entries
5. Save layout
6. Switch to another project (windows hide)
7. Switch back (windows restore)
8. Delete project

**Validation**: End-to-end test passes, covers all major features.

**Dependencies**: All previous tasks
**Estimated Time**: 2 hours

---

### T052: Performance optimization and timing validation [Story: Integration]

**Action**: Measure and optimize critical operations:
- Layout restore: Must complete within 2 seconds (FR-002)
- TUI operations: Must complete within 2 seconds (SC-001)
- Pattern rule testing: Must show results within 500ms (SC-006)
- Monitor updates: Must update within 1 second (SC-010)

If any operations exceed thresholds:
- Profile with cProfile
- Optimize slow operations (reduce i3 IPC calls, cache results, async parallelization)
- Re-measure until constraints met

**Validation**: All timing constraints met per spec.

**Dependencies**: All previous tasks
**Estimated Time**: 2-3 hours

---

### T053: Update CLAUDE.md with new TUI features [Story: Documentation]

**File**: `/etc/nixos/CLAUDE.md`

**Action**: Add section documenting new TUI features:
- Layout management workflow (save/restore/delete/export)
- Workspace configuration
- Window classification wizard
- Auto-launch configuration
- Pattern matching
- Navigation tips (breadcrumbs, vim keys, mouse, search)
- Testing framework usage

**Validation**: Documentation is clear and accurate.

**Dependencies**: None (can be done anytime)
**Estimated Time**: 1 hour

---

### T054: Run full test suite and generate coverage report [Story: Integration]

**Action**: Execute complete test suite:
```bash
pytest tests/i3pm/ -v --cov=home-modules/tools/i3_project_manager --cov-report=html --cov-report=term
```

**Validation**:
- All tests pass
- Coverage >80% for core modules
- Coverage >70% for TUI screens
- Test suite executes in <5 minutes (SC-007)

**Dependencies**: All previous tasks
**Estimated Time**: 30 minutes + fixes

---

**FINAL CHECKPOINT**: All user stories complete. Feature ready for production.

---

## Task Summary

### Total Tasks: 54

**By Phase**:
- Phase 1 (Setup): 3 tasks (T001-T003)
- Phase 2 (US7 - Testing Framework): 7 tasks (T004-T010)
- Phase 3 (US1 - Layout Management): 8 tasks (T011-T018)
- Phase 4 (US2 - Workspace Config): 7 tasks (T019-T025)
- Phase 5 (US7 - Unit/Integration Tests): 4 tasks (T026-T029)
- Phase 6 (US3 - Classification Wizard): 4 tasks (T030-T033)
- Phase 7 (US4 - Auto-Launch Config): 5 tasks (T034-T038)
- Phase 8 (US8 - Monitor Detection): 3 tasks (T039-T041)
- Phase 9 (US6 - Pattern Matching): 4 tasks (T042-T045)
- Phase 10 (US5 - Navigation/UX): 5 tasks (T046-T050)
- Phase 11 (Polish): 4 tasks (T051-T054)

**By User Story**:
- US1 (Layout Management - P1): 8 tasks
- US2 (Workspace Config - P1): 7 tasks
- US3 (Classification - P2): 4 tasks
- US4 (Auto-Launch - P2): 5 tasks
- US5 (Navigation - P3): 5 tasks
- US6 (Pattern Matching - P3): 4 tasks
- US7 (Testing - P1): 11 tasks (spread across phases)
- US8 (Monitor Detection - P2): 3 tasks
- Setup & Polish: 7 tasks

### Parallel Execution Opportunities

**Phase 1**: T001, T002, T003 can all run in parallel (different files)

**Phase 2**: T004 and T005 parallel, T008 and T009 parallel

**Phase 3**: T012 and T013 parallel, T014 and T015 parallel, T015 and T016 parallel, T026 and T027 parallel

**Phase 4**: T028 and T029 parallel

**Phase 10**: T046 and T047 parallel, T048 and T049 parallel

**Estimated Total Time with Parallelization**: 80-100 hours sequential, 60-75 hours with parallel execution

---

## Implementation Strategy

### MVP Scope (Minimum Viable Product)

**Recommend implementing first**:
- Phase 1: Setup (T001-T003)
- Phase 2: Testing Framework (T004-T010)
- Phase 3: Layout Management (T011-T018)

**MVP Deliverable**: Users can save, restore, delete, and export layouts with full test coverage. This addresses the #1 priority user need (User Story 1) and establishes testing infrastructure for all future work.

**MVP Timeline**: ~20-28 hours

### Incremental Delivery

**Sprint 1** (MVP): US1 + US7 Testing Framework
**Sprint 2**: US2 (Workspace Config) + US7 Unit Tests
**Sprint 3**: US3 (Classification) + US4 (Auto-Launch)
**Sprint 4**: US8 (Monitor) + US6 (Patterns)
**Sprint 5**: US5 (Navigation/UX) + Polish

Each sprint delivers independently testable functionality.

### Dependencies Between User Stories

```
US7 (Testing Framework)
  ↓ enables testing for all other stories
US1 (Layout Management)
  ↓ uses
US2 (Workspace Config)
  ↓ referenced by
US4 (Auto-Launch Config)

US3 (Classification Wizard)
  ↓ enhances
US6 (Pattern Matching)

US8 (Monitor Detection)
  ↓ uses
US2 (Workspace Config)

US5 (Navigation/UX) → applies to all screens
```

**Critical Path**: US7 → US1 → US2 → remaining stories can be done in any order

---

## Validation Checklist

After completing all tasks, verify:

- [ ] All 54 tasks completed
- [ ] All 8 user stories implemented
- [ ] Full test suite passes (pytest tests/i3pm/ -v)
- [ ] Test coverage >70% overall
- [ ] All performance constraints met (2s operations, 5min test suite)
- [ ] All 33 functional requirements implemented (FR-001 through FR-033)
- [ ] All 10 success criteria achieved (SC-001 through SC-010)
- [ ] Backward compatibility maintained (existing layouts still load)
- [ ] Documentation updated (CLAUDE.md, quickstart.md)
- [ ] No regressions in existing TUI functionality
- [ ] Constitution principles upheld (Python 3.11+, async patterns, pytest, i3 IPC authority)

---

**Status**: Ready for implementation
**Next Command**: `/speckit.implement` to execute tasks in order

**Generated**: 2025-10-21
**Feature Branch**: `022-create-a-new`
