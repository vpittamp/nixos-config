---
name: cluster-desired-state
description: "Authoritative end-to-end guide to how PittampalliOrg reaches the DESIRED STATE for every cluster in the hub-and-spoke fleet — hub, ryzen, and dev. Use whenever you need the ordered path from nothing to a healthy cluster (provisioning -> GitOps registration -> Tailscale secret transport -> hub->spoke connectivity -> workloads -> verification), the cross-cutting architecture (cluster-Secret contract, spoke-transport contract, source-hydrator + GitOps Promoter, env/hub / env/spokes-* / inner-loop branch flow, AWI->Tailscale secret migration, the ryzen host-device raw-TCP-passthrough connectivity pattern, per-cluster ExternalSecret parameterization), or the recovery runbooks and gotchas (Talos ISO vs k8s in-place upgrade, kueue ClientSideApplyMigration wedge, RFC6902 op:add clobber, env-table SWE-bench restore, stale tailnet device cleanup). Use this to plan or audit a fresh build or a full recreate of hub/ryzen/dev; for narrow tasks defer to the talos-clusters, ryzen-spoke-bootstrap, or gitops skills it cross-references."
---

# Cluster Desired State (hub / ryzen / dev)

The single map of **what each cluster in the PittampalliOrg/stacks fleet should be**
and **the ordered path to get there**. The fleet is one ArgoCD/GitOps management
plane (the **hub**) plus spokes that the hub renders and reconciles. Three clusters
matter today:

| Cluster | Role | Provisioning | Branch it syncs | API reach | Secrets |
|---|---|---|---|---|---|
| **hub** | management plane + central Tekton build pool | manual Talos/Hetzner (`docs/hub-cluster-setup.md`) | `env/hub` (path `hub-apps/`) | `k8s-api-hub.tail286401.ts.net` ProxyGroup VIP | **canonical** Azure KV + AWI |
| **ryzen** | bare-metal local-dev spoke | imperative `bootstrap-spoke-cluster.sh` (Talos-in-Docker) | `inner-loop` -> `env/spokes-ryzen` | `ryzen.tail286401.ts.net:6443` (host-device raw TCP passthrough, full TLS verify) | hub mirror over Tailscale |
| **dev** | disposable Hetzner SWE-bench spoke | scripts: `provision-spoke.sh` + `bootstrap-spoke-deps.sh` + `enroll-dev-agent.sh` | `main` -> `env/spokes-dev` | no ArgoCD kube-API reach (managed agent, gRPC out) | hub mirror over Tailscale |

> **The hub keeps Azure Key Vault + Azure Workload Identity as the single source of
> truth. The AWI->Tailscale migration moved only the SPOKES off Azure** — spokes now
> read hub-mirrored secrets via an ESO kubernetes-provider `ClusterSecretStore`
> (`hub-secrets-store`) over Tailscale. Do not re-introduce `azure-keyvault-store`
> on a spoke.

## Start Here

1. **Pick the cluster + operation** and read its reference, then its runbook:
   - Build/recreate the **hub** -> `references/hub.md`, then `runbooks/build-hub.md`.
   - Build/recreate **ryzen** (bare-metal Docker spoke) -> `references/ryzen.md`,
     then `runbooks/recreate-ryzen.md`.
   - Build/recreate **dev** (script-provisioned Hetzner spoke) -> `references/dev.md`,
     then `runbooks/recreate-dev.md`.
2. **Need the shared model?** (cluster-Secret contract, transport contract,
   source-hydrator/Promoter, branch flow, AWI->Tailscale, ryzen host-passthrough
   connectivity, per-cluster ES parameterization) -> `references/architecture.md`.
3. **Hit a known failure?** -> `runbooks/recovery-and-gotchas.md` (Talos ISO/k8s
   in-place upgrade, ryzen host-passthrough connectivity, kueue `ClientSideApplyMigration`,
   RFC6902 `op: add` clobber, env-table SWE-bench restore, stale tailnet device
   cleanup).
4. **Cross-reference the focused skills** for the deep mechanics:
   - `gitops` — ArgoCD health/drift, Promoter/source-hydrator recovery, image pins.
   - `talos-clusters` — hub Talos provisioning + (removed) Crossplane history;
     **dev is NOT Crossplane-provisioned** (Crossplane removed in Phase D — dev is
     script-provisioned + agent-enrolled, the same imperative path as hub & ryzen).
   - `ryzen-spoke-bootstrap` — the imperative ryzen Docker bootstrap mechanics.
   - `evaluations` / `workflow-builder` — workload-level validation after a rebuild.

