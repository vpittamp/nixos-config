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
- **ryzen**: STATIC committed
  `packages/components/hub-management/manifests/spoke-credentials/Secret-cluster-ryzen.yaml`
  (`server: https://ryzen-operator.tail286401.ts.net`, `bearerToken: "unused"`,
  `auth-mode=tailscale-acl-impersonation`, no KV token / no JWKS).

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
- hub->ryzen ArgoCD: `src tag:k8s -> dst tag:k8s-operator app tailscale.com/cap/kubernetes impersonate.groups=[system:masters]`.

---

## 5. hub -> spoke connectivity (apiserver-proxy SNI/CoreDNS, ryzen-only)

dev's public API is reachable, so its cluster-Secret `server` is the **direct IP**
`https://<ip>:6443` — no SNI workaround.

ryzen sits behind the Tailscale operator apiserver-proxy (operator v1.92.4) which
**STRICTLY validates the wire SNI == its own hostname**, and ArgoCD does **not** send
`tlsClientConfig.serverName` as the wire SNI (verified: even with `serverName` +
`caData`, ArgoCD sends the server-URL host as SNI). So:
- cluster-Secret `server: https://ryzen-operator.tail286401.ts.net` (the SNI comes
  from the server-URL host); config carries `insecure:true`, `serverName:ryzen-operator...`,
  `bearerToken:"unused"`.
- **HUB** CoreDNS rewrite
  `ryzen-operator.tail286401.ts.net -> ryzen-api-egress.tailscale.svc.cluster.local`
  routes the name to the in-cluster egress while the SNI stays correct.
- `ryzen-api-egress` ExternalName Service (ns `tailscale`, annotation
  `tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net`) is defined inline
  in `packages/components/hub-management/apps/headlamp.yaml` (extraManifests).
- Spoke operator (`packages/components/tailscale-serve/manifests/tailscale-operator/Deployment-operator.yaml`):
  `OPERATOR_HOSTNAME=ryzen-operator`, `APISERVER_PROXY=true`,
  `OPERATOR_INITIAL_TAGS=tag:k8s-operator`, `PROXY_TAGS=tag:k8s`.

Verify with curl forcing the SNI:
```bash
curl -k --connect-to ryzen-operator.tail286401.ts.net:443:<egress>:443 \
  https://ryzen-operator.tail286401.ts.net/version   # expect HTTP 200
```

> NOTE: the shared operator manifest hardcodes `OPERATOR_HOSTNAME=ryzen-operator`,
> so the HUB operator device is also named `ryzen-operator` — a latent collision
> risk, flag it if hub operator device-name issues arise. The hub does NOT depend on
> its own operator apiserver-proxy for spoke connectivity (spokes reach hub kube-api
> via the separate `k8s-api-hub-ingress` device; remote kubectl via the `k8s-api-hub`
> ProxyGroup VIP).

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

## 7. Where everything lives (file map)

```
packages/overlays/hub/kustomization.yaml                 # hub root composition + cluster-config
packages/overlays/ryzen/kustomization.yaml               # ryzen overlay (namePrefix ryzen-, ES repoints, kueue patch)
packages/overlays/dev/kustomization.yaml                 # dev overlay (inherits ../talos)
packages/components/hub-base/                             # hub- infra apps, ProxyGroup-kube-apiserver.yaml
packages/components/hub-management/                       # Promoter, headlamp, spoke-credentials/, spoke-secrets/
  .../spoke-credentials/Secret-cluster-ryzen.yaml         # static ryzen registration
  .../spoke-credentials/ExternalSecret-cluster-talos.yaml # dev/staging registration
  .../spoke-secrets/{Namespace,ExternalSecret-<c>-shared-secrets,RBAC-spoke-secrets-reader,Ingress-k8s-api-hub-ingress}.yaml
  .../apps/headlamp.yaml                                  # ryzen-api-egress Service (inline extraManifests)
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
