# Runbook: Promote an image to dev / staging spokes

## Symptoms / when to use

User wants a new image tag of `workflow-builder` (or any other promoted workflow-builder-system component) running on dev and/or staging.

Normal path: hub Tekton outer-loop has built the image, pushed it to GHCR, and opened a `release/workflow-builder-*` release-intent PR that updates `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml`.

Manual path: the tag has been built/imported and you need to edit release metadata yourself.

## Diagnostic — verify tag and digest exist on ghcr.io

dev/staging pull from `ghcr.io/pittampalliorg/<image>:<tag>` and render tag+digest refs when `digests.<image>` is set. Confirm the tag exists before merging release metadata, otherwise the spoke pods will land in `Init:ImagePullBackOff`:

```bash
# Preferred when you have registry credentials available:
skopeo inspect --no-tags docker://ghcr.io/pittampalliorg/<image>:git-<sha> | jq -r .Digest

# Or validate every release pin in the repo:
scripts/gitops/validate-workflow-builder-release-pins.sh
```

If missing → run `runbooks/mirror-image-gitea-to-ghcr.md` first.

## Fix steps

### Normal path — release-intent PR

1. Find the release PR:

```bash
gh pr list --repo PittampalliOrg/stacks --state open --search "head:release/workflow-builder" \
  --json number,title,headRefName,updatedAt
```

2. Inspect the release metadata change:

```bash
gh pr diff <number> --repo PittampalliOrg/stacks
```

Confirm the relevant key changed consistently under:

- `images`
- `digests`
- `imageRefs`
- `sourceShas`
- `pipelineRuns`
- `updatedAts`

3. Merge the PR when it is the desired release. The merge to `origin/main` starts source-hydrator + GitOps Promoter.

### Manual path — exceptional

1. Edit `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml`.

Available promoted keys:
`workflow-builder`, `workflow-mcp-server`, `mcp-gateway`, `function-router`, `workflow-orchestrator`, `code-parser`, `code-runtime`, `openshell-agent-runtime`, `openshell-sandbox`, `openshell-sandbox-xlsx`, `dapr-agent-py-sandbox`, `dapr-agent-py-testing-sandbox`, `browser-use-agent-sandbox`, `workspace-runtime`.

`images` is the compatibility tag map. If the image exists on GHCR, also fill the matching `digests`, `imageRefs`, `sourceShas`, `pipelineRuns`, and `updatedAts` entries. Use an empty digest only as a temporary compatibility fallback.

2. Validate release pins and sanity-build overlays:

```bash
scripts/gitops/validate-workflow-builder-release-pins.sh
for ovl in hub dev staging kind-ryzen; do
  kubectl kustomize packages/overlays/$ovl > /dev/null && echo "$ovl OK" || echo "$ovl FAIL"
done
```

3. Commit and push. For release-only metadata, opening/merging a PR to `origin/main` is sufficient for dev/staging; use `scripts/gitops/check-branch-drift.sh` afterward if you need the ryzen mirror aligned too.

```bash
git add packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml
git commit -m "chore(release-pins): release <image> <tag>"
git push origin HEAD:release/workflow-builder-<image>-<tag>
gh pr create --repo PittampalliOrg/stacks --base main --head release/workflow-builder-<image>-<tag>
```

4. Watch the promoter advance:

```bash
# These are read-only; use Ctrl-C when you've seen enough
kubectl --kubeconfig ~/.kube/hub-config get changetransferpolicy -A -w
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder staging-workflow-builder -n argocd -w
```

Expected timeline:
- ~30-90s after merge to `origin/main`: hub source-hydrator regenerates `env/spokes-dev-next` and `env/spokes-staging-next`
- ~30-60s: `workflow-builder-release` PromotionStrategy creates PRs on the env-next branches and evaluates `argocd-health` plus `timer`
- ~30-60s: dev merges after health (`timer=0s`)
- ~10m plus reconcile latency: staging merges after health plus soak timer
- ~1-2 min: hub ArgoCD picks up the new env/spokes-* HEAD, syncs the spoke apps; `db-migrate` Job runs; `workflow-builder` Deployment rolls forward

If dev's `argocd-health` gate fails (Deployment Unhealthy), staging won't promote until dev is recovered. If staging is healthy but waiting, check the `timer` CommitStatus before intervening.

## Verify

```bash
# 1. App-level
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder staging-workflow-builder \
  -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
# Both should be: Synced + Healthy

# 2. Image actually live on the spoke (use Crossplane kubeconfig fallback if Tailscale broken)
KUBECONFIG=/tmp/dev-kubeconfig kubectl -n workflow-builder get deploy workflow-builder \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# Should match ghcr.io/pittampalliorg/workflow-builder:<new-tag>@sha256:<digest> when digest metadata is present

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
