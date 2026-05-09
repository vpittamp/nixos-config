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
```

For dev SWE-bench capacity, continue with
`validate-dev-swebench-capacity.md`.
