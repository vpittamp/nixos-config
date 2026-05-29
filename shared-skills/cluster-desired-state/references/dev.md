# DEV — desired state + path

A **disposable** Hetzner Talos spoke, fully hub-managed via a Crossplane
`TalosSpokeClusterClaim`. Shared model in `architecture.md`; recreate steps in
`../runbooks/recreate-dev.md`; deep Crossplane mechanics in the `talos-clusters`
skill; canonical doc `docs/recreate-disposable-dev.md`. Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`.

## Desired state

**Infrastructure** (Crossplane XR e.g. `dev-9677r`, claim `dev` in ns crossplane-system)
- 3 control planes (cpx41) + 6 workers (cpx51), location `hil`, networkZone `us-west`,
  network 10.0.0.0/16 subnet 10.0.1.0/24. Workers labeled
  `stacks.io/swebench-pool=dev-benchmark`. (LIVE TRUTH wins over docs that still say
  `ash`/cpx51 — verify the claim.)
- Talos `1.13.2`, Kubernetes `1.36.0`, booting Hetzner ISO id `125127`. Claim file:
  `packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/TalosSpokeClusterClaim-dev.yaml`.
- Claim SYNCED=True, READY=True. (Transient READY=False during a rebuild is BENIGN if
  it is only the group-4 `<xr>-iso-detach` Job still iterating Talos-API polls;
  spoke-bootstrap/spoke-register/pg-auth Jobs Complete.) Status has
  terraformWorkspaceReady=true, kubeconfigReady=true, 3 controlPlaneIPs + 6 workerIPs.
- All 6 workers Ready, untainted, DiskPressure=False.

**Connectivity / registration**
- argocd cluster Secret `cluster-dev` (ns argocd): labels secret-type=cluster,
  cluster-role=spoke, hub-managed=true, platform=talos, **workflow-builder=true**;
  annotation spoke-cluster=dev; **`server` = DIRECT public IP `https://<ip>:6443`**
  (dev API is reachable, so unlike ryzen it needs NO Tailscale-FQDN-SNI workaround and
  NO hub CoreDNS rewrite). managed-by=crossplane-spoke-register.
- Hub generates `spoke-dev` (XR group-8 Application) + `spoke-dev-workflow-builder`
  (spoke-workloads appset). All ~70 dev-* apps Synced/Healthy.

**AWI-free secrets** (Contract 2, GitOps via overlay)
- Hub `dev-shared-secrets` ExternalSecret (ns spoke-secrets, ~79 keys, SecretSynced)
  mirrors every KV secret dev consumes. Spoke `hub-secrets-store` CSS reads it over the
  standalone `k8s-api-hub-ingress` device (caBundle ISRG Root X1; scoped read-only SA).
  `dev-spoke-transport` app Synced/Healthy with the egress Service permanently
  OutOfSync (EXPECTED — operator rewrites `externalName`). Workload ESes repointed to
  `dev-shared-secrets` via the render script's dev-gated patches (`architecture.md` §6).

**Workloads**: workflow-builder tier healthy; db-migrate runs before db-seed;
re-running db-seed creates no duplicate SWE-bench rows
(`SEED_SWEBENCH_FIXTURES_SKIP_WHEN_ACTIVE=true`); SWE-bench Lite=300 / Verified=500;
Kimi/DeepSeek agents registered.

## Path to state (ordered)

0. **PREFLIGHT** — back up SWE-bench fixtures from the CURRENT dev BEFORE deleting
   infra (the pg_dump env-table backup/restore lives in the workflow-builder APP repo,
   not stacks). Confirm no active work and cancel/drain runs+leases+Dapr workflows. See
   `../runbooks/recovery-and-gotchas.md` "env-table SWE-bench restore".
1. **REMOVE LEGACY** — delete legacy manual HCloud servers/network/firewall; remove a
   stale hub `cluster-dev` Secret if not owned by the current claim; clean stale
   Tailscale devices/service-hosts (esp. `dev-operator` / `k8s-api-dev` VIPService).
2. **RECREATE** — apply the claim (or sync the `crossplane-hcloud-compositions` app;
   it auto-syncs from main with selfHeal):
   `kubectl --kubeconfig ~/.kube/hub-config apply -f .../TalosSpokeClusterClaim-dev.yaml`.
   To change versions, patch the **LIVE** claim (the app overwrites a git-only edit via
   selfHeal):
   `kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system patch talospokeclusterclaims.platform.pittampalli.io dev --type=merge -p '...'`.
   **ISO/k8s constraint** (see `../runbooks/recovery-and-gotchas.md`): a one-shot
   Talos 1.13.2 + k8s 1.36 claim on the 1.12.4 ISO cannot bootstrap — transiently set
   kubernetesVersion 1.35, bootstrap, then raise to 1.36.
