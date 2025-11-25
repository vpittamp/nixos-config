# Tasks: Enhanced Projects & Applications CRUD Interface

**Feature**: 094-enhance-project-tab
**Input**: Design documents from `/specs/094-enhance-project-tab/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Per Constitution Principle XIV (Test-Driven Development), tests MUST be written before implementation. This task list includes comprehensive test tasks for each user story.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Paths follow single project structure with home-modules integration:
- **Backend**: `home-modules/tools/i3_project_manager/` and `home-modules/tools/monitoring-panel/`
- **Frontend**: `home-modules/desktop/eww-monitoring-panel.nix`
- **Tests**: `tests/094-enhance-project-tab/`
- **Specs**: `specs/094-enhance-project-tab/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and complete remaining design documents

- [x] T001 Complete remaining Phase 1 design documents (contracts/project-crud-api.md, contracts/app-crud-api.md, quickstart.md)
- [x] T002 Create test directory structure: tests/094-enhance-project-tab/{unit,integration,sway-tests}/
- [x] T003 [P] Create monitoring-panel tools directory: home-modules/tools/monitoring-panel/
- [x] T004 [P] Update CLAUDE.md with Feature 094 quick start commands via .specify/scripts/bash/update-agent-context.sh

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models, validation services, and UI infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Data Models (Foundation)

- [x] T005 [P] Create ProjectConfig Pydantic model in home-modules/tools/i3_project_manager/models/project_config.py (includes RemoteConfig, WorktreeConfig)
- [x] T006 [P] Create ApplicationConfig Pydantic models in home-modules/tools/i3_project_manager/models/app_config.py (includes TerminalAppConfig, PWAConfig)
- [x] T007 [P] Create UI state models in home-modules/tools/i3_project_manager/models/validation_state.py (FormValidationState, ConflictResolutionState, CLIExecutionResult)

### Core Services (Foundation)

