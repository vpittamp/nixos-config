# RYZEN — desired state + path

A hub-managed, **bare-metal Talos-in-Docker** local-development spoke on the ryzen
workstation. Unlike dev/staging it is bootstrapped **imperatively** (no Crossplane).
Shared model in `architecture.md`; recreate steps in `../runbooks/recreate-ryzen.md`;
deep bootstrap mechanics in the `ryzen-spoke-bootstrap` skill. Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`.

## Desired state

**Topology / identity**
- 3 nodes (ryzen-controlplane-1 + ryzen-worker-1/2), OS-IMAGE `Talos (v1.13.2)`,
  k8s v1.36.0, containerd 2.2.3, subnet 10.6.0.0/24. (CP 4GiB/3cpu, 2 workers
  13GiB/5cpu, exposes 9443:443.)
- Registered by the STATIC argocd cluster Secret `cluster-ryzen`
  (`packages/components/hub-management/manifests/spoke-credentials/Secret-cluster-ryzen.yaml`):
  labels secret-type=cluster, cluster-role=spoke, hub-managed=true, platform=talos;
  `workload.stacks.io/workflow-builder` is **intentionally OMITTED** (the overlay
  composes workflow-builder-system directly). Annotations spoke-cluster=ryzen,
  `stacks.io/source-branch=inner-loop`, `stacks.io/auth-mode=tailscale-acl-impersonation`.

**Rendering / sync**
- The hub spoke-clusters appset materializes `spoke-ryzen`: drySource path
  `packages/overlays/ryzen`, `targetRevision=inner-loop`, hydrateTo/syncSource
  `env/spokes-ryzen` path `ryzen-apps`. (Path-based, no `kustomize` field.)
- `packages/overlays/ryzen` applies namePrefix `ryzen-` and rewrites every child
  Application's destination from `kubernetes.default.svc` to `destination.name=ryzen`.
  It composes 3 components: `profiles/local-core-ryzen`, `workloads/workflow-builder-system`,
  `addons/observability-clickhouse-client`.
- DESIRED: all `ryzen-*` child apps Synced/Healthy (~59 apps).

**Profile fit** (Contour+Kourier, idpbuilder-local gitea, no Azure)
- Ingress is **Contour + Kourier** (+ Knative net-kourier), **NOT ingress-nginx**.
- gitea is idpbuilder-local; there is **NO hub-managed `gitea` namespace**.
- **No Azure Workload Identity / azure-keyvault-store on the spoke.** Only
  ClusterSecretStores are `argocd`, `default-namespace`, and `hub-secrets-store`.

**Secret transport** (Contract 2)
- ESO `ClusterSecretStore hub-secrets-store` reads hub ns `spoke-secrets` Secret
  `ryzen-shared-secrets` over Tailscale. Ready=True; `hub-secrets-token` in ns
  external-secrets; spoke CoreDNS rewrite present; ESes SecretSynced/Valid.

**Hub->ryzen connectivity** (SNI/CoreDNS — the ryzen-only path)
- cluster-ryzen `server = https://ryzen-operator.tail286401.ts.net`; HUB CoreDNS
  rewrite `ryzen-operator... -> ryzen-api-egress.tailscale.svc.cluster.local`; hub ns
  `tailscale` Service `ryzen-api-egress` ExternalName with
  `tailnet-fqdn=ryzen-operator.tail286401.ts.net`; spoke operator
  OPERATOR_HOSTNAME=ryzen-operator, APISERVER_PROXY=true. See `architecture.md` §5.

**Branch**: ryzen tracks `inner-loop`, NOT `main`.

## Path to state (ordered)

1. **PROVISION (imperative).** `deployment/scripts/bootstrap-spoke-cluster.sh` on the
   ryzen host. Canonical recreate:
   `bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate --ts-acl-mode`
   (`--ts-acl-mode` = Tailscale-ACL hub<->spoke, no Azure bearer token / no JWKS+AAD
   wait). Produces bare Talos-Docker with ONLY: Tailscale operator (helm), the
   ProxyGroup/ProxyClass for kube-api exposure, hub-spoke SA+CRB. It does NOT install
   cert-manager/ESO/ArgoCD/gitea/tekton/observability/workflow-builder — the hub
   deploys all of those via rendered child Applications. Requires env
   `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_CLIENT_SECRET`.
2. **GITOPS REGISTRATION** (Contract 1). The static `Secret-cluster-ryzen.yaml` is
   GitOps-delivered (referenced from `hub-management/kustomization.yaml`). The
   **hub-spoke-appsets** spoke-clusters-appset templates `spoke-ryzen` with
   `targetRevision=inner-loop`. (Edit the hub-spoke-appsets copy, not the hub-base
   copy — see `architecture.md` §3.)
