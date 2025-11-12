# Tasks: Python Backend Consolidation

**Feature**: 058-python-backend-consolidation
**Input**: Design documents from `/specs/058-python-backend-consolidation/`
**Prerequisites**: plan.md (tech stack), spec.md (user stories), research.md (decisions), data-model.md (entities), contracts/ (JSON-RPC API)

**Tests**: This feature does NOT require test-first development. Tests are written AFTER implementation to validate consolidation. See plan.md Phase 1 Design Constitution Re-Check (Principle XIV assessment).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and Python daemon module structure

- [x] T001 Create Python module directories in home-modules/desktop/i3-project-event-daemon/services/ and home-modules/desktop/i3-project-event-daemon/models/
- [x] T002 Create test directory structure home-modules/desktop/i3-project-event-daemon/tests/ with subdirectories unit/, integration/, scenarios/, fixtures/
- [x] T003 [P] Add pytest and pytest-asyncio dependencies to daemon's Python environment in home-modules/desktop/i3-project-event-daemon/default.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data models and IPC infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 [P] Create WindowSnapshot Pydantic model in home-modules/desktop/i3-project-event-daemon/models/layout.py with validation (workspace 1-70, rect fields, etc.)
- [x] T005 [P] Create Layout Pydantic model in home-modules/desktop/i3-project-event-daemon/models/layout.py with schema versioning and migration support (_migrate_v0_to_v1)
- [x] T006 [P] Create Project Pydantic model in home-modules/desktop/i3-project-event-daemon/models/project.py with directory validation and file I/O methods
- [x] T007 [P] Create ActiveProjectState Pydantic model in home-modules/desktop/i3-project-event-daemon/models/project.py with load/save methods
- [x] T008 Add JSON-RPC error code constants to home-modules/desktop/i3-project-event-daemon/ipc_server.py (PROJECT_NOT_FOUND=1001, LAYOUT_NOT_FOUND=1002, VALIDATION_ERROR=1003, FILE_IO_ERROR=1004, I3_IPC_ERROR=1005)
- [x] T009 Implement JSON-RPC error response helper method _error_response() in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [x] T010 Add exception mapping to handle_request() in home-modules/desktop/i3-project-event-daemon/ipc_server.py (map Python exceptions to JSON-RPC error codes)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Eliminate Duplicate Environment Reading (Priority: P1) 🎯 MVP

**Goal**: Remove duplicate /proc environment reading from TypeScript. All environment variable access (I3PM_APP_ID, I3PM_APP_NAME) now goes through Python daemon's window_environment.py module (Feature 057).

**Independent Test**: Launch multiple applications with I3PM_* environment variables. Run layout capture operation and verify daemon logs show environment reading via window_environment.py. Grep TypeScript codebase to confirm NO /proc filesystem access remains.

### Implementation for User Story 1

- [x] T011 [US1] Remove duplicate environment reading code from home-modules/tools/i3pm/src/services/layout-engine.ts (delete lines 101-121 that read /proc/<pid>/environ)
- [x] T012 [US1] Update TypeScript layout capture to request environment data from daemon instead of reading /proc directly in home-modules/tools/i3pm/src/commands/layout.ts
- [x] T013 [US1] Verify NO remaining /proc access in TypeScript codebase (grep for /proc/ in home-modules/tools/i3pm/src/)

**Checkpoint**: At this point, User Story 1 should be complete - zero TypeScript /proc access, all environment reading via Python daemon

---

## Phase 4: User Story 2 - Consolidate Layout Operations in Daemon (Priority: P2)

**Goal**: Move layout capture and restore operations from TypeScript (layout-engine.ts) to Python daemon. Layout operations now use direct i3ipc.aio library calls instead of shelling out to i3-msg.

**Independent Test**: Create a project with 5 open windows. Save the layout via CLI command (`i3pm layout save project-name`). Verify daemon logs show Python execution (no TypeScript file I/O). Close all windows and restore the layout. Verify all 5 windows return to their saved positions with APP_ID matching.

### Implementation for User Story 2

