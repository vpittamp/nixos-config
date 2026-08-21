---
name: kubernetes-capacity
description: "Audit, tune, and prove shared Kubernetes capacity across PreviewEnvironments, interactive agents, warm pools, evaluations, benchmarks, and secure sandboxes. Use for Kueue quota, cohorts, priority, capacity-observer and PSI signals, exact preview plans, physical headroom, session fits, dynamic concurrency, idle-return policy, and Kueue upgrade validation. Use preview-environments for lifecycle actions, evaluations for campaign launches, talos-clusters for node or OS upgrades, and gitops for delivery."
---

# Kubernetes Capacity

Treat capacity as a live decision made from exact workload shapes, Kueue
admission, physical headroom, and observed pressure. Never infer it from a
single quota, pod count, node count, UI limit, or historical estimate.

## Start From Current Authority

Read current source before using remembered versions or limits:

- stacks `docs/capacity-management.md`
- stacks `docs/preview-environment-architecture.md`
- stacks `packages/components/workloads/kueue-capacity/`
- stacks `packages/components/workloads/capacity-observer/`
- stacks preview-control and system-executor manifests
- Workflow Builder `docs/session-resource-metrics-and-kueue-admission.md`
- stacks and Workflow Builder `docs/evaluation-control-plane.md`
- Workflow Builder preview capacity compiler, pressure policy, API, and page

Inspect the rendered target and live cluster after source. Distinguish desired,
rendered, and live versions explicitly; do not copy version or capacity values
into this skill.

## Decision Layers

Keep these layers separate when explaining a refusal or safe concurrency:

1. **Product and lifecycle policy**: total objects, awake previews, idle sleep,
   protected work, and public-origin availability.
2. **Exact workload shape**: immutable requests compiled from profile,
   selected services, execution concurrency, and safety margin.
3. **Kueue ledger**: LocalQueue, ClusterQueue, cohort borrowing, priority,
   admission, inadmissibility, and preemption policy.
4. **Physical schedulability**: allocatable minus requested resources on
   eligible Ready nodes, including CPU, memory, pods, and ephemeral storage.
5. **Observed pressure**: fresh capacity-observer measurements, utilization,
   PSI, and historical session metrics.
6. **Exposure**: a public preview also consumes an origin; a headless preview
   does not. Origin exhaustion is not Kubernetes exhaustion.

The safe count is the minimum fit across every applicable layer and resource.
Report both the binding dimension and the arithmetic.

## Audit Workflow

1. Fetch current repository state and identify the target cluster and queue.
2. Compare source, rendered, and live Kubernetes, Talos, Kueue, CNI, and
   capacity-controller versions.
3. Open `/workspaces/<slug>/capacity/debug` for the product-facing explanation
   of decision inputs, exact reservations, materialized and observed usage,
   queue arithmetic, node headroom, PSI, lifecycle timers, and raw snapshot.
4. Inspect ClusterQueues, LocalQueues, cohorts, admitted Workloads, pending
   reasons, priorities, and AdmissionChecks.
5. Read a forced-fresh capacity-observer snapshot and verify its age, coverage,
   eligible-node set, requested headroom, utilization, and PSI warnings.
6. Inspect the exact synthetic preview Workload or session Workload. Do not
   substitute a fixed per-preview reservation for the immutable plan.
7. Separate queue quota, physical headroom, lifecycle limits, provider or
   evaluator concurrency, and origin availability in the conclusion.
8. Use historical request and observed-usage metrics to propose right-sizing;
   do not make observed usage the admission contract without a bounded margin.

Useful read-only checks include:

```bash
kubectl --context dev get clusterqueue,localqueue,workload -A
kubectl --context dev describe clusterqueue <queue>
kubectl --context dev get nodes -o wide
kubectl --context dev top nodes
kubectl --context dev get pods -A -o wide
```

Use the current capacity-observer service/API contract from source rather than
a remembered URL. Never print secrets, kubeconfigs, or credential-bearing
request headers.

## Preview Admission

