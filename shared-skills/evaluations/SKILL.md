---
name: evaluations
description: "Use for workflow-builder evals on the active dev cluster: official SWE-bench runs, exact-ready inference images, Benchmarks UI, Kimi K3/DeepSeek/Claude provider canaries, coordinator/evaluator jobs, datasets, graders, predictions, run inspection, code-eval templates, score_model grading, runtime rollout, and benchmark provenance. Ryzen and dormant staging are opt-in historical/specialized lanes only."
---

# Workflow-Builder Evaluations

Build, run, and debug the OpenAI-parity evaluation system in `/home/vpittamp/repos/PittampalliOrg/workflow-builder/main`. The current shared deployment and test target is **dev**. Do not deploy to or run on Ryzen or dormant staging unless the user explicitly requests that target. This skill covers the SvelteKit UI/BFF, the Python `evaluation-coordinator` Dapr workflow, grader runners, per-session Sandbox pods and the shared `dapr-agent-py` pool, official SWE-bench execution, and runtime rollout.

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
   - SWE-bench coordinator/evaluator: `services/swebench-coordinator/src/app.py`, `services/swebench-evaluator/`
   - Grader logic: `src/lib/server/evaluations/graders.ts` (sync) + `grader-runners.ts` (async)
   - Coordinator: `services/evaluation-coordinator/src/app.py`
   - Sync evaluator endpoint: `services/dapr-agent-py/src/main.py` (search `/api/grader-evaluate`)
   - Claude Agent SDK runtime: `services/claude-agent-py/src/claude_sdk_runner.py`

2. Decide the layer first: UI (Svelte), service (TypeScript), grader runtime (TS + Python), or operational (kubectl + Tekton). Keep changes scoped to that layer unless the symptom crosses boundaries.

3. For deeper detail (tables, lifecycle, gotchas, smoke tests) read `references/system-model.md`. For SWE-bench concurrency/capacity questions, read `references/swebench-concurrency.md` before changing limits. For SWE-bench inference image builds, exact-ready coverage, and cache strategy, read `references/swebench-image-builds.md`. For same-instance agent/model comparison campaigns and MLflow grouping, read `references/swebench-mlflow-comparison.md`.

## Decision Table

