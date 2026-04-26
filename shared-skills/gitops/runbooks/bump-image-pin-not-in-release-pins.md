# Runbook: Bump an image pin that lives OUTSIDE release-pins

## Symptoms / when to use

You've built or mirrored a new tag of one of the following on `ghcr.io/pittampalliorg/...`, but bumping `release-pins/workflow-builder-images.yaml` alone does **not** roll the change to dev/staging:

- `browserstation`
- `chrome-sandbox`
- `browser-use-agent-sandbox`
- `dapr-agent-py-sandbox`
- `dapr-agent-py-testing-sandbox`

These images are pinned through one of two paths that the matrix-generator's release-pins file does not own:

1. **Inline kustomize.images strings in `spoke-workloads-appset.yaml`** (browserstation, chrome-sandbox)
2. **`AGENT_RUNTIME_*_DEFAULT_IMAGE` env vars on `Deployment-workflow-builder.yaml`** (browser-use-agent-sandbox, dapr-agent-py-sandbox; consumed by `registry-sync.ts:725`)

Both bypass `release-pins/workflow-builder-images.yaml`. `kustomize.images` substitutes container `image:` fields; it does not substitute env var string values.

## Diagnostic — confirm where the pin lives

```bash
# Does release-pins reference this image at all?
grep -n "<image-name>" packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml || \
  echo "Not in release-pins — check the alternates below."

# Inline kustomize patch?
grep -n "<image-name>=ghcr" packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml

# AgentRuntime env var?
grep -n "AGENT_RUNTIME.*DEFAULT_IMAGE" packages/components/active-development/manifests/workflow-builder/Deployment-workflow-builder.yaml
```

## Fix steps

### Path A: browserstation / chrome-sandbox

Edit the inline kustomize.images entry in `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml`:

```yaml
patch: |
  - op: add
    path: /spec/source/kustomize
    value:
      images:
        # Bump the tag here:
        - 'gitea-ryzen.tail286401.ts.net/giteaadmin/browserstation=ghcr.io/pittampalliorg/browserstation:git-<NEW-SHA>'
        - 'gitea-ryzen.tail286401.ts.net/giteaadmin/chrome-sandbox=ghcr.io/pittampalliorg/chrome-sandbox:latest'
```

Commit + push to `origin/main`. Then because this is an ApplicationSet template change (NOT a release-pins change), the matrix-generator will not re-template until the env/hub PR is merged. See "ApplicationSet template-only re-render" in SKILL.md gotchas — push an empty commit on `origin/main` to bump the dry SHA if hydration appears stalled.

### Path B: browser-use-agent-sandbox / dapr-agent-py-sandbox (AgentRuntime CR images)

Two things must be updated together:

1. **Edit the env var literal** in `packages/components/active-development/manifests/workflow-builder/Deployment-workflow-builder.yaml`:

   ```yaml
   - name: AGENT_RUNTIME_BROWSER_USE_DEFAULT_IMAGE
     value: "ghcr.io/pittampalliorg/browser-use-agent-sandbox:git-<NEW-SHA>"
   - name: AGENT_RUNTIME_DEFAULT_IMAGE
     value: "ghcr.io/pittampalliorg/dapr-agent-py-sandbox:git-<NEW-SHA>"
   ```

   Commit + push to `origin/main`. `dev-workflow-builder` Application reads from `HEAD` directly so this lands without env/hub indirection.

2. **Patch every existing AgentRuntime CR** that's already published with the OLD image. `registry-sync.ts` only re-runs at agent publish time, so existing CRs keep their old `spec.environment.imageTag` until you patch them or the agent is re-published:

   ```bash
   # Find affected CRs:
   KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get agentruntime -n workflow-builder \
     -o jsonpath='{range .items[*]}{.metadata.name} {.spec.environment.imageTag}{"\n"}{end}' \
     | grep "<image-name>:git-<OLD-SHA>"

   # Patch each:
   KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl patch agentruntime -n workflow-builder <name> \
     --type=merge -p '{"spec":{"environment":{"imageTag":"ghcr.io/pittampalliorg/<image-name>:git-<NEW-SHA>"}}}'
   ```

   The kopf controller reconciles each patch into the underlying Deployment, which rolls a new pod with the new image.

### After both paths

If the parent ArgoCD app (`spoke-dev-workflow-builder`) is failing to apply the rendered child Application (e.g., `dev-browserstation`) with `Application.argoproj.io "..." is invalid: status.sync.comparedTo.source.repoURL: Required value`, this is a known SSA validation gap. Patch the live child Application directly to bypass:

```bash
ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-config -n argocd patch app dev-<child-name> --type=json \
  -p='[{\"op\":\"replace\",\"path\":\"/spec/source/kustomize/images/0\",\"value\":\"...\"}]'"
```

The parent will keep retrying with the failing apply, but the child's live spec is correct and the underlying RayCluster / Deployment will roll.

## Verify

For browserstation/chrome-sandbox: spec image on the live RayCluster reflects the new tag, and at least one fresh pod is running on the new image:

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get raycluster -n ray-system browserstation \
  -o jsonpath='{.spec.headGroupSpec.template.spec.containers[0].image}{"\n"}'

# Head doesn't auto-roll — delete it explicitly to pick up the new image:
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl delete pod -n ray-system browserstation-head-<id>
```

For AgentRuntime CR images: the matching `agent-runtime-<slug>` Deployment in `workflow-builder` namespace shows the new image, and on next workflow execution the spawned pod uses it.

## Why the split exists

The matrix-generator only watches `release-pins/workflow-builder-images.yaml` for parameters, so changes to other appset fields don't re-template per-spoke Applications. AgentRuntime CR images are runtime-resolvable from a static env var because the agent registry needs to know the image at agent-publish time before the AgentRuntime CR exists. There is no current GitOps loop that propagates a single tag through both paths automatically.
