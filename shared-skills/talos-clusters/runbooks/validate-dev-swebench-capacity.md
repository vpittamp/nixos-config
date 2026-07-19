# Runbook: Validate Dev SWE-bench Capacity After Rebuild

Use after recreating or resizing `dev` for benchmark traffic.

## Cluster Gates

```bash
KUBECONFIG=/tmp/dev-kubeconfig kubectl get nodes -o wide
KUBECONFIG=/tmp/dev-kubeconfig kubectl get nodes \
  -l stacks.io/swebench-pool=dev-benchmark --no-headers | wc -l
KUBECONFIG=/tmp/dev-kubeconfig kubectl get pods -A \
  --field-selector=status.phase!=Running,status.phase!=Succeeded
```

Expected for the 72-capacity dev target:

- Nine Ready nodes: three control planes and six workers.
- Six workers labeled `stacks.io/swebench-pool=dev-benchmark`.
- No worker has `DiskPressure`.
- Aggregate worker nodefs/ephemeral headroom supports at least 72 sandboxes.

## Argo Gates

```bash
kubectl --kubeconfig ~/.kube/hub-config -n argocd get app | rg 'dev|spoke-dev'
```

All dev/spoke-dev Applications should be Synced and Healthy. If a workload app
is stuck, fix the specific drift or missing dependency before benchmark traffic.

## Workflow-builder Data Gates

```bash
KUBECONFIG=/tmp/dev-kubeconfig kubectl exec -n workflow-builder postgresql-0 -- \
  psql -U postgres -d workflow_builder -c "
    select count(*) as lite from benchmark_instances where suite_slug = 'swebench_lite';
    select count(*) as verified from benchmark_instances where suite_slug = 'swebench_verified';
    select id, slug, runtime_app_id, registry_status from agents
      where id in (
        'agnt_kimi_k26_swe_canary',
        'agnt_deepseek_v4_pro_swe_smoke',
        'agnt_foundry_deepseek_swe_smoke'
      )
      order by id;
    select count(*) as active_runs from benchmark_runs
      where status not in ('completed', 'failed', 'cancelled');
    select count(*) as active_leases from benchmark_resource_leases
      where status = 'active';
  "
```

Expected from the dev rebuild:

- SWE-bench Lite has 300 instances.
- SWE-bench Verified has 500 instances.
- Kimi and DeepSeek smoke/canary agents exist and are `registered`.
- Kimi canary uses `agent-runtime-pool-coding`.
- Active benchmark runs, leases, workflow executions, sessions, and runtime pods
  are zero before launching.

## Dapr Runtime Gates

For pooled SWE-bench agents, `workflowstatestore` must be the only visible
`actorStateStore=true` Component. It is namespace-wide on current dev because
per-session Kueue agent hosts use unique app IDs. `dapr-agent-py-statestore`
should also be namespace-wide, but `actorStateStore=false`; it is agent
application state, not durable workflow actor state:

```bash
KUBECONFIG=/tmp/dev-kubeconfig kubectl get component -n workflow-builder \
  workflowstatestore dapr-agent-py-statestore -o json | \
  jq '.items[]? // . | {name:.metadata.name, scopes:.scopes}'
```

The parent workflow owner must also pass the app-level start gate before any
capacity run:

```bash
KUBECONFIG=/tmp/dev-kubeconfig kubectl exec -n workflow-builder deploy/workflow-orchestrator -c workflow-orchestrator -- \
  python - <<'PY'
import urllib.request
print(urllib.request.urlopen("http://127.0.0.1:8080/readyz", timeout=10).read().decode())
PY
```

Expected: `"workflowConnectedWorkers":1` or higher and `"taskhubReady":true`.
If `workflowConnectedWorkers` stays zero, wait for the watchdog to replace the
pod or delete only the `workflow-orchestrator` pod after confirming no active
run depends on it. Replacing only the Python container is insufficient because a
stale `daprd` sidecar can remain in the pod.

Do not launch during workflow-builder rollout or hook activity. The BFF launch
stability gate should show a stable workflow-builder Deployment, no active
`db-migrate`/`db-seed`/`sync-platform-oauth-apps` hook Jobs, and a synced,
healthy managing Argo Application before a capacity run is inserted.

MLflow is restored but background best-effort. `[mlflow]` timeout logs should
not block a capacity smoke; the health signal is run creation, Dapr instance
IDs, OpenShell pod admission, session IDs, token usage, and evaluator handoff.

## Capacity API Gate

Use an authenticated workflow-builder token for the project that owns the canary
agents, then call. The retained `agnt_kimi_k26_swe_canary` identifier is a
legacy fixture identity; its current model mapping is `kimi/kimi-k3`. Do not
infer that K2.6 remains an available model from the slug.

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  --data '{
    "agentId": "agnt_kimi_k26_swe_canary",
    "instanceCount": 72,
    "requestedConcurrency": 72,
    "evaluationConcurrency": 24,
    "modelNameOrPath": "kimi/kimi-k3"
  }' \
  https://workflow-builder-dev.tail286401.ts.net/api/benchmarks/capacity | jq
```

Launch gates:

- `blockedBy` is empty.
- Runtime slots are at least 72.
- `schedulableKueueInstanceCapacity` is at least the requested effective
  inference concurrency when the Kueue backend is active. This is the
  full-instance bundle cap; do not rely on `schedulableSandboxCapacity` alone.
- `diskPressureNodeCount == 0`.
- Stale active leases/workflows/sessions are zero.

Only after these pass should a 10/24/48/72 benchmark ramp be started. Use
distinct exact-ready SWE-bench_Verified instances. A `maxTurns=3` two-instance
canary is useful after runtime changes: it is expected to finish unresolved or
`empty_patch`, but it must create sessions, record LLM usage, and launch the
evaluator. For infra-capacity cohorts, prefer `maxTurns=25`; it is long enough
to exercise LLM/tool/sandbox behavior without creating very long cohort tails.

Current clean checkpoint to compare against: run `W4ZmHxaEMEYQDCZ_Ypo41`
completed 25 distinct exact-ready SWE-bench_Verified instances with DeepSeek V4
Pro at `maxTurns=25`. It requested/effectively ran inference 25/25; evaluator
requested/effective was 24/9 due `kueue_eval_capacity`. Results were 13
resolved / 7 unresolved / 5 empty-patch, with zero evaluator errors, zero hard
errors, zero active leases after cleanup, and no Dapr activity-registration
failures. The next checkpoint should be 50 only after active runs/leases, stale
pods, Dapr scheduler/placement, workflow-builder launch stability, and
exact-ready coverage are all clean.
