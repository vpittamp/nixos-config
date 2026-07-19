---
name: evaluations
description: "Build, run, inspect, or debug Workflow Builder evaluations and official SWE-bench benchmarks on dev. Use for datasets, eval definitions, graders, code-eval templates, benchmark campaigns, exact-ready inference images, Kueue capacity, evaluator Jobs, runtime/provider canaries, MLflow comparison, provenance, cancellation, and cleanup. Use gitops for image delivery and workflow-builder for general workflow or session behavior."
---

# Evaluations

Use `dev` for shared evaluation work unless the user explicitly names another
target. Do not copy model defaults, capacity limits, or previous run IDs from
this skill; resolve them from current code, runtime registry, deployment env,
and live capacity.

## Two Product Models

| Model      | Use it for                                                 | Primary storage and surface                      |
| ---------- | ---------------------------------------------------------- | ------------------------------------------------ |
| Evaluation | Dataset + reusable eval definition + run + ordered graders | `evaluation_*`, `/workspaces/<slug>/evaluations` |
| Benchmark  | Official SWE-bench inference and harness evaluation        | `benchmark_*`, `/workspaces/<slug>/benchmarks`   |

The legacy SWE-bench evaluation template is not the official harness path.
Use the Benchmarks surface whenever official resolved/unresolved outcomes and
harness provenance are required.

## Start From Source

```bash
WFB_ROOT=/home/vpittamp/repos/PittampalliOrg/workflow-builder/main
STACKS_ROOT=/home/vpittamp/repos/PittampalliOrg/stacks/main
git -C "$WFB_ROOT" fetch origin
git -C "$WFB_ROOT" status --short --branch
```

Use clean worktrees for edits. Before changing behavior, inspect the route,
application service, coordinator, runtime, manifests, and tests that own the
reported stage.

## Task Map

| Task                                         | Read or inspect                                                                                     |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Evaluation data model, UI, and run lifecycle | `src/lib/server/evaluations/`, evaluation routes/components, and `services/evaluation-coordinator/` |
| Grader behavior                              | `graders.ts`, `grader-runners.ts`, and the target runtime grader endpoint                           |
| Code-eval templates                          | Template API routes and saved `code-eval-item` workflow definition                                  |
| Official SWE-bench operations                | `docs/swebench-dapr-workflow-operations.md`                                                         |
| Concurrency and admission                    | `docs/swebench-concurrency.md`, Kueue manifests, and live capacity snapshots                        |
| Inference images and exact-ready selection   | `docs/swebench-image-builds-and-caching.md` and environment build code                              |
| Same-instance comparisons and MLflow         | `docs/swebench-mlflow-comparison.md` and `docs/benchmark-statistics.md`                             |
| Runtime selection or capability mismatch     | `services/shared/runtime-registry.json` and `docs/durable-session-runtime-contract.md`              |
| Image rollout                                | Use the `gitops` skill                                                                              |

## Run Workflow

1. **Define the question.** Separate product correctness, model quality,
   runtime routing, infrastructure capacity, and evaluator correctness. Do not
   use one run to answer all five.
2. **Select the model.** Choose Evaluation or Benchmark explicitly. Record the
   target project, subject, saved version, runtime, model key, suite, and fixed
   instance set where applicable.
3. **Preflight readiness.** Verify orchestrator readiness, runtime capability,
   exact environment coverage, Kueue quota, node headroom, evaluator capacity,
   provider limits, and zero conflicting active work.
4. **Launch through the owning surface.** Use the UI, authenticated application
   API, or checked-in launch script. Do not create or repair runs with direct
   SQL.
5. **Observe stage transitions.** Follow the parent run, coordinator workflow,
   per-item execution/session, Sandbox and Kueue Workload, inference events,
   predictions artifacts, evaluator Job/TaskRuns, and callback.
6. **Verify results and provenance.** Confirm selected instance coverage,
   prediction validity, artifact hashes, evaluator image, harness output,
   runtime/model identity, and active-resource cleanup.
7. **Cancel through the owner.** Cancel the evaluation or benchmark run; do not
   stop a coordinator-owned instance independently.

## Diagnosis Ladder

For a stuck or zero-token benchmark, check in order:

1. Run and instance status plus active resource leases.
2. Preflight child workflow and exact-ready environment decision.
3. Hub environment-image PipelineRun when a build is required.
4. Workflow execution and session IDs.
5. Kueue admission and Sandbox/pod readiness.
6. Runtime and `daprd` logs.
7. `agent.llm_usage` and terminal session events.
8. Predictions/dataset artifacts and evaluator Job.
9. Internal callback and final summary recomputation.

This order distinguishes build waiting, queue pressure, runtime startup,
provider failure, and harness failure without mutating state.

## Stable Invariants

- Official SWE-bench resolved/unresolved status comes from the harness callback,
  not an LLM scorer or a UI inference.
- Random launch readiness and coordinator preflight must use the same exact
  environment-spec predicate. A coarse repo/version match is insufficient.
- Effective concurrency is the minimum of BFF policy, Kueue quota, node
  headroom, runtime slots, Dapr worker limits, evaluator capacity, image
  readiness, and provider limits.
- Benchmark scorers and Evaluation graders are separate lifecycles and storage
  models even when they reuse transport code.
- Runtime identity comes from the saved run, runtime registry resolution,
  workflow output, traces, and live image/env. A workspace template or container
  label alone is not proof.
- Cancellation is request/confirm work owned by the run and Lifecycle
  Controller. Product rows must not be marked terminal before durable children
  and Sandboxes converge.
- `workflowstatestore` remains the sole actor/workflow state store. Do not add a
  per-agent actor store to solve an evaluation incident.

## Safety Rules

- Do not roll workflow-builder, orchestrator, coordinator, evaluator, or agent
  runtime images while a proof run is active; durable replay can break across
  code schedules.
- Do not raise concurrency from a historical checkpoint. Read current live
  capacity and increase one layer at a time.
- Do not run parallel benchmark campaigns on ryzen unless explicitly requested
  and capacity-proven.
- Do not expose dataset secrets, provider keys, predictions, or admin database
  credentials in logs or PRs.
- Do not treat an empty patch as infrastructure failure when the harness records
  it as a valid model outcome.
- Do not merge or deploy an image change until the `gitops` delivery chain and
  live runtime identity are proven.

## Completion Evidence

A useful handoff records:

- Target, source revision, run ID, and fixed cohort.
- Agent/version, runtime, model key, and effective concurrency.
- Exact-ready environment source and image digest summary.
- Stage timings, official outcomes, grader/scorer results, and artifacts.
- Evaluator identity and provenance.
- Final counts for active runs, leases, sessions, workflows, Sandboxes, and
  evaluator workloads.

## Canonical Sources

- `docs/swebench-concurrency.md`
- `docs/swebench-dapr-workflow-operations.md`
- `docs/swebench-image-builds-and-caching.md`
- `docs/swebench-mlflow-comparison.md`
- `docs/benchmark-statistics.md`
- `src/lib/server/evaluations/`
- `src/lib/server/benchmarks/`
- `src/routes/api/{evaluations,benchmarks,internal/benchmarks}/`
- `services/{evaluation-coordinator,swebench-coordinator,swebench-evaluator}/`
- `services/shared/runtime-registry.json`
- stacks workload, Kueue, Tekton, and release-pin manifests
