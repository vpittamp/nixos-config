---
name: evaluations
description: "Build, run, inspect, or debug Workflow Builder evaluation campaigns on dev, including native datasets, immutable subjects, scorers, SWE-bench official harnesses, Harbor task/verifier adapters, DSPy offline optimization inputs, provenance, cancellation, and cleanup. Use kubernetes-capacity for shared Kueue or physical-capacity policy and gitops for image delivery."
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
- stacks `docs/evaluation-control-plane.md`
- workflow-builder `src/lib/server/application/domain/evaluations/`
- workflow-builder `src/lib/server/application/ports/evaluation-control-plane.ts`
- workflow-builder `services/evaluation-orchestrator/`
- stacks `packages/components/workloads/evaluation-control-plane/`

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
7. Verify exact task/subject/repetition coverage, immutable digests, model and
   runtime identity, scores, scorer/harness provenance, and resource cleanup.

Campaigns also appear in unified Runs. Use the campaign detail for frozen
snapshot, capacity arithmetic, trial/score matrix, environment artifacts, and
lineage; use Runs for the common activity and trace lens.

UI ownership is deliberate:

- Dashboard and Runs show the campaign parent and its ordinary workflow child
  once a trial reaches subject execution.
- Workflows is the reusable-definition catalog. It shows `Evaluation coding
  subject` and its recent ordinary child executions, but must not duplicate the
  campaign parent.
- A campaign parked on environment preparation or capacity has no ordinary
  workflow child yet, so it belongs only in Dashboard/Runs and Evaluations.

## SWE-bench

- Freeze the Hugging Face dataset to a revision.
- Treat each imported `offset`/row-count window as a distinct immutable dataset
  version. Re-importing another window must not reuse the project/name/version
  identity or attach cases to an older subset.
- Resolve the official `swebench/sweb.eval.x86_64.<instance>` Docker Hub image
  to its linux/amd64 platform digest; do not launch from `latest`.
- Validate the `openshell-compat-v4` boundary: default user and primary group
  `sandbox`, non-root UID, `HOME=/sandbox`, writable `/sandbox/.git`, Python,
  Git, POSIX shell, `ip`, and `getent`. If the official image fails, the
  expected path is a separate minimal hub-built compatibility image; never
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
native catalog. Shared-image verifiers run in the task image. A separate
verifier image must be digest-pinned and receives only the declared artifact
boundary. Require canonical `reward.json`/`reward.txt`, logs, and provenance;
Harbor containers do not own campaign state or retries.

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

## Diagnosis order

1. Campaign snapshot, status, cancellation intent, and lineage.
2. Environment artifact discovery/resolution/build/validation receipt.
3. Fresh capacity decision and Kueue admission condition.
4. Trial ordinary workflow execution, session/Sandbox, runtime image, and Dapr
   sidecar/workflow worker readiness.
5. Subject output/patch and scorer plan.
6. Harness TaskRun, verifier logs, callback/event, and score provenance.
7. Cleanup receipt and reconciler result.

This order separates build waiting, capacity parking, runtime failure, subject
failure, scorer failure, and cleanup convergence without mutating evidence.

For a Dapr multi-app error saying an orchestrator was not registered, verify in
this order: the target worker calls `register_workflow(..., name=<exact
versioned public name>)`; the parent uses that same name with the target
`app_id`; both apps are in the same namespace and share the same actor state
store; then inspect `WorkflowAccessPolicy`. A Python bound-method name is an
implementation detail and must never become the cross-app durable identity.

The platform-owned evaluation subject is reconciled from the canonical seed;
ordinary saved workflows remain owner-editable. Do not launch a campaign while
that seed/Deployment rollout is converging: publish the immutable subject only
after the live workflow spec digest is stable.

## Safety and delivery

- Do not roll workflow, evaluation, scorer, harness, or runtime images during a
  proof campaign whose replay depends on them.
- Do not expose provider keys, dataset secrets, expected answers, patches from
  private data, internal tokens, or kubeconfigs.
- Use `kubernetes-capacity` for quota/cohort/PSI tuning, `gitops` for builds and
  Argo delivery, and `workflow-builder` for non-evaluation workflow behavior.
- Never resize, reprovision, replace, or delete Hetzner servers. Software
  upgrades use separately authorized in-place Talos procedures.

Completion evidence must link source SHA -> hub PipelineRun -> GHCR digest ->
release pin/render -> Argo sync/health -> live image/env -> canonical campaign.
Record task coverage, subject/runtime/model identity, effective concurrency,
environment digests, scores/provenance, terminal lineage, and final absence of
TaskRuns, Workloads, Sandboxes, leases, and active workflow resources.
