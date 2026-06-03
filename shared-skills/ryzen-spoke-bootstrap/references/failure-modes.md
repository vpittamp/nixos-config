# Failure modes during ryzen spoke bootstrap

## Tailscale ACL pattern: APISERVER_PROXY hardcoded false in source manifest

**Symptom**: Cluster Secret with `bearerToken: "unused"` (per Tailscale ACL guide) gets "the server has asked for the client to provide credentials" when ArgoCD's application-controller tries to use it. Curl to `https://<spoke-operator>.tail286401.ts.net:443` returns "Connection refused".

**Cause**: Although `bootstrap-spoke-cluster.sh` passes `apiServerProxyConfig.mode=true` to the Tailscale operator helm chart, ArgoCD's reconcile of `packages/components/tailscale-serve/manifests/tailscale-operator/Deployment-operator.yaml` overwrites it with `APISERVER_PROXY: "false"` shortly after. The operator pod restarts without the API server proxy running, so port 443 on the operator's tailnet device returns Connection Refused, and the Tailscale ACL impersonation flow has no proxy to honor it.

**Fix**: Already committed in stacks `83ce11f0f` (2026-05-28). Source `Deployment-operator.yaml` now has `APISERVER_PROXY: "true"`. Operators upgrading an existing cluster need ArgoCD to sync `ryzen-tailscale-operator` Application AND must NOT block on Kueue webhook (see next mode); during the validation we had to direct-patch the live Deployment to break a chicken-and-egg deadlock — `kubectl --context admin@ryzen patch deployment operator -n tailscale ...` with the desired env block.

## Tailscale ACL pattern: TLS SNI mismatch — server URL must be the operator FQDN + HUB CoreDNS rewrite (NOT tlsClientConfig.serverName)

**Symptom**: After enabling APISERVER_PROXY=true and adding the ACL grant, ArgoCD's cluster-list shows the spoke as Failed with `tls: internal error`. Operator pod logs show `TLS handshake error from <hub-egress-IP>:NNNN: 500 Internal Server Error: invalid domain "ryzen-api-egress.tailscale.svc.cluster.local"; must be one of ["ryzen-operator.tail286401.ts.net"]`.

**Cause**: The spoke operator's apiserver-proxy (v1.92.4+) STRICTLY validates the wire TLS SNI against its own tailnet hostname (`ryzen-operator.tail286401.ts.net`). If the cluster Secret's `server` field is the in-cluster ExternalName (`ryzen-api-egress.tailscale.svc.cluster.local`), ArgoCD sends that as the wire SNI and the proxy rejects it.

**Fix (CURRENT, verified 2026-05-29)**: ArgoCD does NOT apply `tlsClientConfig.serverName` as the wire SNI — setting `serverName` (even with `caData`) still sent the *server-URL host* as the SNI. So the SNI must come from the server-URL host itself. The static `cluster-ryzen` Secret therefore sets:

```yaml
stringData:
  server: https://ryzen-operator.tail286401.ts.net   # <- this host becomes the wire SNI
  config: |
    { "tlsClientConfig": { "insecure": true, "serverName": "ryzen-operator.tail286401.ts.net" }, "bearerToken": "unused" }
```

and a HUB CoreDNS rewrite routes that tailnet name to the in-cluster egress so the SNI stays correct while the connection reaches the egress pod:

```
rewrite name exact ryzen-operator.tail286401.ts.net ryzen-api-egress.tailscale.svc.cluster.local
```

The `ryzen-api-egress` ExternalName Service (ns `tailscale` on the hub, `tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net`) is defined inline in `packages/components/hub-management/apps/headlamp.yaml`. Verify with `curl --connect-to` forcing the `ryzen-operator` SNI → expect HTTP 200. Pattern generalizes to any Tailscale-apiserver-proxy spoke: `server = https://<spoke>-operator.tail286401.ts.net` + a HUB CoreDNS rewrite `<spoke>-operator.tail286401.ts.net → <spoke>-api-egress.tailscale.svc.cluster.local`. (The earlier `42ddb16cd` `tlsClientConfig.serverName`-only fix was superseded; `serverName` is kept in the config but is not what carries the SNI.)

## Stale duplicate `<spoke>-operator` tailnet device after recreate

**Symptom**: After a recreate, hub→spoke ArgoCD sync keeps failing SNI validation or the egress can't reach the proxy; `tailscale status` shows TWO `ryzen-operator` entries (one offline/stale), and the new operator may have registered under `ryzen-operator-1`.

**Cause**: A recreate leaves the previous cluster's `ryzen-operator` device on the tailnet. Tailscale's name-collision avoidance forces the new operator to a `-1` suffix, so the canonical `ryzen-operator.tail286401.ts.net` that the cluster Secret + CoreDNS rewrite target no longer points at the live cluster.

