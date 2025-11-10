# Tasks: Sway Test Framework Usability Improvements

**Feature**: 070-sway-test-improvements
**Input**: Design documents from `/etc/nixos/specs/070-sway-test-improvements/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No test tasks included - Feature 069 already provides comprehensive sync-based testing infrastructure. Implementation will be validated through existing test framework.

**Organization**: Tasks are grouped by user story (P1: US1 & US2, P2: US3 & US4, P3: US5) to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US5)
- Include exact file paths in descriptions

## Phase 1: Setup (Completed)

**Status**: ✅ COMPLETE (T001-T003 completed in prior session)

**Purpose**: Foundational data models and registries

- [x] T001 Create PWADefinition model with ULID validation in home-modules/tools/sway-test/src/models/pwa-definition.ts
- [x] T002 Create AppDefinition model with scope/workspace validation in home-modules/tools/sway-test/src/models/app-definition.ts
- [x] T003 Add list entry transforms (AppListEntry, PWAListEntry) to data model files

**Checkpoint**: Core data models exist and validated with Zod schemas

---

## Phase 2: Foundational (Completed)

**Status**: ✅ COMPLETE (T004-T006 completed in prior session)

**Purpose**: Core infrastructure for PWA registry integration - BLOCKS all user stories

**⚠️ CRITICAL**: This phase must be complete before any user story work begins

- [x] T004 Generate pwa-registry.json from pwa-sites.nix in home-modules/desktop/app-registry.nix
- [x] T005 Implement PWA registry loading with lookupPWA() and lookupPWAByULID() in home-modules/tools/sway-test/src/services/app-registry-reader.ts
- [x] T006 Add launch_pwa_sync action type to TestCase schema in home-modules/tools/sway-test/src/models/test-case.ts

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Clear Error Diagnostics (Priority: P1) 🎯 MVP

**Goal**: Provide structured error messages with diagnostic context and remediation steps for all test framework failures

**Independent Test**: Intentionally create failing tests (missing app, invalid PWA ULID, malformed JSON) and verify error messages clearly explain the problem with actionable remediation steps

### Implementation for User Story 1

- [x] T007 [P] [US1] Create ErrorType enum with 8 error types (APP_NOT_FOUND, PWA_NOT_FOUND, INVALID_ULID, LAUNCH_FAILED, TIMEOUT, MALFORMED_TEST, REGISTRY_ERROR, CLEANUP_FAILED) in home-modules/tools/sway-test/src/models/structured-error.ts
- [x] T008 [P] [US1] Implement StructuredError class extending Error with type/component/cause/remediation/context fields in home-modules/tools/sway-test/src/models/structured-error.ts
- [x] T009 [P] [US1] Add Zod schema validation for StructuredError in home-modules/tools/sway-test/src/models/structured-error.ts
- [x] T010 [P] [US1] Create ErrorHandler service with formatError() method for console output in home-modules/tools/sway-test/src/services/error-handler.ts
- [x] T011 [US1] Integrate StructuredError into app-registry-reader.ts for APP_NOT_FOUND and REGISTRY_ERROR cases in home-modules/tools/sway-test/src/services/app-registry-reader.ts
- [x] T012 [US1] Integrate StructuredError into PWA lookup functions for PWA_NOT_FOUND and INVALID_ULID cases in home-modules/tools/sway-test/src/services/app-registry-reader.ts
- [x] T013 [US1] Add context enrichment to error messages (available apps list, registry path, current state) in home-modules/tools/sway-test/src/services/error-handler.ts [Note: Completed as part of T011/T012 - all StructuredError instances include comprehensive context]
- [x] T014 [US1] Update test runner to catch and format StructuredError instances in home-modules/tools/sway-test/main.ts
- [x] T015 [US1] Add error logging to framework log file in home-modules/tools/sway-test/src/services/error-handler.ts [Note: Completed as part of T010 - handleError() includes file logging via logErrorToFile()]

**Checkpoint**: All test framework errors use StructuredError format with clear remediation steps

---

## Phase 4: User Story 2 - Graceful Cleanup Commands (Priority: P1)

**Goal**: Automatic cleanup of test-spawned processes and windows with manual CLI fallback for interrupted sessions

**Independent Test**: Run test that launches multiple apps, forcibly stop test mid-execution, then verify cleanup commands successfully restore clean state without manual intervention

### Implementation for User Story 2

- [x] T016 [P] [US2] Create CleanupReport interface with ProcessCleanupEntry/WindowCleanupEntry/CleanupError types in home-modules/tools/sway-test/src/models/cleanup-report.ts
- [x] T017 [P] [US2] Add Zod schemas for CleanupReport and nested types in home-modules/tools/sway-test/src/models/cleanup-report.ts
- [x] T018 [P] [US2] Create ProcessTracker service for tracking spawned PIDs with SIGTERM→SIGKILL escalation in home-modules/tools/sway-test/src/services/process-tracker.ts
- [x] T019 [P] [US2] Create WindowTracker service for tracking window markers with Sway IPC close commands in home-modules/tools/sway-test/src/services/window-tracker.ts
- [x] T020 [US2] Implement CleanupManager service with registerProcess(), registerWindow(), cleanup() methods in home-modules/tools/sway-test/src/services/cleanup-manager.ts
- [x] T021 [US2] Integrate CleanupManager into test runner teardown (automatic cleanup on test completion/failure) in home-modules/tools/sway-test/src/commands/run.ts
- [x] T022 [US2] Create cleanup CLI command with --all/--processes/--windows/--markers/--dry-run/--json flags in home-modules/tools/sway-test/src/commands/cleanup.ts
- [x] T023 [US2] Create CleanupReporter UI formatter for human-readable cleanup reports in home-modules/tools/sway-test/src/ui/cleanup-reporter.ts
- [x] T024 [US2] Add cleanup command to CLI entry point in home-modules/tools/sway-test/main.ts
- [x] T025 [US2] Implement clearRegistryCache() for test isolation in home-modules/tools/sway-test/src/services/app-registry-reader.ts

**Checkpoint**: Zero orphaned processes/windows after test completion, manual cleanup command available

---

## Phase 5: User Story 3 - PWA Application Support (Priority: P2)

**Goal**: First-class PWA testing with launch_pwa_sync action supporting friendly names and ULID resolution

**Independent Test**: Create test launching PWA by name (e.g., "youtube"), verify it appears on correct workspace, validate window properties without manual ULID management

### Implementation for User Story 3

- [x] T026 [US3] Implement executeLaunchPWASync() handler in ActionExecutor with firefoxpwa subprocess execution in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T027 [US3] Add PWA name resolution via lookupPWA() in launch_pwa_sync handler in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T028 [US3] Add PWA ULID resolution via lookupPWAByULID() in launch_pwa_sync handler in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T029 [US3] Integrate sync protocol for window detection after PWA launch in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T030 [US3] Add allow_failure parameter support for optional PWA launches in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T031 [US3] Implement firefoxpwa pre-flight check with clear error if binary missing in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T032 [US3] Add timeout handling (5s default, configurable via test params) for PWA launches in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T033 [US3] Register PWA process PID with CleanupManager for automatic teardown in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T034 [US3] Add StructuredError integration for LAUNCH_FAILED scenarios (firefoxpwa not found, PWA not installed) in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T035 [US3] Update test-case.ts with launch_pwa_sync parameter validation (pwa_name XOR pwa_ulid required) in home-modules/tools/sway-test/src/models/test-case.ts

**Checkpoint**: Tests can launch PWAs by friendly name with automatic workspace assignment validation

---

## Phase 6: User Story 4 - App Registry Integration (Priority: P2)

**Goal**: Name-based app launches with automatic metadata resolution from application registry

**Independent Test**: Write test launching app by registry name only, change app command in registry, verify test still works without modification

### Implementation for User Story 4

- [x] T036 [US4] Extend launch_app_sync handler to support app_name parameter with registry lookup in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T037 [US4] Add app command resolution from registry when app_name provided in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T038 [US4] Add expected_class resolution from registry for window detection in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T039 [US4] Add workspace validation using registry preferred_workspace metadata in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T040 [US4] Add monitor role validation using registry preferred_monitor_role in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T041 [US4] Add floating window configuration support (state and size preset) from registry in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T042 [US4] Implement parameter passing for registry apps (e.g., "ghostty -e btop") in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T043 [US4] Add fuzzy matching suggestions when app name not found (show similar apps) in home-modules/tools/sway-test/src/services/app-registry-reader.ts
- [x] T044 [US4] Register app process PID with CleanupManager for automatic teardown in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T045 [US4] Add StructuredError integration for APP_NOT_FOUND with available apps list in home-modules/tools/sway-test/src/services/action-executor.ts
- [x] T046 [US4] Update test-case.ts to allow app_name as alternative to command parameter in home-modules/tools/sway-test/src/models/test-case.ts
- [x] T047 [US4] Add scope validation (global/scoped) from registry for project-scoped tests in home-modules/tools/sway-test/src/services/action-executor.ts

**Checkpoint**: Tests use app names only, framework resolves all metadata from registry

---

## Phase 7: User Story 5 - Convenient CLI Access (Priority: P3)

**Goal**: CLI discovery commands for exploring available apps and PWAs without reading Nix configuration

**Independent Test**: Run CLI commands (list-apps, list-pwas) and verify they display formatted tables with all registry information

### Implementation for User Story 5

- [x] T048 [P] [US5] Create TableFormatter utility using @std/cli/unicode-width for column alignment in home-modules/tools/sway-test/src/ui/table-formatter.ts
- [x] T049 [P] [US5] Implement list-apps command with table/JSON output in home-modules/tools/sway-test/src/commands/list-apps.ts
- [x] T050 [P] [US5] Implement list-pwas command with table/JSON output in home-modules/tools/sway-test/src/commands/list-pwas.ts
- [x] T051 [US5] Add filter argument support for name-based searching in list-apps command in home-modules/tools/sway-test/src/commands/list-apps.ts
- [x] T052 [US5] Add filter argument support for name-based searching in list-pwas command in home-modules/tools/sway-test/src/commands/list-pwas.ts
- [x] T053 [US5] Add --workspace/--monitor/--scope filter flags for list-apps in home-modules/tools/sway-test/src/commands/list-apps.ts
- [x] T054 [US5] Add --workspace/--monitor/--ulid filter flags for list-pwas in home-modules/tools/sway-test/src/commands/list-pwas.ts
- [x] T055 [US5] Add --verbose flag for full metadata display (descriptions, nix_package, full URLs) in list commands in home-modules/tools/sway-test/src/commands/list-apps.ts and list-pwas.ts
- [x] T056 [US5] Add --format csv option for spreadsheet export in home-modules/tools/sway-test/src/commands/list-apps.ts and list-pwas.ts
- [x] T057 [US5] Integrate list-apps and list-pwas commands into CLI entry point in home-modules/tools/sway-test/main.ts
- [x] T058 [US5] Add registry file missing error handling with setup instructions in home-modules/tools/sway-test/src/commands/list-apps.ts and list-pwas.ts
- [x] T059 [US5] Add help text for list-apps command (--help flag) in home-modules/tools/sway-test/src/commands/list-apps.ts
- [x] T060 [US5] Add help text for list-pwas command (--help flag) in home-modules/tools/sway-test/src/commands/list-pwas.ts

**Checkpoint**: Developers can discover apps/PWAs without reading Nix configuration files

---

## Phase 8: Integration Tests & Validation

**Purpose**: End-to-end validation of all user stories using existing Feature 069 sync test framework

- [x] T061 [P] Create PWA launch test using pwa_name parameter in home-modules/tools/sway-test/tests/sway-tests/integration/test_pwa_name_launch.json
- [x] T062 [P] Create PWA launch test using pwa_ulid parameter in home-modules/tools/sway-test/tests/sway-tests/integration/test_pwa_ulid_launch.json
- [x] T063 [P] Create app registry launch test using app_name parameter in home-modules/tools/sway-test/tests/sway-tests/integration/test_app_name_launch.json
- [x] T064 [P] Create error scenario test (PWA not found) verifying StructuredError format in home-modules/tools/sway-test/tests/sway-tests/integration/test_pwa_not_found.json
- [x] T065 [P] Create error scenario test (invalid ULID format) verifying validation in home-modules/tools/sway-test/tests/sway-tests/integration/test_invalid_ulid.json
- [x] T066 [P] Create cleanup validation test (launches 5 apps, verifies zero orphaned processes) in home-modules/tools/sway-test/tests/sway-tests/integration/test_cleanup.json
- [ ] T067 Run all integration tests and verify 100% pass rate with sway-test run tests/sway-tests/integration/
- [ ] T068 Verify success criteria SC-001 through SC-010 from spec.md

**Checkpoint**: All user stories validated end-to-end with zero flakiness

---

## Phase 9: Polish & Documentation

**Purpose**: Production readiness and developer documentation

- [ ] T069 [P] Add performance benchmarks for registry loading (<50ms target) in home-modules/tools/sway-test/src/services/app-registry-reader.ts
- [ ] T070 [P] Add performance benchmarks for cleanup operations (<2s for 10 resources) in home-modules/tools/sway-test/src/services/cleanup-manager.ts
- [ ] T071 [P] Create error message catalog with all StructuredError examples in specs/070-sway-test-improvements/error-catalog.md
- [ ] T072 Update quickstart.md with final CLI examples and troubleshooting in specs/070-sway-test-improvements/quickstart.md
- [ ] T073 Update CLAUDE.md with Feature 070 context (TypeScript/Deno, Zod, StructuredError patterns) in CLAUDE.md
- [ ] T074 [P] Add --help text for cleanup command in home-modules/tools/sway-test/src/commands/cleanup.ts
- [ ] T075 [P] Add --version flag displaying sway-test framework version in home-modules/tools/sway-test/main.ts
- [ ] T076 Validate all quickstart.md examples execute successfully

**Checkpoint**: Feature 070 ready for production use

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: ✅ COMPLETE - No dependencies
- **Foundational (Phase 2)**: ✅ COMPLETE - Depends on Setup completion - BLOCKED all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - **US1 (P1)**: Can start after Foundational - No dependencies on other stories
  - **US2 (P1)**: Can start after Foundational - No dependencies on other stories
  - **US3 (P2)**: Can start after Foundational - Depends on US1 (StructuredError) for error handling
  - **US4 (P2)**: Can start after Foundational - Depends on US1 (StructuredError) and US2 (CleanupManager)
  - **US5 (P3)**: Can start after Foundational - Depends on US1 (StructuredError) for error messages
- **Integration Tests (Phase 8)**: Depends on US1-US4 completion (US5 optional)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start immediately after Foundational - No dependencies on other stories
- **User Story 3 (P2)**: Depends on US1 (StructuredError for error handling) - Otherwise independently testable
- **User Story 4 (P2)**: Depends on US1 (StructuredError) and US2 (CleanupManager) - Otherwise independently testable
- **User Story 5 (P3)**: Depends on US1 (StructuredError for registry errors) - Otherwise independently testable

### Within Each User Story

**US1 (Error Diagnostics)**:
- T007-T009 (models) can run in parallel
- T010 (ErrorHandler) can run in parallel with models
- T011-T012 (integration) depend on T007-T010 completion
- T013-T015 (enrichment/logging) depend on T010-T012

**US2 (Cleanup Commands)**:
- T016-T019 (models and trackers) can run in parallel
- T020 (CleanupManager) depends on T018-T019 completion
- T021-T025 (CLI and integration) depend on T020 completion
- T023 (CleanupReporter) can run in parallel with T021-T022

**US3 (PWA Support)**:
- All T026-T035 must run sequentially (single file action-executor.ts)
- T035 (test-case.ts update) can run in parallel

**US4 (Registry Integration)**:
- T036-T042, T044-T045, T047 (action-executor.ts) must run sequentially
- T043 (fuzzy matching) can run in parallel
- T046 (test-case.ts update) can run in parallel

**US5 (CLI Access)**:
- T048-T050 can run in parallel (different files)
- T051-T052 depend on T049-T050 respectively
- T053-T056 are independent enhancements (can parallelize)
- T057-T060 finalize CLI integration

### Parallel Opportunities

**Phase 3 (US1)**:
- T007, T008, T009, T010 - all different concerns within StructuredError

**Phase 4 (US2)**:
- T016, T017, T018, T019 - all independent services/models

**Phase 7 (US5)**:
- T048, T049, T050 - all different files

**Phase 8 (Integration Tests)**:
- T061-T066 - all independent test files

**Phase 9 (Polish)**:
- T069, T070, T071, T074, T075 - all independent files

---

## Parallel Example: User Story 1

```bash
# Launch all models/services for US1 together:
Task T007: "Create ErrorType enum in structured-error.ts"
Task T008: "Implement StructuredError class in structured-error.ts"
Task T009: "Add Zod schema for StructuredError in structured-error.ts"
Task T010: "Create ErrorHandler service in error-handler.ts"

