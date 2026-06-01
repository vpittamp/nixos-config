# Build / recover the HUB

Ordered checklist to bring the hub from nothing (or recover it) to the desired state in
`../references/hub.md`. Canonical docs: `docs/hub-cluster-setup.md` (Talos/Hetzner),
`docs/hub-gitops-bootstrap.md` (ArgoCD/ESO/Tailscale/Promoter), `docs/hub-recovery-runbook.md`.
Paths relative to `/home/vpittamp/repos/PittampalliOrg/stacks/main`.

> The hub is rebuilt rarely. `deployment/scripts/recreate-hub.sh` now drives
> recovery/rebuild (modes `--verify-only` / `--seed-secret` / `--fixups` /
> `--dry-run-clone` / `--in-place --confirm-wipe hub-cluster`); it NEVER hcloud-deletes
> the 5 ash servers (no spare inventory). `--in-place` does a rolling `talosctl reset`
> reusing `talos-cluster/main/secrets/hub-secrets.yaml` (preserves etcd identity),
> re-apply, re-bootstrap ONE CP, and seeds `onepassword-sa-token` via `op read` (NOT
> JWKS); `--dry-run-clone` rehearses on a throwaway cluster via `provision-spoke.sh`.
> Convergence is checked by `deployment/scripts/hub-verify-gate.sh` (9-check read-only
> gate). This runbook is the ordered spine + the manual fixes that are easy to miss.

## 0. Decide: full rebuild vs recovery

- Nodes gone / fresh cluster -> full rebuild (steps 1-9).
- Cluster up but a layer is broken -> jump to the matching layer + `docs/hub-recovery-runbook.md`
  and `recovery-and-gotchas.md` (§G permanent drifts, §H flannel).

## 1. Provision (Talos/Hetzner)

Per `docs/hub-cluster-setup.md`: hcloud net `hub-cluster-net` (10.1.0.0/16) + subnet,
firewall (6443/50000/41641-udp/icmp); 3x cpx41 + 2x ccx33 attached at
10.1.1.{1,2,3,11,12}; attach Talos ISO; poweron. `talosctl gen secrets` (git-crypt). Gen
config with the hub-common + controlplane patches (flannel, proxy enabled,
allowSchedulingOnControlPlanes, apiServer OIDC issuer). apply-config per node; bootstrap
etcd on hub-cp-1; rewrite kubeconfig 10.1.1.1 -> public CP IP.

**Manual post-provision fixes (easy to miss):**
- Label + taint build nodes: `stacks.io/build-pool=hub` (label) + `:NoSchedule` (taint).
- Patch kube-flannel DaemonSet `--iface=enp7s0` (see `recovery-and-gotchas.md` §H —
  re-apply after every Talos upgrade).
- Patch coredns podAntiAffinity across nodes.
- (The two Talos-non-persisted patches above are also re-applied by the self-healing
  `kube-system-fixups` CronJob — `packages/components/hub-management/manifests/kube-system-fixups/`;
  `recreate-hub.sh --fixups` applies it.)

## 2. Bootstrap the 1Password Service-Account token

The hub secret root is now **1Password** (2026-06 AWI->1Password migration), not Azure.
Seed the single bootstrap secret — one scoped read-only 1Password Service-Account token
(`hub-eso-reader`) into Secret `onepassword-sa-token` (ns `external-secrets`), persisted
at `op://CLI/<id>/credential` and read at recreate via the operator's developer SA token
(`op read`). `recreate-hub.sh --seed-secret` does this. The Azure OIDC/JWKS federation
(`oidcissuer04a3332f`, AD App `gitops-kind-localdev`, `sync-jwks-to-azure.sh`) is
**DORMANT — no longer in the hub path** (`sync-jwks-to-azure.sh` is a SPOKE-only tool now).

## 3. Core platform (helm)

ArgoCD chart (hydrator + commitServer + server.insecure); patch `argocd-cmd-params-cm`
hydrator commit identity (DCO) and `argocd-cm` Lua health overrides for the Promoter
CRDs (REQUIRED — else sync deadlocks when spokes unreachable). Install ESO
(`certController.enabled=false`); seed the `onepassword-sa-token` Secret (step 2);
create ClusterSecretStore `onepassword-store` (ESO `onepasswordSDK` provider ->
`hub-eso` vault).

## 4. Root application + first promotion

Apply `root-application` (sourceHydrator drySource `packages/overlays/hub` @main ->
hydrateTo `env/hub-next` -> syncSource `env/hub` path `hub-apps`). **Merge the Promoter
PR `env/hub-next -> env/hub`** (autoMerge:false) — child apps only appear after the merge.

> Gotcha: unlike the spoke hydrators, the hub hydrator does **NOT** auto-recreate
> `env/hub-next` after the Promoter PR merges. A stuck `PromotionStrategy`
> (`ChangeTransferPolicyNotReady` / missing `env/hub-next` ref) may need a manual
> `env/hub-next` recreate. See `recovery-and-gotchas.md`.

## 5-9. Platform layers

- **5 Tailscale + ProxyGroup auth**: hub-base operator + ProxyGroups
  (`k8s-api-cluster`->`k8s-api-hub`, cluster-ingress) + subnet-router; run
  `deployment/scripts/tailscale/proxygroup-auth.sh --cluster hub`.
- **6 Spoke management wiring**: cluster Secrets + appsets + Promoter
  (`../references/architecture.md` §3). Confirm the hub uses the **hub-spoke-appsets**
  spoke-clusters-appset, not the hub-base copy.
- **7 Spoke secret transport (hub side)**: the `spoke-secrets` mirror, standalone
  `k8s-api-hub-ingress` device, spoke-secrets-reader RBAC, `tag:k8s->tag:k8s` impersonate
  ACL grant (`../references/architecture.md` §4).
- **8 Crossplane**: providers + functions Healthy; hcloud token ExternalSecret.
- **9 Build pool (hub-tekton)**: Tekton + outer-loop builds + kueue capacity; verify ALL
  build PipelineRuns carry the `stacks.io/build-pool=hub` nodeSelector + toleration.

## 10. Verify

Run the full block in `../references/hub.md` "Verification" (or
`deployment/scripts/hub-verify-gate.sh`). Pass = only `root-application` +
`dev-spoke-transport` OutOfSync; everything else Synced/Healthy; 5 nodes Ready v1.32.0;
ProxyGroups Ready; ClusterSecretStores `onepassword-store` + `argocd` Valid; Promoter 2/2.
