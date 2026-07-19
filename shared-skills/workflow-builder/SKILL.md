---
name: workflow-builder
description: "Author, save, run, inspect, or debug Workflow Builder dynamic-script workflows and durable agent sessions. Use for Workflow MCP workspace auth, script primitives and validation, saved agents, runtime-registry routing, structured output, action catalog calls, MCP connections, Prompt Workbench, goal loops, artifacts, lifecycle stop/purge, Sandbox/Kueue startup, Dapr sidecars, and failed executions. Use preview-environments for preview vClusters and dapr-agents-workflow for standalone upstream Python apps."
---

# Workflow Builder

New workflow authoring uses the `dynamic-script` engine. Treat SW 1.0 graph and
Serverless Workflow definitions as frozen compatibility formats: inspect or
migrate them when required, but do not use them for new work.

## Product Boundary

A saved dynamic workflow contains script source plus metadata. The durable
script pump evaluates deterministic primitives, journals dispatched work, and
replays from recorded results. Agent calls resolve through the runtime registry
and normally launch Kueue-admitted per-session Sandbox pods. This is different
from writing a standalone Python `dapr-agents` application; use
`dapr-agents-workflow` for that framework.

## Start From Source

```bash
WFB_ROOT=/home/vpittamp/repos/PittampalliOrg/workflow-builder/main
STACKS_ROOT=/home/vpittamp/repos/PittampalliOrg/stacks/main
git -C "$WFB_ROOT" fetch origin
git -C "$WFB_ROOT" status --short --branch
```

Use a clean worktree for edits. Resolve details from current docs, types, tests,
runtime registry, and live target instead of hard-coding a remembered model,
runtime, action slug, or user/project ID.

## Authoring Workflow

For external Workflow MCP, use this sequence:

1. `get_workflow_context`
2. `get_workflow_script_spec`
3. Draft an exported literal `meta` plus script using supported primitives.
4. `validate_workflow_script`
5. `save_workflow_script`
6. `run_workflow_script`
7. Inspect the execution and user-visible result.

Workflow operations use the workspace authenticated by the `wfb_...` key. Do
not pass a session ID as workflow ownership. Optional session attachment is
verified goal, trace, and lineage context only.

Prefer Workflow MCP or the UI. The bundled
`scripts/upsert-workflow.py <workflow.json>` is a secondary authenticated BFF
path for an access JWT or cookie; it intentionally rejects workspace keys and
has no Postgres fallback.

## Kimi K3 Contract

Resolve the current model route from source and live runtime evidence before
making a claim. When a call resolves to `kimi/kimi-k3`, require the complete
platform contract:

- `contextWindowTokens` is `1048576` and `reasoningEffort` is `max`; a lower
  per-call effort must not downgrade K3.
- Schema-bearing dynamic-script calls use K3 as the default structured-output
  route and retain the resolved structured-output mode and schema validation.
- Authentication comes only from `KIMI_API_KEY` through the owning secret and
  deployment path. Never copy the key into workflow input, agent config, logs,
  fixtures, or a preview.
- Multimodal messages keep native content arrays. Images must reach K3 as
  structured image objects containing supported base64 data URIs or uploaded
  file references, not JSON-stringified screenshot metadata.

Vision is not browser control. Use the current browser runtime or catalog
actions to navigate and capture pixels, then pass the resulting image content
to K3. Remove model-specific text-only browser workarounds only after proving
the supported control and capture path still covers the workflow.

## Task Map

| Task                             | Read or inspect                                                                        |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| Author a script                  | `docs/dynamic-script-authoring-guide.md`                                               |
| Understand execution/replay      | `docs/dynamic-script-workflows.md` and script-engine code/tests                        |
| Connect an external MCP client   | `docs/workflow-mcp-server.md`                                                          |
| Attach tools to spawned agents   | `docs/mcp-agent-workflows.md`, MCP resolution code, and piece-runtime manifests        |
| Select or swap an agent runtime  | `docs/durable-session-runtime-contract.md` and `services/shared/runtime-registry.json` |
| Stop, terminate, purge, or reset | `docs/workflow-lifecycle-termination.md` and `src/lib/server/lifecycle/`               |
| Set or debug a persistent goal   | `docs/goal-loop.md` and goal application adapters                                      |
| Produce typed run artifacts      | `docs/workflow-artifacts.md`                                                           |
| Edit prompts or presets          | Prompt Workbench components, prompt APIs, and current prompt docs                      |
| Diagnose a rollout               | Use `gitops`                                                                           |
| Develop inside a preview         | Use `preview-environments`                                                             |
| Run SWE-bench or evals           | Use `evaluations`                                                                      |

