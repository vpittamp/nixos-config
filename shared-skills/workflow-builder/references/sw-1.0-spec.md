# SW 1.0 Spec Reference

Scope: the canonical shape of a SW 1.0 document as the workflow-builder orchestrator parses it. Use this when you need to write a new spec or validate an existing one. Source of truth: `services/workflow-orchestrator/core/sw_types.py` (Pydantic models) and `services/workflow-orchestrator/core/sw_expressions.py` (jq evaluation).

## Top-level shape

```json
{
  "document": {
    "dsl": "1.0.0",
    "namespace": "workflow-builder",
    "name": "my-workflow",
    "version": "1.0.0",
    "title": "Optional human title",
    "summary": "Optional one-liner",
    "tags": { "owner": "team-x" }
  },
  "input": {
    "schema": {
      "format": "json",
      "document": { "type": "object", "properties": { ... }, "required": [ ... ] }
    }
  },
  "use": { "functions": { ... }, "retries": { ... }, "timeouts": { ... } },
  "do": [ { "<task_name>": { "call": "...", "with": { ... } } } ],
  "output": { "as": { "result": "${ .last_task.data }" } },
  "timeout": { "after": "PT30M" }
}
```

`document.dsl` MUST be `"1.0.0"`. `document.namespace`, `document.name`, `document.version` are required. The orchestrator only ever sees this top-level shape — anything else lives under `metadata` or `document['x-workflow-builder']`.

## The `do` array

`do` is a list of single-key objects. The key is the **task name** — and that's exactly the canvas node ID. Order matters; tasks execute in declared order unless flow directives redirect.

```json
"do": [
  { "fetch_data": { "call": "system/http-request", "with": { "url": "..." } } },
  { "summarize":  { "call": "durable/run", "with": { "agentRef": { ... }, "prompt": "..." } } }
]
```

Each task value is one of the **12 task types** below. Pick the type by which top-level field is set: `call`, `do`, `for`, `fork`, `switch`, `try`, `wait`, `set`, `emit`, `listen`, `run`, `raise`. Setting more than one is an error.

## The 12 task types

From `core/sw_types.py:139-152`. Each accepts the `TaskBase` shared fields below.

| Type | Trigger field | Use it for |
| --- | --- | --- |
| `call` | `call: <slug-or-protocol>` | The 95% case. Function or HTTP/gRPC/OpenAPI call. The `call` value is either a slug like `system/http-request` / `durable/run` or a protocol literal `http`/`grpc`/`openapi`/`asyncapi`. See `references/action-catalog.md` for the slug routing table. |
| `do` | `do: [...]` | Sequential sub-task list. Same shape as the top-level `do`. |
| `for` | `for: { each, in, at?, while? }` | Loop over a collection. `each` names the iteration variable; `in` is a jq expression yielding the array. |
| `fork` | `fork: { branches: [...], compete?: bool }` | Parallel branches. `compete: true` returns the first branch that completes. |
| `switch` | `switch: [{ case: { when, then }}, ...]` | Conditional routing. `when` is a jq expression; `then` is `"continue"` / `"exit"` / `"end"` / `<taskName>`. |
| `try` | `try: [...], catch: { errors?, do }` | Error handling with retry/catch. |
| `wait` | `wait: <Duration>` | Timer. ISO-8601 (`PT5M`, `PT30S`) or `{minutes: 5}`. |
| `set` | `set: { var1: <expr>, var2: <expr> }` | Update workflow state vars. Read back later as `${ .var1 }`. |
| `emit` | `emit: { event: { with: { type, source, data? } } }` | Publish a CloudEvent via Dapr pub/sub. |
| `listen` | `listen: { to: { one: { with: { type, source } } } }` | Wait for an external event (CloudEvent). |
| `run` | `run: { workflow / shell / script / container }` | Sub-workflow OR shell/script in a sandbox. For agent runs use `call: durable/run` instead. |
| `raise` | `raise: { error: { type, status, title?, detail? } }` | Raise a typed error. |

The orchestrator's mapping to Dapr primitives lives in `services/workflow-orchestrator/workflows/sw_workflow.py:1-21` (header docstring summarizes it).

## TaskBase shared fields

Every task accepts these in addition to its type-specific field:

| Field | Type | Purpose |
| --- | --- | --- |
| `if` | `string` (jq) | Skip the task when `if` evaluates falsy. |
| `input` | `InputDefinition` | Per-task input mapping. `from` (jq) selects/transforms parent input; `schema` validates it. |
| `output` | `OutputDefinition` | Per-task output mapping. `as` (jq object) shapes the output that downstream tasks read. **Use this aggressively** — without it, downstream tasks see the raw dispatcher response. |
| `export` | `ExportDefinition` | Promote task output into workflow state vars. |
| `timeout` | `{ after: Duration }` | Per-task timeout. |
| `then` | `"continue"` / `"exit"` / `"end"` / `<taskName>` | Override the next-task pointer (`continue` = next in list, `exit` = leave current scope, `end` = terminate workflow). |
| `metadata` | `dict` | Arbitrary annotations; ignored at runtime. |

