---
name: preview-environments
description: "Operate and prove Workflow Builder PreviewEnvironment lifecycles and canonical DevelopmentRuns on the dev cluster. Use for Previews inventory, system-live/app-live/candidate profiles, target selection, Dapr Agents or CLI builders, HMR, DevelopmentOutput, MCP development_run tools, checkpoint/fork/handoff/reproduce, delivery receipts, sleep/wake, durable evidence, and signed 12-check teardown. Use workflow-builder for ordinary workflows, and gitops for persistent delivery."
---

# Preview Environments

`PreviewEnvironment` is the only user-facing isolated development environment.
`DevelopmentRun` is the only agent-assisted development control path. The run
is host-owned; the application under test and its receivers run in the dev
vCluster. Do not create a second workflow, session, source transport, or UI path
for preview development.

## Start From Current Sources

Read the current versions of:

- Workflow Builder `docs/preview-environments.md`
- Workflow Builder `docs/preview-environment-agent-development.md`
- Workflow Builder `docs/host-preview-development-lifecycle.md`
- Workflow Builder `docs/execution-evidence.md`
- stacks `docs/preview-environment-architecture.md`
- stacks `docs/preview-environment-runbook.md`
- stacks `docs/capacity-management.md`
- this skill's [DevelopmentRun contract](references/development-run-contract.md)

Then inspect current target/service catalogs, runtime registry, effective APM
packages, workflow fixture, adapters, CRD, runner, policy, pins, and live
receipts. Do not rely on remembered services, digests, versions, capacity, run
IDs, or timings.

## Authority Model

- `PreviewEnvironment` status is lifecycle truth. SEA is the only privileged
  physical executor. Kueue is the one physical capacity ledger.
- Workflow Builder compiles and persists the immutable ChangeSet, Generation,
  DevelopmentPlan, and coordinate-free DevelopmentExecution.
- The compiler selects `prepare`, `apply`, `observe`, `verify`, `deliver`, and
  `cleanup` adapters. Callers never name adapters or arbitrary commands.
- The host derives repositories, full revisions, workspace, identities,
  credentials, policy, agent/APM configuration, and delivery coordinates.
- The broker re-reads the live immutable tuple before every boundary crossing;
  the preview validates the minted leaf and tuple independently.
- Dapr owns durable workflow state. Receivers own source-generation and health
  receipts. The delivery adapter owns GitHub writes. Tekton and ArgoCD own
  persistent build and deployment.
- Presentation and agents never receive namespaces, pod addresses, database
  URLs, NATS subjects, preview credentials, kubeconfigs, GitHub write targets,
  or provider secrets.

## Choose A Profile

| Need                                                             | Profile              |
| ---------------------------------------------------------------- | -------------------- |
| Namespaced stacks and application changes in one generation      | `system-live`        |
| Application HMR or a pull-request preview                        | `app-live`           |
| Immutable namespaced stacks validation                           | `manifest-candidate` |
| Talos, CNI/CSI, host network/storage, Tailscale, or argocd-agent | `host-candidate`     |

`host-candidate` uses a disposable physical cluster. Hub management, Source
Hydrator, and GitOps Promoter changes have no vCluster preview lane.

Public exposure and compute capacity are independent. A public preview consumes
one origin from the current public pool; a headless preview consumes none.
Choose headless when browser or callback exposure is unnecessary, but never
present origin availability as proof that Kubernetes capacity exists.

### Adaptive capacity

SEA compiles an immutable plan from the selected profile, services, execution
concurrency, and margin. One synthetic Kueue Workload reserves that exact shape
on physical dev; it does not launch pods. Provisioning begins only after Kueue
admission and a forced-fresh capacity-observer headroom check.

Use `/workspaces/<slug>/capacity/debug` to explain versions, decision inputs,
exact reservations, materialized and observed usage, queue arithmetic, node
headroom, PSI, lifecycle timers, and raw evidence. For cluster-wide quota,
cohort, PSI, right-sizing, or concurrency work, use `kubernetes-capacity`.

