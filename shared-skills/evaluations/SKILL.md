---
name: evaluations
description: "Use this skill whenever the user mentions evals, evaluations, benchmarks, graders (string_check, text_similarity, model labeler, model scorer, python grader, endpoint grader), the eval wizard, datasets, predictions JSONL, run summaries, run items, the Inspect drawer, SWE-bench templates, the evaluation-coordinator, or debugging anything in `/workspaces/<slug>/evaluations` of the workflow-builder app. Triggers also include questions about how the OpenAI-parity eval UI compares to platform.openai.com/evaluation, score_model live grading via the per-agent runtime pod, or rolling out dapr-agent-py grader changes."
---

# Workflow-Builder Evaluations

Build, run, and debug the OpenAI-parity evaluation system in `/home/vpittamp/repos/PittampalliOrg/workflow-builder/main`. This skill covers the SvelteKit UI, the SvelteKit BFF service layer, the Python `evaluation-coordinator` Dapr workflow, the asynchronous grader runners (including the live `score_model` path against per-agent runtime pods), and the operational steps to roll dapr-agent-py changes into ryzen and dev/staging.

The system intentionally mirrors **platform.openai.com/evaluation** surface-by-surface:

- `/workspaces/<slug>/evaluations?tab=datasets|evals` — list with empty-state copy that matches OpenAI verbatim.
- `/workspaces/<slug>/evaluations/evals/<evalId>` — eval detail (Report tab) + run selector (Data tab).
- `/workspaces/<slug>/evaluations/evals/<evalId>/runs/<runId>` — run detail with `result_counts` KPI strip and per-criteria breakdown.
- `/workspaces/<slug>/evaluations/evals/create` — 3-step wizard (data → criteria → review/run).
- `/workspaces/<slug>/evaluations/datasets/<datasetId>` — dataset detail with rows table and drawer.
- The legacy 1100-line `+page.svelte` is preserved at `evaluations/evals-legacy/` as a fallback.

## Mental Model

A **dataset** is versionable input rows. An **eval** is a reusable contract = data source + ordered graders. A **run** is one async execution of that contract against a **subject** (Agent / Workflow / Imported outputs / SWE-bench template). Postgres stores the projection; Dapr Workflows provide execution durability via the `evaluation-coordinator` and `workflow-orchestrator`. Grading runs BFF-side after each item completes — the BFF dispatches to sync grader logic for `string_check` / `text_similarity` / `multi` / `external_harness` and to async runners (`grader-runners.ts`) for `score_model` / `python` / endpoint-shaped `external_harness`.

## First Steps For Any Eval Question

1. Read the canonical surface BEFORE making claims. Start with:
   - UI shell: `src/routes/workspaces/[slug]/evaluations/+page.svelte`
   - Detail routes: `evals/[evalId]/+page.svelte`, `evals/[evalId]/runs/[runId]/+page.svelte`, `datasets/[datasetId]/+page.svelte`
   - Wizard host: `evals/create/+page.svelte` + `src/lib/components/evaluations/wizard/`
   - Shared components: `src/lib/components/evaluations/{run-items-table,run-inspect-drawer,types}.{svelte,ts}`
   - Service: `src/lib/server/evaluations/service.ts`
   - Grader logic: `src/lib/server/evaluations/graders.ts` (sync) + `grader-runners.ts` (async)
   - Coordinator: `services/evaluation-coordinator/src/app.py`
   - Sync evaluator endpoint: `services/dapr-agent-py/src/main.py` (search `/api/grader-evaluate`)

2. Decide the layer first: UI (Svelte), service (TypeScript), grader runtime (TS + Python), or operational (kubectl + Tekton). Keep changes scoped to that layer unless the symptom crosses boundaries.

3. For deeper detail (tables, lifecycle, gotchas, smoke tests) read `references/system-model.md`.

## Decision Table

