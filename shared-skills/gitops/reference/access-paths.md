# Access paths: how to reach hub, spokes, ArgoCD, and registries

## Hub kubectl

**From ryzen (the user's workstation):** the hub kubeconfig is local — no SSH wrapper:

```bash
kubectl --kubeconfig ~/.kube/hub-config get nodes
```

**From any other host:**

```bash
ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-config get nodes"
```

Both target the Talos endpoint `5.161.99.23:6443` and bypass any Tailscale VIP (so they keep working when the `k8s-api-hub` ProxyGroup is degraded).

You can also use the Tailscale-VIP context if it's healthy:

```bash
kubectl --context hub-cluster get nodes
# uses k8s-api-hub.tail286401.ts.net
```

## Spoke kubectl — primary path (Tailscale)

Per-spoke ProxyGroups expose each spoke's API server as `<spoke>-api-v2.tail286401.ts.net` (or similar — check `hub-and-spoke-quickstart.md` for the current naming). The K9s launcher script auto-merges them into `~/.kube/config`:

```bash
kubectl --context dev-api-v2.tail286401.ts.net get nodes
kubectl --context staging-api-v2.tail286401.ts.net get nodes
kubectl --context dev-cluster get nodes      # if Tailscale registers it
kubectl --context staging-cluster get nodes
kubectl --context kind-ryzen get nodes        # ryzen kind, no Tailscale needed
```

If the context exists in `~/.kube/config` but `kubectl` errors with `lookup …: no such host`, the Tailscale device for that ProxyGroup isn't registering its hostname publicly (often the orphan-tag issue — see `runbooks/debug-funnel-orphan-tag.md`).

The `*-api-v2` VIPs are Tailscale service-hosts. `policy.hujson` must approve `svc:dev-api-v2` / `svc:staging-api-v2`, and devices authenticated as `tag:spoke-api` need a Kubernetes grant to `tag:k8s` with `system:masters`. If ACL policy has changed but the VIP still fails, re-authenticate the spoke ProxyGroup with `deployment/scripts/tailscale/proxygroup-auth.sh --cluster <spoke>` after verifying the Tailscale ACL GitHub Action succeeded.

## Spoke kubectl — fallback (Crossplane-managed kubeconfig)

When the Tailscale path is broken, every spoke's full admin kubeconfig lives in a Secret on the hub, written by Crossplane's `kubernetes` provider during cluster onboarding:

```bash
# Find it
kubectl --kubeconfig ~/.kube/hub-config get secrets -n crossplane-system | grep kubeconfig
# dev-2frrm-kubeconfig                                connection.crossplane.io/v1alpha1
# staging-j7ptt-kubeconfig                            connection.crossplane.io/v1alpha1

# Extract — admin certs, treat with care
kubectl --kubeconfig ~/.kube/hub-config get secret dev-2frrm-kubeconfig -n crossplane-system \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/dev-kubeconfig
chmod 600 /tmp/dev-kubeconfig

KUBECONFIG=/tmp/dev-kubeconfig kubectl get nodes
# … do whatever you came to do …

shred -u /tmp/dev-kubeconfig    # ALWAYS shred when done
```

The kubeconfig points at the spoke's first control-plane public IP (e.g. `https://178.156.225.243:6443` for dev), bypassing Tailscale entirely. The Crossplane secret name suffix (`-2frrm`, `-j7ptt`) is the composition revision; if you delete and recreate the spoke, the suffix changes.

The full procedure is in `runbooks/access-spoke-cluster-fallback.md`.

## Headlamp (hub UI → spokes)

ryzen Headlamp connectivity uses a dedicated `headlamp-cluster-ryzen` Secret (real kube-API endpoint = the ryzen host's raw-TCP Tailscale passthrough + read-only SA token + CA, label `headlamp.dev/cluster=true`) — **separate** from the ArgoCD agent path. `enroll-ryzen-agent.sh` step 5b re-stages it on every recreate, and now also auto-restarts hub Headlamp (`kubectl -n headlamp rollout restart deploy/hub-headlamp deploy/hub-headlamp-embedded`) so the new endpoint/token take effect (Fix 3) — the hub Headlamp only builds its kubeconfig in its init-container at pod start, so a pod predating the recreate keeps serving the stale spoke. Same pattern for dev via `enroll-dev-agent.sh` step 5b. Full detail in `cluster-desired-state/runbooks/recovery-and-gotchas.md`.

## ArgoCD CLI

ArgoCD on the hub is exposed via its own Tailscale ProxyGroup (`argocd-hub.tail286401.ts.net`), which is **independent** of the per-spoke ProxyGroups. So `argocd` works whenever the hub argocd-server is up and Tailscale's funnel ingress for argocd is healthy — even when individual spoke connectivity is broken.

```bash
ADMIN_PASS=$(kubectl --kubeconfig ~/.kube/hub-config -n argocd \
  get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login argocd-hub.tail286401.ts.net --username admin --password "$ADMIN_PASS" --grpc-web
```

Use the CLI when:
- You need to **terminate a stuck operation** (`argocd app terminate-op`) — `kubectl patch app … -p '{"operation":null}'` doesn't always work
- You need `argocd app sync --force` to bypass the "Skipping auto-sync: failed previous attempt" guard
- You want a friendly diff/wait UX (`argocd app wait`, `argocd app diff`)

## Hetzner / Talos

```bash
hcloud context list                    # active: stacks
hcloud server list                      # see all hub/dev/staging nodes + IPs

# Talos config files in ~/.talos/
talosctl --talosconfig ~/.talos/hub-config get members      # hub
talosctl --talosconfig ~/.talos/talos-config get members    # talos-cluster (Hetzner)
```

Spoke clusters do **not** have a ready-made talosconfig file in `~/.talos/`. If you need talosctl on a spoke, generate one from the spoke kubeconfig (or use the kubeconfig fallback above for kubectl-level inspection).

## Container registries

| Registry | URL | Auth | Reachable from |
|---|---|---|---|
| ghcr.io | `ghcr.io/pittampalliorg/<image>` | `ghcr-push-credentials` Secret in `tekton-pipelines` ns on hub (org PAT); local `~/.docker/config.json` for read | Hub Tekton, dev/staging spokes (public reads), local |
| ~~gitea-ryzen~~ (retired post-A6) | n/a | All clusters now pull from ghcr.io; the local Gitea image registry on ryzen no longer exists | n/a |
| ~~gitea-hub / cnoe.localtest.me~~ (retired post-A6) | n/a | Historical; spoke-workloads AppSet still rewrites these to ghcr.io if found | n/a |

**Hub pods reach ryzen kube-api via Tailscale egress.** Pattern: `ryzen-api-egress.tailscale.svc.cluster.local` ExternalName Service points at the operator-rendered headless egress pod for the `ryzen-api-v3.tail286401.ts.net` device. For other hub→ryzen traffic, follow the same `tailscale.com/tailnet-fqdn` egress pattern
- Run the command from ryzen host, where the Tailscale daemon resolves the hostname natively

## GitHub & Azure

- `gh` is authenticated as `vpittamp`. Useful for: webhook delivery history (`gh api repos/PittampalliOrg/workflow-builder/hooks/<id>/deliveries`), OAuth app metadata, PR/run inspection.
- `az` is logged in to the user's Azure tenant. KeyVault: `keyvault-thcmfmoo5oeow`. Common commands:

```bash
az keyvault secret show --vault-name keyvault-thcmfmoo5oeow --name <NAME> --query attributes.updated -o tsv
az keyvault secret set  --vault-name keyvault-thcmfmoo5oeow --name <NAME> --value '<v>' --output none
```

## Tailscale

```bash
tailscale status                       # what the local daemon sees on the tailnet
tailscale status --json | jq '.Self'   # local device's caps (funnel, etc.)

# From inside an operator-managed proxy pod:
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale <pod> -- tailscale status --json | \
  jq '.Self | {Tags, CapMap}'
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale <pod> -- tailscale serve status
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale <pod> -- tailscale funnel status
```

The local daemon doesn't see every device on the tailnet — sharing/ACL rules can hide them. If `tailscale status` doesn't show a device but `kubectl exec` into its operator pod does, the device is alive but not shared with you (or the device's tag dropped its share grant — see orphan-tag runbook).

### ProxyGroup service-host VIPs

Hub browser services such as `argocd-hub`, `nocodb-hub`, and `gitops-inventory-hub` are Tailscale Ingresses served by the `cluster-ingress` ProxyGroup. They are **not** Funnel endpoints. Their readiness depends on the Tailscale `service-host` capability, so four layers must line up:

- The Ingress has `tailscale.com/proxy-group: cluster-ingress` and `tailscale.com/tags: tag:k8s-services`.
- `policy.hujson` has `autoApprovers.services["svc:<hostname>"]` allowing `tag:k8s-services`.
- The Tailscale Service exists as `svc:<hostname>` with the same service tag.
- The `cluster-ingress-*` proxy pods authenticate as `tag:k8s-services` and expose `Self.CapMap["service-host"]` for the service.

Quick check:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n tailscale exec cluster-ingress-0 -- \
  tailscale status --json | jq '.Self | {Tags, serviceHost: .CapMap["service-host"]}'
```

If a ProxyGroup-hosted Ingress has no address, `tailscale cert <host>.tail286401.ts.net` says the domain is invalid, or `curl` to the VIP times out despite a healthy backing Service, use `runbooks/debug-proxygroup-service-host.md`.

Promoted-spoke app URLs such as `phoenix-staging` are normally device-backed Tailscale Ingresses unless they explicitly set `tailscale.com/proxy-group`. They should not have `svc:*` service approvals. If one gets a `-1` suffix or its Ingress address is empty while the device works, use `runbooks/debug-device-backed-tailscale-ingress.md`.

### Workflow-builder web URLs (L4 LoadBalancer + in-cluster TLS)

`workflow-builder` is reached at `https://workflow-builder-{dev,ryzen,staging}.tail286401.ts.net`. As of PR #2319 it is **not** a Tailscale Ingress and uses **no Let's Encrypt**:

- A Tailscale **L4 LoadBalancer Service** (`type: LoadBalancer`, `loadBalancerClass: tailscale`, annotation `tailscale.com/hostname`) puts the device on the tailnet and forwards `443` to the pod's `https-tls` port.
- HTTPS is terminated **in-cluster** by a per-pod nginx `tls-terminator` sidecar serving a persistent self-signed wildcard `*.tail286401.ts.net` (signed by the `tailnet-dev-ca` `ClusterIssuer`, see below).
- Because the CA is stable across cluster recreation, this avoids LE's 5-certs/168h exact-hostname limit (the recreate-churn failure mode the old `ingressClassName: tailscale` + `development-prod-cert` exposure kept hitting).

Manifests: base `packages/base/manifests/tailscale-ingresses/Service-workflow-builder-tailnet.yaml` (dev/staging, CLUSTER-templated, 443→`https-tls`); ryzen `packages/components/workloads/workflow-builder-tailnet-lb/`; sidecar + `ConfigMap-workflow-builder-tls-terminator.yaml` + `Certificate-tailnet-wildcard.yaml` under `packages/components/workloads/workflow-builder/manifests/`. The dev/staging overlays `$patch:delete` the old workflow-builder/mcp-gateway Tailscale Ingresses.

**`mcp-gateway` is no longer on the tailnet** — it is in-cluster only; workflow-builder reaches it at `MCP_GATEWAY_BASE_URL=http://mcp-gateway.workflow-builder.svc.cluster.local:8080`. `ORIGIN`/`APP_PUBLIC_URL` stay `https://workflow-builder-<cluster>.tail286401.ts.net` (ryzen's #2316 plain-HTTP flip was reverted).

**Workstation CA trust.** To open these URLs without a cert warning, the client must trust the self-signed **"PittampalliOrg Tailnet Dev CA"**. nixos-config trusts it (commit `44ba6324`) in `modules/services/cluster-certs.nix` (system/curl/git) AND `home-modules/tools/chromium.nix` (NSS seed of `~/.pki/nssdb` — REQUIRED because `security.pki` does not cover Chrome on NixOS). Otherwise use `curl -k`.

**502 for browsers but 302 for curl (PR #2327):** the `tls-terminator` nginx default 8k proxy header buffer overflows on SvelteKit auth's large `Set-Cookie` headers, so **browsers get 502 while bare `curl` (small headers) returns 302**, masking it. Fix is already in the sidecar ConfigMap (`proxy_buffer_size 32k; proxy_buffers 8 32k; proxy_busy_buffers_size 64k; large_client_header_buffers 4 32k`). Lesson: verify HTTPS app exposure with a real browser (or `curl` with full browser headers), and diagnose via the sidecar nginx error log.

### Workflow-builder deployment inventory paths

The inventory service has two intentional network paths:

| Path | Host | Use |
|---|---|---|
| HTTPS service-host VIP | `https://gitops-inventory-hub.tail286401.ts.net/inventory.json` | Human/browser and direct operator checks |
| Node-backed egress target | `gitops-inventory-hub-node.tail286401.ts.net:8080` via `gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080` | workflow-builder pods on dev/staging/ryzen |

Do not configure Tailscale egress to target the service-host VIP. Cluster egress proxies target tailnet nodes or IPs; `gitops-inventory-hub` is `svc:gitops-inventory-hub`, not a node. If a spoke workflow-builder pod logs `fetch failed`, verify `WORKFLOW_BUILDER_GITOPS_INVENTORY_URL` and the `tailscale.com/tailnet-fqdn` annotation on `Service/gitops-inventory-hub-egress`.