| Task | Do this |
| --- | --- |
| **Explain how evals work** | Summarize the three-resource model (Dataset → Eval → Run) + grader catalog + Dapr-backed execution + the OpenAI-parity surface. |
| **Demo the wizard end-to-end** | Open `evals/create`, pick `Upload a file`, paste a small JSONL, add a `String check` grader, set Subject = `Imported outputs` with a predictions JSONL of `{id:"row_N", output:...}`. Click Create and run. Drawer + KPIs populate. |
| **Add or modify a grader form** | Edit `src/lib/components/evaluations/wizard/<grader>-form.svelte`. Six exist today: `string-check`, `text-similarity`, `model-labeler`, `model-scorer`, `python`, `endpoint`. Each takes `{grader, onChange}` and emits a config compatible with `validateGraderConfig` in `graders.ts`. |
| **Change run-detail KPIs, items table, or drawer** | Edit `src/lib/components/evaluations/run-items-table.svelte` (table + per-grader columns) or `run-inspect-drawer.svelte` (left rail + Input/Expected/Output/Graders sections). Run pages now fetch `GET /api/evaluations/runs/<runId>?items=summary` and lazy-load a full item with `GET /api/evaluations/runs/<runId>/items/<itemId>` when the drawer opens. Preserve this compact-summary path for active polling. |
| **Debug eval UI freezes** | Check payload size and client rendering first. Code-eval rows can contain large prompts, generated test files, pytest output, raw workflow outputs, and solution text. The run table/drawer should use compact summaries and shallow previews, not `JSON.stringify` of every row on every 4s poll. |
| **Change grader scoring or wire a new grader** | Sync types live in `src/lib/server/evaluations/graders.ts` (`runGrader`, `validateGraderConfig`, `aggregateGraderResults`). Async runners (`runScoreModelGrader`, `runPythonGrader`, `runEndpointGrader`) live in `grader-runners.ts`. Service-side dispatch is in `service.ts:gradeLoadedEvaluationRunItem` — it awaits `runGraderAsync`. |
| **Add a runner that needs an external service** | Use `daprFetch` from `$lib/server/dapr-client` (retry-enabled). Grader/runtime traffic targets the runtime app id (e.g. `agent-runtime-pool-coding` for the shared coding pool) over Dapr service-invoke; the per-session runtime is an ephemeral agent-sandbox Sandbox pod (Kueue-admitted, self-reaped), so there's no per-agent CR to wake. |
| **Debug a stuck `agent` or `workflow` run** | Check coordinator logs, orchestrator logs, the runtime Sandbox pod readiness (or the shared `dapr-agent-py` pool pod for `agent-runtime-pool-coding` runs), and `workflow_executions.dapr_instance_id`. See the diagnosis ladder in `references/system-model.md`. |
| **Roll dapr-agent-py grader changes** | The agent endpoint lives in `services/dapr-agent-py/src/main.py`. Per-session runtime pods use `dapr-agent-py-sandbox:<tag>` (selected by the `AGENT_RUNTIME_DEFAULT_IMAGE` env var); the static `dapr-agent-py` pool uses `dapr-agent-py:<tag>`. Rebuild normally needs the runtime, sandbox, and testing-sandbox PipelineRuns; rolling the runtime forward is an env-var bump (next session picks it up) — no AgentRuntime CR patch. See "Operational Rollout" below. |
| **Roll claude-agent-py runtime changes** | Build `claude-agent-py-sandbox:<tag>`, update `AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE`, verify the live BFF pod env, then launch a Claude SWE-bench or 3B1B smoke and check `agentRuntime=claude-agent-py`. |
| **Add a new code-eval template** (HumanEval+/MBPP+/BigCodeBench) | Caller fetches rows from `datasets-server.huggingface.co/rows?dataset=<hf_id>&split=test`, POSTs to `/api/evaluations/templates/{humaneval,mbpp,bigcodebench}`. `createCodeEvalTemplate` (`service.ts`) creates dataset+eval with `taskConfig.workflowId="code-eval-item"` and a default grader stack (`string_check` on pytest exit + `score_model` labeler with strict `responseSchema`). |
| **Make a score_model judge return guaranteed JSON** | Set `responseSchema` (JSON Schema) + `responseToolName` (default `emit_evaluation`) on the grader config. The runtime forces a single Anthropic tool call constrained to that schema and returns `tool_use.input` as the parsed object — no prose, no JSON.parse fallback. See "Forced-tool LLM judge" below. |
| **Use a reusable workflow for an eval** | Set `taskConfig.workflowId`; the evaluation application service resolves the scoped/public saved definition. Save changes through Workflow MCP/BFF application ports. Current producer flags port eval/code-eval/SWE-bench definitions to dynamic scripts; direct-DB seed/upsert helpers are not an operator path. |
| **Run/verify official SWE-bench in the UI** | Use `/workspaces/<slug>/benchmarks` and `/api/benchmarks/*`, not the eval wizard template. Normal run creation starts agent inference; deterministic operator smoke can seed `benchmark_runs`/`benchmark_run_instances` with known patches and then call coordinator helpers to write artifacts and launch the evaluator Job. Results must land back in the Benchmarks page with provenance, artifact SHA-256s, official result, and raw harness notes. |
| **Run a Claude Agent SDK SWE-bench smoke** | Seed fixtures under `vinod@pittampalli.com`, choose `agnt_claude_code_swebench_smoke`, set model `anthropic/claude-opus-4-8`, runtime `claude-agent-py`, and launch through `scripts/start-swebench-benchmark-run.ts` with `--agent-id agnt_claude_code_swebench_smoke --apply`. Use traces and `benchmark_runs.agent_runtime` to prove routing. |
| **Compare multiple SWE-bench agents on the same instances** | Use the Benchmarks launch sheet's `Compare agents` mode (or `start-swebench-benchmark-run.bundle.js` per agent with a shared `--tag`). One `benchmark_runs` row per agent, identical instance ids (deterministic for fixed `--limit`), shared campaign tag → `/workspaces/<slug>/benchmarks/compare?tag=<tag>`. MLflow: parent `swebench_run` + `swebench_instance` + `swebench_mlflow_eval` children with `workflow_builder.benchmark_tag.<tag>=true`. **⚠️ On ryzen, launch the per-agent runs STRICTLY SEQUENTIALLY (one terminal before the next, conc ≤ 3, ryzen-health-gated between runs).** Parallel multi-agent launch (9-way) froze a worker node and cascaded postgres/orchestrator down — inference is not admission-controlled. See "System State Update (2026-05-19)". |
| **Handle the legacy SWE-bench eval template** | It's still wired (`/api/evaluations/templates/swebench` + `buildSwebenchEvaluationWorkflowSpec`) but **not the official harness path**. Use it only when explicitly working on the old OpenAI-parity eval adapter. For real SWE-bench validation, use the Benchmarks page/coordinator/evaluator Job path. Prefer HumanEval+/MBPP+/BigCodeBench (sandbox-native pytest) for eval-wizard code-eval coverage. (Note: the eval/code-eval paths grade via sandbox pytest and do NOT call ActivePieces pieces; `fn-activepieces` was deleted and AP pieces now run on the converged per-piece `ap-<piece>-service` piece-runtime in all paths — irrelevant here.) |

## Official SWE-bench Benchmarks

Use this path when the user asks for SWE-bench evals that should show up in workflow-builder's Benchmarks UI:

1. UI/API surface: `/workspaces/<slug>/benchmarks`, `GET/POST /api/benchmarks/runs`, `GET /api/benchmarks/runs/<runId>`.
2. Data model: `benchmark_suites`, `benchmark_instances`, `benchmark_runs`, `benchmark_run_instances`, `benchmark_artifacts`, `benchmark_run_provenance`, and (Braintrust adoption, 2026-04-30) `benchmark_run_instance_scores`, `benchmark_run_instance_annotations`, plus `evaluation_dataset_rows.{origin_run_instance_id, origin_session_id}`.
3. Coordinator path: `services/swebench-coordinator/src/app.py` writes `dataset.jsonl` + `predictions.jsonl`, validates JSONL and selected instance coverage, then creates a Kubernetes evaluator Job.
4. Evaluator callback: `/api/internal/benchmarks/evaluation-results` records official resolved/unresolved/empty-patch status, harness report/stdout/stderr/test-output paths, parsed counters, raw harness notes, and run provenance.
5. Provenance should include evaluator image/job name, resource class, max workers, timeout/deadline, dataset/prediction paths + SHA-256s, harness report path, environment image/digest summaries, and timestamps.

Provider canaries use the same Benchmarks path, not the eval wizard. Kimi canaries use only `kimi/kimi-k3` through `llm-kimi-k3`, authenticated with `KIMI_API_KEY`; K3 calls use a 1,048,576-token context window and maximum thinking. Retired Kimi K2/K2.5/K2.6 model ids must not be selected. Direct DeepSeek models are `deepseek/deepseek-v4-pro` and `deepseek/deepseek-v4-flash`; they route through `dapr-agent-py` components `llm-deepseek-v4-pro` and `llm-deepseek-v4-flash`, not Together. Current Claude canaries should use `anthropic/claude-opus-4-8` on `claude-agent-py`; current GPT canaries should use `openai/gpt-5.5` when that model key is configured. SWE-bench coding agents should expose the normal coding tool set, including `grep_search`, and run only on validated inference environments. Current dev concurrency is governed by the layered capacity model in `references/swebench-concurrency.md`; do not assume the launch-sheet value is the effective throughput. For the current dev scale-up, use DeepSeek V4 Pro, distinct exact-ready SWE-bench_Verified instances, and `maxTurns=25` for infra-capacity checkpoints unless the user explicitly asks for a model-quality run.

The current clean dev checkpoint is run `W4ZmHxaEMEYQDCZ_Ypo41`: 25 distinct exact-ready SWE-bench_Verified instances, DeepSeek V4 Pro, `maxTurns=25`, requested/effective inference concurrency 25/25, requested/effective evaluator concurrency 24/9 because Kueue clamped evaluation, completed with 13 resolved / 7 unresolved / 5 empty-patch, zero evaluator errors, zero hard errors, zero active leases, and no Dapr activity-registration failures. Use this as the baseline before attempting the next larger infra-capacity cohort.

**Claude Agent SDK smoke path (2026-06-06).** Current fixtures synthesize two Claude agents if missing: `agnt_claude_code_sdk_smoke` and `agnt_claude_code_swebench_smoke`. Both use model `anthropic/claude-opus-4-8`, runtime `claude-agent-py`, and runtime app id `agent-runtime-pool-coding`. Seed under the real user:

```bash
DATABASE_URL='postgres://postgres:password@workflow-builder-postgres-dev.tail286401.ts.net:5432/workflow_builder' \
SEED_WORKFLOW_USER_EMAIL='vinod@pittampalli.com' \
SEED_WORKFLOW_PROJECT_ID='N1nbCo9zESa-S0UrzVrOw' \
SEED_SWEBENCH_FIXTURES_SKIP_WHEN_ACTIVE=true \
pnpm tsx scripts/seed-swebench-fixtures.ts
```

For ryzen, use host `workflow-builder-postgres-ryzen.tail286401.ts.net` and project `AgbRSkJ_pVxerT_WOoZwF`. Add `SEED_SWEBENCH_FIXTURES_ROLLBACK=true` for the first dry run. Launch a one-instance smoke with `scripts/start-swebench-benchmark-run.ts --suite SWE-bench_Verified --instance-id astropy__astropy-7166 --limit 1 --concurrency 1 --evaluation-concurrency 1 --user-email vinod@pittampalli.com --project-id <spoke-project-id> --agent-id agnt_claude_code_swebench_smoke --tag claude-agent-py-<spoke>-smoke --apply`. The proof is not the sandbox label; it is `benchmark_runs.agent_runtime='claude-agent-py'`, `agent_runtime_app_id='agent-runtime-pool-coding'`, `model_name_or_path='anthropic/claude-opus-4-8'`, the trace id, and a resolved harness result.

**SWE-bench comparison campaigns and MLflow.** For agent/model/config
comparisons, keep Dapr/workflow-builder as the execution owner and use MLflow
as the tracking/evaluation projection. The recommended shape is one benchmark
run per agent/configuration over the exact same suite and instance ids, grouped
by a stable campaign tag. The launch sheet's `Compare agents` mode applies the
tag and opens the compare route. MLflow should contain one parent
`workflow_builder.kind=swebench_run` run per benchmark run, one
`workflow_builder.kind=swebench_instance` child run per instance with
`mlflow.parentRunId`, and one `workflow_builder.kind=swebench_mlflow_eval`
child run when post-hoc evaluation runs. Campaign tags are queryable as
`tags.\`workflow_builder.benchmark_tag.<tag>\` = 'true'`; do not rely on run
names for grouping. Official SWE-bench resolved/unresolved remains the harness
callback result, not an MLflow scorer override.

