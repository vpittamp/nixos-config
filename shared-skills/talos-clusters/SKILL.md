---
name: talos-clusters
description: "Create, recreate, resize, upgrade, and troubleshoot PittampalliOrg Talos Kubernetes clusters on Hetzner, especially hub-owned Crossplane TalosSpokeClusterClaim spokes such as dev and staging. Use this whenever the user mentions Talos, HCloud/Hetzner cluster nodes, Crossplane-owned spokes, dev/staging cluster rebuilds, TalosSpokeClusterClaim changes, kube-apiserver ProxyGroups, stale Tailscale device names after cluster recreation, or SWE-bench capacity validation on Talos workers."
---

# Talos Clusters

Operational workflow for PittampalliOrg Talos clusters managed through the
`PittampalliOrg/stacks` hub-and-spoke architecture.

## Orientation

- The hub is a 5-node Talos `v1.12.x` / Kubernetes `v1.32.0` cluster on Hetzner
  (Flannel CNI, NOT Cilium, kube-proxy enabled). It owns spoke lifecycle through
  Crossplane and is provisioned imperatively (`docs/hub-cluster-setup.md`), not
  by a TalosSpokeClusterClaim. The hub keeps Azure Workload Identity + Key Vault
  as the canonical secret source.
- Dev and staging should be treated as GitOps/Crossplane spokes, not manually
  maintained HCloud clusters. Prefer committed claims and compositions over
  one-off `hcloud` and `talosctl` steps.
- This skill is for the Crossplane-driven Hetzner spokes (dev/staging). The
  `ryzen` spoke is NOT in scope here: it is a bare-metal Talos-in-Docker cluster
  bootstrapped imperatively (`deployment/scripts/bootstrap-spoke-cluster.sh`),
  not provisioned by a claim. Use the `ryzen-spoke-bootstrap` skill for ryzen.
- Spokes no longer use Azure Workload Identity for workload secrets. They read
  hub-mirrored secrets over Tailscale via a `hub-secrets-store` ClusterSecretStore
  (ESO kubernetes provider) against the hub `spoke-secrets` namespace Secret
  `<cluster>-shared-secrets`. See `references/system-model.md`.
- The current Hetzner shape is tuned for US placement: `ash` maps to
  `us-east`, `hil` maps to `us-west`, and dev may use Hillsboro when Ashburn
  capacity is unavailable. Check server-type support before choosing a size.
- The primary spoke API path is Tailscale ProxyGroup service-host DNS such as
  `dev-api-v2.tail286401.ts.net`. The break-glass path is the Crossplane
  kubeconfig secret on the hub.
- Headlamp on the hub mirrors ArgoCD cluster secrets into a generated
  kubeconfig at pod start. After a spoke is recreated or its Argo cluster secret
  changes, restart `hub-headlamp` before judging the UI connection stale.
- Promoted spoke workloads flow through source-hydrator and GitOps Promoter:
  `origin/main` -> dry source -> `env/spokes-<name>-next` ->
  `env/spokes-<name>` -> hub ArgoCD child Applications.
- Device-backed Tailscale Ingresses and ProxyGroup service-hosts are different
  naming models. A stale service-host or offline device can reserve the desired
  hostname and cause `-1` suffix drift.

## Start Here

1. Identify the operation:
   - New or rebuilt spoke: read `runbooks/recreate-crossplane-spoke.md`.
   - Resize or version change: read `runbooks/resize-or-upgrade.md`.
   - API, hostname, or `-1` suffix issue: read
     `runbooks/tailscale-name-recovery.md`.
   - Post-rebuild dev/SWE-bench validation: read
     `runbooks/validate-dev-swebench-capacity.md`.
2. Read `references/system-model.md` if you need file paths, resource names, or
   the mental model before editing.
3. Use the `gitops` skill alongside this one for ArgoCD health, promoter/source
   hydrator recovery, image pin rollouts, and Tailscale app ingress details.
4. Use the `evaluations` skill alongside this one before launching paid or
   quota-sensitive SWE-bench ramps.

## Default Working Rules

- Commit the desired cluster shape first. For spokes, the claim is the source of
  truth; HCloud servers are implementation detail.
- Pause before destructive steps unless the user has explicitly authorized the
  outage. Verify no active benchmark runs, leases, Dapr workflow executions, or
  OpenShell sandboxes are still running.
- Preserve canonical names. Clean stale Tailscale devices/services before
  accepting suffixed hostnames or bumping API hostnames.
- Validate both infrastructure and runtime data. A Talos cluster is not "done"
  when nodes are Ready; Argo child apps, DB hooks, Tailscale endpoints, and
  workload capacity must also be healthy.
