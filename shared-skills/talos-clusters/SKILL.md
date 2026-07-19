---
name: talos-clusters
description: "Create, recreate, resize, upgrade, and troubleshoot PittampalliOrg Talos Kubernetes clusters on Hetzner, especially the script-provisioned dev spoke (deployment/scripts/talos-hetzner). Use whenever the user mentions Talos, HCloud/Hetzner cluster nodes, dev cluster rebuilds, provision/bootstrap/enroll spoke scripts, argocd-agent managed-agent enrollment, stale Tailscale device names after cluster recreation, or SWE-bench capacity validation on Talos workers."
---

# Talos Clusters

Operational workflow for PittampalliOrg Hetzner+Talos spoke provisioning via the
`deployment/scripts/talos-hetzner` scripts in `PittampalliOrg/stacks`. This skill
covers provisioning, recreating, resizing, upgrading, and troubleshooting the
script-provisioned Hetzner Talos spoke (`dev`).

> Historical note: dev (and a never-fully-live `staging`) were once Crossplane
> `TalosSpokeClusterClaim` composites. Crossplane was REMOVED in Phase D; the
> single live composite (`dev`) was orphaned (kept running) and all future
> recreates use the three imperative scripts below — the SAME path hub and ryzen
> already use. There is no TalosSpokeClusterClaim, Composition, or group-N
> function anymore. Stale Crossplane mechanics in the runbooks are clearly
> marked HISTORICAL.

## Orientation

- The hub is a 5-node Talos `v1.12.x` / Kubernetes `v1.32.0` cluster on Hetzner
  (Flannel CNI, NOT Cilium, kube-proxy enabled). It is provisioned imperatively
  (`docs/hub-cluster-setup.md`) and runs the **argocd-agent v0.9.0 PRINCIPAL**
  (single ArgoCD pane, ns `argocd`). The hub's 21 ExternalSecrets resolve from
  the **`onepassword-store`** ClusterSecretStore (ESO `onepasswordSDK` provider ->
  the dedicated **`hub-eso`** 1Password vault) as of 2026-06; root-of-trust is one
  scoped read-only 1Password Service-Account token (`hub-eso-reader`) in Secret
  `onepassword-sa-token` (ns `external-secrets`). Azure Workload Identity + Key
  Vault (`keyvault-thcmfmoo5oeow`) + the AD App + the OIDC/JWKS federation are
  DORMANT (not deleted).
- Control plane = **argocd-agent v0.9.0**. Each spoke runs a LOCAL ArgoCD + an
  agent that dials the hub principal OUTBOUND over tailnet mTLS (8443). dev is a
  **MANAGED agent** (hub authors `Application` objects in ns `dev` == agent name;
  the principal pushes them; dev's local controller reconciles —
  `kubectl --context hub-cluster -n dev get applications` is the single pane).
  ryzen is an **AUTONOMOUS agent** (reconciles its own apps; hub aggregates
  status). Sync OPERATIONS run on the SPOKE's local controller, so the hub pane
  shows sync+health but NOT operation lifecycle ("Unknown operation status" on
  the hub is architectural and benign).
- dev is a **script-provisioned** Hetzner Talos spoke. Use
  `deployment/scripts/talos-hetzner/` + `packages/overlays/<spoke>/`, NOT
  committed claims/compositions. See "New / Rebuilt Spoke" below.
- The `ryzen` spoke (bare-metal Talos-in-Docker) is NOT in scope here. Use the
  `ryzen-spoke-bootstrap` skill for ryzen.
- For the canonical end-to-end recreate path (provision -> register -> secret
  transport -> connectivity -> workloads -> verify), defer to the
  **`cluster-desired-state`** skill: `runbooks/recreate-dev.md` is the
  authoritative dev runbook.
- Spokes no longer use Azure Workload Identity for workload secrets. They read
  hub-mirrored secrets over Tailscale via a `hub-secrets-store` ClusterSecretStore
  (ESO kubernetes provider) against the hub `spoke-secrets` namespace Secret
  `<cluster>-shared-secrets`. See `references/system-model.md`.
- The current Hetzner shape is tuned for US placement: `ash` maps to
  `us-east`, `hil` maps to `us-west`, and dev may use Hillsboro when Ashburn
  capacity is unavailable. Check server-type support before choosing a size.
