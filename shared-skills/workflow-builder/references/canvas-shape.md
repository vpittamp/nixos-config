# Canvas Shape (`nodes` + `edges`)

Scope: the JSON shape of `workflows.nodes` and `workflows.edges` (the SvelteFlow canvas). Source of truth: `src/lib/utils/spec-graph-adapter.ts`.

## TL;DR — let the adapter do it

The adapter takes a SW 1.0 spec and emits `{nodes, edges}` using the official `@serverlessworkflow/sdk::buildGraph()`. **You almost never hand-author nodes/edges.** The standard authoring flow is:

1. Write the SW 1.0 spec.
2. Call `specToGraph(spec)` (in TS) — or trust the BFF's PUT endpoint to call it for you on save.
3. Persist all three: `spec`, `nodes`, `edges`.

If you do hand-author `nodes`/`edges` — for example, when bootstrapping a workflow before the BFF runs the adapter — they MUST stay consistent with the spec or the canvas will look broken on next render. The adapter is idempotent on round-trip.

## Adapter behavior

`specToGraph(spec, metadata?) → { nodes, edges } | null` (lines 48-66):

1. Calls `buildGraph(spec)` from `@serverlessworkflow/sdk`.
2. Maps SDK node types to canvas node types via `NODE_TYPE_MAP` (lines 16-36).
3. Renames synthetic SDK IDs `root-entry-node` / `root-exit-node` to `__start__` / `__end__` (lines 39-42).
4. For each task, looks up its raw def in `do[]` and stamps `data.taskConfig` to it.
5. Special-cases agent tasks: if `isAgentTaskConfig(taskDef)` (`call === "durable/run"`) is true, sets `node.type = "agent"` instead of the SDK-mapped type.
6. Falls back to `buildLinearGraphFromSpec()` when `buildGraph` fails or returns zero rendered tasks.

## Node shape

```json
{
  "id": "fetch_data",
  "type": "call",
  "position": { "x": 250, "y": 200 },
  "data": {
    "label": "Fetch Data",
    "type": "call",
    "taskConfig": {
      "call": "system/http-request",
      "with": { "url": "${ .trigger.url }", "method": "GET" },
      "output": { "as": { "data": "${ .data }" } }
    },
    "status": "idle",
    "enabled": true
  }
}
```

| Field | Required | Source |
| --- | --- | --- |
| `id` | Yes | Task name (the key in `do[]`); `__start__` / `__end__` for synthetic nodes. |
| `type` | Yes | One of: `start`, `end`, `call`, `agent`, `set`, `switch`, `wait`, `emit`, `listen`, `for`, `fork`, `try`, `do`, `run`, `raise`. |
| `position.x` / `.y` | Yes | The adapter uses x=250 center + y=50 + 150 per node. Hand-authored values are preserved. |
| `data.label` | Yes | The adapter uses the SDK label or task name; for `start`/`end` it forces `"Start"`/`"End"`. |
| `data.type` | Yes | Mirror of `node.type`. |
| `data.taskConfig` | Yes for non-trigger | The raw task definition from `do[]` (the value, not the wrapping `{taskName: {...}}`). |
| `data.status` | Yes | `"idle"` initially. Updated to `"running"` / `"success"` / `"failed"` during execution. |
| `data.enabled` | Yes | `true`. Disabled nodes are skipped at runtime. |
| `data.<catalogMetadata>` | No | Cached display metadata (icon, description) merged in by the adapter from `metadata?` arg. Survives rebuilds — don't strip it. |
| `data.agent` | No (agent only) | When set, mirrors `with.agentRef` for the canvas detail panel. Optional but the UI shows nicer info when present. |

## Edge shape

```json
{
  "id": "fetch_data->summarize",
  "source": "fetch_data",
  "target": "summarize"
}
```

| Field | Required | Source |
| --- | --- | --- |
| `id` | Yes | Convention: `${source}->${target}`. The adapter generates this. |
| `source` | Yes | Source node id. |
| `target` | Yes | Target node id. |
| `label` | No | SDK includes a label for switch/condition edges. |
| `type` | No | Some fixtures use `"smoothstep"`. The adapter omits it (UI default). |

## Synthetic start/end nodes

The adapter adds two synthetic nodes that don't appear in `do[]`:

```json
{
  "id": "__start__",
  "type": "start",
  "position": { "x": 250, "y": 50 },
  "data": {
    "label": "Start",
    "type": "start",
    "taskConfig": { "input": { "format": "json", "schema": { "format": "json", "document": { ... } } } },
    "status": "idle",
    "enabled": true
  }
}
```

The start node's `data.taskConfig.input.schema.document` is what powers the Execute dialog form — the adapter normalizes both placements (`spec.input.schema.document` and `spec.document['x-workflow-builder'].input.schema`) into this canonical shape (lines 79-94 of `spec-graph-adapter.ts`).

End node:

```json
{ "id": "__end__", "type": "end", "position": { "x": 250, "y": <last+150> }, "data": { "label": "End", "type": "end", "status": "idle", "enabled": true } }
```

## Layout

The adapter uses a simple top-down layout: x=250 center, y starts at 50 and increments by 150 per node, in topological order (entry → tasks in `do[]` order → exit). For more complex layouts (branches, loops) ELK is available via `src/lib/utils/layout/elk-layout.ts` — invoked from the canvas component on user request. Persisted positions in `nodes[*].position` win on subsequent loads.

## Agent node type

When `taskDef.call === "durable/run"`, the node's `type` becomes `"agent"` (regardless of what the SDK said). This is the only special-case in the type map. The agent node has the same `data` shape as a `call` node, plus optionally `data.agent = { id, slug, runtime }` for nicer rendering.

## Sample fixture

`scripts/fixtures/sample-workflows.json` in the workflow-builder repo has three complete workflows you can borrow from:

- `browser-use-web-navigator` — single agent step, parameterized URL + task.
- `powerpoint-agent-smoke` — workspace/profile → durable/run sandbox-bridging.
- `excel-agent-smoke` — same pattern with a different agent.

These are the freshest examples in-repo; they're what production looks like.

## See also

- `references/sw-1.0-spec.md` — the spec side.
- `references/agent-task.md` — `durable/run` body shape that goes into agent-node `data.taskConfig`.
- `references/authoring-recipe.md` — when to write nodes/edges by hand vs. let the adapter do it.
