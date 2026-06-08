# Troubleshooting

Scope: failure-symptom triage map for workflow runs. Each entry: **Symptom → Where to look → Likely cause → Fix.** Pulled from CLAUDE.md's "Troubleshooting" section + several feedback notes; updated when new failure modes land.

## How to triage

1. **Read the run status in the UI first** — `/workspaces/<slug>/workflows/<id>/runs/<execId>`. The failed task + last few log lines usually point straight at the cause.
2. **Use traces to line up the layers** — copy the run/execution `trace_id` from the UI or DB, then correlate workflow output, `sessions`, benchmark run instance rows, and OTel/MLflow spans before changing runtime images.
3. **Then check orchestrator logs** — `kubectl -n workflow-builder logs deploy/workflow-orchestrator -c workflow-orchestrator --tail=200`. Parse errors land here.
4. **For agent failures, check the per-session Sandbox pod** — find it via `kubectl -n workflow-builder get sandbox` / `kubectl -n workflow-builder get pods -l <session-label>`, then `kubectl logs <pod> -c dapr-agent-py --tail=200` (or the `claude-agent-py`/`adk-agent-py`/agent-host container). Agent runtime errors land here. (The retired per-agent `agent-runtime-<slug>` Deployment no longer exists.)
5. **For Dapr issues, check the daprd sidecar** — `kubectl -n workflow-builder logs <pod> -c daprd --tail=100`. Boot crashes + placement issues land here.
6. **For MCP/tool failures, check resolved bootstrap config** — inspect bootstrap MCP env, `activepieces-mcp-catalog`, and `[mcp-bootstrap]` logs before changing the workflow spec.

## Symptom map

