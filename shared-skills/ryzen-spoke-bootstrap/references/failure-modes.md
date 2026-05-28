# Failure modes during ryzen spoke bootstrap

## Kueue CRDs partial-apply during transient hub→ryzen instability

**Symptom**: After cluster recreate, ~14 ryzen-* Deployment-bearing Apps stuck OutOfSync with admission webhook errors like `failed calling webhook "vworkload.kb.io"`. `kubectl get pods -n kueue-system` shows `kueue-controller-manager` CrashLoopBackOff with `no resource matches the kind "Workload"` or similar missing-CRD errors. `kubectl get crds | grep kueue.x-k8s.io | wc -l` returns less than the expected 16.

**Cause**: ArgoCD's ryzen-kueue Application syncs at sync-wave 40 via Helm. If hub→ryzen network is briefly flaky (operator first-contact phase, egress pod reconnecting), Helm's apply may complete some CRDs and fail on others. ArgoCD marks syncResult Failed but doesn't retry the failed CRDs automatically. Controller-manager starts before all CRDs exist, crashes, then auto-sync hits max-retry-backoff before Kueue stabilizes.

**Fix**: `bootstrap-spoke-cluster.sh` step 6c now pre-installs Kueue from upstream release manifest BEFORE any ArgoCD sync (Phase 1 of P1 backlog, 2026-05-28). ArgoCD's later helm sync becomes a no-op via `--server-side --force-conflicts` field-ownership handover. If running an older script:
```bash
KUEUE_VERSION=v0.17.3
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/manifests.yaml" \
  --force-conflicts
kubectl wait --for=condition=Available deployment/kueue-controller-manager \
  -n kueue-system --timeout=3m
```

## Hub egress pod retains stale Tailscale auth after spoke recreate

**Symptom**: After fresh cluster recreate + new Tailscale device registration, `argocd cluster list` keeps showing the spoke as `Unknown` or "Connection refused" for many minutes (51 min observed on 2026-05-28). The hub-side `ts-${CLUSTER_NAME}-api-egress-0` pod is Running but its connection state is stale (still trying old auth).

**Cause**: Tailscale operator's egress pod caches auth state at pod create. The spoke's Tailscale device key rotates on cluster recreate but the hub-side pod doesn't observe Secret changes or device re-registration.

**Fix**: `register-spoke-with-hub.sh` step 6.5 now force-deletes the hub egress pods after CSS Ready (Phase 2 of P1 backlog, 2026-05-28) and waits for the operator to spin a fresh one. Manual recovery:
```bash
kubectl --kubeconfig ~/.kube/hub-config delete pods -n tailscale \
  -l tailscale.com/parent-resource=ryzen-api-egress --grace-period=0 --force
```

## Ryzen-* Applications stuck OutOfSync after Kueue webhook timeout during initial sync

**Symptom**: After CSS Ready and Headlamp restart, many ryzen-* apps remain OutOfSync. Their `operationState.message` references admission webhook timeouts or "webhook not ready". Auto-sync isn't retrying because it hit max-retry-backoff during the initial reconcile window.

**Cause**: ArgoCD's auto-sync exponential backoff caps at ~5 min. If Kueue's webhook took longer than that to become Ready during the initial reconcile window, the backed-off apps don't retry until external operator action or a meaningful event.

**Fix**: `register-spoke-with-hub.sh` step 8.5 now lists ryzen-* Apps via the argocd CLI and force-syncs any OOS/Degraded ones asynchronously (Phase 3 of P1 backlog, 2026-05-28). Manual recovery:
```bash
for app in $(argocd --server argocd-hub.tail286401.ts.net app list --grpc-web --insecure -o name | grep '^argocd/ryzen-'); do
  argocd --server argocd-hub.tail286401.ts.net app sync "$app" --grpc-web --insecure --async
done
```

## talosctl flag drift after Talos version bump (script bug)

**Symptom**: `bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate` destroys the existing cluster, then immediately fails `talosctl cluster create docker` with `unknown flag: --cidr` (or `--memory`, or `--cpus`). The cluster is gone but not recreated — host now has no kube-api.

**Cause**: talosctl v1.13 renamed CLI flags vs older versions:
- `--cidr` → `--subnet`
- `--memory` (control plane) → `--memory-controlplanes`
- `--cpus` (control plane) → `--cpus-controlplanes`

