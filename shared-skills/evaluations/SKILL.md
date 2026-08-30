---
name: evaluations
description: "Build, run, inspect, or debug Workflow Builder evaluation campaigns on dev, including native datasets, immutable subjects, frozen runtime topology, scorers, SWE-bench official harnesses, Harbor task/verifier adapters, DSPy offline optimization inputs, provenance, cancellation, and cleanup. Use kubernetes-capacity for shared Kueue or physical-capacity policy and gitops for image delivery."
---

# Evaluations

Use the canonical evaluation control plane on `dev`. SWE-bench and Harbor are
catalog/environment/scorer adapters, not separate products or coordinator
stacks. Historical benchmark and first-generation evaluation rows are
throwaway after the full cutover; do not restore their APIs or runtime paths.

Resolve the current workflow-builder/stacks source, runtime registry, desired
images, rendered manifests, and live capacity before using a model, version,
run ID, limit, or image reference.

## Architecture boundary

Keep the evaluation bounded context hexagonal:

- application services own campaign creation, admission, cancellation, cleanup,
  and read models;
- ports describe catalog, campaign persistence, Dapr orchestration, capacity,
  OCI environments, scorers, lineage, and cleanup;
- Postgres, Dapr, capacity-observer, registries, Harbor, Hugging Face,
  Tekton/Kueue, and lifecycle control are adapters;
- domain/application code must not import Kubernetes, registry, Dapr SDK, or
  database clients;
- Python orchestrator domain/ports stay separate from Dapr and HTTP adapters.

The durable tree is campaign -> shard -> trial -> ordinary dynamic-script
workflow -> scorer workflow. Subject execution must reuse the normal workflow
engine. Reference answers, expected patches, and verifier scripts are
scorer-only; never place them in subject input.

Read first:

- workflow-builder `docs/evaluation-control-plane.md`
- workflow-builder `docs/agent-runtime-comparison.md`
- stacks `docs/evaluation-control-plane.md`
- workflow-builder `src/lib/server/application/domain/evaluations/`
- workflow-builder `src/lib/server/application/ports/evaluation-control-plane.ts`
- workflow-builder `services/evaluation-orchestrator/`
- stacks `packages/components/workloads/evaluation-control-plane/`

## Runtime topology

A subject's execution topology is a registry fact, resolved once at publish and
frozen into the immutable subject version as its `executionProfile`
(`wfb.evaluation-subject-execution/v1`). Domain and application code consume
that frozen value through ports and never read the runtime registry,
Kubernetes, or the environment; only the subject-runtime adapter resolves it.
`evaluation-runtime-topology-boundary.test.ts` enforces that split. A subject
predating the frozen contract is rejected outright — there is no inference
fallback and no migration.

Read `services/shared/runtime-registry.json` for the live set rather than
trusting a remembered list. As of the harness cutover:

- `dapr-agent-py` — `hostMode: harness`, workspace `openshell-shared`. The LLM
  loop runs on the replicated `dapr-agent-harness` Deployment and tools run in
  a shared OpenShell workspace (`evaluation-trial-<id>` for a trial), with no
  per-session executor pod. This is the default for evaluation subjects.
- `dapr-agent-py-local` — `hostMode: harness`, workspace `sandbox-executor`.
  Loop on the harness, tools in a per-session executor pod.
- CLI/CUA/browser descriptors — `hostMode: per-session-pod`, a declared
  capability exception for a native PTY, CUA device, or browser sidecar.

The former `shared-pool` host mode, `agent-runtime-pool-*` workloads, and the
`dapr-agent-py-harness` alias are retired. Do not reintroduce those names or
infer physical topology from a runtime id, app id, env var, or pod name.

Two consequences, both publish-time:

- The provider-budget observer app-id is derived from the runtime's `hostMode`
  (`harness` resolves `harnessAppIdForRuntime`, default `dapr-agent-harness`;
  other host modes have no standing app and resolve to null) and is frozen with
  the profile. Changing a subject's topology requires a republish; editing a
  live runtime never re-points an already-published subject.
- Comparing topologies means republishing the subject **alone**. Attach the new
  subject version to the SAME immutable dataset, task, and scorer versions, so
  the only difference between the two campaigns is the subject. Only then does
  a difference in outcome belong to the topology. Identical outcomes across
  topologies on the same sealed windows are the expected, correct result — not
  a null finding — and a divergence is a topology defect worth escalating.

## Campaign workflow

1. Define the question and distinguish subject quality, runtime correctness,
   capacity, environment preparation, and scorer correctness.
2. Publish a versioned dataset, immutable subject version, and scorer versions.
   Native, SWE-bench, and Harbor imports must normalize into the same records.
