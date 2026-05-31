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
- Registered as an **argocd-agent AUTONOMOUS agent**. The argocd cluster Secret
  `cluster-ryzen` is now an **agent MAPPING** (`managed-by: argocd-agent`, label
  `argocd-agent.argoproj-labs.io/agent-name=ryzen`, annotation `spoke-cluster=ryzen`):
  `server=https://argocd-agent-resource-proxy:9090?agentName=ryzen` with embedded mTLS
  certData/keyData/caData and **no bearerToken**, created by
  `argocd-agentctl agent create ryzen`. ryzen's local controller reconciles its own
  apps (autonomous); the hub principal aggregates status. `source-branch=inner-loop`
  still drives what ryzen hydrates.
  > The legacy `ExternalSecret-cluster-ryzen.yaml` (KV-materialized
  > `server=https://ryzen.tail286401.ts.net:6443`, `insecure:false`+caData, per-recreate
  > SA bearerToken minted by register-spoke `--ts-host-passthrough`) is now **vestigial**
  > for ArgoCD — the agent mapping supersedes it. That host-passthrough kube-API endpoint
  > + SA token is what **Headlamp** uses to reach ryzen (via the dedicated
  > `headlamp-cluster-ryzen` Secret). `workload.stacks.io/workflow-builder` is still
  > intentionally OMITTED (ryzen's overlay composes workflow-builder-system directly).
  > See `tailscale-and-certs.md` for the host-passthrough + Headlamp-Secret detail.

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

**Web exposure** (Contract 3, `architecture.md` §7)
- workflow-builder reachable at `https://workflow-builder-ryzen.tail286401.ts.net` via a
  Tailscale **L4 LoadBalancer** Service (`packages/components/workloads/workflow-builder-tailnet-lb/`)
  + an in-cluster nginx `tls-terminator` sidecar serving the persistent self-signed
  `*.tail286401.ts.net` wildcard — **NO Let's Encrypt, NO Tailscale Ingress**, and NOT the
  old plain-HTTP LB (PRs #2314/#2316 superseded by #2319). The `tailnet-ca` app
  (`packages/base/apps/tailnet-ca.yaml`) restores the shared CA into a `tailnet-dev-ca` CA
  ClusterIssuer that issues the wildcard cert (in the workflow-builder ns).
- **mcp-gateway is in-cluster only** now
  (`MCP_GATEWAY_BASE_URL=http://mcp-gateway.workflow-builder.svc.cluster.local:8080`);
  `ORIGIN`/`APP_PUBLIC_URL` stay `https://workflow-builder-ryzen...` (the #2316 http flip
  was reverted).

**Hub->ryzen connectivity** (host-device raw TCP passthrough — the ryzen-only path)
- hub ArgoCD reaches the ryzen Talos kube-apiserver DIRECTLY over Tailscale via the
  ryzen HOST device (`ryzen.tail286401.ts.net`, `100.96.102.1`, `tag:k8s`) running
  `tailscale serve --bg --tcp=6443` as a RAW TCP passthrough to the local apiserver
  (nixos-config `services.tailscaleK8sApiserver` / the `tailscale-serve-k8s-apiserver`
  oneshot auto-discovers the Docker host port; the stacks bootstrap restarts it after
  each cluster create).
- Raw passthrough = NO TLS termination, so the Talos apiserver's OWN serving cert
  reaches the hub end-to-end and the hub does FULL TLS verify (`insecure:false`)
  against the Talos cluster CA. The cert carries `apiServer.certSANs:
  [ryzen.tail286401.ts.net, 100.96.102.1]` (set by the bootstrap `--config-patch`),
  so verification passes — **no SNI workaround needed** (the cert legitimately covers
  the hostname).
- cluster-ryzen `server = https://ryzen.tail286401.ts.net:6443`; HUB CoreDNS rewrite
  `ryzen.tail286401.ts.net -> ryzen-api-egress.tailscale.svc.cluster.local`
  (self-healing CronJob); hub ns `tailscale` Service `ryzen-api-egress` ExternalName
  with `tailnet-fqdn=ryzen.tail286401.ts.net`, port 6443. The Tailscale operator
  apiserver-proxy is NO LONGER in this path (it still runs for other tailnet
  exposures but never provisions an LE cert because nothing connects to its
  hostname). See `architecture.md` §5.

**Branch**: ryzen tracks `inner-loop`, NOT `main`.

## Path to state (ordered)

1. **PROVISION (imperative).** `deployment/scripts/bootstrap-spoke-cluster.sh` on the
   ryzen host. Canonical recreate:
   `bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate --ts-host-passthrough`
   (`--ts-host-passthrough` = hub->ryzen over the ryzen host device's raw TCP
   passthrough + a per-recreate ServiceAccount bearer token; register-spoke mints the
   SA token, extracts the Talos CA, and pushes both to KV as
   `ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}`; restarts the `tailscale-serve-k8s-apiserver`
   oneshot). The legacy `--ts-acl-mode` (operator apiserver-proxy + ACL impersonation)
   is **deprecated for ryzen** — it reintroduces the Let's Encrypt dependency.
   Produces bare Talos-Docker with ONLY: Tailscale operator (helm), the
   ProxyGroup/ProxyClass for kube-api exposure, hub-spoke SA+CRB. It does NOT install
   cert-manager/ESO/ArgoCD/gitea/tekton/observability/workflow-builder — the hub
   deploys all of those via rendered child Applications. Requires env
   `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_CLIENT_SECRET`.
2. **AGENT ENROLLMENT** (Contract 1, argocd-agent). `argocd-agentctl agent create ryzen`
   writes the `cluster-ryzen` AGENT MAPPING Secret on the hub (`?agentName=ryzen` +
   embedded mTLS, `managed-by: argocd-agent`). ryzen runs as an **AUTONOMOUS** agent: its
   local controller reconciles its own apps (hydrated from `inner-loop`) and reports
   status to the principal — the hub does NOT reconcile ryzen's apps through a kube-API
   connection. (The legacy `ExternalSecret-cluster-ryzen.yaml` + spoke-clusters-appset
   `spoke-ryzen` templating are vestigial now; the agent mapping supersedes them.)
3. **SECRET TRANSPORT** (Contract 2, spoke side is IMPERATIVE for ryzen). The
   `hub-secrets-store` CSS + egress Service are applied by
   `deployment/scripts/lib/spoke-transport-bootstrap.sh` (invoked from
   `bootstrap-spoke-cluster.sh`) using `deployment/manifests/spoke-transport/`. The
   **spoke** CoreDNS rewrite (`k8s-api-hub-ingress... -> k8s-api-hub-egress...`) is
   re-applied every recreate (Talos resets the Corefile). The hub mirror
   (`ExternalSecret-ryzen-shared-secrets.yaml`) + RBAC + Ingress device are GitOps on
   the hub side. See `architecture.md` §4.
4. **HUB->RYZEN CONNECTIVITY** (host-device raw TCP passthrough, §5). Confirm the ryzen
   HOST device's `tailscale serve --bg --tcp=6443` is up and the hub CoreDNS rewrite
   (`ryzen.tail286401.ts.net -> ryzen-api-egress`) is present. Verify with a
   full-verify kubectl through the hub's cluster-ryzen connection (NOT an SNI curl) —
   `insecure:false`+caData must validate the Talos serving cert. No operator
   apiserver-proxy or LE cert is in this path, so the stale-`ryzen-operator`-device
   cleanup is **moot for hub->ryzen connectivity** (the operator device, if present,
   no longer affects sync).
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
kubectl --kubeconfig $K -n argocd get secret cluster-ryzen -o jsonpath='{.data.server}' | base64 -d   # https://ryzen.tail286401.ts.net:6443
kubectl --kubeconfig $K -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep ryzen.tail286401   # rewrite -> ryzen-api-egress
kubectl --kubeconfig $K -n tailscale get svc ryzen-api-egress                                          # ExternalName tailnet-fqdn=ryzen.tail286401.ts.net, port 6443
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
- **Stale duplicate `ryzen-operator` device** after a recreate is now **moot for
  hub->ryzen connectivity** (host-passthrough doesn't use the operator proxy). The
  operator still runs for other tailnet exposures, so optionally delete the duplicate
  via TS API for hygiene, but it no longer blocks sync.
