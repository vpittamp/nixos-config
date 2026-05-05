---
name: evaluations
description: "Use for workflow-builder evals, official SWE-bench benchmark runs, Benchmarks UI, DeepSeek/Together SWE-bench provider canaries, swebench-coordinator/evaluator jobs, provenance, datasets, graders, predictions JSONL, run summaries/items, benchmark cancellation/cleanup, the Inspect drawer, eval wizard, OpenAI-parity eval UI, HumanEval+/MBPP+/BigCodeBench code-eval templates, the legacy SWE-bench eval template, evaluation-coordinator, code-eval-item workflow rows, strict-tool LLM judges, score_model live grading through per-agent runtime pods, taskConfig.workflowId workflow lookup, dapr-agent-py grader rollout, the Braintrust-adoption analyst surfaces on the Benchmarks page (regression detection / scorer tiles / promote-to-dataset / composite trace view / cohort pivots / human annotations), benchmark_run_instance_scores + benchmark_run_instance_annotations tables, and the Phase G inline scorer-runner."
---

# Workflow-Builder Evaluations

Build, run, and debug the OpenAI-parity evaluation system in `/home/vpittamp/repos/PittampalliOrg/workflow-builder/main`. This skill covers the SvelteKit UI, the SvelteKit BFF service layer, the Python `evaluation-coordinator` Dapr workflow, the asynchronous grader runners (including the live `score_model` path against per-agent runtime pods), the official SWE-bench Benchmarks page/coordinator/evaluator path, and the operational steps to roll dapr-agent-py changes into ryzen and dev/staging.

The system intentionally mirrors **platform.openai.com/evaluation** surface-by-surface:

- `/workspaces/<slug>/evaluations?tab=datasets|evals` — list with empty-state copy that matches OpenAI verbatim.
- `/workspaces/<slug>/evaluations/evals/<evalId>` — eval detail (Report tab) + run selector (Data tab).
- `/workspaces/<slug>/evaluations/evals/<evalId>/runs/<runId>` — run detail with `result_counts` KPI strip and per-criteria breakdown.
- `/workspaces/<slug>/evaluations/evals/create` — 3-step wizard (data → criteria → review/run).
- `/workspaces/<slug>/evaluations/datasets/<datasetId>` — dataset detail with rows table and drawer.
- The legacy 1100-line `+page.svelte` is preserved at `evaluations/evals-legacy/` as a fallback.

Official SWE-bench runs that operators need to see in the product use the separate `/workspaces/<slug>/benchmarks` surface backed by `benchmark_*` tables, `/api/benchmarks/*`, `swebench-coordinator`, and a Kubernetes evaluator Job.

## Mental Model

A **dataset** is versionable input rows. An **eval** is a reusable contract = data source + ordered graders. A **run** is one async execution of that contract against a **subject** (Agent / Workflow / Imported outputs / legacy SWE-bench eval template). Postgres stores the projection; Dapr Workflows provide execution durability via the `evaluation-coordinator` and `workflow-orchestrator`. Grading runs BFF-side after each item completes — the BFF dispatches to sync grader logic for `string_check` / `text_similarity` / `multi` / `external_harness` and to async runners (`grader-runners.ts`) for `score_model` / `python` / endpoint-shaped `external_harness`.

The official SWE-bench harness is deliberately separate from that eval-run model: `benchmark_runs` snapshot selected `benchmark_instances`, the coordinator writes dataset/predictions artifacts, validates predictions JSONL, launches one evaluator Job, and stores official resolved/unresolved/empty-patch results plus provenance for the Benchmarks page.

## First Steps For Any Eval Question

1. Read the canonical surface BEFORE making claims. Start with:
   - UI shell: `src/routes/workspaces/[slug]/evaluations/+page.svelte`
   - Detail routes: `evals/[evalId]/+page.svelte`, `evals/[evalId]/runs/[runId]/+page.svelte`, `datasets/[datasetId]/+page.svelte`
   - Wizard host: `evals/create/+page.svelte` + `src/lib/components/evaluations/wizard/`
   - Shared components: `src/lib/components/evaluations/{run-items-table,run-inspect-drawer,types}.{svelte,ts}`
   - Service: `src/lib/server/evaluations/service.ts`
   - Benchmarks surface: `src/routes/workspaces/[slug]/benchmarks/`, `src/routes/api/benchmarks/`, `src/routes/api/internal/benchmarks/`
   - SWE-bench coordinator/evaluator: `deploy/swebench-coordinator/src/app.py`, `services/swebench-evaluator/`
   - Grader logic: `src/lib/server/evaluations/graders.ts` (sync) + `grader-runners.ts` (async)
   - Coordinator: `services/evaluation-coordinator/src/app.py`
   - Sync evaluator endpoint: `services/dapr-agent-py/src/main.py` (search `/api/grader-evaluate`)

2. Decide the layer first: UI (Svelte), service (TypeScript), grader runtime (TS + Python), or operational (kubectl + Tekton). Keep changes scoped to that layer unless the symptom crosses boundaries.

3. For deeper detail (tables, lifecycle, gotchas, smoke tests) read `references/system-model.md`. For SWE-bench concurrency/capacity questions, read `references/swebench-concurrency.md` before changing limits.

## Decision Table

