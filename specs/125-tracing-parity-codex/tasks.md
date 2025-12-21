# Tasks: Tracing Parity for Gemini CLI and Codex CLI

**Input**: Design documents from `/specs/125-tracing-parity-codex/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Manual verification via CLI runs + Grafana trace inspection (as per plan.md)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Nix modules**: `home-modules/`, `modules/`
- **Python service**: `scripts/otel-ai-monitor/`
- **Specs**: `specs/125-tracing-parity-codex/`

---

## Phase 1: Setup (Verification)

**Purpose**: Verify existing infrastructure is ready for enhancement

- [X] T001 Verify Grafana Alloy is running and receiving telemetry on port 4318
- [X] T002 Verify otel-ai-monitor service is running and tracking Claude Code sessions
- [X] T003 [P] Verify Gemini CLI is installed and OTEL config exists in home-modules/ai-assistants/gemini-cli.nix
- [X] T004 [P] Verify Codex CLI is installed and OTEL config exists in home-modules/ai-assistants/codex.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data model and provider infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Add Provider enum (anthropic, openai, google) to scripts/otel-ai-monitor/models.py
- [X] T006 Add provider pricing tables (Anthropic, OpenAI, Google models) to scripts/otel-ai-monitor/models.py
- [X] T007 Add event name mappings per provider to scripts/otel-ai-monitor/models.py
- [X] T008 Add session_id attribute mapping per provider to scripts/otel-ai-monitor/models.py
- [X] T009 Extend Session model with provider field in scripts/otel-ai-monitor/models.py
- [X] T010 Run nixos-rebuild dry-build to verify Nix changes compile

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Unified Trace Analysis in Grafana (Priority: P1) 🎯 MVP

**Goal**: Developers can query Tempo for traces from all three CLIs using the same attribute filters

**Independent Test**: Run each CLI, verify traces appear in Grafana Tempo with normalized attributes (session.id, openinference.span.kind, gen_ai.*)

### Implementation for User Story 1

- [X] T011 [P] [US1] Add provider detection logic based on service.name in scripts/otel-ai-monitor/receiver.py
- [X] T012 [P] [US1] Add session.id extraction for Codex (conversation_id → session.id) in scripts/otel-ai-monitor/receiver.py
- [X] T013 [P] [US1] Add session.id extraction for Gemini (session.id passthrough) in scripts/otel-ai-monitor/receiver.py
- [X] T014 [US1] Create new Session for each detected provider in scripts/otel-ai-monitor/session_tracker.py
- [X] T015 [US1] Verify Gemini CLI OTEL config sends to localhost:4318 in home-modules/ai-assistants/gemini-cli.nix
- [X] T016 [US1] Verify Codex CLI OTEL config sends to localhost:4318 in home-modules/ai-assistants/codex.nix
- [X] T017 [US1] Run nixos-rebuild switch and test with Gemini CLI session
- [X] T018 [US1] Test with Codex CLI session and verify traces in Grafana Tempo
- [ ] T019 [US1] Verify all three CLIs queryable with same filters (session.id, gen_ai.request.model)

**Checkpoint**: User Story 1 complete - traces from all CLIs visible in Grafana with unified queries

---

## Phase 4: User Story 2 - Cost Visibility Across All CLIs (Priority: P2)

**Goal**: Cost metrics (gen_ai.usage.cost_usd) appear on LLM spans for all CLIs

**Independent Test**: Run sessions on each CLI, verify cost metrics in otel-ai-monitor logs and Grafana

### Implementation for User Story 2

- [X] T020 [P] [US2] Create pricing.py module with calculate_cost(provider, model, input_tokens, output_tokens) in scripts/otel-ai-monitor/pricing.py
- [X] T021 [P] [US2] Add default rate ($5/1M) for unrecognized models with cost.estimated=true in scripts/otel-ai-monitor/pricing.py
- [X] T022 [US2] Extract token counts from span attributes in scripts/otel-ai-monitor/receiver.py
- [X] T023 [US2] Calculate and store cost_usd in SessionMetrics in scripts/otel-ai-monitor/session_tracker.py
- [X] T024 [US2] Add cost aggregation to session summary output in scripts/otel-ai-monitor/session_tracker.py
- [ ] T025 [US2] Test cost calculation with Gemini CLI session
- [ ] T026 [US2] Test cost calculation with Codex CLI session
- [ ] T027 [US2] Verify costs appear in Grafana metrics

**Checkpoint**: User Story 2 complete - cost metrics visible for all CLIs

---

## Phase 5: User Story 3 - Local Session Tracking for All CLIs (Priority: P2)

**Goal**: EWW panel shows session status (idle/working/completed) for Gemini and Codex CLIs

**Independent Test**: Run each CLI, observe EWW panel status transitions and desktop notifications

### Implementation for User Story 3

- [X] T028 [P] [US3] Add Gemini CLI event detection (api.request, tool.call) in scripts/otel-ai-monitor/receiver.py
- [X] T029 [P] [US3] Add Codex CLI event detection (agent-turn-complete, tool_calls) in scripts/otel-ai-monitor/receiver.py
- [X] T030 [US3] Update session state (IDLE→WORKING→COMPLETED) based on events in scripts/otel-ai-monitor/session_tracker.py
- [X] T031 [US3] Emit EWW-compatible session status for Gemini/Codex in scripts/otel-ai-monitor/session_tracker.py
- [X] T032 [US3] Add desktop notification trigger on session completion in scripts/otel-ai-monitor/session_tracker.py
- [ ] T033 [US3] Test EWW panel with Gemini CLI session
- [X] T034 [US3] Test EWW panel with Codex CLI session
- [ ] T035 [US3] Verify desktop notifications fire on session completion

**Checkpoint**: User Story 3 complete - session tracking works for all CLIs in EWW panel

---

## Phase 6: User Story 4 - Trace-Log-Metric Correlation (Priority: P3)

**Goal**: Navigate from traces to logs to metrics in Grafana via session.id

**Independent Test**: Follow a trace in Grafana, verify links to Loki logs and Mimir metrics

### Implementation for User Story 4

- [X] T036 [US4] Verify session.id is included in log output for Gemini/Codex in scripts/otel-ai-monitor/session_tracker.py
- [ ] T037 [US4] Verify Alloy spanmetrics connector includes session.id dimension in modules/services/grafana-alloy.nix
- [ ] T038 [US4] Test trace-to-log correlation in Grafana for Gemini CLI
- [ ] T039 [US4] Test trace-to-log correlation in Grafana for Codex CLI
- [ ] T040 [US4] Test metric exemplars link back to traces

**Checkpoint**: User Story 4 complete - full trace-log-metric correlation works

---

## Phase 7: User Story 5 - Error Tracking Across All CLIs (Priority: P3)

**Goal**: Error classifications (auth, rate_limit, timeout, server) appear on failed spans

**Independent Test**: Induce errors (rate limits, auth failures), verify error.type attributes

### Implementation for User Story 5

- [X] T041 [P] [US5] Add error classification logic based on HTTP status in scripts/otel-ai-monitor/session_tracker.py
- [X] T042 [P] [US5] Add error_count tracking to SessionMetrics in scripts/otel-ai-monitor/session_tracker.py
- [X] T043 [US5] Map Gemini CLI error attributes to error.type in scripts/otel-ai-monitor/session_tracker.py
- [X] T044 [US5] Map Codex CLI error attributes to error.type in scripts/otel-ai-monitor/session_tracker.py
- [ ] T045 [US5] Test error classification with simulated rate limit (429)
- [ ] T046 [US5] Test error classification with auth error

**Checkpoint**: User Story 5 complete - error tracking works for all CLIs

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [X] T047 [P] Update CLAUDE.md with new Gemini/Codex tracing commands
- [ ] T048 [P] Run full quickstart.md validation checklist
- [ ] T049 Verify graceful degradation when Alloy is temporarily stopped
- [ ] T050 Clean up any debug logging from development

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - verification only
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Foundation only - No dependencies on other stories
- **User Story 2 (P2)**: Foundation + US1 (needs session.id extraction from US1)
- **User Story 3 (P2)**: Foundation + US1 (needs provider detection from US1)
- **User Story 4 (P3)**: Foundation + US1 + US3 (needs session tracking from US3)
- **User Story 5 (P3)**: Foundation + US1 (needs provider detection from US1)

### Within Each User Story

- Nix config verification before Python changes
- receiver.py changes before session_tracker.py changes
- Python changes before nixos-rebuild switch
- Manual testing after each story

### Parallel Opportunities

- T003, T004: Verify CLI configs in parallel
- T011, T012, T013: Provider detection + session.id extraction in parallel
- T015, T016: Nix config verification in parallel
- T020, T021: pricing.py module creation in parallel
- T028, T029: Event detection for both CLIs in parallel
- T041, T042: Error handling setup in parallel
- T047, T048: Documentation updates in parallel

---

## Parallel Example: User Story 1

```bash
# Launch provider detection and session.id extraction in parallel:
Task: "Add provider detection logic based on service.name in scripts/otel-ai-monitor/receiver.py"
Task: "Add session.id extraction for Codex (conversation_id → session.id) in scripts/otel-ai-monitor/receiver.py"
Task: "Add session.id extraction for Gemini (session.id passthrough) in scripts/otel-ai-monitor/receiver.py"

# Then sequentially:
Task: "Create new Session for each detected provider in scripts/otel-ai-monitor/session_tracker.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup verification
2. Complete Phase 2: Foundational (Provider enum, pricing, event mappings)
3. Complete Phase 3: User Story 1 (Unified trace analysis)
4. **STOP and VALIDATE**: Test all three CLIs in Grafana Tempo
5. Deploy if ready - basic trace parity achieved

### Incremental Delivery

1. Setup + Foundational → Provider infrastructure ready
2. Add User Story 1 → Unified traces in Grafana (MVP!)
3. Add User Story 2 → Cost visibility added
4. Add User Story 3 → EWW session tracking added
5. Add User Story 4 → Full correlation in Grafana
6. Add User Story 5 → Error tracking added
7. Each story adds value without breaking previous stories

---

## Notes

- All Nix changes require `nixos-rebuild dry-build` before `switch`
- Python changes to otel-ai-monitor require `systemctl --user restart otel-ai-monitor`
- Manual testing involves running CLI sessions and checking Grafana/EWW
- Session.id extraction is critical for all subsequent stories
- Cost calculation uses hardcoded pricing (can be externalized later)
