---
name: talos-clusters
description: "Create, recreate, resize, upgrade, and troubleshoot PittampalliOrg Talos Kubernetes clusters on Hetzner, especially hub-owned Crossplane TalosSpokeClusterClaim spokes such as dev and staging. Use this whenever the user mentions Talos, HCloud/Hetzner cluster nodes, Crossplane-owned spokes, dev/staging cluster rebuilds, TalosSpokeClusterClaim changes, kube-apiserver ProxyGroups, stale Tailscale device names after cluster recreation, or SWE-bench capacity validation on Talos workers."
---

# Talos Clusters

Operational workflow for PittampalliOrg Talos clusters managed through the
`PittampalliOrg/stacks` hub-and-spoke architecture.

## Orientation

- The hub is a Talos cluster on Hetzner and owns spoke lifecycle through
  Crossplane.
- Dev and staging should be treated as GitOps/Crossplane spokes, not manually
  maintained HCloud clusters. Prefer committed claims and compositions over
  one-off `hcloud` and `talosctl` steps.
- The primary spoke API path is Tailscale ProxyGroup service-host DNS such as
  `dev-api-v2.tail286401.ts.net`. The break-glass path is the Crossplane
  kubeconfig secret on the hub.
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

- The correct dev shape for the 72-capacity target was conservative but large:
  `3 x cpx41` control planes and `6 x cpx51` workers in `ash`, with all workers
  labeled `stacks.io/swebench-pool=dev-benchmark`.
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