**Fix**: Delete the stale device via the TS API (token minted from the operator-oauth Secret) BEFORE/at recreate so the new operator claims the canonical hostname. `cleanup-tailnet-devices.sh` (invoked by `--recreate`) covers this; match `^ryzen-operator($|-)` in addition to `ryzen-api-*`. Then verify SNI:
```bash
curl -sk --connect-to ryzen-operator.tail286401.ts.net:443:<egress-or-tailnet-ip>:443 \
  https://ryzen-operator.tail286401.ts.net/version  # expect HTTP 200
```

## Tailscale ACL pattern: tag mismatch between hub egress and spoke operator (need explicit ACL grant)

**Symptom**: After APISERVER_PROXY=true and Secret with serverName, the proxy log shows the connection arrives but no impersonation header is injected — kube-apiserver rejects with auth required.

**Cause**: ACL impersonation matches `src tag → dst tag`. Hub-side Tailscale egress pods carry `tag:k8s` (from operator's `PROXY_TAGS`), but the spoke operator pod carries `tag:k8s-operator` (from `OPERATOR_INITIAL_TAGS`). The existing `policy.hujson` grants `tag:k8s-operator → tag:k8s-operator` and `tag:spoke-api → tag:k8s` but NOT `tag:k8s → tag:k8s-operator`. The hub-to-spoke-operator path is uncovered.

**Fix**: Already committed in stacks `83ce11f0f` (2026-05-28). New grant added to `policy.hujson`:
```hujson
{
  "src": ["tag:k8s"],
  "dst": ["tag:k8s-operator"],
  "app": {
    "tailscale.com/cap/kubernetes": [
      { "impersonate": { "groups": ["system:masters"] } }
    ]
  }
}
```
The `.github/workflows/tailscale-acl.yml` GitHub Action applies it to the tailnet on push to main.

## Kueue label mismatch — kueue-webhook-service has zero endpoints

**Symptom**: Any Deployment update (including the Tailscale operator's APISERVER_PROXY=true sync) fails admission with `failed calling webhook "mdeployment.kb.io": ... connect: connection refused`. `kubectl get endpoints kueue-webhook-service -n kueue-system` shows `ENDPOINTS: <none>`.

**Cause**: The upstream Kueue release manifest's `kueue-controller-manager` Deployment template carries labels `app.kubernetes.io/name=kueue, control-plane=controller-manager` — but the helm-rendered `kueue-webhook-service`'s selector ALSO requires `app.kubernetes.io/instance=kueue`. The Service selector doesn't match the pod, so endpoints stay empty and every admission webhook call timeouts.

**Fix**: Already committed in stacks `a9da1d030` (2026-05-28). `bootstrap-spoke-cluster.sh` step 6c now patches the Deployment template to add the missing `app.kubernetes.io/instance=kueue` label immediately after applying the release manifest. Manual recovery for an existing cluster:
```bash
kubectl --context admin@<cluster> patch deployment kueue-controller-manager -n kueue-system \
  -p '{"spec":{"template":{"metadata":{"labels":{"app.kubernetes.io/instance":"kueue"}}}}}'
```

## Kueue rollout race — webhook port not ready when wait Available returns

**Symptom**: After the label patch in `bootstrap-spoke-cluster.sh` step 6c, the script proceeds to step 7 (spoke-registration kustomize apply) and fails immediately with the same webhook timeout (`mjob.kb.io`: connection refused) — even though `kubectl wait --for=condition=Available` returned success.

**Cause**: `kubectl wait Available` checks the Deployment-level Available condition, which requires `availableReplicas >= minAvailable`. During a Recreate-strategy rollout triggered by the label patch, the OLD pod is briefly Available right after the patch is applied — the wait returns immediately on that pod, even though it's already being terminated. The NEW pod's webhook port (:9443) hasn't started accepting connections yet.

**Fix**: Already committed in stacks `85ed6fbca` (2026-05-28). Bootstrap now uses `kubectl rollout status` (waits for new replicaset to fully roll over) followed by an explicit poll of `kubectl get endpoints kueue-webhook-service -n kueue-system` until at least one address populates. Replaces the bare `kubectl wait Available`.

## bootstrap-spoke-cluster.sh STACKS_DIR resolves to wrong repo when run from another cwd

**Symptom**: `bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate` destroys the cluster, runs helms successfully, then fails at step 7: `error: must build at directory: not a valid directory: evalsymlink failure on '/home/vpittamp/repos/vpittamp/nixos-config/main/packages/overlays/ryzen-spoke-registration' : lstat ... : no such file or directory`. The script's exit code may still come back 0 because the calling shell piped to tee without pipefail, masking the actual non-zero exit.

**Cause**: The previous `STACKS_DIR="${STACKS_DIR:-$(git rev-parse --show-toplevel)}"` derived STACKS_DIR from the operator's current working directory, not from the script's location. Running from any other repo (e.g., from `~/repos/vpittamp/nixos-config/main` after committing skill docs there) pointed STACKS_DIR at the wrong tree.

**Fix**: Already committed in stacks `d98d6d7a7` (2026-05-28). STACKS_DIR is now derived from SCRIPT_DIR (`$SCRIPT_DIR/../..`), location-independent. Operators with a real need to override can still set STACKS_DIR explicitly in env.

> **SUPERSEDED for ryzen (kept for the bearer-token / dev-staging context).** The three modes below — JWKS storage-account pollution, the `register-spoke-with-hub.sh` CSS→ArgoCD circular deadlock, and "ESO ClusterSecretStore stays InvalidProviderConfig" — all assume the spoke runs `azure-keyvault-store` resolved via Azure Workload Identity. **Ryzen no longer does**: the spoke has no Azure (verified live: `azure-workload-identity-system` empty, no `azure-keyvault-store` CSS), reads secrets via `hub-secrets-store` over Tailscale, and `--ts-acl-mode` skips the KV-token round-trip + JWKS sync entirely. For ryzen failures see "ESO hub-secrets-store" and "Tailscale ACL pattern" modes instead. JWKS sync still matters only for the HUB's own AWI.

## sync-jwks-to-azure.sh uploads to wrong storage account due to polluted shell env

**Symptom**: `register-spoke-with-hub.sh` step 5 (JWKS sync) prints `Storage Account: oidcissuerryzen` then fails to upload with `Failed to resolve 'oidcissuerryzen.blob.core.windows.net' ([Errno -2] Name or service not known)`. The Talos cluster's actual issuer is `oidcissuer65846b7df97b` — the shell's `AZURE_STORAGE_ACCOUNT=oidcissuerryzen` overrode the script's default.

**Cause**: Operator previously sourced `.env-files/kind.env` (legacy KIND setup) in their shell. That file exports `AZURE_STORAGE_ACCOUNT`, `SERVICE_ACCOUNT_ISSUER`, and `RESOURCE_GROUP` with KIND-era values. `sync-jwks-to-azure.sh` respects them via `${VAR:-default}`, so the legacy values take precedence and JWKS gets uploaded to a non-existent storage account. ESO then stays InvalidProviderConfig indefinitely.

**Fix**: Already committed in stacks `0d2f5a9bf` (2026-05-28). `register-spoke-with-hub.sh` now wraps the invocation with `env -u AZURE_STORAGE_ACCOUNT -u SERVICE_ACCOUNT_ISSUER -u RESOURCE_GROUP` so the sync script's hardcoded Talos defaults always take effect. To genuinely override (e.g., for a non-prod test issuer), set the vars *immediately before* calling register-spoke-with-hub.sh; sourcing kind.env earlier in the session no longer leaks through.

## register-spoke-with-hub.sh circular deadlock: CSS poll → ArgoCD App → hub→spoke kube-api → egress pod

**Symptom**: `register-spoke-with-hub.sh` step 6 CSS Ready poll runs for 30 min then times out. The log shows repeating `status=Error from server (NotFound): clustersecretstores.external-secrets.io "azure-keyvault-store" not found`. Meanwhile `argocd cluster list` shows the spoke as Failed with `dial tcp ... i/o timeout` or `lookup ... no such host`.

**Cause**: The spoke's `azure-keyvault-store` CSS is itself synced from hub by ArgoCD (via the `ryzen-azure-keyvault-store` Application). Hub can't sync that App until hub→spoke kube-api works. Hub→spoke depends on a fresh hub-side `ts-ryzen-api-egress-*-0` Tailscale egress pod (the previous spoke's auth state is stale after recreate). Previous step ordering — step 6 (CSS poll) followed by step 6.5 (egress restart) — created a circular wait: CSS would never appear because step 6.5 to enable the App sync hadn't run yet.

**Fix**: Already committed in stacks `f74becf81` (2026-05-28). Step ordering changed: egress restart is now step **5.5** (between JWKS sync and CSS poll). With hub→spoke connectivity restored before the poll begins, the CSS appears within ~30s of the egress pod becoming Ready and the AAD federated-cred cache invalidating (~10 min typical).

## Force-deleting hub egress pod leaves Tailscale state Secret malformed (CrashLoopBackOff)

**Symptom**: After `register-spoke-with-hub.sh` step 5.5 force-deletes the hub-side egress pod (`ts-ryzen-api-egress-zwnbx-0`), the StatefulSet recreates it but the new pod CrashLoopBackOffs with: `boot: 2026/... invalid state: tailscaled daemon started with a config file, but tailscale is not logged in: ensure you pass a valid auth key in the config file.` Hub→spoke kube-api stays broken.

**Cause**: The Tailscale operator stores the egress pod's tailscaled state in a per-pod Secret named after the pod (`TS_KUBE_SECRET=$POD_NAME`). When the pod is force-deleted but the Secret is left in place, the new pod boots reading the existing Secret — which references a stale machineAuthorization that's no longer valid. The pod can't re-register because the auth-key is missing (the original was consumed on first registration; the operator only generates fresh auth-keys when the Secret is absent).

**Fix**: Already committed in stacks `78a4c6979` (2026-05-28). Step 5.5 now deletes both the per-pod Secret (`kubectl delete secret <pod-name>`) AND the pod, in that order. The operator's reconciler then provisions a fresh OAuth-based auth-key into a new Secret before the new pod boots. Manual recovery if the script ran an older version:
```bash
POD=ts-ryzen-api-egress-zwnbx-0  # from kubectl get pods -n tailscale | grep ryzen-api-egress
kubectl --kubeconfig ~/.kube/hub-config -n tailscale delete secret "$POD" --ignore-not-found
kubectl --kubeconfig ~/.kube/hub-config -n tailscale delete pod "$POD" --grace-period=0 --force
```

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

## bootstrap-spoke-cluster.sh `TS_OPERATOR_CHART_VERSION` unbound-variable abort (PR #2395)

**Symptom**: `bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate` destroys the cluster, installs external-secrets, then ABORTS at the `tailscale-operator` helm install with `TS_OPERATOR_CHART_VERSION: unbound variable` (under `set -u`). Because the abort lands AFTER destroy already ran, ryzen is left DOWN with no kube-api.

**Cause**: `bootstrap-spoke-cluster.sh` is STANDALONE — it does NOT source `deployment/scripts/lib/common.sh`, which is where the Tailscale-operator chart pin (`1.96.5`) lives. So `${TS_OPERATOR_CHART_VERSION}` was unbound under `set -u` and the recreate aborted at the helm install (right after external-secrets).

**Fix**: Already committed in stacks `a395874dc` (PR #2395). The script now self-defaults the pin next to the other version pins (~line 125):
```bash
TS_OPERATOR_CHART_VERSION="${TS_OPERATOR_CHART_VERSION:-1.96.5}"
```
**INVARIANT**: keep this in lockstep with `lib/common.sh` + the GitOps `tailscale-operator` manifests; any variable this standalone script shares with `common.sh` MUST be self-defaulted (the script never sources `common.sh`). Full detail: `shared-skills/cluster-desired-state/runbooks/recovery-and-gotchas.md`.

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

## (SUPERSEDED for ryzen) ESO `azure-keyvault-store` stays `InvalidProviderConfig` forever

> **Ryzen does not run `azure-keyvault-store` anymore** — this is retained for the dev/staging bearer-token + AWI context only. For ryzen secret-transport failures use the "ESO hub-secrets-store" mode below.

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

## ESO `hub-secrets-store` NotReady / ExternalSecrets SecretSyncedError on ryzen (the CURRENT transport)

**Symptom**: `kubectl --context admin@ryzen get clustersecretstore hub-secrets-store` shows Ready=False, or workload ExternalSecrets show `SecretSyncedError`. Common messages: TLS / x509 verification failure against the hub Ingress cert, `dial tcp ... i/o timeout` / `no such host`, or `selfsubjectrulesreviews` forbidden.

**Cause** (one of):
1. **caBundle mismatch** — ESO (now v2.4.1) still REQUIRES `caBundle` on the store; it must be the **ISRG Root X1** root (the LE cert on the hub `k8s-api-hub-ingress` device chains to it). A missing/wrong caBundle → x509 failure. (Hard-set in `packages/components/spoke-tailscale-secrets/manifests/spoke-transport/ClusterSecretStore-hub-secrets-store.yaml`.)
2. **RYZEN CoreDNS rewrite missing** — Talos resets the Corefile every recreate, so `rewrite name exact k8s-api-hub-ingress.tail286401.ts.net k8s-api-hub-egress.tailscale.svc.cluster.local` (inserted by `spoke-transport-bootstrap.sh`) is gone → SNI/host mismatch or no-route. The store host must be `k8s-api-hub-ingress.tail286401.ts.net` (the standalone hub Tailscale **Ingress DEVICE**, NOT the k8s-api-hub ProxyGroup VIP — the VIP route never propagates into a spoke egress netmap).
3. **`hub-secrets-token` Secret absent** — the scoped hub SA token must live at `external-secrets/hub-secrets-token` (key `token`) on the spoke; re-minted by `spoke-transport-bootstrap.sh`.
4. **ACL grant missing** — `policy.hujson` needs `tag:k8s → tag:k8s` impersonate group `tailscale:spoke-secrets-reader` (the ryzen→hub read path), plus the hub-side RBAC (`spoke-secrets-reader` SA/Group: get/list/watch secrets in `spoke-secrets` + cluster-wide create on `selfsubjectrulesreviews` for ESO store validation).

**Fix**:
```bash
# Re-run the imperative transport bootstrap (idempotent)
bash deployment/scripts/lib/spoke-transport-bootstrap.sh --apply-manifests deployment/manifests/spoke-transport/
# Verify the pieces
kubectl --context admin@ryzen -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep k8s-api-hub-ingress
kubectl --context admin@ryzen -n external-secrets get secret hub-secrets-token
kubectl --context admin@ryzen get clustersecretstore hub-secrets-store -o jsonpath='{.status.conditions}'
# Hub mirror must be populated
kubectl --kubeconfig ~/.kube/hub-config -n spoke-secrets get externalsecret ryzen-shared-secrets   # SecretSynced
```

## Hub-side Tailscale egress pod fails with "Tailscale node not found"

**Symptom**: `ts-ryzen-api-egress-*` pod on hub logs `Tailscale node "ryzen-operator.tail286401.ts.net." not found; it either does not exist, or not reachable because of ACLs`.

**Causes** (any one):
1. The new ryzen operator registered under a different hostname (e.g., `ryzen-operator-1`) because the stale `ryzen-operator` device wasn't deleted before bootstrap (see "Stale duplicate `<spoke>-operator` tailnet device after recreate").
2. Hub's `ryzen-api-egress` Service annotation `tailscale.com/tailnet-fqdn` points at an old device name.
3. The ACL grant `tag:k8s → tag:k8s-operator` (impersonate system:masters) is missing, so the egress can't reach the operator proxy.

**Fixes**:
1. Verify the new device hostname: `tailscale status | grep ryzen-operator`. If it has a `-N` suffix, delete the stale device via the TS API and force the operator to re-register cleanly so it claims the canonical `ryzen-operator`.
2. Confirm/patch the hub-side Service annotation (source of truth: `packages/components/hub-management/apps/headlamp.yaml`):
   ```bash
   kubectl --kubeconfig ~/.kube/hub-config annotate svc ryzen-api-egress -n tailscale \
     "tailscale.com/tailnet-fqdn=ryzen-operator.tail286401.ts.net" --overwrite
   kubectl --kubeconfig ~/.kube/hub-config delete pod -n tailscale \
     -l tailscale.com/parent-resource=ryzen-api-egress --grace-period=0 --force
   ```
3. Ensure `policy.hujson` carries the `tag:k8s → tag:k8s-operator` impersonation grant and that the spoke operator has `APISERVER_PROXY=true` (so it actually listens on :443 of its device).

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

## root-ryzen child Apps stuck on "namespaces X not found"

**Symptom**: a `ryzen-*` Application's `operationState.message` says `one or more objects failed to apply, reason: namespaces "gitea" not found`.

**Cause**: Ryzen reconciles its OWN apps via the LOCAL ArgoCD (`root-ryzen` @ `main`, destination in-cluster). A rendered resource targets a namespace that doesn't exist on ryzen (e.g. a `gitea`-ns resource the profile should have deleted). NOTE: this is NOT the retired pre-agent model where the hub rendered the overlay and applied stray resources to ITSELF — ryzen now applies to its own cluster.

**Fixes** (pick one):
- Quick: `kubectl --context admin@ryzen create ns <missing-ns>` to unblock.
- Proper: in the ryzen overlay / `local-core-ryzen` profile, `$patch: delete` the offending resource (it targets a service that no longer exists on ryzen). Commit + merge to `main` → `root-ryzen` reconciles (or `deployment/scripts/ryzen-sync.sh`).

## Pods stuck pulling `gitea.cnoe.localtest.me:8443/giteaadmin/<image>`

**Symptom**: `kubectl get pods -n workflow-builder` shows ImagePullBackOff with `gitea.cnoe.localtest.me:8443/giteaadmin/python:3.12-slim` etc.

**Cause**: The ryzen overlay or individual workload manifests have legacy kustomize `images:` rewrites pointing at the RETIRED local Gitea registry. Ryzen uses GHCR (`ghcr.io/pittampalliorg/*`) — there is no local registry.

**Fix**: grep for `newName: gitea.cnoe.localtest.me` in `packages/components/workloads/*/manifests/kustomization.yaml` and replace with `newName: ghcr.io/pittampalliorg/<svc>`. Commit + merge to `main` → `root-ryzen` reconciles (or `deployment/scripts/ryzen-sync.sh`). (CAVEAT: the HUB Tekton lanes still legitimately reference `gitea.cnoe.localtest.me` in some tasks — scope this fix to ryzen workload image refs only.)

## ExternalSecrets failing on a retired `gitea` ClusterSecretStore

**Symptom**: ExternalSecrets like `workflow-builder-gitea-admin` show `STATUS: SecretSyncedError, error: the desired SecretStore gitea is not ready`.

**Cause**: A leftover ExternalSecret references a `gitea` ClusterSecretStore that expected a local Gitea instance. Ryzen has no local Gitea (retired).

**Fix**: Drop these ExternalSecrets from their source kustomizations. If a stub Secret is needed for compatibility, `kubectl create secret generic <name> --from-literal=username=disabled --from-literal=password=disabled`.

> **Note (PR #2317):** The `gitea-registry-creds` imagePullSecret was a dead reference (the Secret was never produced on any cluster) and has been REMOVED fleet-wide from 23 manifests + 2 SAs. All images pull via `ghcr-pull-credentials` from `ghcr.io/pittampalliorg/*`. Do NOT re-add `gitea-registry-creds` (the only legitimate use left is build-side PUSH in `deployment/scripts/trigger-tekton-builds.sh`).

## ryzen-* Apps stuck OutOfSync — auto-sync disabled

**Symptom**: Apps like `ryzen-external-secrets`, `ryzen-tailscale-operator` show OutOfSync/Healthy and never converge automatically. (NOTE: `ryzen-azure-keyvault-store` and `ryzen-azure-workload-identity` no longer exist on ryzen — `local-core-ryzen` deletes those Applications, post-AWI-removal.)

**Cause**: An old patch in `packages/components/profiles/local-core-ryzen/kustomization.yaml` removed `/spec/syncPolicy/automated` from these Apps (intended to avoid races with AWI admission webhook during standalone-ryzen bootstrap).

**Fix**: Already removed in commit `a07e038d4` (May 2026). If it reappears, look for `op: remove path: /spec/syncPolicy/automated` patches and delete them.

## Ingresses with class=nginx stuck ADDRESS=<none> (ryzen = Contour + Kourier, NOT nginx)

**Symptom**: `kubectl get ingress -n workflow-builder` shows nginx-class Ingresses (`workflow-builder`, `workflow-builder-mcp-gateway`) with empty ADDRESS. Parent Applications stuck Synced/Progressing.

**Cause**: **Ryzen runs Contour + Kourier (+ Knative serving net-kourier), NOT ingress-nginx** — only the `tailscale` IngressClass and Contour/Kourier are available. External access on ryzen goes via Tailscale, not nginx. Relatedly, ryzen has NO local gitea (retired — GitHub + GHCR only) and NO `gitea` namespace, so `local-core-ryzen` excludes the `gitea-secretstore` + `nginx-tls-secret` Applications and the `gitea-tailscale-backend` Service (target ns `gitea`, absent on ryzen).

**Fix**: Add ryzen-overlay kustomize patches that `$patch: delete` the nginx Ingresses for affected Apps. dev/staging still get them (they run nginx-ingress). The `gitea-secretstore` / `nginx-tls-secret` / `gitea-tailscale-backend` deletions live in `packages/components/profiles/local-core-ryzen/kustomization.yaml` (~lines 465-505).

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

**Cause**: The ryzen overlay's workflow-builder Deployment patch was setting `BENCHMARK_ARGOCD_APPLICATION_NAME=workflow-builder` + `BENCHMARK_ARGOCD_KUBECONFIG_MODE=in-cluster`, enabling the launch-stability gate. dev/staging leave them unset so the gate short-circuits to `stable: true`; ryzen should match (the gate isn't wanted on ryzen).

**Fix**: Removed in commit `bda45c3a5`. If it reappears, ensure neither env var is set on the workflow-builder Deployment on ryzen — dev/staging leave them unset so the launch-stability check short-circuits to `stable: true`.

## workflow-builder UI not reachable on ryzen (no Ingress)

**Symptom**: `https://workflow-builder-ryzen.tail286401.ts.net/` doesn't resolve. `kubectl get ingress -A` on ryzen shows nothing.

**Cause**: Ryzen has no nginx-ingress-controller; the base `Ingress-workflow-builder.yaml` uses `ingressClassName: nginx`. Post-A6 the ryzen overlay deletes it.

**Fix (CURRENT, PR #2319):** workflow-builder is exposed via a Tailscale **L4 LoadBalancer Service** (`type: LoadBalancer`, `loadBalancerClass: tailscale`, annotation `tailscale.com/hostname: workflow-builder-ryzen`) — NOT an Ingress, and NO Let's Encrypt. HTTPS is terminated **in-cluster** by a per-pod nginx `tls-terminator` sidecar serving the self-signed `*.tail286401.ts.net` wildcard, so the LB only forwards TCP. The ryzen LB Service lives at `packages/components/workloads/workflow-builder-tailnet-lb/`; the sidecar + its ConfigMap + the wildcard Certificate live in `packages/components/workloads/workflow-builder/manifests/`. The Tailscale operator registers the tailnet device `workflow-builder-ryzen` automatically. Access: `https://workflow-builder-ryzen.tail286401.ts.net`.

> **History:** earlier this was a Tailscale-class **Ingress** with a per-hostname **Let's Encrypt** cert (ProxyClass `development-prod-cert`) — recreate churn exhausted LE's 5-certs/168h limit → 429 → unreachable (commit `502bccd3c`). ryzen then briefly used a plain-HTTP Tailscale LoadBalancer (PRs #2314/#2316). Both are SUPERSEDED by the L4-LB + in-cluster self-signed-CA HTTPS model (PR #2319). Do NOT re-add `ingressClassName: tailscale` or `development-prod-cert`.

> **CA trust:** the wildcard is signed by the self-signed "PittampalliOrg Tailnet Dev CA" (KV `TAILNET-DEV-CA-CRT`/`-KEY`, mirrored hub → ns `spoke-secrets` Secret `tailnet-ca`, restored on the spoke into `cert-manager/tailnet-dev-ca` by the `tailnet-ca` app, signed by the `tailnet-dev-ca` `ClusterIssuer`). The SAME CA is reused on every cluster, so it survives recreation. Workstation trust is seeded by nixos-config (`modules/services/cluster-certs.nix` for system/curl/git + `home-modules/tools/chromium.nix` certutil seed of `~/.pki/nssdb` — REQUIRED because `security.pki` does NOT cover Chrome's own NSS db; nixos-config commit `44ba6324`).

## workflow-builder 502 for browsers only — tls-terminator proxy buffers too small

**Symptom**: `https://workflow-builder-ryzen.tail286401.ts.net/` returns **502** in a real browser, but `curl -sk` (which sends small headers) returns **302** — the curl success masks the browser failure.

**Cause**: The `tls-terminator` sidecar's nginx ships an 8k default proxy header buffer. SvelteKit auth's large `Set-Cookie` response headers overflow it → nginx 502 ("upstream sent too big header"). Bare curl never trips it because its request/response headers are tiny.

**Fix (PR #2327)**: Raise the buffers in the sidecar ConfigMap (`ConfigMap-workflow-builder-tls-terminator.yaml`):
```nginx
proxy_buffer_size       32k;
proxy_buffers           8 32k;
proxy_busy_buffers_size 64k;
large_client_header_buffers 4 32k;
```
**LESSON**: verify HTTPS app exposure with a REAL browser (or curl carrying full browser-sized headers), not bare curl. Diagnose via the sidecar nginx error log.

## Headlamp UI: "Failed to get authentication information: ryzen" (FIXED BY PR #2395)

> **FIXED BY PR #2395** — the enroll scripts now auto-restart hub Headlamp after re-staging the spoke kubeconfig Secret, so this no longer surfaces on a recreate. See "Hub Headlamp kubeconfig stale after spoke recreate" below. The manual recovery here is still valid for a LIVE token rotation that didn't go through enroll.

**Symptom**: Open `https://headlamp-hub.tail286401.ts.net/` → click the `ryzen` cluster tab → red banner "Failed to get authentication information". Hub Headlamp Pod is otherwise healthy.

**Cause**: Headlamp's `generate-kubeconfig` initContainer reads the `cluster-ryzen` Secret ONCE at pod start and writes a kubeconfig into an emptyDir. If the cluster Secret's bearer token rotates after the pod started (typical after a ryzen recreate), the in-memory kubeconfig still has the old token. The new token in the Secret never reaches the running Headlamp container.

**Fix**:
```bash
kubectl --context hub-cluster rollout restart deploy -n headlamp hub-headlamp hub-headlamp-embedded
```

To make this automatic going forward, consider adding the Reloader annotation (`reloader.stakater.com/auto: "true"`) on the Headlamp Deployments so they restart whenever the `cluster-ryzen` Secret changes.

## Hub Headlamp kubeconfig stale after spoke recreate (PR #2395)

**Symptom**: After EVERY spoke recreate (dev + ryzen), the hub Headlamp can't auth to the rebuilt cluster — the spoke tab shows "Failed to get authentication information" even though the staged `headlamp-cluster-<spoke>` Secret on the hub already carries the fresh endpoint/CA/token.

**Cause**: `enroll-{dev,ryzen}-agent.sh` step 5b re-stages the `headlamp-cluster-<spoke>` Secret (fresh kube-API endpoint + read-only SA token + CA, label `headlamp.dev/cluster=true`), but the hub Headlamp builds its kubeconfig ONLY in its `generate-kubeconfig` init-container at pod start. A pod that predates the recreate keeps serving the OLD spoke endpoint/CA/token and cannot auth to the rebuilt cluster, so the freshly staged Secret is inert.

**Fix**: Already committed in stacks `6cee88a70` (PR #2395). Both enroll scripts now restart hub Headlamp on the hub after staging the Secret (step 5b):
```bash
kubectl -n headlamp rollout restart deploy/hub-headlamp deploy/hub-headlamp-embedded
```
The restart is guarded on the Deployments existing and is non-fatal (Headlamp is off the critical path). Full detail: `shared-skills/cluster-desired-state/runbooks/recovery-and-gotchas.md`.

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

## Local repo-server not ready when controller first syncs `root-ryzen` (PR #2395, ~5min stall)

**Symptom**: On a fresh recreate, `root-ryzen` sticks in `ComparisonError` (sync=Unknown) with ZERO child apps rendered, and convergence stalls for ~5 min before anything happens. The app's message references `dial tcp ...:8081: connect: connection refused` to the local `argocd-repo-server`.

**Cause**: The local `argocd-application-controller` runs `root-ryzen`'s FIRST comparison before the local `argocd-repo-server` is accepting connections (dial `:8081` connection refused) → `root-ryzen` goes `ComparisonError`. The controller does NOT re-queue the errored app for a full resync window (~5 min observed), so convergence stalls with no child apps until a manual refresh.

**Fix**: Already committed in stacks `89fd0df8b` (PR #2395). Force a clean first comparison after the local repo-server is Available:
- `enroll-ryzen-agent.sh` step 6b waits then hard-refreshes:
  ```bash
  kspoke -n argocd rollout status deploy/argocd-repo-server --timeout=120s
  kubectl -n argocd annotate application root-ryzen argocd.argoproj.io/refresh=hard --overwrite
  ```
- `bootstrap-spoke-cluster.sh` step 10: hard-refresh `root-ryzen` again (so it re-compares against the latest `main` HEAD).

Both steps are NON-FATAL (the resync timer would eventually heal it on its own; this just makes the recreate hands-off and fast). Full detail: `shared-skills/cluster-desired-state/runbooks/recovery-and-gotchas.md`.

## kueue large-CRD wedge — ArgoCD 3.4.2 ClientSideApplyMigration writes a >262144-byte annotation (ryzen-only)

**Symptom**: `ryzen-kueue` won't sync. ArgoCD reports the apply of the `workloads.kueue.x-k8s.io` CRD failing with `metadata.annotations: Too long: must have at most 262144 bytes` (or a wedged sync that never completes on that CRD). This surfaces on ryzen but not on a clean dev/staging.

**Cause**: ArgoCD 3.4.2 runs a **ClientSideApplyMigration** step before SSA whenever a live object is not yet owned by `argocd-controller`. For the ~1.4MB `workloads.kueue.x-k8s.io` CRD, that intermediate client-side apply writes the entire object into the `kubectl.kubernetes.io/last-applied-configuration` annotation, which exceeds the 262144-byte annotation limit and wedges the apply (argo-cd#26279). Triggered on ryzen because the CRD had been hand-applied with `kubectl` during recovery, so the live managedFields owners are `[kubectl, argocd-controller, kube-apiserver, kueue]` — `argocd-controller` is not the sole owner, so the migration step fires.

**Fix**: Set `ClientSideApplyMigration=false` as a syncOption on the **ryzen-only** overlay patch. Verified present at `packages/overlays/ryzen/kustomization.yaml:~261`:
```yaml
- op: add
  path: /spec/syncPolicy/syncOptions/-
  value: ClientSideApplyMigration=false
```
This forces pure SSA — a clean field-ownership transfer with no Workload CR data loss and no oversized annotation. It is a harmless no-op on a clean recreate (where `argocd-controller` already owns the CRD), so keep it while `kubectl` co-owns the CRD.

## kustomize RFC6902 `op: add /spec/source/kustomize` clobber — co-located patches overwrite each other

**Symptom**: After a ryzen sync, an Application that should have a `$patch: delete` (e.g., the `gitea-tailscale-backend` Service) instead fails with `namespaces "gitea" not found`, OR the tailscale-operator's `PROXY_IMAGE` override disappears. `argocd app diff` shows only one of the two intended modifications took effect.

**Cause**: A kustomize `op: add` to `/spec/source/kustomize` REPLACES the whole node (last-writer-wins) — it is NOT a merge. Both `packages/components/profiles/local-core-ryzen/kustomization.yaml` AND `packages/overlays/ryzen/kustomization.yaml` op:add to the **same** `/spec/source/kustomize` path on the tailscale-operator Application. The overlay runs AFTER the component, so the overlay's block wins and silently clobbers the component's block.

**Fix**: The WINNING (overlay) block must carry EVERYTHING that path needs: for tailscale-operator that means BOTH the `PROXY_IMAGE=v1.92.4` env AND the `gitea-tailscale-backend` Service `$patch:delete`, co-located in the `overlays/ryzen` block. If you move the Service delete into the profile block, it gets clobbered and the sync fails "namespaces gitea not found". This clobber rule governs every co-located `op: add /spec/source/kustomize` between `profiles/local-core-ryzen` and `overlays/ryzen` — always put the complete set in the overlay.
