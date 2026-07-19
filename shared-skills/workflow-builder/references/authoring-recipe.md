# Dynamic-Script Authoring Recipe

Scope: create a new user workflow, save it in the authenticated workspace, and
run it on dev. SW 1.0 is a frozen legacy format; it is not the new-workflow
template.

## 1. Establish the workspace

Connect to the dev Workflow MCP endpoint with a workspace `wfb_...` API key and
call `get_workflow_context`. Confirm the expected workspace and `workflow:write`
and `workflow:execute` capabilities before authoring.

Workflow operations do not take `sessionId`. A verified Workflow Builder
session is optional goal/trace lineage only.

## 2. Read the live dialect

Call `get_workflow_script_spec` before writing. The server response is the
authoritative client-facing contract. The repository sources are:

- `docs/dynamic-script-authoring-guide.md`
- `docs/dynamic-script-workflows.md`
- `docs/code-first-cutover.md`

The common primitives are:

- `await agent(prompt, opts)` for an agent call
- `await parallel(thunks)` for a barrier fan-out
- `await pipeline(items, ...stages)` for per-item streaming stages
- `await action(slug, input, opts)` for deterministic platform actions
- `await sleep(seconds)` and `await approve()` / `waitForEvent()`
- `await workflow(name, args)` for one-level saved-workflow composition
- `phase(title)` and `log(message)` for progress

Always await async primitives. Un-awaited calls and Promises in the returned
value are hard script errors.

## 3. Write the script

Start with a pure literal metadata export:

```js
export const meta = {
  name: 'inspect-page',
  description: 'Inspect a page and return a structured summary',
  input: {
    type: 'object',
    properties: {
      url: { type: 'string', format: 'uri' },
    },
    required: ['url'],
  },
}

const RESULT = {
  type: 'object',
  properties: {
    title: { type: 'string' },
    summary: { type: 'string' },
  },
  required: ['title', 'summary'],
}

const result = await agent(
  `Open ${args.url}, inspect the rendered page, and summarize it.`,
  {
    agent: 'kimi-k3-browser-agent',
    model: 'kimi/kimi-k3',
    effort: 'max',
    schema: RESULT,
    label: 'inspect-page',
  },
)

return result
```

Kimi K3 is the default dapr-agent-py model. It uses `KIMI_API_KEY`, a
1,048,576-token context window, and maximum thinking. For vision, preserve
structured image objects or base64 data URIs; never stringify multimodal
content arrays into screenshot metadata.

Use `opts.agent` for a saved agent/persona slug. `opts.agentType` selects a
runtime such as `dapr-agent-py` or `browser-use-agent`; it is not a persona.
Use exact platform model keys, not tier aliases.

## 4. Validate, save, and run

Use this exact loop:

```text
validate_workflow_script
  -> fix every reported error
  -> save_workflow_script
  -> run_workflow_script { workflowName, args }
```

`save_workflow_script` validates again and upserts by workflow name inside the
authenticated workspace. Save before run so the reusable definition has a
stable workspace-owned identity and appears in the Workflows UI.

## 5. Verify

1. Read the saved definition with `get_workflow`.
2. Open `https://workflow-builder-dev.tail286401.ts.net/workspaces/<slug>/workflows/<id>`.
3. Confirm the script canvas and `meta.input` form.
4. Run by saved name and inspect the run page, script-call journal, spawned
   session, Sandbox/Kueue admission, and returned value.
5. For a staged Workflow MCP token/bootstrap change, start a fresh session.
   Retrying spawn for an already-running session does not refresh its token.

## Secondary BFF JSON path

`scripts/upsert-workflow.py` is available for a machine-generated full JSON
definition. It creates with POST or updates when the payload includes `id`.
It requires a Workflow Builder access JWT or login cookie:

```bash
WORKFLOW_BUILDER_COOKIE='wb_access_token=<access-jwt>; wb_refresh_token=<refresh-jwt>' \
  python3 scripts/upsert-workflow.py workflow.json
```

A workspace `wfb_...` API key authenticates Workflow MCP, not the
session-authenticated `/api/workflows` BFF routes. The helper has no direct
Postgres fallback.

## Legacy SW 1.0

Existing SW definitions remain readable/runnable through `sw_workflow_v1`.
When `SW_AUTHORING_FROZEN=true`, explicit new SW creation and SW spec writes are
rejected while metadata-only edits and internal migration producers remain
possible. Use `sw-1.0-spec.md`, `agent-task.md`, and `canvas-shape.md` only to
diagnose or migrate an existing row. Never bypass the freeze or application
ports with SQL.
