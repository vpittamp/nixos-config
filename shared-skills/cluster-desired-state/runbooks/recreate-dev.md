# Recreate DEV (disposable scripted spoke)

Bring dev from nothing (or rebuild it) to the desired state in `../references/dev.md`.
dev is **script-provisioned + script-enrolled** on Hetzner — the SAME imperative path as
hub & ryzen (Crossplane was REMOVED in Phase D; no `TalosSpokeClusterClaim`, no
Composition, no group-N pipeline). The three scripts:
`talos-hetzner/provision-spoke.sh` -> `talos-hetzner/bootstrap-spoke-deps.sh` ->
`argocd-agent/enroll-dev-agent.sh`. Deep Tailscale + cert detail:
`../references/tailscale-and-certs.md`. Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`.

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

Destroy the prior dev infra and clean stale identity:
```bash
CLUSTER_NAME=dev deployment/scripts/talos-hetzner/provision-spoke.sh --destroy
```
This removes the dev Hetzner servers/network/firewall. `--destroy` now deletes the N
Hetzner servers **in parallel** (no inter-server ordering), mirroring the parallel create
(PR #2395 Fix 4: ~156s -> ~20s for 9 servers; was ~18s each sequential). Then remove a stale hub
`cluster-dev` Secret if it is not the current agent mapping, and clean stale Tailscale
devices (esp. the `dev-operator` proxy device) via the TS API — the stale `-N` device
cleanup pattern is documented in `../references/tailscale-and-certs.md`. The gated
`deployment/scripts/cleanup-tailnet-devices.sh` is the hard pre-recreate guarantee; the hub
`tailnet-device-sweeper` CronJob is only an offline-device hygiene backstop.

## 2. Provision (Hetzner + Talos)

```bash
CLUSTER_NAME=dev deployment/scripts/talos-hetzner/provision-spoke.sh
```
Boots the public Talos 1.12.4 ISO (Hetzner id 125127), `apply-config` installs Talos 1.13.2
to disk (disk-first boot; ISO detached as cleanup), installs Cilium CNI, then in-place
`upgrade-k8s` 1.35 -> 1.36. Output: a healthy bare Talos cluster + kubeconfig at
`/tmp/talos-spoke-dev/kubeconfig`. Requires `hcloud` (target-project API token), `talosctl`,
`kubectl`, `jq`.

> **ISO/k8s constraint** (`recovery-and-gotchas.md` §A): the 1.12.4 ISO rejects k8s 1.36 at
> apply-config time ("version of Kubernetes 1.36.0 is too new to be used with Talos
> 1.12.4"). The script bootstraps at `BOOTSTRAP_K8S_VERSION=1.35.0`, then once the installed
> Talos 1.13.2 is running it `upgrade-k8s` to `K8S_VERSION=1.36.0`. `install.image` (from
> `TALOS_VERSION`) drives the installed Talos line.

## 3. Bootstrap deps + spoke->hub transport

```bash
CLUSTER_NAME=dev deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh
# needs TS_OAUTH_CLIENT_ID / TS_OAUTH_CLIENT_SECRET (1Password or hub Key Vault)
```
Installs the minimal seed the agent needs before it can enroll:
- **cert-manager v1.14.4** (Tailscale operator dep).
- **ESO 2.4.1** controller-only (`webhook.create=false certController.create=false`,
  `unsafeServeV1Beta1=true`).
- **Tailscale operator** with `operatorConfig.hostname=dev-operator` (the per-cluster
  override — without it the operator collides with `ryzen-operator` on the tailnet; see
  `../references/tailscale-and-certs.md`).
- **spoke->hub ESO transport** via `lib/spoke-transport-bootstrap.sh --apply-manifests
  --wait-ready`: the `hub-secrets-store` ClusterSecretStore + egress Service + CoreDNS
  rewrite + scoped hub token, gated on the store going Ready (proves the spoke can read hub
  `spoke-secrets` over Tailscale). This transport later delivers the agent's mTLS cert +
  repo cred — KEEP it, never remove.

It also pre-labels privileged namespaces, but that is now a **REDUNDANT backstop**:
privileged PodSecurity is PRIMARILY declarative (managedNamespaceMetadata on the
CreateNamespace Helm apps + privileged-labelled Namespace manifests, PR #2359). The loop
only removes the first-sync ordering window for the sync-wave -100 local-path-provisioner.

## 4. Enroll the managed agent

```bash
deployment/scripts/argocd-agent/enroll-dev-agent.sh dev
```
Idempotent + re-runnable. It:
1. Asserts the hub principal is live and `principal.allowed-namespaces` includes `dev`
   (warns otherwise — managed apps in ns `dev` won't be pushed without it).
2. **Mints the agent mTLS cert on the hub** (holding ns) and stages it to
   `spoke-secrets/dev-agent-cert` for **ESO delivery** (so no hub->spoke kube-API reach is
   needed — the agent dials the principal OUTBOUND over tailnet mTLS, 8443).
3. Renders + applies the spoke-side agent-managed bundle; waits for ESO to materialize the
   cert + the `argocd-agent-agent` rollout.
4. **Creates the `cluster-dev` AGENT MAPPING Secret on the hub**
   (`server=https://argocd-agent-resource-proxy:9090?agentName=dev` with embedded mTLS,
   **NO bearerToken**) via `argocd-agentctl agent create`.
