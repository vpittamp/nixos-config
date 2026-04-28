---
name: gitops
description: "Use this skill for PittampalliOrg/stacks GitOps operations: ArgoCD app health/drift review across hub/dev/staging/ryzen; image promotion; release-pins, GHCR/Gitea image drift, and image pins outside release-pins; workflow-builder spoke runtime drift; workflow-builder MCP/auth and ActivePieces piece MCP services; Dapr AgentRuntime statestore, sidecar readiness, and 1/2 pod recovery; GitOps Promoter stuck apps, env branches, source-hydrator, and hub promotion; Tailscale ACLs, device-backed Ingress DNS/status, ProxyGroup service-host VIPs, spoke API access, stale tailnet devices/services, and Funnel webhooks; OAuth/secret rotation, deployment inventory, workflow JSON DB upserts, and app placement."
---

# GitOps for PittampalliOrg/stacks

Operational knowledge for the hub-and-spoke gitops system across **dev**, **staging**, **ryzen** (kind), and **hub** (Talos control plane). Read this whole file, then drill into `reference/` or `runbooks/` based on the decision tree.

## Orientation

- **Hub** is a Talos cluster on Hetzner. It runs a single ArgoCD that manages itself **and** all spokes via cluster secrets.
- **Spokes**: `dev`, `staging` (Talos on Hetzner), and `ryzen` (kind on the user's workstation). The hub ArgoCD pushes workloads to all three.
- **Two Tekton instances**:
  - **Hub Tekton** (outer-loop): triggered by GitHub webhooks on app repos (`PittampalliOrg/workflow-builder`, etc.); builds images, pushes to **ghcr.io**, then `update-stacks` writes tag/digest/provenance to `release-pins/workflow-builder-images.yaml`. Current pipelines may push the release metadata commit directly to `origin/main`; older/alternate pipelines may open a `release/workflow-builder-*` release-intent PR. Inspect `update-stacks` logs and branch/PR state before assuming the handoff. A release metadata commit on `origin/main` drives **dev/staging**.
  - **Ryzen Tekton** (inner-loop): triggered locally on ryzen; builds images, pushes to the **gitea-ryzen** registry, commits to `gitea-ryzen/main` at `active-development/manifests/<image>/kustomization.yaml`. This drives **ryzen** only.
- **GitOps Promoter** gates hub and spoke promotions. `workflow-builder-release` gates dev → staging through `argocd-health` plus the `timer` gate from `TimedCommitStatus-workflow-builder-soak.yaml` (dev `0s`, staging `10m`); both environments still have `autoMerge: true`. `stacks-environments` gates hub self-management from `env/hub-next` → `env/hub`.
- **ArgoCD Promoter UI extension** is installed on hub ArgoCD so operators can visualize `PromotionStrategy`, `ChangeTransferPolicy`, `PullRequest`, and related Promoter CRDs in the ArgoCD UI.
- **Source-hydrator** renders `packages/overlays/<spoke>` → `env/spokes-<spoke>-next`; promoter merges to `env/spokes-<spoke>`; hub ArgoCD syncs the generated spoke Applications to the target clusters. Dev/staging usually do not have their own local ArgoCD Application CRDs.
- **Deployment inventory** is generated on the hub by `gitops-deployment-inventory`. Browser/human access uses the HTTPS service-host VIP `gitops-inventory-hub.tail286401.ts.net`; spoke workflow-builder pods use a separate node-backed Tailscale LoadBalancer `gitops-inventory-hub-node.tail286401.ts.net:8080` through the in-cluster egress Service `gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080`.
- **Promoted spoke hostnames are declarative.** Dev/staging workflow-builder system URLs live in `spoke-workloads-appset.yaml`, device-backed Tailscale Ingresses live under `packages/base/manifests/tailscale-ingresses/`, and `policy.hujson` is reserved for tailnet policy such as real `svc:*` service-host approvals, device tags, Funnel grants, and Kubernetes grants.
- **OpenShell depends on agent sandbox CRDs.** Keep `agent-sandbox-crds` / `<spoke>-agent-sandbox-crds`; it owns required `AgentRuntime`, `Sandbox`, `SandboxClaim`, `SandboxTemplate`, and `SandboxWarmPool` CRDs. AutoKube is legacy and has been removed.
- **Workflow-builder MCP/auth is a DB-backed runtime path, not just static manifests.** Project MCP rows in workflow-builder's `mcp_connection` table bind ActivePieces pieces to `app_connection.external_id` credentials. The `activepieces-mcps` app reconciles those rows into cluster-local Knative `ap-<piece>-service` MCP servers plus an `activepieces-mcp-catalog` ConfigMap. Agent publish/registry sync writes resolved MCP servers into each `AgentRuntime`, and the controller injects them into the runtime pod as `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON`.
- **Sandboxed Dapr agents use centralized durable state.** `workflowstatestore` is scoped to parent workflow runtimes; `dapr-agent-py-statestore` is the shared actor state store for per-agent runtimes. The agent-runtime controller mutates only Component scopes so each sidecar sees exactly one actor state store. Do not create per-agent state stores or move durable history into pod-local state.

The two image-pin systems for the **same workflow-builder base** are the most common source of confusion. Read `reference/architecture.md` first if you've never seen this setup.

## The "which file?" matrix (single most-referenced piece of knowledge)

| Cluster | Image source | Bump path | Branch the bump lands on |
|---|---|---|---|
| **ryzen** | `packages/components/active-development/manifests/<image>/kustomization.yaml` (`images:` block) | Ryzen Tekton inner-loop pipeline `workflow-builder-image-build` (commit subject: `chore(dev-images): deploy <image> <tag> to ryzen`) | `gitea-ryzen/main` (Gitea on ryzen) — **NOT pushed to GitHub** |
| **dev / staging** | `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` (`images` compatibility tags plus `digests`, `imageRefs`, `sourceShas`, `pipelineRuns`, `updatedAts`; consumed by `spoke-workloads` and rendered as tag+digest GHCR refs when available) | Hub Tekton outer-loop `update-stacks` writes release metadata; observed current path can push directly to `origin/main`, while PR-mode opens `release/workflow-builder-*`. Manual changes must update/validate the same metadata | `origin/main` release metadata commit, or `release/workflow-builder-*` PR branch → `origin/main` when PR mode is active |
| **hub** itself | source-hydrator from `packages/overlays/hub` on `origin/main` → `env/hub-next` → `env/hub` (gated by `stacks-environments` PromotionStrategy) | Edit overlay; merge to `origin/main` | `origin/main` (GitHub) |

`agent-runtime-controller` is a third path: bumped directly in `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` (no per-cluster override), so a single bump applies to all spokes once it's on `origin/main`.

`release-pins/workflow-builder-images.yaml` is **not** the only image-pin file for dev/staging. Two important exceptions live outside it; bumping release-pins alone is insufficient for either:

- **`browserstation` and `chrome-sandbox`** are pinned inline as kustomize.images strings inside `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` (search `browserstation=ghcr.io`). The matrix-generator's release-pins file covers app-build images only.
- **AgentRuntime CR images** (`browser-use-agent-sandbox`, `dapr-agent-py-sandbox`) are read at agent-publish time from `AGENT_RUNTIME_*_DEFAULT_IMAGE` env vars on the workflow-builder Deployment (`packages/components/active-development/manifests/workflow-builder/Deployment-workflow-builder.yaml`). `kustomize.images` substitutes container `image:` fields but **not** env var values, so release-pins bumps don't touch these. Bump the env var, AND patch already-published `AgentRuntime` CRs (`spec.environment.imageTag`) — registry-sync only re-runs at agent publish time. See `runbooks/bump-image-pin-not-in-release-pins.md`.

Ryzen has one extra branch nuance: ryzen workload Applications usually read manifests from `gitea-ryzen/main`, but the ryzen root Application spec tracks `gitea-ryzen/ryzen-main`. If a manual stacks change affects ryzen child Application specs, ignoreDifferences, appsets, or root-managed resources, fast-forward both `gitea-ryzen/main` and `gitea-ryzen/ryzen-main`.

MCP/auth has a third, non-image flow. `mcp_connection` and `app_connection` rows live in the workflow-builder DB; `activepieces-mcps` reconciles those rows into Knative services; `AgentRuntime` registry sync copies the resolved server list into the runtime CR/pod. A source push alone does not fix an already-published agent if its `AgentRuntime` still has stale MCP bootstrap JSON; run registry sync or patch/re-publish the AgentRuntime, then verify the generated Deployment env and runtime logs.

## Decision tree

### "I need to roll out / promote / bump an image"

1. Which cluster? **ryzen only** → handled automatically by ryzen Tekton inner-loop on the next push to the app repo. Nothing to do in stacks unless you're adding a new image.
2. **dev or staging** → normal path is hub Tekton outer-loop builds GHCR and `update-stacks` writes tag, digest, and provenance. Read the task logs: if it pushed directly to `origin/main`, track source-hydrator + Promoter from that commit; if it opened a `release/workflow-builder-*` PR, review/merge it first. Manual path: edit all release metadata maps in `release-pins/workflow-builder-images.yaml`, verify the GHCR tag/digest, run `scripts/gitops/validate-workflow-builder-release-pins.sh`, then follow `runbooks/promote-image-to-spokes.md`.
3. Want to mirror current ryzen tags into dev/staging (typical "catch up" task) → first run `runbooks/reconcile-branches.md` (origin/main and gitea-ryzen/main usually diverge), then bump release-pins as part of the merge commit.

### "I pushed workflow-builder and need to verify ryzen + dev"

1. Confirm the app repo pushed to the right remotes: `origin/main` feeds hub/dev/staging; `gitea-ryzen/main` feeds ryzen. If one remote was already current, record that instead of force-pushing.
2. Ryzen: watch the `workflow-builder-image-build` PipelineRun, then verify both the declarative Deployment image and the actual serving pod. DevSpace may leave the declarative `workflow-builder` Deployment at `replicas=0` while `workflow-builder-devspace` serves live traffic from synced source; inspect the live pod before assuming the image rollout is what users hit.
3. Dev: watch hub `outer-loop-workflow-builder-*`; capture the built GHCR tag/digest and read `update-stacks` logs. The task may push release metadata directly to `origin/main` or open a release PR depending on the active pipeline.
4. Track `spoke-dev-workflow-builder.status.sourceHydrator.currentOperation.{drySHA,hydratedSHA}`, the `workflow-builder-release-env-spokes-dev-*` ChangeTransferPolicy, and `dev-workflow-builder` / `spoke-dev-workflow-builder` health. If `env/spokes-dev-next` advanced but the CTP still proposes the older dry SHA after one source-hydrator poll, annotate `PromotionStrategy/workflow-builder-release` and the dev CTP with fresh `promoter.argoproj.io/refresh-ts`.
5. Finish with authenticated smoke tests against the public URLs. On NixOS, if Playwright's bundled browser cannot launch, use system Chrome at `/etc/profiles/per-user/vpittamp/bin/google-chrome`.

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

### "GitHub webhook didn't fire / image is on gitea-ryzen but missing on ghcr.io"

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

- **Branch divergence is normal.** `origin/main` and `gitea-ryzen/main` drift 10+ commits each way after a few days because two different Tekton instances commit independently. Reconcile periodically via `runbooks/reconcile-branches.md`. Eleven files commonly conflict.
- **Outer-loop release handoff can be direct-main or PR-mode.** Hub Tekton `update-stacks` is the source of truth: inspect its logs and Git state to see whether release metadata was pushed directly to `origin/main` or placed on a `release/workflow-builder-*` PR branch. Direct human edits to release pins should be exceptional and must pass `scripts/gitops/validate-workflow-builder-release-pins.sh`.
- **`stacks-environments` PromotionStrategy has `autoMerge: false`.** Unlike `workflow-builder-release` (env/spokes-dev + env/spokes-staging) which auto-merge after `argocd-health`, the `env/hub` PR (`gitops-promoter-*[bot]: Promote <sha> to env/hub`) requires **manual** merge. Every change under `packages/overlays/hub` (which includes `spoke-workloads-appset.yaml`, AppSet templates, etc.) opens such a PR and the dev/staging cascade is blocked until it's merged. Easy to miss because `workflow-builder-release` IS auto.
- **Hub promoter status can lag branch tips.** If `env/hub-next` has a newer hydrated SHA but `stacks-environments-env-hub-*` still proposes the prior dry SHA/PR, annotate both `PromotionStrategy/stacks-environments` and the `ChangeTransferPolicy` with a fresh `promoter.argoproj.io/refresh-ts`.
- **`workflow-builder-release` can lag source-hydrator too.** If `env/spokes-dev-next` has advanced but `workflow-builder-release-env-spokes-dev-*` still proposes the prior dry SHA after one poll interval, refresh `PromotionStrategy/workflow-builder-release` plus the dev CTP with `promoter.argoproj.io/refresh-ts`. Do not use hard-sync as a substitute for Promoter catching up.
- **ApplicationSet template-only changes don't auto-trigger spoke hydration.** When you edit inline kustomize patches in `spoke-workloads-appset.yaml` (image overrides, env values, ignoreDifferences) without touching `release-pins/workflow-builder-images.yaml`, the matrix-generator only re-templates child Apps when the release-pins content changes OR a new `origin/main` commit propagates through env/hub. After the env/hub merge, if `spoke-dev-workflow-builder` still shows the OLD inlined patch in `.spec.sourceHydrator.drySource`, the source-hydrator rendered before the ApplicationSet controller re-templated. Push an empty commit on `origin/main` (`git commit --allow-empty -m "chore: bump dry SHA"`) to force the next render cycle. Same fix applies if `env/spokes-<spoke>-next` shows the prior dry SHA's content despite `currentOperation.drySHA` advancing.
- **Do not delete agent sandbox CRDs as "duplicates."** `agent-sandbox-crds` is the CRD owner for OpenShell/agent-runtime sandbox resources. It is separate from controllers and workload apps by design so CRDs sync early.
- **AutoKube is legacy.** If AutoKube Applications, Ingresses, ACL service approvals, or manifests appear, remove them declaratively and let Argo prune them instead of repairing them.
- **Argo drift review is keep/remove first, fix second.** For needed resources, run `argocd app diff` and prefer declaring API defaults (ExternalSecret defaults, Tekton EventListener defaults, CRD defaults) over hiding real drift. Empty `argocd app diff` with OutOfSync status usually means stale Argo status; hard-refresh first and restart the application controller only if it remains stale.
- **AgentRuntime CR images flow through the BFF env var, not release-pins.** `agent-runtime-<slug>` Deployment images are set at agent-publish time by `registry-sync.ts:725` reading `env.AGENT_RUNTIME_BROWSER_USE_DEFAULT_IMAGE` (browser-use-agent runtime) or `env.AGENT_RUNTIME_DEFAULT_IMAGE` (default). These env vars are static literals on `Deployment-workflow-builder.yaml`. Bumping release-pins does not update them; you must edit the Deployment YAML AND patch existing `AgentRuntime` CRs (`spec.environment.imageTag`) to re-roll already-published agents. The env var on ryzen typically points at `gitea-ryzen.tail286401.ts.net/giteaadmin/dapr-agent-py-sandbox:git-<sha>`; on dev/staging it points at `ghcr.io/pittampalliorg/dapr-agent-py-sandbox:git-<sha>`. Different registries — don't assume the ryzen tag exists on ghcr.io. See `runbooks/bump-image-pin-not-in-release-pins.md`.

- **Sandbox templates (`workspace_profile.with.sandboxTemplate`) resolve via `SANDBOX_TEMPLATE_IMAGES_JSON`** on the workflow-builder Deployment (NOT release-pins, NOT `kustomize.images`). The env var is a JSON object mapping template names to image refs. Currently on ryzen: `dapr-agent`, `default-sandbox`, `dapr-agent-xlsx`, `xlsx`, `code-eval`. Adding a new template name = (1) add a `Dockerfile.<name>` under `services/openshell-sandbox/environments/` in the workflow-builder repo, (2) commit with subject `environment(<name>):` so the env-image-build pipeline fires, (3) update `SANDBOX_TEMPLATE_IMAGES_JSON` in stacks `Deployment-workflow-builder.yaml`. The pipeline pushes `gitea-ryzen.tail286401.ts.net/giteaadmin/openshell-sandbox-<name>:git-<sha>` only — **no `:latest` retag**. If the env var references `:latest`, manually `skopeo copy --src-tls-verify=false --dest-tls-verify=false docker://...:git-<sha> docker://...:latest` after the build completes.

- **Tekton's `update-dev-tag` task races manual stacks pushes.** When the workflow-builder image-build pipeline succeeds on ryzen, its second task commits `chore(dev-images): deploy <image> git-<sha> to ryzen` directly to `gitea-ryzen/main`. If you're holding a local stacks branch waiting to push, the bot commit can land between your `git fetch` and `git push`, causing `Updates were rejected (non-fast-forward)`. Fix: `git fetch gitea-ryzen && git rebase gitea-ryzen/main && git push gitea-ryzen HEAD:main`. Don't force-push; the bot commits are real history.

- **Orchestrator `wfstate_state` orphan reminders block new StartInstance.** `workflowstatestore` is `state.postgresql v2` with `tablePrefix=wfstate_`. When a workflow row is purged but its actor reminder is still in dapr-scheduler-server's ETCD, daprd retries the reminder ~every 10s and logs `Unable to get data on the instance: <id>, no such instance exists`. The retry loop can serialize behind the workflow runtime worker queue and make new `ctx.call_child_workflow` / `StartInstance` calls hit `DEADLINE_EXCEEDED` after 60s. Confirm via daprd logs first; fix with `kubectl exec postgresql-0 -- psql ... -c "TRUNCATE wfstate_state"` then `kubectl rollout restart deploy/workflow-orchestrator`. Note this only clears the actor state half — orphan reminders in the scheduler ETCD may re-fire after restart. If they do, restart `dapr-scheduler-server-0` too. Don't reach for this fix without the smoking gun in the daprd logs.

- **`environment(<slug>):` commit subject is the only trigger for the env-image-build pipeline.** The hub-tekton EventListener (`build-environment-image` trigger in `EventListener-workflow-builder-fn-builds.yaml`) filters on `body.commits[*].message ~= '^environment\\(.+?\\):'` AND a modified `services/openshell-sandbox/environments/Dockerfile.<slug>` path. Both conditions must hold per push. Slug is extracted via `c.message.split('(')[1].split(')')[0]`. Commit message typos like `env(code-eval):` will silently skip the build with no visible error.
- **ActivePieces piece MCP URLs should not include port `:3100` when targeting Knative.** The container listens on 3100, but callers hit the cluster-local Knative Service URL. Stale AgentRuntime or workflow configs containing `http://ap-...svc.cluster.local:3100/mcp` bypass Knative routing and can leave agents silent.
- **MCP auth is request-scoped by connection external ID.** For piece MCP tools, the runtime sends `X-Connection-External-Id`; `piece-mcp-server` calls workflow-builder's internal decrypt API. Do not put OAuth tokens, decrypted credentials, or user-specific secrets into KService env, workflow JSON, or GitOps manifests. The reconciler may set a fallback `CONNECTION_EXTERNAL_ID`, but per-request headers are the correct multi-user path.
- **ActivePieces MCP services are generated from DB state.** Pinned pieces (`github`, `google-calendar`, `openai`) stay available; enabled `mcp_connection` pieces create additional KServices and catalog entries. If a user adds Outlook/Excel/OneDrive and the KService is missing, debug `activepieces-mcp-reconciler` before patching workloads by hand.
- **Piece MCP KServices scale to zero by design.** `knative-serving` must allow `allow-zero-initial-scale: "true"`, and generated services use `initialScale: "0"`. Cold starts can make the first `/health` or `/mcp` probe exceed a short timeout; retry with a longer timeout before treating it as a hard failure.
- **Dapr durable protocol compatibility depends on a single actor state store per sidecar.** Parent workflows use `workflowstatestore`; per-agent runtimes use `dapr-agent-py-statestore`. The controller enrolls each agent app id into the shared Component scopes. If agent sessions hang after an AgentRuntime change, verify Component scopes before restarting pods or clearing state.
- **Dapr sidecar liveness can stay green while readiness is permanently false.** After placement/scheduler restarts or cert churn, workflow-builder runtime pods can show `1/2` because the app container is healthy but `daprd` returns `ERR_HEALTH_NOT_READY: [grpc-api-server grpc-internal-server]`. Logs often include `Actor runtime shutting down`, `Placement client shutting down`, or `Workflow engine stopped`. Verify `dapr-system` is currently healthy, then recycle the affected Deployment (`workspace-runtime`, `swebench-coordinator`, or another Dapr-enabled runtime). See `runbooks/debug-dapr-sidecar-stale-readiness.md`.
- **Workflow JSON specs do not flow through image rebuilds.** `services/<agent>/<name>.workflow.json` is excluded from the production Dockerfile copy list. Editing it in the repo + rebuilding doesn't change runtime behavior; the spoke's `workflows.spec` JSONB column is read at execution time. Updating the spec requires a DB UPDATE on each spoke. See `runbooks/upsert-workflow-json.md`.
- **ArgoCD SSA validation blocks parent-syncs-child-Application apply.** When the parent app (e.g., `spoke-dev-workflow-builder`) tries to apply a kustomize-patched child Application (e.g., `dev-browserstation`), you may see `Application.argoproj.io "<child>" is invalid: status.sync.comparedTo.source.repoURL: Required value`. The parent's SSA payload nullifies a status field the CRD validator requires. Workaround: patch the live child directly with `kubectl patch app dev-<name> --type=json -p='[{op:replace,path:/spec/source/kustomize/images/0,value:...}]'`. The parent will keep retrying with the failing apply but the child's live spec is correct.
- **KubeRay head pod doesn't auto-roll on image change.** When a RayCluster spec image is bumped via `kustomize.images`, the KubeRay operator gradually rolls workers but the head stays on the old image until explicitly deleted (`kubectl delete pod -n ray-system browserstation-head-<id>`). Workers wait on head GCS via `wait-gcs-ready` init container, so a stuck old head blocks worker rollout too. Verify with `kubectl get pod -l ray.io/cluster=browserstation -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[?(@.name=="ray-head")].image}{.spec.containers[?(@.name=="ray-worker")].image}{"\n"}{end}'`.
- **Buildah short-name resolution is enforced on ryzen Tekton inner-loop.** `FROM rayproject/ray:2.47.1-cpu` fails with `short-name resolution enforced but cannot prompt without a TTY`. Always fully-qualify base images (`docker.io/rayproject/...`). Fix is in the Dockerfile, not the pipeline.
- **Ryzen DevSpace can mask declarative image rollout.** The ryzen Application can be Synced/Healthy and the declarative Deployment image can point at the new tag while `replicas=0`; live traffic may be served by `workflow-builder-devspace` with source mounted. Verify the actual serving pod, image, and synced files before declaring ryzen done.
- **DevSpace pods cache stale env vars across ArgoCD updates.** A subtle variant of the above: when ArgoCD bumps an env var on `Deployment-workflow-builder.yaml` (e.g. `AGENT_RUNTIME_DEFAULT_IMAGE`), the Deployment+ReplicaSet roll, but the long-lived `workflow-builder-devspace-*` pod was created hours/days earlier and won't restart on its own. The serving pod reads the OLD env value, which means BFF code paths that use that env (like `registry-sync.ts` stamping `AGENT_RUNTIME_DEFAULT_IMAGE` into newly-published or newly-woken `AgentRuntime` CRs) keep emitting stale tags despite the manifest being "synced". Diagnose: `kubectl get deploy workflow-builder -o jsonpath='{...env...}'` shows the new value but `kubectl exec deploy/workflow-builder -- printenv AGENT_RUNTIME_DEFAULT_IMAGE` still shows the old one. Recovery: `devspace purge` (clears the dev override entirely) OR `kubectl delete pod workflow-builder-devspace-*` (forces a fresh pod from the current Deployment template). After either, verify both the standard `workflow-builder-*` pod and any AgentRuntime CRs that newly woke have the expected image.
- **AgentRuntime CR `imageTag` revert loop.** Even after `kubectl patch agentruntime <name> spec.environment.imageTag=...`, the next agent wake (or any registry-sync trigger) re-reads the BFF env var and resets the CR back to the OLD image. The CR is *not* the source of truth — the BFF env var is. To roll an already-published agent forward durably: (1) bump the env var in the stacks Deployment YAML AND (2) verify the BFF *pod* (not just the manifest) sees the new value AND (3) patch the CR. Skipping any of the three undoes the others. The dance is documented in `runbooks/bump-image-pin-not-in-release-pins.md`.
- **`rayproject/ray:2.47.1-cpu` ships Python 3.9.** PEP-604 union syntax (`def f(x: float | None)`) fails at module import with `TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'`. Add `from __future__ import annotations` at the top of the file or use `Optional[X]`. Caused a head-pod CrashLoopBackOff on the Tier 2 browserstation rollout.
- **Skopeo mirror needs DNS to gitea-ryzen + GHCR org-write creds.** Both are satisfied by running on ryzen with hub's `ghcr-push-credentials` secret. If `hostname` is `ryzen`, run skopeo locally. Off ryzen, SSH-wrap to ryzen (DNS won't resolve `gitea-ryzen.tail286401.ts.net` elsewhere). Agents (any host) should always SSH-wrap because the bash-tool's "Production Reads" guard trips on `kubectl get secret <production> | base64 -d > /tmp/...` regardless of hostname; the wrapper hides the redirect inside the remote shell. See `runbooks/mirror-image-gitea-to-ghcr.md` for the two cases.
- **Tailscale Funnel orphan tags silently break webhooks.** If a tag is removed from `policy.hujson` but a device still uses it, the operator pod claims "Funnel on" locally but the control plane revokes the cap. Public DNS goes NXDOMAIN. Diagnostic: `tailscale status --json | jq '.Self.{Tags, CapMap}'` from inside the proxy pod.
- **ProxyGroup service-host tags are separate from Funnel tags.** For hub browser VIPs, the Ingress `tailscale.com/tags`, Tailscale Service tags, `policy.hujson` `autoApprovers.services`, and the authenticated ProxyGroup pod tag must agree. Hub `cluster-ingress` should authenticate as `tag:k8s-services`; `tag:k8s` is legacy compatibility only.
- **Device-backed Tailscale Ingresses are not `svc:*` service-hosts.** Promoted-spoke app URLs without `tailscale.com/proxy-group` register as Tailscale devices, usually tagged `tag:k8s`. Do not add `autoApprovers.services["svc:<hostname>"]` for these. A stale `svc:<hostname>` record can reserve the canonical DNS name and force the real device to register as `<hostname>-1`.
- **Tailscale operator Secret metadata matters after manual recovery.** Ingress proxy state Secrets such as `tailscale/ts-workflow-builder-tailscale-*-0` must keep labels `tailscale.com/managed=true`, `tailscale.com/parent-resource=<ingress>`, `tailscale.com/parent-resource-ns=<namespace>`, and `tailscale.com/parent-resource-type=ingress`. If a manual auth/key repair leaves a huge `kubectl.kubernetes.io/last-applied-configuration` annotation or strips labels, the endpoint may work while ArgoCD stays `Progressing`; restore labels and remove the stale annotation.
- **Tailscale egress targets nodes, not service-host VIPs.** `gitops-inventory-hub.tail286401.ts.net` is a service-host VIP backed by `cluster-ingress`; egressing to it produces "node not found", `ECONNREFUSED`, or timeouts. Spoke inventory fetches must use `gitops-inventory-hub-node.tail286401.ts.net:8080` through `gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080`.
- **Tailscale operator mutates egress Services.** It writes `/spec/externalName` and may add `/spec/ports/0/targetPort`; Argo Applications that own egress Services should ignore both fields or they will stay OutOfSync despite working traffic.
- **Dev/staging service URLs must be declared, not inferred from ryzen.** `MCP_GATEWAY_BASE_URL` and Phoenix URLs belong in the spoke ApplicationSet template with `{{cluster}}`; matching `mcp-gateway-*`/`phoenix-*` Tailscale Ingresses must exist. Add `policy.hujson` `svc:*` approvals only when the hostname is actually served by a ProxyGroup/Tailscale Service.
- **Spoke API VIPs need both service approval and Kubernetes grants.** `dev-api-v2`/`staging-api-v2` service-hosts need `autoApprovers.services` entries, and the authenticated `tag:spoke-api` devices need a Kubernetes impersonation grant to `tag:k8s` with `system:masters`. Re-authenticate the spoke ProxyGroup after ACL changes if the device still has stale caps.
- **ESO refresh ↔ pod restart race.** When rotating a KeyVault secret, ESO may not finish writing the K8s Secret before a Deployment restart kicks off. The new pod reads the stale value. Always verify the K8s Secret head matches the new value **before** triggering the restart.
- **Hub pods cannot resolve `gitea-ryzen.tail286401.ts.net`.** Use the Tailscale **egress** service pattern (`gitea-ryzen-egress.tailscale.svc.cluster.local`) or run skopeo/git from ryzen host instead of inside hub.
- **Stacks repo is mirrored to two remotes.** `origin/main` (GitHub) feeds hub ArgoCD. `gitea-ryzen/main` feeds ryzen. Release metadata intentionally lands on `origin/main` only, either by direct `update-stacks` push or release PR merge; manual platform/app-spec changes usually need both remotes unless you specifically want one-sided drift. Use `scripts/gitops/check-branch-drift.sh` to verify `origin/main`, `gitea-ryzen/main`, and `gitea-ryzen/ryzen-main`.
- **Ryzen root tracks `ryzen-main`.** If ryzen workloads look correct but root/child Application specs are stale, check `git ls-remote gitea-ryzen refs/heads/main refs/heads/ryzen-main`. Fast-forward `gitea-ryzen/ryzen-main` for ryzen app-spec changes.
- **`argocd-hub.tail286401.ts.net` works even when other Tailscale ProxyGroups are down.** It's an independent ProxyGroup. When per-spoke Tailscale access is broken, you can still drive ArgoCD ops from the hub via `argocd login argocd-hub.tail286401.ts.net --grpc-web`.
- **GitOps Promoter app releases may be newer than the Helm chart appVersion.** Verify both upstream release and Helm chart metadata. As of 2026-04-24, the controller runs `v0.27.1`; the latest Helm chart is `0.6.0` with `appVersion: 0.26.2`, so stacks keeps chart `0.6.0` and overrides `manager.image.tag`.
- **Promoter UI patch hooks need a shell-capable kubectl image.** `registry.k8s.io/kubectl` is distroless and has no `/bin/sh`; use `alpine/k8s:<version>` for shell-scripted hook jobs. The ArgoCD Helm chart's server container is named `server`, even though the Deployment is `argocd-server`.
- **Hub source-hydrator status can pin a stale dry SHA.** If `root-application.status.sourceHydrator.currentOperation.drySHA` stays behind `origin/main`, remove `currentOperation` and `lastSuccessfulOperation` from status and hard-refresh the app. See `runbooks/manage-gitops-promoter.md`.
- **Drizzle Kit silently skips SQL files lacking `_journal.json` entries.** The `db-migrate` Sync hook on dev/staging runs `npx drizzle-kit migrate`, which globs `drizzle/*.sql` BUT only applies files with a matching `entries[]` tag in `drizzle/meta/_journal.json`. Job exits 0 either way — easy to miss. Always update the journal when adding a migration; older files in the repo (0006/0007/0020/0032/0037-0043) lack journal entries because their columns were applied via out-of-band paths historically. See `runbooks/fix-drizzle-migration.md`.
- **Two migration runners read from two different directories.** `src/lib/server/startup.ts` reads from `atlas/migrations/` (timestamp-prefixed); `npx drizzle-kit migrate` reads from `drizzle/` (incremental + journal-gated). The production image's `Dockerfile` copies `drizzle/` but `.dockerignore` excludes `atlas/`, so the atlas-runner is effectively only active in the ryzen devspace pod (which file-syncs source). New migrations usually need to live in BOTH dirs, both idempotent (`ADD COLUMN IF NOT EXISTS`).
- **Source-hydrator polls every ~3 min.** After release metadata lands on `origin/main`, expect 5-8 min before dev's pod is rolling on the new image, then staging waits for its configured soak timer after health. `argocd app refresh --hard` triggers manifest re-render but does NOT immediately repoll branch tips. `argocd app sync --revision <sha>` is rejected on auto-sync + branch-tracking apps (`Cannot sync to <sha>: auto-sync currently set to <branch>`). Don't hard-sync; wait. See `runbooks/track-promotion-state.md` for what's-actually-stuck triage.
- **Generated `env/spokes-*` branches need guardrails.** If the generated app directory drifts from `env/spokes-*-next`, use `scripts/gitops/reconcile-spoke-generated-dir.sh <dev|staging> check|fix`; do not hand-edit generated env branches unless the script proves the root and child dry SHAs match.
- **`git status --porcelain` `R ` prefix means "renamed in INDEX, already staged".** Filtering with `grep -E "^A |^M "` MISSES it. After a stale `git add` or interrupted commit, your next `git commit` will scoop in any pre-staged renames/deletes alongside what you intended. Before committing, either `git reset HEAD --` to clear the index then re-stage exact paths, or use `git diff --cached --name-status` (which shows ALL staged changes including renames + deletes + mode changes).

