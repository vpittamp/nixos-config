# Troubleshooting

Scope: failure-symptom triage map for workflow runs. Each entry: **Symptom → Where to look → Likely cause → Fix.** Pulled from CLAUDE.md's "Troubleshooting" section + several feedback notes; updated when new failure modes land.

## How to triage

1. **Read the run status in the UI first** — `/workspaces/<slug>/workflows/<id>/runs/<execId>`. The failed task + last few log lines usually point straight at the cause.
2. **Then check orchestrator logs** — `kubectl -n workflow-builder logs deploy/workflow-orchestrator -c workflow-orchestrator --tail=200`. Parse errors land here.
3. **For agent failures, check the per-agent pod** — `kubectl -n workflow-builder logs deploy/agent-runtime-<slug> -c dapr-agent-py --tail=200`. Agent runtime errors land here.
4. **For Dapr issues, check the daprd sidecar** — `kubectl -n workflow-builder logs <pod> -c daprd --tail=100`. Boot crashes + placement issues land here.
5. **For MCP/tool failures, check resolved bootstrap config** — inspect `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`, `activepieces-mcp-catalog`, and `[mcp-bootstrap]` logs before changing the workflow spec.

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
| `durable/run` step times out, agent never starts | AgentRuntime CR `phase=Sleeping` or pod not woken | `kubectl -n workflow-builder get agentruntime/<slug>` → if Sleeping for >30s after the wake annotation, restart the controller: `kubectl -n workflow-builder rollout restart deploy/agent-runtime-controller`. Kopf annotation watcher dropouts after dapr-placement-server flaps are a known issue. |
| `ctx.call_child_workflow` times out `the app may not be available` | Target pod isn't Dapr-placement-registered (scaled to 0 OR cross-namespace) | Confirm pod replicas: `kubectl -n workflow-builder get deploy/agent-runtime-<slug>`. Per-agent pods MUST be in the `workflow-builder` namespace — Dapr workflow sub-orchestration doesn't cross namespaces. |
| Agent loops with empty assistant responses, never terminates | Anthropic SDK [issue #1204](https://github.com/anthropics/anthropic-sdk-python/issues/1204) — Opus 4.7 + adaptive thinking emits empty `end_turn` | Empty-response circuit breaker should trip after `DAPR_AGENT_PY_EMPTY_RESPONSE_THRESHOLD` (default 3). Check pod logs for `[call-llm] circuit-breaker tripped`. Tunable via env. |
| Agent responds but lacks expected MCP tools | `mcpConnectionMode` is `explicit`, project `mcp_connection` row is disabled/missing, or AgentRuntime bootstrap wasn't refreshed after MCP changes | Read `references/mcp-connections.md`; inspect `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`; run agent registry sync or re-publish. |
| Agent with Outlook/Excel/etc. MCP gets no response or tool call hangs | Generated AP piece KService missing/cold-starting, stale `:3100` URL, or missing `X-Connection-External-Id` | Check `activepieces-mcp-catalog`, `ksvc ap-<piece>-service`, and runtime logs for `[mcp-bootstrap]` / `Missing credentials`. KService URL should omit `:3100`. |
| Child session hangs forever, no LLM traffic | Session-turn timer timeout (default 600s) didn't fire | Check pod logs for `Session turn N exceeded`. Tunable via `DAPR_AGENT_PY_SESSION_TURN_TIMEOUT_SECONDS`. If the timer didn't fire at all, look for `when_any` handler issues in `session_workflow`. |
| Anthropic API returns `HTTP 400 prompt is too long: N tokens > 1000000` | Image tool_results accumulated past compaction limit | `_compact_image_tool_results` keeps the last `DAPR_AGENT_PY_MAX_IMAGE_TOOL_RESULTS` (default 3) images intact. Lower the env var or tighten the validator prompt to take fewer screenshots. |
| Anthropic API returns `HTTP 400 Streaming is required for operations that may take longer than 10 minutes` | Non-streaming `messages.create()` exceeded the server's 10-min estimate | Should already be fixed by `_stream_final_message` in `anthropic_adapter.py` — verify the deployed image is recent. As a workaround, lower `DAPR_AGENT_PY_MAX_TOKENS` (default 16384). |
| AgentRuntime pod stays `0/2` for 2+ minutes after wake; logs cycle through `[mcp-bootstrap] connect piece_microsoft-* failed: unhandled errors in a TaskGroup` every 30s | Agent has `mcpConnectionMode: "auto"` and empty `mcpServers`; `resolveAgentConfigMcpForProject` expanded all project `mcp_connection` rows; each piece KService is at `replicas=0` and serially cold-starts | Set `mcpConnectionMode: "explicit"` on the agent, force registry-sync, recycle the pod. CR's `mcpServers` will go to `[]` and the pod boots in <30s. Project-using agents are unaffected. |

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

### Replay chatter (false alarms)

| Symptom | Why it's normal |
| --- | --- |
| Orchestrator logs `Ignoring unexpected taskCompleted event with ID = N` | durabletask-worker emits this during every `call_child_workflow` replay cycle while the child runs. Not a stuck signal. |
| Orchestrator logs `Orchestrator yielded with 1 task(s) and 0 event(s) outstanding` repeatedly | Normal during a long child workflow. Becomes a real signal only if it persists >5 min AND the AgentRuntime phase is wrong AND placement is flapping in target daprd logs. |

Don't intervene on replay chatter alone — check AgentRuntime phase + `sessions.updated_at` first.

### Workspace / sandbox

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Live-preview proxy returns 404 "Retained sandbox not found for this execution" | `workflow_workspace_sessions` row missing or `status='cleaned'` | Check `with.keepAfterRun: true` is set on the `workspace/*` step. The `_should_cleanup_workspaces` gate (`sw_workflow.py:130-180`) reads the spec — the flag MUST be in the spec, not just task outputs. Manually revive: `UPDATE workflow_workspace_sessions SET status='active' WHERE workflow_execution_id=<id>`. |
| Tool fails with `[Errno 2] No such file or directory: '/root/.config/openshell/active_gateway'` | `seed-openshell-config` init container didn't run | Re-publish the agent to rebuild its Deployment with the current pod shape. The `openshell-sandbox-dapr-webhook` namespaceSelector must include `workflow-builder`. |
| SWE-bench (or any benchmark) child workflow fails with `Request to openshell-agent-runtime (workspace/profile) timed out after 300000ms` — esp. under burst load | function-router image pre-dates workflow-builder commit `2a68cca7` (2026-05-09); `MAX_WORKSPACE_PROFILE_TIMEOUT_MS` was hard-coded to `300_000` | Roll dev `function-router` to `ghcr.io/pittampalliorg/function-router:git-2a68cca7c63b…` or newer. The cap is now an env var (default 1h). See `shared-skills/evaluations/references/swebench-concurrency.md` § Function-Router Workspace/Profile Timeout. |
| `browser/validate` fails with `Dev server did not become ready` even though the server log shows it bound successfully (e.g. `Serving HTTP on 0.0.0.0 port 8080 ...`) | The runtime allocates its own port via `_allocate_local_port()` and probes that port; user's `devServerCommand` is binding a different port (hardcoded 3009/8080/etc.) | Omit `devServerCommand` (the runtime's default `_local_devserver_runner` auto-detects index.html / package.json) OR use the `{port}` / `${PORT}` / `$PORT` placeholder. Bind to `0.0.0.0`, not `127.0.0.1`. See `references/action-catalog.md` § `browser/validate`. |