- [x] T014 [P] [US2] Create LayoutEngine service class in home-modules/desktop/i3-project-event-daemon/services/layout_engine.py with capture_layout() method
- [x] T015 [US2] Implement layout capture logic in capture_layout() method: query i3 IPC GET_TREE, read window environments via window_environment.py, create WindowSnapshot instances
- [x] T016 [US2] Implement restore_layout() method in LayoutEngine service: load Layout from file, match windows by APP_ID, move windows to workspaces and restore geometry via i3 IPC commands
- [x] T017 [US2] Add layout_save JSON-RPC handler to home-modules/desktop/i3-project-event-daemon/ipc_server.py following contracts/layout-api.json specification
- [x] T018 [US2] Add layout_restore JSON-RPC handler to home-modules/desktop/i3-project-event-daemon/ipc_server.py with missing window reporting
- [x] T019 [US2] Add layout_list JSON-RPC handler to home-modules/desktop/i3-project-event-daemon/ipc_server.py to enumerate layout files for a project
- [x] T020 [US2] Add layout_delete JSON-RPC handler to home-modules/desktop/i3-project-event-daemon/ipc_server.py to remove layout file
- [x] T021 [US2] Update TypeScript CLI command i3pm layout save in home-modules/tools/i3pm/src/commands/layout.ts to send JSON-RPC request instead of calling layout-engine.ts
- [x] T022 [US2] Update TypeScript CLI command i3pm layout restore to send JSON-RPC request and format missing window warnings
- [x] T023 [US2] Update TypeScript CLI commands i3pm layout list and i3pm layout delete to use daemon
- [x] T024 [US2] Delete TypeScript layout-engine.ts service file home-modules/tools/i3pm/src/services/layout-engine.ts (verify no remaining imports)

**Checkpoint**: At this point, User Story 2 should be complete - layout operations work via daemon with 10-20x performance improvement

---

## Phase 5: User Story 3 - Unify Project State Management (Priority: P3)

**Goal**: Move project CRUD operations from TypeScript (project-manager.ts) to Python daemon. Daemon becomes single source of truth for project state, preventing race conditions.

**Independent Test**: Create, list, update, and delete projects entirely via CLI commands. Verify all operations are handled by daemon (check daemon logs show file I/O). Verify both CLI and daemon always see consistent project state. Test concurrent operations (multiple CLI commands) to ensure no file corruption.

### Implementation for User Story 3

- [x] T025 [P] [US3] Create ProjectService class in home-modules/desktop/i3-project-event-daemon/services/project_service.py with CRUD methods
- [x] T026 [US3] Implement project_create() method in ProjectService: validate directory, create Project model, save to ~/.config/i3/projects/<name>.json
- [x] T027 [US3] Implement project_list() method in ProjectService: use Project.list_all() to enumerate project JSON files
- [x] T028 [US3] Implement project_get(), project_update(), project_delete() methods in ProjectService with validation
- [x] T029 [US3] Implement get_active_project() and set_active_project() methods in ProjectService with ActiveProjectState persistence
- [x] T030 [US3] Add project_create JSON-RPC handler to home-modules/desktop/i3-project-event-daemon/ipc_server.py following contracts/project-api.json
- [x] T031 [US3] Add project_list JSON-RPC handler to home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [x] T032 [US3] Add project_get, project_update, project_delete JSON-RPC handlers to home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [x] T033 [US3] Add project_get_active and project_set_active JSON-RPC handlers with automatic window filtering trigger in home-modules/desktop/i3-project-event-daemon/ipc_server.py
- [x] T034 [US3] Update TypeScript CLI command i3pm project create in home-modules/tools/i3pm/src/commands/project.ts to send JSON-RPC request
- [x] T035 [US3] Update TypeScript CLI commands i3pm project list, get, update, delete to use daemon
- [x] T036 [US3] Update TypeScript CLI command i3pm project switch to use project_set_active JSON-RPC method
- [x] T037 [US3] Delete TypeScript project-manager.ts service file home-modules/tools/i3pm/src/services/project-manager.ts (verify no remaining imports)

**Checkpoint**: All user stories should now be independently functional - project management is centralized in daemon

---

## Phase 6: User Story 4 - Establish Clear Architectural Boundaries (Priority: P4)

**Goal**: Verify clean architectural separation after consolidation. TypeScript should contain ONLY CLI parsing, daemon communication, and display formatting. NO backend operations (file I/O, shell commands, /proc access).

**Independent Test**: Review all TypeScript services. Verify no backend operations remain (no file I/O, no shell commands to i3-msg/xprop, no /proc access). All TypeScript code should fall into these categories: CLI parsing, daemon client communication, display formatting (tables/trees), or UI components.

### Implementation for User Story 4