## What to read next

| If the task is… | Read |
|---|---|
| New to the system / orienting | `reference/architecture.md` |
| Need kubectl / argocd on a cluster | `reference/access-paths.md` |
| Deciding whether an app belongs on hub or a spoke | `reference/app-placement.md` |
| Anything secret-related (rotation, audit, debugging) | `reference/secret-flow.md` |
| Bumping an image to dev/staging | `runbooks/promote-image-to-spokes.md` |
| Post-push workflow-builder rollout verification on ryzen/dev | `runbooks/track-promotion-state.md` |
| Agent is silent after adding MCP/OAuth connection; ActivePieces piece MCP catalog, Knative KServices, AgentRuntime bootstrap, or Dapr statestore scope is suspect | `runbooks/debug-workflow-builder-mcp-auth.md` |
| workflow-builder pod shows `1/2`, `daprd` readiness is false, or `workspace-runtime` / `swebench-coordinator` is unavailable | `runbooks/debug-dapr-sidecar-stale-readiness.md` |
| workflow-builder works on ryzen but not dev/staging | `runbooks/reconcile-workflow-builder-spoke-environment.md` |
| Catching dev/staging up to ryzen | `runbooks/reconcile-branches.md` |
| Image missing on ghcr.io | `runbooks/mirror-image-gitea-to-ghcr.md` |
| Bumping browserstation, chrome-sandbox, browser-use-agent-sandbox, dapr-agent-py-sandbox (images outside release-pins) | `runbooks/bump-image-pin-not-in-release-pins.md` |
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
| `skopeo` | Image mirroring between gitea-ryzen and ghcr.io. Use `--dest-authfile` with hub's `ghcr-push-credentials` secret. Run from **ryzen** (DNS) |
| `talosctl` | Hub: `--talosconfig ~/.talos/hub-config`; Talos cluster (Hetzner): `~/.talos/talos-config`. Spokes don't have ready-made talosconfig — use kubeconfig fallback |
| `hcloud` | Active context `stacks` (`hcloud context list`). `hcloud server list` for full Hetzner topology |
| `tailscale` | `status --json` for orphan-tag diagnosis; `serve status` / `funnel status` from inside operator pods |
| `git` | Three remotes commonly seen: `origin` (GitHub), `gitea` and `gitea-ryzen` (both point at the same Gitea on ryzen). Push to BOTH `origin` and `gitea-ryzen` after manual edits |

