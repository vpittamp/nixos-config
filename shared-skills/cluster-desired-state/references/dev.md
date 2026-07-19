# DEV — desired state + path

A **disposable** Hetzner Talos spoke, provisioned + enrolled by SCRIPTS — the SAME
imperative path as hub & ryzen (Crossplane was REMOVED in Phase D; there is no
`TalosSpokeClusterClaim`/Composition/group-N pipeline any more). dev runs a LOCAL ArgoCD
plus an **argocd-agent v0.9.0 MANAGED agent**: the hub authors the dev Application objects
in ns `dev` (== agent name), the hub principal pushes them to the dev agent, and dev's
local controller reconciles them. Single pane = `kubectl --context hub-cluster -n dev get
applications`. Shared model in `architecture.md`; recreate steps in
`../runbooks/recreate-dev.md`; deep Tailscale + cert-avoidance detail in
`tailscale-and-certs.md` (canonical — do not re-explain it here). Paths relative to
`/home/vpittamp/repos/PittampalliOrg/stacks/main`.

## Desired state

**Infrastructure** (scripted Hetzner + Talos)
- 3 control planes (cpx41) + 6 workers (cpx51), location `hil`, networkZone `us-west`,
  network 10.0.0.0/16 subnet 10.0.1.0/24. Workers labeled
  `stacks.io/swebench-pool=dev-benchmark`. (LIVE TRUTH wins over docs — these are the
  `provision-spoke.sh` defaults that reproduce the live dev cluster; verify against the
  running cluster.)
- Booted from the PUBLIC Talos maintenance ISO (Hetzner id `125127` = Talos 1.12.4 amd64);
  `talosctl apply-config` installs the pinned **Talos 1.13.2** to disk, then in-place
  `upgrade-k8s` raises Kubernetes to **1.36.0**. **Cilium** CNI (cluster provisioned with
  `cni:none`, Cilium 1.16.5 installed so nodes go Ready). The 1.12.4 ISO REJECTS k8s 1.36
  at apply-config time, so provisioning bootstraps at k8s 1.35 first — see "ISO/k8s
  constraint" below + `../runbooks/recovery-and-gotchas.md`.
- All 6 workers Ready, untainted, DiskPressure=False.

**Connectivity / registration** (argocd-agent MANAGED mode)
- Hub argocd Secret `cluster-dev` (ns argocd) is an **AGENT MAPPING**, NOT a direct cluster
  registration: `server = https://argocd-agent-resource-proxy:9090?agentName=dev` with
  embedded mTLS (`certData`/`keyData`/`caData`) and **NO bearerToken**. The hub principal
  reaches dev only through the agent's OUTBOUND tailnet gRPC (8443) — there is NO
  hub→spoke kube-API reach for ArgoCD.
- The hub authors the dev Application objects directly in ns `dev`; the principal pushes
  them to the dev agent, which its local ArgoCD reconciles. dev's workflow-builder apps
  arrive via a bridge appset (`spoke-dev-workflow-builder`, drySource
  `workflow-builder-system-overlays/dev`). All dev apps should be Synced/Healthy in the
  hub pane (`kubectl --context hub-cluster -n dev get applications`).
- **Sync OPERATIONS run on dev's LOCAL controller**, so the hub pane shows sync + health
  but NOT operation lifecycle — "Unknown operation status" on the hub is architectural and
  BENIGN.
- Headlamp (hub dashboard) reaches dev via a DEDICATED `headlamp.dev/cluster=true` Secret
  (`headlamp-cluster-dev`) carrying dev's DIRECT PUBLIC IP (`https://<ip>:6443`) + a
  read-only SA token + CA — NOT the agent cluster-mapping Secret (which has no bearerToken
  post-cutover). See `tailscale-and-certs.md`.

**AWI-free secrets** (Contract 2, GitOps via overlay)
- Hub `dev-shared-secrets` ExternalSecret (ns spoke-secrets, ~79 keys, SecretSynced)
  mirrors every KV secret dev consumes. Spoke `hub-secrets-store` ClusterSecretStore reads
  it over the standalone `k8s-api-hub-ingress` device (caBundle ISRG Root X1; scoped
  read-only SA). This same spoke→hub ESO transport ALSO delivers the agent's mTLS cert +
  repo cred (see `tailscale-and-certs.md` for the transport mechanics — KEEP it, never
  remove). Workload ESes repointed to `dev-shared-secrets` via the render script's
  dev-gated patches (`architecture.md` §6).

