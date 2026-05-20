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

## Inner loop — start

```bash
pnpm dev:skaffold                                # workflow-builder (default)
pnpm dev:skaffold:orchestrator                   # workflow-orchestrator
pnpm dev:skaffold:all                            # all 6 modules

# Arbitrary subset:
bash scripts/skaffold-dev.sh function-router
bash scripts/skaffold-dev.sh workflow-builder workflow-orchestrator mcp-gateway
```

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

## Outer loop — deploy a new prod image

```bash
pnpm deploy:skaffold                                  # workflow-builder
pnpm deploy:skaffold:orchestrator                     # workflow-orchestrator
bash scripts/skaffold-deploy.sh fn-activepieces       # any single service
bash scripts/skaffold-deploy.sh workflow-builder workflow-orchestrator  # batch
```

End-to-end timeline (workflow-builder, fresh build, no cache):
- Build (SvelteKit prod multi-stage): ~70s
- Push to gitea-ryzen: ~30s
- `commit-pin.sh`: ~2s (fetch + reset + edit + commit + push)
- ArgoCD reconcile + PreSync `db-migrate` Job: ~30–90s
- Deployment rolling update: ~30s

## Outer loop — verify pin landed + Argo applied

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

## Outer loop — rollback / revert

Edit the gitea-ryzen pin back to the prior tag and re-push from the cache clone:

```bash
cd ~/.cache/skaffold/stacks-ryzen
git fetch --depth 50 origin main
git reset --hard origin/main

python3 - <<'PY'
import pathlib, re
p = pathlib.Path("packages/components/active-development/manifests/workflow-builder/kustomization.yaml")
t = p.read_text()
pattern = re.compile(r'(\n  - name: workflow-builder\n)(    newName: )[^\n]+(\n)(    newTag: )[^\n]+(\n)')
new, _ = pattern.subn(r'\g<1>\g<2>ghcr.io/pittampalliorg/workflow-builder\g<3>\g<4>git-<prior-sha>\g<5>', t)
p.write_text(new)
PY

git add packages/components/active-development/manifests/workflow-builder/kustomization.yaml
git commit -m "chore(workflow-builder): revert pin to prod tag"
git push origin main

kubectl -n argocd annotate application workflow-builder \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Cluster-level preflight (before first session of a day)

```bash
kubectl config current-context        # expect admin@ryzen
kubectl get nodes                     # 3 nodes Ready
kubectl -n workflow-builder get deploy workflow-builder workflow-orchestrator function-router fn-activepieces mcp-gateway swebench-coordinator
kubectl get application workflow-builder workflow-orchestrator -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name} sync={.status.sync.status} health={.status.health.status}{"\n"}{end}'
docker info >/dev/null && echo "docker OK"
skaffold version                      # v2.17.x or later
```

If `docker login` is not present for `gitea-ryzen.tail286401.ts.net`, the Skaffold push step fails with "no basic auth credentials". Re-login:

```bash
docker login -u giteaadmin gitea-ryzen.tail286401.ts.net
# password: see existing ~/.docker/config.json or org credential store
```

## Module-specific quirks

- **workflow-builder**: SvelteKit's `.svelte-kit/tsconfig.json` doesn't exist on first start — `[WARNING] Cannot find base config file` is benign; vanishes after the first route hit.
- **workflow-orchestrator**: uvicorn `--reload` watches `/app`; py edits trigger restart. Dapr's scheduler-disconnected logs at startup are normal — placement reconnects within seconds.
- **fn-activepieces**: the prod Deployment file is a multi-doc YAML (Deployment + Service). The dev overlay's `resources:` references the file; both kinds render but only the Deployment is patched.
- **swebench-coordinator**: build context is the repo root (Dockerfile uses `services/swebench-coordinator/...` paths). Same .dockerignore exclusions as workflow-orchestrator.

## When to use devspace instead

- The service is fn-system (Knative).
- The service hasn't been added to the Skaffold module set yet.
- You need devspace's profile-based multi-service composition for an experimental setup.

See the [`devspace-quick-iteration`](../../devspace-quick-iteration/SKILL.md) skill.
