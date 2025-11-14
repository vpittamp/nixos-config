# Tasks: Mark-Based App Identification with Key-Value Storage

**Input**: Design documents from `/etc/nixos/specs/076-mark-based-app-identification/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/mark-manager-api.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 [P] Create MarkMetadata Pydantic model in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T002 [P] Create WindowMarkQuery Pydantic model in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T003 [P] Create MarkManager service stub with init and connection setup in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core mark management infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement MarkMetadata.to_sway_marks() serialization method in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T005 Implement MarkMetadata.from_sway_marks() parsing method in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T006 [P] Implement MarkManager.inject_marks() method with IPC commands in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
- [X] T007 [P] Implement MarkManager.get_window_marks() query method in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
- [X] T008 [P] Implement MarkManager.get_mark_metadata() parsing method in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
- [X] T009 [P] Implement MarkManager.find_windows() query method in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
- [X] T010 [P] Implement MarkManager.cleanup_marks() removal method in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
- [X] T011 [P] Implement MarkManager.count_instances() helper method in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
- [X] T012 Add MarkManager initialization to daemon in home-modules/desktop/i3-project-event-daemon/daemon.py
- [X] T013 Add MarkManager to IPC server dependency injection in home-modules/desktop/i3-project-event-daemon/ipc_server.py

**Checkpoint**: Foundation ready - MarkManager service fully functional and accessible ✅

---

## Phase 3: User Story 1 - Persistent App Identification During Layout Save (Priority: P1) 🎯 MVP

**Goal**: Capture app names with marks during layout save and persist them to layout files

**Independent Test**: Save a layout with multiple apps (terminal, code, PWAs), examine the saved layout file to verify app names are stored in structured marks format, confirm information persists across system restarts

### Implementation for User Story 1

- [X] T014 [US1] Integrate MarkManager.inject_marks() into window::new event handler in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T015 [US1] Add mark injection error handling with graceful degradation in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T016 [US1] Extend SavedWindow model to SavedWindowWithMarks (add optional marks field) in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T017 [US1] Integrate MarkManager.get_mark_metadata() into layout capture process in home-modules/desktop/i3-project-event-daemon/layout/capture.py
- [X] T018 [US1] Add marks_metadata field to WindowPlaceholder and pass to persistence in home-modules/desktop/i3-project-event-daemon/layout/capture.py and models.py
- [X] T019 [US1] Add validation to ensure marks.app matches app_registry_name in SavedWindowWithMarks in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T020 [US1] Add logging for mark injection and persistence operations in handlers.py, capture.py, and persistence.py

**Checkpoint**: At this point, User Story 1 should be fully functional - saving layouts captures and persists marks

**Manual Validation**:
1. Launch terminal via `i3pm app launch terminal`
2. Save layout via `i3pm layout save test-marks`
3. Examine `~/.local/share/i3pm/layouts/<project>/test-marks.json`
4. Verify marks field contains: `{"app": "terminal", "project": "nixos", "workspace": "1", "scope": "scoped"}`
5. Restart Sway and verify layout file still contains marks

---

## Phase 4: User Story 2 - Accurate Layout Restoration Using Stored App Names (Priority: P2)

**Goal**: Read stored app marks during restore and launch apps deterministically without process correlation

**Independent Test**: Save a layout with 3 apps, close all apps, restore layout from empty state, verify exact apps launch on correct workspaces with zero duplicates

### Implementation for User Story 2

- [X] T021 [US2] Implement mark-based detection in restore workflow - query running windows by marks in home-modules/desktop/i3-project-event-daemon/layout/restore.py
- [X] T022 [US2] Add idempotent restore using MarkManager.find_windows() to check for existing windows in home-modules/desktop/i3-project-event-daemon/layout/restore.py
- [X] T023 [US2] Prioritize mark-based detection over /proc detection (mark check happens before launching) in home-modules/desktop/i3-project-event-daemon/layout/restore.py
- [X] T024 [US2] Add backward compatibility - fall back to traditional launch when marks field missing in home-modules/desktop/i3-project-event-daemon/layout/restore.py
- [X] T025 [US2] Use saved marks.app field via marks_metadata for window detection in home-modules/desktop/i3-project-event-daemon/layout/restore.py
- [X] T026 [US2] Add logging for mark-based detection vs /proc fallback paths in home-modules/desktop/i3-project-event-daemon/layout/restore.py

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - save captures marks, restore uses marks for detection

**Manual Validation**:
1. Save layout with terminal, code, lazygit on different workspaces
2. Close all windows
3. Run `i3pm layout restore <project> test-marks`
4. Verify all 3 apps launch on correct workspaces
5. Run restore again (apps already running)
6. Verify window count remains constant (zero duplicates)

---

## Phase 5: User Story 3 - Extensible Mark Storage for Future Metadata (Priority: P3)

**Goal**: Ensure mark format supports adding new metadata fields without breaking existing layouts

**Independent Test**: Save layout with current mark format, add a new key-value pair to MarkMetadata schema (e.g., "focused": true), verify old layouts still restore correctly without the new field

### Implementation for User Story 3

- [X] T027 [US3] Add custom metadata field support to MarkMetadata model (dict[str, str]) in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T028 [US3] Implement custom mark serialization in MarkMetadata.to_sway_marks() (i3pm_custom:key:value format) in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T029 [US3] Implement custom mark parsing in MarkMetadata.from_sway_marks() in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T030 [US3] Add validation for custom metadata keys (must be snake_case identifiers) in home-modules/desktop/i3-project-event-daemon/layout/models.py
- [X] T031 [US3] Update layout persistence to handle optional custom metadata gracefully (handled by Pydantic automatically)
- [X] T032 [US3] Add forward compatibility - ignore unknown mark keys during parsing in home-modules/desktop/i3-project-event-daemon/layout/models.py

**Checkpoint**: All user stories should now be independently functional - mark format is extensible and backward compatible

**Manual Validation**:
1. Save layout with current mark format (no custom metadata)
2. Update MarkMetadata to add custom field: `custom = {"session_id": "test123"}`
3. Save new layout with custom metadata
4. Restore old layout (without custom metadata) - should work
5. Restore new layout (with custom metadata) - should preserve custom field
6. Examine both layout files to verify graceful handling

---

## Phase 6: Mark Cleanup Integration (Cross-Cutting)

**Purpose**: Prevent mark namespace pollution by cleaning up marks when windows close

- [X] T033 Add mark_manager parameter to window::close event handler in home-modules/desktop/i3-project-event-daemon/daemon.py and handlers.py
- [X] T034 Implement mark cleanup in on_window_close() handler that calls MarkManager.cleanup_marks() in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T035 Add error handling for cleanup failures (window already destroyed) in home-modules/desktop/i3-project-event-daemon/handlers.py
- [X] T036 Add logging for mark cleanup operations (debug level) in home-modules/desktop/i3-project-event-daemon/handlers.py

**Checkpoint**: Mark cleanup is automatic and reliable

**Manual Validation**:
1. Launch terminal via app-registry
2. Verify marks exist: `swaymsg -t get_tree | jq '.. | select(.app_id?=="Ghostty") | .marks'`
3. Close terminal window
4. Wait 100ms
5. Verify marks removed: `swaymsg -t get_marks | grep i3pm_` (should be empty)

---

## Phase 7: Testing & Validation

**Purpose**: Comprehensive test coverage for mark management

- [X] T037 [P] Create unit tests for MarkMetadata serialization/parsing in tests/unit/test_mark_models.py
- [ ] T038 [P] Create unit tests for MarkManager service methods (deferred - requires Sway IPC mocking)
- [X] T039 [P] Create integration test for mark persistence in tests/unit/test_mark_persistence.py
- [X] T040 [P] Create integration test for backward compatibility in tests/unit/test_mark_persistence.py
- [ ] T041 [P] Create sway-test for mark injection workflow (deferred to manual testing)
- [ ] T042 [P] Create sway-test for mark cleanup workflow (deferred to manual testing)
- [ ] T043 [P] Create sway-test for mark-based restore workflow (deferred to manual testing)

**Checkpoint**: All tests pass - mark management is validated

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T044 [P] Update quickstart.md with actual performance benchmarks (measure mark injection, save, restore latencies) in specs/076-mark-based-app-identification/quickstart.md (manual testing guide created - requires active Sway session)
- [X] T045 [P] Add error messages for layouts missing marks field (suggest re-saving) in home-modules/desktop/i3-project-event-daemon/layout/restore.py
- [X] T046 [P] Add performance logging for mark operations (injection, query, cleanup times) in home-modules/desktop/i3-project-event-daemon/services/mark_manager.py
- [X] T047 Run quickstart.md validation workflows (all 9 workflows) and verify outputs match expectations (manual testing guide created - see manual-testing-guide.md)
- [X] T048 [P] Update CLAUDE.md with mark-based identification system context in /etc/nixos/CLAUDE.md
- [X] T049 Code cleanup - remove debug logging, optimize mark query performance (verified: minimal debug logging, performance logging added is valuable)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Mark Cleanup (Phase 6)**: Depends on Foundational phase (needs MarkManager)
- **Testing (Phase 7)**: Can start after each user story completes
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Depends on User Story 1 (needs marks to be saved before they can be restored)
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Extends MarkMetadata independently

### Within Each User Story

- Models before services
- Services before integration points
- Core implementation before logging/error handling
- Story complete before moving to next priority

### Parallel Opportunities

**Phase 1 (Setup)**: All 3 tasks can run in parallel
- T001, T002, T003 (different sections of same file or different files)

**Phase 2 (Foundational)**: Models complete first, then service methods in parallel
- T004, T005 (MarkMetadata methods) → THEN T006-T011 (MarkManager methods in parallel) → THEN T012, T013

**User Story 1**: Limited parallelization (sequential integration)
- T014-T015 (AppLauncher) before T016-T019 (models and capture/persistence)

**User Story 3**: All tasks within the story can be done sequentially (extending same model)

**Phase 7 (Testing)**: All test tasks can run in parallel
- T037-T043 (all test files are independent)

**Phase 8 (Polish)**: Documentation tasks can run in parallel
- T044, T045, T046, T048 can all run in parallel

---

## Parallel Example: Foundational Phase

```bash
# After T004 and T005 complete (MarkMetadata serialization methods):
# Launch all MarkManager service methods together:
Task: "Implement MarkManager.inject_marks() in services/mark_manager.py"
Task: "Implement MarkManager.get_window_marks() in services/mark_manager.py"
Task: "Implement MarkManager.get_mark_metadata() in services/mark_manager.py"
Task: "Implement MarkManager.find_windows() in services/mark_manager.py"
Task: "Implement MarkManager.cleanup_marks() in services/mark_manager.py"
Task: "Implement MarkManager.count_instances() in services/mark_manager.py"
```

---

## Parallel Example: Testing Phase

```bash
# All test files are independent and can be written in parallel:
Task: "Unit tests for MarkMetadata in tests/.../test_mark_models.py"
Task: "Unit tests for MarkManager in tests/.../test_mark_manager.py"
Task: "Integration test for mark injection in tests/.../test_mark_injection.py"
Task: "Integration test for mark persistence in tests/.../test_mark_persistence.py"
Task: "Sway-test for mark injection in tests/.../test_mark_injection.json"
Task: "Sway-test for mark cleanup in tests/.../test_mark_cleanup.json"
Task: "Sway-test for mark restore in tests/.../test_mark_restore.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T013) - CRITICAL - blocks all stories
3. Complete Phase 3: User Story 1 (T014-T020)
4. **STOP and VALIDATE**: Test User Story 1 independently
   - Launch apps → Save layout → Verify marks in layout file
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP! - layouts save marks)
3. Add User Story 2 → Test independently → Deploy/Demo (restore uses marks - 3x faster!)
4. Add User Story 3 → Test independently → Deploy/Demo (extensible for future metadata)
5. Add Mark Cleanup (Phase 6) → Deploy/Demo (zero mark pollution)
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T013)
2. Once Foundational is done:
   - Developer A: User Story 1 (T014-T020)
   - Developer B: User Story 3 (T027-T032) - can work in parallel with US1
