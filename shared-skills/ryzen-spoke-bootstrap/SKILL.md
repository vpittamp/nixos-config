---
name: ryzen-spoke-bootstrap
description: Use this skill when creating, recreating, or repairing the ryzen local development cluster as a hub-managed Talos-Docker spoke of the talos-hub ArgoCD. Covers the talosctl + helm + kubectl bootstrap flow (replacing the retired idpbuilder path), the hub->ryzen apiserver-proxy SNI fix (static cluster-ryzen Secret using the ryzen-operator tailnet FQDN + hub CoreDNS rewrite, stale ryzen-operator device cleanup), the ryzen->hub AWI->Tailscale secret transport (ESO hub-secrets-store ClusterSecretStore reading ryzen-shared-secrets), ryzen profile fit (Contour+Kourier ingress, idpbuilder-local gitea, no Azure on the spoke), the kueue ClientSideApplyMigration=false wedge, and the spoke-ryzen Application sync chain on hub (hydrated from the inner-loop branch).
---

# Ryzen Spoke Bootstrap

## What this skill covers

Bootstrap a fresh ryzen Talos Docker cluster as an **AUTONOMOUS argocd-agent spoke** of the hub principal: ryzen runs a LOCAL ArgoCD that reconciles its own apps and an agent that dials the hub principal OUTBOUND over tailnet mTLS (8443). As of 2026-06 ryzen is enrolled via `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh` (called by `bootstrap-spoke-cluster.sh --recreate`); the `cluster-ryzen` Secret is now an agent MAPPING (`server: https://argocd-agent-resource-proxy:9090?agentName=ryzen`, embedded mTLS, NO bearerToken), not a hub→spoke kube credential. This replaces the retired idpbuilder-based standalone-ryzen flow.

> **AGENT-ERA NOTE (2026-06):** the hub→spoke kube-API reach material throughout this doc — the apiserver-proxy SNI fix, the static `cluster-ryzen` bearer/`unused` Secret, the HUB CoreDNS rewrite to `ryzen-api-egress`, and `register-spoke-with-hub.sh` — is the **pre-agent** model and is **RETIRED for ArgoCD sync**. ryzen now reconciles locally. That hub→spoke kube path survives ONLY as (a) the **spoke→hub ESO** secret-fetch transport (ryzen reads hub-mirrored secrets over Tailscale) and (b) the ryzen host raw-TCP-passthrough kube endpoint used ONLY by **Headlamp**. Treat the SNI / static-Secret / register-spoke sections below as **legacy/diagnostics**, and defer to the **`cluster-desired-state`** skill as authoritative for the current model.

**Control plane (argocd-agent v0.8.1):** the fleet now runs argocd-agent — the hub runs the PRINCIPAL (single pane, ns `argocd`) and each spoke runs a LOCAL ArgoCD + an agent dialing the principal OUTBOUND over tailnet mTLS (8443). **ryzen = AUTONOMOUS agent** (reconciles its own apps locally; the hub aggregates status). **dev = MANAGED agent** (the hub authors Application objects in ns `dev` and the principal pushes them to the dev agent). Sync OPERATIONS run on the spoke's local controller, so the hub pane shows sync+health but not operation lifecycle ("Unknown operation status" on the hub is architectural/benign). See the `cluster-desired-state` skill for the full end-to-end model and `cluster-desired-state/references/tailscale-and-certs.md` for the cert/Tailscale detail.

**Quick reference for the steady-state architecture**: `references/desired-state.md` — describes the component inventory, networking paths, GitOps source-of-truth, and what a healthy ryzen cluster looks like. Read this first if you're trying to understand the current system without going through the full bootstrap.