### Daprd boot crashes (per-agent pod won't start)

| Crash message | Likely cause | Fix |
| --- | --- | --- |
| `detected duplicate actor state store` | Pod sees more than one Component with `actorStateStore=true`, or Component scopes drifted | Verify `workflowstatestore` is scoped only to parent workflow apps and `dapr-agent-py-statestore` includes the per-agent app id. The controller should patch scopes on AgentRuntime create/update; do not create per-agent state stores. See `references/cluster-topology.md` § Dapr Component scoping. |
| `no X509 SVID available / failed to get configuration` | The `dapr.io/config`-referenced Configuration is missing in pod's namespace | Ensure `Configuration/openshell-sandbox-dapr` exists in `workflow-builder` (file: `packages/components/active-development/manifests/workflow-builder/Configuration-openshell-sandbox-dapr.yaml`). |
| Pod has no daprd sidecar at all | Webhook didn't fire | Confirm `MutatingWebhookConfiguration/openshell-sandbox-dapr-webhook` exists and `namespaceSelector` includes `workflow-builder`. Re-publish the agent to retry the inject. |

### BFF / orchestrator connectivity

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| BFF `/api/workflows/[id]/execute` fails with `TypeError: fetch failed` + `ECONNREFUSED <orchestrator-svc-IP>:8080` | Orchestrator pod CrashLoopBackOff | `kubectl -n workflow-builder logs deploy/workflow-orchestrator -c workflow-orchestrator --previous`. Common cause: orchestrator image pre-dates an `activities/<x>.py` file referenced by `sw_workflow.py`, raising `ModuleNotFoundError`. Rebuild from a commit that includes the file. |
| Workflow won't start; UI shows generic "execution failed" | Orchestrator parse error swallowed at SSE | `kubectl -n workflow-builder logs deploy/workflow-orchestrator --tail=300 | grep -E 'ERROR|Removed|Unknown'`. |
| SWE-bench run creates no sessions and token counts stay zero | Parent orchestrator readiness gate is closed, preflight has not finished, or no OpenShell pod was admitted | Check in order: `benchmark_runs.status`, preflight logs/builds, `workflow-orchestrator /readyz`, `benchmark_run_instances.dapr_instance_id`, OpenShell pods, `sessions.id`, then `agent.llm_usage`. MLflow `[mlflow]` timeouts are not a start blocker when `MLFLOW_FAILURE_MODE=best_effort`. |
| `workflow-orchestrator /readyz` shows `workflowConnectedWorkers=0` or sidecar logs mention workflow actor registration errors | Stale `daprd` sidecar after Dapr control-plane churn or partial container restart | Wait for the orchestrator watchdog to self-delete the pod, or delete the `workflow-orchestrator` pod if no active run depends on it. Full pod replacement is required so the `daprd` sidecar restarts too. |
| ArgoCD says `dev-workflow-orchestrator` is Synced but the live Deployment still runs the previous image | Argo application cache/source refresh lag | Hard-refresh the app: `kubectl --kubeconfig ~/.kube/hub-config -n argocd annotate app dev-workflow-orchestrator argocd.argoproj.io/refresh=hard --overwrite`, then re-check the Deployment image. |

