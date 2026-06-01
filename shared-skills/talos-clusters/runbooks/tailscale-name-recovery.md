# Runbook: Recover Canonical Tailscale Names After Recreate

Use when a recreated cluster gets `-1`, `-2`, or similar Tailscale hostnames, or
when `dev-api-v2` / `staging-api-v2` cannot be claimed.

## Identify The Exposure Model

ProxyGroup service-host:

- Examples: `dev-api-v2`, `staging-api-v2`, `argocd-hub`.
- Tailscale object is a Service named `svc:<hostname>`.
- Requires tailnet policy `autoApprovers.services["svc:<hostname>"]`.
- Check proxy pod `Self.CapMap["service-host"]`.

Device-backed (LoadBalancer or Ingress):

- Examples: `workflow-builder-dev`, `openshell-dev`, `tekton-dashboard-dev`.
- Tailscale object is a device hostname.
- Do not add `svc:*` approvals.
- Stale offline devices reserve names and force suffixes.
- `workflow-builder` is now a Tailscale **L4 LoadBalancer Service**
  (`loadBalancerClass: tailscale`), NOT an Ingress and NOT Let's Encrypt (PR
  #2319) — it still owns the `workflow-builder-<spoke>` device and is still
  subject to `-1` drift. HTTPS terminates in-cluster via the `tls-terminator`
  sidecar (self-signed wildcard cert, no LE), so there is no per-hostname LE cert
  to churn. `mcp-gateway` is gone from the tailnet (in-cluster only); there is no
  `mcp-gateway-<spoke>` device to recover.

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

6. For device-backed exposures (Ingress or LoadBalancer), deleting the Tailscale
   proxy StatefulSet/pod is usually enough after the old device is gone.

## Stale-device cleanup: hard guarantee vs backstop

Two mechanisms keep stale `-N` collisions from accruing; they are complementary,
not redundant:

- **Hard on-recreate guarantee:** the gated
  `deployment/scripts/cleanup-tailnet-devices.sh` run pre-recreate. This is the
  authoritative cleanup — always run it before recreating a spoke so the new
  cluster claims canonical names. An in-Composition pre-onboarding cleanup was
  deliberately NOT built, because a function-pipeline error would halt ALL spoke
  provisioning.
- **Hygiene backstop:** the hub CronJob `tailnet-device-sweeper` (ns `tailscale`,
  every 15m; PR #2322/#2325) best-effort deletes OFFLINE stale spoke devices
  (offline-only via `lastSeen > 30m`) so dead devices do not silently accumulate
  between recreates. It does NOT replace the gated script.

API gotcha when matching devices: the Tailscale device `hostname` field DROPS
the `-N` suffix, so a live device and its dead `-N` twin share one `hostname` —
match on the MagicDNS `name` (which keeps the suffix), not `hostname`. `lastSeen`
IS a reliable liveness signal: control-plane keepalives keep it fresh for
connected devices, so an offline device's `lastSeen` genuinely ages out.

## Verify

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n tailscale get ingress -A
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n tailscale get proxygroup
# workflow-builder is a Tailscale LoadBalancer Service, not an Ingress:
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  get svc -l tailscale.com/parent-resource-ns -o wide
```

Check that public DNS and Kubernetes contexts use canonical names:

```bash
kubectl --context <spoke>-api-v2.tail286401.ts.net get nodes
curl -kfsS https://workflow-builder-<spoke>.tail286401.ts.net/health || true
```

Only bump API hostnames when cleanup cannot release the canonical name. Bumping
creates follow-up work in tailnet policy, Argo cluster secrets, kubeconfigs,
operator docs, and user tooling.
