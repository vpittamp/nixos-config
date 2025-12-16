# Tasks: OpenTelemetry AI Assistant Monitoring

**Input**: Design documents from `/specs/123-otel-tracing/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested in specification - omitted. Add tests phase if TDD approach desired.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md:
- Python service: `scripts/otel-ai-monitor/`
- Nix modules: `home-modules/services/`, `home-modules/ai-assistants/`, `home-modules/desktop/`
- Tests: `tests/otel-ai-monitor/`

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Create project structure and Python package

- [x] T001 Create directory structure `scripts/otel-ai-monitor/` with `__init__.py`
- [x] T002 Create CLI entry point `scripts/otel-ai-monitor/__main__.py` with argument parsing (port, timeout settings)
- [x] T003 [P] Create Pydantic models in `scripts/otel-ai-monitor/models.py` (Session, SessionState, AITool, TelemetryEvent, SessionUpdate, SessionList per data-model.md)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core OTLP receiver and output infrastructure that ALL user stories depend on

**CRITICAL**: No user story can be implemented until Phase 2 is complete

- [x] T004 Implement OTLP HTTP receiver in `scripts/otel-ai-monitor/receiver.py` (aiohttp server on port 4318, POST /v1/logs endpoint)
- [x] T005 [P] Implement protobuf parsing in `scripts/otel-ai-monitor/receiver.py` (parse ExportLogsServiceRequest, extract log records)
- [x] T006 [P] Implement JSON parsing fallback in `scripts/otel-ai-monitor/receiver.py` (Content-Type: application/json support)
- [x] T007 Implement event extraction in `scripts/otel-ai-monitor/receiver.py` (map OTLP LogRecord to TelemetryEvent model)
- [x] T008 Implement JSON stream output in `scripts/otel-ai-monitor/output.py` (NDJSON writer to stdout, SessionUpdate/SessionList formats)
- [x] T009 [P] Implement named pipe output in `scripts/otel-ai-monitor/output.py` (write to `$XDG_RUNTIME_DIR/otel-ai-monitor.pipe`)
- [x] T010 Create Nix service module `home-modules/services/otel-ai-monitor.nix` (systemd user service, ExecStart, dependencies)
- [x] T011 [P] Add health endpoint `/health` in `scripts/otel-ai-monitor/receiver.py` (returns `{"status": "ok"}`)

**Checkpoint**: OTLP receiver accepts events and outputs JSON - ready for user story implementation

---

## Phase 3: User Story 1 - Real-Time Working State Indicator (Priority: P1)

**Goal**: Display working indicator in EWW top bar within 1 second of AI prompt submission

**Independent Test**: Start Claude Code, submit prompt, observe working indicator appears in top bar immediately

### Implementation for User Story 1

- [x] T012 [US1] Implement session tracker in `scripts/otel-ai-monitor/session_tracker.py` (create session on first event, thread-safe dict)
- [x] T013 [US1] Add event-to-session mapping in `scripts/otel-ai-monitor/session_tracker.py` (extract session_id from thread_id/conversation_id attributes)
- [x] T014 [US1] Implement IDLE→WORKING transition in `scripts/otel-ai-monitor/session_tracker.py` (trigger on user_prompt/conversation_starts events)
- [x] T015 [US1] Add tool detection in `scripts/otel-ai-monitor/session_tracker.py` (map claude_code.* → CLAUDE_CODE, codex.* → CODEX_CLI)
- [x] T016 [US1] Wire session tracker to receiver in `scripts/otel-ai-monitor/receiver.py` (call tracker on each parsed event)
- [x] T017 [US1] Emit SessionUpdate on state change in `scripts/otel-ai-monitor/session_tracker.py` (call output.write_update)
- [x] T018 [US1] Configure Claude Code OTLP export in `home-modules/ai-assistants/claude-code.nix` (add CLAUDE_CODE_ENABLE_TELEMETRY, OTEL_* env vars per research.md R2)
- [x] T019 [P] [US1] Create Codex CLI OTLP config template for `~/.codex/config.toml` in `home-modules/ai-assistants/codex.nix` (add [otel] section per research.md R3)
- [x] T020 [US1] Replace defpoll with deflisten in `home-modules/desktop/eww-top-bar/eww.yuck.nix` (consume otel-ai-monitor JSON stream)
- [x] T021 [US1] Create AI indicator widget in `home-modules/desktop/eww-top-bar/eww.yuck.nix` (show spinner icon for working state)
- [x] T022 [P] [US1] Add working state CSS in `home-modules/desktop/eww-top-bar/eww.scss.nix` (spinning animation for working indicator)

**Checkpoint**: Working indicator appears when AI receives prompt - User Story 1 complete

---

## Phase 4: User Story 2 - Completion Notification (Priority: P1)

**Goal**: Desktop notification appears within 1 second when AI processing completes

**Independent Test**: Submit prompt to Claude Code, switch windows, verify notification appears when complete

### Implementation for User Story 2

- [x] T023 [US2] Implement quiet period timer in `scripts/otel-ai-monitor/session_tracker.py` (3-second asyncio timer after last event)
- [x] T024 [US2] Implement WORKING→COMPLETED transition in `scripts/otel-ai-monitor/session_tracker.py` (trigger when quiet period expires)
- [x] T025 [US2] Implement desktop notifier in `scripts/otel-ai-monitor/notifier.py` (notify-send wrapper with app-name, urgency)
- [x] T026 [US2] Add notification on completion in `scripts/otel-ai-monitor/session_tracker.py` (call notifier when state → COMPLETED)
- [x] T027 [US2] Add focus action to notification in `scripts/otel-ai-monitor/notifier.py` (--action for terminal focus)
- [x] T028 [US2] Implement COMPLETED→IDLE auto-transition in `scripts/otel-ai-monitor/session_tracker.py` (30-second timeout)
- [x] T029 [US2] Add completed state icon in `home-modules/desktop/eww-top-bar/eww.yuck.nix` (show check icon for completed state)
- [x] T030 [P] [US2] Add completed state CSS in `home-modules/desktop/eww-top-bar/eww.scss.nix` (attention styling for completed)

**Checkpoint**: Notification appears on completion, indicator shows completed state - User Story 2 complete

---

## Phase 5: User Story 3 - Multi-Session Awareness (Priority: P2)

**Goal**: Monitoring panel shows all active sessions with distinct states

**Independent Test**: Start Claude Code in two projects, verify both appear in monitoring panel with distinct states

### Implementation for User Story 3

- [x] T031 [US3] Implement periodic SessionList broadcast in `scripts/otel-ai-monitor/session_tracker.py` (every 5 seconds, full state for recovery)
- [x] T032 [US3] Add project extraction in `scripts/otel-ai-monitor/session_tracker.py` (parse project context from telemetry attributes)
- [x] T033 [US3] Implement session expiry in `scripts/otel-ai-monitor/session_tracker.py` (5-minute timeout → EXPIRED → remove)
- [x] T034 [US3] Implement session cleanup on close in `scripts/otel-ai-monitor/session_tracker.py` (detect terminal close, remove within 5 seconds)
- [x] T035 [US3] Update monitoring panel in `home-modules/desktop/eww-monitoring-panel.nix` (consume JSON stream instead of badge files)
- [x] T036 [US3] Create AI sessions tab in `home-modules/desktop/eww-monitoring-panel.nix` (list sessions with tool type, project, state)
- [x] T037 [P] [US3] Add multi-session CSS in `home-modules/desktop/eww-monitoring-panel.nix` (styling for session list)

**Checkpoint**: Multiple sessions shown with distinct states - User Story 3 complete

---

## Phase 6: User Story 4 - Session Metrics (Priority: P3)

**Goal**: Token consumption displayed per session

**Independent Test**: Complete AI interaction, check if token counts appear in session details

### Implementation for User Story 4

- [x] T038 [US4] Add token metric extraction in `scripts/otel-ai-monitor/session_tracker.py` (parse input_tokens, output_tokens, cache_tokens from codex.sse_event)
- [x] T039 [US4] Add metrics to Session model in `scripts/otel-ai-monitor/models.py` (cumulative token counters)
- [x] T040 [US4] Include metrics in SessionUpdate output in `scripts/otel-ai-monitor/output.py` (add metrics field when available)
- [x] T041 [US4] Display metrics in monitoring panel in `home-modules/desktop/eww-monitoring-panel.nix` (show token counts in session details)
- [x] T042 [P] [US4] Add metrics CSS in `home-modules/desktop/eww-monitoring-panel.nix` (styling for token display)

**Checkpoint**: Token metrics visible in session details - User Story 4 complete

---

## Phase 7: Legacy Cleanup & Polish

**Purpose**: Remove legacy code, final integration

- [x] T043 [P] Remove `scripts/tmux-ai-monitor/` directory (entire legacy monitor)
- [x] T044 [P] Remove `scripts/claude-hooks/prompt-submit-notification.sh`
- [x] T045 [P] Remove `scripts/claude-hooks/stop-notification.sh`
- [x] T046 [P] Remove `scripts/claude-hooks/stop-notification-handler.sh`
- [x] T047 [P] Remove `scripts/claude-hooks/swaync-action-callback.sh`
- [x] T048 [P] Remove `home-modules/services/tmux-ai-monitor.nix` (legacy service module)
- [x] T049 Remove `home-modules/desktop/eww-top-bar/scripts/ai-sessions-status.sh` (polling script)
- [x] T050 Update `home-modules/ai-assistants/claude-code.nix` (remove state hooks, keep bash-history hook only)
- [x] T051 Remove tmux-ai-monitor.enable from host configs (hetzner.nix, etc.)
- [x] T052 Add otel-ai-monitor.enable to host configs (hetzner.nix)
- [x] T053 Run quickstart.md validation (verify all steps work per quickstart.md)
- [x] T054 NixOS dry-build test (`sudo nixos-rebuild dry-build --flake .#hetzner-sway`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - Core MVP
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2), can parallel with US1
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2), can parallel with US1/US2
- **User Story 4 (Phase 6)**: Depends on Foundational (Phase 2), can parallel with others
- **Cleanup (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

- **User Story 1 (P1)**: Independent - core working state detection
- **User Story 2 (P1)**: Independent - completion notification (shares state machine with US1)
- **User Story 3 (P2)**: Independent - multi-session tracking
- **User Story 4 (P3)**: Independent - metrics display (uses same data model)

Note: US1 and US2 both modify `session_tracker.py` and EWW widgets - implement sequentially or coordinate carefully.

### Within Each User Story

- Models before services
- Session tracker before output
- Python service before Nix configuration
- Nix configuration before EWW widgets
- Core implementation before styling

### Parallel Opportunities

**Phase 1 (Setup):**
- T001, T002 sequential (structure first)
- T003 can parallel with T002

**Phase 2 (Foundational):**
- T005, T006 parallel (both extend receiver.py parsing)
- T009, T011 parallel (independent receiver features)

**Phase 3-6 (User Stories):**
- CSS tasks (T022, T030, T037, T042) can all parallel (different files)
- T019 (Codex config) parallel with Claude Code tasks
- All user stories can technically parallel, but US1+US2 share session_tracker.py

**Phase 7 (Cleanup):**
- T043-T048 all parallel (different files to remove)

---

## Parallel Example: User Story 1

```bash
# After T017 (session tracker emits updates), these can run in parallel:
Task: T019 [P] [US1] "Create Codex CLI OTLP config template"
Task: T022 [P] [US1] "Add working state CSS"

# Earlier in Phase 2, these can run in parallel:
Task: T005 [P] "Implement protobuf parsing"
Task: T006 [P] "Implement JSON parsing fallback"
Task: T011 [P] "Add health endpoint"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011)
3. Complete Phase 3: User Story 1 - Working State (T012-T022)
4. Complete Phase 4: User Story 2 - Notifications (T023-T030)
5. **STOP and VALIDATE**: Test both stories with Claude Code
6. Skip US3/US4 if MVP sufficient

### Incremental Delivery

1. Setup + Foundational → OTLP receiver working
2. Add User Story 1 → Working indicator visible (First value!)
3. Add User Story 2 → Notifications working (Core complete!)
4. Add User Story 3 → Multi-session support (Power user feature)
5. Add User Story 4 → Metrics visible (Analytics feature)
6. Cleanup → Legacy code removed

### Single Developer Strategy

Since US1 and US2 share `session_tracker.py`:

1. Complete Setup + Foundational
2. Implement US1 first (working state)
3. Implement US2 immediately after (adds completion to same state machine)
4. Validate US1+US2 together
5. Add US3 (multi-session)
6. Add US4 (metrics)
7. Cleanup phase

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- Each user story is independently testable after completion
- US1 and US2 are both Priority P1 - implement both for minimum viable product
- Commit after each task or logical group
- Nix rebuild required after modifying .nix files
- Test with `journalctl --user -u otel-ai-monitor -f` for service logs
