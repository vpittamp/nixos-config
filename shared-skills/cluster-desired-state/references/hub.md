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
  hub-onepassword-store, hub-tailscale-{crds,operator,...},
  hub-tekton-{pipelines,triggers,dashboard}, hub-outer-loop-builds, hub-kueue,
  hub-mlflow, hub-headlamp, ...) plus un-prefixed gitops-promoter, spoke
  appsets, nocodb*, redash*, prometheus-agent, metrics-server, grafana*.
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
- Crossplane is absent from the active hub overlay and is not a health or
  lifecycle dependency. Any `crossplane*` Application or provider that appears
  live is stale inventory to investigate, not a controller to repair.
- GitOps Promoter pod 2/2 (ns gitops-promoter-system); PromotionStrategies
  `stacks-environments` (env/hub, autoMerge:false) + `workflow-builder-release`
  READY; GitRepository `stacks-repo` + ScmProvider `github` READY.
- ClusterSecretStores `onepassword-store` (Valid/Ready — **THE CANONICAL secret
  source** since 2026-06, ESO `onepasswordSDK` provider -> the dedicated `hub-eso`
  1Password vault; the 21 hub ExternalSecrets resolve from it) + `argocd` healthy.
  `azure-keyvault-store` (KV `keyvault-thcmfmoo5oeow` via Workload Identity) is now
  **DORMANT — not deleted** (the AD App + Azure OIDC/JWKS federation are likewise
  dormant); it is no longer the canonical source.
- ns `spoke-secrets`: ExternalSecrets `dev-shared-secrets` (~80 keys) and
  `ryzen-shared-secrets` (~77 keys) both SecretSynced — the hub-side mirror spokes
  read over Tailscale. These spoke-secrets ExternalSecrets now read from
  `onepassword-store` (not `azure-keyvault-store`); spokes are UNAFFECTED — they still
  read the hub-mirrored Secrets via the ESO kubernetes-provider `hub-secrets-store` over
  Tailscale regardless of how the hub populates them. PLUS `tailnet-ca` (Contract 3): a CLUSTER-NEUTRAL mirror of the
  persistent self-signed CA (`TAILNET-DEV-CA-CRT/KEY`) into Secret `tailnet-ca` that
  every spoke reads via the namespace-wide `spoke-secrets-reader` Role — no per-cluster
  CA (`ExternalSecret-tailnet-ca.yaml`, `architecture.md` §7). PR #2319.
- ns `kube-system`: self-healing CronJob `kube-system-fixups`
  (`packages/components/hub-management/manifests/kube-system-fixups/`) re-applies the
  Flannel `--iface=enp7s0` + CoreDNS anti-affinity patches that Talos does not persist
  (so the post-provision manual fixes survive reboots/upgrades).
- ns `tailscale`: CronJob `tailnet-device-sweeper` (every 15m) deletes OFFLINE stale
  spoke tailnet devices (`lastSeen > 30m`) as a hygiene BACKSTOP so dead devices don't
  force `-N` hostname collisions; the hard on-recreate guarantee is still the gated
  `cleanup-tailnet-devices.sh` (`../runbooks/recovery-and-gotchas.md` §F). PRs #2322/#2325.
- `env/hub` branch exists on origin (the branch hub ArgoCD syncs from); `env/hub-next`
  for hydration (can go MISSING after a hub promotion PR merges — see gotchas).

## Path to state (ordered)

> **Recreate automation.** `deployment/scripts/recreate-hub.sh` drives recovery/rebuild
> (modes `--verify-only` / `--seed-secret` / `--fixups` / `--dry-run-clone` /
> `--in-place --confirm-wipe hub-cluster`). It NEVER hcloud-deletes the 5 ash servers
> (no spare inventory); `--in-place` does a rolling `talosctl reset` reusing
> `talos-cluster/main/secrets/hub-secrets.yaml` (preserves etcd identity), re-apply,
> re-bootstrap ONE CP, and bootstraps `onepassword-sa-token` via `op read` (NOT JWKS);
> `--dry-run-clone` rehearses on a throwaway cluster via `provision-spoke.sh`.
> Convergence is checked by `deployment/scripts/hub-verify-gate.sh` (a 9-check read-only
> gate). The steps below are the ordered spine the script and the docs follow.

1. **PROVISION** (`docs/hub-cluster-setup.md`). hcloud net/subnet/firewall; create
   3x cpx41 + 2x ccx33, attach Talos ISO, poweron. `talosctl gen secrets` ->
   `secrets/hub-secrets.yaml` (git-crypt). Gen config with patches: hub-common
   (kubelet nodeIP validSubnets 10.1.0.0/16, `cni.name=flannel`, `proxy.disabled=false`,
   allowSchedulingOnControlPlanes), controlplane (clusterName=hub-cluster). apply-config +
   bootstrap etcd on hub-cp-1. **POST-PROVISION manual fixes**: label+taint build
   nodes; patch kube-flannel DaemonSet `--iface=enp7s0` (Hetzner blocks VXLAN over
   public IP — **re-apply after every Talos upgrade**); patch coredns podAntiAffinity.
   (These two Talos-non-persisted patches are now also re-applied by the self-healing
   `kube-system-fixups` CronJob — see step 3 and `recovery-and-gotchas.md` §H.)