## Repo paths cheat-sheet

| Path | Role |
|---|---|
| `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml` | dev/staging image pins (the file you edit most often) |
| `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` | The matrix ApplicationSet that consumes release-pins and patches each spoke's apps, including promoted-spoke runtime env such as MCP/Phoenix URLs |
| `packages/base/manifests/tailscale-ingresses/` | Shared device-backed Tailscale Ingress declarations using `*-CLUSTER` placeholders for promoted-spoke app hostnames |
| `packages/components/active-development/manifests/<image>/kustomization.yaml` | Per-image kustomization with the gitea-ryzen registry tag (ryzen-only) |
| `packages/components/active-development/manifests/workflow-builder/Deployment-workflow-builder.yaml` | `AGENT_RUNTIME_*_DEFAULT_IMAGE` env vars that drive AgentRuntime CR images (separate from release-pins; see gotchas) |
| `packages/components/active-development/manifests/activepieces-mcps/` | Reconciler that turns workflow-builder DB `mcp_connection` rows into cluster-local ActivePieces piece MCP Knative Services and `activepieces-mcp-catalog` |
| `packages/base/manifests/knative-serving/kustomization.yaml` | Knative Serving install and autoscaler config, including `allow-zero-initial-scale` needed by generated piece MCP services |
| `packages/components/active-development/manifests/workflow-builder/Component-workflowstatestore.yaml` | Parent workflow Dapr actor state store, scoped away from per-agent runtimes |
| `packages/components/active-development/manifests/openshell-agent-runtime/Component-dapr-agent-py-statestore.yaml` | Shared per-agent Dapr actor state store; agent-runtime-controller mutates scopes for durable AgentRuntime pods |
| `packages/base/manifests/agent-sandbox-crds/` | Required OpenShell/agent-runtime CRDs: `AgentRuntime`, `Sandbox`, `SandboxClaim`, `SandboxTemplate`, `SandboxWarmPool` |
| `packages/base/manifests/openshell/Deployment-agent-runtime-controller.yaml` | Direct image edit — no per-cluster override |
| `packages/components/hub-management/manifests/gitops-promoter/PromotionStrategy-workflow-builder-release.yaml` | env/spokes-dev → env/spokes-staging promotion config |
| `packages/components/hub-management/manifests/gitops-promoter/ArgoCDCommitStatus.yaml` | The `argocd-health` gate definition |
| `packages/components/hub-management/manifests/gitops-promoter/TimedCommitStatus-workflow-builder-soak.yaml` | The `timer` gate for dev/staging release soak (`dev=0s`, `staging=10m`) |
| `packages/components/hub-management/manifests/gitops-promoter/gitops-deployment-inventory.yaml` | Hub inventory API consumed by workflow-builder admin deployment metadata |
| `packages/components/active-development/manifests/workflow-builder/Service-gitops-inventory-hub-egress.yaml` | Spoke Tailscale egress Service for workflow-builder inventory fetches; targets `gitops-inventory-hub-node.tail286401.ts.net:8080` |
| `packages/components/active-development/apps/workflow-builder.yaml` | Workflow-builder Argo Application; ignores Tailscale-mutated egress Service fields |
| `packages/components/hub-management/apps/gitops-promoter.yaml` | GitOps Promoter Helm chart app; chart version plus `manager.image.tag` override |
| `packages/components/hub-management/apps/argocd-gitops-promoter-ui.yaml` | Hub ArgoCD Application that installs/patches the GitOps Promoter UI extension |
| `packages/components/hub-management/manifests/argocd-gitops-promoter-ui/` | UI-extension patch Job, RBAC, and `argocd-cm` resource links/custom labels |
| `deployment/config/argocd-values.yaml` | Bootstrap-time ArgoCD Helm values; keep Promoter UI extension settings in sync with the patch app |
| `scripts/gitops/validate-workflow-builder-release-pins.sh` | Validates release-pin schema and GHCR tag/digest existence |
| `scripts/gitops/check-branch-drift.sh` | Checks `origin/main`, `gitea-ryzen/main`, and `gitea-ryzen/ryzen-main` alignment |
| `docs/hub-spoke-app-placement.md` | Current hub-vs-spoke app placement policy |
| `policy.hujson` | Tailscale ACL — `tagOwners`, `nodeAttrs` (Funnel grants), Kubernetes grants, and real `svc:*` service approvals. Do not add `svc:*` approvals for device-backed app Ingress hostnames. Synced to tailnet by `.github/workflows/tailscale-acl.yml` on push to main |
| `docs/outer-loop-promotion.md` | Full reference (this skill is a curated subset). Has its own "Recovery Runbooks" section |