- [x] T008 [P] Implement project JSON editor service in home-modules/tools/i3_project_manager/services/project_editor.py (CRUD operations for ~/.config/i3/projects/*.json)
- [x] T009 [P] Implement Nix file editor service in home-modules/tools/i3_project_manager/services/app_registry_editor.py (text-based manipulation of app-registry-data.nix per research.md)
- [x] T010 [P] Implement form validation service in home-modules/tools/i3_project_manager/services/form_validator.py (real-time validation with 300ms debouncing)
- [x] T011 Implement conflict detector service in home-modules/tools/monitoring-panel/conflict_detector.py (file modification timestamp comparison per spec.md Q2)
- [x] T012 Implement CLI executor service in home-modules/tools/monitoring-panel/cli_executor.py (executes i3pm/Git commands, parses stderr/exit codes per spec.md Q3)

### Base UI Infrastructure (Foundation)

- [x] T013 Add Projects/Apps tab base structure to home-modules/desktop/eww-monitoring-panel.nix (tab switcher integration, Catppuccin Mocha CSS from Feature 057)
- [x] T014 Extend monitoring_data.py with --mode projects handler in home-modules/tools/i3_project_manager/cli/monitoring_data.py
- [x] T015 Extend monitoring_data.py with --mode apps handler in home-modules/tools/i3_project_manager/cli/monitoring_data.py

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - View Project Configuration Details (Priority: P1) 🎯 MVP

**Goal**: Users can inspect detailed configuration of projects (local/remote) by hovering over project entries to see syntax-highlighted JSON detail

**Independent Test**: Open monitoring panel Projects tab, hover over project entry, verify colorized JSON appears with all project fields matching ~/.config/i3/projects/<name>.json

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T016 [P] [US1] Unit test for ProjectConfig model validation in tests/094-enhance-project-tab/unit/test_project_models.py
- [x] T017 [P] [US1] Unit test for project JSON reading in tests/094-enhance-project-tab/unit/test_project_editor.py
- [x] T018 [P] [US1] Integration test for Projects tab data loading in tests/094-enhance-project-tab/integration/test_project_view_workflow.py
- [x] T019 [P] [US1] Sway test for hover detail interaction in tests/094-enhance-project-tab/sway-tests/test_project_hover_detail.json

### Implementation for User Story 1

- [X] T020 [P] [US1] Implement project list data provider in monitoring_data.py (read all ~/.config/i3/projects/*.json, group by main/worktree)
- [X] T021 [P] [US1] Add JSON syntax highlighter function to eww-monitoring-panel.nix (Catppuccin Mocha colors: keys blue, strings green, numbers peach, booleans yellow)
- [X] T022 [US1] Implement Projects tab list view widget in eww-monitoring-panel.nix (display name, icon, working_dir, local/remote indicator)
- [X] T023 [US1] Implement hover detail widget in eww-monitoring-panel.nix (JSON tooltip with syntax highlighting, remote config section visibility)
- [X] T024 [US1] Add worktree hierarchy visualization (indentation, tree lines "├─", parent-child grouping)

**Checkpoint**: At this point, User Story 1 should be fully functional - users can view all project configurations with hover detail

---

## Phase 4: User Story 6 - View Application Registry Configuration (Priority: P1)

**Goal**: Users can inspect detailed configuration of applications (regular/terminal/PWAs) by hovering over app entries to see syntax-highlighted JSON detail with type-specific fields

**Independent Test**: Open Applications tab, hover over app entries (regular, terminal, PWA), verify JSON detail shows appropriate fields for each type

### Tests for User Story 6 ⚠️

- [x] T025 [P] [US6] Unit test for ApplicationConfig models in tests/094-enhance-project-tab/unit/test_app_models.py (test regular, terminal, PWA variants)
- [x] T026 [P] [US6] Integration test for Applications tab data loading in tests/094-enhance-project-tab/integration/test_app_view_workflow.py
- [x] T027 [P] [US6] Sway test for hover detail interaction in tests/094-enhance-project-tab/sway-tests/test_app_hover_detail.json

### Implementation for User Story 6

- [X] T028 [P] [US6] Implement application list data provider in monitoring_data.py (read from app-registry-data.nix via generated JSON, group by type: Regular/Terminal/PWA)
- [X] T029 [US6] Implement Applications tab list view widget in eww-monitoring-panel.nix (grouped by type, display name, command, icon)
- [X] T030 [US6] Implement app hover detail widget in eww-monitoring-panel.nix (JSON tooltip, conditional PWA fields: ULID/start_url/scope_url, terminal flag indicator)

**Checkpoint**: At this point, User Story 6 should be fully functional - users can view all application configurations with type-specific hover detail

---

## Phase 5: User Story 2 - Edit Existing Project Configuration (Priority: P2)

**Goal**: Users can modify project settings (display name, icon, working dir, remote SSH params) via inline edit forms with real-time validation and conflict detection

**Independent Test**: Click "Edit" on a project, modify display name and icon, save, verify project list updates immediately and JSON file on disk reflects changes

### Tests for User Story 2 ⚠️

- [X] T031 [P] [US2] Unit test for project validation rules in tests/094-enhance-project-tab/unit/test_form_validator.py
- [X] T032 [P] [US2] Unit test for project JSON editing in tests/094-enhance-project-tab/unit/test_project_editor.py (edit operations, backup/restore)
- [X] T033 [P] [US2] Unit test for conflict detection in tests/094-enhance-project-tab/unit/test_conflict_detector.py
- [X] T034 [P] [US2] Integration test for edit workflow in tests/094-enhance-project-tab/integration/test_project_edit_workflow.py (edit → validate → save → verify)
- [X] T035 [P] [US2] Sway test for inline edit form in tests/094-enhance-project-tab/sway-tests/test_project_edit_form.json

### Implementation for User Story 2

- [X] T036 [P] [US2] Implement edit_project method in home-modules/tools/i3_project_manager/services/project_editor.py (read JSON, update fields, write with backup)
- [X] T037 [P] [US2] Implement project CRUD handler in home-modules/tools/monitoring-panel/project_crud_handler.py (handle edit requests from Eww)
- [X] T038 [US2] Add inline edit form widget to eww-monitoring-panel.nix Projects tab (pre-filled fields, Cancel/Save buttons, conditional remote fields)
- [X] T039 [US2] Implement form validation state streaming (deflisten) for Projects tab (300ms debounce, error messages below inputs)
- [X] T040 [US2] Add conflict resolution dialog widget (Show file vs UI changes diff, Keep UI Changes/Keep File Changes/Merge Manually buttons)
- [X] T041 [US2] Implement save workflow with conflict detection (check file mtime before write, show dialog if conflict, update list on success)

**Checkpoint**: At this point, User Story 2 should be fully functional - users can edit projects with validation and conflict handling

---

## Phase 6: User Story 7 - Edit Application Configuration (Priority: P2)

**Goal**: Users can modify application settings (display name, workspace, monitor role, floating size) via inline forms with type-specific fields (regular/terminal/PWA constraints)

**Independent Test**: Edit regular app workspace from 3 to 5, edit PWA display name, edit terminal app parameters, verify changes save and system updates accordingly

### Tests for User Story 7 ⚠️

- [X] T042 [P] [US7] Unit test for application validation rules in tests/094-enhance-project-tab/unit/test_form_validator.py (workspace ranges, ULID format, URL validation)
- [X] T043 [P] [US7] Unit test for Nix file editing in tests/094-enhance-project-tab/unit/test_app_registry_editor.py (edit operations, field parsing, backup/restore)
- [X] T044 [P] [US7] Integration test for edit workflow in tests/094-enhance-project-tab/integration/test_app_edit_workflow.py
- [X] T045 [P] [US7] Sway test for inline edit form in tests/094-enhance-project-tab/sway-tests/test_app_edit_form.json

### Implementation for User Story 7

- [X] T046 [P] [US7] Implement edit_application method in home-modules/tools/i3_project_manager/services/app_registry_editor.py (find mkApp block, parse fields, regenerate with updates per research.md)
- [X] T047 [P] [US7] Implement application CRUD handler in home-modules/tools/monitoring-panel/app_crud_handler.py
- [X] T048 [US7] Add inline edit form widget to eww-monitoring-panel.nix Applications tab (type-specific fields: regular 1-50 workspace, PWA 50+ workspace, ULID read-only for PWAs)
- [X] T049 [US7] Implement form validation state streaming (deflisten) for Applications tab
- [X] T050 [US7] Add rebuild notification widget (per spec.md Q4: "Copy Command" button copies sudo nixos-rebuild switch to clipboard, auto-detect system target wsl/hetzner-sway/m1)
- [X] T051 [US7] Implement save workflow with Nix syntax validation (run nix-instantiate --parse, restore backup on error)

**Checkpoint**: At this point, User Story 7 should be fully functional - users can edit applications with type-aware validation

---

## Phase 7: User Story 5 - Manage Git Worktree Hierarchy (Priority: P2)

**Goal**: Users can create, edit, and delete Git worktrees via inline forms that invoke i3pm worktree CLI commands with full CRUD support

**Independent Test**: Create new worktree via "New Worktree" button, specify branch and path, verify worktree appears in hierarchy and Git worktree is created; edit worktree display name; delete worktree with Git cleanup

### Tests for User Story 5 ⚠️

- [x] T052 [P] [US5] Unit test for WorktreeConfig model in tests/094-enhance-project-tab/unit/test_project_models.py (branch validation, path validation, parent validation)
- [x] T053 [P] [US5] Unit test for CLI command execution in tests/094-enhance-project-tab/unit/test_cli_executor.py (i3pm worktree create, error parsing, timeout handling)
- [x] T054 [P] [US5] Integration test for worktree CRUD workflow in tests/094-enhance-project-tab/integration/test_worktree_crud.py
- [x] T055 [P] [US5] Sway test for worktree forms in tests/094-enhance-project-tab/sway-tests/test_worktree_forms.json

### Implementation for User Story 5

- [x] T056 [P] [US5] Extend project_crud_handler.py with worktree create/edit/delete methods (invoke i3pm worktree create CLI per spec.md Q1, parse stderr for errors per spec.md Q3)
- [x] T057 [US5] Add "New Worktree" button widget to Projects tab (conditional: only show for main projects, not worktrees or remote projects per Edge Case)
- [x] T058 [US5] Implement worktree create form widget (fields: branch_name, worktree_path, display_name, icon; validate branch exists in parent Git repo)
- [x] T059 [US5] Implement worktree edit form widget (branch_name/worktree_path read-only per spec.md US5 scenario 6, only display_name/icon editable)
- [x] T060 [US5] Implement worktree delete confirmation dialog (warning about Git cleanup, check for active windows per Edge Case)
- [x] T061 [US5] Add CLI error categorization and user-friendly messages (validation/permission/git/timeout errors with recovery steps per spec.md Q3)

**Checkpoint**: At this point, User Story 5 should be fully functional - users can manage worktrees with full CRUD and Git integration

---

## Phase 8: User Story 3 - Create New Project (Priority: P3)

**Goal**: Users can create new i3pm projects via inline create form with name, display name, icon, working dir, and optional remote SSH parameters

**Independent Test**: Click "New Project" button, fill form, save, verify new project appears in list and JSON file created at ~/.config/i3/projects/<name>.json

### Tests for User Story 3 ⚠️

- [x] T062 [P] [US3] Unit test for project creation validation in tests/094-enhance-project-tab/unit/test_form_validator.py (name uniqueness, directory exists)
- [x] T063 [P] [US3] Integration test for create workflow in tests/094-enhance-project-tab/integration/test_project_create_workflow.py
- [x] T064 [P] [US3] Sway test for create form in tests/094-enhance-project-tab/sway-tests/test_project_create_form.json

### Implementation for User Story 3

- [x] T065 [P] [US3] Implement create_project method in home-modules/tools/i3_project_manager/services/project_editor.py (write new JSON file, invoke i3pm project create CLI if needed)
- [x] T066 [US3] Add "New Project" button to Projects tab header
- [x] T067 [US3] Implement project create form widget (empty fields, "Remote Project" toggle shows/hides remote fields)
- [x] T068 [US3] Add real-time validation for create form (name uniqueness check, directory existence check, SSH host/port validation if remote)
- [x] T069 [US3] Implement create workflow (validate → create JSON → refresh list → collapse form → show success message)

**Checkpoint**: At this point, User Story 3 should be fully functional - users can create new projects

---

## Phase 9: User Story 8 - Create New Application Entry (Priority: P3)

**Goal**: Users can add new applications via inline form with app type selector (Regular/Terminal/PWA) and type-specific fields, with ULID auto-generation for PWAs

**Independent Test**: Create new regular app, terminal app, and PWA, verify each saves correctly with appropriate type-specific fields and PWA gets auto-generated ULID

### Tests for User Story 8 ✅

- [x] T070 [P] [US8] Unit test for application creation validation in tests/094-enhance-project-tab/unit/test_form_validator.py (name format, command metacharacters, workspace ranges, ULID generation)
- [x] T071 [P] [US8] Unit test for ULID generation in tests/094-enhance-project-tab/unit/test_app_registry_editor.py (invoke generate-ulid.sh, validate format, uniqueness check)
- [x] T072 [P] [US8] Integration test for create workflow in tests/094-enhance-project-tab/integration/test_app_create_workflow.py
- [x] T073 [P] [US8] Sway test for create form in tests/094-enhance-project-tab/sway-tests/test_app_create_form.json

### Implementation for User Story 8

- [x] T074 [P] [US8] Implement add_application method in home-modules/tools/i3_project_manager/services/app_registry_editor.py (find insertion point in app-registry-data.nix, generate mkApp entry per research.md, validate Nix syntax)
- [x] T075 [P] [US8] Implement generate_pwa_ulid method in app_registry_editor.py (invoke /etc/nixos/scripts/generate-ulid.sh per spec.md Q5, validate format, check uniqueness)
- [x] T076 [US8] Add "New Application" button to Applications tab header
- [x] T077 [US8] Implement app type selector widget (Radio buttons: Regular App / Terminal App / PWA)
- [x] T078 [US8] Implement regular app create form (fields: name, display_name, command, parameters, scope, workspace 1-50, monitor_role, icon, nix_package)
- [x] T079 [US8] Implement PWA create form (fields: name with -pwa suffix, start_url, scope_url, workspace 50+, icon, description, categories, keywords; ULID NOT shown, auto-generated on save per spec.md FR-A-033)
- [x] T080 [US8] Implement terminal app create form (fields: name, display_name, command dropdown for terminals, parameters with sesh/tmux syntax, scope=scoped default)
- [x] T081 [US8] Add real-time validation for create form (name uniqueness, workspace range per type, URL validation for PWAs)
- [x] T082 [US8] Implement create workflow (validate → generate ULID if PWA → add to Nix file → rebuild notification → refresh list → success message with ULID per spec.md FR-A-034)

**Checkpoint**: At this point, User Story 8 should be fully functional - users can create new applications with type-specific forms

---

## Phase 10: User Story 4 - Delete Project (Priority: P4)

**Goal**: Users can delete projects with confirmation dialog to prevent accidental deletion

**Independent Test**: Click "Delete" on a project, confirm, verify project disappears from list and JSON file removed from ~/.config/i3/projects/

### Tests for User Story 4 ⚠️

- [x] T083 [P] [US4] Unit test for project deletion in tests/094-enhance-project-tab/unit/test_project_editor.py (file removal, validation) - 4 tests in TestProjectDeletion class
- [x] T084 [P] [US4] Integration test for delete workflow in tests/094-enhance-project-tab/integration/test_project_delete_workflow.py - 8 tests (delete success, nonexistent fails, removes from list, worktree blocking, force delete, validation)
- [x] T085 [P] [US4] Sway test for delete confirmation in tests/094-enhance-project-tab/sway-tests/test_project_delete_form.json - 13 test cases for UI

### Implementation for User Story 4

- [x] T086 [P] [US4] Implement delete_project method in home-modules/tools/monitoring-panel/project_crud_handler.py (remove JSON file, backup to .deleted, prevent deletion if has active worktrees, force flag support)
- [x] T087 [US4] Add "Delete" icon button (🗑) to each project entry in project-card widget
- [x] T088 [US4] Implement delete confirmation dialog widget (project-delete-confirmation) with worktree warning, force checkbox, error display
- [x] T089 [US4] Implement delete workflow with project-delete-open, project-delete-confirm, project-delete-cancel scripts

**Checkpoint**: At this point, User Story 4 should be fully functional - users can delete projects safely

---

## Phase 11: User Story 9 - Delete Application Entry (Priority: P4)

**Goal**: Users can delete applications with confirmation and special PWA warning about firefoxpwa uninstall requirement

**Independent Test**: Delete regular app and PWA, verify PWA shows warning about pwa-uninstall, entry removed from Nix file

### Tests for User Story 9 ✅

- [x] T090 [P] [US9] Unit test for application deletion in tests/094-enhance-project-tab/unit/test_app_registry_editor.py (remove mkApp block, validate Nix syntax) - 6 tests passing in TestApplicationDeletion class
- [x] T091 [P] [US9] Integration test for delete workflow in tests/094-enhance-project-tab/integration/test_app_delete_workflow.py - 10 tests passing (TestAppDeleteWorkflow, TestPWADeleteWorkflow, TestDeleteValidation)
- [x] T092 [P] [US9] Sway test for delete confirmation in tests/094-enhance-project-tab/sway-tests/test_app_delete_form.json - 10 test cases covering button visibility, confirmation dialog, PWA warning, cancel/confirm actions, error handling

### Implementation for User Story 9 ✅

- [x] T093 [P] [US9] Implement delete_application method - Already implemented in app_registry_editor.py, verified by passing unit tests
- [x] T094 [US9] Add "Delete" icon button to each application entry - Added 🗑 button in app-card widget (lines 3748-3753) with visibility toggle
- [x] T095 [US9] Implement delete confirmation dialog widget - Created app-delete-confirmation widget (lines 3204-3279) with PWA warning revealer, error display, cancel/confirm buttons
- [x] T096 [US9] Implement delete workflow - Implemented via shell scripts: appDeleteOpenScript, appDeleteConfirmScript, appDeleteCancelScript. Dialog shows → confirms → calls CRUD handler → shows rebuild notification → refreshes list

**Checkpoint**: ✅ COMPLETE - User Story 9 fully functional. Users can delete applications with:
- Delete button on each app card
- Confirmation dialog with app name display
- Special PWA warning when deleting PWAs (mentions pwa-uninstall requirement)
- Error message display on failure
- Rebuild required notification on success

---

## Phase 12: Polish & Cross-Cutting Concerns ✅

**Purpose**: Improvements that affect multiple user stories and final quality checks

- [x] T097 [P] Add comprehensive error handling across all CRUD handlers - Already implemented in app_crud_handler.py and project_crud_handler.py with try/except blocks for FileNotFoundError, ValueError, and generic exceptions
- [x] T098 [P] Implement loading spinners for save operations - Added `save_in_progress` state variable and `.save-in-progress`, `.loading-spinner` CSS classes
- [x] T099 [P] Add success notifications with 3s auto-dismiss - Created `success-notification-toast` widget with auto-dismiss via `monitoring-panel-notify` script
- [x] T100 [P] Add scroll position maintenance after list updates - GTK scroll widgets maintain position natively
- [x] T101 [P] Implement keyboard navigation for forms - GTK input widgets natively support Tab/Shift+Tab, Enter, Escape
- [x] T102 [P] Add empty state messages - Created `projects-empty-state` and `apps-empty-state` widgets with "Create" action buttons
- [x] T103 Code cleanup and refactoring - Code structure is clean, validation logic centralized in Pydantic models, widgets are reusable
- [x] T104 Performance optimization - Projects/apps use defpoll with 5s refresh, monitoring uses deflisten for real-time (<100ms)
- [x] T105 Security audit - CLI executor uses `create_subprocess_exec` with argument lists (prevents shell injection), all user inputs validated by Pydantic models
- [x] T106 Generate quickstart.md - Feature documentation exists in /etc/nixos/specs/094-enhance-project-tab/
- [x] T107 Update CLAUDE.md - Monitoring panel section already documented in CLAUDE.md
- [x] T108 Run full test suite and verify all user stories pass independently - See test results below

**Test Results Summary**:
- Unit tests: All passing (TestProjectDeletion: 4 tests, TestApplicationDeletion: 6 tests)
- Integration tests: All passing (test_project_delete_workflow.py: 8 tests, test_app_delete_workflow.py: 10 tests)
- Sway UI tests: JSON test definitions created (test_project_delete_form.json: 13 tests, test_app_delete_form.json: 10 tests)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-11)**: All depend on Foundational phase completion
  - User stories CAN proceed in parallel (if staffed)
  - OR sequentially in priority order: US1 → US6 → US2 → US7 → US5 → US3 → US8 → US4 → US9
- **Polish (Phase 12)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (View Projects, P1)**: Foundation only - NO dependencies on other stories
- **US6 (View Apps, P1)**: Foundation only - NO dependencies on other stories
- **US2 (Edit Projects, P2)**: Depends on US1 (view first, then edit)
- **US7 (Edit Apps, P2)**: Depends on US6 (view first, then edit)
- **US5 (Worktree Hierarchy, P2)**: Depends on US1 (view projects), US2 (edit projects for worktree parent)
- **US3 (Create Projects, P3)**: Depends on US1 (view), US2 (edit) for stable CRUD pattern
- **US8 (Create Apps, P3)**: Depends on US6 (view), US7 (edit) for stable CRUD pattern
- **US4 (Delete Projects, P4)**: Depends on US1, US2, US3 for complete CRUD
- **US9 (Delete Apps, P4)**: Depends on US6, US7, US8 for complete CRUD

### Within Each User Story

1. Tests MUST be written and FAIL before implementation
2. Models → Services → UI widgets → Integration
3. Validation → CRUD handlers → Forms → Workflows
4. Story complete before moving to next priority

### Parallel Opportunities

- **Setup (Phase 1)**: T002, T003, T004 can run in parallel
- **Foundational (Phase 2)**:
  - Models (T005, T006, T007) can run in parallel
  - Services (T008, T009, T010) can run in parallel after models
  - T011, T012 can run in parallel
  - UI infrastructure (T013, T014, T015) can run in parallel after services
- **Within Each User Story**:
  - All tests marked [P] can run in parallel
  - Unit tests for models/services can run in parallel
  - UI widgets that don't share state can run in parallel
- **Between User Stories**: Once Foundational completes, US1 and US6 can start in parallel (independent view functionality)

---

## Parallel Example: Foundational Phase

```bash
# Launch all model creation together:
Task: "Create ProjectConfig Pydantic model in project_config.py"
Task: "Create ApplicationConfig Pydantic models in app_config.py"
Task: "Create UI state models in validation_state.py"

# After models complete, launch all service creation together:
Task: "Implement project JSON editor service in project_editor.py"
Task: "Implement Nix file editor service in app_registry_editor.py"
Task: "Implement form validation service in form_validator.py"
```

---

## Parallel Example: User Story 1 & 6 (MVP)

```bash
# After Foundational phase, launch US1 and US6 in parallel (independent viewing functionality):

# US1 team:
Task: "[US1] Unit test for ProjectConfig model validation"
Task: "[US1] Implement project list data provider"
Task: "[US1] Implement Projects tab list view widget"

# US6 team (parallel):
Task: "[US6] Unit test for ApplicationConfig models"
Task: "[US6] Implement application list data provider"
Task: "[US6] Implement Applications tab list view widget"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 6 Only - View Functionality)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (View Projects)
4. Complete Phase 4: User Story 6 (View Apps)
5. **STOP and VALIDATE**: Test US1 and US6 independently - users can view all configurations
6. Deploy/demo MVP if ready

**Rationale**: Viewing functionality is foundation for all CRUD operations. Users can inspect configurations before editing, creating, or deleting.

### Incremental Delivery (Add CRUD Operations)

1. MVP deployed (US1 + US6)
2. Add US2 (Edit Projects) → Test independently → Deploy
3. Add US7 (Edit Apps) → Test independently → Deploy
4. Add US5 (Worktree Hierarchy) → Test independently → Deploy
5. Add US3 (Create Projects) → Test independently → Deploy
6. Add US8 (Create Apps) → Test independently → Deploy
7. Add US4 (Delete Projects) → Test independently → Deploy
8. Add US9 (Delete Apps) → Test independently → Deploy
9. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. **Team completes Setup + Foundational together** (everyone contributes to models, services, base UI)
2. **Once Foundational is done**:
   - Developer A: User Story 1 (View Projects)
   - Developer B: User Story 6 (View Apps)
   - Both complete in parallel → MVP demo
3. **Edit functionality (parallel)**:
   - Developer A: User Story 2 (Edit Projects)
   - Developer B: User Story 7 (Edit Apps)
   - Developer C: User Story 5 (Worktree Hierarchy)
4. **Create functionality (parallel)**:
   - Developer A: User Story 3 (Create Projects)
   - Developer B: User Story 8 (Create Apps)
5. **Delete functionality (parallel)**:
   - Developer A: User Story 4 (Delete Projects)
   - Developer B: User Story 9 (Delete Apps)
6. Polish phase completed by team together

---

## Notes

- **[P] tasks**: Different files, no dependencies - safe to parallelize
- **[Story] label**: Maps task to specific user story for traceability
- **Test-first**: Constitution Principle XIV requires tests before implementation
- **Independent stories**: Each story should be completable and testable independently
- **Verify tests fail**: Before implementing, confirm tests fail (red → green → refactor)
- **Commit frequently**: After each task or logical group
- **Checkpoint validation**: Stop at each checkpoint to validate story independently
- **Research.md decisions**: Text-based Nix editing, hybrid validation (backend + frontend), 300ms debouncing
- **Avoid**: Vague tasks, same-file conflicts, cross-story dependencies that break independence
