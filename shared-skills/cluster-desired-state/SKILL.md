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
| **dev** | disposable Hetzner SWE-bench spoke | Crossplane `TalosSpokeClusterClaim` | `main` -> `env/spokes-dev` | direct public IP `:6443` | hub mirror over Tailscale |

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
   - Build/recreate **dev** (Crossplane Hetzner spoke) -> `references/dev.md`,
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
   - `talos-clusters` — Crossplane spoke lifecycle, ProxyGroups, SWE-bench capacity.
   - `ryzen-spoke-bootstrap` — the imperative ryzen Docker bootstrap mechanics.
   - `evaluations` / `workflow-builder` — workload-level validation after a rebuild.

## The desired-state mental model (all three clusters)

Every cluster is healthy when **all six layers** below are green. The reference
and runbook files walk each layer in order. A cluster is **not** "done" when nodes
are Ready — Argo child apps, secret transport, hub connectivity, and workload data
must all be healthy too.

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
6. VERIFY           the per-cluster verification command block passes clean
```

## Cross-cutting architecture (one-screen summary)

Full detail in `references/architecture.md`. The load-bearing pieces:

- **Cluster-Secret contract** (Contract 1). A Secret in ns `argocd` labeled
  `argocd.argoproj.io/secret-type=cluster` + `stacks.io/hub-managed=true` +
  `stacks.io/cluster-role=spoke` + `stacks.io/platform=talos`, annotated
  `spoke-cluster=<name>`. dev/staging AND ryzen materialize it from KV via an
  ExternalSecret. **ryzen uses `ExternalSecret-cluster-ryzen.yaml`** (the old static
  `Secret-cluster-ryzen.yaml` was deleted): `server=https://ryzen.tail286401.ts.net:6443`,
  `insecure:false`+caData, a per-recreate ServiceAccount bearerToken,
  `source-branch=inner-loop`.
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
  `caBundle` is hard-set to it, REQUIRED by ESO v0.9.13), authenticating with a
  scoped read-only SA token. A spoke CoreDNS rewrite maps that FQDN ->
  `k8s-api-hub-egress.tailscale.svc.cluster.local`.
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
