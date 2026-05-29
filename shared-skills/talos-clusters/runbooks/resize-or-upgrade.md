# Runbook: Resize Or Upgrade A Talos Spoke

Use when changing control-plane/worker counts, HCloud server types, Talos
version, Kubernetes version, ISO ID, or worker labels.

## Decide Whether This Is Mutable

Small GitOps workload changes are mutable. Many Talos/HCloud infrastructure
changes are effectively replace-and-reconcile in the current Crossplane
composition. Before editing, inspect `Composition-talospokecluster.yaml` to see
whether the field patches an existing managed resource cleanly or changes a
bootstrap-time input.

Conservative default:

- Worker labels: mutable through Talos/Kubernetes config if composition supports
  it; verify live labels after sync.
- Worker count within XRD maximum: composition must have matching generated
  worker resources. If it does not, expand schema/composition first.
- Server type or ISO: plan as recreate unless the composition has explicit,
  tested replacement behavior.
- Kubernetes/Talos major/minor version: plan a controlled upgrade path, not a
  casual claim edit.
- HCloud server type or location changes can fail late if the target type is not
  available in the target location. Check `hcloud server-type describe` before
  changing the claim.

## Hetzner ISO vs Kubernetes Version Constraint

This is the most common bootstrap wall for a fresh Hetzner spoke recreate.

- The Hetzner public catalog ships only a Talos `1.12.4` ISO. There is no
  custom-ISO upload API; a custom ISO requires a Hetzner support ticket with a
  direct `factory.talos.dev` URL.
- `install.image` is derived from the claim's `talos.version` inside the
  Terraform `talos_machine_configuration` data source (the composition module
  itself sets only `install.disk=/dev/sda` + `wipe=true`, NOT `install.image`).
  `install.image` governs the Talos version that gets WRITTEN TO DISK, even when
  the node boots the older `1.12.4` ISO.
- BUT while still in maintenance mode (before the install completes) the node
  validates the REQUESTED `kubernetesVersion` against the RUNNING ISO Talos
  (`1.12.4`). A new Kubernetes minor that the running `1.12.4` Talos does not
  support will fail the bootstrap before the newer Talos is ever on disk.

Net effect: a one-shot claim of Talos `1.13.2` + Kubernetes `1.36` on the
`1.12.4` ISO CANNOT bootstrap. This is not a Talos failure; it is the
maintenance-mode k8s-version validation against the ISO's running version.

## Kubernetes Upgrade Guidance (Supported In-Place Path)

For the `1.12.4`-ISO-vs-newer-Talos case, the supported recovery is a transient
two-step Kubernetes version, performed by patching the LIVE claim:

1. Set `kubernetesVersion` to a value the running `1.12.4` ISO accepts (e.g.
   `1.35.0`) while keeping `talos.version: 1.13.2`. Because `install.image`
   follows `talos.version`, the node still installs Talos `1.13.x` to disk; it
   just bootstraps Kubernetes `1.35` first.

   ```bash
   kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system patch \
     talospokeclusterclaims.platform.pittampalli.io <spoke> --type=merge \
     -p '{"spec":{"parameters":{"talos":{"kubernetesVersion":"1.35.0"}}}}'
   ```

2. Let the cluster finish bootstrapping on k8s `1.35` (now running Talos
   `1.13.x`, which DOES support k8s `1.36`).

3. Raise `kubernetesVersion` back to `1.36.0`:

   ```bash
   kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system patch \
     talospokeclusterclaims.platform.pittampalli.io <spoke> --type=merge \
     -p '{"spec":{"parameters":{"talos":{"kubernetesVersion":"1.36.0"}}}}'
   ```

Patch the LIVE claim, not just Git. `crossplane-hcloud-compositions` auto-syncs
from `main` with selfHeal, so a Git edit alone may be overwritten in flight; the
live patch is what drives the in-flight reconcile (commit the final desired
value to Git afterward so it persists).

Verify the installed Talos via the OS-IMAGE column (NOT the claim value):

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes -o wide
# OS-IMAGE should read Talos (v1.13.x); k8s VERSION the requested 1.36.0
talosctl --talosconfig /tmp/<spoke>-talosconfig version
```

If you cannot reason about ISO-vs-target compatibility, you can still dry-run a
stepwise in-place k8s upgrade before patching:

```bash
talosctl --talosconfig /tmp/<spoke>-talosconfig version
talosctl --talosconfig /tmp/<spoke>-talosconfig upgrade-k8s --to <next-minor> --dry-run
```

For a fully disposable spoke, a clean recreate from the committed claim plus the
two-step `kubernetesVersion` sequence above is the reliable end-to-end path.

## Worker Labels

There are two label paths:

- `machine.nodeLabels` keeps labels in Talos machine config.
- Kubelet `extraArgs.node-labels` makes custom labels appear on Kubernetes Nodes
  during registration.

For labels that schedulers or capacity checks rely on, ensure the composition
passes only custom labels to kubelet:

```yaml
machine:
  nodeLabels:
    node-role.kubernetes.io/worker: ""
    stacks.io/swebench-pool: dev-benchmark
  kubelet:
    extraArgs:
      node-labels: stacks.io/swebench-pool=dev-benchmark
```

Do not pass reserved role labels such as `node-role.kubernetes.io/worker` in
`kubelet.extraArgs.node-labels`; kubelet rejects unknown `kubernetes.io` and
`k8s.io` label prefixes there and may fail to start.

## Edit Checklist

1. Update the claim for desired shape.
2. Update the XRD schema if count limits or fields change.
3. Update the composition resource fan-out if adding more workers.
4. Keep worker pools simple unless the user explicitly asks for mixed pools.
5. Validate kustomize and YAML parsing.
6. Commit and push; then let hub Argo/Crossplane reconcile.

## Talos Version Notes

The claim records the intended Talos version and Hetzner ISO ID, but live nodes
must still be checked after bootstrap:

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes -o wide
talosctl --talosconfig /tmp/<spoke>-talosconfig version
```

The installed Talos version is set by `install.image` (derived from
`talos.version`), NOT by the booted ISO ID, so the OS-IMAGE column should match
`talos.version` even though nodes boot the older Hetzner `1.12.4` ISO. If the
OS-IMAGE differs from `talos.version`, treat it as a real finding: check the
Terraform `talos_machine_configuration` `install.image`, the claim
`talos.version`, the ISO ID, and composition defaults before assuming the claim
value won. The booted ISO version still matters for one thing only: the
maintenance-mode Kubernetes-version validation described above.

## Validation

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes -o wide
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes -L stacks.io/swebench-pool
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl describe nodes | rg 'DiskPressure|nodefs|Allocatable'
talosctl --talosconfig /tmp/<spoke>-talosconfig get kubeletconfig
```

For dev SWE-bench capacity, continue with
`validate-dev-swebench-capacity.md`.
