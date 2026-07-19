# Workflow Artifacts

Declare typed, named outputs on any SW 1.0 task and have them render coherently in the run-detail UI. Replaces "stuff your output into `workflow_executions.output` JSONB and hope the operator finds it" with a single generic surface that works across markdown, JSON, text, tables, images, links, cards.

This reference covers: when to declare artifacts, the spec shape, the post-task expression context (the part that costs the most time when expressions resolve to null), and where things live in the UI.

## When to declare artifacts

Add an `artifacts:` block to a task whenever the task produces something a human or downstream tool will read. Concretely:

- **Agent synthesis output** (`durable/run` returning a markdown response) → `kind: markdown`, `slot: primary`.
- **Structured per-iteration data from a `for` loop** (`web/crawl.async` extractions) → `kind: json` (one row per iteration via `node_id = "<for_name>/<sub>[<idx>]"`).
- **Fetched markdown / HTML excerpt** → `kind: markdown`, `slot: aux`.
- **Tabular results** (CSV-shaped data, score matrices) → `kind: table` with `{columns, rows}`.
- **A URL the operator should click** → `kind: link`.

Skip artifacts when:
- The task's role is purely to feed downstream tasks (intermediate jq expression hosts) — those don't need a UI surface.
- The output is already covered by a dedicated surface — `browser/validate` writes `workflow_browser_artifacts` (separate Browser tab), `claude/plan`-equivalent paths write `workflow_plan_artifacts` (separate Plan tab). Keep those.

## Spec shape

Attach `artifacts: [...]` alongside `with:` on any task. Each entry is independent — they don't compose, they don't share state.

```yaml
synthesize:
  call: durable/run
  with:
    workspaceRef: local
    agentRef: { id: "...", slug: "text-research-synthesizer" }
    prompt: "${ ... }"
  artifacts:
    - kind: markdown                                  # required, discriminator for the UI renderer
      slot: primary                                   # optional: primary | secondary | aux
      title: "Research synthesis"                     # required (jq or literal)
      description: "${ .trigger.topic }"              # optional (jq or literal)
      from: "${ .data.content }"                      # jq → wrapped per-kind for inlinePayload
      contentType: "text/markdown"                    # optional
      metadata: "${ { topic: .trigger.topic, urlCount: (.trigger.urls | length) } }"
      if: "${ .data.content != null }"                # optional guard
```

**One entry → one DB row.** Activity ID is `wfa_<sha256(workflowId|executionId|nodeId|kind|title)[:24]>`, so re-runs / Dapr activity retries UPSERT cleanly on the same row.

**Auto-wrapping by kind** — what `from:` evaluates to gets wrapped into `inline_payload` based on `kind`:

| `kind` | `from: ${ X }` → `inline_payload` | UI renderer |
|---|---|---|
| `markdown` | `{ markdown: <X> }` | `Response` (Streamdown + Shiki) |
| `text` | `{ text: <X> }` | `<pre>` |
| `json` | `{ value: <X> }` | `JsonViewer` |
| `link` | `{ url: <X> }` | anchor |
| `table` | `<X>` (must be `{columns, rows}`) | inline table |
| `image` | `{ alt: <X> }` (blob via separate `fileId:` field) | `<img>` |
| `card` | `<X>` (must be `{body, footer?}`) | shadcn `<Card>` |
| anything else | `<X>` (passthrough) | falls back to JSON dump |

## The post-task expression context (this is where you'll lose time)

`artifacts: from:` / `title:` / `description:` / `metadata:` / `if:` jq runs after the task's result is stored. The orchestrator builds a *per-task* expression context that exposes the just-completed task's payload uniformly so the same `${ .data.X }` idiom works regardless of how nested the producer's envelope is:

- **Crawl-style task** (payload naturally has `.data` — e.g. `{complete, success, data: {tier, url, markdown, extracted, ...}, error}`): root is the payload. `${ .data.markdown }` resolves to the adapter's markdown; `${ .complete }`, `${ .success }`, `${ .error }` also work.
- **Agent-style task** (payload is flat — e.g. `{success, content, turn, agentWorkflowId, ...}`): root is wrapped as `{data: <payload>}` so `${ .data.content }` still works. Same idiom on both shapes — that's the design.
- **`for`-loop sub-task**: same rules apply; `node_id` carries the iteration suffix (e.g. `fetch_each/crawl[0]`, `fetch_each/crawl[1]`).

Also exposed in this context:
- `${ .trigger.X }` — workflow trigger fields.
- `${ .state.X }` — for-loop iteration vars and `set:` task assignments. Iteration vars (e.g. `${ .url }`) are also promoted to top level.
- `${ .<task_name>.<X> }` — every previously-completed task's output (canonical pattern for cross-task refs).
- `${ .task.X }` / `${ .output.X }` — explicit aliases for the just-completed task's unwrapped payload (useful when a state var would shadow `.data`).

**Don't conflate `${ .data.X }` with `${ .<task_name>.data.X }`.** Inside an `artifacts:` block, `.data` is THIS task's payload (one layer of unwrap). For cross-task refs (e.g. synthesis reading prior fetch outputs), use the full task name: `${ .fetch_each.data.tier }` works because the build-context loop stores each completed task's unwrapped payload at `context[task_name]` with the same one-layer-strip semantic.

