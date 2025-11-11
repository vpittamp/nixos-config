# Tasks: Workspace Mode Visual Feedback

**Input**: Design documents from `/etc/nixos/specs/058-workspace-mode-feedback/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are NOT included in this feature per spec.md (no test requirements specified)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and Python environment setup

- [X] T001 Create feature branch `058-workspace-mode-feedback` from main
- [X] T002 [P] Add `PendingWorkspaceState` Pydantic model to `home-modules/desktop/i3-project-event-daemon/models.py`
- [X] T003 [P] Add `WorkspaceModeEvent` Pydantic model to `home-modules/tools/sway-workspace-panel/models.py`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core IPC infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement `_calculate_pending_workspace()` method in `home-modules/desktop/i3-project-event-daemon/workspace_mode.py` (returns workspace number from accumulated_digits, validates 1-70 range)
- [X] T005 Implement `_get_output_for_workspace()` method integration in `workspace_mode.py` (resolves monitor output from workspace number per Feature 001)
- [X] T006 Extend `add_digit()` method in `workspace_mode.py` to calculate and emit pending workspace state via IPC
- [X] T007 Extend `execute()` method in `workspace_mode.py` to emit pending workspace state before navigation
- [X] T008 Extend `cancel()` method in `workspace_mode.py` to emit null pending workspace state on mode exit
- [X] T009 Implement `_emit_workspace_mode_event()` helper method in `workspace_mode.py` for async event broadcasting
- [X] T010 Extend `sway-workspace-panel` daemon in `home-modules/tools/sway-workspace-panel/workspace_panel.py` to subscribe to i3pm daemon IPC socket
- [X] T011 Implement `handle_workspace_mode_event()` handler in `workspace_panel.py` to process incoming pending workspace events

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Workspace Button Pending Highlight (Priority: P1) 🎯 MVP

**Goal**: Highlight workspace buttons in yellow when user types corresponding digits in workspace mode, showing exactly which workspace will be focused when Enter is pressed

**Independent Test**: Enter workspace mode (CapsLock), type "23", visually verify workspace 23 button shows yellow pending highlight that clears on Enter

### Implementation for User Story 1

- [X] T012 [P] [US1] Add `.workspace-button.pending` CSS class to `home-modules/desktop/eww-workspace-bar-styles.scss` with yellow Catppuccin Mocha styling (background: rgba(249, 226, 175, 0.25), border, icon glow)
- [X] T013 [P] [US1] Add `pending` boolean parameter to `workspace-button` Eww widget in `home-modules/desktop/eww-workspace-bar.nix` Yuck definition
- [X] T014 [US1] Update `workspace_panel.py` to inject `pending: true/false` field in workspace Yuck output based on pending_workspace event matching workspace number
- [X] T015 [US1] Update `workspace_panel.py` to filter pending highlight by output name (only highlight on monitor where workspace will appear)
- [X] T016 [US1] Update `workspace_panel.py` to clear pending state when workspace mode exits (event_type="cancel" or "execute")
- [X] T017 [US1] Add logging for pending workspace calculation and event emission in `workspace_mode.py`
- [X] T018 [US1] Add CSS transition properties for smooth pending highlight fade in/out (transition: all 0.2s)
- [X] T019 [US1] Implement pending state mutex logic (pending overrides focused on same workspace button)
- [X] T020 [US1] Update Nix module to rebuild Eww workspace bar with new pending CSS classes

**Checkpoint**: User Story 1 (MVP) should be fully functional - type workspace digits, see yellow button highlight, press Enter to navigate

---

## Phase 4: User Story 2 - Target Workspace Preview Card (Priority: P2)

**Goal**: Display floating preview card showing target workspace number, icon, and application name when user types digits in workspace mode

**Independent Test**: Enter workspace mode, type "5", verify preview card appears showing "Workspace 5" with workspace icon and app name (if workspace has windows)

**⚠️ DEFERRED**: This user story is marked P2 (lower priority than MVP). Consider implementing after User Story 1 is validated in production.

### Implementation for User Story 2 (When Prioritized)

- [ ] T021 [US2] Create Eww floating window widget definition for workspace preview card in `home-modules/desktop/eww-workspace-preview-card.nix`
- [ ] T022 [P] [US2] Add preview card CSS styling to `home-modules/desktop/eww-workspace-bar-styles.scss` (card background, positioning, fade animations)
- [ ] T023 [US2] Implement preview card positioning logic (near workspace bar, on correct monitor per Feature 001)
- [ ] T024 [US2] Extend `handle_workspace_mode_event()` in `workspace_panel.py` to emit preview card Yuck literal with workspace details
- [ ] T025 [US2] Add workspace icon and application name lookup in preview card using existing Feature 057 icon resolution logic
- [ ] T026 [US2] Implement "Empty" state display for workspaces with no windows in preview card
- [ ] T027 [US2] Add fade-in animation (<300ms) when preview card appears
- [ ] T028 [US2] Add fade-out animation (<300ms) when workspace mode exits
- [ ] T029 [US2] Implement multi-window display (show first app + count of additional windows, e.g., "Firefox +2 more")
- [ ] T030 [US2] Add mode type differentiation in preview card header ("Workspace X" for goto mode, "Move to Workspace X" for move mode)

**Checkpoint**: Preview card should appear alongside pending button highlight, providing richer workspace context

---

## Phase 5: User Story 3 - Notification Badge on Workspace Button (Priority: P2)

**Goal**: Display Apple-style circular red badge (8px diameter) in top-right corner of workspace buttons when workspaces have urgent windows, using Eww native overlay widget

**Independent Test**: Trigger urgent window on workspace 5, verify red circular badge appears on workspace 5 button, badge fades out when urgent clears

### Implementation for User Story 3

- [X] T031 [P] [US3] Refactor `workspace-button` widget in `home-modules/desktop/eww-workspace-bar.nix` to use Eww `overlay` structure (base button as first child, badge container as second child)
- [X] T032 [P] [US3] Add `.notification-badge-container` CSS class to `home-modules/desktop/eww-workspace-bar-styles.scss` (positioning: margin 2px 2px 0 0)
- [X] T033 [P] [US3] Add `.notification-badge` CSS class with Catppuccin Mocha Red styling (min-width/height 8px, background #f38ba8, border 2px white, border-radius 50%)
- [X] T034 [US3] Add badge overlay box to Yuck widget with `:visible urgent` attribute (badge visibility tied to workspace urgent state)
- [X] T035 [US3] Add CSS fade-out transition for badge (opacity transition 0.2s) when urgent state clears
- [X] T036 [US3] Verify badge and pending highlight can coexist (urgent workspace with pending state shows both yellow background and red badge)
- [X] T037 [US3] Update workspace button tooltip to include urgent state information when badge is visible
- [X] T038 [US3] Test badge layering with Eww overlay widget (badge should render on top without layout shifts)

**Checkpoint**: Notification badges should render cleanly on urgent workspaces, compatible with pending highlights

---

## Phase 6: User Story 4 - Multi-Digit Workspace Confidence Indicator (Priority: P3)

**Goal**: Show visual confirmation of digit accumulation as user types multi-digit workspace numbers (e.g., "2_" → "23")

**Independent Test**: Enter workspace mode, type "2" (verify "2_" displayed), pause, type "3" (verify "23" displayed)

**⚠️ DEFERRED**: This user story is marked P3 (lowest priority). Consider implementing after US1, US2, US3 are validated.

### Implementation for User Story 4 (When Prioritized)

- [ ] T039 [US4] Extend preview card (from US2) to show digit accumulation indicator ("2_" when single digit entered)
- [ ] T040 [US4] Implement underscore removal logic when second digit entered ("2_" → "23")
- [ ] T041 [US4] Implement leading zero handling display (typing "0" then "5" shows "5" not "05")
- [ ] T042 [US4] Add auto-resolve timer (500ms delay after single digit to resolve workspace, e.g., "5" → "Workspace 5")
- [ ] T043 [US4] Display resolved workspace name in preview card after auto-resolve timeout

**Checkpoint**: Multi-digit workspace entry should feel confident and responsive with clear visual feedback

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and refinements across all user stories

- [X] T044 [P] Update `quickstart.md` with real usage examples and troubleshooting for implemented user stories
- [X] T045 [P] Update `/etc/nixos/CLAUDE.md` with feature reference (keybindings, CLI commands, architecture notes)
- [X] T046 Validate CSS contrast ratios meet WCAG AA standards (yellow on dark: ~11:1 contrast ratio)
- [X] T047 Verify multi-monitor pending highlight behavior on Hetzner Cloud (3 virtual displays)
- [X] T048 Verify single-monitor behavior on M1 Mac (eDP-1)
- [X] T049 Performance validation: Measure end-to-end latency from digit press to button highlight (<50ms requirement)
- [X] T050 Edge case validation: Test invalid workspace (99), leading zeros (05), rapid digit entry (>10/sec)
- [X] T051 Code cleanup: Remove debug logging, optimize IPC event payload size (<500 bytes)
- [X] T052 Run quickstart.md validation scenarios for all implemented user stories

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in priority order (P1 → P2 → P3)
  - Or P2/P3 can be deferred if MVP (P1) is sufficient
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - **REQUIRED FOR MVP**
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent of US1 (complements button highlight with preview card)
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Independent of US1/US2 (notification badge uses separate overlay layer)
- **User Story 4 (P3)**: Depends on User Story 2 (uses preview card for digit echo display)

### Within Each User Story

- CSS/Yuck widget changes marked [P] can run in parallel
- Daemon logic changes must happen before UI updates
- Each story complete before moving to next priority

### Parallel Opportunities

- **Phase 1 Setup**: T002 and T003 can run in parallel (different files)
- **Phase 3 (US1)**: T012 (CSS) and T013 (Yuck) can run in parallel with T017 (logging)
- **Phase 5 (US3)**: T032 (badge container CSS) and T033 (badge CSS) can run in parallel
- **Phase 7 Polish**: T044 (quickstart) and T045 (CLAUDE.md) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch CSS and Yuck widget updates together:
Task T012: "Add .workspace-button.pending CSS class to eww-workspace-bar-styles.scss"
Task T013: "Add pending boolean parameter to workspace-button Eww widget"

# While CSS/Yuck changes are happening, add logging in parallel:
Task T017: "Add logging for pending workspace calculation and event emission"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

**Recommended Approach**: Implement US1 (Pending Highlight) first, validate in production, then prioritize US2/US3 based on user feedback

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011) - CRITICAL - blocks all stories
3. Complete Phase 3: User Story 1 (T012-T020)
4. **STOP and VALIDATE**: Test pending highlight independently
   - Enter workspace mode, type digits, verify yellow button highlight
   - Test on both M1 Mac (single monitor) and Hetzner (multi-monitor)
   - Measure latency (<50ms requirement)
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. **DECISION POINT**: Based on user feedback, prioritize:
   - Option A: Add User Story 3 (notification badges) - simpler, high visual impact
   - Option B: Add User Story 2 (preview card) - more complex, richer context
   - Option C: Ship MVP and gather more usage data before prioritizing US2/US3
4. Add User Story 4 (digit echo) if US2 already implemented

### Single Developer Strategy (Recommended)

1. Complete Phase 1 + Phase 2 (foundation)
2. Implement User Story 1 (P1) - MVP milestone
3. Validate MVP with real usage
4. Prioritize User Story 2 or 3 based on feedback
5. Defer User Story 4 (P3) unless US2 already exists

---

## Suggested MVP Scope

**Minimum Viable Product**: User Story 1 only (Pending Button Highlight)

**Rationale**:
- US1 addresses the core user problem (no visual feedback in workspace mode)
- US1 leverages existing workspace bar UI (familiar to users)
- US1 has minimal implementation complexity (CSS + IPC events)
- US2 (preview card) adds complexity without addressing core problem
- US3 (badges) is complementary but not critical for MVP
- US4 (digit echo) provides diminishing returns for MVP

**MVP Tasks**: T001-T020 (20 tasks)
- Phase 1: Setup (3 tasks)
- Phase 2: Foundational (8 tasks)
- Phase 3: User Story 1 (9 tasks)

**Total Implementation Estimate**: ~8-12 hours for MVP
- Foundation: 4-6 hours (IPC event system, daemon extensions)
- User Story 1: 3-5 hours (CSS, Yuck, pending state logic)
- Validation: 1 hour (manual testing, performance measurement)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- **MVP recommendation**: Implement US1 only, validate, then prioritize US2/US3 based on feedback
- US2, US3, US4 marked as **DEFERRED** (P2/P3) - implement incrementally after MVP validation
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
