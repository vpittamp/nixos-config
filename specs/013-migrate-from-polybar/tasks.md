# Tasks: Migrate from Polybar to i3 Native Status Bar

**Input**: Design documents from `/specs/013-migrate-from-polybar/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/i3blocks-protocol.md

**Tests**: No test tasks included (not requested in feature specification)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, or Setup/Foundational)
- File paths are shown for NixOS configuration structure

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the configuration structure and remove polybar

- [X] T001 [Setup] Remove polybar module import from `home-vpittamp.nix`
- [X] T002 [P] [Setup] Delete polybar configuration file `home-modules/desktop/polybar.nix`
- [X] T003 [P] [Setup] Create directory `home-modules/desktop/i3blocks/scripts/` for status scripts

**Checkpoint**: Polybar removed, structure ready for i3bar implementation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core i3bar configuration that MUST be complete before ANY user story can display

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [Foundational] Add i3bar configuration block to `home-modules/desktop/i3.nix`
  - Add bar {} block with position, font, statusCommand
  - Configure Catppuccin Mocha colors for bar background, statusline, separator
  - Set workspace button colors (focused, active, inactive, urgent)
  - Reference: data-model.md sections 1-2, research.md section 4

- [X] T005 [P] [Foundational] Create i3blocks module skeleton in `home-modules/desktop/i3blocks/default.nix`
  - Import i3blocks package
  - Setup xdg.configFile for i3blocks config generation
  - Configure global properties (separator_block_width, markup)
  - Reference: data-model.md section 4

**Checkpoint**: Foundation ready - i3bar will display with workspace buttons (US1), status blocks can now be added independently

---

## Phase 3: User Story 1 - View Active Workspaces (Priority: P1) 🎯 MVP

**Goal**: Display workspace indicators on all monitors with current workspace highlighted

**Independent Test**: Open system, verify workspace indicators visible on each monitor's bar, switch workspaces to confirm active workspace is highlighted

### Implementation for User Story 1

- [X] T006 [US1] Verify workspace button configuration in i3bar colors (already done in T004)
- [X] T007 [US1] Test workspace display by rebuilding config: `sudo nixos-rebuild dry-build --flake .#hetzner`
- [X] T008 [US1] Apply configuration: `sudo nixos-rebuild switch --flake .#hetzner`
- [X] T009 [US1] Validate workspace indicators appear on all 3 monitors
- [X] T010 [US1] Validate workspace switching updates indicator within 100ms
- [X] T011 [US1] Validate monitor connect/disconnect handling

**Checkpoint**: User Story 1 COMPLETE - Workspace indicators fully functional on all monitors

---

## Phase 4: User Story 2 - View System Information (Priority: P2)

**Goal**: Display CPU, memory, network, and date/time in status bar with 5-second updates

**Independent Test**: View status bar and confirm system metrics update in real-time (watch CPU change during load)

### Implementation for User Story 2

- [X] T012 [P] [US2] Create CPU usage script in `home-modules/desktop/i3blocks/scripts/cpu.sh`
  - Read CPU usage from /proc or mpstat
  - Output JSON with color coding (>95% red, >80% yellow, normal gray)
  - Target execution time <50ms
  - Reference: contracts/i3blocks-protocol.md example 2

- [X] T013 [P] [US2] Create memory usage script in `home-modules/desktop/i3blocks/scripts/memory.sh`
  - Read memory from /proc/meminfo
  - Calculate percentage: (Total - Available) / Total * 100
  - Output JSON with color thresholds
  - Reference: contracts/i3blocks-protocol.md example 3

- [X] T014 [P] [US2] Create network status script in `home-modules/desktop/i3blocks/scripts/network.sh`
  - Check primary interface via ip route
  - Display interface name + status or "disconnected"
  - Green when up, red when down
  - Reference: contracts/i3blocks-protocol.md example 4

- [X] T015 [P] [US2] Create date/time script in `home-modules/desktop/i3blocks/scripts/datetime.sh`
  - Format: YYYY-MM-DD HH:MM (ISO 8601)
  - Normal color (no thresholds)
  - Reference: contracts/i3blocks-protocol.md example 5

- [X] T016 [US2] Register all system info blocks in `home-modules/desktop/i3blocks/default.nix`
  - Add CPU block with interval=5
  - Add memory block with interval=5
  - Add network block with interval=10
  - Add datetime block with interval=60
  - Reference: data-model.md section 4

- [X] T017 [US2] Test system info blocks: `sudo nixos-rebuild dry-build --flake .#hetzner`
- [X] T018 [US2] Apply and validate: `sudo nixos-rebuild switch --flake .#hetzner`
- [X] T019 [US2] Validate all metrics display and update within 5 seconds

**Checkpoint**: User Story 2 COMPLETE - All system metrics displaying and updating

---

## Phase 5: User Story 3 - View Project Context Indicator (Priority: P3)

**Goal**: Display active project name from project management system in status bar

**Independent Test**: Switch between projects using i3-project-switch and verify status bar updates to show correct project name

### Implementation for User Story 3