| Task | Do this |
| --- | --- |
| **Explain how evals work** | Summarize the three-resource model (Dataset → Eval → Run) + grader catalog + Dapr-backed execution + the OpenAI-parity surface. |
| **Demo the wizard end-to-end** | Open `evals/create`, pick `Upload a file`, paste a small JSONL, add a `String check` grader, set Subject = `Imported outputs` with a predictions JSONL of `{id:"row_N", output:...}`. Click Create and run. Drawer + KPIs populate. |
| **Add or modify a grader form** | Edit `src/lib/components/evaluations/wizard/<grader>-form.svelte`. Six exist today: `string-check`, `text-similarity`, `model-labeler`, `model-scorer`, `python`, `endpoint`. Each takes `{grader, onChange}` and emits a config compatible with `validateGraderConfig` in `graders.ts`. |
| **Change run-detail KPIs or items table** | Edit `src/lib/components/evaluations/run-items-table.svelte` (table + per-grader columns) or `run-inspect-drawer.svelte` (left rail + Input/Expected/Output/Graders sections). Both are reused by the eval-detail Data tab. |
| **Change grader scoring or wire a new grader** | Sync types live in `src/lib/server/evaluations/graders.ts` (`runGrader`, `validateGraderConfig`, `aggregateGraderResults`). Async runners (`runScoreModelGrader`, `runPythonGrader`, `runEndpointGrader`) live in `grader-runners.ts`. Service-side dispatch is in `service.ts:gradeLoadedEvaluationRunItem` — it awaits `runGraderAsync`. |
| **Add a runner that needs an external service** | Use `daprFetch` from `$lib/server/dapr-client` (retry-enabled). For service-invoke against per-agent runtimes, also call `wakeAgentRuntime(slug, 30_000)` from `$lib/server/kube/client` first. |
| **Debug a stuck `agent` or `workflow` run** | Check coordinator logs, orchestrator logs, the `AgentRuntime` CR phase + pod readiness, and `workflow_executions.dapr_instance_id`. See the diagnosis ladder in `references/system-model.md`. |
| **Roll dapr-agent-py grader changes** | The agent endpoint lives in `services/dapr-agent-py/src/main.py`. Per-agent runtime pods use `dapr-agent-py-sandbox:<tag>`. Rebuild needs **two PipelineRuns**; re-rolling already-published agents needs a CR patch. See "Operational Rollout" below. |
| **Handle SWE-bench** | It's an eval template, not a separate model. The wizard's Step 1 has a SWE-bench tile that POSTs `/api/evaluations/templates/swebench`. The harness output is graded by `external_harness` with `resultPath: generatedOutput.evaluation`. |

## Grader Catalog (live status)

| Grader | UI form | Runner | Status | Where it lives |
|---|---|---|---|---|
| `string_check` | `string-check-form.svelte` | sync `runStringCheck` | Live | `graders.ts` |
| `text_similarity` | `text-similarity-form.svelte` | sync `runTextSimilarity` (token Jaccard) | Live | `graders.ts` |
| `score_model` (Model labeler / Model scorer) | `model-labeler-form.svelte`, `model-scorer-form.svelte` | async `runScoreModelGrader` | Live | `grader-runners.ts` → POST `/v1.0/invoke/agent-runtime-<slug>/method/api/grader-evaluate` |
| `python` | `python-grader-form.svelte` | async `runPythonGrader` | Live | `grader-runners.ts` → POST to `code-runtime` `/execute` with `{language:"python", source, entrypoint:"grade", args:[sample,item]}` |
| `endpoint` (saved as `external_harness` with `config.url`) | `endpoint-grader-form.svelte` | async `runEndpointGrader` | Live | `grader-runners.ts` — direct HTTPS POST `{sample, item}` + `scorePath` extraction |
| `multi` | n/a (composite) | sync `runMultiGrader` | Live | `graders.ts` |
| `external_harness` (legacy SWE-bench) | n/a | sync `runExternalHarness` | Live | `graders.ts` |

The wizard's "Endpoint grader" UI is intentionally saved as `type: external_harness` with `config.url + headers + scorePath + passThreshold`; the dispatcher routes to the async runner whenever `external_harness && config.url` is set.

`runScoreModelGrader` accepts a bare label string (`Pass`, `Fail`, `Positive`, ...) when JSON parsing fails, by looking up the response token in the configured labels list. Equivalent fallback for scorer mode parses bare numerics. This is necessary because real LLMs ignore the "respond with JSON" instruction more often than expected.

## Wizard Shape

3 steps, 2-pane (wizard left, live preview right). State is a Svelte 5 `$state` runes module at `src/lib/components/evaluations/wizard/wizard-store.svelte.ts` (note the `.svelte.ts` suffix — Svelte 5 requires it for `$state` outside components).

1. **Step 1 — Data source**: 5 tiles (Import Logs disabled · Create new data · Upload a file · SWE-bench template · Use the API disabled). Selecting a tile reveals the matching editor: manual rows table, JSONL/JSON/CSV upload, or SWE-bench suite picker.
2. **Step 2 — Criteria**: `Add` opens `<GraderPickerDialog>` with all 6 grader tiles. Each grader form is rendered inline once added; configs are bindable via `onChange`.
3. **Step 3 — Review**: Name + description + `<SubjectPicker>` (Agent / Workflow / Imported outputs tabs) + concurrency + timeoutSeconds + Summary card. `Create and run` POSTs `/api/evaluations/evals` then `/api/evaluations/runs` (or hits `/api/evaluations/templates/swebench` for SWE-bench preset) and redirects to the run detail page.

