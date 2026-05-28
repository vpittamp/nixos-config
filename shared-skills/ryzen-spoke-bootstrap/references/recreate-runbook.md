# Recreating an existing ryzen cluster

Use this when ryzen already exists and you need to tear it down and rebuild — e.g., upgrading Talos, recovering from corruption, or testing the bootstrap flow.

## Pre-destruction capture

Save anything you'll need from the existing cluster:

```bash
# Tailscale OAuth (used to be in the Tailscale operator Secret)
kubectl --context admin@ryzen get secret -n tailscale operator-oauth \
  -o jsonpath='{.data.client_id}' | base64 -d
kubectl --context admin@ryzen get secret -n tailscale operator-oauth \
  -o jsonpath='{.data.client_secret}' | base64 -d

# Azure WI tenant + client (also present on hub if hub-managed)
kubectl --context admin@ryzen get sa external-secrets -n external-secrets \
  -o jsonpath='{.metadata.annotations}'

# Postgres data — any tables you care about
kubectl --context admin@ryzen exec -n workflow-builder postgresql-0 -- \
  pg_dump -U postgres -d workflow_builder \
  -t environment_image_builds --data-only --column-inserts > /tmp/eib.sql
```

## Destroy the cluster

```bash
talosctl cluster destroy --name ryzen
# Verify
docker ps --filter "name=ryzen" --format "{{.Names}}"  # should be empty
ls ~/.talos/clusters/  # ryzen subdir should be gone
```

## Clean up kubeconfig contexts

```bash
kubectl config use-context hub  # switch away from soon-to-be-deleted ryzen
for ctx in $(kubectl config get-contexts --no-headers 2>/dev/null | awk '$2=="ryzen"{print $1}'); do
  kubectl config delete-context "$ctx"
done
kubectl config delete-cluster ryzen 2>/dev/null
kubectl config delete-user admin@ryzen 2>/dev/null
```

## Clean up stale Tailscale devices

When the cluster is recreated, the Tailscale operator registers fresh devices. But the OLD devices linger and can steal the `ryzen-api-v3` hostname (Tailscale's name-collision avoidance appends `-1`, `-2`...). Delete them via the Tailscale API before bootstrap.

```bash
# Get OAuth token from the old cluster's operator Secret (or new env vars)
TS_CLIENT_ID="$TS_OAUTH_CLIENT_ID"
TS_CLIENT_SECRET="$TS_OAUTH_CLIENT_SECRET"
TOKEN=$(curl -s -X POST "https://api.tailscale.com/api/v2/oauth/token" \
  -d "client_id=$TS_CLIENT_ID" -d "client_secret=$TS_CLIENT_SECRET" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# List + delete ryzen-tagged devices
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://api.tailscale.com/api/v2/tailnet/tail286401.ts.net/devices" | \
  python3 -c "
import sys, json, re, subprocess
d = json.load(sys.stdin)
patterns = [
  re.compile(r'^ryzen-'),
  re.compile(r'-ryzen($|-)'),
  re.compile(r'^k8s-api-cluster-'),  # old ProxyGroup pod hostnames
]
for x in d.get('devices', []):
    name = x['name'].split('.')[0]
    if any(p.search(name) for p in patterns):
        print(name, x['id'])
"
# Then for each id:
# curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "https://api.tailscale.com/api/v2/device/$id"
```

Also delete the stale Tailscale Service VIP (if a ProxyGroup-with-kube-apiserver was used previously):

```bash
curl -s -X DELETE -H "Authorization: Bearer $TOKEN" \
  "https://api.tailscale.com/api/v2/tailnet/tail286401.ts.net/services/svc:ryzen-api-v3"
```

## Reset hub-side state that pinned to old cluster

The hub's `tailscale/ryzen-api-egress` Service has annotation `tailscale.com/tailnet-fqdn: <previous-device>`. If the device name changes on recreate, update the annotation OR commit the right value to source manifest (`packages/components/hub-management/apps/headlamp.yaml`):

```bash
# Quick hub-side patch (will be reverted by ArgoCD selfHeal — also commit to source)
kubectl --context hub annotate svc ryzen-api-egress -n tailscale \
  "tailscale.com/tailnet-fqdn=ryzen-api-v3.tail286401.ts.net" --overwrite

# Force operator to recreate the StatefulSet pod
kubectl --context hub delete pod -n tailscale -l tailscale.com/parent-resource=ryzen-api-egress --grace-period=0 --force
```

## Now run the main bootstrap

Return to the main SKILL.md workflow from step 1.

## Post-bootstrap: re-merge env/hub Promoter PRs

If any in-flight Promoter PRs for env/hub are open, merge them so hub's reconciled state matches the source. The Promoter sometimes gets confused after cluster Secret changes; manual `gh pr create --base env/hub --head env/hub-next` + merge unblocks it.