## The desired-state mental model (all three clusters)

Every cluster is healthy when **all seven layers** below are green. The reference
and runbook files walk each layer in order. A cluster is **not** "done" when nodes
are Ready — Argo child apps, secret transport, hub connectivity, web exposure, and
workload data must all be healthy too.

```
1. PROVISION        nodes Ready, correct Talos/k8s version, CNI + build/pool labels
        |
2. REGISTER         argocd cluster Secret in ns argocd (the cluster-Secret contract)
        |           -> appset materializes the spoke-<name> root Application
3. SECRET TRANSPORT spoke ESO reads hub ns spoke-secrets over Tailscale
        |           (hub-secrets-store CSS; AWI/KV stays hub-only canonical)
4. HUB CONNECTIVITY hub ArgoCD can reach the spoke API (direct IP, or ryzen
        |           host-device raw TCP passthrough over Tailscale + CoreDNS egress)
5. WORKLOADS        all <name>-* child apps Synced/Healthy; DB migrate-then-seed;
        |           per-cluster ExternalSecret repointing applied
6. WEB EXPOSURE     workflow-builder reachable at https://workflow-builder-<cluster>.tail286401.ts.net
        |           via a Tailscale L4 LoadBalancer Service + in-cluster nginx tls-terminator
        |           sidecar serving the persistent self-signed *.tail286401.ts.net wildcard
        |           (NO Let's Encrypt, NO Tailscale Ingress). mcp-gateway is in-cluster only.
7. VERIFY           the per-cluster verification command block passes clean
```

## Cross-cutting architecture (one-screen summary)

Full detail in `references/architecture.md`. The load-bearing pieces:

- **Control plane = argocd-agent v0.8.1.** The hub runs the **principal** (single pane,
  ns `argocd`); each spoke runs a **local ArgoCD + an agent** dialing the principal
  OUTBOUND over tailnet mTLS (`:8443`). **dev = MANAGED agent** — the hub authors the
  `Application` objects in ns `dev` (== the agent name), the principal pushes them to
  the dev agent, and dev's LOCAL controller reconciles (single pane: hub
  `kubectl -n dev get applications`). **ryzen = AUTONOMOUS agent** — reconciles its own
  apps; the hub only aggregates status. Sync **operations run on the SPOKE's local
  controller**, so the hub pane shows sync + health but NOT operation lifecycle —
  `"Unknown operation status"` on the hub is architectural and **benign**. The
  `cluster-<spoke>` Secret is now an agent MAPPING (Contract 1 below), not a direct
  server+bearerToken.
- **Cluster-Secret contract** (Contract 1). A Secret in ns `argocd` labeled
  `argocd.argoproj.io/secret-type=cluster` + `stacks.io/hub-managed=true` +
  `stacks.io/cluster-role=spoke` + `stacks.io/platform=talos`, annotated
  `spoke-cluster=<name>`. **BOTH dev and ryzen are now argocd-agent MAPPINGS**
  (`managed-by: argocd-agent`, label `argocd-agent.argoproj-labs.io/agent-name`):
  `server=https://argocd-agent-resource-proxy:9090?agentName=<name>` with embedded mTLS
  certData/keyData/caData and **no bearerToken**. dev's is created by `enroll-dev-agent.sh`
  (it replaced the old group-5 spoke-register + `ExternalSecret-cluster-talos.yaml`
  direct-IP+token Secret); ryzen's by `argocd-agentctl agent create ryzen`. The two spokes
  differ only in agent **mode** (dev = MANAGED, ryzen = AUTONOMOUS), NOT in Secret shape.
  > The legacy `ExternalSecret-cluster-ryzen.yaml` (a real `server=https://ryzen.tail286401.ts.net:6443`
  > + caData + SA bearerToken) is now **vestigial** — superseded by the agent mapping. That
  > host-passthrough kube-API endpoint + SA token is what **Headlamp** uses to reach ryzen
  > (via the dedicated `headlamp-cluster-ryzen` Secret), NOT the ArgoCD cluster Secret. ryzen
  > still hydrates from `inner-loop` (its `source-branch`). See `references/tailscale-and-certs.md`.