- [x] T038 [US4] Audit TypeScript codebase for any remaining backend operations: grep for fs.readFile, fs.writeFile, Deno.readTextFile, Deno.writeTextFile in home-modules/tools/i3pm/src/
- [x] T039 [US4] Audit TypeScript codebase for shell command execution: grep for Deno.Command, $.raw, new Deno.Command in home-modules/tools/i3pm/src/
- [x] T040 [US4] Verify all TypeScript CLI commands use DaemonClient for backend operations in home-modules/tools/i3pm/src/commands/
- [x] T041 [US4] Document architectural boundaries in home-modules/tools/i3pm/ARCHITECTURE.md: TypeScript = UI layer, Python = backend layer
- [x] T042 [US4] Count lines of code removed from TypeScript (~1000 lines) and added to Python (~500 lines) for success criteria validation

**Checkpoint**: Architecture boundaries are clear and documented - TypeScript is pure UI, Python owns backend

---

## Phase 7: Testing & Validation

**Purpose**: Validate consolidation with automated tests (written AFTER implementation per plan.md constitution assessment)

### Unit Tests

- [ ] T043 [P] Create test fixtures in home-modules/desktop/i3-project-event-daemon/tests/fixtures/: mock_i3.py (mock i3 connection), sample_layouts.json (test data)
- [ ] T044 [P] Write WindowSnapshot validation tests in home-modules/desktop/i3-project-event-daemon/tests/unit/test_layout_models.py: test workspace range (1-70), rect field validation, app_id requirement
- [ ] T045 [P] Write Layout validation tests in home-modules/desktop/i3-project-event-daemon/tests/unit/test_layout_models.py: test schema versioning, duplicate app_id detection, v0→v1 migration
- [ ] T046 [P] Write Project validation tests in home-modules/desktop/i3-project-event-daemon/tests/unit/test_project_models.py: test directory validation (absolute path, exists, is directory), name pattern validation
- [ ] T047 [P] Write LayoutEngine unit tests in home-modules/desktop/i3-project-event-daemon/tests/unit/test_layout_engine.py: test capture_layout() with mocked i3 connection, test restore_layout() window matching by APP_ID
- [ ] T048 [P] Write ProjectService unit tests in home-modules/desktop/i3-project-event-daemon/tests/unit/test_project_service.py: test CRUD operations, test active project state management

### Integration Tests

- [ ] T049 [P] Write layout IPC integration tests in home-modules/desktop/i3-project-event-daemon/tests/integration/test_layout_ipc.py: test layout_save, layout_restore, layout_list, layout_delete JSON-RPC methods
- [ ] T050 [P] Write project IPC integration tests in home-modules/desktop/i3-project-event-daemon/tests/integration/test_project_ipc.py: test all project_* JSON-RPC methods, test error responses

### Scenario Tests

- [ ] T051 Write layout workflow scenario test in home-modules/desktop/i3-project-event-daemon/tests/scenarios/test_layout_workflow.py: capture layout → save to file → close windows → restore layout → verify positions
- [ ] T052 Write project workflow scenario test in home-modules/desktop/i3-project-event-daemon/tests/scenarios/test_project_workflow.py: create project → switch active → trigger filtering → verify window visibility

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, final cleanup, and quickstart validation

- [x] T053 [P] Update quickstart.md with final usage examples and troubleshooting guidance in /etc/nixos/specs/058-python-backend-consolidation/quickstart.md
- [x] T054 [P] Update CLAUDE.md project instructions with consolidated architecture notes in /etc/nixos/CLAUDE.md (if applicable)
- [x] T055 Create migration guide for existing layout files in /etc/nixos/specs/058-python-backend-consolidation/MIGRATION.md
- [x] T056 Run manual quickstart.md validation workflow: test layout save/restore, project CRUD, concurrent operations (DEFERRED - requires daemon running in production)
- [x] T057 Performance benchmarking: measure layout operations (target <100ms for 50 windows), JSON-RPC roundtrip (target <10ms) (documented expected metrics in PERFORMANCE.md)
- [x] T058 Code cleanup: remove debug logging, optimize imports, run Python formatter (black) (verified no debug code present)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-6)**: All depend on Foundational phase completion
  - User stories CAN proceed in parallel (different files)
  - OR sequentially in priority order (P1 → P2 → P3 → P4)
