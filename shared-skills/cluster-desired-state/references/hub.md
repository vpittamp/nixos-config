# HUB — desired state + path

The single ArgoCD/GitOps management plane and centralized Tekton build pool for the
whole fleet. Shared model in `architecture.md`; build steps in
`../runbooks/build-hub.md`; canonical docs `docs/hub-cluster-setup.md`,
`docs/hub-gitops-bootstrap.md`, `docs/hub-recovery-runbook.md`. Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`.

## Desired state (what "healthy + correct" means)

**Topology / identity**
- 5-node Talos v1.12.2 / k8s v1.32.0 on Hetzner Cloud (location `ash`), **Flannel
  CNI (NOT Cilium** — Cilium breaks ArgoCD gRPC on Hetzner vSwitch), kube-proxy
  enabled. clusterName=`hub-cluster`, network `hub-cluster-net` 10.1.0.0/16 (subnet
  10.1.1.0/24).
- 3x cpx41 control-plane/management `hub-cp-1/2/3` (10.1.1.1-3) +
  2x ccx33 dedicated build nodes `hub-build-1/2` (10.1.1.11-12), labeled
  `stacks.io/build-pool=hub` and tainted `stacks.io/build-pool=hub:NoSchedule` so
  Tekton/Buildah bursts never starve the control plane.
- All 5 nodes Ready; build-pool labels/taints present.

**ArgoCD / apps** (~189 Applications in ns argocd)
- Hub-self apps are `hub-` prefixed (hub-cert-manager, hub-external-secrets,
  hub-azure-keyvault-store, hub-azure-workload-identity, hub-tailscale-{crds,operator,...},
  hub-tekton-{pipelines,triggers,dashboard}, hub-outer-loop-builds, hub-kueue,
  hub-mlflow, hub-headlamp, ...) plus un-prefixed gitops-promoter, spoke
  appsets, crossplane(+hcloud-providers/compositions), nocodb*, redash*,
  prometheus-agent, metrics-server, grafana*.
- Hub also TRACKS ~75 `dev-*` and ~55 `ryzen-*` child apps (rendered via appsets;
  they run ON spokes).
- Everything Synced/Healthy EXCEPT two benign permanent drifts:
  **`root-application` OutOfSync** (ServerSideApply sees ESO-added fields on the two
  spoke-secrets ExternalSecrets as drift) and **`dev-spoke-transport` OutOfSync**
  (operator rewrites the egress Service's `externalName`). Do not chase these.

**Platform**
- ProxyGroups: `k8s-api-hub` ProxyGroupReady (URL `https://k8s-api-hub.tail286401.ts.net`,
  kube-apiserver mode, 2 replicas — for remote kubectl), `cluster-ingress`
  ProxyGroupReady. Tailscale operator Deployment 1/1; subnet-router Connector
  advertises 10.244.0.0/16 (pods) + 10.96.0.0/16 (services).
- Crossplane providers all Installed+Healthy (provider-hetzner v1.0.0-alpha.1,
  provider-talos v0.1.2, provider-terraform v1.1.1, provider-kubernetes v1.2.1;
  functions cel-filter/patch-and-transform/sequencer Healthy).
- GitOps Promoter pod 2/2 (ns gitops-promoter-system); PromotionStrategies
  `stacks-environments` (env/hub, autoMerge:false) + `workflow-builder-release`
  READY; GitRepository `stacks-repo` + ScmProvider `github` READY.
- ClusterSecretStores `azure-keyvault-store` (Valid/Ready — **THE CANONICAL secret
  source**, KV `keyvault-thcmfmoo5oeow` via Workload Identity) + `argocd` healthy.
- ns `spoke-secrets`: ExternalSecrets `dev-shared-secrets` (~80 keys) and
  `ryzen-shared-secrets` (~77 keys) both SecretSynced — the hub-side mirror spokes
  read over Tailscale.
- `env/hub` branch exists on origin (the branch hub ArgoCD syncs from); `env/hub-next`
  for hydration.

## Path to state (ordered)

1. **PROVISION** (`docs/hub-cluster-setup.md`). hcloud net/subnet/firewall; create
   3x cpx41 + 2x ccx33, attach Talos ISO, poweron. `talosctl gen secrets` ->
   `secrets/hub-secrets.yaml` (git-crypt). Gen config with patches: hub-common
   (kubelet nodeIP validSubnets 10.1.0.0/16, `cni.name=flannel`, `proxy.disabled=false`,
   allowSchedulingOnControlPlanes), controlplane (clusterName=hub-cluster, apiServer
   service-account-issuer/jwks-uri = the Azure OIDC issuer URL). apply-config +
   bootstrap etcd on hub-cp-1. **POST-PROVISION manual fixes**: label+taint build
   nodes; patch kube-flannel DaemonSet `--iface=enp7s0` (Hetzner blocks VXLAN over
   public IP — **re-apply after every Talos upgrade**); patch coredns podAntiAffinity.
2. **AZURE OIDC FEDERATION** (`docs/hub-gitops-bootstrap.md` Step 1). Fresh bootstrap
   mints new SA signing keys: `kubectl get --raw /openid/v1/jwks` -> upload to Azure
   storage `oidcissuer04a3332f` `$web/openid/v1/jwks` + `.well-known/openid-configuration`.
   AD App `gitops-kind-localdev` (clientID 137fbb08-..., tenant 0c4da9c5-...) needs
   federated credential subject `system:serviceaccount:external-secrets:external-secrets`,
   audience `api://AzureADTokenExchange`. Wait 15-30 min for AAD JWKS cache (AADSTS700211).