- **spoke-clusters-appset** (cluster generator) turns each cluster Secret into a
  `spoke-<name>` Application: `drySource` path `packages/overlays/<name>`,
  `targetRevision` from the `stacks.io/source-branch` annotation (default `main`,
  ryzen=`inner-loop`), hydrateTo/syncSource `env/spokes-<name>`. The
  **spoke-workloads-appset** (selector `workload.stacks.io/workflow-builder=true`)
  adds the `spoke-<name>-workflow-builder` app (dev/staging only; ryzen composes
  workflow-builder in its overlay instead).
- **GitOps source-hydrator + Promoter.** `drySource` on `main`/`inner-loop` is
  rendered to `env/<env>-next`; GitOps Promoter PRs `env/<env>-next -> env/<env>`;
  ArgoCD syncs from `env/<env>`. **Hub syncs from `env/hub` (path `hub-apps/`), NOT
  `main`.** dev/staging from `env/spokes-<env>`. **ryzen hydrates from `inner-loop`**
  (advance with `git push origin origin/main:refs/heads/inner-loop`) — no Promoter.
- **AWI -> Tailscale secret transport** (Contract 2). Hub mirrors every
  spoke-consumed KV secret into ns `spoke-secrets` as `<cluster>-shared-secrets`.
  The spoke ESO `ClusterSecretStore hub-secrets-store` (kubernetes provider) reads
  them over Tailscale via the standalone hub Ingress **device**
  `k8s-api-hub-ingress.tail286401.ts.net` (LE cert chaining to **ISRG Root X1** —
  `caBundle` is hard-set to it, still REQUIRED on ESO v2.4.1), authenticating with a
  scoped read-only SA token. A spoke CoreDNS rewrite maps that FQDN ->
  `k8s-api-hub-egress.tailscale.svc.cluster.local`.
- **External Secrets Operator is `2.4.1` fleet-wide on the `external-secrets.io/v1`
  API** (2026-05-30). Chart `2.4.1` is pinned in `packages/base/apps/external-secrets.yaml`
  (spoke default) and `packages/components/hub-base/apps/external-secrets.yaml` (hub),
  both with `crds.unsafeServeV1Beta1: true` so the CRDs serve `v1` (storage) **and**
  the deprecated `v1beta1` (lets any lingering v1beta1 manifest keep working). **All
  ES/CSS manifests are `external-secrets.io/v1`** (PushSecret/ClusterPushSecret stay
  `v1alpha1` — no v1). Spokes run ESO **controller-only** (`webhook.create:false`,
  `certController.create:false`; v2 renders the same shape). A global `argocd-cm`
  `resource.customizations.ignoreDifferences.external-secrets.io_ExternalSecret`
  (via the `argocd-cm-patches` Job) ignores the server-defaulted fields
  (`conversionStrategy`/`decodingStrategy`/`metadataPolicy`/`nullBytePolicy` +
  `target.deletionPolicy`/`template.engineVersion`/`mergePolicy`) so ArgoCD's
  client-side diff doesn't flag them. **ESO version is per-cluster — ALWAYS check
  `kubectl get crd externalsecrets.external-secrets.io -o jsonpath='{.spec.versions[*].name}'`
  on EACH target before migrating manifest apiVersions** (the hub was bumped to v2
  before the spokes; flipping spoke manifests to `v1` while a spoke still served only
  `v1beta1` broke every spoke ES app with `resource mapping not found`). See
  `runbooks/recovery-and-gotchas.md` for the webhook-spoke in-place-upgrade fix.
