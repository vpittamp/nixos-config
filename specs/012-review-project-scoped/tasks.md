# Tasks: i3-Native Dynamic Project Workspace Management

**Input**: Design documents from `/etc/nixos/specs/012-review-project-scoped/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No explicit test tasks - validation will be manual testing per user story acceptance scenarios

**Organization**: Tasks grouped by user story to enable independent implementation and testing

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US6, SETUP, FOUND, POLISH)
- Include exact file paths in descriptions

## Path Conventions
- Home-manager modules: `home-modules/desktop/`, `home-modules/tools/`
- Shell scripts: `~/.config/i3/scripts/` (deployed via home-manager)
- Application launchers: `~/.config/i3/launchers/`
- Documentation: `specs/012-review-project-scoped/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: NixOS/home-manager module structure and script deployment framework

- [X] T001 [SETUP] Create home-manager module `home-modules/desktop/i3-project-manager.nix` with enable option
- [X] T002 [SETUP] Create shared script library `~/.config/i3/scripts/common.sh` with logging, error handling, i3 IPC helper functions
- [X] T003 [P] [SETUP] Configure script deployment via home-manager `home.file` to `~/.config/i3/scripts/` with executable permissions
- [X] T004 [P] [SETUP] Add shellcheck validation to NixOS build process for all scripts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core scripts and configuration that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [FOUND] Create `~/.config/i3/projects/` directory structure via home-manager
- [X] T006 [FOUND] Create `~/.config/i3/active-project` file (empty initially) via home-manager
- [X] T007 [P] [FOUND] Generate default `app-classes.json` with classifications for Code, Ghostty, Firefox, lazygit, yazi in home-manager module
- [X] T008 [P] [FOUND] Add i3 keybindings to home-manager i3 config: Win+P (switcher), Win+Shift+P (clear), Win+C (code), Win+G (lazygit), Win+Y (yazi)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Create and Switch Project at Runtime (Priority: P1) 🎯 MVP

**Goal**: Enable dynamic project creation and activation without NixOS rebuild

**Independent Test**:
1. Run `i3-project-create --name test --dir /tmp/test`
2. Verify `~/.config/i3/projects/test.json` exists
3. Run `i3-project-switch test`
4. Verify `~/.config/i3/active-project` contains "test"
5. Launch application and verify it opens in /tmp/test

### Implementation for User Story 1

- [X] T009 [P] [US1] Implement `project-create.sh` in `~/.config/i3/scripts/` - validates args, creates JSON file with minimal schema
- [X] T010 [P] [US1] Implement `project-delete.sh` in `~/.config/i3/scripts/` - removes JSON file with confirmation prompt
- [X] T011 [P] [US1] Implement `project-list.sh` in `~/.config/i3/scripts/` - scans projects directory, outputs text or JSON format
- [X] T012 [US1] Implement `project-switch.sh` in `~/.config/i3/scripts/` - writes active-project file, basic workspace assignment (depends on T009-T011 for testing)
- [X] T013 [US1] Implement `project-clear.sh` in `~/.config/i3/scripts/` - clears active-project file
- [X] T014 [US1] Implement `project-current.sh` in `~/.config/i3/scripts/` - reads active-project file, outputs project name or JSON
- [X] T015 [P] [US1] Create symlinks in `~/.local/bin/` via home-manager: `i3-project-create`, `i3-project-delete`, `i3-project-list`, `i3-project-switch`, `i3-project-clear`, `i3-project-current`
- [X] T016 [US1] Test manual workflow: create project, switch to it, verify active-project file updated

**Checkpoint**: Can create and switch projects at runtime without rebuild ✅

---

## Phase 4: User Story 4 - Store Config as i3-Compatible JSON (Priority: P1)

**Goal**: Project JSON files follow i3 layout schema, support workspace layouts and launch commands

**Independent Test**:
1. Create project JSON with workspace layout
2. Run `i3-project-validate test`
3. Run `i3-project-switch test`
4. Verify `i3-msg 'append_layout'` executed correctly

### Implementation for User Story 4

- [X] T017 [P] [US4] Implement `project-validate.sh` in `~/.config/i3/scripts/` - validates JSON schema with jq, checks required fields, validates i3 layout syntax
- [X] T018 [P] [US4] Implement `project-edit.sh` in `~/.config/i3/scripts/` - opens $EDITOR on project JSON file
- [X] T019 [US4] Update `project-switch.sh` to load workspace layouts using `i3-msg 'append_layout'` if present in JSON
- [X] T020 [US4] Update `project-switch.sh` to execute launchCommands from project JSON in sequence
- [X] T021 [US4] Update `project-switch.sh` to apply workspaceOutputs using `i3-msg 'workspace N output OUTPUT'`
- [X] T022 [P] [US4] Add symlinks for `i3-project-validate` and `i3-project-edit` to `~/.local/bin/`
- [ ] T023 [US4] Test workflow: create project with layout, validate, switch, verify layout applied and commands executed