| Task | Do this |
| --- | --- |
| **Explain how evals work** | Summarize the three-resource model (Dataset → Eval → Run) + grader catalog + Dapr-backed execution + the OpenAI-parity surface. |
| **Demo the wizard end-to-end** | Open `evals/create`, pick `Upload a file`, paste a small JSONL, add a `String check` grader, set Subject = `Imported outputs` with a predictions JSONL of `{id:"row_N", output:...}`. Click Create and run. Drawer + KPIs populate. |
| **Add or modify a grader form** | Edit `src/lib/components/evaluations/wizard/<grader>-form.svelte`. Six exist today: `string-check`, `text-similarity`, `model-labeler`, `model-scorer`, `python`, `endpoint`. Each takes `{grader, onChange}` and emits a config compatible with `validateGraderConfig` in `graders.ts`. |
| **Change run-detail KPIs, items table, or drawer** | Edit `src/lib/components/evaluations/run-items-table.svelte` (table + per-grader columns) or `run-inspect-drawer.svelte` (left rail + Input/Expected/Output/Graders sections). Run pages now fetch `GET /api/evaluations/runs/<runId>?items=summary` and lazy-load a full item with `GET /api/evaluations/runs/<runId>/items/<itemId>` when the drawer opens. Preserve this compact-summary path for active polling. |
| **Debug eval UI freezes** | Check payload size and client rendering first. Code-eval rows can contain large prompts, generated test files, pytest output, raw workflow outputs, and solution text. The run table/drawer should use compact summaries and shallow previews, not `JSON.stringify` of every row on every 4s poll. |
| **Change grader scoring or wire a new grader** | Sync types live in `src/lib/server/evaluations/graders.ts` (`runGrader`, `validateGraderConfig`, `aggregateGraderResults`). Async runners (`runScoreModelGrader`, `runPythonGrader`, `runEndpointGrader`) live in `grader-runners.ts`. Service-side dispatch is in `service.ts:gradeLoadedEvaluationRunItem` — it awaits `runGraderAsync`. |
| **Add a runner that needs an external service** | Use `daprFetch` from `$lib/server/dapr-client` (retry-enabled). For service-invoke against per-agent runtimes, also call `wakeAgentRuntime(slug, 30_000)` from `$lib/server/kube/client` first. |
| **Debug a stuck `agent` or `workflow` run** | Check coordinator logs, orchestrator logs, the `AgentRuntime` CR phase + pod readiness, and `workflow_executions.dapr_instance_id`. See the diagnosis ladder in `references/system-model.md`. |
| **Roll dapr-agent-py grader changes** | The agent endpoint lives in `services/dapr-agent-py/src/main.py`. Per-agent runtime pods use `dapr-agent-py-sandbox:<tag>`. Rebuild needs **two PipelineRuns**; re-rolling already-published agents needs a CR patch. See "Operational Rollout" below. |
| **Add a new code-eval template** (HumanEval+/MBPP+/BigCodeBench) | Caller fetches rows from `datasets-server.huggingface.co/rows?dataset=<hf_id>&split=test`, POSTs to `/api/evaluations/templates/{humaneval,mbpp,bigcodebench}`. `createCodeEvalTemplate` (`service.ts`) creates dataset+eval with `taskConfig.workflowId="code-eval-item"` and a default grader stack (`string_check` on pytest exit + `score_model` labeler with strict `responseSchema`). |
| **Make a score_model judge return guaranteed JSON** | Set `responseSchema` (JSON Schema) + `responseToolName` (default `emit_evaluation`) on the grader config. The runtime forces a single Anthropic tool call constrained to that schema and returns `tool_use.input` as the parsed object — no prose, no JSON.parse fallback. See "Forced-tool LLM judge" below. |
| **Use a reusable workflow for an eval** | Set `taskConfig.workflowId` on the eval definition. `startEvaluationRunItemWorkflow` (`service.ts:~1107`) loads the workflow from the `workflows` table, stamps `agentRef` into `trigger.input`, and runs that spec instead of generating one in TS. Edit the workflow JSON via the canonical seed file + `scripts/upsert-<workflow>-workflow.mjs` to roll prompts/maxTurns without a BFF redeploy. |
| **Run/verify official SWE-bench in the UI** | Use `/workspaces/<slug>/benchmarks` and `/api/benchmarks/*`, not the eval wizard template. Normal run creation starts agent inference; deterministic operator smoke can seed `benchmark_runs`/`benchmark_run_instances` with known patches and then call coordinator helpers to write artifacts and launch the evaluator Job. Results must land back in the Benchmarks page with provenance, artifact SHA-256s, official result, and raw harness notes. |
| **Handle the legacy SWE-bench eval template** | It's still wired (`/api/evaluations/templates/swebench` + `buildSwebenchEvaluationWorkflowSpec`) but **not the official harness path**. Use it only when explicitly working on the old OpenAI-parity eval adapter. For real SWE-bench validation, use the Benchmarks page/coordinator/evaluator Job path. Prefer HumanEval+/MBPP+/BigCodeBench (sandbox-native pytest) for eval-wizard code-eval coverage. |

## Official SWE-bench Benchmarks

Use this path when the user asks for SWE-bench evals that should show up in workflow-builder's Benchmarks UI:

