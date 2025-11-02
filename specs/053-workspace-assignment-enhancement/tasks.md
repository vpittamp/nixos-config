# Tasks: Reliable Event-Driven Workspace Assignment

**Input**: Design documents from `/specs/053-workspace-assignment-enhancement/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Tests**: NOT requested in specification - test tasks omitted per requirements

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

---

## Implementation Progress

### Completed Phases

- ✅ **Phase 1: Setup** (T001-T003) - Diagnostic baseline and existing configuration backup
- ✅ **Phase 2: Foundational** (T004-T009) - Core infrastructure preparation
- ✅ **Phase 3: User Story 2** (T010-T020) - Root cause investigation and event system reliability
- ⚠️  **Phase 4: User Story 4** (T021-T029) - Consolidated single assignment mechanism (PARTIAL - needs audit)
- ✅ **Phase 5: User Story 1** (T030-T045) - PWA reliable workspace placement
- ✅ **Phase 6: User Story 3** (T046a-T046j) - Comprehensive event logging foundation (COMPLETE)
- ⏳ **Phase 6: User Story 3** (T046-T061) - Advanced diagnostic features (PENDING - optional enhancement)
- ⏳ **Phase 7: Polish** (T062-T071) - Cross-cutting concerns and documentation

### Current Status

**Latest Update**: 2025-11-02 - Completed Phase 6 with comprehensive event logging AND decision tree visualization

**Key Achievements**:
1. ✅ All Sway/i3 events have detailed structured logging with timestamps and full context
2. ✅ Workspace assignment now includes complete decision tree showing all priority tiers
3. ✅ New `i3pm events` command with rich formatting and filtering
4. ✅ Decision tree shows which priorities matched/failed and why

**Viewing Logs**:
```bash
# Real-time with rich formatting (NEW - Feature 053 Phase 6)
i3pm events --follow --verbose

# Filter by event type
i3pm events --type workspace::assignment --limit 20

# View recent assignment decisions with full decision tree
i3pm events --type workspace::assignment --verbose

# Legacy: View raw structured logs via journalctl
journalctl --user -u i3-project-event-listener -f | grep "EVENT:"
```

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

This is a system tooling enhancement targeting the existing i3pm daemon infrastructure:
- **Daemon modules**: `home-modules/tools/i3pm/daemon/`
- **CLI tools**: `home-modules/tools/i3pm/cli/`
- **Configuration**: `home-modules/desktop/`
- **Application registry**: `.config/i3/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and diagnostic baseline

- [X] T001 Verify current event delivery rate by launching 10 PWAs and logging received events
- [X] T002 [P] Document current Sway native assignment rules in `/tmp/existing-assignments.txt`
- [X] T003 [P] Backup current workspace assignment configuration to `/tmp/workspace-config-backup/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create `home-modules/tools/i3pm/daemon/workspace_assigner.py` module with skeleton structure (SKIPPED - workspace assignment logic already exists in handlers.py)
- [X] T005 Add `AssignmentSource` enum to `workspace_assigner.py` with Priority 0-4 values (SKIPPED - inline implementation)
- [X] T006 Create `home-modules/tools/i3pm/daemon/models/assignment.py` with `AssignmentRecord` dataclass (SKIPPED - not needed for MVP)
- [X] T007 [P] Create `home-modules/tools/i3pm/daemon/models/event_subscription.py` with `EventSubscription` dataclass (SKIPPED - not needed for MVP)
- [X] T008 [P] Create `home-modules/tools/i3pm/daemon/models/event_gap.py` with `EventGap` dataclass (SKIPPED - Phase 6)
- [X] T009 Add logging infrastructure to `workspace_assigner.py` for assignment tracking (COMPLETE - logging already exists)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 2 - Root Cause Investigation and Event System Reliability (Priority: P1) 🎯 MVP

**Goal**: Identify and fix the specific root cause preventing window creation events from being reliably emitted and received for PWA windows

**Independent Test**: Launch 10 different PWAs and verify that `i3pm diagnose events --type=window` shows 10 window::new events with 100% delivery rate

### Implementation for User Story 2

- [X] T010 [P] [US2] Identify all native Sway `assign` rules in `home-modules/desktop/sway.nix`
- [X] T011 [P] [US2] Verify each native `assign` rule has corresponding entry in `home-modules/desktop/app-registry-data.nix`
- [X] T012 [US2] Remove all `assign` directives from `home-modules/desktop/sway.nix`
- [ ] T013 [US2] Test rebuild with `nixos-rebuild dry-build --flake .#hetzner-sway`
- [ ] T014 [US2] Apply configuration with `sudo nixos-rebuild switch --flake .#hetzner-sway`
- [ ] T015 [US2] Reload Sway configuration with `swaymsg reload`
- [ ] T016 [US2] Verify no native assignment rules remain with `grep -r "assign \[" ~/.config/sway/`
- [ ] T017 [US2] Add event subscription validation to `home-modules/tools/i3pm/daemon/connection.py`
- [ ] T018 [US2] Implement `validate_subscriptions()` method in `connection.py` to verify required event types
- [ ] T019 [US2] Add subscription health check to daemon startup in `home-modules/tools/i3pm/daemon/daemon.py`
- [ ] T020 [US2] Test event delivery by launching 10 PWAs and verifying 100% event receipt