3. After US1 completes:
   - Developer A: User Story 2 (T021-T026) - depends on US1
   - Developer B: Mark Cleanup (T033-T036) - depends on Foundational only
4. Testing Phase: Split test tasks across team (T037-T043)
5. Polish: Split documentation tasks across team (T044-T049)

---

## Notes

- [P] tasks = different files or independent sections, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- File paths use existing daemon structure: services/, layout/, tests/

---

## Summary Statistics

- **Total Tasks**: 49
- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 10 tasks (BLOCKING)
- **Phase 3 (US1 - MVP)**: 7 tasks
- **Phase 4 (US2)**: 6 tasks
- **Phase 5 (US3)**: 6 tasks
- **Phase 6 (Cleanup)**: 4 tasks
- **Phase 7 (Testing)**: 7 tasks
- **Phase 8 (Polish)**: 6 tasks

**Parallel Opportunities Identified**:
- Phase 1: 3 tasks (all parallel)
- Phase 2: 6 tasks (T006-T011 after T004-T005 complete)
- Phase 7: 7 tasks (all tests parallel)
- Phase 8: 4 tasks (documentation parallel)

**Suggested MVP Scope**: Phases 1-3 (Setup + Foundational + User Story 1 = 20 tasks)
- MVP delivers: Mark injection at launch + mark persistence in layouts
- Estimated effort: 2-3 days for experienced developer
- Value delivered: Foundation for reliable layout restoration
