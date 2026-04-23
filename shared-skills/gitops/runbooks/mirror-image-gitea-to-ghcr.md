# Runbook: Mirror an image from gitea-ryzen → ghcr.io

## Symptoms / when to use

A workflow-builder-system image tag exists on `gitea-ryzen.tail286401.ts.net/giteaadmin/<image>:git-<sha>` (because ryzen Tekton inner-loop built it) but is NOT on `ghcr.io/pittampalliorg/<image>:git-<sha>` (because hub Tekton outer-loop didn't run — usually because the GitHub webhook isn't reaching the hub; see `debug-funnel-orphan-tag.md` for that).

Concrete symptoms:
- After bumping `release-pins/workflow-builder-images.yaml`, dev/staging Job pods sit in `Init:ImagePullBackOff` with `failed to resolve reference … ghcr.io/pittampalliorg/<image>:<tag>: not found`.
- `gh api repos/PittampalliOrg/workflow-builder/hooks/<id>/deliveries` shows `status_code: 0` for recent pushes (webhook never reached hub) → this confirms outer-loop never ran for this commit.

## Diagnostic — confirm the gap

```bash
# Source: tag exists on gitea-ryzen?
skopeo inspect --raw \
  docker://gitea-ryzen.tail286401.ts.net/giteaadmin/<image>:git-<sha> | jq .schemaVersion
# Should print 2 (schema valid)

# Destination: tag missing on ghcr.io?
GHCR_TOKEN=$(curl -sS "https://ghcr.io/token?scope=repository:pittampalliorg/<image>:pull" | jq -r .token)
curl -sI -H "Authorization: Bearer $GHCR_TOKEN" \
  "https://ghcr.io/v2/pittampalliorg/<image>/manifests/git-<sha>" | head -1
# HTTP/2 200 = exists (you don't need to mirror); 404 / "manifest unknown" = missing
```

If source exists and dest is missing → mirror.

## Fix steps

**Run from ryzen** — hub pods cannot resolve `gitea-ryzen.tail286401.ts.net` through cluster DNS, and your local docker config probably lacks org write scope to `pittampalliorg`. Use the hub's `ghcr-push-credentials` Secret (the same secret outer-loop uses).

```bash
# 1. Extract hub's GHCR push credentials to a local authfile
kubectl --kubeconfig ~/.kube/hub-config get secret ghcr-push-credentials -n tekton-pipelines \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/ghcr-config.json
chmod 600 /tmp/ghcr-config.json

# 2. Mirror with skopeo (from ryzen — both registries resolve here)
skopeo copy --retry-times 3 --dest-authfile /tmp/ghcr-config.json \
  docker://gitea-ryzen.tail286401.ts.net/giteaadmin/<image>:git-<sha> \
  docker://ghcr.io/pittampalliorg/<image>:git-<sha>

# 3. ALWAYS shred the auth file
shred -u /tmp/ghcr-config.json
```

If you have multiple images to mirror, repeat step 2 for each (workflow-builder + workflow-orchestrator + browser-use-agent-sandbox is a typical "catch up dev/staging to ryzen" set).

## Verify

```bash
# Mirror succeeded — manifest now resolvable on ghcr.io
GHCR_TOKEN=$(curl -sS "https://ghcr.io/token?scope=repository:pittampalliorg/<image>:pull" | jq -r .token)
curl -sI -H "Authorization: Bearer $GHCR_TOKEN" \
  "https://ghcr.io/v2/pittampalliorg/<image>/manifests/git-<sha>" | head -1
# HTTP/2 200

# If a spoke pod was already in ImagePullBackOff for this tag, it will retry within ~30s.
# If you want to force the retry, delete the stuck pod (Deployment will recreate):
KUBECONFIG=/tmp/dev-kubeconfig kubectl -n workflow-builder delete pod -l app=workflow-builder
```

## Why outer-loop should normally do this for you

The hub Tekton `outer-loop-build` Pipeline (in `tekton-pipelines` ns on hub) builds the image fresh from GitHub source AND pushes to ghcr.io with the same `git-<sha>` tag, then commits the bump to `release-pins/workflow-builder-images.yaml` automatically. So a fresh push to `PittampalliOrg/workflow-builder` should trigger a build, push to ghcr.io, and stage the dev/staging rollout — no manual mirror needed.

When that flow is broken (typically: GitHub webhook → Tailscale Funnel → hub EventListener path), you fall back to this manual mirror. **Fix the upstream cause too** — see `debug-funnel-orphan-tag.md` — otherwise you'll be mirroring by hand for every future commit.

## Risks

- **The mirrored image is built from gitea-ryzen, not from the GitHub source repo.** If the gitea-ryzen image has any local divergence from the GitHub `git-<sha>` commit (uncommitted local changes baked in, different Dockerfile target, etc.), the manually-mirrored ghcr.io tag won't be byte-identical to what outer-loop would produce. For workflow-builder this rarely matters because the inner-loop pipeline builds from gitea-ryzen which mirrors the GitHub source, but **don't use this mirror procedure for production-only images** without confirming source provenance.
- **You're using hub's `ghcr-push-credentials`** which has org-write scope. Treat the extracted authfile carefully and shred it as soon as the mirror is done.
