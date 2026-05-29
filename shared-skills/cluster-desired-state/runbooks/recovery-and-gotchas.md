# Recovery runbooks & fleet-wide gotchas

Failure modes discovered/validated across hub/ryzen/dev. Each is **Symptom ->
Diagnosis -> Fix -> Verify**. Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`. For ArgoCD/Promoter recovery
mechanics defer to the `gitops` skill; for Crossplane spoke specifics, `talos-clusters`.

---

## A. Talos ISO vs Kubernetes version — in-place upgrade (dev/staging recreate)

**Symptom.** A fresh Crossplane claim of Talos 1.13.2 + k8s 1.36 never bootstraps;
the maintenance-mode node rejects the requested Kubernetes version.

**Diagnosis.** Hetzner's public catalog has ONLY a Talos **1.12.4** ISO (no
custom-ISO upload API; a custom ISO = a Hetzner support ticket with a direct
`factory.talos.dev` URL). `install.image` (derived from `talos.version` inside the TF
`talos_machine_configuration` data source — the Composition module sets only
`install.disk=/dev/sda` + `wipe=true`, NOT `install.image` directly) governs the
INSTALLED Talos version even when booting the 1.12.4 ISO. BUT the maintenance-mode node
validates the REQUESTED k8s version against the RUNNING (1.12.4) Talos. So 1.36 on a
1.12.4 ISO can't one-shot.

**Fix (supported in-place path).** Patch the LIVE claim to transiently lower k8s while
keeping the newer Talos version (so `install.image` still installs Talos 1.13.x):
```bash
K=~/.kube/hub-config
# 1. bootstrap on k8s 1.35 (keep talos version 1.13.2)
kubectl --kubeconfig $K -n crossplane-system patch talospokeclusterclaims.platform.pittampalli.io dev \
  --type=merge -p '{"spec":{"parameters":{"talos":{"kubernetesVersion":"1.35.0"}}}}'
# ...wait for bootstrap / nodes Ready...
# 2. raise to 1.36
kubectl --kubeconfig $K -n crossplane-system patch talospokeclusterclaims.platform.pittampalli.io dev \
  --type=merge -p '{"spec":{"parameters":{"talos":{"kubernetesVersion":"1.36.0"}}}}'
```
`crossplane-hcloud-compositions` auto-syncs from main with selfHeal — patch the **live**
claim; a git-only edit alone won't stick if the app overwrites it.

**Verify.** `kubectl --context dev get nodes -o wide` — OS-IMAGE shows Talos 1.13.x and
nodes Ready on the target k8s.

---

## B. hub -> spoke ArgoCD apiserver-proxy SNI mismatch (ryzen / Tailscale-proxy spokes)

**Symptom.** `spoke-ryzen` (or any Tailscale-apiserver-proxy spoke) can't connect; TLS
SNI/cert errors at the operator proxy; "x509"/handshake failures in the ArgoCD
application-controller logs.

**Diagnosis.** The Tailscale operator apiserver-proxy (v1.92.4) STRICTLY validates the
wire SNI == its own hostname (`<spoke>-operator.tail286401.ts.net`). ArgoCD does NOT
apply `tlsClientConfig.serverName` as the wire SNI — it sends the **server-URL host** as
SNI (verified: even with `serverName` + `caData`, the server-URL host is still sent).

**Fix.**
1. Set the cluster Secret `server` to the operator FQDN so the SNI matches:
   `server: https://<spoke>-operator.tail286401.ts.net` (config: `insecure:true`,
   `serverName:<spoke>-operator...`, `bearerToken:"unused"`).
2. Add a **HUB** CoreDNS rewrite so the name resolves to the in-cluster egress while the
   SNI stays correct:
   `rewrite name exact <spoke>-operator.tail286401.ts.net <spoke>-api-egress.tailscale.svc.cluster.local`.
   The `<spoke>-api-egress` ExternalName Service (ns tailscale, annotation
   `tailscale.com/tailnet-fqdn: <spoke>-operator...`) is defined inline in
   `packages/components/hub-management/apps/headlamp.yaml` extraManifests.
3. Spoke operator must set `OPERATOR_HOSTNAME=<spoke>-operator` + `APISERVER_PROXY=true`
   (`packages/components/tailscale-serve/manifests/tailscale-operator/Deployment-operator.yaml`).

**Verify.**
```bash
curl -k --connect-to <spoke>-operator.tail286401.ts.net:443:<egress>:443 \
  https://<spoke>-operator.tail286401.ts.net/version    # expect HTTP 200
kubectl --kubeconfig ~/.kube/hub-config -n argocd get application spoke-<spoke>   # Synced/Healthy
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
devices; for ryzen, `cleanup-tailnet-devices.sh` runs in the `--recreate` path. Then
patch/restart the hub egress Service or the operator StatefulSet pod so it re-resolves.

**Verify.** The canonical hostname (no `-1` suffix) is present; the SNI curl in §B
returns HTTP 200; no stale offline devices remain in the tailnet admin list. See the
`talos-clusters` skill `runbooks/tailscale-name-recovery.md` and the `gitops` skill for
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

## H. Flannel `--iface` after Talos upgrade (hub)

**Symptom.** Cross-node pod networking silently breaks on the hub after a Talos upgrade.

**Diagnosis.** Hetzner blocks VXLAN over the public IP; the kube-flannel DaemonSet must
pin `--iface=enp7s0`, and a Talos upgrade resets it.

**Fix.** Re-apply the kube-flannel DaemonSet `--iface=enp7s0` patch after every hub Talos
upgrade (post-provision manual fix, `docs/hub-cluster-setup.md`).

**Verify.** Cross-node pod-to-pod connectivity; flannel pods Ready on all 5 nodes.
