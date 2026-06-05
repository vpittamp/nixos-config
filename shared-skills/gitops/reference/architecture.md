# Architecture: hub + spokes, release pins, and ryzen affected sync

## Cluster roles

```
                         ┌─────────────────────────────────────────────┐
                         │  HUB (Talos on Hetzner)                       │
                         │  - Single ArgoCD (manages itself + spokes)   │
                         │  - Hub Tekton (GHCR outer-loop builds)       │
                         │  - GitOps Promoter + ArgoCD Promoter UI      │
                         │  - Crossplane (spoke lifecycle)              │
                         │  - ExternalSecrets Operator                  │
                         │  - Tailscale operator (ProxyGroups, Funnel)  │
                         └─────────────────────────────────────────────┘
                                  │  cluster Secrets in argocd ns
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
        ┌─────────┐         ┌─────────┐         ┌──────────────┐
        │   dev   │         │ staging │         │    ryzen     │
        │ (Talos, │         │ (Talos, │         │ (Talos-in-   │
        │ Hetzner)│         │ Hetzner)│         │  Docker on   │
        └─────────┘         └─────────┘         │  user's      │
                                                │  workstation;│
                                                │  hub-managed │
                                                │  spoke)      │
                                                └──────────────┘
```

`hcloud server list` (context `stacks`):
- hub: `hub-cp-1..3` control/management nodes and `hub-build-1..2` dedicated Tekton build workers on `hub-cluster-net` (10.1.1.0/24)
- dev: `dev-cp-1/2/3` (178.156.225.243, .239.75, .226.121), `dev-worker-1/2` on `dev-network` (10.0.1.0/24)
- staging: `staging-cp-1/2/3`, `staging-worker-1/2` on `staging-network`

ryzen is the user's local workstation (`hostname` returns `ryzen`). The Talos-in-Docker cluster (formerly kind; bootstrapped imperatively by `deployment/scripts/bootstrap-spoke-cluster.sh`, **not** Crossplane-provisioned like dev/staging) is enrolled with the hub ArgoCD principal as an AUTONOMOUS agent. **Ryzen HAS its OWN local ArgoCD** (reconciles its own apps), and has NO local Gitea and NO idpbuilder (GitHub + GHCR only). The `ryzen-*` Applications are rendered by ryzen's LOCAL `root-ryzen` app-of-apps from `packages/overlays/ryzen` @ `main` and live on ryzen's cluster (NOT on the hub — the hub only sees a push-mirrored status in ns `ryzen`). dev is now SCRIPT-provisioned + enrolled (Crossplane `TalosSpokeClusterClaim` removed in Phase D); ryzen is imperative.

**Recreate-automation entry points (named scripts):**
- **dev:** `deployment/scripts/talos-hetzner/recreate-dev.sh` — ORCHESTRATOR wrapping data backup/restore (`environment_image_builds`/agents/workflows) + `provision-spoke.sh` + `bootstrap-spoke-deps.sh` + `argocd-agent/enroll-dev-agent.sh` + the verify gate.
- **ryzen:** `deployment/scripts/bootstrap-spoke-cluster.sh --recreate` — enrolls the autonomous agent via `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh` + the `packages/components/hub-management/manifests/ryzen-agent-bootstrap` kustomize component (`argocd-agentctl agent create ryzen` writes the `cluster-ryzen` agent mapping). `register-spoke-with-hub.sh` is RETIRED/uncalled; `--ts-acl-mode` / `--ts-host-passthrough` are vestigial flags.

