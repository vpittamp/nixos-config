---
name: workflow-builder
description: "Author, save, run, visualize, and debug dynamic-script workflows for workflow-builder, while supporting frozen legacy SW 1.0 runs. Use for Workflow MCP workspace authentication and session context, Kimi K3 defaults and structured output, script agent/action/workflow primitives, goal loops, Prompt Workbench, agent MCP connections, failed runs, Dapr sidecars, runtime routing, and sandbox troubleshooting."
---

# Workflow Builder

Author new workflows with the code-first `dynamic-script` engine, save and run
them through Workflow MCP, and diagnose their runtime behavior. SW 1.0 remains
a frozen legacy execution/view format; use its references only to inspect,
operate, or migrate an existing definition.

## Mental model in one paragraph

A user workflow is a saved `{engine:"dynamic-script", script, meta, defaults?}`
definition executed by the single durable `dynamic_script_workflow_v1` pump.
The zero-secret evaluator plans deterministic `agent()`, `action()`, `sleep()`,
`approve()`/`waitForEvent()`, and `workflow()` calls; a content-addressed journal
preserves replay, skip, and resume-after-edit. Agent calls resolve through the
runtime registry and launch per-session Kueue-admitted Sandbox pods; browser
runtime uses a warm pool. There is no `AgentRuntime` CR/controller. Saved agent
MCP connections are resolved at launch with two-level `allowedTools` narrowing,
and OAuth credentials remain reference-forwarded. Legacy SW 1.0 definitions
still run through `sw_workflow_v1`, but new authoring must target dynamic script.

## When to use this skill

Trigger on any of: "build a workflow", "author a workflow", "add an agent step", "add a trigger", "make this run on a webhook", "the run failed", "the agent never starts", "the canvas is empty", "${ .trigger.x } isn't resolving", "what slugs are available", "why isn't my sandbox persisting", "why is daprd crashing", "where does my workflow run", "set a goal on this session", "the goal loop stopped continuing", "the goal budget burned instantly", "Session Pulse cost/context looks wrong".

**Not this skill — use `dapr-agents-workflow` instead** when writing upstream
`dapr/dapr-agents` Python directly. This skill is the workflow-builder product:
scripts are saved as data and executed by the registered pump, while agent
runtimes remain registry-selected opaque targets.

## Quick decision tree

| The user wants to… | Do this |
| --- | --- |
| Add an HTTP or deterministic integration call | Use `await action(slug, input, opts)` in a dynamic script and discover the slug through the action catalog. |
| Add an agent step | Use `await agent(prompt, opts)`. Use `opts.agent` for a saved persona slug, `opts.model` for a model key, and `opts.schema` for structured output. |
| Author a workflow (default path) | Use `get_workflow_context` -> `get_workflow_script_spec` -> `validate_workflow_script` -> `save_workflow_script` -> `run_workflow_script`. Read repo `docs/dynamic-script-authoring-guide.md` and `docs/code-first-cutover.md`. Recursion/team capabilities are signed platform claims, never caller-supplied headers. |
| Inspect or migrate an existing SW 1.0 workflow | Treat it as frozen legacy. Read `references/sw-1.0-spec.md`, `references/agent-task.md`, and `references/canvas-shape.md`; do not use those formats for a new workflow. |
| Edit an agent persona or manage prompt presets | Use the agent detail Prompt Workbench. Read `references/prompt-workbench.md`; presets write into unsaved agent config until the normal save/publish flow runs. |
| Debug a workflow agent-node compiled prompt preview | Read `references/prompt-workbench.md` and `references/agent-task.md`. The preview shows the canonical Dapr shape: system message, `chat_history`, appended node prompt. |
| Return workflow output | Return a JSON-serializable value from the script. Use schema-constrained agent calls when downstream code needs a stable object. |
| Take user input at run time | Declare `meta.input` JSON Schema and read the validated, defaulted value from `args`. |
| Share a workspace across agent calls | Create/bind the platform workspace through the documented `action('workspace/profile', ...)` plus script sandbox binding; read `docs/code-first-cutover.md`. |
| Save or run workflows through the external Workflow MCP server, or decide what `sessionId` means | Read `references/workflow-mcp-server.md`. Call `get_workflow_context` first. Workflow definition operations use the authenticated workspace and take no `sessionId`; a Workflow Builder session is optional goal/trace lineage only. |
| Attach or debug MCP tools used by a spawned agent | Read `references/mcp-connections.md`. This is distinct from the external Workflow MCP authoring server. |
| Discover action slugs | Call `GET /api/action-catalog` (see `references/action-catalog.md`) and invoke the result with script `action()`; do not guess. |
| Save a workflow | Prefer Workflow MCP `save_workflow_script`, which upserts by name in the authenticated workspace. The BFF JSON helper is a secondary access-JWT/cookie path, not a `wfb_` MCP-key path. |
| Diagnose a failed run | Read `references/troubleshooting.md` and triage by symptom (parse error / agent timeout / replay chatter / prompt-too-long / project_id NULL). |
| Stop / terminate / purge a running session or workflow run (or wonder why "Stop" did nothing) | Route through the vetted **Lifecycle Controller** — `POST /api/v1/sessions/[id]/stop` or `POST /api/workflows/executions/[id]/stop` with `{mode: interrupt\|terminate\|purge\|reset}`. Read `references/troubleshooting.md` § *Stopping a run (Lifecycle Controller)* + the SSOT `docs/workflow-lifecycle-termination.md`. |
| Set a persistent objective on a live session (autonomous goal loop), manage/pause/re-arm it, or debug a goal that stopped continuing | UI Goal card on session detail, `GET/POST/PATCH /api/v1/sessions/[id]/goal`, or have the agent use the auto-wired goal MCP tools. Read `references/goal-loop.md`. |
| Session token/cost/context numbers look wrong, or a goal budget burns far too fast on one provider | Read `references/goal-loop.md` § *Usage-event convention* — check `agent.llm_usage` `input_tokens` vs `cache_read_input_tokens` for gross/subset semantics. |
| Debug `1/2` pods or `daprd` not ready | Read `references/cluster-topology.md` for the runtime model, then use the gitops runbook `runbooks/debug-dapr-sidecar-stale-readiness.md` for live Kubernetes triage. |
| Run official SWE-bench or Benchmarks UI work | Use the evaluations skill; those paths are intentionally outside normal SW 1.0 workflow authoring. |
| Confirm a freshly saved workflow shows up + runs | Read `references/verify-in-ui.md`. |
| Understand "where does my workflow actually run?" | Read `references/cluster-topology.md`. |
| Prove a Claude/SWE-bench run used the right runtime | Read `references/troubleshooting.md` and the evaluations skill. Trust `benchmark_runs.agent_runtime`, `agent_runtime_app_id`, workflow output `agentRuntime`, `agentWorkflowMode`, trace IDs, and `outputSync` before container labels. |
| Watch a build/promotion/sync land on dev, or debug the GitOps pipeline view | Open dev `/admin/gitops/system` (hub **Argo Events** -> `gitops_activity_events` -> SSE). The header `build <sha>` badge is the running dev image. See the `gitops` skill. Do not deploy, sync, or test Ryzen unless the user explicitly requests Ryzen. |
| See an image's build status + the Commit→Build→Pin→Promote→Deploy chain | Same view: stage cards carry a **build chip** (Built/Building/Failed + duration + Tekton deep-link) and the node drawer has a **Delivery timeline** (inter-step gaps + durations + a `commit→live` lead-time, lane-aware Promote). This is **inventory-sourced** (the hub inventory's per-app `build`/`promotion`/`live` + `imageHistory`), NOT the Argo-Events stream — see the `gitops` skill § *Event-driven activity stream → Build feedback + delivery timeline*. |
| Get notified when a deploy goes live (any page) | App-wide **deployment notifications** (admin-gated): a toast + a sidebar **notification bell** fire when a component's LIVE image tag changes on a cluster. INVENTORY-diff (tag-SET diff of `live.images`), not the event stream; store at `src/lib/stores/deployment-notifications.svelte.ts`, started in the root layout. See the `gitops` skill § *Event-driven activity stream → App-wide deployment notifications*. |