## Stable Invariants

- Script workflow bodies must be deterministic. Put network, clock, random,
  filesystem, and other side effects behind supported dispatched primitives.
- `args` is the validated runtime input. Keep `meta` literal and compatible with
  the current script spec.
- Discover action slugs through the action catalog. Do not guess or restore a
  removed action type.
- Use schema-constrained agent output when downstream script code needs a stable
  object. Preserve actual image parts for vision; stringified screenshot
  metadata is not image input.
- Runtime identity and capabilities come from the runtime registry and resolved
  saved-agent configuration, not a pod label or sandbox template name.
- Agent MCP configuration is resolved at session launch. Project access is the
  ceiling; per-agent allowed tools can only narrow it.
- OAuth and ActivePieces credentials are reference-forwarded. Plaintext must not
  enter scripts, prompts, runtime env, logs, or PRs.
- `workflowstatestore` is the sole actor/workflow store. Agent application state
  is separate and must remain non-actor state.
- All user stop paths use the Lifecycle Controller and request/confirm semantics.
  Coordinator-owned eval or benchmark instances are stopped through their run.
- Usage and goal-budget calculations depend on the normalized
  `agent.llm_usage` event contract. Diagnose raw events before changing budget
  logic.

## Diagnosis Ladder

For a failed or silent run, inspect in order:

1. Call `get_workflow_context`, then use `list_workflow_executions` only when
   the exact execution ID is unknown.
2. Call `debug_workflow_execution` for the bounded overview and server-issued
   `nextActions`, followed by `trace_get_digest` for phases, usage, critical
   path, and evidence coverage.
3. Drill down narrowly with `trace_search_spans`, `trace_get_span`, and
   `trace_get_logs`. Use returned cursors rather than requesting an unbounded
   trace.
4. For model evidence, call `trace_get_llm_turn` with exactly one of `spanId`
   or `sessionId`. For browser evidence, call
   `trace_get_browser_screenshot` with an execution-bound storage reference;
   it returns native MCP image content for vision analysis.
5. Compare the MCP evidence with the saved workflow engine, script, metadata,
   validation result, durable instance, current node, and replay journal.
6. Verify saved-agent version, runtime-registry resolution, effective model
   config, MCP/tool config, session events, usage, artifacts, and terminal
   status.
7. Only then inspect Kueue Workload, Sandbox, pod scheduling, init containers,
   orchestrator/runtime logs, and both app and `daprd` containers when the
   bounded product evidence identifies a runtime gap.
8. Confirm the same result through the user-facing API/UI state.

Normal replay messages are not proof of a hang. Prove lack of progress with
durable state, timestamps, queue admission, and runtime logs before intervening.

## Verification

A workflow change is complete when:

- Validation passes against the current script spec.
- Save and read-back return the intended engine, source, and metadata in the
  authenticated workspace.
- A fresh execution reaches the expected terminal state.
- Structured output/artifacts match their declared schemas.
- Runtime, model, MCP/tool, and workspace identity are evidenced from resolved
  state and events.
- Stop or cleanup behavior is verified when the change touches lifecycle code.
- The result appears correctly in the product surface.

## Safety Rules

- Never write workflow definitions or lifecycle state directly to Postgres.
- Never direct-patch action routing, runtime registry, Dapr Components, or MCP
  services on the cluster; deliver durable changes through source and GitOps.
- Do not deploy or restart the orchestrator while durable workflows are active;
  replay order can become incompatible with persisted history.
- Do not create per-agent or per-session actor state stores.
- Do not expose workspace keys, session assertions, OAuth tokens, or decrypted
  connection data.
- Do not use a local dev server as proof for a dev-cluster rollout.

## Canonical Sources

- `docs/dynamic-script-authoring-guide.md`
- `docs/dynamic-script-workflows.md`
- `docs/workflow-mcp-server.md`
- `docs/durable-session-runtime-contract.md`
- `docs/workflow-lifecycle-termination.md`
- `docs/goal-loop.md`
- `docs/mcp-agent-workflows.md`
- `docs/workflow-artifacts.md`
- `services/shared/runtime-registry.json`
- `services/workflow-orchestrator/`
- `services/workflow-mcp-server/`
- `src/lib/server/application/`
- `src/lib/server/lifecycle/`
- `src/lib/server/agents/`
- `src/lib/server/mcp-connections.ts`
- `src/lib/server/goals/`
