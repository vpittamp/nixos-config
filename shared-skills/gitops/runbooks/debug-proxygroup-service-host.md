# Runbook: Debug Tailscale ProxyGroup service-host VIPs

## When to use

Use this for Tailscale Ingresses served by the hub `cluster-ingress` ProxyGroup, such as `argocd-hub`, `nocodb-hub`, `autokube-hub`, and `gitops-inventory-hub`.

Symptoms:
- Ingress `status.loadBalancer.ingress` is empty.
- `curl https://<service>.tail286401.ts.net` times out or has TLS handshake errors.
- `tailscale cert <service>.tail286401.ts.net` from a proxy pod says the domain is invalid.
- The Tailscale Service exists, but the proxy pod's `Self.CapMap["service-host"]` does not list it.

This is different from Funnel. If GitHub webhooks to `tekton-hub.tail286401.ts.net` return `status_code: 0` or DNS is NXDOMAIN, use `debug-funnel-orphan-tag.md` instead.

## Mental model

Four things must agree for a ProxyGroup-hosted VIP:

| Layer | Check |
|---|---|
| Kubernetes Ingress | `tailscale.com/hostname`, `tailscale.com/proxy-group`, and `tailscale.com/tags` |
| Tailnet policy | `policy.hujson` `autoApprovers.services["svc:<hostname>"]` includes the service tag |
| Tailscale Service | API shows `svc:<hostname>` with the expected tag and port |
| ProxyGroup device | Proxy pod `Self.Tags` matches the service tag and `Self.CapMap["service-host"]` includes `svc:<hostname>` |

For the hub `cluster-ingress` ProxyGroup, the preferred long-term tag is `tag:k8s-services`. `tag:k8s` is legacy compatibility only.

## Diagnostic

```bash
SERVICE=gitops-inventory-hub

# 1. Check live Ingress annotations and address.
kubectl --kubeconfig ~/.kube/hub-config -n argocd get ingress gitops-deployment-inventory \
  -o jsonpath='hostname={.metadata.annotations.tailscale\.com/hostname} tag={.metadata.annotations.tailscale\.com/tags} address={.status.loadBalancer.ingress[0].hostname}{"\n"}'

# 2. Check the hub ProxyGroup spec and status.
kubectl --kubeconfig ~/.kube/hub-config get proxygroup cluster-ingress \
  -o jsonpath='tags={.spec.tags} ready={.status.conditions[?(@.type=="ProxyGroupReady")].reason}{"\n"}'

# 3. Check what the proxy pod actually authenticated as and what services it may host.
kubectl --kubeconfig ~/.kube/hub-config -n tailscale exec cluster-ingress-0 -- \
  tailscale status --json | jq '.Self.Tags, .Self.CapMap["service-host"]'

# 4. Check Tailscale operator logs for this Ingress.
kubectl --kubeconfig ~/.kube/hub-config -n tailscale logs deploy/operator --since=20m | \
  grep -E "${SERVICE}|Ensuring Tailscale Service|Updating serve config|error|failed"

# 5. Confirm policy has an auto-approval for the service.
grep -A4 "\"svc:${SERVICE}\"" policy.hujson
```

If you need to inspect the tailnet Service object, use Tailscale OAuth credentials from Key Vault or the operator secret and query `/api/v2/tailnet/-/services`. The service should show `tags: ["tag:k8s-services"]` for hub `cluster-ingress` VIPs.

## Fix

1. Align Git first:
   - In the stacks repo, set the Ingress `tailscale.com/tags` to `tag:k8s-services`.
   - In `policy.hujson`, ensure `autoApprovers.services["svc:<hostname>"]` includes `tag:k8s-services`.
   - Push to `origin/main` so `.github/workflows/tailscale-acl.yml` applies the ACL policy.
   - Push to `gitea-ryzen/main` too if the stacks source branches should remain converged.

2. Let Argo apply the manifest change. Do not manually patch the Ingress unless this is an emergency:

   ```bash
   kubectl --kubeconfig ~/.kube/hub-config -n argocd get app gitops-promoter-config \
     -o jsonpath='rev={.status.sync.revision} sync={.status.sync.status} health={.status.health.status}{"\n"}'
   ```

3. Re-authenticate the hub `cluster-ingress` ProxyGroup if the proxy pods still show the old tag:

   ```bash
   KUBECONFIG=~/.kube/hub-config \
     deployment/scripts/tailscale/proxygroup-auth.sh --cluster hub
   ```

   The script should derive `["tag:k8s-services"]` from `ProxyGroup.spec.tags`, inject a one-hour auth key into the versioned `*-config` Secret, restart the proxy pods, remove the auth key, and restore the Tailscale operator.

4. If the helper fails around config secret parsing, make sure the stacks repo includes the versioned config fix: the live config key is usually `cap-*.hujson`, not `config.hujson`.

## Verify

```bash
# Proxy pods use the desired service tag and can host the VIP.
for pod in cluster-ingress-0 cluster-ingress-1; do
  kubectl --kubeconfig ~/.kube/hub-config -n tailscale exec "$pod" -- \
    tailscale status --json | jq -r \
    '"\(.Self.HostName) tags=\(.Self.Tags | join(",")) services=\(.Self.CapMap["service-host"][0] | keys | join(","))"'
done

# Ingress has an address.
kubectl --kubeconfig ~/.kube/hub-config -n argocd get ingress gitops-deployment-inventory \
  -o jsonpath='tag={.metadata.annotations.tailscale\.com/tags} address={.status.loadBalancer.ingress[0].hostname}{"\n"}'

# Auth key was removed from config secrets.
for secret in cluster-ingress-0-config cluster-ingress-1-config; do
  key=$(kubectl --kubeconfig ~/.kube/hub-config -n tailscale get secret "$secret" \
    -o json | jq -r '.data | keys[] | select(test("^cap-[0-9]+\\.hujson$"))' | head -1)
  kubectl --kubeconfig ~/.kube/hub-config -n tailscale get secret "$secret" -o json | \
    jq -r --arg key "$key" '.data[$key] | @base64d | fromjson | has("AuthKey")'
done

# Inventory-specific smoke test.
TOKEN=$(kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret gitops-deployment-inventory \
  -o jsonpath='{.data.bearerToken}' | base64 -d)
curl -kfsS -H "Authorization: Bearer ${TOKEN}" \
  https://gitops-inventory-hub.tail286401.ts.net/inventory.json | \
  jq '{generatedAt, environments: (.environments | length)}'
```

## Notes

- Restarting the proxy pods may be enough to refresh `service-host` after policy changes, but it does not change the device tag. If the pod is authenticated as the wrong tag, re-authenticate the ProxyGroup.
- The hub `argocd-hub` browser VIP and `gitops-inventory-hub` inventory VIP are both served by `cluster-ingress`. Fixing this ProxyGroup affects all of those browser services.
- Do not use this runbook for `ts-tekton-github-triggers` / `tekton-hub`; that path uses Funnel and is covered by `debug-funnel-orphan-tag.md`.