**Architecture (post-A6, current as of May 2026):**
- Ryzen: Talos Docker cluster (3 nodes: `ryzen-controlplane-1` + `ryzen-worker-1/2`, OS-IMAGE Talos v1.13.2, k8s v1.36.0, subnet 10.6.0.0/24), no local ArgoCD, no local Tekton, and gitea is `idpbuilder-local` (there is NO hub-managed `gitea` namespace)
- Profile fit: ryzen runs **Contour + Kourier** (NOT ingress-nginx) and has **no Azure on the spoke** (no azure-workload-identity, no azure-keyvault-store ClusterSecretStore)
- Hub: sole ArgoCD instance; renders `packages/overlays/ryzen` and applies Application CRDs to its own argocd namespace, each with `destination.name: ryzen`
- Hub→ryzen sync: the static `cluster-ryzen` Secret's `server` is `https://ryzen-operator.tail286401.ts.net` (the spoke operator's apiserver-proxy hostname — strict SNI); a HUB CoreDNS rewrite routes that name to the in-cluster egress `ryzen-api-egress.tailscale.svc.cluster.local`. Auth is Tailscale-ACL impersonation (`bearerToken: "unused"`), NOT a per-spoke bearer token. See `references/failure-modes.md`.
- Ryzen→hub secrets: ryzen reads hub-mirrored secrets over Tailscale via ClusterSecretStore **`hub-secrets-store`** (ESO kubernetes provider) → hub ns `spoke-secrets` Secret **`ryzen-shared-secrets`**. As of 2026-06 the hub's secret root migrated AWI→1Password: the hub's 21 ExternalSecrets (incl. the `ryzen-shared-secrets` mirror) now resolve from the **`onepassword-store`** ClusterSecretStore (ESO onepasswordSDK provider → the **hub-eso** 1Password vault); Azure KV + AWI are DORMANT (not deleted). The spoke transport is unchanged — ryzen reads the hub-mirrored k8s Secret regardless of how the hub populates it, and never authenticates to Azure. See `references/desired-state.md`.
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

The canonical recreate (`bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate`)
does NOT need Azure on the spoke: ryzen reconciles locally as an autonomous agent, and the
spoke's workload secrets arrive from the hub mirror over Tailscale (ClusterSecretStore
`hub-secrets-store` → `ryzen-shared-secrets`), not from `azure-keyvault-store` on the spoke.
`az login` and `AZURE_*` env vars are NOT required for a ryzen recreate. (`--ts-acl-mode` /
`--ts-host-passthrough` are vestigial — parsed for compat, ignored.) JWKS-to-Azure sync is
NOT part of the ryzen recreate; note that the hub's own secret root migrated AWI→1Password
in 2026-06, so `sync-jwks-to-azure.sh` is now a SPOKE-only tool, not a hub-bootstrap step.

If recreating an existing cluster, run the destroy + cleanup steps before bootstrap — see `references/recreate-runbook.md`.

### 2. Run the bootstrap script (does everything end-to-end)

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
# Canonical recreate (provisions Talos + deps + transport, then ENROLLS the autonomous agent):
bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate
# Other forms:
bash deployment/scripts/bootstrap-spoke-cluster.sh                # fresh cluster
bash deployment/scripts/bootstrap-spoke-cluster.sh --no-register  # bootstrap only, skip agent enrollment
```

Note: "destroy and recreate as needed" on ryzen is treated as ambient consent for
`--recreate` invocations — ryzen is the default spoke-registration prototype target
(not talos-test). The `--ts-acl-mode` / `--ts-host-passthrough` flags are VESTIGIAL
(parsed for compat, ignored). The hub-side `cluster-ryzen` Secret is now written by
`enroll-ryzen-agent.sh` as an agent MAPPING (server
`https://argocd-agent-resource-proxy:9090?agentName=ryzen`, embedded mTLS, NO bearerToken)
via `argocd-agentctl agent create ryzen`, NOT a static apiserver-proxy bearer Secret —
`register-spoke-with-hub.sh` is RETIRED and NO LONGER CALLED.