3. Confirm task environments are linux/amd64, digest-pinned, and `ready` with a
   validation receipt. Builds are separate hub work; campaigns never build an
   image in-band.
4. Inspect `/workspaces/<slug>/capacity/debug`. Requested concurrency is only a
   ceiling; fresh exact-shape quota/cohort and physical-headroom evidence decides
   each shard. Stale observer data must park and retry.
5. Start through the Evaluations UI or authenticated canonical API. Do not
   create, repair, or terminalize rows with SQL.
6. Follow campaign lineage, trial ordinary workflow/session, Kueue Workload or
   TaskRun, scorer completion, artifacts, and terminal outcome.
7. Verify exact task/subject/repetition coverage, immutable digests, model,
   runtime and topology identity, scores, scorer/harness provenance, and
   resource cleanup.

Campaigns also appear in unified Runs. Use the campaign detail for frozen
snapshot, capacity arithmetic, campaign score/performance analytics,
environment artifacts, and lineage; use Runs for the common activity and trace
lens.

UI ownership is deliberate:

- Dashboard and Runs show the campaign parent and its ordinary workflow child
  once a trial reaches subject execution.
- Workflows is the reusable-definition catalog. It shows `Evaluation coding
  subject` and its recent ordinary child executions, but must not duplicate the
  campaign parent.
- A campaign parked on environment preparation or capacity has no ordinary
  workflow child yet, so it belongs only in Dashboard/Runs and Evaluations.

## Publishing and immutable identity

Publishing is content-addressed, so most publish failures are identity
failures. Check these before debugging a 422 or a prepare-time digest error:

- `HARBOR_EXECUTION_PROFILE_VERSION` (in `domain/evaluations/harbor.ts`) is
  part of the derivation identity. Bump it in the same change that alters the
  derivation output; otherwise publishing the changed derivation collides with
  the stored version and fails `already exists with different content`.
  Datasets derived under an older profile keep their immutable identity — only
  new publishes take the fresh version key.
- `provenance.requestedReference` is excluded from the dataset content digest
  by `evaluationDatasetContentIdentity`. The caller's spelling of a registry
  reference (`name` versus `name@sha256:...`) is provenance, not content, so a
  second publish of the same resolved package attaches a new subject to the
  existing dataset instead of tripping the duplicate guard. Never fold that
  field back into the digest.
- The platform-owned evaluation subject is reconciled from the canonical seed.
  Changing the seed changes the reconciled workflow spec digest, and every
  already-published immutable subject version then fails at trial prepare with
  `Evaluation subject workflow digest no longer matches its version`
  (preparation stage, platform owner). Republish subjects after any seed
  change, and publish only once the live workflow spec digest is stable — never
  while that seed or Deployment rollout is still converging.

Ordinary saved workflows remain owner-editable; the subject seed does not.

## Environment artifacts and readiness

An artifact row advances `importing -> building -> validating -> ready` only
while something polls the compatibility adapter for it. A cancelled campaign, a
failed launch, or a BFF restart leaves nothing polling.

- The `*/2` lifecycle reconciler (stacks
  `CronJob-evaluation-lifecycle-reconciler.yaml` posting to
  `/api/internal/evaluation-control/reconcile`) reconciles stale in-flight
  artifacts alongside cancellation, harness failures, and preparation. A stale
  build is re-requested a bounded number of times and then set `failed` with an
  error, so readiness stops waiting instead of parking forever. Retry
  bookkeeping lives in `provenance.reconciliation` (`retryCount`,
  `lastRequeueAt`, `lastRequeueReason`); an absent key means never requeued.
- That route returns 503 while any lane still has pending durable intent, and
  the CronJob uses `curl --fail`. A red reconciler Job is visible unconverged
  intent, not necessarily a broken lane; read the per-lane `pending` arrays.
- Readiness surfaces the waiting set per task as `waitingTaskCases`
  (`taskCaseId`, `stage`, `retryCount`, `lastRequeueAt`). A campaign parked on
  environment preparation with a climbing `retryCount` is a build problem; a
  flat `retryCount` with no reconciler activity is a lane problem.
- Compatibility-validation TaskRuns and their pods are garbage-collected one
  hour after completion (stacks `CronJob-evaluation-taskrun-cleanup.yaml`). The
  validation receipt is persisted on the environment row before the TaskRun
  goes terminal, so the TaskRun is a short forensic window and never the
  record. A missing TaskRun is not a lost validation.

## SWE-bench

- Freeze the Hugging Face dataset to a revision.
- Treat each imported `offset`/row-count window as a distinct immutable dataset
  version. Re-importing another window must not reuse the project/name/version
  identity or attach cases to an older subset.
