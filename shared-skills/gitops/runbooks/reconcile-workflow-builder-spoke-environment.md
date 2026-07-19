# Reconcile the dev workflow-builder environment

## When to use

Use this when workflow-builder or one of its system services is wrong on the
active dev target. Compare against another target only when the user explicitly
requested that comparison. Staging configuration is retained but the cluster is
currently dormant. Typical symptoms:

- `workflow-builder-dev` loads but backend calls point at ryzen, localhost, or missing hostnames.
- `phoenix-dev.tail286401.ts.net` does not resolve, times out, or is not declared.
- `https://workflow-builder-dev.tail286401.ts.net` is unreachable, or returns 502 in a browser while `curl` returns 302 (see the tls-terminator buffer gotcha in Notes).
- The dev Deployment lacks `MCP_GATEWAY_BASE_URL`, `PUBLIC_PHOENIX_URL`, `PHOENIX_BASE_URL`, or `PHOENIX_API_BASE_URL`.
- `kubectl --context admin@dev get nodes` fails while `/tmp/talos-spoke-dev/kubeconfig` still works.
- A stale ExternalSecret, Service, or registry credential remains from an old ryzen/local-only app shape.

## Mental model

Dev is a managed argocd-agent spoke. Do not fix environment drift by patching
live Deployments; declare it in stacks. Ryzen has a separate autonomous lane
and staging is dormant, so neither is a default validation prerequisite.

| Concern | Declarative owner |
|---|---|
| Runtime URLs for workflow-builder pods | `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` |
| Tailnet app/service exposures (device-backed Ingresses like `phoenix-*`, plus the workflow-builder L4 LoadBalancer Service) | `packages/base/manifests/tailscale-ingresses/` plus per-spoke overlays |
| Tailscale ACL policy and Kubernetes API grants | `policy.hujson` |
| Hub/root ApplicationSet changes | `origin/main` → `env/hub-next` → `env/hub` through `stacks-environments` |
| Dev rendered workload changes | `origin/main` -> `env/spokes-dev-next` -> `env/spokes-dev` through `workflow-builder-release` |

For app-spec or root-managed changes, push to GitHub `main`. Dev reconciles via
hub Source Hydrator, auto-merging Promoter, and the managed dev agent. Other
cluster lanes are opt-in.

## Diagnostic

Start with the rendered desired state before touching the live cluster:

```bash
cd /path/to/stacks/main

kubectl kustomize packages/overlays/dev/tailscale-ingresses | \
  rg 'workflow-builder-dev|phoenix-dev'
# workflow-builder is an L4 LoadBalancer Service (not an Ingress); mcp-gateway is no longer on the tailnet.

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

1. Declare missing runtime URLs in the `spoke-workloads` ApplicationSet patch for workflow-builder. Use cluster-derived hostnames for tailnet-exposed services, and the in-cluster Service DNS for `mcp-gateway` (dropped from the tailnet in PR #2319):

```yaml
- name: MCP_GATEWAY_BASE_URL
  value: http://mcp-gateway.workflow-builder.svc.cluster.local:8080
- name: PUBLIC_PHOENIX_URL
  value: https://phoenix-{{cluster}}.tail286401.ts.net
- name: PHOENIX_BASE_URL
  value: https://phoenix-{{cluster}}.tail286401.ts.net
- name: PHOENIX_API_BASE_URL
  value: https://phoenix-{{cluster}}.tail286401.ts.net
```

`ORIGIN` and `APP_PUBLIC_URL` stay `https://workflow-builder-{{cluster}}.tail286401.ts.net` (ryzen's #2316 plain-HTTP flip was reverted).

