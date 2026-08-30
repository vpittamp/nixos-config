---
name: workflow-builder
description: "Author, save, run, inspect, or debug Workflow Builder dynamic-script workflows and durable agent sessions. Use for Workflow MCP workspace auth, host and preview runs, live traces, sealed evidence, script primitives, saved agents, runtime-registry routing and host modes (per-session-pod, harness), event-log context strategy, runtime admission (conformanceVerified, 409 override), structured output, action catalog, MCP connections, goals, artifacts, lifecycle stop/purge, and failed executions. Use runtime-conformance to verify a runtime, agent-session-recovery for run recovery, preview-environments for previews."
---

# Workflow Builder

New workflow authoring uses the `dynamic-script` engine. Treat SW 1.0 graph and
Serverless Workflow definitions as frozen compatibility formats: inspect or
migrate them when required, but do not use them for new work.

## Product Boundary

A saved dynamic workflow contains script source plus metadata. The durable
script pump evaluates deterministic primitives, journals dispatched work, and
replays from recorded results. Agent calls cross the runtime-registry port;
every runtime declares an explicit `hostMode`. The architecture is harness-first
brains-from-hands (`docs/agent-runtime-comparison.md`): `dapr-agent-harness` is
the only standing brain for the Dapr family, and its hands are replaceable — an
OpenShell shared workspace, or a credential-free SEA sandbox executor. CLI, CUA,
and browser adapters that cannot separate their loop from their tools are
`per-session-pod` capability exceptions, never a fallback. Standalone Python
`dapr-agents` applications are a different thing; use `dapr-agents-workflow`
for those.

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

Preview development is a privileged application path. Create an `app-live` or
`system-live` PreviewEnvironment, wait for its exact generation to become
Ready, then use `development_run_start`. The server compiles the immutable
ChangeSet, Generation, DevelopmentPlan, and DevelopmentExecution and launches
the internal `preview-host-development` workflow. Generic workflow start tools
must reject that seeded workflow; users and agents never select it directly.
Use the `preview-environments` skill for the complete lifecycle.

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

`claude-code-cli`, `codex-cli`, `kimi-code-cli`, `agy-cli`, and other
`interactive-cli` runtimes run the official vendor binary — never an SDK
reimplementation — in one of two execution modes. Do not confuse the mode with
the registry field: `capabilities.cliExecutionMode` accepts only `native-tui`
and asserts terminal-attachability, which the workflow bridge requires of every
`interactiveTerminal` runtime (agy included) alongside the registry-owned
`cliAdapter`. The per-turn mode is an adapter env switch, reported back as
`executionMode` in the start result:

- `native-tui` — the binary runs inside Herdr's PTY and prompts are injected
  into it. Default for claude, codex, and kimi; required for attached
  human sessions, which need a live terminal.
- `headless-print` — each turn is its own subprocess speaking the vendor's
  structured stdio protocol (claude `-p --output-format stream-json --verbose`,
  kimi `--prompt --output-format stream-json`, codex `exec --json`, agy
  `-p --output-format stream-json`), with turn continuity through that CLI's
  own resume handle. Default and only supported mode for `agy-cli`, whose TUI
  wedges under pty injection; opt-in for the others via
  `CLI_AGENT_{CLAUDE,KIMI,CODEX}_HEADLESS=1`. No vendor here offers ACP —
  print mode is the structured-transport equivalent.