3. **CROSSPLANE PIPELINE** (`Composition-talospokecluster.yaml`, function-sequencer
   order): group-1-network -> group-2-servers (booted from ISO) ->
   group-3-talos-workspace (provider-terraform talos provider: machine_secrets ->
   machine_configuration cp/worker -> apply -> bootstrap -> kubeconfig; writes
   connection Secret `dev-kubeconfig`) -> group-4-iso-detach (poll Talos API :50000,
   detach ISO + reset). Then onboarding: group-7-spoke-bootstrap -> group-5-spoke-register
   -> group-9-proxygroup-auth (group-6 hub-connectivity + group-8 hub-argocd are
   dependency-ordered).
   - **group-7 spoke-bootstrap** (image `mcr.microsoft.com/azure-cli:latest` — the LAST
     Azure tendril in dev provisioning, deferred): labels kube-system privileged PSA,
     deletes the ingress-nginx-admission webhook, and `az keyvault secret show` for
     TAILSCALE-OAUTH-CLIENT-ID/SECRET -> creates `tailscale/operator-oauth` Secret.
   - **group-5 spoke-register** (image `alpine/k8s:1.36.0`, no az): waits for spoke API,
     creates SA argocd-remote-manager + cluster-admin CRB, mints an 8760h token, writes
     the Contract-1 cluster Secret `cluster-dev` DIRECTLY to the hub (no KV middleman).
     Then the dev-GATED Contract-2 glue: mint scoped hub token
     (`kubectl -n spoke-secrets create token spoke-secrets-reader --duration=8760h`) ->
     inject on the spoke as Secret `external-secrets/hub-secrets-token`; insert the
     CoreDNS rewrite via **jq** (NOT awk — the azure-cli image lacks awk; switched to jq)
     after the `ready` plugin line, then rollout-restart coredns.
   - **group-9 proxygroup-auth** (`alpine/k8s:1.36.0` + tailscale TF provider): cleans
     stale ArgoCD apps / Tailscale Service `svc:k8s-api-dev` / stale devices via TS API,
     generates a pre-authorized auth key, creates ProxyGroup `k8s-api-dev`, injects
     TS_AUTHKEY.
4. **GITOPS REGISTRATION & SYNC** — group-8 creates Application `spoke-dev` (drySource
   path `packages/overlays/dev` @main -> env/spokes-dev-next -> env/spokes-dev path
   dev-apps). The spoke-workloads appset generates `spoke-dev-workflow-builder`
   (drySource `packages/components/workloads/workflow-builder-system-overlays/dev` ->
   env/spokes-dev path dev-workflow-builder-apps; gated by `workflow-builder-release`).
   dev tracks `main` (NOT inner-loop).
5. **OVERLAY CONTENT** — `packages/overlays/dev/kustomization.yaml` inherits `../talos`,
   adds `components: [../../components/spoke-tailscale-secrets]` (DEV/staging-only;
   delivers `hub-secrets-store` + egress Service, deletes azure-keyvault-store +
   azure-workload-identity + tailscale-operator-secrets/tailscale-secrets/nginx-tls-secret
   Apps), namePrefix dev-, destination.name=dev, renames ProxyGroup
   k8s-api-cluster->k8s-api-dev, INGRESS_HOST=ai401kchat.com, letsencrypt-prod.
6. **PER-CLUSTER ES PARAMETERIZATION** — run
   `scripts/gitops/render-workflow-builder-release-overlays.sh` (dev-gated repoints onto
   `dev-shared-secrets`; `--check` validates staleness). See `architecture.md` §6.
7. **VALIDATE** (below).

## Verification

```bash
C="kubectl --context dev"     # refresh the context after recreate; may point at a stale worker IP
$C get nodes -o wide                                              # 9 nodes, OS-IMAGE Talos 1.13.x (confirms install.image worked)
$C get nodes -l stacks.io/swebench-pool=dev-benchmark             # 6 workers Ready, DiskPressure=False
# db ordering + idempotency: db-migrate before db-seed; re-run db-seed -> no dup SWE-bench rows; Lite=300/Verified=500

K=~/.kube/hub-config
kubectl --kubeconfig $K -n crossplane-system get talospokeclusterclaims,job
kubectl --kubeconfig $K -n argocd get app spoke-dev spoke-dev-workflow-builder    # Synced/Healthy
kubectl --kubeconfig $K -n argocd get applications | grep '^dev-'                 # all Synced/Healthy
kubectl --kubeconfig $K -n spoke-secrets get externalsecret dev-shared-secrets    # SecretSynced
```

> From the ryzen shell, the dev public API is NOT routable (i/o timeout). Inspect dev
> via the hub ArgoCD cached resource tree, or via the break-glass `dev-kubeconfig`
> connection Secret once the XR is READY (`architecture.md` Access).

## Dev-specific gotchas (fixes in `../runbooks/recovery-and-gotchas.md`)

- **CLAIM vs DOCS divergence** — live truth wins (claim = hil + 6 cpx51). Verify the
  live claim, don't trust ash/cpx41-worker docs.
- **ISO/k8s in-place upgrade** — Hetzner public catalog only ships a Talos 1.12.4 ISO;
  the maintenance-mode node validates the requested k8s version against the RUNNING
  1.12.4. `install.image` (from talos.version) drives the INSTALLED Talos version.
  Recovery = transient kubernetesVersion 1.35 -> bootstrap -> raise to 1.36.
- **local-path PodSecurity recreate hang** — ArgoCD CreateNamespace=true creates a bare
  ns -> baseline PSA rejects local-path hostPath helper pods -> PVCs Pending ->
  stateful workloads hang. Fix via managedNamespaceMetadata (ryzen done; talos-only base
  may still be exposed — watch on dev recreate).
- **db-seed idempotency** — `Job-db-seed.yaml` PostSync hook;
  `SEED_SWEBENCH_FIXTURES_SKIP_WHEN_ACTIVE=true` so re-runs create no dup SWE-bench rows.
  db-migrate (sync-wave; render script injects a repair-schema-drift initContainer) runs
  before db-seed.
- **render-script gating** — all dev repoints are gated `[ "${cluster}" = "dev" ]` so
  staging output stays byte-identical; without the gate dev would wrongly read ryzen's
  bundle (shared manifests hardcode `ryzen-shared-secrets`).