1. UI/API surface: `/workspaces/<slug>/benchmarks`, `GET/POST /api/benchmarks/runs`, `GET /api/benchmarks/runs/<runId>`.
2. Data model: `benchmark_suites`, `benchmark_instances`, `benchmark_runs`, `benchmark_run_instances`, `benchmark_artifacts`, `benchmark_run_provenance`, and (Braintrust adoption, 2026-04-30) `benchmark_run_instance_scores`, `benchmark_run_instance_annotations`, plus `evaluation_dataset_rows.{origin_run_instance_id, origin_session_id}`.
3. Coordinator path: `deploy/swebench-coordinator/src/app.py` writes `dataset.jsonl` + `predictions.jsonl`, validates JSONL and selected instance coverage, then creates a Kubernetes evaluator Job.
4. Evaluator callback: `/api/internal/benchmarks/evaluation-results` records official resolved/unresolved/empty-patch status, harness report/stdout/stderr/test-output paths, parsed counters, raw harness notes, and run provenance.
5. Provenance should include evaluator image/job name, resource class, max workers, timeout/deadline, dataset/prediction paths + SHA-256s, harness report path, environment image/digest summaries, and timestamps.

Provider canaries use the same Benchmarks path, not the eval wizard. Direct DeepSeek models are `deepseek/deepseek-v4-pro` and `deepseek/deepseek-v4-flash`; they route through `dapr-agent-py` components `llm-deepseek-v4-pro` and `llm-deepseek-v4-flash`, not Together. SWE-bench coding agents should expose the normal coding tool set, including `grep_search`, and run only on validated inference environments. Current dev concurrency is governed by the layered capacity model in `references/swebench-concurrency.md`; do not assume the launch-sheet value is the effective throughput.

Deterministic operator smoke is allowed when agent inference is not the thing under test: insert a queued `benchmark_runs` row and explicit-id `benchmark_run_instances` rows with `model_patch`, `patch_sha256`, and `patch_bytes`; mark the run `inferencing`; call `_write_predictions`, `_write_evaluation_dataset`, then `_ensure_evaluator_job`. The status guard is strict (`queued -> inferencing -> evaluating -> completed/failed/cancelled`), so launching from `queued` fails.

Empty or null `model_patch` is a valid evaluator input and should become `empty_patch` when the harness reports it. That is an expected unresolved instance, not a harness failure. Official SWE-bench resolved/unresolved remains authoritative even if raw pytest output has extra non-graded errors; show those separately as raw harness notes.

**K8s label sanitization on coordinator-launched Jobs.** Run IDs are nanoid-generated and can legally end in `_` or `-`, which fails K8s label-value validation `(([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])?`. Symptom: run goes `failed` at the evaluating stage with HTTP 422 `Invalid value: "<id>": a valid label must ... start and end with an alphanumeric character`. The Phase G `patch_files_overlap_gold` scorer (gated on harness completion) won't fire as a side effect. Fix landed in coordinator at workflow-builder `0f369b58` via `_safe_label_value` (strips outer `[._-]`, caps 63 chars). If you add another K8s resource that labels with a run/instance ID, mirror the helper.

**Cancellation and stalled-instance cleanup are Dapr lifecycle work, not just DB updates.** A terminal benchmark run may still have a parent `workflow-orchestrator` workflow plus `dapr-agent-py` session and per-turn child workflows running. Terminate/poll/purge the agent-runtime session/turn workflows first, then the parent workflow. Only mark `sessions`/`workflow_executions` terminal, delete sandboxes, or release leases after every durable instance is terminal or missing. If shutdown is not confirmed, leave leases and sandboxes in place so retry cleanup can find the still-running workflows. Post-cancel events such as `sandbox not found` or orphaned Dapr histories mean cleanup raced ahead of durable shutdown.

## Benchmarks UI: Braintrust-adoption surfaces (Phase F → K)

Six analyst surfaces shipped 2026-04-30 alongside the existing `/workspaces/<slug>/benchmarks` Phase A–E metrics. Each gates on its data being present so empty states render naturally — Phase G/K only populate after a fresh run completes (scorers fire inside `recomputeRunSummary` on instance terminal, not retroactively).

