# Architecture: hub + 3 spokes, two image-pin systems, two Tekton instances

## Cluster roles

```
                         ┌─────────────────────────────────────────────┐
                         │  HUB (Talos on Hetzner, 5.161.99.23:6443)    │
                         │  - Single ArgoCD (manages itself + spokes)   │
                         │  - Hub Tekton (outer-loop, GHCR pushes)      │
                         │  - GitOps Promoter (workflow-builder-release)│
                         │  - Crossplane (spoke lifecycle)              │
                         │  - ExternalSecrets Operator                  │
                         │  - Tailscale operator (ProxyGroups, Funnel)  │
                         └─────────────────────────────────────────────┘
                                  │  cluster secrets in argocd ns
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
        ┌─────────┐         ┌─────────┐         ┌─────────┐
        │   dev   │         │ staging │         │  ryzen  │
        │ (Talos, │         │ (Talos, │         │  (kind, │
        │ Hetzner)│         │ Hetzner)│         │  user's │
        └─────────┘         └─────────┘         │  workst.│
                                                │  + own  │
                                                │  Tekton │
                                                │  inner- │
                                                │  loop)  │
                                                └─────────┘
```

`hcloud server list` (context `stacks`):
- hub: `hub-cp-1` (5.161.48.192), `hub-worker-1` (5.161.43.68) on `hub-cluster-net` (10.1.1.0/24)
- dev: `dev-cp-1/2/3` (178.156.225.243, .239.75, .226.121), `dev-worker-1/2` on `dev-network` (10.0.1.0/24)
- staging: `staging-cp-1/2/3`, `staging-worker-1/2` on `staging-network`

ryzen is the user's local workstation (`hostname` returns `ryzen`); the kind cluster is registered with the hub ArgoCD as cluster `ryzen`.

## Two Tekton instances, two image-pin systems

This is **the** mental model for this system. The same workflow-builder base manifests at `packages/components/active-development/manifests/workflow-builder/` are used by all three spokes, but the image tags come from **different files**:

```
GitHub push to PittampalliOrg/workflow-builder
    │
    │  webhook (Tailscale Funnel: tekton-hub.tail286401.ts.net)
    ▼
┌──────────────────────────────────────────────┐
│  HUB TEKTON outer-loop pipeline               │
│  - Build with Buildah                         │
│  - Push to ghcr.io/pittampalliorg/<img>:git-… │
│  - Update release-pins on origin/main         │
└──────────────────────────────────────────────┘
    │
    │  release-pins/workflow-builder-images.yaml
    ▼
┌──────────────────────────────────────────────┐
│  spoke-workloads ApplicationSet (matrix gen)  │
│  - Reads release-pins from main HEAD          │
│  - Templates per spoke (dev, staging, ryzen)  │
│  - Patches spec.source.kustomize.images       │
│    rewriting all gitea/local refs → ghcr.io   │
└──────────────────────────────────────────────┘
    │
    │  source-hydrator renders to env/spokes-{spoke}-next
    ▼
┌──────────────────────────────────────────────┐
│  GitOps Promoter (workflow-builder-release)   │
│  - Gates on argocd-health CommitStatus        │
│  - autoMerge: true on dev AND staging         │
│  - Promotes env/spokes-{spoke}-next →         │
│    env/spokes-{spoke}                         │
└──────────────────────────────────────────────┘
    │
    ▼
Hub ArgoCD syncs spoke apps from env/spokes-{spoke}
   → manifests applied to dev / staging cluster

============================================================

Local edit on ryzen (push to gitea-ryzen, the local Gitea)
    │
    ▼
┌──────────────────────────────────────────────┐
│  RYZEN TEKTON inner-loop pipeline             │
│  - Build with Buildah                         │
│  - Push to gitea-ryzen.tail286401.ts.net/…    │
│  - Update active-development/manifests/<img>/ │
│    kustomization.yaml on gitea-ryzen/main     │
│  - Commit subject:                            │
│    "chore(dev-images): deploy <img> <tag>     │
│     to ryzen"  (author: Tekton Hub)           │
└──────────────────────────────────────────────┘
    │
    ▼
Hub ArgoCD syncs ryzen apps from gitea-ryzen/main
   → manifests applied to ryzen kind cluster
```

