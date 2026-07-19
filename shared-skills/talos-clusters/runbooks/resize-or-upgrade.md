# Runbook: Resize Or Upgrade A Talos Spoke

Use when changing dev control-plane/worker counts, HCloud server types or
location, Talos/Kubernetes versions, the maintenance ISO, or worker labels.
Paths are relative to `/home/vpittamp/repos/PittampalliOrg/stacks/main`.

Crossplane is retired. There is no live `TalosSpokeClusterClaim`, XRD,
Composition, or provider reconcile to patch or wait for. The current authority
is `deployment/scripts/talos-hetzner/provision-spoke.sh`, normally driven by the
destructive `deployment/scripts/talos-hetzner/recreate-dev.sh` orchestrator.

## Choose The Operation

- Workload-only changes are mutable through GitOps and do not belong in this
  runbook.
- A Kubernetes-only minor upgrade may be performed in place with
  `talosctl upgrade-k8s` after a successful dry run.
- Node count/type, location/network, ISO, Talos version, and bootstrap machine
  configuration changes default to a full dev recreate. Do not manually add an
  HCloud server and expect the provisioning script or Talos PKI to adopt it.
- For a one-off validation cluster, pass environment overrides to
  `provision-spoke.sh`. For a durable dev default, edit that script's parameter
  defaults and the matching current docs before recreating.

The full recreate is destructive. Confirm no active benchmark/evaluation work,
review the data backup scope, and use
`cluster-desired-state/runbooks/recreate-dev.md` for the complete safety and
recovery sequence. `recreate-dev.sh` backs up its declared application tables,
destroys labeled HCloud resources, cleans stale tailnet devices, provisions,
bootstraps dependencies, enrolls the managed argocd-agent, restores data, and
runs the convergence gate.

## Current Provisioning Parameters

Read the script before every change; its checked-in defaults are the source of
truth. The primary controls are:

```text
LOCATION / NETWORK_ZONE
NETWORK_CIDR / SUBNET_CIDR
CP_COUNT / CP_TYPE
WORKER_COUNT / WORKER_TYPE
TALOS_VERSION
BOOTSTRAP_K8S_VERSION / K8S_VERSION
ISO_ID
WORKER_NODE_LABELS
PREVIEW_BUILD_WORKER_COUNT / PREVIEW_BUILD_USERNS_MAX
INSTALL_CNI / CILIUM_VERSION
```

Before choosing an HCloud type or location, verify availability rather than
assuming a similarly named type exists there:

```bash
hcloud location list -o columns=name,description,country,city,network_zone
for type in cpx41 cpx51 cpx42 cpx62; do
  hcloud server-type describe "$type" -o json | jq -r \
    --arg type "$type" '"\($type): " + ([.locations[]?.name] | join(","))'
done
```

## Resize Or Replace Dev

For an invocation-only override, export the target shape on the orchestrator.
The following illustrates the interface; set values to the approved target:

```bash
WORKER_COUNT=6 \
WORKER_TYPE=cpx51 \
CP_COUNT=3 \
CP_TYPE=cpx41 \
  deployment/scripts/talos-hetzner/recreate-dev.sh
```

To make a shape the durable default, update the corresponding default values in
`provision-spoke.sh`, validate the script, commit the change, and then run the
orchestrator. Do not create a replacement claim/XRD/composition layer.

For a small disposable test cluster, call the provisioner directly with a
non-dev name and isolated network CIDRs, then run the documented bootstrap and
enrollment sequence only if that test needs workloads:

```bash
CLUSTER_NAME=devtest \
CP_COUNT=1 WORKER_COUNT=1 \
CP_TYPE=cpx21 WORKER_TYPE=cpx21 \
NETWORK_CIDR=10.9.0.0/16 SUBNET_CIDR=10.9.1.0/24 \
  deployment/scripts/talos-hetzner/provision-spoke.sh
```

Destroy that test with the same identity and network parameters:

```bash
CLUSTER_NAME=devtest \
NETWORK_CIDR=10.9.0.0/16 SUBNET_CIDR=10.9.1.0/24 \
  deployment/scripts/talos-hetzner/provision-spoke.sh --destroy
```

## ISO And Kubernetes Version Constraint

The current Hetzner public Talos maintenance ISO is `1.12.4` (`ISO_ID=125127`).
It validates the requested bootstrap Kubernetes version while the node is still
running Talos 1.12.4. A one-shot bootstrap at a newer unsupported Kubernetes
minor fails before the target Talos image is installed to disk.

`provision-spoke.sh` encodes the supported sequence:

1. Generate machine configs for `BOOTSTRAP_K8S_VERSION` (currently 1.35).
2. Install `TALOS_VERSION` to disk through the generated machine config.
3. Install Cilium and wait for nodes.
4. When `K8S_VERSION` differs from the bootstrap version, run
   `talosctl upgrade-k8s` on the installed Talos system.

The default recreate stays at the bootstrap Kubernetes version for speed. Opt
into a newer target explicitly:

```bash
deployment/scripts/talos-hetzner/recreate-dev.sh --upgrade-k8s=1.36.0
```

For a Kubernetes-only upgrade on the existing dev cluster, first verify the
installed Talos supports the target and dry-run it:

```bash
T=/tmp/talos-spoke-dev/talosconfig
talosctl --talosconfig "$T" version
talosctl --talosconfig "$T" upgrade-k8s --to 1.36.0 --dry-run
talosctl --talosconfig "$T" upgrade-k8s --to 1.36.0
```

Do not patch a retired Crossplane claim to perform either sequence.

## Worker Labels

Pass custom-domain labels as a comma-separated `WORKER_NODE_LABELS` value. The
provisioner renders them into Talos `machine.nodeLabels` and performs its
post-bootstrap worker labeling required by the SWE-bench ResourceFlavor.

```bash
WORKER_NODE_LABELS='stacks.io/swebench-pool=dev-benchmark' \
  deployment/scripts/talos-hetzner/recreate-dev.sh
```

Do not put reserved `node-role.kubernetes.io/*` labels into the Talos
`machine.nodeLabels` input. NodeRestriction prevents the kubelet from
self-setting them; the provisioner stamps the worker role after bootstrap with
the admin kubeconfig.

## Change Checklist

1. Inspect `provision-spoke.sh` and confirm the current defaults and supported
   parameters.
2. Decide whether the change is an in-place Kubernetes upgrade or a destructive
   recreate.
3. Check HCloud location/type capacity and the ISO/Kubernetes compatibility.
4. Drain or cancel active work and verify the recreate backup covers required
   product data.
5. For a durable default, edit only the script parameters and matching current
   docs; do not edit retired Crossplane artifacts.
6. Validate shell syntax and run the full recreate or in-place upgrade.
7. Pass the orchestrator verify gate and the workload-specific capacity gates.

## Validation

```bash
bash -n deployment/scripts/talos-hetzner/provision-spoke.sh
bash -n deployment/scripts/talos-hetzner/recreate-dev.sh

K=/tmp/talos-spoke-dev/kubeconfig
T=/tmp/talos-spoke-dev/talosconfig
kubectl --kubeconfig "$K" get nodes -o wide
kubectl --kubeconfig "$K" get nodes \
  -L node-role.kubernetes.io/worker,stacks.io/swebench-pool
kubectl --kubeconfig "$K" describe nodes | rg 'DiskPressure|nodefs|Allocatable'
talosctl --talosconfig "$T" version

kubectl --kubeconfig ~/.kube/hub-config -n dev get applications
deployment/scripts/talos-hetzner/recreate-dev.sh --verify-only
```

For dev SWE-bench capacity, continue with
`validate-dev-swebench-capacity.md` before launching a ramp.

## Historical Boundary

Before Phase D, claims, XRD schema limits, composition worker fan-out, and
Crossplane provider health controlled this operation. Those mechanics are
retired context only and must not be used to operate or recreate dev.