| Phase | Surface | Server | Storage |
|---|---|---|---|
| **F** Statistical regression detection | `MetricRegressionStrip` on the compare page (`?runs=A,B[,C…]`) — Welch's t-test + Fisher's exact p-values vs the baseline run. 2 Fisher's tests + 5 Welch tests. | `src/lib/server/benchmarks/regression.ts` (pure TS, no deps; Fisher's exact, Welch's t-test, Lanczos log-gamma, Wilson). Wired through `comparison.ts:loadCompareData`. | none |
| **G** Scorers | `ScorerTiles` on run-detail; per-instance scorer rows in the trace tab. **4 scorers** today: `patch_files_overlap_gold` (deterministic, harness-gated) · `ran_tests_locally` (deterministic span scan) · `edit_minimality` (LLM-judge via `claude-haiku-4-5`) · `reasoning_quality` (LLM-judge). | `score-runner.ts` invoked from `recomputeRunSummary` inline (~10–30 s after harness). Idempotent on `(run_instance_id, scorer_name, scorer_version)`. | `benchmark_run_instance_scores` (migration 0057) |
| **H** Promote-to-dataset | `PromoteToDataset` popover on the drawer's Harness tab. Captures the SWE-bench problem identity + the harness-graded outcome as an evaluation dataset row, with bidirectional pointer back to the source run. | `POST /api/evaluations/datasets/[datasetId]/rows-from-benchmark`. Extends `createEvaluationDatasetRows`. | `evaluation_dataset_rows.{origin_run_instance_id, origin_session_id}` (migration 0058) |
| **I** Composite trace view | `TraceDetail` Svelte component as a new `Trace` tab on the run-instance drawer. Header strip (turns/tool calls/TTFT/tokens) + scorers panel + chronological waterfall (LLM/tool spans, click-to-expand input/output) + annotation footer. | `GET /api/benchmarks/runs/[runId]/instances/[instanceId]/scores` for scorer rows; existing `/spans` for span data. | none |
| **J** Cohort pivots | `CohortPivot` Svelte component on run-detail (5 dimensions × 8 measures dropdowns + horizontal bar chart). | `RunStats.cohortRows` shipped from `computeRunStats`. **`pivot()` lives at `$lib/benchmarks/cohort.ts`** — NOT `$lib/server/benchmarks/stats.ts`, intentionally — Svelte components can't import from `$lib/server` (vite-plugin-sveltekit-guard). | none |
| **K** Human annotations | `<TraceDetail>` annotation footer: 4 verdict buttons (correct/incorrect/partial/unsure) + reasoning textarea. Run-detail page tile shows aggregate counts + `harnessDisagreement` count. | `GET/POST/DELETE /api/benchmarks/runs/[runId]/instances/[instanceId]/annotations`. UPSERT keyed on `(run_instance_id, user_id)` — one verdict per user per instance. Aggregated as `RunStats.humanAnnotations.{counts, totalAnnotated, harnessDisagreement}`. | `benchmark_run_instance_annotations` (migration 0059) |

**Operator workflow that exercises all 6**:
1. Launch 2 runs vs the same Verified instance subset on different agents → compare page shows Fisher/Welch p-values.
2. Open a run's instances drawer → Harness tab shows "Add to dataset"; Trace tab shows header strip + scorer rows + waterfall + annotation footer.
3. Run-detail page shows scorer tiles + cohort pivot dropdowns + (after annotations exist) human-annotation aggregate tile.

**Don't roll workflow-orchestrator/swebench-coordinator images mid-run.** Dapr durable-task replay compares the in-process code's `call_activity` ordering to the persisted history. New image lands on the worker pod between yields → replay fails with `Sub-orchestration task #N failed: A previous execution called call_activity with ID=M, but the current execution doesn't have this action with this ID`. Hit twice on 2026-04-30. Wait for active runs to terminate before pushing image bumps.

**Phase G scorer-runner integration with the existing grader system**: `score-runner.ts` reuses the same `score_model` LLM-judge transport (Anthropic Messages API via fetch) used by `runScoreModelGrader`, but it writes to `benchmark_run_instance_scores` instead of evaluation grader rows, and runs unconditionally per-instance from `recomputeRunSummary` — not per evaluation grader contract. The two systems are orthogonal: graders are part of the eval-run lifecycle and gate on `evaluation_run_items.status='terminal'`; benchmark scorers are part of `benchmark_run_instances.status='resolved'/'unresolved'/etc` and are SWE-bench-specific (the `patch_files_overlap_gold` and `ran_tests_locally` scorers only make sense for code-modifying agent runs).

## Grader Catalog (live status)

| Grader | UI form | Runner | Status | Where it lives |
|---|---|---|---|---|
| `string_check` | `string-check-form.svelte` | sync `runStringCheck` | Live | `graders.ts` |
| `text_similarity` | `text-similarity-form.svelte` | sync `runTextSimilarity` (token Jaccard) | Live | `graders.ts` |
| `score_model` (Model labeler / Model scorer) | `model-labeler-form.svelte`, `model-scorer-form.svelte` | async `runScoreModelGrader` | Live + strict-tool path | `grader-runners.ts` → POST `/v1.0/invoke/agent-runtime-<slug>/method/api/grader-evaluate` with optional `responseSchema` + `responseToolName` for guaranteed-shape JSON |
| `python` | `python-grader-form.svelte` | async `runPythonGrader` | Live | `grader-runners.ts` → POST to `code-runtime` `/execute` with `{language:"python", source, entrypoint:"grade", args:[sample,item]}` |
| `endpoint` (saved as `external_harness` with `config.url`) | `endpoint-grader-form.svelte` | async `runEndpointGrader` | Live | `grader-runners.ts` — direct HTTPS POST `{sample, item}` + `scorePath` extraction |
| `multi` | n/a (composite) | sync `runMultiGrader` | Live | `graders.ts` |
| `external_harness` (legacy SWE-bench) | n/a | sync `runExternalHarness` | Live | `graders.ts` |

The wizard's "Endpoint grader" UI is intentionally saved as `type: external_harness` with `config.url + headers + scorePath + passThreshold`; the dispatcher routes to the async runner whenever `external_harness && config.url` is set.

`runScoreModelGrader` accepts a bare label string (`Pass`, `Fail`, `Positive`, ...) when JSON parsing fails, by looking up the response token in the configured labels list. Equivalent fallback for scorer mode parses bare numerics. The bare-label fallback is now mostly unnecessary — set `responseSchema` on the grader config and the runtime forces a strict tool call (see below).

## Forced-tool LLM judge (`responseSchema`)

