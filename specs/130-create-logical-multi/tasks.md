# Tasks: Logical Multi-Span Trace Hierarchy for Claude Code

**Input**: Design documents from `/specs/130-create-logical-multi/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/otlp-span-examples.json, quickstart.md

**Tests**: Manual verification via Grafana Tempo (no automated tests - interceptor testing requires infrastructure)

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Completion Summary

| Phase | Status | Tasks |
|-------|--------|-------|
| Phase 1: Setup | ✅ Complete | T001-T002 |
| Phase 2: Foundational | ✅ Complete | T003-T010 |
| Phase 3: US1 - Turn Visibility | ✅ Complete | T011-T019 |
| Phase 4: US2 - Tool Tracing | ✅ Complete | T020-T030 |
| Phase 5: US3 - Subagent Correlation | ✅ Complete | T031-T037 |
| Phase 6: US4 - Token Attribution | ✅ Complete | T038-T044 |
| Phase 7: Polish | ✅ Complete (55/56) | T045-T055 done, T056 pending |

**Overall**: 55/56 tasks complete (98%)
**Remaining**: T056 (remove backup after 1 week - due 2025-12-27)
**Last Validated**: 2025-12-20 - Subagent trace propagation verified

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

```text
scripts/
├── minimal-otel-interceptor.js     # PRIMARY FILE - complete replacement
└── claude-hooks/
    └── bash-history.sh             # Unaffected

home-modules/ai-assistants/
└── claude-code.nix                 # May need minor updates

