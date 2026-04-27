# Authoring Recipe

Scope: the end-to-end happy path for "I want a workflow that does X." Steps from blank slate → spec → DB row → rendered canvas → green run. Cross-references to the deeper references and templates.

## Step 1 — Pick a template

Open the matching file in `assets/`:

- One HTTP call → `assets/minimal-http.workflow.json`.
- One agent step → `assets/minimal-agent.workflow.json`.
- Workspace-bridged agent → `assets/workspace-keepalive.workflow.json`.
- Just the trigger schema block → `assets/trigger-schema.snippet.json`.

These are *complete* (`spec`, `nodes`, `edges`) — the BFF can ingest them directly.

## Step 2 — Fill in real values

Make a working copy. Then:

1. **document.name + document.title** — short, descriptive, unique-ish. The `name` ends up in the URL.
2. **input.schema** — declare every field the user provides at run time. See `assets/trigger-schema.snippet.json` for JSON Schema patterns. Fields you'll reference must appear here, otherwise `${ .trigger.<field> }` resolves to null.
3. **The `do[]` tasks** — adapt the templates. Reach for `references/sw-1.0-spec.md` for the 12 task types and `references/agent-task.md` for `durable/run` body.
4. **agentRef.id** — for any `durable/run`, replace the placeholder ID. Get a real one via:
   ```bash
   curl -s http://workflow-builder:3000/api/agents | jq '.[] | {id, slug, name}'
   ```
   Or inside the BFF pod:
   ```bash
   kubectl -n workflow-builder exec deploy/workflow-builder -- \
     psql "$DATABASE_URL" -c "SELECT id, slug, name FROM agents WHERE NOT is_archived ORDER BY updated_at DESC LIMIT 10;"
   ```
5. **nodes/edges** — easiest path: leave the template's start/end + one task as-is and only edit `data.taskConfig` to mirror your `do[]` change. The adapter won't run on direct DB upserts, so spec and nodes/edges must agree. If you change the spec significantly, regenerate via the BFF (see Step 3 path B).

## Step 3 — Run the spec validation checklist

From `references/sw-1.0-spec.md`:

1. ☐ `document.dsl == "1.0.0"`, namespace + name + version present.
2. ☐ Every `do[]` entry is a single-key object with one of the 12 task types set.
3. ☐ No rejected slugs (`claude/run`, `openshell/run`, `dapr-agent-py/run`, `mastra/*`, `agent/*`, …).
4. ☐ Every `${...}` value is fully wrapped (full-string rule).
5. ☐ `${ .trigger.<x> }` matches a declared input property.
6. ☐ `${ .<task>.<x> }` references an earlier task only.
7. ☐ Every `durable/run` has `with.agentRef.id`.
8. ☐ Sandbox-keep steps have `with.keepAfterRun: true`.

## Step 4 — Insert into the DB

### Path A (preferred): use the bundled script

```bash
python3 ~/.claude/skills/workflow-builder/scripts/upsert-workflow.py my-workflow.json
```

The script:
1. Resolves `project_id` from the user's session (or `WORKFLOW_BUILDER_API_KEY` env).
2. POSTs `{name, nodes, edges, engineType}` to `/api/workflows` (which stamps `userId` + `projectId`).
3. PUTs `{spec}` to `/api/workflows/<id>` to set the `spec` JSONB column.
4. Prints the canvas URL: `http://workflow-builder:3000/workspaces/<slug>/workflows/<id>`.
5. Falls back to direct `psql INSERT` if the BFF is unreachable (you must set `DATABASE_URL` and `--project-id` in that case).

Why both POST + PUT: `POST /api/workflows` does not accept a `spec` field — only `name`, `nodes`, `edges`, `engineType`. The `spec` column is set via `PUT /api/workflows/[id]` (see `src/routes/api/workflows/[workflowId]/+server.ts:50-77`). The script handles both calls.