## Safety guards before you act

- **Do not silently create branch drift.** Release-intent PRs are origin-only by design; for manual platform/app-spec changes, push both `origin/main` and `gitea-ryzen/main` unless the change is intentionally one-sided.
- **For ryzen app-spec changes, push `gitea-ryzen/ryzen-main` too.** `gitea-ryzen/main` keeps the child manifests/image pins current; `gitea-ryzen/ryzen-main` keeps the ryzen root Application's generated child Application specs current.
- **Always shred extracted credentials.** When you `kubectl get secret … -o jsonpath='{...}' | base64 -d > /tmp/foo`, immediately `shred -u /tmp/foo` after. The Crossplane spoke kubeconfigs are admin certs.
- **Rotating a KeyVault secret** = wait for ESO + verify K8s Secret head + restart pod (in that order). Skipping the verify step bites every time.
- **A release metadata commit on `origin/main`** triggers rollout to dev and staging via `workflow-builder-release`. Dev promotes after health; staging promotes after health plus its soak timer. There is no manual confirmation step after the metadata commit lands.
- **Do not bypass Promoter for dev/staging rollout state.** Direct workload patches, manual Argo syncs, or ad hoc deploy scripts are emergency diagnostics only; the normal path is GitHub push → hub Tekton → release metadata direct-push or PR merge → source-hydrator → Promoter → ArgoCD.
