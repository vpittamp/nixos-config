# Runbook: Reconcile workflow-builder after moving from ryzen to dev/staging

## When to use

Use this when workflow-builder or one of its system services works on ryzen but fails after promotion to dev or staging. Typical symptoms:

- `workflow-builder-dev` loads but backend calls point at ryzen, localhost, or missing hostnames.
- `mcp-gateway-dev.tail286401.ts.net` or `phoenix-dev.tail286401.ts.net` does not resolve, times out, or is not declared.
- The dev/staging Deployment lacks `MCP_GATEWAY_BASE_URL`, `PUBLIC_PHOENIX_URL`, `PHOENIX_BASE_URL`, or `PHOENIX_API_BASE_URL`.
- `kubectl --context dev-api-v2.tail286401.ts.net get nodes` fails even though the Crossplane fallback kubeconfig works.
- A stale ExternalSecret, Service, or registry credential remains from an old ryzen/local-only app shape.

## Mental model

Ryzen proves the local kind shape. Dev and staging are promoted spokes with different public hostnames and API access paths. Do not fix environment drift by patching live Deployments. Declare it in stacks:

| Concern | Declarative owner |
|---|---|
| Runtime URLs for workflow-builder pods | `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` |
| Tailscale Ingresses for app/service hostnames | `packages/base/manifests/tailscale-ingresses/` plus per-spoke overlays |
| Tailscale ACL policy and Kubernetes API grants | `policy.hujson` |
| Hub/root ApplicationSet changes | `origin/main` → `env/hub-next` → `env/hub` through `stacks-environments` |
| Dev/staging rendered workload changes | `origin/main` → `env/spokes-<env>-next` → `env/spokes-<env>` through `workflow-builder-release` |

For app-spec or root-managed changes that also affect ryzen, push `gitea-ryzen/ryzen-main` in addition to `origin/main` and `gitea-ryzen/main`.

## Diagnostic

Start with the rendered desired state before touching the live cluster:

```bash
cd /path/to/stacks/main

kubectl kustomize packages/overlays/dev/tailscale-ingresses | \
  rg 'workflow-builder-dev|mcp-gateway-dev|phoenix-dev'
kubectl kustomize packages/overlays/staging/tailscale-ingresses | \
  rg 'workflow-builder-staging|mcp-gateway-staging|phoenix-staging'

kubectl kustomize packages/overlays/hub | \
  rg 'MCP_GATEWAY_BASE_URL|PUBLIC_PHOENIX_URL|PHOENIX_BASE_URL|PHOENIX_API_BASE_URL'
```

Then compare live state:

```bash
kubectl --context hub-cluster -n argocd get app \
  root-application spoke-dev-workflow-builder dev-workflow-builder dev-tailscale-ingresses \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,OP:.status.operationState.phase,REV:.status.sync.revision

kubectl --context dev-api-v2.tail286401.ts.net -n workflow-builder get deploy workflow-builder \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | \
  rg 'WORKFLOW_BUILDER_ENV|MCP_GATEWAY_BASE_URL|PHOENIX'
```

If `dev-api-v2` is unavailable, use `runbooks/access-spoke-cluster-fallback.md` and shred the extracted kubeconfig when done.

## Fix steps

1. Declare missing runtime URLs in the `spoke-workloads` ApplicationSet patch for workflow-builder. Use cluster-derived hostnames:

```yaml
- name: MCP_GATEWAY_BASE_URL
  value: https://mcp-gateway-{{cluster}}.tail286401.ts.net
- name: PUBLIC_PHOENIX_URL
  value: https://phoenix-{{cluster}}.tail286401.ts.net
- name: PHOENIX_BASE_URL
  value: https://phoenix-{{cluster}}.tail286401.ts.net
- name: PHOENIX_API_BASE_URL
  value: https://phoenix-{{cluster}}.tail286401.ts.net
```

2. Add missing Tailscale Ingresses to `packages/base/manifests/tailscale-ingresses/`. Use the `*-CLUSTER` placeholder plus `stacks.io/hostname-segments` so dev/staging/talos overlays rewrite the hostname. Promoted-spoke app Ingresses are normally device-backed and do not set `tailscale.com/proxy-group`:

```yaml
metadata:
  annotations:
    stacks.io/hostname-segments: "3"
    tailscale.com/hostname: mcp-gateway-CLUSTER
spec:
  tls:
    - hosts:
        - mcp-gateway-CLUSTER
  rules:
    - host: mcp-gateway-CLUSTER
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mcp-gateway
                port:
                  number: 8080
```

3. Add or remove Tailscale ACL entries in `policy.hujson` according to the resource type.

