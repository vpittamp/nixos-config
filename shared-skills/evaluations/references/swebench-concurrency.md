# SWE-bench Concurrency Reference

Use this when a user asks why only N SWE-bench instances are running, asks to
raise/remove benchmark limits, or asks whether inference/evaluation is
parallelized.

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

### Launch UI and BFF

Files: `src/lib/components/benchmarks/launch-run-sheet.svelte`,
`src/lib/server/benchmarks/runtime-capacity.ts`,
`src/lib/server/benchmarks/service.ts`.

| Name | Current fallback | Meaning |
| --- | ---: | --- |
| `DEFAULT_INFERENCE_CONCURRENCY` | `10` | Launch-sheet initial inference request. |
| `DEFAULT_EVALUATION_CONCURRENCY` | `24` | Launch-sheet initial evaluation request and BFF fallback. |
| `MAX_INFERENCE_CONCURRENCY` | `128` | Launch-sheet slider maximum; backend still clamps. |
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

## Verified Capacity Envelope (post-2026-05-09 profile-timeout fix)

Use this section before launching the next dev SWE-bench capacity ramp. Both
runs below targeted SWE-bench_Verified at `--max-turns 30` on the
`dapr-kueue` execution backend with `--execution-class benchmark-fast`, agent
slug `kimi-k26-swebench-canary`, project `OJi0fn1xt2cKlh6HdnpZP`.

| Run | Concurrency | Outcome |
| --- | ---: | --- |
| `lkbeOLXlGbsAC5eZa8tri` (pre-fix) | 177 | Cancelled. 67 children failed with `Request to openshell-agent-runtime (workspace/profile) timed out after 300000ms`. |
| `IxyOaK1w6gs2spe51QyoH` (post-fix) | 72 | Success. 72/72 workflow executions; 72/72 sessions recorded usage; evaluator job ran. Result: 22 resolved / 28 unresolved / 22 empty patch. Empty patches were `maxTurns`/model behavior, not infra. No profile-timeout errors. |

**Recommended ramp ladder**: 120 → 144 → 177. Don't jump straight to 177
unless you are specifically testing full burst saturation.

**Idle-state preflight** (run before launching to confirm no active runs or
dangling leases):

```sql
select status,count(*) from benchmark_runs where status not in ('completed','failed','cancelled') group by status;
select status,count(*) from benchmark_resource_leases where status='active' group by status;
```

Run via `kubectl --context dev -n workflow-builder exec postgresql-0 -- psql -U postgres -d workflow_builder -c "<sql>"`.

**Canonical launch invocation** (substitute `--limit`/`--concurrency` per
ladder step):

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
