# Recreate / repair RYZEN

Bring ryzen from nothing (or repair it) to the desired state in
`../references/ryzen.md`. ryzen is **imperatively** bootstrapped (Talos-in-Docker) — no
Crossplane. Deep mechanics: `ryzen-spoke-bootstrap` skill. "Destroy and recreate as
needed" is the default posture for ryzen prototypes. Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`.

## 0. Preconditions

- Run on the ryzen host (`kubectl --context admin@ryzen`, hub via
  `kubectl --kubeconfig ~/.kube/hub-config`).
- Env: `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_CLIENT_SECRET` (the `--recreate` path can auto-load
  these from KV if unset).
- Confirm inner-loop currency you intend to deploy:
  `git -C . rev-list --count origin/inner-loop..origin/main`.

## 1. Provision (imperative bootstrap)

```bash
bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate --ts-host-passthrough
```
`--ts-host-passthrough` = hub->ryzen reaches the Talos apiserver DIRECTLY over Tailscale
via the ryzen HOST device's raw TCP serve (`tailscale serve --bg --tcp=6443`), with a
per-recreate SA bearer token + Talos CA into KV (`ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}`); the
bootstrap `--config-patch` adds `cluster.apiServer.certSANs:
[ryzen.tail286401.ts.net, 100.96.102.1]` so the apiserver's own cert verifies end-to-end
(no operator apiserver-proxy, no Let's Encrypt — `../references/architecture.md` §5). It
also restarts the host `tailscale-serve-k8s-apiserver` unit (Docker re-maps the port).
The `--recreate` path also runs the gated `cleanup-tailnet-devices.sh` to delete stale
devices (the HARD pre-recreate guarantee; the hub `tailnet-device-sweeper` CronJob is only
an offline-device hygiene backstop — see `recovery-and-gotchas.md` §F), `talosctl cluster
destroy`, and deletes the old kube context. It produces a bare Talos-Docker cluster — the
hub deploys everything else.
(Legacy `--ts-acl-mode` = the deprecated operator apiserver-proxy + impersonation path;
do not use it for ryzen.)

## 2. GitOps registration (Contract 1, already committed)

`packages/components/hub-management/manifests/spoke-credentials/ExternalSecret-cluster-ryzen.yaml`
materializes `cluster-ryzen` from KV `ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}` (the static
`Secret-cluster-ryzen.yaml` was deleted, PR #2308). The bootstrap `--ts-host-passthrough`
register-spoke step mints those KV values per-recreate, so a fresh recreate refreshes the
registration automatically. The hub-spoke-appsets spoke-clusters-appset materializes
`spoke-ryzen` (`targetRevision=inner-loop`). Nothing to do unless the ExternalSecret /
appset changed on `main` — if so, advance the hub: merge the `env/hub-next -> env/hub`
Promoter PR (`gitops` skill).

## 3. Secret transport (Contract 2 — spoke side is IMPERATIVE for ryzen)

Applied by `deployment/scripts/lib/spoke-transport-bootstrap.sh` (invoked from the
bootstrap script) using `deployment/manifests/spoke-transport/`:
- `hub-secrets-store` CSS (caBundle ISRG Root X1) + egress Service.
- `external-secrets/hub-secrets-token` Secret (scoped SA bearer token).
- **Spoke** CoreDNS rewrite `k8s-api-hub-ingress... -> k8s-api-hub-egress...`
  (re-applied every recreate — Talos resets the Corefile), then rollout-restart coredns.

The hub side (mirror ExternalSecret + RBAC + Ingress device + ACL grant) is GitOps and
should already be live (`../references/hub.md` step 7).

## 4. Hub -> ryzen connectivity (Tailscale host TCP passthrough)

The durable path is a raw TCP passthrough on the ryzen HOST device
(`ryzen.tail286401.ts.net`, `tailscale serve --bg --tcp=6443`) — the hub does a full TLS
verify against the Talos CA, no operator apiserver-proxy / no Let's Encrypt
(`../references/architecture.md` §5). Mostly handled by the bootstrap:
- `--ts-host-passthrough` mints the SA token + Talos CA into KV
  (`ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}`) and restarts the host
  `tailscale-serve-k8s-apiserver` unit. If the serve is not pointing at the current
  Docker apiserver port after a recreate: `sudo systemctl restart
  tailscale-serve-k8s-apiserver` on the ryzen host (or re-run bootstrap).
- The hub CoreDNS rewrite (`CronJob-coredns-spoke-rewrites`) and `ryzen-api-egress`
  Service (`tailnet-fqdn: ryzen.tail286401.ts.net`, port 6443) are committed/self-healing.

Verify by confirming the materialized cluster-Secret `server` is
`https://ryzen.tail286401.ts.net:6443` and `ryzen-*` apps are Synced; optionally full-verify
with a real-TLS `kubectl --server=... --certificate-authority=<Talos CA> --token=<SA> get
nodes` (no `--insecure`). The old SNI `curl --connect-to` check is obsolete.

## 5. Deploy content (advance inner-loop)

ryzen NEVER reads `main`. To push main's content to ryzen:
```bash
git -C /home/vpittamp/repos/PittampalliOrg/stacks/main push origin origin/main:refs/heads/inner-loop
```
The hydrator re-dispatches drySHA -> renders `packages/overlays/ryzen` -> pushes
`env/spokes-ryzen`; `ryzen-*` apps reconcile from path `ryzen-apps`. A frozen ryzen is
almost never the empty-`drySource.kustomize` hydrator-stall bug (spoke-ryzen is
path-based) — check `targetRevision=inner-loop` and inner-loop freshness first.

## 6. Watch for the ryzen gotchas

- **RFC6902 op:add clobber** — the overlay tailscale-operator block must carry BOTH
  PROXY_IMAGE=v1.92.4 AND the `gitea-tailscale-backend` Service `$patch:delete`
  (`recovery-and-gotchas.md` §D).
- **kueue ClientSideApplyMigration=false** stays in the ryzen overlay
  (`recovery-and-gotchas.md` §C).
- Profile fit: Contour+Kourier (no nginx), no `gitea` ns, no Azure on the spoke.

## 7. Verify

Run the full block in `../references/ryzen.md` "Verification". Pass = Talos v1.13.2 /
k8s v1.36.0, contour+kourier (zero nginx), ns gitea NotFound, `hub-secrets-store`
Ready=True, all `ryzen-*` apps Synced/Healthy on the hub, cluster-ryzen server =
`https://ryzen.tail286401.ts.net:6443` (`insecure:false` + caData), inner-loop count 0.

**Web exposure post-sync** (Contract 3, `../references/architecture.md` §7). Confirm the
CA/wildcard/sidecar chain comes up: the `tailnet-dev-ca` CA `ClusterIssuer` Ready -> the
`*.tail286401.ts.net` wildcard Certificate issued -> the workflow-builder `tls-terminator`
sidecar serves :443, so `https://workflow-builder-ryzen.tail286401.ts.net` loads in a REAL
browser (NOT bare curl — 502 buffer gotcha, `recovery-and-gotchas.md` §I). NO Let's Encrypt.
```bash
C="kubectl --context admin@ryzen"
$C get clusterissuer tailnet-dev-ca                                       # Ready=True
$C -n workflow-builder get certificate                                    # tailnet wildcard Ready=True
$C -n workflow-builder get svc workflow-builder-tailnet -o wide           # type LoadBalancer (loadBalancerClass tailscale), EXTERNAL-IP assigned
```

## 8. Post-bootstrap data migrations (optional)

Some ryzen workloads want data restored from dev (e.g. `environment_image_builds`):
```bash
kubectl --context dev exec -n workflow-builder postgresql-0 -- pg_dump -U postgres -d workflow_builder \
  -t environment_image_builds --data-only --column-inserts > /tmp/eib.sql
kubectl --context admin@ryzen cp /tmp/eib.sql workflow-builder/postgresql-0:/tmp/eib.sql
kubectl --context admin@ryzen exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -f /tmp/eib.sql
```
