# Tasks: Project-Scoped Application Workspace Management

**Input**: Design documents from `/etc/nixos/specs/011-project-scoped-application/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/i3-ipc-api.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US6)
- Include exact file paths in descriptions

## Path Conventions
- **NixOS configuration structure**: `/etc/nixos/`
- **Scripts**: `/etc/nixos/scripts/`
- **Home modules**: `/etc/nixos/home-modules/`
- **Documentation**: `/etc/nixos/docs/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Enhance existing project structure with application classification schema

- [X] T001 [P] Enhance projects.json schema with applications array in home-modules/desktop/i3-projects.nix
- [X] T002 [P] Create project-switch-hook.sh skeleton in scripts/ directory
- [X] T003 [P] Add monitor detection utilities (xrandr wrapper functions) in scripts/detect-monitors.sh

**Checkpoint**: Project structure ready for application launchers and window management logic

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement window-to-project matching logic in scripts/project-switch-hook.sh (parse `[PROJECT:id]` from titles)
- [X] T005 Implement scratchpad hiding mechanism in scripts/project-switch-hook.sh (i3-msg move scratchpad)
- [X] T006 Implement workspace reassignment logic in scripts/project-switch-hook.sh (i3-msg move to workspace)
- [X] T007 [P] Create monitor detection script scripts/detect-monitors.sh (xrandr query parsing)
- [X] T008 [P] Create workspace-to-monitor assignment script scripts/assign-workspace-monitor.sh (priority-based logic)
- [X] T009 Integrate project-switch-hook.sh call into scripts/project-set.sh (trigger on project activation)
- [X] T010 Update ~/.config/i3/projects.json with enhanced schema (add applications array to nixos, stacks, personal projects)

**Checkpoint**: Foundation ready - window management, monitor detection, project switching core logic complete

---

## Phase 3: User Story 1 - Switch Project Context and See Relevant Applications (Priority: P1) 🎯 MVP

**Goal**: When switching projects, automatically show active project's applications and hide inactive project's applications

**Independent Test**: Activate "NixOS" project, launch VS Code and Ghostty, switch to "Stacks" project, verify NixOS applications are hidden

### Implementation for User Story 1

- [X] T011 [US1] Implement get_project_windows() function in scripts/project-switch-hook.sh (query i3 window tree, filter by project ID)
- [X] T012 [US1] Implement hide_project_windows() function in scripts/project-switch-hook.sh (move to scratchpad)
- [X] T013 [US1] Implement show_project_windows() function in scripts/project-switch-hook.sh (move to workspace)
- [X] T014 [US1] Implement project switch workflow orchestration in scripts/project-switch-hook.sh (hide old, show new)
- [X] T015 [US1] Test project switching with existing manually-launched applications (set titles manually with wmctrl)
- [X] T016 [US1] Add error handling for missing window properties in scripts/project-switch-hook.sh
- [X] T017 [US1] Add logging to ~/.config/i3/project-switch.log for debugging

**Checkpoint**: User Story 1 complete - Project switching hides/shows windows correctly based on project context

---

## Phase 4: User Story 2 - Launch Applications in Project Context (Priority: P1) 🎯 MVP

**Goal**: Project-aware launchers that embed project ID in window titles and open applications in correct context

**Independent Test**: Activate "NixOS" project, press Mod+c, verify VS Code opens /etc/nixos with `[PROJECT:nixos]` in title

### Implementation for User Story 2

- [X] T018 [P] [US2] Create scripts/launch-code.sh (VS Code launcher: read current project, open directory, set window title via --title if supported or wmctrl)
- [X] T019 [P] [US2] Create scripts/launch-ghostty.sh (Ghostty + sesh launcher: printf ANSI escape for title, exec sesh connect)
- [X] T020 [P] [US2] Create scripts/launch-lazygit.sh (lazygit launcher: printf ANSI escape for title, exec lazygit -p <repo>)
- [X] T021 [P] [US2] Create scripts/launch-yazi.sh (yazi launcher: printf ANSI escape for title, exec yazi <directory>)
- [X] T022 [US2] Update home-modules/desktop/i3.nix with project-aware keybindings (Mod+c → launch-code.sh, Mod+Return → launch-ghostty.sh, Mod+g → launch-lazygit.sh, Mod+y → launch-yazi.sh)
- [X] T023 [US2] Test each launcher in isolation (verify title embedding, correct directory/session)
- [X] T024 [US2] Test launcher fallback behavior when no project is active (global mode)
- [X] T025 [US2] Add error handling for missing project directory in all launcher scripts

