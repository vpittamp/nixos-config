# Architecture: hub + 3 spokes, two image-pin systems, two Tekton instances

## Cluster roles

```
                         ┌─────────────────────────────────────────────┐
                         │  HUB (Talos on Hetzner, 5.161.99.23:6443)    │
                         │  - Single ArgoCD (manages itself + spokes)   │
                         │  - Hub Tekton (outer-loop, GHCR pushes)      │
                         │  - GitOps Promoter + ArgoCD Promoter UI      │
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
│  - Open release PR with tag/digest metadata   │
└──────────────────────────────────────────────┘
    │
    │  release/workflow-builder-* PR → origin/main
    │  release-pins/workflow-builder-images.yaml
    ▼
┌──────────────────────────────────────────────┐
│  spoke-workloads ApplicationSet (matrix gen)  │
│  - Reads release-pins from main HEAD          │
│  - Uses images tags + digests/provenance maps │
│  - Templates per spoke (dev, staging, ryzen)  │
│  - Patches spec.source.kustomize.images       │
│    rewriting all gitea/local refs → ghcr.io   │
└──────────────────────────────────────────────┘
    │
    │  source-hydrator renders to env/spokes-{spoke}-next
    ▼
┌──────────────────────────────────────────────┐
│  GitOps Promoter (workflow-builder-release)   │
│  - Gates on argocd-health + timer statuses    │
│  - autoMerge true: dev immediate, staging soak│
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
- A bump on ryzen does **not** propagate to dev/staging. Bumping dev/staging normally means merging the hub Tekton release-intent PR for `release-pins/workflow-builder-images.yaml`.
- A tag/digest bumped to dev/staging via release-pins **must already exist on `ghcr.io`**. Outer-loop normally builds it and records the digest/provenance in the PR, but if the GitHub webhook is broken, the tag exists only on gitea-ryzen and you need to skopeo-mirror it manually.
- `release-pins/workflow-builder-images.yaml` is schema v2: `images` remains the compatibility tag map; `digests`, `imageRefs`, `sourceShas`, `pipelineRuns`, and `updatedAts` hold immutable/provenance metadata. Dev/staging templates render tag+digest refs when a digest is present.
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
    ├─ human/browser path:
    │    https://gitops-inventory-hub.tail286401.ts.net/inventory.json
    │    (Tailscale Ingress service-host VIP on cluster-ingress)
    │
    └─ spoke workload path:
         gitops-deployment-inventory-tailnet LoadBalancer
         → gitops-inventory-hub-node.tail286401.ts.net:8080
         → spoke Service gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080
    ▼
workflow-builder WORKFLOW_BUILDER_GITOPS_INVENTORY_URL
    │
    ▼
/admin/deployments
```

Use this first when the question is "which image/commit is live on dev or staging?" It shows desired release-pin images, live Argo images, drift state, hydrated/source SHAs, commit metadata, and recent build/promotion evidence in one place. Fall back to `PromotionStrategy`, `ChangeTransferPolicy`, and raw ArgoCD Applications when the inventory is stale or unavailable.

Do not point spoke Tailscale egress at `gitops-inventory-hub.tail286401.ts.net`: it is a service-host VIP (`svc:gitops-inventory-hub`), not a Tailscale node. Cluster egress targets must be nodes or IPs, so workflow-builder uses the separate node-backed `gitops-inventory-hub-node` endpoint on port `8080`.

## Promoted spoke runtime URLs

Dev and staging are not just ryzen with a different image registry. Workflow-builder and its system services need cluster-specific public URLs, declared in GitOps:

