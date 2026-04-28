---
name: workflow-builder
description: "Author, visualize, and debug SW 1.0 workflows for the workflow-builder app. Use for agent durable/run steps, trigger schemas, jq expressions, action slugs, workflow or agent MCP connections, ActivePieces piece MCP auth, canvas JSON, DB-backed workflow rows, failed workflow runs, silent agents, Dapr workflow sidecar readiness, pod 1/2 due to daprd, and workflow-orchestrator/workspace-runtime/swebench-coordinator troubleshooting across PittampalliOrg/workflow-builder and PittampalliOrg/stacks."
---

# Workflow Builder

Author SW 1.0 workflows for the workflow-builder app, get them rendered in the canvas, and run them end-to-end. Diagnose runtime failures using the cluster topology of the per-agent runtime model, including MCP connection resolution and Dapr durability state.

## Mental model in one paragraph

A workflow is a **CNCF Serverless Workflow 1.0** document with workflow-builder extensions, stored in the `workflows` table as three JSONB columns: `spec` (the SW 1.0 doc), `nodes` + `edges` (SvelteFlow canvas representation derived from the spec). The Python `workflow-orchestrator` pod parses the spec at execution time and dispatches each task: most go through `function-router` via Dapr service-invoke, but `durable/run` agent steps are dispatched as **Dapr child workflows** to a per-agent runtime pod (`agent-runtime-<slug>`) reconciled from an `AgentRuntime` CR. Agent MCP tools come from two layers: explicit `mcpServers` in the agent/workflow config and project-level `mcp_connection` rows resolved by `mcpConnectionMode` (`auto`, `project`, `explicit`). OAuth-backed ActivePieces MCP tools pass only `X-Connection-External-Id`; credentials stay in `app_connection` storage and are decrypted by workflow-builder's internal API. The SvelteKit BFF is a UI + proxy layer; everything durable lives in Dapr. Edits to a workflow's spec are picked up at the next execution — no image rebuild required.

## When to use this skill

Trigger on any of: "build a workflow", "author a workflow", "add an agent step", "add a trigger", "make this run on a webhook", "the run failed", "the agent never starts", "the canvas is empty", "${ .trigger.x } isn't resolving", "what slugs are available", "why isn't my sandbox persisting", "why is daprd crashing", "where does my workflow run".

## Quick decision tree

| The user wants to… | Do this |
| --- | --- |
| Add an HTTP call | Copy `assets/minimal-http.workflow.json`. Read `references/sw-1.0-spec.md` for jq rules. |
| Add an agent step (call Claude/GPT in a sandbox) | Copy `assets/minimal-agent.workflow.json`. Read `references/agent-task.md`. |
| Take user input at run time | Use the `input.schema` block from `assets/trigger-schema.snippet.json`; reference fields as `${ .trigger.<name> }`. Read `references/authoring-recipe.md` § *Trigger inputs*. |
| Share a sandbox between a coding step and an agent step | Copy `assets/workspace-keepalive.workflow.json`. Read `references/agent-task.md` § *Sandbox bridging*. |
| Attach or debug MCP tools on an agent/workflow | Read `references/mcp-connections.md`, then `references/agent-task.md` § *MCP servers*. |
| Discover what `actionType` slugs exist | Call `GET /api/action-catalog` (see `references/action-catalog.md`) — don't guess. |
| Insert a finished workflow into the DB | Run `scripts/upsert-workflow.py <file.json>`. It POSTs to the BFF (which stamps `project_id`) and PUTs the `spec` column. |
| Diagnose a failed run | Read `references/troubleshooting.md` and triage by symptom (parse error / agent timeout / replay chatter / prompt-too-long / project_id NULL). |
| Debug `1/2` pods or `daprd` not ready | Read `references/cluster-topology.md` for the runtime model, then use the gitops runbook `runbooks/debug-dapr-sidecar-stale-readiness.md` for live Kubernetes triage. |
| Confirm a freshly-inserted workflow shows up + runs | Read `references/verify-in-ui.md`. |
| Understand "where does my workflow actually run?" | Read `references/cluster-topology.md`. |

## Critical gotchas (memorize these — they cost the most time)

These are the failure modes that look like obscure bugs but are actually doing-it-wrong. Each entry has the *why* so you can judge edge cases instead of robotically applying the rule.

