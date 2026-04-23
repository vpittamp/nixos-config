# Runbook: Promote an image to dev / staging spokes

## Symptoms / when to use

User wants a new image tag of `workflow-builder` (or any other workflow-builder-system component) running on dev and/or staging. The tag has been built (either by ryzen Tekton inner-loop, or by hub Tekton outer-loop, or imported manually) and the user has identified the SHA / tag they want deployed.

## Diagnostic — verify the tag exists on ghcr.io

dev/staging pull from `ghcr.io/pittampalliorg/<image>:<tag>`. Confirm the tag exists before editing release-pins, otherwise the spoke pods will land in `Init:ImagePullBackOff`:

```bash
GHCR_TOKEN=$(curl -sS "https://ghcr.io/token?scope=repository:pittampalliorg/workflow-builder:pull" | jq -r .token)
curl -sI -H "Authorization: Bearer $GHCR_TOKEN" \
  "https://ghcr.io/v2/pittampalliorg/workflow-builder/manifests/git-<sha>" | head -1
# HTTP/2 200 = exists; HTTP/2 404 / "manifest unknown" = missing
```

If missing → run `runbooks/mirror-image-gitea-to-ghcr.md` first.

## Fix steps

1. **Edit `release-pins`** in the stacks repo:

```bash
cd /path/to/stacks/main
# Edit packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml
# Update the relevant key, e.g.:
#   workflow-builder: git-c0f662425e0e301abbcb065001ebe21a2350d970
```

Available keys (don't add new ones unless you also update the AppSet template):
`workflow-builder`, `workflow-mcp-server`, `mcp-gateway`, `function-router`, `workflow-orchestrator`, `code-parser`, `code-runtime`, `openshell-agent-runtime`, `openshell-sandbox`, `openshell-sandbox-xlsx`, `dapr-agent-py-sandbox`, `dapr-agent-py-testing-sandbox`, `browser-use-agent-sandbox`, `workspace-runtime`.

2. **Sanity-build the affected overlays** before pushing:

```bash
for ovl in hub dev staging kind-ryzen; do
  kubectl kustomize packages/overlays/$ovl > /dev/null && echo "$ovl OK" || echo "$ovl FAIL"
done
```

3. **Commit + push to BOTH remotes** (origin/main is what hub ArgoCD reads, gitea-ryzen/main keeps the mirror in sync):

```bash
git add packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml
git commit -m "chore(release-pins): bump <image> to <tag>"
git push origin HEAD:main
git push gitea-ryzen HEAD:main
```

4. **Watch the promoter advance:**

```bash
# These are read-only; use Ctrl-C when you've seen enough
kubectl --kubeconfig ~/.kube/hub-config get changetransferpolicy -A -w
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder staging-workflow-builder -n argocd -w
```

Expected timeline:
- ~30-90s: hub source-hydrator regenerates `env/spokes-dev-next` and `env/spokes-staging-next`
- ~30-60s: `workflow-builder-release` PromotionStrategy creates PRs on the env-next branches and `argocd-health` gate evaluates
- ~30-60s: with `autoMerge: true`, both env/spokes-dev and env/spokes-staging get merged
- ~1-2 min: hub ArgoCD picks up the new env/spokes-* HEAD, syncs the spoke apps; `db-migrate` Job runs; `workflow-builder` Deployment rolls forward

If dev's `argocd-health` gate fails (Deployment Unhealthy), staging won't promote until dev is recovered.

## Verify

```bash
# 1. App-level
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder staging-workflow-builder \
  -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
# Both should be: Synced + Healthy

# 2. Image actually live on the spoke (use Crossplane kubeconfig fallback if Tailscale broken)
KUBECONFIG=/tmp/dev-kubeconfig kubectl -n workflow-builder get deploy workflow-builder \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# Should match ghcr.io/pittampalliorg/workflow-builder:<new-tag>

# 3. Image overrides on the spoke-workloads-managed Application
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder -n argocd \
  -o jsonpath='{.spec.source.kustomize.images}' | tr ',' '\n' | grep workflow-builder
```

Pass criteria: both apps Synced + Healthy at the new revision, pod images updated, no `db-migrate` errors in pod logs.

## If something stuck

- App in `Running` / `waiting for completion of hook batch/Job/db-migrate` for >5 min → `runbooks/recover-stuck-job-finalizer.md`
- Controller log `Skipping auto-sync: failed previous sync attempt` → `runbooks/recover-stuck-promotion.md`
- `Init:ImagePullBackOff` for the new tag → `runbooks/mirror-image-gitea-to-ghcr.md` (your tag isn't on ghcr.io)
- PromotionStrategy `READY=False` → check `kubectl get changetransferpolicy -A -o yaml`; common cause is the stacks-repo write token expired
