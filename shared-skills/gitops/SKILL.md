---
name: gitops
description: "Operate PittampalliOrg/stacks delivery and recovery, with dev as the default shared target. Use for ArgoCD or argocd-agent health, Source Hydrator and GitOps Promoter, hub Tekton builds, release and runtime image pins, generated overlays, deployment inventory, secrets, Tailscale exposure, Dapr workload readiness, Workflow MCP deployment/auth wiring, and live rollout proof. Use preview-environments for PreviewEnvironment lifecycles and cluster-desired-state for full cluster recreation."
---

# GitOps

Default shared delivery and live verification to `dev`. Operate `ryzen`, dormant
environments, or destructive hub recovery only when the user explicitly names
that target.

## Authority And Worktrees

```bash
STACKS_ROOT=/home/vpittamp/repos/PittampalliOrg/stacks/main
WFB_ROOT=/home/vpittamp/repos/PittampalliOrg/workflow-builder/main
git -C "$STACKS_ROOT" fetch origin
git -C "$WFB_ROOT" fetch origin
git -C "$STACKS_ROOT" status --short --branch
git -C "$WFB_ROOT" status --short --branch
```

Use fresh worktrees from `origin/main` for edits. Never reset a dirty shared
checkout. Resolve disagreements in this order:

1. Current manifests, renderers, validators, and controller code.
2. Rendered desired state and live controller status.
3. Focused repository docs.
4. This skill.

Avoid copying live image tags, versions, app counts, or one-time incident IDs
into skill text. Discover them from source and the target cluster.

## Delivery Model

| Target  | Source and writer                                                                                   | Reconciliation                                                              |
| ------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `dev`   | App merge to GitHub; hub Tekton builds GHCR and updates release metadata plus generated dev overlay | Source Hydrator -> GitOps Promoter -> `env/spokes-dev` -> managed dev agent |
| `hub`   | `stacks/main` dry source and generated hub state                                                    | Source Hydrator -> Promoter -> `env/hub` -> hub ArgoCD                      |
| `ryzen` | Explicit GitHub `main` manifest/image pin                                                           | Local autonomous ArgoCD `root-ryzen`; no Promoter lane                      |

The hub is the build and fleet-observation plane. Reconciliation operations run
on the target's local ArgoCD under argocd-agent. A hub status mirror may not
carry local operation history; use the target-local controller when that detail
matters.

## Choose The Path

| Task                                                     | Start here                                                                                                                                                      |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Understand branch and promotion ownership                | `docs/gitops-architecture-overview.md` and current hub-management manifests                                                                                     |
| Build and promote an app image                           | `docs/outer-loop-promotion.md`, hub Tekton triggers/pipelines, release-pin renderer                                                                             |
| Inspect a rollout                                        | GitHub checks -> hub PipelineRun -> release metadata -> hydrated branch -> Promoter -> target Application -> live image/env/route                               |
| Change generated workflow-builder overlays or image pins | Run `scripts/gitops/render-workflow-builder-release-overlays.sh`; never hand-edit generated output                                                              |
| Review ArgoCD drift                                      | Compare desired render, Application source/revision, diff, operation state, and live owner mutations                                                            |
| Repair a stuck promotion                                 | Inspect hydrator status, Promoter CRs/PRs/checks, then target Application health before retrying an operation                                                   |
| Diagnose a `1/2` Dapr workload                           | Check app container, `daprd` health/logs, placement/scheduler/control plane, Components, then recycle only the affected pod after proving control-plane health  |
| Diagnose Workflow MCP auth                               | Use the `workflow-builder` skill and `docs/workflow-mcp-server.md`; separate workspace keys, optional session context, and internal assertions                  |
| Deliver or recover durable execution evidence            | Inspect `docs/execution-evidence.md`, object-store config, archive reconciler env, ClickHouse evidence tables, release pins, and the live query surface          |
| Triage a run start refused `409 instance_conflict_live`  | Compare the durable instance against its execution row: the instance is live while the row reads terminal. Find the divergence; `WORKFLOW_ALLOW_DESTRUCTIVE_ID_REUSE=true` is a rollback lever, not a fix |
| Diagnose Tailscale exposure                              | Read the owning Ingress/LoadBalancer/ProxyGroup manifests, `docs/tailscale-naming.md`, and `policy.hujson`; identify device versus service-host ownership first |
| Rotate or repair secrets                                 | Trace ExternalSecret -> ClusterSecretStore -> remote key -> consuming pod; verify sync before restart and never print values                                    |
| Recreate a cluster                                       | Use `cluster-desired-state`                                                                                                                                     |
| Operate a preview vCluster                               | Use `preview-environments`                                                                                                                                      |
| Deliver a verified DevelopmentRun                        | Start from its linked delivery receipts, then prove review/merge -> Tekton build/digest -> image/config pins -> hydration/promotion where applicable -> ArgoCD reconciliation -> live user/runtime path; do not create another source writer |
| Deliver a `system-live` platform/runtime change          | Validate the compiled contract and pre-admission boundaries, rebuild any image-baked runner/runtime, render pins, advance the exact dev-preview-platform pointer, finish with one admitted runner digest, then prove a fresh generation, session, evidence receipt, and teardown |