- Resolve the official `swebench/sweb.eval.x86_64.<instance>` Docker Hub image
  to its linux/amd64 platform digest; do not launch from `latest`.
- Validate the current `openshell-compat-v7` boundary: default user and primary
  group `sandbox`, non-root UID, `HOME=/sandbox`, writable `/sandbox/.git`,
  Python, Git, POSIX shell, `ip`, `getent`, and `rg`. A compatibility wrapper
  seeds the official `/testbed` checkout into the native `/sandbox` workspace
  without removing image-baked ignored artifacts. If the source image fails,
  the expected path is a separate minimal hub-built compatibility image; never
  modify the image during campaign execution.
- Require exact-ready artifact coverage before start.
- Require the `evaluation-hermetic` OpenShell policy profile for subject
  workspaces. Subject commands are outbound-default-deny: inference and the
  official harness run outside that sandbox, so the checkout needs no source
  host, package registry, or model-provider access.
- Prove hermeticity on a canary by attempting a bounded request to the task's
  public source host from the subject workspace. Any successful source lookup,
  including reference-code access through `raw.githubusercontent.com`,
  contaminates the result: cancel the campaign, discard its scores, correct the
  policy boundary, and rerun from a fresh immutable trial.
- Each harness step must declare ephemeral-storage requests and limits. Keep
  every container within the namespace LimitRange ratio so Kueue can account
  the materialized TaskRun instead of losing it at pod admission.
- Treat official harness output as the resolution authority. An empty patch is
  a valid subject outcome, not automatically infrastructure failure.
- A useful canary proves ordinary dynamic-script inference, official verifier
  scoring, immutable environment provenance, terminal lineage, and cleanup.

## Harbor

The Harbor anti-corruption adapter converts a versioned task bundle into the
native catalog. Shared-image verifiers run in the task image; a separate
verifier image must be digest-pinned and receives only the declared artifact
boundary. Require canonical `reward.json`/`reward.txt`, logs, and provenance;
Harbor containers do not own campaign state or retries.

**Verifier execution.** Scoring runs against the RETAINED sandbox rather than
replaying a captured patch, whenever the trial qualifies: adapter `harbor`,
verifier `environmentMode: shared`, and an ordinary-workflow sandbox claim
whose workspace topology is OpenShell-shared. `resolveHarborVerifierExecution`
then returns `retained-sandbox`, and the Tekton `evaluation-harbor-trial` Task
execs the tests into the sandbox the agent actually mutated. Non-git workspace
state — installed packages, running services, files outside the checkout —
survives into scoring, matching Harbor's own shared-verifier semantics.

Patch replay stays the plan, by typed reason, for `not-harbor`,
`separate-verifier-image`, `no-retained-sandbox-claim`, and
`workspace-topology-not-shared`; pod-local CLI runtimes only sync a patch
artifact into their sandbox, so they can never qualify. Read the mode from the
scorer provenance (`verifier.execution`) before interpreting any Harbor score.

That distinction is the triage rule: with `verifier.execution =
retained-sandbox`, a reward of 0 alongside a real test failure is a genuine
subject failure. Do not reopen it as an infrastructure defect and do not
attribute it to lost workspace state — that failure mode is closed on this
path. A missing or unparseable `reward.json` is still a scorer fault.

The tests bundle is injected only after the subject reaches terminal, so the
subject can never read the verifier. Workspace retention is derived, not
hand-configured: the subject receives only a retention flag and a TTL backstop
(agent timeout plus verifier timeout plus cleanup grace). Scorer-stage cleanup
deletes the sandbox as soon as the score is durable, so a retained sandbox
outliving a durable score is a cleanup defect, not a safety margin.

An agent deadline is a policy, not automatically a lost trial: a definition
whose task config sets `executionBudget.onDeadline: verify-partial` captures
the workspace at the deadline and still scores it. Definitions without a valid
budget keep the historical `terminate` behaviour, so read the frozen definition
before calling a timed-out trial unscoreable.

## DSPy

DSPy is an optional offline optimizer adapter. It may propose versioned
instructions, demonstrations, plans, or dynamic scripts, but it must not call
`action()`, save workflows, access credentials/Kubernetes, or own Dapr
execution. Publish each candidate as an immutable subject and compare it in a
canonical campaign. Select/promote from canonical scores only.

For dynamic-script authoring, keep the reviewed platform contract fixed and
optimize `SelectActions -> DraftScript -> RepairScript`. Apply deterministic
validation/action-schema gates before semantic scoring. Start with a baseline
and BootstrapFewShot, then GEPA for feedback-rich failures; compare MIPROv2 only
when joint instruction/demo search is justified. DSPy `compile()` remains an
offline batch activity, not a Dapr workflow scheduler.

