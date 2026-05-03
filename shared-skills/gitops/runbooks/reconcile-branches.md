# Runbook: Reconcile origin/main ↔ gitea-ryzen/main

## Symptoms / when to use

`git log origin/main..gitea-ryzen/main` and the reverse both show 5+ commits each → the branches have diverged. Common because two automated paths write different sources of truth:

- **Hub Tekton outer-loop** opens release-intent PRs or pushes release metadata to `origin/main` (file: `release-pins/workflow-builder-images.yaml`)
- **Hub Tekton Gitea/dev-image lane** commits ryzen-only image bumps to `gitea-ryzen/main` (commit subject: `chore(dev-images): deploy <image> <tag> to ryzen`, file: `active-development/manifests/<image>/kustomization.yaml`)

Reconcile when:
- Bumping dev/staging to "what ryzen has" — needs ryzen's tags merged into origin first
- Manual edit on one side that should also live on the other
- Generally letting the branches drift more than 2 weeks

## Diagnostic — assess the gap

```bash
git fetch --all --prune

# Commits on gitea-ryzen NOT on origin (typically ryzen-only image bumps + agent-runtime-controller):
git log --oneline origin/main..gitea-ryzen/main | head -20

# Commits on origin NOT on gitea-ryzen:
git log --oneline gitea-ryzen/main..origin/main | head -20

# Files modified on BOTH sides (true conflicts after merge):
comm -12 \
  <(git diff --name-only origin/main...gitea-ryzen/main | sort) \
  <(git diff --name-only gitea-ryzen/main...origin/main | sort)
```

Expect ~10 commits each way after a few days of activity. The "files modified on both sides" list is usually 5-11 files; that's what you'll have to resolve.

## Fix steps

1. **Branch off the side hub ArgoCD reads** (`origin/main`) and merge gitea-ryzen with `--no-ff`:

```bash
git checkout -b merge-ryzen-into-main-$(date +%Y%m%d) origin/main
git merge --no-ff --no-commit gitea-ryzen/main
# Auto-merge will resolve most files; leaves the conflicts in UU state
```

2. **Resolve the ~5-11 conflicts** by these defaults (override per-case as needed):

| Conflict file | Resolution rule |
|---|---|
| `packages/components/active-development/manifests/<workload>/kustomization.yaml` (image pins for ryzen) | **Take gitea-ryzen** — it has the newer ryzen tag |
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` | **Take origin's schema v2 structure**, then update the `images` tag and matching `digests`/provenance maps only for tags that exist on GHCR |
| `packages/components/hub-tekton/manifests/workflow-builder-builds/kustomization.yaml` and other Tekton resource lists | **Union** — keep all entries from both sides (origin tends to add new pipelines first) |
| `packages/components/active-development/manifests/dapr-agent-py/Component-dapr-agent-py-statestore.yaml` and other Dapr Component scopes | **Take gitea-ryzen** (it's the working scope set; origin may have a partial refactor) |
| `packages/components/active-development/manifests/.../ExternalSecret-*.yaml` (data lists like `INTERNAL_API_TOKEN`, `BROWSERSTATION_API_KEY`) | **Union** — keep all data entries from both sides |
| `packages/components/active-development/manifests/workflow-builder/Deployment-workflow-builder.yaml` (env vars) | **Hand-merge** — keep origin's structural env additions (e.g., GITEA admin creds), bump any embedded image tags to the latest ryzen value |
| `packages/components/active-development/manifests/workflow-builder/Component-workflowstatestore.yaml` | **Take gitea-ryzen** (broader scope including dapr-agent-py / workflow-builder needed by the working architecture) |

After resolving each:

```bash
git add <file>
```

3. **Sanity-build all four overlays before committing:**

```bash
for ovl in hub dev staging kind-ryzen; do
  kubectl kustomize packages/overlays/$ovl > /dev/null && echo "$ovl OK" || echo "$ovl FAIL"
done
```

If any FAIL, fix before committing.

4. **Commit + push to BOTH remotes** so they reconverge:

```bash
git commit -m "$(cat <<'EOF'
Merge gitea-ryzen/main and bump release-pins

Reconciles divergence between origin/main and gitea-ryzen/main, then sets
release-pins tags to match ryzen so dev/staging catch up.

<list of image bumps>
<conflict-resolution notes per file>
EOF
)"

git push origin HEAD:main
git push gitea-ryzen HEAD:main
```

If the merge includes ryzen root/child Application spec changes (for example app `ignoreDifferences`, new app resources, or root overlay changes), also fast-forward the branch tracked by ryzen's root Application:

```bash
git push gitea-ryzen HEAD:ryzen-main
```

## Verify

```bash
# Both main branches should now point at the same commit:
git rev-parse origin/main gitea-ryzen/main

# If ryzen app-spec changes were included, ryzen-main should also match:
git ls-remote gitea-ryzen refs/heads/main refs/heads/ryzen-main

# Hub ArgoCD picks up the new origin/main HEAD; check root-application revision:
kubectl --kubeconfig ~/.kube/hub-config get app root-application -n argocd \
  -o jsonpath='{.status.sync.revision}{"\n"}'

# spoke-workloads ApplicationSet re-templates dev/staging apps with new release-pins tag/digest metadata;
# expect dev-workflow-builder and staging-workflow-builder to enter a sync within ~2 min.
```

## Risks

- **Tekton may commit again during the merge.** If the hub Gitea/dev-image lane lands a `chore(dev-images):` commit on gitea-ryzen between your fetch and push, you'll see a non-fast-forward push rejection. Re-merge and try again.
- **The release-pins update triggers a Promoter rollout** as soon as the merge lands on origin/main. Verify the new image tags/digests exist on ghcr.io before pushing (otherwise dev workflow-builder lands in ImagePullBackOff). If the bump is for ryzen-only tags that haven't been mirrored to ghcr.io, run `runbooks/mirror-image-gitea-to-ghcr.md` first, then `scripts/gitops/validate-workflow-builder-release-pins.sh`.
- **Long branch-divergence (>50 commits each way)** is harder to merge cleanly; consider doing it in stages or asking for help.
