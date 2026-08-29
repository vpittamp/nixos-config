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
| Upgrade Kubernetes only            | Use a Talos-supported in-place Kubernetes upgrade after health and etcd backup checks                     |
| Upgrade Talos                      | Use an in-place Talos image upgrade; verify compatibility before Kubernetes changes                       |
| Add a system extension (gVisor)    | In-place `talosctl upgrade` to an Image Factory schematic; see "In-place system extension upgrade"        |
| Validate benchmark capacity        | Use `kubernetes-capacity` for exact shapes, Kueue, observer, PSI, and dynamic concurrency                 |

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

### In-place Hetzner upgrade contract

Talos and Kubernetes upgrades on existing hub/dev Hetzner servers must preserve
the HCloud server objects and IDs. Use Talos-supported rolling upgrade APIs and
wait for each node to recover. Never call the provision, recreate, resize,
replace, or delete paths as an upgrade fallback: doing so can reprice servers
that currently have preferred pricing. If in-place upgrade cannot proceed,
stop and report the blocker rather than reprovisioning.

After each bounded upgrade, verify Kueue controllers/webhooks, capacity-observer
freshness, eligible-node PSI coverage, queue admission, and one representative
workload in addition to ordinary node/CNI/storage health.

### In-place system extension upgrade (gVisor)

Dev workers run the `siderolabs/gvisor` Talos extension from Image Factory
schematic `d9ff89777e246792e7642abd3220a616afb4e49822382e4213a2e528ab826fe5`.
It was installed by an in-place `talosctl upgrade` to that schematic's installer
image, one worker at a time — no Hetzner reprovision, resize, or replace, which
would reprice the servers. The desired state is codified in stacks
`deployment/scripts/talos-hetzner/provision-spoke.sh` (`WORKER_EXT_SCHEMATIC`,
`WORKER_GVISOR_EXT`) and `RuntimeClass-secure-gvisor.yaml`; edit those, never
only the live nodes.

| Step | Recipe |
| --- | --- |
| Address nodes | Use the talosctl endpoint from the talosconfig with `-n <node>`; do not pass `-e 10.0.1.1` |
| Sysctl | Set `user.max_user_namespaces=15000` in the machine config; the Talos default of 0 makes the runsc gofer fail with ENOSPC |
| Drain | PDB-protected pods block the built-in drain: `kubectl drain --disable-eviction <node>`, then `talosctl upgrade --drain=false -n <node>` |
| CNPG primary | Before draining the primary's node, move it with `kubectl patch cluster <name> --subresource=status` on `targetPrimary`; do not wait for the drain to trigger a failover |
| Label and RuntimeClass | Nodes carry `stacks.io/gvisor=true`; RuntimeClass `secure-gvisor` uses that nodeSelector |
| Prove | Interactive CLI profiles on execution class `interactive-cli-gvisor`: claude and kimi PASS the PTY + JuiceFS + headless-print matrix; codex is blocked only by an expired user credential; agy and glm are NOT tested (agy needs `Unconfined` seccomp, which runsc cannot provide) — see workflow-builder `docs/interactive-cli-sessions.md`. Production `dapr-agent-py` stays on runc. |

Repeat the drain/upgrade/uncordon cycle per worker and confirm the node reports
the extension and the `stacks.io/gvisor=true` label before moving on.

## Capacity Checks

Use `kubernetes-capacity` for workload-level tuning. At this infrastructure
boundary, do not infer safe concurrency from node count or a UI slider. Before
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
- Never resize, reprovision, replace, or delete an existing Hetzner Cloud server
  as part of a Talos, Kubernetes, Kueue, or CNI upgrade.
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
