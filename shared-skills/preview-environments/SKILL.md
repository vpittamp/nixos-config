---
name: preview-environments
description: "Operate and prove Workflow Builder PreviewEnvironment lifecycles on the dev cluster. Use for preview vClusters, app-live or candidate profiles, agentic development, host-driven attach-mode development (preview-host-development), host-resident preview product DBs (preview-db pooler), durable post-teardown execution evidence, multi-service adoption and sync, retained previews, interactive handoff, HMR, impact gates, out-of-scope rejection, draft-PR capture, teardown checks, preview logs, and preview platform manifests. Use workflow-builder for ordinary workflow authoring and gitops for the host delivery lane."
---

# Preview Environments

PreviewEnvironment is a dev-cluster vCluster lifecycle, not a workflow execution
Sandbox and not the ryzen Skaffold loop. Keep those three runtime models
separate.

## Canonical Documentation

Read both repository entry points before operating the platform:

- Workflow Builder: `docs/preview-environments.md`
- Workflow Builder evidence: `docs/execution-evidence.md`
- Stacks architecture: `docs/preview-environment-architecture.md`
- Stacks host/preview split: `docs/host-driven-preview-development.md`
- Stacks operator procedure: `docs/preview-environment-runbook.md`

Then inspect the current lifecycle fixture, API, CRD/manifests, scripts, catalog,
and executable tests. The docs explain the contract; source and receipts prove
the active implementation.

## Authority Model

- The host derives repository, revision, workspace, Kubernetes target, preview
  identity, and policy. Caller input must not override privileged authority.
- `PreviewEnvironment` status and controller-owned resources are lifecycle
  truth. Agent logs and workflow output are evidence, not alternate authority.
- The preview vCluster is isolated desired state. Host credentials and broad
  host-cluster APIs must not be copied into it.
- Promotion captures an agent artifact as a draft PR. A proof draft is evidence
  and must not be merged unless a separate reviewed delivery task explicitly
  designates it.

## Profiles

| Profile              | Purpose                                                                   |
| -------------------- | ------------------------------------------------------------------------- |
| `app-live`           | Boot a prod-shaped app surface and optionally enter agentic development   |
| `manifest-candidate` | Render and gate a candidate manifest change                               |
| `host-candidate`     | Validate a host/platform candidate through its dedicated receipt boundary |

Choose the smallest profile that answers the question. Do not use a host
candidate to test an ordinary service edit.

`host-candidate` is not a vCluster launch mode. Its dedicated host adapter and
receipt boundary must reject attempts to route it through the app-live runner.

## Workflow MCP Operations

Use the BFF-authorized Workflow MCP tools instead of Kubernetes discovery for
normal lifecycle work:

1. `list_preview_services`, then `list_preview_environments`.
2. `launch_preview_environment`, followed by `get_preview_environment` until
   the accepted generation is Ready.
3. `debug_preview_environment` for the bounded lifecycle/runtime/trace bundle,
   then `query_preview_traces` for explicit service, status, search, and time
   filters.
4. For a terminal run, allow the telemetry grace, then use
   `list_execution_evidence`, `get_execution_evidence`, and a bounded
   `get_execution_evidence_part` or
   `query_execution_evidence_telemetry`. Live trace tools diagnose active
   executions; the evidence key is the durable post-teardown identity.
5. Read the generation again immediately before teardown. Pass its exact
   `provenance.requestId` and `sourceRevision` to
   `teardown_preview_environment`, then poll the returned signed ticket with
   `get_preview_teardown_status` until all twelve checks are true.

Honor `telemetry.refreshAfterMs`, generation-fence warnings, pagination, and
server-issued `nextActions`. A partial or `7/12` cleanup snapshot can be a
normal transition between dev-side physical cleanup and hub finalizer
convergence; only `12/12` is terminal proof.

The physical dev workspace key is never forwarded into a preview. A direct
preview-local Workflow MCP connection uses a preview-local key and audience.
Its standard execution/trace tools keep authorization in the preview while
deep evidence is read through the tuple-bound physical diagnostics adapter.
The host evidence catalog is a separate read boundary and remains available
after the preview generation and logical product database are gone.

## Preview Runtime Boundary