- **Persistent self-signed CA** (Contract 3, web exposure). A 10-year offline CA
  ("PittampalliOrg Tailnet Dev CA") lives in Azure KV as `TAILNET-DEV-CA-CRT/KEY`;
  the hub mirrors it CLUSTER-NEUTRALLY into ns `spoke-secrets` Secret `tailnet-ca`
  (`ExternalSecret-tailnet-ca.yaml`; the namespace-wide `spoke-secrets-reader` Role
  means every spoke reads the SAME key — no per-cluster CA). The spoke base app
  `packages/components/tailnet-ca` (via `packages/base/apps/tailnet-ca.yaml`, spoke-only)
  restores it into a `tailnet-dev-ca` CA `ClusterIssuer` that signs the
  `*.tail286401.ts.net` wildcard Certificate consumed by the workflow-builder
  `tls-terminator` sidecar. Same CA on every cluster -> clients trust it ONCE and it
  SURVIVES recreation (improves on idpbuilder's per-install CA). PR #2319.
- **Host-device raw TCP passthrough** (ryzen-only, hub->spoke direction). hub->ryzen
  reaches the ryzen Talos kube-apiserver DIRECTLY over Tailscale via the ryzen HOST
  device (`ryzen.tail286401.ts.net`, `100.96.102.1`, `tag:k8s`) running
  `tailscale serve --bg --tcp=6443` as a RAW TCP passthrough to the local apiserver
  (nixos-config `services.tailscaleK8sApiserver` / the `tailscale-serve-k8s-apiserver`
  oneshot; the stacks bootstrap restarts it after each cluster create). No TLS
  termination, so the Talos apiserver's own serving cert reaches the hub end-to-end;
  the hub does FULL TLS verify (`insecure:false`) against the Talos CA, and the cert's
  `apiServer.certSANs` cover `ryzen.tail286401.ts.net`+`100.96.102.1` — **no SNI
  workaround needed**. HUB CoreDNS rewrite `ryzen.tail286401.ts.net -> ryzen-api-egress`
  (self-healing CronJob) points at the egress; the Tailscale operator apiserver-proxy
  is NO LONGER in this path (so it never provisions an LE cert). WHY: the operator
  proxy's per-hostname Let's Encrypt cert (5 dup-certs/week limit) was exhausted by
  recreate churn, taking the ryzen fleet to 0-healthy (2026-05-29). Host-passthrough
  consumes ZERO LE quota. PRs #2305 (hub cutover), #2307 (`--ts-host-passthrough`).
- **Per-cluster ExternalSecret parameterization.** Shared workload manifests
  hardcode `remoteRef.key=ryzen-shared-secrets`. dev re-points them onto
  `dev-shared-secrets` via `scripts/gitops/render-workflow-builder-release-overlays.sh`
  (dev-gated `emit_es_key_repoint` / `emit_es_store_repoint` / `emit_oauth_op`).
  ryzen re-points its OAuth + swebench ESes inline in `packages/overlays/ryzen`.

> **Canonical Tailscale/cert doc.** `references/tailscale-and-certs.md` is the SINGLE
> canonical home for the full Tailscale topology + Let's-Encrypt-avoidance rationale
> (host raw-TCP passthrough, tailnet LoadBalancer Services, per-cluster operator
> hostname, the one stable hub-Ingress LE cert, ESO transport, stale-device cleanup).
> Read it for the WHY; the bullets above and the table below are the quick reference.

## Two distinct Tailscale paths — do not conflate

| Direction | Used for | FQDN | Rewrite location -> target |
|---|---|---|---|
| **hub -> ryzen** | ArgoCD sync to spoke API (raw TCP passthrough via ryzen HOST device) | `ryzen.tail286401.ts.net:6443` | **HUB** CoreDNS -> `ryzen-api-egress.tailscale.svc.cluster.local` |
| **ryzen/dev -> hub** | ESO secret fetch | `k8s-api-hub-ingress.tail286401.ts.net` | **SPOKE** CoreDNS -> `k8s-api-hub-egress.tailscale.svc.cluster.local` |

Different devices, different rewrites, different clusters. ESO uses the
**standalone hub Ingress device** (not the `k8s-api-hub` ProxyGroup VIP — the VIP
route never propagates into a spoke egress netmap).

## Default working rules

- **Commit the desired shape first.** For spokes the claim/overlay is the source of
  truth; HCloud servers and Docker containers are implementation detail.
- **Know the branch.** Pushing to `main` alone never reaches the hub (needs `env/hub`
  merge) and never reaches ryzen (needs `inner-loop`). See `references/architecture.md`.
- **Never delete a working Tailscale VIP** even if it shows `ProxyGroupInvalid`.
- **Pause before destructive recreate.** Drain active SWE-bench runs/leases/Dapr
  workflows and back up the env tables first (`runbooks/recovery-and-gotchas.md`).
- **Validate infra AND runtime.** Close every build/recreate with the per-cluster
  verification block in the reference file.

## Authoritative stacks docs (canonical living source)

This skill is a curated snapshot; the stacks docs are canonical. Re-sync after any
major procedure change.

- `docs/hub-cluster-setup.md`, `docs/hub-gitops-bootstrap.md`, `docs/hub-recovery-runbook.md`
- `docs/gitops-architecture-overview.md`
- `docs/crossplane-spoke-onboarding.md`, `docs/recreate-disposable-dev.md`, `docs/hcloud-server-setup.md`
- `docs/outer-loop-promotion.md`, `docs/spoke-cluster-access.md`
- `packages/components/spoke-tailscale-secrets/CONTRACT.md` (the spoke transport contract)
