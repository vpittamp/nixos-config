# Cluster Topology

Scope: the K8s mental model needed to reason about *where* a workflow runs and *why* a run might be stuck. Not GitOps — for image promotion / ArgoCD / Tailscale, use the `gitops` skill. Source: workflow-builder CLAUDE.md + stacks repo manifests in `packages/components/active-development/manifests/workflow-builder/` and `packages/base/manifests/openshell/`.

## One-paragraph mental model

The user submits a workflow → SvelteKit **workflow-builder** BFF (port 3000) writes to Postgres + tells **workflow-orchestrator** (Python Dapr, port 8080) to start an instance. The orchestrator parses the SW 1.0 spec and walks `do[]`. For every task except `durable/run`, it does a Dapr service-invoke to **function-router**, which decrypts credentials, looks up the slug in the **function-registry ConfigMap**, and forwards to fn-system / fn-activepieces / openshell-agent-runtime / code-runtime. For `durable/run`, the orchestrator resolves project MCP connections when requested, then yields `ctx.call_child_workflow("session_workflow", app_id="agent-runtime-<slug>")` — a native Dapr child workflow, not HTTP — to a **per-agent runtime pod** in the same `workflow-builder` namespace. That pod was reconciled from an `AgentRuntime` CR by the **agent-runtime-controller** (Kopf operator). It scales 0↔1 on demand. Durable state is centralized in Dapr actor state stores, scoped so each pod sees exactly one actor state store.

## Pods that matter

All in `workflow-builder` namespace unless noted.