### Output mapping example

```json
{
  "fetch_user": {
    "call": "system/http-request",
    "with": { "url": "https://api.example.com/users/${ .trigger.id }", "method": "GET" },
    "output": { "as": { "user": "${ .data }", "etag": "${ .headers.etag }" } }
  }
}
```

Downstream tasks then read `${ .fetch_user.user }` and `${ .fetch_user.etag }` instead of digging through the raw response.

## jq expressions — the full-string rule

From `core/sw_expressions.py::is_expression_string` (lines 43-95):

```python
def is_expression_string(value):
    return isinstance(value, str) and value.strip().startswith("${") and value.strip().endswith("}")
```

**Only fully-wrapped strings evaluate.** Embedded interpolation does NOT work.

| String | Result |
| --- | --- |
| `"${ .trigger.url }"` | jq expression, evaluates to `trigger.url` |
| `"prefix ${ .trigger.url } suffix"` | **literal text** — no evaluation |
| `"${ \"prefix \" + .trigger.url + \" suffix\" }"` | jq expression, evaluates to concatenated string |
| `"${ .trigger.task // \"default task\" }"` | jq alternative operator — fall back to default if null |

This bites on prompts, URLs, and any field where you'd naturally want template-string interpolation. Always wrap the entire value as one jq expression.

### Available context keys

Inside `${ ... }` you can read:

| Path | Contents |
| --- | --- |
| `.trigger.<field>` | Trigger inputs (declared in `spec.input.schema.document.properties`). Resolved from `tc.task_outputs["trigger"].data` per `sw_workflow.py:421-434`. |
| `.<task_name>.<field>` | Output of an earlier task (after `output.as` shaping). E.g. `${ .fetch_user.user.name }`. |
| `.<state_var>` | State var set by a `set` task or an `export`. |
| `.workflow.document.name` | Current workflow document fields. |
| `.runtime.executionId` | Current execution id, db execution id, workflow id. |
| `.input` | Current task's input (after `input` mapping resolves). |

`${ .trigger.<field> }` and `${ .<task_name>.<field> }` are the two you'll use 90% of the time.

## Trigger schema

Two equivalent placements; the spec→graph adapter normalizes both (`src/lib/utils/spec-graph-adapter.ts:79-94`).

**Canonical** (preferred):

```json
"input": {
  "schema": {
    "format": "json",
    "document": {
      "type": "object",
      "properties": {
        "url":  { "type": "string", "format": "uri", "title": "Starting URL", "default": "https://example.com" },
        "task": { "type": "string", "title": "What to do", "default": "Summarize the page in 2 sentences." }
      },
      "required": ["url", "task"]
    }
  }
}
```

**Alternate** (used by some templates):

```json
"document": {
  "...": "...",
  "x-workflow-builder": {
    "input": {
      "mode": "structured",
      "schema": { "type": "object", "properties": { ... }, "required": [ ... ] }
    }
  }
}
```

Pick one and stick with it. The canonical placement renders identically in the Execute dialog.

## Spec validation checklist

Before submitting a spec, run through this list. Most failures hit one of these.

1. ☐ `document.dsl == "1.0.0"`, `document.namespace`, `document.name`, `document.version` all present.
2. ☐ Every entry in `do[]` is a single-key object with one of the 12 task types set.
3. ☐ `call` slugs are not in the rejected list (`claude/run`, `openshell/run`, `openshell-langgraph/run`, `dapr-agent-py/run`, `dapr-swe/run`, `mastra/*`, `agent/*`).
4. ☐ Every string value containing `${` is **wrapped entirely** in one `${...}` expression.
5. ☐ Any `${ .trigger.<x> }` reference matches a declared `input.schema.document.properties.<x>`.
6. ☐ Any `${ .<task>.<x> }` reference points to a task that appears earlier in `do[]`.
7. ☐ Every `durable/run` step has `with.agentRef.id` (or `with.body.agentRef.id` for the nested form). Without it, the orchestrator falls back to the legacy `dapr-agent-py` pod, which is not what you want.
8. ☐ If the workflow uses a workspace sandbox you want to keep alive, the `workspace/*` step has `with.keepAfterRun: true`.
9. ☐ `workflows.project_id` will be stamped at insert time — the BFF does this from `locals.session.projectId`. If you're inserting via psql, set it explicitly to a real project id.

## See also

- `references/action-catalog.md` — slug routing + how to discover available actions.
- `references/canvas-shape.md` — how the spec becomes nodes/edges.
- `references/agent-task.md` — `durable/run` body shape in depth.
- `references/authoring-recipe.md` — end-to-end author → upsert → run.
