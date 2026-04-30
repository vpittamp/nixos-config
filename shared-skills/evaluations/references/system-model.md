# Evaluation System Model

Use this reference when you need more detail than `SKILL.md`: implementation work, operational debugging, or accurate explanations of how eval runs move through the system. The current implementation mirrors **platform.openai.com/evaluation** — Datasets, Evals, Runs as first-class resources; an Inspect drawer with row navigation; a 3-step Create wizard with six grader forms. Official SWE-bench runs use a separate Benchmarks surface and coordinator/evaluator path so they can run the Docker harness and appear in the workflow-builder operator UI.

## Core Objects

| Concept | Table / Module | Notes |
| --- | --- | --- |
| Dataset | `evaluation_datasets` | Project-scoped collection of rows. Source can be hand-authored, JSONL/JSON/CSV import, or adapter-created (e.g., legacy SWE-bench eval template). |
| Dataset row | `evaluation_dataset_rows` | Stores `externalId`, `input`, `expectedOutput`, optional `generatedOutput`, annotations, rating, and feedback. The wizard's upload mode auto-injects `externalId: "row_${i+1}"` when missing so predictions JSONL can match by id. |
| Eval definition | `evaluations` | Reusable contract. Links to a dataset and stores `taskConfig`. |
| Grader | `evaluation_graders` | Ordered, enabled criteria with type, config, weight, and pass threshold. |
| Run | `evaluation_runs` | Async execution for subject type `imported_outputs`, `agent`, or `workflow`; stores execution config, status, summary, usage, and errors. |
| Run item | `evaluation_run_items` | One row execution/result. Stores generated output, grader results, scores, session/workflow IDs, traces, status, and errors. |
| Artifact | `evaluation_artifacts` | Run/item-level artifacts such as predictions JSONL, harness output, logs, or paths. |

Official SWE-bench uses parallel benchmark objects instead of `evaluation_*`: `benchmark_suites`, `benchmark_instances`, `benchmark_runs`, `benchmark_run_instances`, `benchmark_artifacts`, and `benchmark_run_provenance`. Keep that model separate from the legacy `/api/evaluations/templates/swebench` adapter.

## Public Routes

UI:

- `/workspaces/<slug>/evaluations?tab=datasets|evals` — router shell with tab strip, search, and Create CTA.
- `/workspaces/<slug>/evaluations/evals/<evalId>` — eval detail. Top tabs: **Report** (default — summary cards + runs table) and **Data** (run selector + extracted `<RunItemsTable>` + `<RunInspectDrawer>`). URL pattern: `?tab=report|data`. The Data tab fetches run items in summary mode and lazy-loads the selected full item.
- `/workspaces/<slug>/evaluations/evals/<evalId>/runs/<runId>` — run detail. KPI strip mirroring OpenAI's `result_counts: { total, passed, failed, errored }`, per-criteria breakdown, items table with per-grader pass/fail icons, Inspect drawer with row rail. Cancel / Re-grade / Download predictions actions. Polls every 4s while status is non-terminal, but only with compact row summaries.
- `/workspaces/<slug>/evaluations/evals/create` — 3-step wizard. Reads `?preset=` query param.
- `/workspaces/<slug>/evaluations/datasets/<datasetId>` — dataset detail with rows table and side drawer.
- `/workspaces/<slug>/evaluations/evals-legacy` — preserved monolith fallback.
- `/workspaces/<slug>/benchmarks` — operator-visible SWE-bench suite/run list and run detail. Reads `benchmark_*` state and provenance; this is the surface to use when a SWE-bench run must show up in workflow-builder.

Public API (`src/routes/api/evaluations/`):