| Runtime dependency | Dev/staging declaration |
|---|---|
| workflow-builder app URL | Device-backed Tailscale Ingress `workflow-builder-CLUSTER` rendered by the spoke tailscale-ingresses overlay |
| MCP gateway URL | `MCP_GATEWAY_BASE_URL=https://mcp-gateway-{{cluster}}.tail286401.ts.net` in `spoke-workloads-appset.yaml`; matching device-backed `mcp-gateway-CLUSTER` Ingress |
| Phoenix URL | `PUBLIC_PHOENIX_URL`, `PHOENIX_BASE_URL`, and `PHOENIX_API_BASE_URL` set to `https://phoenix-{{cluster}}.tail286401.ts.net` in `spoke-workloads-appset.yaml`; matching device-backed Phoenix Ingress |
| Tailscale policy | Device-backed app Ingresses register as Tailscale devices, not `svc:*` services. Reserve `policy.hujson` `autoApprovers.services` entries for real ProxyGroup/Tailscale Service hostnames. |
| Spoke Kubernetes API | `svc:dev-api-v2` / `svc:staging-api-v2` service-host approvals plus a `tag:spoke-api` Kubernetes grant to `tag:k8s` as `system:masters` |

If a promoted spoke fails because it is using ryzen/localhost hostnames or a hostname is missing from the tailnet, fix the declaration in stacks and let source-hydrator + Promoter reconcile it. Do not leave live Deployment patches behind.

If a promoted-spoke app hostname resolves as `<name>-1.tail286401.ts.net`, look for a stale tailnet `svc:<name>` Service or old offline device that is reserving the canonical name. Remove the stale tailnet record and remove the matching `svc:*` ACL entry from `policy.hujson` if the hostname is device-backed.

## Workflow-builder MCP/auth runtime

The workflow-builder MCP path is intentionally split between durable DB state, generated platform services, and per-agent runtime bootstrap:

```
app_connection + oauth_app + mcp_connection rows
    |
    | activepieces-mcps CronJob
    v
cluster-local Knative KServices
  ap-<piece>-service.workflow-builder.svc.cluster.local/mcp
    |
    |- activepieces-mcp-catalog ConfigMap for searchable/predefined MCP choices
    |
    `- piece-mcp-server containers that decrypt per-request credentials through
       workflow-builder's internal connection decrypt API

Agent publish / registry sync
    |
    v
AgentRuntime.spec.mcpServers
    |
    | agent-runtime-controller
    v
agent-runtime-<slug> Deployment
  DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON
    |
    v
dapr-agent-py loads tools and calls piece MCP with X-Connection-External-Id
```

Important boundaries:
- **Service discovery**: `activepieces-mcps` reconciles enabled `mcp_connection` rows and pinned pieces into Knative Services plus `activepieces-mcp-catalog`. Workflow-builder uses that catalog for search/predefined MCP server choices.
- **Auth**: OAuth credentials stay in workflow-builder app connection storage. Runtime MCP requests carry `X-Connection-External-Id`; `piece-mcp-server` calls the internal decrypt API. Do not put decrypted OAuth values into GitOps manifests or workflow JSON.
- **Networking**: callers use the Knative Service URL without `:3100`; the container port is hidden behind Knative.
- **Scale**: generated piece MCP services use `initialScale: "0"` and can cold-start. `knative-serving` must keep `allow-zero-initial-scale: "true"`.
- **Existing agents**: changing `mcp_connection` rows or catalog entries does not by itself rewrite an already-published `AgentRuntime`. Re-run registry sync/re-publish, then verify the runtime Deployment env.

## Dapr durable state for agents

Dapr durable workflows use actor state, and each sidecar must see exactly one `actorStateStore=true` Component.

| Component | Scope | Purpose |
|---|---|---|
| `workflowstatestore` | `workspace-runtime`, `workflow-orchestrator`, `swebench-coordinator` | Parent workflow/orchestrator durable state |
| `dapr-agent-py-statestore` | `dapr-agent-py` plus per-agent app ids enrolled by agent-runtime-controller | Shared durable state for sandboxed per-agent runtimes |

The agent-runtime controller mutates the shared `dapr-agent-py-statestore` `scopes` list when AgentRuntime CRs are created or updated. This keeps history centralized and avoids creating/deleting per-agent Dapr Components, while preserving Dapr's requirement that a sidecar has a single actor state store.

## Branch model

| Branch | Origin | Role |
|---|---|---|
| `main` | both `origin` (GitHub) and `gitea-ryzen` | Source of truth for all overlays. Two automated bumpers commit independently → branches drift |
| `env/hub-next` | `origin` only | Source-hydrator output for hub overlay. Promoter merges to `env/hub` |
| `env/hub` | `origin` only | What hub root-application syncs from |
| `env/spokes-dev-next` / `env/spokes-staging-next` | `origin` only | Source-hydrator output per spoke |
| `env/spokes-dev` / `env/spokes-staging` | `origin` only | What spoke ArgoCD apps sync from (`workflow-builder-release` PromotionStrategy promotes to these) |
| (no `env/spokes-ryzen-next`) | — | Ryzen does not go through promoter; spoke-workloads AppSet writes directly to `env/spokes-ryzen` |

Ryzen also has a local source branch split:

| Branch | Role |
|---|---|
| `gitea-ryzen/main` | Default branch used by ryzen child Applications and inner-loop image-pin commits |
| `gitea-ryzen/ryzen-main` | Branch tracked by the ryzen root Application; fast-forward this for root/child Application spec changes such as ignoreDifferences or new app resources |

## Hub self-management and GitOps Promoter

Hub changes follow the same GitOps shape as spoke changes, but with their own promotion strategy:

```
origin/main
   │
   │ root-application sourceHydrator
   ▼