| Pod | Role | Port | Source manifest |
| --- | --- | --- | --- |
| `workflow-builder` | SvelteKit BFF + UI | 3000 | `packages/components/active-development/manifests/workflow-builder/Deployment-workflow-builder.yaml` |
| `workflow-orchestrator` | Python Dapr orchestrator | 8080 | `packages/components/active-development/manifests/workflow-orchestrator/Deployment-workflow-orchestrator.yaml` |
| `workspace-runtime` | Durable workspace/file/command runtime; backs `workspace/*` flows | 8001 | `packages/components/active-development/manifests/workspace-runtime/` |
| `swebench-coordinator` | Legacy SWE-bench Dapr coordinator and evaluator job launcher | 8080 | `packages/components/active-development/manifests/swebench-coordinator/` |
| `agent-runtime-<slug>` | Per-agent runtime (one Deployment per published agent) | n/a (Dapr-app-id routed) | Created by `agent-runtime-controller` from `AgentRuntime` CR; image set via env var on the BFF Deployment |
| `agent-runtime-controller` | Kopf operator that reconciles AgentRuntime CRs | n/a | `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` (lives in `openshell` ns; `CONTROLLER_NAMESPACE=workflow-builder` env points it at our ns) |
| `function-router` | Sync credential broker + Knative proxy | 8080 | `packages/components/active-development/manifests/function-router/` |
| `fn-system` | system/* slugs | 8080 | `fn-system` app |
| `fn-activepieces` | AP piece executor | 8080 | `fn-activepieces` app |
| `activepieces-mcps` | Reconciles project MCP rows into AP piece MCP KServices + catalog | n/a | `packages/components/active-development/manifests/activepieces-mcps/` |
| `openshell-agent-runtime` | workspace/* + browser/* + openshell/* slugs | 8080 | `openshell-agent-runtime` app |
| `dapr-agent-py` (legacy) | Legacy shared agent pod, kept for backwards compat | n/a | `dapr-agent-py` app (one Deployment) |
| `mcp-gateway` | Hosted MCP gateway | 8080 | `mcp-gateway` app |
| `postgresql` | Workflow DB | 5432 | `StatefulSet-postgresql.yaml` |

## The per-agent runtime model

When the user publishes an agent, `src/lib/server/agents/registry-sync.ts` upserts an `AgentRuntime` CR (`agents.x-k8s.io/v1alpha1`). The controller reconciles one `Deployment/agent-runtime-<slug>` per CR with this pod shape:

- **`seed-openshell-config` init container** — writes `${XDG_CONFIG_HOME}/openshell/active_gateway` + mTLS certs from the `openshell-client-tls` + `openshell-server-client-ca` Secrets. Without this, OpenShell-backed tools (`write_file`, `bash_run`, `execute_command`) crash with ENOENT.
- **`dapr-agent-py` main container** — runs the `session_workflow` + `agent_workflow` + plugins/hooks. Reads `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON` from CR spec; those entries may include project-resolved ActivePieces piece MCP servers with `X-Connection-External-Id` headers.
- **`daprd` sidecar** — injected by the `openshell-sandbox-dapr-webhook` MutatingWebhookConfiguration (`packages/base/manifests/openshell/MutatingWebhookConfiguration-openshell-sandbox-dapr-webhook.yaml`). Its `namespaceSelector` includes both `openshell` and `workflow-builder`.
- *(Optional)* **`chromium` + `playwright-mcp` browser sidecars** when the agent has a Playwright MCP preset (auto-rewritten — see `references/agent-task.md`). Controller adds a per-agent `ClusterIP Service` (`agent-runtime-<slug>-mcp:3100`) so other pods can reach the browser endpoint.

### Scaling

- Pods default to 0 replicas.
- BFF wakes the pod on demand by writing `agents.x-k8s.io/wake` annotation on the CR → controller scales to 1, waits up to 20s for readiness.
- After `idleTtlSeconds` (default 1800; configurable via env `agentRuntimeIdleTtlSeconds`) since `lastActiveAt`, the controller's `idle_reaper` timer scales back to 0.
- Cross-namespace dispatch is NOT supported — Dapr workflow placement only resolves intra-namespace. Per-agent pods MUST colocate with the orchestrator (`workflow-builder` ns).

## Dapr Component scoping (the invariant that bites)

A Dapr sidecar refuses to start if it sees more than one Component with `actorStateStore=true`. The current architecture uses centralized state stores with narrow scopes:

| Component | actorStateStore | Scopes | Used by | File |
| --- | --- | --- | --- | --- |
| `workflowstatestore` | true | workspace-runtime, workflow-orchestrator, swebench-coordinator | Parent workflow/orchestrator history | `Component-workflowstatestore.yaml` |
| `dapr-agent-py-statestore` | true | dapr-agent-py plus `agent-runtime-<slug>` app ids enrolled by the controller | Per-agent pod durable actor state | `Component-dapr-agent-py-statestore.yaml` |
| `agent-workflow` | true | legacy openshell-durable-agent / vanilla-durable-agent (no active consumers) | n/a | `Component-agent-workflow.yaml` |

When an `AgentRuntime` is created or updated, `agent-runtime-controller` patches `dapr-agent-py-statestore.scopes` with the runtime Dapr app id. Do not create per-agent Components as a workaround. If daprd crashes with actor-store errors, check that the shared Component exists, that the controller is running, and that the app id appears exactly once in the scopes list.

## Dapr Configuration

The `openshell-sandbox-dapr` `Configuration` object MUST exist in the pod's namespace — daprd reads it for trace exporter config + log level + mTLS settings. It lives at `packages/components/active-development/manifests/workflow-builder/Configuration-openshell-sandbox-dapr.yaml`. If missing, daprd crashes with `no X509 SVID available / failed to get configuration`.

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

function-router consults the `function-registry` ConfigMap (`packages/components/active-development/manifests/function-router/ConfigMap-function-registry.yaml`) on every request to map slug → target service URL. The ConfigMap is **authoritative** (overrides built-in fallback registry — see `services/function-router/src/core/registry.ts::loadRegistry`).

To add a new slug routing entry, edit the ConfigMap in the stacks repo via GitOps (don't direct-patch the cluster — see `gitops` skill).

## Workflow → Session bridge

Every `durable/run` step goes through a session bridge so workflow-driven runs appear in the same `/sessions/[id]` UI as direct sessions. The structural invariant (replaced the old `WORKFLOW_USE_SESSIONS` flag):

1. Orchestrator yields `spawn_session_for_workflow` activity → POSTs to BFF `/api/internal/sessions/ensure-for-workflow`.
2. BFF rewrites `agentConfig.mcpServers` (Playwright sidecar rewrite + project MCP resolution), finds-or-creates the `sessions` row keyed by `child_instance_id = <exec>__<kind>__<node>__run__<index>`, wakes the per-agent pod (20s timeout), returns `{sessionId, agentId, agentVersion, childInput, reused}`.
3. Orchestrator yields `ctx.call_child_workflow("session_workflow", input=childInput, instance_id=child_instance_id, app_id=target_app_id)`.
4. `session_workflow` runs on `agent-runtime-<slug>` with `autoTerminateAfterEndTurn: true` — one turn of `agent_workflow`, emits `session.status_idle{end_turn}` + `session.status_terminated`, returns.
5. Parent resumes; final output persists to `workflow_executions.output`.

## Image flow (read-only summary)

- `dapr-agent-py:git-<sha>` → legacy `dapr-agent-py` + `dapr-agent-py-testing` Deployments. Pinned by GitOps tag bump.
- `dapr-agent-py-sandbox:latest` → per-agent runtime pods. Stamped into AgentRuntime CR `environment.imageTag` at agent-publish time. Uses `imagePullPolicy: Always`, so scaling 0→1 picks up new digests.

A change in `services/dapr-agent-py/src/**` requires both the runtime image and sandbox image builds. The current build plane is centralized on hub; see the `gitops` skill for details.

## Workflow JSON specs are NOT baked into images

The production workflow-builder Dockerfile copies `src/` and `drizzle/` only — `services/` (where workflow JSONs live in dev) is excluded. Spec changes require a DB UPSERT against the spoke's Postgres. Image rebuilds alone don't change runtime behavior. See `references/authoring-recipe.md` for the upsert path.

## When to read the gitops skill

Anything about image promotion, ArgoCD app health, branch divergence, Tailscale, OAuth rotation, or function-registry ConfigMap deployment goes through the `gitops` skill. This skill covers only the *runtime* topology workflow authors need to know.
