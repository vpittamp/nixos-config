# Workflow-Builder Skaffold Reference

## Paths

Workflow-builder repo (ryzen):

```bash
cd /home/vpittamp/repos/PittampalliOrg/workflow-builder/main
```

Stacks repo cache (auto-created by `commit-pin.sh`):

```bash
ls ~/.cache/skaffold/stacks-ryzen
```

Stacks repo (canonical GitOps source consumed by hub):

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
git log --oneline origin/main -5
git ls-remote origin env/hub-next env/hub  # see what's pending Promoter merge
```

Ryzen has no local Gitea and no idpbuilder — it uses GitHub + GHCR, and runs a
LOCAL ArgoCD that reconciles `overlays/ryzen` @ `main` DIRECTLY (the `inner-loop`
branch is RETIRED; no hub Source Hydrator, no Promoter on the ryzen lane). All
manifest changes flow through GitHub `main`: commit to `main` and ryzen's local
ArgoCD re-renders on its next reconcile (dev/staging consume the same `main`
content via their Promoter PRs — env/hub-next → env/hub, env/spokes-dev-next →
env/spokes-dev). Use the Skaffold inner loop for live source hot reload and the
outer loop (`pnpm deploy:skaffold`) for image bake + commit-pin to `main`.

**The hub github-outer-loop auto-builds + promotes ALL Skaffold-owned services
to dev on merge to `main` — not just workflow-builder.** The `github-outer-loop`
EventListener has PER-SERVICE triggers (CEL: a commit touching `services/<svc>/**`,
or commit message `[build all]`); a merge fires THAT service's trigger → the
PARAMETERIZED service-agnostic `outer-loop-build` Pipeline → GHCR → `update-stacks`
pins the SHARED `release-pins/workflow-builder-images.yaml` (ONE file holds EVERY
service's pin) + renders the dev overlay → source-hydrator → Promoter →
`env/spokes-dev` → `dev-<svc>` rolls. Verified end-to-end 2026-06-05 for
workflow-builder, workflow-orchestrator, function-router, mcp-gateway,
swebench-coordinator. ryzen is OFF this path (the github-outer-loop never touches
ryzen's pin — ryzen is the Skaffold `commit-pin.sh` lane). `update-stacks`'s
`git push origin main` now retries with backoff (6 attempts, 4/8/12/16/20s, rebase
between, stacks #2455) so a transient GitHub 500 / push contention no longer
silently drops a build's promotion.

There is NO inbound webhook path to a spoke. All 3 GitHub webhooks are HUB-FACING
(Tailscale Funnel): `tekton-hub` (build EventListener), `argocd-webhook-hub`
(`/api/webhook`), `gitops-promoter-webhook-hub`. ryzen, being an autonomous
argocd-agent with no argocd-server, can only be refreshed by its own SPOKE-LOCAL
ArgoCD (which is why commit-pin `refresh=hard`es the ryzen app directly rather
than relying on a relay — the argocd-agent principal does NOT relay refreshes to
autonomous agents on v0.8.1, verified live). The MANAGED dev agent DOES receive
relayed refreshes (hub annotation → reconcile in ~3s). For DEV, stacks PR #2449
added `argocd.argoproj.io/manifest-generate-paths` to the `spoke-workloads`
ApplicationSet hydrator template (pointing at each spoke's dry-source overlay,
`/packages/components/workloads/workflow-builder-system-overlays/<spoke>`); the
hub argocd-server already gets the stacks git webhook (`argocd-webhook-hub`), but
without that annotation it did NOT fire hydration on a release-pin render into
that overlay (~120s hydrator-poll wait). The hydrator app `spoke-dev-workflow-builder`
is HUB-reconciled (ns argocd), so the webhook drives it directly — no agent relay
on that hop. ryzen is unaffected (sourced by root-ryzen, not this hub appset).

## Inner loop — start

```bash
pnpm dev:skaffold                                # workflow-builder (default)
pnpm dev:skaffold:orchestrator                   # workflow-orchestrator
pnpm dev:skaffold:all                            # active modules

# Arbitrary subset:
bash scripts/skaffold-dev.sh function-router
bash scripts/skaffold-dev.sh workflow-builder workflow-orchestrator mcp-gateway
```

> The ActivePieces piece-runtime (`ap-<piece>-service`) is NOT a Skaffold module — those per-piece Knative services are reconciler-owned (`activepieces-mcps`), delivered via image rebuild + metadata re-sync, not the Skaffold inner/outer loop. (`fn-activepieces` was deleted.)

Steady-state for a single-module session: pod 2/2 Ready in ~3 min (Dapr sidecar dominates), then "Watching for changes..." and port-forward live (e.g. `http://localhost:3002` for workflow-builder).

## Inner loop — verify sync

Touch a sync'd file and confirm it landed in the pod:

```bash
# Edit any matched src path locally, e.g. src/routes/+layout.svelte (workflow-builder)
# or services/workflow-orchestrator/app.py (orchestrator). Then:

pod=$(kubectl -n workflow-builder get pod -l app=workflow-builder -o jsonpath='{.items[0].metadata.name}')
kubectl -n workflow-builder exec "$pod" -c workflow-builder -- head -5 /app/src/routes/+layout.svelte
```

Skaffold's log line `Syncing N files for <image>` confirms the sync fired. For workflow-orchestrator, uvicorn `--reload` logs `Registering activity 'publish_workflow_failed' with runtime` after each reload.

## Inner loop — exit + ArgoCD resume

`Ctrl+C` in the skaffold session. The wrapper's EXIT trap calls `argo-resume.sh` automatically.

Manual recovery if the trap doesn't fire (e.g. SIGKILL):

```bash
ARGO_APPS="workflow-builder" bash skaffold/hooks/argo-resume.sh

# Or multiple at once:
ARGO_APPS="workflow-builder workflow-orchestrator function-router" \
  bash skaffold/hooks/argo-resume.sh
```

Verify Argo cleared the pause:

```bash
kubectl get application workflow-builder -n argocd \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/skip-reconcile}{"\n"}'
# (should print blank)
```

## Legacy ryzen-only image loop

Prefer the GitHub/GHCR build lane plus an `origin/main` pin for durable workflow-builder images. For workflow-builder + workflow-mcp-server the ryzen pin is now FULLY AUTOMATED: `commit-pin.sh` upserts the flat pins file `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml` AND renders + commits the kustomize Component `packages/components/workloads/workflow-builder-ryzen-image/kustomization.yaml` LOCALLY (running `WFB_RENDER_ENVS=ryzen scripts/gitops/render-workflow-builder-release-overlays.sh` in its fresh hard-reset `~/.cache/skaffold/stacks-ryzen` clone — deterministic, byte-identical to CI), all in the SAME push, then `refresh=hard`es the ryzen SPOKE-LOCAL app. ryzen's autonomous local ArgoCD then reconciles `overlays/ryzen@main` in SECONDS (no ~1-2 min CI wait, no 30s-poll wait). No manifests `newTag` edit. stacks CI (`render-ryzen-image.yml`) is UNCHANGED but is now just a DRIFT-CORRECTION SAFETY NET — it re-renders on push and commits only on a diff, so it NO-OPS when commit-pin's local render already matches. (Phase 2d is DONE — ryzen no longer reads a bare `manifests/kustomization.yaml` `images:` block for these two services; the render now runs in commit-pin locally with CI as a drift net.) Use the Skaffold deploy path only for narrow ryzen-only recovery/testing.

The local render (instead of relying on a webhook to ryzen) is required because there is NO inbound webhook path to ryzen: ryzen is an AUTONOMOUS argocd-agent with NO argocd-server (so no inbound `/api/webhook`), AND the argocd-agent principal does NOT relay a refresh to autonomous agents on v0.8.1 (live test: a hub-side `argocd.argoproj.io/refresh` annotation on the ryzen mirror NEVER reached the spoke). The only fast path is the SPOKE-LOCAL refresh commit-pin issues directly. (By contrast the MANAGED agent (dev) relay WORKS — a hub-side refresh annotation reached the dev agent and reconciled in ~3s.)

```bash
pnpm deploy:skaffold                                  # workflow-builder
pnpm deploy:skaffold:orchestrator                     # workflow-orchestrator
bash scripts/skaffold-deploy.sh function-router       # any single service
bash scripts/skaffold-deploy.sh workflow-builder workflow-orchestrator  # batch
```

**Bring a STALE service current on DEV without a source change.** The hub
per-service trigger only fires on a `services/<svc>/` change, so a service with no
recent edits stays frozen at its last successful dev image. To rebuild from current
`main` HEAD into dev (not ryzen), create a PipelineRun from the `outer-loop-build`
Pipeline with params `git_url=https://github.com/PittampalliOrg/workflow-builder.git`,
`git_sha=<current main HEAD>`, `image_name=<svc>`, `dockerfile=services/<svc>/Dockerfile`,
`context=.` (Node: function-router/mcp-gateway) or `services/<svc>` (Python:
workflow-orchestrator/swebench-coordinator), + workspaces `shared-workspace`
(emptyDir), `dockerconfig` (Secret `ghcr-push-credentials`), `buildah-cache`
(PVC `buildah-cache-<svc>`). The per-service `image_name`/`dockerfile`/`context`
come from each `outer-loop-<svc>` TriggerBinding; `update-stacks` then re-pins dev.
(Used 2026-06-05 to bring mcp-gateway/swebench-coordinator/function-router current.)

End-to-end timeline (workflow-builder, fresh build, no cache):
- Build (SvelteKit prod multi-stage): ~70s
- Push to GHCR: ~30s
- `commit-pin.sh`: ~2s (fetch + reset + edit + commit + push)
- ArgoCD reconcile + PreSync `db-migrate` Job: ~30–90s
- Deployment rolling update: ~30s

## Legacy ryzen-only loop — verify pin landed + Argo applied

```bash
# Local cache repo state
git -C ~/.cache/skaffold/stacks-ryzen log -1 --oneline
git -C ~/.cache/skaffold/stacks-ryzen show HEAD --stat

# Argo state
kubectl get application workflow-builder -n argocd \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status} phase={.status.operationState.phase}{"\n"}'

# Live image
kubectl -n workflow-builder get deploy workflow-builder \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

When sync stalls (Argo phase=Running but never finishes), check the operation message:

```bash
kubectl get application workflow-builder -n argocd \
  -o jsonpath='{.status.operationState.message}{"\n"}'
# Common stall: "waiting for completion of hook batch/Job/db-migrate"
```

`db-migrate` is a PreSync hook; check the Job pod logs (`kubectl -n workflow-builder logs job/workflow-builder-db-migrate-…`).

## Legacy ryzen-only loop — rollback / revert

For **workflow-builder** and **workflow-mcp-server**, the ryzen pin lives in a FLAT pins file (the bare `images:` block was deleted from `packages/components/workloads/workflow-builder/manifests/kustomization.yaml`). For a MANUAL revert, edit the flat pins file back to the prior tag AND render the Component locally (or let the CI drift-net re-render), then push + refresh the ryzen SPOKE app:

```bash
cd ~/.cache/skaffold/stacks-ryzen
git fetch --depth 50 origin main
git reset --hard origin/main

# Edit packages/components/hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml:
# set the workflow-builder images/imageRefs/digests/sourceShas entries back to the prior tag/digest.
# (commit-pin.sh upserts this file; for a manual revert, edit it directly.)
$EDITOR packages/components/hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml

# Render the Component locally (deterministic; same as commit-pin / CI):
WFB_RENDER_ENVS=ryzen scripts/gitops/render-workflow-builder-release-overlays.sh

git add packages/components/hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml \
        packages/components/workloads/workflow-builder-ryzen-image/kustomization.yaml
git commit -m "chore(workflow-builder): revert ryzen pin to prior tag"
git push origin main
# If you skip the local render, stacks CI (.github/workflows/render-ryzen-image.yml)
# re-renders + commits the Component on push (drift-correction net) — but you then
# wait on that CI run before the ryzen pin is effective.

# Refresh the ryzen SPOKE-LOCAL app directly (no inbound webhook/relay path to ryzen):
kubectl -n argocd annotate application ryzen-workflow-builder \
  argocd.argoproj.io/refresh=hard --overwrite
```

ryzen's workflow-builder Application sources `manifests/` directly; that kustomization `components:`-includes the rendered `workflow-builder-ryzen-image` Component, so the regenerated Component IS ryzen's effective pin once it's committed. (For all OTHER Skaffold-owned services — `workflow-orchestrator`, `function-router`, `mcp-gateway` — the pin is still the bare `manifests/kustomization.yaml` `newTag`, edited directly; the flat-pins→render path is workflow-builder/workflow-mcp-server-only.)

## Cluster-level preflight (before first session of a day)

```bash
pnpm skaffold:doctor                # preferred; read-only Skaffold preflight
pnpm --silent skaffold:doctor -- --json  # machine-readable for agents
kubectl config current-context        # expect admin@ryzen
kubectl get nodes                     # 3 nodes Ready
kubectl -n workflow-builder get deploy workflow-builder workflow-orchestrator function-router mcp-gateway swebench-coordinator
kubectl get application workflow-builder workflow-orchestrator -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name} sync={.status.sync.status} health={.status.health.status}{"\n"}{end}'
docker info >/dev/null && echo "docker OK"
skaffold version                      # v2.17.x or later
```

If `docker login` is not present for `ghcr.io`, the Skaffold push step fails with "no basic auth credentials". Re-login (PAT needs `write:packages`):

```bash
docker login -u PittampalliOrg ghcr.io
# password: a GHCR PAT (write:packages); see the org credential store
```

## Module-specific quirks

- **workflow-builder**: SvelteKit's `.svelte-kit/tsconfig.json` doesn't exist on first start — `[WARNING] Cannot find base config file` is benign; vanishes after the first route hit.
- **workflow-orchestrator**: uvicorn `--reload` watches `/app`; py edits trigger restart. Dapr's scheduler-disconnected logs at startup are normal — placement reconnects within seconds.
- **swebench-coordinator**: build context is the repo root (Dockerfile uses `services/swebench-coordinator/...` paths). Same .dockerignore exclusions as workflow-orchestrator.
- **Node services + pnpm v10 build gotcha**: a Node service whose Dockerfile uses UNPINNED `npm install -g pnpm` gets pnpm v10, which FAILS the prod build at `RUN pnpm build` with `ERR_PNPM_IGNORED_BUILDS` (esbuild/protobufjs build scripts blocked behind an approval gate). FIX: pin `pnpm@9` (like mcp-gateway); do NOT rely on `--ignore-scripts` (leaves esbuild's binary missing for the build stage). This kind of prod-build break can hide indefinitely because the hub per-service trigger only fires on a `services/<svc>/` change — the image just stays frozen at the last good build (function-router was stuck at a May-21 image for this reason; fixed wfb PR #42).

## When Skaffold is NOT the right path

- **`fn-system` (Knative)** — treat the cluster's Argo-managed pod as an external dependency. Skaffold sync into a transient Knative revision is impractical. `scripts/sandbox-dev.sh` is the experimental sandbox-based alternative for Knative-style workloads.
- **ActivePieces piece-runtime (`ap-<piece>-service`)** — reconciler-owned per-piece Knative services (`activepieces-mcps`), not a Skaffold module. Deliver changes via an image rebuild (`piece-mcp-server`) + metadata re-sync, not Skaffold. (`fn-activepieces` was deleted.)
- **Services not in the Skaffold module set** — add them to `skaffold/<svc>.skaffold.yaml` and the root `requires:` list rather than using a side-channel inner-loop.