The script does, in order:
0. (If `--recreate`) Auto-load `TS_OAUTH_*` from KV if env vars unset, then run `cleanup-tailnet-devices.sh` to delete stale devices (including the stale duplicate `ryzen-operator` device — see step 3), `talosctl cluster destroy`, and `kubectl config delete-{context,cluster,user}` for the old context
1. `talosctl cluster create docker --name ryzen --subnet 10.6.0.0/24 --workers 2 --memory-controlplanes 4GiB --memory-workers 13GiB --cpus-workers 5 --exposed-ports 9443:443/tcp`
2. Helm install cert-manager (jetstack 1.14.4)
3. Helm install external-secrets (2.4.1 controller-only: webhook.create=false certController.create=false crds.unsafeServeV1Beta1=true - matches GitOps base/apps/external-secrets.yaml so hub ArgoCD adopts it with no version bump; a FRESH install defaults CRD conversion.strategy:None and avoids the cluster-desired-state runbook section L webhook-conversion fix that an in-place 0.9.13->2.4.1 upgrade needs)
4. Helm install tailscale-operator (chart v1.96.5: `apiServerProxyConfig.mode=true` + `allowImpersonation=true`). Spoke operator runs `OPERATOR_HOSTNAME=ryzen-operator`, `APISERVER_PROXY=true`, `OPERATOR_INITIAL_TAGS=tag:k8s-operator`, `PROXY_TAGS=tag:k8s`. NOTE: under `--ts-acl-mode` there is NO azure-workload-identity-webhook helm install — the spoke has no Azure. The chart pin `TS_OPERATOR_CHART_VERSION` is **self-defaulted** at the version-pins block (~line 125: `TS_OPERATOR_CHART_VERSION="${TS_OPERATOR_CHART_VERSION:-1.96.5}"`, PR #2395 commit `a395874dc`) because `bootstrap-spoke-cluster.sh` is STANDALONE and does NOT source `deployment/scripts/lib/common.sh` (where the pin lives) — without the self-default the var was unbound under `set -u` and the recreate ABORTED at this exact helm install (right after external-secrets), AFTER destroy had run, leaving ryzen DOWN. INVARIANT: keep the self-default in lockstep with `lib/common.sh` + the GitOps tailscale-operator manifests; any var this standalone script shares with `common.sh` MUST be self-defaulted.
5. Label `tailscale` + `local-path-storage` namespaces with `pod-security.kubernetes.io/enforce=privileged` so the operator's proxy pods + provisioner can launch
6. Pre-install Kueue from the upstream release manifest server-side (avoids the CRD partial-apply race) and apply the spoke-registration overlay (SA + ClusterRoleBinding) so the hub can reach the spoke kube-api via the operator apiserver-proxy
7. **Apply the spoke-transport static half imperatively** (`deployment/scripts/lib/spoke-transport-bootstrap.sh`, invoked ~line 301 with `--apply-manifests deployment/manifests/spoke-transport/`): creates the ClusterSecretStore `hub-secrets-store` + the `k8s-api-hub-egress` ExternalName Service, mints the scoped hub SA token onto the spoke as Secret `external-secrets/hub-secrets-token` (key `token`), and inserts the SPOKE CoreDNS rewrite `rewrite name exact k8s-api-hub-ingress.tail286401.ts.net k8s-api-hub-egress.tailscale.svc.cluster.local` (Talos resets the Corefile each recreate, so this re-runs) then rollout-restarts coredns. For ryzen this transport is imperative — `packages/overlays/ryzen` does NOT list `../../components/spoke-tailscale-secrets` in its components (dev/staging GitOps it via the `spoke-transport` Application).
8. Wait for the spoke operator apiserver-proxy device to advertise on the tailnet (still used for the spoke→hub ESO transport and the Headlamp kube endpoint)
9. **Auto-invoke the autonomous agent enrollment** (`enroll-ryzen-agent.sh`) — see step 3 below
10. **(step 10) After the inner-loop advance, hard-refresh `root-ryzen` again** (`kubectl -n argocd annotate application root-ryzen argocd.argoproj.io/refresh=hard --overwrite`) so it re-compares against the advanced HEAD — the second leg of the repo-server cold-start fix (PR #2395 commit `89fd0df8b`; the first leg is enroll-ryzen-agent.sh step 6b). Non-fatal.

### 3. Autonomous agent enrollment (automated by `--recreate`)

ryzen reconciles its own apps locally; the hub principal only aggregates status. Enrollment is handled by `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh` (invoked by `bootstrap-spoke-cluster.sh` step 9; `register-spoke-with-hub.sh` is RETIRED). `enroll-ryzen-agent.sh`:

1. **Mints the agent mTLS client cert** (CN `ryzen`) used to dial the hub principal at `:8443`.
2. **Applies the `ryzen-agent-bootstrap` kustomize component** (`packages/components/hub-management/manifests/ryzen-agent-bootstrap`): the **agent-autonomous** bundle + params `mode=autonomous`, the `cluster-ryzen-local` cluster alias, `stacks-repo-read` repo creds, the cert ExternalSecrets, and the `root-ryzen` app-of-apps (overlays/ryzen @ inner-loop).
3. **Runs `argocd-agentctl agent create ryzen`** on the hub — this writes the `cluster-ryzen` AGENT MAPPING Secret (`server: https://argocd-agent-resource-proxy:9090?agentName=ryzen`, embedded mTLS, NO bearerToken).
4. **Stages the Headlamp Secret** (Headlamp still reaches ryzen kube-api via the host raw-TCP passthrough) and **restarts the hub Headlamp** (step 5b — see below) and **advances the inner-loop branch**.
5. **(step 5b) Re-stages the `headlamp-cluster-ryzen` Secret** (fresh kube-API endpoint + read-only SA token + CA, label `headlamp.dev/cluster=true`) on the hub, then **`kubectl -n headlamp rollout restart deploy/hub-headlamp deploy/hub-headlamp-embedded`** (PR #2395 commit `6cee88a70`). The hub Headlamp builds its kubeconfig ONLY in its `generate-kubeconfig` init-container at pod start, so a pod predating the recreate keeps serving the OLD spoke endpoint/CA/token and the staged Secret is inert — the restart forces a kubeconfig rebuild. Guarded on deploy existence, non-fatal (Headlamp is off the critical path).
6. **(step 6b) Hard-refreshes `root-ryzen` after the local repo-server is Available** (PR #2395 commit `89fd0df8b`): `kspoke -n argocd rollout status deploy/argocd-repo-server --timeout=120s` then `kubectl -n argocd annotate application root-ryzen argocd.argoproj.io/refresh=hard --overwrite`. On a fresh recreate the local `argocd-application-controller` runs `root-ryzen`'s FIRST comparison before the local `argocd-repo-server` accepts connections (dial `:8081` connection refused) → `root-ryzen` sticks in `ComparisonError` (sync=Unknown), and the controller does NOT re-queue the errored app for a full resync window (~5min observed) → convergence stalls with ZERO child apps rendered until a manual refresh. The hard-refresh forces a clean first comparison. Non-fatal (the resync timer would eventually heal it; this makes the recreate hands-off + fast).
7. **Advances the inner-loop branch**, then **hard-refreshes `root-ryzen` again** to re-compare against the advanced HEAD — this is `bootstrap-spoke-cluster.sh` step 10 (after the inner-loop advance), the second leg of the cold-start fix.

The remaining live wiring that survives the agent cutover (NOT for ArgoCD sync):

- **policy.hujson grant** `tag:k8s → tag:k8s` impersonate `tailscale:spoke-secrets-reader` (the ryzen→hub ESO read path).
- **Stale duplicate `ryzen-operator` device cleanup**: a recreate leaves a stale duplicate `ryzen-operator` tailnet device. Delete it via the TS API (token minted from the operator-oauth Secret) so the new operator claims the canonical hostname (the ESO transport + Headlamp endpoint depend on it).

To run agent enrollment manually (e.g., after `--no-register`):
```bash
bash deployment/scripts/argocd-agent/enroll-ryzen-agent.sh
```
(LEGACY/DIAGNOSTICS — the pre-agent hub→ryzen sync wiring: static `cluster-ryzen` bearer Secret `server: https://ryzen-operator.tail286401.ts.net` + `bearerToken "unused"`, the HUB CoreDNS rewrite `ryzen-operator.tail286401.ts.net → ryzen-api-egress`, the `ryzen-api-egress` ExternalName Service, and the `tag:k8s → tag:k8s-operator` impersonate-`system:masters` grant — all RETIRED for sync. Keep for diagnosing the residual Headlamp / ESO Tailscale paths only.)

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
- For dev/staging spoke management — dev is now SCRIPT-provisioned (`provision-spoke.sh` + `bootstrap-spoke-deps.sh` + `enroll-dev-agent.sh`), the SAME imperative path as ryzen (Crossplane was removed in Phase D — no `TalosSpokeClusterClaim`, no Composition). dev runs as a MANAGED argocd-agent (hub authors its Application objects in ns `dev`). See the `cluster-desired-state` skill for the full dev provisioning + enrollment path.

## Critical files (in the stacks repo)

- `deployment/scripts/bootstrap-spoke-cluster.sh` — the canonical bootstrap entrypoint (`--recreate`); step 9 enrolls the autonomous agent (no longer calls `register-spoke-with-hub.sh`)
- `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh` — the autonomous-agent enrollment: mints the agent mTLS cert, applies the `ryzen-agent-bootstrap` component, runs `argocd-agentctl agent create ryzen` (writes the `cluster-ryzen` agent mapping), stages the Headlamp Secret, advances inner-loop
- `packages/components/hub-management/manifests/ryzen-agent-bootstrap/` — the kustomize component applied during enrollment (agent-autonomous bundle + params `mode=autonomous` + `cluster-ryzen-local` alias + `stacks-repo-read` + cert ExternalSecrets + `root-ryzen` app-of-apps)
- `deployment/scripts/lib/spoke-transport-bootstrap.sh` + `deployment/manifests/spoke-transport/` — the imperative spoke-transport half (ClusterSecretStore `hub-secrets-store`, egress Service, `hub-secrets-token`, SPOKE CoreDNS rewrite). Ryzen applies this imperatively (not GitOps).
- `packages/overlays/ryzen-spoke-registration/` — thin overlay applied during bootstrap (no Application CRDs)
- `packages/overlays/ryzen/kustomization.yaml` — full overlay reconciled by hub via spoke-ryzen (namePrefix `ryzen-`, `destination.name=ryzen`, all per-app ryzen patches, ES repoints; ClientSideApplyMigration=false at line ~261; the workflow-builder / swebench ES repoints to `ryzen-shared-secrets` on `hub-secrets-store` at ~lines 730-775)
- `packages/components/profiles/local-core-ryzen/kustomization.yaml` — profile component (extends base; deletes azure-workload-identity + azure-keyvault-store; profile-mismatch deletions of `gitea-secretstore` + `nginx-tls-secret` + `gitea-tailscale-backend` Service; three base-tail AWI exclusions)
- `packages/components/hub-management/manifests/spoke-credentials/Secret-cluster-ryzen.yaml` — LEGACY (pre-agent) static hub-side cluster Secret (server `https://ryzen-operator.tail286401.ts.net`, `bearerToken "unused"`). RETIRED for sync — in the agent model the `cluster-ryzen` Secret is the agent MAPPING written by `argocd-agentctl agent create ryzen` (`server: https://argocd-agent-resource-proxy:9090?agentName=ryzen`, embedded mTLS, NO bearerToken). Keep for diagnostics only.
- `packages/components/hub-management/apps/headlamp.yaml` — contains the hub-side `ryzen-api-egress` ExternalName Service with `tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net`
- `packages/components/hub-management/manifests/spoke-secrets/{Namespace-spoke-secrets,ExternalSecret-ryzen-shared-secrets,RBAC-spoke-secrets-reader,Ingress-k8s-api-hub-ingress}.yaml` — the hub mirror + RBAC + standalone Ingress DEVICE that ryzen ESO reads over Tailscale
- `packages/components/tailscale-serve/manifests/tailscale-operator/Deployment-operator.yaml` — shared operator manifest, `OPERATOR_HOSTNAME=ryzen-operator` + `APISERVER_PROXY=true`
- `policy.hujson` — ACL grant `tag:k8s → tag:k8s` (impersonate `tailscale:spoke-secrets-reader`, the surviving ESO read path). The `tag:k8s → tag:k8s-operator` impersonate-system:masters grant was the pre-agent hub→ryzen ArgoCD sync path — LEGACY now that ryzen reconciles locally (still backs the Headlamp kube endpoint).
- `packages/components/hub-spoke-appsets/apps/spoke-clusters-appset.yaml` — the AUTHORITATIVE appset (the `hub-base` copy hardcodes `targetRevision: main` + has the buggy empty `kustomize: {}` and is NOT used; edit the hub-spoke-appsets copy)

## Critical gotchas (failure modes documented in references/)

> The canonical home for the recreate-hardening gotchas below (TS_OPERATOR_CHART_VERSION self-default, root-ryzen repo-server cold-start hard-refresh, Headlamp restart) is `shared-skills/cluster-desired-state/runbooks/recovery-and-gotchas.md` — defer there for full detail. Validation (PR #2395): ryzen `bootstrap-spoke-cluster.sh --recreate` = 13m9s hands-off, 64/65 Synced/Healthy, ZERO manual intervention.

- **Hub→ryzen apiserver-proxy SNI (LEGACY — RETIRED for sync)** — pre-agent, the hub reconciled ryzen's apps over a hub→spoke kube path and the spoke operator's apiserver-proxy (v1.92.4+) STRICTLY validated the wire TLS SNI (only its own hostname `ryzen-operator.tail286401.ts.net`). With the argocd-agent cutover ryzen reconciles LOCALLY, so this whole hub→ryzen ArgoCD-sync path is no longer used. It survives ONLY for (b) the ryzen→hub ESO secret-fetch and the Headlamp kube endpoint. Diagnostics detail (legacy): static `cluster-ryzen` `server: https://ryzen-operator...` + HUB CoreDNS rewrite (`ryzen-operator.tail286401.ts.net → ryzen-api-egress`); the surviving ESO path is `k8s-api-hub-ingress.tail286401.ts.net` + RYZEN CoreDNS rewrite → `k8s-api-hub-egress`.
- **Stale duplicate `ryzen-operator` device after recreate** — a recreate leaves a stale duplicate `ryzen-operator` tailnet device; delete it via the TS API (token minted from the operator-oauth Secret) so the new operator claims the canonical hostname. Verify SNI with `curl --connect-to` forcing the `ryzen-operator` SNI → HTTP 200.
- **Hub-mirror→Tailscale secret transport** — the spoke has NO Azure (no azure-workload-identity, no azure-keyvault-store ClusterSecretStore — verified live NotFound). Ryzen reads hub-mirrored secrets over Tailscale via ClusterSecretStore `hub-secrets-store` (ESO kubernetes provider) → hub ns `spoke-secrets` Secret `ryzen-shared-secrets`. The store URL host is `k8s-api-hub-ingress.tail286401.ts.net`, `caBundle` is hard-set to ISRG Root X1 (REQUIRED - the hub Ingress LE cert chains to it; still required on ESO v2.4.1; ClusterSecretStore manifest is now external-secrets.io/v1), and `bearerToken` is the SA token minted onto the spoke as Secret `external-secrets/hub-secrets-token`. The RYZEN CoreDNS rewrite (`k8s-api-hub-ingress → k8s-api-hub-egress.tailscale.svc.cluster.local`) re-runs every recreate because Talos resets the Corefile. As of 2026-06 the HUB-side `ryzen-shared-secrets` mirror resolves from the `onepassword-store` ClusterSecretStore (onepasswordSDK → hub-eso vault), NOT `azure-keyvault-store` (Azure KV + AWI are dormant). This is transparent to ryzen — the spoke still reads the same hub k8s Secret. JWKS-to-Azure sync is NO LONGER part of any recreate path here.
- **Workload ES repoints** — shared workload manifests hardcode `remoteRef.key=ryzen-shared-secrets`; the ryzen overlay still repoints two workloads off azure: `workflow-builder-secrets` data[9,10,21,22] to the `*-RYZEN` KV keys, and `swebench-runtime-builds` ESes `github-clone-credentials` + `gitea-registry-credentials` onto `hub-secrets-store` / `ryzen-shared-secrets` (`/property` ADDED — source ESes carry only `/key`).
- **Ryzen profile fit: Contour + Kourier, NOT nginx; idpbuilder-local gitea, NO hub gitea ns** — `local-core-ryzen` deletes the `gitea-secretstore` + `nginx-tls-secret` Applications and the `gitea-tailscale-backend` Service (target ns `gitea`, absent on ryzen). External web access on ryzen is via a Tailscale **L4 LoadBalancer Service** (NOT an Ingress, NOT nginx).
- **workflow-builder tailnet exposure = L4 LB + in-cluster HTTPS (PR #2319, NOT LE Ingress)** — workflow-builder is reachable at `https://workflow-builder-ryzen.tail286401.ts.net` via a Tailscale `type: LoadBalancer` Service (`loadBalancerClass: tailscale`, `tailscale.com/hostname: workflow-builder-ryzen`, NO Let's Encrypt). HTTPS is terminated by a per-pod nginx `tls-terminator` sidecar serving the self-signed `*.tail286401.ts.net` wildcard signed by the shared "PittampalliOrg Tailnet Dev CA". The CA is mirrored hub → ns `spoke-secrets` Secret `tailnet-ca` and restored on the spoke by the `tailnet-ca` base app (`packages/base/apps/tailnet-ca.yaml` → `packages/components/tailnet-ca`), which also defines the `tailnet-dev-ca` `ClusterIssuer`. mcp-gateway is NO LONGER on the tailnet (in-cluster only: `MCP_GATEWAY_BASE_URL=http://mcp-gateway.workflow-builder.svc.cluster.local:8080`). The retired LE-Ingress / `development-prod-cert` path (commit `502bccd3c`) and the plain-HTTP-LB interlude (#2314/#2316) are SUPERSEDED — do not re-add them. Browser-only 502 fix = larger sidecar proxy buffers (PR #2327). See `references/failure-modes.md`.
- **gitea-registry-creds is RETIRED fleet-wide (PR #2317)** — the `gitea-registry-creds` imagePullSecret was a dead reference (the Secret was never produced) and was removed from 23 manifests + 2 SAs. All images pull via `ghcr-pull-credentials` from `ghcr.io/pittampalliorg/*`. Do NOT re-add it (the build-side PUSH use in `deployment/scripts/trigger-tekton-builds.sh` is a separate, kept credential).
- **RFC6902 `op: add /spec/source/kustomize` CLOBBER** — a kustomize `op: add` to `/spec/source/kustomize` REPLACES the whole node (last-writer-wins). Both `profiles/local-core-ryzen` AND `overlays/ryzen` op:add to the tailscale-operator's `/spec/source/kustomize`; the overlay runs LAST and wins, so the overlay's tailscale-operator patch must carry BOTH the `PROXY_IMAGE=v1.92.4` env AND the `gitea-tailscale-backend` Service `$patch:delete` co-located. Move the Service delete into the profile block and it gets clobbered → sync fails "namespaces gitea not found". This clobber rule governs every co-located op:add between the two files.
- **kueue ClientSideApplyMigration=false (ryzen-only)** — the ~1.4MB `workloads.kueue.x-k8s.io` CRD wedges ArgoCD 3.4.2's pre-SSA ClientSideApplyMigration step (it writes a >262144-byte last-applied-configuration annotation; argo-cd#26279) whenever the live CRD is not yet argocd-owned. Triggered on ryzen because the CRD was hand-kubectl-applied during recovery (live managedFields owners = kubectl, argocd-controller, kube-apiserver, kueue). Fix = `ClientSideApplyMigration=false` syncOption on the ryzen-only overlay patch (`packages/overlays/ryzen/kustomization.yaml:~261`) — pure SSA, clean ownership transfer, no Workload CR data loss. Harmless no-op on a clean recreate; keep it while kubectl co-owns the CRD.
- **ryzen reads `inner-loop`, NOT `main`** — pushing to `main` alone never reaches ryzen. Advance with `git push origin origin/main:refs/heads/inner-loop`. `spoke-ryzen` is path-based (`packages/overlays/ryzen`, no `kustomize` field) so do NOT mis-diagnose a frozen ryzen as the empty-`drySource.kustomize` hydrator-stall bug — check `targetRevision`/inner-loop first.
- **PodSecurity admission** blocks Tailscale proxy + local-path-provisioner helper pods if their namespaces enforce `baseline:latest`. Label `tailscale` and `local-path-storage` namespaces `pod-security.kubernetes.io/enforce=privileged`. (Spoke-overlay `CreateNamespace=true` can create a bare ns whose baseline PSA rejects local-path hostPath helper pods → PVCs Pending → stateful workloads hang; ryzen is fixed via `managedNamespaceMetadata`.)
- **GHCR_PAT username matters** — use `PittampalliOrg` (org name), not personal username, for image pulls. Source the PAT from KV secret `GITHUB-PAT` (NOT `GHCR-PAT` which doesn't exist); on ryzen this now arrives via the `ryzen-shared-secrets` hub mirror.
- **SWE-bench sandbox pods stay Pending without worker node labels.** The Kueue ResourceFlavor `dev-benchmark` selects nodes by both `stacks.io/swebench-pool=dev-benchmark` AND `node-role.kubernetes.io/worker=""`. Pre-A6 KIND ryzen got these from kind-config kubeadm extraArgs; post-A6 Talos doesn't. `bootstrap-spoke-cluster.sh` now applies the labels after kube-api is up (commit 9871c7217); if you bootstrap with an older script, apply them manually.
- **Headlamp's per-cluster bearer tokens are baked into a kubeconfig at pod start.** The init container (`generate-kubeconfig`) reads cluster Secrets ONCE and renders them into an emptyDir volume. If the ryzen kube endpoint/CA/token is rotated (i.e. after EVERY recreate), the hub Headlamp pods that predate the recreate keep serving the OLD spoke endpoint and the freshly-staged `headlamp-cluster-ryzen` Secret is inert → the UI shows "Failed to get authentication information: ryzen". `enroll-ryzen-agent.sh` step 5b now handles this automatically: it re-stages the `headlamp-cluster-ryzen` Secret (fresh endpoint + read-only SA token + CA, label `headlamp.dev/cluster=true`) and then `kubectl -n headlamp rollout restart deploy/hub-headlamp deploy/hub-headlamp-embedded` on the hub (PR #2395 commit `6cee88a70`; guarded on deploy existence, non-fatal). If repairing by hand, do both — re-stage the Secret AND restart both Deployments.
- **root-ryzen repo-server cold-start race (~5min convergence stall)** — on a fresh recreate the local `argocd-application-controller` runs `root-ryzen`'s FIRST comparison before the local `argocd-repo-server` is accepting connections (dial `:8081` connection refused) → `root-ryzen` sticks in `ComparisonError` (sync=Unknown), and the controller does NOT re-queue the errored app for a full resync window (~5min observed) → convergence stalls with ZERO child apps rendered until a manual refresh. Fixed by forcing a clean first comparison after the local repo-server is Available: `enroll-ryzen-agent.sh` step 6b waits `rollout status deploy/argocd-repo-server` then hard-refreshes `root-ryzen` (`argocd.argoproj.io/refresh=hard`), and `bootstrap-spoke-cluster.sh` step 10 hard-refreshes again after the inner-loop advance (re-compare vs the advanced HEAD). Both non-fatal — the resync timer would eventually heal it; this makes the recreate hands-off + fast (PR #2395 commit `89fd0df8b`).
- **ArgoCD 3.4 stricter ServerSideApply rejects unknown schema fields.** Examples we hit: `terminationGracePeriodSeconds` on Knative Service (gated behind a feature flag) and Tekton Pipelines/Tasks where the mutating webhook injects empty defaults (`computeResources: {}`, `metadata: {}`, etc.). Either remove the field from source or add `ignoreDifferences` with jq path expressions covering the operator-injected paths.