**Workloads**: workflow-builder tier healthy; db-migrate runs before db-seed;
re-running db-seed creates no duplicate SWE-bench rows
(`SEED_SWEBENCH_FIXTURES_SKIP_WHEN_ACTIVE=true`); SWE-bench Lite=300 / Verified=500;
Kimi/DeepSeek agents registered.

**Web exposure** (Contract 3, `architecture.md` §7): workflow-builder reachable at
`https://workflow-builder-dev.tail286401.ts.net` via a Tailscale **L4 LoadBalancer**
Service (base `Service-workflow-builder-tailnet.yaml`, CLUSTER-templated, 443->https-tls)
+ an in-cluster nginx `tls-terminator` sidecar serving the persistent self-signed
`*.tail286401.ts.net` wildcard — **NO Let's Encrypt, NO Tailscale Ingress** (the dev
overlay `$patch:delete`s the old workflow-builder/mcp-gateway Tailscale Ingresses). The
`tailnet-ca` app (`packages/base/apps/tailnet-ca.yaml`) restores the shared CA into a
`tailnet-dev-ca` CA ClusterIssuer that issues the wildcard cert. **mcp-gateway is
in-cluster only** (`MCP_GATEWAY_BASE_URL=http://mcp-gateway.workflow-builder.svc.cluster.local:8080`);
`ORIGIN`/`APP_PUBLIC_URL` stay `https://workflow-builder-dev...`. See
`tailscale-and-certs.md` for the LoadBalancer-vs-Ingress cert-avoidance rationale.

## Path to state (ordered) — PROVISION -> BOOTSTRAP-DEPS -> ENROLL -> GITOPS SYNC -> ES REPOINT -> VALIDATE

0. **PREFLIGHT** — back up SWE-bench fixtures from the CURRENT dev BEFORE destroying it
   (the pg_dump env-table backup/restore lives in the workflow-builder APP repo, not
   stacks). Confirm no active work and cancel/drain runs+leases+Dapr workflows. See
   `../runbooks/recovery-and-gotchas.md` "env-table SWE-bench restore".
1. **REMOVE LEGACY** — destroy the prior dev infra (`provision-spoke.sh --destroy`, which
   removes the dev Hetzner servers/network/firewall). Remove a stale hub `cluster-dev`
   Secret if it is not the current agent mapping; clean stale Tailscale devices
   (esp. the `dev-operator` proxy device) via the TS API — see `tailscale-and-certs.md`
   for the stale `-N` device cleanup pattern.
2. **PROVISION** — `deployment/scripts/talos-hetzner/provision-spoke.sh` (Hetzner + Talos,
   the scripted replacement for the old Crossplane groups 1–4). Boots the public Talos
   1.12.4 ISO, `apply-config` installs Talos 1.13.2 to disk (disk-first boot order; ISO
   detached as cleanup), installs Cilium CNI, then in-place upgrades k8s 1.35 -> 1.36.
   Output: a healthy bare Talos cluster + a kubeconfig (`/tmp/talos-spoke-dev/kubeconfig`).
   ```bash
   CLUSTER_NAME=dev deployment/scripts/talos-hetzner/provision-spoke.sh
   # destroy a prior cluster first:  CLUSTER_NAME=dev deployment/scripts/talos-hetzner/provision-spoke.sh --destroy
   ```
   - **ISO/k8s constraint** (see `../runbooks/recovery-and-gotchas.md`): the 1.12.4 ISO
     rejects a too-new k8s at apply-config time, so the script bootstraps at
     `BOOTSTRAP_K8S_VERSION=1.35.0` then `upgrade-k8s` to 1.36 once the installed Talos
     1.13.2 is running. `install.image` (from `TALOS_VERSION`) drives the installed Talos.