**Checkpoint**: User Story 2 complete - All project-scoped applications launch with correct context and are properly tagged for window management

---

## Phase 5: User Story 3 - Access Global Applications Across Projects (Priority: P2)

**Goal**: Global applications remain visible and accessible regardless of active project

**Independent Test**: Open Firefox, switch between projects multiple times, verify Firefox remains visible on workspace 3

### Implementation for User Story 3

- [X] T026 [US3] Update scripts/project-switch-hook.sh to skip windows without `[PROJECT:]` tag (treat as global)
- [X] T027 [US3] Update projects.json applications array with projectScoped=false for Firefox, YouTube PWA, K9s (Already working: global apps don't have PROJECT tags)
- [X] T028 [US3] Test global application visibility during project switches (Firefox, YouTube PWA should remain on workspaces)
- [X] T029 [US3] Verify global applications can be launched while project is active

**Checkpoint**: User Story 3 complete - Global applications remain accessible across all project contexts

---

## Phase 6: User Story 4 - See Current Project in Status Bar (Priority: P2)

**Goal**: Polybar displays active project name with icon, clickable to open project switcher

**Independent Test**: Activate "Stacks" project, verify polybar shows " Stacks Platform"

### Implementation for User Story 4

- [X] T030 [US4] Update home-modules/desktop/polybar.nix to add project indicator module (read ~/.config/i3/current-project, display name + icon)
- [X] T031 [US4] Add click handler to polybar project module (click → project-switcher.sh, right-click → project-clear.sh)
- [X] T032 [US4] Test polybar updates on project activation (verify project name and icon display)
- [X] T033 [US4] Test polybar "No Project" state when project is cleared
- [X] T034 [US4] Add polybar refresh logic to scripts/project-set.sh and scripts/project-clear.sh (send update signal if needed)

**Checkpoint**: User Story 4 complete - Polybar provides clear visual feedback of active project

---

## Phase 7: User Story 5 - Adaptive Monitor Assignment (Priority: P2)

**Goal**: Workspaces automatically distribute across 1-3 monitors based on priority assignments

**Independent Test**: Connect 2 monitors, verify workspaces 1-2 on primary, 3-9 on secondary

### Implementation for User Story 5

- [X] T035 [US5] Implement monitor count detection logic in scripts/detect-monitors.sh (xrandr --query parsing)
- [X] T036 [US5] Implement primary monitor detection in scripts/detect-monitors.sh (grep ' connected primary')
- [X] T037 [US5] Implement 1-monitor assignment logic in scripts/assign-workspace-monitor.sh (all workspaces → primary)
- [X] T038 [US5] Implement 2-monitor assignment logic in scripts/assign-workspace-monitor.sh (WS 1-2 → primary, 3-9 → secondary)
- [X] T039 [US5] Implement 3-monitor assignment logic in scripts/assign-workspace-monitor.sh (WS 1-2 → primary, 3-5 → secondary, 6-9 → tertiary)
- [X] T040 [US5] Integrate monitor detection into scripts/project-set.sh (call detect-monitors.sh + assign-workspace-monitor.sh)
- [X] T041 [US5] Add keybinding Mod+Shift+m in home-modules/desktop/i3.nix for manual monitor detection trigger
- [X] T042 [US5] Test workspace distribution with 1 monitor (all workspaces on single display)
- [X] T043 [US5] Test workspace distribution with 2 monitors (verify primary/secondary split)
- [X] T044 [US5] Test workspace distribution with 3 monitors (verify tertiary assignment)
- [X] T045 [US5] Test monitor hotplug (disconnect monitor, press Mod+Shift+m, verify reassignment)

**Checkpoint**: User Story 5 complete - Multi-monitor workspace assignment works for 1-3 monitor configurations

---

## Phase 8: User Story 6 - Clear Project Context for Global Work (Priority: P3)

**Goal**: User can return to global mode where all applications are visible without project filtering

**Independent Test**: Activate project, hide some windows, clear project, verify all windows reappear

### Implementation for User Story 6

- [X] T046 [US6] Update scripts/project-clear.sh to call project-switch-hook.sh with empty project (show all scratchpad windows)
- [X] T047 [US6] Implement show_all_project_windows() function in scripts/project-switch-hook.sh (move all `[PROJECT:*]` windows from scratchpad to workspaces)
- [X] T048 [US6] Test clearing project returns all hidden windows to visibility
- [X] T049 [US6] Test subsequent application launches use global workspace assignments after clearing project
- [X] T050 [US6] Verify polybar shows "No Project" after clearing (returns empty JSON {} when no project active)

**Checkpoint**: User Story 6 complete - Global mode escape hatch functional

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, testing, and refinement across all user stories

- [ ] T051 [P] Create docs/PROJECT_WORKSPACE_MANAGEMENT.md (architecture overview, design decisions, troubleshooting)
- [X] T052 [P] Update docs/CLAUDE.md with project management workflow (keybindings, quick reference)
- [X] T053 [P] Add comprehensive comments to all launcher scripts (explain title embedding, sesh integration) - Scripts already have comprehensive documentation
- [X] T054 [P] Add comprehensive comments to project-switch-hook.sh (explain window matching algorithm) - Function headers and inline comments already present
- [ ] T055 Test end-to-end workflow from quickstart.md on Hetzner (reference platform with RDP)
- [ ] T056 Test on WSL2 (verify scripts work without multi-monitor, confirm sesh/Ghostty availability)
- [ ] T057 Test on M1 Mac (verify Wayland compatibility for window properties)
- [ ] T058 [P] Add validation for projects.json schema (check required fields, workspace ranges, duplicate applications)
- [ ] T059 [P] Add performance logging (measure project switch time, window move operations)
- [ ] T060 Run full validation against success criteria (SC-001 through SC-010 from spec.md)

**Checkpoint**: All user stories tested and documented, ready for production use

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - User Story 1 (P1): Core project switching - **MVP priority**
  - User Story 2 (P1): Project-aware launchers - **MVP priority**
  - User Story 3 (P2): Global applications - Can implement in parallel with US4/US5
  - User Story 4 (P2): Polybar integration - Can implement in parallel with US3/US5
  - User Story 5 (P2): Multi-monitor support - Can implement in parallel with US3/US4
  - User Story 6 (P3): Clear project - Depends on US1 being complete
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational (Phase 2) - Core switching logic
- **User Story 2 (P1)**: Depends on Foundational (Phase 2) - Launcher scripts independent of US1 but work together
- **User Story 3 (P2)**: Depends on US1 (relies on project-switch-hook.sh skip logic)
- **User Story 4 (P2)**: Depends on Setup (reads current-project state file)
- **User Story 5 (P2)**: Depends on Foundational (uses monitor detection scripts)
- **User Story 6 (P3)**: Depends on US1 (extends project-switch-hook.sh with show-all logic)

### Parallel Opportunities

**Setup Phase**:
- T001, T002, T003 can run in parallel (different files)

**Foundational Phase**:
- T007 (detect-monitors.sh) and T008 (assign-workspace-monitor.sh) can run in parallel
- T004-T006 must be sequential (same file: project-switch-hook.sh)

**User Story 2 (Launchers)**:
- T018, T019, T020, T021 can run in parallel (different launcher scripts)

**User Story 5 (Multi-monitor)**:
- T037-T039 can run in parallel (different conditional blocks in same script) with care
- T042-T044 can run in parallel (independent test scenarios)

**Polish Phase**:
- T051, T052, T053, T054, T058, T059 can run in parallel (different files)

---

## Parallel Example: User Story 2 (Launchers)

```bash
# Launch all launcher script creation together:
Task: "Create scripts/launch-code.sh"
Task: "Create scripts/launch-ghostty.sh"
Task: "Create scripts/launch-lazygit.sh"
Task: "Create scripts/launch-yazi.sh"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. **Complete Phase 1: Setup** (~30 minutes)
   - Enhance projects.json schema
   - Create script skeletons
   - Add monitor detection stubs

2. **Complete Phase 2: Foundational** (~2-3 hours)
   - Core window matching and switching logic
   - Monitor detection scripts
   - Integration with project-set.sh

3. **Complete Phase 3: User Story 1** (~1-2 hours)
   - Window show/hide orchestration
   - Testing with manual windows
   - Error handling

4. **Complete Phase 4: User Story 2** (~2-3 hours)
   - All 4 launcher scripts (VS Code, Ghostty, lazygit, yazi)
   - i3 keybinding updates
   - Testing title embedding

5. **STOP and VALIDATE**: Test combined US1+US2
   - Switch between projects
   - Launch applications
   - Verify hiding/showing works
   - **Deploy/demo if ready** (Hetzner test)

**Total MVP Estimate**: 6-10 hours

### Incremental Delivery

**MVP (P1 Stories)**:
1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Core switching works
3. Add User Story 2 → Test independently → **MVP COMPLETE** (can switch projects and launch apps)
4. Deploy to Hetzner, gather feedback

**Enhancement 1 (P2 Stories)**:
5. Add User Story 3 → Global applications accessible
6. Add User Story 4 → Polybar visual feedback
7. Add User Story 5 → Multi-monitor support
8. Deploy enhancement 1

**Enhancement 2 (P3 + Polish)**:
9. Add User Story 6 → Clear project capability
10. Complete Phase 9 → Documentation and testing
11. Final deployment

### Parallel Team Strategy

With 2 developers (after Foundational phase complete):

**Developer A (Core):**
- Phase 3: User Story 1 (project switching)
- Phase 4: User Story 2 (launchers)
- Phase 8: User Story 6 (clear project)

**Developer B (Enhancements):**
- Phase 5: User Story 3 (global apps)
- Phase 6: User Story 4 (polybar)
- Phase 7: User Story 5 (multi-monitor)

Then both collaborate on Phase 9 (Polish).

---

## Testing Checkpoints

### After Foundational (Phase 2)
- [ ] Window matching works (manually set title `[PROJECT:nixos]`, verify detection)
- [ ] Scratchpad hiding works (move window to scratchpad via script)
- [ ] Monitor detection works (run detect-monitors.sh, verify xrandr parsing)

### After User Story 1 (MVP Core)
- [ ] Switch from NixOS to Stacks project hides NixOS windows
- [ ] Switch back to NixOS shows NixOS windows again
- [ ] Global applications remain visible throughout

### After User Story 2 (MVP Complete)
- [ ] Launch VS Code in NixOS project opens /etc/nixos
- [ ] Launch Ghostty connects to nixos sesh session
- [ ] Launch lazygit opens /etc/nixos repository
- [ ] Launch yazi starts in /etc/nixos
- [ ] All windows have correct `[PROJECT:nixos]` title prefix

### After User Story 5 (Multi-monitor)
- [ ] Single monitor: All workspaces on one display
- [ ] Dual monitors: WS 1-2 on primary, 3-9 on secondary
- [ ] Triple monitors: WS 1-2 on primary, 3-5 on secondary, 6-9 on tertiary
- [ ] Hotplug: Disconnect monitor, trigger reassignment, verify redistribution

### Final Validation (Success Criteria)
- [ ] SC-001: Project switch completes in <2 seconds
- [ ] SC-002: 100% application launch accuracy (correct context)
- [ ] SC-003: 100% window show/hide accuracy
- [ ] SC-004: Global applications accessible 100% of time
- [ ] SC-005: Polybar updates within 1 second
- [ ] SC-006: Full workflow completion in <20 seconds
- [ ] SC-007: Zero incorrect workspace assignments
- [ ] SC-008: Workspace distribution in <2 seconds
- [ ] SC-009: High-priority workspaces on primary 100% of time
- [ ] SC-010: Monitor hotplug recovery in <3 seconds

---

## Notes

- **[P] tasks** = different files, no dependencies
- **[Story]** label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Test on Hetzner (reference platform) first, then WSL2 and M1
- Run `nixos-rebuild dry-build --flake .#hetzner` before each apply
- Commit after each checkpoint or logical group
- Window title format: `[PROJECT:project-id] <original-title>`
- Scratchpad is primary hiding mechanism (not workspace 90+)
- Monitor priority: 1 (primary) > 2 (secondary) > 3 (tertiary)