# After T007-T010 complete, integrate in parallel:
Task T011: "Integrate StructuredError into app-registry-reader.ts (APP_NOT_FOUND)"
Task T012: "Integrate StructuredError into PWA lookup (PWA_NOT_FOUND, INVALID_ULID)"
```

---

## Implementation Strategy

### MVP First (US1 + US2 Only)

1. ✅ Complete Phase 1: Setup (DONE)
2. ✅ Complete Phase 2: Foundational (DONE)
3. Complete Phase 3: User Story 1 (Clear Error Diagnostics)
4. Complete Phase 4: User Story 2 (Graceful Cleanup Commands)
5. **STOP and VALIDATE**: Test US1 + US2 independently
6. Run quickstart.md validation for error diagnostics and cleanup
7. Deploy/demo if ready

**Rationale**: US1 + US2 are both P1 priority and provide immediate value - clear errors help debugging, automatic cleanup prevents test interference

### Incremental Delivery

1. ✅ Setup + Foundational → Foundation ready (DONE)
2. Add US1 (Error Diagnostics) → Test independently → Deploy/Demo
3. Add US2 (Cleanup Commands) → Test independently → Deploy/Demo (MVP complete)
4. Add US3 (PWA Support) → Test independently → Deploy/Demo
5. Add US4 (Registry Integration) → Test independently → Deploy/Demo
6. Add US5 (CLI Access) → Test independently → Deploy/Demo
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers after Foundational phase completes:

**Week 1 (P1 priorities)**:
- Developer A: User Story 1 (Error Diagnostics) - T007-T015
- Developer B: User Story 2 (Cleanup Commands) - T016-T025

**Week 2 (P2 priorities)**:
- Developer A: User Story 3 (PWA Support) - T026-T035
- Developer B: User Story 4 (Registry Integration) - T036-T047

**Week 3 (P3 + validation)**:
- Developer A: User Story 5 (CLI Access) - T048-T060
- Developer B: Integration Tests - T061-T068

**Week 4 (polish)**:
- Both: Phase 9 (Polish & Documentation) - T069-T076

---

## Notes

- [P] tasks = different files, no dependencies within the user story
- [Story] label (US1-US5) maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Phase 1 & 2 already complete - implementation starts at Phase 3 (T007)
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- Total: 76 tasks (6 complete, 70 remaining)