2. Add missing tailnet exposures to `packages/base/manifests/tailscale-ingresses/`. Use the `*-CLUSTER` placeholder plus `stacks.io/hostname-segments` so dev/staging/talos overlays rewrite the hostname.

   - **workflow-builder** is an L4 **LoadBalancer Service** + in-cluster `tls-terminator` sidecar (PR #2319), declared in `Service-workflow-builder-tailnet.yaml` (443→`https-tls`, NO Let's Encrypt). The dev/staging overlays `$patch:delete` the old workflow-builder/mcp-gateway Tailscale Ingresses — do not re-add them.
   - **Remaining device-backed Ingresses** (e.g. `phoenix-*`) do not set `tailscale.com/proxy-group`:

```yaml
metadata:
  annotations:
    stacks.io/hostname-segments: "3"
    tailscale.com/hostname: phoenix-CLUSTER
spec:
  ingressClassName: tailscale
  tls:
    - hosts:
        - phoenix-CLUSTER
  rules:
    - host: phoenix-CLUSTER
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: phoenix
                port:
                  number: 6006
```

3. Add or remove Tailscale ACL entries in `policy.hujson` according to the resource type.

Do **not** add `autoApprovers.services["svc:<hostname>"]` for device-backed app Ingresses such as `phoenix-dev` or `phoenix-staging` unless the manifest explicitly uses a ProxyGroup/service-host model. These hostnames register as Tailscale devices, usually tagged `tag:k8s`. (`workflow-builder-{dev,staging}` is an L4 LoadBalancer Service that also registers as a `tag:k8s` device, not a `svc:*` service — same rule applies; `mcp-gateway` is in-cluster only and needs no ACL.)

Only add `autoApprovers.services` entries for real service-host or Tailscale Service resources. For spoke Kubernetes API VIPs, ensure `svc:dev-api-v2` and `svc:staging-api-v2` are approved and `tag:spoke-api` has a Kubernetes impersonation grant to `tag:k8s` with `system:masters`.

If a device-backed hostname was previously declared as `svc:<hostname>`, remove the stale policy entry and delete the stale tailnet Service after confirming no ProxyGroup/device owns it. A stale `svc:<hostname>` can reserve the canonical DNS name and force the live device to register as `<hostname>-1`.

4. Remove orphaned live objects only when they are not owned by a current Argo Application. Prefer declarative deletion by removing the source manifest, but stale resources from an older app name may require one live cleanup:

```bash
KUBECONFIG=/tmp/dev-kubeconfig kubectl -n workflow-builder delete ingress \
  mcp-gateway-tailscale --ignore-not-found   # retired in PR #2319; mcp-gateway is in-cluster only now
```

Do **not** re-create a `gitea-registry-creds` imagePullSecret. PR #2317 removed it fleet-wide (23 manifests + 2 SAs) because the secret was never produced on any cluster; it was a dead reference. All images pull from `ghcr.io/pittampalliorg/*` via `ghcr-pull-credentials`. (`deployment/scripts/trigger-tekton-builds.sh` keeps a same-named build-side PUSH credential — that is different and intentionally retained.)

5. Commit and push exact paths:

```bash
git add \
  packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml \
  packages/base/manifests/tailscale-ingresses \
  policy.hujson
git commit -m "fix(workflow-builder): declare dev spoke hostnames"
git push origin HEAD:main
```

6. Wait for GitHub checks. `Tailscale ACL GitOps` must succeed before expecting new or re-tagged Tailscale services to work.

7. If hub hydration is stuck on an older dry SHA, use `runbooks/manage-gitops-promoter.md` to clear `root-application.status.sourceHydrator.currentOperation` and `lastSuccessfulOperation`, then hard-refresh. `stacks-environments` auto-merges `env/hub-next` to `env/hub`; do not wait for a second manual PR.

8. If a spoke API ProxyGroup still does not work after the ACL has applied, re-authenticate it:

```bash
KUBECONFIG=/tmp/talos-spoke-dev/kubeconfig bash deployment/scripts/tailscale/proxygroup-auth.sh --cluster dev
kubectl --context admin@dev get nodes -o name
```

## Verify

```bash
# Hub/root and dev workload apps are converged.
kubectl --context hub-cluster -n argocd get app \
  root-application spoke-dev-workflow-builder \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,OP:.status.operationState.phase,REV:.status.sync.revision
kubectl --context hub-cluster -n dev get app \
  dev-workflow-builder dev-tailscale-ingresses \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision

# Runtime env is dev-specific.
kubectl --context admin@dev -n workflow-builder get deploy workflow-builder \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | \
  rg 'WORKFLOW_BUILDER_ENV|MCP_GATEWAY_BASE_URL|PHOENIX'

# Public hostnames and in-cluster service path work.
dig +short workflow-builder-dev.tail286401.ts.net
dig +short workflow-builder-dev-1.tail286401.ts.net  # should be empty
# Use -k unless the workstation trusts the Tailnet Dev CA (nixos-config 44ba6324).
curl -k -sSI --max-time 10 https://workflow-builder-dev.tail286401.ts.net | head -3
curl -k -sSI --max-time 10 https://phoenix-dev.tail286401.ts.net | head -3
kubectl --context admin@dev -n workflow-builder run curl-mcp-check \
  --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- \
  curl -sS -I --max-time 10 http://mcp-gateway.workflow-builder.svc.cluster.local:8080/health
```

Expected:
- Argo apps are `Synced` and `Healthy`.
- `WORKFLOW_BUILDER_ENV=dev`.
- `MCP_GATEWAY_BASE_URL` is the in-cluster `http://mcp-gateway...:8080`; Phoenix URLs are `*-dev.tail286401.ts.net`.
- `workflow-builder-dev` returns `200` in a browser (not just `curl`) and in-cluster `mcp-gateway` returns `200`.
- `workflow-builder-release` promotes the dev render to `env/spokes-dev` after its health/timer gates pass.

## Notes

- Do not copy another target's URLs into dev values. Keep cluster placeholders where the retained multi-environment manifest contract requires them.
- Do not hand-patch Deployment env values except to prove a hypothesis; live patches will be reverted by ArgoCD and hide the missing declaration.
- Tailscale ACL changes are asynchronous through `.github/workflows/tailscale-acl.yml`. Re-authenticate ProxyGroups only after the policy workflow succeeds.
- `argocd app get --hard-refresh` can trigger an existing operation; if an app reports `operation already in progress`, poll the app before forcing a sync.
- **`workflow-builder-<cluster>` 502 for browsers, 302 for curl (PR #2327).** The `tls-terminator` nginx default 8k proxy header buffer overflows on SvelteKit auth's large `Set-Cookie` headers, so browsers get 502 while bare `curl` (small headers) returns 302 — masking it. Fix lives in the sidecar `ConfigMap-workflow-builder-tls-terminator.yaml` (`proxy_buffer_size 32k; proxy_buffers 8 32k; proxy_busy_buffers_size 64k; large_client_header_buffers 4 32k`). Always verify HTTPS exposure with a real browser (or `curl` with full browser headers), and diagnose via the sidecar nginx error log.
