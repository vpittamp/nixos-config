---
name: ryzen-spoke-bootstrap
description: Use this skill when creating, recreating, or repairing the ryzen local development cluster as a hub-managed Talos-Docker spoke of the talos-hub ArgoCD. Covers the talosctl + helm + kubectl bootstrap flow (replacing the retired idpbuilder path), the hub->ryzen apiserver-proxy SNI fix (static cluster-ryzen Secret using the ryzen-operator tailnet FQDN + hub CoreDNS rewrite, stale ryzen-operator device cleanup), the ryzen->hub AWI->Tailscale secret transport (ESO hub-secrets-store ClusterSecretStore reading ryzen-shared-secrets), ryzen profile fit (Contour+Kourier ingress, idpbuilder-local gitea, no Azure on the spoke), the kueue ClientSideApplyMigration=false wedge, and the spoke-ryzen Application sync chain on hub (hydrated from the inner-loop branch).
---

# Ryzen Spoke Bootstrap

## What this skill covers

Bootstrap a fresh ryzen Talos Docker cluster so the hub ArgoCD (running on talos-hub at Hetzner) can register it as a spoke and apply all workloads (workflow-builder, dapr, observability, etc.) via cluster Secret + bearer token. This replaces the retired idpbuilder-based standalone-ryzen flow.

**Quick reference for the steady-state architecture**: `references/desired-state.md` — describes the component inventory, networking paths, GitOps source-of-truth, and what a healthy ryzen cluster looks like. Read this first if you're trying to understand the current system without going through the full bootstrap.

**Automation backlog**: `references/automation-backlog.md` — friction log from the 2026-05-28 recreate, prioritized list of script-level fixes (P0 = `register-spoke-with-hub.sh`, P0 = move `sync-jwks-to-azure.sh` into main, P0 = `cleanup-tailnet-devices.sh`, etc.). Reduces manual steps from ~10 to ~3 on next recreate.

**Architecture (post-A6, current as of May 2026):**
- Ryzen: Talos Docker cluster (3 nodes: `ryzen-controlplane-1` + `ryzen-worker-1/2`, OS-IMAGE Talos v1.13.2, k8s v1.36.0, subnet 10.6.0.0/24), no local ArgoCD, no local Tekton, and gitea is `idpbuilder-local` (there is NO hub-managed `gitea` namespace)
- Profile fit: ryzen runs **Contour + Kourier** (NOT ingress-nginx) and has **no Azure on the spoke** (no azure-workload-identity, no azure-keyvault-store ClusterSecretStore)
- Hub: sole ArgoCD instance; renders `packages/overlays/ryzen` and applies Application CRDs to its own argocd namespace, each with `destination.name: ryzen`
- Hub→ryzen sync: the static `cluster-ryzen` Secret's `server` is `https://ryzen-operator.tail286401.ts.net` (the spoke operator's apiserver-proxy hostname — strict SNI); a HUB CoreDNS rewrite routes that name to the in-cluster egress `ryzen-api-egress.tailscale.svc.cluster.local`. Auth is Tailscale-ACL impersonation (`bearerToken: "unused"`), NOT a per-spoke bearer token. See `references/failure-modes.md`.
- Ryzen→hub secrets: ryzen reads hub-mirrored secrets over Tailscale via ClusterSecretStore **`hub-secrets-store`** (ESO kubernetes provider) → hub ns `spoke-secrets` Secret **`ryzen-shared-secrets`**. The hub keeps AWI + Azure Key Vault as the canonical source; the spoke no longer authenticates to Azure. See `references/desired-state.md`.
- Branch: ryzen hydrates from the **`inner-loop`** branch, NOT `main`. Advance with `git push origin origin/main:refs/heads/inner-loop`.
- Images: cluster pulls from `ghcr.io/pittampalliorg/*`; Skaffold's outer-loop also pushes to ghcr.io

## Workflow

### 1. Prerequisites check

```bash
# Required tools on the workstation
for cmd in talosctl helm kubectl docker tailscale; do
  command -v "$cmd" >/dev/null || echo "MISSING: $cmd"
done

# Required env vars (Tailscale OAuth for the operator helm install)
echo "TS_OAUTH_CLIENT_ID=${TS_OAUTH_CLIENT_ID:?missing}"
echo "TS_OAUTH_CLIENT_SECRET=${TS_OAUTH_CLIENT_SECRET:?missing}"
```