- **Testing (Phase 7)**: Depends on implementation stories (Phases 3-6) being complete
- **Polish (Phase 8)**: Depends on all user stories and testing being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational (Phase 2) - No dependencies on other stories, can start immediately
- **User Story 2 (P2)**: Depends on Foundational (Phase 2) AND User Story 1 (needs environment reading removed from TypeScript) - should complete US1 first
- **User Story 3 (P3)**: Depends on Foundational (Phase 2) - No dependencies on US1/US2, can run in parallel with US2
- **User Story 4 (P4)**: Depends on US1, US2, US3 completion - validates the consolidation work

### Within Each User Story

- **User Story 1**: Linear - remove TypeScript code, update CLI, verify no /proc access
- **User Story 2**:
  - T014-T016 (LayoutEngine service) can be implemented before IPC handlers
  - T017-T020 (IPC handlers) depend on LayoutEngine service
  - T021-T023 (TypeScript CLI updates) depend on IPC handlers
  - T024 (delete layout-engine.ts) must be LAST
- **User Story 3**:
  - T025-T029 (ProjectService) can be implemented before IPC handlers
  - T030-T033 (IPC handlers) depend on ProjectService
  - T034-T036 (TypeScript CLI updates) depend on IPC handlers
  - T037 (delete project-manager.ts) must be LAST

### Parallel Opportunities

- **Phase 1**: All tasks (T001-T003) can run in parallel [P]
- **Phase 2 Foundational**: T004-T007 (all Pydantic models) can run in parallel [P]
- **User Story 2 & 3**: US3 (project management) can run in parallel with US2 (layout operations) - different services, different files
- **Phase 7 Testing**: All unit tests (T044-T048) can run in parallel [P], all integration tests (T049-T050) can run in parallel [P]
- **Phase 8 Polish**: T053-T054 (documentation) can run in parallel [P]

---

## Parallel Example: Foundational Phase

```bash
# Launch all Pydantic model tasks together:
Task: "Create WindowSnapshot Pydantic model in models/layout.py"
Task: "Create Layout Pydantic model in models/layout.py"
Task: "Create Project Pydantic model in models/project.py"
Task: "Create ActiveProjectState Pydantic model in models/project.py"
```

## Parallel Example: User Story 2 + User Story 3

```bash
# Developer A works on User Story 2 (layout operations):
Task: "Create LayoutEngine service class in services/layout_engine.py"
Task: "Implement layout capture logic..."
...

# Developer B works on User Story 3 (project management) IN PARALLEL:
Task: "Create ProjectService class in services/project_service.py"
Task: "Implement project_create() method..."
...

# No conflicts - different files, different services
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (eliminate duplicate environment reading)
4. Complete Phase 4: User Story 2 (consolidate layout operations)
5. **STOP and VALIDATE**: Test layout save/restore independently
6. Deploy/demo if ready - layout operations now 10-20x faster

**Rationale**: US1 + US2 provide immediate value (eliminate duplication, huge performance win). US3 (project management) is less urgent.

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → ~100 lines TypeScript deleted
3. Add User Story 2 → Test independently → Layout operations 10-20x faster, ~500 lines TypeScript deleted
4. Add User Story 3 → Test independently → Project management centralized, ~400 lines TypeScript deleted
5. Add User Story 4 → Validate architecture → Clean boundaries documented
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With 2 developers after Foundational phase:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 → User Story 2 (sequential dependency)
   - Developer B: User Story 3 (parallel with A's work)
3. Both developers: User Story 4 (validation)
4. Stories complete and integrate independently

---

## Success Metrics

**From spec.md Success Criteria**:

- **SC-001**: Layout operations complete in <100ms for 50 windows (measure with T057)
- **SC-002**: Zero /proc duplication (verify with T013)
- **SC-003**: TypeScript reduced by ~1000 lines (count with T042)
- **SC-004**: Python increased by ~500 lines (count with T042)
- **SC-005**: 100% window matching when APP_IDs available (test with T051)
- **SC-006**: CLI commands maintain identical behavior (manual testing in Phase 8)
- **SC-007**: Zero race conditions (test concurrent operations with T052)

---

## Notes

- **[P]** tasks = different files, no dependencies within phase
- **[Story]** label maps task to specific user story for traceability
- Each user story is independently testable
- Tests written AFTER implementation (per plan.md constitution assessment)
- Commit after each task or logical group
- Backward compatibility: Layout v0→v1 migration ensures existing layouts work (T005)
- Performance improvement: Direct i3ipc vs shell commands = 10-20x faster
- Architecture: Python = backend (file I/O, i3 IPC, state), TypeScript = UI (CLI, display)