- **jq is full-string-only.** `is_expression_string` (in `services/workflow-orchestrator/core/sw_expressions.py:43-95`) only evaluates a value if the *entire* string starts with `${` and ends with `}`. So `"${ .trigger.url }"` evaluates; `"prefix ${ .trigger.url }"` passes through as literal text. To interpolate, concat inside one expression: `"${ \"prefix \" + .trigger.url }"`.

- **Trigger context is `.trigger`, not `.input`.** `tc.task_outputs["trigger"] = {label, actionType, data: trigger_data}` — the orchestrator's expression context exposes the unwrapped data under `${ .trigger.<field> }` (see `services/workflow-orchestrator/workflows/sw_workflow.py:421-434`). `${ .input }` resolves to a different thing (per-task input).

- **Trigger schema has TWO equivalent placements.** Either top-level `spec.input.schema.document` (canonical, preferred) OR `spec.document['x-workflow-builder'].input.schema` (alternate). The spec→graph adapter normalizes both into the start node's `data.taskConfig.input` (see `src/lib/utils/spec-graph-adapter.ts:79-94`). Pick one and stick with it; when in doubt use the canonical placement.

- **Node IDs equal task names.** The key in each `do[]` entry IS the node ID in the canvas. `__start__` and `__end__` are the synthetic entry/exit nodes. The adapter uses `@serverlessworkflow/sdk::buildGraph()` so 99% of the time you should let the spec drive node generation rather than hand-author `nodes`/`edges`.

- **`durable/run` is a Dapr child workflow, not an HTTP call.** It bypasses function-router. The orchestrator yields `ctx.call_child_workflow("session_workflow", app_id="agent-runtime-<slug>")` — `agent-runtime-<slug>` is computed from `with.agentRef.id` → DB `agents.runtime_app_id` → `agent-runtime-<agent.slug>`. Missing `agentRef`/`agentSlug` falls back to legacy `dapr-agent-py`. The target pod must be in the same namespace (`workflow-builder`) — Dapr workflow sub-orchestration doesn't cross namespaces.

- **`isAgentTaskConfig` is just `call === "durable/run"`.** That's the entire check (see `src/lib/types/agent-graph.ts:401-407`). The canvas marks the node `type: "agent"` automatically. Don't worry about a strict TS body shape — both flat (`with: {agentRef, prompt, ...}`) and nested (`with: {body: {agentRef, prompt, ...}, mode, sandboxName, ...}`) are accepted at runtime.

- **File operations are slug-as-action, not `workspace/file` with an `operation` field.** Valid slugs: `workspace/read_file`, `workspace/write_file`, `workspace/edit_file`, `workspace/list_files`, `workspace/delete_file`, `workspace/mkdir`, `workspace/file_stat`. Calling `workspace/file` with `operation: "write"` returns `workspace-runtime HTTP 400: operation is required and must be one of read_file, write_file, edit_file, list_files, delete_file, mkdir, file_stat` — that error message *is* the canonical list of valid slugs.

- **`agentRef` placeholders fail the resolver if they're a jq string.** When you author `${ .trigger.agentRef }` in a workflow JSON's `durable/run.with.body.agentRef`, the BFF's `resolveSpecAgentRefs` runs at workflow-LOAD time (before the orchestrator evaluates jq). It expects `agentRef` to be an object literal with `id` or `slug`, sees the string, and throws `Task X (durable/run) is missing agentRef. All workflows must be backfilled to named agents before executing.` For evals, `service.ts` solves this with a helper `stampAgentRefIntoDurableRunSteps(spec, {id, version})` that walks the spec and replaces the placeholder with the real ref before handing it to the resolver. If you build similar dispatch glue for non-eval flows, mirror the helper — don't try to make the resolver tolerate jq strings.

- **`with.keepAfterRun: true` is required to retain a workspace sandbox.** The `_should_cleanup_workspaces` gate in `sw_workflow.py:130-180` reads the spec directly (looking for `workspace/*` steps with `with.keepAfterRun=true` OR `with.body.input.keepAfterRun=true`), not just task outputs — because openshell-agent-runtime doesn't echo the flag back. Without this flag, the live-preview proxy returns 404 "Retained sandbox not found" after the run.

- **Removed slugs raise at parse time.** `claude/run`, `openshell/run`, `openshell-langgraph/run`, `dapr-agent-py/run`, `dapr-swe/run`, and any `mastra/*` / `agent/*` legacy slug throws `Removed SW 1.0 agent action`. The orchestrator's full reject list lives in CLAUDE.md.