- Hub->spoke kube-API reach (cert detail in
  `cluster-desired-state/references/architecture.md`):
  - **hub->ryzen**: the ryzen HOST runs `tailscale serve --tcp=6443` (raw TCP
    passthrough to the Talos apiserver) — NO Let's Encrypt cert; the hub verifies
    the Talos CA + an SA bearer token from Key Vault.
  - **hub->dev**: NO ArgoCD kube-API reach at all (managed agent, gRPC outbound
    only). Headlamp reaches dev via its DIRECT PUBLIC IP (`https://<ip>:6443`) +
    a read-only SA token.
- Headlamp on the hub builds its kubeconfig from dedicated `headlamp.dev/cluster=true`
  Secrets (per-spoke endpoint + read-only SA token + CA), NOT the argocd-agent
  cluster-mapping Secrets (which carry no bearerToken post-cutover). After a spoke
  is recreated or its Headlamp Secret changes, restart `hub-headlamp` before
  judging the UI connection stale.
- Promoted spoke workloads flow through source-hydrator and GitOps Promoter:
  `origin/main` -> dry source -> `env/spokes-<name>-next` ->
  `env/spokes-<name>` -> root-application. SPOKE lanes (e.g. `env/spokes-dev`)
  AUTO-promote.
- Device-backed Tailscale exposures and ProxyGroup service-hosts are different
  naming models. A stale service-host or offline device can reserve the desired
  hostname and cause `-1` suffix drift. The per-cluster operator device hostname
  (`dev-operator`/`ryzen-operator`) must be overridden away from the hardcoded
  `ryzen-operator` on every non-ryzen cluster (dev does this via PR #2364).

## New / Rebuilt Spoke (the 3-script flow)

A fresh or rebuilt Hetzner Talos spoke (`dev`) is provisioned + enrolled by three
imperative scripts in `PittampalliOrg/stacks`, run in order. The ORCHESTRATOR that
wraps all three (plus data backup/restore of
`environment_image_builds`/`agents`/`workflows` and the verify gate) is
`deployment/scripts/talos-hetzner/recreate-dev.sh` — use it as the dev rebuild
entry point. `register-spoke-with-hub.sh` is RETIRED (replaced by
`enroll-dev-agent.sh`). The authoritative end-to-end runbook is
`cluster-desired-state` `runbooks/recreate-dev.md`; this is the summary:

1. `deployment/scripts/talos-hetzner/provision-spoke.sh` — Hetzner network +
   firewall + servers (boots the PUBLIC Talos `1.12.4` amd64 ISO), `talosctl
   gen/apply/bootstrap`, kubeconfig, Cilium CNI (`cni: none`), disk-first boot
   after install. Bootstraps k8s `1.35` (the `1.12.4` ISO REJECTS `1.36`), then
   in-place `talosctl upgrade-k8s` to the target. `--destroy` tears it down.
2. `deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh` — cert-manager
   v1.14.4 + ESO 2.4.1 (controller-only) + the Tailscale operator + the
   spoke->hub ESO transport. It also seeds privileged namespaces, but that is now
   a REDUNDANT backstop: privileged PodSecurity is PRIMARILY declarative
   (`managedNamespaceMetadata` on CreateNamespace Helm apps + privileged-labelled
   Namespace manifests, PR #2359).
3. `deployment/scripts/argocd-agent/enroll-dev-agent.sh` — managed-agent enroll:
   mint the agent mTLS cert on the hub + deliver via ESO; create `cluster-dev`
   (the `?agentName=dev` resource-proxy mapping); AppProject; principal-egress
   Service; CoreDNS principal rewrite; and stage the hub Headlamp read SA Secret.
   Outbound-only — no hub->spoke kube-API reach.

## Start Here

1. Identify the operation:
   - New or rebuilt spoke: see "New / Rebuilt Spoke" above; the authoritative runbook
     is `cluster-desired-state` `runbooks/recreate-dev.md` (the old Crossplane-era
     `recreate-crossplane-spoke.md` was removed — Crossplane is gone).
   - Resize or version change: read `runbooks/resize-or-upgrade.md`.
   - API, hostname, or `-1` suffix issue: read
     `runbooks/tailscale-name-recovery.md`.
   - Post-rebuild dev/SWE-bench validation: read
     `runbooks/validate-dev-swebench-capacity.md`.
2. Read `references/system-model.md` if you need file paths, resource names, or
   the mental model before editing.
3. Use the `gitops` skill alongside this one for ArgoCD health, promoter/source
   hydrator recovery, image pin rollouts, and Tailscale app exposure details.
4. Use the `evaluations` skill alongside this one before launching paid or
   quota-sensitive SWE-bench ramps.

## Default Working Rules

- Provision with the scripts; commit the desired WORKLOAD shape in
  `packages/overlays/<spoke>/` (delivered by GitOps). HCloud servers and the
  imperative script parameters are the cluster shape; the overlay is the workload
  shape.
- Pause before destructive steps unless the user has explicitly authorized the
  outage. Verify no active benchmark runs, leases, Dapr workflow executions, or
  OpenShell sandboxes are still running.
- Preserve canonical names. Clean stale Tailscale devices/services before
  accepting suffixed hostnames or bumping API hostnames.
- Validate both infrastructure and runtime data. A Talos cluster is not "done"
  when nodes are Ready; the spoke's local ArgoCD apps, DB hooks, Tailscale
  endpoints, and workload capacity must also be healthy.
- Prefer capacity gates over optimism for SWE-bench. Do not start a 72-instance
  ramp unless diagnostics show enough sandbox headroom, runtime slots, no
  DiskPressure, and zero stale active state.

## Lessons From The Dev Rebuild

- The correct dev shape for the 72-capacity target is conservative but large:
  `3 x cpx41` control planes and `6 x cpx51` workers, with all workers labeled
  `stacks.io/swebench-pool=dev-benchmark`. Prefer `ash` when capacity exists;
  use `hil`/`us-west` when a US fallback is needed. Do not assume `cpx42` or
  `cpx62` are placeable in US regions.
- The Hetzner public catalog ships only a Talos `1.12.4` ISO (no custom-ISO
  upload API; a custom ISO requires a Hetzner support ticket with a direct
  `factory.talos.dev` URL). `install.image` (from `provision-spoke.sh`'s
  `TALOS_VERSION`, written into the generated machine config) governs the
  INSTALLED Talos version even when the node boots the `1.12.4` ISO, but the
  maintenance-mode node validates the REQUESTED Kubernetes version against the
  RUNNING (`1.12.4`) Talos. So a one-shot install of Talos `1.13.2` + k8s `1.36`
  on the `1.12.4` ISO cannot bootstrap. The script bootstraps at
  `BOOTSTRAP_K8S_VERSION=1.35.0` (installs Talos `v1.13.2` via `install.image`),
  then `talosctl upgrade-k8s --to ${K8S_VERSION}` once `1.13.2` is running.
  Verify the installed Talos via `kubectl get nodes -o wide` (OS-IMAGE column).
  See `runbooks/resize-or-upgrade.md`.
- Worker labels have two layers. `machine.nodeLabels` belongs in Talos machine
  config, but labels that must appear immediately on Kubernetes Nodes also need
  kubelet `extraArgs.node-labels` (the provisioner's `WORKER_NODE_LABELS`). Only
  pass custom labels there; kubelet rejects reserved labels such as
  `node-role.kubernetes.io/worker`.
- Ordered hooks matter. `db-migrate` must complete before `db-seed`, and the
  SWE-bench fixture seed should be idempotent and restore only sanitized,
  runtime-required rows.
- Runtime correctness depends on details outside node readiness. The dev rebuild
  exposed stale Tailscale names, a disabled Dapr dashboard ingress, an unused PVC
  blocking app health, Tekton default drift, and missing Dapr Component scopes
  for `agent-runtime-pool-coding`.
- A green capacity API is a better launch gate than manual arithmetic. It caught
  the Dapr state-store scoping issue even after the cluster had enough CPU,
  memory, and nodefs headroom.
- Recent hardening (PR #2395): four recreate fixes — Headlamp on the hub is now
  rollout-restarted by `enroll-dev-agent.sh` (step 5b) after the
  `headlamp.dev/cluster=true` Secret is re-staged (the init-container builds its
  kubeconfig only at pod start, so a pre-recreate pod serves the stale spoke
  endpoint); `provision-spoke.sh --destroy` now deletes the Hetzner servers
  concurrently (~156s -> ~20s for 9, mirroring the parallel create);
  `root-<spoke>` gets a hard-refresh after its local repo-server is Available to
  skip the ~5min cold-start ComparisonError stall; and the standalone bootstrap
  scripts now self-default the Tailscale-operator chart pin. INVARIANT: a
  standalone script that does NOT source `deployment/scripts/lib/common.sh` (e.g.
  `bootstrap-spoke-cluster.sh`, where `TS_OPERATOR_CHART_VERSION` was unbound
  under `set -u`) MUST self-default any version pin it shares with `common.sh`
  (now `TS_OPERATOR_CHART_VERSION:-1.96.5`), kept in lockstep with the GitOps
  tailscale-operator manifests. Full detail:
  `cluster-desired-state` `runbooks/recovery-and-gotchas.md`.

## Common Commands

```bash
# Hub principal pane: dev managed-agent Applications (single pane, ns dev == agent name)
kubectl --kubeconfig ~/.kube/hub-config -n dev get applications

# Hub agent/principal health
kubectl --kubeconfig ~/.kube/hub-config -n argocd get pods | rg 'argocd-agent|principal'
kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret cluster-dev \
  -o jsonpath='{.data.config}' | base64 -d   # resource-proxy mapping (?agentName=dev), no bearerToken

# Provision / recreate (run from PittampalliOrg/stacks; see cluster-desired-state recreate-dev.md)
deployment/scripts/talos-hetzner/recreate-dev.sh                               # 0. ORCHESTRATOR (backup/restore + 1-3 + verify)
CLUSTER_NAME=dev deployment/scripts/talos-hetzner/provision-spoke.sh           # 1. Hetzner+Talos
CLUSTER_NAME=dev TS_OAUTH_CLIENT_ID=… TS_OAUTH_CLIENT_SECRET=… \
  deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh                     # 2. deps + transport
deployment/scripts/argocd-agent/enroll-dev-agent.sh dev                        # 3. managed-agent enroll
CLUSTER_NAME=dev deployment/scripts/talos-hetzner/provision-spoke.sh --destroy # teardown

# Basic spoke health (use the provisioner's kubeconfig output, or break-glass via PUBLIC IP)
kubectl --kubeconfig <spoke-kubeconfig> get nodes -o wide
kubectl --kubeconfig <spoke-kubeconfig> get pods -A \
  --field-selector=status.phase!=Running,status.phase!=Succeeded
```

## Edit Targets

- Dev recreate orchestrator: `deployment/scripts/talos-hetzner/recreate-dev.sh`
  (wraps backup/restore + the 3 scripts + the verify gate)
- Provisioning scripts (Hetzner+Talos): `deployment/scripts/talos-hetzner/`
  (`provision-spoke.sh`, `bootstrap-spoke-deps.sh`, `README.md`)
- Agent enrollment: `deployment/scripts/argocd-agent/enroll-dev-agent.sh`
  (`register-spoke-with-hub.sh` is RETIRED)
- Spoke workload overlay: `packages/overlays/<spoke>/`
- Authoritative recreate runbook: `cluster-desired-state` `runbooks/recreate-dev.md`
- Tailscale + cert detail: `cluster-desired-state` `references/architecture.md`

## Validation

Always close with the evidence that matches the operation:

- Git/Kustomize: `kubectl kustomize packages/overlays/<spoke>` parses for overlay
  changes; `bash -n` for script edits.
- Hub: principal pane shows the spoke's Applications (`-n dev get applications`)
  Synced/Healthy; `cluster-<spoke>` is the resource-proxy mapping (no
  bearerToken); the agent pod on the spoke is connected to the principal.
- Spoke: all nodes Ready, expected labels, no DiskPressure, no unexpected bad
  pods; the spoke's LOCAL ArgoCD controller is reconciling. Note: "Unknown
  operation status" on the hub pane is architectural (operations run on the
  spoke), not a failure.
- Tailscale: canonical API/app hostnames present with no stale `-1` replacements
  unless intentionally accepted; the per-cluster operator hostname is correct
  (`dev-operator`, not `ryzen-operator`).
- Runtime: migrations/seeds ran in the expected order and idempotent seeds did
  not duplicate data.
- SWE-bench: capacity diagnostics pass before benchmark ramps.
