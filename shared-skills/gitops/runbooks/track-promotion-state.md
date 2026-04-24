# Runbook: Track a promotion in flight

## When to use

You bumped `release-pins/workflow-builder-images.yaml` (or one of its peers) and want to see:
- Where the promotion is in the pipeline (hydrating? promoter PR open? spoke synced?)
- What's gating the next step (most often: dev's `argocd-health` not green yet → staging blocked)
- Which spoke is currently on which image
- Whether "stuck" is actually stuck or just waiting on a normal poll

The ArgoCD UI doesn't have a dedicated promoter view, so most of the visibility is via CRD inspection.

For workflow-builder specifically, start with `/admin/deployments` in the app. It is backed by the hub `gitops-deployment-inventory` API and usually answers "what's live, what's desired, and what is drifting?" faster than stitching together the lower-level CRDs.

## Mental model

```
origin/main
   │  (per-app sourceHydrator on hub-side spoke-<env>-<app>)
   ▼
env/spokes-<env>-next   ──merged──▶  env/spokes-<env>   ──synced──▶  Spoke cluster (dev/staging)
   │                       ▲                                              │
   │                       │                                              │ ArgoCD reports health
   │            ChangeTransferPolicy                                      │ via CommitStatus
   │            (PR opened with autoMerge: true)                          │ on the hydrated sha
   │                       ▲                                              │
   │                       └────── argocd-health gate (must = success) ◀──┘
   ▼
env/spokes-staging-next ── blocked until dev's argocd-health=success ──▶ env/spokes-staging
```

Four layers of state to read in order:

| Layer | What to look at | What it tells you |
|---|---|---|
| 0. Inventory | workflow-builder `/admin/deployments` or `gitops-inventory-hub` | Desired images, live images, drift, commit/build metadata, and promotion SHAs in one place |
| 1. Hydrator | `env/spokes-<env>-next` branch tip on github | Whether your release-pins commit got rendered (~30-90s after origin/main lands) |
| 2. Promoter | `PromotionStrategy.status.environments[*]` + `ChangeTransferPolicy` | Whether the promoter PR was opened/merged (gated by `argocd-health` CommitStatus) |
| 3. Spoke ArgoCD | `spoke-<env>-<app>` and `<env>-<app>` Application status | Whether the spoke synced; whether the new image is live |

## Web UI on argocd-hub.tail286401.ts.net

1. **workflow-builder `/admin/deployments`** — preferred first view for app/runtime metadata. It compares release-pins, live Argo images, commit metadata, build status, and promotion state.
2. **PromotionStrategy** — `argocd / workflow-builder-release` (or `stacks-environments` for hub-only changes). View YAML; look at `.status.environments[]` for per-environment dry/hydrated SHAs and `commitStatuses[?(@.key=="argocd-health")].phase`.
3. **`spoke-<env>-<app>` apps** (e.g. `spoke-dev-workflow-builder`) — these are the meta-apps that watch `env/spokes-<env>` and deploy Application CRDs to the spoke cluster. Sync revision = the hydrated commit currently serving.
4. **`<env>-<app>` apps** (e.g. `dev-workflow-builder`) — these run ON the spoke cluster (`destination.name=dev`) and deploy actual workloads. `summary.images` shows the resolved image tag after kustomize image substitution.
5. **Open PRs in stacks** — promoter creates auto-merge PRs from `env/spokes-<env>-next` → `env/spokes-<env>` for each promotion. https://github.com/PittampalliOrg/stacks/pulls?q=is%3Aopen+head%3Aenv%2Fspokes-

## CLI cheat-sheet