SEA compiles one immutable plan for each awake preview from its composable
platform, profile, selected services, execution concurrency, and margin. It
submits one synthetic Kueue Workload on physical dev. The Workload reserves
capacity; it is not a pod launcher. After Kueue admission, SEA requires fresh
physical-headroom evidence before provisioning.

`VCLUSTER_PREVIEW_MAX=0` means awake preview concurrency is delegated to exact
plans and capacity signals. The separate total-object cap remains lifecycle
protection. Do not reintroduce a fixed count gate or raise one ceiling while
ignoring the others.

For a refusal, report:

- stage and typed reason;
- exact requested shape;
- remaining quota and cohort borrowing allowance;
- physical headroom and observer freshness;
- limiting resource or origin; and
- the next safe action, such as sleeping an idle preview or choosing a smaller
  service set.

## Pressure And Elastic Return

Pressure may be asserted by pending queues, blocked Workloads, exhausted
physical headroom, zero reference fits, or configured memory/IO PSI thresholds.
Incomplete PSI coverage is a warning under the current deployed policy unless
source says otherwise.

The current PSI AdmissionCheck applies to benchmark, warm, and secure queues,
not preview or interactive-agent queues. Always verify the rendered profile
before relying on that scope.

Pressure only accelerates evidence-gated return of idle previews and warm
pools. It must not terminate active or protected work, bypass lifecycle owners,
or treat a missing observer as authorization to mutate. Preserve operator
cordons; a node guard may recover only nodes it owns under its current policy.

Evaluation concurrency follows the same live authority. Each Dapr campaign
shard asks the capacity port for an exact trial-shape decision. A stale observer
parks the campaign; it never fails the campaign or authorizes new work. The
materialized Tekton TaskRun or Sandbox remains Kueue-owned, while campaign
state and cancellation remain evaluation-owned.

## Changing Capacity Policy

Prefer changes in this order:

1. Correct stale or misleading product diagnostics.
2. Remove unnecessary preview services or make them dormant by profile.
3. Right-size exact requests using historical evidence and a safety margin.
4. Adjust queue/cohort lending and borrowing within physical limits.
5. Adjust lifecycle return policy while preserving active work.
6. Change physical infrastructure only under an explicit, separate request.

Change the authoritative source, render all capacity profiles, and review every
target before rollout. Keep Kueue quota, product policy, exact-plan logic, and
physical headroom as independent protections.

For a Kueue upgrade, verify current Kubernetes compatibility and release notes,
CRDs, controller image, feature gates, webhooks, generated manifests, and
upgrade/skew guidance. Prove existing Workloads survive and new admissions,
borrowing, priority, and cleanup behave as intended.

## Verification

Use the repository's current focused validators, including where applicable:

```bash
scripts/gitops/validate-kueue-capacity-profiles.sh
scripts/gitops/validate-preview-vcluster-surface.sh
deployment/scripts/tests/test-preview-job-admission-defaults.sh
```

Then prove the live path:

- capacity-observer is fresh and its eligible-node coverage is explained;
- ClusterQueues and LocalQueues are active with expected cohorts and checks;
- one representative exact preview plan admits and materializes correctly;
- the capacity debug page explains both an allowed and a refused decision;
- sleeping or teardown returns the synthetic Workload and quota;
- session/evaluation cleanup returns their Workloads and leases; and
- no active or protected work was reclaimed under pressure.

## Skill Boundaries And Safety

- Use `preview-environments` for launch, sleep, wake, DevelopmentRun, and signed
  teardown actions.
- Use `evaluations` for benchmark/evaluation campaign shape and launch.
- Use `gitops` to deliver capacity source changes and prove ArgoCD convergence.
- Use `talos-clusters` for Kubernetes, Talos, node, and CNI upgrades.
- Use `cluster-desired-state` only for an explicitly requested full-cluster
  rebuild or recovery.
- Never resize, reprovision, replace, or delete a Hetzner Cloud server during a
  capacity audit or software upgrade. Those actions may change preferred
  pricing and require separate explicit authority.
- Never hand-edit generated manifests, bypass Kueue, delete Workloads owned by
  another controller, or use a quota increase as proof of schedulability.
- Preserve unrelated work and use current `origin/main` worktrees for edits.