Pressure may accelerate evidence-gated sleep of idle previews, but it cannot
terminate active or protected work. Observer failure is never permission to
reclaim. Treat total preview objects, awake capacity, public origins, and exact
Kueue admission as separate limits.

Preview vClusters are not an evaluation execution lane. Canonical evaluation
campaigns, ordinary subject children, and scorer harnesses execute on physical
dev through the `benchmark-eval` ledger. They share capacity-observer signals
with previews but not lifecycle authority, reservations, or product read
models. Use `evaluations` for campaign scores and trace-derived usage.

### Source-baseline clamp

A hot-reload receiver seeds its workspace from the pinned `workflow-builder-dev`
image's BAKED source, so that revision — not repository HEAD — is the only
source a preview can truthfully serve. A default launch therefore resolves
`sourceRevision` to the dev image's baked revision
(`WORKFLOW_BUILDER_DEV_IMAGE_SOURCE_REVISION`, published in the image-pins
ConfigMap and pinned on the preview-control broker). An explicit
`sourceRef`/`sourceRevision` that resolves elsewhere is refused with
`source-baseline-mismatch`, and SEA preflight carries the
`dev-image-source-revision-mismatch` backstop for callers that bypass the host
resolver.

Treat that refusal as correct: without the clamp, every file changed between
the image revision and HEAD that the builder does not itself edit is simply
ABSENT from the receiver (digest delivery never re-sends unmodified files), so
routes 500 on missing imports and browser evidence can never be captured. The
fix is to rebuild and repin `workflow-builder-dev` for the wanted revision, not
to relaunch.

## Canonical Flow

1. Discover services and targets with `list_preview_services`, then inspect
   `list_preview_environments`.
2. Launch a `system-live` or `app-live` PreviewEnvironment with the typed MCP or
   UI surface. The server resolves full revisions and policy.
3. Poll `get_preview_environment` until that exact generation is Ready. For
   cold-start work, inspect `bootSeconds` and `preview-boot-telemetry/v1`; use
   its `controlPlane`, `argoCD`, `workloads`, `auth`, and `exposure` totals
   before drilling into raw step timings.
4. Call `development_run_start` with the environment name, intent, selected
   target IDs, and optional public builder profile.
5. Use only `development_run_get`, `development_run_apply`,
   `development_run_follow_output`, `development_run_verify`,
   `development_run_submit`, and `development_run_cancel`.
6. Use `development_run_checkpoint`, `development_run_fork`,
   `development_run_handoff`, or `development_run_reproduce` when needed. They
   operate on the same run and provenance.
7. After terminal telemetry grace, verify sealed evidence through
   `list_execution_evidence`, `get_execution_evidence`, and one bounded package
   part or telemetry query.
8. Re-read the preview generation, request typed teardown, and poll
   `get_preview_teardown_status` until all 12 checks pass.

Honor server-issued next actions, typed failures, refresh delays, cursors, and
generation fences. Generic workflow start, continuation, and promotion tools
are not preview-development alternatives.

Cancellation is host-owned and durable. The runtime may preempt a process-local
provider stream only after persisting the request; `agent.turn_preempted` proves
that fast path but not terminal cleanup. Cross-pod delivery still converges
through Dapr state and the parent DevelopmentRun.

A generic checkpoint continuation is intentionally outside the active
DevelopmentRun. It is permitted only after the source execution is terminal,
materializes a detached tree that may have no `.git`, and has no
`wfb-development`, receiver, preview synchronization, or submission authority.
Use `development_run_handoff` or `development_run_reproduce` to remain inside
the canonical preview-development lifecycle.

## Targets And Builders

Target kinds are `deployment-service`, `greenfield-module`, `session-runtime`,
`infrastructure`, and `agent-configuration`. A new target requires a catalog
descriptor and, only when necessary, one versioned adapter. It must not add a
new page, workflow, MCP schema, or transport.

Public builder profiles are:

