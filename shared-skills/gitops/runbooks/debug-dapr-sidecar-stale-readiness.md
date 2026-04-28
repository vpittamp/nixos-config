# Debug Dapr Sidecar Stale Readiness

## Symptoms

- A workflow-builder runtime Deployment shows `1/2` ready even though the app container is running.
- `workspace-runtime`, `swebench-coordinator`, `workflow-orchestrator`, or another Dapr-enabled runtime is unavailable after Dapr control-plane churn.
- `daprd` readiness returns `ERR_HEALTH_NOT_READY` and names `grpc-api-server` or `grpc-internal-server`.
- Logs mention `Actor runtime shutting down`, `Placement client shutting down`, or `Workflow engine stopped`.

## Diagnostic

Confirm the target context and affected pod:

```bash
kubectl config current-context
kubectl get deploy,pod -A | rg 'workflow-builder|workspace-runtime|swebench-coordinator|workflow-orchestrator|dapr-agent-py'
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

## Fix Steps

If `dapr-system` is currently healthy, recycle only the affected workflow-builder Deployment:

```bash
kubectl rollout restart deployment/<deployment> -n workflow-builder
kubectl rollout status deployment/<deployment> -n workflow-builder --timeout=180s
```

For the known ryzen incident affecting both runtime services:

```bash
kubectl rollout restart deployment/workspace-runtime deployment/swebench-coordinator -n workflow-builder
kubectl rollout status deployment/workspace-runtime -n workflow-builder --timeout=180s
kubectl rollout status deployment/swebench-coordinator -n workflow-builder --timeout=180s
```

Do not restart Dapr control-plane components first unless they are still unhealthy. Do not truncate actor state tables or clear scheduler state for a sidecar readiness-only issue.

## Verify

```bash
kubectl get deploy,pod -n workflow-builder | rg 'workspace-runtime|swebench-coordinator|workflow-orchestrator|dapr-agent-py'
kubectl get pod -n workflow-builder <new-pod> -o jsonpath='{range .status.containerStatuses[*]}{.name} ready={.ready} restarts={.restartCount}{"\n"}{end}'
kubectl exec -n workflow-builder <new-pod> -c <app-container> -- curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3501/v1.0/healthz
kubectl exec -n workflow-builder <new-pod> -c <app-container> -- curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3500/v1.0/metadata
```

Healthy sidecar probes return `204`, and the Deployment returns to `2/2`.

## Notes

- This failure is readiness-specific. Kubernetes liveness can pass because the sidecar process is alive while internal gRPC servers remain unready.
- If the new pod also gets stuck, treat `dapr-system` as actively unhealthy and inspect placement/scheduler/cert-manager before cycling more workloads.
- If logs show orphan workflow reminders or actor state errors instead of sidecar health errors, use the workflow-state runbook/gotcha path before deleting or truncating any state.
