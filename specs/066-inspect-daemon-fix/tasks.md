# Tasks: Tree Monitor Inspect Command - Daemon Backend Fix

**Input**: Design documents from `/etc/nixos/specs/066-inspect-daemon-fix/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No automated tests requested - manual testing via CLI only

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Note**: Code fix is already implemented in `home-modules/tools/sway-tree-monitor/rpc/server.py` lines 333-337. Tasks focus on verification, deployment, and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Python daemon**: `home-modules/tools/sway-tree-monitor/` (local package)
- **NixOS modules**: `home-modules/tools/sway-tree-monitor.nix`, `home-modules/desktop/sway.nix`
- **TypeScript client**: `home-modules/tools/i3pm/src/` (completed in Feature 065, no changes)

---

## Phase 1: Setup (Verification & Pre-deployment)

**Purpose**: Verify existing implementation and prepare for deployment

- [X] T001 [P] Verify type conversion fix exists in home-modules/tools/sway-tree-monitor/rpc/server.py lines 333-337
- [X] T002 [P] Verify NixOS package version is 1.1.1 in home-modules/tools/sway-tree-monitor.nix (fixed Python deps packaging)
- [X] T003 [P] Verify daemon module import in home-modules/desktop/sway.nix
- [X] T004 Check current daemon status via systemctl --user status sway-tree-monitor (found packaging issue, fixed)

---

## Phase 2: Foundational (Deployment & Daemon Restart)

**Purpose**: Deploy updated daemon with fix and verify new code is loaded

**⚠️ CRITICAL**: No user story testing can begin until daemon is running with new code

- [ ] T005 Run nixos-rebuild dry-build to verify configuration compiles
- [ ] T006 Run sudo nixos-rebuild switch to deploy daemon version 1.1.0
- [ ] T007 Restart daemon via systemctl --user restart sway-tree-monitor
- [ ] T008 Verify daemon is running new code via journalctl --user -u sway-tree-monitor

**Checkpoint**: Daemon running with version 1.1.0 - user story testing can now begin

---

## Phase 3: User Story 1 - Inspect Individual Events (Priority: P1) 🎯 MVP

**Goal**: Users can drill down into individual window state events to understand exactly what changed, why it happened, and what system context was involved

**Independent Test**: Run `i3pm tree-monitor inspect <event_id>` and verify that detailed event information displays correctly with all sections (metadata, correlation, diff, enrichment). Delivers immediate value for debugging window behavior.

### Manual Testing for User Story 1

- [ ] T009 [US1] Query recent events via i3pm tree-monitor history --last 5 to get valid event IDs
- [ ] T010 [US1] Test inspect command with string event ID: i3pm tree-monitor inspect "15"
- [ ] T011 [US1] Test inspect command with integer event ID: i3pm tree-monitor inspect 15
- [ ] T012 [US1] Verify event metadata displays (ID, timestamp, type, significance level)
- [ ] T013 [US1] Verify user action correlation displays with confidence indicator
- [ ] T014 [US1] Verify field-level diff displays with old → new values
- [ ] T015 [US1] Verify I3PM enrichment data displays (PID, env vars, marks, launch context)
- [ ] T016 [US1] Test error handling for non-existent event ID (expect "Event not found")
- [ ] T017 [US1] Test error handling for invalid event ID: i3pm tree-monitor inspect "abc" (expect clear error message)
- [ ] T018 [US1] Test error handling when daemon not running (expect actionable error with startup instructions)

**Checkpoint**: At this point, User Story 1 should be fully functional - inspect command displays complete event details

---

## Phase 4: User Story 2 - JSON Output for Automation (Priority: P2)

**Goal**: Users can output event details as JSON for programmatic analysis, enabling integration with scripts, monitoring systems, and automated diagnostics

**Independent Test**: Run `i3pm tree-monitor inspect <event_id> --json` and verify valid JSON output that matches the RPC response schema. Enables scripting and automation use cases.

### Manual Testing for User Story 2

- [ ] T019 [US2] Test JSON output mode: i3pm tree-monitor inspect 15 --json
- [ ] T020 [US2] Verify JSON is valid via: i3pm tree-monitor inspect 15 --json | python3 -m json.tool
- [ ] T021 [US2] Verify all event fields present: event_id, timestamp_ms, event_type, diff, correlations, enrichment
- [ ] T022 [US2] Verify metadata fields: event_id matches request, timestamp_ms is integer, event_type is string
- [ ] T023 [US2] Verify diff structure: diff_id, total_changes, significance_score, significance_level, node_changes
- [ ] T024 [US2] Verify correlations structure: action, confidence, time_delta_ms, reasoning
- [ ] T025 [US2] Verify enrichment structure: window_id, pid, i3pm_app_id, project_marks, app_marks
- [ ] T026 [US2] Test JSON output integrates with jq: i3pm tree-monitor inspect 15 --json | jq '.diff.significance_level'

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - JSON automation works

---

## Phase 5: User Story 3 - Performance & Reliability (Priority: P3)

**Goal**: Inspect operations complete within 500ms and handle all edge cases gracefully, providing a smooth and reliable user experience

**Independent Test**: Measure response time with timing tests and verify edge case scenarios (timeouts, connection errors, malformed responses).

### Manual Testing for User Story 3

- [ ] T027 [US3] Measure response time: time i3pm tree-monitor inspect 15 (expect <500ms)
- [ ] T028 [US3] Test with 10 rapid consecutive requests to verify performance consistency
- [ ] T029 [US3] Test daemon timeout handling by stopping daemon and running inspect (expect 5s timeout + retry suggestion)
- [ ] T030 [US3] Test with event at buffer boundary (oldest event still in buffer)
- [ ] T031 [US3] Test with event just before buffer wraparound
- [ ] T032 [US3] Verify no events have missing correlation data (gracefully handled)
- [ ] T033 [US3] Verify no events have missing enrichment data (gracefully handled)
- [ ] T034 [US3] Verify events with no diff changes display "No changes detected"

**Checkpoint**: All user stories should now be independently functional - performance and reliability verified

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T035 [P] Verify all 6 success criteria from spec.md are met
- [ ] T036 [P] Test inspect command with --snapshots flag (verify large payloads work)
- [ ] T037 [P] Verify daemon memory usage stays below 50MB with 500 events
- [ ] T038 [P] Run quickstart.md validation: follow all 9 common tasks and verify outputs
- [ ] T039 Test RPC protocol directly via netcat: echo '{"jsonrpc":"2.0","method":"get_event","params":{"event_id":"15"},"id":1}' | nc -U /run/user/1000/sway-tree-monitor.sock
- [ ] T040 Verify backward compatibility: existing query_events RPC method still works
- [ ] T041 Document any edge cases or limitations discovered during testing

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup verification - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion (daemon running with new code)
  - User stories can proceed sequentially in priority order (P1 → P2 → P3)
  - Can also be tested in parallel if multiple testers available
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Extends US1 but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Validates US1/US2 but independently testable

### Within Each User Story

- All testing tasks within a story can run sequentially
- Some tasks can run in parallel (e.g., metadata verification vs diff verification)
- Error handling tests should run after success tests
- JSON validation should run after basic functionality is verified

### Parallel Opportunities

- Phase 1 (Setup): T001, T002, T003 can run in parallel
- Phase 6 (Polish): T035, T036, T037, T038 can run in parallel
- User Story 1 testing: Multiple tests can run concurrently if event IDs are different
- User Story 2 testing: Multiple JSON validation tests can run concurrently

---

## Parallel Example: User Story 1

```bash
# Launch multiple inspect tests together (different event IDs):
Task: "Test inspect with string event ID: i3pm tree-monitor inspect '15'"
Task: "Test inspect with integer event ID: i3pm tree-monitor inspect 20"
Task: "Test error handling for invalid ID: i3pm tree-monitor inspect 'abc'"