**Fix**: Already committed in stacks `fdc45ff85` (2026-05-28). If the script silently destroyed the cluster on a future talosctl upgrade, re-run after pulling latest, or run `talosctl cluster create docker --help` to find new flag names.

## Tailscale operator chart drift (script bug)

**Symptom**: After helm install, the operator pod is CrashLoopBackOff with `panic: unknown APISERVER_PROXY value "auth"`. `helm list -n tailscale` shows the chart upgraded to a newer version than the script knows about.

**Cause**: tailscale-operator chart v1.98+ renamed `apiServerProxyConfig.mode` values:
- Old: `"auth"` (single value)
- New: `mode: "true"|"false"|"noauth"` PLUS separate `allowImpersonation: "true"|"false"` for the ClusterRole grants

**Fix**: Already committed in stacks `f3c345e1e`. Script now sets both `apiServerProxyConfig.mode=true` and `apiServerProxyConfig.allowImpersonation=true`. If a future chart drops these too, check the live chart's `helm show values tailscale/tailscale-operator | grep -A 15 apiServerProxyConfig`.

## OIDC issuer YAML key in config-patch (script bug)

**Symptom**: `talosctl cluster create docker` errors with `error parsing config patch: unknown keys found during decoding: cluster.serviceAccount.issuerURL`.

**Cause**: `cluster.serviceAccount.issuerURL` is NOT a valid v1alpha1 Talos config key. The correct path is `cluster.apiServer.extraArgs.service-account-issuer`.

**Fix**: Already committed in stacks `1ce550054`. Verifies via reference: https://docs.siderolabs.com/talos/v1.13/reference/configuration/v1alpha1/config/

## `tailscale` + `local-path-storage` namespaces need `pod-security.kubernetes.io/enforce=privileged`

**Symptom**: After Tailscale operator install, when the operator tries to create a kube-api proxy pod (or when local-path-provisioner tries to bind a PVC), the apiserver returns: `would violate PodSecurity "restricted:latest": privileged (containers must not set securityContext.privileged=true)`. Pods never schedule; PVCs stay Pending.

**Cause**: Talos's apiserver defaults to PSA `restricted:latest` enforcement. The Tailscale operator's egress/ingress proxy pods + the local-path provisioner both require privileged + capabilities to bring up network interfaces / manage host paths.

**Fix**: bootstrap-spoke-cluster.sh now labels both namespaces automatically (step 6 in the workflow). If running on an older script:
```bash
kubectl label namespace tailscale pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace local-path-storage pod-security.kubernetes.io/enforce=privileged --overwrite
```

## Hub `ryzen-api-egress` Service doesn't auto-rotate egress pod on annotation change

**Symptom**: After updating `tailscale.com/tailnet-fqdn` annotation on the hub-side `ryzen-api-egress` Service (e.g., to point at a renamed device after recreate), `argocd cluster list` keeps showing connection-refused / i/o timeout. The egress proxy pod (`ts-ryzen-api-egress-*-0`) is still trying to reach the OLD device.

**Cause**: The Tailscale operator reads the `tailnet-fqdn` annotation when creating the StatefulSet pod; subsequent annotation changes don't trigger a pod rotate.

**Fix**: Force the StatefulSet pod to recreate:
```bash
kubectl --kubeconfig ~/.kube/hub-config delete pods -n tailscale \
  -l tailscale.com/parent-resource=ryzen-api-egress --grace-period=0 --force
```
`register-spoke-with-hub.sh` step 6.5 now handles this automatically after CSS Ready (Phase 2 of P1 backlog, 2026-05-28). Same recovery applies if running an older script.

## ESO ClusterSecretStore stays `InvalidProviderConfig` forever

**Symptom**: `kubectl get clustersecretstore azure-keyvault-store -o jsonpath='{.status.conditions}'` keeps showing `reason: InvalidProviderConfig, message: unable to create client`. Events show AADSTS7000272 — "certificate with identifier X used to sign the federated credential could not be found in the metadata of identity provider".