- Preserve user-scoped subscription OAuth delivery through `cliAuth` and the
  session Secret path. Do not replace it with a provider API key or an SDK
  client. Headless print mode is NOT such a replacement: it runs the same
  binary under the same subscription token (verified live — a headless turn
  reports the subscription's own rate-limit window, not API billing), so the
  auth contract is unchanged in either execution mode.
- For `app-live` or `system-live` preview development, public profiles are
  `dapr-agent-py`, `claude-code-cli`, `codex-cli`, `kimi-code-cli`, and
  `agy-cli`. Fixture-local `*-host` values are internal adapter mappings and
  must not be exposed as caller input. `adk-agent-py` is retired.
- In a persistent CLI profile, edit the seeded host checkout and run
  `wfb-development apply`, `observe`, or `verify`. The application reconstructs
  the parent DevelopmentRun and compiler-owned adapter from session identity.
  When supervised watch mode is active, run `wfb-development await-sync` with
  `--wait --repo <edited-checkout>` and require `applied` before inspecting the
  result; the verdict covers the primary checkout and every imported repository.
  Inspect through the session's Playwright MCP. Submission and cancellation are
  parent-run gates; arbitrary event payloads and unrelated workflow actions are
  rejected. Never copy an OAuth Secret or CLI pod into the vCluster.
- Kimi Code uses device-login OAuth from the exact
  `$KIMI_CODE_HOME/credentials/kimi-code.json` file. Capture and rotate only
  that file; remove Kimi and Moonshot API-key variables before launching the
  CLI.
- Workflow kickoff is accepted only after the native composer reports a
  positive receipt. Native hooks normally own completion, failure, permission,
  and compaction events. Transcript ingestion is append-only and retains a
  durable high-water mark so a restarted wrapper does not duplicate events.
- Some CLIs can terminate a turn before emitting a stop hook. After a bounded
  grace period, a transcript terminal failure may fail the turn; a later native
  stop or failure hook cancels that fallback. Terminal pixels remain diagnostic
  evidence, never completion authority.
- Persist native transcripts with prompt, response, and tool content intact.
  Treat them as queryable execution evidence; do not apply blanket content
  redaction.
- A missing kickoff receipt fails the child with
  `native_tui_kickoff_not_accepted`. Dynamic-script `agent()` resolves errored
  journal entries to `null`, so required calls must check and reject `null`.
- `CLI_AGENT_WORKFLOW_BATCH=0` exists only as compatibility configuration for
  older images. Current runtime source has no workflow batch branch.
- Borrow Omnigent's explicit capability declarations, session-scoped homes,
  and supervised high-water transcript ingestion where they strengthen this
  adapter. Do not introduce a second lifecycle, scheduling, or durable-state
  authority beside Dapr, Kueue, the BFF, and JuiceFS.

## Host Modes and Where Tools Run

`hostMode` in `services/shared/runtime-registry.json` fixes where the loop and
the tools run (`docs/harness-host.md`):

| hostMode | Loop runs on | Tools run in | Transport | Credentials |
| --- | --- | --- | --- | --- |
| `per-session-pod` (CLI, browser, and `cua-*` adapters) | the `agent-host-<gen>` Sandbox pod | the same pod | dedicated `agent-session-*` app-id reached by pod IP on port 8002 | loop and tools share the pod's secrets |
| `harness` + `openshell-shared` (`dapr-agent-py`, the canonical default) | static-app-id `dapr-agent-harness` Deployment (2 replicas, PDB) | the per-run OpenShell workspace named by `childInput.sandboxName`; NO per-session host is built (`runtimeSandboxName` null, `runtimeHostOwned` false) | Dapr invoke to the harness | OpenShell receives no platform credentials at all |
| `harness` + `sandbox-executor` (`dapr-agent-py-local`) | the same harness Deployment | the per-session pod as a sandbox executor via `POST /executor/exec` | Dapr invoke to the harness; harness -> executor with the executor token | executor pod: no daprd, no provider keys, no `DATABASE_URL`, no `INTERNAL_API_TOKEN`; only its per-session `SANDBOX_EXECUTOR_TOKEN` from Secret `agent-host-cred-<gen>` |

- The `shared-pool` host mode, `agent-runtime-pool-*` workloads, the standing
  `dapr-agent-py` Deployment, and the `dapr-agent-py-harness` alias are RETIRED
  (wfb #1970): state naming them is rejected, never adapted.
- Transport rule (`src/lib/server/application/session-host-transport.ts`): only
  a dedicated `agent-session-*` app-id is reached by pod IP; harness hosts go
  through Dapr invoke. SEA takes `hostRole: agent-loop |
  sandbox-executor`.
- The harness resolves the executor token from SEA
  `GET /api/v1/agent-workflow-hosts/{gen}/executor-credential`;
  `childInput.sandboxHost` carries the non-secret executor descriptor only.
- `call_llm` spans attribute to the harness, tool spans to the executor sandbox.
  `/executor/healthz` reports `workspaceRoot`/`workspaceReady`; the BFF
  readiness probe gates on `ok`.
- Resilience proven live (executor pod and harness replica each deleted
  mid-turn; same execution finishes): `agent-session-recovery`.

## Context Strategy

- `capabilities.contextStrategy` (`docs/context-strategy.md`) defaults to
  `event_log` for the dapr-agent-py family (env mirror
  `DAPR_AGENT_PY_DEFAULT_CONTEXT_STRATEGY`); CLI runtimes keep vendor
  autocompaction.
- Compaction is a read-time PROJECTION: the checkpoint lives under Dapr state
  key `{prefix}_compaction:{instance}`, `entry.messages` is never mutated, and
  deleting the checkpoint restores the verbatim transcript. Projection byte
  ceiling `DAPR_AGENT_PY_PROJECTION_MAX_BYTES` defaults to 12 MiB, clamped
  under the 16 MiB Dapr limit.
- `ReadSessionEvents` is visible by default and exempt from `tools` /
  `builtinTools` narrowing under `event_log`; it is hidden only when a call opts
  into `contextStrategy: compaction`. After compaction the summary hint says
  "call read_session_events(after_sequence=<cursor>)".
- Trap: a per-agent `compaction.autoCompactWindow` below summary_reserve
  (20000) + `bufferTokens` clamps the threshold to 0: compaction every iteration.

## Runtime Admission

- Registry `conformanceVerified` (distinct from `capabilitiesVerified`) gates
  dispatch. An unverified target is swap-safety severity `error`: the
  durable/run bridge and direct spawn return HTTP 409 `Runtime "<id>" is not
  conformance-verified (...); set AGENT_RUNTIME_ALLOW_UNVERIFIED_RUNTIME=true or
  agentConfig.allowUnverifiedRuntime=true to override`; the override degrades
  the check to `warn` and emits `runtime.swap_degraded`.
- `agentConfig.runtimeImageRef` exists for testing an UNRELEASED runtime image
  on dev: a digest-pinned `ghcr.io/pittampalliorg/<repo>@sha256:<64 hex>` in the
  runtime's own registry `imageRepository` family, replacing the image of THIS
  agent's per-session sandbox/executor pod only — never a shared Deployment, and
  refused outright by runtimes that build no per-session host (the canonical
  `dapr-agent-py` among them, `imageRepository: null`). Two invariants an author
  must not violate: it is honoured only with `allowUnverifiedRuntime` on the same
  agent (else 409), and it is never valid on a published evaluation subject (422
  `subject_runtime_image_override` at publish, refused again at campaign launch).
  Shape, per-runtime support, and the proof recipe: `runtime-conformance`.
- Both conformance lanes, the results file (the authority for which runtimes are
  verified), and the GENERATED `## Current runtimes` table in
  `docs/durable-session-runtime-contract.md` are owned by `runtime-conformance`;
  recovery and forensics belong to `agent-session-recovery`.

## Task Map

| Task                             | Read or inspect                                                                        |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| Author a script                  | `docs/dynamic-script-authoring-guide.md`                                               |
| Understand execution/replay      | `docs/dynamic-script-workflows.md` and script-engine code/tests                        |
| Connect an external MCP client   | `docs/workflow-mcp-server.md`                                                          |
| Attach tools to spawned agents   | `docs/mcp-agent-workflows.md`, MCP resolution code, and piece-runtime manifests        |
| Select or swap an agent runtime  | `docs/durable-session-runtime-contract.md` and `services/shared/runtime-registry.json` |
| Verify or admit a runtime        | Use `runtime-conformance`; `conformanceVerified` needs static=PASS and live=PASS |
| Recover a run after a pod/orchestrator loss or do run forensics | Use `agent-session-recovery` |
| Stop, terminate, purge, or reset | `docs/workflow-lifecycle-termination.md` and `src/lib/server/lifecycle/`               |
| Set or debug a persistent goal   | `docs/goal-loop.md` and goal application adapters                                      |
| Produce typed run artifacts      | `docs/workflow-artifacts.md`                                                           |
| Query terminal/post-teardown evidence | `docs/execution-evidence.md` and Workflow MCP execution-evidence tools            |
| Inspect or restore run code      | `list_code_checkpoints`, `get_checkpoint_diff`, `restore_checkpoint`, `continue_checkpoint` |
| Resume or fork a run             | `resume_workflow_execution` and `docs/dynamic-script-workflows.md`                      |
| Promote a run's code to a PR     | `promote_run_to_pr`                                                                     |
| Edit prompts or presets          | Prompt Workbench components, prompt APIs, and current prompt docs                      |
| Diagnose a rollout               | Use `gitops`                                                                           |
| Develop or inspect runs inside a preview | Use `preview-environments`; start at `/previews`, then use the exact `/dev/system` detail and host `/runs` surfaces |
| Explain capacity or admission    | Start at `/workspaces/<slug>/capacity/debug`; use `kubernetes-capacity` for queue, observer, PSI, or policy work |
| Run or compare SWE-bench, Harbor, or evals | Use `evaluations`; campaign detail owns score, duration, token/tool, cost, and trial-trace analytics; execution is dev-only |

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
- Credential boundary: executor pods never hold provider keys, `DATABASE_URL`,
  or `INTERNAL_API_TOKEN`; the executor token reaches the harness only through
  SEA `executor-credential`, and `childInput` never carries it.
- Compaction never rewrites the durable log: it is a projection checkpoint over
  an immutable `entry.messages`; deleting the checkpoint restores the transcript.
- `/workspaces/<slug>/runs` is the canonical run entry point. A host-owned
  DevelopmentRun uses the ordinary run detail and its Live tab. Legacy
  preview-local activity and sealed evidence enter only through federated,
  read-only application ports. Presentation code must not know preview database
  credentials, namespaces, broker URLs, or Kubernetes clients.
- Preview development uses `development_run_get` and
  `development_run_follow_output`; checkpoint, fork, handoff, and reproduction
  use their corresponding `development_run_*` commands on the same run. Generic
  workflow continuation is not a second preview-development path.
- A `system-live` stacks tree with no rendered infrastructure delta is a
  successful no-op: it acquires no temporary ownership and has no readiness
  work. Cancellation releases application adoption before infrastructure
  ownership and restores the exact baseline before ArgoCD resumes.
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
- An active provider stream may be preempted only through the runtime's
  cancellation port after the request is durably persisted. Treat
  `agent.turn_preempted` as fast-path evidence, not terminal authority; cross-pod
  convergence still comes from durable state and the Lifecycle Controller.
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
   bounded product evidence identifies a runtime gap. Use
   `/workspaces/<slug>/capacity/debug` and `kubernetes-capacity` when the failure
   is admission or physical headroom rather than session behavior.
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
sub-lane brands those `error` / `start_orphaned` past
`EXECUTION_START_ORPHANED_STALE_SECONDS` (default 900, floor 600), but only
after probing the deterministic candidate instance id — an instance the runtime
knows means a lost attach write, so the row is skipped (`skip_unverified`).
`team-run` and `host` dispatch-backend rows hold NULL BY DESIGN; never brand or
hand-fix one. The lane's own `EXECUTION_START_ORPHANED_DRY_RUN` defaults TRUE,
and an observe-only decision still increments `executionLivenessRepaired` —
check `decisions[].outcome` for `repaired_start_orphaned` with `executed: false`
before believing a repair happened.

Normal replay messages are not proof of a hang. Prove lack of progress with
durable state, timestamps, queue admission, and runtime logs before intervening.

For a fan-out that stalls after an orchestrator roll, read
`customStatus.repolled` / `repollProbes`: `repolled > 0` means the in-band
repoll lane recovered a lost child completion, not a hang — the lane itself
belongs to `agent-session-recovery`. For a dapr-agent-py session the harness
turn-start line `[context] instance=… strategy=event_log
readSessionEvents=visible roster=[…]` evidences the effective context strategy
and tool roster.

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
- `continue_checkpoint` is the recovery path when the source execution is
  terminal or its live host is gone. It creates or reuses an independently
  runnable session, restores the durable ref once before the first turn, and
  leaves the source execution read-only. Restore and later captures retain the
  source execution ID as checkpoint-chain owner, so the restored SHA is the
  next mutation's parent rather than a full-tree addition.
- A recovery workspace is a detached source materialization and may have no
  `.git`. Use checkpoint rows and `get_checkpoint_diff`, not `git status` or
  `git diff`, as recovery authority. Runtime `.wfb-diff-git` bookkeeping is
  excluded from captures. A recovery session is not an active DevelopmentRun:
  never run `wfb-development` there, and leave preview synchronization,
  verification, and submission to a later DevelopmentRun or delivery action.
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
  DevelopmentRun delivery uses `development_run_submit`, not this generic tool.
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
  A merged change reaches dev through the `main` merge queue, whose build reuses
  the PR-head image instead of rebuilding it — see `gitops`.
- Orchestrator rolls are safe mid fan-out: any replica resumes from durable
  state alone and the in-band repoll lane recovers lost child completions.
  Verify with `scripts/probes/orchestrator-roll-proof.sh` (saved workflow
  `orchestrator-roll-proof`); a lost completion shows as `repolled > 0`.
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
- `docs/session-resource-metrics-and-kueue-admission.md`
- `docs/harness-host.md`
- `docs/context-strategy.md`
- `services/shared/runtime-registry.json`
- `services/shared/runtime_conformance/`
- `scripts/runtime-conformance/`
- `scripts/probes/orchestrator-roll-proof.sh`
- `services/workflow-orchestrator/`
- `services/workflow-mcp-server/`
- `src/lib/server/application/`
- `src/lib/server/lifecycle/`
- `src/lib/server/agents/`
- `src/lib/server/mcp-connections.ts`
- `src/lib/server/goals/`
