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
| Diagnose Tailscale exposure                              | Read the owning Ingress/LoadBalancer/ProxyGroup manifests, `docs/tailscale-naming.md`, and `policy.hujson`; identify device versus service-host ownership first |
| Rotate or repair secrets                                 | Trace ExternalSecret -> ClusterSecretStore -> remote key -> consuming pod; verify sync before restart and never print values                                    |
| Recreate a cluster                                       | Use `cluster-desired-state`                                                                                                                                     |
| Operate a preview vCluster                               | Use `preview-environments`                                                                                                                                      |

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
- `workflowstatestore` is the sole Dapr actor/workflow store. Agent application
  state is separate and must not become a second actor state store.
- Runtime selection comes from the workflow-builder runtime registry and live
  deployment env, not from a remembered pod label.
- ActivePieces credentials are reference-forwarded; plaintext credentials must
  not enter workflow JSON, agent prompts, KService env, logs, or PRs.
- External Workflow MCP uses a workspace principal. Optional session context is
  lineage, not workflow ownership and not a substitute credential.
- Device-backed Tailscale hostnames and service-host VIPs have different
  ownership and cleanup paths. Identify the model before changing ACLs or
  deleting devices.
- A direct live patch is diagnostic only. Encode the durable fix in source and
  prove reconciliation restores it.

## Safety Rules

- Do not trigger ArgoCD syncs or roll workflow-builder control-plane pods while
  a preview, benchmark, or durable workflow proof is executing.
- Read every required PR check and generated-drift check before merging a
  stacks change.
- Never hand-edit generated image-pin ConfigMaps or generated kustomizations.
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
- `services/shared/runtime-registry.json`
- `src/lib/server/gitops/`
- `src/lib/server/lifecycle/`