- `datasets`: create / list datasets.
- `datasets/[datasetId]`: read / update / delete dataset.
- `datasets/[datasetId]/import`: JSONL/JSON/CSV import.
- `datasets/[datasetId]/rows`: add rows.
- `datasets/[datasetId]/rows/[rowId]`: update / delete rows.
- `evals`: create / list eval definitions.
- `evals/[evaluationId]`: read / update / delete eval definition.
- `runs`: create / list runs and start coordinator for executable subjects.
- `runs/[runId]`: run detail. Accepts `?items=summary` to compact each run item (`input`, `expectedOutput`, `generatedOutput`) for table/drawer polling.
- `runs/[runId]/items/[itemId]`: full run-item detail on demand for the Inspect drawer.
- `runs/[runId]/grade`: grade or re-grade.
- `runs/[runId]/cancel`: cancel.
- `runs/[runId]/predictions.jsonl`: download predictions in compatibility format.
- `templates/swebench`: create a SWE-bench dataset/eval from imported content or instance IDs.
- `templates/humaneval`, `templates/mbpp`, `templates/bigcodebench`: create sandbox-native code-eval dataset/eval definitions.

Benchmarks API (`src/routes/api/benchmarks/`):

- `suites`, `instances`, and `runs`: list/create benchmark resources for the Benchmarks page.
- `runs/[runId]`: read run detail, instance results, artifacts, and `benchmark_run_provenance`.
- Internal artifact/status/result callbacks live under `src/routes/api/internal/benchmarks/` and require `INTERNAL_API_TOKEN`.

Internal coordinator routes are BFF-only and require `INTERNAL_API_TOKEN`. They live under `/api/internal/evaluations/...` and start/sync/status-mark run items.

## Sidebar / Navigation