An `app-live` vCluster does not inherit the physical host OpenShell or
`workspace-runtime`. Do not restore host credentials or host workspace URLs to
make an agent call pass. For preview-local agent proofs, confirm the selected
runtime is the preview-native `dapr-agent-py-juicefs` lane and that Sandbox
Execution API receives the immutable environment tuple plus its tuple-scoped
storage scope and class before launching the workflow.

A preview vCluster runs its OWN Dapr control plane, pinned by the provisioner
and asserted by `scripts/gitops/validate-preview-vcluster-surface.sh`. It is
deliberately allowed to lag the host: previews have their own acceptance gates,
so a host control-plane upgrade does NOT reach previews until that pin and its
validator move together. Read the version from the preview, never from the host,
before attributing a runtime behavior to a Dapr version.

K3 vision analyzes pixels but does not navigate a browser. Keep the supported
browser control/capture boundary, pass native screenshot image content to K3,
and remove only obsolete model-specific text/metadata compensation.

## Host-Driven Development Lane

`preview-host-development` (seeded dynamic-script workflow) is the attach-mode
inverse of the preview-local child: ONE host execution adopts a service inside
an EXISTING app-live preview through the preview-control broker, seeds a host
workspace, runs a policy-owned builder profile, live-syncs each iteration,
captures source from the HOST workspace, promotes a draft PR carrying the
builder reports, and releases the adoption in a `finally` block. Run evidence
(journal, sessions, LLM turns, cost, artifacts) lives in the HOST database; only
the application under test runs in the vCluster.

The default `pydantic-ai-k3-host` profile preserves the Kimi K3 builder. The
single-CLI profiles are `claude-code-cli-host`, `codex-cli-host`, and
`kimi-code-cli-host`; `cli-fanout` runs those three in that fixed order against
one execution-scoped host checkout. The ordering is load-bearing: concurrent
writers on the same JuiceFS tree would make source outcomes timing-dependent.
CLI pods, OAuth delivery, hooks, and transcripts stay on physical dev. Never
restore or copy CLI OAuth into a preview to make this lane work.

Launch it ONLY via `start_dev_environment_session` with
`workflowName: preview-host-development`, passing `intent`, `previewOrigin`,
an optional closed `builderProfile`, and `previewTarget` — the preview's immutable tuple copied EXACTLY from
`get_preview_environment` (name, `provenance.requestId`, `platformRevision`,
`sourceRevision`, `catalogDigest`). The broker re-reads the live generation and
refuses any drift, including a single wrong digest character.

Proven operational rules (each traces to a live failure on dev):

- Write the intent inside the target service's dev-sync `syncPaths` (e.g.
  `src/` for workflow-builder) — the diff-scope gate rejects out-of-scope
  files every iteration and the run fails after `maxIterations`.
- Adoption readiness is slow-boot tolerant BY DESIGN: the dev pod's first
  vite SSR render compiles the whole module graph (~30-55s) and the startup
  probe carries it in one long attempt; transient boot 500s get the full
  window. SEA's `waitReadySeconds` is the timeout authority, not the kubelet.
  Do not "harden" these probes toward fast failure.
- The derived adoption id `host-dev-<environmentRequestId>` is STABLE per
  preview: the preview persists its workspace-session tombstone without
  execution linkage, and SEA teardown intents expire after 180s rather than
  permanently retiring the id.
- After a run releases its adoption, give SEA ~60s to converge before
  relaunching against the same preview; an adopt racing the deleting Sandbox
  CR fails with an empty-bodied 409.
- Preview-side fixes (SEA, preview BFF) ride NEW previews — the tuple pins
  them at provision. Host-side fixes ride the pin rollout. Re-verify a fix on
  whichever side it lives before claiming it works.

## Host-Resident Preview Data And Evidence (live 2026-07-29)

- The preview PRODUCT database is one logical DB per preview on the HOST
  `preview-db` CNPG cluster, reached only through `preview-db-pooler`
  (transaction pgbouncer, wildcard routing). Previews run NO CNPG operator,
  cluster, or PVC. App/Dapr URLs carry the pooler's ClusterIP — in-vcluster
  pods resolve no host service DNS, so never "fix" a preview DB issue by
  pointing anything at a host service NAME from inside the vcluster.
