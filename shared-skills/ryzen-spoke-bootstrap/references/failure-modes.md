# Failure modes during ryzen spoke bootstrap

## ESO ClusterSecretStore stays `InvalidProviderConfig` forever

**Symptom**: `kubectl get clustersecretstore azure-keyvault-store -o jsonpath='{.status.conditions}'` keeps showing `reason: InvalidProviderConfig, message: unable to create client`. Events show AADSTS7000272 — "certificate with identifier X used to sign the federated credential could not be found in the metadata of identity provider".

**Cause**: Talos's service-account signing key changed on cluster recreate. Azure AD's federated-identity validation fetches the OIDC issuer's JWKS endpoint (the Azure Storage static website at `oidcissuer65846b7df97b.z13.web.core.windows.net`) — which still serves the OLD cluster's key.

**Fix**:
```bash
bash /home/vpittamp/repos/PittampalliOrg/stacks/122-crawl4ai/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh
# Wait 1-15 minutes for Azure AD's metadata cache to invalidate
# Verify the cluster's KID matches the published JWKS:
curl -s https://oidcissuer65846b7df97b.z13.web.core.windows.net/openid/v1/jwks | jq -r '.keys[0].kid'
kubectl get --raw /openid/v1/jwks | jq -r '.keys[0].kid'
# Should match
```

## Hub-side Tailscale egress pod fails with "Tailscale node not found"

**Symptom**: `ts-ryzen-api-egress-*` pod on hub logs `Tailscale node "ryzen-api-v3.tail286401.ts.net." not found; it either does not exist, or not reachable because of ACLs`.

**Causes** (any one):
1. The new ryzen registered under a different hostname (e.g., `ryzen-api-v3-1`) because the stale `ryzen-api-v3` device wasn't deleted before bootstrap.
2. Hub's `ryzen-api-egress` Service annotation `tailscale.com/tailnet-fqdn` points at an old device name (e.g., `ryzen-api-headlamp-6`).
3. ProxyGroup-style exposure creates a Service VIP, not a tailnet device — the operator's egress mechanism only resolves device FQDNs.

**Fixes**:
1. Verify the new device hostname: `tailscale status | grep ryzen-api`. If it has a `-N` suffix, delete it + delete stale devices + delete stale Service VIP via API, then force the operator to re-register cleanly.
2. Patch the hub-side Service annotation:
   ```bash
   kubectl --context hub annotate svc ryzen-api-egress -n tailscale \
     "tailscale.com/tailnet-fqdn=ryzen-api-v3.tail286401.ts.net" --overwrite
   kubectl --context hub delete pod -n tailscale \
     -l tailscale.com/parent-resource=ryzen-api-egress --grace-period=0 --force
   ```
   Then commit the same value to `packages/components/hub-management/apps/headlamp.yaml` so it survives ArgoCD selfHeal.
3. Use the `tailscale.com/expose: "true"` Service pattern instead of ProxyGroup-kube-apiserver — that registers a regular device that the egress can target.

## Hub's argocd-application-controller can't reach kube-api: "connection refused"

**Symptom**: `kubectl --context hub get application spoke-ryzen -n argocd -o jsonpath='{.status.conditions}'` shows `dial tcp 10.244.X.Y:443: connect: connection refused`.