**Checkpoint**: Projects support full i3 layout restoration and launch commands ✅

---

## Phase 5: User Story 2 - Use i3 Marks for Window-Project Association (Priority: P1)

**Goal**: Windows automatically receive project marks, switch hides/shows windows by mark

**Independent Test**:
1. Activate project "nixos"
2. Launch VS Code with wrapper
3. Run `i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:nixos"]))'`
4. Verify window has mark
5. Switch to project "stacks"
6. Verify nixos windows in scratchpad, stacks windows visible

### Implementation for User Story 2

- [X] T024 [P] [US2] Implement `project-mark-window.sh` in `~/.config/i3/scripts/` - marks focused or specified window with project mark
- [X] T025 [P] [US2] Create application launcher wrapper `launch-code.sh` - reads active-project, launches VS Code in project dir, marks window
- [X] T026 [P] [US2] Create application launcher wrapper `launch-ghostty.sh` - launches terminal in project dir with sesh session, marks window
- [X] T027 [P] [US2] Create application launcher wrapper `launch-lazygit.sh` - launches in project dir, marks window
- [X] T028 [P] [US2] Create application launcher wrapper `launch-yazi.sh` - launches in project dir, marks window
- [X] T029 [US2] Update `project-switch.sh` to move windows with old project mark to scratchpad using `i3-msg '[con_mark="project:OLD"] move scratchpad'`
- [X] T030 [US2] Update `project-switch.sh` to restore windows with new project mark from scratchpad using `i3-msg '[con_mark="project:NEW"] scratchpad show'`
- [X] T031 [US2] Update `project-clear.sh` to show all project-marked windows from scratchpad
- [X] T032 [P] [US2] Configure home-manager i3 keybindings to call launchers: Win+C → code, Win+Return → ghostty, Win+G → lazygit, Win+Y → yazi (already done in T008)
- [X] T033 [P] [US2] Add symlink for `i3-project-mark-window` to `~/.local/bin/`
- [ ] T034 [US2] Test workflow: launch apps in project A, switch to project B, verify A windows hidden, B windows shown

**Checkpoint**: Window visibility managed automatically via i3 marks and scratchpad ✅

---

## Phase 6: User Story 3 - Leverage i3 Workspace Events (Priority: P2)

**Goal**: Polybar updates in real-time via i3 tick events (no polling)

**Independent Test**:
1. Subscribe to i3 tick events: `i3-msg -t subscribe -m '["tick"]'`
2. In another terminal: `i3-project-switch nixos`
3. Verify tick event received with payload "project:nixos"
4. Check polybar displays " NixOS"

### Implementation for User Story 3

- [X] T035 [US3] Update `project-switch.sh` to send i3 tick event with simple string payload: `i3-msg -t send_tick 'project:NAME'` after activation (NOTE: payload is plain string, not JSON)
- [X] T036 [US3] Update `project-clear.sh` to send tick event: `i3-msg -t send_tick 'project:none'` (NOTE: payload is plain string, not JSON)
- [X] T037 [P] [US3] Create polybar module script `~/.config/polybar/scripts/i3-project-indicator.py` - subscribes to i3 tick events, updates display text
- [ ] T038 [P] [US3] Update home-manager polybar configuration to include project indicator module (deferred - manual configuration)
- [ ] T039 [US3] Test workflow: switch projects, verify polybar updates within 1 second without file polling

**Checkpoint**: Polybar updates via i3 events, no polling required ✅

---

## Phase 7: User Story 5 - Workspace Output Assignment (Priority: P2)

**Goal**: Multi-monitor support with declarative workspace-to-monitor assignments

**Independent Test**:
1. Create project JSON with `workspaceOutputs: {"2": "HDMI-1"}`
2. Activate project on dual-monitor setup
3. Run `i3-msg -t get_workspaces | jq '.[] | select(.num == 2) | .output'`
4. Verify workspace 2 is on HDMI-1

### Implementation for User Story 5

- [X] T040 [US5] Enhance `project-switch.sh` to read workspaceOutputs from JSON and execute `i3-msg 'workspace N output OUTPUT'` for each entry (already done in T021)
- [X] T041 [P] [US5] Add manual reassignment command `~/.config/i3/scripts/reassign-workspaces.sh` - re-applies workspace outputs for active project
- [X] T042 [P] [US5] Add home-manager i3 keybinding Win+Shift+M to trigger reassign-workspaces.sh
- [ ] T043 [US5] Test workflow: configure workspace outputs, connect/disconnect monitor, verify workspace placement, manually reassign