The canonical recreate uses `--ts-acl-mode`, which does NOT need Azure on the spoke:
the hub→spoke auth is Tailscale-ACL impersonation (no per-spoke bearer token, no JWKS
sync, no AAD federated-credential cache wait), and the spoke's workload secrets arrive
from the hub mirror over Tailscale (ClusterSecretStore `hub-secrets-store` →
`ryzen-shared-secrets`), not from `azure-keyvault-store` on the spoke. The hub keeps
AWI + Key Vault as the canonical source. `az login` and `AZURE_*` env vars are NOT
required for a ryzen recreate. (JWKS-to-Azure sync still matters for the *hub's own*
AWI, not for ryzen.)

If recreating an existing cluster, run the destroy + cleanup steps before bootstrap — see `references/recreate-runbook.md`.

### 2. Run the bootstrap script (does everything end-to-end)

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
# Canonical recreate (Tailscale-ACL hub<->spoke, no Azure bearer token / no JWKS+AAD wait):
bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate --ts-acl-mode
# Other forms:
bash deployment/scripts/bootstrap-spoke-cluster.sh --ts-acl-mode  # fresh cluster
bash deployment/scripts/bootstrap-spoke-cluster.sh --no-register  # bootstrap only, skip hub registration
```

Note: "destroy and recreate as needed" on ryzen is treated as ambient consent for
`--recreate` invocations — ryzen is the default spoke-registration prototype target
(not talos-test). The cluster Secret `cluster-ryzen` is now a STATIC GitOps-delivered
Secret (`packages/components/hub-management/manifests/spoke-credentials/Secret-cluster-ryzen.yaml`),
not an ExternalSecret — `--ts-acl-mode` skips the KV-token round-trip entirely.

The script does, in order:
0. (If `--recreate`) Auto-load `TS_OAUTH_*` from KV if env vars unset, then run `cleanup-tailnet-devices.sh` to delete stale devices (including the stale duplicate `ryzen-operator` device — see step 3), `talosctl cluster destroy`, and `kubectl config delete-{context,cluster,user}` for the old context
1. `talosctl cluster create docker --name ryzen --subnet 10.6.0.0/24 --workers 2 --memory-controlplanes 4GiB --memory-workers 13GiB --cpus-workers 5 --exposed-ports 9443:443/tcp`
2. Helm install cert-manager (jetstack 1.14.4)
3. Helm install external-secrets (0.9.13)
4. Helm install tailscale-operator (chart v1.98.x: `apiServerProxyConfig.mode=true` + `allowImpersonation=true`). Spoke operator runs `OPERATOR_HOSTNAME=ryzen-operator`, `APISERVER_PROXY=true`, `OPERATOR_INITIAL_TAGS=tag:k8s-operator`, `PROXY_TAGS=tag:k8s`. NOTE: under `--ts-acl-mode` there is NO azure-workload-identity-webhook helm install — the spoke has no Azure.
5. Label `tailscale` + `local-path-storage` namespaces with `pod-security.kubernetes.io/enforce=privileged` so the operator's proxy pods + provisioner can launch
6. Pre-install Kueue from the upstream release manifest server-side (avoids the CRD partial-apply race) and apply the spoke-registration overlay (SA + ClusterRoleBinding) so the hub can reach the spoke kube-api via the operator apiserver-proxy
7. **Apply the spoke-transport static half imperatively** (`deployment/scripts/lib/spoke-transport-bootstrap.sh`, invoked ~line 301 with `--apply-manifests deployment/manifests/spoke-transport/`): creates the ClusterSecretStore `hub-secrets-store` + the `k8s-api-hub-egress` ExternalName Service, mints the scoped hub SA token onto the spoke as Secret `external-secrets/hub-secrets-token` (key `token`), and inserts the SPOKE CoreDNS rewrite `rewrite name exact k8s-api-hub-ingress.tail286401.ts.net k8s-api-hub-egress.tailscale.svc.cluster.local` (Talos resets the Corefile each recreate, so this re-runs) then rollout-restarts coredns. For ryzen this transport is imperative — `packages/overlays/ryzen` does NOT list `../../components/spoke-tailscale-secrets` in its components (dev/staging GitOps it via the `spoke-transport` Application).
8. Wait for the spoke operator apiserver-proxy device to advertise on the tailnet
9. **Auto-invoke the hub registration** — see step 3 below

### 3. Hub registration (automated under `--ts-acl-mode`)

Under `--ts-acl-mode` there is NO per-spoke bearer-token round-trip, NO `az keyvault secret set`, NO JWKS sync, and NO ~10–29 min AAD federated-cache wait. The hub→ryzen auth is Tailscale-ACL impersonation. The static GitOps cluster Secret `cluster-ryzen` is what registers ryzen on the hub — it is delivered by `packages/components/hub-management/kustomization.yaml`, not minted by the bootstrap. The remaining live wiring the recreate must converge:

1. **Static cluster Secret** `cluster-ryzen` (ns argocd) with `server: https://ryzen-operator.tail286401.ts.net`, `config.tlsClientConfig.{insecure: true, serverName: ryzen-operator.tail286401.ts.net}`, `bearerToken: "unused"`, labels (`stacks.io/cluster-role=spoke`, `stacks.io/hub-managed=true`, `stacks.io/platform=talos`; `workload.stacks.io/workflow-builder` intentionally OMITTED), annotations `spoke-cluster=ryzen`, `stacks.io/source-branch=inner-loop`, `stacks.io/auth-mode=tailscale-acl-impersonation`.
2. **HUB CoreDNS rewrite** `rewrite name exact ryzen-operator.tail286401.ts.net ryzen-api-egress.tailscale.svc.cluster.local` so ArgoCD reaches the in-cluster egress while the wire SNI stays `ryzen-operator...` (ArgoCD does NOT apply `tlsClientConfig.serverName` as the wire SNI — verified 2026-05-29 — so the SNI must come from the server-URL host).
3. **`ryzen-api-egress` ExternalName Service** (ns `tailscale` on the hub, `tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net`), defined inline in `packages/components/hub-management/apps/headlamp.yaml`.
4. **policy.hujson grants**: `tag:k8s → tag:k8s-operator` impersonate `system:masters` (hub egress → spoke operator proxy, the ArgoCD sync path) and `tag:k8s → tag:k8s` impersonate `tailscale:spoke-secrets-reader` (the ryzen→hub ESO read path).
5. **Stale duplicate `ryzen-operator` device cleanup**: a recreate leaves a stale duplicate `ryzen-operator` tailnet device. Delete it via the TS API (token minted from the operator-oauth Secret) so the new operator claims the canonical `ryzen-operator` hostname. Verify with `curl --connect-to` forcing the `ryzen-operator` SNI → expect HTTP 200.

