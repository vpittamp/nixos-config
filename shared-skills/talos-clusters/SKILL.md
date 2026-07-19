---
name: talos-clusters
description: "Operate PittampalliOrg Talos and Hetzner cluster infrastructure. Use for Talos node provisioning, dev worker resize, machine configuration, Kubernetes or Talos upgrades, HCloud failures, capacity validation, and node-level recovery. Use cluster-desired-state for a full hub/dev/ryzen rebuild and gitops for application reconciliation after the nodes are healthy."
---

# Talos Clusters

Keep this skill at the infrastructure boundary: machines, Talos, Kubernetes,
networking, storage prerequisites, and schedulable capacity. A complete fleet
recreate belongs to `cluster-desired-state`.

## Source First

Use current source from both repositories:

```bash
STACKS_ROOT=/home/vpittamp/repos/PittampalliOrg/stacks/main
TALOS_ROOT=/home/vpittamp/repos/PittampalliOrg/talos-cluster/main
git -C "$STACKS_ROOT" status --short --branch
git -C "$TALOS_ROOT" status --short --branch
```

Create clean worktrees from `origin/main` for edits. Read the current script,
patches, Talos version pins, and `--help` before running a remembered command.
Crossplane claims and compositions are retired and are not a control surface.

## Decide The Operation

| Request                            | Owning path                                                                                              |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Recreate dev from scratch          | `cluster-desired-state` and `deployment/scripts/talos-hetzner/recreate-dev.sh`                           |
| Provision or replace dev nodes     | `deployment/scripts/talos-hetzner/provision-spoke.sh`                                                    |
| Install dev bootstrap dependencies | `deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh`                                               |
| Recreate ryzen Talos-in-Docker     | `cluster-desired-state` and `deployment/scripts/bootstrap-spoke-cluster.sh`                              |
| Recreate or repair hub machines    | `cluster-desired-state`, `deployment/scripts/recreate-hub.sh`, and the `talos-cluster` repo              |
| Resize worker capacity             | Modify the imperative provisioner inputs and regenerate; do not patch a retired claim                    |
| Upgrade Kubernetes only            | Use a Talos-supported Kubernetes upgrade after health and etcd backup checks                             |
| Upgrade Talos                      | Use machine configuration/image upgrade semantics; verify compatibility before Kubernetes changes        |
| Validate benchmark capacity        | Inspect live node allocatable/requested resources, Kueue quotas, and workflow-builder capacity snapshots |

## Change Workflow

1. **Inspect health before mutation.** Capture nodes, Talos health, etcd health,
   pod placement, storage, Kueue queues, and active workloads.
2. **Classify the change.** Separate machine replacement, Talos upgrade,
   Kubernetes upgrade, worker-count change, and workload-capacity tuning. Do not
   combine them without an explicit reason and rollback point.
3. **Back up state.** Take an etcd snapshot for control-plane work and use the
   target recreate path for product data. Confirm the backup can be read.
4. **Edit desired inputs.** Change scripts, patches, or checked-in config in a
   clean worktree. Keep credentials and generated machine secrets out of git.
5. **Validate configuration.** Run the repository's render/config validation
   and review the resulting machine and Kubernetes version changes.
6. **Apply in bounded order.** Preserve quorum, wait for each node to recover,
   and stop if health regresses.
7. **Hand back to GitOps.** Once nodes and core services are healthy, use
   `cluster-desired-state` or `gitops` to verify agent and workload convergence.

## Capacity Checks

Do not infer safe benchmark concurrency from node count or a UI slider. Before
raising a limit, verify:

- Node allocatable CPU, memory, ephemeral storage, and current requests.
- Kueue ClusterQueue and LocalQueue quota and admitted workloads.
- Sandbox plus agent-host composite request size.
- Dapr workflow worker and sidecar readiness.
- Evaluator parallelism and exact-ready image coverage.
- Provider rate limits and active benchmark/resource leases.

Use a small clean cohort first, prove cleanup returns active leases and
workloads to zero, then increase one layer at a time. Record current evidence in
the task or canonical product docs, not as a permanent number in this skill.

## Verification

At minimum, prove:

```bash
talosctl health --talosconfig <target-config>
kubectl --context <target> get nodes -o wide
kubectl --context <target> get pods -A
kubectl --context <target> get storageclass,pv,pvc -A
kubectl --context <target> get clusterqueue,localqueue,workload -A
```

Then run `deployment/scripts/cluster-readiness.sh` or the target-specific
verification gate and confirm the target agent/Application view converges.

## Safety Rules

- Require explicit user intent before deleting or recreating machines.
- Preserve etcd quorum and never upgrade all control-plane nodes together.
- Do not mix Talos ISO replacement with an in-place Kubernetes upgrade.
- Do not expose generated kubeconfig, talosconfig, machine secrets, or HCloud
  credentials in logs or commits.
- Do not use ryzen when the requested target is dev.
- Treat live patches as diagnostics; encode durable fixes in source.

## Canonical Sources

- `PittampalliOrg/stacks/deployment/scripts/talos-hetzner/`
- `PittampalliOrg/stacks/deployment/scripts/{cluster-readiness.sh,cluster-health-check.sh}`
- `PittampalliOrg/stacks/deployment/scripts/bootstrap-spoke-cluster.sh`
- `PittampalliOrg/stacks/deployment/scripts/recreate-hub.sh`
- `PittampalliOrg/talos-cluster/scripts/`
- `PittampalliOrg/talos-cluster/patches/`
- Current Talos and Kubernetes compatibility documentation