- `dapr-agent-py`
- `claude-code-cli`
- `codex-cli`
- `kimi-code-cli`
- `agy-cli`

Fixture-local `*-host` identifiers are internal mappings, not caller input.
`adk-agent-py` is retired. Do not restore it or a Pydantic preview runtime.
General Pydantic AI skills remain valid for unrelated upstream applications;
they are not Workflow Builder runtime authority.

Official CLI pods, OAuth files, native hooks, transcripts, and MCP sessions stay
on physical dev. Persistent sessions edit the host checkout and invoke
`wfb-development apply`, `observe`, or `verify`. Submission and cleanup remain
parent DevelopmentRun commands.

### CLI execution mode: headless print turns

A CLI builder runs in one of two execution modes, and the mode is a runtime
property — never a caller input:

- `native-tui`: the CLI runs as a herdr pane and prompts are injected into its
  pty. This remains the preview-local baseline for `claude-code-cli`,
  `codex-cli`, and `kimi-code-cli` when no headless gate is delivered.
- `headless-print`: each turn is its own subprocess speaking the CLI's
  structured stdio protocol (`agy -p --output-format stream-json
  --conversation`, `claude -p --output-format stream-json --verbose --resume`,
  `kimi --prompt --output-format stream-json --session`, `codex exec [resume
  <id>] --json`). Default and only supported mode for `agy-cli`, whose TUI
  wedges under pty injection; selected physical-dev runtimes opt in via
  `CLI_AGENT_{CLAUDE,KIMI,CODEX}_HEADLESS=1`.

Read the current host and preview ConfigMaps before asserting a mode. The
physical-dev runtime is presently the bounded headless testbed for Claude,
Kimi, and Codex, while the preview-local runtime policy deliberately omits
those gates and retains native TUI. That difference is classified in
`preview-runtime-config-policy.json`; do not copy the gates into previews or
change the classification as incidental drift cleanup.

No CLI in this fleet exposes ACP (agent client protocol); print mode is the
native structured-transport equivalent. Subscription auth is unaffected —
headless inherits the same OAuth token env the pane uses.

Headless invariants (each traces to a live dev failure):

- The `wfb-development` CLI resolves identity from the process environment. A
  headless turn is a direct subprocess with an EXPLICIT env, so the runtime
  widens the curated pane env with `DAPR_AGENT_SESSION_ID`,
  `DAPR_AGENT_SESSION_HOST_INSTANCE_ID`, `WORKFLOW_BUILDER_URL`, and
  `INTERNAL_API_TOKEN` — and nothing else. Provider API keys never cross.
  Without this every stage transition fails
  `interactive session identity is unavailable` while transport looks healthy.
- A headless turn ENDS its subprocess, so a per-turn CLI hook is a turn edge,
  not a session edge. `SessionEnd` is suppressed while a headless runner is
  active; otherwise the durable session dies after turn one.
- Turn continuity is the CLI's own resume handle (conversation / session /
  thread id) captured from the first turn's events. Resume argv is NOT the
  fresh argv: `codex exec resume` accepts only bare flags (`--cd`/`--model`/
  `-c` are a usage error), and kimi rejects `--agent`/`--agent-file` plus every
  permission-mode flag (`--yolo`, `--auto`) in prompt mode.
- Tool governance still runs through the wfb hook relay. For codex that
  requires `--dangerously-bypass-hook-trust` in the rebuilt `exec` argv;
  without it codex runs with NO hooks and emits no tool events at all while
  still reporting successful turns.

For `system-live`, watch mode covers the primary checkout plus every imported
ChangeSet repository under `/sandbox/work/repositories` and coalesces one burst
into one ordered content generation. Infrastructure edits must remain under the
generation's immutable `candidatePaths`. Agents edit source only; they never
receive Kubernetes credentials or apply rendered manifests.

The watcher publishes the same composite-digest verdict ledger into every
member checkout. After editing any repository, run `wfb-development await-sync`
with `--wait --repo <edited-checkout>` and require `applied` before inspecting
the environment. `failed`, `unwatched`, and `timeout` are not success. A busy
durable phase defers the batch; do not start a second apply authority.

