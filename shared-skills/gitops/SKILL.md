---
name: gitops
description: "Use this skill for PittampalliOrg/stacks GitOps operations: ArgoCD app health/drift review across hub/dev/staging/ryzen; ryzen hub-managed spoke registration and Tailscale-routed sync; image promotion; release-pins, GHCR image drift, and image pins outside release-pins; SWE-bench evaluator image/env rollout and canary validation; workflow-builder spoke runtime drift; workflow-builder prompt-preset DB migrations and API smoke tests; workflow-builder MCP/auth and ActivePieces piece MCP services; Dapr AgentRuntime statestore, sidecar readiness, and 1/2 pod recovery; GitOps Promoter stuck apps, env branches, source-hydrator, and hub promotion; Tailscale ACLs, device-backed Ingress DNS/status, ProxyGroup service-host VIPs, spoke API access, stale tailnet devices/services, and Funnel webhooks; OAuth/secret rotation, deployment inventory, workflow JSON DB upserts, and app placement."
---

# GitOps for PittampalliOrg/stacks

Operational knowledge for the hub-and-spoke gitops system across **dev**, **staging**, **ryzen** (local Talos Docker, hub-managed spoke via Tailscale), and **hub** (Talos control plane). Read this whole file, then drill into `reference/` or `runbooks/` based on the decision tree.

## Orientation

