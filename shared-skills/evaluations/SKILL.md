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

## SWE-bench

- Freeze the Hugging Face dataset to a revision.
- Resolve the official `swebench/sweb.eval.x86_64.<instance>` Docker Hub image
  to its linux/amd64 platform digest; do not launch from `latest`.
- Require exact-ready artifact coverage before start.
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

Dapr `COMPLETED` does not prove product success: a workflow can return an error
envelope. Require the explicit terminal outcome and scorer evidence. Never
infer terminal rows from a missing Dapr instance or edit them to unblock the UI.

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
