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
bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate --ts-acl-mode
```
`--ts-acl-mode` = Tailscale-ACL hub<->spoke (no Azure bearer token, no JWKS+AAD wait).
The `--recreate` path also runs `cleanup-tailnet-devices.sh` to delete stale devices
(see `recovery-and-gotchas.md` §F), `talosctl cluster destroy`, and deletes the old kube
context. It produces a bare Talos-Docker cluster with ONLY the Tailscale operator,
ProxyGroup/ProxyClass, and hub-spoke SA+CRB — the hub deploys everything else.

## 2. GitOps registration (Contract 1, already committed)

The static `packages/components/hub-management/manifests/spoke-credentials/Secret-cluster-ryzen.yaml`
is GitOps-delivered. The hub-spoke-appsets spoke-clusters-appset materializes
`spoke-ryzen` (`targetRevision=inner-loop`). Nothing to do unless the cluster Secret /
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

## 4. Hub -> ryzen connectivity (SNI/CoreDNS)

Already committed (cluster-Secret `server`, hub CoreDNS rewrite, `ryzen-api-egress`
Service, operator hostname). After a recreate, **delete the stale duplicate
`ryzen-operator` device** via the TS API or the operator suffixes `-1`
(`recovery-and-gotchas.md` §F). Verify the SNI with `curl --connect-to` -> HTTP 200
(`../references/architecture.md` §5).

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
`https://ryzen-operator.tail286401.ts.net`, inner-loop count 0.

## 8. Post-bootstrap data migrations (optional)

Some ryzen workloads want data restored from dev (e.g. `environment_image_builds`):
```bash
kubectl --context dev exec -n workflow-builder postgresql-0 -- pg_dump -U postgres -d workflow_builder \
  -t environment_image_builds --data-only --column-inserts > /tmp/eib.sql
kubectl --context admin@ryzen cp /tmp/eib.sql workflow-builder/postgresql-0:/tmp/eib.sql
kubectl --context admin@ryzen exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -f /tmp/eib.sql
```
