# Tasks: Declarative PWA Installation (TDD Approach)

**Feature**: 056-declarative-pwa-installation
**Input**: Design documents from `/specs/056-declarative-pwa-installation/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Testing Strategy**: This feature follows Test-Driven Development (TDD). All tests MUST be written FIRST and fail (RED), then implementation makes them pass (GREEN).

**Organization**: Tasks are grouped by user story with tests written before implementation for each story.

## Format: `- [ ] [ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- NixOS configuration at `/etc/nixos/`
- Home-manager modules in `home-modules/tools/`
- Shared configuration in `shared/`
- Test files in `tests/pwa-installation/`
- Helper scripts packaged as Nix derivations

---

## Phase 1: Setup (Test Infrastructure + Data)

**Purpose**: Project initialization, test framework, and basic structure for declarative PWA system

- [X] T001 Create tests/pwa-installation/ directory structure with unit/, integration/, acceptance/, fixtures/ subdirectories
- [X] T002 [P] Create test fixtures in /etc/nixos/tests/pwa-installation/fixtures/ with test PWA definitions (minimal, complete, invalid, edge-case)
- [X] T003 [P] Create pwa-sites.nix in /etc/nixos/shared/ with initial PWA definitions and ULID mappings
- [X] T004 [P] Create pwa-helpers.nix in /etc/nixos/home-modules/tools/ for helper command packaging
- [X] T005 [P] Generate ULIDs for existing PWAs using ulid CLI tool and document in pwa-sites.nix
- [X] T006 Setup NixOS checks in flake.nix for running unit tests via nix build .#checks.x86_64-linux.pwa-unit-tests

**Checkpoint**: Test infrastructure ready, test fixtures created, data files in place

---

## Phase 2: Foundational (Core Functions with TDD)

**Purpose**: Core Nix functions with unit tests written FIRST

**⚠️ CRITICAL**: Follow TDD cycle for each function - Test FIRST (RED), then implement (GREEN)

### Unit Tests for validateULID (TR-001, TR-004, TR-005)

- [X] T007 [P] Write test for valid ULID in /etc/nixos/tests/pwa-installation/unit/test-validate-ulid.nix - expect FAIL
- [X] T008 [P] Write test for invalid ULID with forbidden chars (I,L,O,U) in test-validate-ulid.nix - expect FAIL
- [X] T009 [P] Write test for invalid ULID length (<26, >26) in test-validate-ulid.nix - expect FAIL
- [X] T010 Implement validateULID function in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix - make tests PASS
- [X] T011 Verify all validateULID tests pass (GREEN), refactor if needed

### Unit Tests for generateManifest (TR-002, TR-006, TR-007)

- [X] T012 [P] Write test for valid manifest JSON generation in /etc/nixos/tests/pwa-installation/unit/test-generate-manifest.nix - expect FAIL
- [X] T013 [P] Write test for manifest with all required fields in test-generate-manifest.nix - expect FAIL
- [X] T014 [P] Write test for manifest with missing optional fields in test-generate-manifest.nix - expect FAIL
- [X] T015 Implement generateManifest function in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix - make tests PASS
- [X] T016 Verify all generateManifest tests pass (GREEN), refactor if needed

### Unit Tests for generateFirefoxPWAConfig (TR-003, TR-008)

- [X] T017 [P] Write test for empty PWA list config in /etc/nixos/tests/pwa-installation/unit/test-generate-config.nix - expect FAIL
- [X] T018 [P] Write test for single PWA config in test-generate-config.nix - expect FAIL
- [X] T019 [P] Write test for multiple PWAs config in test-generate-config.nix - expect FAIL
- [X] T020 [P] Write test for duplicate ULID rejection in test-generate-config.nix - expect FAIL
- [X] T021 Implement generateFirefoxPWAConfig function in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix - make tests PASS
- [X] T022 Verify all generateFirefoxPWAConfig tests pass (GREEN), refactor if needed

### Module Infrastructure

- [X] T023 Add ulid package to system packages in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T024 Create basic module structure with enable option in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix

**Checkpoint**: Foundation ready - all unit tests passing (GREEN), core functions validated

---

## Phase 3: User Story 1 - Zero-Touch PWA Deployment (Priority: P1) 🎯 MVP

**Goal**: Enable automatic PWA installation from declarative configuration without manual Firefox GUI interaction

**Independent Test**: Define one PWA in pwa-sites.nix, rebuild system, verify PWA appears in firefoxpwa profile list without manual installation

### Integration Tests for User Story 1 (TR-009, TR-010, TR-012, TR-013, TR-016, TR-017)

**⚠️ Write these tests FIRST - they will FAIL until implementation is complete**

- [X] T025 [P] [US1] Write integration test for fresh system deployment in /etc/nixos/tests/pwa-installation/integration/test-us1-fresh-deployment.nix - expect FAIL
- [X] T026 [P] [US1] Write integration test for idempotent installation in /etc/nixos/tests/pwa-installation/integration/test-us1-idempotency.nix - expect FAIL
- [X] T027 [P] [US1] Write integration test for desktop entry creation in /etc/nixos/tests/pwa-installation/integration/test-us1-desktop-entries.nix - expect FAIL
- [X] T028 [P] [US1] Write integration test for manifest accessibility in /etc/nixos/tests/pwa-installation/integration/test-us1-manifest-urls.nix - expect FAIL
- [X] T029 [P] [US1] Write integration test for installation error handling in /etc/nixos/tests/pwa-installation/integration/test-us1-error-handling.nix - expect FAIL

### Acceptance Tests for User Story 1 (TR-019)

- [X] T030 [P] [US1] Write acceptance test for US1 Scenario 1 (declarative install) in /etc/nixos/tests/pwa-installation/acceptance/test-us1-scenario1.sh - expect FAIL
- [X] T031 [P] [US1] Write acceptance test for US1 Scenario 2 (fresh machine) in /etc/nixos/tests/pwa-installation/acceptance/test-us1-scenario2.sh - expect FAIL
- [X] T032 [P] [US1] Write acceptance test for US1 Scenario 3 (preserve existing) in /etc/nixos/tests/pwa-installation/acceptance/test-us1-scenario3.sh - expect FAIL

### Implementation for User Story 1

**⚠️ Tests above MUST be failing (RED) before starting implementation**

- [X] T033 [P] [US1] Import pwa-sites.nix in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix as data source
- [X] T034 [P] [US1] Generate manifest files for all PWAs using generateManifest in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T035 [US1] Generate firefoxpwa config.json using generateFirefoxPWAConfig in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T036 [US1] Write config.json to ~/.config/firefoxpwa/config.json via xdg.configFile in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T037 [US1] Implement installPWAScript function in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix to run firefoxpwa site install
- [X] T038 [US1] Add idempotency check in installPWAScript - query installed PWAs before attempting installation
- [X] T039 [US1] Create home.activation.managePWAs entry in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix to run installPWAScript
- [X] T040 [US1] Handle installation failures gracefully - log errors and continue with remaining PWAs
- [X] T041 [US1] Add desktop entry symlink creation in home.activation.linkPWADesktopFiles in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T042 [US1] Verify all User Story 1 tests pass (GREEN) - integration and acceptance tests now passing
- [X] T043 [US1] Manual validation on hetzner-sway - define YouTube PWA, rebuild, verify installation

**Checkpoint**: User Story 1 complete and tested - all tests GREEN, PWAs automatically install during rebuild

---

## Phase 4: User Story 2 - Cross-Machine Configuration Portability (Priority: P2)

**Goal**: Ensure PWA configuration works identically across all machines without machine-specific customization

**Independent Test**: Deploy same configuration to two different machines, verify PWAs install and launch correctly without configuration changes

### Integration Tests for User Story 2 (TR-011)

**⚠️ Write these tests FIRST - they will FAIL until implementation is complete**

- [X] T044 [P] [US2] Write integration test for cross-machine ULID consistency in /etc/nixos/tests/pwa-installation/integration/test-us2-ulid-portability.nix - expect FAIL
- [X] T045 [P] [US2] Write integration test for manifest path portability in /etc/nixos/tests/pwa-installation/integration/test-us2-manifest-portability.nix - expect FAIL
- [X] T046 [P] [US2] Write integration test for launch-pwa-by-name on multiple machines in /etc/nixos/tests/pwa-installation/integration/test-us2-launch-wrapper.nix - expect FAIL

### Acceptance Tests for User Story 2 (TR-020)

- [X] T047 [P] [US2] Write acceptance test for US2 Scenario 1 (machine A → B) in /etc/nixos/tests/pwa-installation/acceptance/test-us2-scenario1.sh - expect FAIL
- [X] T048 [P] [US2] Write acceptance test for US2 Scenario 2 (dynamic ID resolution) in /etc/nixos/tests/pwa-installation/acceptance/test-us2-scenario2.sh - expect FAIL
- [X] T049 [P] [US2] Write acceptance test for US2 Scenario 3 (path resolution) in /etc/nixos/tests/pwa-installation/acceptance/test-us2-scenario3.sh - expect FAIL

### Implementation for User Story 2

**⚠️ Tests above MUST be failing (RED) before starting implementation**

- [X] T050 [P] [US2] Verify ULID mappings in /etc/nixos/shared/pwa-sites.nix use static strings (not dynamic generation)
- [X] T051 [P] [US2] Add assertion checks for static ULIDs in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T052 [US2] Create launch-pwa-by-name wrapper script in /etc/nixos/home-modules/tools/pwa-helpers.nix for cross-machine PWA launching
- [X] T053 [US2] Update Walker custom commands to use launch-pwa-by-name instead of hardcoded ULIDs
- [X] T054 [US2] Verify all User Story 2 tests pass (GREEN) - portability tests now passing
- [X] T055 [US2] Manual validation - deploy to M1 Mac, verify same pwa-sites.nix works without changes
- [X] T056 [US2] Manual validation - deploy to WSL, verify same pwa-sites.nix works without changes
- [X] T057 [US2] Document cross-machine portability guarantees in /etc/nixos/specs/056-declarative-pwa-installation/quickstart.md

**Checkpoint**: User Stories 1 AND 2 complete - all tests GREEN, PWAs install identically across all machines

---

## Phase 5: User Story 3 - Single Source of Truth for PWA Metadata (Priority: P3)

**Goal**: Define PWA metadata (name, URL, workspace assignment, icon) in one location so changes propagate to all dependent files

**Independent Test**: Modify PWA metadata in pwa-sites.nix, rebuild, verify changes appear in config.json, manifests, and desktop entries

### Integration Tests for User Story 3 (TR-018)

**⚠️ Write these tests FIRST - they will FAIL until implementation is complete**

- [X] T058 [P] [US3] Write integration test for metadata change propagation in /etc/nixos/tests/pwa-installation/integration/test-us3-metadata-propagation.nix - expect FAIL
- [X] T059 [P] [US3] Write integration test for workspace assignment from app-registry in /etc/nixos/tests/pwa-installation/integration/test-us3-workspace-assignment.nix - expect FAIL
- [X] T060 [P] [US3] Write integration test for icon/category propagation in /etc/nixos/tests/pwa-installation/integration/test-us3-desktop-metadata.nix - expect FAIL

### Acceptance Tests for User Story 3 (TR-021)

- [X] T061 [P] [US3] Write acceptance test for US3 Scenario 1 (registry extraction) in /etc/nixos/tests/pwa-installation/acceptance/test-us3-scenario1.sh - expect FAIL
- [X] T062 [P] [US3] Write acceptance test for US3 Scenario 2 (workspace change) in /etc/nixos/tests/pwa-installation/acceptance/test-us3-scenario2.sh - expect FAIL
- [X] T063 [P] [US3] Write acceptance test for US3 Scenario 3 (manifest reflection) in /etc/nixos/tests/pwa-installation/acceptance/test-us3-scenario3.sh - expect FAIL

### Implementation for User Story 3

**⚠️ Tests above MUST be failing (RED) before starting implementation**

- [X] T064 [P] [US3] Integrate pwa-sites.nix with app-registry-data.nix - add PWA entries to app registry
- [X] T065 [P] [US3] Extract preferred_workspace from app-registry and include in PWA site definitions in /etc/nixos/shared/pwa-sites.nix
- [X] T066 [US3] Update generateManifest to use metadata from pwa-sites.nix (name, description, icon, scope) in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T067 [US3] Update desktop entry categories/keywords from pwa-sites.nix in firefoxpwa installation in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T068 [US3] Verify all User Story 3 tests pass (GREEN) - metadata propagation tests now passing
- [X] T069 [US3] Manual validation - update YouTube description in pwa-sites.nix, rebuild, verify in manifest and config.json
- [X] T070 [US3] Manual validation - verify workspace assignment from app-registry works with i3pm daemon integration

**Checkpoint**: All user stories complete - all tests GREEN, single source of truth for all PWA metadata

---

## Phase 6: Helper Commands with Tests (TR-015)

**Purpose**: User-facing commands for manual PWA management and validation

### Unit Tests for Helper Commands

**⚠️ Write these tests FIRST - they will FAIL until implementation is complete**

- [X] T071 [P] Write test for pwa-install-all command in /etc/nixos/tests/pwa-installation/unit/test-cmd-install-all.sh - expect FAIL
- [X] T072 [P] Write test for pwa-list command in /etc/nixos/tests/pwa-installation/unit/test-cmd-list.sh - expect FAIL
- [X] T073 [P] Write test for pwa-validate command in /etc/nixos/tests/pwa-installation/unit/test-cmd-validate.sh - expect FAIL
- [X] T074 [P] Write test for pwa-get-ids command in /etc/nixos/tests/pwa-installation/unit/test-cmd-get-ids.sh - expect FAIL
- [X] T075 [P] Write test for pwa-1password-status command in /etc/nixos/tests/pwa-installation/unit/test-cmd-1password-status.sh - expect FAIL

### Implementation of Helper Commands

**⚠️ Tests above MUST be failing (RED) before starting implementation**

- [X] T076 [P] Package pwa-install-all command in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T077 [P] Package pwa-list command in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T078 [P] Package pwa-validate command in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T079 [P] Package pwa-get-ids command in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T080 [P] Package pwa-1password-status command in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T081 [P] Package pwa-install-guide command in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T082 Implement installPWAScript shell logic with firefoxpwa profile list query and installation loop in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T083 Add error handling and user-friendly messages for all helper commands in /etc/nixos/home-modules/tools/pwa-helpers.nix
- [X] T084 Verify all helper command tests pass (GREEN)
- [X] T085 Manual validation - test all helper commands on hetzner-sway configuration

**Checkpoint**: All helper commands working and tested - tests GREEN, commands provide clear feedback

---

## Phase 7: Integration & Configuration (TR-014)

**Purpose**: Enable the module across all NixOS configurations and ensure proper integration

### Integration Tests for Multi-Configuration Deployment

- [X] T086 [P] Write integration test for 1Password runtime.json in /etc/nixos/tests/pwa-installation/integration/test-1password-integration.nix - expect FAIL
- [X] T087 [P] Write integration test for Walker PWA launch in /etc/nixos/tests/pwa-installation/integration/test-walker-integration.nix - expect FAIL

### Implementation of Configuration Integration

- [X] T088 Import firefox-pwas-declarative.nix in /etc/nixos/configurations/hetzner-sway.nix
- [X] T089 [P] Import firefox-pwas-declarative.nix in /etc/nixos/configurations/m1.nix
- [X] T090 [P] Import firefox-pwas-declarative.nix in /etc/nixos/configurations/wsl.nix
- [X] T091 Enable programs.firefoxpwa in hetzner-sway home-manager configuration
- [X] T092 [P] Enable programs.firefoxpwa in M1 home-manager configuration
- [X] T093 [P] Enable programs.firefoxpwa in WSL home-manager configuration
- [X] T094 Configure 1Password runtime.json integration in /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
- [X] T095 Verify 1Password and Walker integration tests pass (GREEN)
- [X] T096 Test full rebuild on hetzner-sway with dry-build first
- [X] T097 Apply configuration to hetzner-sway and verify all PWAs install
- [X] T098 Apply configuration to M1 Mac and verify all PWAs install
- [X] T099 Apply configuration to WSL and verify all PWAs install

**Checkpoint**: Declarative PWA installation working across all three configurations - all tests GREEN

---

## Phase 8: Edge Cases & Error Handling (TR-022)

**Purpose**: Test and handle all edge cases from spec.md

### Tests for Edge Cases

**⚠️ Write these tests FIRST - they will FAIL until error handling is implemented**

- [X] T100 [P] Write test for network failure during installation in /etc/nixos/tests/pwa-installation/integration/test-edge-network-failure.nix - expect FAIL
- [X] T101 [P] Write test for ULID collision detection in /etc/nixos/tests/pwa-installation/unit/test-edge-ulid-collision.nix - expect FAIL
- [X] T102 [P] Write test for manual PWA uninstall handling in /etc/nixos/tests/pwa-installation/integration/test-edge-manual-uninstall.nix - expect FAIL
- [X] T103 [P] Write test for unavailable manifest URLs in /etc/nixos/tests/pwa-installation/integration/test-edge-manifest-unavailable.nix - expect FAIL

### Implementation of Edge Case Handling

- [X] T104 [P] Add network failure handling in installPWAScript - retry logic with timeout
- [X] T105 [P] Add ULID collision detection in generateFirefoxPWAConfig with clear error message
- [X] T106 [P] Document manual uninstall behavior in quickstart.md (declarative config doesn't auto-remove)
- [X] T107 [P] Add manifest URL validation before installation attempt
- [X] T108 Verify all edge case tests pass (GREEN)

**Checkpoint**: All edge cases handled - tests GREEN, errors provide clear user guidance

---

## Phase 9: Polish, Documentation & Final Validation (TR-023, TR-024)

**Purpose**: Documentation, performance validation, and final end-to-end testing

### Performance & Coverage Validation

- [X] T109 [P] Run all unit tests, verify completion <30 seconds (TR-023)
- [X] T110 [P] Run all integration tests, verify completion <5 minutes (TR-024)
- [X] T111 Measure test coverage, verify ≥90% for shell scripts, 100% for Nix functions
- [X] T112 Generate test coverage report in /etc/nixos/tests/pwa-installation/coverage-report.txt

### Documentation

- [X] T113 [P] Complete quickstart.md with usage examples, troubleshooting, and common workflows in /etc/nixos/specs/056-declarative-pwa-installation/quickstart.md
- [X] T114 [P] Update CLAUDE.md with new PWA installation workflows and helper commands in /etc/nixos/CLAUDE.md
- [X] T115 Add inline comments to firefox-pwas-declarative.nix explaining ULID validation, manifest generation, and installation logic
- [X] T116 Document TDD workflow and test structure in /etc/nixos/tests/pwa-installation/README.md

### Final End-to-End Validation

- [X] T117 Run complete test suite (unit + integration + acceptance) on hetzner-sway - all tests must pass
- [X] T118 Run complete test suite on M1 Mac - all tests must pass
- [X] T119 Run complete test suite on WSL - all tests must pass
- [X] T120 Validate all PWAs install correctly with pwa-validate command on all three configurations
- [X] T121 Test launching PWAs via Walker on hetzner-sway and M1
- [X] T122 Test 1Password integration in installed PWAs - verify extension loads automatically
- [X] T123 Run full quickstart.md validation workflow on fresh hetzner-sway deployment
- [X] T124 Create migration guide for users with existing manual PWA installations in /etc/nixos/specs/056-declarative-pwa-installation/quickstart.md

**Checkpoint**: All tests GREEN across all platforms, documentation complete, feature ready for production

---

## Dependencies & Execution Order (TDD Workflow)

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately (test infrastructure first!)
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
  - **TDD Cycle**: Test → Fail (RED) → Implement → Pass (GREEN) → Refactor
- **User Stories (Phase 3-5)**: All depend on Foundational phase
  - **TDD Cycle**: Integration tests → Acceptance tests (all RED) → Implement → All tests GREEN
  - User Story 1 (P1): Must complete before US2
  - User Story 2 (P2): Depends on US1 core functionality
  - User Story 3 (P3): Can start in parallel with US2
- **Helper Commands (Phase 6)**: Depends on US1 core installation logic
- **Integration (Phase 7)**: Depends on US1, US2, US3
- **Edge Cases (Phase 8)**: Can run in parallel with Phase 7
- **Polish (Phase 9)**: Depends on all implementation phases

### TDD Workflow for Each Phase

**Critical Rule**: NEVER implement without failing test first

1. **Write Test** (T-XXX with "expect FAIL")
2. **Verify RED**: Run test, confirm it fails
3. **Implement** (T-YYY implementation task)
4. **Verify GREEN**: Run test, confirm it passes
5. **Refactor**: Improve code, tests stay green
6. **Commit**: Test + implementation together

### Parallel Opportunities

**Setup Phase (Phase 1)**:
- T002, T003, T004, T005 can all run in parallel

**Foundational Phase (Phase 2)**:
- Test writing: T007-T009 (validateULID tests) in parallel
- Test writing: T012-T014 (generateManifest tests) in parallel
- Test writing: T017-T020 (generateFirefoxPWAConfig tests) in parallel
- After tests written, implementations can proceed sequentially (T010, T015, T021)

**User Story 1 (Phase 3)**:
- All integration test writing (T025-T029) in parallel
- All acceptance test writing (T030-T032) in parallel
- Implementation tasks: T033-T034 in parallel, rest sequential

**User Story 2 (Phase 4)**:
- All integration test writing (T044-T046) in parallel
- All acceptance test writing (T047-T049) in parallel
- Implementation tasks: T050-T051 in parallel

**User Story 3 (Phase 5)**:
- All integration test writing (T058-T060) in parallel
- All acceptance test writing (T061-T063) in parallel
- Implementation tasks: T064-T065 in parallel

**Helper Commands (Phase 6)**:
- All test writing (T071-T075) in parallel
- All command packaging (T076-T081) in parallel

**Integration (Phase 7)**:
- T089-T090 (M1/WSL imports) in parallel
- T092-T093 (M1/WSL enable) in parallel

**Edge Cases (Phase 8)**:
- All test writing (T100-T103) in parallel
- All implementation (T104-T107) in parallel

---

## Success Metrics (Must be Validated by Tests)

After completing all tasks, the system should meet these criteria from spec.md:

- **SC-001**: PWAs ready within 5 minutes ✓ (validated by TR-009)
- **SC-002**: Zero config changes between machines ✓ (validated by TR-011)
- **SC-003**: Metadata propagates with single rebuild ✓ (validated by TR-018)
- **SC-004**: 100% PWAs installed ✓ (validated by TR-009, TR-015)
- **SC-005**: Authentication persists ✓ (validated by TR-014)
- **SC-006**: Idempotent rebuilds ✓ (validated by TR-010)
- **Test Coverage**: ≥90% ✓ (validated by Phase 9)
- **All Tests GREEN**: Unit + Integration + Acceptance ✓

---

## TDD Checklist (Use Before Each Implementation Task)

Before implementing ANY task:

- [ ] Test written for this task?
- [ ] Test executed and FAILED (RED)?
- [ ] Test has clear failure message?
- [ ] Test is independent (no dependencies)?
- [ ] Test data in fixtures (not hardcoded)?

After implementing:

- [ ] Test now PASSES (GREEN)?
- [ ] All other tests still pass?
- [ ] Code refactored for quality?
- [ ] Test + implementation committed together?

**⚠️ CRITICAL**: If ANY checkbox is unchecked, DO NOT PROCEED with implementation.

---

## Notes

- **TDD Mandate**: Tests MUST be written before implementation
- **RED before GREEN**: Always verify test fails before implementing
- **100% Test Coverage**: All Nix functions must have tests
- **[P] tasks** = different files, can run in parallel
- **[Story] label** = maps to user story for traceability
- Always test with `nix build .#checks.x86_64-linux.pwa-unit-tests` before implementing
- Commit test + implementation as atomic unit
- CI pipeline MUST be green before merging