3. **BOOTSTRAP-DEPS** — `deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh`: the
   minimal seed the agent needs before it can enroll, plus the spoke→hub transport.
   Installs **cert-manager v1.14.4**, **ESO 2.4.1** (controller-only:
   `webhook.create=false certController.create=false`, `unsafeServeV1Beta1=true`), the
   **Tailscale operator** (with `operatorConfig.hostname=dev-operator` — the per-cluster
   override, see below), and the **spoke→hub ESO transport** (`hub-secrets-store`
   ClusterSecretStore + egress Service + CoreDNS rewrite + scoped hub token, via
   `lib/spoke-transport-bootstrap.sh --apply-manifests --wait-ready`). It also pre-labels
   the privileged namespaces — but that is now a **REDUNDANT backstop**: privileged
   PodSecurity is PRIMARILY declarative (managedNamespaceMetadata on the CreateNamespace
   Helm apps + privileged-labelled Namespace manifests, PR #2359), so the agent's own apps
   create + selfHeal those namespaces privileged. The loop just removes the first-sync
   ordering window for the sync-wave -100 local-path-provisioner.
   ```bash
   CLUSTER_NAME=dev deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh
   # needs TS_OAUTH_CLIENT_ID / TS_OAUTH_CLIENT_SECRET (1Password or hub Key Vault)
   ```
   - The Tailscale-operator chart pin (`TS_OPERATOR_CHART_VERSION`, 1.96.5) now
     **self-defaults** in the standalone bootstrap (PR #2395, Fix 1); it does not source
     `lib/common.sh` where the shared pin lives, so previously it was unbound under `set -u`
     and the recreate aborted at the operator helm install. See
     `../runbooks/recovery-and-gotchas.md`.
4. **ENROLL** (managed-agent) —
   `deployment/scripts/argocd-agent/enroll-dev-agent.sh dev`. Idempotent + re-runnable.
   It: asserts the hub principal is live and `principal.allowed-namespaces` includes `dev`;
   **mints the agent mTLS cert on the hub** (holding ns) and stages it to
   `spoke-secrets/dev-agent-cert` for **ESO delivery** (no hub→spoke reach needed); applies
   the spoke-side agent-managed bundle; waits for ESO to materialize the cert + the agent
   rollout; **creates the `cluster-dev` AGENT MAPPING Secret on the hub**
   (`server=https://argocd-agent-resource-proxy:9090?agentName=dev` with embedded mTLS, NO
   bearerToken) via `argocd-agentctl agent create`; restarts the agent so it connects +
   re-pushes status; and **stages the hub Headlamp read Secret** (`headlamp-cluster-dev`
   with dev's public endpoint + read-only SA token + CA). The AppProject, principal-egress
   Service, and CoreDNS principal rewrite come from the agent bootstrap kustomize
   (`packages/components/hub-management/manifests/dev-agent-bootstrap`).
   ```bash
   deployment/scripts/argocd-agent/enroll-dev-agent.sh dev
   ```
   - **Step 5b** restarts the hub Headlamp deployments (`kubectl -n headlamp rollout restart
     deploy/hub-headlamp deploy/hub-headlamp-embedded`) after staging the
     `headlamp-cluster-dev` Secret (PR #2395, Fix 3). The hub Headlamp builds its kubeconfig
     only in its generate-kubeconfig init-container, so a pod predating the recreate keeps
     serving the OLD dev endpoint/CA/token and the staged Secret is inert without the bounce.
     Guarded on deploy existence + non-fatal. See `../runbooks/recovery-and-gotchas.md`.
5. **GITOPS SYNC** — once enrolled, the hub principal PUSHES the dev Application objects
   (authored in hub ns `dev`) to the dev agent, whose local controller reconciles them.
   GitOps delivery is source-hydrator + GitOps Promoter: `overlays/dev` -> `env/spokes-dev-next`
   -> (AUTO-promote, spoke lanes auto-merge) -> `env/spokes-dev` -> root-application. dev's
   workflow-builder apps come via the `spoke-dev-workflow-builder` bridge appset (drySource
   `workflow-builder-system-overlays/dev`). dev tracks `main` (via the source-hydrator +
   Promoter ladder). Confirm: `kubectl --context hub-cluster -n dev get applications` all
   Synced/Healthy ("Unknown operation status" is benign).
6. **PER-CLUSTER ES PARAMETERIZATION** — run
   `scripts/gitops/render-workflow-builder-release-overlays.sh` (dev-gated repoints onto
   `dev-shared-secrets`; `--check` validates staleness). See `architecture.md` §6.
7. **VALIDATE** (below).

## Verification

```bash
SK=/tmp/talos-spoke-dev/kubeconfig                                  # from provision-spoke.sh
kubectl --kubeconfig $SK get nodes -o wide                          # 9 nodes, OS-IMAGE Talos 1.13.x (confirms install.image worked)
kubectl --kubeconfig $SK get nodes -l stacks.io/swebench-pool=dev-benchmark  # 6 workers Ready, DiskPressure=False
kubectl --kubeconfig $SK -n argocd rollout status deploy/argocd-agent-agent  # agent Ready + connected to the principal
# db ordering + idempotency: db-migrate before db-seed; re-run db-seed -> no dup SWE-bench rows; Lite=300/Verified=500

K=~/.kube/hub-config
kubectl --kubeconfig $K -n argocd get secret cluster-dev -o jsonpath='{.data.server}' | base64 -d   # ...resource-proxy:9090?agentName=dev (mapping, no bearerToken)
kubectl --kubeconfig $K -n dev get applications                    # all Synced/Healthy (ignore "Unknown" operation status)
kubectl --kubeconfig $K -n spoke-secrets get externalsecret dev-shared-secrets  # SecretSynced
argocd-agentctl agent list --principal-context hub-cluster --principal-namespace argocd  # dev listed/connected
```

> dev has NO hub→spoke kube-API reach for ArgoCD (managed agent, gRPC outbound only).
> Inspect dev workloads via the spoke kubeconfig from `provision-spoke.sh`, via Headlamp
> (which uses the dedicated `headlamp-cluster-dev` endpoint), or via the hub pane's cached
> resource tree in ns `dev`.

## Dev-specific gotchas (fixes in `../runbooks/recovery-and-gotchas.md`)

- **"Unknown operation status" on the hub** — architectural + BENIGN. Sync OPERATIONS run
  on dev's local controller; the hub principal sees sync + health but not operation
  lifecycle.
- **ISO/k8s in-place upgrade** — Hetzner public catalog only ships a Talos 1.12.4 ISO; the
  maintenance-mode node validates the requested k8s version against the RUNNING 1.12.4.
  `install.image` (from `TALOS_VERSION`) drives the INSTALLED Talos version. The script
  bootstraps at k8s 1.35 then `upgrade-k8s` to 1.36.
- **local-path PodSecurity recreate hang** — historically CreateNamespace=true created a
  bare ns -> baseline PSA rejected local-path hostPath helper pods -> PVCs Pending ->
  stateful workloads hang. Now PRIMARILY fixed declaratively (managedNamespaceMetadata +
  privileged-labelled Namespace manifests, PR #2359); `bootstrap-spoke-deps.sh`'s
  pre-label loop is only a redundant fast-path backstop.
- **db-seed idempotency** — `Job-db-seed.yaml` PostSync hook;
  `SEED_SWEBENCH_FIXTURES_SKIP_WHEN_ACTIVE=true` so re-runs create no dup SWE-bench rows.
  db-migrate (sync-wave; render script injects a repair-schema-drift initContainer) runs
  before db-seed.
- **render-script gating** — all dev repoints are gated `[ "${cluster}" = "dev" ]` so other
  cluster output stays byte-identical; without the gate dev would wrongly read ryzen's
  bundle (shared manifests hardcode `ryzen-shared-secrets`).
- **per-cluster operator hostname** — the shared tailscale-operator manifest hardcodes
  `OPERATOR_HOSTNAME=ryzen-operator`; dev MUST override it (`dev-operator`, via the dev
  overlay patch PR #2364, and `bootstrap-spoke-deps.sh` sets it at install time) or the
  operator collides on the tailnet. See `tailscale-and-certs.md` for stale `-N` device
  cleanup.
