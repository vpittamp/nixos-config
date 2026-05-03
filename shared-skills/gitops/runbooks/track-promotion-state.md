# Runbook: Track a promotion in flight

## When to use

You merged a `release/workflow-builder-*` release-intent PR, or manually changed `release-pins/workflow-builder-images.yaml`, and want to see:
- Where the promotion is in the pipeline (hydrating? promoter PR open? spoke synced?)
- What's gating the next step (most often: dev's `argocd-health` not green yet → staging blocked)
- Which spoke is currently on which image
- Whether "stuck" is actually stuck or just waiting on a normal poll

The hub ArgoCD UI has the GitOps Promoter extension installed. Use it for visualizing Promoter resources and relationships, but still treat CRD status and branch tips as authoritative when debugging.

For workflow-builder specifically, start with `/admin/deployments` in the app. It is backed by the hub `gitops-deployment-inventory` API and usually answers "what's live, what's desired, and what is drifting?" faster than stitching together the lower-level CRDs.

## Mental model

```
origin/main
   │  (merge of release PR updates release-pins tag/digest/provenance)
   │  (per-app sourceHydrator on hub-side spoke-<env>-<app>)
   ▼
env/spokes-<env>-next   ──merged──▶  env/spokes-<env>   ──synced──▶  Spoke cluster (dev/staging)
   │                       ▲                                              │
   │                       │                                              │ ArgoCD reports health
   │            ChangeTransferPolicy                                      │ via argocd-health
   │            (dev: timer=0s, staging: timer=10m)                       │ + timer CommitStatus
   │            (PR opened with autoMerge: true)                          │ on the hydrated sha
   │                       ▲                                              │
   │                       └────── argocd-health + timer gates ◀──────────┘
   ▼
env/spokes-staging-next ── blocked until dev's argocd-health=success ──▶ env/spokes-staging
```

Four layers of state to read in order:

| Layer | What to look at | What it tells you |
|---|---|---|
| 0. Inventory | workflow-builder `/admin/deployments`, `gitops-inventory-hub`, or in-cluster egress | Desired images, live images, drift, commit/build metadata, and promotion SHAs in one place |
| 1. Hydrator | `env/spokes-<env>-next` branch tip on github | Whether your release-pins commit got rendered (~30-90s after origin/main lands) |
| 2. Promoter | `PromotionStrategy.status.environments[*]` + `ChangeTransferPolicy` | Whether the promoter PR was opened/merged (gated by `argocd-health` and `timer` CommitStatuses) |
| 3. Spoke ArgoCD | `spoke-<env>-<app>` and `<env>-<app>` Application status | Whether the spoke synced; whether the new image is live |

## Web UI on argocd-hub.tail286401.ts.net

1. **workflow-builder `/admin/deployments`** — preferred first view for app/runtime metadata. It compares release-pins, live Argo images, commit metadata, build status, and promotion state.
2. **GitOps Promoter UI extension in ArgoCD** — use the Promoter section to visualize `PromotionStrategy`, `ChangeTransferPolicy`, `PullRequest`, and related CRDs. If the section is missing, see `runbooks/manage-gitops-promoter.md`.
3. **PromotionStrategy** — `argocd / workflow-builder-release` for spokes, or `argocd / stacks-environments` for hub-only changes. View YAML; look at `.status.environments[]` for per-environment dry/hydrated SHAs and `commitStatuses[?(@.key=="argocd-health" || @.key=="timer")].phase`.
4. **`spoke-<env>-<app>` apps** (e.g. `spoke-dev-workflow-builder`) — these are the meta-apps that watch `env/spokes-<env>` and deploy Application CRDs to the spoke cluster. Sync revision = the hydrated commit currently serving.
5. **`<env>-<app>` apps** (e.g. `dev-workflow-builder`) — these run ON the spoke cluster (`destination.name=dev`) and deploy actual workloads. `summary.images` shows the resolved image tag after kustomize image substitution.
6. **Open PRs in stacks** — promoter creates auto-merge PRs from `env/spokes-<env>-next` → `env/spokes-<env>` for each promotion. https://github.com/PittampalliOrg/stacks/pulls?q=is%3Aopen+head%3Aenv%2Fspokes-

