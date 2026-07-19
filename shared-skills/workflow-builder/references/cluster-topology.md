# Cluster Topology

Scope: the K8s mental model needed to reason about *where* a workflow runs and *why* a run might be stuck. Not GitOps — for image promotion / ArgoCD / Tailscale, use the `gitops` skill. Source: workflow-builder CLAUDE.md + stacks repo manifests in `packages/components/workloads/workflow-builder/manifests/` and `packages/base/manifests/openshell/`.

## One-paragraph mental model

The SvelteKit BFF saves a dynamic script and starts the Python Dapr
`dynamic_script_workflow_v1` pump. The zero-secret `script-evaluator` plans
journaled agent/action/event/timer calls; the pump dispatches them through
registered activities/children. `agent()` resolves a runtime through
`services/shared/runtime-registry.json` and calls `session_workflow` on a
per-session Kueue-admitted Sandbox app id. `action()` uses the deterministic
function-router/piece-runtime path and reference-forwards connection ids, not
plaintext credentials. Legacy SW rows still run through `sw_workflow_v1` and
`durable/run`, but they are not the new authoring lane. Durable state remains in
the single namespace-wide `workflowstatestore`; `dapr-agent-py-statestore` is
non-actor application state.

## Pods that matter

All in `workflow-builder` namespace unless noted.

