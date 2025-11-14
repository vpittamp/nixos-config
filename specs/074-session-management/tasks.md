# Tasks: Comprehensive Session Management

**Input**: Design documents from `/specs/074-session-management/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ipc-api.md, quickstart.md

**Tests**: Not explicitly requested in specification - focusing on implementation tasks only.

**Organization**: Tasks are grouped by user story (P1, P2, P3 priorities) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

All paths relative to `/etc/nixos/home-modules/desktop/i3-project-event-daemon/`:
- **Layout system**: `layout/` (models.py, capture.py, restore.py, persistence.py)
- **Services**: `services/` (focus_tracker.py, terminal_cwd.py, correlation.py)
- **Models**: `models/` (config.py for ProjectConfiguration)
- **State**: `state.py` (StateManager extensions)
- **Event handlers**: `handlers.py` (project switch logic)
- **IPC**: `ipc_server.py` (JSON-RPC endpoints)
- **Tests**: `tests/` (unit/, integration/, sway-tests/)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and baseline structure for session management

- [X] T001 Read existing layout/models.py to understand current WindowPlaceholder and LayoutSnapshot structure
- [X] T002 Read existing state.py to understand current StateManager implementation
- [X] T003 Read existing handlers.py to identify _switch_project() method location and signature
- [X] T004 [P] Review existing layout/capture.py to understand layout capture workflow
- [X] T005 [P] Review existing layout/restore.py to identify swallow mechanism at lines 475-505
- [X] T006 [P] Review existing ipc_server.py to understand JSON-RPC endpoint registration pattern

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data model extensions that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T007 Extend WindowPlaceholder model in layout/models.py with optional fields: cwd (Path), focused (bool), restoration_mark (str)
- [X] T008 Add field validator for cwd in WindowPlaceholder (must be absolute path if provided)
- [X] T009 Add is_terminal() method to WindowPlaceholder checking window_class against terminal list
- [X] T010 Add get_launch_env() method to WindowPlaceholder generating environment with restoration mark
- [X] T011 Extend LayoutSnapshot model in layout/models.py with optional field: focused_workspace (int, 1-70)
- [X] T012 Add model_validator to LayoutSnapshot ensuring focused_workspace exists in workspace_layouts
- [X] T013 Add is_auto_save() and get_timestamp() methods to LayoutSnapshot for auto-save detection
- [X] T014 [P] Create models/config.py with ProjectConfiguration Pydantic model (name, directory, auto_save, auto_restore, default_layout, max_auto_saves)
- [X] T015 [P] Add get_layouts_dir(), get_auto_save_name(), list_auto_saves(), get_latest_auto_save() methods to ProjectConfiguration

### Feature 057 Integration: Wrapper-Based Restoration

**Purpose**: Integrate with app registry wrapper system for consistent I3PM_* environment variable injection

- [X] T015A Extend WindowPlaceholder model in layout/models.py with optional field: app_registry_name (str)
- [X] T015B Create services/app_launcher.py with AppLauncher service class
- [X] T015C Implement __init__() in AppLauncher loading app registry JSON from ~/.config/i3/application-registry.json
- [X] T015D Implement launch_app() method with app name lookup, parameter substitution, environment injection
- [X] T015E Implement _build_command() helper for $PROJECT_DIR and $CWD substitution
- [X] T015F Implement _build_environment() helper for I3PM_APP_NAME, I3PM_PROJECT, I3PM_RESTORE_MARK injection
- [X] T015G Add get_app_info() and list_apps() helper methods for validation

**Checkpoint**: Foundation ready - Pydantic models extended with backward-compatible optional fields + AppLauncher service for wrapper-based restoration

---

## Phase 3: User Story 1 - Workspace Focus Restoration (Priority: P1) 🎯 MVP

**Goal**: Users can switch between projects and automatically return to their previously focused workspace

**Independent Test**: (1) Focus workspace 3 in Project A, (2) Switch to Project B, (3) Switch back to Project A, (4) Verify automatic focus on workspace 3

### Implementation for User Story 1

- [X] T016 [P] [US1] Extend DaemonState dataclass in models/legacy.py with project_focused_workspace: Dict[str, int] field
- [X] T017 [P] [US1] Add get_focused_workspace(project) method to DaemonState returning Optional[int]
- [X] T018 [P] [US1] Add set_focused_workspace(project, workspace_num) method to DaemonState
- [X] T019 [P] [US1] Extend DaemonState.to_json() method to serialize project_focused_workspace dictionary
- [X] T020 [P] [US1] Extend DaemonState.from_json() method to deserialize project_focused_workspace dictionary
- [X] T021 [US1] Create services/focus_tracker.py with FocusTracker service class
- [X] T022 [US1] Implement track_workspace_focus(project, workspace_num) method in FocusTracker updating DaemonState
- [X] T023 [US1] Implement get_project_focused_workspace(project) method in FocusTracker retrieving from DaemonState
- [X] T024 [US1] Implement persist_focus_state() method in FocusTracker writing to ~/.config/i3/project-focus-state.json
- [X] T025 [US1] Implement load_focus_state() method in FocusTracker reading from ~/.config/i3/project-focus-state.json
- [X] T026 [US1] Add workspace::focus event handler in event_handlers/workspace.py calling FocusTracker.track_workspace_focus()
- [X] T027 [US1] Modify _switch_project() in handlers.py to call FocusTracker.get_project_focused_workspace() and restore focus
- [X] T028 [US1] Add fallback logic in _switch_project() to focus workspace 1 if no focus history exists
- [X] T029 [US1] Add fallback logic to focus first workspace with project windows if previously focused workspace doesn't exist
- [X] T030 [US1] Add project.get_focused_workspace IPC method in ipc_server.py returning focused workspace for project
- [X] T031 [US1] Add project.set_focused_workspace IPC method in ipc_server.py allowing manual focus override

**Checkpoint**: Workspace focus restoration fully functional - project switches restore workspace context automatically

---

## Phase 4: User Story 2 - Terminal Working Directory Preservation (Priority: P1)

**Goal**: Terminal windows reopen in their original working directories when restoring sessions

**Independent Test**: (1) Open terminal in /etc/nixos/modules, (2) Save session, (3) Restore session, (4) Verify terminal opens in /etc/nixos/modules

### Implementation for User Story 2

- [X] T032 [US2] Create services/terminal_cwd.py with TerminalCwdTracker service class
- [X] T033 [US2] Implement get_terminal_cwd(pid) method in TerminalCwdTracker reading /proc/{pid}/cwd symlink
- [X] T034 [US2] Add TERMINAL_CLASSES constant in TerminalCwdTracker (ghostty, Alacritty, kitty, foot, WezTerm)
- [X] T035 [US2] Implement is_terminal_window(window_class) method in TerminalCwdTracker checking against TERMINAL_CLASSES
- [X] T036 [US2] Extend capture_layout() in layout/capture.py to call TerminalCwdTracker.get_terminal_cwd() for terminal windows
- [X] T037 [US2] Extend capture_layout() to populate WindowPlaceholder.cwd field for terminal windows
- [X] T037A [US2] Extend capture_layout() in layout/capture.py to read I3PM_APP_NAME from /proc/{pid}/environ and populate WindowPlaceholder.app_registry_name
- [X] T038 [US2] Implement get_launch_cwd(placeholder, project_config) method in TerminalCwdTracker with fallback chain
- [X] T039 [US2] Add fallback logic: original cwd → project root → $HOME in get_launch_cwd()
- [X] T040 [US2] Extend restore_layout() in layout/restore.py to use WindowPlaceholder.cwd for terminal launches
- [X] T041 [US2] Modify window launch subprocess.Popen calls to include cwd parameter for terminals

**Checkpoint**: Terminal working directory preservation complete - terminals restore to original directories

---

## Phase 5: User Story 3 - Sway-Compatible Window Restoration (Priority: P1)

**Goal**: Window restoration works on Sway using mark-based correlation instead of broken swallow mechanism

**Independent Test**: (1) Save layout on Sway with 3 windows, (2) Restore layout, (3) Verify windows appear with correct geometry and placement

**Architecture Note**: This phase integrates with Feature 057 (app registry wrapper system) to ensure consistent I3PM_* environment variable injection during restoration. Windows are launched via AppLauncher service (T015A-T015G) which replicates the wrapper behavior used by Walker/Rofi, ensuring:
- PWAs launch via `launch-pwa-by-name <ULID>` wrapper
- Terminal apps use proper ghostty wrapper with parameters
- All windows receive I3PM_APP_NAME for deterministic correlation
- Fallback to direct launch for unknown/manual windows

### Implementation for User Story 3

- [X] T042 [P] [US3] Create layout/correlation.py with RestoreCorrelation Pydantic model (from data-model.md)
- [X] T043 [P] [US3] Add CorrelationStatus enum (PENDING, MATCHED, TIMEOUT, FAILED) to correlation.py
- [X] T044 [P] [US3] Add mark_matched(), mark_timeout(), mark_failed() methods to RestoreCorrelation
- [X] T045 [P] [US3] Add elapsed_seconds and is_complete properties to RestoreCorrelation
- [X] T046 [US3] Create MarkBasedCorrelator service class in layout/correlation.py
- [X] T047 [US3] Implement generate_restoration_mark() method returning unique i3pm-restore-{8-char-hex} mark
- [X] T048 [US3] Implement inject_mark_env(placeholder, project) method adding I3PM_RESTORE_MARK to environment
- [X] T049 [US3] Implement wait_for_window_with_mark(mark, timeout) async method polling Sway tree
- [X] T050 [US3] Implement apply_window_geometry(window_id, placeholder) method applying saved geometry
- [X] T051 [US3] Implement remove_restoration_mark(window_id, mark) method cleaning up temporary mark
- [X] T052 [US3] Implement correlate_window(placeholder, project, timeout) orchestration method
- [X] T053 [US3] Add correlation tracking with RestoreCorrelation model instances during restoration
- [X] T054 [US3] Replace _swallow_window() method in layout/restore.py (lines 475-505) with mark-based correlation
- [X] T055 [US3] Modify restore_workspace() in layout/restore.py to use MarkBasedCorrelator for all windows
- [X] T055A [US3] Initialize AppLauncher in restore.py __init__() method
- [X] T055B [US3] Modify _restore_window() to use AppLauncher.launch_app() when WindowPlaceholder.app_registry_name is present
- [X] T055C [US3] Add fallback to direct launch for windows without app_registry_name (backward compatibility)
- [X] T056 [US3] Add timeout handling logging failed correlations and continuing with remaining windows
- [X] T057 [US3] Add correlation statistics tracking (windows_launched, windows_matched, windows_timeout, windows_failed)
- [X] T058 [US3] Add layout.restore IPC method in ipc_server.py returning correlation statistics
- [X] T059 [US3] Add layout.capture IPC method in ipc_server.py with workspace/window counts

**Checkpoint**: Mark-based correlation complete - Sway window restoration functional with >95% accuracy target

---

## Phase 6: User Story 4 - Focused Window Restoration (Priority: P2)

**Goal**: Each workspace focuses the correct window (not arbitrary) when restoring sessions

**Independent Test**: (1) Focus VS Code on workspace 2, (2) Save session, (3) Restore session, (4) Verify VS Code has focus on workspace 2

### Implementation for User Story 4

- [ ] T060 [P] [US4] Extend DaemonState dataclass with workspace_focused_window: Dict[int, int] field
- [ ] T061 [P] [US4] Add get_focused_window(workspace_num) method to DaemonState
- [ ] T062 [P] [US4] Add set_focused_window(workspace_num, window_id) method to DaemonState
- [ ] T063 [P] [US4] Extend DaemonState.to_json() to serialize workspace_focused_window dictionary
- [ ] T064 [P] [US4] Extend DaemonState.from_json() to deserialize workspace_focused_window dictionary
- [ ] T065 [US4] Extend FocusTracker service in services/focus_tracker.py with track_window_focus() method
- [ ] T066 [US4] Add window::focus event handler in event_handlers/window.py calling FocusTracker.track_window_focus()
- [ ] T067 [US4] Extend capture_layout() in layout/capture.py to detect focused window per workspace
- [ ] T068 [US4] Set WindowPlaceholder.focused=True for focused window in each workspace during capture
- [ ] T069 [US4] Implement restore_workspace_focus() in layout/restore.py focusing window with focused=True
- [ ] T070 [US4] Add fallback logic to focus first available window if focused window doesn't exist
- [ ] T071 [US4] Call restore_workspace_focus() after all windows in workspace are correlated

**Checkpoint**: Focused window restoration complete - each workspace focuses correct window automatically

---

## Phase 7: User Story 5 - Automatic Session Save (Priority: P2)

**Goal**: System automatically saves layout when switching away from a project (no manual save needed)

**Independent Test**: (1) Arrange windows in Project A, (2) Switch to Project B without manual save, (3) Verify auto-saved layout exists

### Implementation for User Story 5

- [ ] T072 [P] [US5] Create layout/auto_save.py with AutoSaveManager service class
- [ ] T073 [P] [US5] Implement should_auto_save(project) method checking ProjectConfiguration.auto_save
- [ ] T074 [P] [US5] Implement generate_auto_save_name() method returning auto-YYYYMMDD-HHMMSS format
- [ ] T075 [P] [US5] Implement prune_old_auto_saves(project, max_count) method deleting oldest auto-saves
- [ ] T076 [P] [US5] Ensure prune_old_auto_saves() only deletes layouts with names starting with "auto-"
- [ ] T077 [US5] Implement auto_save_on_switch(old_project) method capturing and saving layout
- [ ] T078 [US5] Modify _switch_project() in handlers.py to call AutoSaveManager.auto_save_on_switch() before switching
- [ ] T079 [US5] Add auto-save capture before project filtering logic to capture current state
- [ ] T080 [US5] Add async execution for auto-save to avoid blocking project switch (<200ms target)
- [ ] T081 [US5] Emit layout.auto_saved event notification via IPC server after successful auto-save
- [ ] T082 [US5] Add layout.list IPC method in ipc_server.py listing saved layouts with metadata
- [ ] T083 [US5] Add layout.delete IPC method in ipc_server.py for manual layout cleanup
- [ ] T084 [US5] Add include_auto_saves parameter to layout.list for filtering auto-saves
- [ ] T085 [US5] Add config.get IPC method in ipc_server.py returning ProjectConfiguration for project
- [ ] T086 [US5] Add config.set IPC method in ipc_server.py for runtime configuration updates

**Checkpoint**: Auto-save complete - layouts automatically captured on project switch with pruning

---

## Phase 8: User Story 6 - Automatic Session Restore (Priority: P3)

**Goal**: Automatically restore saved layout when activating a project (if enabled)

**Independent Test**: (1) Save layout for Project A with auto-restore enabled, (2) Switch to Project B, (3) Switch back to Project A, (4) Verify layout auto-restores

### Implementation for User Story 6

- [ ] T087 [US6] Create layout/auto_restore.py with AutoRestoreManager service class
- [ ] T088 [US6] Implement should_auto_restore(project) method checking ProjectConfiguration.auto_restore
- [ ] T089 [US6] Implement get_restore_layout_name(project_config) method resolving default_layout or latest auto-save
- [ ] T090 [US6] Implement auto_restore_on_activate(project) method restoring layout if enabled
- [ ] T091 [US6] Add graceful handling for missing layout (no error, just info log)
- [ ] T092 [US6] Modify _switch_project() in handlers.py to call AutoRestoreManager.auto_restore_on_activate() after switching
- [ ] T093 [US6] Add auto-restore after workspace focus restoration to maintain correct workspace context
- [ ] T094 [US6] Emit layout.auto_restored event notification via IPC server after successful restore
- [ ] T095 [US6] Add restoration cancellation logic if another project switch occurs during restore

**Checkpoint**: Auto-restore complete - layouts automatically restore on project activation when enabled

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Integration, documentation, and validation across all user stories

- [ ] T096 [P] Add state.get IPC method in ipc_server.py returning complete daemon state with focus dictionaries
- [ ] T097 [P] Add daemon.version IPC method for API version negotiation (contracts/ipc-api.md:559-578)
- [ ] T098 [P] Add workspace.focus_restored event notification emission after focus restoration
- [ ] T099 [P] Update StateManager in state.py to initialize FocusTracker, TerminalCwdTracker, AutoSaveManager, AutoRestoreManager
- [ ] T100 [P] Add error handling for all IPC methods with proper error codes (1001-1009 from contracts)
- [ ] T101 [P] Add performance logging for workspace focus switch (<100ms target)
- [ ] T102 [P] Add performance logging for auto-save capture (<200ms target)
- [ ] T103 [P] Add performance logging for mark-based correlation (<500ms typical target)
- [ ] T104 Add integration between all services: FocusTracker + AutoSaveManager + AutoRestoreManager coordination
- [ ] T105 Add persistence of focus state on daemon shutdown for cross-restart recovery
- [ ] T106 Add loading of focus state on daemon startup from JSON files
- [ ] T107 Test complete workflow: Project A → ws3 → terminal in /etc/nixos → switch to B → auto-save → switch back to A → verify focus + cwd + windows
- [ ] T108 Validate backward compatibility: load existing layout JSON files without new fields
- [ ] T109 Validate quickstart.md examples work end-to-end with implemented features
- [ ] T110 Run manual validation on M1 Mac (Sway/Wayland primary target environment)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - workspace focus restoration
- **User Story 2 (Phase 4)**: Depends on Foundational - terminal cwd tracking
- **User Story 3 (Phase 5)**: Depends on Foundational - mark-based correlation
- **User Story 4 (Phase 6)**: Depends on Foundational + US1 (workspace focus) - focused window restoration
- **User Story 5 (Phase 7)**: Depends on Foundational + US2 (cwd) + US3 (correlation) - auto-save
- **User Story 6 (Phase 8)**: Depends on Foundational + US3 (correlation) + US5 (auto-save) - auto-restore
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Independent - can start after Foundational
- **User Story 2 (P1)**: Independent - can start after Foundational
- **User Story 3 (P1)**: Independent - can start after Foundational
- **User Story 4 (P2)**: Depends on US1 (needs workspace focus tracking)
- **User Story 5 (P2)**: Depends on US2 + US3 (needs cwd and correlation for complete capture)
- **User Story 6 (P3)**: Depends on US3 + US5 (needs correlation and auto-save)

### Within Each User Story

- Foundational models MUST be complete before any story begins
- Within stories: Models → Services → Integration → IPC
- P1 stories (US1, US2, US3) can proceed in parallel after Foundational
- P2 stories (US4, US5) can start once their dependencies are met
- P3 stories (US6) can start once P2 dependencies are met

### Parallel Opportunities

**Phase 2 (Foundational)**:
- T007-T013 (WindowPlaceholder + LayoutSnapshot extensions) in parallel
- T014-T015 (ProjectConfiguration model) in parallel with above

**Phase 3 (US1 - Workspace Focus)**:
- T016-T020 (DaemonState extensions) all in parallel
- T021-T025 (FocusTracker service) sequential after state model ready
- T030-T031 (IPC methods) in parallel after service ready

**Phase 4 (US2 - Terminal CWD)**:
- T032-T035 (TerminalCwdTracker core) all in parallel
- T036-T037 (capture integration) sequential after tracker ready
- T038-T039 (fallback logic) in parallel
- T040-T041 (restore integration) sequential

**Phase 5 (US3 - Mark Correlation)**:
- T042-T045 (RestoreCorrelation model) all in parallel
- T046-T052 (MarkBasedCorrelator service) sequential after model
- T053-T059 (restore integration + IPC) sequential after service

**Phase 6 (US4 - Focused Window)**:
- T060-T064 (DaemonState extensions) all in parallel
- T065-T066 (focus tracking) sequential after state
- T067-T071 (capture + restore integration) sequential

**Phase 7 (US5 - Auto-Save)**:
- T072-T076 (AutoSaveManager service) all in parallel
- T077-T081 (integration) sequential after service
- T082-T086 (IPC methods) all in parallel after integration

**Phase 8 (US6 - Auto-Restore)**:
- T087-T091 (AutoRestoreManager) all in parallel
- T092-T095 (integration) sequential after service

**Phase 9 (Polish)**:
- T096-T103 (IPC + logging) all in parallel
- T104-T110 (integration + validation) sequential

---

## Parallel Example: Foundational Phase

```bash
# Launch all Pydantic model extensions together:
Task T007: "Extend WindowPlaceholder with cwd, focused, restoration_mark"
Task T008: "Add field validator for cwd"
Task T009: "Add is_terminal() method"
Task T010: "Add get_launch_env() method"
Task T011: "Extend LayoutSnapshot with focused_workspace"
Task T012: "Add model_validator to LayoutSnapshot"
Task T013: "Add is_auto_save() and get_timestamp() methods"
Task T014: "Create ProjectConfiguration model"
Task T015: "Add helper methods to ProjectConfiguration"
```

---

## Parallel Example: User Story 1 (Workspace Focus)

```bash
# Launch all DaemonState extensions together:
Task T016: "Add project_focused_workspace field"
Task T017: "Add get_focused_workspace() method"
Task T018: "Add set_focused_workspace() method"
Task T019: "Extend to_json()"
Task T020: "Extend from_json()"