- Prefer capacity gates over optimism for SWE-bench. Do not start a 72-instance
  ramp unless diagnostics show enough sandbox headroom, runtime slots, no
  DiskPressure, and zero stale active state.

## Lessons From The Dev Rebuild

- The correct dev shape for the 72-capacity target is conservative but large:
  `3 x cpx41` control planes and `6 x cpx51` workers, with all workers labeled
  `stacks.io/swebench-pool=dev-benchmark`. Prefer `ash` when capacity exists;
  use `hil`/`us-west` when a US fallback is needed. Do not assume `cpx42` or
  `cpx62` are placeable in US regions.
- The Hetzner public catalog ships only a Talos `1.12.4` ISO (no custom-ISO
  upload API; a custom ISO requires a Hetzner support ticket with a direct
  `factory.talos.dev` URL). `install.image` (derived from the claim's
  `talos.version` inside the Terraform `talos_machine_configuration` data source)
  governs the INSTALLED Talos version even when the node boots the `1.12.4` ISO,
  but the maintenance-mode node validates the REQUESTED Kubernetes version
  against the RUNNING (`1.12.4`) Talos. So a one-shot claim of Talos `1.13.2` +
  k8s `1.36` on the `1.12.4` ISO cannot bootstrap. Recovery is an in-place
  upgrade: transiently set `kubernetesVersion` to `1.35` (keep
  `version: 1.13.2` so `install.image` installs Talos `1.13.x`), let it bootstrap
  on k8s `1.35`, then raise `kubernetesVersion` back to `1.36`. Patch the LIVE
  claim, not just Git; `crossplane-hcloud-compositions` auto-syncs from `main`
  with selfHeal. Verify the installed Talos via `kubectl get nodes -o wide`
  (OS-IMAGE column). See `runbooks/resize-or-upgrade.md`.
- Worker labels have two layers. `machine.nodeLabels` belongs in Talos machine
  config, but labels that must appear immediately on Kubernetes Nodes also need
  kubelet `extraArgs.node-labels`. Only pass custom labels there; kubelet rejects
  reserved labels such as `node-role.kubernetes.io/worker`.
- Crossplane `Ready=False` after a rebuild can be a readiness aggregation
  artifact. Inspect the composite resources, Terraform workspace generations,
  jobs, Argo registration, and live spoke health before treating it as a failed
  cluster.
- Ordered hooks matter. `db-migrate` must complete before `db-seed`, and the
  SWE-bench fixture seed should be idempotent and restore only sanitized,
  runtime-required rows.
- Runtime correctness depends on details outside node readiness. The dev rebuild
  exposed stale Tailscale names, a disabled Dapr dashboard ingress, an unused PVC
  blocking Argo health, Tekton default drift, and missing Dapr Component scopes
  for `agent-runtime-pool-coding`.
- A green capacity API is a better launch gate than manual arithmetic. It caught
  the Dapr state-store scoping issue even after the cluster had enough CPU,
  memory, and nodefs headroom.

## Common Commands

```bash
# Hub Argo/Crossplane view
kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system get talospokeclusterclaims,talospokeclusters,job
kubectl --kubeconfig ~/.kube/hub-config -n argocd get app | rg 'spoke|dev|staging|crossplane'

# Extract break-glass spoke kubeconfig from the hub
kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system get secret \
  <spoke>-XXXXX-kubeconfig -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/<spoke>-kubeconfig
chmod 600 /tmp/<spoke>-kubeconfig

# Basic spoke health
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes -o wide
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get pods -A \
  --field-selector=status.phase!=Running,status.phase!=Succeeded
```

## Edit Targets

- Claim: `packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/TalosSpokeClusterClaim-<spoke>.yaml`
- XRD: `packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/CompositeResourceDefinition-talospokecluster.yaml`
- Composition: `packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/Composition-talospokecluster.yaml`
- Spoke overlay: `packages/overlays/<spoke>/`
- Rebuild runbook in stacks: `docs/recreate-disposable-dev.md`

## Validation

Always close with the evidence that matches the operation:

- Git/Kustomize: `yq` or `kubectl kustomize` parsing for changed claims,
  compositions, and overlays.
- Hub: Crossplane claim/composite Ready, provisioning/onboarding jobs completed,
  hub Argo apps Synced/Healthy.
- Spoke: all nodes Ready, expected labels, no DiskPressure, no unexpected bad
  pods.
- Tailscale: canonical API/app hostnames present with no stale `-1` replacements
  unless intentionally accepted.
- Runtime: migrations/seeds ran in the expected order and idempotent seeds did
  not duplicate data.
- SWE-bench: capacity diagnostics pass before benchmark ramps.