## Rollout Proof

Follow the complete causality chain. A green PR or a running pod alone is not
proof that the requested behavior is live.

1. **Source:** identify the merged app and stacks revisions.
2. **Build:** prove the expected hub PipelineRun built the expected image from
   the source SHA and pushed the recorded digest.
3. **Pin/render:** inspect release metadata and regenerate any derived overlay
   with its owning script.
4. **Hydrate/promote:** verify dry and hydrated revisions, Promoter gates, PR
   state, and current environment branch.
5. **Reconcile:** verify the target Application source, sync, health, and diff.
6. **Runtime:** read the live Deployment/Job image, relevant env, pod readiness,
   Dapr sidecar state, and logs.
7. **User path:** exercise the authenticated API, UI route, or workflow that the
   change was intended to affect.

Use `/admin/gitops/system` as an observation surface, but treat repository,
controller, inventory, and live runtime evidence as authoritative.

## Diagnostic Order

For drift or an unavailable service, work top down:

```bash
git -C "$STACKS_ROOT" log -1 --oneline origin/main
kubectl --kubeconfig ~/.kube/hub-config get pipelineruns -n tekton-pipelines \
  --sort-by=.metadata.creationTimestamp
kubectl --kubeconfig ~/.kube/hub-config get promotionstrategy,pullrequest,timedcommitstatus -A
kubectl --kubeconfig ~/.kube/hub-config get applications -A
kubectl --context <target> get deploy,pod -n workflow-builder
```

Then inspect one failing owner at a time. Do not bulk-sync or restart unrelated
controllers to hide the first causal error.

## Stable Invariants

- One writer owns each generated pin/overlay. Run its renderer and validator in
  the same change.
- `workflowstatestore` is the sole Dapr actor/workflow store, and that is now
  mechanically enforced by
  `scripts/gitops/validate-dapr-actor-store-uniqueness.sh`. It rejects dead
  `state.*` Component manifests that no sibling kustomization references,
  same-name Component drift inside one (cluster-scope, namespace), and any
  namespace where an unscoped `actorStateStore: "true"` store is not the only
  true store. Preview vClusters count as their own cluster scope. It takes no
  arguments and hangs off its own CI check only — no aggregate sweep runs it, so
  run it yourself when a change touches Components. Agent application state
  stays separate and must never become a second actor state store.
- The orchestrator reaches product data only through the BFF's internal
  workflow-data HTTP API; `WORKFLOW_DATA_API_MODE` is strict `http` on every
  surface. A DB-fallback mode makes the orchestrator a second direct-Postgres
  writer that bypasses the projection fence. Environments that set nothing
  inherit the base ConfigMap, so the base value is the one that matters.
- The Dapr control plane is versioned per target, not fleet-wide. The shared
  base carries the host control plane, preview vClusters carry their own chart
  pin (asserted by `scripts/gitops/validate-preview-vcluster-surface.sh`, which
  must move in the same change), and the dormant `local-core-ryzen` profile
  carries its own copy. Never state a fleet version from one target's manifests.
- Runtime selection comes from the workflow-builder runtime registry and live
  deployment env, not from a remembered pod label.
- `system-live` is one immutable preview generation across stacks candidate
  paths and Workflow Builder services. Cataloged Deployments and the registered
  `development-module` use hot reload; `dapr-agent-py` is a session runtime and
  requires a built/pinned image plus a fresh session. Do not direct-patch a
  running durable agent or describe the retired Pydantic runtime as current.
- DevelopmentRun `submit` is the only preview-development delivery entry point.
  Its linked receipts are inputs to the ordinary GitOps chain, not permission
  for an agent to choose branches, repositories, commits, PRs, pins, or ArgoCD
  operations. Keep Tekton, renderer, Hydrator/Promoter, and ArgoCD ownership
  unchanged.