Do **not** add `autoApprovers.services["svc:<hostname>"]` for device-backed app Ingresses such as `workflow-builder-dev`, `workflow-builder-staging`, `mcp-gateway-dev`, `mcp-gateway-staging`, `phoenix-dev`, or `phoenix-staging` unless the manifest explicitly uses a ProxyGroup/service-host model. These hostnames register as Tailscale devices, usually tagged `tag:k8s`.

Only add `autoApprovers.services` entries for real service-host or Tailscale Service resources. For spoke Kubernetes API VIPs, ensure `svc:dev-api-v2` and `svc:staging-api-v2` are approved and `tag:spoke-api` has a Kubernetes impersonation grant to `tag:k8s` with `system:masters`.

If a device-backed hostname was previously declared as `svc:<hostname>`, remove the stale policy entry and delete the stale tailnet Service after confirming no ProxyGroup/device owns it. A stale `svc:<hostname>` can reserve the canonical DNS name and force the live device to register as `<hostname>-1`.

4. Remove orphaned live objects only when they are not owned by a current Argo Application. Prefer declarative deletion by removing the source manifest, but stale resources from an older app name may require one live cleanup:

```bash
KUBECONFIG=/tmp/dev-kubeconfig kubectl -n workflow-builder delete externalsecret \
  gitea-registry-creds-external --ignore-not-found
```

5. Commit and push exact paths:

```bash
git add \
  packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml \
  packages/base/manifests/tailscale-ingresses \
  policy.hujson
git commit -m "fix(workflow-builder): declare dev spoke hostnames"
git push origin HEAD:main
git push gitea-ryzen HEAD:main
git push gitea-ryzen HEAD:ryzen-main   # if app-spec/root-managed changes affect ryzen
```

6. Wait for GitHub checks. `Tailscale ACL GitOps` must succeed before expecting new or re-tagged Tailscale services to work.

7. If hub hydration is stuck on an older dry SHA, use `runbooks/manage-gitops-promoter.md` to clear `root-application.status.sourceHydrator.currentOperation` and `lastSuccessfulOperation`, then hard-refresh. Merge the generated `env/hub-next` → `env/hub` PR only after checking the diff is expected.

8. If a spoke API ProxyGroup still does not work after the ACL has applied, re-authenticate it:

```bash
KUBECONFIG=/tmp/dev-kubeconfig bash deployment/scripts/tailscale/proxygroup-auth.sh --cluster dev
kubectl --context dev-api-v2.tail286401.ts.net get nodes -o name
```

## Verify

```bash
# Hub/root and dev workload apps are converged.
kubectl --context hub-cluster -n argocd get app \
  root-application spoke-dev-workflow-builder dev-workflow-builder dev-tailscale-ingresses \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,OP:.status.operationState.phase,REV:.status.sync.revision

# Runtime env is dev-specific.
kubectl --context dev-api-v2.tail286401.ts.net -n workflow-builder get deploy workflow-builder \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | \
  rg 'WORKFLOW_BUILDER_ENV|MCP_GATEWAY_BASE_URL|PHOENIX'

# Public hostnames and in-cluster service path work.
dig +short workflow-builder-dev.tail286401.ts.net
dig +short workflow-builder-dev-1.tail286401.ts.net  # should be empty
curl -sSI --max-time 10 https://workflow-builder-dev.tail286401.ts.net | head -3
curl -sSI --max-time 10 https://phoenix-dev.tail286401.ts.net | head -3
curl -sSI --max-time 10 https://mcp-gateway-dev.tail286401.ts.net/health | head -3
kubectl --context dev-api-v2.tail286401.ts.net -n workflow-builder run curl-mcp-check \
  --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- \
  curl -sS -I --max-time 10 http://mcp-gateway.workflow-builder.svc.cluster.local:8080/health
```

Expected:
- Argo apps are `Synced` and `Healthy`.
- `WORKFLOW_BUILDER_ENV=dev`.
- MCP and Phoenix URLs are `*-dev.tail286401.ts.net`.
- `mcp-gateway-dev` and in-cluster `mcp-gateway` both return `200`.
- `workflow-builder-release` promotes `env/spokes-dev` first; staging follows after dev `argocd-health` is successful.

## Notes

- Do not copy ryzen URLs into dev/staging values. Use the cluster placeholder so one declaration covers both promoted spokes.
- Do not hand-patch Deployment env values except to prove a hypothesis; live patches will be reverted by ArgoCD and hide the missing declaration.
- Tailscale ACL changes are asynchronous through `.github/workflows/tailscale-acl.yml`. Re-authenticate ProxyGroups only after the policy workflow succeeds.
- `argocd app get --hard-refresh` can trigger an existing operation; if an app reports `operation already in progress`, poll the app before forcing a sync.