- [X] T020 [US3] Create project indicator script in `home-modules/desktop/i3blocks/scripts/project.sh`
  - Read state file: `~/.config/i3/active-project`
  - Parse JSON (requires jq): extract display_name and icon
  - Handle no-project state (show "∅" dimmed)
  - Handle invalid JSON gracefully
  - Output format: "{icon} {display_name}" in lavender color
  - Reference: contracts/i3blocks-protocol.md example 6

- [X] T021 [US3] Register project block in `home-modules/desktop/i3blocks/default.nix`
  - Add project block with interval=once and signal=10
  - Color: #b4befe (lavender)
  - Reference: data-model.md section 4

- [X] T022 [US3] Update i3-project-switch scripts to send signal to i3blocks
  - Locate all project switch scripts (i3-project-switch, i3-project-clear)
  - Add signal command: `pkill -RTMIN+10 i3blocks 2>/dev/null || true`
  - Place signal after project state file write
  - Reference: research.md section 3

- [X] T023 [US3] Test project indicator: `sudo nixos-rebuild dry-build --flake .#hetzner`
- [X] T024 [US3] Apply configuration: `sudo nixos-rebuild switch --flake .#hetzner`
- [X] T025 [US3] Validate project indicator displays current project
- [X] T026 [US3] Validate project switch triggers immediate update (<100ms)
- [X] T027 [US3] Validate global mode (no project) displays correctly

**Checkpoint**: User Story 3 COMPLETE - Project context indicator fully functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and validation across all user stories

- [X] T028 [P] [Polish] Verify no polybar processes running: `pgrep -a polybar` (should return nothing)
- [X] T029 [P] [Polish] Validate i3bar processes: `pgrep -a i3bar` (should show one per monitor)
- [X] T030 [P] [Polish] Validate i3blocks process: `pgrep -a i3blocks` (should show one process)
- [X] T031 [Polish] Test configuration rebuild survival
  - Note current workspace and project
  - Run: `sudo nixos-rebuild switch --flake .#hetzner`
  - Verify bar reappears with correct state
  - Success criteria: No manual restart needed
- [X] T032 [P] [Polish] Run quickstart.md validation scenarios
  - Test changing bar position (top/bottom)
  - Test customizing colors
  - Test changing update intervals
  - Reference: quickstart.md sections 1-3
- [X] T033 [Polish] Performance validation
  - Measure workspace update latency: `<100ms` (success criteria SC-002)
  - Measure bar startup time: `<2s` (success criteria SC-003)
  - Measure script execution: `time ~/.config/i3blocks/scripts/cpu.sh` (<100ms)
- [X] T034 [Polish] Update CLAUDE.md documentation
  - Update "Recent Updates" section with migration completion
  - Document i3bar + i3blocks as standard status bar
  - Add quickstart reference for customization

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - workspace buttons from i3bar config
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) - can start independently after foundation
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) - can start independently after foundation
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

```
Setup (Phase 1)
     ↓
Foundational (Phase 2) ← CRITICAL BLOCKER
     ↓
     ├─→ User Story 1 (P1) - Workspace Display [MVP] ← Start here
     ├─→ User Story 2 (P2) - System Info [Can run in parallel with US3]
     └─→ User Story 3 (P3) - Project Indicator [Can run in parallel with US2]
          ↓
     Polish (Phase 6)
```

- **User Story 1 (P1)**: Minimal dependencies - workspace buttons configured in T004 (Foundational)
- **User Story 2 (P2)**: Independent after Foundational - no dependencies on US1 or US3
- **User Story 3 (P3)**: Independent after Foundational - no dependencies on US1 or US2 (but integrates with existing project system)

### Within Each User Story

- **User Story 1**: Sequential validation tasks (T006-T011)
- **User Story 2**:
  - Scripts (T012-T015) can run in parallel [P]
  - Registration (T016) depends on all scripts
  - Validation (T017-T019) sequential
- **User Story 3**:
  - Script creation (T020) before registration (T021)
  - Integration (T022) can run parallel with T020-T021
  - Validation (T023-T027) sequential

### Parallel Opportunities

**Phase 1 - Setup**: T002 and T003 can run in parallel [P]

**Phase 2 - Foundational**: T005 can run in parallel with T004 [P] (different files)

**Phase 4 - User Story 2**: All four scripts can be created in parallel
```bash
# Launch all US2 scripts together:
Task T012: Create cpu.sh
Task T013: Create memory.sh
Task T014: Create network.sh
Task T015: Create datetime.sh
```

**Cross-Story Parallelization**: After Phase 2 completes, US2 and US3 can proceed in parallel (different components)
```bash
# With multiple developers or sequential implementation:
Developer A: User Story 1 (T006-T011)
Developer B: User Story 2 (T012-T019) [Can start after US1 or in parallel]
Developer C: User Story 3 (T020-T027) [Can start after US1 or in parallel]
```

**Phase 6 - Polish**: T028, T029, T030, T032 can run in parallel [P]

---

## Parallel Example: User Story 2 (System Information)