modules/services/
└── grafana-alloy.nix               # May need span type updates
```

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Backup existing implementation and prepare for replacement

- [x] T001 Create backup of scripts/minimal-otel-interceptor.js to scripts/minimal-otel-interceptor.js.backup
- [x] T002 Review current interceptor structure and identify all state variables in scripts/minimal-otel-interceptor.js

---

## Phase 2: Foundational (Core State Machine)

**Purpose**: Implement the state management infrastructure required by ALL user stories

**Critical**: This phase implements the InterceptorState, SessionState, and core OTLP export functions that all spans depend on.

- [x] T003 Create new scripts/minimal-otel-interceptor.js with module header, version 3.0.0, configuration constants
- [x] T004 Implement generateId(bytes) helper function for trace/span IDs in scripts/minimal-otel-interceptor.js
- [x] T005 Implement SessionState initialization with traceId, spanId, sessionId, startTime, tokens aggregation in scripts/minimal-otel-interceptor.js
- [x] T006 Implement sendToAlloy(spanRecord) OTLP export function in scripts/minimal-otel-interceptor.js
- [x] T007 Implement createOTLPSpan(spanData) builder function per data-model.md in scripts/minimal-otel-interceptor.js
- [x] T008 Implement session root span export (CHAIN kind) with OpenInference attributes in scripts/minimal-otel-interceptor.js
- [x] T009 Implement process exit handler to finalize session span with aggregated metrics in scripts/minimal-otel-interceptor.js
- [x] T010 Wire fetch interceptor skeleton for api.anthropic.com requests in scripts/minimal-otel-interceptor.js

**Checkpoint**: Session span exports correctly on first API call and updates on process exit

---

## Phase 3: User Story 1 - Complete Turn Visibility (Priority: P1) MVP

**Goal**: Group all operations under user turns, enabling cost and time analysis per interaction

**Independent Test**: Run `claude "Read package.json"`, view trace in Tempo, confirm operations grouped under "User Turn #1" span

### Implementation for User Story 1

- [x] T011 [US1] Implement TurnState tracking with spanId, turnNumber, startTime, tokens in scripts/minimal-otel-interceptor.js
- [x] T012 [US1] Implement isNewTurn(requestBody) detection via last message role analysis per research.md in scripts/minimal-otel-interceptor.js
- [x] T013 [US1] Implement startNewTurn() function creating AGENT span under session in scripts/minimal-otel-interceptor.js
- [x] T014 [US1] Implement endCurrentTurn() function completing turn span with aggregated metrics in scripts/minimal-otel-interceptor.js
- [x] T015 [US1] Wire turn detection into fetch interceptor - start new turn when last message is user role in scripts/minimal-otel-interceptor.js
- [x] T016 [US1] Implement LLM span creation (CLIENT kind) as child of current turn with OpenTelemetry GenAI attributes in scripts/minimal-otel-interceptor.js
- [x] T017 [US1] Implement turn end detection - response without tool_use blocks triggers turn completion in scripts/minimal-otel-interceptor.js
- [x] T018 [US1] Add token aggregation from LLM spans to turn span and session span in scripts/minimal-otel-interceptor.js
- [x] T019 [US1] Add turn.number, turn.llm_call_count attributes to turn spans per data-model.md in scripts/minimal-otel-interceptor.js

**Checkpoint**: Traces show Session → Turn → LLM hierarchy with accurate token totals

---

## Phase 4: User Story 2 - Tool Execution Tracing (Priority: P1)

**Goal**: Capture individual tool executions with timing and status for performance analysis

**Independent Test**: Run `claude "Run npm --version"`, confirm trace shows "Tool: Bash" span with duration and exit status

### Implementation for User Story 2

- [x] T020 [US2] Implement PendingToolSpan tracking structure with toolCallId, toolName, spanId, startTime per data-model.md in scripts/minimal-otel-interceptor.js
- [x] T021 [US2] Implement extractToolUseBlocks(responseContent) to parse tool_use blocks from API response in scripts/minimal-otel-interceptor.js
- [x] T022 [US2] Implement createToolSpan(toolUse) creating INTERNAL/TOOL span under current turn in scripts/minimal-otel-interceptor.js
- [x] T023 [US2] Add pendingTools Map to track active tool spans awaiting results in scripts/minimal-otel-interceptor.js
- [x] T024 [US2] Implement extractToolResults(requestMessages) to parse tool_result blocks from next request in scripts/minimal-otel-interceptor.js
- [x] T025 [US2] Implement completeToolSpan(toolResult) matching result to pending span, setting end time and status in scripts/minimal-otel-interceptor.js
- [x] T026 [US2] Wire tool span creation on response with tool_use blocks in scripts/minimal-otel-interceptor.js
- [x] T027 [US2] Wire tool span completion on request with tool_result blocks in scripts/minimal-otel-interceptor.js
- [x] T028 [US2] Add tool.status, tool.error_message attributes for failed tools per data-model.md in scripts/minimal-otel-interceptor.js
- [x] T029 [US2] Implement orphan tool cleanup on turn end - mark incomplete tools as error in scripts/minimal-otel-interceptor.js
- [x] T030 [US2] Add turn.tool_call_count attribute to turn spans in scripts/minimal-otel-interceptor.js

**Checkpoint**: Traces show Session → Turn → LLM + Tool spans with accurate timing and status

---

## Phase 5: User Story 3 - Subagent Correlation (Priority: P2)

**Goal**: Link parent and subagent traces for Task tool invocations

**Independent Test**: Run `claude "Use the Task tool to research the codebase"`, confirm both traces are linked via span links in Tempo

### Implementation for User Story 3

- [x] T031 [US3] Implement isTaskTool(toolName) detection for Task tool invocations in scripts/minimal-otel-interceptor.js
- [x] T032 [US3] Implement setTraceParentEnv(traceId, spanId) to set OTEL_TRACE_PARENT env var per research.md in scripts/minimal-otel-interceptor.js
- [x] T033 [US3] Wire Task tool detection to set environment variable before subagent spawns in scripts/minimal-otel-interceptor.js
- [x] T034 [US3] Implement parseTraceParentEnv() to read OTEL_TRACE_PARENT on interceptor startup in scripts/minimal-otel-interceptor.js
- [x] T035 [US3] Implement span link creation on session root when OTEL_TRACE_PARENT present per contracts/otlp-span-examples.json in scripts/minimal-otel-interceptor.js
- [x] T036 [US3] Add subagent.type attribute to linked session spans in scripts/minimal-otel-interceptor.js
- [x] T037 [US3] Add link.type: parent_task attribute to span links per contracts/otlp-span-examples.json in scripts/minimal-otel-interceptor.js

**Checkpoint**: Parent and subagent traces are linked and discoverable in Tempo

---

## Phase 6: User Story 4 - Token Cost Attribution (Priority: P2)

**Goal**: Aggregate token usage at turn and session level for cost analysis

**Independent Test**: Complete multi-turn session, verify session span token totals match sum of all LLM spans

### Implementation for User Story 4

- [x] T038 [US4] Implement TokenCounts structure with input, output, cacheRead, cacheWrite per data-model.md in scripts/minimal-otel-interceptor.js
- [x] T039 [US4] Implement extractTokenUsage(response) parsing Anthropic usage object in scripts/minimal-otel-interceptor.js
- [x] T040 [US4] Wire token extraction on every LLM response in scripts/minimal-otel-interceptor.js
- [x] T041 [US4] Implement turn-level token aggregation in endCurrentTurn() in scripts/minimal-otel-interceptor.js
- [x] T042 [US4] Implement session-level token aggregation on turn completion in scripts/minimal-otel-interceptor.js
- [x] T043 [US4] Add gen_ai.usage.input_tokens, gen_ai.usage.output_tokens to turn and session spans in scripts/minimal-otel-interceptor.js
- [x] T044 [US4] Add cache token attributes (cache_read, cache_creation) to LLM spans in scripts/minimal-otel-interceptor.js

**Checkpoint**: Token totals aggregate correctly from LLM → Turn → Session

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Validation, cleanup, and edge case handling

- [x] T045 [P] Update scope.version to 3.0.0 in all span exports in scripts/minimal-otel-interceptor.js
- [x] T046 [P] Add gen_ai.conversation.id attribute (SESSION_ID) to all span types for cross-trace correlation in scripts/minimal-otel-interceptor.js
- [x] T047 Verify all attribute names match OpenTelemetry GenAI semantic conventions per research.md in scripts/minimal-otel-interceptor.js
- [x] T048 Add error handling for malformed API responses in scripts/minimal-otel-interceptor.js
- [x] T049 Add console.error logging for interceptor version and session info on startup in scripts/minimal-otel-interceptor.js
- [x] T050 Run test scenario 1 from quickstart.md: Simple Q&A (no tools) and verify trace structure
- [x] T051 Run test scenario 2 from quickstart.md: Tool use and verify tool span appears
- [x] T052 Run test scenario 3 from quickstart.md: Multi-turn conversation and verify separate turn spans
- [x] T053 Run test scenario 4 from quickstart.md: Subagent (Task tool) and verify span links
  - **Status**: ✅ Verified 2025-12-20
  - **Test**: Spawned subagent via Task tool, verified trace context inheritance
  - **Results**:
    - Parent trace ID: `b3540f524bb42d1b86bc0d8eda61ece4`
    - Subagent inherited same trace ID: ✅ YES
    - W3C traceparent format valid: ✅ YES
    - Parent-child span relationship: ✅ ESTABLISHED
  - **Mechanism**: Hooks-based propagation (SessionStart + PreToolUse)
    1. SessionStart creates `.claude-trace-context.json` + sets OTEL_* env vars
    2. PreToolUse propagates context before Task tool spawn
    3. Subagent SessionStart reads inherited context
- [x] T054 Verify token aggregation accuracy: session tokens = sum of turn tokens = sum of LLM tokens
- [x] T055 NixOS rebuild and verify interceptor loads via NODE_OPTIONS
- [ ] T056 Remove backup file scripts/minimal-otel-interceptor.js.backup after 1 week stable operation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - backup existing implementation
- **Foundational (Phase 2)**: Depends on Setup - creates core state machine
- **User Stories (Phases 3-6)**: All depend on Foundational completion
  - US1 (Turn Visibility) must complete before US2 (Tool Tracing) - tools are children of turns
  - US3 (Subagent) and US4 (Token) can run in parallel after US2
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

```
Phase 1: Setup
    ↓