## Critical gotchas (memorize these — they cost the most time)

These are the failure modes that look like obscure bugs but are actually doing-it-wrong. Each entry has the *why* so you can judge edge cases instead of robotically applying the rule.

- **jq is full-string-only.** `is_expression_string` (in `services/workflow-orchestrator/core/sw_expressions.py`) only evaluates a value if the *entire* string starts with `${` and ends with `}`. So `"${ .trigger.url }"` evaluates; `"prefix ${ .trigger.url }"` passes through as literal text. To interpolate, concat inside one expression: `"${ \"prefix \" + .trigger.url }"`.

- **Trigger context is `.trigger`, not `.input`.** `tc.task_outputs["trigger"] = {label, actionType, data: trigger_data}` — the orchestrator's expression context exposes the unwrapped data under `${ .trigger.<field> }` (see `services/workflow-orchestrator/workflows/sw_workflow.py`, `tc.task_outputs["trigger"]["data"] = tc.trigger_data`). `${ .input }` resolves to a different thing (per-task input).

- **Inside an `artifacts:` block, `${ .data.X }` is the just-completed task's payload, not a cross-task ref.** `_persist_task_artifacts` builds a per-task context that strips two envelopes (`{label,actionType,data}` storage wrapper + `{success,data,error}` call wrapper) to reach the payload, and exposes it uniformly so the same idiom works for crawl-style nested payloads (`.data.markdown`) and agent-style flat ones (`.data.content` — the orchestrator wraps the flat payload as `{data: payload}` so the canonical idiom holds). For cross-task refs use the full task name: `${ .fetch_each.data.tier }`. See `references/workflow-artifacts.md` § *post-task expression context*.

- **Trigger schema has TWO equivalent placements.** Either top-level `spec.input.schema.document` (canonical, preferred) OR `spec.document['x-workflow-builder'].input.schema` (alternate). The spec→graph adapter normalizes both into the start node's `data.taskConfig.input` (see `src/lib/utils/spec-graph-adapter.ts:79-94`). Pick one and stick with it; when in doubt use the canonical placement.

- **Node IDs equal task names.** The key in each `do[]` entry IS the node ID in the canvas. `__start__` and `__end__` are the synthetic entry/exit nodes. The adapter uses `@serverlessworkflow/sdk::buildGraph()` so 99% of the time you should let the spec drive node generation rather than hand-author `nodes`/`edges`.

- **`durable/run` is a Dapr child workflow, not an HTTP call.** It bypasses function-router. The orchestrator yields `ctx.call_child_workflow("session_workflow", app_id="<runtime-app-id>")` (the dispatched workflow literal is `session_workflow` per `runtime-registry.json` `dispatchWorkflowName`; the distinct sentinel `agent_workflow` is only the bridge-eligibility token). The runtime is resolved by `_resolve_native_agent_runtime` in `sw_workflow.py`, now a thin shim over `core/runtime_registry.resolve()`. The runtime app id comes from `with.agentRef.id` → DB `agents.runtime_app_id` (SWE-bench pool agents use `agent-runtime-pool-coding`). Missing `agentRef`/`agentSlug` falls back to the registry's `defaultRuntimeId` (`dapr-agent-py`). The target pod must be in the same namespace (`workflow-builder`) — Dapr workflow sub-orchestration doesn't cross namespaces.

