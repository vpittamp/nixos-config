# Recover Ryzen idpbuilder Sync

Use this when `idpbuilder stacks sync` on ryzen pushes unexpected image pins, times out waiting for old revisions, or leaves ArgoCD apps stuck in `Running` operations after a local Gitea snapshot.

## Symptoms

- A manual sync fails with `idpbuilder stacks sync lock is already held ...`.
- A sync times out waiting for commit `A`, but most apps already show a later revision `B`.
- A sync fails with `sync to <A> superseded by <B>`.
- Active-development apps suddenly reference `gitea.cnoe.localtest.me:9443/...:git-*` or another release-pin-derived local registry ref instead of an intentional `gitea-ryzen.tail286401.ts.net/...` or GHCR pin.
- ArgoCD app `.operation.sync.revision` points at an older snapshot than `.status.sync.revision`, and the message waits for a Deployment that is using an old image.

## Diagnostic

Check running syncs first:

```bash
ps -eo pid,ppid,stat,etime,cmd | rg 'idpbuilder stacks sync|PID'
source deployment/scripts/cluster-menu.sh
cluster-watch-status
```

Review local Gitea history and reflog:

```bash
git fetch gitea main
git log --date=iso --pretty=format:'%h %ad %s' --max-count=20 gitea/main
git reflog show --date=iso gitea/main | sed -n '1,80p'
```

Compare the suspect image pins across snapshots:

```bash
git show <sha>:packages/components/active-development/manifests/openshell-agent-runtime/kustomization.yaml | sed -n '58,66p'
git show <sha>:packages/components/active-development/manifests/swebench-coordinator/kustomization.yaml | sed -n '23,30p'
```

Check for stale Argo operations:

```bash
kubectl get app <app> -n argocd -o jsonpath='{.operation.sync.revision}{"\n"}{.status.operationState.phase}{"\n"}{.status.operationState.syncResult.revision}{"\n"}{.status.operationState.message}{"\n"}'
```

## Fix Steps

1. Stop duplicate one-shot syncs or watchers if the lock reports another active sync. Keep only the single sync source you intend to publish.
2. Choose a source tree with the correct manifests. If preserving ryzen-local image pins, do not use a clean `origin/main` tree unless it contains those pins.
3. Publish recovery snapshots with seed rewrites disabled. Current `idpbuilder stacks sync` already defaults this way, but keep the flag explicit in recovery commands:

```bash
idpbuilder stacks sync \
  --stacks-repo <source-tree> \
  --reset-local-history \
  --seed-images=false \
  --container-engine podman \
  --seed-image-push-engine skopeo \
  --sync-wait-timeout 8m
```

4. If Argo keeps applying an old operation revision after the current Gitea snapshot is correct, clear only the stale app operation and hard-refresh it:

```bash
kubectl patch application <app> -n argocd --type=json -p='[{"op":"remove","path":"/operation"}]'
kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

Do not clear operations blindly across the fleet. Verify the current snapshot first.

## Verify

Confirm local Gitea has the desired snapshot:

```bash
git fetch gitea main
git rev-parse gitea/main
git show gitea/main:<path-to-kustomization>
```

Confirm the critical apps are synced and healthy:

```bash
kubectl get app -n argocd dapr-runtime openshell-agent-runtime swebench-coordinator workflow-builder \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,OP:.status.operationState.phase,REV:.status.sync.revision
```

Confirm live images and pods, not only Argo status:

```bash
kubectl get deploy,pod -n openshell -l app=dapr-agent-py -o wide
kubectl get deploy,pod -n workflow-builder -l app=swebench-coordinator -o wide
```

## Current Tool Behavior

- Mutating `idpbuilder stacks sync` takes a nonblocking lock beside the sync cache for the full one-shot sync or watch lifetime. Lock contention reports the cluster, repo, branch, cache, and lock path.
- `idpbuilder stacks sync` defaults `--seed-images=false`; `idpbuilder stacks create` still seeds by default for bootstrap/recreate.
- Explicit `idpbuilder stacks sync --seed-images=true` warns when it rewrites active-development kustomizations in the local Gitea snapshot.
- While waiting for commit `A`, idpbuilder detects watched apps or the Gitea branch moving to a descendant commit `B` and reports `sync to <A> superseded by <B>` instead of a generic timeout.