# These can all run simultaneously in different terminals
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (verification)
2. Complete Phase 2: Foundational (deployment and daemon restart - CRITICAL)
3. Complete Phase 3: User Story 1 (core inspect functionality)
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Demo/use if ready

### Incremental Delivery

1. Complete Setup + Foundational → Daemon deployed with fix
2. Add User Story 1 → Test independently → **MVP Ready!**
3. Add User Story 2 → Test independently → Automation support added
4. Add User Story 3 → Test independently → Production-ready quality
5. Polish phase → Final validation

### Sequential Testing Strategy

With single developer/tester:

1. Complete Setup + Foundational together
2. Test User Story 1 completely (10 tasks)
3. Test User Story 2 completely (8 tasks)
4. Test User Story 3 completely (8 tasks)
5. Final polish and validation (7 tasks)

---

## Success Criteria Validation

Map success criteria from spec.md to tasks:

| Success Criterion | Validated By Tasks |
|-------------------|-------------------|
| SC-001: Inspect any event within 500ms | T027, T028 (US3) |
| SC-002: Display all event sections with clear formatting | T012, T013, T014, T015 (US1) |
| SC-003: Error messages provide actionable next steps | T016, T017, T018 (US1), T029 (US3) |
| SC-004: JSON output produces valid, parsable JSON | T019, T020, T021-T026 (US2) |
| SC-005: 100% of events from query_events are inspectable | T009, T010, T011 (US1) |
| SC-006: System handles all error scenarios gracefully | T016, T017, T018 (US1), T029, T030-T034 (US3) |

---

## Notes

- [P] tasks = different verification points, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Manual testing approach (no automated test framework needed for 6 tasks)
- Code is already complete - tasks focus on verification and deployment
- Commit after Phase 2 (daemon deployment) and after each user story completion
- Stop at any checkpoint to validate story independently
- Estimated total time: 1-2 hours (mostly manual testing)
- TypeScript client from Feature 065 requires no changes
- Avoid: vague tests, overlapping test scenarios, missing error handling validation