3. **SECRET TRANSPORT** (Contract 2, spoke side is IMPERATIVE for ryzen). The
   `hub-secrets-store` CSS + egress Service are applied by
   `deployment/scripts/lib/spoke-transport-bootstrap.sh` (invoked from
   `bootstrap-spoke-cluster.sh`) using `deployment/manifests/spoke-transport/`. The
   **spoke** CoreDNS rewrite (`k8s-api-hub-ingress... -> k8s-api-hub-egress...`) is
   re-applied every recreate (Talos resets the Corefile). The hub mirror
   (`ExternalSecret-ryzen-shared-secrets.yaml`) + RBAC + Ingress device are GitOps on
   the hub side. See `architecture.md` §4.
4. **HUB->RYZEN CONNECTIVITY** (SNI/CoreDNS, §5). After a recreate a **stale duplicate
   `ryzen-operator` tailnet device** lingers — delete it via the TS API (token minted
   from the operator-oauth Secret), else the operator suffixes `-1`. Verify SNI with
   `curl --connect-to` -> HTTP 200.
5. **WORKLOAD ES REPOINTING** (inline in `packages/overlays/ryzen/kustomization.yaml`):
   `workflow-builder-secrets` data[9,10,21,22] -> `*-RYZEN` OAuth keys;
   `github-clone-credentials` + `gitea-registry-credentials` -> `hub-secrets-store`,
   key `ryzen-shared-secrets`, `/property` added. See `architecture.md` §6.
6. **DEPLOY content to ryzen.** ryzen NEVER reads main. Fast-forward inner-loop:
   `git push origin origin/main:refs/heads/inner-loop`. The hydrator re-dispatches
   drySHA -> renders `packages/overlays/ryzen` -> pushes `env/spokes-ryzen`; ryzen-*
   apps reconcile.

## Verification

```bash
C="kubectl --context admin@ryzen"
$C get nodes -o wide                                   # Talos v1.13.2 / k8s v1.36.0
$C get pods -A | grep -iE 'contour|kourier|nginx'      # contour+kourier, ZERO nginx
$C get ns gitea                                         # NotFound (expected)
$C get clustersecretstore hub-secrets-store             # Ready=True
$C -n external-secrets get secret hub-secrets-token
$C -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep 'rewrite name'
$C get externalsecrets -A                               # all SecretSynced/Valid

K=~/.kube/hub-config
kubectl --kubeconfig $K -n argocd get application spoke-ryzen           # Synced/Healthy, rev=inner-loop
kubectl --kubeconfig $K -n argocd get applications | grep '^ryzen-'     # all Synced/Healthy
kubectl --kubeconfig $K -n argocd get secret cluster-ryzen -o jsonpath='{.data.server}' | base64 -d   # https://ryzen-operator.tail286401.ts.net
kubectl --kubeconfig $K -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep ryzen-operator
kubectl --kubeconfig $K -n tailscale get svc ryzen-api-egress
git -C /home/vpittamp/repos/PittampalliOrg/stacks/main rev-list --count origin/inner-loop..origin/main   # 0 = current
```

## Ryzen-specific gotchas (see `../runbooks/recovery-and-gotchas.md` for fixes)

- **RFC6902 `op: add /spec/source/kustomize` clobber** — both
  `profiles/local-core-ryzen` AND `overlays/ryzen` op:add to tailscale-operator's
  `/spec/source/kustomize`; last-writer-wins. The OVERLAY block must carry BOTH the
  PROXY_IMAGE=v1.92.4 env AND the `gitea-tailscale-backend` Service `$patch:delete`
  co-located, or sync fails "namespaces gitea not found".
- **kueue `ClientSideApplyMigration=false`** (ryzen-only, `packages/overlays/ryzen/kustomization.yaml:261`)
  — the ~1.4MB `workloads.kueue.x-k8s.io` CRD wedges ArgoCD 3.4.2's pre-SSA
  client-side-apply-migration (>262144B last-applied annotation, argo-cd#26279).
  Keep it while kubectl co-owns the CRD; harmless no-op on a clean recreate.
- **Three base-tail AWI exclusions** (deleted in local-core-ryzen): argocd-server-tls,
  tailscale-operator-secrets, tailscale-secrets; plus azure-workload-identity +
  azure-keyvault-store Apps, and profile-mismatch gitea-secretstore + nginx-tls-secret.
- **ryzen reads inner-loop NOT main.** Do not mis-diagnose a frozen ryzen as the
  empty-`drySource.kustomize` hydrator-stall bug — spoke-ryzen is path-based; check
  `targetRevision`/inner-loop freshness first.
- **Stale duplicate `ryzen-operator` device** after every recreate — delete via TS API.