## CLI cheat-sheet

```bash
# 0. Inventory API: same data workflow-builder uses for /admin/deployments
# Human/browser path: HTTPS service-host VIP on the hub cluster-ingress ProxyGroup.
TOKEN=$(kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret gitops-deployment-inventory \
  -o jsonpath='{.data.bearerToken}' | base64 -d)
curl -fsS -H "Authorization: Bearer ${TOKEN}" \
  https://gitops-inventory-hub.tail286401.ts.net/inventory.json | \
  jq '.environments[] | {env: .name, apps: [.applications[] | {name, desired: .desired.image, live: .live.images, drift: .drift.status}]}'

# Spoke workload path: workflow-builder pods use this URL, not the HTTPS service-host VIP.
# The egress Service must target gitops-inventory-hub-node.tail286401.ts.net:8080.
tmp=$(mktemp /tmp/dev-kubeconfig.XXXXXX)
trap 'shred -u "$tmp"' EXIT
kubectl --kubeconfig ~/.kube/hub-config get secret dev-2frrm-kubeconfig -n crossplane-system \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > "$tmp"
pod=$(KUBECONFIG="$tmp" kubectl -n workflow-builder get pod \
  -l app.kubernetes.io/name=workflow-builder -o jsonpath='{.items[0].metadata.name}')
KUBECONFIG="$tmp" kubectl -n workflow-builder exec "$pod" -c workflow-builder -- node -e '
const http = require("node:http");
const url = process.env.WORKFLOW_BUILDER_GITOPS_INVENTORY_URL;
http.get(url, {headers: {authorization: `Bearer ${process.env.WORKFLOW_BUILDER_GITOPS_INVENTORY_TOKEN || ""}`}}, (res) => {
  let body = "";
  res.on("data", c => body += c);
  res.on("end", () => console.log(res.statusCode, JSON.parse(body).generatedAt));
}).on("error", e => { console.error(e); process.exit(1); });
'

# 1. One-line PromotionStrategy summary (per environment)
kubectl --kubeconfig ~/.kube/hub-config -n argocd get promotionstrategy workflow-builder-release \
  -o jsonpath='{range .status.environments[*]}env={.branch} dry={.active.dry.sha} hydrated={.active.hydrated.sha} health={.active.commitStatuses[?(@.key=="argocd-health")].phase} timer={.active.commitStatuses[?(@.key=="timer")].phase}{"\n"}{end}'

# 2. ChangeTransferPolicies (one per env) — shows promoter PR state
kubectl --kubeconfig ~/.kube/hub-config -n argocd get changetransferpolicy
# Look for: PROPOSED DRY SHA != ACTIVE DRY SHA (promotion in flight) and PR STATE column

# 3. CommitStatus gates (health and timer)
kubectl --kubeconfig ~/.kube/hub-config -n argocd get argocdcommitstatus
kubectl --kubeconfig ~/.kube/hub-config -n argocd get timedcommitstatus,commitstatus | grep -E 'workflow-builder|timer|argocd-health'

# 4. Open promoter-created PRs
gh pr list --repo PittampalliOrg/stacks --state open --search "head:env/spokes" \
  --json number,title,headRefName

# 4b. Open release-intent PRs waiting for human merge to main
gh pr list --repo PittampalliOrg/stacks --state open --search "head:release/workflow-builder" \
  --json number,title,headRefName,updatedAt

# 5. Spoke meta-app + workload-app revisions side-by-side
for env in dev staging; do
  for kind in spoke- ""; do
    name="${kind}${env}-workflow-builder"
    kubectl --kubeconfig ~/.kube/hub-config -n argocd get app $name \
      -o jsonpath='{.metadata.name}: rev={.status.sync.revision} sync={.status.sync.status} health={.status.health.status}{"\n"}'
  done
done

# 6. Promoter logs filtered to OUR ChangeTransferPolicy
kubectl --kubeconfig ~/.kube/hub-config -n gitops-promoter-system logs deploy/gitops-promoter-controller-manager \
  -c manager --tail=200 | grep -E "workflow-builder-release"

# 7. The image actually deployed on dev's pod (live, via argocd app manifests)
argocd login argocd-hub.tail286401.ts.net --grpc-web --plaintext=false \
  --username=admin \
  --password="$(kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d)"
argocd app manifests dev-workflow-builder --source live | grep -E "image: ghcr.io/pittampalliorg/workflow-builder"
```

