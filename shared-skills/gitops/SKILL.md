---
name: gitops
description: "Operate PittampalliOrg/stacks delivery and recovery, with dev as the default shared target. Use for ArgoCD or argocd-agent health, Source Hydrator and GitOps Promoter, hub Tekton builds, release and runtime image pins, generated overlays, deployment inventory, secrets, Tailscale exposure, Dapr workload readiness, Workflow MCP deployment/auth wiring, and live rollout proof. Use kubernetes-capacity for shared capacity policy, preview-environments for PreviewEnvironment lifecycles, platform-monitoring for the signal pipeline, notification kinds, and Drasi/CDC health, and cluster-desired-state for full cluster recreation."
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

| Target  | Source and writer                                                                                   | Reconciliation                                                             |
| ------- | --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `dev`   | App merge to GitHub; hub Tekton builds GHCR and updates release metadata plus generated dev overlay | Source Hydrator -> GitOps Promoter -> `env/spokes-dev` -> managed dev agent |
| `hub`   | `stacks/main` dry source and generated hub state                                                    | Source Hydrator -> Promoter -> `env/hub` -> hub ArgoCD                      |
| `ryzen` | Explicit GitHub `main` manifest/image pin                                                           | Local autonomous ArgoCD `root-ryzen`; no Promoter lane                      |

The hub is the build and fleet-observation plane. Reconciliation operations run
on the target's local ArgoCD under argocd-agent. A hub status mirror may not
carry local operation history; use the target-local controller when that detail
matters.

## Build Lanes

All lanes live in `packages/components/hub-tekton/manifests/outer-loop-builds/`,
are started by the `github-outer-loop` EventListener, and are boxed in by a
per-lane `ValidatingAdmissionPolicy` (`*-image-build-boundary`) that pins the
run name, creating identity, labels, workspaces, and executor contract. Each
lane resolves an existing image before it builds.

| Lane        | Trigger                                                                       | PipelineRun                              | Status posted                                     |
| ----------- | ------------------------------------------------------------------------------- | ------------------------------------------ | --------------------------------------------------- |
| PR head     | `pull_request` — open, **non-draft**, base `main`, **same-repo head**          | `pr-build-workflow-builder-<head sha12>` | `hub/image-build` on the HEAD, pending -> final    |
| Merge queue | `merge_group` — base `refs/heads/main`, head `refs/heads/gh-readonly-queue/...` | `mq-build-workflow-builder-<sha12>`      | `hub/image-build` on the queue commit             |
| Push (main) | `push` to `main`, per-image path CEL                                          | `outer-loop-<image>-*`                   | `hub/build-<image>` from `finally`                |
| Dev images  | `push` to `main`, dev-image inputs                                            | `outer-loop-dev-images-*`                | `hub/build-dev-images` from `finally`             |

- **PR head.** Every non-draft, same-repository PR push builds the exact head and
  pushes `ghcr.io/pittampalliorg/<image>:git-<head sha>` **plus**
  `:tree-<tree sha>`, labelled `io.stacks.source-tree`, `io.stacks.build-lane`,
  `io.stacks.source-revision`, `io.stacks.build-run`. The run name is fixed (not
  `generateName`), so a webhook redelivery for the same head is an
  `AlreadyExists` no-op. Drafts never build; `ready_for_review` starts the first
  build. A real hub build failure on a PR head blocks enqueue until a new push.
- **Cancel-on-push.** The `supersede` task cancels other in-flight `pr-head` runs
  for the same PR and image and posts
  `hub/image-build=error "superseded by <head>"` on the stale head, so a burst of
  pushes costs one build. It first asks GitHub for the PR's *current* head and
  fails fast if this run is the stale one, so an out-of-order delivery cannot
  cancel the real head.