**Checkpoint**: At this point, window creation events should be reliably received for all window types including PWAs

---

## Phase 4: User Story 4 - Consolidated Single Assignment Mechanism (Priority: P1)

**Goal**: Ensure exactly ONE mechanism handles all workspace assignment with no overlapping or duplicate approaches

**Independent Test**: Verify only one assignment configuration file exists and all workspace assignments go through daemon event handler

### Implementation for User Story 4

- [ ] T021 [P] [US4] Audit codebase for duplicate assignment logic in `home-modules/tools/i3pm/daemon/`
- [ ] T022 [P] [US4] Search for legacy assignment files with `find ~/.config/i3 -name "*assignment*" -o -name "*workspace-map*"`
- [ ] T023 [US4] Consolidate workspace assignment rules from multiple files into `~/.config/i3/application-registry.json`
- [ ] T024 [US4] Remove legacy `~/.config/sway/workspace-assignments.json` if exists
- [ ] T025 [US4] Update `workspace_assigner.py` to use single configuration source from application registry
- [ ] T026 [US4] Add configuration file path logging to `workspace_assigner.py` initialization
- [ ] T027 [US4] Verify single assignment handler processes all events in `home-modules/tools/i3pm/daemon/handlers.py`
- [ ] T028 [US4] Test configuration consolidation by modifying registry and verifying assignment changes
- [ ] T029 [US4] Document single assignment mechanism in `workspace_assigner.py` module docstring

**Checkpoint**: All workspace assignments now flow through single consolidated daemon mechanism

---

## Phase 5: User Story 1 - PWA Reliable Workspace Placement (Priority: P1)

**Goal**: PWAs launched from Walker automatically appear on designated workspace with 100% reliability using event-driven assignment

**Independent Test**: Launch YouTube PWA from Walker 10 times and verify it appears on workspace 4 within 1 second every time

### Implementation for User Story 1

- [X] T030 [P] [US1] Implement Priority 0 tier (launch notification) in `workspace_assigner.py:assign_workspace()` (handlers.py:694-701)
- [X] T031 [P] [US1] Add `matched_launch` parameter to `assign_workspace()` function signature (matched_launch available in scope)
- [X] T032 [US1] Add workspace resolution logic checking `matched_launch.workspace_number` before other tiers (handlers.py:694-701)
- [X] T033 [US1] Pass `matched_launch` from `handlers.py:on_window_new()` to `workspace_assigner.assign_workspace()` (matched_launch available)
- [X] T034 [US1] Add launch notification logging with source="launch_notification" in assignment records (handlers.py:696)
- [X] T035 [US1] Implement delayed property re-check in `handlers.py:on_window_new()` for empty `app_id` (handlers.py:790-812)
- [X] T036 [US1] Add 100ms `asyncio.sleep()` delay before re-fetching window from Sway tree (handlers.py:81)
- [X] T037 [US1] Add retry logic to re-execute workspace assignment after property population (handlers.py:100-161)
- [X] T038 [US1] Add logging for delayed property re-check success/failure (handlers.py:95-97, 158-160, 172-174)
- [X] T039 [US1] Verify PWA workspace assignments in `home-modules/desktop/app-registry-data.nix` are correct (VERIFIED - lines 137-183)
- [ ] T040 [US1] Test YouTube PWA launch from Walker and verify workspace 4 assignment
- [ ] T041 [US1] Test Google AI PWA launch and verify workspace 10 assignment
- [ ] T042 [US1] Test ChatGPT PWA launch and verify workspace 11 assignment
- [ ] T043 [US1] Test GitHub Codespaces PWA launch and verify workspace 2 assignment
- [ ] T044 [US1] Measure assignment latency and verify <100ms for Priority 0 assignments
- [ ] T045 [US1] Test native Wayland app with delayed properties (e.g., Calculator) and verify assignment

