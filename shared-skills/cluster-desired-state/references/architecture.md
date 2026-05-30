# Cross-cutting architecture

The shared machinery every cluster build/recreate relies on. Per-cluster specifics
live in `hub.md`, `ryzen.md`, `dev.md`; failure modes in
`../runbooks/recovery-and-gotchas.md`.

All file paths are relative to `/home/vpittamp/repos/PittampalliOrg/stacks/main`.

---

## 1. Topology

One **hub** (Talos/Hetzner, 5 nodes, Flannel CNI, k8s v1.32.0) is the sole ArgoCD
instance and the central Tekton build pool. It renders each spoke from
`packages/overlays/<spoke>` and reconciles workloads onto the spoke through an
argocd **cluster Secret**. Spokes run **no** local ArgoCD/Gitea/Tekton.

- **hub**: management plane + builds. 3x cpx41 control-plane + 2x ccx33 build nodes
  (labeled/tainted `stacks.io/build-pool=hub`).
- **ryzen**: bare-metal Talos-in-Docker local-dev spoke on the ryzen workstation
  (3 nodes, Talos v1.13.2 / k8s v1.36.0). Imperatively bootstrapped.
- **dev**: disposable Hetzner Talos spoke (3 cpx41 CP + 6 cpx51 workers labeled
  `stacks.io/swebench-pool=dev-benchmark`). Crossplane-provisioned.

---

## 2. GitOps branch flow (the #1 operational gotcha)

```
        drySource (main / inner-loop)
                |  ArgoCD source-hydrator renders packages/overlays/<env>
                v
        env/<env>-next         (hydrateTo)
                |  GitOps Promoter PR  (autoMerge:false on hub -> human merges)
                v
        env/<env>              (syncSource)  <-- ArgoCD actually syncs from here
```

| Cluster | drySource branch | hydrateTo | syncSource (ArgoCD reads) | Promoter? |
|---|---|---|---|---|
| hub | `main` | `env/hub-next` | `env/hub` path `hub-apps/` | yes (`stacks-environments`, manual merge) |
| dev | `main` | `env/spokes-dev-next` | `env/spokes-dev` path `dev-apps` | yes |
| staging | `main` | `env/spokes-staging-next` | `env/spokes-staging` | yes |
| ryzen | **`inner-loop`** | `env/spokes-ryzen` | `env/spokes-ryzen` path `ryzen-apps` | **no** |

**Consequences:**
- A push to `main` reaches **hub** only after the `env/hub-next -> env/hub` Promoter
  PR is merged (autoMerge:false). It reaches **dev/staging** after their
  `env/spokes-<env>-next -> env/spokes-<env>` PR. It reaches **ryzen** only after you
  advance inner-loop: `git push origin origin/main:refs/heads/inner-loop` (clean
  fast-forward when inner-loop is strictly behind main).
- **ryzen is path-based** (`drySource.path` only, no `kustomize` field) — a frozen
  ryzen is almost never the empty-`drySource.kustomize` hydrator-stall bug; check
  `targetRevision=inner-loop` and inner-loop freshness first.
- The hub source-hydrator does NOT auto hard-refresh
  (`timeout.hard.reconciliation:0s`). If the drySHA is stale, remove
  `/status/sourceHydrator/currentOperation` + `lastSuccessfulOperation` and annotate
  a hard-refresh (see `gitops` skill).

Verify branch freshness:
```bash
git -C /home/vpittamp/repos/PittampalliOrg/stacks/main rev-list --count origin/inner-loop..origin/main   # 0 = ryzen current
git ls-remote origin env/hub env/spokes-dev                                                             # branches advancing
```

---

## 3. Contract 1 — the argocd cluster-Secret (registration)

A spoke is registered on the hub by a Secret in ns `argocd`:

- Labels: `argocd.argoproj.io/secret-type=cluster`, `stacks.io/hub-managed=true`,
  `stacks.io/cluster-role=spoke`, `stacks.io/platform=talos`. Add
  `workload.stacks.io/workflow-builder=true` to make the workloads-appset generate a
  `spoke-<name>-workflow-builder` app (dev/staging do; **ryzen intentionally omits
  it** — its overlay composes workflow-builder-system directly).