**Random run readiness and preflight must agree.** Random SWE-bench launches require prevalidated inference environments before the run is inserted. The BFF has two valid readiness sources: exact static ConfigMap pins from `SWEBENCH_INFERENCE_ENVIRONMENTS_DIR` and dynamic build rows whose `environment_image_builds.env_spec_hash` matches the current `buildSwebenchEnvironmentSpec()` output. Static pins are exact when suite/repo/baseCommit/version and image digest match; they may omit `environmentSetupCommit`, and preflight still accepts them. Dynamic DB rows must match the current `envSpecHash`, not only repo/version/baseCommit, because harness spec generation can change while those coarse identifiers stay the same. Symptom of a readiness/preflight mismatch: the API accepts a random run, it remains `queued`, and `swebench-preflight-<run>` starts or waits on a hub `swe-env-*` build. Fix the shared readiness predicate instead of treating this as a model-specific DeepSeek/Kimi issue.

**SWE-bench environment builds run on hub Tekton, not dev.** When preflight has to build an inference image, it submits `swe-env-<envSpecHash-prefix>` to hub Tekton via `SWEBENCH_INFERENCE_BUILD_SUBMISSION_MODE=hub` / `SWEBENCH_INFERENCE_BUILD_HUB_KUBECONFIG`. If a run is stuck in `queued` while a `swe-env-*` PipelineRun is active, the workflow is waiting on a hub build to validate and pin an image; it is not building on the dev cluster. After a successful hub build, confirm the dev workflow-builder pod sees the refreshed ConfigMap file under `/etc/workflow-builder/swebench-inference-environments` and the BFF Deployment has rolled if the code path changed.

Deterministic operator smoke is allowed when agent inference is not the thing under test: insert a queued `benchmark_runs` row and explicit-id `benchmark_run_instances` rows with `model_patch`, `patch_sha256`, and `patch_bytes`; mark the run `inferencing`; call `_write_predictions`, `_write_evaluation_dataset`, then `_ensure_evaluator_job`. The status guard is strict (`queued -> inferencing -> evaluating -> completed/failed/cancelled`), so launching from `queued` fails.

Empty or null `model_patch` is a valid evaluator input and should become `empty_patch` when the harness reports it. That is an expected unresolved instance, not a harness failure. Official SWE-bench resolved/unresolved remains authoritative even if raw pytest output has extra non-graded errors; show those separately as raw harness notes.

**K8s label sanitization on coordinator-launched Jobs.** Run IDs are nanoid-generated and can legally end in `_` or `-`, which fails K8s label-value validation `(([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])?`. Symptom: run goes `failed` at the evaluating stage with HTTP 422 `Invalid value: "<id>": a valid label must ... start and end with an alphanumeric character`. The Phase G `patch_files_overlap_gold` scorer (gated on harness completion) won't fire as a side effect. Fix landed in coordinator at workflow-builder `0f369b58` via `_safe_label_value` (strips outer `[._-]`, caps 63 chars). If you add another K8s resource that labels with a run/instance ID, mirror the helper.