To run hub registration manually (e.g., after `--no-register`):
```bash
CLUSTER_NAME=ryzen bash deployment/scripts/register-spoke-with-hub.sh
```
(JWKS-to-Azure sync only matters for the *hub's own* AWI; it is not part of the ryzen ts-acl registration path.)

### 4. Verify (Phase F in `references/desired-state.md`)

Run the checks in `references/desired-state.md` "What a healthy state looks like" section. The most important:

```bash
# All ryzen-* apps on hub Synced + Healthy (the gitea-secretstore / nginx-tls-secret
# Apps and the gitea-tailscale-backend Service are EXCLUDED for ryzen, not Degraded)
kubectl --kubeconfig ~/.kube/hub-config -n argocd get applications | grep '^ryzen-' | grep -vE 'Synced +Healthy'

# spoke-ryzen tracks inner-loop and is Synced/Healthy
kubectl --kubeconfig ~/.kube/hub-config -n argocd get application spoke-ryzen
# expect: Synced / Healthy, rev=inner-loop

# Ryzen profile fit: Contour + Kourier, zero nginx, no gitea ns
kubectl --context admin@ryzen get pods -A | grep -iE 'contour|kourier|nginx'   # contour + kourier, ZERO nginx
kubectl --context admin@ryzen get ns gitea                                      # expect: NotFound

# Secret transport (ryzen->hub over Tailscale) — NOT azure-keyvault-store on the spoke
kubectl --context admin@ryzen get clustersecretstore hub-secrets-store          # Ready=True
kubectl --context admin@ryzen -n external-secrets get secret hub-secrets-token  # the scoped hub SA token
kubectl --context admin@ryzen -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep 'rewrite name'
kubectl --context admin@ryzen get externalsecrets -A | grep -vE 'SecretSynced|Valid'  # expect empty

# Hub->ryzen wiring
kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret cluster-ryzen -o jsonpath='{.data.server}' | base64 -d
# expect: https://ryzen-operator.tail286401.ts.net
kubectl --kubeconfig ~/.kube/hub-config -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep ryzen-operator

# Branch currency (0 = inner-loop fully caught up to main)
git -C /home/vpittamp/repos/PittampalliOrg/stacks/main rev-list --count origin/inner-loop..origin/main
```

### 5. Push spoke-ryzen Application + bootstrap-merge env/hub PR

The hub's `spoke-ryzen` Application (in `packages/components/hub-management/...`) hydrates `packages/overlays/ryzen` from GitHub `inner-loop` branch to `env/spokes-ryzen`. Hub's ArgoCD then applies the rendered Application CRDs to its own argocd namespace, each with `destination.name: ryzen`. From there, hub's controller propagates workloads to ryzen via the cluster Secret.

Ryzen tracks the **`inner-loop`** branch, not `main`. To get `main`'s content onto ryzen, fast-forward inner-loop: `git push origin origin/main:refs/heads/inner-loop`. The hub `spoke-ryzen` Application then re-dispatches the drySHA, renders `packages/overlays/ryzen`, and pushes `env/spokes-ryzen` (path `ryzen-apps`); ryzen-* apps reconcile. There is NO Promoter on the ryzen lane.

Hub-side state that changes affecting the HUB itself (the static `cluster-ryzen` Secret, ApplicationSet definitions, etc.) is committed to `main` and flows `env/hub-next → env/hub` via the GitOps Promoter PR (autoMerge:false — must be merged). If the Promoter is stuck, see the `gitops` skill (`argocd app terminate-op` + `--force sync`, or `gh pr create --base env/hub --head env/hub-next` + merge).

### 6. Post-bootstrap one-time data migrations

Some workloads on ryzen need data restored from dev:

```bash
# environment_image_builds table (216 rows for SWE-bench env image catalog)
kubectl --context dev exec -n workflow-builder postgresql-0 -- pg_dump -U postgres -d workflow_builder \
  -t environment_image_builds --data-only --column-inserts > /tmp/eib.sql
kubectl cp /tmp/eib.sql workflow-builder/postgresql-0:/tmp/eib.sql
kubectl exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -f /tmp/eib.sql
```

## When to use this skill

- Creating ryzen for the first time after the hub-managed migration
- Recreating ryzen (e.g., upgrading Talos version, recovering from corruption)
- Repairing the Tailscale egress when the hub-side proxy lost its target after device cleanup
- Diagnosing why hub's spoke-ryzen Application can't connect to ryzen

## When NOT to use this skill

- For day-to-day GitOps changes — those go through the `inner-loop` branch (no Promoter on the ryzen lane; see `gitops` skill)
- For Skaffold inner-loop iteration — see `skaffold-dev-loop` skill
- For dev/staging spoke management — those are Crossplane-provisioned Hetzner Talos clusters with a different bootstrap path

## Critical files (in the stacks repo)

- `deployment/scripts/bootstrap-spoke-cluster.sh` — the canonical bootstrap entrypoint (`--recreate --ts-acl-mode`)
- `deployment/scripts/lib/spoke-transport-bootstrap.sh` + `deployment/manifests/spoke-transport/` — the imperative spoke-transport half (ClusterSecretStore `hub-secrets-store`, egress Service, `hub-secrets-token`, SPOKE CoreDNS rewrite). Ryzen applies this imperatively (not GitOps).
- `packages/overlays/ryzen-spoke-registration/` — thin overlay applied during bootstrap (no Application CRDs)
- `packages/overlays/ryzen/kustomization.yaml` — full overlay reconciled by hub via spoke-ryzen (namePrefix `ryzen-`, `destination.name=ryzen`, all per-app ryzen patches, ES repoints; ClientSideApplyMigration=false at line ~261; the workflow-builder / swebench ES repoints to `ryzen-shared-secrets` on `hub-secrets-store` at ~lines 730-775)
- `packages/components/profiles/local-core-ryzen/kustomization.yaml` — profile component (extends base; deletes azure-workload-identity + azure-keyvault-store; profile-mismatch deletions of `gitea-secretstore` + `nginx-tls-secret` + `gitea-tailscale-backend` Service; three base-tail AWI exclusions)
- `packages/components/hub-management/manifests/spoke-credentials/Secret-cluster-ryzen.yaml` — the STATIC hub-side cluster Secret (server `https://ryzen-operator.tail286401.ts.net`, `bearerToken "unused"`, tailscale-acl-impersonation, source-branch `inner-loop`). Replaces the old `ExternalSecret-cluster-ryzen.yaml` (KV-token path, retired). Delivered via `packages/components/hub-management/kustomization.yaml`.
- `packages/components/hub-management/apps/headlamp.yaml` — contains the hub-side `ryzen-api-egress` ExternalName Service with `tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net`
- `packages/components/hub-management/manifests/spoke-secrets/{Namespace-spoke-secrets,ExternalSecret-ryzen-shared-secrets,RBAC-spoke-secrets-reader,Ingress-k8s-api-hub-ingress}.yaml` — the hub mirror + RBAC + standalone Ingress DEVICE that ryzen ESO reads over Tailscale
- `packages/components/tailscale-serve/manifests/tailscale-operator/Deployment-operator.yaml` — shared operator manifest, `OPERATOR_HOSTNAME=ryzen-operator` + `APISERVER_PROXY=true`
- `policy.hujson` — ACL grants `tag:k8s → tag:k8s-operator` (impersonate system:masters, the ArgoCD sync path) and `tag:k8s → tag:k8s` (impersonate `tailscale:spoke-secrets-reader`, the ESO read path)
- `packages/components/hub-spoke-appsets/apps/spoke-clusters-appset.yaml` — the AUTHORITATIVE appset (the `hub-base` copy hardcodes `targetRevision: main` + has the buggy empty `kustomize: {}` and is NOT used; edit the hub-spoke-appsets copy)

## Critical gotchas (failure modes documented in references/)

- **Hub→ryzen apiserver-proxy SNI** — the spoke operator's apiserver-proxy (v1.92.4+) STRICTLY validates the wire TLS SNI and only accepts its own hostname (`ryzen-operator.tail286401.ts.net`). ArgoCD does NOT apply `tlsClientConfig.serverName` as the wire SNI (verified 2026-05-29), so the SNI must come from the server-URL host. The static `cluster-ryzen` Secret sets `server: https://ryzen-operator.tail286401.ts.net`; a HUB CoreDNS rewrite (`ryzen-operator.tail286401.ts.net → ryzen-api-egress.tailscale.svc.cluster.local`) routes that name to the in-cluster egress while the SNI stays correct. Two DISTINCT Tailscale paths — do not conflate: (a) hub→ryzen ArgoCD sync = `ryzen-operator.tail286401.ts.net` + HUB CoreDNS rewrite → `ryzen-api-egress`; (b) ryzen→hub ESO = `k8s-api-hub-ingress.tail286401.ts.net` + RYZEN CoreDNS rewrite → `k8s-api-hub-egress`.
- **Stale duplicate `ryzen-operator` device after recreate** — a recreate leaves a stale duplicate `ryzen-operator` tailnet device; delete it via the TS API (token minted from the operator-oauth Secret) so the new operator claims the canonical hostname. Verify SNI with `curl --connect-to` forcing the `ryzen-operator` SNI → HTTP 200.
- **AWI→Tailscale secret transport** — the spoke has NO Azure (no azure-workload-identity, no azure-keyvault-store ClusterSecretStore — verified live NotFound). Ryzen reads hub-mirrored secrets over Tailscale via ClusterSecretStore `hub-secrets-store` (ESO kubernetes provider) → hub ns `spoke-secrets` Secret `ryzen-shared-secrets`. The store URL host is `k8s-api-hub-ingress.tail286401.ts.net`, `caBundle` is hard-set to ISRG Root X1 (REQUIRED by ESO v0.9.13), and `bearerToken` is the SA token minted onto the spoke as Secret `external-secrets/hub-secrets-token`. The RYZEN CoreDNS rewrite (`k8s-api-hub-ingress → k8s-api-hub-egress.tailscale.svc.cluster.local`) re-runs every recreate because Talos resets the Corefile. JWKS-to-Azure sync is NO LONGER part of the ryzen recreate (it only matters for the hub's own AWI).
- **Workload ES repoints** — shared workload manifests hardcode `remoteRef.key=ryzen-shared-secrets`; the ryzen overlay still repoints two workloads off azure: `workflow-builder-secrets` data[9,10,21,22] to the `*-RYZEN` KV keys, and `swebench-runtime-builds` ESes `github-clone-credentials` + `gitea-registry-credentials` onto `hub-secrets-store` / `ryzen-shared-secrets` (`/property` ADDED — source ESes carry only `/key`).
- **Ryzen profile fit: Contour + Kourier, NOT nginx; idpbuilder-local gitea, NO hub gitea ns** — `local-core-ryzen` deletes the `gitea-secretstore` + `nginx-tls-secret` Applications and the `gitea-tailscale-backend` Service (target ns `gitea`, absent on ryzen). External access on ryzen is via Tailscale Ingress, not nginx.
- **RFC6902 `op: add /spec/source/kustomize` CLOBBER** — a kustomize `op: add` to `/spec/source/kustomize` REPLACES the whole node (last-writer-wins). Both `profiles/local-core-ryzen` AND `overlays/ryzen` op:add to the tailscale-operator's `/spec/source/kustomize`; the overlay runs LAST and wins, so the overlay's tailscale-operator patch must carry BOTH the `PROXY_IMAGE=v1.92.4` env AND the `gitea-tailscale-backend` Service `$patch:delete` co-located. Move the Service delete into the profile block and it gets clobbered → sync fails "namespaces gitea not found". This clobber rule governs every co-located op:add between the two files.
- **kueue ClientSideApplyMigration=false (ryzen-only)** — the ~1.4MB `workloads.kueue.x-k8s.io` CRD wedges ArgoCD 3.4.2's pre-SSA ClientSideApplyMigration step (it writes a >262144-byte last-applied-configuration annotation; argo-cd#26279) whenever the live CRD is not yet argocd-owned. Triggered on ryzen because the CRD was hand-kubectl-applied during recovery (live managedFields owners = kubectl, argocd-controller, kube-apiserver, kueue). Fix = `ClientSideApplyMigration=false` syncOption on the ryzen-only overlay patch (`packages/overlays/ryzen/kustomization.yaml:~261`) — pure SSA, clean ownership transfer, no Workload CR data loss. Harmless no-op on a clean recreate; keep it while kubectl co-owns the CRD.
- **ryzen reads `inner-loop`, NOT `main`** — pushing to `main` alone never reaches ryzen. Advance with `git push origin origin/main:refs/heads/inner-loop`. `spoke-ryzen` is path-based (`packages/overlays/ryzen`, no `kustomize` field) so do NOT mis-diagnose a frozen ryzen as the empty-`drySource.kustomize` hydrator-stall bug — check `targetRevision`/inner-loop first.
- **PodSecurity admission** blocks Tailscale proxy + local-path-provisioner helper pods if their namespaces enforce `baseline:latest`. Label `tailscale` and `local-path-storage` namespaces `pod-security.kubernetes.io/enforce=privileged`. (Spoke-overlay `CreateNamespace=true` can create a bare ns whose baseline PSA rejects local-path hostPath helper pods → PVCs Pending → stateful workloads hang; ryzen is fixed via `managedNamespaceMetadata`.)
- **GHCR_PAT username matters** — use `PittampalliOrg` (org name), not personal username, for image pulls. Source the PAT from KV secret `GITHUB-PAT` (NOT `GHCR-PAT` which doesn't exist); on ryzen this now arrives via the `ryzen-shared-secrets` hub mirror.
- **SWE-bench sandbox pods stay Pending without worker node labels.** The Kueue ResourceFlavor `dev-benchmark` selects nodes by both `stacks.io/swebench-pool=dev-benchmark` AND `node-role.kubernetes.io/worker=""`. Pre-A6 KIND ryzen got these from kind-config kubeadm extraArgs; post-A6 Talos doesn't. `bootstrap-spoke-cluster.sh` now applies the labels after kube-api is up (commit 9871c7217); if you bootstrap with an older script, apply them manually.
- **Headlamp's per-cluster bearer tokens are baked into a kubeconfig at pod start.** The init container reads cluster Secrets ONCE and renders them into an emptyDir volume. If the ryzen cluster Secret is rotated (e.g., after recreate), restart both Headlamp Deployments (`hub-headlamp` + `hub-headlamp-embedded`) so the kubeconfig regenerates — otherwise the UI shows "Failed to get authentication information: ryzen".
- **ArgoCD 3.4 stricter ServerSideApply rejects unknown schema fields.** Examples we hit: `terminationGracePeriodSeconds` on Knative Service (gated behind a feature flag) and Tekton Pipelines/Tasks where the mutating webhook injects empty defaults (`computeResources: {}`, `metadata: {}`, etc.). Either remove the field from source or add `ignoreDifferences` with jq path expressions covering the operator-injected paths.