Evaluations is registered under an **Optimize** group in `src/lib/navigation/nav-config.ts` (matches OpenAI's IA). Icon: `FlaskConical`. Match regex covers both `/evaluations` and `/benchmarks` so the official Benchmarks page stays in the same operator area.

## Wizard Internals

`src/lib/components/evaluations/wizard/`:

- `wizard-store.svelte.ts` — Svelte 5 `$state` runes module. `WizardState` includes `step`, `preset`, `dataSource`, `rows`, `uploadFormat`, `uploadContent`, `criteria`, `name`, `description`, `subject` (Agent / Workflow / Imported outputs), `concurrency`, `timeoutSeconds`, `swebenchSuiteSlug`, `swebenchInstanceIds`. Helpers: `addRow`, `updateRow`, `removeRow`, `addCriterion`, `removeCriterion`, `step1Valid`, `step3Valid`, `setStep`, `resetWizard(preset)`.
- `step-1-data-source.svelte` — 5 tile picker; conditional manual rows table / JSONL upload / SWE-bench suite selector.
- `step-2-criteria.svelte` — `Add` opens `<GraderPickerDialog>`; selected criteria render their inline form.
- `step-3-review.svelte` — Name / description / `<SubjectPicker>` / concurrency / timeout / Summary.
- `subject-picker.svelte` — Tabs: Agent (uses `runnableAgents` filter), Workflow (`/api/workflows?projectOnly=1`), Imported outputs (predictions JSONL textarea).
- `grader-picker-dialog.svelte` — 6 tile picker. Each tile carries `{type, mode?}` so Model labeler vs Model scorer both pick `score_model` with the right `config.mode`.
- Six grader forms: `string-check-form`, `text-similarity-form`, `model-labeler-form`, `model-scorer-form`, `python-grader-form`, `endpoint-grader-form`. Each takes `{grader, onChange}`.

`evals/create/+page.svelte`:

- `createDatasetFromRows()` — manual rows path.
- `createDatasetFromUpload()` — uploads JSONL/JSON/CSV. **Injects `externalId: "row_${i+1}"`** on parsed JSONL when no id is present, so predictions can match without forcing the user to add ids.
- `createSwebenchTemplate()` — short-circuits the regular flow and POSTs `/api/evaluations/templates/swebench`. This is the legacy eval adapter, not the official Benchmarks page harness path.
- Predictions JSONL is parsed client-side into `Array<{id, output}>` before POSTing — `normalizeImportedOutputs` only accepts arrays/records and silently drops raw strings.

## Subject Types

- `imported_outputs`: no Dapr execution. The run item generated output is copied from imported outputs (matched by row id, externalId, or row id), or from row `generatedOutput`.
- `agent`: runs a published agent through a generated SW 1.0 hidden workflow. The selected agent id becomes `agentRef.id`; optional version becomes `agentRef.version`.
- `workflow`: runs a selected persisted workflow. Trigger data includes run/item identifiers, dataset row id, `input`, and `expectedOutput`.
- `model`: deliberately rejected at the service layer (`createEvaluationRun` throws 400). Direct model subjects are not implemented; use `agent` with a model-only agent instead.

## Execution Lifecycle

1. UI or API calls `POST /api/evaluations/runs`.
2. `createEvaluationRun` snapshots dataset rows into `evaluation_run_items`.
3. `imported_outputs` runs move straight to grading.
4. `agent` and `workflow` runs start `evaluation-coordinator` via `startEvaluationCoordinator`.
5. Coordinator schedules Dapr workflow `evaluation_run_workflow` with instance id `evaluation-run-<runId>`.
6. Run workflow marks the run `running`, loads run detail, chunks items by `executionConfig.concurrency`, and starts child `evaluation_item_workflow` instances.
7. Item workflow calls BFF `items/<itemId>/start`.
8. The BFF creates a `workflow_executions` row and invokes `workflow-orchestrator` `/api/v2/sw-workflows`.
9. For `agent` subjects, the BFF builds a hidden evaluation workflow with one `durable/run` task. For the legacy SWE-bench eval template, it builds a larger adapter workflow around clone, solve, patch extraction, and harness output.
10. Item workflow polls BFF `items/<itemId>/sync` until the item is terminal or times out.
11. Sync extracts generated output from workflow execution output, grades the item via `runGraderAsync`, recomputes run summary, and completes the run when all items are terminal.

## Official SWE-bench Benchmarks Lifecycle

Use this path for runs that should be visible at `/workspaces/<slug>/benchmarks`:

1. The BFF creates a `benchmark_runs` row and `benchmark_run_instances` rows for selected `benchmark_instances`.
2. The coordinator transitions `queued -> inferencing`, either by running the selected agent or by consuming pre-seeded `model_patch` rows for deterministic smoke tests.
3. `_write_predictions` creates `predictions.jsonl`; `_write_evaluation_dataset` creates `dataset.jsonl`. Artifact rows and `benchmark_run_provenance` capture paths and SHA-256s.
4. Before any Kubernetes Job is created, prediction validation requires parseable JSONL, exactly one row per selected instance, required `instance_id` / `model_name_or_path` / `model_patch`, and a syntactically valid non-empty diff. Empty/null patches are allowed.
5. `_ensure_evaluator_job` transitions `inferencing -> evaluating`, records evaluator image/job/resource/max-workers/timeout/deadline provenance, and launches the evaluator Job with `ttlSecondsAfterFinished=3600`.
6. The evaluator callback records official SWE-bench result semantics (`resolved`, `unresolved`, `empty_patch`, errors), report/stdout/stderr/test-output paths, raw counters when available, and raw harness notes for non-graded pytest errors.
7. The run summary and Benchmarks page show official result separately from raw harness notes. Official resolved/unresolved is the source of truth.

Direct DB smoke runs are acceptable for operator/UI validation when agent inference is not under test. Provide explicit IDs for `benchmark_run_instances`; Drizzle generates IDs app-side and Postgres has no default. Follow the coordinator transition guard exactly: `queued -> inferencing -> evaluating -> completed/failed/cancelled`.

## Run Item Payload Modes

`getEvaluationRun(projectId, runId, { itemMode: "summary" })` keeps the run envelope and item status/score metadata but compacts heavyweight fields:

- `input`: keeps task id, suite, entry point, libs, prompt preview, and omitted byte counts.
- `expectedOutput`: keeps harness metadata, test-file hash, canonical-solution preview, and omitted byte counts.
- `generatedOutput`: keeps phase/success/duration/error plus compact workflow output such as exit code, sandbox, solution/test hashes, runtime probe, pytest tail, solution preview, and omitted byte counts. Raw workflow step outputs stay omitted.

The public run route defaults to full mode for compatibility, but eval run pages should request `?items=summary` and fetch `runs/<runId>/items/<itemId>` only for the selected drawer row. This prevents active code-eval pages from repeatedly downloading and `JSON.stringify`-rendering large test files, pytest logs, raw traces, and solution bodies.

## Prompt Rendering

`buildAgentEvaluationWorkflowSpec` calls `renderPromptTemplate`:

1. Use `evaluation.taskConfig.promptTemplate` if set.
2. Else use `input.prompt` if it is a non-empty string.
3. Else stringify `input`.

Templates support `{{input}}` and `{{input.path.to.value}}`.

The current wizard does not expose prompt template editing. For wizard-created quick evals, put the actual prompt in the row `input.prompt` or `input.<your-field>` and reference it from the grader's templates.

## Grader Behavior

`graders.ts` validates configs and runs scoring synchronously for the simple types. `runGraderAsync` is the canonical entry point used by the service; it dispatches needs-async types to `grader-runners.ts` and falls back to `runGrader` for sync types.

| Type | Behavior |
| --- | --- |
| `string_check` | Default `operation=contains`, `targetPath=generatedOutput`, `referencePath=expectedOutput`, `caseSensitive=false`. Operations: equals / contains / not_contains / starts_with / ends_with / regex. |
| `text_similarity` | Token Jaccard, default threshold `0.8`. Other methods (fuzzy / BLEU / ROUGE / cosine) are present in the form select but disabled "coming soon". |
| `score_model` | Async `runScoreModelGrader`. `config.mode` distinguishes labeler vs scorer. Renders `systemTemplate` + `userTemplate` with `{{item.X}}` and `{{sample.output_text}}` substitutions. Calls the per-agent runtime pod's `/api/grader-evaluate`. Parses JSON `{label, reasoning}` (labeler) or `{score, reasoning}` (scorer). **Falls back to bare-label / bare-numeric** when the LLM ignores the JSON instruction. |
| `python` | Async `runPythonGrader`. POSTs to `code-runtime` `/execute` with `{language: "python", source, entrypoint: "grade", args: [sample, item]}`. Reads `data.result` from the response envelope and clamps to `[0, 1]`. |
| `endpoint` | Saved as `type: external_harness` with `config.url + headers + scorePath + passThreshold`. Dispatcher routes to async `runEndpointGrader` whenever `external_harness && config.url` is set. POSTs `{sample, item}` to the URL and reads `scorePath` from the response. |
| `multi` | Validates child graders, aggregates by `average` / `all` / `any`. |
| `external_harness` (legacy SWE-bench) | Reads structured results using `resultPath`, `passPath`, and `scorePath`. |

`aggregateGraderResults` ignores skipped graders, combines scored grader weights, fails on any active grader error, and requires every active grader to pass.

## Async Runner Wiring

`grader-runners.ts:invokeEvaluatorAgent` (used by score_model):

1. If `EVALUATIONS_GRADER_URL` env is set on the BFF, POST `{systemPrompt, userPrompt, agentSlug}` to that URL. Returns the `{output}` field. Useful escape hatch for Cloudflare Workers or custom rubric services.
2. Otherwise, call `wakeAgentRuntime(slug, 30_000)` from `$lib/server/kube/client` to bring the per-agent pod up.
3. Then POST via the BFF's Dapr sidecar: `${getDaprSidecarUrl()}/v1.0/invoke/agent-runtime-${slug}/method/api/grader-evaluate` with `{systemPrompt, userPrompt}`. Read `{output}`.

`grader-runners.ts:runPythonGrader`:

1. POST to `getCodeRuntimeUrl()/execute` with `{language: "python", source, entrypoint: "grade", args: [sample, item]}`.
2. Read `envelope.data` (the value `grade(sample, item)` returned).
3. Clamp to `[0, 1]`. Compare against `passThreshold`.

`grader-runners.ts:runEndpointGrader`:

1. POST `{sample, item}` to `config.url` with `config.headers`.
2. Read `config.scorePath` (default `score`) from the response. Clamp to `[0, 1]`.

## dapr-agent-py /api/grader-evaluate

Lives in `services/dapr-agent-py/src/main.py` (search the literal string). Synchronous FastAPI endpoint:

```
POST /api/grader-evaluate
{
  "systemPrompt": "...",
  "userPrompt": "...",
  "model": "..."             // optional component override (defaults to env or DEFAULT_LLM_COMPONENT)
}
→ 200 OK { "output": "<assistant text>" }
```

Implementation: builds a one-turn `[{role: "user", content: userPrompt}]` message list with `system=systemPrompt`, calls `_call_anthropic_sdk(component, messages, tools=None, **kwargs)` directly. No tools, no compaction, no MCP, no Dapr workflow. Returns concatenated text content blocks.

The endpoint relies on the per-agent pod's `ANTHROPIC_API_KEY` env var (already configured by AgentRuntime CR).

## Summary Shape

Run summary contains at least:

- `total`
- `passed`
- `failed`
- `errors` (the BFF preserves the legacy field name; `getEvaluationRun` also returns OpenAI-shape `result_counts: { total, passed, failed, errored }` for the UI)
- `passRate`
- `scoreMean`
- `perGrader`: `{ [graderId]: { total, passed, failed, scoreTotal, scored, scoreMean? } }`

Items carry `scores` with aggregate item score/pass and `graderResults` keyed by grader id. Each `GraderResult` has `{ id?, name, type, score, passed, skipped?, error?, details? }`.

## UI Flow For A Fast Demo

Use this when asked to demonstrate the evaluations system:

1. Open `/workspaces/default/evaluations/evals/create`.
2. Step 1: pick `Upload a file`. Paste a few JSONL rows, e.g.:

   ```
   {"input":"My monitor wont turn on","expected":"Hardware"}
   {"input":"I am in vim and cant quit","expected":"Software"}
   {"input":"Best restaurants in Cleveland","expected":"Other"}
   ```

3. Step 2: `Add` → `String check`. Defaults are sensible (`operation=equals`, `targetPath=generatedOutput`, `referencePath=expectedOutput`).
4. Step 3: name `wizard-smoke`, switch Subject to `Imported outputs`, paste predictions:

   ```
   {"id":"row_1","output":"Hardware"}
   {"id":"row_2","output":"Software"}
   {"id":"row_3","output":"Other"}
   ```

5. Click `Create and run`. Redirect lands on the run detail page with `Total 3 / Passed 3 / Failed 0 / Errored 0 / Pass rate 100%`. Click any row → drawer with row rail + Input/Expected/Output/Graders sections.

For an `agent` demo, swap Step 3 to Subject = `Agent` and pick a published agent. Wake takes up to 30s on cold start.

For a `score_model` demo, add a `Model labeler` grader on Step 2, pick a preset (e.g., `Criteria match`), then set `config.model` to a published agent slug whose runtime image includes `/api/grader-evaluate` (any agent published from a workflow-builder commit on or after the OpenAI parity rollout).

## Operational Debugging

Useful checks:

```bash
kubectl logs -n workflow-builder deploy/evaluation-coordinator --tail=200
kubectl logs -n workflow-builder deploy/workflow-orchestrator -c workflow-orchestrator --tail=200
kubectl logs -n workflow-builder deploy/workflow-orchestrator -c daprd --tail=200
kubectl get agentruntimes -n workflow-builder
kubectl get pods -n workflow-builder | rg 'evaluation|workflow-orchestrator|agent-runtime'
```

Inspect recent runs:

```bash
kubectl exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -Atc "
select r.id, r.status, r.summary, r.subject_type, r.subject_id, i.status, i.scores, i.error
from evaluation_runs r
join evaluation_run_items i on i.run_id = r.id
order by r.created_at desc
limit 10;"
```

If an agent run is queued/running too long:

- Verify coordinator item workflow exists in logs.
- Verify `workflow_executions.dapr_instance_id` was recorded.
- Verify `workflow-orchestrator` accepted `/api/v2/sw-workflows`.
- Verify target `AgentRuntime` moved from `Sleeping` to `Starting` to `Active`.
- Verify target runtime pod has both app and daprd containers ready.
- Read agent runtime logs if the item reached `durable/run`.

If a `score_model` grader errors with `agent-runtime-<slug> /api/grader-evaluate returned 404`:

- Confirm the AgentRuntime CR's `spec.environment.imageTag` points at a `dapr-agent-py-sandbox` build that **includes** the `/api/grader-evaluate` endpoint (post OpenAI-parity rollout). Older images return 404.
- The BFF caches nothing here; the failure is per-call. Patching the CR + waking the pod is sufficient.

If a `python` grader errors with `code-runtime returned 404` or `python grader returned non-numeric value`:

- Confirm the user's `def grade(sample, item) -> float:` actually returns a float.
- The wrapper passes `entrypoint=grade`. Renaming the function silently breaks the runner.

## Known Gotchas

- A failed `workflow-orchestrator` `StartInstance` with `DEADLINE_EXCEEDED` may show `workflow_runtime_unavailable` even when health probes say taskhub ready. Record the failure, inspect daprd logs for actor retries, and consider a workflow-orchestrator rollout restart if the local runtime is stuck.
- The generated output for generic agent runs may appear in the UI as the full workflow result object. The assistant content can be nested at `outputs.evaluate.data.content`. Grading may still pass if the expected text is contained in that object.
- Wizard-created evals rely on `row.input.prompt` for now; they do not expose `taskConfig.promptTemplate`.
- The legacy SWE-bench eval template is an adapter, not the base eval model. Do not design new core eval behavior around SWE-bench-only assumptions.
- Local OpenAI `evals/main` registry JSONL files may be Git LFS pointers. Use the README examples or pull LFS data before importing actual rows.
- Do not conflate `/api/benchmarks/*` with the legacy eval adapter. `/api/benchmarks/*` is the current official SWE-bench harness surface for workflow-builder operators; `/api/evaluations/templates/swebench` is the legacy OpenAI-parity eval template.
- LLMs frequently ignore "respond with JSON" instructions and emit a bare label. The bare-label / bare-numeric fallback in `runScoreModelGrader` covers the common case; tighten the rubric if the model still drifts.
- The wizard's upload mode injects `externalId: "row_${i+1}"` only when `id`/`externalId`/`external_id` are absent on the parsed JSONL. If users pre-populate `id`, the predictions JSONL must use the same id values.

## Tests To Prefer

- Unit tests for grader config validation, sync grader scoring, prompt rendering, imported-output normalization, predictions JSONL, and summary aggregation.
- Async runner tests with mocked `daprFetch` (`runScoreModelGrader` happy path; bare-label fallback; `runPythonGrader` against a mocked `code-runtime`; `runEndpointGrader` with a fake fetch).
- Service tests for create run, start item, sync item, grade item/run, cancel, rerun, artifact recording, and adapter output ingestion.
- UI tests for wizard step-by-step navigation, dataset detail, run detail KPI strip, drawer row rail navigation (click + ↑/↓), and predictions link.
- Operational smoke for a single-row published-agent eval, a single-row imported-output eval, and a single-row Model labeler eval against a published evaluator agent.
