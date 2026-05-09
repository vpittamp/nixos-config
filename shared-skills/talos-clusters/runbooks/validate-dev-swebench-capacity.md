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

For pooled Kimi, `workflowstatestore` and `dapr-agent-py-statestore` must include
`agent-runtime-pool-coding` in scopes, otherwise child workflow/session state can
fail even when capacity looks good:

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

MLflow is restored but background best-effort. `[mlflow]` timeout logs should
not block a capacity smoke; the health signal is run creation, Dapr instance
IDs, OpenShell pod admission, session IDs, token usage, and evaluator handoff.

## Capacity API Gate

Use an authenticated workflow-builder token for the project that owns the canary
agents, then call:

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  --data '{
    "agentId": "agnt_kimi_k26_swe_canary",
    "instanceCount": 72,
    "requestedConcurrency": 72,
    "evaluationConcurrency": 24,
    "modelNameOrPath": "moonshotai/kimi-k2-instruct"
  }' \
  https://workflow-builder-dev.tail286401.ts.net/api/benchmarks/capacity | jq
```

Launch gates:

- `blockedBy` is empty.
- Runtime slots are at least 72.
- `schedulableSandboxCapacity >= 72`.
- `diskPressureNodeCount == 0`.
- Stale active leases/workflows/sessions are zero.

Only after these pass should a 10/24/48/72 benchmark ramp be started. A
`maxTurns=3` two-instance canary is useful after runtime changes: it is expected
to finish unresolved or `empty_patch`, but it must create sessions, record LLM
usage, and launch the evaluator.
