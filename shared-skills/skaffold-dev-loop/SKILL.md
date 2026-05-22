---
name: skaffold-dev-loop
description: Manage PittampalliOrg Skaffold dev loops for the workflow-builder microservices system on ryzen. Use for starting/exiting `skaffold dev` inner-loop HMR sessions, troubleshooting Argo pause/resume, SKAFFOLD_DEFAULT_REPO/gitea-ryzen registry issues, dev kustomize overlay drift, legacy ryzen-only commit-pin/image experiments, Knative fn-system exclusion, and choosing between Skaffold, idpbuilder stacks sync, GitHub/GHCR image delivery, and the legacy devspace.yaml fallback.
---

# Skaffold Dev Loop

## Operating model

Skaffold is the in-cluster dev loop for the workflow-builder microservices system. It replaces devspace as the going-forward path; devspace.yaml stays in-tree as a fallback for `fn-system` (Knative) and any service not yet migrated. See the [`devspace-quick-iteration`](../devspace-quick-iteration/SKILL.md) skill for the legacy flow.

There are two loops:

- **Inner loop** (`pnpm dev:skaffold`) — Skaffold builds a dev image (`node:22-alpine` or `python:3.12-slim` + baked deps), deploys it as the workflow-builder Deployment (overwriting Argo's prod pod), then file-syncs `src/`/`lib/`/etc. into the running pod on every save. Vite HMRs the browser; uvicorn `--reload` restarts the Python service. Argo is paused for the session via the wrapper's `trap`.
- **Legacy ryzen-only image loop** (`pnpm deploy:skaffold`) — Skaffold builds the prod multi-stage Dockerfile, pushes to gitea-ryzen, then a wrapper commits the new tag into `stacks/main/.../active-development/manifests/<service>/kustomization.yaml` on gitea-ryzen, and ArgoCD's `automated.selfHeal=true` rolls it out. Use this only for narrow ryzen-only recovery/testing. The durable system path is the GitHub/GHCR build lane plus an `origin/main` active-development pin and `idpbuilder stacks sync --seed-images=false`.

Skaffold does **not** replace the ryzen idpbuilder manifest path. `idpbuilder stacks sync --seed-images=false` snapshots the selected local stacks worktree into in-cluster Gitea, computes affected ArgoCD Applications, hard-refreshes them, and waits for them to observe the pushed revision. Use idpbuilder/`clu` for manifest changes and durable ryzen pins, Skaffold inner loop for live source hot reload, Skaffold deploy only for narrow ryzen-only image-pin experiments, and release-pins/GitOps Promoter for dev/staging.

The Skaffold module set covers 6 of the 7 services in the system:

| Module | Type | Local→Container | Sync paths (dev) |
|---|---|---|---|
| `workflow-builder` | SvelteKit BFF (Node 22) | 3002 → 3000 | `src/**`, `lib/**`, `static/**`, `drizzle/**`, `scripts/**.{ts,js,mjs}`, `vite.config.ts`, … |
| `workflow-orchestrator` | Python/FastAPI Dapr workflow | 3013 → 8080 | `services/workflow-orchestrator/**/*.py`, `*.toml`, `*.yaml` |
| `function-router` | Node Express | 3014 → 8080 | `services/function-router/src/**`, `config/**`, `tsconfig.json` |
| `fn-activepieces` | Node Express | 3016 → 8080 | `services/fn-activepieces/src/**` (inactive on current ryzen by default) |
| `mcp-gateway` | Node Express | 3018 → 8080 | `services/mcp-gateway/src/**` |
| `swebench-coordinator` | Python/FastAPI | 3019 → 8080 | `services/swebench-coordinator/src/**.py`, `pyproject.toml` |

**`fn-system` is excluded** — it runs as a Knative Service (`ksvc fn-system`, scale-to-0). Inner-loop file-sync into a transient Knative pod is impractical. Fall back to `devspace-quick-iteration` for fn-system-specific work, or treat the existing Argo-managed fn-system as a stable dependency.

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
pnpm skaffold:doctor                           # read-only Skaffold + idpbuilder preflight
```

The wrapper:
1. Pauses ArgoCD for each named app (`argocd.argoproj.io/skip-reconcile=true`)
2. Exports `SKAFFOLD_DEFAULT_REPO=gitea-ryzen.tail286401.ts.net/giteaadmin` so kind-ryzen nodes can pull the dev image
3. Runs `skaffold dev -m <modules> --cleanup=false`
4. On Ctrl-C / EXIT / TERM: trap fires `skaffold/hooks/argo-resume.sh` to clear the skip-reconcile annotation and request a hard refresh

Edits to a sync'd path (e.g. `src/**/*.svelte`) tar into the pod in ~1s; Vite HMRs the browser. Edits to `package.json` / `pnpm-lock.yaml` force a full image rebuild + pod restart (~30s).

`pnpm skaffold:doctor` is the preferred first command for LLM coding agents. It checks the kubectl context, required commands, active/inactive module state, Argo pause annotations, live Deployment images, gitea-ryzen pins, `idpbuilder stacks status`, read-only `idpbuilder stacks sync --print-refresh-plan`, and `clhot --ci-one-shot --check`. Use `pnpm --silent skaffold:doctor -- --json` or `bash scripts/skaffold-doctor.sh --json` for machine-readable output.

### Legacy ryzen-only image loop

```bash
pnpm deploy:skaffold                                # workflow-builder
pnpm deploy:skaffold:orchestrator                   # workflow-orchestrator
bash scripts/skaffold-deploy.sh fn-activepieces     # any single service
bash scripts/skaffold-deploy.sh workflow-builder workflow-orchestrator  # batch
```

`scripts/skaffold-deploy.sh`:
1. Runs `skaffold build -m <svc> --push --file-output build.json` (cache-aware)
2. Parses `<repo>:<tag>@sha256:<digest>` from `build.json`
3. Invokes `skaffold/hooks/commit-pin.sh <svc>` unconditionally with that ref

`commit-pin.sh`:
- Maintains a dedicated cache clone at `~/.cache/skaffold/stacks-ryzen` tracking **gitea-ryzen exclusively** (NOT the developer's primary `stacks/main` checkout, which tracks GitHub origin and has a divergent lineage from gitea-ryzen).
- Each run: `git fetch --depth 50 origin main` → `git reset --hard origin/main`, then a Python textual edit of the kustomization's `newName:`/`newTag:` lines (avoids the `kustomize edit` CLI), commit, push to `gitea-ryzen/main`.
- Annotates ArgoCD app with `refresh=hard` to accelerate the poll. Argo's selfHeal + PreSync hook (`Job/db-migrate`) handle the rollout.
- This cache clone is separate from idpbuilder's sync cache. Do not use commit-pin for general manifest edits or durable workflow-builder image pins; use `idpbuilder stacks sync --seed-images=false` / `clu` from the primary stacks worktree so affected-app planning and local worktree snapshot semantics stay intact.

Override the gitea remote with `STACKS_REMOTE_URL=…` or branch with `STACKS_BRANCH=…`.

## Why use the wrappers (don't use `skaffold dev` / `skaffold run` directly)

The wrappers fix several invariants that bare `skaffold` commands violate:

- **Bare `skaffold dev` skips ArgoCD pause/resume.** Argo's `selfHeal=true` would re-apply the prod image within seconds, fighting Skaffold's deployed dev pod.
- **Bare `skaffold dev` doesn't set `SKAFFOLD_DEFAULT_REPO`.** Skaffold then resolves bare artifact names (`workflow-builder-dev`) to `docker.io/library/workflow-builder-dev` → push denied on Docker Hub.
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

- **The overlay extends only the Deployment file**, not the whole prod kustomization folder. The Application's inline `spec.source.kustomize.images` (e.g. `docker.io/library/postgres → gitea.cnoe.localtest.me:8443/.../postgres`) and `patches` (ExternalSecret remoteRef rewrites per cluster) are NOT applied by Skaffold; deploying the full folder would clobber Argo's render with `docker.io/...` refs that kind-ryzen can't pull.
- **The postgres init-container image is rewritten in the overlay's `images:` block** to mirror the Application-level rewrite (`gitea.cnoe.localtest.me:8443/giteaadmin/postgres:15.3-alpine3.18`).
- **The image swap lives in the strategic-merge patch**, not in the overlay's `images:` block — because the parent prod kustomization already rewrote `workflow-builder` → `ghcr.io/.../workflow-builder:git-<sha>` before our child overlay runs, so a child `images:` block keyed on `name: workflow-builder` would no-op.
- **`runAsUser: 0` + `runAsNonRoot: false`** so `pnpm install` / pip install can write under `/app` in the dev image. Triggers a benign PodSecurity `restricted:latest` warning at apply time.
- **`replicas: 1`** during dev — saves resources, and Skaffold's port-forward + sync target a single pod. The Application's `ignoreDifferences` on `/spec/replicas` already allows this.

Kustomize needs `--load-restrictor=LoadRestrictionsNone` to follow the `../../../../../stacks/main/...` reference; the module's `manifests.kustomize.buildArgs` passes this flag.

## Verification checklist

Before calling the inner loop done:
- `pnpm dev:skaffold` reaches "Watching for changes..." with a 2/2-Ready pod
- An edit to a sync'd path lands in the pod (visible via `kubectl exec … -- cat /app/path`) and triggers vite/uvicorn reload in the log
- Ctrl-C resumes the ArgoCD app (verify `metadata.annotations` has no `skip-reconcile`)
- Argo reconciles the Deployment back to the prod image within ~30s

Before calling the legacy ryzen-only image loop done:
- `pnpm deploy:skaffold` finishes with `==> ✓ done`
- The commit appears on `gitea-ryzen/main` (`git -C ~/.cache/skaffold/stacks-ryzen log -1`)
- ArgoCD app shows `sync=Synced health=Healthy phase=Succeeded` and the live Deployment's image matches the new tag
- Optional rollback: edit `~/.cache/skaffold/stacks-ryzen/.../kustomization.yaml` back to the prior pin, push, wait for Argo to roll the prod image. If the image should survive clean idpbuilder syncs, also commit the intended active-development pin to `origin/main`.

## Gotchas (memorize these — they cost the most time)

- **Stacks repo lineage divergence.** The developer's local `stacks/main` checkout (tracking GitHub `origin/main`) has a fundamentally different lineage from `gitea-ryzen/main` (4953+ commits divergent). Rebasing across that divergence would replay every gitea-ryzen commit onto GitHub's lineage — wrong. `commit-pin.sh` avoids touching the local stacks checkout; it uses a dedicated cache clone at `~/.cache/skaffold/stacks-ryzen`.
- **`stacks/main` is a git worktree.** `.git` is a file (containing `gitdir: ...`), not a directory. Don't use `[ -d "$stacks_dir/.git" ]` to check repo presence; use `git rev-parse --git-dir`.
- **Skaffold v2.17's tar walker mis-parses allowlist-style `.dockerignore`.** With `inputDigest` tag policy it errors "file pattern [package.json] must match at least one file" before docker even sees the context. Use `gitCommit:AbbrevCommitSha` tag policy for dev images instead.
- **`context: .` in a module yaml resolves to the module file's directory** (`skaffold/`), not the repo root. Use `context: ..` and adjust `dockerfile:` accordingly so build context = `workflow-builder/main/`.
- **PodSecurity warning at apply time is expected.** The dev container runs as root for hot-reload; the namespace's `restricted:latest` profile warns but doesn't block. Don't try to "fix" by going non-root.
- **fn-system is Knative-only.** It doesn't appear in the cluster as `deploy/fn-system` (only `deploy/fn-system-00001-deployment` scaled 0/0). Skaffold-style sync doesn't work for transient Knative pods. Use devspace or treat fn-system as a stable cluster dependency.
- **Skaffold artifact hooks skip on cache hits.** A re-run of `skaffold build` against unchanged source skips `hooks.after`. That's why the outer-loop wrapper runs commit-pin out-of-band.
- **`workflow-orchestrator/.venv` from prior devspace runs bloats the build context.** The dev `.dockerignore` now excludes `**/.venv`, `**/__pycache__`, `**/.pytest_cache`. If you see a multi-hundred-MB build context, suspect a missed exclude.
- **The dev image is push-required even on a local cluster.** kind nodes have their own containerd image store; `kind load docker-image` isn't wired into our Skaffold flow. `SKAFFOLD_DEFAULT_REPO=gitea-ryzen.tail286401.ts.net/giteaadmin` is the canonical pull path.

## Related skills

- [`devspace-quick-iteration`](../devspace-quick-iteration/SKILL.md) — legacy DevSpace flow. Use only for fn-system or when Skaffold is not yet wired for a service.
- [`workflow-builder`](../workflow-builder/SKILL.md) — authoring SW 1.0 workflows + diagnosing runtime failures in the same system. The Skaffold loop deploys the BFF; the workflow-builder skill covers how to author/debug what the BFF executes.
- [`gitops`](../gitops/SKILL.md) — broader ArgoCD reconcile flow + ryzen affected-app sync. The outer-loop wrapper commits to the same kustomization files that the GitOps skill manages; bigger image promotions (release-pins, dev/staging) go through the GitOps path, not Skaffold.

Concrete commands + recovery examples in [`references/workflow-builder.md`](references/workflow-builder.md).