- **`workflows.project_id` is NOT NULL since migration 0040.** Inserts must come through the BFF (which stamps `projectId` from `locals.session.projectId`) or stamp it manually via psql. Workflows without project_id can't appear in any workspace.

- **POST `/api/workflows` does NOT write the `spec` column.** It writes `name`, `nodes`, `edges`, `engineType`, `userId`, `projectId` only (see `src/routes/api/workflows/+server.ts:34-44`). To set `spec`, follow up with `PUT /api/workflows/[workflowId]` with `body.spec`. The bundled `scripts/upsert-workflow.py` does both calls.

- **Agent statestore scopes are controller-managed now.** The Dapr Component invariant still matters: each sidecar must see exactly one `actorStateStore=true` Component. But new `agent-runtime-<slug>` app ids are enrolled by `agent-runtime-controller` through `dapr-agent-py-statestore.scopes`; do not add per-agent state stores or tell users to hand-edit scopes as the normal publish path. If daprd reports duplicate/no actor state store, verify the controller and Component scopes.

- **Project MCP connections are resolved, not copied as secrets.** `mcp_connection` rows point to server/catalog metadata and optionally `connection_external_id`; `app_connection` stores encrypted OAuth credentials. Runtime MCP calls send `X-Connection-External-Id` to `piece-mcp-server`, which decrypts through workflow-builder. Do not put OAuth tokens or decrypted credential JSON into workflow specs, agent markdown, or KService env.

- **ActivePieces piece MCP URLs should not include `:3100` through Knative.** The container listens on 3100, but workflow/agent configs should target the cluster-local KService URL such as `http://ap-microsoft-outlook-service.workflow-builder.svc.cluster.local/mcp`. Stale `:3100` URLs bypass Knative and make agents look silent.

- **MCP connection changes may require agent registry sync.** Direct workflow runs resolve project MCP at execution, but published/direct agents also carry startup MCP config in `AgentRuntime.spec.mcpServers` → `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`. After changing an agent's MCP settings, re-publish or call `/api/agents/<id>/registry/sync`, then verify the Deployment env and `[mcp-bootstrap]` logs.

- **`Ignoring unexpected taskCompleted event` is normal replay chatter, NOT stuck.** durabletask-worker emits this during every `call_child_workflow` replay cycle. Real "stuck" signals: AgentRuntime CR `phase=Sleeping` after the wake annotation was set, OR the orchestrator emitting the same `Orchestrator yielded with N task(s) and 0 event(s) outstanding` line for >5 min with placement flaps in target daprd logs. Check the AgentRuntime phase + `sessions.updated_at` *before* assuming a hang.

- **Workflow-builder dev runs via DevSpace file sync.** Don't start `pnpm dev` or spin up local containers. Code changes propagate into the running pod automatically. Trying to side-run dev servers fights the sync loop. **DevSpace pod env vars are baked at start time** — when the BFF Deployment manifest changes (e.g. `AGENT_RUNTIME_DEFAULT_IMAGE`, `SANDBOX_TEMPLATE_IMAGES_JSON`), ArgoCD updates the standard ReplicaSet but the long-lived `workflow-builder-devspace-*` pod keeps the old env. Run `devspace purge` (or delete the devspace pod) to drop the override and let the regular ArgoCD-managed pod serve traffic with fresh env.

- **Sandbox templates are looked up by name in `SANDBOX_TEMPLATE_IMAGES_JSON`.** A workflow's `workspace_profile` step takes `with.sandboxTemplate: <name>`; the BFF resolves that name against the `SANDBOX_TEMPLATE_IMAGES_JSON` env var on the workflow-builder Deployment to get the actual image (`gitea-ryzen.tail286401.ts.net/giteaadmin/openshell-sandbox-<name>:latest`). Currently registered: `dapr-agent`, `default-sandbox`, `dapr-agent-xlsx`, `xlsx`, `code-eval`. Adding a new template = add the env var entry in stacks AND build the matching `services/openshell-sandbox/environments/Dockerfile.<name>` (commit subject `environment(<name>):` triggers the env-image-build pipeline; the build doesn't push `:latest` — skopeo-retag manually after a successful build). See the gitops skill for the GitOps cadence.