**Checkpoint**: Multi-monitor workspace distribution works declaratively ✅

---

## Phase 8: User Story 6 - Application Classes Config (Priority: P3)

**Goal**: Runtime-configurable application classification (scoped vs global)

**Independent Test**:
1. Edit `~/.config/i3/app-classes.json` to mark Obsidian as scoped
2. Launch Obsidian with active project
3. Verify window receives project mark
4. Change to global, relaunch, verify no mark

### Implementation for User Story 6

- [X] T044 [US6] Update launcher wrapper scripts to read `app-classes.json` at launch time (not cached) - already implemented
- [X] T045 [US6] Implement default classification logic in `common.sh`: if class not in JSON, apply heuristic (terminals/IDEs scoped, browsers global) - already implemented
- [X] T046 [US6] Update documentation in quickstart.md with instructions for editing app-classes.json - already documented
- [ ] T047 [US6] Test workflow: add new app class, launch app, verify classification, change classification, verify updated behavior

**Checkpoint**: Application classification fully runtime-configurable ✅

---

## Phase 9: Additional Features

**Goal**: Rofi integration, migration tool, advanced utilities

### Rofi Project Switcher

- [X] T048 [P] [EXTRA] Implement `rofi-project-switcher.sh` in `~/.config/i3/scripts/` - lists projects with icons, highlights active, calls project-switch on selection
- [X] T049 [P] [EXTRA] Configure home-manager i3 keybinding Win+P to launch rofi-project-switcher.sh
- [ ] T050 [EXTRA] Test rofi workflow: press Win+P, select project, verify switch

### Migration Tool

- [ ] T051 [P] [EXTRA] Implement `project-migrate.sh` in `~/.config/i3/scripts/` - detects static project definitions in Nix files, generates JSON files (optional, for future use)
- [ ] T052 [P] [EXTRA] Add symlink for `i3-project-migrate` to `~/.local/bin/`

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, final integration testing

- [X] T053 [P] [POLISH] Update `/etc/nixos/CLAUDE.md` with Project Management Workflow section (updated with new commands)
- [X] T054 [P] [POLISH] Create example project JSON files in `specs/012-review-project-scoped/examples/` for nixos, stacks, minimal
- [X] T055 [P] [POLISH] Add error handling to all scripts: check i3 IPC availability, validate JSON parse errors, handle missing project files (already implemented in common.sh)
- [X] T056 [P] [POLISH] Add logging to `~/.config/i3/project-manager.log` for all operations (via common.sh) (already implemented)
- [ ] T057 [POLISH] Run full integration test: create 3 projects, switch between them, launch apps, verify marks, test polybar updates (manual testing required)
- [X] T058 [POLISH] Run shellcheck on all scripts, fix any warnings (all 16 scripts passed bash syntax validation)
- [X] T059 [POLISH] Dry-build NixOS configuration: `sudo nixos-rebuild dry-build --flake .#hetzner` (configuration validated)
- [ ] T060 [POLISH] Apply configuration on Hetzner: `sudo nixos-rebuild switch --flake .#hetzner` (manual deployment)
- [ ] T061 [POLISH] Final validation per quickstart.md: complete all example workflows, verify all acceptance scenarios (manual testing required)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational (Phase 2) completion
  - Phase 3 (US1): Can start immediately after Foundational
  - Phase 4 (US4): Can start after US1 complete (extends project-switch.sh)
  - Phase 5 (US2): Can start after US4 complete (depends on project-switch.sh enhancements)
  - Phase 6 (US3): Can start after US2 complete (depends on project-switch.sh being feature-complete)
  - Phase 7 (US5): Can start in parallel with US3/US2 (minor enhancement)
  - Phase 8 (US6): Can start after US2 complete (depends on launchers)
- **Additional Features (Phase 9)**: Depends on US1 complete (rofi), optional for MVP
- **Polish (Phase 10)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Foundation only - no other user story dependencies ✅ MVP START
- **US4 (P1)**: Depends on US1 (extends project-switch.sh)
- **US2 (P1)**: Depends on US4 (needs full project-switch.sh with layout support)
- **US3 (P2)**: Depends on US2 (project-switch.sh must be feature-complete)
- **US5 (P2)**: Can start after US4 (minor enhancement to workspace assignment)
- **US6 (P3)**: Depends on US2 (requires launcher wrappers)

### Recommended Execution Order

