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
| gitea-ryzen | `gitea-ryzen.tail286401.ts.net/giteaadmin/<image>` | Anonymous reads OK; pushes need `gitea-registry-credentials` Secret | Ryzen, hub via Tailscale **egress** service, local ryzen workstation |
| gitea-hub / cnoe.localtest.me | `gitea-hub.tail286401.ts.net/giteaadmin/<image>` and `gitea.cnoe.localtest.me/giteaadmin/<image>` | Same as gitea-ryzen | Mostly historical/local-dev; spoke-workloads AppSet rewrites these to ghcr.io |

**Hub pods cannot resolve `gitea-ryzen.tail286401.ts.net` through cluster DNS.** Two workarounds:
- Use the Tailscale **egress** Service `gitea-ryzen-egress.tailscale.svc.cluster.local` and add an `/etc/hosts` mapping at runtime (the gitea-build Tasks demonstrate this pattern)
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

Promoted-spoke app URLs such as `workflow-builder-staging`, `mcp-gateway-staging`, and `phoenix-staging` are normally device-backed Tailscale Ingresses unless they explicitly set `tailscale.com/proxy-group`. They should not have `svc:*` service approvals. If one gets a `-1` suffix or its Ingress address is empty while the device works, use `runbooks/debug-device-backed-tailscale-ingress.md`.

### Workflow-builder deployment inventory paths

The inventory service has two intentional network paths:

| Path | Host | Use |
|---|---|---|
| HTTPS service-host VIP | `https://gitops-inventory-hub.tail286401.ts.net/inventory.json` | Human/browser and direct operator checks |
| Node-backed egress target | `gitops-inventory-hub-node.tail286401.ts.net:8080` via `gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080` | workflow-builder pods on dev/staging/ryzen |

Do not configure Tailscale egress to target the service-host VIP. Cluster egress proxies target tailnet nodes or IPs; `gitops-inventory-hub` is `svc:gitops-inventory-hub`, not a node. If a spoke workflow-builder pod logs `fetch failed`, verify `WORKFLOW_BUILDER_GITOPS_INVENTORY_URL` and the `tailscale.com/tailnet-fqdn` annotation on `Service/gitops-inventory-hub-egress`.
