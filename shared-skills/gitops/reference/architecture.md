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

ryzen is the user's local workstation (`hostname` returns `ryzen`). The Talos-in-Docker cluster (formerly kind; bootstrapped imperatively by `deployment/scripts/bootstrap-spoke-cluster.sh`, **not** Crossplane-provisioned like dev/staging) is registered with the hub ArgoCD as cluster `ryzen`. **Post-A6 (May 2026): ryzen has NO local ArgoCD, NO local Gitea, and NO idpbuilder.** All ryzen-* Applications run on hub ArgoCD with `destination.name: ryzen`. dev/staging are Crossplane `TalosSpokeClusterClaim` spokes; ryzen is imperative.

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

Hub→ryzen spoke sync (post-A6, May 2026)
    │
    │  edit stacks worktree → commit to inner-loop branch on GitHub
    ▼
┌──────────────────────────────────────────────┐
│  Hub Source Hydrator                           │
│  - Polls GitHub inner-loop branch (~3 min)     │
│  - Hydrates to env/spokes-ryzen (no Promoter)  │
│  - Hub argocd-application-controller applies   │
│    to ryzen via cluster Secret + Tailscale     │
└──────────────────────────────────────────────┘
    │
    ▼
ryzen Talos-docker cluster (no local ArgoCD)
```

**Key implications:**
- A bump validated on ryzen does **not** propagate to dev/staging. Ryzen bumps live on `inner-loop`; dev/staging require a PR merge of `inner-loop → main` (or a direct main commit via the hub Tekton `update-stacks` task writing `release-pins/workflow-builder-images.yaml`).
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

- A self-signed CA **"PittampalliOrg Tailnet Dev CA"** was generated once (offline) and stored in Azure Key Vault as `TAILNET-DEV-CA-CRT` / `TAILNET-DEV-CA-KEY` (10-year, stable across cluster recreation — an improvement over idpbuilder, which regenerates per-install).
- The hub mirrors it **cluster-neutrally** into ns `spoke-secrets` Secret `tailnet-ca` (`packages/components/hub-management/manifests/spoke-secrets/ExternalSecret-tailnet-ca.yaml`). The namespace-wide `spoke-secrets-reader` Role means every spoke reads the SAME key — no per-cluster key.
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
drySource (overlay on main / inner-loop)
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
- **ryzen** hydrates **directly** to `env/spokes-ryzen` (no `-next`, no Promoter). See the ryzen branch note below.
- **dev/staging workload-layer** apps that source `packages/components/workloads/*/manifests/` at `origin/main` `HEAD` are not promoter-gated for that path; only the `workflow-builder-system-overlays/<spoke>` render goes through `env/spokes-<spoke>-next` → `env/spokes-<spoke>`.

## Branch model

| Branch | Origin | drySource → hydrateTo → syncSource role |
|---|---|---|
| `main` | `origin` (GitHub) | Dry source for hub + dev/staging overlays. Source of truth for promoted overlays, release metadata, and hub/dev/staging delivery |
| `env/hub-next` | `origin` only | Source-hydrator output (`hydrateTo`) for `packages/overlays/hub`. `stacks-environments` PromotionStrategy PRs it to `env/hub` (**`autoMerge: false` — manual merge required**) |
| `env/hub` | `origin` only | `syncSource` (path `hub-apps`) that hub `root-application` syncs from |
| `env/spokes-dev-next` / `env/spokes-staging-next` | `origin` only | Source-hydrator output (`hydrateTo`) for `packages/overlays/{dev,staging}` |
| `env/spokes-dev` / `env/spokes-staging` | `origin` only | `syncSource` (path `<spoke>-apps`) the spoke root Application syncs from. `workflow-builder-release` PromotionStrategy promotes the workflow-builder-system render to these |
| `inner-loop` | `origin` (GitHub) | **Ryzen's dry source.** Ryzen-only image-tag bumps via `commit-pin.sh`; the spoke-clusters ApplicationSet sets `targetRevision: inner-loop` for ryzen from its `stacks.io/source-branch` annotation |
| `env/spokes-ryzen` | `origin` (GitHub) | `syncSource` (path `ryzen-apps`) for ryzen. Hydrated **directly** from `inner-loop` (no `-next`, no Promoter step) |

### Ryzen reads `inner-loop`, NOT `main`

**Pushing to `main` alone NEVER reaches ryzen.** The `cluster-ryzen` Secret carries `annotation stacks.io/source-branch: inner-loop`, so spoke-clusters templates `spoke-ryzen` with `drySource.targetRevision: inner-loop`. To deploy `main`'s content to ryzen, fast-forward `inner-loop`:

```bash
git push origin origin/main:refs/heads/inner-loop   # clean FF when inner-loop is strictly behind main
```

After the push, source-hydrator re-dispatches the new dry SHA → renders `packages/overlays/ryzen` → pushes `env/spokes-ryzen`; the `ryzen-*` apps (sync from `env/spokes-ryzen` path `ryzen-apps`) reconcile. `commit-pin.sh` does the same push for ryzen-only image bumps. Do **not** mis-diagnose a frozen ryzen as the empty-`drySource.kustomize` hydrator-stall bug — `spoke-ryzen` is path-based (no `kustomize` field), so check `targetRevision`/`inner-loop` first.

Hub's argocd-application-controller applies all 60+ ryzen-* Applications to the ryzen cluster via the `cluster-ryzen` Secret in hub argocd ns. The kube-api connectivity for that is the Tailscale-apiserver-proxy SNI path described in "Hub → spoke ArgoCD connectivity" below.

## Spoke registration: the cluster-Secret contract + appsets

Spokes are registered on the hub by an Argo CD **cluster Secret** (label `argocd.argoproj.io/secret-type: cluster`) in the hub `argocd` namespace, and two ApplicationSets fan those Secrets out into Applications.

**Cluster-Secret contract** (`packages/components/hub-management/manifests/spoke-credentials/`):

| Field | Required value | Why |
|---|---|---|
| label `argocd.argoproj.io/secret-type` | `cluster` | Argo CD treats the Secret as a destination cluster |
| label `stacks.io/hub-managed` | `"true"` | Selected by both appsets |
| label `stacks.io/cluster-role` | `spoke` | Selected by both appsets |
| label `stacks.io/platform` | `talos` | Inventory/placement metadata |
| label `workload.stacks.io/workflow-builder` | `"true"` | **Opt-in** to `spoke-workloads-appset` (dev/staging set it; **ryzen OMITS it** — its overlay composes `workflow-builder-system` directly) |
| annotation `spoke-cluster` | `<name>` | Drives the templated Application name (`spoke-<name>`) and overlay path (`packages/overlays/<name>`) |
| annotation `stacks.io/source-branch` | `inner-loop` (ryzen) / unset = `main` (dev/staging) | Selects `drySource.targetRevision` |
| `stringData.server` | spoke API URL — see SNI note below | Where Argo CD connects |
| dev/staging | server = **direct public IP** `https://<ip>:6443`, bearer token from a Crossplane-minted SA | Direct API reachable; no SNI workaround |
| ryzen | server = `https://ryzen-operator.tail286401.ts.net`, `bearerToken: "unused"`, `auth-mode: tailscale-acl-impersonation` | Tailscale-apiserver-proxy + ACL impersonation; no token, no JWKS |

dev/staging cluster Secrets are minted by the Crossplane onboarding pipeline (group-5 spoke-register writes `cluster-dev`/`cluster-staging` directly to the hub). **ryzen's `cluster-ryzen` is a STATIC GitOps-delivered Secret** (`Secret-cluster-ryzen.yaml`, referenced from `hub-management/kustomization.yaml`).

**The two ApplicationSets** (`packages/components/hub-spoke-appsets/apps/`):

- `spoke-clusters-appset.yaml` — `clusters` generator selecting the cluster-Secret labels above. Templates one **root** Application `spoke-<name>` per spoke with `sourceHydrator.drySource.path: packages/overlays/<name>`, `targetRevision` from the source-branch annotation, `hydrateTo: env/spokes-<name>-next` (dev/staging) or `env/spokes-<name>` (ryzen — direct), `syncSource: env/spokes-<name>` path `<name>-apps`. This is the appset the hub actually uses.
  - GOTCHA: there is a SECOND, unused `spoke-clusters-appset.yaml` under `packages/components/hub-base/apps/` that hardcodes `targetRevision: main` and has the buggy empty `kustomize: {}` (the hydrator-stall trap). The hub references only the `hub-spoke-appsets` copy via `packages/overlays/hub/kustomization.yaml`. **Edit the `hub-spoke-appsets` copy, not `hub-base`.**
- `spoke-workloads-appset.yaml` — adds the `workload.stacks.io/workflow-builder=true` selector; generates `spoke-<name>-workflow-builder` from `packages/components/workloads/workflow-builder-system-overlays/<name>`. dev/staging opt in; ryzen does not.

## Hub → spoke ArgoCD connectivity (Tailscale-apiserver-proxy SNI)

dev/staging expose a **direct public kube-API** (`https://<ip>:6443`), so their cluster Secret just points Argo CD at the IP — no SNI workaround.

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
- **Spokes**: workload runtime and failure-domain-local infrastructure. Examples: workflow-builder runtime services, Dapr runtime, cert-manager, External Secrets Operator (resolving the **`hub-secrets-store`** ClusterSecretStore over Tailscale, NOT Azure Workload Identity), CNI/ingress/storage, Tailscale resources needed for that cluster, and per-environment databases/caches/queues. **AWI + Azure Key Vault now live ONLY on the hub** as the canonical secret source; spokes no longer authenticate to Azure AD. See `reference/secret-flow.md`.
- **Ryzen-local**: developer-workstation paths only — Skaffold inner-loop hot reload (HMR sync into a running pod via local kubeconfig). Local Gitea/Tekton/ArgoCD are retired (post-A6).

If production traffic depends on a service during hub outage, keep it per-spoke. If operators use it to manage multiple clusters, centralize it on hub and add spoke agents/access only where needed. See `reference/app-placement.md`.

## Why ryzen is special

Ryzen exists for **fast iteration** (Skaffold hot reload + ryzen-only image pins on the `inner-loop` branch). It's intentionally outside the Promoter chain:
- ryzen uses local Skaffold (`bash scripts/skaffold-dev.sh`) for live source iteration
- ryzen-only manifest changes (image tag bumps) land on the `inner-loop` branch via `commit-pin.sh`; hub Source Hydrator picks them up and applies them to ryzen
- Dev/staging are unaffected until `inner-loop` is PR-merged into `main`

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
| `packages/components/workloads/<image>/manifests/kustomization.yaml` | ryzen image-pin per workload |
| `packages/components/hub-tekton/manifests/outer-loop-builds/` | Hub Tekton pipeline + EventListener |
| `packages/components/hub-tekton/manifests/workflow-builder-builds/` | Workflow-builder build pipeline definitions |
| `scripts/gitops/validate-workflow-builder-release-pins.sh` | Validates release-pin schema and GHCR tag/digest existence |
| `git ls-remote origin env/spokes-ryzen` + hub `argocd app get spoke-ryzen` | Inspect current hub-driven ryzen state instead of running a local sync (no local ArgoCD on ryzen post-A6) |
| `docs/hub-spoke-app-placement.md` | Hub-vs-spoke app placement policy |
| `policy.hujson` | Tailscale ACL — synced via `.github/workflows/tailscale-acl.yml`; `svc:*` approvals are only for real service-host/ProxyGroup/Tailscale Services |

For the original full architecture write-up (covers OpenShell, Dapr workflows, and the (now-retired) DevSpace inner loop), see `docs/gitops-architecture-overview.md` and `docs/outer-loop-promotion.md` in the stacks repo.