### DB scoping

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Workflow inserted but doesn't appear in any workspace | `project_id` is NULL | `SELECT id, name, project_id FROM workflows WHERE id='<id>';`. Backfill: `UPDATE workflows SET project_id='<real-project-id>' WHERE id='<id>';`. Migration 0040 made the column NOT NULL — new inserts can't repeat this, but old rows might. |
| Workflow visible to one user, not their teammate | `project_members` missing the teammate | `SELECT * FROM project_members WHERE project_id='<id>';` then INSERT a row with `role` ∈ ADMIN/EDITOR/OPERATOR/VIEWER. |
| Sessions show raw IDs instead of agent labels | Sessions point at workflow-ephemeral agents | Expected — `/api/agents` filters those out. As of 2026-04-21 `listSessions` LEFT JOINs `agents` and returns `agentName/agentSlug/agentAvatar/agentEphemeral` so the row renders ⚡ + "eph". |

### MLflow trace state (cosmetic-only)

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| MLflow Traces UI shows `IN_PROGRESS` on a workflow that finished long ago | **Known systemic limit** in MLflow OSS 3.10.x. Our orchestrator's Python spans all carry a `parent_id` pointing at `durabletask-go` engine spans that MLflow's OTLP receiver drops (no `gen_ai.*` attrs), so MLflow's `_on_end_impl` never sees a root span to flip state to OK. Affects ~92% of runs (11 of 12 recent async-coding traces; same for browserstation demos). | **No clean client-side fix exists.** MLflow REST API has no state-update endpoint: `StartTraceV3` errors with `"Dependency rule on column 'trace_info.request_id' tried to blank-out primary key column 'trace_tags.request_id'"` when the trace row already has tags; `PATCH/PUT/POST` on `/api/3.0/mlflow/traces/{id}` and `/state` and `/info` and `:end` all return 404/405. Spans + tags + duration are all queryable; only the state badge is wrong. Search filters (`tag.workflow.execution.id = X`, `tag.session.id = Y`, `tag.mlflow.traceName = ...`) work normally. Real fixes: (a) CronJob in mlflow ns doing `UPDATE trace_info SET state='OK' WHERE state='IN_PROGRESS' AND request_time < now() - interval '10 min'` (~1h work); (b) Tailscale egress for mlflow-postgres + inline SQL from orchestrator (~1d). REST-API attempt was tried and reverted (workflow-builder commits `c36747e7` → `854f0828`, 2026-05-12). |

## Diagnostic command cheat sheet

```bash
# Orchestrator parse + dispatch
kubectl -n workflow-builder logs deploy/workflow-orchestrator -c workflow-orchestrator --tail=200 -f

# Per-agent runtime pod
kubectl -n workflow-builder get agentruntime
kubectl -n workflow-builder logs deploy/agent-runtime-<slug> -c dapr-agent-py --tail=200 -f

# MCP bootstrap on a per-agent runtime
kubectl -n workflow-builder get deploy agent-runtime-<slug> -o json | \
  jq -r '.spec.template.spec.containers[] | select(.name=="dapr-agent-py") | .env[] | select(.name=="DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON").value' | jq .
kubectl -n workflow-builder logs deploy/agent-runtime-<slug> -c dapr-agent-py --tail=250 | \
  rg 'mcp-bootstrap|Loaded|Registered|Missing credentials'

# Daprd boot
kubectl -n workflow-builder logs <pod> -c daprd --tail=100

# Wake an agent runtime manually
kubectl -n workflow-builder annotate agentruntime <slug> agents.x-k8s.io/wake="$(date -Iseconds)" --overwrite

# Restart Kopf controller (recovers dropped annotation watchers)
kubectl -n workflow-builder rollout restart deploy/agent-runtime-controller

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
