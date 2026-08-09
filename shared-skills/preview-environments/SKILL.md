---
name: preview-environments
description: "Operate and prove Workflow Builder PreviewEnvironment lifecycles and canonical DevelopmentRuns on the dev cluster. Use for Previews inventory, system-live/app-live/candidate profiles, target selection, Dapr Agents or CLI builders, HMR, DevelopmentOutput, MCP development_run tools, checkpoint/fork/handoff/reproduce, delivery receipts, sleep/wake, durable evidence, and signed 12-check teardown. Use workflow-builder for ordinary workflows, gitops for persistent delivery, and skaffold-dev-loop only for ryzen."
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
- Use `skaffold-dev-loop` only for the trusted ryzen operator loop.
- Use `dapr-agents-workflow` for standalone upstream Dapr Agents Python apps.
- Do not create another DevelopmentRun skill; it would duplicate this authority.

## Safety

- Dev only. Do not redirect a preview proof to ryzen.
- Use fresh worktrees from current `origin/main`; preserve unrelated dirty work.
- Do not roll the response path during an active proof.
- Do not expose workspace keys, preview credentials, kubeconfigs, broker leaves,
  OAuth files, provider secrets, or decrypted values.
- Do not merge a proof artifact unless a reviewed delivery task owns that step.
