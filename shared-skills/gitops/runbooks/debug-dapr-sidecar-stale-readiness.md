# Debug Dapr Sidecar Stale Readiness

## Symptoms

- A workflow-builder runtime Deployment shows `1/2` ready even though the app container is running.
- `openshell-agent-runtime`, `swebench-coordinator`, `workflow-orchestrator`, or another Dapr-enabled runtime is unavailable after Dapr control-plane churn.
- `daprd` readiness returns `ERR_HEALTH_NOT_READY` and names `grpc-api-server` or `grpc-internal-server`.
- Logs mention `Actor runtime shutting down`, `Placement client shutting down`, or `Workflow engine stopped`.
- `workflow-orchestrator` `/readyz` returns 503 with `workflowConnectedWorkers=0`
  or `daprd` logs workflow actor registration errors after the app container
  was restarted.

## Diagnostic

Confirm the target context and affected pod:

```bash
kubectl config current-context
kubectl get deploy,pod -A | rg 'workflow-builder|openshell-agent-runtime|swebench-coordinator|workflow-orchestrator|dapr-agent-py'
```

Check which container is not ready:

```bash
kubectl get pod -n workflow-builder <pod> -o jsonpath='{range .status.containerStatuses[*]}{.name} ready={.ready} restarts={.restartCount}{"\n"}{end}'
kubectl describe pod -n workflow-builder <pod> | rg -n 'Readiness|Unhealthy|daprd|Events'
```

Read the sidecar readiness failure:

```bash
kubectl logs -n workflow-builder <pod> -c daprd --tail=200
kubectl exec -n workflow-builder <pod> -c <app-container> -- curl -sS -i http://127.0.0.1:3501/v1.0/healthz
kubectl exec -n workflow-builder <pod> -c <app-container> -- curl -sS -i http://127.0.0.1:3500/v1.0/healthz/outbound
kubectl exec -n workflow-builder <pod> -c <app-container> -- curl -sS -i http://127.0.0.1:3500/v1.0/metadata
```

If the app container does not include `curl`, use `wget` or a tiny Python `urllib.request.urlopen` probe from inside the app container. The key signal is whether `daprd` is answering but not ready, not whether Kubernetes can reach the pod. Port `3501` is Dapr's public health/readiness port; port `3500` is the app-facing Dapr HTTP API.

Check recent Dapr control-plane health and restarts:

```bash
kubectl get pod,deploy,sts -n dapr-system -o wide
kubectl describe pod -n dapr-system dapr-placement-server-0
kubectl describe pod -n dapr-system dapr-scheduler-server-0
kubectl logs -n dapr-system dapr-placement-server-0 --previous --tail=120
kubectl logs -n dapr-system dapr-scheduler-server-0 --previous --tail=120
```

The ryzen failure mode was a stale sidecar after placement/scheduler churn: app containers were ready, `daprd` liveness stayed green, but readiness remained false with `ERR_HEALTH_NOT_READY: [grpc-api-server grpc-internal-server]`.

For `workflow-orchestrator`, also check the app-level start gate:

```bash
kubectl exec -n workflow-builder deploy/workflow-orchestrator -c workflow-orchestrator -- \
  python - <<'PY'
import urllib.request
print(urllib.request.urlopen("http://127.0.0.1:8080/readyz", timeout=10).read().decode())
PY
```

Healthy output includes `"workflowConnectedWorkers":1` or higher and
`"taskhubReady":true`.

## Fix Steps

If `dapr-system` is currently healthy, recycle only the affected workflow-builder Deployment:

```bash
kubectl rollout restart deployment/<deployment> -n workflow-builder
kubectl rollout status deployment/<deployment> -n workflow-builder --timeout=180s
```

For the known ryzen incident affecting both runtime services:

```bash
kubectl rollout restart deployment/openshell-agent-runtime deployment/swebench-coordinator -n workflow-builder
kubectl rollout status deployment/openshell-agent-runtime -n workflow-builder --timeout=180s
kubectl rollout status deployment/swebench-coordinator -n workflow-builder --timeout=180s
```

Do not restart Dapr control-plane components first unless they are still unhealthy. Do not truncate actor state tables or clear scheduler state for a sidecar readiness-only issue.

For `workflow-orchestrator`, prefer full pod replacement. The deployed
watchdog now self-deletes the pod when `workflowConnectedWorkers` stays zero,
and the service account has a narrow `delete pods` Role for that purpose. A
Python process restart is not enough for the stale-sidecar case because the old
`daprd` container can remain in the same pod.

Verify the RBAC grant before relying on the watchdog:

```bash
kubectl auth can-i delete pods \
  --as system:serviceaccount:workflow-builder:workflow-orchestrator \
  -n workflow-builder
```

If you need to recover immediately and no active benchmark/workflow run is
using the pod, delete only the affected pod:

```bash
kubectl delete pod -n workflow-builder -l app=workflow-orchestrator
```

## Verify

```bash
kubectl get deploy,pod -n workflow-builder | rg 'openshell-agent-runtime|swebench-coordinator|workflow-orchestrator|dapr-agent-py'
kubectl get pod -n workflow-builder <new-pod> -o jsonpath='{range .status.containerStatuses[*]}{.name} ready={.ready} restarts={.restartCount}{"\n"}{end}'
kubectl exec -n workflow-builder <new-pod> -c <app-container> -- curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3501/v1.0/healthz
kubectl exec -n workflow-builder <new-pod> -c <app-container> -- curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3500/v1.0/metadata
```

Healthy sidecar probes return `204`, and the Deployment returns to `2/2`.

## Notes

- This failure is readiness-specific. Kubernetes liveness can pass because the sidecar process is alive while internal gRPC servers remain unready.
- If the new pod also gets stuck, treat `dapr-system` as actively unhealthy and inspect placement/scheduler/cert-manager before cycling more workloads.
- If logs show orphan workflow reminders or actor state errors instead of sidecar health errors, use the workflow-state runbook/gotcha path before deleting or truncating any state.