Phase 2: Foundational (Core State Machine) ← BLOCKS ALL STORIES
    ↓
Phase 3: US1 - Turn Visibility (P1 MVP) ← BLOCKS US2
    ↓
Phase 4: US2 - Tool Tracing (P1)
    ↓
    ├── Phase 5: US3 - Subagent Correlation (P2)
    └── Phase 6: US4 - Token Attribution (P2)
              ↓
         Phase 7: Polish
```

### Within Each Phase

- Tasks without [P] marker must be completed sequentially
- Tasks with [P] marker can run in parallel if in same phase
- Complete all tasks in a phase before moving to next

### Critical Path

T001 → T003-T010 → T011-T019 → T020-T030 → (T031-T037 || T038-T044) → T045-T056

---

## Parallel Execution Examples

### Foundational Phase (T003-T010)

```text
# Sequential - each builds on previous
T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010
```

### User Story 3 & 4 (After US2 Complete)

```text
# Can run in parallel - independent concerns
Agent A: T031 → T032 → T033 → T034 → T035 → T036 → T037
Agent B: T038 → T039 → T040 → T041 → T042 → T043 → T044
```

### Polish Phase

```text
# T045-T046 can run in parallel
T045 || T046
# Then sequential validation
→ T047 → T048 → T049 → T050-T054 → T055 → T056
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational (T003-T010)
3. Complete Phase 3: US1 - Turn Visibility (T011-T019)
4. **STOP and VALIDATE**: Test with simple multi-turn session
5. Traces should show Session → Turn → LLM hierarchy

### Incremental Delivery

1. **MVP**: Setup + Foundational + US1 → Session/Turn/LLM spans working
2. **+Tools**: Add US2 → Tool spans appear under turns
3. **+Subagents**: Add US3 → Span links connect traces
4. **+Tokens**: Add US4 → Cost attribution complete
5. **Polish**: Validation and cleanup

### Single Developer Path

Follow phases sequentially:
```
Setup → Foundational → US1 → US2 → US3 → US4 → Polish
```

---

## Notes

- All tasks modify the same file: `scripts/minimal-otel-interceptor.js`
- This is a complete replacement, not incremental modification
- Test scenarios in `quickstart.md` provide verification steps
- `contracts/otlp-span-examples.json` provides exact span structure templates
- `data-model.md` provides TypeScript interfaces for state management
- `research.md` provides rationale for technical decisions
