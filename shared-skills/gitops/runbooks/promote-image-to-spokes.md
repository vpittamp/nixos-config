# Promote an image to dev

## Symptoms / when to use

User wants a new image tag of `workflow-builder` (or any other promoted workflow-builder-system component) running on **dev**.

Staging is dormant and Ryzen has a separate opt-in lane. This runbook covers
only the active dev promotion.

Normal path: hub Tekton built the image, pushed it to GHCR, and its
`update-stacks` task pushed release metadata to stacks `origin/main` or opened a
release-intent PR. The update touches
`release-pins/workflow-builder-images.yaml` and regenerates
`workflow-builder-system-overlays/dev/kustomization.yaml`.

Manual path: the tag has been built/imported and you need to edit release metadata yourself.

## Diagnostic — verify tag and digest exist on ghcr.io

Dev pulls from `ghcr.io/pittampalliorg/<image>:<tag>` and renders tag+digest
refs when `digests.<image>` is set. Confirm the tag exists before merging
release metadata.

```bash
# Preferred when you have registry credentials available:
skopeo inspect --no-tags docker://ghcr.io/pittampalliorg/<image>:git-<sha> | jq -r .Digest

# Or validate every release pin in the repo:
scripts/gitops/validate-workflow-builder-release-pins.sh
```

If missing → the outer-loop build never published that tag to GHCR; rebuild it from the source commit before promoting (see `runbooks/debug-funnel-orphan-tag.md` for the webhook/EventListener failure that suppresses the build).

## Fix steps

### Normal path — direct-main or release-intent PR

1. Inspect the hub Tekton `update-stacks` task logs first. Current workflow-builder pipelines often push directly to `origin/main`:

```bash
kubectl --kubeconfig ~/.kube/hub-config logs -n tekton-pipelines \
  <outer-loop-workflow-builder-...>-update-stacks-pod --all-containers --tail=240
```

If the logs show `Successfully pushed tag update`, record the stacks commit and skip to promotion tracking. If the logs mention a release branch/PR, continue below.

2. Find the release PR:

```bash
gh pr list --repo PittampalliOrg/stacks --state open --search "head:release/workflow-builder" \
  --json number,title,headRefName,updatedAt
```

3. Inspect the release metadata change:

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

4. Merge the PR when it is the desired release. The merge to `origin/main` starts source-hydrator + GitOps Promoter.

### Manual path — exceptional

1. Edit `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml`.

Available promoted keys:
`workflow-builder`, `workflow-mcp-server`, `mcp-gateway`, `function-router`, `workflow-orchestrator`, `code-parser`, `code-runtime`, `openshell-agent-runtime`, `openshell-sandbox`, `openshell-sandbox-xlsx`, `dapr-agent-py-sandbox`, `dapr-agent-py-testing-sandbox`, `browser-use-agent-sandbox`, `workspace-runtime`.

`images` is the compatibility tag map. If the image exists on GHCR, also fill the matching `digests`, `imageRefs`, `sourceShas`, `pipelineRuns`, and `updatedAts` entries. Use an empty digest only as a temporary compatibility fallback.

2. Validate release pins and sanity-build overlays:

```bash
scripts/gitops/validate-workflow-builder-release-pins.sh
for ovl in hub dev; do
  kubectl kustomize packages/overlays/$ovl > /dev/null && echo "$ovl OK" || echo "$ovl FAIL"
done
```

3. Commit and push. Review and merge a PR to `origin/main`; Source Hydrator
and Promoter handle dev.

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
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder -n dev -w
```

Expected timeline:
- Source Hydrator regenerates `env/spokes-dev-next` (webhook-accelerated, with polling as backstop).
- `workflow-builder-release` evaluates `argocd-health` plus the dev timer and auto-merges to `env/spokes-dev`.
- The managed dev agent/local controller syncs child Applications; `db-migrate` runs and the Deployment rolls.

If dev does not advance, inspect its `argocd-health` and timer statuses before intervening.

## Verify

```bash
# 1. App-level
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder \
  -n dev -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
# Should be: Synced + Healthy

# 2. Image actually live on dev
kubectl --context admin@dev -n workflow-builder get deploy workflow-builder \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# Should match ghcr.io/pittampalliorg/workflow-builder:<new-tag>@sha256:<digest> when digest metadata is present

# 3. Image overrides on the spoke-workloads-managed Application
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder -n dev \
  -o jsonpath='{.spec.source.kustomize.images}' | tr ',' '\n' | grep workflow-builder
```

Pass criteria: dev is Synced/Healthy at the new revision, pod images are
updated, and `db-migrate` has no errors.

## If something stuck

- App in `Running` / `waiting for completion of hook batch/Job/db-migrate` for >5 min → `runbooks/recover-stuck-job-finalizer.md`
- Controller log `Skipping auto-sync: failed previous sync attempt` → `runbooks/recover-stuck-promotion.md`
- `Init:ImagePullBackOff` for the new tag → your tag isn't on ghcr.io; the outer-loop build didn't produce it — rebuild from source, see `runbooks/debug-funnel-orphan-tag.md`
- PromotionStrategy `READY=False` → check `kubectl get changetransferpolicy -A -o yaml`; common cause is the stacks-repo write token expired
