---
name: workflow-builder
description: "Author, save, run, inspect, or debug Workflow Builder dynamic-script workflows and durable agent sessions. Use for Workflow MCP workspace auth, live traces, sealed execution evidence, script primitives and validation, saved agents, runtime-registry routing, structured output, action catalog calls, MCP connections, Prompt Workbench, goal loops, artifacts, lifecycle stop/purge, Sandbox/Kueue startup, Dapr sidecars, and failed executions. Use preview-environments for preview vClusters and dapr-agents-workflow for standalone upstream Python apps."
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

Dev-environment workflows (`preview-development-lifecycle`,
`microservice-dev-session`) launch ONLY via the `start_dev_environment_session`
tool — `execute_workflow` and `run_workflow_script` reject them with HTTP 409
("requires the target-aware Dev launcher").

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

## Native CLI Runtime Contract

`claude-code-cli`, `codex-cli`, and other `interactive-cli` runtimes run the
official interactive binary inside Herdr's PTY for both attached sessions and
workflow auto-turns. The runtime registry must declare
`capabilities.cliExecutionMode: native-tui`; the workflow bridge rejects an
interactive runtime without that declaration or its registry-owned
`cliAdapter`.

- Preserve user-scoped subscription OAuth delivery through `cliAuth` and the
  session Secret path. Do not replace it with a provider API key, SDK, print
  mode, `codex exec`, or another noninteractive subprocess.
- Workflow kickoff is accepted only after the native composer reports a
  positive receipt. Hook/transcript events, especially `turn.completed`, own
  completion and output; terminal pixels are diagnostic evidence only.
- A missing kickoff receipt fails the child with
  `native_tui_kickoff_not_accepted`. Dynamic-script `agent()` resolves errored
  journal entries to `null`, so required calls must check and reject `null`.
- `CLI_AGENT_WORKFLOW_BATCH=0` exists only as compatibility configuration for
  older images. Current runtime source has no workflow batch branch.

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
| Query terminal/post-teardown evidence | `docs/execution-evidence.md` and Workflow MCP execution-evidence tools            |
| Inspect or restore run code      | `list_code_checkpoints`, `get_checkpoint_diff`, `restore_checkpoint`                    |
| Resume or fork a run             | `resume_workflow_execution` and `docs/dynamic-script-workflows.md`                      |
| Promote a run's code to a PR     | `promote_run_to_pr`                                                                     |
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
- Durable evidence retains prompt text and tool inputs/outputs. Its sanitizer
  masks credential-shaped fields and embedded credential values; do not
  implement or describe a blanket prompt/tool-content redaction policy.
- `workflowstatestore` is the sole actor/workflow store. Agent application state
  is separate and must remain non-actor state.
- Nix-managed Codex runs Workflow MCP through a local STDIO proxy. Codex must
  explicitly forward the available 1Password authentication path
  (`OP_SERVICE_ACCOUNT_TOKEN` or `OP_BIOMETRIC_UNLOCK_ENABLED`) and the
  desktop IPC/display variables needed by biometric unlock, plus the supported
  `WFB_*` overrides, to that launcher. On NixOS the launcher must prefer
  `/run/wrappers/bin/op` so 1Password desktop integration sees the security
  wrapper; the direct store binary is only the headless fallback. The launcher
  resolves the narrower workspace key and unsets the 1Password, desktop
  IPC/display, and raw `WFB_API_KEY` variables before starting `mcp-remote`.
  `Auth: Unsupported` is expected for this STDIO entry;
  `Tools: (none)` together with a pre-initialize exit means launcher startup
  failed, not that the Workflow MCP server has no tools.
- `stop_workflow_execution` exists on the Workflow MCP server (request/confirm,
  fail-closed 409 when unconfirmed). If a session's tool list lacks a tool the
  server should have, RECONNECT the MCP client — a list fetched before an image
  roll reads as "tool missing" and has twice sent operators to the UI needlessly.
- A terminal execution row is NOT permission to reuse its durable instance id.
  When Dapr reports the instance `RUNNING`/`PENDING`/`SUSPENDED` while the row
  reads terminal, the orchestrator refuses terminate+purge-for-reuse and the
  start returns HTTP 409 `instance_conflict_live` (the row is left alone, not
  marked start-failed). Investigate the divergence;
  `WORKFLOW_ALLOW_DESTRUCTIVE_ID_REUSE=true` restores the legacy destructive
  self-heal and exists as a roll-back lever, not as a way past the error.
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
3. While the run is active, drill down narrowly with `trace_search_spans`,
   `trace_get_span`, and
   `trace_get_logs`. Use returned cursors rather than requesting an unbounded
   trace.
4. For a terminal or post-teardown run, allow the telemetry grace and use
   `list_execution_evidence` -> `get_execution_evidence` -> one bounded
   `get_execution_evidence_part` or
   `query_execution_evidence_telemetry`. A stable evidence key, not a preview
   name, is the durable identity.
5. For model evidence, call `trace_get_llm_turn` with exactly one of `spanId`
   or `sessionId`. For browser evidence, call
   `trace_get_browser_screenshot` with an execution-bound storage reference;
   it returns native MCP image content for vision analysis.