```bash
# 0. Inventory API: same data workflow-builder uses for /admin/deployments
TOKEN=$(kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret gitops-deployment-inventory \
  -o jsonpath='{.data.bearerToken}' | base64 -d)
curl -fsS -H "Authorization: Bearer ${TOKEN}" \
  https://gitops-inventory-hub.tail286401.ts.net/inventory.json | \
  jq '.environments[] | {env: .name, apps: [.applications[] | {name, desired: .desired.image, live: .live.images, drift: .drift.status}]}'

# 1. One-line PromotionStrategy summary (per environment)
kubectl --kubeconfig ~/.kube/hub-config -n argocd get promotionstrategy workflow-builder-release \
  -o jsonpath='{range .status.environments[*]}env={.branch} dry={.active.dry.sha} hydrated={.active.hydrated.sha} health={.active.commitStatuses[?(@.key=="argocd-health")].phase}{"\n"}{end}'

# 2. ChangeTransferPolicies (one per env) — shows promoter PR state
kubectl --kubeconfig ~/.kube/hub-config -n argocd get changetransferpolicy
# Look for: PROPOSED DRY SHA != ACTIVE DRY SHA (promotion in flight) and PR STATE column

# 3. ArgoCDCommitStatus (the health gate)
kubectl --kubeconfig ~/.kube/hub-config -n argocd get argocdcommitstatus

# 4. Open promoter-created PRs
gh pr list --repo PittampalliOrg/stacks --state open --search "head:env/spokes" \
  --json number,title,headRefName

# 5. Spoke meta-app + workload-app revisions side-by-side
for env in dev staging; do
  for kind in spoke- ""; do
    name="${kind}${env}-workflow-builder"
    kubectl --kubeconfig ~/.kube/hub-config -n argocd get app $name \
      -o jsonpath='{.metadata.name}: rev={.status.sync.revision} sync={.status.sync.status} health={.status.health.status}{"\n"}'
  done
done

# 6. Promoter logs filtered to OUR ChangeTransferPolicy
kubectl --kubeconfig ~/.kube/hub-config -n gitops-promoter-system logs deploy/gitops-promoter-controller-manager \
  -c manager --tail=200 | grep -E "workflow-builder-release"

# 7. The image actually deployed on dev's pod (live, via argocd app manifests)
argocd login argocd-hub.tail286401.ts.net --grpc-web --plaintext=false \
  --username=admin \
  --password="$(kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d)"
argocd app manifests dev-workflow-builder --source live | grep -E "image: ghcr.io/pittampalliorg/workflow-builder"
```

## Why "blocked" usually isn't blocked

There are at least three polling intervals in this pipeline. Each adds latency before "OutOfSync" → "Synced" propagation:

| Layer | Default poll | What's polled |
|---|---|---|
| Source-hydrator (per spoke-app `sourceHydrator`) | ~3 min | The dry-source `targetRevision` (origin/main) for new commits |
| GitOps Promoter controller | ~30-60s | `ChangeTransferPolicy` reconcile (after the dry sha appears on env-next) |
| Spoke ArgoCD application controller | ~3 min | The hydrated branch (`env/spokes-<env>`) for new tip |

So 5–8 minutes from "I just merged to origin/main" to "dev pod is rolling on the new image" is normal. **Don't hard-sync; wait a poll cycle.**

Two known dead-ends:

- **`argocd app refresh --hard`** triggers manifest re-render but does NOT immediately repoll branch tips. Useful when you suspect cache staleness for `targetRevision: <sha>` apps; useless for `sourceHydrator: targetBranch: <branch>` apps.
- **`argocd app sync --revision <sha>`** is rejected on auto-sync + branch-tracking apps with `Cannot sync to <sha>: auto-sync currently set to <branch>`. This is Argo's safety, not a bug.

## What "blocked" actually looks like

Symptoms that justify intervening:

- **PromotionStrategy `health=pending` for >10 min** AND `proposed.hydrated.sha == active.hydrated.sha`: hydrator hasn't picked up your origin/main commit. Check `argocd app get spoke-<env>-<app> --hard-refresh` to nudge.
- **PromotionStrategy `health=pending` for >10 min** AND `proposed.hydrated.sha != active.hydrated.sha`: promoter hasn't merged the env-next PR. Check `kubectl get pr -A` (the promoter creates these as `PullRequest.promoter.argoproj.io` CRs); gh PR view for the actual GitHub PR; `argocd app history dev-workflow-builder` to see if dev has tried syncing on the new sha and reported back.
- **Spoke `<env>-<app>` Synced + Healthy on the new revision but image still old**: kustomize images patch wasn't applied. Check `.spec.source.kustomize.images` on the app — should contain `workflow-builder=ghcr.io/pittampalliorg/workflow-builder:git-<new-sha>`.
- **`db-migrate` Job hookPhase=Succeeded but new columns missing**: classic drizzle-journal-skip bug. See `runbooks/fix-drizzle-migration.md`.

## Verify (after a normal flow)

```bash
# Both spoke meta-apps Synced + Healthy at the new hydrated commit
kubectl --kubeconfig ~/.kube/hub-config -n argocd get app spoke-dev-workflow-builder spoke-staging-workflow-builder \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# Both workload apps have the new image
for env in dev staging; do
  echo "--- $env ---"
  kubectl --kubeconfig ~/.kube/hub-config -n argocd get app ${env}-workflow-builder \
    -o jsonpath='{.status.summary.images}' | tr ',' '\n' | grep workflow-builder
done

# No open promoter PRs left = promotion fully merged
gh pr list --repo PittampalliOrg/stacks --state open --search "head:env/spokes" --json number
# Should be []
```