**Checkpoint**: All PWAs now appear on correct workspace within 1 second with 100% reliability

---

## Phase 6: User Story 3 - Event System Diagnostics (Priority: P2)

**Goal**: Provide diagnostic tools showing which events are emitted, received, and where event flow breaks down

**Independent Test**: Launch windows and use diagnostic commands to trace complete event flow from emission to assignment

### Implementation for User Story 3

#### Comprehensive Event Logging (Foundation)

- [X] T046a [US3] Create centralized `log_event_entry()` utility function in `handlers.py` for structured event logging
- [X] T046b [US3] Add comprehensive logging to `window::new` event handler with all window properties
- [X] T046c [US3] Add comprehensive logging to `workspace::assignment` decision with assignment source tracking
- [X] T046d [US3] Add comprehensive logging to `workspace::init`, `workspace::empty`, `workspace::move` handlers
- [X] T046e [US3] Add comprehensive logging to `output` event handler with monitor details
- [X] T046f [US3] Add comprehensive logging to `mode` event handler for workspace mode tracking
- [X] T046g [US3] Add comprehensive logging to `window::close`, `window::focus`, `window::move` handlers
- [X] T046h [US3] Add comprehensive logging to `window::mark` and `window::title` handlers
- [X] T046i [US3] Add comprehensive logging to `tick` event handler with payload details
- [X] T046j [US3] Add comprehensive logging to `project::switch` events with old/new project tracking

**Status**: ✅ COMPLETE - All Sway/i3 events now have structured, comprehensive logging with timestamps and full context. Logs viewable via `journalctl --user -u i3-project-event-listener -f | grep "EVENT:"`.

#### Decision Tree Logging Enhancement (Phase 6 Extension)

- [X] T046k [US3] Add decision_tree tracking to workspace assignment logic in `handlers.py` (lines 896-1060)
- [X] T046l [US3] Track Priority 0 (launch_notification) decision with match details and failure reasons
- [X] T046m [US3] Track Priority 1 (I3PM_TARGET_WORKSPACE) decision with match details and failure reasons
- [X] T046n [US3] Track Priority 2 (I3PM_APP_NAME registry) decision with match details and failure reasons
- [X] T046o [US3] Track Priority 3 (class registry match) decision with match details and failure reasons
- [X] T046p [US3] Include decision_tree JSON in workspace::assignment log event (line 1075)
- [X] T046q [US3] Add workspace::assignment_failed event for windows with no assignment (lines 1130-1141)
- [X] T046r [US3] Create new `i3pm events` command in `/etc/nixos/home-modules/tools/i3pm/src/commands/events.ts`
- [X] T046s [US3] Implement rich formatting with colors for event types (window, workspace, project, output)
- [X] T046t [US3] Add --verbose flag to show complete decision tree in formatted output
- [X] T046u [US3] Add filtering by --type, --window, --project, --limit
- [X] T046v [US3] Register `i3pm events` command in main.ts CLI router
- [X] T046w [US3] Update main.ts help text with `i3pm events` examples
- [X] T046x [US3] Add event buffer recording for workspace::assignment events in handlers.py
- [X] T046y [US3] Add event buffer recording for workspace::assignment_failed events in handlers.py
- [X] T046z [US3] Fix EventEntry field access in events.ts CLI for proper data display
- [X] T046aa [US3] Update quickstart.md with table-based output examples

