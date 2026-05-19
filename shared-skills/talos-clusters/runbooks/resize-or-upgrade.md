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

## Kubernetes Upgrade Guidance

Do not assume a direct minor-version jump is supported. In the dev rebuild,
Kubernetes `1.32` could not be upgraded directly to `1.35`, and the stepwise
path was blocked by Talos/Kubernetes compatibility checks. For disposable spokes,
prefer a controlled recreate when the safe in-place path is unclear.

Before attempting an in-place upgrade:

```bash
talosctl --talosconfig /tmp/<spoke>-talosconfig version
talosctl --talosconfig /tmp/<spoke>-talosconfig upgrade-k8s --to <next-minor> --dry-run
```

If the dry run or compatibility check fails, stop and plan a recreate or Talos
OS upgrade sequence instead of forcing the Kubernetes version.

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

If Kubernetes reports a node OS version different from the claim, treat it as a
real finding. Check the ISO ID, Terraform Talos install image, and composition
defaults before assuming the claim value won.

## Validation

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes -o wide
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes -L stacks.io/swebench-pool
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl describe nodes | rg 'DiskPressure|nodefs|Allocatable'
talosctl --talosconfig /tmp/<spoke>-talosconfig get kubeletconfig
```

For dev SWE-bench capacity, continue with
`validate-dev-swebench-capacity.md`.