5. Restarts the agent so it connects + re-pushes app statuses (a fresh agent's initial
   status push is often incomplete; the script waits for the hub-pushed apps to appear in
   ns `dev`, then re-restarts).
6. **Stages the hub Headlamp read Secret** `headlamp-cluster-dev` (dev's PUBLIC API
   endpoint + read-only SA token + CA, label `headlamp.dev/cluster=true`) — Headlamp uses
   this, NOT the agent cluster mapping (which has no bearerToken post-cutover). **Step 5b
   then rolls `deploy/hub-headlamp{,-embedded}` on the hub** so Headlamp rebuilds its
   kubeconfig for the rebuilt dev cluster (PR #2395 Fix 3). The hub Headlamp builds its
   kubeconfig ONLY in its `generate-kubeconfig` init-container at pod start, so a pod
   predating the recreate keeps serving the OLD dev endpoint/CA/token and can't auth to the
   rebuilt cluster — the staged Secret alone is inert. The rollout is guarded on deploy
   existence and non-fatal (Headlamp is off the critical path). Full detail:
   `recovery-and-gotchas.md`.

The AppProject, principal-egress Service, and CoreDNS principal rewrite come from the agent
bootstrap kustomize (`packages/components/hub-management/manifests/dev-agent-bootstrap`).

## 5. GitOps sync (principal pushes the dev apps)

Once enrolled, the hub principal PUSHES the dev Application objects (authored in hub ns
`dev`) to the dev agent, whose local controller reconciles them. GitOps delivery is
source-hydrator + GitOps Promoter: `overlays/dev` -> `env/spokes-dev-next` -> (AUTO-promote,
spoke lanes auto-merge) -> `env/spokes-dev` -> root-application. dev's workflow-builder apps
come via the `spoke-dev-workflow-builder` bridge appset (drySource
`workflow-builder-system-overlays/dev`). dev tracks `main` (NOT inner-loop). If the spoke
lane doesn't auto-advance, merge the `env/spokes-dev-next -> env/spokes-dev` Promoter PR
(`gitops` skill).

## 6. Per-cluster ExternalSecret parameterization

Regenerate the dev overlay's ES repoints onto `dev-shared-secrets`:
```bash
scripts/gitops/render-workflow-builder-release-overlays.sh          # writes workflow-builder-system-overlays/dev
scripts/gitops/render-workflow-builder-release-overlays.sh --check  # CI staleness gate
```
All dev repoints are gated `[ "${cluster}" = "dev" ]` (`../references/architecture.md` §6).

## 7. Watch for the dev gotchas

- **"Unknown operation status" on the hub** — architectural + BENIGN. Sync OPERATIONS run
  on dev's local controller; the hub principal sees sync + health but not operation
  lifecycle.
- **local-path PodSecurity recreate hang** — historically CreateNamespace=true bare ns ->
  baseline PSA rejects local-path hostPath helper -> PVCs Pending. Now PRIMARILY fixed
  declaratively (managedNamespaceMetadata + privileged Namespace manifests, PR #2359);
  `bootstrap-spoke-deps.sh`'s pre-label loop is only a redundant fast-path
  (`recovery-and-gotchas.md` E/dev refs).
- **per-cluster operator hostname** — `bootstrap-spoke-deps.sh` sets
  `operatorConfig.hostname=dev-operator`; if the operator collided as `ryzen-operator-N`,
  clean the stale device via the TS API (`../references/tailscale-and-certs.md`).

## 8. Restore data + verify

```bash
kubectl --kubeconfig /tmp/talos-spoke-dev/kubeconfig cp /tmp/eib.sql workflow-builder/postgresql-0:/tmp/eib.sql
kubectl --kubeconfig /tmp/talos-spoke-dev/kubeconfig exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -f /tmp/eib.sql
```
Run the full block in `../references/dev.md` "Verification". Pass = 9 nodes Talos 1.13.x,
6 workers Ready DiskPressure=False, `argocd-agent-agent` Ready + connected, `cluster-dev`
is the resource-proxy AGENT MAPPING (`?agentName=dev`, no bearerToken), all apps in hub ns
`dev` Synced/Healthy (ignore "Unknown" operation status), db-migrate-before-db-seed, no dup
SWE-bench rows, Lite=300/Verified=500, `dev-shared-secrets` SecretSynced. Gate any benchmark
ramp with the `evaluations` skill's capacity diagnostics.

**Web exposure post-sync** (Contract 3, `../references/architecture.md` §7; cert-avoidance
rationale in `../references/tailscale-and-certs.md`). Once the spoke syncs, confirm the
CA/wildcard/sidecar chain comes up: the `tailnet-dev-ca` CA `ClusterIssuer` Ready -> the
`*.tail286401.ts.net` wildcard Certificate issued (Ready) -> the workflow-builder
`tls-terminator` sidecar serves :443. Then `https://workflow-builder-dev.tail286401.ts.net`
loads in a REAL browser (NOT bare curl — see the 502 buffer gotcha, `recovery-and-gotchas.md` §I).
```bash
SK=/tmp/talos-spoke-dev/kubeconfig
kubectl --kubeconfig $SK get clusterissuer tailnet-dev-ca                              # Ready=True (NO Let's Encrypt)
kubectl --kubeconfig $SK -n workflow-builder get certificate                           # tailnet wildcard Ready=True
kubectl --kubeconfig $SK -n workflow-builder get svc workflow-builder-tailnet -o wide  # type LoadBalancer (loadBalancerClass tailscale), EXTERNAL-IP assigned
```
