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
- Workflow Builder `src/lib/server/application/preview-warm-pool.ts`

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
8. Attribute every preview to its owner before reasoning about free capacity:
   warm-pool members are platform-owned but occupy real quota.
9. Use historical request and observed-usage metrics to propose right-sizing;
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

## Preview Warm Pool

A warm pool of ready-to-adopt previews exists, so reusable preview capacity is
real. Treat its members as ordinary previews that happen to be platform-owned.

- Members are PreviewEnvironments owned by `automation/preview-warm-pool`, at
  the current baked baseline and catalog digest, headless, with no host project
  and no public origin. Being headless, a member consumes no origin, but it
  consumes the same CPU, memory, and lifecycle slots as any other preview.
- Replenishment launches through the ordinary admitted path. A member counts
  against the `preview-environments` Kueue queue exactly like a user's preview,
  and the full exact-shape Kueue and observer admission still runs inside the
  launch. There is no reserved pool quota and no bypass.
- Before launching, the lane checks a coarse headroom pre-condition and skips
  replenishment whenever it fails: `PREVIEW_WARM_POOL_HEADROOM_RESERVE`
  (default 1) leaves that many slots of the lifecycle cap free for real
  launches, against both the awake cap and the total-object cap. The pool can
  therefore lag real demand but must never starve it.
- Every non-deleting warm-owned CR occupies a pool slot whatever its phase, so
  counting only Ready members over-launches. Adoption transfers ownership to
  the user, which removes the member from pool capacity and triggers a
  replacement. The steady state to expect is one warm member plus whatever
  previews users actually hold — not one preview total.
- Default size is one (`PREVIEW_WARM_POOL_SIZE`). Sizing, TTL, headroom
  reserve, and launch cooldown are delivered as `PREVIEW_WARM_POOL_*` env on
  the preview-control broker; read the live values rather than assuming.
- Stale-baseline, near-TTL, and failed members are retired through the signed
  teardown contract, never reused. A pin roll makes every older member stale.

A capacity refusal during replenishment creates nothing: the lane records a
`launch-capacity-refused` outcome with the refusal detail and logs it. That is
the design working, and it is the cheapest possible refusal because no object
was created.

Never raise `PREVIEW_WARM_POOL_SIZE` to work around a capacity refusal. A
refusal means the cluster had no headroom for one more preview; a larger pool
asks for the same capacity more often and competes with the user launches the
reserve exists to protect. If warm previews are missing when users want them,
fix the binding dimension — right-size preview plans, return idle previews, or
adjust quota within physical limits — and only then revisit the size.

## Agent Host Shapes

Session capacity depends on the registry `hostMode` and workspace backend, not
on one pod shape. Read `services/shared/runtime-registry.json` for the live set:

- `hostMode: harness` with workspace `openshell-shared` (`dapr-agent-py`): the
  LLM loop runs on the replicated `dapr-agent-harness` Deployment and tools run
  in a shared OpenShell workspace. There is no per-session executor pod, so the
  per-session Kubernetes cost is the workspace, not an agent-loop pod.
- `hostMode: harness` with workspace `sandbox-executor` (`dapr-agent-py-local`):
  loop on the harness, tools in a per-session executor pod. That pod carries no
  daprd sidecar, so it is lighter than an agent-loop pod.
- `hostMode: per-session-pod` (CLI, CUA, and browser descriptors): loop and
  tools share one Kueue-admitted Sandbox pod. This is a declared capability
  exception, not a fallback, so harness pressure never reroutes work here.

The retired `shared-pool` host mode and `agent-runtime-pool-*` workloads must
not reappear in a capacity plan or a rendered manifest.

One image pin, `dapr-agent-py-sandbox`, feeds the harness and the executor image
(`AGENT_RUNTIME_DEFAULT_IMAGE` on the BFF), so a single outer-loop bump rolls
both. Before a live capacity proof, wait for `rollout status` on
`dapr-agent-harness`, `workflow-orchestrator`, and `workflow-builder`. Read the
current replica counts and requests from source and the live Deployments; do
not carry these numbers forward as fixed.

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

Warm-pool members are the correct first thing to give back under pressure,
because retiring one returns real quota and interrupts nobody. Retire them
through the pool lane's signed teardown, never by deleting the CR or its
Workload directly.

Evaluation concurrency follows the same live authority. Each Dapr campaign
shard asks the capacity port for an exact trial-shape decision. A stale observer
parks the campaign; it never fails the campaign or authorizes new work. The
materialized Tekton TaskRun or Sandbox remains Kueue-owned, while campaign
state and cancellation remain evaluation-owned. Evaluation compatibility-
validation TaskRuns are garbage-collected an hour after completion, so a
disappearing TaskRun is cleanup, not capacity loss.

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
- the warm pool holds its configured size across several ticks, and an adoption
  removes the member from pool capacity and is replaced;
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