**Cancellation and stalled-instance cleanup are Dapr lifecycle work, not just DB updates.** A terminal benchmark run may still have a parent `workflow-orchestrator` workflow plus `dapr-agent-py` session and per-turn child workflows running. The benchmark cancel cascade is generalized into — and shared with — the vetted **Lifecycle Controller** (BFF `src/lib/server/lifecycle/`, `stopDurableRun(target, {mode: interrupt|terminate|purge|reset})`): `POST /api/benchmarks/runs/[id]/cancel` (and `…/evaluations/runs/[id]/cancel`) cascade through `stopDurableRun(purge)` — terminating/polling/purging the agent-runtime session/turn workflows first (explicit per-session app-id fan-out — the native Dapr recursive cascade doesn't cross task hubs; the old `terminate_durable_runs_by_parent_execution` was retired), then the parent. **Single stop authority:** a benchmark/eval INSTANCE is not stoppable on its own — the generic per-execution/per-session Stop 409s `coordinator_owned`; cancel the owning RUN. **Request/confirm:** a stop that cannot confirm in-request returns **202 "stopping"** and persists `stop_requested_at`; explicit status reads/control actions call `confirmDurableStop`, and DB/Sandbox cleanup happens only after durable closure is confirmed. The retired terminal-reaper CronJob is not a backstop. The remaining **workflow-builder-sandbox-gc CronJob** only age-cleans orphaned per-session Sandbox CRs and excludes SandboxWarmPool-owned CRs; it does not reconcile Dapr or product rows.

**Debug checklist for `queued` random runs.** First check `benchmark_runs.status`, `benchmark_run_instances.status`, active `benchmark_resource_leases`, and coordinator logs for the run id. If no instance workflows have `session_id` / `workflow_execution_id`, inspect the preflight child workflow and hub Tekton for `swe-env-*` PipelineRuns. If preflight reports static groups with `buildId=null`, `validationStatus=validated`, and `pipelineRunName=null`, the run should leave `queued` quickly. A healthy launch transitions `queued -> inferencing`, fills `inference_environment.source = "static_mapping"` or `"environment_image_builds"`, and creates per-instance workflow executions. Clean operator canaries through the normal benchmark cancel path and verify `active_runs`, `active_leases`, `active_sessions`, and active `workflow_executions` return to zero.

**2026-05 SWE-bench start-path invariant.** BFF instance start calls
`workflow-orchestrator` `GET /readyz` before creating the instance execution row
or dispatching `/api/v2/sw-workflows`. If readiness fails because Dapr has zero
connected workflow workers, the BFF returns `workflow_runtime_unavailable`; the
coordinator releases the lease, requeues the instance, and sleeps
`SWEBENCH_ORCHESTRATOR_NOT_READY_RETRY_SECONDS` (default
`SWEBENCH_LEASE_RETRY_SECONDS`). MLflow is restored but background
best-effort (`MLFLOW_FAILURE_MODE=best_effort`): `[mlflow]` timeouts can leave
tracking IDs null, but they are not a start blocker. When token counts stay at
zero, distinguish the stages in order: run row created, preflight complete,
instance has Dapr workflow ID, OpenShell pod admitted, session ID created,
`agent.llm_usage` recorded, evaluator job launched.

## System State Update (2026-05-19)

This dated snapshot records changes that were verified on Ryzen and dev in May
2026. Use it as implementation history, not as permission to operate Ryzen;
current shared verification defaults to dev.

- **Eval is Kueue OOM-admission-controlled.** The `swebench-eval-{prepare,run-instance,finalize}` Tekton TaskRun pods are now Kueue-admitted on the `benchmark-fast` ClusterQueue. Wiring chain: `swebench-coordinator` Deployment env `SWEBENCH_TEKTON_KUEUE_QUEUE_NAME=benchmark-fast`/`SWEBENCH_TEKTON_KUEUE_PRIORITY_CLASS=swebench-cohort` → forwarded onto the evaluator Job → `services/swebench-evaluator/entrypoint.py` `_common_metadata()` stamps the labels on **`TaskRun.metadata.labels`** (NOT `podTemplate.metadata` — Tekton prunes that; the `f50cb71a`→`b268ed45` bug). `run-instance` step `requests.memory` is 2Gi. kueue-controller hardened (Guaranteed QoS + PDB). Verified: every eval TaskRun/pod carries `kueue.x-k8s.io/queue-name=benchmark-fast`, Workloads `admitted=True`, 0 OOMKilling.
- **Env-spec-exact image gate (`0e895f7e`, full cutover).** `resolveSwebenchInferenceEnvironment` / `isExactValidatedSwebenchInferenceEnvironment` now **require** `expectedEnvSpecHash`; a static ConfigMap pin is only valid when its `envSpecHash` equals the current `buildSwebenchEnvironmentSpec()` hash (static & dynamic readiness symmetric). This stops silent stale-image grading.
- **Crash-callback (`5ee0473f`).** `entrypoint.py` always posts a terminal callback. An empty/non-applying patch yields a structured `harness_result` (`empty_patch` / `patch_failed`, `resolved:false`) and the run reaches `completed` — **never** the generic "Job has reached the specified backoff limit". `evaluation_error` stays NULL for these (the model-quality outcome lives in `harness_result`, not an evaluator error).
- **SWE-bench Solver agents** on ryzen + dev are pool agents (`runtime_app_id=agent-runtime-pool-coding`, served by the static shared `dapr-agent-py` pool Deployment) and need **NO AgentRuntime CR** — the custom AgentRuntime CRD + Kopf `agent-runtime-controller` are RETIRED; runtime identity/capabilities come from the runtime registry SSOT (`services/shared/runtime-registry.json`), and non-pool runs are dispatched as per-session agent-sandbox Sandbox pods that differ only by image. `kubectl get agentruntime` returning empty is EXPECTED, not a fault. When rolling SWE-bench runtimes, note `claude-agent-py` now supports MCP (`agentConfig.mcpServers` wired into the Claude Agent SDK) and that the swap-safety gate (`src/lib/server/agents/swap-safety.ts`) compares an agent's required capabilities against the target runtime's declared capabilities — MCP-loss + provider-mismatch are reject-class (warn-first unless `AGENT_RUNTIME_REJECT_LOSSY_SWAP=true`). Current default Claude/GPT modelSpec strings should be `anthropic/claude-opus-4-8` and `openai/gpt-5.5`; older `anthropic/claude-opus-4-7` / `openai/gpt-5.4` rows are legacy comparison rows unless intentionally pinned. To add another: idempotent `SELECT *` temp-table clone of a known-good solver's `agents`+`agent_versions` rows, swap id/slug/name/tags/`config.modelSpec`/runtime fields, `registry_status='registered'`, insert agents (current_version_id NULL) → agent_versions → set current_version_id (circular FK); `config_hash=encode(sha256(convert_to(config::text,'UTF8')),'hex')`. Validate via `node scripts/start-swebench-benchmark-run.bundle.js … --agent-id <id>` (no `--apply`) or `pnpm tsx scripts/start-swebench-benchmark-run.ts ... --apply` for an actual smoke.
- **Ryzen capacity rule — single run at a time, but let live Kueue capacity cap effective concurrency.** Ryzen now runs the same Kueue-backed SWE-bench path as dev with `BENCHMARK_KUEUE_INSTANCE_REQUEST_MODE=host-worker-composite`, so inference launch is admission-aware for the full sandbox + agent-host bundle. Do not run parallel benchmark campaigns on ryzen; the workstation still has finite RAM and parallel runs can cascade postgres/orchestrator. Within one run, a request for 3 may correctly become effective concurrency 2 when live node request headroom only fits two full bundles. Verified 2026-05-27: run `MPIlRkKWC7UdvHgwFQEiR` selected 3 exact-ready instances, requested/effective 3/2 due `kueue_capacity`, all three reached 10 LLM/tool calls, evaluator completed, and active leases returned to zero. For `Compare agents`, keep sequential per-agent runs with a fresh health check between runs.
- **Dev inference path is wired; model quality is good enough for infra scale-up.** A 64-way DeepSeek V4 Pro, SWE-bench_Verified, distinct exact-ready cohort at `maxTurns=25` produced 33/64 resolved. Treat that as model-quality validation for capacity work. It was not a clean capacity checkpoint because workflow-builder/orchestrator rollout, stale startup cleanup, and Dapr replay-schedule issues interfered. Next dev capacity runs must start from a clean baseline and should not roll workflow-builder, workflow-orchestrator, swebench-coordinator, or agent runtime images mid-run.
- **Current Dapr state-store layout.** `workflowstatestore` is the namespace-wide Dapr workflow/actor store for parent workflows and per-session agent workflows. `dapr-agent-py-statestore` is namespace-wide but `actorStateStore=false`; it is the agent application state API store. Do not recreate the old per-agent actor-store architecture or add scopes for per-session agent-host app IDs.
- **Dapr Agents 1.0.3 activity naming standard.** Repo-owned `services/dapr-agent-py` custom workflow activities must be registered and called only by their scoped names through `self._activity_name(...)`. Do not restore the old dual bare-name/scoped-name compatibility path. If stale histories require the old names, cancel/cleanup/purge the benchmark state instead of keeping two naming standards alive.
- **Recovery is API/Lifecycle Controller work, not DB state editing.** Cancel the owning benchmark/eval run through its authenticated cancel endpoint. That command owns the status transition and `stopDurableRun(purge)` cascade across parent, per-session child workflows, and Sandbox cleanup. Follow its status/cleanup surface to confirmation; no terminal reaper remains. Never mark runs/instances cancelled with SQL before cleanup. A stable warm-pool floor is expected capacity, not incident residue.
- **Image delivery for these changes** is via the gitops skill's GHCR-pin path: ryzen `swebench-coordinator`/`swebench-evaluator`/`workflow-builder` images are pinned `ghcr.io/pittampalliorg/<img>:git-<sha>` in `workloads/<comp>/manifests/kustomization.yaml` on GitHub `main`; ryzen's LOCAL ArgoCD reconciles `packages/overlays/ryzen@main` directly with no source-hydrator or Promoter on the ryzen lane. Dev gets coordinator/evaluator through the normal GitHub/GHCR outer-loop plus GitOps Promoter. If an ArgoCD app won't advance to a new commit, `argocd app terminate-op <app> --grpc-web` (see gitops skill).

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
| `score_model` (Model labeler / Model scorer) | `model-labeler-form.svelte`, `model-scorer-form.svelte` | async `runScoreModelGrader` | Live + strict-tool path | `wakeAgentRuntime(slug)` prefers the named SandboxWarmPool and retains an AgentRuntime compatibility fallback, then Dapr invokes `agent-runtime-${slug}/api/grader-evaluate` with optional `responseSchema` + `responseToolName`. Do not treat the fallback CR as the desired new runtime architecture. |
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

## Reusable workflow lookup (`taskConfig.workflowId`)

`taskConfig.workflowId` remains the compatibility handle for an eval definition
that references a saved workflow. The evaluation application service resolves
that definition inside the project, or accepts an intentionally public reusable
definition. Ownership and visibility checks belong to that application port.

The code-first cutover ports one-shot agent, code-eval, SWE-bench, and GAN
producers to dynamic scripts behind producer flags. New producer work should
emit the dynamic-script dialect and start it through the engine-aware execution
port. SW builders remain callable only for shadow parity/migration while the
cutover flags soak.

Update a reusable user workflow with Workflow MCP `save_workflow_script` or an
authenticated BFF application command, then launch a fresh eval item. Do not
run `upsert-<workflow>.mjs` against a spoke database, guess an owner, or repair a
serialized spec with SQL. Internal migration/fixture code must call an
application port rather than becoming operator guidance.

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

The `code-eval` sandbox template image (`ghcr.io/pittampalliorg/openshell-sandbox-code-eval`) bakes pytest + EvalPlus + the BigCodeBench top-of-funnel library pool (numpy, pandas, scipy, scikit-learn, sympy, networkx, pillow, requests, beautifulsoup4, ...). Built from `services/openshell-sandbox/environments/Dockerfile.code-eval` via Tekton's `environment-image-build` pipeline (commit subject prefix `environment(code-eval):` is the trigger filter). The image is registered in `SANDBOX_TEMPLATE_IMAGES_JSON` on the workflow-builder Deployment.

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

`POST /api/evaluations/runs` snapshots dataset rows. Imported outputs grade
immediately; agent/workflow subjects start the coordinator, fan out per-item
children, and use the producer-selected dynamic-script engine (or an explicit
legacy shadow path). Sync polls terminal state, async graders run, and the
summary is recomputed.

For full detail: `references/system-model.md`.

## Operational Rollout

dapr-agent-py code changes (the `/api/grader-evaluate` endpoint, provider adapters such as `deepseek_adapter.py`, `_call_anthropic_sdk`, MCP, hooks, etc.) now fire THREE image PipelineRuns:

1. `dapr-agent-py-image-build` — for legacy `dapr-agent-py:git-<sha>` (used by the static `dapr-agent-py` pool Deployment that backs the `openshell-durable-agent` enum + the `agent-runtime-pool-coding` benchmark pool, plus `dapr-agent-py-testing`).
2. `dapr-agent-py-sandbox-image-build` — for `dapr-agent-py-sandbox:git-<sha>` (the image used by per-session agent-sandbox Sandbox pods; the runtime is selected per-session via `AGENT_RUNTIME_DEFAULT_IMAGE`, not via any AgentRuntime CR — the CRD + Kopf controller are retired).
3. `dapr-agent-py-testing-sandbox-image-build` — for the testing sandbox image used by runtime/conformance paths.

`claude-agent-py` changes are a peer runtime rollout: build/publish `claude-agent-py-sandbox:git-<sha>`, update the workflow-builder Deployment env `AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE`, and verify the BFF pod sees it before launching/republishing Claude runtime agents. The runtime default model is `claude-opus-4-8`; the UI/modelSpec key is `anthropic/claude-opus-4-8`.

Forced-tool grader-evaluate gotchas seen during the strict-tool rollout:

- **Anthropic API rejects `thinking` + `tool_choice={type:"tool"}`** (HTTP 400 "Thinking may not be enabled when tool_choice forces tool use"). `_call_anthropic_sdk` must suppress the adaptive-thinking kwarg whenever tool_choice forces a single tool. Detection: `isinstance(kwargs.get("tool_choice"), dict) and kwargs["tool_choice"].get("type") == "tool"`.
- **`_convert_tools_for_anthropic` originally only handled AgentTool-like objects** (attribute access `tool.name`). The grader endpoint passes already-formatted dicts. Converter now branches on `isinstance(tool, dict)` and reads from dict keys. Without this branch, tool calls fail with `'dict' object has no attribute 'name'`.
- **`tool_choice={type:"tool", name: ...}` requires `tools[0].strict = true`** for grammar-constrained decoding. Drop the `strict: true` and the model can still emit free-form JSON-ish text inside the tool call.
- **`system` and `tool_choice` were silently dropped from `_call_anthropic_sdk` request_kwargs** before the strict-tool work landed. Both are now forwarded into the streaming request. Pre-existing graders that supplied a `systemPrompt` to the prose path were running without it.
- **Skaffold-owned dev pods cache stale env vars** (`AGENT_RUNTIME_DEFAULT_IMAGE`, `SANDBOX_TEMPLATE_IMAGES_JSON`). When ArgoCD updates `Deployment-workflow-builder.yaml`, the standard ReplicaSet rolls but the long-lived `workflow-builder-dev-*` pod doesn't restart. Exit `skaffold dev` (which removes the override) OR `kubectl delete pod workflow-builder-dev-*` to force a refresh. Verify with `kubectl exec deploy/workflow-builder -- printenv AGENT_RUNTIME_DEFAULT_IMAGE`.

**Ryzen path**:

```bash
# Push source to GitHub when a new image is needed; hub Tekton builds GHCR tags.
git push origin main

# Watch hub builds and capture the GHCR tag/digest.
kubectl --kubeconfig ~/.kube/hub-config -n tekton-pipelines \
  get pipelinerun --sort-by='.metadata.creationTimestamp' | tail -10

# In stacks, repoint the relevant workloads image to the GHCR tag,
# then commit/merge to main; ryzen's local ArgoCD reads main directly.
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
# Inspect ryzen-side: kubectl --context admin@ryzen get app -n argocd | grep ^ryzen-
# Force a local refresh: kubectl --context admin@ryzen annotate app -n argocd root-ryzen argocd.argoproj.io/refresh=hard --overwrite

# Per-session runtimes are agent-sandbox Sandbox pods selected by image, NOT
# AgentRuntime CRs (the CRD + Kopf agent-runtime-controller are retired). To roll
# the runtime image, bump AGENT_RUNTIME_DEFAULT_IMAGE / AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE
# on Deployment-workflow-builder.yaml — the BFF reads it per launch, so the NEXT
# session pulls the new image. No per-agent CR patch, no sleep/wake annotations.
# For the static dapr-agent-py pool (agent-runtime-pool-coding / openshell-durable-agent),
# bump its workloads image pin and let the pool Deployment roll:
kubectl rollout restart deploy/dapr-agent-py -n workflow-builder
```

The deterministic ryzen path is GHCR image availability plus a commit-pin on GitHub `main`; ryzen's LOCAL ArgoCD handles the rest directly.

**Dev path** (outer-loop):

```bash
# Push to GitHub — hub Tekton fires via webhook
git push origin main

# Watch hub builds
kubectl --kubeconfig ~/.kube/hub-config -n tekton-pipelines \
  get pipelinerun --sort-by='.metadata.creationTimestamp' | tail -10

# After build, hub Tekton's update-stacks task writes release metadata to
# stacks repo's release-pins/workflow-builder-images.yaml. GitOps Promoter
# then promotes the active dev environment after its health/timer gates.
```

The `AGENT_RUNTIME_*_DEFAULT_IMAGE` env vars on the workflow-builder Deployment are the per-session source-of-truth for the runtime image (read at launch time — no per-agent AgentRuntime CR or controller exists anymore). To roll a runtime on dev, bump the env var in the stacks Deployment YAML, wait for spoke sync, and verify the live BFF pod sees it; the next session spawns a Sandbox pod on the new image. For the static `dapr-agent-py` pool (`agent-runtime-pool-coding`), bump its image pin and let the pool Deployment roll. See the gitops skill's `bump-image-pin-not-in-release-pins` runbook.

## Operational Commands

```bash
# Coordinator + orchestrator logs
kubectl logs -n workflow-builder deploy/evaluation-coordinator --tail=200
kubectl logs -n workflow-builder deploy/workflow-orchestrator -c workflow-orchestrator --tail=200
kubectl logs -n workflow-builder deploy/workflow-orchestrator -c daprd --tail=200

# Runtime pods (per-session agent-sandbox Sandbox pods + the static dapr-agent-py pool).
# There is NO AgentRuntime CR — `kubectl get agentruntime` is empty by design.
kubectl get pods -n workflow-builder -l app.kubernetes.io/part-of=agent-sandbox
kubectl get deploy dapr-agent-py -n workflow-builder \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# Probe the sync grader endpoint directly on the shared pool pod
POD=$(kubectl get pods -n workflow-builder -o name | grep '/dapr-agent-py-' | head -1)
kubectl exec -n workflow-builder $POD -c dapr-agent-py -- \
  curl -sS -X POST -H "Content-Type: application/json" \
  -d '{"systemPrompt":"...","userPrompt":"..."}' \
  http://localhost:8002/api/grader-evaluate

# Recent runs through the authenticated application API
curl -fsS --cookie "$WORKFLOW_BUILDER_COOKIE" \
  'https://workflow-builder-dev.tail286401.ts.net/api/evaluations/runs?limit=10' | jq .
```

## Guardrails

- Do NOT conflate the legacy SWE-bench eval template with `/api/benchmarks/*`. The OpenAI-parity wizard supersedes the old eval adapter, but `/api/benchmarks/*` plus `/workspaces/<slug>/benchmarks` is the current operator-visible official SWE-bench harness surface.
- Do NOT start a local SvelteKit dev server for a dev-cluster validation. Use the hub Tekton -> Source Hydrator -> Promoter lane. Ryzen Skaffold is a separate opt-in workflow.
- Do NOT bake user workflow definitions into images. Save dynamic scripts through Workflow MCP/BFF; deployment and workspace-data changes are separate operations.
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
services/swebench-coordinator/src/app.py             # writes artifacts, validates predictions, launches evaluator Jobs; _safe_label_value() (0f369b58) sanitizes run IDs for K8s labels
services/swebench-evaluator/                         # official harness wrapper + callback payloads
scripts/fixtures/dynamic-scripts/code-eval-item.js  # current code-eval script producer fixture
services/openshell-sandbox/environments/Dockerfile.code-eval  # sandbox image (pytest + EvalPlus + BigCodeBench libs)
services/evaluation-coordinator/src/app.py           # Dapr workflows
services/dapr-agent-py/src/main.py                   # /api/grader-evaluate (search this string) — accepts responseSchema + responseToolName
services/dapr-agent-py/src/anthropic_adapter.py      # _call_anthropic_sdk forwards system + tool_choice; suppresses thinking on forced-tool path
services/dapr-agent-py/pyproject.toml                # anthropic>=0.51 (required for strict tool-use)
services/claude-agent-py/src/claude_sdk_runner.py    # Claude Agent SDK runtime; default model and output sync behavior
services/workflow-orchestrator/workflows/dynamic_script_workflow.py
```

For the Dapr-native architecture roadmap (mapping our six subsystems to Diagrid's Prompt Chaining / Parallelization / Evaluator-Optimizer / Stateful LLM patterns), see the plan at `/home/vpittamp/.claude/plans/create-a-plan-to-fuzzy-crescent.md`.