**Cause**: Talos's service-account signing key changed on cluster recreate. Azure AD's federated-identity validation fetches the OIDC issuer's JWKS endpoint (the Azure Storage static website at `oidcissuer65846b7df97b.z13.web.core.windows.net`) — which still serves the OLD cluster's key.

**Fix**:
```bash
bash /home/vpittamp/repos/PittampalliOrg/stacks/main/deployment/scripts/sync-jwks-to-azure.sh
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

## workflow-builder UI not reachable on ryzen (no Ingress)

**Symptom**: `https://workflow-builder-ryzen.tail286401.ts.net/` doesn't resolve. `kubectl get ingress -A` on ryzen shows nothing.

**Cause**: Ryzen has no nginx-ingress-controller; the base `Ingress-workflow-builder.yaml` uses `ingressClassName: nginx`. Post-A6 the ryzen overlay deletes it, but historically the replacement (a Tailscale-class Ingress) wasn't added.

**Fix**: The ryzen overlay's workflow-builder kustomize patches list now includes JSON-6902 ops that mutate the base Ingress in place: replace `ingressClassName` → `tailscale`, replace `host` → `workflow-builder-ryzen`, add `tailscale.com/hostname` annotation + `tailscale.com/proxy-class: development-prod-cert` label, remove nginx-specific annotations. The Tailscale operator then registers a tailnet device named `workflow-builder-ryzen` automatically. (Commit `502bccd3c`.)

Note: `$patch: replace` strategic merge DOES NOT fully replace an Ingress in kustomize — fields end up merged, not replaced. Use JSON-6902 `op: replace` per field instead.

## Headlamp UI: "Failed to get authentication information: ryzen"

**Symptom**: Open `https://headlamp-hub.tail286401.ts.net/` → click the `ryzen` cluster tab → red banner "Failed to get authentication information". Hub Headlamp Pod is otherwise healthy.

**Cause**: Headlamp's `generate-kubeconfig` initContainer reads the `cluster-ryzen` Secret ONCE at pod start and writes a kubeconfig into an emptyDir. If the cluster Secret's bearer token rotates after the pod started (typical after a ryzen recreate), the in-memory kubeconfig still has the old token. The new token in the Secret never reaches the running Headlamp container.

**Fix**:
```bash
kubectl --context hub-cluster rollout restart deploy -n headlamp hub-headlamp hub-headlamp-embedded
```

To make this automatic going forward, consider adding the Reloader annotation (`reloader.stakater.com/auto: "true"`) on the Headlamp Deployments so they restart whenever the `cluster-ryzen` Secret changes.

## Tekton Pipelines/Tasks stuck OutOfSync after ArgoCD 3.4 upgrade

**Symptom**: `hub-workflow-builder-builds` (or any Application managing Tekton resources) shows OutOfSync on multiple Pipeline + Task resources. `argocd app diff` reports zero lines — no visible drift. Health stays Healthy.

**Cause**: Tekton's mutating admission webhook injects empty defaults after every apply: `computeResources: {}`, `metadata: {}`, `spec: null`, `description: ""`. Pre-3.4 ArgoCD's looser comparison didn't surface these. 3.4's stricter SSA-based compare flags them.

**Fix**: extend `ignoreDifferences` on the Application with jq path expressions covering the nested taskSpec paths:
```yaml
ignoreDifferences:
  - group: tekton.dev
    kind: Pipeline
    jqPathExpressions:
      - .spec.results[]?.description
      - .spec.tasks[]?.taskRef.kind
      - .spec.finally[]?.taskRef.kind
      - .spec.tasks[]?.taskSpec.metadata
      - .spec.tasks[]?.taskSpec.spec
      - .spec.tasks[]?.taskSpec.steps[]?.computeResources
      - .spec.tasks[]?.taskSpec.results[]?.description
      - .spec.finally[]?.taskSpec.metadata
      - .spec.finally[]?.taskSpec.spec
      - .spec.finally[]?.taskSpec.steps[]?.computeResources
      - .spec.finally[]?.taskSpec.results[]?.description
  - group: tekton.dev
    kind: Task
    jqPathExpressions:
      - .spec.steps[]?.computeResources
      - .spec.results[]?.description
```

Make sure `syncOptions` includes `RespectIgnoreDifferences=true`. (Commit `003e414ed`.)

## Knative Service rejected by ArgoCD 3.4: `terminationGracePeriodSeconds: field not declared in schema`

