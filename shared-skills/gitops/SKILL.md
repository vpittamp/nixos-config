---
name: gitops
description: Use this skill when the user is working with the PittampalliOrg/stacks GitOps system — promoting an image to dev/staging/ryzen, reconciling origin/main with gitea-ryzen/main, recovering a stuck ArgoCD Application or PromotionStrategy, debugging a hub Tekton outer-loop that didn't fire, mirroring an image from gitea-ryzen to ghcr.io, rotating a per-spoke GitHub or Google OAuth client secret, reaching a spoke cluster (dev, staging, ryzen) when Tailscale is broken, or anything involving release-pins/workflow-builder-images.yaml, env/spokes-dev, env/spokes-staging, env/hub-next, source-hydrator, GitOps Promoter, or the ts-tekton-github-triggers Funnel proxy. Provides a decision tree, the two-image-pin mental model, and runbooks for the failure modes that actually happen in this hub-and-spoke Talos / ArgoCD / Tekton / GitOps Promoter setup.
---

# GitOps for PittampalliOrg/stacks

Operational knowledge for the hub-and-spoke gitops system across **dev**, **staging**, **ryzen** (kind), and **hub** (Talos control plane). Read this whole file, then drill into `reference/` or `runbooks/` based on the decision tree.

## Orientation