Wizard quirks worth remembering:

- Upload-mode JSONL gets `externalId: "row_${i+1}"` injected automatically when the row has no `id`/`externalId`/`external_id`. This lets the predictions JSONL reference rows without forcing the user to add ids.
- Imported outputs JSONL is parsed client-side into `Array<{id, output}>` before POSTing — the server's `normalizeImportedOutputs` only accepts arrays/records and silently drops raw strings.
- `state.dataSource === 'swebench'` short-circuits the regular create flow and POSTs `/api/evaluations/templates/swebench` directly.

## Run Detail + Inspect Drawer

`run-items-table.svelte` derives:
- `graderNames`: `graderId → friendly name` from the first item that has each grader's results. Backfills the column header so `String check grader` shows instead of the raw id.
- `graderColumns`: keyed by `summary.perGrader` ids when available, falling back to walking items.

`run-inspect-drawer.svelte`:
- 1000px-wide Sheet split into a 220px left rail + main pane.
- Left rail = one button per `run.items` (row index + status icon + 30-char input preview). Click sets `selectedItemId`. Selected row gets `bg-primary/10 border-l-2 border-primary`.
- Keyboard: `ArrowDown`/`j` moves to next item; `ArrowUp`/`k` to previous. Wraps modulo `run.items.length`. Ignores keys when typing in inputs/textareas.
- Main pane: Input · Expected · Output · Graders (per-grader pass/fail icon + score badge + reasoning details) · Error · Trace IDs.
- Polling stops when run status is terminal (`completed`/`failed`/`cancelled`).

## Run Lifecycle (one-line summary)

`POST /api/evaluations/runs` → `createEvaluationRun` snapshots dataset rows → for `imported_outputs` runs grading is immediate → for `agent`/`workflow` runs the BFF starts the coordinator → coordinator schedules `evaluation_run_workflow` → fan-out per-item child workflows → BFF `items/<id>/start` builds the SW workflow spec and submits to `workflow-orchestrator` → `items/<id>/sync` polls until terminal → BFF runs `runGraderAsync` for each grader → run summary recomputed → run marked `completed`.

For full detail: `references/system-model.md`.

## Operational Rollout

dapr-agent-py code changes (the `/api/grader-evaluate` endpoint, `_call_anthropic_sdk`, MCP, hooks, etc.) need TWO PipelineRuns:

1. `dapr-agent-py-image-build` — for legacy `dapr-agent-py:git-<sha>` (used by the legacy `dapr-agent-py` + `dapr-agent-py-testing` Deployments).
2. `dapr-agent-py-sandbox-image-build` — for `dapr-agent-py-sandbox:git-<sha>` (used by every per-agent runtime pod via the AgentRuntime CR).

**Ryzen path** (inner-loop):

```bash
# Push to gitea-ryzen — Tekton fires automatically
git push gitea-ryzen main

# Watch builds (typical: 4-7 min for sandbox)
kubectl -n tekton-pipelines get pipelinerun --sort-by='.metadata.creationTimestamp' | tail -10

# After build succeeds, patch a target AgentRuntime CR. Existing pods don't auto-roll.
SHA=$(git rev-parse HEAD)
kubectl patch agentruntime agent-runtime-<slug> -n workflow-builder --type=merge \
  -p "{\"spec\":{\"environment\":{\"imageTag\":\"gitea-ryzen.tail286401.ts.net/giteaadmin/dapr-agent-py-sandbox:git-${SHA}\"}}}"

# Sleep + wake to pull new image
kubectl annotate agentruntime agent-runtime-<slug> -n workflow-builder \
  agents.x-k8s.io/sleep=$(date -Iseconds) --overwrite
kubectl annotate agentruntime agent-runtime-<slug> -n workflow-builder \
  agents.x-k8s.io/wake=$(date -Iseconds) --overwrite
```

**Dev/staging path** (outer-loop):

```bash
# Push to GitHub — hub Tekton fires via webhook
git push origin main

# Watch hub builds
kubectl --kubeconfig ~/.kube/hub-config -n tekton-pipelines \
  get pipelinerun --sort-by='.metadata.creationTimestamp' | tail -10

# After build, hub Tekton's update-stacks task writes release metadata to
# stacks repo's release-pins/workflow-builder-images.yaml. GitOps Promoter
# then promotes dev (after argocd-health) and staging (after the soak timer).
```