- Preview admission is physical-dev authority: the compiled contract binds the
  runner, policies, catalog, Dapr/runtime registry, effective agent/APM
  snapshot, database journal/template, seed set, capacity plan, and matching
  ResourceQuota before any lifecycle resource is created. A rollout may admit
  old and new runner digests only as a bounded transition; remove the old
  digest after proof.
- ActivePieces credentials are reference-forwarded; plaintext credentials must
  not enter workflow JSON, agent prompts, KService env, logs, or PRs.
- External Workflow MCP uses a workspace principal. Optional session context is
  lineage, not workflow ownership and not a substitute credential.
- Device-backed Tailscale hostnames and service-host VIPs have different
  ownership and cleanup paths. Identify the model before changing ACLs or
  deleting devices.
- Dev durability: CNPG backs up to in-cluster MinIO, and the
  `offsite-backup-mirror` CronJob (workflow-builder ns, 04:15 UTC) rclone-syncs
  `cnpg-backups` + `wfb-run-archives` to Azure `mlflowhub/dev-offsite-backups`.
  Its one secret is `OFFSITE-AZURE-STORAGE-KEY` via the hub dev-shared-secrets
  chain.
- Preview product data is one logical `preview_<name>` database on the host
  `preview-db` CNPG cluster through `preview-db-pooler`; the vCluster has no
  CNPG operator, cluster, or database PVC. Terminal preview run evidence is
  separately sealed into the host catalog, `wfb-run-archives`, and
  `obs.execution_evidence_{spans,logs}` before normal teardown.
- `WFB_RUN_ARCHIVE_ENABLED`, evidence retention/grace/quota, and
  `PREVIEW_ARCHIVE_ON_TEARDOWN` are active delivery contracts on dev. Preserve
  prompt/tool content and mask credentials only; never describe the current
  path as retired or inventory-only.
- A direct live patch is diagnostic only. Encode the durable fix in source and
  prove reconciliation restores it.

## Safety Rules

- Do not trigger ArgoCD syncs or roll workflow-builder control-plane pods while
  a preview, benchmark, or durable workflow proof is executing.
- Read every required PR check and generated-drift check before merging a
  stacks change.
- Never hand-edit generated image-pin ConfigMaps or generated kustomizations.
- Touching a governed workflow-builder env key or its delivery surfaces requires
  `scripts/gitops/validate-wfb-env-contract.sh` green: every governed key must be
  declared with its required and forbidden surfaces, in both directions. The
  governed prefixes and surface map live in
  `packages/components/workloads/workflow-builder-preview-vcluster/catalog/wfb-env-delivery-contract.json`
  — read that file for the current list rather than a remembered one. A
  mechanism needing opt-in config is not shipped until the config is.
- A NEW reconciler lane ships with its OWN dry-run gate, delivered on every
  required surface and defaulted observe-only. The shared
  `SESSION_RECONCILER_DRY_RUN` is already `false` on host and preview, so a lane
  that inherits only the global flag goes live on deploy with no soak. Flipping
  a lane's own gate is a separate change that carries soak evidence.
- Migrations that relabel or replace pods (e.g. a Service repointed at CNPG)
  must sweep NetworkPolicy podSelectors for the OLD labels — a label-pinned
  egress rule is a hidden consumer and fails as silent connect timeouts.
- Do not bypass Promoter for a normal dev rollout.
- Do not expose tokens, kubeconfigs, decrypted secrets, or OAuth payloads.
- Do not delete stale Tailscale devices, Jobs, PVCs, or workflow state until
  ownership and inactivity are proven.
- Do not use direct SQL to author workflows or force product lifecycle state.

## Canonical Sources

In `PittampalliOrg/stacks`:

- `AGENTS.md`
- `docs/gitops-architecture-overview.md`
- `docs/outer-loop-promotion.md`
- `packages/components/hub-management/`
- `packages/components/hub-spoke-appsets/`
- `packages/components/workloads/`
- `scripts/gitops/render-workflow-builder-release-overlays.sh`
- `scripts/gitops/validate-workflow-builder-release-pins.sh`
- `deployment/scripts/tailscale/`
- `policy.hujson`

In `PittampalliOrg/workflow-builder`:

- `docs/workflow-mcp-server.md`
- `docs/durable-session-runtime-contract.md`
- `docs/execution-evidence.md`
- `services/shared/runtime-registry.json`
- `src/lib/server/gitops/`
- `src/lib/server/lifecycle/`