- Annotations: `spoke-cluster=<name>`, `stacks.io/source-branch=<branch>`
  (ryzen=`inner-loop`, others default `main`), `stacks.io/auth-mode=<mode>`.

How each cluster supplies it:
- **dev/staging**: `ExternalSecret-cluster-talos.yaml` materializes `cluster-<name>`
  from KV `ARGOCD-CLUSTER-{TALOS,...}-TOKEN/CA`; OR the Crossplane group-5
  spoke-register job writes it directly to the hub (`server` = direct public IP
  `https://<ip>:6443`).
- **ryzen**: `ExternalSecret-cluster-ryzen.yaml` materializes `cluster-ryzen` from KV
  `ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}` (minted per-recreate by `register-spoke
  --ts-host-passthrough`): `server: https://ryzen.tail286401.ts.net:6443`,
  `insecure:false` + `caData` (Talos CA), real SA `bearerToken`. The old static
  `Secret-cluster-ryzen.yaml` (operator FQDN, `bearerToken:"unused"`,
  `auth-mode=tailscale-acl-impersonation`) was DELETED (PR #2308) — ryzen now reaches its
  apiserver via the Tailscale host TCP passthrough (§5).

The **spoke-clusters-appset** (cluster generator,
`packages/components/hub-spoke-appsets/apps/spoke-clusters-appset.yaml`) templates a
`spoke-<name>` Application:
```yaml
targetRevision: '{{- $sb := index .metadata.annotations "stacks.io/source-branch" -}}{{- if $sb -}}{{ $sb }}{{- else -}}main{{- end -}}'
syncSource:  { targetBranch: 'env/spokes-{{index .metadata.annotations "spoke-cluster"}}' }
hydrateTo:   { targetBranch: '<...>-next for dev/staging, else env/spokes-<name>' }
```
> GOTCHA: a SECOND copy at `packages/components/hub-base/apps/spoke-clusters-appset.yaml`
> hardcodes `targetRevision: main` and has the buggy empty `kustomize: {}`
> (hydrator-stall trap). The hub uses the **hub-spoke-appsets** copy (referenced by
> `packages/overlays/hub/kustomization.yaml`). Edit that one, not hub-base's.

---

## 4. Contract 2 — AWI -> Tailscale secret transport

The hub stays canonical (Azure KV `keyvault-thcmfmoo5oeow` + Workload Identity).
Spokes no longer authenticate to Azure AD. Contract spec:
`packages/components/spoke-tailscale-secrets/CONTRACT.md`.

**Hub side** (GitOps, `packages/components/hub-management/manifests/spoke-secrets/`):
- `Namespace-spoke-secrets.yaml`.
- `ExternalSecret-<cluster>-shared-secrets.yaml` — mirrors every KV secret the
  cluster consumes from `azure-keyvault-store` into Secret `<cluster>-shared-secrets`
  (dev ~79-80 keys, ryzen ~77 keys, incl. `*-DEV` / `*-RYZEN` OAuth overrides).
- `RBAC-spoke-secrets-reader.yaml` — dual-path: ServiceAccount `spoke-secrets-reader`
  (bearer-token, the active standalone-Ingress path) AND Group
  `tailscale:spoke-secrets-reader` (impersonation, ProxyGroup path). Both scoped to
  get/list/watch secrets in `spoke-secrets` only + cluster-wide create on
  selfsubjectrules/accessreviews (ESO store validation, else NotReady).
- `Ingress-k8s-api-hub-ingress.yaml` — standalone Tailscale Ingress **device**
  `k8s-api-hub-ingress` (ns default, `defaultBackend kubernetes:443`, LE cert).
  Chosen over the ProxyGroup VIPService because the VIP route never propagates into
  a spoke egress netmap; the standalone device does.

**Spoke side**
(`packages/components/spoke-tailscale-secrets/manifests/spoke-transport/`):
- `ClusterSecretStore-hub-secrets-store.yaml` — ESO kubernetes provider, server
  `https://k8s-api-hub-ingress.tail286401.ts.net`, **`caBundle` hard-coded to ISRG
  Root X1** (REQUIRED by ESO v0.9.13's webhook), bearerToken = SA token minted onto
  the spoke as Secret `external-secrets/hub-secrets-token` (key `token`).
- `Service-k8s-api-hub-egress.yaml` — ExternalName egress (operator rewrites
  `.spec.externalName` at runtime; the `dev-spoke-transport` app shows this Service
  permanently OutOfSync/Healthy — EXPECTED, do not chase).
- **Spoke CoreDNS rewrite** (re-applied every recreate — Talos resets the Corefile):
  `rewrite name exact k8s-api-hub-ingress.tail286401.ts.net k8s-api-hub-egress.tailscale.svc.cluster.local`
  after the `ready` plugin line, then rollout-restart coredns.

Delivery differs by cluster:
- **dev/staging**: GitOps via `packages/overlays/dev` listing
  `components: [../../components/spoke-tailscale-secrets]` (the `spoke-transport` App).
- **ryzen**: IMPERATIVE — `packages/overlays/ryzen` does NOT list
  `spoke-tailscale-secrets`; the static half is applied by
  `deployment/scripts/lib/spoke-transport-bootstrap.sh` (invoked from
  `bootstrap-spoke-cluster.sh`) using `deployment/manifests/spoke-transport/`.

ACL grants (`policy.hujson`):
- ryzen->hub ESO read: `src tag:k8s -> dst tag:k8s impersonate.groups=[tailscale:spoke-secrets-reader]`.
- hub->ryzen ArgoCD: now plain tailnet TCP to the ryzen host serve (`tag:k8s -> tag:k8s`,
  port 6443); the SA bearer token (not impersonation) authenticates. The legacy
  `tag:k8s -> tag:k8s-operator app tailscale.com/cap/kubernetes
  impersonate.groups=[system:masters]` grant only applies to the deprecated `--ts-acl-mode`
  operator-proxy path (§5).

---

## 5. hub -> spoke connectivity (ryzen = Tailscale host TCP passthrough)

dev's public API is reachable, so its cluster-Secret `server` is the **direct IP**
`https://<ip>:6443` — no SNI workaround.

ryzen reaches its Talos kube-apiserver **DIRECTLY over Tailscale via the ryzen HOST
device** (`ryzen.tail286401.ts.net`, `100.96.102.1`, `tag:k8s`) running
`tailscale serve --bg --tcp=6443` as a **raw TCP passthrough** to the Talos apiserver.
This is the CANONICAL, durable path — it drops the Tailscale operator apiserver-proxy
(and its per-hostname Let's Encrypt cert) entirely. No SNI workaround.

- **Host serve.** nixos-config `services.tailscaleK8sApiserver` defines a
  `tailscale-serve-k8s-apiserver` oneshot unit that auto-discovers the Talos-in-Docker
  apiserver host port and runs `tailscale serve --bg --tcp=6443`. The stacks bootstrap
  restarts this unit after each cluster create (Docker re-maps the port).
- **End-to-end TLS, no termination.** Raw TCP passthrough does NOT terminate TLS, so
  the **Talos apiserver's own serving cert reaches the hub end-to-end** and the hub does
  a **FULL TLS verify (`insecure:false`)** against the Talos CA. The apiserver cert
  carries `cluster.apiServer.certSANs: [ryzen.tail286401.ts.net, 100.96.102.1]`
  (added by the bootstrap `--config-patch`). No `serverName` / no SNI hack.
- **Auth = per-recreate ServiceAccount bearer token.** `register-spoke
  --ts-host-passthrough` mints an SA token + Talos CA into Azure KV
  (`ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}`). The hub
  `ExternalSecret-cluster-ryzen.yaml` (NOT a static Secret — the static one was deleted,
  PR #2308) materializes `cluster-ryzen` from KV: `server:
  https://ryzen.tail286401.ts.net:6443`, `insecure:false` + `caData`, `bearerToken`.
- **Hub egress + CoreDNS.** `ryzen-api-egress` ExternalName Service (ns `tailscale`,
  annotation `tailscale.com/tailnet-fqdn: ryzen.tail286401.ts.net`, port `6443`) is
  defined inline in `packages/components/hub-management/apps/headlamp.yaml`
  (extraManifests). A self-healing hub CoreDNS rewrite
  `ryzen.tail286401.ts.net -> ryzen-api-egress.tailscale.svc.cluster.local`
  (maintained by `CronJob-coredns-spoke-rewrites`) routes the name to the in-cluster egress.

**WHY this replaced the operator apiserver-proxy.** The old path rode the operator
apiserver-proxy's per-hostname Let's Encrypt cert. Recreate churn exhausted LE's
5-duplicate-certs/week limit and took the whole ryzen fleet to 0-healthy (2026-05-29
incident). Host passthrough drops the LE dependency: a recreate now consumes ZERO LE
quota (validated). PRs #2305 / #2307.

Verify by confirming the materialized cluster-Secret `server` and ryzen app health:
```bash
kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret cluster-ryzen \
  -o jsonpath='{.data.server}' | base64 -d    # https://ryzen.tail286401.ts.net:6443
# optional full verify (real TLS, no --insecure):
kubectl --server=https://ryzen.tail286401.ts.net:6443 \
  --certificate-authority=<Talos CA> --token=<SA token> get nodes
```
The old SNI `curl --connect-to ... :443` check is obsolete.

> LEGACY: `--ts-acl-mode` (operator apiserver-proxy + impersonation +
> `OPERATOR_HOSTNAME=ryzen-operator`) still exists for other Tailscale-proxy spokes but is
> **deprecated for ryzen**. dev/staging use the direct public IP, not the proxy.

---

## 6. Per-cluster ExternalSecret parameterization

Shared workload manifests hardcode `remoteRef.key=ryzen-shared-secrets`. Each
non-ryzen cluster must re-point its workload ExternalSecrets onto its OWN mirror:

- **dev** (and staging): `scripts/gitops/render-workflow-builder-release-overlays.sh`
  loops dev+staging, reads release-pins
  `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml`,
  and writes `packages/components/workloads/workflow-builder-system-overlays/<cluster>/kustomization.yaml`.
  All dev-specific repoints are GATED `[ "${cluster}" = "dev" ]` so staging stays
  byte-identical. Helpers:
  - `emit_es_key_repoint <es> <indices>` — key-only swap to `dev-shared-secrets`.
  - `emit_es_store_repoint <es> <orig-key>` — switch store->`hub-secrets-store`,
    key->`dev-shared-secrets`, add `property=<orig-key>` (for ESes retired off azure
    like `github-clone-credentials`, `gitea-registry-credentials`).
  - `emit_oauth_op` — `workflow-builder-secrets` OAuth -> `*-DEV` via property.
  Regenerate after any release-pin/ES change; CI uses `--check`.
- **ryzen**: re-pointed inline in `packages/overlays/ryzen/kustomization.yaml`:
  - `workflow-builder-secrets` data[9,10,21,22] -> `*-RYZEN` OAuth keys via op:test+op:replace.
  - `github-clone-credentials` + `gitea-registry-credentials` -> `hub-secrets-store`,
    key `ryzen-shared-secrets`, `/property` added.

---

## 7. Contract 3 — web exposure + persistent self-signed CA

workflow-builder is reachable at `https://workflow-builder-{dev,ryzen,staging}.tail286401.ts.net`
over a **Tailscale L4 LoadBalancer**, with HTTPS terminated **in-cluster** by a per-pod
nginx `tls-terminator` sidecar serving a **persistent self-signed `*.tail286401.ts.net`
wildcard**. NO Let's Encrypt, NO Tailscale Ingress. PR #2319.

> **Why this replaced the old LE Tailscale Ingress.** dev/staging/ryzen used to expose
> workflow-builder + mcp-gateway via a Tailscale-class Ingress (`ingressClassName: tailscale`)
> with a per-hostname **Let's Encrypt** cert (ProxyClass `development-prod-cert`). Recreate
> churn exhausted LE's 5-certs/168h limit -> 429 -> unreachable. (ryzen briefly used a plain-HTTP
> Tailscale LoadBalancer, PRs #2314/#2316 — also superseded.) The dev/staging overlays now
> `$patch:delete` the old workflow-builder/mcp-gateway Tailscale Ingresses.

The end-to-end chain:

```
Azure KV  TAILNET-DEV-CA-CRT / TAILNET-DEV-CA-KEY   ("PittampalliOrg Tailnet Dev CA", 10-yr, offline-generated once)
        |  hub ExternalSecret-tailnet-ca.yaml  (CLUSTER-NEUTRAL mirror)
        v
hub ns spoke-secrets  Secret `tailnet-ca`           (namespace-wide spoke-secrets-reader Role -> every spoke reads the SAME key)
        |  spoke ExternalSecret over hub-secrets-store (Contract 2 transport)
        v
spoke cert-manager  Secret `tailnet-dev-ca`         (CA restored on the spoke)
        |  CA ClusterIssuer `tailnet-dev-ca`
        v
`*.tail286401.ts.net` wildcard Certificate          (in the workflow-builder ns)
        |  mounted by the tls-terminator nginx sidecar
        v
Tailscale L4 LoadBalancer Service -> sidecar :443 (HTTPS) -> workflow-builder
```

**Pieces:**
- **CA in KV.** `TAILNET-DEV-CA-CRT` / `TAILNET-DEV-CA-KEY` — generated once offline,
  10-year, stable across cluster recreation. Same CA on every cluster, so clients trust
  it ONCE and the trust survives recreation (improves on idpbuilder's per-install CA).
- **Hub mirror** (`packages/components/hub-management/manifests/spoke-secrets/ExternalSecret-tailnet-ca.yaml`):
  mirrors the CA CLUSTER-NEUTRALLY into ns `spoke-secrets` Secret `tailnet-ca`. The
  `spoke-secrets-reader` Role is namespace-wide, so there is **no per-cluster CA key**.
  (ignoreDifferences for the ESO-added fields, PR #2322.)
- **Spoke restore** (`packages/components/tailnet-ca`, delivered via
  `packages/base/apps/tailnet-ca.yaml` — **spoke-only**; the hub does NOT consume
  `packages/base`): an ExternalSecret (`hub-secrets-store`) restores the CA into
  `cert-manager/tailnet-dev-ca`; the `tailnet-dev-ca` **CA `ClusterIssuer`** signs the
  `*.tail286401.ts.net` wildcard Certificate (`Certificate-tailnet-wildcard.yaml`, in the
  workflow-builder ns).
- **L4 LoadBalancer + sidecar.** `type: LoadBalancer`, `loadBalancerClass: tailscale`,
  annotation `tailscale.com/hostname`, 443->https-tls. The nginx `tls-terminator` sidecar
  + its ConfigMap live in `packages/components/workloads/workflow-builder/manifests/`
  (Deployment sidecar + `ConfigMap-workflow-builder-tls-terminator.yaml`). Service files:
  base `packages/base/manifests/tailscale-ingresses/Service-workflow-builder-tailnet.yaml`
  (dev/staging, CLUSTER-templated); ryzen `packages/components/workloads/workflow-builder-tailnet-lb/`.
- **mcp-gateway is in-cluster ONLY** now (dropped from the tailnet). `MCP_GATEWAY_BASE_URL`
  -> `http://mcp-gateway.workflow-builder.svc.cluster.local:8080`. `ORIGIN` /
  `APP_PUBLIC_URL` stay `https://workflow-builder-<cluster>.tail286401.ts.net` (ryzen's
  #2316 http flip was reverted).
- **Workstation trust** (vpittamp/nixos-config, commit 44ba6324): to open the URLs without
  a cert warning clients must trust the CA — `modules/services/cluster-certs.nix`
  (`security.pki.certificates` for system/curl/git) AND `home-modules/tools/chromium.nix`
  (`home.activation` certutil seed of `~/.pki/nssdb` — REQUIRED because `security.pki` does
  NOT cover Chrome's own NSS db on NixOS). The old `CNOE Local Development CA`
  (`*.cnoe.localtest.me`) idpbuilder trust is still present.

---

## 8. Where everything lives (file map)

```
packages/overlays/hub/kustomization.yaml                 # hub root composition + cluster-config
packages/overlays/ryzen/kustomization.yaml               # ryzen overlay (namePrefix ryzen-, ES repoints, kueue patch)
packages/overlays/dev/kustomization.yaml                 # dev overlay (inherits ../talos)
packages/components/hub-base/                             # hub- infra apps, ProxyGroup-kube-apiserver.yaml
packages/components/hub-management/                       # Promoter, headlamp, spoke-credentials/, spoke-secrets/
  .../spoke-credentials/ExternalSecret-cluster-ryzen.yaml # ryzen registration (KV ARGOCD-CLUSTER-RYZEN-*, host TCP passthrough)
  .../spoke-credentials/ExternalSecret-cluster-talos.yaml # dev/staging registration
  .../spoke-secrets/{Namespace,ExternalSecret-<c>-shared-secrets,RBAC-spoke-secrets-reader,Ingress-k8s-api-hub-ingress}.yaml
  .../spoke-secrets/ExternalSecret-tailnet-ca.yaml        # Contract 3: cluster-neutral CA mirror -> Secret tailnet-ca
  .../manifests/tailnet-device-sweeper/CronJob-tailnet-device-sweeper.yaml  # offline stale-device hygiene backstop (every 15m)
  .../apps/headlamp.yaml                                  # ryzen-api-egress Service (inline extraManifests)
packages/components/tailnet-ca/manifests/{ExternalSecret-tailnet-ca,ClusterIssuer-tailnet-ca}.yaml  # spoke CA restore + CA ClusterIssuer
packages/base/apps/tailnet-ca.yaml                       # spoke-only tailnet-ca App (hub does NOT consume packages/base)
packages/base/manifests/tailscale-ingresses/Service-workflow-builder-tailnet.yaml  # dev/staging L4 LB (CLUSTER-templated, 443->https-tls)
packages/components/workloads/workflow-builder-tailnet-lb/                # ryzen L4 LB Service
packages/components/workloads/workflow-builder/manifests/{ConfigMap-workflow-builder-tls-terminator,Certificate-tailnet-wildcard}.yaml  # nginx sidecar + wildcard cert
packages/components/hub-spoke-appsets/apps/{spoke-clusters,spoke-workloads}-appset.yaml
packages/components/spoke-tailscale-secrets/             # CONTRACT.md + spoke-transport manifests
packages/components/profiles/local-core-ryzen/           # ryzen profile (Contour+Kourier, AWI/profile exclusions)
packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/
  TalosSpokeClusterClaim-dev.yaml, Composition-talospokecluster.yaml, CompositeResourceDefinition-talospokecluster.yaml
packages/components/tailscale-serve/manifests/tailscale-operator/Deployment-operator.yaml
deployment/scripts/bootstrap-spoke-cluster.sh            # ryzen imperative bootstrap
deployment/scripts/lib/spoke-transport-bootstrap.sh      # ryzen imperative transport apply
scripts/gitops/render-workflow-builder-release-overlays.sh
policy.hujson                                            # Tailscale ACL grants
```

## Access

```bash
# hub
kubectl --kubeconfig ~/.kube/hub-config ...          # context admin@hub-cluster; from ryzen host no ssh wrapper
# remote VIP: context hub-cluster (k8s-api-hub.tail286401.ts.net)
# ryzen
kubectl --context admin@ryzen ...
# dev
kubectl --context admin@dev ...                      # refresh after recreate; may point at a stale worker IP
# break-glass spoke kubeconfig from the hub (Crossplane spokes):
kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system get secret <spoke>-XXXXX-kubeconfig \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/<spoke>-kubeconfig
```
