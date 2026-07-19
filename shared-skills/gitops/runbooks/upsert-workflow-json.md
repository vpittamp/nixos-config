# Save a workflow definition to dev

## Current authoring lane

New user workflows are dynamic scripts. Save them through the dev Workflow MCP
server so workspace ownership, validation, and connection synchronization stay
inside the application boundary:

```text
get_workflow_context
  -> get_workflow_script_spec
  -> validate_workflow_script
  -> save_workflow_script
  -> run_workflow_script
```

Endpoint:
`https://workflow-builder-mcp-dev.tail286401.ts.net/mcp`

Authentication: a workspace-scoped `wfb_...` API key. Workflow save/run tools
do not take `sessionId`; an attached Workflow Builder session is optional
goal/trace lineage.

`save_workflow_script` upserts by name in the authenticated workspace. It is the
preferred non-interactive save path.

## BFF JSON path

For a machine-generated full definition, use the API-only helper with a BFF
login credential:

```bash
WORKFLOW_BUILDER_COOKIE='wb_access_token=<access-jwt>; wb_refresh_token=<refresh-jwt>' \
  python3 shared-skills/workflow-builder/scripts/upsert-workflow.py \
  /path/to/workflow.json
```

The helper creates with one full `POST /api/workflows` or updates with
`PUT /api/workflows/<id>` when the JSON includes `id`. Before an update it reads
the scoped row and refuses any engine other than `dynamic-script`; conversion of
a legacy row must use the application's explicit conversion command. Omitted
`nodes`/`edges` are preserved on update. Current POST accepts `spec`; the old
two-phase POST-then-PUT guidance is retired.

Do not pass the `wfb_...` workspace MCP key to `/api/workflows`. BFF workflow
routes require a Workflow Builder access JWT or login cookie.

## Legacy SW 1.0

SW definitions remain readable/runnable for migration and historical runs.
When `SW_AUTHORING_FROZEN=true`, new SW creation and SW spec writes are rejected.
Do not bypass that gate with SQL or an internal route. Convert the definition to
dynamic script; see workflow-builder `docs/code-first-cutover.md`.

## Verify

1. Call `get_workflow` through Workflow MCP and confirm the expected workspace.
2. Open the saved definition on the dev Workflows page.
3. Start a fresh run through `run_workflow_script {workflowName, args}`.
4. Confirm script-call journal state, spawned sessions, Sandbox/Kueue admission,
   result, and model/runtime metadata.
5. After a staged Workflow MCP auth/bootstrap rollout, create a fresh session;
   a retry of an already-running spawn does not refresh its token.

## Deployment relationship

Application code still reaches dev through GitHub -> hub Tekton -> GHCR/release
metadata -> Source Hydrator -> Promoter -> `env/spokes-dev` -> dev ArgoCD.
Saving a workspace definition is an application operation, never a GitOps SQL
hook. If the API is unavailable, restore it and retry.
