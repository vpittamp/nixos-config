# Recovery runbooks & fleet-wide gotchas

Failure modes discovered/validated across hub/ryzen/dev. Each is **Symptom ->
Diagnosis -> Fix -> Verify**. Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`. For ArgoCD/Promoter recovery
mechanics defer to the `gitops` skill; for Crossplane spoke specifics, `talos-clusters`.

---

## A. Talos ISO vs Kubernetes version — in-place upgrade (dev/staging recreate)

**Symptom.** A fresh dev cluster of Talos 1.13.2 + k8s 1.36 never bootstraps; the
maintenance-mode node rejects the requested Kubernetes version (`version of Kubernetes
1.36.0 is too new to be used with Talos 1.12.4`).

**Diagnosis.** Hetzner's public catalog has ONLY a Talos **1.12.4** maintenance ISO (no
custom-ISO upload API; a custom ISO = a Hetzner support ticket with a direct
`factory.talos.dev` URL). The pinned `TALOS_VERSION` (`apply-config` install image) governs
the INSTALLED Talos version even when booting the 1.12.4 ISO. BUT the maintenance-mode node
validates the REQUESTED k8s version against the RUNNING (1.12.4) Talos. So 1.36 on a
1.12.4 ISO can't one-shot.

**Fix (now automatic in the recreate path).** `deployment/scripts/talos-hetzner/provision-spoke.sh`
already encodes the supported in-place path: it bootstraps at `BOOTSTRAP_K8S_VERSION`
(default `1.35.0`) against the 1.12.4 maintenance ISO while installing the pinned
`TALOS_VERSION` (`1.13.2`) to disk, then upgrades k8s to `K8S_VERSION` (`1.36.0`) once the
installed Talos is running and CNI is up. The dev orchestrator
`deployment/scripts/talos-hetzner/recreate-dev.sh` wraps this (data backup -> destroy ->
device cleanup -> provision-spoke.sh -> bootstrap-spoke-deps.sh -> enroll-dev-agent.sh ->
data restore -> verify-gate); use it as the dev rebuild entry point. (The historical
Crossplane `talospokeclusterclaims` two-step `kubernetesVersion` patch is RETIRED — the
Crossplane spoke path was removed.)

**Verify.** `kubectl --context dev get nodes -o wide` — OS-IMAGE shows Talos 1.13.x and
nodes Ready on the target k8s (1.36).

---

## B. hub -> ryzen Tailscale host TCP-passthrough failures (Headlamp-only)

**Symptom.** Headlamp can't reach ryzen; TLS or connection-refused errors reaching
`https://ryzen.tail286401.ts.net:6443`. (This is NO LONGER an ArgoCD-sync symptom —
sync rides the argocd-agent, §B-note below.)