The `AGENT_RUNTIME_*_DEFAULT_IMAGE` env vars on the workflow-builder Deployment are the source-of-truth for newly-published agents. To roll already-published agents on dev/staging: bump the env var (in the stacks repo's Deployment YAML), wait for spoke sync, and patch each `AgentRuntime` CR's `spec.environment.imageTag` (the BFF reads the env var only at agent-publish time). See the gitops skill's "bump-image-pin-not-in-release-pins" runbook for the exact path.

## Operational Commands

```bash
# Coordinator + orchestrator logs
kubectl logs -n workflow-builder deploy/evaluation-coordinator --tail=200
kubectl logs -n workflow-builder deploy/workflow-orchestrator -c workflow-orchestrator --tail=200
kubectl logs -n workflow-builder deploy/workflow-orchestrator -c daprd --tail=200

# Per-agent runtime status + image
kubectl get agentruntimes -n workflow-builder
kubectl get agentruntime agent-runtime-<slug> -n workflow-builder \
  -o jsonpath='{.status.phase}{"\t"}{.spec.environment.imageTag}{"\n"}'

# Probe the sync grader endpoint directly (after pod is Active)
POD=$(kubectl get pods -n workflow-builder -o name | grep agent-runtime-<slug> | head -1)
kubectl exec -n workflow-builder $POD -c dapr-agent-py -- \
  curl -sS -X POST -H "Content-Type: application/json" \
  -d '{"systemPrompt":"...","userPrompt":"..."}' \
  http://localhost:8002/api/grader-evaluate

# Recent runs + items
kubectl exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -Atc "
select r.id, r.status, r.summary, r.subject_type, i.status, i.scores, i.error
from evaluation_runs r join evaluation_run_items i on i.run_id = r.id
order by r.created_at desc limit 10;"
```

## Guardrails

- Do NOT preserve legacy `/api/benchmarks/*` behavior unless explicitly asked — the OpenAI-parity wizard supersedes it.
- Do NOT start a local SvelteKit dev server. The dev loop on ryzen is **devspace sync** to the running pod; on dev/staging it's the hub Tekton outer-loop. Manual `pnpm dev` will not match the live environment.
- Do NOT bake workflow JSON specs into images — `services/<agent>/<name>.workflow.json` is excluded by `.dockerignore`. The workflows table reads from postgres at execution time.
- DO NOT hand-edit `release-pins/workflow-builder-images.yaml` unless the hub Tekton path is broken AND `scripts/gitops/validate-workflow-builder-release-pins.sh` passes locally.
- For score_model graders, the operator can override the transport with `EVALUATIONS_GRADER_URL` env var on the BFF. Useful for routing to a Cloudflare Worker or external rubric service without touching dapr-agent-py.
- The default evaluator agent slug comes from `EVALUATIONS_GRADER_AGENT_SLUG` env (default `evaluator-default`). Publish an agent with that slug or override per-grader with `config.model: <slug>`.

## Authoritative Files

```
src/lib/server/db/schema.ts                          # evaluation_* tables (~line 2861-3214)
src/lib/server/evaluations/service.ts                # CRUD, lifecycle, grade dispatch
src/lib/server/evaluations/graders.ts                # sync runners + runGraderAsync entry
src/lib/server/evaluations/grader-runners.ts         # async score_model / python / endpoint
src/lib/components/evaluations/types.ts              # shared TS types
src/lib/components/evaluations/run-items-table.svelte
src/lib/components/evaluations/run-inspect-drawer.svelte
src/lib/components/evaluations/wizard/               # step-1/2/3, grader forms, subject-picker
src/routes/api/evaluations/                          # public API routes
src/routes/api/internal/evaluations/                 # coordinator-only routes (X-Internal-Token)
src/routes/workspaces/[slug]/evaluations/+page.svelte                    # router shell
src/routes/workspaces/[slug]/evaluations/evals/[evalId]/+page.svelte     # eval detail
src/routes/workspaces/[slug]/evaluations/evals/[evalId]/runs/[runId]/+page.svelte  # run detail
src/routes/workspaces/[slug]/evaluations/evals/create/+page.svelte       # 3-step wizard
src/routes/workspaces/[slug]/evaluations/datasets/[datasetId]/+page.svelte
src/routes/workspaces/[slug]/evaluations/evals-legacy/+page.svelte       # preserved monolith
services/evaluation-coordinator/src/app.py           # Dapr workflows
services/dapr-agent-py/src/main.py                   # /api/grader-evaluate (search this string)
services/workflow-orchestrator/workflows/sw_workflow.py
```

For implementation history (Iteration 1 OpenAI parity, Iteration 2 NTH polish), see the plan at `/home/vpittamp/.claude/plans/review-our-workflow-builder-system-moonlit-pizza.md`.
