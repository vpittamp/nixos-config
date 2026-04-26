# Runbook: Debug device-backed Tailscale Ingresses

## When to use

Use this for promoted-spoke app Ingresses that use `ingressClassName: tailscale` and do **not** set `tailscale.com/proxy-group`.

Typical examples:
- `workflow-builder-dev` / `workflow-builder-staging`
- `mcp-gateway-dev` / `mcp-gateway-staging`
- `phoenix-dev` / `phoenix-staging`

Symptoms:
- The canonical hostname does not resolve, but `<hostname>-1.tail286401.ts.net` does.
- The HTTPS URL works, but ArgoCD reports the tailscale-ingresses app as `Progressing`.
- Ingress `status.loadBalancer.ingress` is empty even though the Tailscale device is online.
- A stale Tailscale Service such as `svc:workflow-builder-staging` exists for a hostname that should be a device.

Do not use this for hub `cluster-ingress` VIPs such as `argocd-hub`, `nocodb-hub`, or `gitops-inventory-hub`; those are ProxyGroup service-hosts. Use `debug-proxygroup-service-host.md`.

## Mental model

Device-backed Tailscale Ingresses create Tailscale devices, usually tagged `tag:k8s`. They are not Tailscale Services and should not have `policy.hujson` `autoApprovers.services["svc:<hostname>"]` entries.

A stale `svc:<hostname>` record can reserve the canonical DNS name. The live Ingress proxy then registers as `<hostname>-1`, which makes the app reachable only on the wrong suffix until the stale Service is removed.

The operator stores device config and state in `tailscale/ts-<ingress-name>-<hash>-0`. If you manually repair that Secret, keep the operator metadata labels intact; otherwise the endpoint may work while Kubernetes/ArgoCD health stays `Progressing`.

## Diagnostic

```bash
CLUSTER=staging
NS=workflow-builder
INGRESS=workflow-builder-tailscale
HOST=workflow-builder-staging

# 1. Confirm this is device-backed, not ProxyGroup-backed.
kubectl --context "$CLUSTER" -n "$NS" get ingress "$INGRESS" -o jsonpath='host={.metadata.annotations.tailscale\.com/hostname} proxyGroup={.metadata.annotations.tailscale\.com/proxy-group} address={.status.loadBalancer.ingress[0].hostname}{"\n"}'

# 2. Check DNS for canonical vs stale suffix.
dig +short "${HOST}.tail286401.ts.net"
dig +short "${HOST}-1.tail286401.ts.net"

# 3. Check the public app path.
curl -k -sS -o /dev/null -w 'http=%{http_code} remote_ip=%{remote_ip} time=%{time_total}\n' \
  -L --max-time 30 "https://${HOST}.tail286401.ts.net"

# 4. Find the operator-managed objects for this Ingress.
kubectl --context "$CLUSTER" -n tailscale get sts,pod,secret | rg "$INGRESS|workflow-builder"
```

Query the live tailnet before deleting anything:

```bash
vault="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
client_id=$(az keyvault secret show --vault-name "$vault" --name TAILSCALE-OAUTH-CLIENT-ID --query value -o tsv)
client_secret=$(az keyvault secret show --vault-name "$vault" --name TAILSCALE-OAUTH-CLIENT-SECRET --query value -o tsv)
token=$(curl -fsS -d "client_id=${client_id}" -d "client_secret=${client_secret}" \
  https://api.tailscale.com/api/v2/oauth/token | jq -r '.access_token')

curl -fsS -H "Authorization: Bearer ${token}" \
  "https://api.tailscale.com/api/v2/tailnet/-/services" | \
  jq -r --arg svc "svc:${HOST}" '.vipServices[]? | select(.name == $svc)'

curl -fsS -H "Authorization: Bearer ${token}" \
  "https://api.tailscale.com/api/v2/tailnet/-/devices?fields=all" | \
  jq -r --arg host "${HOST}" '
    .devices[]?
    | select(.hostname == $host or .hostname == ($host + "-1"))
    | [.id,.hostname,.name,((.tags // [])|join("|")),.connectedToControl,.lastSeen] | @tsv'
```

For stale cleanup candidates, restrict deletion to Kubernetes/operator devices that are offline and carry retired tags such as `tag:spoke-ingress`, `tag:ts-spoke-ui`, or `tag:ts-ingress-proxy`. Do not delete personal user devices just because they are offline.

## Fix

1. Fix the declared policy first.

Remove `svc:<hostname>` from `policy.hujson` if the hostname is device-backed. Keep `svc:*` approvals only for real Tailscale Services and ProxyGroup service-hosts. Push to `origin/main` and wait for `.github/workflows/tailscale-acl.yml` to validate and apply.

2. Delete stale tailnet reservations only after confirming they are stale.

For a stale Tailscale Service, confirm it has no current host devices and the Kubernetes Ingress is not ProxyGroup-backed. Delete it with the Tailscale admin console or Services API. URL-encode the `svc:*` name if using the API.

For a stale offline device, confirm `connectedToControl == false`, the tag is retired, and the current Ingress already has a separate online device. Then delete by device ID:

```bash
curl -fsS -X DELETE -H "Authorization: Bearer ${token}" \
  "https://api.tailscale.com/api/v2/device/${DEVICE_ID}"
```

3. If the endpoint works but ArgoCD stays `Progressing`, repair the proxy Secret metadata.

Compare the Secret to a healthy device-backed proxy on dev. The Secret should have the same Tailscale labels and should not carry a huge `kubectl.kubernetes.io/last-applied-configuration` annotation from a manual `kubectl apply`.

```bash
SECRET=ts-workflow-builder-tailscale-bs69q-0

kubectl --context staging -n tailscale label secret "$SECRET" \
  tailscale.com/managed=true \
  tailscale.com/parent-resource=workflow-builder-tailscale \
  tailscale.com/parent-resource-ns=workflow-builder \
  tailscale.com/parent-resource-type=ingress \
  --overwrite

kubectl --context staging -n tailscale annotate secret "$SECRET" \
  kubectl.kubernetes.io/last-applied-configuration- || true
```

4. If the proxy lost auth entirely, re-auth carefully.

Ingress proxy auth keys are read from the generated `cap-*.hujson` config inside the same Secret, not from a simple pod env var. If you inject a short-lived auth key manually, remove `AuthKey` from the config after the pod logs in, keep the current profile/state keys, and restore the labels above before verifying ArgoCD health.

## Verify

```bash
# Canonical resolves; stale suffix does not.
dig +short workflow-builder-staging.tail286401.ts.net
dig +short workflow-builder-staging-1.tail286401.ts.net

# HTTPS succeeds on canonical.
curl -k -sS -o /dev/null -w 'http=%{http_code} remote_ip=%{remote_ip}\n' \
  -L --max-time 30 https://workflow-builder-staging.tail286401.ts.net

# Ingress status is populated.
kubectl --context staging -n workflow-builder get ingress workflow-builder-tailscale \
  -o custom-columns=HOST:.spec.rules[0].host,ADDRESS:.status.loadBalancer.ingress[0].hostname --no-headers

# ArgoCD sees the tailscale-ingresses app as healthy.
kubectl --kubeconfig ~/.kube/hub-config -n argocd get applications.argoproj.io staging-tailscale-ingresses \
  -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision --no-headers
```

Expected:
- Canonical hostname resolves to the live Tailscale device IP.
- `<hostname>-1.tail286401.ts.net` is empty.
- The public HTTPS path returns `200`.
- The Tailscale device is online with `tag:k8s`.
- The ArgoCD tailscale-ingresses app is `Synced` and `Healthy`.