The legacy "ask the model for JSON in prose" path is unreliable: Opus 4.7 frequently emits `Result: [CORRECT]` or wraps JSON in markdown. The strict-tool path makes Anthropic grammar-constrain the response to a JSON Schema.

How to wire it on a `score_model` grader config:

```json
{
  "name": "Solution implements the task",
  "type": "score_model",
  "config": {
    "mode": "labeler",
    "model": "coding-assistant",
    "systemTemplate": "You are a strict code reviewer. Output ONLY via the emit_evaluation tool.",
    "userTemplate": "Repository: {{item.repo}}\n\nProblem: {{item.problemStatement}}\n\nCandidate: {{sample.output_text}}",
    "labels": [
      {"label": "Pass", "passing": true},
      {"label": "Fail", "passing": false}
    ],
    "passingLabels": ["Pass"],
    "responseSchema": {
      "type": "object",
      "properties": {
        "label": {"enum": ["Pass", "Fail"]},
        "reasoning": {"type": "string"}
      },
      "required": ["label", "reasoning"],
      "additionalProperties": false
    },
    "responseToolName": "emit_evaluation"
  }
}
```

What happens server-side:

- `validateGraderConfig case "score_model"` (`graders.ts`) passes `responseSchema` + `responseToolName` through.
- `runScoreModelGrader` includes them in the POST body to `/api/grader-evaluate`.
- `/api/grader-evaluate` (`services/dapr-agent-py/src/main.py`) builds `tools=[{name, input_schema, "strict": true}]` + `tool_choice={"type":"tool","name": responseToolName}`.
- `_call_anthropic_sdk` forwards `tool_choice` (and now `system`) into `request_kwargs`. **Suppresses the adaptive thinking kwarg** when `tool_choice.type == "tool"` because Anthropic API rejects the combo with HTTP 400 "Thinking may not be enabled when tool_choice forces tool use."
- Response: `{"output": "", "toolUse": {"name": "emit_evaluation", "input": {"label": "...", "reasoning": "..."}}}`.
- `runScoreModelGrader` uses `toolUse.input` as the parsed object — skips JSON.parse + bare-label fallback entirely.

Requirements: Anthropic SDK `>=0.51` (pinned in `services/dapr-agent-py/pyproject.toml`). The dict-vs-AgentTool path in `_convert_tools_for_anthropic` (`anthropic_adapter.py`) accepts already-formatted Anthropic tool dicts so the grader endpoint can pass them directly without wrapping in an `AgentTool`.

Existing `score_model` graders without `responseSchema` continue using the legacy prose path — backwards compatible.

## Workflow-as-DB lookup (`taskConfig.workflowId`)

The default eval lifecycle has the BFF generate a SW 1.0 spec in TypeScript (`buildAgentEvaluationWorkflowSpec` for one-shot agents, `buildSwebenchEvaluationWorkflowSpec` for the legacy SWE-bench template). For the new code-eval family (HumanEval+/MBPP+/BigCodeBench) the BFF instead loads a reusable workflow from the `workflows` table and stamps `agentRef` into the trigger:

```ts
// service.ts:startEvaluationRunItemWorkflow (~line 1150):
if (taskConfigWorkflowId) {
  workflow = await loadEvaluationSubjectWorkflow({projectId, workflowId: taskConfigWorkflowId});
  spec = await prepareEvaluationSubjectWorkflowSpec(workflow.spec);
  triggerData = await prepareEvaluationWorkflowTriggerData({
    spec, runId, itemId, datasetRowId,
    input: { ...row.item.input, agentRef: { id: subjectId, version: subjectVersion } },
    expectedOutput: row.item.expectedOutput,
  });
}
```

The canonical workflow JSON is `services/code-eval-runner/code-eval-item.workflow.json`. Its `solve` step authors `body.agentRef` as a placeholder. **Critical**: `resolveSpecAgentRefs` runs at workflow-LOAD time, BEFORE jq expressions evaluate, so a `${ .trigger.agentRef }` string would fail the resolver's AgentRef shape check with `"Task X (durable/run) is missing agentRef. All workflows must be backfilled to named agents before executing."` Service.ts has a helper `stampAgentRefIntoDurableRunSteps` that walks the spec, finds every `durable/run` task's `body.agentRef`, and replaces it with the live `{id, version}` object BEFORE handing the spec to `prepareEvaluationSubjectWorkflowSpec`. The deep-copy keeps the canonical workflow row in the DB placeholder-shaped.

Edit the JSON, run `node scripts/upsert-code-eval-workflow.mjs --user-email <email>` against the spoke DB, and the next run picks up the new prompt/maxTurns without a BFF restart.

**Cross-project workflow lookup.** `loadEvaluationSubjectWorkflow` accepts a workflow when `(workflowId matches AND (projectId matches OR visibility='public'))`. Public workflows are intentionally cross-project reusable — a single seeded `code-eval-item` row works for every workspace. Don't filter by `projectId` strictly when the workflow is meant to be a shared template.

**Seed-script gotcha**: `${JSON.stringify(workflow.spec)}::jsonb` can double-encode the spec into a JSONB string under some postgres-js conditions. If `jsonb_typeof(spec) = string` after seeding, the workflow won't run (the orchestrator can't parse `spec.do`). Fix by re-running with `sql.json(workflow.spec)` instead — tighter than the cast and avoids the double-escape. Quick check: `select jsonb_typeof(spec), jsonb_array_length(spec->'do') from workflows where id='code-eval-item'` — should return `object` and the step count, not `string` and an error.