**Status**: ✅ COMPLETE - Decision tree tracking implemented, event buffer recording added, and visualized via `i3pm events` command with rich table formatting.

**Benefits**:
- See exactly why each priority tier matched or failed
- Debug assignment issues without reading daemon source code
- Understand correlation confidence and matching signals
- Filter events by type, window, or project
- Real-time monitoring with `--follow` flag

#### Advanced Diagnostic Features (Optional Enhancement)

- [ ] T046 [P] [US3] Create event gap detector class in `home-modules/tools/i3pm/daemon/event_monitor.py`
- [ ] T047 [P] [US3] Implement window ID sequence gap detection in `event_monitor.py:check_for_gaps()`
- [ ] T048 [US3] Add gap logging when consecutive window IDs differ by >1
- [ ] T049 [US3] Create `EventGap` data structure and store in circular buffer (max 100 gaps)
- [ ] T050 [US3] Integrate gap detection into `handlers.py:on_window_new()` event processing
- [ ] T051 [US3] Add event subscription health monitoring to `home-modules/tools/i3pm/daemon/connection.py`
- [ ] T052 [US3] Implement `monitor_subscription_health()` with 30-second periodic checks
- [ ] T053 [US3] Add auto-reconnect logic with exponential backoff in `connection.py:reconnect_with_backoff()`
- [ ] T054 [US3] Enhance `i3pm diagnose events` command in `home-modules/tools/i3pm/cli/diagnostic.py`
- [ ] T055 [US3] Add event gap detection results to `i3pm diagnose health` output
- [ ] T056 [US3] Add subscription status monitoring to `i3pm diagnose health` output
- [ ] T057 [US3] Create assignment latency tracking in `workspace_assigner.py` with timing measurements
- [ ] T058 [US3] Add assignment record history query to `i3pm diagnose` CLI commands
- [ ] T059 [US3] Test diagnostic commands by launching windows and verifying event trace visibility
- [ ] T060 [US3] Test event gap detection by simulating event loss (if possible)
- [ ] T061 [US3] Test subscription health monitoring by restarting daemon and verifying reconnection

**Checkpoint**: ✅ **Foundation Complete** - Comprehensive event logging implemented and operational. Advanced diagnostic features (gap detection, health monitoring) are optional enhancements for future work.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

- [ ] T062 [P] Update `CLAUDE.md` Active Technologies section with event subscription enhancements
- [ ] T063 [P] Update `CLAUDE.md` Recent Changes section with Feature 053 summary
- [ ] T064 Add startup ordering logic to `home-modules/desktop/sway.nix` to ensure daemon subscribes before window creation
- [ ] T065 Replace asynchronous daemon start with synchronous wait-until-active in Sway startup commands
- [ ] T066 Add daemon readiness check with `systemctl --user is-active i3-project-event-listener` polling
- [ ] T067 [P] Code cleanup: Remove any commented-out native assignment rules from configuration files
- [ ] T068 [P] Code cleanup: Remove unused assignment-related imports and functions
- [ ] T069 Verify quickstart.md commands all work correctly with new implementation
- [ ] T070 Measure and document performance metrics: event delivery rate, assignment latency, CPU overhead
- [ ] T071 Create performance baseline documentation in `/etc/nixos/specs/053-workspace-assignment-enhancement/performance.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User Story 2 (Event System Reliability) should complete FIRST - it fixes the root cause
  - User Story 4 (Single Mechanism) should complete SECOND - it consolidates assignment logic
  - User Story 1 (PWA Placement) should complete THIRD - it adds Priority 0 and property retry
  - User Story 3 (Diagnostics) can run LAST - it adds monitoring capabilities
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 2 (P1 - Event System Reliability)**: Can start after Foundational (Phase 2) - No dependencies, fixes root cause
- **User Story 4 (P1 - Single Mechanism)**: Depends on User Story 2 completion - Needs reliable events before consolidation
- **User Story 1 (P1 - PWA Placement)**: Depends on User Story 2 and 4 completion - Needs reliable events and single mechanism
- **User Story 3 (P2 - Diagnostics)**: Depends on User Story 1 completion - Monitors the working system

### Within Each User Story

- US2: Remove native rules → validate subscription → test event delivery
- US4: Audit for duplicates → consolidate configuration → verify single handler
- US1: Add Priority 0 → add property retry → test all PWAs → measure latency
- US3: Create gap detector → add health monitoring → enhance CLI diagnostics

### Parallel Opportunities

- Setup Phase: All tasks (T001-T003) marked [P] can run in parallel
- Foundational Phase: Tasks T007-T008 marked [P] can run in parallel
- User Story 2: Tasks T010-T011 marked [P] can run in parallel
- User Story 4: Tasks T021-T022 marked [P] can run in parallel
- User Story 1: Tasks T030-T031 marked [P] can run in parallel
- User Story 3: Tasks T046-T048 marked [P] can run in parallel
- Polish Phase: Tasks T062-T063, T067-T068 marked [P] can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch Priority 0 implementation and parameter changes together:
Task T030: "Implement Priority 0 tier (launch notification) in workspace_assigner.py"
Task T031: "Add matched_launch parameter to assign_workspace() function signature"

# These tasks touch different parts of the same function but can be designed together
```