2. **BOOTSTRAP 1PASSWORD SERVICE ACCOUNT TOKEN** (root-of-trust since 2026-06). The hub
   secret root is now **1Password**, not Azure. The single bootstrap secret is one scoped
   read-only 1Password Service-Account token (`hub-eso-reader`) in Secret
   `onepassword-sa-token` (ns `external-secrets`), persisted at
   `op://CLI/<id>/credential` and read at recreate via the operator's developer SA token
   (`op read`). `recreate-hub.sh --seed-secret` does this (NOT a JWKS upload). The Azure
   OIDC/JWKS federation (`oidcissuer04a3332f`, AD App `gitops-kind-localdev`,
   `sync-jwks-to-azure.sh`) is **DORMANT — no longer in the hub recreate path**
   (`sync-jwks-to-azure.sh` is a SPOKE-only tool now).
3. **INSTALL CORE PLATFORM** (helm). ArgoCD v7.8.28 chart (now 3.4.x) with
   hydrator.enabled, commitServer.enabled, server.insecure; patch
   `argocd-cmd-params-cm` hydrator commit identity (DCO Signed-off-by) and `argocd-cm`
   Lua health overrides for promoter.argoproj.io PromotionStrategy/ArgoCDCommitStatus
   (else sync deadlocks when spokes unreachable). Install ESO
   (`certController.enabled=false` for Talos/Flannel); seed the `onepassword-sa-token`
   Secret (step 2); create ClusterSecretStore `onepassword-store` (ESO `onepasswordSDK`
   provider -> `hub-eso` vault).
4. **ROOT APPLICATION + SOURCE-HYDRATION** (Step 4). Apply `root-application` with
   sourceHydrator: drySource repoURL stacks path `packages/overlays/hub` targetRevision
   `main` kustomize:{}; hydrateTo `env/hub-next`; syncSource `env/hub` path `hub-apps`.
   The Promoter PR `env/hub-next -> env/hub` must be **merged by a human** (autoMerge:false)
   for the root-application's child apps to appear. `packages/overlays/hub/kustomization.yaml`
   composes 8 components: hub-base, hub-management, hub-spoke-appsets, hub-tekton,
   addons/observability-clickhouse-shared, addons/nocodb, addons/redash, and
   hub-onepassword; cluster-config sets CLUSTER_NAME=hub,
   GIT_REPO_URL/GIT_BRANCH=main, TAILSCALE_TAILNET=tail286401.ts.net, and
   AZURE_KEY_VAULT_NAME=keyvault-thcmfmoo5oeow.
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
   `architecture.md` §4. Plus the **Contract 3** cluster-neutral `tailnet-ca` mirror
   (`ExternalSecret-tailnet-ca.yaml`) and the `tailnet-device-sweeper` CronJob (ns
   tailscale) — see `architecture.md` §7.
8. **SCRIPTED SPOKE LIFECYCLE BOUNDARY.** The hub does not provision spokes.
   `deployment/scripts/talos-hetzner/recreate-dev.sh` owns the destructive dev
   lifecycle (backup, destroy, cleanup, provision, bootstrap, agent enrollment,
   restore, verify); ryzen has its separate imperative bootstrap. The hub owns
   agent principal, secret transport, desired-state delivery, and aggregation.
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
kubectl --kubeconfig $K get clustersecretstore                                    # onepassword-store + argocd Valid/Ready
kubectl --kubeconfig $K get externalsecret -n spoke-secrets                       # dev/ryzen-shared-secrets SecretSynced
if kubectl --kubeconfig $K get applications -n argocd -o name | rg -q 'crossplane'; then
  echo 'unexpected retired Crossplane application remains' >&2; exit 1
fi
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
- **`env/hub-next` can go MISSING after a hub promotion PR merges** — GitOps Promoter
  `ChangeTransferPolicyNotReady` "couldn't find remote ref env/hub-next" -> PromotionStrategy
  `stacks-environments` NotReady (floods warning events). NOT GitHub auto-delete
  (`delete_branch_on_merge=false`); ONLY `env/hub-next` is affected (spoke `-next` branches
  self-heal via their busy hydrators; the idle hub hydrator does not recreate it). Fix when
  active==proposed dry SHA (no pending hub change): recreate it
  `git push origin origin/env/hub:refs/heads/env/hub-next` — the Promoter reconciles to Ready.
- The shared operator manifest hardcodes `OPERATOR_HOSTNAME=ryzen-operator` — the hub
  operator device is also `ryzen-operator` (latent naming collision). Now purely
  cosmetic for connectivity: hub->ryzen rides the ryzen HOST device's raw TCP
  passthrough (`ryzen.tail286401.ts.net:6443`), so NO Tailscale operator
  apiserver-proxy (hub's or ryzen's) is in the spoke-connectivity path — and no
  per-hostname Let's Encrypt cert is provisioned for it.