> **Recreate-hardening notes (PR #2395).** `bootstrap-spoke-cluster.sh` is STANDALONE — it does NOT source `deployment/scripts/lib/common.sh`, so any var it shares with common.sh must be self-defaulted; e.g. `TS_OPERATOR_CHART_VERSION="${TS_OPERATOR_CHART_VERSION:-1.96.5}"` (~line 125, kept in lockstep with common.sh + the GitOps tailscale-operator manifests) — an unbound abort under `set -u` previously left ryzen DOWN post-destroy. On a fresh recreate the local controller compares `root-ryzen` before the local repo-server is up, so `enroll-ryzen-agent.sh` step 6b waits on `argocd-repo-server` then hard-refreshes `root-ryzen`, and `bootstrap-spoke-cluster.sh` step 10 hard-refreshes again (re-compare vs the latest `main` HEAD; avoids a ~5min cold-start convergence stall; both non-fatal). Full detail in `cluster-desired-state/runbooks/recovery-and-gotchas.md`.
- **hub:** `deployment/scripts/recreate-hub.sh` (modes `--verify-only` / `--seed-secret` / `--fixups` / `--dry-run-clone` / `--in-place --confirm-wipe hub-cluster`; never hcloud-deletes the 5 ash servers; `--in-place` is a rolling `talosctl reset` reusing `talos-cluster/main/secrets/hub-secrets.yaml`; bootstraps `onepassword-sa-token` via `op read`, NOT JWKS) + `deployment/scripts/hub-verify-gate.sh` (9-check read-only convergence gate) + the self-healing `kube-system-fixups` CronJob (`packages/components/hub-management/manifests/kube-system-fixups/`) re-applying the Flannel `--iface` + CoreDNS anti-affinity patches Talos drops.

For the full ordered recreate path see the `cluster-desired-state` skill.

## Hub build lane, image pins, and ryzen sync

This is **the** mental model for this system. The same workflow-builder base manifests at `packages/components/workloads/workflow-builder/manifests/` are used by all three spokes, but the image tags come from **different files**:

```
GitHub push to PittampalliOrg/workflow-builder
    │
    │  webhook (Tailscale Funnel: tekton-hub.tail286401.ts.net)
    ▼
┌──────────────────────────────────────────────┐
│  HUB TEKTON outer-loop pipeline               │
│  - Build with Buildah                         │
│  - Push to ghcr.io/pittampalliorg/<img>:git-… │
│  - Push release metadata or open release PR   │
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
│    pinning ghcr.io/pittampalliorg/<svc> tags  │
└──────────────────────────────────────────────┘
    │
    │  source-hydrator renders to env/spokes-{spoke}-next
    ▼
┌──────────────────────────────────────────────┐
│  GitOps Promoter (workflow-builder-release)   │
│  - Gates on argocd-health + timer statuses    │
│  - autoMerge true: dev immediate               │
│  - Promotes env/spokes-{spoke}-next →         │
│    env/spokes-{spoke}                         │
└──────────────────────────────────────────────┘

> **Staging is dormant (no staging cluster, 2026-06).** `workflow-builder-release`
> promotes to **dev only** — the `env/spokes-staging` env + its `10m` soak were
> removed (stacks PR #2436) and the outer-loop renders dev-only (PR #2437). The box
> above describes the mechanism that remains for dev; ryzen is off the Promoter path
> entirely (direct `main`). Net promotion model: **ryzen + dev**. Re-add the staging
> env to the PromotionStrategy + soak to restore.
    │
    ▼
Hub ArgoCD syncs spoke apps from env/spokes-{spoke}
   → manifests applied to dev / staging cluster

============================================================

ryzen autonomous-agent sync (local ArgoCD reconciles main directly)
    │
    │  edit stacks worktree → commit/merge to main on GitHub
    ▼
┌──────────────────────────────────────────────┐
│  ryzen LOCAL ArgoCD (root-ryzen @ main)        │
│  - Reconciles packages/overlays/ryzen @ main   │
│    DIRECTLY (live kustomize, no hydrator)      │
│  - No Promoter, no env/spokes-ryzen branch     │
│  - Renders ryzen-* Apps onto ryzen's cluster   │
│  - Agent push-mirrors status UP to hub ns ryzen│
└──────────────────────────────────────────────┘
    │
    ▼
ryzen Talos-docker cluster (HAS its own local ArgoCD)
```

**Key implications:**
- A bump validated on ryzen does **not** automatically propagate to dev/staging. Ryzen reconciles `main` directly; dev/staging consume the same image via release-pins (hub Tekton `update-stacks` writing `release-pins/workflow-builder-images.yaml` on `main`) + their Promoter step.
- A tag/digest bumped to dev/staging via release-pins **must already exist on `ghcr.io`**. Outer-loop normally builds it and records the digest/provenance in the release metadata.
- `release-pins/workflow-builder-images.yaml` is schema v2: `images` remains the compatibility tag map; `digests`, `imageRefs`, `sourceShas`, `pipelineRuns`, and `updatedAts` hold immutable/provenance metadata. Dev/staging templates render tag+digest refs when a digest is present.
- `agent-runtime-controller` is the exception: bumped directly in `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` (no per-cluster override). Single bump applies to all spokes once on `origin/main`.
- Spokes should not run Buildah for this path. If a `workflow-builder-builds-local` or spoke `gitea-builds-egress` resource appears, treat it as stale until proven otherwise.

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
| workflow-builder app URL | Tailscale **L4 LoadBalancer** Service `workflow-builder-CLUSTER` + in-cluster `tls-terminator` sidecar (PR #2319). NOT an Ingress, NO Let's Encrypt. `https://workflow-builder-{{cluster}}.tail286401.ts.net`. See "Tailnet web HTTPS" below. |
| MCP gateway URL | In-cluster only (PR #2319): `MCP_GATEWAY_BASE_URL=http://mcp-gateway.workflow-builder.svc.cluster.local:8080`. The old `mcp-gateway-CLUSTER` Tailscale Ingress was removed (dev/staging overlays `$patch:delete` it). |
| Phoenix URL | `PUBLIC_PHOENIX_URL`, `PHOENIX_BASE_URL`, and `PHOENIX_API_BASE_URL` set to `https://phoenix-{{cluster}}.tail286401.ts.net` in `spoke-workloads-appset.yaml`; matching device-backed Phoenix Ingress |
| Tailscale policy | Device-backed app Ingresses (e.g. `phoenix-*`) register as Tailscale devices, not `svc:*` services. Reserve `policy.hujson` `autoApprovers.services` entries for real ProxyGroup/Tailscale Service hostnames. |
| Spoke Kubernetes API | `svc:dev-api-v2` / `svc:staging-api-v2` service-host approvals plus a `tag:spoke-api` Kubernetes grant to `tag:k8s` as `system:masters` |

### Tailnet web HTTPS: L4 LoadBalancer + self-signed CA (PR #2319)

`workflow-builder` was migrated off the per-hostname **Let's Encrypt** Tailscale Ingress (ProxyClass `development-prod-cert`) because recreate churn exhausted LE's 5-certs/168h limit → 429 → unreachable. (ryzen also briefly used a plain-HTTP Tailscale LoadBalancer, PRs #2314/#2316 — also superseded.) The uniform replacement:

- A Tailscale **L4 LoadBalancer Service** (`type: LoadBalancer`, `loadBalancerClass: tailscale`, `tailscale.com/hostname`) advertises the device and forwards `443` → the pod's `https-tls` port. No LE.
- HTTPS is terminated **in-cluster** by a per-pod nginx `tls-terminator` sidecar serving a persistent self-signed wildcard `*.tail286401.ts.net`.
- Manifests: base `packages/base/manifests/tailscale-ingresses/Service-workflow-builder-tailnet.yaml` (dev/staging, CLUSTER-templated); ryzen `packages/components/workloads/workflow-builder-tailnet-lb/`; sidecar + `ConfigMap-workflow-builder-tls-terminator.yaml` + `Certificate-tailnet-wildcard.yaml` under `packages/components/workloads/workflow-builder/manifests/`.

This rides on a **new cross-cutting contract: a persistent self-signed CA** (alongside the cluster-Secret and spoke-transport contracts):

- A self-signed CA **"PittampalliOrg Tailnet Dev CA"** was generated once (offline) as `TAILNET-DEV-CA-CRT` / `TAILNET-DEV-CA-KEY` (10-year, stable across cluster recreation). It now lives in the `hub-eso` 1Password vault (the Azure KV copy is dormant after the 2026-06 AWI → 1Password migration).
- The hub mirrors it **cluster-neutrally** into ns `spoke-secrets` Secret `tailnet-ca` (`packages/components/hub-management/manifests/spoke-secrets/ExternalSecret-tailnet-ca.yaml`); that hub spoke-secrets ExternalSecret now reads from the `onepassword-store` ClusterSecretStore (not `azure-keyvault-store`). The namespace-wide `spoke-secrets-reader` Role means every spoke reads the SAME key — no per-cluster key.
- New spoke base app `packages/components/tailnet-ca` (delivered via `packages/base/apps/tailnet-ca.yaml`, **spoke-only** — the hub does not consume `packages/base`): an ExternalSecret (`hub-secrets-store`) restores the CA into `cert-manager/tailnet-dev-ca`; the `tailnet-dev-ca` CA `ClusterIssuer` signs the `*.tail286401.ts.net` wildcard Certificate consumed by the tls-terminator sidecar.
- Because the CA is identical on every cluster, clients trust it once and the trust survives recreation. Workstation trust is in nixos-config commit `44ba6324` (system/curl/git + a Chrome NSS seed, which is REQUIRED on NixOS because `security.pki` does not cover Chrome). PR #2322 adds `ignoreDifferences` so the cert/CA material doesn't show as drift.

If a promoted spoke fails because it is using ryzen/localhost hostnames or a hostname is missing from the tailnet, fix the declaration in stacks and let source-hydrator + Promoter reconcile it. Do not leave live Deployment patches behind.

If a promoted-spoke app hostname resolves as `<name>-1.tail286401.ts.net`, look for a stale tailnet `svc:<name>` Service or old offline device that is reserving the canonical name. Remove the stale tailnet record and remove the matching `svc:*` ACL entry from `policy.hujson` if the hostname is device-backed. The hard on-recreate guarantee against `-N` collisions is the gated `deployment/scripts/cleanup-tailnet-devices.sh` run pre-recreate; as a hygiene backstop the hub CronJob `tailnet-device-sweeper` (ns `tailscale`, every 15m, PRs #2322/#2325) deletes OFFLINE stale spoke devices (`lastSeen > 30m`, best-effort, matched by MagicDNS `name` because the device `hostname` field drops the `-N` suffix). `lastSeen` is a reliable liveness signal. An in-Composition pre-onboarding cleanup was deliberately NOT built (a function-pipeline error would halt ALL spoke provisioning).

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
| `workflowstatestore` | namespace-wide in `workflow-builder` | Shared Dapr workflow/actor durable state for parent workflows, child session workflows, timers, reminders, and activity bookkeeping |
| `dapr-agent-py-statestore` | namespace-wide in `workflow-builder` | Non-actor agent application state APIs and task-output state |

Per-session Kueue agent hosts use unique Dapr app IDs, so Component scope mutation is intentionally avoided. Keep `workflowstatestore` as the only `actorStateStore=true` Component visible to workflow-enabled sidecars, and keep `dapr-agent-py-statestore` at `actorStateStore=false`.

## Source-hydrator + GitOps Promoter flow (the generic shape)

Every environment follows the same three-stage GitOps shape. Argo CD's **source-hydrator** renders an overlay/component on a **dry source** branch into a **hydrated** branch; **GitOps Promoter** opens a PR from the `-next` hydrated branch to the live env branch; Argo CD syncs the live env branch.

```
drySource (overlay on main)
    │  Argo CD source-hydrator renders kustomize → plain manifests
    ▼
hydrateTo  env/<env>-next            (the "-next" staging branch)
    │  GitOps Promoter ChangeTransferPolicy + PromotionStrategy
    │  opens a PR  env/<env>-next → env/<env>   (gated by commit statuses)
    ▼
syncSource env/<env>                 (the branch Argo CD actually syncs)
    │  Argo CD Application sync
    ▼
live cluster resources
```

Two important exceptions to the `-next` → Promoter-PR → live shape:
- **ryzen is NOT on this shape at all.** It runs its OWN local ArgoCD and reconciles `packages/overlays/ryzen` @ `main` DIRECTLY — no source-hydrator, no `env/spokes-ryzen`, no Promoter. See the ryzen branch note below.
- **dev/staging workload-layer** apps that source `packages/components/workloads/*/manifests/` at `origin/main` `HEAD` are not promoter-gated for that path; only the `workflow-builder-system-overlays/<spoke>` render goes through `env/spokes-<spoke>-next` → `env/spokes-<spoke>`.

## Branch model

| Branch | Origin | drySource → hydrateTo → syncSource role |
|---|---|---|
| `main` | `origin` (GitHub) | Dry source for hub + dev/staging overlays, AND the branch ryzen's local ArgoCD reconciles `packages/overlays/ryzen` from directly. Source of truth for promoted overlays, release metadata, and all-cluster delivery |
| `env/hub-next` | `origin` only | Source-hydrator output (`hydrateTo`) for `packages/overlays/hub`. `stacks-environments` PromotionStrategy PRs it to `env/hub` (**`autoMerge: false` — manual merge required**) |
| `env/hub` | `origin` only | `syncSource` (path `hub-apps`) that hub `root-application` syncs from |
| `env/spokes-dev-next` / `env/spokes-staging-next` | `origin` only | Source-hydrator output (`hydrateTo`) for `packages/overlays/{dev,staging}` |
| `env/spokes-dev` / `env/spokes-staging` | `origin` only | `syncSource` (path `<spoke>-apps`) the spoke root Application syncs from. `workflow-builder-release` PromotionStrategy promotes the workflow-builder-system render to these |
(There is **no** `inner-loop` branch — RETIRED/deleted — and **no** `env/spokes-ryzen`. Ryzen reconciles `packages/overlays/ryzen` @ `main` via its own local ArgoCD; nothing hydrates a ryzen env branch.)

### Ryzen reconciles `main` DIRECTLY (no inner-loop, no Promoter)

**Pushing to `main` IS how content reaches ryzen.** Ryzen is an AUTONOMOUS argocd-agent: its LOCAL ArgoCD runs a `root-ryzen` app-of-apps that reconciles `packages/overlays/ryzen` @ `main` with live kustomize. To deploy `main`'s content to ryzen, just commit/merge to `main`; ryzen re-compares on its next poll, or force it immediately:

```bash
deployment/scripts/ryzen-sync.sh   # hard-refreshes root-ryzen (~20-35s converge)
# or: kubectl --context admin@ryzen -n argocd annotate application root-ryzen argocd.argoproj.io/refresh=hard --overwrite
```

`commit-pin.sh` likewise just commits image-tag bumps to `main`. There is NO source-hydrator, NO `env/spokes-ryzen`, NO Promoter on the ryzen lane, so the empty-`drySource.kustomize` hydrator-stall bug does NOT apply — if a frozen ryzen, hard-refresh `root-ryzen`; don't look for an `inner-loop` advance.

Under argocd-agent v0.8.1 ryzen reconciles all 60+ ryzen-* Applications with its OWN local controller (autonomous agent); the hub principal aggregates status, and the agent dials the principal OUTBOUND (8443). The hub does NOT push kube-API syncs to ryzen and does NOT render ryzen's apps. The `cluster-ryzen` Secret is an AGENT MAPPING, not a kube-API endpoint; the legacy Tailscale-apiserver-proxy SNI path in "Hub → spoke ArgoCD connectivity" below is RETIRED for sync and survives ONLY for Headlamp.

## Control plane: argocd-agent v0.8.1

The fleet's control plane is **argocd-agent v0.8.1**. The hub runs the **principal** (single pane, ns `argocd`); each spoke runs a **local ArgoCD + an agent** that dials the principal **OUTBOUND** over tailnet mTLS (8443). **dev = MANAGED agent** (the hub authors Application objects in ns `dev` == the agent name; the principal pushes them to the dev agent; its local controller reconciles — observe via `kubectl -n dev get applications` on the hub). **ryzen = AUTONOMOUS agent** (reconciles its own apps; the hub aggregates status). Sync OPERATIONS run on the spoke's local controller, so the hub pane shows sync+health but NOT operation lifecycle — "Unknown operation status" on the hub is architectural/benign.

For cert-avoidance and the full Tailscale design, see `cluster-desired-state/references/tailscale-and-certs.md` (canonical home). For the end-to-end recreate path (provision → enroll → connectivity → workloads), see the `cluster-desired-state` skill.

## Spoke registration: the cluster-Secret contract + appsets

Spokes are registered on the hub by an Argo CD **cluster Secret** (label `argocd.argoproj.io/secret-type: cluster`) in the hub `argocd` namespace, and two ApplicationSets fan those Secrets out into Applications.

**Agent-mapping cluster Secret (current, for migrated spokes).** Under argocd-agent the `cluster-<spoke>` Secret is an **AGENT MAPPING**, not a direct kube-API endpoint: `server: https://argocd-agent-resource-proxy:9090?agentName=<spoke>` plus embedded mTLS `certData` / `keyData` / `caData` and **NO `bearerToken`**. This replaced the old direct-server + per-spoke-bearerToken shape (now LEGACY). The per-spoke mTLS cert is minted on the hub and delivered to the spoke over the ESO transport. NOTE: a Headlamp restart would otherwise drop all spokes because these mappings carry no bearerToken — Headlamp reads SEPARATE dedicated `headlamp.dev/cluster=true` Secrets (per-spoke real endpoint + read-only SA token + CA), not the argocd-agent mappings.

**Cluster-Secret contract** (`packages/components/hub-management/manifests/spoke-credentials/`):

| Field | Required value | Why |
|---|---|---|
| label `argocd.argoproj.io/secret-type` | `cluster` | Argo CD treats the Secret as a destination cluster |
| label `stacks.io/hub-managed` | `"true"` | Selected by both appsets |
| label `stacks.io/cluster-role` | `spoke` | Selected by both appsets |
| label `stacks.io/platform` | `talos` | Inventory/placement metadata |
| label `workload.stacks.io/workflow-builder` | `"true"` | **Opt-in** to `spoke-workloads-appset` (dev/staging set it; **ryzen OMITS it** — its overlay composes `workflow-builder-system` directly) |
| annotation `spoke-cluster` | `<name>` | Drives the templated Application name (`spoke-<name>`) and overlay path (`packages/overlays/<name>`) |
| annotation `stacks.io/source-branch` | unset = `main` (dev/staging) | Selects `drySource.targetRevision`. (Ryzen does NOT use this — it is not driven by the spoke-clusters appset; its local `root-ryzen` tracks `main`.) |
| `stringData.server` | migrated (agent): `https://argocd-agent-resource-proxy:9090?agentName=<spoke>` + embedded mTLS `certData`/`keyData`/`caData`, NO bearerToken. Legacy: a direct kube-API URL — see SNI note below | Where Argo CD connects / which agent the mapping targets |
| dev (legacy shape, now superseded by agent mapping) | server = **direct public IP** `https://<ip>:6443`, bearer token from a minted SA | Direct API reachable; no SNI workaround |
| ryzen (legacy shape) | server = `https://ryzen-operator.tail286401.ts.net`, `bearerToken: "unused"`, `auth-mode: tailscale-acl-impersonation` | Tailscale-apiserver-proxy + ACL impersonation; no token, no JWKS |

The direct-server + bearerToken Secret shapes above are LEGACY; migrated spokes use the agent-mapping shape (see "Control plane: argocd-agent v0.8.1" above). **dev is now SCRIPT-provisioned + enrolled** (`provision-spoke.sh` + `bootstrap-spoke-deps.sh` + `enroll-dev-agent.sh`) — Crossplane was removed in Phase D (no `TalosSpokeClusterClaim`, no group-N spoke-register). The enroll script mints the dev agent mTLS cert on the hub, delivers it via ESO, and creates `cluster-dev` as a `?agentName=dev` mapping. **ryzen's `cluster-ryzen`** is likewise an AGENT MAPPING written by `argocd-agentctl agent create ryzen` during `enroll-ryzen-agent.sh` (`server: https://argocd-agent-resource-proxy:9090?agentName=ryzen` + embedded mTLS, NO bearerToken). The old static `Secret-cluster-ryzen.yaml` (server `https://ryzen-operator...`) is LEGACY — retired for sync, kept for diagnostics only.

**The two ApplicationSets** (`packages/components/hub-spoke-appsets/apps/`):

- `spoke-clusters-appset.yaml` — `clusters` generator selecting the cluster-Secret labels above. Templates one **root** Application `spoke-<name>` per MANAGED spoke (dev/staging) with `sourceHydrator.drySource.path: packages/overlays/<name>`, `targetRevision` from the source-branch annotation, `hydrateTo: env/spokes-<name>-next`, `syncSource: env/spokes-<name>` path `<name>-apps`. This is the appset the hub actually uses for dev/staging. **Ryzen is NOT driven by this appset** — it reconciles `overlays/ryzen` @ `main` via its own local `root-ryzen`.
  - GOTCHA: there is a SECOND, unused `spoke-clusters-appset.yaml` under `packages/components/hub-base/apps/` that hardcodes `targetRevision: main` and has the buggy empty `kustomize: {}` (the hydrator-stall trap). The hub references only the `hub-spoke-appsets` copy via `packages/overlays/hub/kustomization.yaml`. **Edit the `hub-spoke-appsets` copy, not `hub-base`.**
- `spoke-workloads-appset.yaml` — adds the `workload.stacks.io/workflow-builder=true` selector; generates `spoke-<name>-workflow-builder` from `packages/components/workloads/workflow-builder-system-overlays/<name>`. dev/staging opt in; ryzen does not.

## Hub → spoke kube-API reach (RETIRED for sync — Headlamp-only)

**This whole section is RETIRED as the ArgoCD sync path under argocd-agent v0.8.1.** Spokes reconcile locally and dial the hub principal OUTBOUND (8443); the hub no longer pushes kube-API syncs. The hub→spoke kube endpoint now survives ONLY for **Headlamp** (read via the dedicated `headlamp.dev/cluster=true` Secret, not the `cluster-<spoke>` agent mapping), and ryzen also serves a host raw-TCP `tailscale serve --tcp=6443` passthrough for that. The SNI mechanics below remain accurate for that Headlamp path and as historical context; they no longer gate any Application sync.

dev/staging expose a **direct public kube-API** (`https://<ip>:6443`), so a Headlamp cluster Secret just points at the IP — no SNI workaround.

**ryzen has no public API; it's reached through the spoke Tailscale operator's apiserver-proxy**, and the proxy (Tailscale operator **v1.92.4+**) **STRICTLY validates the wire TLS SNI** — it only accepts its own hostname (`ryzen-operator.tail286401.ts.net`), otherwise returns `500 Internal Server Error: invalid domain ... must be one of [ryzen-operator.tail286401.ts.net]`.

The catch (verified 2026-05-29): **Argo CD does NOT send `tlsClientConfig.serverName` as the wire SNI.** Setting `serverName` (even with `caData`) still sends the *server-URL host* as the SNI. So the SNI must come from the server URL host itself. The fix is two co-operating pieces:

1. **`cluster-ryzen` Secret** `stringData.server: https://ryzen-operator.tail286401.ts.net` (the correct SNI lives in the URL host). `config` carries `tlsClientConfig.insecure: true` + `serverName: ryzen-operator.tail286401.ts.net` + `bearerToken: "unused"`.
2. **Hub CoreDNS rewrite** so that name resolves to the in-cluster egress while the SNI stays correct:
   ```
   rewrite name exact ryzen-operator.tail286401.ts.net ryzen-api-egress.tailscale.svc.cluster.local
   ```
   The `ryzen-api-egress` `ExternalName` Service (ns `tailscale`, `annotation tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net`, port 443) is defined inline in `packages/components/hub-management/apps/headlamp.yaml`.

The spoke operator must run with `OPERATOR_HOSTNAME=ryzen-operator` + `APISERVER_PROXY=true` + `PROXY_TAGS=tag:k8s` (so the proxy listens on 443). The ACL grant authorizing the hop is `policy.hujson` `src tag:k8s → dst tag:k8s-operator` `app tailscale.com/cap/kubernetes` `impersonate.groups: [system:masters]`.

After a ryzen recreate, a **stale duplicate `ryzen-operator` tailnet device** lingers (the new operator registers as `ryzen-operator-1`, breaking the SNI match). Delete the stale device via the Tailscale API (token minted from the operator-oauth Secret). Verify the path end-to-end by forcing the SNI:
```bash
curl --connect-to ryzen-operator.tail286401.ts.net:443:<egress-ip>:443 \
  https://ryzen-operator.tail286401.ts.net/version -k    # expect HTTP 200
```

This is distinct from the **ryzen → hub** ESO secret-fetch path (a different device `k8s-api-hub-ingress.tail286401.ts.net` + a RYZEN-side CoreDNS rewrite); do not conflate the two. See `reference/secret-flow.md`.

Latency reports come from `deployment/scripts/benchmark-ryzen-hot-edit.sh`. Use `BENCHMARK_PURPOSE=normal|manual|threshold-test` and `BENCHMARK_CASE=child-service|app-definition|dependency-file`; `ryzen-hot-loop-summary.sh` defaults to normal successful reports and requires `--purpose all --include-failures` to include deliberate threshold tests.

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
- **Spokes**: workload runtime and failure-domain-local infrastructure. Examples: workflow-builder runtime services, Dapr runtime, cert-manager, External Secrets Operator (resolving the **`hub-secrets-store`** ClusterSecretStore over Tailscale, NOT Azure Workload Identity), CNI/ingress/storage, Tailscale resources needed for that cluster, and per-environment databases/caches/queues. **The hub secret root migrated AWI → 1Password (2026-06):** the hub's 21 ExternalSecrets resolve from the `onepassword-store` ClusterSecretStore (ESO `onepasswordSDK` provider → the dedicated `hub-eso` 1Password vault); the old Azure KV + AD App + OIDC/JWKS federation are DORMANT (not deleted). Spokes are UNAFFECTED — they read hub-mirrored secrets via the ESO kubernetes-provider `hub-secrets-store` ClusterSecretStore over Tailscale regardless of how the hub populates its k8s Secrets. See `reference/secret-flow.md`.
- **Ryzen-local**: developer-workstation paths — Skaffold inner-loop hot reload (HMR sync into a running pod via local kubeconfig) and ryzen's OWN local ArgoCD reconciling `overlays/ryzen` @ `main`. Local Gitea/Tekton are retired (GitHub + GHCR only); ryzen DOES run a local ArgoCD (autonomous agent).

If production traffic depends on a service during hub outage, keep it per-spoke. If operators use it to manage multiple clusters, centralize it on hub and add spoke agents/access only where needed. See `reference/app-placement.md`.

## Why ryzen is special

Ryzen exists for **fast iteration** — it's the bleeding-edge "instant `main` mirror" dev sandbox. It's intentionally outside the Promoter chain:
- ryzen uses local Skaffold (`bash scripts/skaffold-dev.sh`) for live source iteration
- ryzen reconciles `overlays/ryzen` @ `main` DIRECTLY via its own local ArgoCD; manifest changes (incl. image-tag bumps via `commit-pin.sh`) land on `main` and ryzen picks them up immediately (no `inner-loop`, no source-hydrator, no Promoter)
- Dev/staging consume the same `main` content via their own release-pins + Promoter outer-loop path
- ryzen stays AUTONOMOUS (not managed) deliberately: managed mode would clobber the Skaffold `skip-reconcile` pause (the principal reverts foreign Application mutations) and lose hub-down resilience

**Why `commit-pin.sh` renders the ryzen image Component LOCALLY (not via webhook) — argocd-agent relay finding (v0.8.1, verified empirically).** There is NO inbound webhook path to ryzen: as an AUTONOMOUS agent it has no `argocd-server` (so no `/api/webhook`), AND the principal does NOT relay a refresh to autonomous agents on v0.8.1 (live test: a hub-side `argocd.argoproj.io/refresh` annotation on the ryzen mirror NEVER reached the spoke). So the only fast path is the SPOKE-LOCAL refresh `commit-pin.sh` itself issues after its local render — ryzen converges in seconds. (An argocd-agent code-read suggests #447/v0.2.0 SHOULD enable autonomous refresh, but it did NOT reproduce live — trust the live behavior; cause unresolved.) By contrast the MANAGED `dev` agent relay WORKS: a hub-side refresh annotation reached the dev agent and reconciled in ~3s.

**Dev hydration webhook (stacks PR #2449).** The `spoke-workloads` ApplicationSet hydrator template now stamps `argocd.argoproj.io/manifest-generate-paths` pointing at each spoke's dry-source overlay (`packages/components/workloads/workflow-builder-system-overlays/<spoke>`). Without it, a release-pin render into that overlay did NOT fire hydration on the hub's git webhook (`argocd-webhook-hub` `/api/webhook`) — it waited ~120s for ArgoCD's hydrator poll. The hydrator app (`spoke-dev-workflow-builder`) is HUB-reconciled (ns `argocd`), so the webhook drives it directly with no agent relay. ryzen is unaffected (sourced by `root-ryzen`, not this appset).

> The 3 GitHub webhooks are all HUB-FACING (Tailscale Funnel): `tekton-hub` (build EventListener), `argocd-webhook-hub` (`/api/webhook`), `gitops-promoter-webhook-hub`. None reaches a spoke directly.

ryzen **proves the stack works in the local platform shape**. The outer-loop **proves the release artifact and rendered manifests are promotable**. Those are different validations.

## File-level entry points

| Path | What's there |
|---|---|
| `packages/overlays/hub` | Hub overlay; sourceHydrator drySource for root-application |
| `packages/overlays/{dev,staging,ryzen}` | Per-spoke base overlay |
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` | dev/staging release metadata: tags, digests, image refs, source SHAs, PipelineRuns |
| `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` | Matrix AppSet generator + Kustomize patches per spoke, including promoted-spoke MCP/Phoenix runtime env |
| `packages/base/manifests/tailscale-ingresses/` | Shared `*-CLUSTER`-placeholder tailnet exposures for dev/staging/talos app hostnames: device-backed Tailscale Ingresses (e.g. `phoenix-*`) plus the workflow-builder L4 LoadBalancer `Service-workflow-builder-tailnet.yaml` (PR #2319) |
| `packages/components/workloads/activepieces-mcps/manifests/` | CronJob/RBAC/script that turns workflow-builder DB `mcp_connection` rows into piece MCP Knative Services and catalog entries |
| `packages/base/manifests/knative-serving/kustomization.yaml` | Knative Serving and autoscaler settings, including `allow-zero-initial-scale` for piece MCP scale-to-zero |
| `packages/components/hub-management/manifests/gitops-promoter/PromotionStrategy-workflow-builder-release.yaml` | dev → staging promotion (autoMerge true; gates: argocd-health + timer) |
| `packages/components/hub-management/manifests/gitops-promoter/TimedCommitStatus-workflow-builder-soak.yaml` | timer gate (`dev=0s`, `staging=10m`) |
| `packages/components/hub-management/manifests/gitops-promoter/gitops-deployment-inventory.yaml` | Hub inventory API consumed by workflow-builder admin Deployments |
| `packages/components/workloads/workflow-builder/manifests/Service-gitops-inventory-hub-egress.yaml` | Spoke egress Service for inventory; points to `gitops-inventory-hub-node.tail286401.ts.net:8080` |
| `packages/components/workloads/workflow-builder/manifests/Component-workflowstatestore.yaml` | Namespace-wide Dapr workflow/actor state store |
| `packages/components/workloads/workflow-builder/manifests/Component-dapr-agent-py-statestore.yaml` | Namespace-wide non-actor agent application state store |
| `packages/components/workloads/workflow-builder/Application-workflow-builder.yaml` | Workflow-builder Argo app spec, including ignoreDifferences for operator-mutated egress Service fields |
| `packages/base/manifests/agent-sandbox-crds/` | Required OpenShell/agent-runtime CRDs: `AgentRuntime`, `Sandbox`, `SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool`. Do not remove as duplicate. |
| `packages/components/hub-management/apps/gitops-promoter.yaml` | Promoter Helm chart app plus image tag override when chart appVersion lags |
| `packages/components/hub-management/apps/argocd-gitops-promoter-ui.yaml` | ArgoCD app that manages the Promoter UI extension patch resources |
| `packages/components/hub-management/manifests/argocd-gitops-promoter-ui/` | UI extension initContainer patch Job, RBAC, and ArgoCD resource links |
| `deployment/config/argocd-values.yaml` | Bootstrap ArgoCD values; keep Promoter UI extension config synchronized here |
| `packages/components/workloads/<image>/manifests/kustomization.yaml` | ryzen image-pin per workload (bare `newTag`, edited directly by `commit-pin.sh`) — for `workflow-orchestrator`/`function-router`/`mcp-gateway`. **NOT for `workflow-builder`/`workflow-mcp-server`** — their bare `images:` block was deleted (stacks #2443); see the two entries below |
| `packages/components/workloads/workflow-builder-ryzen-image/kustomization.yaml` | Render-generated kustomize **Component** carrying the ryzen `workflow-builder` + `workflow-mcp-server` image pin. The `workflow-builder/manifests/kustomization.yaml` `components:`-includes it, so it IS ryzen's effective pin. **`commit-pin.sh` renders + commits it LOCALLY** (deterministic, verified byte-identical to CI) in the same push as the flat pins file (wfb PR #37); `render-ryzen-image.yml` CI is now just a DRIFT-CORRECTION net that re-renders on push and commits only on a diff (no-ops when the local render already matched). Don't hand-edit |
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images-ryzen.yaml` | Flat ryzen pins file (images/imageRefs/digests/sourceShas) that `commit-pin.sh` UPSERTs for `workflow-builder`/`workflow-mcp-server`; in the SAME push `commit-pin.sh` ALSO renders the Component above locally (`WFB_RENDER_ENVS=ryzen scripts/gitops/render-workflow-builder-release-overlays.sh`) and `refresh=hard`es the ryzen spoke-local app, so ryzen reconciles in seconds — no CI/poll wait. `render-ryzen-image.yml` is the drift-correction safety net |
| `packages/components/hub-tekton/manifests/outer-loop-builds/` | Hub Tekton pipeline + EventListener |
| `packages/components/hub-tekton/manifests/workflow-builder-builds/` | Workflow-builder build pipeline definitions |
| `scripts/gitops/validate-workflow-builder-release-pins.sh` | Validates release-pin schema and GHCR tag/digest existence |
| `kubectl --context admin@ryzen -n argocd get applications` (or `app get root-ryzen`) | Inspect ryzen state on its OWN local ArgoCD — ryzen reconciles its own apps; the hub only sees a status mirror in ns `ryzen` |
| `docs/hub-spoke-app-placement.md` | Hub-vs-spoke app placement policy |
| `policy.hujson` | Tailscale ACL — synced via `.github/workflows/tailscale-acl.yml`; `svc:*` approvals are only for real service-host/ProxyGroup/Tailscale Services |

For the original full architecture write-up (covers OpenShell, Dapr workflows, and the (now-retired) DevSpace inner loop), see `docs/gitops-architecture-overview.md` and `docs/outer-loop-promotion.md` in the stacks repo.