6. Compare the MCP evidence with the saved workflow engine, script, metadata,
   validation result, durable instance, current node, and replay journal.
7. Verify saved-agent version, runtime-registry resolution, effective model
   config, MCP/tool config, session events, usage, artifacts, and terminal
   status.
8. Only then inspect Kueue Workload, Sandbox, pod scheduling, init containers,
   orchestrator/runtime logs, and both app and `daprd` containers when the
   bounded product evidence identifies a runtime gap.
9. Confirm the same result through the user-facing API/UI state.

A `running` execution row is a PROJECTION, not the authority — the durable
runtime is. When a row looks stuck, compare it against the orchestrator's
`/api/v2/workflows/<instanceId>/status`: `FAILED`/`COMPLETED`/`UNKNOWN` there
with `running` in the row means the terminal-status write was lost, and the
reconciler's execution-liveness lane repairs it within a tick (watch
`executionLivenessScanned`/`executionLivenessRepaired` in the
`[session-reconciler] tick:` log line). A row with a stop intent is owned by
the stop lane and is deliberately not touched.

`runtimeStatus` alone is NOT the outcome. A workflow that RETURNS a failure
payload is `COMPLETED` to Dapr, so any repair keyed on the Dapr status writes
`success` over a real failure. The orchestrator therefore stamps a terminal
outcome envelope — `customStatus.terminal` = `{outcome, error, source}`, outcome
one of `success`/`error`/`cancelled` — before the terminal persist, and mirrors
it as `terminalOutcome` in the return value. The status endpoint passes
`customStatus` through, and both the reconciler and the read-model refresh
consult the envelope before any legacy mapping. Read the envelope, not the
status, when judging whether a run succeeded. A COMPLETED repair logged as
`unaudited-legacy` means NO envelope was found and the recorded outcome is
unproven — treat it as a finding, not a repair.

Terminal projection writes are at-least-once: the persist activity re-raises
under a retry policy, and a write still failing after retries is logged loudly
and never flips the workflow itself FAILED. So a lost projection surfaces in
orchestrator logs plus a divergent row, not as a failed workflow.

A row with a NULL `dapr_instance_id` was never scheduled. The start-orphan
sub-lane brands those `error` / `start_orphaned` once they age past
`EXECUTION_START_ORPHANED_STALE_SECONDS` (default 900, floor 600), behind a
fence still requiring a NULL instance id and only after probing the
deterministic candidate instance id: an instance the runtime knows means the
attach write was lost rather than the schedule, so the row is skipped
(`skip_unverified`). `team-run` engine containers and `host` dispatch-backend
rows hold NULL instance ids BY DESIGN and are excluded — never brand or
hand-fix one. The lane carries its own `EXECUTION_START_ORPHANED_DRY_RUN` soak
gate, default TRUE, so it stays observe-only even though the global reconciler
dry run is off — and an observe-only decision still increments
`executionLivenessRepaired`, so check `decisions[].outcome` for
`repaired_start_orphaned` with `executed: false` before believing a repair
happened.

Normal replay messages are not proof of a hang. Prove lack of progress with
durable state, timestamps, queue admission, and runtime logs before intervening.

To see what code a run actually changed, call `list_code_checkpoints` for the
programmatic equivalent of the run's Changes tab (one durable checkpoint per
code-mutating tool call), then `get_checkpoint_diff` for a checkpoint's patch.
Reach for these over the Changes UI when diagnosing headlessly or when you need
the exact diff a single step produced.

## Code Checkpoints, Replay, and Promotion

- A checkpoint is `durable` only once its commit is pushed to the in-cluster
  checkpoint remote (`remoteStatus` `pushed`). Only durable checkpoints can be
  restored.
- `restore_checkpoint` is destructive: it hard-resets the target live sandbox's
  workspace to the checkpoint's commit. Pass the intended `sandboxName`.
- `resume_workflow_execution` starts a NEW run, never mutating the source. For an
  SW-graph run it forks from a node (`fromNodeId`, or the in-flight node when
  omitted). For a dynamic-script run it is resume-after-edit: the source must be
  terminal, the current (possibly edited) script re-runs, unchanged calls resolve
  from the imported done-call journal, and only changed calls re-dispatch — use
  it to fix a step and continue or to iterate a later step without paying for the
  prefix. Read the returned new `executionId`.
- `promote_run_to_pr` opens a REAL GitHub PR (or pushes a branch). With no
  `artifactId` it promotes the single unpromoted code version, or returns the
  version list when the choice is ambiguous; re-call with a chosen `artifactId`.
  Strict preview captures promote through preview continuation, not here.
- Checkpoint reads need `workflow:read`; restore, resume, and promote need
  `workflow:execute`.

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
- Terminal preview runs have a complete or explicit lost durable evidence
  receipt before teardown is treated as finished.
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
- `docs/execution-evidence.md`
- `services/shared/runtime-registry.json`
- `services/workflow-orchestrator/`
- `services/workflow-mcp-server/`
- `src/lib/server/application/`
- `src/lib/server/lifecycle/`
- `src/lib/server/agents/`
- `src/lib/server/mcp-connections.ts`
- `src/lib/server/goals/`