# Then launch IPC methods together (after service ready):
Task T030: "Add project.get_focused_workspace IPC method"
Task T031: "Add project.set_focused_workspace IPC method"
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only - All P1)

1. Complete Phase 1: Setup (T001-T006)
2. Complete Phase 2: Foundational (T007-T015) - CRITICAL
3. Complete Phase 3: User Story 1 - Workspace Focus (T016-T031)
4. Complete Phase 4: User Story 2 - Terminal CWD (T032-T041)
5. Complete Phase 5: User Story 3 - Mark Correlation (T042-T059)
6. **STOP and VALIDATE**: Test all P1 features work together
7. Deploy/demo if ready - core session management functional

### Incremental Delivery

1. Foundation (Phases 1-2) → All models ready
2. Add US1 → Test workspace focus restoration independently
3. Add US2 → Test terminal cwd preservation independently
4. Add US3 → Test Sway window correlation independently
5. **MVP CHECKPOINT** - All P1 features working
6. Add US4 → Test focused window restoration
7. Add US5 → Test auto-save functionality
8. Add US6 → Test auto-restore functionality
9. Polish → Integration + validation

### Parallel Team Strategy

With multiple developers after Foundational phase:

**Phase 3-5 (P1 Stories) - Can proceed in parallel**:
- Developer A: User Story 1 (Workspace Focus) - T016-T031
- Developer B: User Story 2 (Terminal CWD) - T032-T041
- Developer C: User Story 3 (Mark Correlation) - T042-T059

**Phase 6-8 (P2/P3 Stories) - Sequential due to dependencies**:
- After US1: Start US4 (Focused Window)
- After US2+US3: Start US5 (Auto-Save)
- After US3+US5: Start US6 (Auto-Restore)

---

## Notes

- [P] tasks can run in parallel within their phase (different files, no dependencies)
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable (acceptance criteria in spec.md)
- Foundational phase (T007-T015) must complete before ANY user story begins
- P1 stories (US1-US3) are MVP - deliver immediate value independently
- Verify backward compatibility throughout (T108)
- Test on target environment (M1 Mac with Sway) at checkpoints (T110)
- Focus on performance targets: <100ms workspace switch, <200ms auto-save, <30s correlation timeout