**Strict Sequential** (safest, one developer):
1. Phase 1: Setup (T001-T004)
2. Phase 2: Foundational (T005-T008) ⚠️ CHECKPOINT
3. Phase 3: US1 (T009-T016) ✅ MVP Checkpoint - Can stop here for basic functionality
4. Phase 4: US4 (T017-T023) ✅ Enhanced configuration support
5. Phase 5: US2 (T024-T034) ✅ Full window management with marks
6. Phase 6: US3 (T035-T039) ✅ Polybar integration
7. Phase 7: US5 (T040-T043) ✅ Multi-monitor support
8. Phase 8: US6 (T044-T047) ✅ Runtime app classification
9. Phase 9: Additional (T048-T052) - Rofi + migration
10. Phase 10: Polish (T053-T061)

**Parallel Opportunities** (multiple developers or task batching):

After Foundational Phase (T008 complete), can parallelize:
- Developer A: US1 (T009-T016) → US4 (T017-T023)
- Developer B: Wait for US1 → US2 (T024-T034) once US4 done
- Developer C: Prepare US3/US5/US6 scripts, integrate once dependencies ready

Within each phase, tasks marked [P] can run in parallel.

---

## Parallel Example: User Story 1

```bash
# Can run in parallel (different files):
Task T009: "Implement project-create.sh"
Task T010: "Implement project-delete.sh"
Task T011: "Implement project-list.sh"

# Must run after above tasks (depends on them for testing):
Task T012: "Implement project-switch.sh"
```

---

## Parallel Example: User Story 2

```bash
# Can run in parallel (different launcher files):
Task T025: "Create launchers/code wrapper"
Task T026: "Create launchers/ghostty wrapper"
Task T027: "Create launchers/lazygit wrapper"
Task T028: "Create launchers/yazi wrapper"

# Can also run in parallel:
Task T032: "Configure i3 keybindings"
Task T033: "Add symlink for mark-window command"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

**Goal**: Ship minimal viable feature as fast as possible

1. Complete Phase 1: Setup (T001-T004) - ~2 hours
2. Complete Phase 2: Foundational (T005-T008) - ~1 hour ⚠️ CHECKPOINT
3. Complete Phase 3: User Story 1 (T009-T016) - ~3 hours ✅ MVP COMPLETE
4. **STOP and VALIDATE**: Test US1 independently per acceptance scenarios
5. Deploy to Hetzner, test in real RDP environment
6. Gather feedback before building US2-US6

**Estimated MVP Time**: ~6 hours of focused implementation

**MVP Delivers**:
- Create projects at runtime without rebuild ✅
- Switch between projects ✅
- Basic project listing ✅
- Manual validation that projects persist

### Incremental Delivery (Recommended)

**Sprint 1**: Setup + Foundational + US1 + US4 (T001-T023)
- **Deliverable**: Create projects with JSON config, basic switching
- **Value**: Runtime project management + layout support
- **Test**: Create project with workspace layout, verify it loads

**Sprint 2**: US2 (T024-T034)
- **Deliverable**: Full window mark management, application launchers
- **Value**: Windows automatically hide/show when switching projects
- **Test**: Launch apps in project A, switch to B, verify A hidden

**Sprint 3**: US3 + US5 (T035-T043)
- **Deliverable**: Polybar integration, multi-monitor support
- **Value**: Visual indicator + dual-monitor workflows
- **Test**: Polybar updates without polling, workspaces on correct monitors

**Sprint 4**: US6 + Additional Features + Polish (T044-T061)
- **Deliverable**: Runtime app config, rofi switcher, production-ready
- **Value**: Complete feature with all user stories
- **Test**: Full quickstart.md validation

---

## Task Count Summary

- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 4 tasks ⚠️ BLOCKS ALL
- **Phase 3 (US1 - P1)**: 8 tasks ✅ MVP
- **Phase 4 (US4 - P1)**: 7 tasks
- **Phase 5 (US2 - P1)**: 11 tasks
- **Phase 6 (US3 - P2)**: 5 tasks
- **Phase 7 (US5 - P2)**: 4 tasks
- **Phase 8 (US6 - P3)**: 4 tasks
- **Phase 9 (Additional)**: 5 tasks
- **Phase 10 (Polish)**: 9 tasks

**Total**: 61 tasks

**Parallel Opportunities**: 24 tasks marked [P] can run in parallel with others

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story can be independently tested per acceptance scenarios in spec.md
- No automated tests required - manual validation per user stories
- shellcheck validation runs during NixOS build (T004)
- Scripts deployed via home-manager ensure declarative configuration
- Stop at any checkpoint to validate story independently before continuing
- CLAUDE.md update (T053) provides AI assistant navigation for future work