- **Reuse resolution.** PR-head and merge-queue lanes run `resolve-tree-image`
  (`present` | `reuse-tree` | `build`); the pure decision function is
  `outer-loop-tree-reuse.py`. The push lane runs
  `resolve-preview-accepted-image`, whose precedence is **`reuse-exact`** (an
  exact `git-<sha>` tag with merge-queue lineage labels) > **`reuse`** (a
  `preview/immutable-acceptance` receipt for a content-equivalent image) >
  **`build`**. Because GitHub fast-forwards `main` to the queue commit, the push
  lane normally lands on `reuse-exact` and skips its build.
- **Measured end to end.** A PR whose head was already built merges to live on
  dev in **~3.5 min** (queue build ~30 s via `reuse-tree`, push lane
  `reuse-exact`, then pin -> sync -> rollout). A cold build adds **~5.5 min**.
  Build lanes carry `retries: 1`; failed PipelineRuns are kept **7 days**.

## Merging Pull Requests

- **workflow-builder `main` is behind a merge queue** (ruleset "main merge
  queue", squash, ALLGREEN). Required contexts on both the PR head and the queue
  commit: `ci-required` (the aggregator job in `pr-checks.yml`, green only when
  every CI job succeeded) and `hub/image-build`. On the head that status comes
  from the hub PR-head lane; wfb's `image-build-deferred` job is a *fallback*
  that waits ~150 s and posts a deferred success only when the hub posted
  nothing (drafts, forks, lost webhooks).
- Enqueue with `gh pr merge <n> --squash --auto` or the GraphQL
  `enqueuePullRequest` mutation. **`PUT /pulls/<n>/merge` does not work on
  workflow-builder.** A queue entry is dropped when any queue-commit check fails
  (flaky suites included) — confirm the failure is not real, then re-enqueue.
- **stacks `main` is protected by ruleset "main required checks"**: required
  context `stacks-ci-required`, no deletion or force-push, and **App 2970091 is
  the only bypass actor — humans cannot push to `main`**. Merge with
  `PUT /pulls/<n>/merge` once that check is green.
- `.github/workflows/ci-required.yml` runs the spoke-env integrity check inline,
  then waits (15 min cap, two quiet polls) for every other `github-actions` check
  run on the head SHA. A path-gated validator that never registered a check run
  reads as pass — that is the design, not a bug.
- **Trap:** a stacks PR whose head predates `ci-required.yml` never gets the
  required check and is blocked forever. Close/reopen does not help; rebase onto
  `main`.
- Read outcomes from `GET /repos/<r>/commits/<sha>/check-runs` plus the `hub/*`
  commit statuses. `preview/gate`, `preview/immutable-acceptance`,
  `preview/activation-images`, and `pr-preview` are **advisory** — never wait on
  them and never add the `preview` label to turn them green. A PR preview is an
  interactive review tool: label `preview` only when a person wants to use it to
  judge the change. While an acceptance you care about is running, keep `main`
  still; its evidence binds to the baked image and any merge invalidates it.
- Watchers: one at a time, REST only, poll every >=3 minutes (the GraphQL budget
  is shared with subagents); stop on any failing check run. Never `pkill -f` a
  watcher from inside another background command whose own command line contains
  the pattern.

## Failure Signals

- `hub/build-<image>` and `hub/build-dev-images` are posted from the push
  lanes' `finally` on the merged commit. Failure there means the build broke on
  `main` — the run is kept 7 days.
- The BFF raises `build_failed` and `pin_drift` notifications from
  `tekton.pipelinerun` activity events (`src/lib/server/application/adapters/environment-image-builds.ts`,
  `gitops-activity-events.ts`).
- ArgoCD notifications: the **hub** `argocd-notifications-controller`
  (`packages/components/hub-management/manifests/argocd-notifications/`) posts
  through the in-cluster `gitops-event-relay` webhook service to the dev BFF
  (`POST /api/internal/gitops/events/ingest`). Rows land as activityType
  `argocd.application`; the bell
  renders them as `argocd_health` / `argocd_sync`. Subscription scope is the
  label **`notifications.stacks.io/spoke=dev`** on the hub-side `dev-*` child
  Applications and the two dev roots — those are the truthful objects, because
  the agent pushes spoke health into them and child health does not propagate to
  a root. Triggers: `on-health-degraded`, `on-sync-failed`,
  `on-sync-status-unknown`, `on-out-of-sync`, `on-deployed`.

The pipeline carrying those signals — `gitops_activity_events` ingest, the five
notification kinds, ArgoCD subscription-by-label and delivery, retention and the
conditional ArgoCD purge, Drasi continuous queries and the CDC replication-slot
failure mode, and the `/admin/gitops` and `/admin/drasi` surfaces — belongs to
**`platform-monitoring`**. Go there when a signal never arrived at all; what
follows is the delivery view.

**"My change is not on dev" — diagnose in this order:**

1. **Merged?** `git log origin/main` in the app repo, and confirm the queue
   actually merged rather than dropping the entry.
2. **Built?** `hub/image-build` on the merge SHA, then the PipelineRun. No run at
   all points at webhook loss (below), not at a build failure.
3. **Failed?** `hub/build-<image>` / `hub/build-dev-images` on the commit.
4. **Pinned?** Did the push lane write the pin to `stacks/main`? A merge-queue
   run builds the image but **never writes release pins** — only a push-lane run
   proves the push arrived.
5. **Promoted?** Hydrator status, Promoter CRs/PRs, current `env/spokes-dev`.
6. **Synced?** Target Application source/revision/health, and
   `.status.operationState.message` — a failing sync hook parks the entire app
   sync while it reads `OutOfSync` + `Healthy`, which looks benign.
7. **Pinned pointer?** If the change is under the preview platform, see
   *dev-preview-platform Pointer* — that app is pinned to an exact SHA and will
   report `Synced`/`Healthy` on old content.
8. **Live?** Deployment image and env, pod readiness, `daprd` state, then the
   authenticated user path.

## Webhook Delivery Loss

The Funnel edge drops roughly **15% of webhook deliveries with HTTP 502, and
GitHub never retries** — so a `main` push can silently never build, and a lost
`merge_group` delivery stalls a queue entry until GitHub's 60-minute check
timeout.

- The hub CronJob **`outer-loop-webhook-catchup`** (`*/5`, `GRACE_SECONDS=180`)
  covers both classes: each tick it compares `main` HEAD and the open queue refs
  against the PipelineRuns and `hub/image-build` statuses the hub actually has,
  synthesizes the missing `push` or `merge_group` payload, signs it with the
  EventListener's own `github-webhook-secret`, and POSTs it to the EL Service
  in-cluster. **A lost delivery is re-driven within ~8 min.** State lives in the
  ConfigMap `outer-loop-webhook-catchup-ledger` (separate `mergeGroupHistory`
  keys) so a SHA is never replayed twice; results post as `hub/webhook-catchup`.
- Manual remedy when you cannot wait: replay the signed delivery to the
  EventListener yourself (HMAC `X-Hub-Signature-256` from
  `github-webhook-secret`; from the tailnet the EL answers 202 in ~0.2 s).
- Inspect deliveries with `gh api repos/<r>/hooks/<id>/deliveries` and **parse
  with python — `jq` mangles the delivery IDs** (float precision).
- The EventListener answers 202 and logs nothing at info when a trigger overlay
  errors. Read the `tekton-triggers-core-interceptors` pod logs instead of
  editing `config-logging-triggers` (GitOps selfHeal reverts it in seconds).
  Tekton CEL `truncate` is a **receiver method**: `body.x.truncate(12)`.

## Image Pins Have Exactly One Writer

- `scripts/gitops/render-workflow-builder-release-overlays.sh` is the only writer
  of release pins, dev-image env, and execution classes. `--list-outputs` is the
  live inventory — never keep a second copy of that file list.
- The BFF and the sandbox-execution API **read the mounted
  `workflow-builder-image-pins` ConfigMap** (preview vClusters:
  `workflow-builder-image-pins-preview`). Their Deployments carry **no inline
  `*_DEV_IMAGE`, `*_DEFAULT_IMAGE`, `SANDBOX_EXECUTION_CLASSES_JSON`, or
  `SANDBOX_TEMPLATE_IMAGES_JSON` env**. A dev-image bump is therefore a
  ConfigMap-only change and **does not roll the BFF**.
- `scripts/gitops/validate-image-pin-single-writer.sh` proves it four ways:
  inventory from the renderer, freshness against a fresh render, no hand copies
  in any workload manifest or kustomization, and marker ownership (a
  `# renderer:<key>` marker pasted onto a hand-pinned line still fails). It exits
  1 on any hand copy.
- **Resolve rebase conflicts in generated files by re-running the renderer on top
  of `main`, never by hand-merging.** Never hand-edit a generated image-pin
  ConfigMap or kustomization.

## Sync Latency Facts

- **dev is effectively webhook-driven.** The hub argocd-server's GitHub webhook
  stamps `argocd.argoproj.io/refresh` on the hub-side managed Application and
  argocd-agent carries it to the spoke; dev syncs start **~12 s** after a stacks
  `main` commit. The `timeout.reconciliation` 60 s + 15 s jitter poll is only the
  fallback — and the backstop for the Funnel-502 loss class.
- **A spoke cannot have an ArgoCD webhook at all.** The agent bundle installs
  controller, repo-server, and redis and deliberately no argocd-server, so there
  is no `/api/webhook` to expose. Do not propose one.
- Dev sets `controller.sync.wave.delay.seconds: "0"`
  (`packages/overlays/dev/kustomization.yaml`). The old ~85 s "hook wait" was 27
  sync waves times a 2 s delay, **not** the `db-migrate` hook, which is ~4 s.
- Do not blame polling before checking hooks: a failing hook Job still blocks
  every unrelated resource in that app, image pins included.

## dev-preview-platform Pointer

`packages/overlays/dev/apps/dev-preview-platform.yaml` pins an **exact commit
SHA on purpose** — promotion of that pointer is when dev adopts platform content,
and `validate-preview-live.sh` plus the runner-freshness and managed-agent tests
assert exact-revision equality. **Do not propose tracking `HEAD`.** Contrast
`dev-workflow-builder`, which targets `HEAD`: a change spanning both delivers half
on merge. The app reports `Synced`/`Healthy` the whole time it serves old
content, so read `.spec.source.targetRevision` on the `dev-preview-platform`
Application and test it with `git merge-base --is-ancestor <your-commit> <that
SHA>`.

Two writers advance the pointer, so a platform change no longer waits for an
unrelated release: `Task-update-stacks-image` runs the reconciler on **every**
image release, and `.github/workflows/advance-dev-preview-platform.yml` runs
`scripts/gitops/advance-dev-preview-platform-pointer.sh` on pushes touching
`workloads/dev-preview-platform`, `workloads/preview-host-candidate`, or
`workloads/workflow-builder-preview-vcluster`, pushing the pointer-only commit as
`gitops-promoter-23[bot]`. Check that workflow's last run before hand-bumping.

**Exit 3** from the helper = a runner build input changed without a
`VCLUSTER_PREVIEW_RUNNER_IMAGE` re-pin: build and pin the runner through the
activation pipeline, then re-run from the Actions tab.
`test-preview-runner-image-freshness.sh` is **PR-aware** — on `pull_request` it
compares against the merge-base with the base branch (override
`PREVIEW_FRESHNESS_BASE`); push-to-main runs stay strict.

## Credentials

- Tekton's `github-clone-credentials` is a short-lived **GitHub App installation
  token** minted by the ESO `GithubAccessToken` generator `github-clone` (App
  **2970091**), narrowed to `stacks` + `workflow-builder` with `contents`,
  `pull_requests`, `statuses` write. Pushes appear as `gitops-promoter-23[bot]`
  (commit author stays "Tekton Hub (outer-loop)"). The same App is the sole bypass
  actor on stacks `main`, which is what lets pin writes through.
- **Known exception:** one PAT-backed secret remains,
  `github-webhook-admin-credentials`, read only by the
  `ensure-stacks-github-webhooks` step of `Task-update-stacks-image`, because the
  installation lacks the Webhooks permission. Granting `repository_hooks: write`
  and repointing that step retires it; nothing that clones or pushes may reference
  it (`validate-outer-loop-build-boundary.sh` enforces that).
- Never expose tokens, kubeconfigs, decrypted secrets, or OAuth payloads. Rotate
  by tracing ExternalSecret -> ClusterSecretStore -> remote key -> consuming pod;
  verify sync before restart and never print values.

## Choose The Path

| Task                                                     | Start here                                                                                                                                                      |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Understand branch and promotion ownership                | `docs/gitops-architecture-overview.md` and current hub-management manifests                                                                                     |
| Review ArgoCD drift                                      | Compare desired render, Application source/revision, diff, operation state, and live owner mutations                                                            |
| Repair a stuck promotion                                 | Inspect hydrator status, Promoter CRs/PRs/checks, then target Application health before retrying an operation                                                   |
| Diagnose a `1/2` Dapr workload                           | Check app container, `daprd` health/logs, placement/scheduler/control plane, Components, then recycle only the affected pod after proving control-plane health  |
| Diagnose Workflow MCP auth                               | Use the `workflow-builder` skill and `docs/workflow-mcp-server.md`; separate workspace keys, optional session context, and internal assertions                  |
| Deliver or recover durable execution evidence            | Inspect `docs/execution-evidence.md`, object-store config, archive reconciler env, ClickHouse evidence tables, release pins, and the live query surface          |
| Roll the `dapr-agent-py-sandbox` pin                     | One pin feeds the harness (`dapr-agent-harness`) and the executor image on the BFF; wait for `rollout status` on `dapr-agent-harness`, `workflow-orchestrator`, and `workflow-builder` before a live proof |
| Deliver a Kiota generated action                         | Use `generated-actions` for package authoring and promotion; then prove the reviewed Workflow Builder package, seed hook, `kiota-mcp` / `generated-action-runtime` image pins, hydration/promotion, live catalog row, and one credential-reference execution |
| Triage a run start refused `409 instance_conflict_live`  | Compare the durable instance against its execution row: the instance is live while the row reads terminal. Find the divergence; `WORKFLOW_ALLOW_DESTRUCTIVE_ID_REUSE=true` is a rollback lever, not a fix |
| Diagnose Tailscale exposure                              | Read the owning Ingress/LoadBalancer/ProxyGroup manifests, `docs/tailscale-naming.md`, and `policy.hujson`; identify device versus service-host ownership first |
| Recreate a cluster                                       | Use `cluster-desired-state`                                                                                                                                     |
| Operate a preview vCluster                               | Use `preview-environments`                                                                                                                                     |
| Audit or tune shared capacity                            | Use `kubernetes-capacity`; deliver its reviewed manifests and controller changes through this skill                                                            |
| Deliver a verified DevelopmentRun                        | Start from its linked delivery receipts, then prove review/merge -> Tekton build/digest -> image/config pins -> hydration/promotion -> ArgoCD reconciliation -> live user/runtime path; do not create another source writer |
| Deliver a `system-live` platform/runtime change          | Validate the compiled contract and pre-admission boundaries, rebuild any image-baked runner/runtime, render pins, advance the exact dev-preview-platform pointer, finish with one admitted runner digest, then prove a fresh generation, session, evidence receipt, and teardown |

## Rollout Proof

Follow the complete causality chain. A green PR or a running pod alone is not
proof that the requested behavior is live.

1. **Source:** identify the merged app and stacks revisions.
2. **Build:** prove the expected hub PipelineRun produced the expected image from
   that SHA and pushed the recorded digest — or that a lane legitimately resolved
   `reuse-exact` / `reuse-tree` and name the run it reused.
3. **Pin/render:** inspect release metadata and regenerate any derived overlay
   with its owning script.
4. **Hydrate/promote:** verify dry and hydrated revisions, Promoter gates, PR
   state, and current environment branch.
5. **Reconcile:** verify the target Application source, sync, health, and diff.
6. **Runtime:** read the live Deployment/Job image, relevant env, pod readiness,
   Dapr sidecar state, and logs.
7. **User path:** exercise the authenticated API, UI route, or workflow the
   change was intended to affect.

Use `/admin/gitops/system` as an observation surface, but treat repository,
controller, inventory, and live runtime evidence as authoritative.

Build and promotion state live on the hub (`--kubeconfig ~/.kube/hub-config`):
`pipelineruns -n tekton-pipelines --sort-by=.metadata.creationTimestamp` and
`promotionstrategy,pullrequest,timedcommitstatus -A`. Application and workload
state live on the target (`--context dev`). Inspect one failing owner at a time;
do not bulk-sync or restart unrelated controllers to hide the first causal
error.

## Stable Invariants

- Every generated pin/overlay has exactly one writer — run its renderer and
  validator in the same change (see *Image Pins Have Exactly One Writer*).
- `workflowstatestore` is the sole Dapr actor/workflow store, enforced by
  `scripts/gitops/validate-dapr-actor-store-uniqueness.sh`: it rejects dead
  `state.*` Components no sibling kustomization references, same-name Component
  drift within one scope, and any namespace where an unscoped
  `actorStateStore: "true"` store is not the only true store. Preview vClusters
  count as their own cluster scope. No aggregate sweep runs it — run it yourself
  when a change touches Components. Agent application state stays separate and
  must never become a second actor state store.
- The orchestrator reaches product data only through the BFF's internal
  workflow-data HTTP API; `WORKFLOW_DATA_API_MODE` is strict `http` everywhere. A
  DB-fallback mode makes it a second direct-Postgres writer that bypasses the
  projection fence. Environments that set nothing inherit the base ConfigMap, so
  the base value is the one that matters.
- The Dapr control plane is versioned per target, not fleet-wide. The shared base
  carries the host control plane, preview vClusters carry their own chart pin
  (asserted by `scripts/gitops/validate-preview-vcluster-surface.sh`, which must
  move in the same change), and the dormant `local-core-ryzen` profile carries
  its own copy. Never state a fleet version from one target's manifests.
- Runtime selection comes from the workflow-builder runtime registry and live
  deployment env, not from a remembered pod label.
- `system-live` is one immutable preview generation across stacks candidate paths
  and Workflow Builder services. Cataloged Deployments and the registered
  `development-module` hot-reload; `dapr-agent-py` is a session runtime needing a
  built/pinned image plus a fresh session. Do not direct-patch a running durable
  agent. Cleanup releases application adoption first and restores the baseline
  before ArgoCD resumes.
- DevelopmentRun `submit` is the only preview-development delivery entry point.
  Its linked receipts are inputs to the ordinary GitOps chain, not permission for
  an agent to choose branches, repositories, commits, PRs, pins, or ArgoCD
  operations.
- Preview admission is physical-dev authority: the compiled contract binds runner,
  policies, catalog, Dapr/runtime registry, agent/APM snapshot, database
  journal/template, seed set, capacity plan, and ResourceQuota before any
  lifecycle resource exists. Admitting old and new runner digests together is a
  bounded transition only; remove the old digest after proof.
- ActivePieces credentials are reference-forwarded; plaintext credentials must not
  enter workflow JSON, agent prompts, KService env, logs, or PRs.
- External Workflow MCP uses a workspace principal. Optional session context is
  lineage, not workflow ownership and not a substitute credential.
- Device-backed Tailscale hostnames and service-host VIPs have different ownership
  and cleanup paths. Identify the model before changing ACLs or deleting devices.
- Dev durability: CNPG backs up to in-cluster MinIO; the `offsite-backup-mirror`
  CronJob (workflow-builder ns, 04:15 UTC) rclone-syncs `cnpg-backups` +
  `wfb-run-archives` to Azure `mlflowhub/dev-offsite-backups`.
- Preview product data is one logical `preview_<name>` database on the host
  `preview-db` CNPG cluster through `preview-db-pooler`; the vCluster has no CNPG
  operator, cluster, or PVC. Terminal preview run evidence is sealed into the host
  catalog, `wfb-run-archives`, and `obs.execution_evidence_{spans,logs}` before
  normal teardown.
- `WFB_RUN_ARCHIVE_ENABLED`, evidence retention/grace/quota, and
  `PREVIEW_ARCHIVE_ON_TEARDOWN` are active delivery contracts on dev. Preserve
  prompt/tool content and mask credentials only.
- A direct live patch is diagnostic only. Encode the durable fix in source and
  prove reconciliation restores it.
- Kueue quota, exact preview shapes, physical headroom, observed PSI, public
  origins, and lifecycle limits are separate controls. Use the current capacity
  profiles and `docs/capacity-management.md`; do not tune from one live number.

## Safety Rules

- Do not trigger ArgoCD syncs or roll workflow-builder control-plane pods while a
  preview, benchmark, or durable workflow proof is executing. The orchestrator is
  exempt: rolling `workflow-orchestrator` mid fan-out is proven safe (any replica
  resumes from durable state; the in-band repoll lane recovers lost child
  completions as `customStatus.repolled > 0`) and is verified with
  workflow-builder `scripts/probes/orchestrator-roll-proof.sh`.
- Touching a governed workflow-builder env key or its delivery surfaces requires
  `scripts/gitops/validate-wfb-env-contract.sh` green: every governed key must be
  declared with its required and forbidden surfaces, in both directions. Read the
  current surface map in
  `packages/components/workloads/workflow-builder-preview-vcluster/catalog/wfb-env-delivery-contract.json`
  rather than a remembered one. A mechanism needing opt-in config is not shipped
  until the config is.
- A NEW reconciler lane ships with its OWN dry-run gate, delivered on every
  required surface and defaulted observe-only. The shared
  `SESSION_RECONCILER_DRY_RUN` is already `false` on host and preview, so a lane
  that inherits only the global flag goes live on deploy with no soak. Flipping a
  lane's own gate is a separate change that carries soak evidence.
- Migrations that relabel or replace pods (e.g. a Service repointed at CNPG) must
  sweep NetworkPolicy podSelectors for the OLD labels — a label-pinned egress rule
  is a hidden consumer and fails as silent connect timeouts.
- Do not bypass Promoter for a normal dev rollout.
- Do not delete stale Tailscale devices, Jobs, PVCs, or workflow state until
  ownership and inactivity are proven.
- Do not use direct SQL to author workflows or force product lifecycle state.

## Canonical Sources

`PittampalliOrg/stacks`: `AGENTS.md`; `docs/gitops-architecture-overview.md`,
`docs/outer-loop-promotion.md`, `docs/capacity-management.md`;
`packages/components/hub-tekton/manifests/outer-loop-builds/`;
`packages/components/{hub-management,hub-spoke-appsets,workloads}/`;
`scripts/gitops/{render-workflow-builder-release-overlays,validate-image-pin-single-writer,validate-workflow-builder-release-pins}.sh`;
`.github/workflows/{ci-required,advance-dev-preview-platform}.yml`;
`deployment/scripts/tailscale/`; `policy.hujson`.

`PittampalliOrg/workflow-builder`: `docs/workflow-mcp-server.md`,
`docs/durable-session-runtime-contract.md`, `docs/execution-evidence.md`;
`services/shared/runtime-registry.json`; `src/lib/server/gitops/`,
`src/lib/server/lifecycle/`,
`src/lib/server/application/gitops-activity-events.ts`.
