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
- Confirm `main` is at the revision you intend to deploy (ryzen reconciles `overlays/ryzen`
  @ `main` directly): `git -C . rev-parse origin/main`.

## 1. Provision (imperative bootstrap)

```bash
bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate
```
The `--recreate` path provisions a bare Talos-Docker cluster, then ENROLLS the autonomous
argocd-agent via `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh` (the canonical
registration — see §2). It also runs the gated `cleanup-tailnet-devices.sh` to delete stale
devices (the HARD pre-recreate guarantee; the hub `tailnet-device-sweeper` CronJob is only
an offline-device hygiene backstop — see `recovery-and-gotchas.md` §F), `talosctl cluster
destroy`, and deletes the old kube context. The hub principal aggregates status; ryzen's
local controller deploys everything else.

`bootstrap-spoke-cluster.sh` is **standalone** — it does NOT source
`deployment/scripts/lib/common.sh`, where the Tailscale-operator chart pin lives. So
`TS_OPERATOR_CHART_VERSION` now **self-defaults to 1.96.5** at the version-pin block (~line
125): `TS_OPERATOR_CHART_VERSION="${TS_OPERATOR_CHART_VERSION:-1.96.5}"` (PR #2395, Fix 1).
This matters because before the self-default the var was unbound under `set -u` and the
recreate ABORTED at the `tailscale-operator` helm install (right after external-secrets) —
*after* destroy had already run, leaving ryzen DOWN. INVARIANT: keep the pin in lockstep with
`lib/common.sh` + the GitOps tailscale-operator manifests; any var this standalone script
shares with `common.sh` MUST be self-defaulted. See `recovery-and-gotchas.md` for the
operator-version gotcha.
(`register-spoke-with-hub.sh` is RETIRED and NO LONGER called by the bootstrap. The
`--ts-acl-mode` / `--ts-host-passthrough` flags are VESTIGIAL — still parsed for compat but
ignored; the agent-mapping registration does not depend on either. The ryzen HOST device's
raw TCP serve `tailscale serve --bg --tcp=6443` + `apiServer.certSANs` still exist, but ONLY
to serve Headlamp's kube-API reach — `../references/architecture.md` §5 — NOT ArgoCD sync.)

## 2. GitOps registration (Contract 1 — argocd-agent mapping)

The CANONICAL registration is the `cluster-ryzen` AGENT MAPPING Secret on the hub, created
by `argocd-agentctl agent create ryzen` (run by `enroll-ryzen-agent.sh`):
`server=https://argocd-agent-resource-proxy:9090?agentName=ryzen` with embedded mTLS
certData/keyData/caData and **no bearerToken** (`managed-by: argocd-agent`,
`argocd-agent.argoproj-labs.io/agent-name=ryzen`). `enroll-ryzen-agent.sh` mints the agent
mTLS cert, applies the
`packages/components/hub-management/manifests/ryzen-agent-bootstrap` kustomize component
(agent-autonomous bundle + params `mode=autonomous` + `cluster-ryzen-local` alias +
`stacks-repo-read` + the cert ExternalSecrets + the `root-ryzen` app-of-apps), runs
`argocd-agentctl agent create ryzen`, stages the Headlamp Secret, and hard-refreshes `root-ryzen`.

After enroll, **step 6b** waits for the local repo-server then hard-refreshes `root-ryzen`
(PR #2395, Fix 2): `kspoke -n argocd rollout status deploy/argocd-repo-server --timeout=120s`
then `kubectl -n argocd annotate application root-ryzen
argocd.argoproj.io/refresh=hard --overwrite`. On a fresh recreate the local
argocd-application-controller runs `root-ryzen`'s FIRST comparison before the local
argocd-repo-server is accepting connections (dial `:8081` connection refused) → `root-ryzen`
sticks in `ComparisonError` (sync=Unknown) and the controller does NOT re-queue the errored
app for a full resync window (~5min observed) → convergence stalls with ZERO child apps
rendered until a manual refresh. The step forces a clean first comparison once the repo-server
is Available; non-fatal (the resync timer would eventually heal it — this makes the recreate
hands-off + fast). `bootstrap-spoke-cluster.sh` step 10 hard-refreshes `root-ryzen` **again**
(re-compare vs the latest `main` HEAD). See `recovery-and-gotchas.md`
for the cold-start gotcha.

**Step 5b** re-stages the `headlamp-cluster-ryzen` Secret (fresh kube-API endpoint +
read-only SA token + CA, label `headlamp.dev/cluster=true`) AND restarts hub Headlamp
(PR #2395, Fix 3): `kubectl -n headlamp rollout restart deploy/hub-headlamp
deploy/hub-headlamp-embedded` on the hub (guarded on deploy existence, non-fatal — Headlamp
is off the critical path). The hub Headlamp builds its kubeconfig ONLY in its
generate-kubeconfig init-container at pod start, so a pod predating the recreate keeps serving
the OLD spoke endpoint/CA/token and cannot auth to the rebuilt cluster — the staged Secret is
inert without the restart.

The old `ExternalSecret-cluster-ryzen.yaml` was removed. ArgoCD uses the agent
mapping, while Headlamp uses the dedicated `headlamp-cluster-ryzen` Secret that
enrollment stages from the host-passthrough endpoint and a read-only service
account. If the declarative bootstrap changes, merge it to `main` and observe
the hub `env/hub-next` -> `env/hub` auto-merge; do not recreate the old Secret.

## 3. Secret transport (Contract 2 — spoke side is IMPERATIVE for ryzen)

Applied by `deployment/scripts/lib/spoke-transport-bootstrap.sh` (invoked from the
bootstrap script) using `deployment/manifests/spoke-transport/`:
- `hub-secrets-store` CSS (caBundle ISRG Root X1) + egress Service.
- `external-secrets/hub-secrets-token` Secret (scoped SA bearer token).
- **Spoke** CoreDNS rewrite `k8s-api-hub-ingress... -> k8s-api-hub-egress...`
  (re-applied every recreate — Talos resets the Corefile), then rollout-restart coredns.

The hub side (mirror ExternalSecret + RBAC + Ingress device + ACL grant) is GitOps and
should already be live (`../references/hub.md` step 7).

## 4. Hub -> ryzen connectivity (Headlamp-only — NOT the sync path)

ArgoCD sync NO LONGER rides a hub->ryzen kube connection — ryzen's local controller
reconciles its own apps (autonomous agent, §2). The hub->ryzen kube-API reach now exists
ONLY for **Headlamp**: a raw TCP passthrough on the ryzen HOST device
(`ryzen.tail286401.ts.net`, `tailscale serve --bg --tcp=6443`), full TLS verify against the
Talos CA, no operator apiserver-proxy / no Let's Encrypt (`../references/architecture.md`
§5). If Headlamp can't reach ryzen after a recreate:
- The host serve may be pointing at a stale Docker apiserver port: `sudo systemctl restart
  tailscale-serve-k8s-apiserver` on the ryzen host.
- The hub CoreDNS rewrite (`CronJob-coredns-spoke-rewrites`) and `ryzen-api-egress`
  Service (`tailnet-fqdn: ryzen.tail286401.ts.net`, port 6443) are committed/self-healing.

Verify the agent path by confirming `cluster-ryzen` is the agent mapping
(`server=https://argocd-agent-resource-proxy:9090?agentName=ryzen`) and `ryzen-*` apps are
Synced via the principal. Headlamp reach (optional) is a real-TLS
`kubectl --server=https://ryzen.tail286401.ts.net:6443 --certificate-authority=<Talos CA>
--token=<SA> get nodes` (no `--insecure`). The old SNI `curl --connect-to` check is obsolete.

## 5. Deploy content (reconciles main directly)

ryzen reads `main` DIRECTLY via its local ArgoCD (`root-ryzen` @ `main`). To push main's
content to ryzen, just commit/merge to `main`; force an immediate re-compare with:
```bash
deployment/scripts/ryzen-sync.sh   # hard-refreshes root-ryzen (~20-35s converge)
```
`root-ryzen` re-renders `packages/overlays/ryzen` @ `main` and the `ryzen-*` apps reconcile.
There is NO `inner-loop` branch (retired), NO source-hydrator, NO `env/spokes-ryzen`, NO
Promoter on the ryzen lane — so the empty-`drySource.kustomize` hydrator-stall bug never
applies to ryzen. If frozen, hard-refresh `root-ryzen`; don't look for an `inner-loop` advance.

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
Ready=True, all `ryzen-*` apps Synced/Healthy on ryzen's LOCAL ArgoCD, cluster-ryzen is the agent
mapping (`server=https://argocd-agent-resource-proxy:9090?agentName=ryzen`, no bearerToken),
and `root-ryzen`'s synced revision matches `origin/main`.

Hands-off validation result (PR #2395): `bootstrap-spoke-cluster.sh --recreate` =
**13m9s hands-off, 64/65 Synced/Healthy, ZERO manual intervention**.

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