**Owner binding**: when seeding a NEW workflow, `resolveOwner` in the upsert script uses `--user-email <email>` to bind it to a real user's project. Without `--user-email`, it falls back to "first user in DB", which can land the workflow in a stranger's project. Always pass `--user-email vinod@pittampalli.com` (or the deploying user) when seeding `public` workflows on a fresh cluster.

## Code-eval templates (HumanEval+ / MBPP+ / BigCodeBench)

These are sandbox-native Python coding evals (no Docker harness) that supersede SWE-bench for v1 code-eval coverage.

| Suite | HF dataset (config=`default`) | Rows | Template route |
|---|---|---|---|
| HumanEval+ | `evalplus/humanevalplus` | 164 | `POST /api/evaluations/templates/humaneval` |
| MBPP+ | `evalplus/mbppplus` | 378 | `POST /api/evaluations/templates/mbpp` |
| BigCodeBench | `bigcode/bigcodebench` | 1140 | `POST /api/evaluations/templates/bigcodebench` |

`datasets-server.huggingface.co` requires `&config=default` for these datasets — without it the rows endpoint returns 422 `Parameter 'config' is required`.

Lifecycle:

1. Caller fetches rows from `datasets-server.huggingface.co/rows?dataset=<id>&config=default&split=test&offset=0&length=N` (no auth required for these public datasets).
2. POST `{rows: [...], name?, description?, graderAgentSlug?}` to the template route.
3. `createCodeEvalTemplate` normalizes each row to `{taskId, prompt, entryPoint, suite, solvePrompt}` + `{testFileContent, canonicalSolution}`, creates the dataset + eval definition with `taskConfig.workflowId="code-eval-item"`, and seeds default graders.
4. Default grader stack:
   - `string_check` on `generatedOutput.workflowOutput.exitCode == "0"` (pytest passed).
   - `score_model` labeler with strict `responseSchema` — judges whether the candidate solution implements the task vs hardcoding test outputs.
5. Run on a subject `agent` (e.g. `coding-assistant`). Workflow runs `workspace_profile (code-eval template)` → `workspace/write_file test_solution.py` → `durable/run` (agent writes `solution.py`) → `workspace/command pytest`.

### Code-eval harness semantics

`normalizeCodeEvalTestFile` in `service.ts` is suite-aware:

- **HumanEval+/MBPP+** keep the EvalPlus model. The generated header imports `/sandbox/solution.py`, exposes `candidate = getattr(solution, entryPoint)`, and appends a pytest-discoverable wrapper that calls `check(candidate)` when the dataset test defines `check`. This avoids pytest exit code 5 ("no tests collected") while preserving the EvalPlus candidate contract.
- **BigCodeBench** uses the official shared-module namespace model. The generated header imports `/sandbox/solution.py`, exposes the entry point both by its real name and as `task_func`, then copies every non-dunder global from the solution module into the generated test module before appending the dataset `test` body. This makes aliases and imports such as `os`, `np`, `plt`, `Image`, helper functions, and module-level constants visible to `unittest.TestCase` snippets the same way upstream `candidate_code + "\n" + test_code` does.
- BigCodeBench rows carry metadata `testHarness: "bigcodebench-shared-module-globals"` and `testHarnessVersion: 2`, plus `protocolMode: "internal-agent-visible-tests"` and `benchmarkComparable: false`.
- The workflow still runs pytest over `test_solution.py`. Pytest executes BigCodeBench `unittest.TestCase` classes and the EvalPlus wrapper tests; pass/fail grading remains based on the final test command exit code.

Existing BigCodeBench rows created before the shared-globals header can retain stale `expectedOutput.testFileContent`. For verification, recreate the BigCodeBench evals or repair stored rows by replacing only the generated header while preserving the dataset test body.

### Action slug naming gotcha

When writing files in a workflow, use the **slug-as-operation** form: `workspace/write_file`, `workspace/read_file`, `workspace/edit_file`, etc. There is NO `workspace/file` slug with an `operation:` field. The function-router's openshell-agent-runtime returns `workspace-runtime HTTP 400: operation is required and must be one of read_file, write_file, edit_file, list_files, delete_file, mkdir, file_stat` if you call `workspace/file`. The error message is the canonical list of valid operation names — each is its own action slug.

The `code-eval` sandbox template image (`gitea-ryzen.tail286401.ts.net/giteaadmin/openshell-sandbox-code-eval`) bakes pytest + EvalPlus + the BigCodeBench top-of-funnel library pool (numpy, pandas, scipy, scikit-learn, sympy, networkx, pillow, requests, beautifulsoup4, ...). Built from `services/openshell-sandbox/environments/Dockerfile.code-eval` via Tekton's `environment-image-build` pipeline (commit subject prefix `environment(code-eval):` is the trigger filter). The image is registered in `SANDBOX_TEMPLATE_IMAGES_JSON` on the workflow-builder Deployment.

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
- Table previews must stay shallow. Do not `JSON.stringify(item.input/expectedOutput/generatedOutput)` for every row; active code-eval runs can turn that into repeated multi-MB main-thread work.

