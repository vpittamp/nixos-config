# SWE-bench MLflow Comparison Campaigns

Use this when a user wants to compare DeepSeek vs Kimi or any other set of
agents/models on the same SWE-bench instances and inspect the result in
workflow-builder plus MLflow.

## Contract

Execution remains owned by workflow-builder, Dapr Workflows,
`swebench-coordinator`, Kueue/OpenShell sandboxes, and the official evaluator
Job. MLflow is the tracking/evaluation projection.

The MLflow hierarchy is:

```text
MLflow experiment: workflow-builder/<env>/swebench
  parent run: workflow_builder.kind=swebench_run
    child run: workflow_builder.kind=swebench_instance
    child run: workflow_builder.kind=swebench_instance
    child run: workflow_builder.kind=swebench_mlflow_eval
```

For comparisons, create one `benchmark_runs` row per agent/configuration. Every
run in the campaign must use the same suite and exact selected instance ids.
Group the runs with a stable benchmark tag such as:

```text
deepseek-kimi-agent-comparison-2026-05-14
```

That tag is copied into all parent, instance, and eval MLflow runs as:

- `workflow_builder.benchmark_tags=<comma-separated-tags>`
- `workflow_builder.benchmark_tag.<normalized-tag>=true`

## UI Flow

Use `/workspaces/<slug>/benchmarks`:

1. Select a suite and exact instances.
2. Open the launch sheet.
3. Choose `Compare agents`.
4. Select 2-4 registered `dapr-agent-py` or `adk-agent-py` agents.
5. Set a comparison campaign label.
6. Launch.

The UI creates one benchmark run per selected agent and redirects to:

```text
/workspaces/<slug>/benchmarks/compare?runs=<runA>,<runB>[,<runC>,<runD>]&tag=<campaign-tag>
```

The compare route can also expand the most recent tagged runs, up to four:

```text
/workspaces/<slug>/benchmarks/compare?tag=<campaign-tag>
```

Use explicit `runs=` when the comparison set must be fixed.

## MLflow Query

Search campaigns with the boolean tag key:

```text
tags.`workflow_builder.benchmark_tag.<campaign-tag>` = 'true'
```

For two agents over `N` instances, expect `2 + (2 * N) + 2` MLflow runs:
two parent runs, `2 * N` instance child runs, and two eval child runs.

## Interpretation

Official SWE-bench resolved/unresolved/empty-patch status comes from the
evaluator harness callback stored in `benchmark_run_instances`. MLflow eval
metrics and trace-linked scorers enrich the result, but they do not replace the
official harness outcome.

Before treating a campaign as valid comparison evidence, confirm:

- all runs have identical `selected_instance_ids`;
- the compare page shows only the intended differing axis;
- MLflow contains the expected parent, instance, and eval child runs;
- instance and eval child runs have `mlflow.parentRunId`;
- eval runs have harness and patch-quality metrics;
- cleanup removed benchmark pods for the campaign run ids.

## Live Canary Pattern

For a small operator canary after comparison UI or MLflow changes:

1. Pick two validated instances from the same suite.
2. Launch `Compare agents` with two agents and `concurrency=1`.
3. Wait for terminal run statuses.
4. Verify compare UI, DB summary, and MLflow campaign query.
5. Check no benchmark pods remain for the run ids.

The 2026-05-14 dev canary used DeepSeek Pro
`agnt_deepseek_v4_pro_swe_smoke` and Kimi
`agnt_kimi_k26_swe_canary` over `astropy__astropy-12907` and
`astropy__astropy-13033`. Both runs completed and produced the expected MLflow
hierarchy. Neither resolved the two instances; this validated the comparison
architecture, not model quality.

`agnt_kimi_k26_swe_canary` is a retained fixture identifier that now maps to
`kimi/kimi-k3`; do not treat its name as an available K2.6 model option.