Policy, scope, and admission rejections are permanent for that composite
digest. Only command-gate transitions and responses explicitly marked
`retryable` may defer the same tree. The watcher owns the bounded retry and uses
a fresh operation identity; the Dapr action activity must not replay a
persisted privileged-preview verdict. Removing a rejected edit must trigger
exactly one recovery apply, even when the tree returns to the prior successful
digest.

Dapr workflow history is immutable. A `session-runtime` target verifies one
fixed source canary, then requires a built and pinned image plus a fresh session
for deployed proof. Never hot-patch an existing durable workflow.

## Output And Evidence

Start diagnosis with `development_run_get` and
`development_run_follow_output`, not Kubernetes. DevelopmentOutput supports:

```text
process-log compiler-diagnostic health trace prompt-content tool-content
metric browser-console browser-network deployment
```

Reads are bounded and cursor-based. Cursors are fenced to the run generation
and selected signals. Preserve prompt and tool content; mask only
credential-shaped fields and embedded credential values.

For browser-required work, verify screenshots or named observations appear
while the session remains active. CLI supervisors periodically upload and
deduplicate new proof; Dapr Agent sessions persist it after browser tool calls.
Final recording closure and evidence sealing are additional terminal steps.

Use direct pod, SEA, or receiver logs only after bounded product evidence shows
a specific gap. Terminal host and legacy preview-local runs seal separately as
`wfb.execution-evidence/v2`. Evidence is durable; preview runtime state,
logical product data, NATS state, and mutable workspaces are disposable.

## Apply, Verify, And Deliver

- One logical apply uses one generation across the full service set.
- An infrastructure apply renders the exact stacks baseline and candidate in
  separate trusted trees, then hands a digest-bound delta to the preview-local
  receiver under one run-generation Lease.
- During infrastructure ownership, only the exact preview ArgoCD Application
  is paused. The receiver admits bounded namespaced resources, uses one
  server-side-apply field manager, waits for readiness, and returns resource,
  event, workload-log, Dapr, trace, and browser evidence through
  DevelopmentOutput.
- A failed infrastructure generation restores the prior successful generation.
  Cancel and cleanup restore the exact baseline before the local and hub Leases
  are released and ArgoCD resumes.
- An admitted stacks tree with no rendered delta succeeds without acquiring
  infrastructure ownership or scheduling readiness work.
- Cleanup releases application adoption before infrastructure ownership,
  retries transient receiver transport failures, and resumes ArgoCD only after
  baseline restoration.
- Require one `APPLIED` receipt per service plus global terminal convergence.
- Source-only HMR keeps adopted pod UIDs stable; replacement is rollout
  evidence, not HMR evidence.
- Receiver compile, diff-scope, generation, and health decisions are
  authoritative.
- Verification is impact-derived from catalog gates and may include service,
  route, contract, render, runtime, browser, and telemetry checks.
- `submit` performs current-base preflight and returns linked, idempotent
  delivery receipts. The agent never chooses branch, repository, commit, PR, or
  CI coordinates.
- Persistent delivery continues through review, merge, Tekton image build and
  pin, Source Hydrator/Promoter where applicable, and ArgoCD reconciliation.

## Acceptance

For a changed development boundary, require fresh dev-cluster proof:

- invalid/no-op launch requests create zero lifecycle resources and return typed
  reasons;
- source-only HMR returns applied plus terminal ready/failed output within 10s;
- infrastructure file detection is within 1s, render/policy is within 5s,
  admitted API-visible resources converge within 10s, and Deployment or Job
  readiness is decisive within 60s;
- unsupported scope or authority is rejected with zero host/shared mutation;
  rollback completes within 30s and release restores the exact baseline;
- a combined application plus stacks edit is one coalesced generation, and a
  controlled restart causes no duplicate apply;
