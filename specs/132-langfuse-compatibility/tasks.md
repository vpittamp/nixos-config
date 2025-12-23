# Tasks: Langfuse-Compatible AI CLI Tracing

**Input**: Design documents from `/specs/132-langfuse-compatibility/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓, quickstart.md ✓

**Tests**: Not explicitly requested in specification. Tests omitted per task generation rules.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md project structure:
- **Interceptors**: `scripts/` at repository root
- **Monitor Service**: `scripts/otel-ai-monitor/`
- **Nix Modules**: `modules/services/`, `home-modules/tools/`
- **Specs**: `specs/132-langfuse-compatibility/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: NixOS module configuration and Langfuse credential management

- [X] T001 Add Langfuse configuration options to `modules/services/grafana-alloy.nix`
- [X] T002 [P] Add Langfuse environment variables to `home-modules/ai-assistants/claude-code.nix`
- [X] T003 [P] Add Langfuse enable and endpoint config in `configurations/hetzner.nix`
- [X] T004 Add base64 auth header generation script in `scripts/langfuse-auth.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core attribute mappings and OTEL export infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Add Langfuse-specific attribute constants to `scripts/otel-ai-monitor/models.py`
- [X] T006 [P] SKIPPED - Langfuse export handled by Alloy (T001), no separate exporter needed
- [X] T007 [P] Add Langfuse export destination to Alloy config in `modules/services/grafana-alloy.nix` (done in T001)
- [X] T008 Add span enrichment hooks in `scripts/otel-ai-monitor/receiver.py` for `langfuse.*` attributes
- [X] T009 MANUAL - Verify existing EWW panel monitoring is unaffected by running `systemctl --user status eww-monitoring-panel`

**Checkpoint**: Foundation ready - Langfuse export pipeline operational

---

## Phase 3: User Story 1 - View AI Sessions as Langfuse Traces (Priority: P1) 🎯 MVP

**Goal**: AI CLI interactions appear as properly structured traces in Langfuse with chain → llm → tool hierarchy

**Independent Test**: Run a Claude Code session, then view the resulting trace in Langfuse UI with correctly nested generations and tool calls displayed

### Implementation for User Story 1

- [X] T010 [P] [US1] Add `langfuse.session.id` and `langfuse.user.id` for trace root in `scripts/minimal-otel-interceptor.js`
- [X] T011 [P] [US1] Add Langfuse attributes for LLM generation spans in `scripts/minimal-otel-interceptor.js`
- [X] T012 [US1] Add `openinference.span.kind` attributes (CHAIN, LLM, TOOL) in `scripts/minimal-otel-interceptor.js`
- [X] T013 [US1] Add Langfuse attributes in `scripts/otel-ai-monitor/receiver.py` with `enrich_span_for_langfuse`
- [X] T014 [P] [US1] Add Langfuse attributes for Codex CLI in `scripts/codex-otel-interceptor.js`
- [X] T015 [P] [US1] Add Langfuse attributes for Gemini CLI in `scripts/gemini-otel-interceptor.js`
- [X] T016 [US1] EXISTING - Parent-child span relationships already exist in interceptor
- [X] T017 [US1] EXISTING - Span naming already semantic (`LLM Call: Sonnet`, `Turn #1: prompt...`)

**Checkpoint**: Claude Code sessions appear as properly hierarchical traces in Langfuse

---

## Phase 4: User Story 2 - Analyze Token Usage and Costs in Langfuse (Priority: P1)

**Goal**: Accurate token counts and cost metrics appear in Langfuse generation observations

**Independent Test**: Run an AI CLI command with known token counts, verify Langfuse displays matching input/output/cache token counts and calculated costs

### Implementation for User Story 2

- [X] T018 [P] [US2] Add `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens` extraction in `scripts/minimal-otel-interceptor.js`
- [X] T019 [P] [US2] Add `gen_ai.usage.cost` attribute from API response in `scripts/minimal-otel-interceptor.js`
- [X] T020 [US2] EXISTING - Token aggregation already handled in interceptors (cache_read + cache_creation tracked per-span)
- [X] T021 [US2] Add `langfuse.observation.usage_details` JSON attribute with cache token breakdown in all interceptors
- [X] T022 [US2] Add `langfuse.observation.cost_details` JSON attribute in all interceptors
- [X] T023 [P] [US2] Add Codex-specific token extraction (`reasoning_token_count`, `tool_token_count`) in `scripts/codex-otel-interceptor.js`
- [X] T024 [P] [US2] Add Gemini-specific token extraction in `scripts/gemini-otel-interceptor.js`
- [X] T025 [US2] EXISTING - Usage aggregation across turns already implemented in interceptors