## Why "blocked" usually isn't blocked

There are at least three polling intervals in this pipeline. Each adds latency before "OutOfSync" → "Synced" propagation:

| Layer | Default poll | What's polled |
|---|---|---|
| Source-hydrator (per spoke-app `sourceHydrator`) | ~3 min | The dry-source `targetRevision` (origin/main) for new commits |
| GitOps Promoter controller | ~30-60s | `ChangeTransferPolicy` reconcile (after the dry sha appears on env-next) |
| Spoke ArgoCD application controller | ~3 min | The hydrated branch (`env/spokes-<env>`) for new tip |

So 5–8 minutes from "I just merged to origin/main" to "dev pod is rolling on the new image" is normal. Staging also waits for the configured `timer` soak after health before Promoter auto-merges it. **Don't hard-sync; wait a poll cycle.**

Two known dead-ends:

- **`argocd app refresh --hard`** triggers manifest re-render but does NOT immediately repoll branch tips. Useful when you suspect cache staleness for `targetRevision: <sha>` apps; useless for `sourceHydrator: targetBranch: <branch>` apps.
- **`argocd app sync --revision <sha>`** is rejected on auto-sync + branch-tracking apps with `Cannot sync to <sha>: auto-sync currently set to <branch>`. This is Argo's safety, not a bug.
- **Concurrent outer-loop commits can make the dev CTP propose the previous dry SHA.** This has happened when one push produced both workflow-builder and workflow-orchestrator release metadata commits. If source-hydrator's current dry SHA is the new one but `workflow-builder-release-env-spokes-dev-*` still proposes the older dry SHA after a poll, refresh the PromotionStrategy and CTP:

```bash
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ctp=$(kubectl --context hub-cluster -n argocd get changetransferpolicy -o name | \
  rg 'workflow-builder-release-env-spokes-dev-' | head -n1)
kubectl --context hub-cluster annotate promotionstrategy workflow-builder-release -n argocd \
  promoter.argoproj.io/refresh-ts="$ts" --overwrite
kubectl --context hub-cluster annotate "$ctp" -n argocd \
  promoter.argoproj.io/refresh-ts="$ts" --overwrite
kubectl --context hub-cluster annotate app spoke-dev-workflow-builder -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

## What "blocked" actually looks like

Symptoms that justify intervening:

- **PromotionStrategy `health=pending` for >10 min** AND `proposed.hydrated.sha == active.hydrated.sha`: hydrator hasn't picked up your origin/main commit. Check `argocd app get spoke-<env>-<app> --hard-refresh` to nudge.
- **PromotionStrategy `health=pending` for >10 min** AND `proposed.hydrated.sha != active.hydrated.sha`: promoter hasn't merged the env-next PR. Check `kubectl get pr -A` (the promoter creates these as `PullRequest.promoter.argoproj.io` CRs); gh PR view for the actual GitHub PR; `argocd app history dev-workflow-builder` to see if dev has tried syncing on the new sha and reported back.
- **Spoke `<env>-<app>` Synced + Healthy on the new revision but image still old**: kustomize images patch wasn't applied. Check `.spec.source.kustomize.images` on the app — should contain `workflow-builder=ghcr.io/pittampalliorg/workflow-builder:git-<new-sha>@sha256:<digest>` when digest metadata exists.
- **`db-migrate` Job hookPhase=Succeeded but new columns missing**: classic drizzle-journal-skip bug. See `runbooks/fix-drizzle-migration.md`.

## If `/admin/deployments` shows "fetch failed"

Check the inventory URL and egress target from the workflow-builder pod:

```bash
kubectl -n workflow-builder get deploy workflow-builder \
  -o jsonpath='url={.spec.template.spec.containers[?(@.name=="workflow-builder")].env[?(@.name=="WORKFLOW_BUILDER_GITOPS_INVENTORY_URL")].value}{"\n"}'