- permanent policy rejection consumes no retry loop, transient retry preserves
  the digest but rotates operation identity, and removing the rejection causes
  exactly one recovery apply;
- command submission returns a durable receipt within 2s;
- delivery returns a receipt or typed failure within 120s;
- required GitHub checks start within 30s of PR creation or return a typed block;
- duplicate idempotency keys create no duplicate delivery;
- all supported runtimes expose full prompt/tool evidence plus required code
  semantic attributes;
- UI, REST, MCP, and persistent CLI show the same plan, gates, receipts, output,
  and next actions; and
- teardown completes all 12 signed absence checks with no active owned resource.

Keep exact run IDs, SHAs, digests, signatures, and timings in machine-readable
proof, not this skill.

## Teardown

Never substitute raw deletion or namespace absence for the typed contract:

```text
runnerSucceeded previewEnvironmentAbsent applicationAbsent
agentRegistrationAbsent agentNamespacesAbsent databaseAbsent
natsStreamAbsent headlampRegistrationAbsent tailnetEgressAbsent
hostNamespaceAbsent storageScopeAbsent runnerIdentityAbsent
```

Cancel the DevelopmentRun first. A legacy preview-local active-use refusal must
be handled through its owning legacy surface, then sealed or explicitly
quarantined. Do not launch another. `forceFailed` is only for failed or aged
generations and records evidence loss. Never remove finalizers to bypass owners.

## Readiness Stalls

`PreviewEnvironment` status on the hub is lifecycle truth, and the controller
flips `Ready` only when the preview's Argo CD Application is Synced, Healthy,
at the expected revision, AND its last sync `operationState.phase` is
`Succeeded`. A sync that FAILS transiently and then self-heals leaves the app
Synced+Healthy with a `Failed` operation, and the controller's hard refresh
advances `reconciledAt` without creating a new operation — so the CR waits
forever and every `development_run_start` is refused as not Ready.

Diagnose in this order, not with kubectl guesses: CR
`status.conditions[Ready].reason` (`WaitingForApplication`), then the
Application's `operationState.phase`. When that phase is `Failed` while sync
and health are good, request one fresh sync operation so a `Succeeded` lands.
A preview whose up-Job succeeded and whose origin serves traffic is healthy —
the stall is projection, not provisioning.

## Validation

Run focused Workflow Builder domain, adapter, route, fixture, catalog, and MCP
tests. For stacks, select the changed boundary from the runbook and include:

```bash
scripts/gitops/validate-preview-vcluster-surface.sh
scripts/gitops/validate-dev-preview-service-catalog.sh
scripts/gitops/validate-preview-application-policy.sh
scripts/gitops/validate-preview-vcluster-sync-contract.sh
deployment/scripts/tests/test-preview-job-launch-boundary.sh
```

Run the Dapr actor-store validator for Component changes. Image-baked runner or
runtime changes require a rebuild, rendered pins, bounded admission transition,
fresh generation, user-path proof, evidence proof, and teardown proof.

## Skill Boundaries

- Use `workflow-builder` for ordinary dynamic-script workflows, sessions,
  traces, and evidence outside preview lifecycle.
- Use `gitops` after DevelopmentRun delivery for builds, pins, promotion, ArgoCD,
  and live deployment proof.
- Use `kubernetes-capacity` for shared quota, cohorts, PSI, physical headroom,
  exact-plan tuning, pressure policy, and dynamic concurrency.
- The ryzen Skaffold loop is retired; dev is the only test and deploy target.
- Use `dapr-agents-workflow` for standalone upstream Dapr Agents Python apps.
- Do not create another DevelopmentRun skill; it would duplicate this authority.

## Safety

- Dev only. Do not redirect a preview proof to ryzen.
- Use fresh worktrees from current `origin/main`; preserve unrelated dirty work.
- Do not roll the response path during an active proof.
- Do not expose workspace keys, preview credentials, kubeconfigs, broker leaves,
  OAuth files, provider secrets, or decrypted values.
- Do not merge a proof artifact unless a reviewed delivery task owns that step.
