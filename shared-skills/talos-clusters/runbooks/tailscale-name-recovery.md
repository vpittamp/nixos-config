# Runbook: Recover Canonical Tailscale Names After Recreate

Use when a recreated cluster gets `-1`, `-2`, or similar Tailscale hostnames, or
when `dev-api-v2` / `staging-api-v2` cannot be claimed.

## Identify The Exposure Model

ProxyGroup service-host:

- Examples: `dev-api-v2`, `staging-api-v2`, `argocd-hub`.
- Tailscale object is a Service named `svc:<hostname>`.
- Requires tailnet policy `autoApprovers.services["svc:<hostname>"]`.
- Check proxy pod `Self.CapMap["service-host"]`.

Device-backed Ingress:

- Examples: `workflow-builder-dev`, `mcp-gateway-dev`, `openshell-dev`,
  `tekton-dashboard-dev`.
- Tailscale object is a device hostname.
- Do not add `svc:*` approvals.
- Stale offline devices reserve names and force suffixes.

## Inventory

From Kubernetes:

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n tailscale get pods,svc,ingress
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n tailscale logs deploy/operator --since=30m | \
  rg 'hostname|service|ProxyGroup|error|failed'
```

From a proxy pod:

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n tailscale exec <proxy-pod> -- \
  tailscale status --json | jq '.Self | {HostName, DNSName, Tags, CapMap}'
```

From Tailscale API, list devices and look for canonical plus suffixed names:

```bash
curl -fsS -H "Authorization: Bearer $TS_TOKEN" \
  "https://api.tailscale.com/api/v2/tailnet/-/devices" | \
  jq -r '.devices[] | [.id, .hostname, .name, .lastSeen, .online] | @tsv' | \
  sort
```

If service-hosts are involved, inspect services too:

```bash
curl -fsS -H "Authorization: Bearer $TS_TOKEN" \
  "https://api.tailscale.com/api/v2/tailnet/-/services" | jq
```

## Fix

1. Delete stale offline devices that reserve canonical app hostnames.
2. Delete stale `svc:<hostname>` service-host records only when they are from an
   old cluster or wrong tag owner.
3. Wait for Tailscale control-plane propagation. Sixty to one hundred twenty
   seconds is normal.
4. Restart or re-authenticate the relevant proxy pods.
5. For ProxyGroups, run the repo helper from the stacks repo when available:

   ```bash
   KUBECONFIG=/tmp/<spoke>-kubeconfig \
     deployment/scripts/tailscale/proxygroup-auth.sh --cluster <spoke>
   ```

6. For device-backed Ingresses, deleting the Tailscale proxy StatefulSet/pod is
   usually enough after the old device is gone.

## Verify

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n tailscale get ingress -A
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n tailscale get proxygroup
```

Check that public DNS and Kubernetes contexts use canonical names:

```bash
kubectl --context <spoke>-api-v2.tail286401.ts.net get nodes
curl -kfsS https://workflow-builder-<spoke>.tail286401.ts.net/health || true
```

Only bump API hostnames when cleanup cannot release the canonical name. Bumping
creates follow-up work in tailnet policy, Argo cluster secrets, kubeconfigs,
operator docs, and user tooling.
