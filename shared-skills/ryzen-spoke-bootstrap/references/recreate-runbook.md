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

When the cluster is recreated, the Tailscale operator registers fresh devices. But the OLD devices linger and can steal a hostname (Tailscale's name-collision avoidance appends `-1`, `-2`...). The critical one is the **`ryzen-operator`** apiserver-proxy device — if a stale duplicate keeps it, the new operator becomes `ryzen-operator-1` and the cluster Secret `server: https://ryzen-operator.tail286401.ts.net` + HUB CoreDNS rewrite no longer point at the live cluster (hub→ryzen ArgoCD sync stays broken). The `workflow-builder-ryzen` LB device collides the same way. Delete the stale devices via the Tailscale API before bootstrap.

> **The hard on-recreate guarantee is the gated `deployment/scripts/cleanup-tailnet-devices.sh`** run pre-destroy (invoked automatically by `--recreate` before `talosctl cluster destroy`). The manual snippet below is the same logic, for ad-hoc use. A SECOND, best-effort backstop is the hub CronJob **`tailnet-device-sweeper`** (ns `tailscale`, every 15m, PR #2322/#2325): it deletes OFFLINE stale spoke devices (`lastSeen > 30m`) so dead devices don't accumulate. API gotcha: the device `hostname` field DROPS the `-N` suffix (a live device and its dead `-N` twin share one `hostname`), so match on the MagicDNS `name`; `lastSeen` IS a reliable liveness signal (control-plane keepalives keep it fresh for connected devices). An in-Composition pre-onboarding cleanup was deliberately NOT built — a function-pipeline error there would halt ALL spoke provisioning.

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
  re.compile(r'^ryzen-operator($|-)'),  # the apiserver-proxy device — MUST be cleared so the new operator claims the canonical hostname
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

## Reset hub-side state that pinned to old cluster (LEGACY — pre-agent hub→ryzen sync wiring)

> **LEGACY / OPTIONAL DIAGNOSTICS (post argocd-agent cutover, 2026-06):** the hub no longer
> reconciles ryzen's apps over the `ryzen-api-egress` + hub-CoreDNS-rewrite hub→spoke kube path
> (ryzen reconciles LOCALLY as an autonomous agent). This section is NOT required for an agent-era
> recreate. The `ryzen-api-egress` path survives only as the kube endpoint **Headlamp** uses, so
> re-point/verify it if Headlamp can't reach ryzen — otherwise skip.

The hub's `tailscale/ryzen-api-egress` ExternalName Service has annotation `tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net` (it targets the spoke operator's apiserver-proxy device — NOT a separate `ryzen-api-v3` device anymore). The operator reads the annotation only at pod create, so after a recreate force the StatefulSet pod to recreate so it reconnects to the freshly-registered `ryzen-operator` device:

```bash
# Source of truth for the annotation: packages/components/hub-management/apps/headlamp.yaml
# Force operator to recreate the StatefulSet pod (reconnects to the new device)
kubectl --kubeconfig ~/.kube/hub-config delete pod -n tailscale \
  -l tailscale.com/parent-resource=ryzen-api-egress --grace-period=0 --force
```

Confirm the HUB CoreDNS rewrite that routes the operator FQDN to the egress is present (LEGACY — only relevant for the Headlamp kube endpoint now, NOT ArgoCD sync):
```bash
kubectl --kubeconfig ~/.kube/hub-config -n kube-system get cm coredns \
  -o jsonpath='{.data.Corefile}' | grep ryzen-operator
# expect: rewrite name exact ryzen-operator.tail286401.ts.net ryzen-api-egress.tailscale.svc.cluster.local
```

## Now run the main bootstrap

> **AGENT-MODEL UPDATE (argocd-agent cutover, 2026-06).** ryzen is now an **AUTONOMOUS
> argocd-agent** (it reconciles its own apps locally + pushes status to the hub principal;
> the agent dials OUTBOUND over the tailnet). The pre-bootstrap hub→ryzen apiserver-proxy
> SNI / static-`cluster-ryzen`-Secret / operator-FQDN-CoreDNS-rewrite steps ABOVE are
> **obsolete** for an agent-era recreate — the hub no longer reconciles ryzen's apps over a
> hub→spoke kube path. `bootstrap-spoke-cluster.sh` step 9 now ENROLLS the agent via
> `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh` (replacing the retired
> `register-spoke-with-hub.sh`). The `--ts-acl-mode` / `--ts-host-passthrough` flags are
> vestigial (parsed for compat, ignored). See the **`cluster-desired-state`** skill for the
> authoritative current model.

Return to the main SKILL.md workflow from step 1. Canonical recreate command:
```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
# Provisions the Talos cluster + seeds deps + transport, then enrolls the autonomous agent
# (enroll-ryzen-agent.sh) + advances inner-loop. --ts-acl-mode no longer needed.
bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate
```

## Post-bootstrap: spoke secret-transport re-apply (RYZEN CoreDNS rewrite)

`bootstrap-spoke-cluster.sh` applies the imperative spoke-transport half (`deployment/scripts/lib/spoke-transport-bootstrap.sh --apply-manifests deployment/manifests/spoke-transport/`), but because Talos resets the coredns ConfigMap on every recreate, the SPOKE rewrite must be (re-)inserted each time. Confirm it landed:
```bash
kubectl --context admin@ryzen -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep k8s-api-hub-ingress
# expect: rewrite name exact k8s-api-hub-ingress.tail286401.ts.net k8s-api-hub-egress.tailscale.svc.cluster.local
kubectl --context admin@ryzen get clustersecretstore hub-secrets-store   # Ready=True
kubectl --context admin@ryzen -n external-secrets get secret hub-secrets-token
```
If the rewrite is missing or `hub-secrets-store` is NotReady, re-run `spoke-transport-bootstrap.sh` (idempotent). See `references/failure-modes.md` "ESO hub-secrets-store".

## Post-bootstrap: advance inner-loop (+ LEGACY SNI check)

```bash
# Ryzen reads inner-loop, NOT main — advance it so the overlay reaches ryzen:
git -C /home/vpittamp/repos/PittampalliOrg/stacks/main push origin origin/main:refs/heads/inner-loop

# LEGACY/diagnostics only — the operator apiserver-proxy SNI is no longer the sync path
# (ryzen reconciles locally); useful only to confirm the Headlamp/ESO Tailscale endpoint:
curl -sk --connect-to ryzen-operator.tail286401.ts.net:443:<egress-or-tailnet-ip>:443 \
  -o /dev/null -w "%{http_code}\n" https://ryzen-operator.tail286401.ts.net/version   # expect 200
```

## Post-bootstrap: re-merge env/hub Promoter PRs (only if hub-state changed)

If the recreate changed hub-side state (e.g., the static `cluster-ryzen` Secret or appset definitions) and in-flight Promoter PRs for env/hub are open, merge them so hub's reconciled state matches the source. Manual `gh pr create --base env/hub --head env/hub-next` + merge unblocks a stuck Promoter. NOTE: ryzen workloads (`packages/overlays/ryzen` → `env/spokes-ryzen`) have NO Promoter — they advance via the `inner-loop` branch push above.
