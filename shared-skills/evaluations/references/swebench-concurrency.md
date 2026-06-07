# SWE-bench Concurrency Reference

Use this when a user asks why only N SWE-bench instances are running, asks to
raise/remove benchmark limits, or asks whether inference/evaluation is
parallelized.

## Contents

- [Capacity Formula](#capacity-formula)
- [Start-Path Readiness](#start-path-readiness)
- [Control-Plane Stability Gate](#control-plane-stability-gate)
- [MLflow Tracking And Comparison Campaigns](#mlflow-tracking-and-comparison-campaigns)
- [Main Knobs](#main-knobs)
- [Dapr Workflow And State-Store Constraints](#dapr-workflow-and-state-store-constraints)
- [Metric-Driven Capacity Signals](#metric-driven-capacity-signals)
- [Current Dev Capacity Baseline](#current-dev-capacity-baseline)
- [SWE-bench Image Builds](#swe-bench-image-builds)
- [Historical Verified Capacity Envelope](#historical-verified-capacity-envelope-post-2026-05-09-profile-timeout-fix)

## Capacity Formula

Official SWE-bench Benchmarks store an effective inference concurrency, then
the coordinator re-checks resource leases before each instance starts. The
effective inference cap is the minimum of:

- requested concurrency from the launch dialog or API;
- selected instance count;
- runtime replicas * slots per replica;
- runtime replicas * per-sidecar Dapr workflow limit;
- explicit runtime `maxActiveSessions` when configured;
- `BENCHMARK_MAX_ACTIVE_INFERENCE_INSTANCES`;
- `BENCHMARK_AGENT_WORKFLOW_MAX_ACTIVE_TURNS` or `BENCHMARK_MAX_ACTIVE_AGENT_WORKFLOWS`;
- `BENCHMARK_MAX_ACTIVE_SANDBOXES` and live schedulable sandbox headroom;
- `BENCHMARK_MODEL_MAX_ACTIVE_REQUESTS` or `BENCHMARK_MAX_ACTIVE_MODEL_REQUESTS`.

If a run asks for 20 but only 12 are active, inspect the run summary capacity
first, then the `benchmark_resource_leases` blockers. Raising only the UI
slider rarely changes throughput by itself.

On dev and ryzen, treat one active SWE-bench instance as a full-instance
bundle, not a single pod. The current architecture consumes the OpenShell
sandbox/worker side and the agent-host/session-host side for each active
instance. Capacity math, Kueue quota, node requests, and cleanup must account
for both sides. A launcher that admits only sandbox capacity can still overrun
the cluster through agent-host memory, Dapr workflow workers, or state-store
pressure.

The BFF should run with
`BENCHMARK_KUEUE_INSTANCE_REQUEST_MODE=host-worker-composite` for the
Kueue-backed path. In that mode, read `kueueInstanceRequest*`,
`kueueInstancePodCount`, `kueueAvailableInstanceSlots`, and
`schedulableKueueInstanceCapacity` from `benchmark_runs.summary.capacity`. A
modeled `kueueInstancePodCount=3` is a quota budget for the composite
worker/sandbox/agent-host shape, not a claim that three long-lived pods remain
visible for every instance.

## Start-Path Readiness

Benchmark instance start is also gated by parent Dapr runtime readiness. The
BFF calls `workflow-orchestrator` `GET /readyz` before creating the instance
execution row or dispatching `/api/v2/sw-workflows`. Readiness requires Dapr
outbound health, metadata access, at least one connected Dapr workflow worker,
and taskhub access.

If `/readyz` fails, the BFF returns 503
`workflow_runtime_unavailable`. The coordinator treats that as retryable
backpressure: release the lease, requeue the instance at the front of the run
queue, and sleep `SWEBENCH_ORCHESTRATOR_NOT_READY_RETRY_SECONDS` (falling back
to `SWEBENCH_LEASE_RETRY_SECONDS`).

MLflow is not a dispatch gate. With `MLFLOW_FAILURE_MODE=best_effort`, MLflow
timeouts only leave tracking IDs null and log `[mlflow]` warnings; Dapr workflow
IDs, sessions, token usage, and evaluator handoff should continue.

## Control-Plane Stability Gate

Benchmark launch is gated on workflow-builder control-plane stability before a
new run is inserted. The BFF should refuse launch, and preview should surface
the same diagnostics, when any of these are true:

- the `workflow-builder` Deployment is rolling, has unavailable replicas, or
  its ready pods are younger than the configured stable window;
- workflow-builder hook Jobs such as `db-migrate`, `db-seed`, or
  `sync-platform-oauth-apps` are active;
- the managing Argo Application is not `Synced` + `Healthy`, has a running
  operation, or finished an operation too recently.

Do not bypass this with a manual run during capacity testing. Recent failures
showed that launching during a BFF/orchestrator rollout can corrupt the
checkpoint: startup cleanup may terminate active parents, and Dapr durable
replay may hit activity-schedule mismatches if code changes mid-history.

## MLflow Tracking And Comparison Campaigns

Use workflow-builder/Dapr as the execution owner and MLflow as the tracking
projection. A benchmark run should have one parent `swebench_run` MLflow run,
one `swebench_instance` child per instance, and one `swebench_mlflow_eval` child
when post-hoc evaluation runs.

For agent comparisons, launch one benchmark run per agent/configuration over
the same suite and exact instance ids. The Benchmarks UI `Compare agents` mode
does this automatically, applies a stable campaign tag, and opens:

```text
/workspaces/<slug>/benchmarks/compare?runs=<runA>,<runB>[,<runC>,<runD>]&tag=<campaign-tag>
```

The tag is copied into parent, instance, and eval MLflow runs as
`workflow_builder.benchmark_tags` and
`workflow_builder.benchmark_tag.<tag>=true`. Query campaigns with:

```text
tags.`workflow_builder.benchmark_tag.<campaign-tag>` = 'true'
```

For two agents over `N` instances, expect `2 + (2 * N) + 2` MLflow runs:
two parents, `2 * N` instance children, and two eval children. Official
resolved/unresolved still comes from the SWE-bench harness callback. See
`swebench-mlflow-comparison.md` in this directory for the full operator
runbook.

## Main Knobs

### Environment Preflight and Build Readiness

This is not a concurrency cap, but it is the most common reason a random run
appears stuck at zero active instances. The coordinator will not start instance
workflows until every selected instance has a validated inference environment.

Readiness is model-independent. It applies equally to Kimi, DeepSeek, Together,
NVIDIA, Anthropic, and OpenAI-backed agents:

- exact static mappings from `SWEBENCH_INFERENCE_ENVIRONMENTS_DIR` are valid
  when suite/repo/baseCommit/version plus digest-pinned image match; these pins
  may omit `environmentSetupCommit`;
- dynamic rows in `environment_image_builds` are valid only when
  `env_spec_hash` matches the current `buildSwebenchEnvironmentSpec()` output;
- coarse repo/version/baseCommit matches are not enough, because harness spec
  generation can change independently of those fields.

Preflight builds are hub Tekton `swe-env-*` PipelineRuns. They should not run
on dev workers. If `benchmark_runs.status='queued'`, no
`benchmark_run_instances.session_id` values exist, and hub Tekton shows an
active `swe-env-*`, the benchmark is waiting for environment validation rather
than constrained by inference concurrency.

For capacity checkpoints, prefer distinct exact-ready SWE-bench_Verified
instances. Do not use repeated duplicate instances as the primary path. Exact
readiness means the static ConfigMap or dynamic DB row matches the current
environment spec hash; stale coarse repo/version/base-commit matches are not
enough. Follow-up image-build work should improve hub Tekton cache hit rates and
build throughput, but capacity runs should not wait on new images unless image
coverage itself is the thing under test.

### Launch UI and BFF

Files: `src/lib/components/benchmarks/launch-run-sheet.svelte`,
`src/lib/server/benchmarks/runtime-capacity.ts`,
`src/lib/server/benchmarks/service.ts`.

| Name | Current fallback | Meaning |
| --- | ---: | --- |
| `DEFAULT_INFERENCE_CONCURRENCY` | `10` | Launch-sheet initial inference request. |
| `DEFAULT_EVALUATION_CONCURRENCY` | `24` | Launch-sheet initial evaluation request and BFF fallback. |
| `MAX_INFERENCE_CONCURRENCY` | `500` | Launch-sheet slider maximum; backend still clamps. |
| `MAX_EVALUATION_CONCURRENCY` | `128` | Launch-sheet evaluation slider maximum. |
| `BENCHMARK_DEFAULT_CONCURRENCY` | `10` | BFF fallback when the request omits/invalidates inference concurrency. |
| `BENCHMARK_MAX_ACTIVE_INFERENCE_INSTANCES` | `56` | Global active inference resource-lease cap. |
| `BENCHMARK_AGENT_WORKFLOW_MAX_ACTIVE_TURNS` | unset | Global Dapr agent child-workflow cap. |
| `BENCHMARK_MAX_ACTIVE_AGENT_WORKFLOWS` | unset | Alias for `BENCHMARK_AGENT_WORKFLOW_MAX_ACTIVE_TURNS`. |
| `BENCHMARK_MAX_ACTIVE_SANDBOXES` | unset | Configured sandbox cap; effective cap also considers live schedulable headroom. |
| `BENCHMARK_MODEL_MAX_ACTIVE_REQUESTS` | unset | Optional per-model request cap. |
| `BENCHMARK_MAX_ACTIVE_MODEL_REQUESTS` | unset | Alias for `BENCHMARK_MODEL_MAX_ACTIVE_REQUESTS`. |
| `BENCHMARK_RESOURCE_LEASE_SECONDS` | `max(900, timeoutSeconds + 900)` | Lease TTL. Not a throughput cap, but stale leases hold capacity. |
| `BENCHMARK_LEASE_RETRY_SECONDS` | `15` | BFF retry-after when a lease is denied. |
| `BENCHMARK_INFERENCE_STALL_SECONDS` | `480` | Stale inference detector, not a dispatch cap. |
| `MLFLOW_ENABLED` | true | Enables benchmark tracking metadata. |
| `MLFLOW_FAILURE_MODE` | `best_effort` | Logs MLflow failures without blocking benchmark dispatch. |
| `MLFLOW_REQUEST_TIMEOUT_MS` | `30000` | Per-request MLflow timeout; should not block start. |
| `BENCHMARK_WORKFLOW_BUILDER_STABLE_SECONDS` | `120` | Launch-control-plane stable window for BFF rollout/hook/Argo checks. |
| `BENCHMARK_WORKFLOW_BUILDER_NAMESPACE` | `workflow-builder` | Namespace sampled by the launch stability gate. |
| `BENCHMARK_WORKFLOW_BUILDER_DEPLOYMENT` | `workflow-builder` | Deployment sampled by the launch stability gate. |
| `BENCHMARK_ARGOCD_APPLICATION_NAME` | inferred from `APP_PUBLIC_URL` | Optional explicit Argo app name for launch stability. |
| `BENCHMARK_ARGOCD_HUB_KUBECONFIG` | hub kubeconfig env fallback | Kubeconfig path used to inspect the hub Argo Application. |

Sandbox headroom variables in `src/lib/server/benchmarks/sandbox-capacity.ts`:

| Name | Fallback | Meaning |
| --- | ---: | --- |
| `BENCHMARK_SANDBOX_CAPACITY_DISABLED` | false | Disable live sandbox capacity sampling. |
| `BENCHMARK_SANDBOX_CAPACITY_NAMESPACE` | `OPENSHELL_NAMESPACE` or `openshell` | Namespace for fallback pod listing. |
| `BENCHMARK_SANDBOX_REQUEST_CPU` | `100m` | Request used to estimate sandbox slots. |
| `BENCHMARK_SANDBOX_REQUEST_MEMORY` | `256Mi` | Request used to estimate sandbox slots. |
| `OPENSHELL_NAMESPACE` | `openshell` | Fallback namespace. |

### Agent Runtime Capacity

Files: `src/lib/server/agents/runtime-routing.ts`,
`services/agent-runtime-controller/src/main.py`, stacks
`Deployment-workflow-builder.yaml`, and stacks
`Deployment-agent-runtime-controller.yaml`.

| Name/config | Fallback | Meaning |
| --- | ---: | --- |
| `AGENT_RUNTIME_POOL_MAX_REPLICAS` | `2` | Shared-pool replica fallback. Dev currently uses `7`. |
| `AGENT_RUNTIME_POOL_MIN_REPLICAS` | unset | Shared-pool minimum replica metadata. |
| `AGENT_RUNTIME_POOL_APP_IDS_JSON` | unset | Maps runtime classes to shared pools; explicit `slotsPerReplica` here wins for that pool. Dev coding pool observed at `16` ready replicas as of 2026-05-09 — verify with `kubectl --context dev -n workflow-builder get deploy agent-runtime-pool-coding -o jsonpath='{.status.readyReplicas}'`; multiply by the pool's `slotsPerReplica` for effective inference headroom. |
| `AGENT_RUNTIME_SLOTS_PER_REPLICA_JSON` | `{"coding":5,"office":2,"browser":1,"testing":2}` | Runtime-class fallback. Dev uses coding `12` for dedicated coding runtimes. |
| `AGENT_RUNTIME_DAPR_WORKFLOW_LIMIT_PER_SIDECAR` | slots per replica | Per-sidecar Dapr workflow capacity. Dev uses `12`. |
| `DAPR_WORKFLOW_MAX_CONCURRENT_WORKFLOW_INVOCATIONS` | unset | BFF estimate override checked before `AGENT_RUNTIME_DAPR_WORKFLOW_LIMIT_PER_SIDECAR`; controller status does not read it. |
| agent `runtimePool.maxActiveSessions` | unset | Explicit pool/session cap in agent config when present. |
| `AgentRuntime.spec.lifecycle.slotsPerReplica` | class fallback | Controller-reported runtime slot count. |
| `AgentRuntime.spec.lifecycle.daprWorkflowLimitPerSidecar` / `maxConcurrentWorkflowInvocations` | env or slots | Per-AgentRuntime Dapr workflow override. |

### Function-Router Workspace/Profile Timeout

Files: `services/function-router/src/routes/execute.ts` (lines 67–77), tests
in `services/function-router/src/routes/execute.test.ts`.

| Name | Fallback | Meaning |
| --- | ---: | --- |
| `MAX_WORKSPACE_PROFILE_TIMEOUT_MS` | `MAX_WORKSPACE_UTILITY_TIMEOUT_MS` (3_600_000ms / 1h) | Upper clamp for `workspace/profile` action timeouts in function-router. Floor is 300_000ms via `Math.max(300_000, …)`. |

Pre-fix behavior (workflow-builder before commit `2a68cca7`, 2026-05-09):
this constant was hard-coded to `300_000`. Every `workspace/profile` action
got truncated to 5 minutes, even when the caller (e.g. swebench-coordinator
running benchmark workflows on the `dapr-kueue` backend) requested longer.
Symptom: child workflows fail with
`Request to openshell-agent-runtime (workspace/profile) timed out after 300000ms`,
mostly visible under burst load when Kueue sandbox queue waits push profile
cold-start past 5 min.

Post-fix: roll dev `function-router` to image
`ghcr.io/pittampalliorg/function-router:git-2a68cca7c63b743aaa644514fb4cb1a08a1332d2`
or newer. The 1h default suits all benchmark profiles seen so far; only set
`MAX_WORKSPACE_PROFILE_TIMEOUT_MS` explicitly in stacks
`Deployment-function-router.yaml` if you need a tighter cap or a longer one
than 1h.

### SWE-bench Coordinator and Evaluator

Files: `services/swebench-coordinator/src/concurrency.py`,
`services/swebench-coordinator/src/app.py`,
`services/swebench-evaluator/entrypoint.py`, and stacks
`Deployment-swebench-coordinator.yaml`.

| Name | Fallback | Meaning |
| --- | ---: | --- |
| `SWEBENCH_COORDINATOR_MAX_INFERENCE_CONCURRENCY` | `56` | Coordinator backstop for active instance child workflows. |
| `SWEBENCH_COORDINATOR_INSTANCE_START_BATCH_SIZE` | `10` | New instance workflows to start before pacing. Dev intended value is `12`. |
| `SWEBENCH_COORDINATOR_INSTANCE_START_BATCH_DELAY_SECONDS` | `5` | Delay between start batches. Dev intended value is `2`. |
| `SWEBENCH_LEASE_RETRY_SECONDS` | `15` | Coordinator delay after lease denial. |
| `SWEBENCH_ORCHESTRATOR_NOT_READY_RETRY_SECONDS` | `SWEBENCH_LEASE_RETRY_SECONDS` | Coordinator delay after BFF reports parent orchestrator readiness unavailable. |
| `SWEBENCH_EVAL_MAX_PARALLEL` | `24`, clamped `1..128` | Per-instance evaluator TaskRun parallelism. |
| `SWEBENCH_MAX_WORKERS` | `24`, clamped `1..128` | Evaluator alias when `SWEBENCH_EVAL_MAX_PARALLEL` is absent. |

Evaluation is parallelized independently from inference. The coordinator creates
one evaluator Job; the evaluator dispatches one TaskRun per instance in bounded
batches up to `SWEBENCH_EVAL_MAX_PARALLEL`.

### OpenAI-Parity Evaluations

This is not the official SWE-bench Benchmarks path. In
`services/evaluation-coordinator/src/app.py`, `EVALUATION_MAX_CONCURRENCY`
defaults to `32` and clamps `executionConfig.concurrency` for eval item child
workflows.

### Internal Constants

These are not env vars:

- `BENCHMARK_TERMINATION_CONCURRENCY = 8`
- `BENCHMARK_SANDBOX_CLEANUP_CONCURRENCY = 8`

Provider retry knobs such as `DEEPSEEK_RATE_LIMIT_MAX_RETRIES`,
`DEEPSEEK_RATE_LIMIT_BACKOFF_SECONDS`, `TOGETHER_RATE_LIMIT_*`, and
`AZURE_AI_FOUNDRY_RATE_LIMIT_*` are retry controls after 429s, not concurrency
caps.

## Dapr Workflow And State-Store Constraints

Dapr durable workflow history is replay-sensitive. Do not roll
`workflow-orchestrator`, `swebench-coordinator`, `workflow-builder`,
`dapr-agent-py`, or `claude-agent-py` mid-run unless the run is cancelled and
cleanup is complete.
Never gate a scheduled `ctx.call_activity` / `ctx.call_child_workflow` behind a
new env flag after histories exist; keep the schedule stable and make the
activity body no-op if an effect such as tracing must be disabled. A recent
`emit_mlflow_node_span` schedule mismatch killed otherwise healthy histories.

State-store layout on dev:

- `workflowstatestore` is the namespace-wide Dapr workflow/actor store
  (`actorStateStore=true`, `tablePrefix=wfstate_`). Parent orchestrations,
  per-session agent workflows, timers, reminders, and activity bookkeeping all
  share this durable backend. Its `maxConns` is intentionally above the old
  value of 2; keep it below PgBouncer capacity but high enough for the configured
  Dapr worker limits.
- `dapr-agent-py-statestore` is a namespace-wide non-actor application state
  store (`actorStateStore=false`, `tablePrefix=agent_py_`) used by the agent
  state APIs. It should not be treated as the workflow actor store, and it
  should not be cloned per agent/session.

Dapr workflow status APIs can be stale after termination. We observed parent
workflows that logged `TERMINATED` but still returned `RUNNING`, causing normal
purge to refuse deletion. For terminal benchmark cleanup, verify DB state,
leases, session/turn/parent workflows, pods, and state rows together. The BFF
may force-delete scoped `wfstate_state` / `agent_py_state` rows only after the
run is terminal and terminate/poll/purge has failed to clear stale Dapr state;
do not use that path for active stalled-instance diagnosis.

`CLEANUP_STALE_ON_STARTUP` should stay opt-in and must skip benchmark workflows
unless intentionally doing a recovery. Startup cleanup killed active benchmark
parents during a rollout; normal benchmark cleanup belongs in the terminal run
cleanup endpoint.

Dapr Agents 1.0.3 introduced native hooks and changed enough of the workflow
surface that local compatibility shims became risky. For repo-owned custom
activities in `services/dapr-agent-py`, register and call only scoped names via
`self._activity_name(...)`; do not also register bare legacy names. If an old
benchmark history still expects a bare activity name, cancel/cleanup/purge the
old state rather than carrying dual registration forward.

## Metric-Driven Capacity Signals

Prefer live capacity signals over static caps whenever the data is available.
Static env caps remain useful as circuit breakers, but the launch/admission
decision should converge on:

- Kueue available quota for the full-instance pod bundle;
- live pod requests and node schedulability, including taints and benchmark-pool
  labels;
- OpenShell sandbox headroom and active `benchmark_resource_leases`;
- Dapr workflow worker health, connected workers, sidecar readiness, and taskhub
  reachability;
- state-store/pgbouncer pressure and Dapr state API latency;
- evaluator Job/TaskRun capacity and Kueue admission;
- Kubernetes 1.36 node PSI / pressure metrics for debug and trend detection.

Use PSI as an early warning and post-run forensic signal, not the sole admission
gate. Pair PSI with resource requests, pod phase/admission, Kueue Workloads, and
ClickHouse/OTEL historical pod resource samples. The workflow-builder capacity
tab should show both current utilization and trend evidence; a memory chart at
57% is only a cluster-level utilization slice, not proof that a two-pod
SWE-bench instance bundle can be admitted safely.

## Current Dev Capacity Baseline

Current infra-capacity testing uses DeepSeek V4 Pro unless a canary proves the
issue is model-independent. For infra work, `maxTurns=25` is the preferred
checkpoint setting: it gives agents enough activity to exercise LLM/tool/sandbox
paths while avoiding very long cohort tails. Higher turn caps are model-quality
experiments, not required for capacity proof.

The useful model-quality checkpoint was a 64-way DeepSeek V4 Pro,
SWE-bench_Verified, distinct exact-ready cohort at `maxTurns=25`
(`8ITGk-QSGX9rPz5cnTyiT`). It produced 33/64 resolved, which validates model
quality for infra work, but it is not a clean capacity checkpoint because
rollout, startup cleanup, and replay-schedule issues interfered with the run.

The current clean infra checkpoint is `W4ZmHxaEMEYQDCZ_Ypo41`: 25 distinct
exact-ready SWE-bench_Verified instances, DeepSeek V4 Pro, `maxTurns=25`,
requested/effective inference concurrency 25/25, requested/effective evaluator
concurrency 24/9 due `kueue_eval_capacity`, 13 resolved / 7 unresolved / 5
empty-patch, zero evaluator errors, zero hard errors, zero active leases after
cleanup, and no `Activity function named ... not registered` or Dapr workflow
hard failures in log sweeps. Treat 25 as the proven clean baseline; the next
capacity checkpoint should be 50 only after the launch gate, exact-ready
coverage, leases, Dapr scheduler/placement, and stale pod checks are clean.

Ryzen parity checkpoint: run `MPIlRkKWC7UdvHgwFQEiR` selected three distinct
exact-ready SWE-bench_Verified instances at `maxTurns=10`, but correctly
clamped requested/effective inference concurrency from 3/3 to 3/2 because
`schedulableKueueInstanceCapacity=2`. All active sandbox and agent-host pods
scheduled, the queued third instance started when a slot freed, all three
instances reached 10 LLM calls and 10 tool calls, evaluation completed, and
active leases returned to zero. Use this as ryzen evidence that the composite
capacity model prevents the previous unschedulable agent-host failure.

## SWE-bench Image Builds

Image-building work is adjacent to capacity, but it should not be mixed into an
inference-capacity checkpoint unless image coverage is the thing under test. See
`swebench-image-builds.md` for the full runbook. The short version:

- workflow-builder runtime images are built from the app repo and promoted via
  GHCR/release-pins or explicit workloads pins;
- per-instance SWE-bench inference images are built on hub Tekton as
  `swe-env-*` PipelineRuns keyed by `envSpecHash`;
- exact-ready coverage is suite/repo/base/version/digest plus current
  `env_spec_hash`, not a coarse repo/version match;
- the Buildah cache PVC and lock path are throughput-critical, but cache reuse
  never overrides exact-ready validation.

## Historical Verified Capacity Envelope (post-2026-05-09 profile-timeout fix)

Use this section before launching the next dev SWE-bench capacity ramp. Both
runs below targeted SWE-bench_Verified at `--max-turns 30` on the
`dapr-kueue` execution backend with `--execution-class benchmark-fast`, agent
slug `kimi-k26-swebench-canary`, project `OJi0fn1xt2cKlh6HdnpZP`.

| Run | Concurrency | Outcome |
| --- | ---: | --- |
| `lkbeOLXlGbsAC5eZa8tri` (pre-fix) | 177 | Cancelled. 67 children failed with `Request to openshell-agent-runtime (workspace/profile) timed out after 300000ms`. |
| `IxyOaK1w6gs2spe51QyoH` (post-fix) | 72 | Success. 72/72 workflow executions; 72/72 sessions recorded usage; evaluator job ran. Result: 22 resolved / 28 unresolved / 22 empty patch. Empty patches were `maxTurns`/model behavior, not infra. No profile-timeout errors. |

This is historical Kimi evidence, not the current DeepSeek V4 Pro dev ramp
plan. For the current infra-capacity goal, use the "Current Dev Capacity
Baseline" above and increase only after the previous run has no
benchmark-infra failures.

**Idle-state preflight** (run before launching to confirm no active runs or
dangling leases):

```sql
select status,count(*) from benchmark_runs where status not in ('completed','failed','cancelled') group by status;
select status,count(*) from benchmark_resource_leases where status='active' group by status;
```

Run via `kubectl --context dev -n workflow-builder exec postgresql-0 -- psql -U postgres -d workflow_builder -c "<sql>"`.

**Historical launch invocation**:

```bash
kubectl --context dev -n workflow-builder exec deploy/workflow-builder -c workflow-builder -- \
  node /app/scripts/start-swebench-benchmark-run.bundle.js \
  --suite SWE-bench_Verified \
  --limit 120 \
  --concurrency 120 \
  --project-id OJi0fn1xt2cKlh6HdnpZP \
  --agent-slug kimi-k26-swebench-canary \
  --execution-backend dapr-kueue \
  --execution-class benchmark-fast \
  --max-turns 30 \
  --tag capacity-prevalidated-mt30-c120-after-profile-timeout-fix \
  --apply
```

**Per-run monitor block** (substitute `<RUN_ID>`):

```sql
select now();
select status, started_at, updated_at, completed_at, evaluator_job_name, error
  from benchmark_runs where id='<RUN_ID>';
select status,inference_status,evaluation_status,count(*)
  from benchmark_run_instances where run_id='<RUN_ID>'
  group by status,inference_status,evaluation_status
  order by status,inference_status,evaluation_status;
select we.status,count(*)
  from workflow_executions we
  join benchmark_run_instances bri on bri.workflow_execution_id=we.id
  where bri.run_id='<RUN_ID>'
  group by we.status order by we.status;
select count(*) filter(where session_id is not null) with_session,
       count(*) filter(where usage <> '{}'::jsonb) with_usage,
       count(*) filter(where error is not null or inference_error is not null) with_error
  from benchmark_run_instances where run_id='<RUN_ID>';
```

**Interpretation hints**:
- `workflow_executions.status=success` + evaluator handoff = infra path is
  good; resolved/unresolved/empty-patch is then a model+maxTurns story, not a
  capacity story.
- Live token usage may appear in `session_events` before the
  `benchmark_run_instances.usage` summary backfills.
- If `Request to openshell-agent-runtime (workspace/profile) timed out after 300000ms`
  reappears, the fixed function-router image is not on the active path or
  another timeout cap exists — see the Function-Router Workspace/Profile
  Timeout subsection above.

## Operator Checklist

Before raising SWE-bench throughput:

1. Confirm no active benchmark Dapr workflows will be replay-broken by a rollout.
2. Check selected agent capacity in the run summary or Benchmarks launch sheet.
3. For shared agents, adjust pool replicas/slots; for dedicated agents, adjust
   runtime-class slots or AgentRuntime lifecycle.
4. Keep `AGENT_RUNTIME_DAPR_WORKFLOW_LIMIT_PER_SIDECAR` aligned with runtime
   slots so Dapr is not the hidden limiter.
5. Keep global inference, agent workflow, sandbox, and model caps coherent.
6. Raise `SWEBENCH_EVAL_MAX_PARALLEL` separately if the bottleneck is grading.
7. Re-render/apply stacks and verify live Deployment envs before retesting.
8. Verify dev `function-router` Deployment is at image
   `ghcr.io/pittampalliorg/function-router:git-2a68cca7c63b…` or newer so
   `MAX_WORKSPACE_PROFILE_TIMEOUT_MS` (default 1h) is in effect, not the
   legacy hard-coded 300_000ms cap.
