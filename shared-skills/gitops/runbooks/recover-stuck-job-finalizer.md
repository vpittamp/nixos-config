# Runbook: Recover a stuck Job (db-migrate / hook with ArgoCD finalizer)

## Symptoms / when to use

A spoke's `db-migrate` (or any other ArgoCD sync hook Job) sits in `STATUS=Terminating` indefinitely after `kubectl delete job db-migrate`. The hub-side Application's `operationState.message` reads `waiting for completion of hook batch/Job/db-migrate` and never advances.

The cause: the Job has the ArgoCD hook finalizer:

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  get job db-migrate -o jsonpath='{.metadata.finalizers}'
# ["argocd.argoproj.io/hook-finalizer"]
```

When ArgoCD created the hook Job, it added a finalizer so it could clean up the Job after the sync wave completed. If the sync was interrupted (controller restart, app refresh during sync, etc.), the finalizer can outlive the cleanup logic and block deletion forever.

## Diagnostic

```bash
# Get spoke kubeconfig (see access-spoke-cluster-fallback.md)
kubectl --kubeconfig ~/.kube/hub-config get secret <spoke>-XXXXX-kubeconfig -n crossplane-system \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/<spoke>-kubeconfig
chmod 600 /tmp/<spoke>-kubeconfig

# Confirm the Job is stuck Terminating with a finalizer
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder get job db-migrate
# NAME         STATUS        COMPLETIONS   DURATION   AGE
# db-migrate   Terminating   0/1           55m        55m

KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  get job db-migrate -o jsonpath='finalizers: {.metadata.finalizers}{"\n"}deletionTS: {.metadata.deletionTimestamp}{"\n"}'

# Look at the pods (often there's an old Completed pod still attached)
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder get pods -l job-name=db-migrate
```

## Fix steps

```bash
# 1. Force-delete any pods with --grace-period=0 (they may have completed but are stuck on cleanup)
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  delete pod -l job-name=db-migrate --grace-period=0 --force --ignore-not-found

# 2. Patch off the finalizer so the Job can actually be deleted
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  patch job db-migrate --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'

# 3. Verify the Job is gone
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder get jobs

# 4. Shred the kubeconfig
shred -u /tmp/<spoke>-kubeconfig
```

## Verify — argocd retries automatically (usually)

ArgoCD's `selfHeal=true` should detect the missing Job and recreate it on the next reconcile. Watch the Application:

```bash
kubectl --kubeconfig ~/.kube/hub-config get app <spoke>-workflow-builder -n argocd \
  -o jsonpath='phase: {.status.operationState.phase}{"\nmsg: "}{.status.operationState.message}{"\n"}'
```

If the operation is itself stuck (the controller has marked the revision as failed and won't retry), you'll need to additionally run `recover-stuck-promotion.md` to terminate-op + force sync.

## When the new Job ALSO hangs

Common second-order failures after recreating db-migrate:

- **`Init:ImagePullBackOff` on the new Job pod** with `failed to resolve reference … ghcr.io/pittampalliorg/workflow-builder:<tag>: not found` → the tag in release-pins isn't on ghcr.io. Run `mirror-image-gitea-to-ghcr.md`.
- **`CrashLoopBackOff` with database connection errors** → the postgres StatefulSet on the spoke might be unavailable. `KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder get pods,sts`.
- **`CrashLoopBackOff` with migration errors** → the database schema is in a state the migration can't reconcile (rare, but a previous half-completed migration can cause this). `KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder logs job/db-migrate -c repair-schema-drift` then `-c migrate`.

## Risks

- Removing the finalizer bypasses ArgoCD's cleanup contract for that Job. ArgoCD will recreate the Job from spec but won't have a record of the previous attempt's outcome. For db-migrate this is fine (idempotent migrations) but for non-idempotent sync hooks it could cause double-execution. Inspect the hook's command before force-removing the finalizer if you don't recognize it.
- If the Job's pod has a pending finalizer (rare), `--force --grace-period=0` deletion can leave kubelet state inconsistent on the node. Usually self-heals; if it doesn't, drain the node.