**Key implications:**
- A bump on ryzen does **not** propagate to dev/staging. Bumping dev/staging requires a separate edit to release-pins.
- An image tag bumped to dev/staging via release-pins **must already exist on `ghcr.io`**. Outer-loop normally builds it, but if the GitHub webhook is broken, the tag exists only on gitea-ryzen and you need to skopeo-mirror it manually.
- `agent-runtime-controller` is the exception: bumped directly in `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` (no per-cluster override). Single bump applies to all spokes once on `origin/main`.

## Live deployment inventory

Workflow-builder has an admin Deployments view that reads the current GitOps state instead of asking an operator to mentally join release-pins, Promoter status, and ArgoCD summaries. The data path is:

```
Hub CronJob gitops-deployment-inventory
    │  reads release-pins, PromotionStrategy/CommitStatus, ArgoCD Applications,
    │  and recent outer-loop PipelineRuns
    ▼
ConfigMap argocd/gitops-deployment-inventory
    │
    ▼
Deployment/Service/Ingress gitops-deployment-inventory
    │  https://gitops-inventory-hub.tail286401.ts.net/inventory.json
    ▼
workflow-builder WORKFLOW_BUILDER_GITOPS_INVENTORY_URL
    │
    ▼
/admin/deployments
```

Use this first when the question is "which image/commit is live on dev or staging?" It shows desired release-pin images, live Argo images, drift state, hydrated/source SHAs, commit metadata, and recent build/promotion evidence in one place. Fall back to `PromotionStrategy`, `ChangeTransferPolicy`, and raw ArgoCD Applications when the inventory is stale or unavailable.

## Branch model

| Branch | Origin | Role |
|---|---|---|
| `main` | both `origin` (GitHub) and `gitea-ryzen` | Source of truth for all overlays. Two automated bumpers commit independently → branches drift |
| `env/hub-next` | `origin` only | Source-hydrator output for hub overlay. Promoter merges to `env/hub` |
| `env/hub` | `origin` only | What hub root-application syncs from |
| `env/spokes-dev-next` / `env/spokes-staging-next` | `origin` only | Source-hydrator output per spoke |
| `env/spokes-dev` / `env/spokes-staging` | `origin` only | What spoke ArgoCD apps sync from (`workflow-builder-release` PromotionStrategy promotes to these) |
| (no `env/spokes-ryzen-next`) | — | Ryzen does not go through promoter; spoke-workloads AppSet writes directly to `env/spokes-ryzen` |

## Why ryzen is special

Ryzen exists for **fast iteration** (DevSpace hot reload, local builds, kind image loading). It's intentionally outside the promoter chain:
- ryzen pulls from the local gitea-ryzen registry (low-latency, free, unrestricted)
- ryzen has its own Tekton (no waiting on hub builds)
- ryzen's spoke-workloads AppSet writes to `env/spokes-ryzen` directly with no promoter gate

ryzen **proves the stack works in the local platform shape**. The outer-loop **proves the release artifact and rendered manifests are promotable**. Those are different validations.

## File-level entry points

| Path | What's there |
|---|---|
| `packages/overlays/hub` | Hub overlay; sourceHydrator drySource for root-application |
| `packages/overlays/{dev,staging,ryzen}` | Per-spoke base overlay |
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` | dev/staging image pins ← **the file you edit most often** |
| `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` | Matrix AppSet generator + Kustomize patches per spoke |
| `packages/components/hub-management/manifests/gitops-promoter/PromotionStrategy-workflow-builder-release.yaml` | dev → staging promotion (autoMerge: true on both, gate: argocd-health) |
| `packages/components/hub-management/manifests/gitops-promoter/gitops-deployment-inventory.yaml` | Hub inventory API consumed by workflow-builder admin Deployments |
| `packages/components/active-development/manifests/<image>/kustomization.yaml` | ryzen image-pin per workload |
| `packages/components/hub-tekton/manifests/outer-loop-builds/` | Hub Tekton pipeline + EventListener |
| `packages/components/hub-tekton/manifests/workflow-builder-builds/` | Inner-loop pipeline definitions |
| `policy.hujson` | Tailscale ACL — synced via `.github/workflows/tailscale-acl.yml` |

For the original full architecture write-up (covers DevSpace, OpenShell, Dapr workflows), see `docs/gitops-architecture-overview.md` and `docs/outer-loop-promotion.md` in the stacks repo.