**Diagnosis & context.** ArgoCD sync no longer rides a hub->ryzen kube connection at all —
ryzen is an AUTONOMOUS argocd-agent whose local controller reconciles its own apps and
reports to the hub principal. The host TCP-passthrough kube endpoint now serves ONLY
**Headlamp**: the Talos kube-apiserver reached DIRECTLY over Tailscale via the ryzen HOST
device (`ryzen.tail286401.ts.net`, `100.96.102.1`, `tag:k8s`) running `tailscale serve
--bg --tcp=6443` as a raw TCP passthrough — a FULL TLS verify (`insecure:false`) against
the Talos CA (`../references/architecture.md` §5). This dropped the per-hostname Let's
Encrypt cert whose 5-dup-certs/week limit recreate churn exhausted (2026-05-29
fleet-0-healthy incident, PRs #2305/#2307). The two live Headlamp failure modes:

(a) **Host serve not configured / pointing at the wrong Docker port after a recreate**
(connection refused, or hitting a dead port). Fix: `sudo systemctl restart
tailscale-serve-k8s-apiserver` on the ryzen host (the unit auto-discovers the current
Talos-in-Docker apiserver host port), or just re-run bootstrap which does this.

(b) **Apiserver serving cert missing the tailnet certSANs** (TLS verify fails: the hub
trusts the Talos CA but the cert's SANs don't include the FQDN/IP it dialed). Fix: ensure
the bootstrap `--config-patch` adds `cluster.apiServer.certSANs:
[ryzen.tail286401.ts.net, 100.96.102.1]`; to add live, `talosctl patch mc` the same.

(c) **Stale Headlamp pod serving the OLD spoke endpoint after a recreate** (Headlamp can
auth the hub but cannot reach the rebuilt spoke; cluster list shows the old endpoint/CA).
The hub Headlamp builds its kubeconfig ONLY in its `generate-kubeconfig` init-container at
pod start, so a pod predating the recreate keeps the stale `headlamp-cluster-<spoke>`
endpoint/CA/token and the freshly re-staged Secret is inert. Fix: bounce the hub Headlamp
pods so the init-container rebuilds the kubeconfig — `kubectl -n headlamp rollout restart
deploy/hub-headlamp deploy/hub-headlamp-embedded`. `enroll-{dev,ryzen}-agent.sh` step 5b
now does this automatically (after re-staging the `headlamp-cluster-<spoke>` Secret with the
fresh kube-API endpoint + read-only SA token + CA + label `headlamp.dev/cluster=true`),
guarded on deploy existence and non-fatal — Headlamp is off the critical path (PR #2395).

(c2) **Stale `headlamp-cluster-<spoke>` Secret (token+CA) after a recreate -> `x509` + `401`**
(2026-06, `reference_headlamp_recreate_token_race`). DIFFERENT from (c): here the Secret ITSELF
is stale (the prior cluster's bearer token + CA), so even a freshly-restarted Headlamp gets
`x509: certificate signed by unknown authority` (stale CA) + `HTTP 401` (stale token) for that
spoke; reachability is fine (a 401, not a timeout). Cause: enroll step 5b's spoke-token wait
(then 60s) elapsed before the slower **dev** Talos cluster's `headlamp-reader-token` was
populated, so 5b warn-skipped and never refreshed the Secret. ryzen's fast local cluster won the
race. FIXED: step 5b is now `stage_headlamp()` with a **`HEADLAMP_ONLY=true`** re-run mode, a
**180s** wait for BOTH token AND ca.crt, and a POST-convergence re-stage (`recreate-dev.sh` step
8b / `bootstrap-spoke-cluster.sh` step 10b). **Live fix any time it's stale:**
`HEADLAMP_ONLY=true SPOKE_KUBECONFIG=/tmp/talos-spoke-dev/kubeconfig HUB_CONTEXT=hub-cluster bash deployment/scripts/argocd-agent/enroll-dev-agent.sh dev`
(ryzen: `HEADLAMP_ONLY=true RYZEN_CONTEXT=admin@ryzen bash deployment/scripts/argocd-agent/enroll-ryzen-agent.sh ryzen`).
Verify: from a `hub-headlamp` pod, `wget -H "Authorization: Bearer <staged token>" https://<spoke-fqdn>:6443/version` -> 200.

**Agent-sync note.** If `ryzen-*` apps are OutOfSync/unknown on the hub, the problem is the
argocd-agent (principal/agent mTLS or the autonomous agent itself), NOT this kube path —
the `cluster-ryzen` agent mapping has no bearerToken to go stale. `register-spoke-with-hub.sh`
is RETIRED; do NOT re-mint `ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}` to "fix" sync. The
operator apiserver-proxy SNI mismatch likewise no longer applies (dev/staging are also
managed agents now, not direct-IP kube connections).

**Verify.**
```bash
kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret cluster-ryzen \
  -o jsonpath='{.data.server}' | base64 -d    # https://argocd-agent-resource-proxy:9090?agentName=ryzen
kubectl --kubeconfig ~/.kube/hub-config -n argocd get applications | grep '^ryzen-'   # Synced/Healthy
# optional Headlamp real-TLS reachability (no --insecure):
kubectl --server=https://ryzen.tail286401.ts.net:6443 \
  --certificate-authority=<Talos CA> --token=<SA token> get nodes
```

---

## C. kueue large-CRD wedge — ClientSideApplyMigration (ryzen-only)

**Symptom.** ArgoCD 3.4.2 wedges syncing the `workloads.kueue.x-k8s.io` CRD; sync
errors mention a `last-applied-configuration` annotation exceeding 262144 bytes.

**Diagnosis.** ArgoCD 3.4.2 runs a `ClientSideApplyMigration` step before SSA when a
live object is not yet argocd-controller-owned. For the ~1.4MB `workloads.kueue` CRD the
intermediate client-side apply writes a >262144-byte last-applied annotation and wedges
(argo-cd#26279). Triggered on ryzen because the CRD had been hand-`kubectl apply`-ed
during recovery, so kubectl co-owns it.

**Fix.** `ClientSideApplyMigration=false` on the **ryzen-only** overlay patch
(`packages/overlays/ryzen/kustomization.yaml:261`) — pure SSA, clean ownership transfer,
no Workload CR data loss. Keep it while kubectl co-owns the CRD (harmless no-op on a
clean recreate). NOT a hub patch.

**Verify.**
```bash
kubectl --context admin@ryzen get crd workloads.kueue.x-k8s.io \
  -o jsonpath='{.metadata.managedFields[*].manager}'    # kubectl co-ownership persists
kubectl --kubeconfig ~/.kube/hub-config -n argocd get application ryzen-kueue   # Synced/Healthy
```

---

## D. RFC6902 `op: add /spec/source/kustomize` clobber (ryzen overlay)

**Symptom.** A ryzen sync fails with `namespaces "gitea" not found`, or a kustomize env
patch (e.g. PROXY_IMAGE) silently doesn't apply.

**Diagnosis.** A kustomize JSON6902 `op: add /spec/source/kustomize` REPLACES the whole
node (last-writer-wins). BOTH `packages/components/profiles/local-core-ryzen` AND
`packages/overlays/ryzen` op:add to the tailscale-operator app's
`/spec/source/kustomize`. The overlay runs after the component, so it wins and clobbers
the component's block. If the `gitea-tailscale-backend` Service `$patch:delete` lives in
the losing (profile) block, it gets dropped and the sync fails because ns gitea doesn't
exist on ryzen.

**Fix.** Co-locate everything in the WINNING (`overlays/ryzen`) block: the
tailscale-operator overlay patch must carry BOTH the PROXY_IMAGE=v1.92.4 env AND the
`gitea-tailscale-backend` Service `$patch:delete`. This clobber rule governs EVERY
co-located op:add between the two files.

**Verify.** `kubectl kustomize packages/overlays/ryzen | grep -A3 gitea-tailscale-backend`
(should not appear / should be deleted); `ryzen-tailscale-operator` app Synced.

---

## E. env-table SWE-bench restore (dev recreate preflight + post-recreate)

**Symptom.** After a dev recreate the Benchmarks UI has no SWE-bench environment image
catalog / validated env builds; eval runs can't find environments.

**Diagnosis.** The disposable dev recreate wipes Postgres. The db-seed hook restores
only sanitized fixtures (canary agents, hidden runner workflow, Lite/Verified suites +
instances, builtin environments). The richer env-table data (e.g.
`environment_image_builds`) lives in the workflow-builder **APP repo** scripts, not
stacks — it must be backed up BEFORE deleting infra and restored after.

**Fix.**
1. PREFLIGHT (before destroying dev) — confirm no active work and back up:
   ```bash
   kubectl --context dev -n workflow-builder exec postgresql-0 -- psql -U postgres -d workflow_builder \
     -c "select status,count(*) from benchmark_runs group by status; select status,count(*) from benchmark_resource_leases group by status;"
   kubectl --context dev exec -n workflow-builder postgresql-0 -- pg_dump -U postgres -d workflow_builder \
     -t environment_image_builds --data-only --column-inserts > /tmp/eib.sql
   ```
   Cancel/drain active runs + leases + Dapr workflows first.
2. POST-RECREATE — restore after db-migrate/db-seed complete:
   ```bash
   kubectl --context dev cp /tmp/eib.sql workflow-builder/postgresql-0:/tmp/eib.sql
   kubectl --context dev exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -f /tmp/eib.sql
   ```

**Verify.** db-migrate ran before db-seed; re-running db-seed creates no duplicate
SWE-bench rows (`SEED_SWEBENCH_FIXTURES_SKIP_WHEN_ACTIVE=true`); Lite=300/Verified=500;
the env-image catalog row count matches the backup. Use the `evaluations` skill for the
capacity gate before any benchmark ramp.

---

## F. Stale tailnet device cleanup (every spoke recreate)

**Symptom.** After a recreate the operator registers `<spoke>-operator-1` / `-2`
(suffixed) instead of the canonical `<spoke>-operator`, OR hub->spoke connectivity
points at a dead device; ESO/ArgoCD intermittently fail.

**Diagnosis.** A recreate leaves a stale duplicate `<spoke>-operator` (and other) tailnet
devices that still reserve the canonical hostname. The new operator can't claim it and
suffixes. Hub's `<spoke>-api-egress` Service may also stay pinned to the OLD device.

**Fix.** Delete the stale devices via the Tailscale API (token minted from the
operator-oauth Secret / OAuth client), BEFORE or right after bootstrap. For
Crossplane spokes, group-9 proxygroup-auth already cleans `svc:k8s-api-<spoke>` + stale
devices; for ryzen, the gated `deployment/scripts/cleanup-tailnet-devices.sh` runs in the
`--recreate` path. Then patch/restart the hub egress Service or the operator StatefulSet pod
so it re-resolves.

**Backstop = `tailnet-device-sweeper` CronJob** (hub ns `tailscale`, every 15m, PRs
#2322/#2325). Deletes OFFLINE stale spoke tailnet devices (offline-only via
`lastSeen > 30m`, best-effort, matches/logs the MagicDNS `name`) so dead devices don't
accumulate and force `-N` collisions. It is hygiene, NOT the guarantee — the hard
on-recreate guarantee remains the gated pre-recreate `cleanup-tailnet-devices.sh`.
API gotcha: the Tailscale device `hostname` field DROPS the `-N` suffix (a live device and
its dead `-N` twin share one hostname) — match on the MagicDNS `name`; `lastSeen` IS a
reliable liveness signal (control-plane keepalives keep it fresh for connected devices). An
in-Composition pre-onboarding cleanup was deliberately NOT built (a function-pipeline error
would halt ALL spoke provisioning).

**Verify.** The canonical hostname (no `-1` suffix) is present; no stale offline devices
remain in the tailnet admin list. (ryzen hub->spoke no longer uses the operator device —
see §B; this still matters for the ESO transport device and operator-proxy spokes.) See
the `talos-clusters` skill `runbooks/tailscale-name-recovery.md` and the `gitops` skill for
device-backed Ingress DNS recovery.

---

## G. Permanent benign drifts — do NOT chase

- Hub `root-application` OutOfSync — ServerSideApply sees ESO-added fields on the two
  spoke-secrets ExternalSecrets as drift. Cosmetic.
- `dev-spoke-transport` (and the spoke egress Service generally) OutOfSync — the
  Tailscale operator rewrites `.spec.externalName` at runtime vs the
  `invalid.tailnet.internal` placeholder. The ClusterSecretStore itself is Synced.
- ProxyGroup `ProxyGroupInvalid`/`ProxyGroupCreating` on a leaked spoke-owned PG in the
  hub view (transient/stale). **Never delete a working VIP** to "fix" it.
- **"Unknown" operation status on a HANDFUL of spoke apps** (`cert-manager`, `mlflow`, and on
  KIND/ryzen also `ingress-nginx-cert`). They are Synced/Healthy with auto-sync, but
  `status.operationState` is EMPTY because a sync OPERATION never had to RUN — they were already in
  their desired state at creation, and auto-sync only operates on DRIFT. The UI renders "no operation
  run" as **"Unknown."** WHY already-in-sync: `cert-manager` is installed by the spoke BOOTSTRAP
  (a prereq dep, before ArgoCD) and the ArgoCD app merely ADOPTS it; `mlflow` is a decommission app
  (`syncPolicy.allowEmpty: true` — intentionally empty); `ingress-nginx-cert` likewise already-satisfied.
  Benign + somewhat inherent (recurs every recreate since cert-manager is always bootstrap-installed).
  A one-time `argocd app sync` records a `Succeeded` op and flips the indicator green; not worth chasing.
  (NOT the same as the hub's architectural per-spoke "Unknown" — that's a separate, also-benign thing
  where ALL agent apps lack the operation lifecycle because it runs on the spoke. These are distinct:
  they lack an op because none was needed.)
  > **`ingress-nginx-cert` was relocated out of `packages/base/apps`** (2026-06; the legacy
  > kind/idpbuilder lane is RETIRED). Its copy-tls-cert Job sourced `gitops-cert` (produced only by
  > the now-retired idpbuilder ExternalSecret) and its output `persistent-tls-cert` is unreferenced;
  > on Talos the real TLS is the tailnet wildcard cert, so the Job only ever failed there (perpetual
  > "Sync failed"). **dev/staging/hub drop it**, and **ryzen** (Talos-in-Docker, GitHub+GHCR, no
  > idpbuilder) does not use the idpbuilder gitops-cert path either. So a dev recreate no longer shows
  > a `dev-ingress-nginx-cert` app at all.
- **`dev-swebench-runtime-builds` is `Progressing` forever — BENIGN, not a failure**
  (`reference_recreate_gate_cache_pvc`). It owns the persistent buildah-cache PVC
  `buildah-cache-swebench-inference` (`local-path` = WaitForFirstConsumer), which has no consumer at
  rest, so the PVC stays `Pending` and ArgoCD never marks the app Healthy. The PVC is CORRECTLY
  persistent (shared layer cache across builds — do NOT make it ephemeral). `recreate-dev.sh`'s
  verify-gate tolerates this specific case (Progressing app that OWNS a `*cache*` PVC); a stuck
  WORKLOAD/data PVC still fails the gate. Same app is Progressing-forever on every spoke.

---

## H. Flannel `--iface` after Talos upgrade (hub) — now self-healed

**Symptom.** Cross-node pod networking silently breaks on the hub after a Talos upgrade.

**Diagnosis.** Hetzner blocks VXLAN over the public IP; the kube-flannel DaemonSet must
pin `--iface=enp7s0`, and a Talos upgrade (or a hub recreate) resets it. CoreDNS anti-affinity
is similarly not persisted by Talos.

**Fix.** This is now self-healing via the **`kube-system-fixups` CronJob**
(`packages/components/hub-management/manifests/kube-system-fixups/`), which re-applies the
Flannel `--iface=enp7s0` patch AND the CoreDNS anti-affinity patch that Talos does not
persist. The hub recreate path (`deployment/scripts/recreate-hub.sh`) also applies these as
fixups (`--fixups` mode). Only re-apply by hand if the CronJob is absent/disabled.

**Verify.** Cross-node pod-to-pod connectivity; flannel pods Ready on all 5 nodes; the
`kube-system-fixups` CronJob is scheduled and its last run succeeded.

---

## I. workflow-builder 502 "upstream sent too big header" — tls-terminator buffers (PR #2327)

**Symptom.** `https://workflow-builder-<cluster>.tail286401.ts.net` returns **502 in a
real BROWSER** while a bare `curl` returns 302 — so the failure HIDES from a quick
curl smoke test.

**Diagnosis.** Web exposure terminates HTTPS in the in-cluster nginx `tls-terminator`
sidecar (`../references/architecture.md` §7). nginx's default 8k proxy header buffer
overflows on SvelteKit auth's large `Set-Cookie` headers; bare curl sends small headers
so it slips under the limit and returns 302, masking the browser 502. Diagnose via the
sidecar nginx **error log** (`upstream sent too big header while reading response header
from upstream`).

**Fix.** Raise the buffers in the sidecar ConfigMap
(`packages/components/workloads/workflow-builder/manifests/ConfigMap-workflow-builder-tls-terminator.yaml`):
`proxy_buffer_size 32k; proxy_buffers 8 32k; proxy_busy_buffers_size 64k;
large_client_header_buffers 4 32k`.

**Verify / LESSON.** Verify HTTPS app exposure with a REAL browser (or curl WITH full
browser headers), not bare curl. After the fix the browser loads past auth (no 502).

---

## J. env/hub-next MISSING after a hub promotion PR merges

**Symptom.** GitOps Promoter `ChangeTransferPolicyNotReady` "couldn't find remote ref
env/hub-next"; PromotionStrategy `stacks-environments` NotReady, flooding warning events.

**Diagnosis.** NOT GitHub auto-delete (`delete_branch_on_merge=false`). ONLY `env/hub-next`
is affected — spoke `-next` branches self-heal via their busy hydrators, but the idle hub
hydrator does not recreate it after the PR merges.

**Fix.** When active==proposed dry SHA (no pending hub change), recreate the branch:
```bash
git -C /home/vpittamp/repos/PittampalliOrg/stacks/main push origin origin/env/hub:refs/heads/env/hub-next
```
The Promoter reconciles `stacks-environments` back to Ready.

**Verify.** `git ls-remote origin env/hub-next` returns a ref; PromotionStrategy
`stacks-environments` READY; warning-event flood stops.

---

## K. gitea container registry RETIRED fleet-wide — do NOT re-add gitea-registry-creds (PR #2317)

**Symptom.** A manifest or ServiceAccount references the `gitea-registry-creds`
imagePullSecret; you are tempted to "fix" a pull by re-adding it.

**Diagnosis.** `gitea-registry-creds` was a DEAD reference — the secret was never produced
on any cluster. PR #2317 removed it from 23 manifests + 2 SAs. All images are
`ghcr.io/pittampalliorg/*` pulled via `ghcr-pull-credentials`.

**Fix.** Do NOT re-add `gitea-registry-creds`. Ensure the imagePullSecret is
`ghcr-pull-credentials`. (NOTE: `deployment/scripts/trigger-tekton-builds.sh` uses
`gitea-registry-creds` as a build-side PUSH credential — that is a DIFFERENT use, kept.)

**Verify.** No `gitea-registry-creds` imagePullSecret on any workload SA; pods pull
`ghcr.io/pittampalliorg/*` images cleanly.

## L. External Secrets Operator: v2.4.1 + `external-secrets.io/v1` (2026-05-30 migration)

**Desired state.** ESO chart `2.4.1` fleet-wide (hub `hub-base/apps/external-secrets.yaml`,
spokes `base/apps/external-secrets.yaml`), both with `crds.unsafeServeV1Beta1: true`
(CRDs serve `v1` storage + deprecated `v1beta1`). **ALL ExternalSecret/ClusterSecretStore
manifests are `external-secrets.io/v1`** (PushSecret/ClusterPushSecret stay `v1alpha1`).
Spokes run ESO controller-only (no webhook/cert-controller).

**Pre-flight before ANY manifest apiVersion migration — ESO version is per-cluster.**
The hub is bumped to v2 ahead of spokes. Run on EACH target cluster:
`kubectl get crd externalsecrets.external-secrets.io -o jsonpath='{.spec.versions[*].name}'`.
If a cluster does NOT list `v1`, do NOT flip its manifests to `v1` — that breaks every
ES app with `unable to resolve parseableType for GroupVersionKind: external-secrets.io/v1`
/ `resource mapping not found` (no secret outage — existing objects untouched — but
apps can't apply/compare). This is exactly why the first fleet flip was reverted.

**In-place ESO upgrade of a spoke that has a webhook+cert-controller (e.g. ryzen's
old 0.9.13 install) — REQUIRED one-time fix.** After the controller bumps to v2.4.1,
the CRDs still carry `conversion.strategy: Webhook` pointing at the now-stale v0.9.13
webhook, which can't convert to `v1` → ExternalSecrets become UNREADABLE
(`conversion webhook ... no kind ExternalSecret is registered for version v1`). Fix
(live, one-time; the v2 chart leaves `conversion` unset so FRESH rebuilds default to
None and are clean):
```bash
# set every external-secrets.io + generators.external-secrets.io CRD with strategy=Webhook to None
for c in $(kubectl get crd -o name | grep external-secrets.io); do
  [ "$(kubectl get $c -o jsonpath='{.spec.conversion.strategy}')" = Webhook ] && \
    kubectl patch $c --type=json -p '[{"op":"replace","path":"/spec/conversion","value":{"strategy":"None"}}]'
done
# remove the orphan v0.9.13 webhook + cert-controller (not chart-managed under webhook.create:false; inert once strategy=None)
kubectl delete deploy external-secrets-webhook external-secrets-cert-controller -n external-secrets --ignore-not-found
kubectl delete svc  external-secrets-webhook -n external-secrets --ignore-not-found
# CRITICAL — also delete the orphan VALIDATING webhook configs, else they keep pointing at
# the deleted external-secrets-webhook service and EVERY ExternalSecret/SecretStore apply
# fails with `failed calling webhook "validate.externalsecret.external-secrets.io": failed
# to call webhook` -> apps that manage ES (ryzen-workflow-builder/function-router/
# browserstation) get stuck "Syncing" (op Running, retrying) even though sync=Synced
# health=Healthy. controller-only ESO v2 does NOT use them (dev runs without them).
kubectl delete validatingwebhookconfiguration externalsecret-validate secretstore-validate --ignore-not-found
# then sync the app to apply the v1 CRD selectableFields
argocd app sync <cluster>-external-secrets --grpc-web
```
dev was controller-only on 0.9.13 so it needed NONE of this; ryzen did.

**ESO-defaults / nullBytePolicy drift is muted globally — do NOT chase it per-app.**
The v1 schema server-defaults `data[].remoteRef.{conversionStrategy,decodingStrategy,
metadataPolicy,nullBytePolicy}` + `target.{deletionPolicy,template.engineVersion,
template.mergePolicy}` onto stored objects; ArgoCD's client-side diff would flag them
(empty `argocd app diff` but persistent OutOfSync — check the **UI Diff tab**, not the
CLI). Neutralized fleet-wide by a global `argocd-cm`
`resource.customizations.ignoreDifferences.external-secrets.io_ExternalSecret`
(added via the `argocd-cm-patches` Job). Per-app ESO-default `ignoreDifferences`
(tailnet-ca, etc.) are now redundant.

**Migration object-state note.** Flipping a manifest to `v1` only fails the SSA apply
if the live object has `managedFields` pinned to `external-secrets.io/v1beta1` that own
`.spec.data` (then `nullBytePolicy: field not declared in schema`). Fix = reset that
object's managedFields: `kubectl patch <obj> --type=merge -p '{"metadata":{"managedFields":[{}]}}'`
then re-apply at v1. Objects with empty/v1 managedFields apply clean (most do).

**Delivery PRs (history):** spoke ESO upgrade #2339(dev)/#2341(ryzen)/#2342(promote-to-base);
v1 manifest migration #2343; global ignore #2334. End state verified: hub/dev/ryzen all
v2.4.1, all ES served at v1, all SecretSynced, 0/194 OutOfSync.

---

## M. `TS_OPERATOR_CHART_VERSION` unbound abort (ryzen recreate — hard blocker)

**Symptom.** A ryzen `--recreate` ABORTS at the Tailscale-operator helm install (right
after external-secrets) under `set -u` — `TS_OPERATOR_CHART_VERSION: unbound variable`.
Because destroy has ALREADY run by this point, ryzen is left DOWN.

**Diagnosis.** `deployment/scripts/talos-hetzner/bootstrap-spoke-cluster.sh` is a
STANDALONE script — it does NOT source `deployment/scripts/lib/common.sh`, which is where
the Tailscale-operator chart pin (`1.96.5`) lives. So `${TS_OPERATOR_CHART_VERSION}` was
never defined and the recreate died at the helm install.

**Fix.** Self-default the var next to the other version pins in
`bootstrap-spoke-cluster.sh` (~line 125):
```bash
TS_OPERATOR_CHART_VERSION="${TS_OPERATOR_CHART_VERSION:-1.96.5}"
```
(a395874dc, PR #2395). **INVARIANT:** keep this pin in lockstep with `lib/common.sh` AND
the GitOps tailscale-operator manifests; ANY variable this standalone script shares with
`common.sh` MUST be self-defaulted here (it cannot rely on `common.sh` being sourced).

**Verify.** `bootstrap-spoke-cluster.sh --recreate` runs hands-off through the
tailscale-operator helm install without an unbound-variable abort; the operator chart that
lands matches `lib/common.sh` (`1.96.5`).

---

## N. `root-ryzen` ComparisonError repo-server cold-start race (ryzen recreate)

**Symptom.** On a fresh ryzen recreate, convergence stalls ~5 min with ZERO child apps
rendered: `root-ryzen` sits in **ComparisonError** (sync=Unknown) and nothing under it
renders until a manual refresh.

**Diagnosis.** The local `argocd-application-controller` runs `root-ryzen`'s FIRST
comparison BEFORE the local `argocd-repo-server` is accepting connections (`dial :8081
connection refused`), so the app sticks in ComparisonError. The controller does NOT re-queue
an errored app for a full resync window (~5 min observed) — so convergence stalls hands-off
until that timer fires.

**Fix.** Force a clean first comparison once the local repo-server is Available
(89fd0df8b, PR #2395; both non-fatal — the resync timer would eventually heal it, this
just makes the recreate hands-off + fast):
- `enroll-ryzen-agent.sh` step 6b — wait for the repo-server, then hard-refresh:
  ```bash
  kspoke -n argocd rollout status deploy/argocd-repo-server --timeout=120s
  kubectl -n argocd annotate application root-ryzen argocd.argoproj.io/refresh=hard --overwrite
  ```
- `bootstrap-spoke-cluster.sh` step 10 — hard-refresh `root-ryzen` again so it re-compares
  against the latest `main` HEAD.

For older scripts that lack step 6b (or if you hit the stall live), unblock manually:
```bash
kubectl -n argocd annotate application root-ryzen argocd.argoproj.io/refresh=hard --overwrite
```

**Verify.** `kspoke -n argocd get application root-ryzen` leaves ComparisonError and goes
Synced/Healthy; child apps render without waiting out the ~5 min resync window.

---

## Recreate timing & destroy parallelism (validation reference)

- **ryzen** `bootstrap-spoke-cluster.sh --recreate` = **13m9s** hands-off, **64/65**
  Synced/Healthy, ZERO manual intervention (PR #2395, with §M + §N fixes in place).
- **dev** `recreate-dev.sh` = **20m32s** hands-off.
- **Parallel Hetzner destroy (dev).** `provision-spoke.sh --destroy` now deletes the N
  Hetzner servers CONCURRENTLY (no inter-server ordering) instead of sequentially
  (~18s each, ~156s for 9), mirroring the parallel create — ~156s down to ~20s
  (6cee88a70, PR #2395).

## O. Hub `root-application` cold-start: `SkipDryRunOnMissingResource` (hub recreate — hard blocker)

**Symptom.** On a fresh hub recreate the `root-application` sits `OutOfSync` with
`operationState.message = "one or more synchronization tasks are not valid. Retrying attempt #N"`,
**ZERO of the ~62 child apps render**, and the only `SyncFailed` resources are
`tailscale.com/ProxyGroup` (`could not find tailscale.com/ProxyGroup ... Make sure the CRD is installed`).

**Diagnosis.** `env/hub/hub-apps` mixes 62 child `Application`s with raw resources whose CRDs are
installed by SIBLING child apps — notably 2 `ProxyGroup`s whose CRD comes from the
`hub-tailscale-operator`/`hub-tailscale-crds` child app. ArgoCD's sync PLANNING rejects the whole
batch when a resource's GVK is unknown (`SkipDryRunOnMissingResource` was NOT set), so nothing
applies → the operator/CRD never install → permanent deadlock. (Found via the `--dry-run-clone`,
2026-06; the manual hub bootstraps masked it because CRDs were already present.)

**Fix (PR #2397).** The hub `root-application` (`recreate-hub.sh apply_root_application`, inlined)
now sets `syncOptions: [..., SkipDryRunOnMissingResource=true]` + `retry`. The first sync then applies
the child apps (installing CRDs) and skip-then-retries the CRD-dependent raw resources. NOTE: an
already-stuck sync op does NOT pick up the option — applied fresh it works first try; to unstick a
running one, delete+reapply the app (`kubectl delete app root-application --cascade=orphan` then apply).

**Related serialization (FIXED — PR #2398).** Even after the cold-start fix, hub convergence
SERIALIZED behind a sync-wave health-gate on async Tailscale-operator RAW resources in `env/hub/hub-apps`
(`root-application` msg `waiting for healthy state of Ingress/argocd-hub`): 4 in wave 0 (`argocd-hub`
Ingress, `argocd-agent-principal-tailnet` Svc, `cluster-ingress` + `k8s-api-hub` ProxyGroups) gated
waves 12-70 (~24 child apps); 2 in wave 60 gated waves 65-70. **Fix:** all 6 moved to **sync-wave 100**
(after the last child app at 70) — their source manifests in `packages/components/hub-base|hub-management`
carry `argocd.argoproj.io/sync-wave: "100"`. Nothing in waves -120..70 needs them during its own sync
(apps are in-cluster; spokes reconnect via the principal LB / kube-api VIP only AFTER convergence;
the argocd-hub UI is cosmetic), so the child apps now apply without gating and the tailnet exposure
comes up last. This is also why the `--dry-run-clone` couldn't fully converge (it can't provision the
hub's tailnet identity) — now a non-issue for the child apps.

## P. Hub "revert to original state" — etcd snapshot/restore (NOT Hetzner snapshots)

**The net (PR #2397).** `recreate-hub.sh` takes a REAL `talosctl etcd snapshot` in
`snapshot_inventory` BEFORE any `--in-place` wipe (was member-list metadata only; the constitution
requires etcd backups), saved to `~/.recreate-hub/snapshot/etcd-<ts>.snapshot` (+ `etcd-latest.snapshot`)
and pushed off-cluster via the `ETCD_SNAPSHOT_UPLOAD_CMD` hook (set it to an rclone/s3/scp to a Storage
Box — local-only otherwise). Capture validated on the clone (34 MB, hash + key count reported).

**Restore.** `recreate-hub.sh --in-place --confirm-wipe hub-cluster --restore-from <snapshot>` wires
`talosctl bootstrap --recover-from <snapshot>` into the bootstrap step — recovers the exact prior etcd
state on the same (preserved) ash servers. Validate a full restore drill on a `KEEP_CLONE=true` clone
before trusting it on the hub.

**Hetzner snapshots are NOT viable for rollback.** `hcloud server create-image` + rebuild-from-image
requires DELETING the server (servers are immutable) — that releases the ash inventory we must keep.
Reproducible baseline = the git-committed Talos machineconfig + the PINNED
`talos-cluster/main/secrets/hub-secrets.yaml` (NEVER regenerate it — orphans etcd identity).

**Stateful data is EPHEMERAL (by decision).** Observability TSDB (Mimir/Tempo/Loki/Grafana), MLflow
runs, Langfuse restart EMPTY on a hub recreate — no backup/restore. Workloads reconstitute from GitOps
+ 1Password, not their history.

## Q. Hub UI "app can't be found" on managed-agent apps — AppProject `sourceNamespaces` (PR #2400)

**Symptom.** A MANAGED-agent (dev) app lists Synced/Healthy in the hub ArgoCD UI, but CLICKING it
shows **"app can't be found."** (ryzen/autonomous apps are unaffected.) A browser hard-refresh does
NOT help — the failure is server-side.

**Diagnosis (argocd-server log is definitive).** The per-namespace detail `Get` is rejected:
`grpc.code=InvalidArgument desc = app is not allowed in project "default"`. The principal mirrors dev
apps into ns `dev` on the hub and they use `project: default`, but the hub `default` AppProject shipped
with **EMPTY `sourceNamespaces`** — so apps-in-any-namespace forbids argocd-server from serving them.
ryzen works because its apps use `ryzen-default` (`sourceNamespaces=["ryzen"]`). Check:
`kubectl -n argocd get appproject default -o jsonpath='{.spec.sourceNamespaces}'`.

**Fix (PR #2400).** Keep `default`.sourceNamespaces in sync with `principal.allowed-namespaces` — the
namespaces the principal manages (currently `dev`). `recreate-hub.sh ensure_default_project_namespaces`
(wired into `--in-place` + `--reconcile`) does this idempotently; live one-liner:
`kubectl -n argocd patch appproject default --type=merge -p '{"spec":{"sourceNamespaces":["dev"]}}'`.
ADDITIVE + safe — the argocd control-plane ns is always implicitly permitted, so the ~62 ns-`argocd`
hub apps are unaffected. Confirmed in-browser: dev-cert-manager then opens with its full resource tree.