## Cancellation and terminal truth

Cancel the campaign through its owner. The required order is harness cleanup,
ordinary workflow lifecycle purge, confirmed absence/removal, then terminal
trial/campaign/lineage writes. The cancellation reconciler retries abandoned
requests using the same ports and leaves rows nonterminal while cleanup is
pending.

Evaluation trials are immutable and throwaway, so their lifecycle adapter uses
`reset` for cancellation. If Dapr reports the workflow terminal but rejects
purge with `actor is stalled`, the lifecycle controller may delete only the
resolved, execution-scoped durable state; it must still reap the Sandbox and
workspace before terminal rows are written. Do not emulate this with SQL.

Dapr `COMPLETED` does not prove product success: a workflow can return an error
envelope. Require the explicit terminal outcome and scorer evidence. Never
infer terminal rows from a missing Dapr instance or edit them to unblock the UI.
Cancellation of an already terminal campaign is an idempotent no-op. If a
terminal row moves back to `cancelling`, treat that as a lifecycle defect; both
the application service and persistence adapter must protect the terminal
outcome boundary against a late-write race.

## Campaign analytics

Campaign detail consumes the canonical analytics application port with the
exact project and campaign ID. It must not query Postgres, ClickHouse, Kueue,
or trace storage from presentation code. Use the authenticated
`/api/evaluation-analytics?range=all&campaign=<campaign-id>` projection when a
machine-readable view is needed.

Interpret the page precisely:

- campaign wall duration and summed trial duration are different; their ratio
  makes parallel overlap visible;
- the headline token count is input plus output, while cache read and cache
  creation remain separate provider-accounting facts;
- canonical session events own LLM calls, tool calls/errors, first-LLM and
  first-tool latency, and per-trial trace links;
- observed peak CPU/memory is not a Kubernetes request, Kueue reservation, or
  capacity decision;
- direct API cost is shown only from the campaign's frozen rate-card basis;
  subscription and unknown subjects remain explicitly unpriced; and
- compare one exact scorer-version and metric at a time. Never average values
  across scorer versions or scales.

Use the interactive metric bars and outcome filter to find outliers, then open
the selected ordinary workflow trace. Missing usage or duration on a terminal
trial is a data-quality fault, not a zero observation.

## Diagnosis order

1. Campaign snapshot, status, cancellation intent, and lineage.
2. Environment artifact discovery/resolution/build/validation receipt, plus
   `waitingTaskCases` and `provenance.reconciliation` for anything in flight.
3. Fresh capacity decision and Kueue admission condition.
4. Trial ordinary workflow execution, session/Sandbox, frozen
   `executionProfile`, runtime image, and Dapr sidecar/workflow worker
   readiness.
5. Subject output/patch and scorer plan.
6. Harness TaskRun, `verifier.execution` mode, verifier logs, callback/event,
   and score provenance.
7. Cleanup receipt and reconciler result.

This order separates build waiting, capacity parking, runtime failure, subject
failure, scorer failure, and cleanup convergence without mutating evidence.

For a Dapr multi-app error saying an orchestrator was not registered, verify in
this order: the target worker calls `register_workflow(..., name=<exact
versioned public name>)`; the parent uses that same name with the target
`app_id`; both apps are in the same namespace and share the same actor state
store; then inspect `WorkflowAccessPolicy`. A Python bound-method name is an
implementation detail and must never become the cross-app durable identity.

Upstream provider errors (for example repeated HTTP 500s tripping the circuit
breaker) surface as trial `error`, not as a topology or scorer fault. Rerun the
campaign rather than republishing definitions.

## Safety and delivery

- Do not roll workflow, evaluation, scorer, harness, or runtime images during a
  proof campaign whose replay depends on them.
- Do not expose provider keys, dataset secrets, expected answers, patches from
  private data, internal tokens, or kubeconfigs.
- Use `kubernetes-capacity` for quota/cohort/PSI tuning, `gitops` for builds and
  Argo delivery, `runtime-conformance` to verify a runtime before a subject
  depends on it, and `workflow-builder` for non-evaluation workflow behavior.
- Never resize, reprovision, replace, or delete Hetzner servers. Software
  upgrades use separately authorized in-place Talos procedures.

Completion evidence must link source SHA -> hub PipelineRun -> GHCR digest ->
release pin/render -> Argo sync/health -> live image/env -> canonical campaign.
Record task coverage, subject/runtime/topology/model identity, effective
concurrency, environment digests, scores/provenance including
`verifier.execution`, terminal lineage, and final absence of TaskRuns,
Workloads, Sandboxes, leases, and active workflow resources.
