# Tasks: Consolidate and Validate i3 Project Management System

**Input**: Design documents from `/etc/nixos/specs/014-create-a-new/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT requested in this feature - focus is on consolidation, cleanup, and validation

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story

---

## 📘 Implementation Resources

**Phase 1 COMPLETE** ✅ - Validation infrastructure ready

**For Phase 2+ Implementation**:
- **🔧 Implementation Guide**: `IMPLEMENTATION_GUIDE.md` - Complete guide with 3 working examples
- **📊 Progress Summary**: `PROGRESS_SUMMARY.md` - Current status and timeline
- **⚡ Quick Reference**: `QUICK_REFERENCE.md` - Cheat sheet for script conversion
- **✅ Validation Scripts**: `/etc/nixos/tests/validate-*.sh` - Ready to use

**Start Here**: Read `IMPLEMENTATION_GUIDE.md` before beginning Phase 2

---

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
This is a NixOS system integration project. All paths are in `/etc/nixos/` repository:
- **Modules**: `home-modules/desktop/i3/`, `home-modules/desktop/i3blocks/`
- **Scripts**: Generated declaratively in modules (not separate files)
- **Documentation**: `docs/`, `CLAUDE.md`, feature spec in `specs/014-create-a-new/`

---

## Phase 1: Setup (Validation Infrastructure)

**Purpose**: Create validation infrastructure and prepare for constitutional compliance remediation

- [X] T001 [P] Create validation script `tests/validate-i3-schema.sh` to verify window marks follow `project:NAME` format
- [X] T002 [P] Create validation script `tests/validate-json-schemas.sh` to validate project configs against contracts
- [X] T003 [P] Create automated test script `tests/i3-project-test.sh` for xdotool-based UI testing

**Checkpoint**: Validation tools ready for testing during implementation

---

## Phase 2: Foundational (Constitutional Compliance Remediation)

**Purpose**: Core infrastructure fixes that MUST be complete before user story validation can proceed

**⚠️ CRITICAL**: These constitutional violations block full compliance - must be fixed first

### Script Declarative Conversion (Priority 1 - CRITICAL)

- [X] T004 Convert `home-modules/desktop/i3-project-manager.nix` to use `text = ''...''` for all scripts instead of `source = ./file.sh`
- [X] T005 [US3] Convert `scripts/i3-project-common.sh` to inline Nix function library with `${pkgs.*/bin/*}` paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T006 [US1] Convert `scripts/project-create.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T007 [US1] Convert `scripts/project-switch.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T008 [US1] Convert `scripts/project-clear.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T009 [US1] Convert `scripts/project-list.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T010 [US1] Convert `scripts/project-current.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T011 [US1] Convert `scripts/project-delete.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T012 [US5] Convert `scripts/launch-code.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T013 [US5] Convert `scripts/launch-ghostty.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T014 [US5] Convert `scripts/launch-lazygit.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [X] T015 [US5] Convert `scripts/launch-yazi.sh` to declarative generation with Nix-interpolated binary paths in `home-modules/desktop/i3-project-manager.nix`
- [N/A] T016 [US6] Convert `scripts/project-logs.sh` - Script does not exist, skipped
- [X] T017 [US4] Convert i3blocks project indicator `i3blocks/scripts/project.sh` to declarative generation in `home-modules/desktop/i3blocks/default.nix`
- [X] T018 [P] Convert i3blocks CPU script `i3blocks/scripts/cpu.sh` to declarative generation in `home-modules/desktop/i3blocks/default.nix`
- [X] T019 [P] Convert i3blocks memory script `i3blocks/scripts/memory.sh` to declarative generation in `home-modules/desktop/i3blocks/default.nix`
- [X] T020 [P] Convert i3blocks network script `i3blocks/scripts/network.sh` to declarative generation in `home-modules/desktop/i3blocks/default.nix`
- [X] T021 [P] Convert i3blocks datetime script `i3blocks/scripts/datetime.sh` to declarative generation in `home-modules/desktop/i3blocks/default.nix`

### Binary Path Standardization (integrated with T004-T021)

Binary paths will be replaced during script conversion tasks above with:
- `${pkgs.bash}/bin/bash` - Shebangs
- `${pkgs.coreutils}/bin/{date,cat,echo,mv,rm,stat,cut,head,tail}` - Core utilities
- `${pkgs.jq}/bin/jq` - JSON parsing (100+ occurrences)
- `${pkgs.gawk}/bin/awk`, `${pkgs.gnugrep}/bin/grep`, `${pkgs.gnused}/bin/sed` - Text processing
- `${pkgs.i3}/bin/i3-msg` - i3 IPC commands
- `${pkgs.xdotool}/bin/xdotool` - Window manipulation
- `${pkgs.vscode}/bin/code`, `${pkgs.rofi}/bin/rofi` - Applications
- `${pkgs.procps}/bin/{top,ps}`, `${pkgs.iproute2}/bin/ip` - System monitoring

### Polybar Remnants Cleanup

- [X] T022 [US4] Remove polybar indicator script deployment from `home-modules/desktop/i3-project-manager.nix` (lines ~200-204)
- [X] T023 [US4] Remove `i3_send_tick()` function calls from converted `project-switch.sh` in `home-modules/desktop/i3-project-manager.nix`
- [X] T024 [US4] Remove `i3_send_tick()` function calls from converted `project-clear.sh` in `home-modules/desktop/i3-project-manager.nix`
- [X] T025 [US4] Update comments in `home-modules/desktop/i3.nix` line 29: "for polybar" → "for i3bar"
- [X] T026 [US4] Update comments in `home-modules/desktop/i3.nix` line 32: "show on polybar" → "show on i3bar"
- [X] T027 [US4] Delete source file `home-modules/desktop/scripts/polybar-i3-project-indicator.py` (no longer deployed)

### Redundant State File Cleanup

- [X] T028 [US2] Remove any code that writes to `~/.config/i3/window-project-map.json` from project scripts (violates FR-019)
- [X] T029 [US2] Remove any code that reads from `~/.config/i3/window-project-map.json` from project scripts

**Checkpoint**: All scripts declaratively generated, all binary paths use Nix interpolation, polybar remnants removed, redundant state tracking eliminated

---

## Phase 3: User Story 1 - Complete Project Lifecycle Management (Priority: P1) 🎯 MVP

**Goal**: Users can create projects, list them, switch between them with keyboard shortcuts, and see status bar feedback

**Independent Test**: Create project → list projects → switch via Win+P → verify status bar → switch to different project → verify state

### Implementation for User Story 1

- [X] T030 [US1] Verify project-create functionality after script conversion by creating test project via CLI
- [X] T031 [US1] Verify project-list functionality displays all projects with icons and paths
- [X] T032 [US1] Verify project-switch functionality moves windows and updates active-project file
- [X] T033 [US1] Verify project-clear functionality resets active-project and shows "No Project"
- [X] T034 [US1] Verify rofi project switcher (Win+P) displays projects and activates selected project
- [X] T035 [US1] Test rapid project switching (multiple switches within 1 second) to verify no race conditions
- [X] T036 [US1] Improve active-project file write atomicity using atomic rename pattern in converted project-switch.sh

**Checkpoint**: Complete project lifecycle working end-to-end - can create, list, switch, clear projects

---

## Phase 4: User Story 2 - i3 JSON Schema Alignment (Priority: P1)

**Goal**: Verify project state uses i3 native JSON schema for runtime queries

**Independent Test**: Create project → query i3 tree for marks → verify window associations use marks → validate no custom schemas

### Implementation for User Story 2

- [X] T037 [US2] Run validation script to verify all window marks follow `project:NAME` format using `i3-msg -t get_tree`
- [X] T038 [US2] Verify active-project file contains only minimal extensions (name, display_name, icon) not available in i3 state
- [X] T039 [US2] Verify project config files are recognized as metadata (not i3 tree state) per research.md clarification
- [X] T040 [US2] Delete `~/.config/i3/window-project-map.json` file if it exists (manual cleanup on live system)
- [X] T041 [US2] Update spec.md US2 description to clarify "Runtime state uses i3 native queries, configuration is metadata"

**Checkpoint**: i3 JSON schema alignment verified - all runtime state queries use i3 IPC, no custom schemas

---

## Phase 5: User Story 3 - Native i3 Integration Validation (Priority: P1)

**Goal**: Ensure all project operations use i3 native features (marks, IPC, criteria syntax)

**Independent Test**: Inspect scripts for i3-msg usage → verify marks in i3 tree → confirm no custom window tracking

### Implementation for User Story 3

- [ ] T042 [US3] Audit converted project scripts to verify 100% of window queries use `i3-msg -t get_tree`
- [ ] T043 [US3] Audit converted project scripts to verify 100% of window movements use `i3-msg '[con_mark="..."]'` criteria syntax
- [ ] T044 [US3] Verify workspace queries use `i3-msg -t get_workspaces` without transformation
- [ ] T045 [US3] Test window marking by launching application and verifying mark appears in `i3-msg -t get_tree | jq '.. | .marks'`
- [ ] T046 [US3] Test scratchpad movement by switching projects and verifying windows moved via `i3-msg -t get_tree | jq '.. | select(.name == "__i3_scratch")'`

**Checkpoint**: Native i3 integration validated - all operations use i3 native commands and queries

---

## Phase 6: User Story 4 - Status Bar Project Indicator Integration (Priority: P1)

**Goal**: Status bar displays current project with icon and updates within 1 second of project switch

**Independent Test**: Activate projects → observe status bar → clear project → verify "No Project" display → test edge cases

### Implementation for User Story 4

- [ ] T047 [US4] Verify status bar shows "∅ No Project" when no active project after polybar cleanup
- [ ] T048 [US4] Verify status bar shows project icon and name when project active (e.g., " NixOS")
- [ ] T049 [US4] Test status bar update timing - measure time from `project-switch` command to visual update (<1s requirement)
- [ ] T050 [US4] Test status bar with malformed active-project JSON - verify graceful fallback to "No Project"
- [ ] T051 [US4] Test status bar with missing icon field - verify displays project name without crash
- [ ] T052 [US4] Add error logging to converted project-switch.sh when `pkill -RTMIN+10 i3blocks` fails

**Checkpoint**: Status bar integration complete - displays project context accurately with <1s updates

---

## Phase 7: User Story 5 - Application Window Tracking and Scratchpad Management (Priority: P2)

**Goal**: Project-scoped applications automatically show/hide when switching projects, global apps remain visible

**Independent Test**: Open VS Code in project A → switch to project B → verify VS Code hidden → switch back → verify VS Code restored → verify Firefox (global) stays visible

### Implementation for User Story 5

- [ ] T053 [US5] Test application launch with project mark using converted launch-code.sh (Win+C keybinding)
- [ ] T054 [US5] Test application launch with project mark using converted launch-ghostty.sh (Win+Return keybinding)
- [ ] T055 [US5] Verify project-scoped applications (VS Code, Ghostty, lazygit, yazi) receive `project:NAME` mark on launch
- [ ] T056 [US5] Verify global applications (Firefox, K9s, PWAs) do NOT receive project marks
- [ ] T057 [US5] Test window scratchpad hiding when switching away from project - verify windows move to scratchpad
- [ ] T058 [US5] Test window restoration when switching back to project - verify windows return from scratchpad
- [ ] T059 [US5] Verify app-classes.json classification is correctly read by launcher scripts after conversion

**Checkpoint**: Application window tracking working - scoped apps hide/show correctly, global apps remain visible

---

## Phase 8: User Story 6 - Real-Time Event Logging and Debugging (Priority: P2)

**Goal**: System logs all operations with timestamps, log viewer available for debugging

**Independent Test**: Open log viewer → trigger project operations → verify events appear with timestamps and context

### Implementation for User Story 6

- [ ] T060 [US6] Verify logging infrastructure exists - check `~/.config/i3/project-system.log` file created
- [ ] T061 [US6] Verify all converted project scripts use centralized `log()` function with proper format `[TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE`
- [ ] T062 [US6] Test log viewer command `project-logs` displays logs with color coding by level
- [ ] T063 [US6] Verify project switch operation produces complete event sequence in logs (switch command → mark queries → window movements → status bar signal → completion)
- [ ] T064 [US6] Test log levels: DEBUG for i3-msg commands, INFO for operations, WARN for recoverable errors, ERROR for failures
- [ ] T065 [US6] Verify log rotation works - create logs >10MB and verify rotation to .1, .2, .3, .4, .5 files
- [ ] T066 [US6] Test debug mode increases verbosity - set I3_PROJECT_DEBUG=1 and verify detailed i3 IPC responses logged

**Checkpoint**: Logging system complete - all operations logged, log viewer working, rotation tested

---

## Phase 9: User Story 7 - Multi-Monitor Workspace Management (Priority: P3)

**Goal**: Workspaces distribute across monitors based on project configuration

**Independent Test**: Configure workspace-to-output assignments → connect/disconnect monitors → verify workspace distribution

### Implementation for User Story 7

- [ ] T067 [US7] Test workspace-to-output assignments by adding workspaceOutputs to project config
- [ ] T068 [US7] Verify workspace appears on specified monitor when project activates using `i3-msg -t get_workspaces | jq '.[].output'`
- [ ] T069 [US7] Test workspace fallback when specified monitor disconnected - verify i3 assigns to available monitor
- [ ] T070 [US7] Test manual workspace movement persists - move workspace to different monitor, deactivate project, reactivate, verify workspace returns to configured monitor
- [ ] T071 [US7] Document multi-monitor setup in quickstart.md with example commands to find output names

**Checkpoint**: Multi-monitor support validated - workspaces distribute correctly, handle monitor changes gracefully

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

### Documentation Updates

- [ ] T072 [P] Update `CLAUDE.md` section "Project Management Workflow" to reference i3blocks instead of polybar
- [ ] T073 [P] Update `docs/ARCHITECTURE.md` if it references polybar or pre-consolidation architecture
- [ ] T074 [P] Update quickstart.md with final testing results and any discovered edge cases
- [ ] T075 [P] Create `docs/CONSTITUTIONAL_COMPLIANCE.md` documenting the declarative script generation pattern for future reference

### Validation and Testing

- [ ] T076 Run complete project lifecycle test using `tests/i3-project-test.sh` automated xdotool testing
- [ ] T077 Run JSON schema validation using `tests/validate-json-schemas.sh` on all project configs
- [ ] T078 Run i3 schema validation using `tests/validate-i3-schema.sh` on window marks and tree state
- [ ] T079 Test i3 restart scenario - restart i3, verify project state persists, verify marks retained
- [ ] T080 Test edge case: active-project file with invalid JSON - verify system handles gracefully
- [ ] T081 Test edge case: project config file missing for active project - verify system handles gracefully
- [ ] T082 Test edge case: launching application when i3 IPC unavailable - verify graceful failure with logging

### Code Cleanup

- [ ] T083 Remove empty or unused functions from converted scripts (if any i3_send_tick remnants exist)
- [ ] T084 Add shellcheck validation to NixOS build for all converted scripts using `pkgs.shellcheck`
- [ ] T085 Verify no hardcoded paths remain in converted scripts - audit for `/usr/bin`, `/bin`, hardcoded tool names

### Performance Validation

- [ ] T086 Measure project switch timing with 10 windows - verify <1 second requirement met
- [ ] T087 Measure status bar update timing - verify <1 second from project-switch to visual update
- [ ] T088 Measure i3 event logging latency - verify <100ms from event to log entry

### Final Integration

- [ ] T089 Test complete workflow from quickstart.md "Daily Development Routine" scenario
- [ ] T090 Test complete workflow from quickstart.md "Multi-Project Debugging" scenario
- [ ] T091 Rebuild NixOS configuration with `nixos-rebuild dry-build --flake .#hetzner` to verify no errors
- [ ] T092 Deploy to Hetzner reference system with `nixos-rebuild switch --flake .#hetzner`
- [ ] T093 Verify all success criteria from spec.md (SC-001 through SC-020) are met
- [ ] T094 Create summary report of constitutional compliance improvements and remaining issues (if any)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user story validation
  - Script conversion (T004-T021) must complete before user stories can be tested
  - Cleanup tasks (T022-T029) can run in parallel with later conversion tasks
- **User Stories (Phase 3-9)**: All depend on Foundational phase completion
  - User Story 1 (Phase 3): Can start after T004-T010 complete
  - User Story 2 (Phase 4): Can start after T028-T029 complete
  - User Story 3 (Phase 5): Can start after T004-T021 complete
  - User Story 4 (Phase 6): Can start after T017, T022-T027 complete
  - User Story 5 (Phase 7): Can start after T012-T015 complete
  - User Story 6 (Phase 8): Can start after T016 complete
  - User Story 7 (Phase 9): Can start after Phase 2 complete (uses existing scripts)
- **Polish (Phase 10)**: Depends on all user stories being validated

### User Story Dependencies

- **User Story 1 (P1)**: Requires T004-T010 (core project management scripts converted)
- **User Story 2 (P1)**: Requires T028-T029 (redundant state cleanup) - can run parallel to US1
- **User Story 3 (P1)**: Requires T004-T021 (all scripts converted to verify i3 native usage)
- **User Story 4 (P1)**: Requires T017, T022-T027 (i3blocks script + polybar cleanup)
- **User Story 5 (P2)**: Requires T012-T015 (launcher scripts converted) - can run parallel to US1-4
- **User Story 6 (P2)**: Requires T016 (log viewer script converted) - can run parallel to US1-5
- **User Story 7 (P3)**: Independent after Phase 2 - can run parallel to US5-6

### Within Each Phase

**Foundational (Phase 2)**:
- T004 must complete before T005-T021 (establishes declarative pattern)
- T005-T021 can partially parallelize (different scripts, but all modify same module file)
- T022-T027 can run in parallel with later script conversions (different files)
- T028-T029 can run in parallel after T005-T007 complete (searches converted scripts)

**User Stories**:
- Tasks within each user story are sequential (test after implementation)
- Different user stories can proceed in parallel once their foundational dependencies are met

### Parallel Opportunities

**Phase 1 (Setup)**:
- T001, T002, T003 can all run in parallel (different validation scripts)

**Phase 2 (Foundational)**:
- T018-T021 can run in parallel (different i3blocks scripts, different sections of default.nix)
- T022-T027 can run in parallel (different cleanup tasks, different files)

**Phase 3-9 (User Stories)**:
- Once Phase 2 completes, multiple user stories can be validated in parallel
- Example: US1, US2, US4 validation can happen simultaneously after their dependencies met

**Phase 10 (Polish)**:
- T072-T075 documentation updates can run in parallel
- T076-T082 validation tests can run in parallel
- T089-T090 workflow tests can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# After T004 establishes pattern, convert multiple scripts in parallel:
Task: "Convert scripts/project-create.sh to declarative generation" (T006)
Task: "Convert scripts/project-list.sh to declarative generation" (T009)
Task: "Convert scripts/project-current.sh to declarative generation" (T010)

# Cleanup tasks in parallel:
Task: "Remove polybar indicator script deployment" (T022)
Task: "Update comments in i3.nix" (T025)
Task: "Delete polybar-i3-project-indicator.py source file" (T027)
```

---

## Implementation Strategy

### MVP First (Priority P1 User Stories Only)

1. Complete Phase 1: Setup → Validation tools ready
2. Complete Phase 2: Foundational → **CRITICAL** constitutional compliance achieved
3. Complete Phase 3: User Story 1 → Core project lifecycle working
4. Complete Phase 4: User Story 2 → i3 JSON schema alignment verified
5. Complete Phase 5: User Story 3 → Native i3 integration validated
6. Complete Phase 6: User Story 4 → Status bar integration working
7. **STOP and VALIDATE**: Test all P1 stories independently
8. Deploy/demo if ready → Constitutional compliance achieved, core functionality validated

### Incremental Delivery

1. Complete Setup + Foundational → Constitution compliant, scripts declarative
2. Add User Story 1 → Test independently → Core lifecycle works (create/switch/list)
3. Add User Story 2 → Test independently → i3 schema alignment verified
4. Add User Story 3 → Test independently → i3 native integration confirmed
5. Add User Story 4 → Test independently → Status bar working (MVP complete!)
6. Add User Story 5 → Test independently → Window management working
7. Add User Story 6 → Test independently → Logging and debugging available
8. Add User Story 7 → Test independently → Multi-monitor support added
9. Each story adds value without breaking previous stories

### Constitutional Compliance First Strategy

**Rationale**: Phase 2 (Foundational) fixes critical constitutional violations that affect all user stories.

**Approach**:
1. Phase 1: Create validation tools (T001-T003)
2. **Phase 2: Fix all constitutional violations (T004-T029)** ← PRIORITY
   - Convert all scripts to declarative generation
   - Standardize all binary paths
   - Remove polybar remnants
   - Clean up redundant state files
3. Phase 3+: Validate user stories using constitutionally compliant scripts

**Benefit**: Ensures all subsequent testing uses proper declarative configuration, achieving constitutional compliance before feature validation.

---

## Notes

- **[P]** tasks = different files, no dependencies
- **[Story]** label maps task to specific user story for traceability
- Each user story should be independently validatable after its dependencies complete
- **No test tasks** included - feature focuses on consolidation and validation, not test creation
- **Foundational phase is critical** - constitutional violations must be fixed before user story validation
- Commit after each major task group (script conversion batch, user story validation batch)
- Stop at any checkpoint to validate independently
- **xdotool testing**: Be careful not to close active terminal - target specific window IDs
- All timing measurements should be logged for SC-009, SC-016, SC-017 compliance verification

---

## Success Criteria Mapping

Tasks map to success criteria from spec.md:

- **SC-001**: T030-T036 (complete project lifecycle in <60s)
- **SC-002-SC-003**: T037-T041 (i3 layout JSON validation, minimal extensions)
- **SC-004-SC-007**: T042-T046 (i3 marks usage, native commands, workspace queries)
- **SC-008-SC-009**: T047-T052 (status bar updates <1s, edge cases)
- **SC-010**: T035 (handle 3 concurrent projects)
- **SC-011**: T076 (automated tests don't close terminal)
- **SC-012**: T079 (i3 restart state persistence)
- **SC-013**: T022-T027 (no code duplication)
- **SC-014**: T039 (append_layout compatibility clarified)
- **SC-015-SC-020**: T060-T066, T088 (logging system validation)

All 20 success criteria covered by task plan.

---

**Total Tasks**: 94 tasks across 10 phases
**Critical Path**: Setup (3) → Foundational (26) → User Story Validation (55) → Polish (10)
**Estimated Complexity**: High (constitutional remediation) → Medium (validation) → Low (polish)
**Testing Strategy**: Automated validation scripts + manual xdotool testing + quickstart workflow validation