3. **INSTALL CORE PLATFORM** (helm). ArgoCD v7.8.28 chart (now 3.4.x) with
   hydrator.enabled, commitServer.enabled, server.insecure; patch
   `argocd-cmd-params-cm` hydrator commit identity (DCO Signed-off-by) and `argocd-cm`
   Lua health overrides for promoter.argoproj.io PromotionStrategy/ArgoCDCommitStatus
   (else sync deadlocks when spokes unreachable). Install ESO
   (`certController.enabled=false` for Talos/Flannel); annotate the external-secrets SA
   for Workload Identity; create ClusterSecretStore `azure-keyvault-store`.
4. **ROOT APPLICATION + SOURCE-HYDRATION** (Step 4). Apply `root-application` with
   sourceHydrator: drySource repoURL stacks path `packages/overlays/hub` targetRevision
   `main` kustomize:{}; hydrateTo `env/hub-next`; syncSource `env/hub` path `hub-apps`.
   The Promoter PR `env/hub-next -> env/hub` must be **merged by a human** (autoMerge:false)
   for the root-application's child apps to appear. `packages/overlays/hub/kustomization.yaml`
   composes 8 components: hub-base, hub-management, hub-spoke-appsets, hub-tekton,
   crossplane-hetzner-talos, addons/observability-clickhouse-shared, addons/nocodb,
   addons/redash; cluster-config sets CLUSTER_NAME=hub, GIT_REPO_URL/GIT_BRANCH=main,
   TAILSCALE_TAILNET=tail286401.ts.net, AZURE_KEY_VAULT_NAME=keyvault-thcmfmoo5oeow.
5. **TAILSCALE + PROXYGROUP AUTH** (Steps 5-7). hub-base deploys tailscale-operator
   (OAuth from KV), ProxyGroup `k8s-api-cluster` (renamed `k8s-api-hub` via kustomize
   replacement from CLUSTER_NAME), ProxyGroup-cluster-ingress, Ingress argocd-hub,
   subnet-router. Run `deployment/scripts/tailscale/proxygroup-auth.sh --cluster hub`
   (the operator creates empty state secrets; pods need auth-key injection).
6. **SPOKE MANAGEMENT WIRING** (hub-management + hub-spoke-appsets). The cluster
   Secrets (Contract 1), the spoke appsets, and the GitOps Promoter — see
   `architecture.md` §3.
7. **TAILSCALE-NATIVE SPOKE SECRET TRANSPORT** (hub side of Contract 2). The
   `spoke-secrets` mirror + standalone `k8s-api-hub-ingress` device + the
   spoke-secrets-reader RBAC + the `tag:k8s->tag:k8s` impersonate ACL grant — see
   `architecture.md` §4.
8. **CROSSPLANE SPOKE LIFECYCLE** (crossplane-hetzner-talos). Crossplane + providers +
   functions; CRDs `platform.pittampalli.io` (claim -> XR -> Composition). hcloud token
   from `ExternalSecret-hcloud-api-token`.
9. **CENTRALIZED BUILD POOL** (hub-tekton). Tekton + outer-loop builds + kueue capacity
   (ClusterQueue `hub-swebench-image-builds`, ResourceFlavor `hub-build`). ALL build
   PipelineRuns carry `taskRunTemplate.podTemplate.nodeSelector stacks.io/build-pool=hub`
   + matching toleration (see TriggerTemplate-*.yaml). If a build pod lands on a CP
   node, fix the PipelineRun nodeSelector/toleration — **never remove the build-node taint**.

## Verification

```bash
K=~/.kube/hub-config
kubectl --kubeconfig $K get applications -n argocd | grep -vE 'Synced +Healthy'   # expect only root-application + dev-spoke-transport
kubectl --kubeconfig $K get proxygroup -o wide                                    # k8s-api-hub ProxyGroupReady
kubectl --kubeconfig $K get clustersecretstore                                    # azure-keyvault-store + argocd Valid/Ready
kubectl --kubeconfig $K get externalsecret -n spoke-secrets                       # dev/ryzen-shared-secrets SecretSynced
kubectl --kubeconfig $K get providers.pkg.crossplane.io                           # all Healthy
kubectl --kubeconfig $K get pods -n gitops-promoter-system                        # 2/2
kubectl --kubeconfig $K get promotionstrategy -n argocd                           # both READY
kubectl --kubeconfig $K get nodes -o wide                                         # 5 Ready, v1.32.0, Talos 1.12.2
git ls-remote origin env/hub                                                      # hub sync branch advancing
```

## Hub-specific gotchas

- **Flannel not Cilium** (mandatory on Hetzner); re-apply `kube-flannel --iface=enp7s0`
  after every Talos upgrade or cross-node pod networking silently breaks.
- The two permanent cosmetic OutOfSync apps above — leave them.
- The ProxyGroup VIPService route (`svc:k8s-api-hub`) does NOT propagate into spoke
  egress netmaps; that is WHY the standalone `k8s-api-hub-ingress` DEVICE exists for
  spoke secret reads. **Never delete a working VIP** even if it shows ProxyGroupInvalid.
- ArgoCD Lua health overrides for Promoter CRDs are REQUIRED or sync deadlocks when
  spokes are unreachable; ESO `certController.enabled=false` for Talos/Flannel webhook
  timeouts. `ClientSideApplyMigration=false` is a **ryzen-only** overlay patch, NOT hub.
- The shared operator manifest hardcodes `OPERATOR_HOSTNAME=ryzen-operator` — the hub
  operator device is also `ryzen-operator` (latent collision; the hub does not rely on
  its own operator proxy for spoke connectivity).
