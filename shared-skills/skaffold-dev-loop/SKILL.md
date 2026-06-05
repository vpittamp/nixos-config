---
name: skaffold-dev-loop
description: Manage PittampalliOrg Skaffold dev loops for the workflow-builder microservices system on ryzen. Use for starting/exiting `skaffold dev` inner-loop HMR sessions, troubleshooting Argo pause/resume (the LOCAL ryzen ArgoCD selfHeal, since ryzen reconciles its own apps), SKAFFOLD_DEFAULT_REPO/ghcr.io registry issues, dev kustomize overlay drift, outer-loop commit-pin to main, Knative fn-system exclusion, and choosing between Skaffold, hub Promoter PR merge, and GitHub/GHCR image delivery.
---

# Skaffold Dev Loop

## Operating model

Skaffold is the in-cluster dev loop for the workflow-builder microservices system on **ryzen** (the AUTONOMOUS argocd-agent spoke). Ryzen runs a **LOCAL ArgoCD** that reconciles its OWN apps (`root-ryzen` @ `main`); it has no local Gitea, no idpbuilder — it uses GitHub + GHCR. Inner-loop file-sync goes Skaffold → ryzen pod directly via kubeconfig; the wrapper pauses the LOCAL ryzen ArgoCD app's selfHeal (not a hub app). Outer-loop image push targets ghcr.io. (For INFRA/kustomize scratch iteration — re-render+re-apply rather than file-sync — see `deployment/scripts/ryzen-skaffold-dev.sh` in the stacks repo, covered by the `ryzen-spoke-bootstrap`/`gitops` skills.)

For `fn-system` (Knative), treat the hub-Argo-managed pod as a stable dependency; `scripts/sandbox-dev.sh` is the experimental sandbox-based alternative.

There are two loops:

- **Inner loop** (`pnpm dev:skaffold`) — Skaffold builds a dev image (`node:22-alpine` or `python:3.12-slim` + baked deps), deploys it as the workflow-builder Deployment (overwriting hub-Argo's prod pod), then file-syncs `src/`/`lib/`/etc. into the running pod on every save. Vite HMRs the browser; uvicorn `--reload` restarts the Python service. Hub-Argo is paused for the session via the wrapper's `trap`.
- **Outer loop** (`pnpm deploy:skaffold`) — Skaffold builds the prod multi-stage Dockerfile, pushes to `ghcr.io/pittampalliorg/<svc>:git-<sha>`, then a wrapper commit-pins the new tag on the `main` GitHub branch. For most Skaffold-owned services the wrapper edits the bare `stacks/main/.../workloads/<service>/manifests/kustomization.yaml` `newTag`. For **workflow-builder** + **workflow-mcp-server** the wrapper upserts the flat pins file `hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml` AND renders + commits the kustomize Component the workflow-builder manifests include — **locally, in the same push** (wfb PR #37); the stacks CI action is now only a drift-correction safety net (see the outer-loop section). Either way ryzen's LOCAL ArgoCD (`root-ryzen` tracks `main` directly) rolls the new image to ryzen on its next reconcile (no hub Source Hydrator, no Promoter on the ryzen lane). There is no inbound webhook path to ryzen (autonomous argocd-agent has no argocd-server; the principal does not relay refresh to autonomous agents on v0.8.1), so commit-pin's own spoke-local `refresh=hard` is the only fast path.

Skaffold does **not** replace the GitOps manifest path. For non-image manifest changes destined for dev/staging/hub (ConfigMaps, env vars, resource limits), commit to `main` on PittampalliOrg/stacks, then **merge the GitOps Promoter PR** (`env/hub-next → env/hub` or `env/spokes-dev-next → env/spokes-dev`) so those clusters pick up the change. Ryzen itself reconciles `overlays/ryzen` @ `main` directly (no Promoter PR needed for ryzen). See the `gitops` skill for the full promotion flow.

The Skaffold module set covers 6 of the 7 services in the system:

| Module | Type | Local→Container | Sync paths (dev) |
|---|---|---|---|
| `workflow-builder` | SvelteKit BFF (Node 22) | 3002 → 3000 | `src/**`, `lib/**`, `static/**`, `drizzle/**`, `scripts/**.{ts,js,mjs}`, `vite.config.ts`, … |
| `workflow-orchestrator` | Python/FastAPI Dapr workflow | 3013 → 8080 | `services/workflow-orchestrator/**/*.py`, `*.toml`, `*.yaml` |
| `function-router` | Node Express | 3014 → 8080 | `services/function-router/src/**`, `config/**`, `tsconfig.json` |
| `fn-activepieces` | Node Express | 3016 → 8080 | `services/fn-activepieces/src/**` (inactive on current ryzen by default) |
| `mcp-gateway` | Node Express | 3018 → 8080 | `services/mcp-gateway/src/**` |
| `swebench-coordinator` | Python/FastAPI | 3019 → 8080 | `services/swebench-coordinator/src/**.py`, `pyproject.toml` |

**`fn-system` is excluded** — it runs as a Knative Service (`ksvc fn-system`, scale-to-0). Inner-loop file-sync into a transient Knative pod is impractical. Treat the existing Argo-managed fn-system as a stable dependency.

**`fn-activepieces` is inactive by default** — the Skaffold config remains in tree for recovery/parity work, but the current ryzen cluster may not expose a matching regular Argo Application/Deployment. Default `ALL` runs skip it. Use `SKAFFOLD_ALLOW_INACTIVE=1 bash scripts/skaffold-dev.sh fn-activepieces` only when deliberately restoring or testing that path.

## When to use this skill

Trigger on any of: "start the dev loop", "skaffold dev", "deploy to ryzen", "push a new image", "iterate on workflow-builder", "iterate on workflow-orchestrator", "hot reload my svelte/py changes", "argo got paused", "argo won't resume", "dev image won't push", "kind nodes can't pull", "commit-pin failed", "stacks repo divergence on ryzen", `pnpm dev:skaffold`, `pnpm deploy:skaffold`, or any reference to the wrapper scripts at `scripts/skaffold-dev.sh` and `scripts/skaffold-deploy.sh`.

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
bash scripts/skaffold-deploy.sh fn-activepieces     # any single service
bash scripts/skaffold-deploy.sh workflow-builder workflow-orchestrator  # batch
```

`scripts/skaffold-deploy.sh`:
1. **No-pin-target guard**: rejects any service lacking `workloads/<svc>/manifests/kustomization.yaml` (e.g. `fn-system`, `fn-activepieces`) before building — they're pinned outside the Skaffold outer loop.
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

### Deliver a just-merged GitHub PR to ryzen (do NOT rebuild)

After a workflow-builder PR merges to `main`, the **hub github-outer-loop** (Tekton EventListener `github-outer-loop`) builds `ghcr.io/pittampalliorg/workflow-builder:git-<sha>` and writes it to the **dev/staging** pin file (`hub-spoke-appsets/release-pins/workflow-builder-images.yaml`) — so **dev auto-promotes** via the Source Hydrator + GitOps Promoter (the dev app applies it as a `kustomize.images` override). It does **not** touch ryzen's pin file (`workflow-builder-images-ryzen.yaml`). So **ryzen does not auto-update on a merge** — deliver it explicitly by commit-pinning the EXISTING GHCR tag (no rebuild):

```bash
# DON'T `pnpm deploy:skaffold` a just-merged commit — the github-outer-loop already built
# the same git-<sha> tag with a DIFFERENT digest; a rebuild pushes a second digest and the
# release-pins digest then mismatches GHCR. Commit-pin the tag that already exists in GHCR:
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

> **Architecture note (why it's still a manual commit-pin trigger):** ryzen is the autonomous fast-lane — no Promoter, its pin decoupled from dev/staging so it can run a different/newer/test revision. As of 2026-06-04 (stacks #2443/#2447, wfb #33/#37) the workflow-builder + workflow-mcp-server ryzen pin IS fully wired and automated *once you commit-pin*: commit-pin writes the flat `release-pins/workflow-builder-images-ryzen.yaml` AND renders + commits the `workflow-builder-ryzen-image` kustomize Component (which the workflow-builder manifests `components:`-include) LOCALLY in the same push, then `refresh=hard`es the ryzen spoke-local app — so ryzen reconciles `overlays/ryzen@main` in SECONDS (no CI wait, no 30s poll). The stacks CI action `render-ryzen-image.yml` re-renders on push but no-ops when the local render matches; it is now only a drift net. **Why local render, not a webhook:** there is NO inbound webhook path to ryzen — the autonomous argocd-agent has no argocd-server (so no `/api/webhook`), and the argocd-agent principal does NOT relay a hub-side `refresh` annotation to autonomous agents on v0.8.1 (verified empirically; a hub-side annotation on the ryzen mirror never reached the spoke). The managed agent (dev) relay DOES work (~3s). The only manual step is firing commit-pin (the github-outer-loop deliberately doesn't touch ryzen's pin file). This supersedes the older "Phase 2c/2d not yet wired / ryzen still reads the bare manifests" note: Phase 2d is DONE.

## Why use the wrappers (don't use `skaffold dev` / `skaffold run` directly)

The wrappers fix several invariants that bare `skaffold` commands violate:

- **Bare `skaffold dev` skips ArgoCD pause/resume.** Argo's `selfHeal=true` would re-apply the prod image within seconds, fighting Skaffold's deployed dev pod.
- **Bare `skaffold dev` doesn't set `SKAFFOLD_DEFAULT_REPO`.** Skaffold then resolves bare artifact names (`workflow-builder-dev`) to `docker.io/library/workflow-builder-dev` → push denied on Docker Hub. (The outer-loop `run` profile has explicit `image: ghcr.io/pittampalliorg/<svc>` so it doesn't depend on `SKAFFOLD_DEFAULT_REPO`.)
- **Bare `skaffold dev` cleans up on exit by default.** `kubectl delete deployment workflow-builder` leaves a 30+ second window with no workflow-builder until Argo selfHeal recovers. The wrapper passes `--cleanup=false`.
- **`skaffold run -m <svc>` also redeploys the dev kustomize overlay.** Profile-level `manifests: rawYaml: []` + `deploy: kubectl: {}` doesn't override the base config's `manifests.kustomize.paths` in Skaffold v2. The outer-loop wrapper uses `skaffold build` and runs commit-pin separately.
- **`build.artifacts[].hooks.after` is skipped on cache hits.** A re-run with no source changes would silently skip the commit-pin step. The wrapper runs commit-pin unconditionally.

## ArgoCD pause / resume

If Skaffold is `kill -9`'d (or the wrapper's trap doesn't fire for any reason), Argo stays paused. Recover with:

```bash
ARGO_APPS="workflow-builder" bash skaffold/hooks/argo-resume.sh
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
- **Skaffold v2.17's tar walker mis-parses allowlist-style `.dockerignore`.** With `inputDigest` tag policy it errors "file pattern [package.json] must match at least one file" before docker even sees the context. Use `gitCommit:AbbrevCommitSha` tag policy for dev images instead.
- **`context: .` in a module yaml resolves to the module file's directory** (`skaffold/`), not the repo root. Use `context: ..` and adjust `dockerfile:` accordingly so build context = `workflow-builder/main/`.
- **PodSecurity warning at apply time is expected.** The dev container runs as root for hot-reload; the namespace's `restricted:latest` profile warns but doesn't block. Don't try to "fix" by going non-root.
- **fn-system is Knative-only.** It doesn't appear in the cluster as `deploy/fn-system` (only `deploy/fn-system-00001-deployment` scaled 0/0). Skaffold-style sync doesn't work for transient Knative pods. Treat fn-system as a stable cluster dependency.
- **Skaffold artifact hooks skip on cache hits.** A re-run of `skaffold build` against unchanged source skips `hooks.after`. That's why the outer-loop wrapper runs commit-pin out-of-band.
- **`commit-pin` push can 403 on this NixOS host (image + pin are still fine).** `pnpm deploy:skaffold` builds + pushes the image to GHCR and makes the pin commit in `~/.cache/skaffold/stacks-ryzen`, but the final `git push origin main` to stacks pushes over HTTPS with no configured credential helper → falls back to denied browser-OAuth → `Permission to PittampalliOrg/stacks.git denied to vpittamp` / `ELIFECYCLE exit 128`. `vpittamp` *does* have push and `gh`'s token has `repo` scope. Recover without rebuilding: fetch + (cherry-pick onto the new tip if the remote moved) + `git -C ~/.cache/skaffold/stacks-ryzen push "https://x-access-token:$(gh auth token)@github.com/PittampalliOrg/stacks.git" HEAD:main`, then hard-refresh `ryzen-<svc>`. `gh auth setup-git` can't fix it (global git config is a read-only NixOS symlink) — the durable fix is wiring `gh auth git-credential` as the github.com HTTPS helper in nixos-config.
- **Don't `deploy:skaffold` a commit the GitHub outer-loop also builds (i.e. right after merging a wfb PR to `main`).** Both build the same `git-<sha>` tag but produce DIFFERENT digests; whoever pushes last wins the tag, and the GitHub build's digest recorded in `release-pins/` then mismatches GHCR → `validate-workflow-builder-release-pins.sh` fails `digest mismatch`. Dev still pulls by tag (functionally fine), but provenance/CI breaks until the next GitHub build re-pins. To deliver a just-merged commit to ryzen, DON'T rebuild — commit-pin the EXISTING GHCR tag (the two outer-loops write different files: GitHub → release-pins `workflow-builder-images.yaml` + dev/staging overlays; Skaffold commit-pin → for `workflow-builder`/`workflow-mcp-server`, the ryzen pin file `release-pins/workflow-builder-images-ryzen.yaml` PLUS the locally rendered `workflow-builder-ryzen-image` Component; for the other Skaffold-owned services, the ryzen base `workloads/<svc>/manifests/kustomization.yaml`).
- **A local `workflow-orchestrator/.venv` bloats the build context.** The dev `.dockerignore` now excludes `**/.venv`, `**/__pycache__`, `**/.pytest_cache`. If you see a multi-hundred-MB build context, suspect a missed exclude.
- **The dev image is push-required even on a local cluster.** Talos Docker worker nodes have their own containerd image store; `kind load`-style preload isn't wired into our Skaffold flow. The dev image push target is a developer-controlled GHCR namespace (`SKAFFOLD_DEFAULT_REPO`, default `ghcr.io/pittampalliorg`). The `run` profile (outer loop) explicitly pushes to `ghcr.io/pittampalliorg/<svc>` so ryzen pulls from the same registry as dev/staging. (There is no local Gitea registry on ryzen — that path is retired.)
- **ryzen ArgoCD apps are named `ryzen-<module>`, NOT `<module>`.** ryzen's autonomous `root-ryzen` app-of-apps prefixes child Applications with `ryzen-` (in the `argocd` ns), while the workload Deployment keeps the bare `<module>` name (in the `workflow-builder` ns). Any tooling that addresses the Argo app by the bare name silently no-ops — `argo-pause.sh`/`argo-resume.sh` skip apps not found, so a bare-name session would run WITHOUT pausing Argo and Argo would fight the dev pod. The wrappers map `module → ryzen-<module>` via `_modules.sh` (`MODULE_TO_APP`); list them with `kubectl --context admin@ryzen -n argocd get applications | grep ryzen-`.
- **Most workloads image pins use bare `name: <svc>` match-keys in the base manifests** — EXCEPT `workflow-builder` + `workflow-mcp-server`. For `workflow-orchestrator`/`function-router`/`mcp-gateway`, the base `workloads/<svc>/manifests/kustomization.yaml` matches `name: <svc>` → `newName: ghcr.io/pittampalliorg/<svc>` + `newTag: git-<sha>`, with the Deployment carrying `image: <svc>:latest`; these were flipped to the bare form from the retired `gitea-ryzen.tail286401.ts.net/giteaadmin/<svc>` long-form in stacks PR #2435 (image-neutral — resolved image byte-identical). `commit-pin.sh` matches `name == <svc>` OR `name endswith /<svc>`, so it still handles any residual long-form name; `skaffold-status`/`doctor` no longer report `NAME-MISMATCH` for these services (`pinName` is the bare `<svc>`). **`workflow-builder` + `workflow-mcp-server` no longer carry a bare `images:` block** — that was deleted from `workloads/workflow-builder/manifests/kustomization.yaml`, which now `components:`-includes the render-generated `workflow-builder-ryzen-image` Component; their ryzen pin lives in the flat `release-pins/workflow-builder-images-ryzen.yaml` file, rendered into that Component by commit-pin LOCALLY in the same push (stacks CI re-renders only as a drift net) (stacks #2443/#2447, wfb #33/#37).

## Related skills

- [`workflow-builder`](../workflow-builder/SKILL.md) — authoring SW 1.0 workflows + diagnosing runtime failures in the same system. The Skaffold loop deploys the BFF; the workflow-builder skill covers how to author/debug what the BFF executes.
- [`gitops`](../gitops/SKILL.md) — broader ArgoCD reconcile flow + ryzen affected-app sync. The outer-loop wrapper commits to the same kustomization files that the GitOps skill manages; bigger image promotions (release-pins, dev/staging) go through the GitOps path, not Skaffold.

Concrete commands + recovery examples in [`references/workflow-builder.md`](references/workflow-builder.md).