- **Eval-style workflows use `taskConfig.workflowId` to load specs from DB.** When an evaluation has `taskConfig.workflowId` set, `startEvaluationRunItemWorkflow` loads that workflow row from the `workflows` table and stamps `agentRef` into `trigger.input` instead of generating a spec in TypeScript. This is the path used by HumanEval+/MBPP+/BigCodeBench (the `code-eval-item` workflow). The workflow's `durable/run` step references `${ .trigger.agentRef }` so the BFF-supplied agent substitutes at dispatch time. Operators edit the JSON + re-run `scripts/upsert-<workflow>-workflow.mjs` to roll prompt/maxTurns changes without a BFF redeploy.

- **Seed-script `${JSON.stringify(spec)}::jsonb` can double-encode.** The standard upsert pattern in `scripts/upsert-*.mjs` uses postgres-js template literals with an explicit JSON.stringify + jsonb cast. Under some conditions (notably when running through `node --input-type=module -e`) the cast produces a JSONB *string* (a quote-wrapped JSON-text scalar) instead of a JSONB *object*. Symptom: `jsonb_typeof(spec) = 'string'` and `spec->'do'` returns null. Fix: re-upsert with `sql.json(workflow.spec)` — postgres-js handles serialization correctly without the explicit `::jsonb` cast.

- **Orchestrator `wfstate_state` orphan reminders block new StartInstance calls.** The `workflowstatestore` Component is `state.postgresql v2` with `tablePrefix=wfstate_`. When a workflow is purged but its actor reminder is still in dapr-scheduler-server's ETCD, daprd retries the reminder every ~10s and logs `Unable to get data on the instance: <id>, no such instance exists`. The retry loop can serialize behind the workflow runtime's worker queue and make new `ctx.call_child_workflow` / `StartInstance` calls hit `DEADLINE_EXCEEDED` after 60s. Fix: `TRUNCATE wfstate_state` on postgresql-0 + `kubectl rollout restart deploy/workflow-orchestrator`. Note the dapr-scheduler-server ETCD entries are separate; if reminders return after restart, the scheduler pod itself may need attention. Don't reach for this fix unless you've confirmed the orphan-reminder pattern in `kubectl logs -c daprd`.

- **Dapr sidecar `1/2` can be stale after control-plane churn.** If the app container is ready but `daprd` is not, probe `http://127.0.0.1:3501/v1.0/healthz` from inside the pod and read `kubectl logs <pod> -c daprd`. A stale workflow-enabled sidecar can return `ERR_HEALTH_NOT_READY` for `grpc-api-server` / `grpc-internal-server` after placement or scheduler restarts, while `3500/v1.0/metadata` still responds. If logs show `Actor runtime shutting down` or `Workflow engine stopped`, recycle the affected Deployment after confirming the Dapr control plane is healthy. See gitops `runbooks/debug-dapr-sidecar-stale-readiness.md`.

## Reference index

Load these on demand based on what you're doing.

| Task | File |
| --- | --- |
| Authoring a spec from scratch | `references/sw-1.0-spec.md` (12 task types, jq rules, validation checklist) + `references/authoring-recipe.md` (end-to-end) |
| Adding an agent step | `references/agent-task.md` (durable/run body) + `references/cluster-topology.md` (per-agent pods) |
| Adding or debugging MCP tools/connections | `references/mcp-connections.md` (modes, project rows, ActivePieces auth, bootstrap checks) |
| Choosing the right action slug | `references/action-catalog.md` (routing table + catalog API) |
| Debugging pod placement, Dapr sidecars, or runtime topology | `references/cluster-topology.md` |
| Inspecting/editing the canvas JSON | `references/canvas-shape.md` (node + edge shapes) |
| Confirming a workflow renders + runs | `references/verify-in-ui.md` |
| Debugging a failed run | `references/troubleshooting.md` (symptom-keyed triage) |

Each reference file is focused (60–250 lines) and starts with a short scope summary. Read only what's relevant.

## Templates (assets/)

| File | Use when |
| --- | --- |
| `assets/minimal-http.workflow.json` | One `system/http-request` step. Trigger has one `url` property. Demonstrates jq full-string interpolation + `output.as`. |
| `assets/minimal-agent.workflow.json` | One `durable/run` step. Demonstrates `agentRef`, `prompt` with jq concat, `mode`, `maxTurns`, `stopCondition`. Includes the matching 3-node `nodes`/`edges` payload. |
| `assets/workspace-keepalive.workflow.json` | `workspace/profile` (`keepAfterRun: true`) → `durable/run` reading `${ .workspace_profile.sandboxName }`. The sandbox-bridging pattern. |
| `assets/trigger-schema.snippet.json` | Drop-in `input.schema.document` block with form-friendly JSON Schema patterns (uri, enum, defaults, required). |

