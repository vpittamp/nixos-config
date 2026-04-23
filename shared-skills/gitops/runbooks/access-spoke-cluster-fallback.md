# Runbook: Access a spoke cluster when Tailscale is broken

## Symptoms / when to use

`kubectl --context dev-cluster get nodes` (or staging-cluster, etc.) errors with one of:

- `dial tcp: lookup k8s-api-dev.tail286401.ts.net on 100.100.100.100:53: no such host` — Tailscale MagicDNS doesn't resolve the spoke API VIP
- `connection timed out` to a Tailscale IP
- The context doesn't even exist in `~/.kube/config` (the K9s launcher hasn't been able to discover the API endpoint)

Likely upstream cause: the spoke's `k8s-api-<spoke>` ProxyGroup has the same orphan-tag issue documented in `debug-funnel-orphan-tag.md`. While you fix that, you still need to reach the spoke for inspection or surgery.

## Diagnostic — identify the right Crossplane secret

Crossplane's `kubernetes` provider extracts each spoke's admin kubeconfig at provisioning time and stores it in `crossplane-system` on the hub. Secret name pattern: `<spoke>-<5-char-suffix>-kubeconfig`.

```bash
kubectl --kubeconfig ~/.kube/hub-config get secrets -n crossplane-system \
  -o custom-columns='NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp' | \
  grep kubeconfig
# dev-2frrm-kubeconfig                                connection.crossplane.io/v1alpha1   2026-03-28T...
# staging-j7ptt-kubeconfig                            connection.crossplane.io/v1alpha1   2026-03-28T...
```

The 5-char suffix is the Crossplane composition revision; if the spoke is deleted and recreated, the suffix changes — so always grep for the latest rather than memorizing it.

## Fix steps

```bash
# 1. Extract the kubeconfig (admin certs — handle carefully)
kubectl --kubeconfig ~/.kube/hub-config get secret <spoke>-XXXXX-kubeconfig -n crossplane-system \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/<spoke>-kubeconfig
chmod 600 /tmp/<spoke>-kubeconfig

# 2. Sanity test
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes
# Should list the Talos nodes (control-plane + workers)

# 3. Do whatever you came to do
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder get pods
# ... etc

# 4. ALWAYS shred when done — these are admin-equivalent certs
shred -u /tmp/<spoke>-kubeconfig
```

## What this kubeconfig connects to

The kubeconfig embeds Talos client certs and points at the spoke's first control-plane public IP (e.g., `https://178.156.225.243:6443` for dev). It bypasses Tailscale entirely and goes directly to the Hetzner-public Talos endpoint. So:

- It works whenever the spoke's first control-plane node is up and its API server is healthy
- It uses the user's outbound internet → Hetzner public IP, not the tailnet
- TLS is verified against the embedded CA (Talos PKI), so even a network-level intercept can't MitM

For dev/staging:
- dev-cp-1 → 178.156.225.243:6443
- staging-cp-1 → 178.156.230.212:6443

(See `hcloud server list` for the current IPs; servers are persistent so these don't change unless the cluster is recreated.)

## Verify

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get nodes
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl version --short
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get ns
```

If any of these errors with `Unauthorized` or `unable to connect to the server`, the kubeconfig might be stale (spoke was recreated and the Crossplane secret has the OLD certs). Re-check that you grabbed the newest secret name (`-w`-watch the Crossplane composition or `kubectl get secrets -n crossplane-system --sort-by=.metadata.creationTimestamp`).

## Why this isn't the default

The Tailscale path is preferred because:
- Identity-based access via the user's tailnet identity (no shared admin certs)
- API server isn't exposed on the public internet from the cluster's perspective; goes through the Tailscale auth proxy
- K9s + sway integration — zero-config, no extracted files

The Crossplane secret path is the **break-glass** fallback. Don't make it your daily driver — the admin certs are equivalent to root-on-the-cluster, and the more you handle them outside their secret, the more chances for them to leak.

## Related

- `debug-funnel-orphan-tag.md` — fix the underlying Tailscale issue so the normal path works again
- `reference/access-paths.md` — full access path reference