kubectl -n tailscale get svc gitops-inventory-hub-egress \
  -o jsonpath='target={.metadata.annotations.tailscale\.com/tailnet-fqdn} port={.spec.ports[0].port} externalName={.spec.externalName}{"\n"}'
```

Expected:
- URL: `http://gitops-inventory-hub-egress.tailscale.svc.cluster.local:8080/inventory.json`
- Egress target: `gitops-inventory-hub-node.tail286401.ts.net`
- Port: `8080`

If the egress target is `gitops-inventory-hub.tail286401.ts.net`, the proxy is pointing at a Tailscale service-host VIP, not a node. Symptoms are `Tailscale node "...gitops-inventory-hub..." not found`, `ECONNREFUSED <proxy-pod-ip>:443`, or timeouts. Fix the stacks manifests, then push to the relevant branches and let Argo resync.

## Verify (after a normal flow)

```bash
# Both spoke meta-apps Synced + Healthy at the new hydrated commit
kubectl --kubeconfig ~/.kube/hub-config -n argocd get app spoke-dev-workflow-builder spoke-staging-workflow-builder \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# Both workload apps have the new image
for env in dev staging; do
  echo "--- $env ---"
  kubectl --kubeconfig ~/.kube/hub-config -n argocd get app ${env}-workflow-builder \
    -o jsonpath='{.status.summary.images}' | tr ',' '\n' | grep workflow-builder
done

# No open promoter PRs left = promotion fully merged
gh pr list --repo PittampalliOrg/stacks --state open --search "head:env/spokes" --json number
# Should be []
```

## Verify workflow-builder MCP/auth after a rollout

When the change touches MCP connection UX, ActivePieces auth, `piece-mcp-server`, `dapr-agent-py`, or AgentRuntime registry sync, add this check after the normal image/promotion verification:

```bash
ctx=dev

kubectl --context "$ctx" -n workflow-builder get cm activepieces-mcp-catalog \
  -o jsonpath='{.data.servers\.json}' | jq 'keys'

kubectl --context "$ctx" -n workflow-builder get ksvc \
  -l app.kubernetes.io/managed-by=activepieces-mcp-reconciler \
  -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type==\"Ready\")].status,URL:.status.address.url

slug=<agent-slug>
kubectl --context "$ctx" -n workflow-builder get deploy "agent-runtime-${slug}" -o json | \
  jq -r '.spec.template.spec.containers[] | select(.name=="dapr-agent-py") | .env[] | select(.name=="DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON").value' | jq .

kubectl --context "$ctx" -n workflow-builder logs deploy/"agent-runtime-${slug}" \
  -c dapr-agent-py --tail=250 | rg 'mcp-bootstrap|Loaded|Registered|Missing credentials'
```

For piece MCP servers, runtime URLs should be Knative URLs without `:3100`, and OAuth-backed entries should include `headers.X-Connection-External-Id`. If this verification fails, switch to `runbooks/debug-workflow-builder-mcp-auth.md`.

## Verify workflow-builder prompt presets after a rollout

When the change touches Prompt Workbench, `resource_prompts`, `resource_prompt_versions`, or `/api/prompt-presets`, add this after the normal image/promotion verification:

```bash
ctx=dev

kubectl --context "$ctx" -n workflow-builder exec deploy/workflow-builder -- \
  psql "$DATABASE_URL" -c "SELECT to_regclass('public.resource_prompt_versions') AS prompt_versions_table;"

kubectl --context "$ctx" -n workflow-builder exec deploy/workflow-builder -- \
  psql "$DATABASE_URL" -c "SELECT id, hash, created_at FROM drizzle.__drizzle_migrations ORDER BY created_at DESC LIMIT 5;"

# Public unauthenticated requests should not leak project presets.
curl -i https://workflow-builder-dev.tail286401.ts.net/api/prompt-presets
```

Then run an authenticated API smoke in the target workspace: list presets, create a throwaway preset, update it and confirm version 2 exists, archive it, and clean up the smoke rows. If the table is missing but `db-migrate` succeeded, switch to `runbooks/fix-drizzle-migration.md`; the usual cause is a missing Drizzle journal entry.