`run-inspect-drawer.svelte`:
- 1000px-wide Sheet split into a 220px left rail + main pane.
- Left rail = one button per compact `run.items` summary (row index + status icon + shallow input preview). Click sets `selectedItemId`; the page fetches `runs/<runId>/items/<itemId>` for the full row detail and keeps the compact row visible while loading.
- Keyboard: `ArrowDown`/`j` moves to next item; `ArrowUp`/`k` to previous. Wraps modulo `run.items.length`. Ignores keys when typing in inputs/textareas.
- Main pane: Input · Expected · Output · Graders (per-grader pass/fail icon + score badge + reasoning details) · Error · Trace IDs.
- Polling stops when run status is terminal (`completed`/`failed`/`cancelled`). While polling an active run, keep using `?items=summary`; refresh only the selected item's full detail.

## Run Lifecycle (one-line summary)

`POST /api/evaluations/runs` → `createEvaluationRun` snapshots dataset rows → for `imported_outputs` runs grading is immediate → for `agent`/`workflow` runs the BFF starts the coordinator → coordinator schedules `evaluation_run_workflow` → fan-out per-item child workflows → BFF `items/<id>/start` builds the SW workflow spec and submits to `workflow-orchestrator` → `items/<id>/sync` polls until terminal → BFF runs `runGraderAsync` for each grader → run summary recomputed → run marked `completed`.

For full detail: `references/system-model.md`.

## Operational Rollout

dapr-agent-py code changes (the `/api/grader-evaluate` endpoint, provider adapters such as `deepseek_adapter.py`, `_call_anthropic_sdk`, MCP, hooks, etc.) now fire THREE image PipelineRuns:

1. `dapr-agent-py-image-build` — for legacy `dapr-agent-py:git-<sha>` (used by the legacy `dapr-agent-py` + `dapr-agent-py-testing` Deployments).
2. `dapr-agent-py-sandbox-image-build` — for `dapr-agent-py-sandbox:git-<sha>` (used by every per-agent runtime pod via the AgentRuntime CR).
3. `dapr-agent-py-testing-sandbox-image-build` — for the testing sandbox image used by runtime/conformance paths.

Forced-tool grader-evaluate gotchas seen during the strict-tool rollout:

- **Anthropic API rejects `thinking` + `tool_choice={type:"tool"}`** (HTTP 400 "Thinking may not be enabled when tool_choice forces tool use"). `_call_anthropic_sdk` must suppress the adaptive-thinking kwarg whenever tool_choice forces a single tool. Detection: `isinstance(kwargs.get("tool_choice"), dict) and kwargs["tool_choice"].get("type") == "tool"`.
- **`_convert_tools_for_anthropic` originally only handled AgentTool-like objects** (attribute access `tool.name`). The grader endpoint passes already-formatted dicts. Converter now branches on `isinstance(tool, dict)` and reads from dict keys. Without this branch, tool calls fail with `'dict' object has no attribute 'name'`.
- **`tool_choice={type:"tool", name: ...}` requires `tools[0].strict = true`** for grammar-constrained decoding. Drop the `strict: true` and the model can still emit free-form JSON-ish text inside the tool call.
- **`system` and `tool_choice` were silently dropped from `_call_anthropic_sdk` request_kwargs** before the strict-tool work landed. Both are now forwarded into the streaming request. Pre-existing graders that supplied a `systemPrompt` to the prose path were running without it.
- **DevSpace pods cache stale env vars** (`AGENT_RUNTIME_DEFAULT_IMAGE`, `SANDBOX_TEMPLATE_IMAGES_JSON`). When ArgoCD updates `Deployment-workflow-builder.yaml`, the standard ReplicaSet rolls but the long-lived `workflow-builder-devspace-*` pod doesn't restart. Run `devspace purge` to drop the override OR `kubectl delete pod workflow-builder-devspace-*` to force a refresh. Verify with `kubectl exec deploy/workflow-builder -- printenv AGENT_RUNTIME_DEFAULT_IMAGE`.

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

- Do NOT conflate the legacy SWE-bench eval template with `/api/benchmarks/*`. The OpenAI-parity wizard supersedes the old eval adapter, but `/api/benchmarks/*` plus `/workspaces/<slug>/benchmarks` is the current operator-visible official SWE-bench harness surface.
- Do NOT start a local SvelteKit dev server. The dev loop on ryzen is **devspace sync** to the running pod; on dev/staging it's the hub Tekton outer-loop. Manual `pnpm dev` will not match the live environment.
- Do NOT bake workflow JSON specs into images — `services/<agent>/<name>.workflow.json` is excluded by `.dockerignore`. The workflows table reads from postgres at execution time.
- DO NOT hand-edit `release-pins/workflow-builder-images.yaml` unless the hub Tekton path is broken AND `scripts/gitops/validate-workflow-builder-release-pins.sh` passes locally.
- For score_model graders, the operator can override the transport with `EVALUATIONS_GRADER_URL` env var on the BFF. Useful for routing to a Cloudflare Worker or external rubric service without touching dapr-agent-py.
- The default evaluator agent slug comes from `EVALUATIONS_GRADER_AGENT_SLUG` env (default `evaluator-default`). Publish an agent with that slug or override per-grader with `config.model: <slug>`.

## Authoritative Files