- **Hub** is a Talos cluster on Hetzner. It runs a single ArgoCD that manages itself **and** all spokes via cluster secrets.
- **Spokes**: `dev`, `staging` (Talos on Hetzner), and `ryzen` (kind on the user's workstation). The hub ArgoCD pushes workloads to all three.
- **Two Tekton instances**:
  - **Hub Tekton** (outer-loop): triggered by GitHub webhooks on app repos (`PittampalliOrg/workflow-builder`, etc.); builds images, pushes to **ghcr.io**, commits image-tag bumps to `origin/main` (GitHub) at `release-pins/workflow-builder-images.yaml`. This drives **dev/staging**.
  - **Ryzen Tekton** (inner-loop): triggered locally on ryzen; builds images, pushes to the **gitea-ryzen** registry, commits to `gitea-ryzen/main` at `active-development/manifests/<image>/kustomization.yaml`. This drives **ryzen** only.
- **GitOps Promoter** (`workflow-builder-release` PromotionStrategy) gates the dev → staging promotion through `argocd-health` checks; both have `autoMerge: true`.
- **Source-hydrator** renders `packages/overlays/<spoke>` → `env/spokes-<spoke>-next`; promoter merges to `env/spokes-<spoke>`; spoke-side ArgoCD apps sync from there.

The two image-pin systems for the **same workflow-builder base** are the most common source of confusion. Read `reference/architecture.md` first if you've never seen this setup.

## The "which file?" matrix (single most-referenced piece of knowledge)

| Cluster | Image source | Bump path | Branch the bump lands on |
|---|---|---|---|
| **ryzen** | `packages/components/active-development/manifests/<image>/kustomization.yaml` (`images:` block) | Ryzen Tekton inner-loop pipeline `workflow-builder-image-build` (commit subject: `chore(dev-images): deploy <image> <tag> to ryzen`) | `gitea-ryzen/main` (Gitea on ryzen) — **NOT pushed to GitHub** |
| **dev / staging** | `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` (consumed by `spoke-workloads` ApplicationSet matrix generator; rewrites every gitea/local registry name to `ghcr.io/pittampalliorg/...`) | Hub Tekton outer-loop pipeline `outer-loop-build` (triggered by GitHub webhook on the app repo) | `origin/main` (GitHub) |
| **hub** itself | source-hydrator from `packages/overlays/hub` on `origin/main` → `env/hub-next` → `env/hub` (gated by `stacks-environments` PromotionStrategy) | Edit overlay; merge to `origin/main` | `origin/main` (GitHub) |

`agent-runtime-controller` is a third path: bumped directly in `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` (no per-cluster override), so a single bump applies to all spokes once it's on `origin/main`.

## Decision tree

### "I need to roll out / promote / bump an image"

1. Which cluster? **ryzen only** → handled automatically by ryzen Tekton inner-loop on the next push to the app repo. Nothing to do in stacks unless you're adding a new image.
2. **dev or staging** → edit `release-pins/workflow-builder-images.yaml` on `origin/main`. **Verify the new tag exists on `ghcr.io/pittampalliorg/...` first** (outer-loop normally builds this). If not, see `runbooks/mirror-image-gitea-to-ghcr.md`. Then `runbooks/promote-image-to-spokes.md`.
3. Want to mirror current ryzen tags into dev/staging (typical "catch up" task) → first run `runbooks/reconcile-branches.md` (origin/main and gitea-ryzen/main usually diverge), then bump release-pins as part of the merge commit.

### "An ArgoCD app is OutOfSync / stuck"

1. Check `kubectl get app <name> -n argocd -o jsonpath='{.status.operationState.phase}'`.
2. **Phase=Running for hours?** Check `.status.operationState.message` — usually `waiting for completion of hook batch/Job/db-migrate`. Drill: `kubectl get jobs -n workflow-builder` on the spoke; if `db-migrate` is stuck Terminating, see `runbooks/recover-stuck-job-finalizer.md`.
3. **Controller log shows "Skipping auto-sync: failed previous sync attempt"?** ArgoCD won't retry the same revision — see `runbooks/recover-stuck-promotion.md` (terminate-op + force sync via argocd CLI on Tailscale).
4. **Job Pod is `Init:ImagePullBackOff` with "not found"?** The image isn't on ghcr.io yet — see `runbooks/mirror-image-gitea-to-ghcr.md`.

### "GitHub webhook didn't fire / image is on gitea-ryzen but missing on ghcr.io"

Triage by `gh api .../hooks/<id>/deliveries` `status_code` first — there are TWO common failure modes on the same path:

- **`status_code: 0` + `dig @1.1.1.1 tekton-hub.tail286401.ts.net` NXDOMAIN** → Tailscale Funnel orphan-tag on `ts-tekton-github-triggers` proxy. The `policy.hujson` lost a tag the device still uses; control plane drops the funnel cap. See `runbooks/debug-funnel-orphan-tag.md` (Funnel orphan tag section).
- **`status_code: 202` (accepted) but no PipelineRun on hub** → EL processing failure. `el-github-outer-loop` logs show `Post "": unsupported protocol scheme ""` at `sink/sink.go:413` for the matching `/triggers-eventid`. Same runbook, "EL processing failure" section. Workaround: skopeo-mirror to ghcr.io + bump release-pins manually until the EL is fixed.

### "I shipped a migration but the new columns aren't on dev/staging"

Almost always: the SQL file in `drizzle/` is missing from `drizzle/meta/_journal.json`. `npx drizzle-kit migrate` (the `db-migrate` Sync hook) silently skips files without journal entries — Job exits 0 but nothing gets applied. See `runbooks/fix-drizzle-migration.md`. (BFF will then 500 on every query that includes the new column.)

### "I want to track a promotion in flight"

PromotionStrategy + ChangeTransferPolicy + spoke ArgoCD apps each show a different layer. See `runbooks/track-promotion-state.md` for a CLI cheat-sheet. Most "stuck" reports are actually normal ~3 min source-hydrator poll cycles.

### "I need kubectl on a spoke (dev / staging) and Tailscale isn't working"

See `reference/access-paths.md` for normal paths and `runbooks/access-spoke-cluster-fallback.md` for the Crossplane-kubeconfig-secret fallback.

### "OAuth / social login broken — `client_id and/or client_secret passed are incorrect`"

Almost always: KeyVault `*-CLIENT-ID-*` and `*-CLIENT-SECRET-*` were rotated at different times (compare `attributes.updated`). See `runbooks/rotate-oauth-secret.md`. **Watch for the ESO refresh ↔ pod restart race** — `reference/secret-flow.md`.

## Critical gotchas (memorize these)

- **Branch divergence is normal.** `origin/main` and `gitea-ryzen/main` drift 10+ commits each way after a few days because two different Tekton instances commit independently. Reconcile periodically via `runbooks/reconcile-branches.md`. Eleven files commonly conflict.
- **Tailscale Funnel orphan tags silently break webhooks.** If a tag is removed from `policy.hujson` but a device still uses it, the operator pod claims "Funnel on" locally but the control plane revokes the cap. Public DNS goes NXDOMAIN. Diagnostic: `tailscale status --json | jq '.Self.{Tags, CapMap}'` from inside the proxy pod.
- **ESO refresh ↔ pod restart race.** When rotating a KeyVault secret, ESO may not finish writing the K8s Secret before a Deployment restart kicks off. The new pod reads the stale value. Always verify the K8s Secret head matches the new value **before** triggering the restart.
- **Hub pods cannot resolve `gitea-ryzen.tail286401.ts.net`.** Use the Tailscale **egress** service pattern (`gitea-ryzen-egress.tailscale.svc.cluster.local`) or run skopeo/git from ryzen host instead of inside hub.
- **Stacks repo is mirrored to two remotes.** `origin/main` (GitHub) feeds hub ArgoCD. `gitea-ryzen/main` feeds ryzen. Pushing to only one causes drift. After a manual change to stacks, push to both unless you specifically want one-sided.
- **`argocd-hub.tail286401.ts.net` works even when other Tailscale ProxyGroups are down.** It's an independent ProxyGroup. When per-spoke Tailscale access is broken, you can still drive ArgoCD ops from the hub via `argocd login argocd-hub.tail286401.ts.net --grpc-web`.
- **Drizzle Kit silently skips SQL files lacking `_journal.json` entries.** The `db-migrate` Sync hook on dev/staging runs `npx drizzle-kit migrate`, which globs `drizzle/*.sql` BUT only applies files with a matching `entries[]` tag in `drizzle/meta/_journal.json`. Job exits 0 either way — easy to miss. Always update the journal when adding a migration; older files in the repo (0006/0007/0020/0032/0037-0043) lack journal entries because their columns were applied via out-of-band paths historically. See `runbooks/fix-drizzle-migration.md`.
- **Two migration runners read from two different directories.** `src/lib/server/startup.ts` reads from `atlas/migrations/` (timestamp-prefixed); `npx drizzle-kit migrate` reads from `drizzle/` (incremental + journal-gated). The production image's `Dockerfile` copies `drizzle/` but `.dockerignore` excludes `atlas/`, so the atlas-runner is effectively only active in the ryzen devspace pod (which file-syncs source). New migrations usually need to live in BOTH dirs, both idempotent (`ADD COLUMN IF NOT EXISTS`).
- **Source-hydrator polls every ~3 min.** When you bump `release-pins` on origin/main, expect 5-8 min before dev's pod is rolling on the new image (hydrator + promoter + spoke ArgoCD each have their own poll interval). `argocd app refresh --hard` triggers manifest re-render but does NOT immediately repoll branch tips. `argocd app sync --revision <sha>` is rejected on auto-sync + branch-tracking apps (`Cannot sync to <sha>: auto-sync currently set to <branch>`). Don't hard-sync; wait. See `runbooks/track-promotion-state.md` for what's-actually-stuck triage.
- **`git status --porcelain` `R ` prefix means "renamed in INDEX, already staged".** Filtering with `grep -E "^A |^M "` MISSES it. After a stale `git add` or interrupted commit, your next `git commit` will scoop in any pre-staged renames/deletes alongside what you intended. Before committing, either `git reset HEAD --` to clear the index then re-stage exact paths, or use `git diff --cached --name-status` (which shows ALL staged changes including renames + deletes + mode changes).

## What to read next

| If the task is… | Read |
|---|---|
| New to the system / orienting | `reference/architecture.md` |
| Need kubectl / argocd on a cluster | `reference/access-paths.md` |
| Anything secret-related (rotation, audit, debugging) | `reference/secret-flow.md` |
| Bumping an image to dev/staging | `runbooks/promote-image-to-spokes.md` |
| Catching dev/staging up to ryzen | `runbooks/reconcile-branches.md` |
| Image missing on ghcr.io | `runbooks/mirror-image-gitea-to-ghcr.md` |
| ArgoCD operationState stuck Running | `runbooks/recover-stuck-promotion.md` |
| db-migrate Job stuck Terminating | `runbooks/recover-stuck-job-finalizer.md` |
| Webhook not firing / hub Tekton path broken (NXDOMAIN or 202-no-PipelineRun) | `runbooks/debug-funnel-orphan-tag.md` |
| Migration shipped but columns missing on dev | `runbooks/fix-drizzle-migration.md` |
| Track a promotion in flight / what's gating it | `runbooks/track-promotion-state.md` |
| Spoke kubectl when Tailscale down | `runbooks/access-spoke-cluster-fallback.md` |
| Rotate a per-spoke OAuth client secret | `runbooks/rotate-oauth-secret.md` |

The runbooks each follow the same shape: **Symptoms** → **Diagnostic** → **Fix steps** → **Verify**.

## CLIs the agent should assume are available

| Tool | Typical use here |
|---|---|
| `kubectl` | Multi-context via `~/.kube/config`; for hub use `--kubeconfig ~/.kube/hub-config` (no SSH wrapper when on ryzen) |
| `argocd` | Login via Tailscale: `argocd login argocd-hub.tail286401.ts.net --grpc-web` (admin password in `argocd-initial-admin-secret`). Use for `terminate-op`, `app sync --force`, things kubectl-patch can't do |
| `gh` | GitHub API (webhook delivery history, OAuth app metadata, PR/run inspection); already authenticated as `vpittamp` |
| `az` | Azure KeyVault (`keyvault-thcmfmoo5oeow`); `az keyvault secret show/set --query attributes.updated -o tsv` is the bread-and-butter command |
| `skopeo` | Image mirroring between gitea-ryzen and ghcr.io. Use `--dest-authfile` with hub's `ghcr-push-credentials` secret. Run from **ryzen** (DNS) |
| `talosctl` | Hub: `--talosconfig ~/.talos/hub-config`; Talos cluster (Hetzner): `~/.talos/talos-config`. Spokes don't have ready-made talosconfig — use kubeconfig fallback |
| `hcloud` | Active context `stacks` (`hcloud context list`). `hcloud server list` for full Hetzner topology |
| `tailscale` | `status --json` for orphan-tag diagnosis; `serve status` / `funnel status` from inside operator pods |
| `git` | Three remotes commonly seen: `origin` (GitHub), `gitea` and `gitea-ryzen` (both point at the same Gitea on ryzen). Push to BOTH `origin` and `gitea-ryzen` after manual edits |

## Repo paths cheat-sheet

| Path | Role |
|---|---|
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` | dev/staging image pins (the file you edit most often) |
| `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` | The matrix ApplicationSet that consumes release-pins and patches each spoke's apps |
| `packages/components/active-development/manifests/<image>/kustomization.yaml` | Per-image kustomization with the gitea-ryzen registry tag (ryzen-only) |
| `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` | Direct image edit — no per-cluster override |
| `packages/components/hub-management/manifests/gitops-promoter/PromotionStrategy-workflow-builder-release.yaml` | env/spokes-dev → env/spokes-staging promotion config |
| `packages/components/hub-management/manifests/gitops-promoter/ArgoCDCommitStatus.yaml` | The `argocd-health` gate definition |
| `policy.hujson` | Tailscale ACL — `tagOwners`, `nodeAttrs` (funnel grants). Synced to tailnet by `.github/workflows/tailscale-acl.yml` on push to main |
| `docs/outer-loop-promotion.md` | Full reference (this skill is a curated subset). Has its own "Recovery Runbooks" section |

## Safety guards before you act

- **Never push to `origin/main` without also pushing to `gitea-ryzen/main`** (or vice versa) unless you are intentionally diverging.
- **Always shred extracted credentials.** When you `kubectl get secret … -o jsonpath='{...}' | base64 -d > /tmp/foo`, immediately `shred -u /tmp/foo` after. The Crossplane spoke kubeconfigs are admin certs.
- **Rotating a KeyVault secret** = wait for ESO + verify K8s Secret head + restart pod (in that order). Skipping the verify step bites every time.
- **Editing `release-pins/workflow-builder-images.yaml`** triggers an automatic rollout to dev and staging via the `workflow-builder-release` PromotionStrategy. The dev rollout fires first; if dev fails health gate, staging won't promote. There is no manual confirmation step in between.
