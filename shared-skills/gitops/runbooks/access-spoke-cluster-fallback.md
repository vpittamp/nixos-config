# Access dev when the normal Tailscale context is broken

Scope: regain direct `kubectl` access to the script-provisioned dev Talos
cluster. Crossplane provisioning and its `crossplane-system` kubeconfig Secrets
are retired; do not search for or extract them.

## Available paths

Use the least-privileged path that can answer the question:

1. Hub principal view for managed Application sync/health:

   ```bash
   kubectl --kubeconfig ~/.kube/hub-config -n dev get applications
   ```

   This is a status/control-plane view, not arbitrary workload `kubectl`.
   Operation lifecycle is intentionally local to dev.

2. Hub Headlamp for read-oriented workload inspection. Enrollment stages the
   dedicated `headlamp-cluster-dev` Secret and restarts Headlamp after a
   recreate.

3. Direct admin kubeconfig produced by the Talos provisioning scripts:

   ```text
   /tmp/talos-spoke-dev/kubeconfig
   ```

   An existing `admin@dev` context may already point at the same cluster.

## Verify an existing direct kubeconfig

```bash
KUBECONFIG=/tmp/talos-spoke-dev/kubeconfig kubectl get nodes
KUBECONFIG=/tmp/talos-spoke-dev/kubeconfig kubectl -n workflow-builder get pods
```

The file is admin-equivalent. Keep it mode `0600` and do not paste its client
certificate/key into tickets, logs, or chat.

## Re-derive from Talos state

If the kubeconfig is missing or stale but the matching Talos config remains,
derive a fresh one from the live dev control plane:

```bash
WORKDIR=/tmp/talos-spoke-dev
chmod 700 "$WORKDIR"
talosctl --talosconfig "$WORKDIR/talosconfig" \
  kubeconfig "$WORKDIR/kubeconfig" --force
chmod 600 "$WORKDIR/kubeconfig"
KUBECONFIG="$WORKDIR/kubeconfig" kubectl get nodes
```

This is the same recovery pattern used by
`deployment/scripts/talos-hetzner/recreate-dev.sh::ensure_spoke_kubeconfig`.
If `talosctl kubeconfig` cannot reach the cluster, diagnose the Talos endpoint
or use Headlamp/hub status while repairing connectivity. Do not reconstruct a
kubeconfig from the argocd-agent `cluster-dev` Secret: that Secret is an agent
mapping with mTLS for the resource proxy, not a Kubernetes bearer credential.

## Repair the normal path

Once direct access works, repair Tailscale using the explicit dev kubeconfig:

```bash
KUBECONFIG=/tmp/talos-spoke-dev/kubeconfig \
  bash deployment/scripts/tailscale/proxygroup-auth.sh --cluster dev
```

Then verify the normal configured context and the local agent:

```bash
kubectl --context admin@dev get nodes
kubectl --context admin@dev -n argocd get deploy argocd-agent-agent
kubectl --kubeconfig ~/.kube/hub-config -n dev get applications
```

## Cleanup

`/tmp/talos-spoke-dev` is also the provisioning/recreate work directory, so do
not delete it during an active cluster operation. When the user deliberately
wants to remove retained admin material and no recreate/recovery is active,
remove both kubeconfig and Talos config together through the cluster runbook.

Authoritative source: `cluster-desired-state/references/dev.md` and
`deployment/scripts/talos-hetzner/{provision-spoke,recreate-dev}.sh`.