env/hub-next
   │
   │ GitOps Promoter: stacks-environments
   ▼
env/hub
   │
   │ root-application sync source
   ▼
hub ArgoCD resources
```

`stacks-environments` is intentionally part of the normal path for hub changes. If a hub change is merged to `origin/main` but `root-application` is still reading an old `env/hub` commit, inspect `root-application.status.sourceHydrator`. A stale `currentOperation.drySHA` can pin hydration to an old source commit; clear the sourceHydrator status fields and hard-refresh before bypassing Promoter.

GitOps Promoter itself is managed by hub ArgoCD:
- `packages/components/hub-management/apps/gitops-promoter.yaml` deploys the Helm chart. The chart can lag the app release, so the current pattern is to keep the latest chart and override `manager.image.tag` when the latest app release is newer.
- `packages/components/hub-management/apps/gitops-promoter-config.yaml` applies PromotionStrategy, CommitStatus, inventory, and related config.
- `packages/components/hub-management/apps/argocd-gitops-promoter-ui.yaml` installs the Promoter ArgoCD UI extension and `argocd-cm` resource links/custom labels.
- `deployment/config/argocd-values.yaml` mirrors the UI extension settings for fresh/bootstrap ArgoCD installs.

As of 2026-04-24, the live controller is `quay.io/argoprojlabs/gitops-promoter:v0.27.1`. The latest Helm chart at that time is `0.6.0` with `appVersion: 0.26.2`, so the app release is selected with `manager.image.tag: v0.27.1`.

## Hub vs spoke app placement

Default placement policy:

- **Hub**: multi-cluster control plane, release automation, lifecycle automation, cross-cluster inventory/reporting, and shared operator UIs. Examples: ArgoCD, GitOps Promoter, hub Tekton outer-loop, Crossplane, deployment inventory, NocoDB, Redash, and any future shared Backstage/Keycloak deployment.
- **Spokes**: workload runtime and failure-domain-local infrastructure. Examples: workflow-builder runtime services, Dapr runtime, cert-manager, External Secrets Operator, Azure Workload Identity, CNI/ingress/storage, Tailscale resources needed for that cluster, and per-environment databases/caches/queues.
- **Ryzen-local**: local development velocity and KIND-only services. Examples: local Gitea registry, DevSpace/hot-reload flow, workstation-only build helpers, and KIND-specific integrations.

If production traffic depends on a service during hub outage, keep it per-spoke. If operators use it to manage multiple clusters, centralize it on hub and add spoke agents/access only where needed. See `reference/app-placement.md`.

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
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` | dev/staging release metadata: tags, digests, image refs, source SHAs, PipelineRuns |
| `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` | Matrix AppSet generator + Kustomize patches per spoke, including promoted-spoke MCP/Phoenix runtime env |
| `packages/base/manifests/tailscale-ingresses/` | Shared device-backed Tailscale Ingresses with `*-CLUSTER` placeholders for dev/staging/talos app hostnames |
| `packages/components/active-development/manifests/activepieces-mcps/` | CronJob/RBAC/script that turns workflow-builder DB `mcp_connection` rows into piece MCP Knative Services and catalog entries |
| `packages/base/manifests/knative-serving/kustomization.yaml` | Knative Serving and autoscaler settings, including `allow-zero-initial-scale` for piece MCP scale-to-zero |
| `packages/components/hub-management/manifests/gitops-promoter/PromotionStrategy-workflow-builder-release.yaml` | dev → staging promotion (autoMerge true; gates: argocd-health + timer) |
| `packages/components/hub-management/manifests/gitops-promoter/TimedCommitStatus-workflow-builder-soak.yaml` | timer gate (`dev=0s`, `staging=10m`) |
| `packages/components/hub-management/manifests/gitops-promoter/gitops-deployment-inventory.yaml` | Hub inventory API consumed by workflow-builder admin Deployments |
| `packages/components/active-development/manifests/workflow-builder/Service-gitops-inventory-hub-egress.yaml` | Spoke egress Service for inventory; points to `gitops-inventory-hub-node.tail286401.ts.net:8080` |
| `packages/components/active-development/manifests/workflow-builder/Component-workflowstatestore.yaml` | Parent workflow Dapr actor state store |
| `packages/components/active-development/manifests/openshell-agent-runtime/Component-dapr-agent-py-statestore.yaml` | Shared per-agent Dapr actor state store |
| `packages/components/active-development/apps/workflow-builder.yaml` | Workflow-builder Argo app spec, including ignoreDifferences for operator-mutated egress Service fields |
| `packages/base/manifests/agent-sandbox-crds/` | Required OpenShell/agent-runtime CRDs: `AgentRuntime`, `Sandbox`, `SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool`. Do not remove as duplicate. |
| `packages/components/hub-management/apps/gitops-promoter.yaml` | Promoter Helm chart app plus image tag override when chart appVersion lags |
| `packages/components/hub-management/apps/argocd-gitops-promoter-ui.yaml` | ArgoCD app that manages the Promoter UI extension patch resources |
| `packages/components/hub-management/manifests/argocd-gitops-promoter-ui/` | UI extension initContainer patch Job, RBAC, and ArgoCD resource links |
| `deployment/config/argocd-values.yaml` | Bootstrap ArgoCD values; keep Promoter UI extension config synchronized here |
| `packages/components/active-development/manifests/<image>/kustomization.yaml` | ryzen image-pin per workload |
| `packages/components/hub-tekton/manifests/outer-loop-builds/` | Hub Tekton pipeline + EventListener |
| `packages/components/hub-tekton/manifests/workflow-builder-builds/` | Inner-loop pipeline definitions |
| `scripts/gitops/validate-workflow-builder-release-pins.sh` | Validates release-pin schema and GHCR tag/digest existence |
| `scripts/gitops/check-branch-drift.sh` | Checks origin/gitea-ryzen main and ryzen-main alignment |
| `docs/hub-spoke-app-placement.md` | Hub-vs-spoke app placement policy |
| `policy.hujson` | Tailscale ACL — synced via `.github/workflows/tailscale-acl.yml`; `svc:*` approvals are only for real service-host/ProxyGroup/Tailscale Services |

For the original full architecture write-up (covers DevSpace, OpenShell, Dapr workflows), see `docs/gitops-architecture-overview.md` and `docs/outer-loop-promotion.md` in the stacks repo.
