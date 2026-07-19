# Goal Loop, Session Pulse, and the Usage-Event Convention

Scope: the autonomous session goal loop (Codex `/goal` parity — wfb PRs #84/#87/#88), the Session Pulse vitals strip, and the system-wide `agent.llm_usage` net-of-cache accounting convention they both depend on. Use this when setting/managing a goal on a live session, when a goal stops continuing or burns its budget instantly, when Pulse cost/context numbers look wrong for a provider, or when running the goal eval scenarios.

## Mental model

A **goal** is a persistent objective attached to one session (`thread_goals` table, migration `drizzle/0079_thread_goals.sql`; one ACTIVE goal per session enforced by the partial unique index `uq_thread_goals_session_active`). The BFF driver is `src/lib/server/goals/goal-loop.ts`, prompt rendering is in `render.ts`, and persistence stays behind the goal-loop application port with physical adapter `src/lib/server/application/adapters/goal-loop-store.ts`. It re-injects the objective every time the agent finishes a turn, until the agent calls `update_goal` with `status: "complete"` after a completion audit, or a guardrail stops it. Statuses: `active | paused | budget_limited | complete`. Setting a new objective **replaces** any existing `active` OR `budget_limited` row — the `goalId` rotates and usage accounting resets (this is also the re-arm path after a budget stop).

## The driver (event-driven, exactly-once)

The loop is driven off session-event append side effects in `src/lib/server/application/adapters/session-events.ts` — no poller or CronJob:

- **`agent.llm_usage`** → accrues token usage against the goal's budget (`accrueUsage` in `repo.ts`, which also flips `active → budget_limited` SQL-side when the budget is crossed).
- **`session.status_idle{reason: end_turn}`** → renders the next continuation (verbatim Codex templates in `src/lib/server/goals/templates/{continuation,budget_limit}.md`, Mustache-style `{{ objective }}`/budget fields, objective wrapped in `<untrusted_objective>` tags) and injects it as a **visible `user.message`** with `origin=goal-continuation` and deterministic `sourceEventId = goal-continuation:<sessionId>:<iteration>`.

Exactly-once = three layers: an **atomic iteration claim** (`claimNextContinuation` — SQL `UPDATE … RETURNING` on the goal row), the **idle gate** (only fires on `end_turn` idles), and **`sourceEventId` dedup** on the event append. Don't hand-post continuations — a manual `user.message` bypasses the claim and double-drives the turn.

Terminal sessions halt the driver; an interrupt-mode Stop (Lifecycle Controller) **pauses** the goal rather than abandoning it.

## Completion contract (MCP tools, auto-wired)

`services/workflow-mcp-server/src/goal-tools.ts` exposes `create_goal` / `update_goal` / `get_goal`. Session scoping is **never a tool argument**. Platform spawn stamps both `X-Wfb-Session-Id` and a signed, session-bound `X-Wfb-Session-Token` on the Workflow MCP server entry; the BFF verifies session ownership/workspace membership before issuing the short-lived principal assertion used internally. A raw session ID is context, not authentication. `update_goal` accepts only the statuses declared by the current tool contract; completion must follow an evidence-backed audit, while pause/resume/budget transitions remain user/system-controlled.

`spawn.ts` **auto-wires** the goal MCP server into MCP-capable non-CLI sessions (`ensureGoalMcpServer`; skipped when the runtime lacks MCP, an entry already matches, or `GOAL_MCP_AUTO_WIRE=false`; URL override `GOAL_MCP_SERVER_URL`). The deployed `workflow-mcp-server` listens on port 3200 and hosts goal tools alongside workflow tools. Its Deployment receives only explicit `DATABASE_URL` and `INTERNAL_API_TOKEN` secret keys. Keep the BFF's JWT/Workflow MCP signing key out of this pod: the MCP service consumes opaque assertions and must not mint them.

`spawnSessionWorkflow` returns early when the session is already running. A
spawn retry therefore does **not** refresh that session's Workflow MCP token or
bootstrap configuration. After a staged signing/auth/bootstrap rollout, start
a fresh session and validate the new credential there.

External API-key clients follow a different lane: workflow save/run operations are owned by the authenticated workspace and need no session. They may attach a verified same-user/same-workspace `X-Wfb-Session-Id` for goal, trace, or lineage context. See `workflow-mcp-server.md`.

## Budget accounting (codex semantics — net of cache reads)

Per `agent.llm_usage` event, the budget delta is:

```
delta = input_tokens + output_tokens + cache_creation_input_tokens   # cache READS excluded
```

(`goal-loop.ts` ~L59-74.) This matches Codex: cached-read tokens are not "work". The original implementation counted cache reads and over-burned budgets ~20× on cached loops (fixed PR #87). This only works because of the **usage-event convention** below — if an adapter emits gross input, budgets over-burn again.

## Guardrails

| Guardrail | Mechanism |
|---|---|
| `tokenBudget` crossed | Goal flips `active → budget_limited`; exactly ONE wrap-up turn is granted, claimed atomically via `budget_steered_at` (renders `budget_limit.md` — "do not start new substantive work") |
| `maxIterations` reached | Hard cap: `budget_limited` with `stop_reason=iteration_cap`, same one-time wrap-up claim (ours — Codex has no iteration cap) |
| Interrupt stop | Pauses the goal (resume via UI/PATCH) |
| Session terminal | Driver halts |

Re-arm: POST a new goal — replace covers `budget_limited` rows too, rotating `goalId` and resetting accounting.

## Delivery and recovery

The inline session-event hook is the active driver and is fire-and-forget. The old
`goal-loop-tick` CronJob, `POST /api/internal/goal-loop/tick`, and timer-driven
lost-idle probe were retired. Goal creation and the stop-hook paths call the same
idempotent `kickGoalLoop` driver, while the DB iteration claim, idle gate, and
deterministic `sourceEventId` provide exactly-once posting. Do not look for a
timer reaper when diagnosing a stalled goal; inspect the session event append,
goal row, and explicit kick path.

## API + UI

- `GET/POST/PATCH /api/v1/sessions/[id]/goal` (`src/routes/api/v1/sessions/[id]/goal/+server.ts`). POST sets/replaces (objective + optional `tokenBudget`/`maxIterations`); PATCH accepts only `status: "complete" | "paused"`.
- UI: interactive **Goal card** on session detail (`src/lib/components/sessions/session-goal-badge.svelte`) — Set goal dialog; Pause / Mark complete on active; Resume / adjust + Mark complete on paused; New goal on complete/budget_limited. Also a Goal tile in Session Pulse.

## Codex parity divergences (deliberate, documented)

- Continuation is a **visible `user.message`** (Codex: hidden developer role).
- Our wrap-up runs as one extra **autonomous turn** (Codex: steering injected mid-turn; no continuations after BudgetLimited).
- The `update_goal` call itself **is** accounted (Codex excludes it).
- Wall-clock = `now - createdAt` (Codex: active-time deltas).
- No plan-mode/feature-flag gates; no accounting-preserving unpause (re-set resets counters).
- Ours adds `maxIterations` plus DB claim/dedup safeguards; there is no timer-driven lost-idle backstop.

## Session Pulse (vitals strip)

`src/lib/components/sessions/session-pulse.svelte` (PRs #85/#86), mounted on session detail. Tiles + data sources:

| Tile | Source |
|---|---|
| **Tokens** (in/out split) | Rollup of `agent.llm_usage` flat fields |
| **Cache-hit %** ring | `cache_read_input_tokens` vs prompt tokens from `agent.llm_usage` |
| **Cost** (live $, "saved $X via cache") | `GET /api/v1/pricing?model=` backed by `MODEL_PRICING` (`src/lib/server/pricing/model-pricing.ts`) |
| **Context %** | Provider-truth: latest `context_*` fields on `agent.llm_usage` (`context_count_method=provider_usage`) preferred over the pre-call `local_advisory` heuristic on `agent.context_usage` — the heuristic undercounts 20-25% |
| **Elapsed** | Live tick from `createdAt` |
| **Turns + LLM calls** | Event counts |
| **Goal loop** | `GET …/goal` poll (5s) |

**Context % includes cached tokens** (window occupancy = input + cache_read + cache_creation) — this matches Claude Code's `calculateContextPercentages` exactly. Budget accounting deliberately differs (work metric, net of cache). The `context_*` stamp is added post-ingest by dapr-agent-py's `event_publisher.py` with `context_source/context_count_method = provider_usage`.

## Usage-event convention (SYSTEM INVARIANT)

**All dapr-agent-py adapters emit `agent.llm_usage` with `input_tokens` NET of cache reads** — `input_tokens` and `cache_read_input_tokens` are disjoint, never subset. OpenAI and Alibaba providers report gross (cache-inclusive) prompt tokens; their adapters normalize with `max(0, gross - cache_read)` (+ `prompt_tokens_details` fallback) — fixed in PR #90 (`services/dapr-agent-py/src/{openai_adapter,alibaba_adapter}.py`). Goal budgets, Pulse cost, and the post-ingest `context_*` stamp all depend on this convention.

**Triage when budgets/cost/context look wrong for a provider**: inspect raw `agent.llm_usage` events for that provider and check whether `input_tokens` ≥ `cache_read_input_tokens` on heavily-cached calls — subset/gross semantics (input including cache reads) means a non-normalized adapter. Smoking-gun scale from the eval that caught it: 242 net tokens booked as 17,906 per call on OpenAI gpt-5.5.

## Goal eval scenarios (reusable regression harness)

Run by setting a goal on a live session — the dev agent `goal-eval-deepseek` (`P-1UUm25pvbzh3da4TXJD`) exists for these:

1. **itsdangerous TDD** — objective: clone `pallets/itsdangerous`, establish a green full-suite baseline, write `PLAN.md` with `file:line` references, add 4 new tests, finish with a full-suite completion audit. Exercises multi-iteration continuation + budget accrual end-to-end (this scenario on OpenAI gpt-5.5 caught the gross-input accounting bug).
2. **red-green TDD on `pytest-dev/iniconfig`** — objective REQUIRES a failing stage at step 2 (tests written and shown failing before implementation). Proves the completion audit rejects false completion — the goal cannot be marked complete by skipping the red phase.