### Spec parse / dispatch errors

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Removed SW 1.0 agent action: claude/run` (or similar) at orchestrator startup | Spec uses a rejected legacy slug | Replace with `durable/run` + `with.agentRef` (see `references/agent-task.md`). |
| `Unknown task type` in orchestrator logs | Task missing one of the 12 type-trigger fields | Confirm the task value has exactly one of `call`/`do`/`for`/`fork`/`switch`/`try`/`wait`/`set`/`emit`/`listen`/`run`/`raise`. |
| `${ .trigger.x }` resolves to null at runtime | Field not declared in `spec.input.schema.document.properties` | Add the property to the trigger schema (see `references/sw-1.0-spec.md` § Trigger schema). |
| Prompt or URL contains literal `${` text in the run output | jq full-string rule violation — only fully-wrapped values evaluate | Wrap the entire string in one `${...}` expression: `"${ \"prefix \" + .trigger.x }"`. |
| BFF returns `400 No active workspace` on POST | `locals.session.projectId` is null — user has no active workspace | Click a workspace in the sidebar; or pass `--project-id` to the upsert script; or `UPDATE projects SET ...` to set defaults. |
| BFF returns `503 Database not configured` | DB connection string missing in BFF pod | Check `DATABASE_URL` env on the workflow-builder Deployment; ESO secret may not be hydrated. |

### Agent dispatch / execution

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `durable/run` step times out, agent never starts | Per-session Sandbox pod never got Kueue-admitted / never reached Running (cluster at capacity, no `ResourceFlavor`/quota, or image pull stall) | `kubectl -n workflow-builder get sandbox` and the matching pod; check Kueue admission: `kubectl -n workflow-builder get workloads`. If the Workload is `Pending`/not admitted, the local-queue/cluster-queue is out of quota or the pod is unschedulable — free capacity or fix the queue. There is no AgentRuntime CR / Kopf controller to wake anymore. |
| `ctx.call_child_workflow` times out `the app may not be available` | Target Sandbox pod isn't Dapr-placement-registered (not yet admitted/Running OR cross-namespace) | Confirm the per-session Sandbox pod is Running in `workflow-builder` (or, for the pool path, `kubectl -n workflow-builder get deploy/dapr-agent-py`). Session Sandbox pods MUST be in the `workflow-builder` namespace — Dapr workflow sub-orchestration doesn't cross namespaces. |
| Agent loops with empty assistant responses, never terminates | Anthropic SDK [issue #1204](https://github.com/anthropics/anthropic-sdk-python/issues/1204) — Opus 4.7 + adaptive thinking emits empty `end_turn` | Empty-response circuit breaker should trip after `DAPR_AGENT_PY_EMPTY_RESPONSE_THRESHOLD` (default 3). Check pod logs for `[call-llm] circuit-breaker tripped`. Tunable via env. |
| Agent responds but lacks expected MCP tools | `mcpConnectionMode` is `explicit`, project `mcp_connection` row is disabled/missing, or the bootstrap env wasn't refreshed after MCP changes (NOTE: `claude-agent-py` now supports MCP too — `agentConfig.mcpServers` is wired into the SDK) | Read `references/mcp-connections.md`; inspect the launched Sandbox pod's `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON` env; run agent registry sync or re-publish. |
| Agent with Outlook/Excel/etc. MCP gets no response or tool call hangs | Generated AP piece KService missing/cold-starting, stale `:3100` URL, or missing `X-Connection-External-Id` | Check `activepieces-mcp-catalog`, `ksvc ap-<piece>-service`, and runtime logs for `[mcp-bootstrap]` / `Missing credentials`. KService URL should omit `:3100`. |
| Child session hangs forever, no LLM traffic | No in-workflow turn timer exists anymore — the durable 600s `when_any([child, timer])` session-turn timer was **deleted** (commit `72154581`). An out-of-band **host-monitor thread** (`session_host_monitor.py`) observes start/idle stalls but its default action is **`"warn"`**, not terminate. | First check the per-agent pod logs for the host-monitor warning and the underlying stall (placement flap, LLM provider hang, MCP cold-start). To actually halt it, **use the Lifecycle Controller** — `POST /api/v1/sessions/[id]/stop {mode:"terminate"}` (or `interrupt` to ask the agent to halt cooperatively; both runtimes now honor mid-turn cancel). For a hung pod that died before emitting `session.status_terminated`, the **lifecycle-terminal-reaper CronJob** reconciles the stuck `running` DB row against the terminal/gone Dapr instance within one interval — you no longer have to hand-run SQL. The host-monitor only auto-escalates to terminate if its non-terminal-timeout action is explicitly set to `terminate`/`exit`/`fail`; by default it just warns. |
| SWE-bench or 3B1B output says `agentRuntime=claude-agent-py`, but the sandbox/runtime label mentions `dapr-agent` or `dapr-agent-py` | Workspace template and agent runtime are being conflated, or the agent-host container label is legacy/static | Treat this as expected until DB/runtime evidence says otherwise. Check `benchmark_runs.agent_runtime`, `agent_runtime_app_id`, `model_name_or_path`, workflow output `agentWorkflowMode`, trace id, and live image/env pins. `sandboxTemplate: "dapr-agent"` often names the OpenShell workspace image, not the Claude runtime. |
| Anthropic API returns `HTTP 400 prompt is too long: N tokens > 1000000` | Image tool_results accumulated past compaction limit | `_compact_image_tool_results` keeps the last `DAPR_AGENT_PY_MAX_IMAGE_TOOL_RESULTS` (default 3) images intact. Lower the env var or tighten the validator prompt to take fewer screenshots. |
| Anthropic API returns `HTTP 400 Streaming is required for operations that may take longer than 10 minutes` | Non-streaming `messages.create()` exceeded the server's 10-min estimate | Should already be fixed by `_stream_final_message` in `anthropic_adapter.py` — verify the deployed image is recent. As a workaround, lower `DAPR_AGENT_PY_MAX_TOKENS` (default 16384). |
| Per-session Sandbox pod stays `0/2` for 2+ minutes after launch; logs cycle through `[mcp-bootstrap] connect piece_microsoft-* failed: unhandled errors in a TaskGroup` every 30s | Agent has `mcpConnectionMode: "auto"` and empty `mcpServers`; `resolveAgentConfigMcpForProject` expanded all project `mcp_connection` rows; each piece KService is at `replicas=0` and serially cold-starts | Set `mcpConnectionMode: "explicit"` on the agent, force registry-sync. The bootstrap `mcpServers` env will go to `[]` and the next launched Sandbox boots in <30s. Project-using agents are unaffected. |

### Prompt cache (Anthropic + OpenAI)

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `agent.llm_usage` shows `prompt_cache_eligible: false` despite a verbose prompt | Static prefix didn't cross the 4000-char threshold (≈1024 tokens) — usually because boundary sentinel was stripped or the prompt is genuinely short | Inspect `prompt_prefix_chars` on the event. If 0, `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` is missing from `rendered.system` (bundle composition bug). If non-zero but <4000, the prompt is too short to cache — pad with preset content or accept the no-cache path. |
| Anthropic agent shows `cache_creation_input_tokens` on every turn, never `cache_read_input_tokens` | Cache key churn between turns: tool-list shuffle (MCP reconnect), TTL flip, or system content drift | Diff `prompt.tools_hash` and `instructionHash` on consecutive `agent.llm_usage` events; if `tools_hash` changes, MCP/plugin churn is the culprit (verify the adapter's deterministic sort kept the order stable). If `instructionHash` changes, something injected a volatile value into the static prefix. |
| OpenAI agent never sees cached_tokens despite identical prompts across sessions | `prompt_cache_key` not being stamped — agent has no `id+version` (ephemeral inline workflow agent) so `derive_openai_cache_key` returns None and OpenAI default-routes by `(org_id, prompt_prefix)` hash, scattering across pods | Publish the agent so it gets a stable id+version, OR for the inline path accept that ephemeral agents won't share cache shards across replicas. |
| Anthropic 1h TTL set but `cache_creation_input_tokens` is high relative to `cache_read_input_tokens` over many turns | Either pod restarted within window (fresh cache once per pod) or the agent isn't actually pausing >5min between turns | Sample `agent.llm_usage` over a week grouped by agent. If hit ratio < 0.5, 5m TTL would have been cheaper (1h writes cost 2× base vs 1.25× for 5m). Flip back to 5m. |
| `cacheTtl: "1h"` on an OpenAI-component agent has no effect | `cacheTtl` is silently ignored on OpenAI — there's no API surface for it | This is by design. OpenAI emits `prompt_cache_ttl: "auto"` on the event; check Phoenix `prompt.cache_key` to confirm routing pin instead. |

### Prompt Workbench / presets

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Prompt preset applies in the editor but the running agent still uses old instructions | Applying a preset only changes unsaved `AgentConfig` fields | Save the agent, then publish or registry-sync through the normal agent version flow. Runtime reads the saved compiled instruction bundle, not the preview. |
| `{{runtime.cwd}}`, `{{args.foo}}`, or similar text appears in the actual run prompt | Prompt Workbench Mustache variables are preview-only in V1 | Use SW jq expressions for workflow runtime values, or move stable text into the saved agent config. Treat Mustache warnings as authoring feedback, not runtime substitution. |
| `/api/prompt-presets` returns 500 after deployment | `resource_prompt_versions` migration did not apply, usually because Drizzle journal metadata is missing | Check `to_regclass('public.resource_prompt_versions')`, `drizzle/meta/_journal.json`, and the `db-migrate` Job logs. Production migrations are Drizzle/journal-gated; see the gitops `runbooks/fix-drizzle-migration.md`. |
| Enabled prompt preset is missing from the picker | Preset is archived/disabled, belongs to a different project, or latest version pointer is missing | Query `resource_prompts` by project and enabled/archive state, then confirm a latest `resource_prompt_versions` row exists. Normal picker APIs are project-scoped. |
| Prompt-cache hit rate drops after a prompt edit | Volatile values moved into the system/preset prefix | Keep cwd, sandbox, run/session ids, and workflow inputs in the appended user prompt when possible. Audit template hash and instruction hash before changing cache settings. |

### Stopping a run (Lifecycle Controller)

Every user-facing "stop" routes through ONE vetted server-side **Lifecycle Controller** — `stopDurableRun(target, {mode})` in `src/lib/server/lifecycle/{index,cascade,resolvers,reaper}.ts`. Don't hand-roll terminate/purge or DB-flips; call the controller (or its HTTP surfaces). It generalizes — and is shared with — the benchmark cancellation cascade.

| Surface | Call |
| --- | --- |
| Stop a session (UI/agent run) | `POST /api/v1/sessions/[id]/stop` body `{mode, reason?, graceMs?}` |
| Stop a workflow execution | `POST /api/workflows/executions/[id]/stop` body `{mode, reason?}` (the old `.../terminate` route still exists but is now a thin `mode:"terminate"` delegate; prefer `/stop`) |
| UI buttons | **Stop** (terminate) / **Stop & Reset** (purge/reset) on the session-detail + workflow-run pages |

**Modes** (`target.kind ∈ workflowExecution | session | evalRun`):

- `interrupt` — cooperative halt of the current turn; keeps the run. No purge, no reap, no DB flip. Both runtimes now honor mid-turn cancel.
- `terminate` — hard-stop the durable tree (graceful → forceful). No purge.
- `purge` — terminate → confirm terminal → recursive Dapr purge of state + reap the per-session Sandbox CR + flip DB rows terminal.
- `reset` — purge + force-delete state rows even if Dapr never confirmed terminal (the user-reachable "Stop & reset" byte-clean mode, scope-guarded).

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| "Stop" returns **202 "stopping"** and the run lingers briefly | **By design (request/confirm)** — the stop persisted a `stop_requested_at` intent and the durable tree is still converging (e.g. a `terminate` blocked inside a long activity applies only when it yields). It does NOT flip DB / reap until Dapr is confirmed terminal. | Nothing — the UI shows "Stopping…" and polls `GET …/stop/status` (→ `confirmDurableStop`); the `lifecycle-terminal-reaper` is the backstop if the tab closes. A `durable/run` parent **wedged** awaiting a cross-app child is force-finalized after `LIFECYCLE_WEDGE_FINALIZE_GRACE_SECONDS` (default 180s) once its child session is DB-terminated. |
| "Stop" returns **409** | A genuine non-request failure, OR **`coordinator_owned`** — the target is a benchmark/eval instance. | If `coordinator_owned`, cancel the owning **run** (`POST /api/benchmarks/runs/[id]/cancel` or `…/evaluations/runs/[id]/cancel`), not the instance — the UI links there. Otherwise check the parent + per-session child workflow status (the cascade fans out terminate/purge **explicitly per per-session app-id**; the native Dapr recursive cascade doesn't cross task hubs) + the Sandbox CR/pod, then escalate to `mode:"reset"`. |
| Delete/Archive returns **409 "Stop the run first"** | The run is still active; destructive delete is blocked while a durable run is live. | Stop the run first (`mode:"terminate"` or `"purge"`), then delete. The sessions-list "Archive" action was relabeled **Delete** (it always hard-DELETEd). |
| Mid-turn `interrupt` did nothing (old behavior) | Was the `dapr-agent-py` cancel-key write/read mismatch for `durable/run`. | **Fixed** — the read strips `__turn__N`/`:turn-N` so keys agree; `claude-agent-py` reached management parity (`/api/v2/agent-runs/{id}/{terminate,pause,resume}` + DELETE purge + between-turn cooperative-cancel). If interrupt still no-ops, verify the deployed runtime image is recent. |
| `/api/workflow-ops/*` returns 401/403 | Those routes now require **platform admin** (they were previously an UNAUTHENTICATED JSON API). | Authenticate as a platform admin. The dead unauthenticated `DELETE /api/orchestrator/workflows/[id]` route + the 404 api-client methods (`workflows.terminateExecution`, `orchestrator.terminate/raiseEvent`) were removed. |
| Re-running the same workflow node inherits a stale pod / state | Was the per-session Sandbox CR 409-adopting an existing CR, or `_idempotent_schedule` reusing a stuck non-terminal instance. | **Fixed** — sandbox-execution-api stamps an owner-run-id annotation and adopts only the SAME run, else deletes+recreates; `_idempotent_schedule`'s purge-before-reuse is guarded to ONLY the DB-terminal-but-Dapr-non-terminal divergence (it never kills a legitimately running instance). The orchestrator's `purge_workflow` is recursive-by-default + forwards `force` (purge-force, Dapr 1.17.9). A clean re-run should start byte-clean. |

SSOT: `docs/workflow-lifecycle-termination.md` (in the workflow-builder repo).

### Stuck durable / DB state (now automated)

The old framing — "manual SQL resets and `scripts/*purge*` are the only cleanup" — is **superseded**. Cleanup is now automated by GitOps CronJobs + the controller; reach for manual SQL only as incident recovery after the automated paths have run.

| Mechanism | What it does |
| --- | --- |
| **lifecycle-terminal-reaper CronJob** → `POST /api/internal/lifecycle/reap-terminal` | Reconciles DB rows stuck non-terminal against terminal/gone Dapr instances, purges orphans. **SKIPS while a benchmark run/lease is active** (so it never races a live eval). This is what flips a `running` `sessions`/`workflow_executions` row whose pod died before emitting `session.status_terminated`. |
| **workflow-builder-sandbox-gc CronJob** | Age-based GC of orphaned per-session agent-host Sandbox CRs **in the `workflow-builder` namespace** (excludes `SandboxWarmPool`-owned). Previously the only Sandbox-GC swept the `openshell` namespace only. |
| **Unified Dapr `stateRetentionPolicy = 168h`** | Parent (`workflow-orchestrator-no-tracing`) AND the per-session child Configs (`workflow-builder-agent-runtime`, `openshell-sandbox-dapr`) now share 168h. This closed the cascade-termination race where children were auto-purged (old 30m) before the parent finished and the parent then looped on `no such instance exists`. |
| **runbooks/phase0-lifecycle-clean-slate.{sh,md}** (stacks) | A guarded, **dry-run-by-default** one-time bulk purge for a clean slate. NOT auto-run — operator-invoked only. |

If you still see a stuck row after a reaper interval: confirm the reaper ran (it's skipped during active benchmark runs/leases), then use `mode:"reset"` via the Lifecycle Controller, and only then fall back to scoped `wfstate_state`/`agent_py_state` truncation as last-resort incident recovery (after active runs + leases are zero).

### Replay chatter (false alarms)

| Symptom | Why it's normal |
| --- | --- |
| Orchestrator logs `Ignoring unexpected taskCompleted event with ID = N` | durabletask-worker emits this during every `call_child_workflow` replay cycle while the child runs. Not a stuck signal. |
| Orchestrator logs `Orchestrator yielded with 1 task(s) and 0 event(s) outstanding` repeatedly | Normal during a long child workflow. Becomes a real signal only if it persists >5 min AND the session Sandbox pod isn't Running/admitted AND placement is flapping in target daprd logs. |

Don't intervene on replay chatter alone — check the session Sandbox pod status + `sessions.updated_at` first.

### Workspace / sandbox

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Live-preview proxy returns 404 "Retained sandbox not found for this execution" | `workflow_workspace_sessions` row missing or `status='cleaned'` | Check `with.keepAfterRun: true` is set on the `workspace/*` step. The `_should_cleanup_workspaces` gate (`sw_workflow.py`, def at ~L261) reads the spec — the flag MUST be in the spec, not just task outputs. Manually revive: `UPDATE workflow_workspace_sessions SET status='active' WHERE workflow_execution_id=<id>`. |
| Tool fails with `[Errno 2] No such file or directory: '/root/.config/openshell/active_gateway'` | `seed-openshell-config` init container didn't run in the launched Sandbox pod | Confirm the Sandbox pod template includes the `seed-openshell-config` init container and that the `openshell-client-tls` / `openshell-server-client-ca` Secrets exist; the `openshell-sandbox-dapr-webhook` namespaceSelector must include `workflow-builder`. Re-launch the session after fixing. |
| SWE-bench (or any benchmark) child workflow fails with `Request to openshell-agent-runtime (workspace/profile) timed out after 300000ms` — esp. under burst load | function-router image pre-dates workflow-builder commit `2a68cca7` (2026-05-09); `MAX_WORKSPACE_PROFILE_TIMEOUT_MS` was hard-coded to `300_000` | Roll dev `function-router` to `ghcr.io/pittampalliorg/function-router:git-2a68cca7c63b…` or newer. The cap is now an env var (default 1h). See `shared-skills/evaluations/references/swebench-concurrency.md` § Function-Router Workspace/Profile Timeout. |
| `browser/validate` fails with `Dev server did not become ready` even though the server log shows it bound successfully (e.g. `Serving HTTP on 0.0.0.0 port 8080 ...`) | The runtime allocates its own port via `_allocate_local_port()` and probes that port; user's `devServerCommand` is binding a different port (hardcoded 3009/8080/etc.) | Omit `devServerCommand` (the runtime's default `_local_devserver_runner` auto-detects index.html / package.json) OR use the `{port}` / `${PORT}` / `$PORT` placeholder. Bind to `0.0.0.0`, not `127.0.0.1`. See `references/action-catalog.md` § `browser/validate`. |

### Daprd boot crashes (per-agent pod won't start)

| Crash message | Likely cause | Fix |
| --- | --- | --- |
| `detected duplicate actor state store` | Pod sees more than one Component with `actorStateStore=true`, or a legacy Component was made visible again | Current dev expects namespace-wide `workflowstatestore` as the only actor/workflow store and `dapr-agent-py-statestore` as `actorStateStore=false`. Do not create per-agent state stores. See `references/cluster-topology.md` § Dapr Component scoping. |
| `no X509 SVID available / failed to get configuration` | The `dapr.io/config`-referenced Configuration is missing in pod's namespace | Ensure `Configuration/openshell-sandbox-dapr` exists in `workflow-builder` (file: `packages/components/workloads/workflow-builder/manifests/Configuration-openshell-sandbox-dapr.yaml`). |
| Pod has no daprd sidecar at all | Webhook didn't fire | Confirm `MutatingWebhookConfiguration/openshell-sandbox-dapr-webhook` exists and `namespaceSelector` includes `workflow-builder`. Re-launch the session to retry the inject. |

### BFF / orchestrator connectivity

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| BFF `/api/workflows/[id]/execute` fails with `TypeError: fetch failed` + `ECONNREFUSED <orchestrator-svc-IP>:8080` | Orchestrator pod CrashLoopBackOff | `kubectl -n workflow-builder logs deploy/workflow-orchestrator -c workflow-orchestrator --previous`. Common cause: orchestrator image pre-dates an `activities/<x>.py` file referenced by `sw_workflow.py`, raising `ModuleNotFoundError`. Rebuild from a commit that includes the file. |
| Workflow won't start; UI shows generic "execution failed" | Orchestrator parse error swallowed at SSE | `kubectl -n workflow-builder logs deploy/workflow-orchestrator --tail=300 | grep -E 'ERROR|Removed|Unknown'`. |
| SWE-bench run creates no sessions and token counts stay zero | Parent orchestrator readiness gate is closed, preflight has not finished, or no OpenShell pod was admitted | Check in order: `benchmark_runs.status`, preflight logs/builds, `workflow-orchestrator /readyz`, `benchmark_run_instances.dapr_instance_id`, OpenShell pods, `sessions.id`, then `agent.llm_usage`. MLflow `[mlflow]` timeouts are not a start blocker when `MLFLOW_FAILURE_MODE=best_effort`. |
| `workflow-orchestrator /readyz` shows `workflowConnectedWorkers=0` or sidecar logs mention workflow actor registration errors | Stale `daprd` sidecar after Dapr control-plane churn or partial container restart | Wait for the orchestrator watchdog to self-delete the pod, or delete the `workflow-orchestrator` pod if no active run depends on it. Full pod replacement is required so the `daprd` sidecar restarts too. |
| ArgoCD says `dev-workflow-orchestrator` is Synced but the live Deployment still runs the previous image | Argo application cache/source refresh lag | Hard-refresh the app: `kubectl --kubeconfig ~/.kube/hub-config -n argocd annotate app dev-workflow-orchestrator argocd.argoproj.io/refresh=hard --overwrite`, then re-check the Deployment image. |
| Benchmark run is terminal in DB/evaluator, but Dapr status still reports parent/session workflow `RUNNING` | Dapr durable state/status is stale after terminate; normal purge refuses non-terminal status | Use terminal benchmark cleanup (now shared with the Lifecycle Controller cascade), not DB-only edits. It terminates/polls/purges agent session and turn workflows first (explicit per-session app-id fan-out), then parent workflows. The **lifecycle-terminal-reaper CronJob** also reconciles stuck rows on a timer — except while a benchmark run/lease is active, so it won't race a live eval. Only after the run is terminal and cleanup has attempted normal purge should scoped `wfstate_state` / `agent_py_state` rows be removed as last-resort recovery. |
| Many instances stop advancing after a rollout with replay errors such as `previous execution called call_activity ... current execution doesn't have this action` | A scheduled activity/child workflow was added, removed, or conditionally skipped while Dapr histories existed | Roll back or deploy code that preserves the historical schedule. If disabling MLflow/tracing/hooks, keep the scheduled activity and make its body no-op. Do not roll workflow-orchestrator/coordinator/agent runtime images during an active benchmark run. |
| `Activity function named <name> is not registered` from `dapr-agent-py` after a runtime update | Dapr history or call site references an activity name that no longer matches the registered Dapr Agents 1.0.3 name | Current code standard is scoped custom activity names through `self._activity_name(...)` only. Verify the live `dapr-agent-py` image contains the scoped-name fix, then cancel/cleanup/purge stale histories if they require old bare names. Do not add dual bare/scoped registration. |

### DB scoping

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Workflow inserted but doesn't appear in any workspace | `project_id` is NULL | `SELECT id, name, project_id FROM workflows WHERE id='<id>';`. Backfill: `UPDATE workflows SET project_id='<real-project-id>' WHERE id='<id>';`. Migration 0040 made the column NOT NULL — new inserts can't repeat this, but old rows might. |
| Workflow visible to one user, not their teammate | `project_members` missing the teammate | `SELECT * FROM project_members WHERE project_id='<id>';` then INSERT a row with `role` ∈ ADMIN/EDITOR/OPERATOR/VIEWER. |
| Sessions show raw IDs instead of agent labels | Sessions point at workflow-ephemeral agents | Expected — `/api/agents` filters those out. As of 2026-04-21 `listSessions` LEFT JOINs `agents` and returns `agentName/agentSlug/agentAvatar/agentEphemeral` so the row renders ⚡ + "eph". |

### MLflow trace state finalization

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| MLflow Traces UI shows `IN_PROGRESS` after a workflow finished | The `finalize_mlflow_trace_root` activity didn't run, or `MLFLOW_FINALIZE_ROOT_SPAN_ENABLED=false`, or the OTLP collector is unreachable. | **Fixed since 2026-05-12** (commit `b9c3dfbb`, live as `3a724061`): orchestrator yields `finalize_mlflow_trace_root` at workflow end which builds a synthetic OTLP `ResourceSpans` proto with the workflow's trace_id + `parent_span_id` empty + status OK/ERROR, then POSTs it raw to `${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces`. MLflow's OTLP receiver sees a root-span end and transitions `trace_info.state` to OK. The activity is **best-effort** — it logs `[MLflow Finalize] root span export failed` on warning if the OTLP endpoint is unreachable or the proto build fails, but never breaks the workflow. Verify: `kubectl -n workflow-builder logs deploy/workflow-orchestrator \| grep "MLflow Finalize"`. Disable via env `MLFLOW_FINALIZE_ROOT_SPAN_ENABLED=false`. Implementation: `services/workflow-orchestrator/activities/finalize_mlflow_trace_root.py` + `tracing.py::emit_mlflow_trace_root_span`. |
| The activity emits a span but trace state still IN_PROGRESS | SDK tracer is interfering — synthetic span got attached as child of an active OTel context | The synthetic span **must be sent via raw HTTP**, not through the SDK's BatchSpanProcessor. The SDK would attach the span as a child of whatever context is active (typically the activity span). Verify `emit_mlflow_trace_root_span` is using `urllib.request` (or equivalent) directly, not `tracer.start_as_current_span`. |

## Diagnostic command cheat sheet

```bash
# Orchestrator parse + dispatch
kubectl -n workflow-builder logs deploy/workflow-orchestrator -c workflow-orchestrator --tail=200 -f

# Per-session runtime Sandbox pod (no AgentRuntime CR — use Sandbox/pods)
kubectl -n workflow-builder get sandbox
kubectl -n workflow-builder get workloads   # Kueue admission status
kubectl -n workflow-builder logs <session-sandbox-pod> -c dapr-agent-py --tail=200 -f
# Surviving static pool / openshell-durable-agent enum:
kubectl -n workflow-builder logs deploy/dapr-agent-py -c dapr-agent-py --tail=200 -f

# SWE-bench runtime proof (run inside workflow-builder pod or with DATABASE_URL)
psql "$DATABASE_URL" -c "
select id, agent_runtime, agent_runtime_app_id, model_name_or_path, status, summary
from benchmark_runs
order by created_at desc
limit 5;"

# MCP bootstrap on a launched per-session Sandbox pod
kubectl -n workflow-builder get pod <session-sandbox-pod> -o json | \
  jq -r '.spec.containers[] | select(.name=="dapr-agent-py") | .env[] | select(.name=="DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON").value' | jq .
kubectl -n workflow-builder logs <session-sandbox-pod> -c dapr-agent-py --tail=250 | \
  rg 'mcp-bootstrap|Loaded|Registered|Missing credentials'

# Daprd boot
kubectl -n workflow-builder logs <pod> -c daprd --tail=100

# Kueue admission for a stuck session (no wake annotation exists anymore)
kubectl -n workflow-builder get workloads
kubectl -n workflow-builder describe sandbox <session-sandbox>

# Inspect a stuck workflow instance via Dapr
kubectl -n workflow-builder exec deploy/workflow-orchestrator -c daprd -- \
  dapr workflow get -i <execution-id> --app-id workflow-orchestrator

# Recent execution status
kubectl -n workflow-builder exec deploy/workflow-builder -- \
  psql "$DATABASE_URL" -c "SELECT id, status, started_at, completed_at FROM workflow_executions WHERE workflow_id='<id>' ORDER BY started_at DESC LIMIT 5;"
```

## When to escalate to the gitops skill

Anything that's actually a deploy / image / GitOps issue:

- Image needs to be rebuilt or promoted (`dapr-agent-py` source change, etc.).
- ConfigMap (`function-registry`) needs a slug routing change.
- Dapr Component scopes or controller-managed `dapr-agent-py-statestore` reconciliation drifted.
- `activepieces-mcps`, Knative Serving, or piece MCP services are missing/unhealthy.
- ArgoCD app stuck OutOfSync.

The `gitops` skill covers all of that — this skill stops at "what does the runtime do and how do I read its logs."