- **Claude Agent SDK is a peer runtime, not a sandbox template.** `services/claude-agent-py` runs the Claude SDK path and should report `agentRuntime=claude-agent-py` / `agentWorkflowMode=claude-agent-sdk` in workflow outputs. It is Anthropic-only, runs the whole agent loop in one Dapr activity (`durabilityGranularity: per-turn`, vs `dapr-agent-py`'s per-activity), owns its own sandbox, and **now supports MCP** — `agentConfig.mcpServers` is wired into the SDK (capabilities declared in `runtime-registry.json`). It is not proved or disproved by seeing `sandboxTemplate: "dapr-agent"`; that template names the OpenShell workspace image used by `workspace/profile`. For SWE-bench there are two sandboxes: the repo testbed environment (for example `swebench-inference-astropy-1.3`) and the agent-host/runtime sandbox. The old-looking `dapr-agent` or `dapr-agent-py` container label can be a static/legacy label; use DB fields, workflow output, traces, and image/env pins as truth.

- **Kimi K3 is the dapr-agent-py and dynamic-script default.** Use model key `kimi/kimi-k3`, Dapr component `llm-kimi-k3`, and `KIMI_API_KEY`. The model selector declares a 1,048,576-token context window and `reasoningEffort: "max"`; the native adapter also rejects any `KIMI_REASONING_EFFORT` other than `max`. `DYNAMIC_SCRIPT_DEFAULT_MODEL` and `DYNAMIC_SCRIPT_STRUCTURED_MODEL` both default to `kimi/kimi-k3`. Older GLM/Kimi variants are legacy. Anthropic and OpenAI remain explicit alternatives (`anthropic/claude-opus-4-8`, `openai/gpt-5.5`) rather than the dapr-agent-py default.

- **Kimi vision requires actual image parts.** Preserve structured multimodal content and pass supported `image_url` objects or base64 `data:image/...` URLs. Never stringify a multimodal content array: screenshot metadata without pixel bytes is not vision input. Browser DOM/MCP actions provide interaction and retrieval; they do not replace the screenshot bytes K3 needs. Keep `browser-use-agent`/BrowserStation/Playwright for browser control and capture, and use K3 for visual reasoning over the captured pixels.

- **Stopping a run goes through ONE vetted Lifecycle Controller — don't hand-roll terminate/purge.** `stopDurableRun(target, {mode})` (`src/lib/server/lifecycle/{index,cascade,resolvers}.ts`) is the single server-side entry point for stopping any durable run (`target.kind ∈ workflowExecution | session | evalRun`). Modes: `interrupt` (cooperative halt of the current turn, keeps the run — no purge/reap/DB-flip), `terminate` (hard-stop the durable tree, no purge), `purge` (terminate → confirm terminal → recursive Dapr purge + reap the Sandbox CR + flip DB rows terminal), `reset` (purge + force-delete state rows even if Dapr never confirmed terminal — the user-reachable "Stop & reset" byte-clean mode, scope-guarded). Cooperative-first: terminate/purge/reset give a short grace (`LIFECYCLE_TERMINATE_GRACE_SECONDS`, default 5s) so the agent's cancel-key can halt at the next turn/tool boundary before forcing. Every user "stop" routes through it: `POST /api/v1/sessions/[id]/stop` and `POST /api/workflows/executions/[id]/stop` (body `{mode, reason?, graceMs?}`), session `control/interrupt`, eval/benchmark run cancel. Generalized from — and shared with — the benchmark cancellation cascade. UI: **Stop** / **Stop & Reset** on session-detail + workflow-run pages.

- **Stop is request/confirm (202 "stopping"), NOT a one-shot fail-closed 409.** A stop persists a `stop_requested_at` intent (migration 0071) and returns **HTTP 202 "stopping"** while the durable tree converges; it **only flips DB / reaps once Dapr is confirmed terminal** — finalized by the idempotent `GET …/stop/status` poll or a later explicit control-plane action. The retired terminal-reaper CronJob is not a backstop. **200** = confirmed, **202** = stopping, **409** ONLY on a genuine non-request failure or `coordinator_owned`. The UI shows "Stopping…" and polls to convergence; if the tab closes, the intent remains until a later status read/control action confirms it.

- **The cross-app `durable/run` Stop WEDGE is solved BFF-side — `call_child_workflow` was KEPT.** A `durable/run` step dispatches its agent child via `ctx.call_child_workflow("session_workflow", app_id=<per-session agent app-id>)` — a sub-orchestration on a SEPARATE per-session Dapr task hub, which Dapr's task-hub-bounded recursive terminate can't reach, so on Stop the cascade terminates the child agent fine but the PARENT hangs `RUNNING` (the "wedge"). Fix (#77, hardened #78/#79): the BFF `confirmDurableStop` **force-finalizes** the wedged parent — force-delete its durable state rows (the `reset` mechanism) + flip DB — treating it as DB-state cleanup since the agent is already stopped. It fires only on **positive evidence**: after a grace (`LIFECYCLE_WEDGE_FINALIZE_GRACE_SECONDS`, default 180s) the parent's live `currentNodeId` is a `durable/run` node whose child **session is DB-terminated** (not a booting-sandbox 404, not a later non-agent node). **Rejected alternative:** replacing `call_child_workflow` with fire-and-forget + status-poll dispatch was tried (#74/#75) and **reverted (#76)** — per-session Kueue sandboxes aren't Dapr-service-invokable (no `<appid>-dapr` service; `call_child_workflow` routes via PLACEMENT not DNS), a start-ready cap broke SWE-bench, and the agent's first turn didn't fire under `StartInstance` → "Inference stalled". `call_child_workflow` is the proven dispatch; don't re-attempt fire-and-poll.

- **Single stop authority — a benchmark/eval INSTANCE is not stoppable on its own.** A coordinator-driven benchmark/eval instance (a `workflow_executions` row or its agent session) 409s `coordinator_owned` on the generic per-execution/per-session Stop (both routes check `ownsBenchmarkOrEvalRun`); cancel the owning **run** instead (`POST /api/benchmarks/runs/[id]/cancel` / `…/evaluations/runs/[id]/cancel`, which cascade through `stopDurableRun(purge)`). The UI hides the generic Stop and links to the run's Cancel.

- **Delete/Archive is BLOCKED while a run is active** — they 409 with "Stop the run first" (the controller's `inspectDurableRun` reports the run still active). The sessions-list "Archive" row action was relabeled **Delete** (it always hard-DELETEd). Stop the run (terminate/purge) before deleting.

- **Dapr workflow termination is still asynchronous under the hood** — `terminate` means "request shutdown", not proof of terminal. The controller handles the poll-to-terminal + per-session app-id fan-out for you (the native Dapr recursive cascade only reaches same-task-hub children; per-session `session_workflow` children run under per-session sandbox app-ids, so the controller fans out terminate/purge **explicitly per app-id**). The orchestrator's old `terminate_durable_runs_by_parent_execution` activity was **RETIRED** (it only ever fanned out to the legacy `claude-code-agent` app-id). Don't add bespoke terminate-then-DB-flip code paths; call the controller.

- **Both runtimes now stop mid-turn.** `dapr-agent-py`'s cooperative cancel-key write/read AGREE for `durable/run` (the read strips `__turn__N`/`:turn-N` from candidate keys), so a mid-turn `user.interrupt`/`session.terminate` actually halts (previously a silent no-op for workflow-driven sessions). `claude-agent-py` reached management PARITY: `POST /api/v2/agent-runs/{id}/{terminate,pause,resume}` + DELETE purge (via `DaprWorkflowClient`), cancellation persistence, a between-turn cooperative-cancel check, and `TERMINAL_CONTROL_EVENT_TYPES`.

- **`agent.llm_usage` `input_tokens` is NET of cache reads — a SYSTEM INVARIANT.** Every dapr-agent-py adapter emits `input_tokens` disjoint from `cache_read_input_tokens` (OpenAI + Alibaba report gross and are normalized with `max(0, gross - cache_read)`, wfb PR #90). Goal budgets (`delta = input + output + cache_creation`, cache READS excluded — codex semantics), Session Pulse cost, and the post-ingest `context_*` stamp all depend on it. A provider whose budgets/cost burn ~20× too fast on cached loops = a non-normalized adapter; check raw `agent.llm_usage` for subset semantics. See `references/goal-loop.md`.

- **Goal continuations are exactly-once and driver-owned — don't hand-post them.** The goal loop injects each continuation as a visible `user.message` with `origin=goal-continuation` and deterministic `sourceEventId goal-continuation:<sid>:<iter>`, gated by an atomic iteration claim on `end_turn` idles. A manual repost double-drives the turn. Interrupt-stop PAUSES the goal (resume via the Goal card/PATCH). The retired goal-loop CronJob is not a recovery path; goal creation and stop-hook handling explicitly call the idempotent `kickGoalLoop` driver. Re-arm a `budget_limited` goal by setting a new one (goalId rotates, accounting resets). See `references/goal-loop.md`.

- **Session Pulse Context % trusts provider usage, not the local heuristic.** The tile prefers the latest `context_*` fields on `agent.llm_usage` (`context_count_method=provider_usage`) over the pre-call `local_advisory` heuristic on `agent.context_usage` (which undercounts 20-25%), and INCLUDES cached tokens (window occupancy — matches Claude Code's `calculateContextPercentages`). Budget accounting deliberately differs (work metric, net of cache). Don't "fix" one to match the other.

- **Dynamic-script model routing: dapr-agent-py reads `agentConfig.modelSpec`, NOT `model`.** The script engine stamps both; anything else dispatching sessions must too. Dev defaults `DYNAMIC_SCRIPT_DEFAULT_MODEL` and `DYNAMIC_SCRIPT_STRUCTURED_MODEL` to `kimi/kimi-k3`; an explicit per-call/phase model still wins. Object-shaped K3 schemas use the synthetic `StructuredOutput` finalizer so browser/coding/MCP tools remain available before finalization; Pydantic and non-object schemas retain native strict JSON Schema. K3 reasoning stays `max` even when a script requests another effort. Sibling engine invariants: terminal paths persist via `persist_results_to_db`, usage aggregation waits for async event ingest, and in-flight budget overshoot is expected. Full SSOT: repo `docs/dynamic-script-workflows.md`.

- **`isAgentTaskConfig` is just `call === "durable/run"`.** That's the entire check (see `src/lib/types/agent-graph.ts`, `isAgentTaskConfig` at ~L438). The canvas marks the node `type: "agent"` automatically. Don't worry about a strict TS body shape — both flat (`with: {agentRef, prompt, ...}`) and nested (`with: {body: {agentRef, prompt, ...}, mode, sandboxName, ...}`) are accepted at runtime.

- **File operations are slug-as-action, not `workspace/file` with an `operation` field.** Valid slugs: `workspace/read_file`, `workspace/write_file`, `workspace/edit_file`, `workspace/list_files`, `workspace/delete_file`, `workspace/mkdir`, `workspace/file_stat`. Calling `workspace/file` with `operation: "write"` returns `workspace-runtime HTTP 400: operation is required and must be one of read_file, write_file, edit_file, list_files, delete_file, mkdir, file_stat` — that error message *is* the canonical list of valid slugs.

- **`agentRef` placeholders fail the resolver if they're a jq string.** When you author `${ .trigger.agentRef }` in a workflow JSON's `durable/run.with.body.agentRef`, the BFF's `resolveSpecAgentRefs` runs at workflow-LOAD time (before the orchestrator evaluates jq). It expects `agentRef` to be an object literal with `id` or `slug`, sees the string, and throws `Task X (durable/run) is missing agentRef. All workflows must be backfilled to named agents before executing.` For evals, `service.ts` solves this with a helper `stampAgentRefIntoDurableRunSteps(spec, {id, version})` that walks the spec and replaces the placeholder with the real ref before handing it to the resolver. If you build similar dispatch glue for non-eval flows, mirror the helper — don't try to make the resolver tolerate jq strings.

- **`with.keepAfterRun: true` is required to retain a workspace sandbox.** The `_should_cleanup_workspaces` gate in `sw_workflow.py` (def at ~L261) reads the spec directly (looking for `workspace/*` steps with `with.keepAfterRun=true` OR `with.body.input.keepAfterRun=true`), not just task outputs — because openshell-agent-runtime doesn't echo the flag back. Without this flag, the live-preview proxy returns 404 "Retained sandbox not found" after the run.

- **Removed slugs raise at dispatch.** The orchestrator's `_REMOVED_AGENT_ACTION_TYPES` set is exactly eight slugs: `claude/run`, `openshell/run`, `openshell/session-start`, `openshell-langgraph/run`, `openshell-langgraph-observable/run`, `dapr-agent-py/run`, `dapr-swe/run`, `durable/plan`. Any of these raises `Removed SW 1.0 agent action`. Note: `mastra/*` and `agent/*` are legacy/unsupported but are NOT in that set — they don't raise the "Removed" error; they fall through to the default route (function-router → `function-registry` `_default` `{type: activepieces}`, which computes a per-piece `ap-<piece>-service`) and fail there as an unknown piece/action. (The repo's own CLAUDE.md still lists `mastra/*`/`agent/*` as "rejected"; the code is authoritative — only the eight above hard-raise.)

- **`workflows.project_id` is NOT NULL since migration 0040.** Save through Workflow MCP or the authenticated BFF so the application stamps `projectId` from the workspace principal. Never create or repair workflow definitions with direct SQL; rows outside the application port can bypass ownership, graph derivation, and validation.

- **POST `/api/workflows` accepts `spec`.** The application command stamps workspace/user ownership, validates dynamic scripts, writes the full definition, and syncs connection references in one create call. `PUT /api/workflows/[workflowId]` updates an existing scoped definition. Workspace `wfb_...` keys authenticate Workflow MCP, not these session-authenticated BFF routes.

- **Dapr workflow state is shared through `workflowstatestore`; agent app state is separate.** Each workflow-enabled sidecar must see exactly one `actorStateStore=true` Component. On current dev, that is namespace-wide `workflowstatestore` (`tablePrefix=wfstate_`) for parent workflows, per-session agent workflows, timers, reminders, and activity bookkeeping. `dapr-agent-py-statestore` is namespace-wide too, but `actorStateStore=false`; it is only the agent application state API store (`tablePrefix=agent_py_`). Do not create per-agent or per-session actor stores, and do not move durable history into pod-local state.

- **Project MCP connections are resolved, not copied as secrets.** `mcp_connection` rows point to server/catalog metadata and optionally `connection_external_id`; `app_connection` stores encrypted OAuth credentials. AP credentials use **reference-forwarding** for BOTH MCP tools AND deterministic workflow activities: the caller forwards only `X-Connection-External-Id` (function-router writes the `credential_access_logs` audit, source `reference_forwarded`), and the piece-runtime self-resolves the plaintext by GETting the BFF `/api/internal/connections/<id>/decrypt` — the BFF is the SOLE decryptor. Do not put OAuth tokens or decrypted credential JSON into workflow specs, agent markdown, or KService env.

- **AP action slugs run on the per-piece piece-runtime, not a monolith.** An AP action slug (e.g. `github/create-issue`) dispatches via function-router (`function-registry` `_default` `{type: activepieces}`) to the per-piece `ap-<piece>-service` — one converged `piece-mcp-server` image parameterized by `PIECE_NAME` — where it runs as a deterministic Dapr activity (`POST /execute`). The SAME service also serves `/mcp` (agent tools) + `/options` (canvas dropdowns). `fn-activepieces` was deleted; the ~47 `ap-<piece>-service` Knative services are reconciler-provisioned from enabled `mcp_connection` rows + pinned pieces (all-catalog, so a new piece is automatic — no manual per-piece add).

- **ActivePieces piece MCP URLs should not include `:3100` through Knative.** The container listens on 3100, but workflow/agent configs should target the cluster-local KService URL such as `http://ap-microsoft-outlook-service.workflow-builder.svc.cluster.local/mcp`. Stale `:3100` URLs bypass Knative and make agents look silent.

- **MCP connection changes may require agent registry sync.** Direct workflow runs resolve project MCP at execution, but published/direct agents also carry startup MCP config that the BFF stamps into the per-session Sandbox pod's env as `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`. After changing an agent's MCP settings, re-publish or call `/api/agents/<id>/registry/sync`, then verify the bootstrap env on the next launched Sandbox and the `[mcp-bootstrap]` logs.

- **The include-all toggle attaches ALL project-level MCPs.** In the Tools & Integrations surface, leaving an agent's own attach-list empty with the include-all toggle ON expands the project's `mcp_connection` rows into the agent's bootstrap list. Each piece MCP's KService (`ap-<piece>-service`) scales to zero by default, so the first launch serially cold-starts every one — a typical 5-piece Microsoft set hangs pod readiness for 2.5+ minutes. Fix: turn include-all OFF (attach only the specific servers the agent needs) for agents that don't actually use project MCPs (smoke-test agents, prompt-cache validation agents). The bootstrap `mcpServers` then goes to `[]` and the Sandbox pod boots in <30s. Project-using agents are fine; the explicit attach-list just makes intent precise.

- **Prompt-cache TTL + cache-key are per-provider.** Anthropic uses `AgentConfig.cacheTtl: "5m" | "1h"` (1h opt-in via the `extended-cache-ttl-2025-04-11` beta header — right call for Dapr durable agents pausing >5min between turns; 1h costs 2× the base for cache writes vs 1.25× at 5m). OpenAI ignores `cacheTtl` (no API surface) and instead uses `prompt_cache_key` derived from `agent_id:version` to pin the cache shard. Both providers emit cross-provider telemetry on `agent.llm_usage` (`prompt_cache_ttl`, `prompt_cache_eligible`, `prompt_prefix_chars`, etc.) and a greppable `[instruction-bundle] mode=... cache_ttl=... [provider=openai]` log line. Threshold for cache eligibility is ≥4000 chars on the static prefix, shared between providers. See `references/prompt-caching.md` for the protocol details.

- **Direct DeepSeek is its own provider, not Together DeepSeek.** `deepseek/deepseek-v4-pro` and `deepseek/deepseek-v4-flash` map to `llm-deepseek-v4-pro` / `llm-deepseek-v4-flash` and are handled by `services/dapr-agent-py/src/deepseek_adapter.py` against DeepSeek's OpenAI-compatible `/chat/completions` endpoint using `DEEPSEEK_API_KEY`. Normal chat enables thinking (`DEEPSEEK_REASONING_EFFORT=max` by default); tool chat and structured summary calls disable thinking, and structured output uses `response_format: {"type":"json_object"}` rather than `json_schema`.

- **Prompt Workbench is an authoring and preview surface, not a runtime templating engine.** In V1, Mustache variables in agent persona fields, presets, or node prompt previews render only in the UI preview. Runtime still uses the canonical Dapr prompt path: one compiled system message from the instruction bundle, `chat_history`, and the current user prompt appended by Dapr.

- **Do not parameterize the stable system prompt unless the cache benefit is worth losing.** The 9 LLM adapters monkeypatch `DaprChatClient.generate` to call each provider's HTTP API **directly** — they deliberately bypass the still-ALPHA Dapr Conversation API, so prompt caching is the provider's own (Anthropic `cache_control` / `cacheTtl`, OpenAI `prompt_cache_key`), NOT a Conversation-component feature. Keep volatile values such as cwd, run id, session id, sandbox name, and workflow input out of the system/preset prefix when possible; put per-run data in the appended user prompt or workflow input so prompt-cacheable prefixes stay stable.

- **Prompt presets are project-scoped, versioned, and latest-by-default.** `resource_prompts` is the parent row; template edits create `resource_prompt_versions` rows with `messages`, `arguments`, `template_format`, and `template_hash`. Disabled or archived presets should not appear in normal picker results.

- **Unresolved Mustache variables must stay visible in preview.** A missing `{{runtime.cwd}}` / `{{args.foo}}` value should produce a warning and preserve the placeholder, not silently blank the prompt.

- **`Ignoring unexpected taskCompleted event` is normal replay chatter, NOT stuck.** durabletask-worker emits this during every `call_child_workflow` replay cycle. Real "stuck" signals: the target session Sandbox pod never got Kueue-admitted / never reached Running, OR the orchestrator emitting the same `Orchestrator yielded with N task(s) and 0 event(s) outstanding` line for >5 min with placement flaps in target daprd logs. Check the Sandbox pod status + `sessions.updated_at` *before* assuming a hang.

- **The current deployment/test lane is dev, through GitOps.** Do not start a local `pnpm dev` server for rollout verification. Merge workflow-builder source to GitHub `main`, let hub Tekton build GHCR images and update dev release metadata, then follow Source Hydrator -> GitOps Promoter -> `env/spokes-dev` -> dev ArgoCD. Use the `skaffold-dev-loop` skill only when the user explicitly asks for the separate Ryzen loop.

- **Sandbox templates are looked up by name in `SANDBOX_TEMPLATE_IMAGES_JSON`.** Script workspace/profile actions and legacy SW workspace steps resolve a template name through the workflow-builder Deployment env. Adding a template requires its environment Dockerfile/image plus the declarative env mapping in stacks. Deliver and verify it through the active dev GitOps lane; dormant staging and Ryzen are opt-in.

- **Seed/run under the real dev user unless intentionally testing another account.** Use `vinod@pittampalli.com` and dev project `N1nbCo9zESa-S0UrzVrOw`, not `admin@example.com` or `dev-admin-user`. Use `SEED_SWEBENCH_FIXTURES_ROLLBACK=true` for a dry run. Treat other cluster IDs as opt-in, target-local data.

- **Evaluation producers are migrating to dynamic scripts.** `taskConfig.workflowId` resolves a saved workspace definition through the application service; producer flags choose the script port during the cutover. Update reusable definitions through Workflow MCP/BFF application ports and validate with the evaluations skill. Do not run direct-DB `upsert-<workflow>` helpers as an operator workflow.

- **Dapr-agent custom activities use scoped names only.** With Dapr Agents 1.0.3, repo-owned `services/dapr-agent-py` custom workflow activities are registered and called through `self._activity_name(...)`. Do not restore the old bare-name fallback or register both names "for compatibility"; stale durable histories should be cancelled/cleaned/purged instead of keeping an ambiguous activity namespace. (This is a do-not-regress rule for *this repo's* runtime service. To author activities/agents in a fresh upstream Dapr app — generic `@wfr.activity(name=...)` / `DurableAgent` — use the `dapr-agents-workflow` skill.)

- **Orchestrator `wfstate_state` orphan reminders can block new StartInstance calls.** The `workflowstatestore` Component is `state.postgresql v2` with `tablePrefix=wfstate_`. When a workflow is purged but its actor reminder is still in dapr-scheduler-server's ETCD, daprd retries the reminder every ~10s and logs `Unable to get data on the instance: <id>, no such instance exists`. The retry loop can serialize behind the workflow runtime's worker queue and make new `ctx.call_child_workflow` / `StartInstance` calls hit `DEADLINE_EXCEEDED` after 60s. Confirm the daprd log pattern first. For terminal workflow cleanup, use the **Lifecycle Controller** (`stopDurableRun` with `mode:"purge"`/`"reset"` — recursive purge forwards `force`, Dapr 1.17.9 cleans the associated reminders). `workflow-builder-sandbox-gc` only removes aged orphan Sandbox CRs; it does not reconcile Dapr history or DB rows. Use manual `wfstate_state` truncation only as incident recovery after active runs and leases are zero.

- **Dapr sidecar `1/2` can be stale after control-plane churn.** If the app container is ready but `daprd` is not, probe `http://127.0.0.1:3501/v1.0/healthz` from inside the pod and read `kubectl logs <pod> -c daprd`. A stale workflow-enabled sidecar can return `ERR_HEALTH_NOT_READY` for `grpc-api-server` / `grpc-internal-server` after placement or scheduler restarts, while `3500/v1.0/metadata` still responds. If logs show `Actor runtime shutting down` or `Workflow engine stopped`, recycle the affected Deployment after confirming the Dapr control plane is healthy. See gitops `runbooks/debug-dapr-sidecar-stale-readiness.md`.

- **Don't roll workflow-orchestrator images while a workflow is mid-run.** Dapr durable-task replay compares the in-process code's `call_activity` ordering to the persisted history. If a new image lands on the worker pod between yields, replay fails with `Sub-orchestration task #N failed: A previous execution called call_activity with ID=M, but the current execution doesn't have this action with this ID`. The run is dead even if no orchestrator code actually changed (Python module import order, dep updates, or activity-registration reordering can shift IDs). Wait for active runs to finish before pushing image bumps. Hit twice on 2026-04-30 — both failed runs had this error and a fresh run on the stable image worked end-to-end.

## Reference index

Load these on demand based on what you're doing.

| Task | File |
| --- | --- |
| Authoring a workflow from scratch | `references/authoring-recipe.md` (dynamic-script end-to-end) |
| Inspecting or migrating a legacy SW 1.0 spec | `references/sw-1.0-spec.md` (12 task types, jq rules, validation checklist) |
| Adding an agent step | `references/agent-task.md` (durable/run body) + `references/cluster-topology.md` (per-agent pods) |
| Persisting typed outputs (markdown / JSON / table / link / image) for run-detail rendering | `references/workflow-artifacts.md` (declarative `artifacts:` block + UI surfaces) |
| Editing agent prompts, presets, preview variables, or prompt-cache-sensitive content | `references/prompt-workbench.md` |
| Reading per-provider prompt-cache telemetry, picking a `cacheTtl`, debugging cache hit rates | `references/prompt-caching.md` (Anthropic 5m/1h, OpenAI auto + `prompt_cache_key`, `agent.llm_usage` field map) |
| Saving/running workflows through the external Workflow MCP server, workspace-key setup, or optional session lineage | `references/workflow-mcp-server.md` |
| Adding or debugging agent-attached MCP tools/connections | `references/mcp-connections.md` (project ceiling, agent selection, ActivePieces auth, Sandbox bootstrap checks) |
| Setting/managing session goals, debugging the goal loop or budgets, reading Session Pulse, or triaging per-provider usage accounting | `references/goal-loop.md` (driver mechanics, MCP completion contract, guardrails, tick reaper, net-of-cache invariant, eval scenarios) |
| Choosing the right action slug | `references/action-catalog.md` (routing table + catalog API) |
| Debugging pod placement, Dapr sidecars, or runtime topology | `references/cluster-topology.md` |
| Inspecting/editing the canvas JSON | `references/canvas-shape.md` (node + edge shapes) |
| Confirming a workflow renders + runs | `references/verify-in-ui.md` |
| Debugging a failed run | `references/troubleshooting.md` (symptom-keyed triage) |
| Stopping / terminating / purging a run, or recovering stuck durable/DB state | `references/troubleshooting.md` § *Stopping a run (Lifecycle Controller)* + § *Stuck durable / DB state (now automated)* + the SSOT `docs/workflow-lifecycle-termination.md` |

Each reference file is focused (60–250 lines) and starts with a short scope summary. Read only what's relevant.

## Templates (assets/)

| File | Use when |
| --- | --- |
| `assets/minimal-http.workflow.json` | One `system/http-request` step. Trigger has one `url` property. Demonstrates jq full-string interpolation + `output.as`. |
| `assets/minimal-agent.workflow.json` | One `durable/run` step. Demonstrates `agentRef`, `prompt` with jq concat, `mode`, `maxTurns`, `stopCondition`. Includes the matching 3-node `nodes`/`edges` payload. |
| `assets/workspace-keepalive.workflow.json` | `workspace/profile` (`keepAfterRun: true`) → `durable/run` reading `${ .workspace_profile.sandboxName }`. The sandbox-bridging pattern. |
| `assets/with-artifacts.workflow.json` | One `durable/run` step with an `artifacts:` block (`kind: markdown`, `slot: primary`). Renders the agent's response on the run-detail Overview tab front-and-centre. Demonstrates the post-task `${ .data.content }` access pattern. |
| `assets/trigger-schema.snippet.json` | Drop-in `input.schema.document` block with form-friendly JSON Schema patterns (uri, enum, defaults, required). |

Open the file in `assets/` first to see the exact shape before drafting your own. Edit a copy — don't modify the templates in-place.

## Scripts (scripts/)

- **`scripts/upsert-workflow.py <file.json>`** — creates with one full POST or updates the payload's existing `id` with PUT. It requires a BFF access JWT or login cookie (not a `wfb_` Workflow MCP key), fails closed, and has no Postgres fallback. Prefer `save_workflow_script` for normal dynamic-script authoring.

## CLIs assumed available

| Tool | Typical use |
| --- | --- |
| `kubectl` | `kubectl get sandbox -n workflow-builder -w` to watch a per-session Sandbox pod get Kueue-admitted and start; `kubectl logs deploy/workflow-orchestrator -n workflow-builder` for parse errors |
| `psql` | Read-only incident diagnostics when explicitly approved; never a workflow authoring/write path |
| `gh` | API spec diffs, GitHub Actions trigger context for webhook-triggered workflows |
| `dapr` | `dapr workflow get -i <instance_id> --app-id workflow-orchestrator` to inspect a stuck run |
| `scripts/upsert-workflow.py` | Secondary BFF-authenticated create/update by JSON file |

## Safety guards before you act

- **Don't direct-patch the `function-registry` ConfigMap** on the cluster. Slug routing changes go through GitOps (PittampalliOrg/stacks). Read the `gitops` skill for the promotion flow.
- **Don't `pnpm dev` for rollout verification.** The active shared lane is the dev cluster through the GitHub/Tekton/GitOps path. Skaffold is a separate Ryzen-only loop and must be explicitly requested.
- **Do not start new work in SW 1.0.** Dynamic scripts use ordinary JavaScript and `args`; the jq full-string rule applies only when diagnosing a frozen legacy SW definition.
- **Don't write workflow definitions directly to Postgres.** Use Workflow MCP, the UI, or authenticated BFF APIs so the application ports enforce ownership, authorization, validation, connection synchronization, and audit behavior.
- **Don't create per-agent Dapr state stores.** Workflow runtimes use the centralized `workflowstatestore`; agent application state uses centralized `dapr-agent-py-statestore`. Per-agent/per-session stores make component visibility and durable replay harder to reason about.
- **Don't store MCP OAuth credentials in workflow JSON or agent markdown.** Bind project MCP rows to `app_connection.external_id` and let runtime requests carry `X-Connection-External-Id`.

## Authoritative source files (in the repos, not in this skill)

When you need ground truth, read these:

- workflow-builder lifecycle (stop/terminate/purge): `docs/workflow-lifecycle-termination.md` (SSOT), `src/lib/server/lifecycle/{index,cascade,resolvers}.ts`, `src/routes/api/v1/sessions/[id]/stop/{+server.ts,status/+server.ts}`, `src/routes/api/workflows/executions/[executionId]/stop/{+server.ts,status/+server.ts}`
- workflow-builder authoring/auth/model contracts: `docs/code-first-cutover.md`, `docs/dynamic-script-authoring-guide.md`, `docs/workflow-mcp-server.md`, `docs/dynamic-script-workflows.md`, `services/workflow-mcp-server/src/{auth-context,context-tools,script-tools,workflow-tools}.ts`, `services/dapr-agent-py/src/kimi_adapter.py`, `src/lib/agents/model-options.ts`
- workflow-builder SW/runtime: `CLAUDE.md`, `docs/workflow-artifacts.md`, `services/workflow-orchestrator/core/sw_types.py`, `services/workflow-orchestrator/core/sw_expressions.py`, `services/workflow-orchestrator/workflows/sw_workflow.py`, `services/workflow-orchestrator/activities/resolve_mcp_config.py`, `services/workflow-orchestrator/activities/persist_artifact.py`, `src/lib/utils/spec-graph-adapter.ts`, `src/lib/types/agent-graph.ts`, `src/lib/types/agents.ts`, `src/lib/server/agents/mcp-resolution.ts`, `src/lib/server/mcp-connections.ts`, `src/lib/server/action-catalog/index.ts`, `services/claude-agent-py/src/claude_sdk_runner.py`, `services/fn-system/src/steps/dapr-converse-structured-output.ts`, `services/piece-mcp-server/src/auth-resolver.ts`
- workflow-builder runtime SSOT: `services/shared/runtime-registry.json` (canonical), `services/workflow-orchestrator/core/runtime_registry.py`, `src/lib/server/agents/runtime-registry.ts`, `src/lib/server/agents/swap-safety.ts`, `src/lib/server/sessions/spawn.ts`, `scripts/sync-runtime-registry.mjs`
- workflow-builder goal loop + Pulse: `src/lib/server/goals/{goal-loop,render}.ts` + `templates/{continuation,budget_limit}.md`, `src/lib/server/application/adapters/{goal-loop-store,session-events}.ts`, `src/routes/api/v1/sessions/[id]/goal/+server.ts`, `services/workflow-mcp-server/src/{goal-tools,goal-db,goal-context}.ts`, `src/lib/components/sessions/{session-goal-badge,session-pulse}.svelte`, `src/lib/server/pricing/model-pricing.ts`, `services/dapr-agent-py/src/{openai_adapter,alibaba_adapter,event_publisher}.py`, `drizzle/0079_thread_goals.sql`; stacks: `{Deployment,Service}-workflow-mcp-server.yaml`
- stacks: `packages/components/workloads/workflow-builder/manifests/Component-dapr-agent-py-statestore.yaml`, `packages/components/workloads/workflow-builder/manifests/Component-workflowstatestore.yaml`, `packages/components/workloads/activepieces-mcps/manifests/`, `packages/base/manifests/knative-serving/kustomization.yaml`, `packages/components/workloads/function-router/manifests/ConfigMap-function-registry.yaml`, the upstream `kubernetes-sigs/agent-sandbox` + Kueue CRDs/manifests, `packages/base/manifests/openshell/MutatingWebhookConfiguration-openshell-sandbox-dapr-webhook.yaml`

The skill summarizes — these are authoritative if anything looks contradictory.