**Checkpoint**: Token counts and costs visible in Langfuse generation observations

---

## Phase 5: User Story 3 - Trace Tool Calls and MCP Operations (Priority: P2)

**Goal**: Tool invocations appear as distinct observations in Langfuse with inputs/outputs and parent-child relationships

**Independent Test**: Run Claude Code session using Read/Write/Bash tools, verify each tool call appears as "tool" type observation with inputs and results

### Implementation for User Story 3

- [X] T026 [P] [US3] Add `langfuse.observation.type = "span"` for tool spans in `scripts/minimal-otel-interceptor.js`
- [X] T027 [P] [US3] Add `gen_ai.tool.name` and `gen_ai.tool.call.id` attributes in `scripts/minimal-otel-interceptor.js`
- [X] T028 [US3] Add `langfuse.observation.input` (tool parameters as JSON) in interceptors
- [X] T029 [US3] EXISTING - Tool output already in `output.value` attribute for tools that provide it
- [X] T030 [US3] EXISTING - tool_use_id correlation via `gen_ai.tool.call.id` and parent span linking
- [X] T031 [US3] Add `langfuse.observation.level = "ERROR"` for failed tool calls in interceptors
- [X] T032 [P] [US3] EXISTING - MCP tool names already include server prefix in tool.name attribute
- [X] T033 [US3] EXISTING - Task tool spans already use AGENT span kind with parent-child linking
- [X] T034 [US3] EXISTING - Tool run cleanup on conversation end already in session tracker

**Checkpoint**: Tool calls visible as properly nested observations in Langfuse

---

## Phase 6: User Story 4 - Group Related Traces by Session (Priority: P2)

**Goal**: Related AI sessions are grouped by session ID in Langfuse

**Independent Test**: Run multiple Claude Code sessions in same i3pm project, verify Langfuse groups them under same session

### Implementation for User Story 4

- [X] T035 [P] [US4] Extract session ID from `session.id` hook attribute in `scripts/minimal-otel-interceptor.js`
- [X] T036 [P] [US4] Extract session ID from `conversation.id` for Codex in `scripts/codex-otel-interceptor.js`
- [X] T037 [US4] Set `langfuse.session.id` on all span types in all interceptors
- [X] T038 [US4] EXISTING - i3pm project name already in `working_directory` and `project.name` attributes
- [X] T039 [P] [US4] Add Gemini session ID handling in `scripts/gemini-otel-interceptor.js`

**Checkpoint**: Multiple traces grouped by session in Langfuse Sessions tab

---

## Phase 7: User Story 5 - View Prompt and Response Content (Priority: P2)

**Goal**: Full prompt/response content visible in Langfuse generation observations

**Independent Test**: Submit specific prompt to Claude Code, verify Langfuse displays exact input messages and output content

### Implementation for User Story 5

- [X] T040 [P] [US5] EXISTING - Content visible via `input.value` and `output.value` attributes on LLM spans
- [X] T041 [P] [US5] EXISTING - Message history captured in `llm.request.messages` attribute
- [X] T042 [US5] EXISTING - Input content in `input.value` attribute (up to 5000 chars)
- [X] T043 [US5] EXISTING - Output content in `output.value` attribute (up to 5000 chars)
- [X] T044 [US5] EXISTING - ThinkingBlock content included in output when present
- [X] T045 [US5] EXISTING - Tool results captured via tool span completion with result content

**Checkpoint**: Full conversation content visible in Langfuse generation observations

---

## Phase 8: User Story 6 - Filter and Search Traces Effectively (Priority: P3)

**Goal**: Rich, queryable metadata enables efficient trace filtering in Langfuse

**Independent Test**: Run sessions with different models/projects, use Langfuse filters to find specific traces

### Implementation for User Story 6

- [X] T046 [P] [US6] Add `gen_ai.system` attribute (anthropic, openai, google) in all interceptors
- [X] T047 [P] [US6] Add `gen_ai.request.model` attribute from API response in all interceptors
- [X] T048 [US6] Add `langfuse.trace.tags` JSON array attribute in Gemini interceptor (LANGFUSE_TAGS env var)
- [X] T049 [US6] EXISTING - Provider-specific metadata in gen_ai.* and provider.* attributes
- [X] T050 [US6] EXISTING - LANGFUSE_TAGS environment variable support in all interceptors
- [X] T051 [US6] EXISTING - LANGFUSE_SESSION_ID passed via langfuse.session.id from interceptors