- Admin DDL (create/drop of `preview_<name>`) is runner-side against
  `preview-db-rw`; teardown terminates backends, drops the logical DB, and
  proves absence. Verify with `psql` on `preview-db-1`, never by trusting
  workflow output alone.
- Durable execution evidence is host-owned. The recurring archive job and
  normal teardown reconcile terminal preview executions through the exact
  immutable tuple into sealed `wfb.execution-evidence/v2` packages. Incomplete
  evidence blocks normal teardown and remains retryable; the supported
  failed/aged-generation quarantine path writes a `lost` receipt.
- Packages contain execution/journal data, sessions/events, dynamic-script
  calls, artifacts, browser captures, checkpoints, promotion receipts, spans,
  and logs. Preserve prompt text and tool inputs/outputs. Mask only
  credential-shaped fields and embedded credential values.
- Catalog receipts live in host Postgres, package bytes in
  `wfb-run-archives`, and evidence-keyed spans/logs in the long-retention
  ClickHouse projection. Dev retention is 365 days with a 30 GiB active-package
  quota and oldest-first purge.
- `VCLUSTER_PREVIEW_DB_MODE=cnpg` is the DB rollback lever. Evidence capture is
  currently active through `WFB_RUN_ARCHIVE_ENABLED=true` and
  `PREVIEW_ARCHIVE_ON_TEARDOWN=true`; do not describe it as retired or
  inventory-only.
- Changing the runner or its policies means REBUILDING the runner image
  (runner.sh + host-policy.yaml are image-baked): build from the component
  dir, keep a TWO-digest VAP rotation window, update renderer +
  SEA-component pins, then advance the commit-pinned dev-preview-platform
  app — stacks-only changes never auto-advance it.

## Lifecycle Workflow

1. **Prepare.** Confirm dev health, host image/flags, preview capacity, source
   revision, service catalog, required credentials, and zero conflicting
   platform rollout.
2. **Validate source changes.** Run the focused preview tests and render checks
   before launching. Admission-policy changes require the launch-boundary test.
3. **Write intents inside the sync scope.** The receiver's diff-scope gate
   rejects ANY file outside the service's declared sync roots, with the exact
   file and allowed set in the error. An intent that edits e.g. `docs/` fails
   verification no matter how well the agent executes it — check the
   dev-preview registry `syncPaths` for the service before writing the intent.
4. **Launch through the product path.** Use the UI, Workflow MCP, or authenticated
   BFF lifecycle workflow. Do not create the CR or helper Jobs manually for a
   normal proof.
5. **Observe provisioning.** Follow the host execution, PreviewEnvironment CR,
   provisioner/runner Jobs, vCluster readiness, managed-agent registration, and
   application health.
6. **Observe development.** Stream adopted workflow-builder pod logs and the
   in-vCluster Sandbox Execution API logs while the run is active. Adopted pod
   logs can disappear after failure, so post-failure polling is insufficient.
7. **Verify edits.** Prove each selected service was adopted, synced, and live.
   Multi-service runs require one applied result per service and one shared sync
   generation, not independent generations.
8. **Verify gates.** Prove rejected generations do not promote, corrected
   generations can proceed, and receiver-authoritative diff scope blocks files
   outside the allowed set.
9. **Capture.** Inspect the draft PR for exact source identity and all intended
   service files. Do not merge a proof artifact.
10. **Seal evidence, then retain or teardown.** For terminal preview-local
   executions, verify a complete host evidence receipt. Follow the selected
   lifecycle policy and verify the complete contract rather than inferring
   cleanup from workflow completion.

## Retention Contract

For a retained interactive preview, verify all of the following:

- The lifecycle succeeds while the PreviewEnvironment remains available.
- Host status carries the interactive session URL when handoff is requested.
- A follow-up edit reaches the retained preview through the supported HMR/sync
  path.
- Write-oriented sync is frozen after retention; rejected writes are expected.
- The original lease is released and a later session can reattach through the
  supported handoff path.
- Final teardown still completes every current cleanup check.

Retention is not permission to leave ownership ambiguous. Record the preview
name, source revision, lease state, expiry, and explicit teardown owner.

## Multi-Service Proof

Before claiming multi-service support:

- Confirm the host deployment has the current feature gate and catalog.
- Select only preview-native services from the catalog.
- Prove batch adoption and service-specific workspaces.
- Prove one `APPLIED` result per service and one shared `SYNCED` generation.
- Exercise a real edit in every selected service.
- Confirm the draft PR contains every intended service change and no unrelated
  file.
- Complete the current teardown contract with no leaked leases, Jobs, pods,
  PVCs, namespaces, or agent mappings.

## Gate Proof

Impact review must be behaviorally demonstrated, not only enabled:

1. Produce a generation that violates the requested impact rule.
2. Capture the rejection receipt and prove it did not become the accepted
   generation.
3. Correct the change in the next iteration and prove acceptance.
4. Separately attempt an out-of-scope generated-file edit and prove the receiver
   rejects it as `out_of_scope_changes`.

Use the current receipt schema and tests as truth for exact fields.

## Teardown Gate

The platform currently exposes a 12-check teardown contract. Read the named
checks from source and require `12/12`; do not replace them with a smaller
hand-written checklist. Also inspect helper Sandbox/PVC cleanup separately from
preview-vCluster cleanup.

Refusals and their designed escape paths (all `retryable: false` — retrying
verbatim never helps):

- `active-use` naming a preview-LOCAL execution: stop that child first through
  the preview's own UI or preview-local Workflow MCP, then tear down normally.
- `active-use` naming the HOST parent: if the row is stale the reconciler
  repairs it within a tick; a run finalizing its OWN preview is exempted via
  `finalizingExecutionId` (never spoof another run's id). One row class does
  NOT self-repair: an active row that never attached a durable instance id is
  owned by the start-orphan sub-lane, which is observe-only by default, so it
  will keep blocking teardown until that gate is flipped or the row is resolved
  through a supported path.
- `archive-required` / `executions-bad-response` (the preview's BFF is dead):
  first determine whether complete evidence can still be reconciled.
  `forceFailed: true` is the DESIGNED path for `failed` / aged-out
  `provisioning` previews — it quarantines with an explicit loss receipt. For
  other states an admin `discardUnarchived: true` proceeds only on positive
  host evidence (populated namespace, zero live agent pods); an empty namespace
  stays refused except for `slept`.
- Never bypass with kubectl deletes of the CR: the 12-check contract and
  quarantine receipts only exist on the supported path.

## Safety Rules

- Dev cluster only. Never redirect preview proof to ryzen.
- Do not trigger ArgoCD syncs or host-BFF/control-plane rollouts while a proof
  run is executing; transient host disruption can invalidate the run.
- Use fresh worktrees from `origin/main` for code changes and preserve dirty
  shared checkouts.
- Run `scripts/gitops/render-workflow-builder-release-overlays.sh` for generated
  preview pins or overlays; never hand-edit them.
- Run `deployment/scripts/tests/test-preview-job-launch-boundary.sh` before any
  preview VAP/CEL change.
- Never print preview credentials, vCluster kubeconfigs, session assertions, or
  SEA secrets.
- Never merge agent-artifact proof PRs.

## Failure Capture

For an intermittent or pre-promotion failure, collect concurrently while the
run is live:

- Host lifecycle execution status and activity number.
- PreviewEnvironment status and recent events.
- Provisioner/runner Job logs.
- Adopted workflow-builder pod, app container, and `daprd` logs.
- In-vCluster SEA/Sandbox pod logs.
- Lease, sync-generation, and receipt state.
- The sealed evidence key/completeness after the telemetry grace, when the run
  is terminal.

Compare one minimal control run with one changed variable. Do not vary retention,
service count, gates, and source revision at the same time.

## Canonical Sources

Workflow Builder:

- `docs/preview-environments.md`
- `docs/execution-evidence.md`
- `docs/host-preview-development-lifecycle.md`
- `docs/preview-environment-agent-development.md`
- `docs/preview-governance-gate.md`
- lifecycle fixture, preview API routes, and preview tests

Stacks:

- `docs/preview-environment-{architecture,runbook}.md`
- `docs/preview-{governance-gate,activation-image-builds}.md`
- `packages/components/workloads/workflow-builder-preview-vcluster/`
- `deployment/scripts/tests/test-preview-*.sh`
- `scripts/gitops/validate-preview-vcluster-surface.sh`