### Path B (manual, BFF available): UI editor

Open `/workspaces/<slug>/workflows/new`, paste the spec into the Code tab, click Save. The BFF runs `specToGraph` to regenerate `nodes`/`edges` from the spec — that means you can hand-author *just* the spec and the BFF fills in the rest.

### Path C (manual, BFF down): direct psql

```bash
kubectl -n workflow-builder exec -it deploy/postgresql -- \
  psql -U postgres -d workflow_builder -c "
    INSERT INTO workflows (id, name, nodes, edges, engine_type, user_id, project_id, spec)
    VALUES ('wf_$(uuidgen | tr -d -)',
            'My Workflow',
            '<paste nodes JSON>'::jsonb,
            '<paste edges JSON>'::jsonb,
            'dapr',
            '<user-id>',
            '<project-id>',
            '<paste spec JSON>'::jsonb)
    RETURNING id;"
```

⚠ `project_id` is NOT NULL; without a real value the insert fails. Get one via:

```sql
SELECT id, slug, name FROM projects WHERE owner_user_id = '<user-id>' ORDER BY created_at LIMIT 5;
```

## Step 5 — Verify in the UI

Read `references/verify-in-ui.md`. Quick version:

1. `kubectl -n workflow-builder logs deploy/workflow-builder | tail -20` — confirm no compile errors.
2. Browse to `/workspaces/<slug>/workflows/<id>` — the canvas should render with start/end + your tasks.
3. Click **Execute** — the dialog should render form fields matching `input.schema.document.properties`.
4. Submit — runs page (`/workspaces/<slug>/workflows/<id>/runs/<execId>`) shows live execution.

## Recipe variants

### Adding an agent step to an existing workflow

1. Find the agent: `curl /api/agents` → copy `id` + `slug`.
2. Confirm the agent is published/registered. The `agent-runtime-<slug>` Deployment lands when the agent is published; agents not yet published WILL fail at runtime even if the spec parses.
3. If the agent needs project MCP tools, set its `mcpConnectionMode`/MCP connections in the agent UI or use an unresolved `mcpServers` reference; read `references/mcp-connections.md`.
4. Append a `durable/run` task to `do[]` per `assets/minimal-agent.workflow.json`.
5. Update `nodes`/`edges` to include the new node + edge to/from existing nodes (or use Path B in Step 4 to let the BFF regenerate).
6. Re-upsert via the script.

### Defining trigger inputs

The trigger drives `${ .trigger.<field> }`. Two-step:

1. Edit `spec.input.schema.document` (or `spec.document['x-workflow-builder'].input.schema` — the adapter normalizes both):
   ```json
   "input": {
     "schema": {
       "format": "json",
       "document": {
         "type": "object",
         "properties": {
           "url": { "type": "string", "format": "uri", "title": "Starting URL", "default": "https://example.com" },
           "task": { "type": "string", "title": "What to do", "default": "Summarize this page in 2 sentences." }
         },
         "required": ["url", "task"]
       }
     }
   }
   ```
2. Reference each declared field as `${ .trigger.url }`, `${ .trigger.task }`, etc. The Execute dialog auto-renders form fields from JSON Schema (string/number/enum/format=uri all work; nested objects are flattened).

### Workflow that runs on a webhook

Set up the webhook in the BFF: `POST /api/workflows/[workflowId]/webhook` with auth via JWT API key (`wfb_*` prefix). The webhook payload becomes the trigger data — so `${ .trigger.<field> }` reads webhook body fields. See `src/routes/api/workflows/[workflowId]/webhook/+server.ts` for the auth + payload shape.

## See also

- `references/sw-1.0-spec.md` — the spec.
- `references/agent-task.md` — `durable/run` body.
- `references/canvas-shape.md` — nodes/edges shapes.
- `references/troubleshooting.md` — when something goes wrong.
- `references/verify-in-ui.md` — confirming it shows up.
