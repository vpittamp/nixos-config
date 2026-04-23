# Runbook: Recover a stuck Application / PromotionStrategy

## Symptoms / when to use

A hub-side ArgoCD Application's `operationState.phase` is `Running` for 10+ minutes (typically `dev-workflow-builder` or `staging-workflow-builder`), and `kubectl patch app <name> -p '{"operation":null}'` doesn't clear it. Common downstream symptom: hub controller log shows:

```
Skipping auto-sync: failed previous sync attempt to [<sha>] and will not retry for [<sha>]
```

This means ArgoCD has marked the revision as failed and refuses to retry, even after `selfHeal=true` would normally trigger.

## Diagnostic

```bash
# Confirm phase Running with stale startedAt
kubectl --kubeconfig ~/.kube/hub-config get app <app-name> -n argocd \
  -o jsonpath='phase: {.status.operationState.phase}{"\nstartedAt: "}{.status.operationState.startedAt}{"\nmessage: "}{.status.operationState.message}{"\n"}'

# Check controller logs (last few minutes)
kubectl --kubeconfig ~/.kube/hub-config -n argocd logs argocd-application-controller-0 --since=2m | \
  grep -iE "<app-name>|skipping auto-sync|failed previous"
```

If the `message` is `waiting for completion of hook batch/Job/db-migrate`, the underlying Job is stuck — see `recover-stuck-job-finalizer.md` first. Only fall through to this runbook if the operation itself won't terminate after the Job is cleared.

## Fix steps — argocd CLI via Tailscale

Plain `kubectl patch app … -p '{"operation":null}'` may not propagate through the controller's in-flight queue. Use the argocd CLI's proper terminate-op + force-sync, which the controller honors:

```bash
# 1. Login (Tailscale ProxyGroup argocd-hub is independent of per-spoke ProxyGroups)
ADMIN_PASS=$(kubectl --kubeconfig ~/.kube/hub-config -n argocd \
  get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login argocd-hub.tail286401.ts.net \
  --username admin --password "$ADMIN_PASS" --grpc-web
# Discard $ADMIN_PASS
unset ADMIN_PASS

# 2. Terminate the in-flight operation
argocd app terminate-op <app-name> --grpc-web

# 3. Force-sync (--force skips the "already attempted, won't retry" guard)
argocd app sync <app-name> --force --grpc-web

# Optional: wait for it
argocd app wait <app-name> --health --timeout 600 --grpc-web
```

## Verify

```bash
kubectl --kubeconfig ~/.kube/hub-config get app <app-name> -n argocd \
  -o jsonpath='sync: {.status.sync.status}{"\nhealth: "}{.status.health.status}{"\nphase: "}{.status.operationState.phase}{"\n"}'
# Expect: Synced + Healthy + Succeeded
```

If the new sync also fails (genuine application-level error, not a stuck operation), look at:
- The actual sync hook results: `kubectl get app <name> -o jsonpath='{.status.operationState.syncResult.resources}' | jq '.[] | select(.hookPhase != "Succeeded")'`
- Pod logs on the spoke (use Crossplane kubeconfig fallback if needed)

## Why kubectl patch alone doesn't work

ArgoCD's application-controller has an in-memory operation queue. Setting `.operation` to null on the CRD removes the desired-operation marker, but if the controller is mid-process on the operation it was already running, it doesn't necessarily honor the cancel — and `selfHeal` re-enqueues a new attempt for the same revision on the next reconcile, hitting the "won't retry failed revision" guard.

The argocd CLI's `TerminateOperation` API call goes through the API server which uses the controller's proper cancel path; combined with `app sync --force` it bypasses the failed-revision guard.

## Risks

- `--force sync` will re-run all hooks (db-migrate, sync-platform-oauth-apps). If db-migrate had already partially modified the database, re-running it should be idempotent (it's drizzle-kit migrations) but verify against the migration logs if the schema state matters.
- If multiple apps are stuck, terminate them one at a time so you can see which sync the controller is actually processing.