**Symptom**: `ryzen-fn-system` (or any Application with a Knative Service) shows sync Failed with: `failed to create typed patch object: .spec.template.spec.terminationGracePeriodSeconds: field not declared in schema`.

**Cause**: Knative's RevisionSpec schema gates `terminationGracePeriodSeconds` behind the `kubernetes.podspec-terminationgraceperiodseconds` feature flag (in `config-features` ConfigMap). Without the flag, the field doesn't exist in the CRD schema. Pre-3.4 ArgoCD silently sent it and Knative silently dropped it. 3.4's stricter typed-patch validation rejects the apply outright.

**Fix**: Either enable the feature flag in `knative-serving/config-features` ConfigMap, or remove the field from the source manifest (and from any `ignoreDifferences` for that field). We chose remove. (Commit `7c3d22e49`.)

## ArgoCD Application stuck on retired PostSync hook (e.g., gitea-ryzen webhook setup)

**Symptom**: `hub-workflow-builder-builds` or `ryzen-workflow-builder` op phase = `Running` indefinitely, message: "waiting for completion of hook batch/Job/<name>". The Job spins in CrashLoopBackOff or sits at "Ensuring repo exists..." forever.

**Cause**: A PostSync hook that calls a now-retired service (e.g., `gitea-http.gitea.svc.cluster.local` or `gitea-ryzen.tail286401.ts.net`). With `BeforeHookCreation` delete-policy, deleting the live Job re-creates it on next attempt, so the wedge survives.

**Fix**: Remove the hook from the source kustomization, NOT just from the cluster. Examples already removed: `workflow-builder-build-webhook-setup` (commit `fb434a340`), `sync-gitea-oauth-app` on ryzen (commit `c9b19aeb6`). Then terminate the wedged op via `kubectl patch app <name> -n argocd --type=json -p='[{"op":"replace","path":"/operation","value":null}]'`.

## ArgoCD Application perpetually OutOfSync with empty `kustomize.images: []`

**Symptom**: A child Application rendered by a parent app-of-apps shows OutOfSync but `argocd app diff` shows only an added `kustomize.images: []` block. SSA never accepts the empty array.

**Cause**: ArgoCD's ServerSideApply strips empty arrays during apply (they don't get propagated to managedFields). The compare engine then re-detects them as "missing" on next reconcile. Perpetual drift.

**Fix**: Remove the empty-array patches from the parent overlay. Per-cluster image-override scaffolding with no actual images serves no purpose. (Commit `b07ca4519`.)

## Two ArgoCD Apps dual-own the same resource (tracking-id flip-flops)

**Symptom**: An OutOfSync resource has tracking-id from App A in the live state but App B's compare engine claims it. `argocd app diff` for App B shows only the tracking-id annotation differing.

**Cause**: Two Application sources both declare a resource with the same kind/name/namespace. Whichever applied last wins the tracking-id; the other App perpetually reports drift.

**Fix**: In the App that should NOT own the resource, add a `$patch: delete` patch in its kustomize.patches. Don't remove the manifest from the shared base — other Apps may still reference it. Example pattern from `packages/components/hub-tekton/apps/workflow-builder-builds.yaml`: cache PVCs are declared in the shared manifest dir but explicitly $patch:delete'd in this Application so only `hub-outer-loop-builds` claims them.

## ArgoCD Application stuck with stale `operationState.phase: Failed`

**Symptom**: Application shows `sync=Synced, health=Healthy, opPhase=Failed`. The "Failed" message references an issue that was already fixed (e.g., the ProxyClass null-spec fix from earlier in the session). No active operation.

**Cause**: ArgoCD's `operationState` is only updated when a new Operation runs. If selfHeal didn't fire (because live already matches desired) and no manual sync was triggered after the fix, the failed state stays in the API even though the underlying issue is resolved.

**Fix**: Trigger a clean sync to overwrite the operationState:
```bash
kubectl --context hub-cluster patch app <name> -n argocd --type=merge \
  -p '{"operation":{"sync":{"syncOptions":["ServerSideApply=true"]}}}'
```
If still stuck (Argo's cached comparison), add `argocd.argoproj.io/refresh=hard` annotation first to bust the repo-server cache.