**Checkpoint**: Traces filterable by provider, model, project, and session in Langfuse

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, edge case handling, and documentation

- [X] T052 [P] EXISTING - Alloy provides built-in buffering (100MB) when Langfuse unavailable
- [X] T053 [P] EXISTING - Alloy batch processor handles flush on timeout (10s default)
- [X] T054 Update `docs/AI_TRACING_GRAFANA.md` with Langfuse integration section
- [X] T055 [P] EXISTING - W3C Trace Context already propagated via traceId/spanId in all interceptors
- [X] T056 Run `sudo nixos-rebuild dry-build --flake .#hetzner` to validate NixOS configuration
- [X] T057 Verified services running: grafana-alloy, otel-ai-monitor processing events correctly
- [X] T058 Verified EWW panel active and monitoring sessions via inotify watcher

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-8)**: All depend on Foundational phase completion
  - US1 and US2 are both P1, can proceed in parallel after Phase 2
  - US3, US4, US5 are all P2, can proceed in parallel after Phase 2
  - US6 is P3, can proceed after Phase 2 but lowest priority
- **Polish (Phase 9)**: Depends on at least US1 and US2 being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories ← **MVP**
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories ← **MVP**
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Builds on US1's span hierarchy
- **User Story 4 (P2)**: Can start after Foundational (Phase 2) - Independent
- **User Story 5 (P2)**: Can start after Foundational (Phase 2) - Independent
- **User Story 6 (P3)**: Can start after Foundational (Phase 2) - Independent

### Within Each User Story

- Models/constants before implementation
- Interceptor changes can be parallelized across CLIs
- Receiver changes may depend on interceptor attributes
- Core implementation before integration

### Parallel Opportunities

- All Setup tasks can run in parallel (T002, T003 marked [P])
- All Foundational tasks marked [P] can run in parallel
- Claude/Codex/Gemini interceptor changes marked [P] can run in parallel
- US1 and US2 can run in parallel (both P1, different focus areas)
- US3, US4, US5, US6 can all run in parallel after Phase 2

---

## Parallel Example: User Story 1 + 2 (MVP)

```bash
# Phase 1 (Setup) - parallel where marked:
Task: T001 "Add Langfuse config options to modules/services/grafana-alloy.nix"
Task: T002 [P] "Add Langfuse env vars to home-modules/tools/claude-code/otel-config.nix"
Task: T003 [P] "Add 1Password secret refs in configurations/hetzner-sway.nix"
Task: T004 "Add auth header generation script in scripts/langfuse-auth.sh"

# Phase 2 (Foundational) - parallel where marked:
Task: T005 "Add Langfuse attribute constants to models.py"
Task: T006 [P] "Create Langfuse exporter in langfuse_exporter.py"
Task: T007 [P] "Add Langfuse export to Alloy config"
Task: T008 "Add span enrichment hooks in receiver.py"
Task: T009 "Verify EWW panel unaffected"

# Phase 3+4 (US1 + US2) - run in parallel after Phase 2:
# Team A: User Story 1 tasks (T010-T017)
# Team B: User Story 2 tasks (T018-T025)
```

---

## Implementation Strategy

### MVP First (User Story 1 + 2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (trace hierarchy)
4. Complete Phase 4: User Story 2 (token/cost tracking)
5. **STOP and VALIDATE**: Test both stories in Langfuse UI
6. Deploy if ready

### Incremental Delivery

1. Setup + Foundational → Langfuse export pipeline ready
2. Add User Story 1 → Traces visible in Langfuse (MVP!)
3. Add User Story 2 → Token/cost metrics visible (MVP complete!)
4. Add User Story 3 → Tool calls visible
5. Add User Story 4 → Session grouping works
6. Add User Story 5 → Full content visible
7. Add User Story 6 → Advanced filtering works
8. Each story adds value without breaking previous stories

### Single Developer Strategy

1. Complete Setup + Foundational together
2. Complete US1 (trace structure) first - this is the foundation
3. Complete US2 (tokens/costs) - most value for analysis
4. Complete US3 (tool calls) - enables debugging
5. Complete US4, US5, US6 in order or as needed

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- All JSON attributes must be valid JSON strings per contract
- Maintain backward compatibility with EWW panel throughout
