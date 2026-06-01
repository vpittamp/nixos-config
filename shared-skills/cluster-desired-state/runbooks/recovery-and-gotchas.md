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