```bash
# Create all system info scripts in parallel:
Task T012: "Create CPU usage script in home-modules/desktop/i3blocks/scripts/cpu.sh"
Task T013: "Create memory usage script in home-modules/desktop/i3blocks/scripts/memory.sh"
Task T014: "Create network status script in home-modules/desktop/i3blocks/scripts/network.sh"
Task T015: "Create date/time script in home-modules/desktop/i3blocks/scripts/datetime.sh"

# Then sequentially:
Task T016: "Register all blocks in i3blocks/default.nix" (depends on T012-T015)
Task T017: "Test configuration" (depends on T016)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

**Recommended approach for fastest value delivery:**

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T005) ← CRITICAL
3. Complete Phase 3: User Story 1 (T006-T011)
4. **STOP and VALIDATE**: Test workspace display independently
5. Deploy/demo if ready - basic workspace functionality restored

**Time estimate**: 1-2 hours for experienced Nix user

### Incremental Delivery

**Add features one story at a time:**

1. **Milestone 1**: Setup + Foundational + US1 → Workspace display working (MVP!)
   - User can navigate workspaces effectively
   - Validates i3bar integration works
   - Polybar removed without loss of core functionality

2. **Milestone 2**: Add US2 → System monitoring restored
   - CPU, memory, network, time all displaying
   - 5-second updates working
   - Feature parity with polybar system info

3. **Milestone 3**: Add US3 → Project context integrated
   - Project indicator displaying and updating
   - Signal-based updates working
   - Full feature set complete

4. **Milestone 4**: Polish → Production ready
   - Performance validated
   - Documentation updated
   - All success criteria met

### Parallel Team Strategy

With multiple team members or iterative implementation:

1. **Everyone**: Complete Setup + Foundational together (T001-T005)
2. **Split work** after Foundational phase completes:
   - **Track A**: User Story 1 (T006-T011) - Priority, get working first
   - **Track B**: User Story 2 (T012-T019) - Can start after or parallel to US1
   - **Track C**: User Story 3 (T020-T027) - Can start after or parallel to US1
3. **Converge**: Polish together (T028-T034)

**Note**: For a single developer, sequential priority order (P1 → P2 → P3) is recommended.

---

## Success Criteria Validation

Map tasks to success criteria from spec.md:

- **SC-001** (Workspace visibility): T009 validates
- **SC-002** (100ms update): T010 validates
- **SC-003** (2s startup): T033 validates
- **SC-004** (Rebuild survival): T031 validates
- **SC-005** (5s info updates): T019 validates
- **SC-006** (No polybar processes): T028 validates
- **SC-007** (Navigation effectiveness): T011 validates
- **SC-008** (Fewer lines of code): Compare after completion
- **SC-009** (Monitor events): T011 validates

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to user story (US1, US2, US3) for traceability
- Each user story should be independently completable and testable
- Always run dry-build before switch to validate configuration
- Commit after each phase or logical group
- Stop at any checkpoint to validate story independently
- File paths follow NixOS home-manager conventions
- Scripts follow i3blocks JSON protocol (see contracts/)
- All colors use Catppuccin Mocha palette (see data-model.md section 2)

---

## Quick Reference

**File Structure**:
```
/etc/nixos/
├── home-vpittamp.nix                      # T001: Remove polybar import
├── home-modules/desktop/
│   ├── i3.nix                            # T004: Add bar {} block
│   ├── polybar.nix                       # T002: DELETE THIS FILE
│   └── i3blocks/
│       ├── default.nix                   # T005, T016, T021: i3blocks config
│       └── scripts/
│           ├── cpu.sh                    # T012: CPU usage
│           ├── memory.sh                 # T013: Memory usage
│           ├── network.sh                # T014: Network status
│           ├── datetime.sh               # T015: Date/time
│           └── project.sh                # T020: Project indicator
```

**Commands**:
```bash
# Test configuration
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply configuration
sudo nixos-rebuild switch --flake .#hetzner

# Validate processes
pgrep -a polybar    # Should return nothing
pgrep -a i3bar      # Should show 3 processes (one per monitor)
pgrep -a i3blocks   # Should show 1 process

# Test signal
pkill -RTMIN+10 i3blocks

# Validate script output
~/.config/i3blocks/scripts/cpu.sh | jq .
time ~/.config/i3blocks/scripts/cpu.sh
```

---

**Total Tasks**: 34 tasks
- Setup: 3 tasks
- Foundational: 2 tasks (CRITICAL)
- User Story 1 (P1): 6 tasks [MVP]
- User Story 2 (P2): 8 tasks
- User Story 3 (P3): 8 tasks
- Polish: 7 tasks

**Parallel Opportunities**:
- Setup: 2 tasks can run in parallel
- Foundational: 2 tasks can run in parallel
- User Story 2: 4 script tasks can run in parallel
- User Story 3: Script + integration can run in parallel
- Polish: 4 validation tasks can run in parallel

**Independent Test Criteria**:
- US1: Switch workspaces and see indicator update immediately
- US2: Watch CPU/memory values change in real-time
- US3: Switch projects and see indicator update within 100ms

**Suggested MVP Scope**: User Story 1 only (Phases 1-3, tasks T001-T011)