```
src/lib/server/db/schema.ts                          # evaluation_* tables (~line 2861-3214)
src/lib/server/evaluations/service.ts                # CRUD, lifecycle, grade dispatch, createCodeEvalTemplate, taskConfig.workflowId branch
src/lib/server/evaluations/graders.ts                # sync runners + runGraderAsync entry; score_model validator passes responseSchema/responseToolName through
src/lib/server/evaluations/grader-runners.ts         # async score_model / python / endpoint; returns {output, toolUse}
src/lib/components/evaluations/types.ts              # shared TS types
src/lib/components/evaluations/run-items-table.svelte      # compact shallow row previews
src/lib/components/evaluations/run-inspect-drawer.svelte   # compact rail + lazy full-row detail
src/lib/components/evaluations/wizard/               # step-1/2/3, grader forms, subject-picker
src/routes/api/evaluations/                          # public API routes
src/routes/api/evaluations/runs/[runId]/+server.ts   # supports ?items=summary
src/routes/api/evaluations/runs/[runId]/items/[itemId]/+server.ts # full item detail on demand
src/routes/api/evaluations/templates/swebench/       # legacy SWE-bench template (Docker harness — not recommended)
src/routes/api/evaluations/templates/humaneval/      # HumanEval+ template
src/routes/api/evaluations/templates/mbpp/           # MBPP+ template
src/routes/api/evaluations/templates/bigcodebench/   # BigCodeBench template
src/routes/api/internal/evaluations/                 # coordinator-only routes (X-Internal-Token)
src/routes/workspaces/[slug]/evaluations/+page.svelte                    # router shell
src/routes/workspaces/[slug]/evaluations/evals/[evalId]/+page.svelte     # eval detail
src/routes/workspaces/[slug]/evaluations/evals/[evalId]/runs/[runId]/+page.svelte  # run detail
src/routes/workspaces/[slug]/evaluations/evals/create/+page.svelte       # 3-step wizard
src/routes/workspaces/[slug]/evaluations/datasets/[datasetId]/+page.svelte
src/routes/workspaces/[slug]/evaluations/evals-legacy/+page.svelte       # preserved monolith
src/routes/workspaces/[slug]/benchmarks/             # operator-visible SWE-bench benchmark runs (Phase A–E metrics + F–K Braintrust surfaces)
src/routes/workspaces/[slug]/benchmarks/compare/+page.svelte  # Phase F MetricRegressionStrip slot
src/routes/api/benchmarks/                           # benchmark run/suite API
src/routes/api/benchmarks/runs/[runId]/instances/[instanceId]/scores/+server.ts       # Phase G/I per-instance scorer rows
src/routes/api/benchmarks/runs/[runId]/instances/[instanceId]/annotations/+server.ts  # Phase K CRUD (one row per (instance, user))
src/routes/api/evaluations/datasets/[datasetId]/rows-from-benchmark/+server.ts        # Phase H promote endpoint
src/routes/api/internal/benchmarks/                  # coordinator/evaluator artifact, status, result callbacks
src/lib/benchmarks/cohort.ts                         # Phase J pivot() helper — IMPORTANT: NOT in $lib/server (client imports)
src/lib/server/benchmarks/regression.ts              # Phase F Welch's t-test + Fisher's exact (pure TS)
src/lib/server/benchmarks/regression.test.ts         # 11-case Phase F unit tests
src/lib/server/benchmarks/score-runner.ts            # Phase G scorer dispatch from recomputeRunSummary
src/lib/server/benchmarks/score-prompts.ts           # Phase G LLM-judge prompts (edit_minimality, reasoning_quality)
src/lib/server/benchmarks/stats.ts                   # computeRunStats() — sources cohortRows, byScorer, humanAnnotations
src/lib/components/benchmarks/{metric-regression-strip,scorer-tiles,promote-to-dataset,trace-detail,cohort-pivot}.svelte  # F–J components
deploy/swebench-coordinator/src/app.py               # writes artifacts, validates predictions, launches evaluator Jobs; _safe_label_value() (0f369b58) sanitizes run IDs for K8s labels
services/swebench-evaluator/                         # official harness wrapper + callback payloads
services/code-eval-runner/code-eval-item.workflow.json  # canonical 4-step code-eval workflow (workspace_profile → write_test → solve → run_tests)
scripts/upsert-code-eval-workflow.mjs                # seed code-eval-item into the workflows table
services/openshell-sandbox/environments/Dockerfile.code-eval  # sandbox image (pytest + EvalPlus + BigCodeBench libs)
services/evaluation-coordinator/src/app.py           # Dapr workflows
services/dapr-agent-py/src/main.py                   # /api/grader-evaluate (search this string) — accepts responseSchema + responseToolName
services/dapr-agent-py/src/anthropic_adapter.py      # _call_anthropic_sdk forwards system + tool_choice; suppresses thinking on forced-tool path
services/dapr-agent-py/pyproject.toml                # anthropic>=0.51 (required for strict tool-use)
services/workflow-orchestrator/workflows/sw_workflow.py
```

For the Dapr-native architecture roadmap (mapping our six subsystems to Diagrid's Prompt Chaining / Parallelization / Evaluator-Optimizer / Stateful LLM patterns), see the plan at `/home/vpittamp/.claude/plans/create-a-plan-to-fuzzy-crescent.md`.