**Cause**: DNS resolved the ExternalName Service to the hub-side egress pod IP, but the pod isn't accepting connections on 443. Either:
- The Service has BOTH `tailscale.com/tailnet-fqdn` AND `tailscale.com/tailnet-ip` annotations (operator rejects duplicate and leaves `externalName: invalid.tailnet.internal`)
- The egress proxy is configured to forward to a Service VIP (which can't be reached without subscription)

**Fix**: Remove the duplicate annotation, then verify externalName points at the headless Service:
```bash
kubectl --context hub patch svc ryzen-api-egress -n tailscale --type=json \
  -p '[{"op":"remove","path":"/metadata/annotations/tailscale.com~1tailnet-ip"}]'
# Wait for operator to reconcile externalName to the actual headless Service
kubectl --context hub get svc ryzen-api-egress -n tailscale -o jsonpath='{.spec.externalName}'
# expected: ts-ryzen-api-egress-XXXX.tailscale.svc.cluster.local
```

## spoke-ryzen sync blocked on "namespaces X not found"

**Symptom**: spoke-ryzen's `operationState.message` says `one or more objects failed to apply, reason: namespaces "gitea" not found, namespaces "workflow-builder" not found`.

**Cause**: spoke-ryzen renders the ryzen overlay AND applies it to **hub** (its destination is `https://kubernetes.default.svc`, app-of-apps pattern). Some resources in the rendered manifest (e.g., Ingresses with namespace=gitea) get applied directly to hub, not to ryzen. Hub doesn't have those namespaces.

**Fixes** (pick one):
- Quick: `kubectl --context hub create ns gitea workflow-builder` to unblock.
- Proper: in the ryzen overlay, either wrap those bare resources in an Application (so they get the destination=ryzen patch) or `$patch: delete` them entirely if they're for ryzen-local services that no longer exist post-A6.

## Pods stuck pulling `gitea.cnoe.localtest.me:8443/giteaadmin/<image>`

**Symptom**: `kubectl get pods -n workflow-builder` shows ImagePullBackOff with `gitea.cnoe.localtest.me:8443/giteaadmin/python:3.12-slim` etc.

**Cause**: The ryzen overlay or individual workload manifests have legacy kustomize `images:` rewrites pointing at the local Gitea pull-through registry (which doesn't exist post-A6).

**Fix**: grep for `newName: gitea.cnoe.localtest.me` in `packages/components/workloads/*/manifests/kustomization.yaml` and replace with `newName: ghcr.io/pittampalliorg/<svc>`. Commit + push + merge Promoter PR.

## ExternalSecrets failing on the gitea ClusterSecretStore

**Symptom**: ExternalSecrets like `workflow-builder-gitea-admin`, `gitea-registry-creds-external` show `STATUS: SecretSyncedError, error: the desired SecretStore gitea is not ready`.

**Cause**: The `gitea` ClusterSecretStore on ryzen expects a local Gitea instance. Post-A6 there's no local Gitea.

**Fix**: Drop these ExternalSecrets from their source kustomizations. If a stub Secret is needed for compatibility, `kubectl create secret generic <name> --from-literal=username=disabled --from-literal=password=disabled`.

## ryzen-* Apps stuck OutOfSync — auto-sync disabled

**Symptom**: Apps like `ryzen-external-secrets`, `ryzen-azure-keyvault-store`, `ryzen-tailscale-operator` show OutOfSync/Healthy and never converge automatically.

**Cause**: An old patch in `packages/components/profiles/local-core-ryzen/kustomization.yaml` removed `/spec/syncPolicy/automated` from these Apps (intended to avoid races with AWI admission webhook during standalone-ryzen bootstrap).

**Fix**: Already removed in commit `a07e038d4` (May 2026). If it reappears, look for `op: remove path: /spec/syncPolicy/automated` patches and delete them.

## Ingresses with class=nginx stuck ADDRESS=<none>

**Symptom**: `kubectl get ingress -n workflow-builder` shows nginx-class Ingresses (`workflow-builder`, `workflow-builder-mcp-gateway`) with empty ADDRESS. Parent Applications stuck Synced/Progressing.

**Cause**: Ryzen has no nginx-ingress-controller — only `tailscale` IngressClass is available. External access on ryzen goes via Tailscale, not nginx.

**Fix**: Add ryzen-overlay kustomize patches that `$patch: delete` the nginx Ingresses for affected Apps. dev/staging still get them (they run nginx-ingress).

## SWE-bench sandbox pods stuck Pending for ~6 min — node labels missing

**Symptom**: `kubectl get pod -n openshell` shows a `swebench-*` pod Pending with `FailedScheduling` events: "0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match Pod's node affinity/selector". Workflow status sits at `workspace_profile` `running` indefinitely. After ~6 min it may timeout entirely.

**Cause**: The Kueue ResourceFlavor `dev-benchmark` (in `packages/components/workloads/kueue-capacity`) selects nodes by BOTH `stacks.io/swebench-pool=dev-benchmark` AND `node-role.kubernetes.io/worker=""`. Pre-A6 KIND ryzen applied these via `kind-config.yaml` kubeadm extraArgs at cluster create. Post-A6 Talos doesn't auto-apply them.

**Fix (one-shot)**:
```bash
kubectl --kubeconfig ~/.kube/config label node \
  $(kubectl get nodes -o name | grep -E 'worker') \
  stacks.io/swebench-pool=dev-benchmark \
  node-role.kubernetes.io/worker= --overwrite
```

**Fix (durable)**: `bootstrap-spoke-cluster.sh` was patched to label worker nodes after kube-api comes up (commit 9871c7217). If you rebuild ryzen with an older script, re-apply the labels manually.

## SWE-bench launch paused with "argocd_application_not_stable"

**Symptom**: SWE-bench UI shows `SWE-bench launch is paused while workflow-builder control plane stabilizes: argocd_application_not_stable` and no workflow starts.

**Cause**: The ryzen overlay's workflow-builder Deployment patch was setting `BENCHMARK_ARGOCD_APPLICATION_NAME=workflow-builder` + `BENCHMARK_ARGOCD_KUBECONFIG_MODE=in-cluster` (pre-A6 these pointed at ryzen's local ArgoCD). Post-A6 there is no local ArgoCD on ryzen, so the in-cluster lookup hits the empty `argocd` namespace and fails.

**Fix**: Removed in commit `bda45c3a5`. If it reappears, ensure neither env var is set on the workflow-builder Deployment on ryzen — dev/staging leave them unset so the launch-stability check short-circuits to `stable: true`.