Open the file in `assets/` first to see the exact shape before drafting your own. Edit a copy — don't modify the templates in-place.

## Scripts (scripts/)

- **`scripts/upsert-workflow.py <file.json>`** — POSTs `{name, nodes, edges, engineType}` to BFF `/api/workflows`, then PUTs the spec to `/api/workflows/[id]`. Resolves `project_id` automatically from the user's session (or `WORKFLOW_BUILDER_API_KEY` env). Falls back to a `psql` upsert when the BFF is unreachable. Prints the canvas URL. **Use this** instead of curl-ing the API by hand — every author needs the same boilerplate.

## CLIs assumed available

| Tool | Typical use |
| --- | --- |
| `kubectl` | `kubectl get agentruntime/<slug> -n workflow-builder -w` to watch a per-agent pod wake; `kubectl logs deploy/workflow-orchestrator -n workflow-builder` for parse errors |
| `psql` | Direct DB writes when the BFF isn't reachable; `SELECT id, name, project_id FROM workflows ORDER BY updated_at DESC LIMIT 5;` |
| `gh` | API spec diffs, GitHub Actions trigger context for webhook-triggered workflows |
| `dapr` | `dapr workflow get -i <instance_id> --app-id workflow-orchestrator` to inspect a stuck run |
| `scripts/upsert-workflow.py` | Insert/update a workflow by JSON file |

## Safety guards before you act

- **Don't direct-patch the `function-registry` ConfigMap** on the cluster. Slug routing changes go through GitOps (PittampalliOrg/stacks). Read the `gitops` skill for the promotion flow.
- **Don't `pnpm dev`** in the workflow-builder repo. DevSpace file sync into the running pod is the canonical dev loop.
- **Don't run a workflow with `"prefix ${ .trigger.x }"` style expressions** — they'll silently pass through as literal text. Fix the jq to a single full-string expression first.
- **Don't insert workflows directly into psql without `project_id`.** Migration 0040 made the column NOT NULL; without it the workflow can't appear in any workspace.
- **Don't create per-agent Dapr state stores.** Per-agent runtimes use the centralized `dapr-agent-py-statestore`; the controller enrolls app ids in its scopes.
- **Don't store MCP OAuth credentials in workflow JSON or agent markdown.** Bind project MCP rows to `app_connection.external_id` and let runtime requests carry `X-Connection-External-Id`.

## Authoritative source files (in the repos, not in this skill)

When you need ground truth, read these:

- workflow-builder: `CLAUDE.md`, `services/workflow-orchestrator/core/sw_types.py`, `services/workflow-orchestrator/core/sw_expressions.py`, `services/workflow-orchestrator/workflows/sw_workflow.py`, `services/workflow-orchestrator/activities/resolve_mcp_config.py`, `src/lib/utils/spec-graph-adapter.ts`, `src/lib/types/agent-graph.ts`, `src/lib/types/agents.ts`, `src/lib/server/agents/mcp-resolution.ts`, `src/lib/server/mcp-connections.ts`, `src/lib/server/mcp-catalog.ts`, `src/routes/api/workflows/+server.ts`, `src/routes/api/mcp-connections/`, `src/lib/server/action-catalog/index.ts`, `services/piece-mcp-server/src/auth-resolver.ts`, `scripts/fixtures/sample-workflows.json`
- stacks: `packages/components/active-development/manifests/workflow-builder/Component-dapr-agent-py-statestore.yaml`, `packages/components/active-development/manifests/workflow-builder/Component-workflowstatestore.yaml`, `packages/components/active-development/manifests/activepieces-mcps/`, `packages/base/manifests/knative-serving/kustomization.yaml`, `packages/components/active-development/manifests/function-router/ConfigMap-function-registry.yaml`, `packages/base/manifests/agent-sandbox-crds/CustomResourceDefinition-agentruntimes.yaml`, `packages/base/manifests/openshell/MutatingWebhookConfiguration-openshell-sandbox-dapr-webhook.yaml`

The skill summarizes — these are authoritative if anything looks contradictory.