| Pod | Role | Port | Source manifest |
| --- | --- | --- | --- |
| `workflow-builder` | SvelteKit BFF + UI | 3000 | `packages/components/workloads/workflow-builder/manifests/Deployment-workflow-builder.yaml` |
| `workflow-orchestrator` | Python Dapr orchestrator | 8080 | `packages/components/workloads/workflow-orchestrator/manifests/Deployment-workflow-orchestrator.yaml` |
| `swebench-coordinator` | SWE-bench Dapr coordinator + evaluator Job launcher (current operator-visible SWE-bench path; eval TaskRuns now Kueue-admitted) | 8080 | `packages/components/workloads/swebench-coordinator/manifests/` |
| per-session **Sandbox** pod (`agent-sandbox`) | Ephemeral durable-agent runtime, one per session; runs `session_workflow`. Differs only by container image (`dapr-agent-py` / `claude-agent-py` / `adk-agent-py`). | n/a (Dapr-app-id routed) | Created on demand from a `Sandbox` CR (upstream `kubernetes-sigs/agent-sandbox`), Kueue-admitted, self-reaped on session end; image resolved by the BFF from `AGENT_RUNTIME_*_DEFAULT_IMAGE` env |
| `browser-use-agent` warm-pool pod | Browser/vision runtime; uses a `SandboxWarmPool` carve-out to absorb Chromium boot latency | n/a (Dapr-app-id routed) | `SandboxWarmPool` (upstream agent-sandbox) |
| `function-router` | Credential-reference forwarder + Knative proxy | 8080 | `packages/components/workloads/function-router/manifests/` |
| `fn-system` | system/* slugs | 8080 | `fn-system` app |
| per-piece `ap-<piece>-service` (piece-runtime) | Converged AP piece-runtime: deterministic activities (`/execute`) + MCP tools (`/mcp`) + canvas options (`/options`) + `/health`. ONE `piece-mcp-server` image per piece (`PIECE_NAME` env), Knative scale-to-zero. ~47 services, on-demand by the reconciler. | n/a (KService) | `piece-mcp-server` image; reconciled by `activepieces-mcps` |
| `activepieces-mcps` | All-catalog reconciler (every 2 min): provisions every catalog piece's `ap-<piece>-service` from enabled `mcp_connection` rows + pinned pieces, plus `activepieces-mcp-catalog` ConfigMap | n/a | `packages/components/workloads/activepieces-mcps/manifests/` |
| `openshell-agent-runtime` | workspace/* + browser/* + openshell/* slugs | 8080 | `openshell-agent-runtime` app |
| `dapr-agent-py` (legacy static Deployment, `replicas:4`) | Survives ONLY for the `openshell-durable-agent` enum path + the `agent-runtime-pool-coding` benchmark pool. Not the per-session dispatch path. | n/a | `dapr-agent-py` app (one Deployment) |
| `claude-agent-py` | Claude Agent SDK runtime, peer to `dapr-agent-py` for coding/SWE-bench/3B1B agent turns. NO dedicated Deployment — ships via the `AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE` pin + a ConfigMap, launched as a per-session Sandbox. | n/a (Dapr-app-id routed) | `services/claude-agent-py`; image/env pinned in stacks workflow-builder manifests |
| `mcp-gateway` | Hosted MCP gateway | 8080 | `mcp-gateway` app |
| `postgresql` | Workflow DB | 5432 | `StatefulSet-postgresql.yaml` |

## The agent-sandbox runtime model (replaces the retired AgentRuntime CRD)

> **Retired:** the custom `AgentRuntime` CRD, the Kopf `agent-runtime-controller`, `src/lib/server/agents/registry-sync.ts` upserting per-agent CRs, and per-agent wake/idle annotations are GONE. There is no `Deployment/agent-runtime-<slug>` per published agent anymore. Anything describing those is stale.

The runtime catalog is declared in the **runtime registry** — canonical `services/shared/runtime-registry.json`, regenerated into two build-context-local copies by `scripts/sync-runtime-registry.mjs` (the Python orchestrator reads `services/workflow-orchestrator/core/runtime_registry.json`; the TS BFF reads `src/lib/server/agents/runtime-registry.data.json`), drift-guarded by tests + `--check`. Each runtime entry carries identity (`appIdConfigKey`, `instancePrefix`, `mainContainerName`, `imageEnvKey`, `agentMetadataFramework`, `benchmarkEligible`) and a capability descriptor (`durabilityGranularity`, `supportsMcp`, `supportsHooks`, `supportsPermissionGating`, `incrementalEvents`, `ownsSandbox`, `requiresWarmPool`, `requiresBrowserSidecars`, `multiProvider`, `supportedProviders`). The orchestrator's `_resolve_native_agent_runtime` is a thin shim over `runtime_registry.resolve()`; the BFF reads the registry for container allowlists, image override, the benchmark list, the default-runtime fallback, and the agent-framework label.

When the orchestrator dispatches a `durable/run` step, the BFF launches a **per-session ephemeral Sandbox pod** (upstream `kubernetes-sigs/agent-sandbox`, Kueue-admitted) that differs from the other runtimes ONLY by container image. The pod shape:

- **`seed-openshell-config` init container** — writes `${XDG_CONFIG_HOME}/openshell/active_gateway` + mTLS certs from the `openshell-client-tls` + `openshell-server-client-ca` Secrets. Without this, OpenShell-backed tools (`write_file`, `bash_run`, `execute_command`) crash with ENOENT.
- **Runtime main container** — runs the `session_workflow` for the selected runtime image (`dapr-agent-py` / `claude-agent-py` / `adk-agent-py`). Some agent-host containers still carry legacy names in labels or pod/container names, so check run metadata before concluding the wrong runtime was used. MCP-capable runtimes read bootstrap MCP server JSON from env (`DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`); those entries may include project-resolved ActivePieces piece MCP servers with `X-Connection-External-Id` headers.
- **`daprd` sidecar** — injected by the `openshell-sandbox-dapr-webhook` MutatingWebhookConfiguration (`packages/base/manifests/openshell/MutatingWebhookConfiguration-openshell-sandbox-dapr-webhook.yaml`). Its `namespaceSelector` includes both `openshell` and `workflow-builder`.
- *(Optional)* **`chromium` + `playwright-mcp` browser sidecars** when the agent has a Playwright MCP preset (auto-rewritten — see `references/agent-task.md`).

### Lifecycle & scaling

- Non-browser runtimes (`dapr-agent-py` / `claude-agent-py` / `adk-agent-py`) are launched **per session** as a Kueue-admitted Sandbox pod and **self-reap on session end** — no per-agent Deployment, no scale-to-0, no wake annotation, no `idle_reaper`.
- `browser-use-agent` uses a dedicated `SandboxWarmPool` carve-out so Chromium boot latency is pre-paid; pods are drawn from the warm pool rather than cold-started per session.
- A legacy static `dapr-agent-py` Deployment (`replicas:4`) survives ONLY for the `openshell-durable-agent` enum + the `agent-runtime-pool-coding` benchmark pool.
- A **swap-safety gate** (`src/lib/server/agents/swap-safety.ts`, wired into `src/lib/server/sessions/spawn.ts`) derives an agent's required capabilities from its `agentConfig` and compares them against the target runtime's declared registry capabilities → `{decision: allow|warn|reject, drops[]}`. MCP-loss + provider-mismatch are REJECT-class; hooks/plugins/permission/durability downgrades are WARN-class. It is WARN-FIRST — it only hard-rejects when `AGENT_RUNTIME_REJECT_LOSSY_SWAP=true`.
- Cross-namespace dispatch is NOT supported — Dapr workflow placement only resolves intra-namespace. Session Sandbox pods MUST colocate with the orchestrator (`workflow-builder` ns).

## Dapr Component scoping (the invariant that bites)

A Dapr sidecar refuses to start if it sees more than one Component with `actorStateStore=true`. The current architecture uses centralized namespace-wide state stores:

| Component | actorStateStore | Scopes | Used by | File |
| --- | --- | --- | --- | --- |
| `workflowstatestore` | true | unscoped in `workflow-builder` | Parent workflow history, child agent/session workflow history, timers, reminders, activity bookkeeping | `Component-workflowstatestore.yaml` |
| `dapr-agent-py-statestore` | false | unscoped in `workflow-builder` | Agent application state APIs and task-output state, not Dapr workflow actor state | `Component-dapr-agent-py-statestore.yaml` |
| `agent-workflow` | false | legacy openshell-durable-agent / vanilla-durable-agent only | Legacy non-actor state component | `Component-agent-workflow.yaml` |

Do not create per-agent Components as a workaround. If daprd crashes with actor-store errors, check that no legacy Component was made visible as `actorStateStore=true`, and that `workflowstatestore` is the only actor store in the namespace. Per-session Kueue agent hosts use unique app IDs, so component scope mutation is intentionally avoided.

## Dapr Configuration

The `openshell-sandbox-dapr` `Configuration` object MUST exist in the pod's namespace — daprd reads it for trace exporter config + log level + mTLS settings. It lives at `packages/components/workloads/workflow-builder/manifests/Configuration-openshell-sandbox-dapr.yaml`. If missing, daprd crashes with `no X509 SVID available / failed to get configuration`.

## Dapr Sidecar Readiness

Pods with Dapr injection have two relevant health surfaces:

- App container readiness, e.g. `GET /healthz` or `GET /api/ready`.
- `daprd` readiness, e.g. `GET http://127.0.0.1:3501/v1.0/healthz` from inside the pod.

If a Deployment shows `1/1` replicas unavailable or a pod shows `1/2 Running`, check container statuses before touching app code:

```bash
kubectl get pod -n workflow-builder <pod> \
  -o jsonpath='{range .status.containerStatuses[*]}{.name} ready={.ready} restarts={.restartCount}{"\n"}{end}'
kubectl describe pod -n workflow-builder <pod> | rg -n 'Readiness|Unhealthy|daprd|Events'
kubectl logs -n workflow-builder <pod> -c daprd --tail=200
```

Known stale-sidecar pattern: Dapr placement/scheduler restarts or certificate churn can leave workflow-enabled sidecars alive but unhealthy. The app container remains ready and `3500/v1.0/metadata` may still return actors/components, but `3501/v1.0/healthz` returns `ERR_HEALTH_NOT_READY` for `grpc-api-server` and/or `grpc-internal-server`; logs may show `Actor runtime shutting down`, `Placement client shutting down`, or `Workflow engine stopped`. Once `dapr-system` control-plane pods are healthy, recycle only the affected Deployment (`kubectl rollout restart deploy/<name> -n workflow-builder`) and verify `3501/v1.0/healthz` returns `204`.

For the operational runbook and verification sequence, use the gitops skill: `runbooks/debug-dapr-sidecar-stale-readiness.md`.

## Function-router routing

function-router consults the `function-registry` ConfigMap (`packages/components/workloads/function-router/manifests/ConfigMap-function-registry.yaml`) on every request to map slug → target service URL. The ConfigMap is **authoritative** (overrides built-in fallback registry — see `services/function-router/src/core/registry.ts::loadRegistry`). The `_default` entry is `{type: activepieces}`: for an AP slug, function-router computes the per-piece `ap-<piece>-service` URL (not a monolith) and forwards `X-Connection-External-Id` only — it never fetches plaintext. Those per-piece piece-runtime Knative services are created on-demand by the all-catalog `activepieces-mcps` reconciler, not by function-router.

To add a new slug routing entry, edit the ConfigMap in the stacks repo via GitOps (don't direct-patch the cluster — see `gitops` skill).

## Workflow → Session bridge

Every `durable/run` step goes through a session bridge so workflow-driven runs appear in the same `/sessions/[id]` UI as direct sessions. The structural invariant (replaced the old `WORKFLOW_USE_SESSIONS` flag):

1. Orchestrator yields `spawn_session_for_workflow` activity → POSTs to BFF `/api/internal/sessions/ensure-for-workflow`.
2. BFF rewrites `agentConfig.mcpServers` (Playwright sidecar rewrite + project MCP resolution), runs the swap-safety gate, finds-or-creates the `sessions` row keyed by `child_instance_id = <exec>__<kind>__<node>__run__<index>`, launches the per-session Sandbox pod (Kueue-admitted), returns `{sessionId, agentId, agentVersion, childInput, reused}`.
3. Orchestrator yields `ctx.call_child_workflow("session_workflow", input=childInput, instance_id=child_instance_id, app_id=target_app_id)`.
4. `session_workflow` runs on the per-session Sandbox pod with `autoTerminateAfterEndTurn: true` — one turn, emits `session.status_idle{end_turn}` + `session.status_terminated`, returns; the Sandbox self-reaps.
5. Parent resumes; final output persists to `workflow_executions.output`.

## Runtime proof checklist

When the question is "did this run use Claude or the right container?", collect these before changing manifests:

- `benchmark_runs.agent_runtime`, `agent_runtime_app_id`, and `model_name_or_path` for SWE-bench.
- `benchmark_run_instances.trace_id`, `workflow_execution_id`, `session_id`, `model_patch`, and harness outcome.
- Workflow output fields: `agentRuntime`, `agentWorkflowMode`, `runtimeSandboxName`, `outputSync.method`, `outputSync.fileCount`, and artifact ids.
- Live workflow-builder Deployment env: `AGENT_RUNTIME_DEFAULT_IMAGE`, `AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE`, `SANDBOX_TEMPLATE_IMAGES_JSON`, `OPENAI_MODEL`, and the Claude default model ConfigMap.
- The actual image on the agent-host/runtime pod. Treat a `dapr-agent` or `dapr-agent-py` sandbox/container label as weak evidence only; it may name the workspace template or a legacy/static container label.

## Image flow (read-only summary)

- `dapr-agent-py:git-<sha>` → legacy static `dapr-agent-py` + `dapr-agent-py-testing` Deployments (openshell-durable-agent enum + benchmark pool). Pinned by GitOps tag bump.
- `dapr-agent-py-sandbox:latest` → per-session `dapr-agent-py` Sandbox pods. The BFF resolves the image from `AGENT_RUNTIME_DEFAULT_IMAGE` at session-launch time (no AgentRuntime CR). Uses `imagePullPolicy: Always`, so each freshly-launched Sandbox picks up new digests.
- `dapr-agent-py-sandbox:git-<sha>` and `dapr-agent-py-testing-sandbox:git-<sha>` -> current hub-built sandbox images used by SWE-bench agent/session hosts. A `services/dapr-agent-py` source change should roll both images, and the workflow-builder BFF pod must see the matching `AGENT_RUNTIME_*_DEFAULT_IMAGE` env values before newly launched session Sandboxes are considered updated.
- `claude-agent-py-sandbox:git-<sha>` → Claude Agent SDK runtime image. The workflow-builder BFF reads `AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE` for Claude runtime launches and GitOps UI exposes `claude-agent-py-sandbox` in the workflow-builder service matrix.

A change in `services/dapr-agent-py/src/**` requires both the runtime image and sandbox image builds. A change in `services/claude-agent-py/**` requires the Claude runtime/sandbox image plus the workflow-builder BFF env pin that points at it. The current build plane is centralized on hub; see the `gitops` skill for details.

## Workflow JSON specs are NOT baked into images

The production workflow-builder Dockerfile does not make repo workflow JSON
files the runtime source of truth. Image rebuilds alone do not change saved
workflow behavior. Save the new definition through Workflow MCP, the UI, or the
authenticated BFF API; never update the workflow row directly. See
`references/authoring-recipe.md`.

## When to read the gitops skill

Anything about image promotion, ArgoCD app health, branch divergence, Tailscale, OAuth rotation, or function-registry ConfigMap deployment goes through the `gitops` skill. This skill covers only the *runtime* topology workflow authors need to know.