## Where the rows land + how to read them back

**Storage** — single table `workflow_artifacts` (drizzle 0067). Columns: `id`, `workflow_execution_id` (FK CASCADE), `node_id`, `slot`, `kind`, `title`, `description`, `inline_payload jsonb` (≤256 KB practical), `file_id` (FK files SET NULL — for blob-backed), `content_type`, `size_bytes`, `metadata jsonb`, `created_at`.

**APIs**:
- `GET /api/workflows/executions/[id]/artifacts` — workspace-scoped read (user auth, slot-ordered then `created_at` asc).
- `POST /api/internal/workflows/executions/[id]/artifacts` — internal-token write, UPSERT by deterministic id. Used by the orchestrator's `persist_workflow_artifact` activity.

**UI surfaces**:
- **Overview tab** — `<ArtifactList mode="primary" />` features primary-slot artifacts above the raw `output` JSON. When artifacts exist, the raw Output card collapses by default (chevron-only header) so the artifact gets the visual real estate. Without artifacts, the JsonViewer stays expanded — backward compat preserved.
- **Outputs tab** (new, between Overview and Steps) — `<ArtifactList mode="all" />` shows all artifacts grouped by slot. Primary expanded, Secondary expanded, Aux + Other collapsed by default. Tab badge shows the count.

## Dapr durability + idempotency

The persist activity is `ctx.call_activity(persist_workflow_artifact, ...)` — full Dapr durability:
- Orchestrator pod restart mid-run resumes per-activity from history. Already-persisted artifacts are no-ops (UPSERT).
- BFF unreachable / 5xx → activity logs a warning but doesn't propagate. **Best-effort by design**: observability never breaks the workflow it describes.
- Re-runs of the same execution / for-loop iteration UPSERT on the same row (deterministic id).

## Verify in the UI

After triggering a run:

```sql
SELECT id, slot, kind, title, length(inline_payload::text) AS bytes
FROM workflow_artifacts
WHERE workflow_execution_id = '<execId>'
ORDER BY slot NULLS LAST, created_at;
```

In the browser, open `/workspaces/<slug>/workflows/<id>/runs/<execId>`:
- Overview tab → primary-slot artifact card visible above the Input card; Output card collapsed.
- Outputs tab → click the tab; expect badge count to equal the SQL row count.

If the row exists but the `inline_payload` is `{markdown:""}` or `{value:null}`: your `${ .data.X }` jq probably resolved null. Double-check the producer's payload shape — for crawl tasks `.data.X`; for agent runs, what `_run_native_durable_agent_child_workflow` returns dictates the flat-vs-nested shape (it's flat unless the agent explicitly wraps).

If no row appears at all: check `kubectl logs deploy/workflow-orchestrator -n workflow-builder | grep persist_workflow_artifact` — best-effort warnings log here. Common causes: `INTERNAL_API_TOKEN` mismatch, BFF `/api/internal/workflows/executions/[id]/artifacts` returning 503 (DB pool exhausted), or `if:` guard evaluating to false.

## Backward compatibility

- `workflow_browser_artifacts` and `workflow_plan_artifacts` stay unchanged. Their dedicated tabs (Browser, Plan) keep working. We do NOT migrate those into `workflow_artifacts`.
- Workflows authored before this surface existed have no `artifacts:` blocks → no rows → Overview falls back to the original `<JsonViewer data={output} />`, Outputs tab shows "No artifacts persisted for this execution."

## Authoritative source files

When the skill seems wrong or the behavior surprises you, read these:

- **Producer**: `services/workflow-orchestrator/workflows/sw_workflow.py` (`_persist_task_artifacts`), `services/workflow-orchestrator/activities/persist_artifact.py` (the durable activity + deterministic id helper).
- **APIs**: `src/routes/api/workflows/executions/[executionId]/artifacts/+server.ts` (read), `src/routes/api/internal/workflows/executions/[executionId]/artifacts/+server.ts` (write).
- **UI**: `src/lib/components/workflow/execution/artifact-renderer.svelte` (discriminated-union switch), `src/lib/components/workflow/execution/artifact-list.svelte` (slot grouping + collapsible sections), `src/routes/workspaces/[slug]/workflows/[workflowId]/runs/[executionId]/+page.svelte` (Overview integration + Outputs TabsContent).
- **Schema**: `src/lib/server/db/schema.ts` (`workflowArtifacts`), `drizzle/0067_workflow_artifacts.sql`.
- **Read model**: `src/lib/server/application/workflow-execution-read-model.ts`, `src/lib/server/workflow-artifacts.ts`, `src/lib/types/execution-stream.ts` (`ExecutionReadModel.artifacts`).
- **Repo-side doc**: `docs/workflow-artifacts.md` is the canonical doc; CLAUDE.md has a one-section summary.

## Template

`assets/with-artifacts.workflow.json` — minimal 1-task `durable/run` with one primary markdown artifact attached. Copy + replace `agentRef`.