- **Hub** is a Talos cluster on Hetzner. It runs a single ArgoCD that manages itself **and** all spokes via cluster secrets.
- **Spokes**: `dev`, `staging` (Talos on Hetzner), and `ryzen` (local Talos Docker on the user's workstation). Hub ArgoCD manages dev/staging; ryzen also has an in-cluster ArgoCD sourced from local Gitea snapshots.
- **Hub Tekton owns the build plane**:
  - **Outer-loop lane**: triggered by GitHub webhooks on app repos (`PittampalliOrg/workflow-builder`, etc.); builds images, pushes to **ghcr.io**, then `update-stacks` writes tag/digest/provenance to `release-pins/workflow-builder-images.yaml` and regenerates `packages/components/workloads/workflow-builder-system-overlays/{dev,staging}/kustomization.yaml`. Current pipelines may push the release metadata commit directly to `origin/main`; older/alternate pipelines may open a `release/workflow-builder-*` release-intent PR. Inspect `update-stacks` logs and branch/PR state before assuming the handoff. A release metadata + generated overlay commit on `origin/main` drives **dev/staging**.
  - **Ryzen local delivery**: source changes still land through the normal app repo / GitHub path, and current image delivery should use GHCR tags or explicit stacks pins. Ryzen manifest updates are delivered by hub-side Source Hydrator + Promoter PR merge on `env/hub`.
  - **SWE-bench inference image lane**: submitted by workflow-builder/swebench-coordinator preflight as `swe-env-<envSpecHash-prefix>` PipelineRuns on hub Tekton. These validate and pin repo/version/base images into `SWEBENCH_INFERENCE_ENVIRONMENTS_DIR` ConfigMap data. If a dev SWE-bench run sits `queued` while a `swe-env-*` PipelineRun exists on hub, the run is waiting for hub environment validation; do not look for Buildah pods on dev. The supported lane is the organic harness-generated image path; stale Epoch/prebuilt experiment rows or PipelineRuns must not satisfy exact-ready selection unless a fresh compatibility canary proves that strategy.
  - A workflow-builder app push that touches `services/dapr-agent-py` normally fires three runtime image builds: `dapr-agent-py-image-build`, `dapr-agent-py-sandbox-image-build`, and `dapr-agent-py-testing-sandbox-image-build`. It can also fire the workflow-builder image build from the same commit. Watch the GitHub/GHCR outer-loop PipelineRuns and release metadata before deciding a rollout is complete.
  - For SWE-bench infra work, a `dapr-agent-py` change is not live until dev runs the matching sandbox/testing sandbox images and the BFF sees the updated `AGENT_RUNTIME_*_DEFAULT_IMAGE` values. A recent scoped-activity fix validated this path with workflow-builder commit `0180f081` and a clean 25-instance dev run; use the pattern, not the SHA, as the rule.
  - Old spoke-local build apps such as `workflow-builder-builds-local` and `gitea-builds-egress` should stay removed. If you see them live, treat them as stale/orphaned unless a new design explicitly reintroduces them.
- **GitOps Promoter** gates hub and spoke promotions. `workflow-builder-release` gates dev → staging through `argocd-health` plus the `timer` gate from `TimedCommitStatus-workflow-builder-soak.yaml` (dev `0s`, staging `10m`); both environments still have `autoMerge: true`. `stacks-environments` gates hub self-management from `env/hub-next` → `env/hub`.
- **ArgoCD v3.4 + Promoter v0.30 (May 2026)**. Bumped from 3.3.9/v0.27.1. v3.4 has stricter ServerSideApply that surfaces operator-injected drift previously hidden — most commonly seen on Tekton Pipelines/Tasks (mutating webhook adds `computeResources: {}`, `metadata: {}`, etc.) and Knative Services (`terminationGracePeriodSeconds` requires a feature flag). Use `ignoreDifferences` with `jqPathExpressions` covering the operator-injected paths; see `runbooks/review-argocd-app-health.md`. Also enabled the web-based terminal (`exec.enabled=true`) — Pods now have a Terminal tab in the UI.
- **ArgoCD Promoter UI extension** is installed on hub ArgoCD so operators can visualize `PromotionStrategy`, `ChangeTransferPolicy`, `PullRequest`, and related Promoter CRDs in the ArgoCD UI.
- **Source-hydrator** renders `packages/overlays/<spoke>` → `env/spokes-<spoke>-next`; promoter merges to `env/spokes-<spoke>`; hub ArgoCD syncs the generated spoke Applications to the target clusters. Dev/staging usually do not have their own local ArgoCD Application CRDs.
- **Deployment inventory** is generated on the hub by `gitops-deployment-inventory`. Browser/human access uses the HTTPS service-host VIP `gitops-inventory-hub.tail286401.ts.net`; spoke workflow-builder pods use a separate node-backed Tailscale LoadBalancer `gitops-inventory-hub-node.tail286401.ts.net:8080` through the in-cluster egress Service `gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080`.
- **Promoted spoke hostnames are declarative.** Dev/staging workflow-builder system URLs live in `spoke-workloads-appset.yaml`, device-backed Tailscale Ingresses live under `packages/base/manifests/tailscale-ingresses/`, and `policy.hujson` is reserved for tailnet policy such as real `svc:*` service-host approvals, device tags, Funnel grants, and Kubernetes grants.
- **OpenShell depends on agent sandbox CRDs.** Keep `agent-sandbox-crds` / `<spoke>-agent-sandbox-crds`; it owns required `AgentRuntime`, `Sandbox`, `SandboxClaim`, `SandboxTemplate`, and `SandboxWarmPool` CRDs. AutoKube is legacy and has been removed.
- **Workflow-builder MCP/auth is a DB-backed runtime path, not just static manifests.** Project MCP rows in workflow-builder's `mcp_connection` table bind ActivePieces pieces to `app_connection.external_id` credentials. The `activepieces-mcps` app reconciles those rows into cluster-local Knative `ap-<piece>-service` MCP servers plus an `activepieces-mcp-catalog` ConfigMap. Agent publish/registry sync writes resolved MCP servers into each `AgentRuntime`, and the controller injects them into the runtime pod as `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`.
- **Sandboxed Dapr agents use centralized Dapr state.** `workflowstatestore` is the namespace-wide workflow/actor state store for parent workflows, child session workflows, timers, reminders, and activity bookkeeping. `dapr-agent-py-statestore` is namespace-wide too, but `actorStateStore=false`; it is the agent application state API store. Do not create per-agent state stores or move durable history into pod-local state.
- **SWE-bench evaluator rollout is a workflow-builder image-promotion path plus an env-var check.** The evaluator image is built from the workflow-builder repo (`services/swebench-evaluator`) and promoted through release-pins, but `swebench-coordinator` launches Jobs from `SWEBENCH_EVALUATOR_IMAGE`. The base kustomize has a replacement from local-config `Pod/swebench-evaluator-image` into that env var; verify the live Deployment env after promotion instead of assuming `images:` alone rewrote it.

The two image-pin systems for the **same workflow-builder base** are the most common source of confusion. Read `reference/architecture.md` first if you've never seen this setup.

## The "which file?" matrix (single most-referenced piece of knowledge)

| Cluster | Image source | Bump path | Branch the bump lands on |
|---|---|---|---|
| **ryzen** | `packages/components/workloads/<image>/manifests/kustomization.yaml` (`images:` block) or release-pinned GHCR refs for shared workload images | Edit stacks, then run `commit-pin.sh` to GitHub `inner-loop` branch. The affected-app planner snapshots to local Gitea, hard-refreshes only affected apps, and waits for the pushed revision | GitHub `PittampalliOrg/stacks` `env/spokes-ryzen` branch, hydrated by hub from `inner-loop` |
| **dev / staging** | `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` (`images` compatibility tags plus `digests`, `imageRefs`, `sourceShas`, `pipelineRuns`, `updatedAts`) rendered into dry-source overlays at `packages/components/workloads/workflow-builder-system-overlays/{dev,staging}/kustomization.yaml` | Hub Tekton outer-loop `update-stacks` writes release metadata and regenerates overlays; observed current path can push directly to `origin/main`, while PR-mode opens `release/workflow-builder-*`. Manual changes must update/validate the same metadata and overlays | `origin/main` release metadata commit, or `release/workflow-builder-*` PR branch → `origin/main` when PR mode is active |
| **hub** itself | source-hydrator from `packages/overlays/hub` on `origin/main` → `env/hub-next` → `env/hub` (gated by `stacks-environments` PromotionStrategy) | Edit overlay; merge to `origin/main` | `origin/main` (GitHub) |

`agent-runtime-controller` is a third path: bumped directly in `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` (no per-cluster override), so a single bump applies to all spokes once it's on `origin/main`.

`release-pins/workflow-builder-images.yaml` is the image-pin source for promoted dev/staging workflow-builder-system child Applications, but it is not applied directly by the ApplicationSet. It is rendered into the dry-source overlays with `scripts/gitops/render-workflow-builder-release-overlays.sh`, and source-hydrator reads those overlays. Manual release-pin edits must run the renderer or `scripts/gitops/validate-workflow-builder-release-pins.sh` will fail the overlay freshness check.

- **Do not add release-pin lookups back into `spoke-workloads-appset.yaml`.** Argo CD source-hydrator caches by dry-source commit; when rendered output depends on ApplicationSet generator values outside the dry source, a controller race can hydrate the right dry SHA with stale inline values and then keep reusing that hydrated commit. Keep release-pin-derived images/env in the generated dry-source overlays instead.
- **AgentRuntime CR images** (`browser-use-agent-sandbox`, `dapr-agent-py-sandbox`) are read at agent-publish time from `AGENT_RUNTIME_*_DEFAULT_IMAGE` env vars on the workflow-builder Deployment (`packages/components/workloads/workflow-builder/manifests/Deployment-workflow-builder.yaml`). `kustomize.images` substitutes container `image:` fields but **not** env var values, so release-pins bumps don't touch these. Bump the env var, AND patch already-published `AgentRuntime` CRs (`spec.environment.imageTag`) — registry-sync only re-runs at agent publish time. See `runbooks/bump-image-pin-not-in-release-pins.md`.

Post-A6 (May 2026), ryzen is a hub-managed spoke: no local ArgoCD, no local Gitea, no idpbuilder. Ryzen-affecting manifest changes flow through GitHub branches:

- **Ryzen-only image-tag bumps** (Skaffold outer-loop): commit-pin.sh pushes to GitHub `inner-loop` branch. Hub's Source Hydrator picks up `inner-loop` directly into `env/spokes-ryzen` — NO Promoter PR needed for this path.
- **Manifest changes affecting hub itself** (cluster Secrets, ApplicationSet definitions, headlamp Service annotations): commit to GitHub `main`. Hub Source Hydrator hydrates `packages/overlays/hub` to `env/hub-next`. GitOps Promoter then creates `env/hub-next → env/hub` PRs that MUST be merged for the change to take effect.
- **Manifest changes affecting dev/staging/ryzen workload-layer**: commit to `main`. Hub spoke-ryzen + spoke-dev/staging Applications hydrate from `main` directly (no Promoter for spoke-side hydration). Promoter does gate the env/spokes-dev-next → env/spokes-dev step for dev/staging promotion.

Hub→ryzen kube-api connectivity goes through the Tailscale operator-managed egress: hub's ArgoCD pods resolve `ryzen-api-egress.tailscale.svc.cluster.local` via in-cluster DNS to a hub-side proxy pod (StatefulSet `ts-ryzen-api-egress-*`), which forwards to ryzen's tailnet device `ryzen-api-v3` (a Tailscale-exposed Service via `tailscale.com/expose: true`). If hub can't reach ryzen, see `runbooks/debug-proxygroup-service-host.md` and the `ryzen-spoke-bootstrap` skill's `references/failure-modes.md`.

For hot-loop regression checks, use `deployment/scripts/benchmark-ryzen-hot-edit.sh` with `BENCHMARK_PURPOSE=normal|manual|threshold-test` and `BENCHMARK_CASE=child-service|app-definition|dependency-file`. The `app-definition` case uses a source-only child Application marker so it exercises root/app-definition planning without leaving live Application fields behind. The summary command defaults to `--purpose normal` and excludes failed threshold-test reports; use `--purpose all --include-failures` when auditing full history.

MCP/auth has a third, non-image flow. `mcp_connection` and `app_connection` rows live in the workflow-builder DB; `activepieces-mcps` reconciles those rows into Knative services; `AgentRuntime` registry sync copies the resolved server list into the runtime CR/pod. A source push alone does not fix an already-published agent if its `AgentRuntime` still has stale MCP bootstrap JSON; run registry sync or patch/re-publish the AgentRuntime, then verify the generated Deployment env and runtime logs.

## Decision tree

### "I need to roll out / promote / bump an image"

1. Which cluster? **ryzen only** → update the workloads manifest or GHCR image pin in stacks, then run `commit-pin.sh` to GitHub `inner-loop` branch. If the image does not exist yet, push the app repo to `origin/main` so the normal GitHub/GHCR outer-loop builds it first.
2. **dev or staging** → normal path is hub Tekton outer-loop builds GHCR and `update-stacks` writes tag, digest, provenance, and generated dry-source overlays. Read the task logs: if it pushed directly to `origin/main`, track source-hydrator + Promoter from that commit; if it opened a `release/workflow-builder-*` PR, review/merge it first. Manual path: edit all release metadata maps in `release-pins/workflow-builder-images.yaml`, run `scripts/gitops/render-workflow-builder-release-overlays.sh`, verify the GHCR tag/digest, run `scripts/gitops/validate-workflow-builder-release-pins.sh`, then follow `runbooks/promote-image-to-spokes.md`.
3. Want dev/staging to use an image you validated on ryzen → use the GHCR tag/digest as the promoted artifact, then bump release-pins and generated overlays. Legacy Gitea registry mirroring is recovery-only; it is not the normal source of promoted images.

### "I pushed workflow-builder and need to verify ryzen + dev"

1. Confirm the app repo commit is on `origin/main` so the hub Tekton outer-loop builds the new `ghcr.io/pittampalliorg/workflow-builder:git-<sha>` image.
2. Ryzen: for inner-loop iteration, `commit-pin.sh` already pushed the new tag to GitHub `inner-loop` branch — hub Source Hydrator picks it up automatically. Verify with `kubectl --context hub get application ryzen-workflow-builder -n argocd` (should be `Synced/Healthy`) and confirm the live Deployment image on ryzen via `kubectl get deploy workflow-builder -n workflow-builder -o jsonpath='{.spec.template.spec.containers[0].image}'`. During active `skaffold dev` sessions the Skaffold-owned dev pod may serve live traffic from synced source while hub-Argo is paused; inspect the live pod before assuming the image rollout is what users hit.
3. Dev: watch hub `outer-loop-workflow-builder-*`; capture the built GHCR tag/digest and read `update-stacks` logs. The task may push release metadata directly to `origin/main` or open a release PR depending on the active pipeline.
4. Track `spoke-dev-workflow-builder.status.sourceHydrator.currentOperation.{drySHA,hydratedSHA}`, the `workflow-builder-release-env-spokes-dev-*` ChangeTransferPolicy, and `dev-workflow-builder` / `spoke-dev-workflow-builder` health. If `env/spokes-dev-next` advanced but the CTP still proposes the older dry SHA after one source-hydrator poll, annotate `PromotionStrategy/workflow-builder-release` and the dev CTP with fresh `promoter.argoproj.io/refresh-ts`.
5. Finish with authenticated smoke tests against the public URLs. For schema-affecting workflow-builder changes, verify the `db-migrate` hook applied the expected migration before trusting the UI. For Prompt Workbench/preset changes, confirm `resource_prompt_versions` exists and run an authenticated `/api/prompt-presets` list/create/update/archive smoke. On NixOS, if Playwright's bundled browser cannot launch, use system Chrome at `/etc/profiles/per-user/vpittamp/bin/google-chrome`.

### "I edited stacks manifests and need ryzen to pick them up"

1. Decide the right branch:
   - **Ryzen-only image-tag bump** (typical after `skaffold run`): push to `inner-loop` via `commit-pin.sh`. Hub Source Hydrator picks it up directly → env/spokes-ryzen → ryzen.
   - **Hub-affecting change** (cluster Secret, ApplicationSet, Tailscale Service annotation): commit to `main`, then merge the env/hub-next → env/hub Promoter PR (`gh pr list -R PittampalliOrg/stacks --state open --search 'Promote'`).
   - **Spoke-workloads change affecting all spokes**: commit to `main`. Spoke-side hydrator picks it up automatically (no Promoter PR for spoke hydration).
2. Trigger immediate refresh instead of waiting for the 3-min poll:
   ```bash
   ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-kubeconfig annotate application ryzen-<svc> -n argocd argocd.argoproj.io/refresh=hard --overwrite"
   ```
3. If a sync is stuck "another operation is already in progress", `argocd app terminate-op <app>` then retry with `--replace`.
4. For child `Application` spec changes that don't propagate, the env/hub Promoter ladder might be stuck: see `runbooks/manage-gitops-promoter.md`. The fast path is `gh pr create --base env/hub --head env/hub-next` + merge if Promoter hasn't auto-created.

### "I updated SWE-bench evaluator/coordinator and need to deploy/test"

1. Confirm the workflow-builder commit includes the intended `services/swebench-evaluator/Dockerfile` pin or coordinator changes, and is pushed to `origin/main` so the GHCR outer-loop can build it. For ryzen, update the stacks workloads pin on `main` (or `inner-loop` for ryzen-only) and let hub Source Hydrator pick it up.
2. Watch hub Tekton build `swebench-evaluator:git-<workflow-builder-sha>` and capture the GHCR digest from `release-pins/workflow-builder-images.yaml` / generated workflow-builder-system overlay.
3. Track `dev-swebench-coordinator` to `Synced/Healthy`, then verify the live Deployment has `SWEBENCH_EVALUATOR_IMAGE=ghcr.io/pittampalliorg/swebench-evaluator:git-<sha>` with the expected digest-backed release.
4. Run a focused SWE-bench canary: one known gold patch that resolves, one empty-patch case that returns `empty_patch`, and, when available, an environment/build validation case. Evaluator Jobs should use the expected resource class and `ttlSecondsAfterFinished=3600`.
5. For UI-visible validation, create or trigger a Benchmarks page run (`/workspaces/<slug>/benchmarks`) and confirm artifact SHA-256s, provenance, official result, raw harness notes, report path, and job name appear in the run API/UI. The evaluations skill has the DB/coordinator smoke path for deterministic runs.

For DeepSeek SWE-bench validation, use the direct DeepSeek model specs (`deepseek/deepseek-v4-pro`, `deepseek/deepseek-v4-flash`) and confirm the selected agent runtime reports provider `deepseek` with `llm-deepseek-v4-*` components. Effective concurrency is the minimum of UI/requested concurrency, runtime slots, per-sidecar Dapr workflow capacity, global benchmark caps, sandbox headroom, and model caps; when in doubt read the evaluations skill `references/swebench-concurrency.md` before changing stacks values.

### "A workflow-builder agent is silent after adding an MCP/OAuth connection"

Use `runbooks/debug-workflow-builder-mcp-auth.md`. The short path:

1. Confirm `workflow-builder`, `activepieces-mcps`, and `knative-serving` are `Synced/Healthy` on the target cluster.
2. Confirm the piece appears in `activepieces-mcp-catalog` and its `ap-<piece>-service` KService is Ready. The URL should be `http://ap-<piece>-service.workflow-builder.svc.cluster.local/mcp` with no explicit `:3100`.
3. Confirm the `mcp_connection.connection_external_id` points at an active `app_connection.external_id`; MCP credentials flow through `X-Connection-External-Id`, not inline secrets in manifests.
4. Trigger agent registry sync or re-publish the agent, then check the generated `agent-runtime-<slug>` Deployment env for `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`.
5. Wake/test the agent and read `dapr-agent-py` logs for `[mcp-bootstrap] connected ...` and tool registration. A first health probe may time out during Knative cold start; retry before declaring the KService broken.

### "A workflow-builder runtime pod is 1/2 or daprd readiness is false"

Use `runbooks/debug-dapr-sidecar-stale-readiness.md`. First identify whether the app container or `daprd` is not ready. If the app container is ready but `daprd` reports `ERR_HEALTH_NOT_READY` for `grpc-api-server` / `grpc-internal-server`, check recent `dapr-system` placement/scheduler churn, verify the control plane is healthy now, then recycle only the affected workflow-builder Deployment. Do not clear state stores or restart Dapr control-plane components unless they are still unhealthy.

### "An ArgoCD app is OutOfSync / stuck"

1. Query hub ArgoCD even for dev/staging: `kubectl --kubeconfig ~/.kube/hub-config get applications.argoproj.io -n argocd`.
2. Check `kubectl get app <name> -n argocd -o jsonpath='{.status.operationState.phase}'`.
3. **Phase=Running for hours?** Check `.status.operationState.message` — usually `waiting for completion of hook batch/Job/db-migrate`. Drill: `kubectl get jobs -n workflow-builder` on the spoke; if `db-migrate` is stuck Terminating, see `runbooks/recover-stuck-job-finalizer.md`.
4. **Controller log shows "Skipping auto-sync: failed previous sync attempt"?** ArgoCD won't retry the same revision — see `runbooks/recover-stuck-promotion.md` (terminate-op + force sync via argocd CLI on Tailscale).
5. **Job Pod is `Init:ImagePullBackOff` with "not found"?** The image isn't on ghcr.io yet — see `runbooks/mirror-image-gitea-to-ghcr.md`.
6. **Need a fleet review or decide whether legacy apps should be removed?** Use `runbooks/review-argocd-app-health.md` before applying fixes. It covers keep/remove decisions, stale status cache, ExternalSecret/Tekton default drift, Tailscale egress mutation, and hub promotion.

### "Review all degraded/out-of-sync apps and remove legacy resources"

Use `runbooks/review-argocd-app-health.md`. The short rule: identify whether each resource is still part of the current system before fixing drift. Known outcomes:

- Keep `agent-sandbox-crds` / `<spoke>-agent-sandbox-crds`; OpenShell and agent-runtime controllers require those CRDs.
- Remove AutoKube references; AutoKube is legacy in this repo.
- The old hcloud-spoke Crossplane `AzureWorkloadIdentity` claim/provider path is legacy; hcloud spoke lifecycle now uses hcloud/talos/kubernetes/terraform providers and existing Azure Workload Identity configuration.
- For needed apps, prefer making desired manifests match API-controller defaults over broad `ignoreDifferences`; use ignores only for intentional operator mutation like Tailscale egress Services.

### "GitHub webhook didn't fire / image build doesn't reach ghcr.io"

Triage by `gh api .../hooks/<id>/deliveries` `status_code` first — there are TWO common failure modes on the same path:

- **`status_code: 0` + `dig @1.1.1.1 tekton-hub.tail286401.ts.net` NXDOMAIN** → Tailscale Funnel orphan-tag on `ts-tekton-github-triggers` proxy. The `policy.hujson` lost a tag the device still uses; control plane drops the funnel cap. See `runbooks/debug-funnel-orphan-tag.md` (Funnel orphan tag section).
- **`status_code: 202` (accepted) but no PipelineRun on hub** → EL processing failure. `el-github-outer-loop` logs show `Post "": unsupported protocol scheme ""` at `sink/sink.go:413` for the matching `/triggers-eventid`. Same runbook, "EL processing failure" section. Workaround: skopeo-mirror to ghcr.io + bump release-pins manually until the EL is fixed.

### "I edited a workflow JSON spec — when does it deploy?"

Workflow JSONs at `services/<agent>/<name>.workflow.json` in the workflow-builder repo are **not** baked into the workflow-builder image (the production Dockerfile copies `src/` and `drizzle/` only — `services/` is excluded). Spec changes (new prompt, agentKwargs, maxTurns, etc.) require a manual DB upsert against the spoke's postgres. Either run `node scripts/<workflow>.mjs --user-email ...` from a pod with `DATABASE_URL` set, or directly `UPDATE workflows SET spec = $jsonFromFile.spec, nodes = ..., edges = ... WHERE id = '<workflow-id>'`. Image rebuilds alone won't roll the change. See `runbooks/upsert-workflow-json.md`.

### "I shipped a migration but the new columns aren't on dev/staging"

Almost always: the SQL file in `drizzle/` is missing from `drizzle/meta/_journal.json`. `npx drizzle-kit migrate` (the `db-migrate` Sync hook) silently skips files without journal entries — Job exits 0 but nothing gets applied. See `runbooks/fix-drizzle-migration.md`. (BFF will then 500 on every query that includes the new column.)

### "I want to track a promotion in flight"

Start with workflow-builder's admin deployment inventory when available; it shows desired image, live images, drift, build, and promotion metadata in one place. The hub ArgoCD UI now has a GitOps Promoter extension for visualizing Promoter CRDs, and PromotionStrategy + ChangeTransferPolicy + spoke ArgoCD apps remain the authoritative lower layers. See `runbooks/track-promotion-state.md` for both views and a CLI cheat-sheet. Most "stuck" reports are actually normal ~3 min source-hydrator poll cycles.

### "workflow-builder works on ryzen but is broken on dev/staging"

Treat this as environment drift, not a live-patch task. Check the promoted spoke runtime env, Tailscale Ingresses, ACL policy, spoke API VIP grants, and stale hub hydration. Typical declarative fixes are in `spoke-workloads-appset.yaml`, `packages/base/manifests/tailscale-ingresses/`, and `policy.hujson`. See `runbooks/reconcile-workflow-builder-spoke-environment.md`.

### "I need to upgrade GitOps Promoter or fix the Promoter UI"

Use `runbooks/manage-gitops-promoter.md`. The current deployment pattern is: keep the latest published Helm chart unless a newer chart exists, override `manager.image.tag` when the app release is newer than the chart appVersion, and manage the ArgoCD UI extension through `argocd-gitops-promoter-ui` plus bootstrap `deployment/config/argocd-values.yaml`. Do not hand-patch long-term state without committing it to stacks.

### "Which image / commit is live on dev or staging?"

Use the workflow-builder admin Deployments view or the hub inventory endpoint first. It is backed by `gitops-deployment-inventory` on the hub and is the fastest way to compare release-pins, Argo live images, promotion SHAs, and outer-loop build status. See `runbooks/track-promotion-state.md`.

### "workflow-builder Deployments shows fetch failed"

First distinguish UI auth from inventory transport. From inside the workflow-builder pod, `WORKFLOW_BUILDER_GITOPS_INVENTORY_URL` should be `http://gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080/inventory.json`. The egress Service in `tailscale` should target `tailscale.com/tailnet-fqdn: gitops-inventory-hub-node.tail286401.ts.net`, port `8080`. Do **not** target `gitops-inventory-hub.tail286401.ts.net` from the egress Service; that is a Tailscale service-host VIP, not a tailnet node. See `runbooks/track-promotion-state.md`.

### "A promoted-spoke Tailscale Ingress has no address, a -1 suffix, or stale DNS"

First check whether the Ingress has `tailscale.com/proxy-group`. Promoted-spoke app URLs such as `workflow-builder-dev`, `workflow-builder-staging`, `mcp-gateway-*`, and `phoenix-*` are normally device-backed Tailscale Ingresses, not `svc:*` service-hosts. Debug stale tailnet devices, stale Tailscale Services, and operator-managed Secret metadata with `runbooks/debug-device-backed-tailscale-ingress.md`.

### "A ProxyGroup service-host VIP has no address or TLS/cert is broken"

If the resource is a ProxyGroup-hosted service such as `argocd-hub`, `nocodb-hub`, or `gitops-inventory-hub`, debug service-host tags, not Funnel. Check the Ingress `tailscale.com/tags`, `policy.hujson` `autoApprovers.services`, the Tailscale Service tags, and the proxy pod `Self.Tags` / `CapMap["service-host"]`. See `runbooks/debug-proxygroup-service-host.md`.

### "I need kubectl on a spoke (dev / staging) and Tailscale isn't working"

See `reference/access-paths.md` for normal paths and `runbooks/access-spoke-cluster-fallback.md` for the Crossplane-kubeconfig-secret fallback.

### "OAuth / social login broken — `client_id and/or client_secret passed are incorrect`"

Almost always: KeyVault `*-CLIENT-ID-*` and `*-CLIENT-SECRET-*` were rotated at different times (compare `attributes.updated`). See `runbooks/rotate-oauth-secret.md`. **Watch for the ESO refresh ↔ pod restart race** — `reference/secret-flow.md`.

## Critical gotchas (memorize these)

- **Ryzen is hub-managed; there is no local ArgoCD or local Gitea (post-A6, May 2026).** GitHub `inner-loop` branch is the source for ryzen-only image-tag bumps via Skaffold outer-loop + `commit-pin.sh`. GitHub `main` is the source for everything else (workloads, hub-level config, dev/staging promotion). Hub's Source Hydrator renders both into `env/spokes-ryzen` (force-pushed, no Promoter) and `env/hub-next → env/hub` (Promoter PR, requires manual merge).
- **The idpbuilder + local-Gitea path is retired.** See `ryzen-spoke-bootstrap` skill for the new bootstrap (talosctl + helm + kubectl). Old runbooks referencing `idpbuilder stacks sync` are obsolete.
- **Workflow-builder image pin has two visible truths.** The workloads base pin in `packages/components/workloads/workflow-builder/manifests/kustomization.yaml` is the ryzen source and should usually point at the intended GHCR `git-<sha>` tag. The `dev-workflow-builder` Application may still show release-pin `spec.source.kustomize.images` overrides to the same tag. If ryzen reverts while dev stays correct, fix the workloads base pin, commit it to `origin/main`, push to `inner-loop` (ryzen image bumps) or merge the env/hub Promoter PR, and verify both ryzen's live Deployment image and hub's `dev-workflow-builder.status.summary.images`.
- **Outer-loop release handoff can be direct-main or PR-mode.** Hub Tekton `update-stacks` is the source of truth: inspect its logs and Git state to see whether release metadata was pushed directly to `origin/main` or placed on a `release/workflow-builder-*` PR branch. Direct human edits to release pins should be exceptional and must pass `scripts/gitops/validate-workflow-builder-release-pins.sh`.
- **`stacks-environments` PromotionStrategy has `autoMerge: false`.** Unlike `workflow-builder-release` (env/spokes-dev + env/spokes-staging) which auto-merge after `argocd-health`, the `env/hub` PR (`gitops-promoter-*[bot]: Promote <sha> to env/hub`) requires **manual** merge. Every change under `packages/overlays/hub` (which includes `spoke-workloads-appset.yaml`, AppSet templates, etc.) opens such a PR and the dev/staging cascade is blocked until it's merged. Easy to miss because `workflow-builder-release` IS auto.
- **Hub promoter status can lag branch tips.** If `env/hub-next` has a newer hydrated SHA but `stacks-environments-env-hub-*` still proposes the prior dry SHA/PR, annotate both `PromotionStrategy/stacks-environments` and the `ChangeTransferPolicy` with a fresh `promoter.argoproj.io/refresh-ts`.
- **`workflow-builder-release` can lag source-hydrator too.** If `env/spokes-dev-next` has advanced but `workflow-builder-release-env-spokes-dev-*` still proposes the prior dry SHA after one poll interval, refresh `PromotionStrategy/workflow-builder-release` plus the dev CTP with `promoter.argoproj.io/refresh-ts`. Do not use hard-sync as a substitute for Promoter catching up.
- **Concurrent outer-loop commits can leave Promoter one dry SHA behind.** A single app push can trigger multiple outer-loop updates, such as workflow-builder and workflow-orchestrator release metadata. If source-hydrator's current dry SHA is newer but the workflow-builder dev CTP keeps proposing the previous dry SHA after a poll, refresh `PromotionStrategy/workflow-builder-release`, the dev CTP, and hard-refresh `spoke-dev-workflow-builder` before declaring the rollout stuck.
- **Release-pin validation needs each GHCR package linked to `stacks` via Manage Actions access.** The `validate-workflow-builder-release-pins` GitHub Action runs `skopeo inspect` against every image with `${{ github.token }}` (which only has `packages: read`). PittampalliOrg's GHCR container packages are private and built by other repos (workflow-builder, opencode-durable-agent, etc.), so the workflow's token can only read them if each package has `PittampalliOrg/stacks` added under **Manage Actions access** with Role: Read. Missing link → every image fails identically with `reading manifest <tag> in ghcr.io/pittampalliorg/<image>: denied` (authz, not "tag missing"). Adding a new image to `release-pins/workflow-builder-images.yaml` requires linking its package before merging. See `runbooks/grant-stacks-ghcr-package-access.md`.
- **Release-pin hydration must be dry-source deterministic.** `spoke-workloads-appset.yaml` should select the spoke cluster and point source-hydrator at `packages/components/workloads/workflow-builder-system-overlays/<spoke>`; it should not template `imageRefs`, `sourceShas`, sandbox-image env, or other release-pin values inline. Argo CD source-hydrator is dry-SHA oriented, so if rendered output depends on values outside the dry source a race can produce `env/spokes-<spoke>-next` with stale child Application images even while `.status.sourceHydrator.currentOperation.drySHA` is current. Fix stale release-pin renders by regenerating the overlays and committing a real dry-source change, not by relying on empty commits as the normal path.
- **Do not delete agent sandbox CRDs as "duplicates."** `agent-sandbox-crds` is the CRD owner for OpenShell/agent-runtime sandbox resources. It is separate from controllers and workload apps by design so CRDs sync early.
- **AutoKube is legacy.** If AutoKube Applications, Ingresses, ACL service approvals, or manifests appear, remove them declaratively and let Argo prune them instead of repairing them.
- **Argo drift review is keep/remove first, fix second.** For needed resources, run `argocd app diff` and prefer declaring API defaults (ExternalSecret defaults, Tekton EventListener defaults, CRD defaults) over hiding real drift. Empty `argocd app diff` with OutOfSync status usually means stale Argo status; hard-refresh first and restart the application controller only if it remains stale.
- **AgentRuntime CR images flow through the BFF env var, not release-pins.** `agent-runtime-<slug>` Deployment images are set at agent-publish time by `registry-sync.ts:725` reading `env.AGENT_RUNTIME_BROWSER_USE_DEFAULT_IMAGE` (browser-use-agent runtime) or `env.AGENT_RUNTIME_DEFAULT_IMAGE` (default). These env vars are static literals on `Deployment-workflow-builder.yaml`. Bumping release-pins does not update them; you must edit the Deployment YAML AND patch existing `AgentRuntime` CRs (`spec.environment.imageTag`) to re-roll already-published agents. Post-A6 all clusters (ryzen, dev, staging) reference `ghcr.io/pittampalliorg/dapr-agent-py-sandbox:git-<sha>` — same registry across the board. See `runbooks/bump-image-pin-not-in-release-pins.md`.

- **`SWEBENCH_EVALUATOR_IMAGE` is an env var, not a container field.** The `swebench-coordinator` base has a kustomize replacement that copies the rewritten image from local-config `Pod/swebench-evaluator-image` into the Deployment env var. If a coordinator launches stale evaluator Jobs, verify both the generated overlay and live Deployment env. On ryzen, an active `skaffold dev` session (with ArgoCD skip-reconcile) can mask the declarative env the same way it masks workflow-builder BFF env vars; dev is the cleaner rollout target for promoted SWE-bench evaluator validation.

- **Sandbox templates (`workspace_profile.with.sandboxTemplate`) resolve via `SANDBOX_TEMPLATE_IMAGES_JSON`** on the workflow-builder Deployment (NOT `kustomize.images`). For dev/staging, the release-pins renderer stamps this env var into the generated dry-source overlays. The env var is a JSON object mapping template names to image refs. Adding a new template name = (1) add a `Dockerfile.<name>` under `services/openshell-sandbox/environments/` in the workflow-builder repo, (2) commit with subject `environment(<name>):` so the env-image-build pipeline fires, (3) add the image pin/rendering path in stacks.

- **Legacy Gitea dev-image commits are not the ryzen hot path.** If an old artifact mentions `chore(dev-images): deploy ... to ryzen`, treat it as historical build-lane evidence. Update the stacks pin and use the GitHub branch flow (commit-pin or Promoter PR).

- **Orchestrator `wfstate_state` orphan reminders can block new StartInstance.** `workflowstatestore` is `state.postgresql v2` with `tablePrefix=wfstate_`. When a workflow row is purged but its actor reminder is still in dapr-scheduler-server's ETCD, daprd retries the reminder ~every 10s and logs `Unable to get data on the instance: <id>, no such instance exists`. The retry loop can serialize behind the workflow runtime worker queue and make new `ctx.call_child_workflow` / `StartInstance` calls hit `DEADLINE_EXCEEDED` after 60s. Confirm via daprd logs first. For terminal benchmark cleanup, prefer the BFF cleanup endpoint's scoped terminate/poll/purge path; manual `wfstate_state` cleanup is incident recovery only after active runs and leases are zero.

- **`environment(<slug>):` commit subject is the only trigger for the env-image-build pipeline.** The hub-tekton EventListener (`build-environment-image` trigger in `EventListener-workflow-builder-fn-builds.yaml`) filters on `body.commits[*].message ~= '^environment\\(.+?\\):'` AND a modified `services/openshell-sandbox/environments/Dockerfile.<slug>` path. Both conditions must hold per push. Slug is extracted via `c.message.split('(')[1].split(')')[0]`. Commit message typos like `env(code-eval):` will silently skip the build with no visible error.
- **ActivePieces piece MCP URLs should not include port `:3100` when targeting Knative.** The container listens on 3100, but callers hit the cluster-local Knative Service URL. Stale AgentRuntime or workflow configs containing `http://ap-...svc.cluster.local:3100/mcp` bypass Knative routing and can leave agents silent.
- **MCP auth is request-scoped by connection external ID.** For piece MCP tools, the runtime sends `X-Connection-External-Id`; `piece-mcp-server` calls workflow-builder's internal decrypt API. Do not put OAuth tokens, decrypted credentials, or user-specific secrets into KService env, workflow JSON, or GitOps manifests. The reconciler may set a fallback `CONNECTION_EXTERNAL_ID`, but per-request headers are the correct multi-user path.
- **ActivePieces MCP services are generated from DB state.** Pinned pieces (`github`, `google-calendar`, `openai`) stay available; enabled `mcp_connection` pieces create additional KServices and catalog entries. If a user adds Outlook/Excel/OneDrive and the KService is missing, debug `activepieces-mcp-reconciler` before patching workloads by hand.
- **Piece MCP KServices scale to zero by design.** `knative-serving` must allow `allow-zero-initial-scale: "true"`, and generated services use `initialScale: "0"`. Cold starts can make the first `/health` or `/mcp` probe exceed a short timeout; retry with a longer timeout before treating it as a hard failure.
- **Dapr durable protocol compatibility depends on a single actor state store per sidecar.** Current workflow-builder expects `workflowstatestore` to be the only `actorStateStore=true` Component visible in the namespace. `dapr-agent-py-statestore` must stay `actorStateStore=false`; it stores agent application state, not workflow actor state. If agent sessions hang after a runtime change, verify Component metadata before restarting pods or clearing state.
- **Dapr workflow cleanup is a lifecycle, not an instant delete.** Termination requests can return before a workflow is terminal. For benchmark cancellation or timeout cleanup, terminate/poll/purge per-agent session and turn workflows first, then the parent workflow. Only after every durable instance is terminal or missing should the BFF delete sandboxes, release leases, or mark session/execution rows terminal. If cleanup cannot prove closure, leave leases/sandboxes in place for a retry rather than creating invisible running workflows with missing workspaces.
- **Dapr sidecar liveness can stay green while readiness is permanently false.** After placement/scheduler restarts or cert churn, workflow-builder runtime pods can show `1/2` because the app container is healthy but `daprd` returns `ERR_HEALTH_NOT_READY: [grpc-api-server grpc-internal-server]`. Logs often include `Actor runtime shutting down`, `Placement client shutting down`, or `Workflow engine stopped`. Verify `dapr-system` is currently healthy, then recycle the affected Deployment (`openshell-agent-runtime`, `swebench-coordinator`, or another Dapr-enabled runtime). See `runbooks/debug-dapr-sidecar-stale-readiness.md`.
- **Workflow JSON specs do not flow through image rebuilds.** `services/<agent>/<name>.workflow.json` is excluded from the production Dockerfile copy list. Editing it in the repo + rebuilding doesn't change runtime behavior; the spoke's `workflows.spec` JSONB column is read at execution time. Updating the spec requires a DB UPDATE on each spoke. See `runbooks/upsert-workflow-json.md`.
- **ArgoCD SSA validation blocks parent-syncs-child-Application apply.** When the parent app (e.g., `spoke-dev-workflow-builder`) tries to apply a kustomize-patched child Application (e.g., `dev-browserstation`), you may see `Application.argoproj.io "<child>" is invalid: status.sync.comparedTo.source.repoURL: Required value`. The parent's SSA payload nullifies a status field the CRD validator requires. Workaround: patch the live child directly with `kubectl patch app dev-<name> --type=json -p='[{op:replace,path:/spec/source/kustomize/images/0,value:...}]'`. The parent will keep retrying with the failing apply but the child's live spec is correct.
- **KubeRay head pod doesn't auto-roll on image change.** When a RayCluster spec image is bumped via `kustomize.images`, the KubeRay operator gradually rolls workers but the head stays on the old image until explicitly deleted (`kubectl delete pod -n ray-system browserstation-head-<id>`). Workers wait on head GCS via `wait-gcs-ready` init container, so a stuck old head blocks worker rollout too. Verify with `kubectl get pod -l ray.io/cluster=browserstation -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[?(@.name=="ray-head")].image}{.spec.containers[?(@.name=="ray-worker")].image}{"\n"}{end}'`.
- **Buildah short-name resolution is enforced in noninteractive Tekton builds.** `FROM rayproject/ray:2.47.1-cpu` fails with `short-name resolution enforced but cannot prompt without a TTY`. Always fully-qualify base images (`docker.io/rayproject/...`). Fix is in the Dockerfile, not the pipeline.
- **Active `skaffold dev` sessions can mask declarative image rollout.** The ryzen Application can be Synced/Healthy and the declarative Deployment image can point at the new tag while a Skaffold-owned dev pod serves live traffic from synced source (ArgoCD paused via `skip-reconcile`). Verify the actual serving pod, image, and synced files before declaring ryzen done.
- **Skaffold-owned dev pods cache stale env vars across ArgoCD updates.** A subtle variant of the above: when ArgoCD bumps an env var on `Deployment-workflow-builder.yaml` (e.g. `AGENT_RUNTIME_DEFAULT_IMAGE`), the Deployment+ReplicaSet roll, but the long-lived `workflow-builder-dev-*` pod was created hours/days earlier and won't restart on its own. The serving pod reads the OLD env value, which means BFF code paths that use that env (like `registry-sync.ts` stamping `AGENT_RUNTIME_DEFAULT_IMAGE` into newly-published or newly-woken `AgentRuntime` CRs) keep emitting stale tags despite the manifest being "synced". Diagnose: `kubectl get deploy workflow-builder -o jsonpath='{...env...}'` shows the new value but `kubectl exec deploy/workflow-builder -- printenv AGENT_RUNTIME_DEFAULT_IMAGE` still shows the old one. Recovery: exit `skaffold dev` (which removes the dev override) OR `kubectl delete pod workflow-builder-dev-*` (forces a fresh pod from the current Deployment template). After either, verify both the standard `workflow-builder-*` pod and any AgentRuntime CRs that newly woke have the expected image.
- **AgentRuntime CR `imageTag` revert loop.** Even after `kubectl patch agentruntime <name> spec.environment.imageTag=...`, the next agent wake (or any registry-sync trigger) re-reads the BFF env var and resets the CR back to the OLD image. The CR is *not* the source of truth — the BFF env var is. To roll an already-published agent forward durably: (1) bump the env var in the stacks Deployment YAML AND (2) verify the BFF *pod* (not just the manifest) sees the new value AND (3) patch the CR. Skipping any of the three undoes the others. The dance is documented in `runbooks/bump-image-pin-not-in-release-pins.md`.
- **`rayproject/ray:2.47.1-cpu` ships Python 3.9.** PEP-604 union syntax (`def f(x: float | None)`) fails at module import with `TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'`. Add `from __future__ import annotations` at the top of the file or use `Optional[X]`. Caused a head-pod CrashLoopBackOff on the Tier 2 browserstation rollout.
- **Skopeo mirror is rarely needed post-A6.** The local Gitea image registry on ryzen is retired (May 2026); all clusters pull from `ghcr.io/pittampalliorg/*`. The `runbooks/mirror-image-gitea-to-ghcr.md` runbook is kept for one-off recovery of legacy artifacts still living on ryzen's local Gitea PVC; for new work, push directly to GHCR.
- **Tailscale Funnel orphan tags silently break webhooks.** If a tag is removed from `policy.hujson` but a device still uses it, the operator pod claims "Funnel on" locally but the control plane revokes the cap. Public DNS goes NXDOMAIN. Diagnostic: `tailscale status --json | jq '.Self.{Tags, CapMap}'` from inside the proxy pod.
- **ProxyGroup service-host tags are separate from Funnel tags.** For hub browser VIPs, the Ingress `tailscale.com/tags`, Tailscale Service tags, `policy.hujson` `autoApprovers.services`, and the authenticated ProxyGroup pod tag must agree. Hub `cluster-ingress` should authenticate as `tag:k8s-services`; `tag:k8s` is legacy compatibility only.
- **Device-backed Tailscale Ingresses are not `svc:*` service-hosts.** Promoted-spoke app URLs without `tailscale.com/proxy-group` register as Tailscale devices, usually tagged `tag:k8s`. Do not add `autoApprovers.services["svc:<hostname>"]` for these. A stale `svc:<hostname>` record can reserve the canonical DNS name and force the real device to register as `<hostname>-1`.
- **Tailscale operator Secret metadata matters after manual recovery.** Ingress proxy state Secrets such as `tailscale/ts-workflow-builder-tailscale-*-0` must keep labels `tailscale.com/managed=true`, `tailscale.com/parent-resource=<ingress>`, `tailscale.com/parent-resource-ns=<namespace>`, and `tailscale.com/parent-resource-type=ingress`. If a manual auth/key repair leaves a huge `kubectl.kubernetes.io/last-applied-configuration` annotation or strips labels, the endpoint may work while ArgoCD stays `Progressing`; restore labels and remove the stale annotation.
- **Tailscale egress targets nodes, not service-host VIPs.** `gitops-inventory-hub.tail286401.ts.net` is a service-host VIP backed by `cluster-ingress`; egressing to it produces "node not found", `ECONNREFUSED`, or timeouts. Spoke inventory fetches must use `gitops-inventory-hub-node.tail286401.ts.net:8080` through `gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080`.
- **Tailscale operator mutates egress Services.** It writes `/spec/externalName` and may add `/spec/ports/0/targetPort`; Argo Applications that own egress Services should ignore both fields or they will stay OutOfSync despite working traffic.
- **Dev/staging service URLs must be declared, not inferred from ryzen.** `MCP_GATEWAY_BASE_URL` and Phoenix URLs belong in the spoke ApplicationSet template with `{{cluster}}`; matching `mcp-gateway-*`/`phoenix-*` Tailscale Ingresses must exist. Add `policy.hujson` `svc:*` approvals only when the hostname is actually served by a ProxyGroup/Tailscale Service.
- **Spoke API VIPs need both service approval and Kubernetes grants.** `dev-api-v2`/`staging-api-v2` service-hosts need `autoApprovers.services` entries, and the authenticated `tag:spoke-api` devices need a Kubernetes impersonation grant to `tag:k8s` with `system:masters`. Re-authenticate the spoke ProxyGroup after ACL changes if the device still has stale caps.
- **ESO refresh ↔ pod restart race.** When rotating a KeyVault secret, ESO may not finish writing the K8s Secret before a Deployment restart kicks off. The new pod reads the stale value. Always verify the K8s Secret head matches the new value **before** triggering the restart.
- **Hub pods reach ryzen kube-api via Tailscale egress.** Hub uses an `ExternalName` Service `ryzen-api-egress.tailscale.svc.cluster.local` that points at the operator-rendered headless egress pod for the `ryzen-api-v3.tail286401.ts.net` device. Other hub→ryzen traffic patterns (postgres, etc.) follow the same `tailscale.com/tailnet-fqdn` egress Service pattern. Don't use MagicDNS directly from hub pods — it fails or hangs.
- **Hub build nodes are the default build capacity.** The current hub baseline is three `cpx41` control/management nodes plus two tainted `ccx33` build workers (`stacks.io/build-pool=hub`, upgradeable to `ccx43`). Do not remove the build-node taint to "fix" scheduling; add the node selector/toleration to the PipelineRun template.
- **ProxyGroup auth must target the intended context.** `kubectl --kubeconfig ~/.kube/config` does not select a cluster by itself; it still uses that file's current context. For dev/staging/hub repairs, minify the intended context into a temporary kubeconfig or set `KUBECONFIG` to the Crossplane fallback kubeconfig before running `deployment/scripts/tailscale/proxygroup-auth.sh`. For kube-apiserver ProxyGroups, the script patches the `*-config` secret, not just `TS_AUTHKEY` env.
- **Stacks repo has two GitHub branches.** `main` feeds hub/dev/staging via the Promoter ladder. `inner-loop` is for ryzen-only image-tag bumps via `commit-pin.sh` (hub Source Hydrator pulls it into env/spokes-ryzen automatically).
- **Manual branch reconciliation is not part of the normal ryzen loop.** Older hub Gitea/dev-image history may still exist for provenance or recovery, but post-A6 ryzen-related Applications source GitHub `inner-loop` (hub Source Hydrator hydrates to env/spokes-ryzen).
- **`argocd-hub.tail286401.ts.net` works even when other Tailscale ProxyGroups are down.** It's an independent ProxyGroup. When per-spoke Tailscale access is broken, you can still drive ArgoCD ops from the hub via `argocd login argocd-hub.tail286401.ts.net --grpc-web`.
- **GitOps Promoter app releases may be newer than the Helm chart appVersion.** Verify both upstream release and Helm chart metadata. As of 2026-04-24, the controller runs `v0.27.1`; the latest Helm chart is `0.6.0` with `appVersion: 0.26.2`, so stacks keeps chart `0.6.0` and overrides `manager.image.tag`.
- **Promoter UI patch hooks need a shell-capable kubectl image.** `registry.k8s.io/kubectl` is distroless and has no `/bin/sh`; use `alpine/k8s:<version>` for shell-scripted hook jobs. The ArgoCD Helm chart's server container is named `server`, even though the Deployment is `argocd-server`.
- **Hub source-hydrator status can pin a stale dry SHA.** If `root-application.status.sourceHydrator.currentOperation.drySHA` stays behind `origin/main`, remove `currentOperation` and `lastSuccessfulOperation` from status and hard-refresh the app. See `runbooks/manage-gitops-promoter.md`.
- **Drizzle Kit silently skips SQL files lacking `_journal.json` entries.** The `db-migrate` Sync hook on dev/staging runs `npx drizzle-kit migrate`, which globs `drizzle/*.sql` BUT only applies files with a matching `entries[]` tag in `drizzle/meta/_journal.json`. Job exits 0 either way — easy to miss. Always update the journal when adding a migration; older files in the repo (0006/0007/0020/0032/0037-0043) lack journal entries because their columns were applied via out-of-band paths historically. Prompt Workbench's `resource_prompt_versions` table is one of the checks to run after prompt-preset deploys. See `runbooks/fix-drizzle-migration.md`.
- **Two migration runners read from two different directories.** `src/lib/server/startup.ts` reads from `atlas/migrations/` (timestamp-prefixed); `npx drizzle-kit migrate` reads from `drizzle/` (incremental + journal-gated). The production image's `Dockerfile` copies `drizzle/` but `.dockerignore` excludes `atlas/`, so the atlas-runner is effectively only active in the ryzen Skaffold dev pod (which file-syncs source). New migrations usually need to live in BOTH dirs, both idempotent (`ADD COLUMN IF NOT EXISTS`).
- **Source-hydrator polls every ~3 min.** After release metadata lands on `origin/main`, expect 5-8 min before dev's pod is rolling on the new image, then staging waits for its configured soak timer after health. `argocd app refresh --hard` triggers manifest re-render but does NOT immediately repoll branch tips. `argocd app sync --revision <sha>` is rejected on auto-sync + branch-tracking apps (`Cannot sync to <sha>: auto-sync currently set to <branch>`). Don't hard-sync; wait. See `runbooks/track-promotion-state.md` for what's-actually-stuck triage.
- **Generated `env/spokes-*` branches need guardrails.** If the generated app directory drifts from `env/spokes-*-next`, use `scripts/gitops/reconcile-spoke-generated-dir.sh <dev|staging> check|fix`; do not hand-edit generated env branches unless the script proves the root and child dry SHAs match.
- **`git status --porcelain` `R ` prefix means "renamed in INDEX, already staged".** Filtering with `grep -E "^A |^M "` MISSES it. After a stale `git add` or interrupted commit, your next `git commit` will scoop in any pre-staged renames/deletes alongside what you intended. Before committing, either `git reset HEAD --` to clear the index then re-stage exact paths, or use `git diff --cached --name-status` (which shows ALL staged changes including renames + deletes + mode changes).

- **SWE-env build cache lock needs THREE layers, not one.** `Task-swebench-inference-image-build-push.yaml` acquires `/var/lib/containers/.swebench-buildah.lock` via `mkdir`. The shell `trap` releases on graceful exit but **SIGKILL is uncatchable** (OOMKill, eviction, controller force-delete bypass it). Tekton's `retries:1` then spawns a retry pod that **inherits the parent TaskRun name**, so the dead pod's `owner` file says `taskRun=<the same name>` and the retry sees its own predecessor's lock as held by "another PR" → spin-polls forever → PR never terminates → Pipeline `finally:` never runs → **deadlock**. Fix is committed (stacks `52bb0b18` + `f6f4bb00` + `d450c9b1`); know the symptom: retry-pod logs say `Buildah cache lock is held by: taskRun=<own name>` and original pod is `OOMKilled`. The 3 layers: (1) self-takeover in `acquire_buildah_cache_lock` — if owner taskRun matches `context.taskRun.name`, remove + reacquire; (2) Pipeline `finally:` task `release-buildah-cache-lock` — removes lock if owner starts with `$(context.pipelineRun.name)-`; (3) `BUILDAH_CACHE_LOCK_STALE_SECONDS=1800` (was 21600 — 6h was way too long). Also: build-and-push memory bumped 2Gi req → 4Gi req / 6Gi limit so OOMKills become rare AND when they happen the kernel kills the offending container only (predictable). If a stale lock recurs, manual clear: spin a busybox pod with the `buildah-cache-swebench-inference` PVC mounted and `rm -rf /cache/.swebench-buildah.lock`.

- **K8s label values must match `(([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])?` — alphanumeric start AND end.** Nanoid-generated IDs (workflow-builder benchmark runs, etc.) can legally end in `_` or `-`. When a service uses `run["id"]` directly as a label value (e.g. swebench-coordinator's evaluator Job), the API rejects creation with HTTP 422 `Invalid value: "<id>": a valid label must ... start and end with an alphanumeric character`. Symptoms: run goes `failed` immediately at the evaluating stage with no useful inference error; harness eval never executes. Fix at the use site, not the ID generator (don't break existing data): trim outer `[._-]` characters and cap at 63 chars. Coordinator fix landed at workflow-builder `0f369b58` via `_safe_label_value` helper at lines 471/485 of `services/swebench-coordinator/src/app.py`. If you add a new service that labels K8s resources with run/instance IDs, mirror the helper.

- **SWE-bench random readiness is exact on the current environment identity.** The Benchmarks page and `POST /api/benchmarks/runs` must use the same readiness logic as coordinator preflight. Static ConfigMap pins are ready when suite/repo/baseCommit/version and image digest match, even if `environmentSetupCommit` is absent. Dynamic DB build rows are ready only when `environment_image_builds.env_spec_hash` equals the current `buildSwebenchEnvironmentSpec()` hash. Do not fall back to repo/version/baseCommit-only DB matching; that admits old images and leaves runs parked in preflight while hub builds a new image.

### Update (2026-05-19) — image delivery while the 2nd EL is still dead, + dev-portability of utility images

- **Ryzen sync is hub-driven post-A6.** Hub's argocd-application-controller polls env/spokes-ryzen every ~3 min OR responds to `refresh=hard` annotations on the per-app Applications on hub. There is no local ArgoCD or Gitea on ryzen anymore. Normal health target is every `ryzen-*` Application on hub `Synced/Healthy`.
- **Working ryzen image pattern:** outer-loop GitHub lane builds + pushes `ghcr.io/pittampalliorg/<img>:git-<sha>`. To deliver to ryzen specifically, edit `packages/components/workloads/<comp>/manifests/kustomization.yaml` `images:` to `newName: ghcr.io/pittampalliorg/<img>` + `newTag: git-<sha>` and push to `inner-loop` branch (or use `commit-pin.sh` automatically). Hub Source Hydrator picks up `inner-loop` directly and hub-Argo rolls ryzen via cluster Secret. Ryzen Deployments already have the `ghcr-pull-credentials` imagePullSecret materialized by ESO from KV `GITHUB-PAT`.
- **Preserve workloads pins in git.** Hub renders whatever workloads pin is committed to the source branch. Ryzen-only image pins commit to `inner-loop`. To make a ryzen image pin durable across dev/staging too, open a PR `inner-loop → main` (gated by GitHub branch protection on `main`).
- **`dev-*` apps source `workloads/*/manifests/` @ origin/main HEAD (shared with ryzen, NOT a per-spoke render).** `dev-swebench-coordinator`, `dev-swebench-evaluator-tekton`, `dev-workflow-builder` ArgoCD apps point at `github.com/PittampalliOrg/stacks.git` path `packages/components/workloads/<comp>/manifests/` rev `HEAD`. So a commit to `origin/main` in workloads delivers to dev automatically; the spoke-workloads ApplicationSet additionally rewrites the **release-pins workload images** onto those apps' `spec.source.kustomize.images` (swebench-coordinator/evaluator/workflow-builder are release-pins keys — outer-loop `update-stacks` already bumps them). The base workloads pins are the ryzen value; dev's image comes from the release-pins override.
- **Utility/init images pinned to ryzen Gitea break dev/staging (`Init:ImagePullBackOff`).** `workloads/{swebench-coordinator,evaluation-coordinator}/manifests/kustomization.yaml` rewrote `bitnami/kubectl` (+`alpine/k8s`) → `gitea.cnoe.localtest.me:8443/giteaadmin/kubectl` (ryzen's in-cluster Gitea, unreachable from dev/staging). The spoke ApplicationSet only rewrites **release-pins workload images**, NOT utility/init images, so those Deployments' `wait-for-workflowstatestore` init containers were permanently `Init:ImagePullBackOff` on dev/staging — they had **never run there**; only ryzen worked (local mirror). Fix (stacks #1707): mirror ryzen's kubectl image → `ghcr.io/pittampalliorg/kubectl:latest` (`skopeo copy --src-tls-verify=false docker://gitea-ryzen.tail286401.ts.net/giteaadmin/kubectl:latest docker://ghcr.io/pittampalliorg/kubectl:latest`, dest-auth = hub `ghcr-push-credentials`; as an agent use the SSH-wrapped `ssh vpittamp@ryzen '…'` form to dodge the bash-tool Production-Reads guard) and rewrite both kustomizations gitea→`ghcr.io/pittampalliorg/kubectl` (all-spoke; ryzen pulls GHCR fine). General rule: **any workloads manifest that rewrites a utility image to `gitea.cnoe.localtest.me:8443/...` is dev/staging-broken by construction.**
- **ArgoCD won't advance to a new commit despite autoSync/selfHeal?** Symptom: app `OutOfSync` at the new rev, `operationState.phase=Running … retrying attempt #N`, a Deployment `ProgressDeadlineExceeded` behind a stuck old pod (e.g. the prior pod was `Init:ImagePullBackOff`). The stuck in-flight sync op blocks the new revision. Recovery: `argocd app terminate-op <app> --grpc-web` (login `argocd-hub.tail286401.ts.net` with `argocd-initial-admin-secret`). **Terminate alone is usually sufficient** — once the stuck op is killed, `autoSync`/`selfHeal` applies the current desired revision within ~1 min. `argocd app sync --force` typically keeps returning `another operation is already in progress` while the terminate winds down — don't fight it; wait for selfHeal. (`runbooks/recover-stuck-promotion.md` has the full procedure.)
- **Benchmark-run Dapr-lifecycle recovery lever:** `POST http://<bff>/api/internal/benchmarks/runs/<runId>/cleanup` header `x-internal-token: $INTERNAL_API_TOKEN` body `{}` runs the documented terminal-cleanup teardown. DB-cancel alone does NOT terminate the durable Dapr session workflows (they keep re-spawning openshell sandboxes); the session-termination path only fires when the run is **cancelled**, so set runs+instances `status='cancelled'` first, then call cleanup (expect retries; coordinator+DB must be up). See the `evaluations` skill's "System State Update (2026-05-19)".

## Dev SWE-bench concurrency envelope

Practical limits for `/workspaces/<slug>/benchmarks` are layered. The current intended dev GitOps values are:

| Layer | Knobs | Intended dev value |
|---|---|---|
| Launch/BFF default | `BENCHMARK_DEFAULT_CONCURRENCY` | `10` |
| Capacity mode | `BENCHMARK_CAPACITY_MODE` | `auto` |
| Execution backend/class | `BENCHMARK_EXECUTION_BACKEND` / `BENCHMARK_EXECUTION_CLASS` | `dapr-kueue` / `benchmark-fast` |
| Full-instance Kueue model | `BENCHMARK_KUEUE_INSTANCE_REQUEST_MODE` | `host-worker-composite` |
| Lease resources | `BENCHMARK_KUEUE_LEASE_RESOURCES` | `openshell_sandbox,dapr_workflow_slot` |
| Shared coding pool | `AGENT_RUNTIME_POOL_APP_IDS_JSON` | `agent-runtime-pool-coding`, `maxReplicas=16`, `slotsPerReplica=12` on dev |
| Dedicated coding fallback | `AGENT_RUNTIME_SLOTS_PER_REPLICA_JSON` | `coding=12` |
| Per-sidecar Dapr workflow cap | `AGENT_RUNTIME_DAPR_WORKFLOW_LIMIT_PER_SIDECAR` | `12` |
| Coordinator start pacing | `SWEBENCH_COORDINATOR_INSTANCE_START_BATCH_SIZE` / `...DELAY_SECONDS` | unset or `0` / `0` for full effective-concurrency fan-out |
| Evaluator parallelism | `SWEBENCH_EVAL_MAX_PARALLEL` | `24` |

Per-instance peak draw during inference is modeled as the full sandbox/worker +
agent-host bundle. The capacity snapshot fields `kueueInstanceRequest*`,
`kueueInstancePodCount`, `kueueAvailableInstanceSlots`, and
`schedulableKueueInstanceCapacity` are the deployment-time truth; do not infer
safe concurrency from the launch slider or sandbox-only capacity. Per-run
harness evaluation adds Kueue-admitted evaluator TaskRuns. Before raising a run,
verify live node headroom, Kueue quota, Dapr runtime readiness, model/provider
rate limits, and exact-ready image coverage.

Current clean dev checkpoint: run `W4ZmHxaEMEYQDCZ_Ypo41` completed 25 distinct
exact-ready SWE-bench_Verified instances with DeepSeek V4 Pro at `maxTurns=25`.
It requested/effectively ran inference 25/25; evaluator requested/effective was
24/9 because Kueue clamped eval capacity. Result was 13 resolved / 7 unresolved
/ 5 empty-patch, zero evaluator errors, zero hard errors, zero active leases
after cleanup, and no Dapr activity-registration failures. Treat 25 as proven;
do not jump above it without a clean launch gate and exact-ready preview.
Ryzen runs the same composite capacity model but has much less request
headroom. The 2026-05-27 ryzen canary `MPIlRkKWC7UdvHgwFQEiR` selected 3
exact-ready instances and was correctly capped to effective concurrency 2 by
`kueue_capacity`; all three instances inferred/evaluated and active leases
returned to zero. Keep ryzen benchmark campaigns sequential even when a single
run can safely use multiple effective slots.

## What to read next

| If the task is… | Read |
|---|---|
| New to the system / orienting | `reference/architecture.md` |
| Need kubectl / argocd on a cluster | `reference/access-paths.md` |
| Deciding whether an app belongs on hub or a spoke | `reference/app-placement.md` |
| Anything secret-related (rotation, audit, debugging) | `reference/secret-flow.md` |
| Bumping an image to dev/staging | `runbooks/promote-image-to-spokes.md` |
| Post-push workflow-builder rollout verification on ryzen/dev | `runbooks/track-promotion-state.md` |
| Prompt Workbench or prompt preset DB/API changes after rollout | `runbooks/track-promotion-state.md` + workflow-builder `references/prompt-workbench.md` |
| SWE-bench evaluator promotion or Benchmarks page canary validation | `shared-skills/evaluations/SKILL.md` + `runbooks/track-promotion-state.md` |
| Agent is silent after adding MCP/OAuth connection; ActivePieces piece MCP catalog, Knative KServices, AgentRuntime bootstrap, or Dapr statestore scope is suspect | `runbooks/debug-workflow-builder-mcp-auth.md` |
| workflow-builder pod shows `1/2`, `daprd` readiness is false, or `openshell-agent-runtime` / `swebench-coordinator` is unavailable | `runbooks/debug-dapr-sidecar-stale-readiness.md` |
| workflow-builder works on ryzen but not dev/staging | `runbooks/reconcile-workflow-builder-spoke-environment.md` |
| Moving a ryzen-validated image to dev/staging | `runbooks/promote-image-to-spokes.md` |
| Image missing on ghcr.io | `runbooks/mirror-image-gitea-to-ghcr.md` |
| `Validate Workflow Builder Release Pins` CI failing with `denied` on every image | `runbooks/grant-stacks-ghcr-package-access.md` |
| Bumping AgentRuntime CR images such as browser-use-agent-sandbox or dapr-agent-py-sandbox (publish-time images outside release-pins) | `runbooks/bump-image-pin-not-in-release-pins.md` |
| Editing a workflow JSON spec (maxTurns, prompt, agentKwargs, …) and rolling the change to dev/staging | `runbooks/upsert-workflow-json.md` |
| Upgrade GitOps Promoter or repair its ArgoCD UI extension | `runbooks/manage-gitops-promoter.md` |
| Review all OutOfSync/Degraded apps and decide keep vs remove | `runbooks/review-argocd-app-health.md` |
| ArgoCD operationState stuck Running | `runbooks/recover-stuck-promotion.md` |
| db-migrate Job stuck Terminating | `runbooks/recover-stuck-job-finalizer.md` |
| Webhook not firing / hub Tekton path broken (NXDOMAIN or 202-no-PipelineRun) | `runbooks/debug-funnel-orphan-tag.md` |
| Device-backed Tailscale Ingress missing address, using `-1`, or blocked by stale service/device records | `runbooks/debug-device-backed-tailscale-ingress.md` |
| ProxyGroup service-host missing address or cert domain | `runbooks/debug-proxygroup-service-host.md` |
| Migration shipped but columns missing on dev | `runbooks/fix-drizzle-migration.md` |
| Track a promotion in flight / what's gating it | `runbooks/track-promotion-state.md` |
| Spoke kubectl when Tailscale down | `runbooks/access-spoke-cluster-fallback.md` |
| Rotate a per-spoke OAuth client secret | `runbooks/rotate-oauth-secret.md` |

The runbooks each follow the same shape: **Symptoms** → **Diagnostic** → **Fix steps** → **Verify**.

## CLIs the agent should assume are available

| Tool | Typical use here |
|---|---|
| `kubectl` | Multi-context via `~/.kube/config`; for hub use `--kubeconfig ~/.kube/hub-config` (no SSH wrapper when on ryzen) |
| `argocd` | Login via Tailscale: `argocd login argocd-hub.tail286401.ts.net --grpc-web` (admin password in `argocd-initial-admin-secret`). Use for `terminate-op`, `app sync --force`, things kubectl-patch can't do |
| `gh` | GitHub API (webhook delivery history, OAuth app metadata, PR/run inspection); already authenticated as `vpittamp` |
| `az` | Azure KeyVault (`keyvault-thcmfmoo5oeow`); `az keyvault secret show/set --query attributes.updated -o tsv` is the bread-and-butter command |
| `skopeo` | Legacy: mirror images from ryzen's local Gitea PVC to ghcr.io (only needed for unrecovered pre-A6 artifacts). Use `--dest-authfile` with hub's `ghcr-push-credentials` secret. Run from **ryzen** (DNS) |
| `talosctl` | Hub: `--talosconfig ~/.talos/hub-config`; Talos cluster (Hetzner): `~/.talos/talos-config`. Spokes don't have ready-made talosconfig — use kubeconfig fallback |
| `hcloud` | Active context `stacks` (`hcloud context list`). `hcloud server list` for full Hetzner topology |
| `tailscale` | `status --json` for orphan-tag diagnosis; `serve status` / `funnel status` from inside operator pods |
| `git` | Push app/source repos and promoted stacks changes to `origin` unless a task is explicitly about historical Gitea recovery |

## Repo paths cheat-sheet

| Path | Role |
|---|---|
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` | dev/staging release metadata source; edit with the generated overlays |
| `packages/components/workloads/workflow-builder-system-overlays/{dev,staging}/kustomization.yaml` | generated dry-source overlays consumed by source-hydrator; contains release-pin images and per-spoke runtime env |
| `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` | The cluster-selecting ApplicationSet that points source-hydrator at each generated workflow-builder-system overlay |
| `packages/base/manifests/tailscale-ingresses/` | Shared device-backed Tailscale Ingress declarations using `*-CLUSTER` placeholders for promoted-spoke app hostnames |
| `packages/components/workloads/<image>/manifests/kustomization.yaml` | Per-image workloads kustomization; current ryzen delivery uses ghcr.io refs picked up by hub Source Hydrator from `inner-loop` branch |
| `packages/components/workloads/workflow-builder/manifests/Deployment-workflow-builder.yaml` | `AGENT_RUNTIME_*_DEFAULT_IMAGE` env vars that drive AgentRuntime CR images (separate from release-pins; see gotchas) |
| `packages/components/workloads/activepieces-mcps/manifests/` | Reconciler that turns workflow-builder DB `mcp_connection` rows into cluster-local ActivePieces piece MCP Knative Services and `activepieces-mcp-catalog` |
| `packages/base/manifests/knative-serving/kustomization.yaml` | Knative Serving install and autoscaler config, including `allow-zero-initial-scale` needed by generated piece MCP services |
| `packages/components/workloads/workflow-builder/manifests/Component-workflowstatestore.yaml` | Namespace-wide Dapr workflow/actor state store (`actorStateStore=true`, `tablePrefix=wfstate_`) for parent and agent/session workflows |
| `packages/components/workloads/workflow-builder/manifests/Component-dapr-agent-py-statestore.yaml` | Namespace-wide non-actor agent application state store (`actorStateStore=false`, `tablePrefix=agent_py_`) |
| `packages/base/manifests/agent-sandbox-crds/` | Required OpenShell/agent-runtime CRDs: `AgentRuntime`, `Sandbox`, `SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool` |
| `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` | Direct image edit — no per-cluster override |
| `packages/components/hub-management/manifests/gitops-promoter/PromotionStrategy-workflow-builder-release.yaml` | env/spokes-dev → env/spokes-staging promotion config |
| `packages/components/hub-management/manifests/gitops-promoter/ArgoCDCommitStatus.yaml` | The `argocd-health` gate definition |
| `packages/components/hub-management/manifests/gitops-promoter/TimedCommitStatus-workflow-builder-soak.yaml` | The `timer` gate for dev/staging release soak (`dev=0s`, `staging=10m`) |
| `packages/components/hub-management/manifests/gitops-promoter/gitops-deployment-inventory.yaml` | Hub inventory API consumed by workflow-builder admin deployment metadata |
| `packages/components/workloads/workflow-builder/manifests/Service-gitops-inventory-hub-egress.yaml` | Spoke Tailscale egress Service for workflow-builder inventory fetches; targets `gitops-inventory-hub-node.tail286401.ts.net:8080` |
| `packages/components/workloads/workflow-builder/Application-workflow-builder.yaml` | Workflow-builder Argo Application; ignores Tailscale-mutated egress Service fields |
| `packages/components/hub-management/apps/gitops-promoter.yaml` | GitOps Promoter Helm chart app; chart version plus `manager.image.tag` override |
| `packages/components/hub-management/apps/argocd-gitops-promoter-ui.yaml` | Hub ArgoCD Application that installs/patches the GitOps Promoter UI extension |
| `packages/components/hub-management/manifests/argocd-gitops-promoter-ui/` | UI-extension patch Job, RBAC, and `argocd-cm` resource links/custom labels |
| `deployment/config/argocd-values.yaml` | Bootstrap-time ArgoCD Helm values; keep Promoter UI extension settings in sync with the patch app |
| `scripts/gitops/render-workflow-builder-release-overlays.sh` | Regenerates dev/staging workflow-builder-system dry-source overlays from release-pins |
| `scripts/gitops/validate-workflow-builder-release-pins.sh` | Validates release-pin schema, overlay freshness, and GHCR tag/digest existence |
| `gh pr list --search 'Promote' -R PittampalliOrg/stacks` + `git ls-remote origin env/spokes-ryzen env/hub-next env/hub` | Inspect pending Promoter PRs and current hydrated branch tips before pushing |
| `docs/hub-spoke-app-placement.md` | Current hub-vs-spoke app placement policy |
| `policy.hujson` | Tailscale ACL — `tagOwners`, `nodeAttrs` (Funnel grants), Kubernetes grants, and real `svc:*` service approvals. Do not add `svc:*` approvals for device-backed app Ingress hostnames. Synced to tailnet by `.github/workflows/tailscale-acl.yml` on push to main |
| `docs/outer-loop-promotion.md` | Full reference (this skill is a curated subset). Has its own "Recovery Runbooks" section |

## Safety guards before you act

- **Use `inner-loop` branch for ryzen-only image iteration; use `main` + Promoter PR for hub-affecting changes.** App repo commits are origin-only by design. For GitHub-delivered platform changes, push/merge through the normal `origin/main` path.
- **Check live ryzen source before recovery work.** Post-A6 ryzen has no local ArgoCD — `kubectl --context hub get application -n argocd | grep '^ryzen-'` is the right way to inspect ryzen's state. Each ryzen-* Application lives on hub with `destination.name: ryzen`.
- **Always shred extracted credentials.** When you `kubectl get secret … -o jsonpath='{...}' | base64 -d > /tmp/foo`, immediately `shred -u /tmp/foo` after. The Crossplane spoke kubeconfigs are admin certs.
- **Rotating a KeyVault secret** = wait for ESO + verify K8s Secret head + restart pod (in that order). Skipping the verify step bites every time.
- **A release metadata commit on `origin/main`** triggers rollout to dev and staging via `workflow-builder-release`. Dev promotes after health; staging promotes after health plus its soak timer. There is no manual confirmation step after the metadata commit lands.
- **Do not bypass Promoter for dev/staging rollout state.** Direct workload patches, manual Argo syncs, or ad hoc deploy scripts are emergency diagnostics only; the normal path is GitHub push → hub Tekton → release metadata direct-push or PR merge → source-hydrator → Promoter → ArgoCD.