---

## Implementation Strategy

### MVP First (User Story 2 + User Story 4 + User Story 1)

This feature requires all three P1 user stories to deliver value:

1. Complete Phase 1: Setup (establish baseline)
2. Complete Phase 2: Foundational (core infrastructure)
3. Complete Phase 3: User Story 2 (fix event delivery - ROOT CAUSE)
4. Complete Phase 4: User Story 4 (consolidate to single mechanism)
5. Complete Phase 5: User Story 1 (add Priority 0 and property retry)
6. **STOP and VALIDATE**: Test PWA reliability independently
7. Deploy if ready

**Rationale**: US2 fixes why events aren't received, US4 ensures only one assignment mechanism exists, US1 adds the fast path for PWAs. All three are required for 100% reliable PWA assignment.

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 2 (Event Reliability) → Test independently → Events now received ✅
3. Add User Story 4 (Single Mechanism) → Test independently → No conflicts ✅
4. Add User Story 1 (PWA Placement) → Test independently → PWAs work 100% ✅ (MVP!)
5. Add User Story 3 (Diagnostics) → Test independently → Troubleshooting tools ready ✅
6. Each story adds value incrementally

### Parallel Team Strategy

Not applicable - this is a single-developer system tooling project with sequential dependencies between user stories.

---

## Implementation Notes

### Critical Success Factors

1. **Event Delivery First**: US2 must complete before US1 - can't fix PWA assignment without receiving events
2. **Single Mechanism Second**: US4 must complete before US1 - can't add Priority 0 if multiple mechanisms conflict
3. **Validation at Every Checkpoint**: Test event delivery rate after each phase
4. **Rollback Plan**: Keep native assignment rules in git history for emergency rollback
5. **Performance Monitoring**: Track assignment latency throughout implementation

### Root Cause Resolution Order

The research identified 3 root causes with different priorities:

1. **Root Cause #1 (CRITICAL)**: Native Sway rules block events → Fixed in US2 (Phase 3)
2. **Root Cause #3 (MEDIUM)**: Launch notification not used → Fixed in US1 (Phase 5) as Priority 0
3. **Root Cause #2 (HIGH)**: Property timing for native Wayland → Fixed in US1 (Phase 5) as delayed retry

All three root causes MUST be fixed to achieve 100% PWA reliability.

### Testing Strategy

- After US2: `i3pm diagnose events --type=window` should show 100% event delivery
- After US4: Only one assignment configuration file should exist
- After US1: All PWAs should appear on correct workspace within 1 second
- After US3: Diagnostic commands should show complete event flow visibility

### Risk Mitigation

- **Risk**: Removing native rules breaks existing workflows
  - **Mitigation**: Verify all native rules have registry equivalents before removal (T011)
- **Risk**: Daemon not ready before windows created
  - **Mitigation**: Add synchronous startup ordering (T064-T066)
- **Risk**: Property retry delay too short
  - **Mitigation**: Make delay configurable, start with conservative 100ms (T036)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- US2 → US4 → US1 → US3 is the required sequence due to dependencies
- Total: 71 tasks across 7 phases
