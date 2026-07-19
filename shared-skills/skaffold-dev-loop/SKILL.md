---
name: skaffold-dev-loop
description: "Manage the explicit Ryzen-only PittampalliOrg Skaffold loop for workflow-builder microservices. Use only when the user names Ryzen, skaffold dev, pnpm dev:skaffold, or pnpm deploy:skaffold: start or exit HMR, pause or resume Ryzen's local ArgoCD, diagnose GHCR or commit-pin failures, and separate this local lane from the active dev-cluster GitOps lane."
---

# Skaffold Dev Loop

> Scope guard: this is a specialized Ryzen loop, not the current shared dev
> deployment path. Do not invoke it for a generic workflow-builder deploy or
> test. Default those requests to the dev cluster GitHub -> hub Tekton ->
> Source Hydrator -> Promoter path described by the `gitops` skill.

## Operating model

Skaffold is the in-cluster dev loop for the workflow-builder microservices system on **ryzen** (the AUTONOMOUS argocd-agent spoke). Ryzen runs a **LOCAL ArgoCD** that reconciles its OWN apps (`root-ryzen` @ `main`); it has no local Gitea, no idpbuilder — it uses GitHub + GHCR. Inner-loop file-sync goes Skaffold → ryzen pod directly via kubeconfig; the wrapper pauses the LOCAL ryzen ArgoCD app's selfHeal (not a hub app). Outer-loop image push targets ghcr.io. (For INFRA/kustomize scratch iteration — re-render+re-apply rather than file-sync — see `deployment/scripts/ryzen-skaffold-dev.sh` in the stacks repo, covered by the `ryzen-spoke-bootstrap`/`gitops` skills.)

For `fn-system` (Knative), treat the Argo-managed pod as a stable dependency; `scripts/sandbox-dev.sh` is the experimental sandbox-based alternative.

There are two loops:

- **Inner loop** (`pnpm dev:skaffold`) — Skaffold builds a dev image, deploys it over the Ryzen Argo-managed workload, then file-syncs source into the running pod. Vite HMRs the browser; uvicorn `--reload` restarts Python. Ryzen's local ArgoCD is paused for the session through the wrapper's `trap`.
- **Outer loop** (`pnpm deploy:skaffold`) — Skaffold builds the prod multi-stage Dockerfile, pushes to `ghcr.io/pittampalliorg/<svc>:git-<sha>`, then a wrapper commit-pins the new tag on the `main` GitHub branch. For most Skaffold-owned services the wrapper edits the bare `stacks/main/.../workloads/<service>/manifests/kustomization.yaml` `newTag`. For **workflow-builder** + **workflow-mcp-server** the wrapper upserts the flat pins file `hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml` AND renders + commits the kustomize Component the workflow-builder manifests include — **locally, in the same push** (wfb PR #37); the stacks CI action is now only a drift-correction safety net (see the outer-loop section). Either way ryzen's LOCAL ArgoCD (`root-ryzen` tracks `main` directly) rolls the new image to ryzen on its next reconcile (no hub Source Hydrator, no Promoter on the ryzen lane). There is no inbound webhook path to ryzen because the autonomous agent has no argocd-server. The design uses commit-pin's spoke-local `refresh=hard`; it does not depend on principal relay behavior. A historical v0.8.1 relay observation is recorded below.

Skaffold does **not** replace the GitOps manifest path. For manifest changes destined for the active dev lane, commit to `main` on PittampalliOrg/stacks and follow Source Hydrator/Promoter into `env/spokes-dev`. Ryzen itself reconciles `overlays/ryzen` at `main` directly. See the `gitops` skill for dev delivery.

The Skaffold module set covers 5 of the 6 services in the system:

| Module | Type | Local→Container | Sync paths (dev) |
|---|---|---|---|
| `workflow-builder` | SvelteKit BFF (Node 22) | 3002 → 3000 | `src/**`, `lib/**`, `static/**`, `drizzle/**`, `scripts/**.{ts,js,mjs}`, `vite.config.ts`, … |
| `workflow-orchestrator` | Python/FastAPI Dapr workflow | 3013 → 8080 | `services/workflow-orchestrator/**/*.py`, `*.toml`, `*.yaml` |
| `function-router` | Node Express | 3014 → 8080 | `services/function-router/src/**`, `config/**`, `tsconfig.json` |
| `mcp-gateway` | Node Express | 3018 → 8080 | `services/mcp-gateway/src/**` |
| `swebench-coordinator` | Python/FastAPI | 3019 → 8080 | `services/swebench-coordinator/src/**.py`, `pyproject.toml` |

**`fn-system` is excluded** — it runs as a Knative Service (`ksvc fn-system`, scale-to-0). Inner-loop file-sync into a transient Knative pod is impractical. Treat the existing Argo-managed fn-system as a stable dependency.

**The ActivePieces piece-runtime is NOT a Skaffold module.** `fn-activepieces` was deleted; AP pieces now run on per-piece `ap-<piece>-service` Knative Services (one converged `piece-mcp-server` image parameterized by `PIECE_NAME`, serving `/execute` + `/mcp` + `/options` + `/health`), provisioned by the reconciler-owned `activepieces-mcps` app — not Skaffold-iterable. Deliver piece-runtime changes via an image rebuild + metadata re-sync (see the `gitops` skill), not the inner/outer Skaffold loops.

## When to use this skill

Trigger only when the request explicitly names Ryzen/Skaffold or one of these commands: `skaffold dev`, `pnpm dev:skaffold`, `pnpm deploy:skaffold`, `scripts/skaffold-dev.sh`, or `scripts/skaffold-deploy.sh`. Generic "deploy workflow-builder", "test on dev", "push a new image", or "iterate on workflow-builder" requests belong to the dev GitOps lane instead.

## Default workflow

### Inner loop

From `/home/vpittamp/repos/PittampalliOrg/workflow-builder/main` on ryzen (kubectl context `admin@ryzen`):

```bash
pnpm dev:skaffold                              # workflow-builder (default)
pnpm dev:skaffold:orchestrator                 # workflow-orchestrator
pnpm dev:skaffold:all                          # active modules (heavy)
bash scripts/skaffold-dev.sh function-router   # any single module
bash scripts/skaffold-dev.sh workflow-builder workflow-orchestrator  # subset
pnpm skaffold:doctor                           # read-only Skaffold preflight
```

The wrapper:
1. Pauses ryzen's LOCAL ArgoCD reconciliation for each named app (`argocd.argoproj.io/skip-reconcile=true` on the local `ryzen-<svc>` Application — ryzen reconciles its own apps; the annotation is NOT on a hub app)
2. Runs `skaffold dev -m <modules> --cleanup=false` — pushes dev images to ghcr.io (requires `docker login ghcr.io` with PAT having `write:packages`)
3. On Ctrl-C / EXIT / TERM: trap fires `skaffold/hooks/argo-resume.sh` to clear the skip-reconcile annotation and request a hard refresh on the local `ryzen-<svc>` app

The module set, the Skaffold-owned-services list, the per-module ports, and the **`module → ryzen-<svc>` Argo-app map** are centralized in `scripts/_modules.sh`, which all four wrapper scripts source.

Edits to a sync'd path (e.g. `src/**/*.svelte`) tar into the pod in ~1s; Vite HMRs the browser. Edits to `package.json` / `pnpm-lock.yaml` force a full image rebuild + pod restart (~30s).

`pnpm skaffold:doctor` is the preferred first command for LLM coding agents. It checks the kubectl context (`admin@ryzen`), required commands, the `ghcr.io/pittampalliorg` default-repo, the GitHub-`main` pin cache, active/inactive module state, the `ryzen-<svc>` Argo apps (skip-reconcile + sync + pin drift), and live Deployment image pins. (The old idpbuilder/`clhot` readiness checks were removed when those tools were retired.) Use `pnpm --silent skaffold:doctor -- --json` or `bash scripts/skaffold-doctor.sh --json` for machine-readable output.

### Outer loop (image build + pin)

```bash
pnpm deploy:skaffold                                # workflow-builder
pnpm deploy:skaffold:orchestrator                   # workflow-orchestrator
bash scripts/skaffold-deploy.sh function-router     # any single service
bash scripts/skaffold-deploy.sh workflow-builder workflow-orchestrator  # batch
```

`scripts/skaffold-deploy.sh`:
1. **No-pin-target guard**: rejects any service lacking `workloads/<svc>/manifests/kustomization.yaml` (e.g. `fn-system`) before building — they're pinned outside the Skaffold outer loop.
2. Runs `skaffold build -m <svc> --push --file-output build.json` (cache-aware) → `ghcr.io/pittampalliorg/<svc>:git-<sha>`
3. Parses `<repo>:<tag>@sha256:<digest>` from `build.json`
4. Invokes `skaffold/hooks/commit-pin.sh <svc>` unconditionally with that ref

`commit-pin.sh`:
- Maintains a dedicated cache clone at `~/.cache/skaffold/stacks-ryzen` tracking the configured `STACKS_REMOTE_URL` (GitHub `main` by default — ryzen reconciles `main` directly; the `inner-loop` branch + the old gitea-ryzen remote are RETIRED). A **stale-cache origin-reconcile** repoints a warm cache cloned from the old gitea remote to GitHub on first run.
- A **writer-precedence guard** (exit 66) refuses to push a pin for any service NOT in `SKAFFOLD_OWNED_DEFAULT` (the 5 Skaffold modules), so commit-pin stays the single GitHub-`main` writer for those services; the other ryzen workloads are pinned by the hub outer-loop. Override the owned set via `SKAFFOLD_OWNED_SERVICES="…"`.
- Each run: fetch + hard-reset to remote tip, then write the pin:
  - **Most Skaffold-owned services** (`workflow-orchestrator`, `function-router`, `mcp-gateway`): Python textual edit of the bare `workloads/<svc>/manifests/kustomization.yaml` `newName:`/`newTag:` lines (avoids the `kustomize edit` CLI), commit, push.
  - **`workflow-builder` + `workflow-mcp-server`**: UPSERTS the FLAT pins file `hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml` (`images`/`imageRefs`/`digests`/`sourceShas`) AND renders + commits the kustomize Component **locally in the same push** (running `WFB_RENDER_ENVS=ryzen scripts/gitops/render-workflow-builder-release-overlays.sh` in the fresh hard-reset cache clone — the render is deterministic, byte-identical to CI), then push. The stacks CI action re-renders on push but no-ops when this local render already matches; it is only a drift-correction safety net (wfb PR #37; see below).
  - GitHub auth resolves via the git credential helper / `gh` / `GITHUB_TOKEN` (no embedded credential).
- Annotates ryzen's LOCAL Application with `refresh=hard` so it polls immediately instead of waiting for the reconcile interval — it tries `ryzen-<svc>` first (ryzen's autonomous argocd-agent names apps `ryzen-<svc>`; a bare-name annotate no-ops).
- After push, ryzen's local ArgoCD (`root-ryzen` @ `main`) re-renders `overlays/ryzen` and applies the new image tag in SECONDS — for workflow-builder/workflow-mcp-server the Component is already rendered in the same push, so there is no ~1-2 min CI wait — no hub Source Hydrator, no `env/spokes-ryzen` (both retired for ryzen).
- **For workflow-builder + workflow-mcp-server only**: the bare `images:` block was DELETED from `workloads/workflow-builder/manifests/kustomization.yaml`; it now `components:`-includes a render-generated Component at `workloads/workflow-builder-ryzen-image/kustomization.yaml` carrying the workflow-builder + workflow-mcp-server pin (`newName`/`newTag`). commit-pin renders + commits that Component LOCALLY (via `scripts/gitops/render-workflow-builder-release-overlays.sh` with `WFB_RENDER_ENVS=ryzen`) in the same push as the flat pins file (wfb PR #37). The stacks CI action `.github/workflows/render-ryzen-image.yml` (UNCHANGED) re-renders on every push that touches the pins file and commits only on a diff (author `github-actions[bot]`) — so it NO-OPS when commit-pin's local render already matches; it is now purely a drift-correction safety net. ryzen's workflow-builder Application sources `manifests/` directly, so the Component IS ryzen's effective pin. (stacks #2443/#2447, wfb #33/#37.)
- Image-tag bumps committed straight to `main` are the same bumps dev/staging consume via their own outer-loop path; non-image manifest edits destined for dev/staging/hub still flow through the Promoter PRs (env/hub-next → env/hub, env/spokes-dev-next → env/spokes-dev).

Override the remote with `STACKS_REMOTE_URL=…` or branch with `STACKS_BRANCH=…` (default `main`).

### The two outer-loop lanes (DEV auto, RYZEN manual)

The outer loop has **two independent lanes** that write to **different pin files** and never touch each other:

1. **DEV lane = hub github-outer-loop (AUTO on merge, ALL Skaffold-owned services).** The hub Tekton EventListener `github-outer-loop` has **per-service triggers** (CEL filter: a commit touching `services/<svc>/**`, or commit message `[build all]`). When a merge to `main` touches `services/<svc>/`, that service's trigger fires the **parameterized** `outer-loop-build` Pipeline (service-agnostic) → builds the image → `ghcr.io/pittampalliorg/<svc>:git-<sha>` → the `update-stacks` task pins the SHARED pin file `hub-spoke-appsets/release-pins/workflow-builder-images.yaml` (ONE file holds EVERY service's dev pin) + renders the dev overlay (`workflow-builder-system-overlays/dev`) → Source Hydrator → GitOps Promoter → `env/spokes-dev` → `dev-<svc>` rolls. **VERIFIED end-to-end 2026-06-05 for workflow-builder, workflow-orchestrator, function-router, mcp-gateway, swebench-coordinator.** (The earlier "only workflow-builder auto-builds" belief was wrong — the live EventListener has always carried the per-service triggers; they had simply never been exercised because no non-wfb service had been pushed to `main` since the current EL pod started, so they looked dead.) workflow-builder's OWN trigger additionally fires on `src/`, `lib/`, `scripts/`, `static/`, `drizzle/`, `Dockerfile`, `package.json` changes. The DEV lane deliberately does NOT touch ryzen's pin file (`workflow-builder-images-ryzen.yaml`).

   **Push-retry backoff (stacks #2455):** the `update-stacks` task's `git push origin main` now retries with **backoff** — 6 attempts at 4/8/12/16/20s, with a `git rebase` between each. The OLD loop was 3 tries in ~1s with NO backoff, which could DROP a build's promotion on a transient GitHub 500 / push contention (e.g. a build racing a concurrent merge). Transient push failures now self-heal — "a transient GitHub 500 drops the promotion" is no longer true.

   **Bring a stale service current without a source change:** because a per-service trigger only fires on a `services/<svc>/` change, a service whose source hasn't moved stays frozen at its last successful build. To rebuild from current `main` HEAD, create a PipelineRun from the `outer-loop-build` Pipeline with params `git_url=https://github.com/PittampalliOrg/workflow-builder.git`, `git_sha=<current main HEAD>`, `image_name=<svc>`, `dockerfile=services/<svc>/Dockerfile`, `context=.` (Node: function-router/mcp-gateway) or `services/<svc>` (Python: workflow-orchestrator/swebench-coordinator), plus workspaces `shared-workspace` (emptyDir), `dockerconfig` (secret `ghcr-push-credentials`), `buildah-cache` (PVC `buildah-cache-<svc>`). The per-service `image_name`/`dockerfile`/`context` values come from the `outer-loop-<svc>` TriggerBinding. The build → `update-stacks` re-pins dev. (Used 2026-06-05 to bring mcp-gateway/swebench-coordinator/function-router current.)

2. **RYZEN lane = Skaffold `deploy:skaffold` commit-pin (MANUAL).** Documented above (outer-loop section) — commit-pin writes the ryzen pin: the locally rendered `workflow-builder-ryzen-image` Component for `workflow-builder`/`workflow-mcp-server`, or the bare-manifests `newTag` for the others. ryzen does NOT auto-update on a merge.

#### Deliver a just-merged GitHub PR to ryzen (do NOT rebuild)

After a PR merges to `main` and the DEV lane builds the image, **ryzen does not auto-update** (different lane) — deliver it explicitly by commit-pinning the EXISTING GHCR tag (no rebuild). For workflow-builder:

```bash
# DON'T `pnpm deploy:skaffold` a just-merged commit — for the SAME service the github-outer-loop
# already built the same git-<sha> tag with a DIFFERENT digest; a rebuild pushes a second digest
# and that service's release-pins digest then mismatches GHCR. Commit-pin the tag already in GHCR:
SKAFFOLD_IMAGE=ghcr.io/pittampalliorg/workflow-builder:git-<merged-sha> \
  bash skaffold/hooks/commit-pin.sh workflow-builder
```

`commit-pin.sh` upserts the flat `release-pins/workflow-builder-images-ryzen.yaml` pins file AND renders + commits the kustomize Component locally on `main` in the same push (wfb PR #37 — no CI wait), and ryzen's local ArgoCD reconciles it. The command hard-refreshes the local `ryzen-workflow-builder` app. On the **NixOS 403** push failure, push the cached pin (which already includes the locally rendered Component) manually then hard-refresh:

```bash
git -C ~/.cache/skaffold/stacks-ryzen push \
  "https://x-access-token:$(gh auth token)@github.com/PittampalliOrg/stacks.git" HEAD:main
kubectl --context admin@ryzen -n argocd annotate application ryzen-workflow-builder \
  argocd.argoproj.io/refresh=hard --overwrite
```

Verify ryzen flips: `kubectl --context admin@ryzen -n workflow-builder get deploy workflow-builder -o jsonpath='{.spec.template.spec.containers[0].image}'` shows `git-<sha>` and `ryzen-workflow-builder` is `Synced/Healthy`.

> **Architecture note (why it's still a manual commit-pin trigger):** ryzen is the autonomous fast-lane — no Promoter, its pin decoupled from dev/staging so it can run a different/newer/test revision. As of 2026-06-04 (stacks #2443/#2447, wfb #33/#37) the workflow-builder + workflow-mcp-server ryzen pin IS fully wired and automated *once you commit-pin*: commit-pin writes the flat `release-pins/workflow-builder-images-ryzen.yaml` AND renders + commits the `workflow-builder-ryzen-image` kustomize Component (which the workflow-builder manifests `components:`-include) LOCALLY in the same push, then `refresh=hard`es the ryzen spoke-local app — so ryzen reconciles `overlays/ryzen@main` in SECONDS (no CI wait, no 30s poll). The stacks CI action `render-ryzen-image.yml` re-renders on push but no-ops when the local render matches; it is now only a drift net. **Why local render, not a webhook:** there is NO inbound webhook path to ryzen — the autonomous argocd-agent has no argocd-server (so no `/api/webhook`). **Historical observation (v0.8.1, 2026-06-04):** the principal did not relay a hub-side `refresh` annotation to the autonomous agent, while the managed dev relay worked (~3s). Current v0.9.0 behavior must be verified independently; the design does not rely on it. The only manual step is firing commit-pin (the github-outer-loop deliberately doesn't touch ryzen's pin file). This supersedes the older "Phase 2c/2d not yet wired / ryzen still reads the bare manifests" note: Phase 2d is DONE.

## Why use the wrappers (don't use `skaffold dev` / `skaffold run` directly)

The wrappers fix several invariants that bare `skaffold` commands violate:

- **Bare `skaffold dev` skips ArgoCD pause/resume.** Argo's `selfHeal=true` would re-apply the prod image within seconds, fighting Skaffold's deployed dev pod.
- **Bare `skaffold dev` doesn't set `SKAFFOLD_DEFAULT_REPO`.** Skaffold then resolves bare artifact names (`workflow-builder-dev`) to `docker.io/library/workflow-builder-dev` → push denied on Docker Hub. (The outer-loop `run` profile has explicit `image: ghcr.io/pittampalliorg/<svc>` so it doesn't depend on `SKAFFOLD_DEFAULT_REPO`.)
- **Bare `skaffold dev` cleans up on exit by default.** `kubectl delete deployment workflow-builder` leaves a 30+ second window with no workflow-builder until Argo selfHeal recovers. The wrapper passes `--cleanup=false`.
- **`skaffold run -m <svc>` also redeploys the dev kustomize overlay.** Profile-level `manifests: rawYaml: []` + `deploy: kubectl: {}` doesn't override the base config's `manifests.kustomize.paths` in Skaffold v2. The outer-loop wrapper uses `skaffold build` and runs commit-pin separately.
- **`build.artifacts[].hooks.after` is skipped on cache hits.** A re-run with no source changes would silently skip the commit-pin step. The wrapper runs commit-pin unconditionally.

## ArgoCD pause / resume

If Skaffold is `kill -9`'d (or the wrapper's trap doesn't fire for any reason), Argo stays paused. **The exit hook can also silently skip ryzen's app even on a clean exit** — when the resume path receives the bare module name, the `ryzen-<svc>` Application lookup no-ops with no error. Diagnostic: the app still carries `argocd.argoproj.io/skip-reconcile=true` and the live Deployment is stuck on the `workflow-builder-dev` image long after the session ended. Recover **from the workflow-builder repo root** with the `ryzen-` prefixed app name:

```bash
ARGO_APPS=ryzen-workflow-builder bash skaffold/hooks/argo-resume.sh
```

Both `argo-pause.sh` and `argo-resume.sh` are idempotent and accept positional args:

```bash
bash skaffold/hooks/argo-pause.sh workflow-builder workflow-orchestrator function-router
bash skaffold/hooks/argo-resume.sh workflow-builder workflow-orchestrator function-router
```

After resume, Argo's hard-refresh annotation triggers reconcile within seconds. If the workflow-builder Deployment was deleted (e.g. because `--cleanup=false` was NOT used), Argo selfHeal recreates it; in the meantime, the live URL 503s.

## Dev overlay shape

Each module's dev overlay lives at `skaffold/dev/<service>/`:

```
skaffold/dev/<service>/
├── kustomization.yaml      # extends ../../../../../stacks/main/.../<service>/Deployment-<service>.yaml
├── deployment-dev-patch.yaml   # strategic-merge: image, NODE_ENV, securityContext (runAsUser:0)
└── Dockerfile.dev          # FROM node:22-alpine / python:3.12-slim + baked deps
```

Critical invariants:

- **The overlay extends only the Deployment file**, not the whole prod kustomization folder. The Application's per-cluster `patches` (ExternalSecret remoteRef rewrites) are NOT applied by Skaffold; deploying the full folder would clobber Argo's render.
- **No postgres image rewrite is needed.** The init container uses bare `docker.io/library/postgres:15.3-alpine3.18`, which ryzen pulls directly via the authenticated containerd `docker.io/hosts.toml` mirror + Spegel P2P. (The former `gitea.cnoe.localtest.me` mirror rewrite in the dev overlay was deleted with Gitea.)
- **The image swap lives in the strategic-merge patch, and MUST cover every container that uses the `workflow-builder` image — the main container AND the `db-migrate` init container.** Because the overlay extends only the raw `Deployment-workflow-builder.yaml` (not the prod kustomization), the prod `images:` rewrite never runs, so both containers carry the base placeholder `workflow-builder:latest`. The patch sets the Skaffold artifact alias `workflow-builder-dev` on each (Skaffold then rewrites it to the built tag). Any container left unpatched fails `ErrImagePull` on `workflow-builder:latest` and the whole deploy reports `1/1 deployment(s) failed` — this is a deploy-time failure, NOT a sync failure, so it shows up before "Watching for changes...". `db-migrate` runs `node scripts/db-migrate-runtime.mjs`, which the dev image bakes in (`COPY scripts` + `COPY drizzle` + `pnpm install`; the `.mjs` imports only `drizzle-orm`/`postgres` from node_modules, no build), so it runs correctly off the dev image. (Fixed in wfb PR #28; the old "a child `images:` block keyed on `name: workflow-builder` would no-op because the prod kustomization already rewrote it" rationale was wrong — the prod kustomization is NOT in this overlay's resources, so such an `images:` block would in fact rewrite both containers and is a valid alternative.)
- **`runAsUser: 0` + `runAsNonRoot: false`** so `pnpm install` / pip install can write under `/app` in the dev image. Triggers a benign PodSecurity `restricted:latest` warning at apply time.
- **`replicas: 1`** during dev — saves resources, and Skaffold's port-forward + sync target a single pod. The Application's `ignoreDifferences` on `/spec/replicas` already allows this.

Kustomize needs `--load-restrictor=LoadRestrictionsNone` to follow the `../../../../../stacks/main/...` reference; the module's `manifests.kustomize.buildArgs` passes this flag.

## Verification checklist

Before calling the inner loop done:
- `pnpm dev:skaffold` reaches "Watching for changes..." with a 2/2-Ready pod
- An edit to a sync'd path lands in the pod (visible via `kubectl exec … -- cat /app/path`) and triggers vite/uvicorn reload in the log
- Ctrl-C resumes the ArgoCD app (verify `metadata.annotations` has no `skip-reconcile`)
- Argo reconciles the Deployment back to the prod image within ~30s

Before calling the outer loop done:
- `pnpm deploy:skaffold` finishes with `==> ✓ done`
- The commit appears on the configured remote/branch (`git -C ~/.cache/skaffold/stacks-ryzen log -1`) — default: GitHub `main` branch
- The LOCAL `ryzen-<svc>` Application on ryzen's ArgoCD shows `sync=Synced health=Healthy` and the live Deployment on ryzen has the new image tag
- Image-tag bumps land on `main` directly; dev/staging consume the same image via their own release-pin / Promoter outer-loop path (see the `gitops` skill)

## Gotchas (memorize these — they cost the most time)

- **Stacks repo: dedicated cache clone for commit-pin.** `commit-pin.sh` avoids touching the developer's primary `stacks/main` checkout; it uses a dedicated cache clone at `~/.cache/skaffold/stacks-ryzen` tracking the configured remote (GitHub `main` branch — `inner-loop` is retired). The cache is force-reset to the remote tip each run, so any local cruft is discarded.
- **`stacks/main` is a git worktree.** `.git` is a file (containing `gitdir: ...`), not a directory. Don't use `[ -d "$stacks_dir/.git" ]` to check repo presence; use `git rev-parse --git-dir`.
- **A killed `skaffold dev` can silently skip the ryzen Argo resume AND leave stale git `index.lock`s.** Two distinct residues after a non-clean exit (and the resume skip has been seen even on apparently clean exits): (1) the `ryzen-<svc>` app stays paused — symptom is the `argocd.argoproj.io/skip-reconcile=true` annotation plus a Deployment stuck on the `workflow-builder-dev` image; fix with `ARGO_APPS=ryzen-workflow-builder bash skaffold/hooks/argo-resume.sh` run from the wfb repo root (see *ArgoCD pause / resume*). (2) a stale `index.lock` under the worktree git dir — `.bare/worktrees/main/index.lock` in the workflow-builder repo AND in the stacks cached clone — which makes every subsequent git operation fail `Unable to create ... index.lock: File exists`. Verify no git process is still running (`pgrep -fa git`), then remove the lock file.
- **Skaffold v2.17's tar walker mis-parses allowlist-style `.dockerignore`.** With `inputDigest` tag policy it errors "file pattern [package.json] must match at least one file" before docker even sees the context. Use `gitCommit:AbbrevCommitSha` tag policy for dev images instead.
- **`context: .` in a module yaml resolves to the module file's directory** (`skaffold/`), not the repo root. Use `context: ..` and adjust `dockerfile:` accordingly so build context = `workflow-builder/main/`.
- **PodSecurity warning at apply time is expected.** The dev container runs as root for hot-reload; the namespace's `restricted:latest` profile warns but doesn't block. Don't try to "fix" by going non-root.
- **fn-system is Knative-only.** It doesn't appear in the cluster as `deploy/fn-system` (only `deploy/fn-system-00001-deployment` scaled 0/0). Skaffold-style sync doesn't work for transient Knative pods. Treat fn-system as a stable cluster dependency.
- **Skaffold artifact hooks skip on cache hits.** A re-run of `skaffold build` against unchanged source skips `hooks.after`. That's why the outer-loop wrapper runs commit-pin out-of-band.
- **`commit-pin` push can 403 on this NixOS host (image + pin are still fine).** `pnpm deploy:skaffold` builds + pushes the image to GHCR and makes the pin commit in `~/.cache/skaffold/stacks-ryzen`, but the final `git push origin main` to stacks pushes over HTTPS with no configured credential helper → falls back to denied browser-OAuth → `Permission to PittampalliOrg/stacks.git denied to vpittamp` / `ELIFECYCLE exit 128`. `vpittamp` *does* have push and `gh`'s token has `repo` scope. Recover without rebuilding: fetch + (cherry-pick onto the new tip if the remote moved) + `git -C ~/.cache/skaffold/stacks-ryzen push "https://x-access-token:$(gh auth token)@github.com/PittampalliOrg/stacks.git" HEAD:main`, then hard-refresh `ryzen-<svc>`. `gh auth setup-git` can't fix it (global git config is a read-only NixOS symlink) — the durable fix is wiring `gh auth git-credential` as the github.com HTTPS helper in nixos-config.
- **Don't `deploy:skaffold` a commit the GitHub DEV lane also builds (i.e. right after merging a PR touching `services/<svc>/` to `main`).** This applies PER SERVICE: when a merge fires `<svc>`'s github-outer-loop trigger, both lanes build the same `git-<sha>` tag for that service but produce DIFFERENT digests; whoever pushes last wins the tag, and the GitHub build's digest recorded in `release-pins/` then mismatches GHCR → `validate-workflow-builder-release-pins.sh` fails `digest mismatch`. Dev still pulls by tag (functionally fine), but provenance/CI breaks until the next GitHub build re-pins. To deliver a just-merged commit to ryzen, DON'T rebuild — commit-pin the EXISTING GHCR tag (the two lanes write different files: GitHub DEV lane → shared `release-pins/workflow-builder-images.yaml` + dev overlays; Skaffold RYZEN commit-pin → for `workflow-builder`/`workflow-mcp-server`, the ryzen pin file `release-pins/workflow-builder-images-ryzen.yaml` PLUS the locally rendered `workflow-builder-ryzen-image` Component; for the other Skaffold-owned services, the ryzen base `workloads/<svc>/manifests/kustomization.yaml`).
- **A local `workflow-orchestrator/.venv` bloats the build context.** The dev `.dockerignore` now excludes `**/.venv`, `**/__pycache__`, `**/.pytest_cache`. If you see a multi-hundred-MB build context, suspect a missed exclude.
- **pnpm v10 fails a Node service's prod build (`ERR_PNPM_IGNORED_BUILDS`); pin `pnpm@9`.** A Node service whose Dockerfile installs pnpm with an unpinned `npm install -g pnpm` gets pnpm v10, which fails `RUN pnpm build` with `ERR_PNPM_IGNORED_BUILDS` — esbuild/protobufjs build scripts are blocked behind a v10 approval gate. Fix: **pin `pnpm@9`** (like mcp-gateway already does); do NOT reach for `--ignore-scripts` (that leaves esbuild's binary missing for the build stage). KEY INSIGHT: such a prod-build break can HIDE indefinitely — the DEV-lane per-service trigger only fires on a `services/<svc>/` change, so the image just stays frozen at the last successful build (function-router was stuck at a May-21 image for exactly this reason; fixed in wfb PR #42). Surface it with the "bring a stale service current" PipelineRun above.
- **The dev image is push-required even on a local cluster.** Talos Docker worker nodes have their own containerd image store; `kind load`-style preload isn't wired into our Skaffold flow. The dev image push target is a developer-controlled GHCR namespace (`SKAFFOLD_DEFAULT_REPO`, default `ghcr.io/pittampalliorg`). The `run` profile (outer loop) explicitly pushes to `ghcr.io/pittampalliorg/<svc>` so ryzen pulls from the same registry as dev/staging. (There is no local Gitea registry on ryzen — that path is retired.)
- **ryzen ArgoCD apps are named `ryzen-<module>`, NOT `<module>`.** ryzen's autonomous `root-ryzen` app-of-apps prefixes child Applications with `ryzen-` (in the `argocd` ns), while the workload Deployment keeps the bare `<module>` name (in the `workflow-builder` ns). Any tooling that addresses the Argo app by the bare name silently no-ops — `argo-pause.sh`/`argo-resume.sh` skip apps not found, so a bare-name session would run WITHOUT pausing Argo and Argo would fight the dev pod. The wrappers map `module → ryzen-<module>` via `_modules.sh` (`MODULE_TO_APP`); list them with `kubectl --context admin@ryzen -n argocd get applications | grep ryzen-`.
- **Most workloads image pins use bare `name: <svc>` match-keys in the base manifests** — EXCEPT `workflow-builder` + `workflow-mcp-server`. For `workflow-orchestrator`/`function-router`/`mcp-gateway`, the base `workloads/<svc>/manifests/kustomization.yaml` matches `name: <svc>` → `newName: ghcr.io/pittampalliorg/<svc>` + `newTag: git-<sha>`, with the Deployment carrying `image: <svc>:latest`; these were flipped to the bare form from the retired `gitea-ryzen.tail286401.ts.net/giteaadmin/<svc>` long-form in stacks PR #2435 (image-neutral — resolved image byte-identical). `commit-pin.sh` matches `name == <svc>` OR `name endswith /<svc>`, so it still handles any residual long-form name; `skaffold-status`/`doctor` no longer report `NAME-MISMATCH` for these services (`pinName` is the bare `<svc>`). **`workflow-builder` + `workflow-mcp-server` no longer carry a bare `images:` block** — that was deleted from `workloads/workflow-builder/manifests/kustomization.yaml`, which now `components:`-includes the render-generated `workflow-builder-ryzen-image` Component; their ryzen pin lives in the flat `release-pins/workflow-builder-images-ryzen.yaml` file, rendered into that Component by commit-pin LOCALLY in the same push (stacks CI re-renders only as a drift net) (stacks #2443/#2447, wfb #33/#37).
- **Ryzen's workflow-builder image is now SINGLE-authority (the Component) — the Application-level override that silently defeated it was REMOVED (2026-06-05).** The `root-ryzen` app-of-apps (`packages/overlays/ryzen/kustomization.yaml`) USED TO patch the `ryzen-workflow-builder` Application's OWN `spec.source.kustomize.images` to a hardcoded `git-<sha>`. ArgoCD applies `spec.source.kustomize.images` **on top of** the rendered kustomization, so that override WON over the render-generated `workflow-builder-ryzen-image` Component commit-pin maintains: commit-pin updated the Component + flat pins, the app showed `Synced`, but the live Deployment stayed **FROZEN on the stale override sha** — and **restarting `argocd-repo-server` did NOT help** (it is override-precedence, not a cache). **Telltale:** `kubectl --context admin@ryzen -n argocd get application ryzen-workflow-builder -o jsonpath='{.spec.source.kustomize.images}'` shows an OLD sha while a LOCAL `kubectl kustomize packages/components/workloads/workflow-builder/manifests` (at the pinned revision) renders the NEW image. The override was REMOVED in stacks (the app keeps only its non-image `patches:` — Ingress-delete / Deployment-resources / Namespace-label); ArgoCD docs call Application-object image overrides a GitOps anti-pattern. A CI guard **`validate-ryzen-no-app-image-overrides`** (`.github/workflows/validate-ryzen-no-app-image-overrides.yml` + `scripts/gitops/validate-ryzen-no-app-image-overrides.sh`) now builds the ryzen overlay and FAILS if any Application reintroduces `spec.source.kustomize.images`. **Net: `deploy:skaffold`/commit-pin now rolls ryzen via the Component ALONE — no overlay edit, no repo-server restart** (verified end-to-end 2026-06-05: one merged SHA reached dev via the Promoter lane and ryzen via commit-pin, no manual overlay touch).

## Related skills

- [`workflow-builder`](../workflow-builder/SKILL.md) — authoring SW 1.0 workflows + diagnosing runtime failures in the same system. The Skaffold loop deploys the BFF; the workflow-builder skill covers how to author/debug what the BFF executes.
- [`gitops`](../gitops/SKILL.md) — broader ArgoCD reconcile flow + ryzen affected-app sync. The outer-loop wrapper commits to the same kustomization files that the GitOps skill manages; bigger image promotions (release-pins, dev/staging) go through the GitOps path, not Skaffold.

Concrete commands + recovery examples in [`references/workflow-builder.md`](references/workflow-builder.md).
