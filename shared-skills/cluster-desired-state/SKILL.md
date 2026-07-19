---
name: cluster-desired-state
description: "Plan, recreate, repair, or audit the PittampalliOrg hub, dev, and ryzen clusters end to end. Use for full-cluster desired state, provisioning order, argocd-agent enrollment, GitOps branch ownership, Tailscale secret transport, hub or spoke recovery, and post-rebuild convergence. Use talos-clusters for a narrow Talos node or capacity change and gitops for an application rollout or drift incident."
---

# Cluster Desired State

Use this skill for the ordered path from infrastructure to a healthy fleet. Do
not treat this skill as a snapshot of live versions or resource counts.

## Authority

Work from fresh repository state:

```bash
STACKS_ROOT=/home/vpittamp/repos/PittampalliOrg/stacks/main
git -C "$STACKS_ROOT" fetch origin
git -C "$STACKS_ROOT" status --short --branch
```

If the checkout is dirty or on unrelated work, create a worktree from
`origin/main`. Never reset or overwrite another user's changes.

Resolve contradictions in this order:

1. Provisioning, enrollment, render, and verification scripts.
2. Current manifests and executable tests on `origin/main`.
3. Focused repository docs.
4. This skill.

Historical Crossplane, local-Gitea, Azure-root-secret, and direct hub-to-spoke
ArgoCD procedures are not operating instructions. Confirm every named flag and
resource against current source before using it.

## Fleet Model

| Cluster | Role                                                      | Reconciliation authority                                     | Delivery branch                        |
| ------- | --------------------------------------------------------- | ------------------------------------------------------------ | -------------------------------------- |
| `hub`   | Management plane, principal, build and promotion services | Hub ArgoCD                                                   | Hydrated `env/hub`                     |
| `dev`   | Active shared workload spoke                              | Managed argocd-agent; applications are authored from the hub | Hydrated and promoted `env/spokes-dev` |
| `ryzen` | Local development spoke                                   | Autonomous argocd-agent and local ArgoCD                     | `main` directly through `root-ryzen`   |

The hub secret root is 1Password-backed. Spokes consume hub-mirrored secrets
through the Tailscale transport contract. Verify the current ExternalSecret and
ClusterSecretStore manifests instead of reintroducing an older Azure Workload
Identity path on a spoke.

## Choose The Entrypoint

| Operation                            | Canonical entrypoint                                                             |
| ------------------------------------ | -------------------------------------------------------------------------------- |
| Recreate or verify the hub           | `deployment/scripts/recreate-hub.sh` and `deployment/scripts/hub-verify-gate.sh` |
| Recreate dev                         | `deployment/scripts/talos-hetzner/recreate-dev.sh`                               |
| Recreate ryzen                       | `deployment/scripts/bootstrap-spoke-cluster.sh --recreate --ts-host-passthrough` |
| Enroll or repair dev agent mapping   | `deployment/scripts/argocd-agent/enroll-dev-agent.sh`                            |
| Enroll or repair ryzen agent mapping | `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh`                          |
| Narrow Talos resize or upgrade       | Use the `talos-clusters` skill                                                   |
| Application drift or image delivery  | Use the `gitops` skill                                                           |

Read each script's `--help` and source before execution. The wrapper scripts own
ordering, secret transport, agent enrollment, Headlamp credential refresh, and
verification; do not manually replay a remembered subset of their steps.

## Recreate Workflow

1. **Establish target and blast radius.** Confirm cluster name, requested
   operation, source revision, active workloads, and whether destruction is
   expected.
2. **Drain and preserve state.** Stop active benchmark, workflow, preview, and
   build activity through their owning APIs. Back up target-local product data
   using the current recreate script's supported path.
3. **Validate credentials and tools.** Check `talosctl`, `kubectl`, `hcloud`,
   `tailscale`, `argocd`, `op`, and required kubeconfigs without printing
   secrets.
4. **Inspect desired state.** Read the target script, its sourced libraries,
   relevant overlay, agent enrollment manifest, and verification gate at the
   same revision.
5. **Run the canonical wrapper.** Preserve its logs and stop on the first failed
   phase. Do not patch around a failed phase before finding the owning source.
6. **Verify every layer.** A Ready node is necessary but not sufficient.
7. **Reconcile declaratively.** Put durable corrections through `stacks`; use
   imperative edits only to diagnose or restore the controller that owns the
   desired state.

## Convergence Gate

Do not call a rebuild complete until all of these are demonstrated:

- Nodes, CNI, DNS, storage, and required capacity labels are healthy.
- The argocd-agent principal and target agent agree on identity and mode.
- The hub cluster mapping is an agent mapping where expected, not a stale
  bearer-token cluster credential.
- External Secrets and the spoke transport store are Ready without exposing
  secret values.
- Root and child Applications use the expected source branch and are
  `Synced`/`Healthy` or have an explicitly understood exception.
- Tailscale API, service, and user-facing routes resolve through the intended
  device or service-host ownership model.
- Workflow Builder and one representative durable workflow path are healthy
  when that workload belongs on the target.
- Temporary admin kubeconfigs, bootstrap Jobs, active leases, and failed
  operations are cleaned up.

## Safety Rules

- Never recreate a cluster while live benchmark, preview, or durable workflow
  work is still running.
- Never infer a spoke's authority from a legacy Secret name. Inspect its current
  argocd-agent mode and local Applications.
- Never delete a Tailscale device or service reservation until the current
  owner, hostname, and replacement are proven.
- Keep generated overlays generated. Run their owning renderer and validation
  script; do not hand-edit generated output.
- Keep admin kubeconfigs mode `0600`, outside git, and remove temporary copies
  after recovery.
- Do not use ryzen as a substitute target when the request names dev or hub.

## Source Map

Start with these current sources in `PittampalliOrg/stacks`:

- `AGENTS.md`
- `deployment/scripts/recreate-hub.sh`
- `deployment/scripts/hub-verify-gate.sh`
- `deployment/scripts/talos-hetzner/recreate-dev.sh`
- `deployment/scripts/bootstrap-spoke-cluster.sh`
- `deployment/scripts/argocd-agent/`
- `deployment/scripts/lib/spoke-transport-bootstrap.sh`
- `packages/overlays/{hub,dev,ryzen}/`
- `packages/components/hub-management/`
- `packages/components/spoke-tailscale-secrets/CONTRACT.md`
- `packages/components/hub-onepassword/README.md`

Use `docs/gitops-architecture-overview.md`, `docs/hub-cluster-setup.md`, and
`docs/hub-recovery-runbook.md` as orientation only where they agree with the
executable sources above.
