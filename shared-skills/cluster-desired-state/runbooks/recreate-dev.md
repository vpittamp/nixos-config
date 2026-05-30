# Recreate DEV (disposable Crossplane spoke)

Bring dev from nothing (or rebuild it) to the desired state in `../references/dev.md`.
dev is **Crossplane-provisioned** on Hetzner via a `TalosSpokeClusterClaim`. Deep
mechanics: `talos-clusters` skill; canonical doc `docs/recreate-disposable-dev.md`.
Paths relative to `/home/vpittamp/repos/PittampalliOrg/stacks/main`.

## 0. Preflight (BEFORE destroying — data lives in the disposable cluster)

Confirm no active work and back up SWE-bench fixtures (`recovery-and-gotchas.md` §E):
```bash
kubectl --context dev -n workflow-builder exec postgresql-0 -- psql -U postgres -d workflow_builder \
  -c "select status,count(*) from benchmark_runs group by status; select status,count(*) from benchmark_resource_leases group by status;"
kubectl --context dev exec -n workflow-builder postgresql-0 -- pg_dump -U postgres -d workflow_builder \
  -t environment_image_builds --data-only --column-inserts > /tmp/eib.sql
```
Cancel/drain active runs + leases + Dapr workflows. Use the `evaluations` skill to
confirm nothing is mid-benchmark.

## 1. Remove legacy

Delete legacy manual HCloud servers/network/firewall; remove a stale hub `cluster-dev`
Secret if not owned by the current claim; clean stale Tailscale devices/service-hosts
(esp. `dev-operator` / `k8s-api-dev` VIPService) — `recovery-and-gotchas.md` §F. The hard
pre-recreate guarantee is the gated `deployment/scripts/cleanup-tailnet-devices.sh` (for
dev, group-9 proxygroup-auth also cleans `svc:k8s-api-dev` + stale devices); the hub
`tailnet-device-sweeper` CronJob is only an offline-device hygiene backstop.

## 2. Recreate (apply the claim)

```bash
K=~/.kube/hub-config
kubectl --kubeconfig $K apply -f \
  packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/TalosSpokeClusterClaim-dev.yaml
# (or just let the crossplane-hcloud-compositions app self-heal from main)
```

> **ISO/k8s constraint** (`recovery-and-gotchas.md` §A): a one-shot Talos 1.13.2 + k8s
> 1.36 claim on the Hetzner 1.12.4 ISO can't bootstrap. Transiently lower the LIVE claim
> to k8s 1.35, let it bootstrap, then raise to 1.36. Patch the **live** claim (selfHeal
> overwrites git-only edits).

## 3. Crossplane pipeline (automatic, function-sequencer order)

group-1-network -> group-2-servers (ISO 125127) -> group-3-talos-workspace (TF talos
provider: secrets -> config -> apply -> bootstrap -> kubeconfig; writes `dev-kubeconfig`)
-> group-4-iso-detach. Then onboarding group-7-spoke-bootstrap -> group-5-spoke-register
-> group-9-proxygroup-auth. Notable:
- group-7 still uses `mcr.microsoft.com/azure-cli:latest` (`az keyvault` for the
  Tailscale operator OAuth — the last Azure tendril, deferred).
- group-5 uses `alpine/k8s:1.36.0` (no az); writes `cluster-dev` (server = direct public
  IP `:6443`) directly to the hub, then the dev-gated transport glue (scoped hub token ->
  spoke `hub-secrets-token`; CoreDNS rewrite via **jq**, not awk).
- group-9 cleans `svc:k8s-api-dev` + stale devices, creates ProxyGroup `k8s-api-dev`.

Watch: a transient claim `READY=False` is BENIGN if only the group-4 `<xr>-iso-detach`
Job is still polling and the other onboarding Jobs are Complete.

## 4. GitOps registration & sync

group-8 creates `spoke-dev` (drySource `packages/overlays/dev` @main -> env/spokes-dev).
The spoke-workloads appset adds `spoke-dev-workflow-builder`. dev tracks `main` (NOT
inner-loop). Merge the `env/spokes-dev-next -> env/spokes-dev` Promoter PR if it doesn't
auto-advance (`gitops` skill).

## 5. Per-cluster ExternalSecret parameterization

Regenerate the dev overlay's ES repoints onto `dev-shared-secrets`:
```bash
scripts/gitops/render-workflow-builder-release-overlays.sh          # writes workflow-builder-system-overlays/dev
scripts/gitops/render-workflow-builder-release-overlays.sh --check  # CI staleness gate
```
All dev repoints are gated `[ "${cluster}" = "dev" ]` (`../references/architecture.md` §6).

## 6. Watch for the dev gotchas

- **local-path PodSecurity recreate hang** — CreateNamespace=true bare ns -> baseline PSA
  rejects local-path hostPath helper -> PVCs Pending. Fix via managedNamespaceMetadata
  (`recovery-and-gotchas.md` E/dev refs). Watch on every dev recreate (talos base may
  still be exposed).
- **CLAIM vs DOCS divergence** — live truth wins (hil + 6 cpx51). Verify the live claim.

## 7. Restore data + verify

```bash
kubectl --context dev cp /tmp/eib.sql workflow-builder/postgresql-0:/tmp/eib.sql
kubectl --context dev exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -f /tmp/eib.sql
```
Run the full block in `../references/dev.md` "Verification". Pass = 9 nodes Talos 1.13.x,
6 workers Ready DiskPressure=False, db-migrate-before-db-seed, no dup SWE-bench rows,
Lite=300/Verified=500, `spoke-dev` + all `dev-*` apps Synced/Healthy, `dev-shared-secrets`
SecretSynced. Gate any benchmark ramp with the `evaluations` skill's capacity diagnostics.

**Web exposure post-sync** (Contract 3, `../references/architecture.md` §7). Once the
spoke syncs, confirm the CA/wildcard/sidecar chain comes up: the `tailnet-dev-ca` CA
`ClusterIssuer` Ready -> the `*.tail286401.ts.net` wildcard Certificate issued (Ready) ->
the workflow-builder `tls-terminator` sidecar serves :443. Then `https://workflow-builder-dev.tail286401.ts.net`
loads in a REAL browser (NOT bare curl — see the 502 buffer gotcha, `recovery-and-gotchas.md` §I).
```bash
kubectl --context dev get clusterissuer tailnet-dev-ca                              # Ready=True (NO Let's Encrypt)
kubectl --context dev -n workflow-builder get certificate                           # tailnet wildcard Ready=True
kubectl --context dev -n workflow-builder get svc workflow-builder-tailnet -o wide  # type LoadBalancer (loadBalancerClass tailscale), EXTERNAL-IP assigned
```
