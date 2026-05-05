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

## Main Knobs

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
| `AGENT_RUNTIME_POOL_APP_IDS_JSON` | unset | Maps runtime classes to shared pools; explicit `slotsPerReplica` here wins for that pool. Dev coding pool is `7 * 8 = 56` slots. |
| `AGENT_RUNTIME_SLOTS_PER_REPLICA_JSON` | `{"coding":5,"office":2,"browser":1,"testing":2}` | Runtime-class fallback. Dev uses coding `12` for dedicated coding runtimes. |
| `AGENT_RUNTIME_DAPR_WORKFLOW_LIMIT_PER_SIDECAR` | slots per replica | Per-sidecar Dapr workflow capacity. Dev uses `12`. |
| `DAPR_WORKFLOW_MAX_CONCURRENT_WORKFLOW_INVOCATIONS` | unset | BFF estimate override checked before `AGENT_RUNTIME_DAPR_WORKFLOW_LIMIT_PER_SIDECAR`; controller status does not read it. |
| agent `runtimePool.maxActiveSessions` | unset | Explicit pool/session cap in agent config when present. |
| `AgentRuntime.spec.lifecycle.slotsPerReplica` | class fallback | Controller-reported runtime slot count. |
| `AgentRuntime.spec.lifecycle.daprWorkflowLimitPerSidecar` / `maxConcurrentWorkflowInvocations` | env or slots | Per-AgentRuntime Dapr workflow override. |

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
