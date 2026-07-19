# Workflow MCP server

Scope: connect an external MCP client to Workflow Builder, confirm its
workspace, and save or run workflows. This server is an authoring/execution
surface; agent-attached tool servers are covered by `mcp-connections.md`.

## Connect to dev

1. Open `/workspaces/<workspace-slug>/settings/keys` in Workflow Builder.
2. Create a workspace API key and retain the one-time `wfb_...` value.
3. Connect the MCP client to:

   ```text
   https://workflow-builder-mcp-dev.tail286401.ts.net/mcp
   ```

4. Send the key on every request:

   ```text
   Authorization: Bearer <WFB_API_KEY>
   ```

The Nix-managed Codex, Claude Code, Kimi Code, and Antigravity clients use the
shared `mcp-remote` wrapper. It reads `WFB_API_KEY`, or resolves
`WFB_API_KEY_OP_REF` at process startup. `WFB_MCP_URL` is an explicit endpoint
override. Secrets must not be written into the Nix store or generated client
configuration.

## First call

Call `get_workflow_context` before any write. It reports the authenticated
workspace, scopes, capabilities, and optional attached Workflow Builder
session. It does not return the key.

Workflow definition operations use the authenticated workspace:

- `list_workflows`
- `get_workflow`
- `save_workflow_script`
- `validate_workflow_script`
- `run_workflow_script`
- `execute_workflow`

These operations do **not** take a `sessionId` tool argument. The workspace
resolved from the bearer key owns saved workflows and scopes all lookups.

For a dynamic script, use this sequence:

```text
get_workflow_context
  -> get_workflow_script_spec
  -> validate_workflow_script
  -> save_workflow_script
  -> run_workflow_script
```

Saving before running gives the workflow a stable workspace-owned definition
that can be inspected, edited, and rerun by name. Inline script execution is
available for deliberate one-off tests, but it is not a replacement for saving
the reusable workflow.

## Optional Workflow Builder session

Set `WFB_MCP_SESSION_ID` only when intentionally attaching an existing Workflow
Builder `sessions.id`:

```bash
export WFB_MCP_SESSION_ID='<workflow-builder-session-id>'
```

The wrapper sends it as `X-Wfb-Session-Id`. The server verifies that it belongs
to the same user and workspace as the API key. API-key session context is only
for goal, trace, and explicit lineage operations. It does not authenticate the
request, change workflow ownership, or grant team capabilities.

Platform-spawned agents receive a signed, session-bound bootstrap credential
automatically. Users do not forge or supply it. Team role and script recursion
depth are signed claims; raw headers do not grant those capabilities.

## Do not confuse these IDs

| ID | Meaning | Workflow owner or credential? |
| --- | --- | --- |
| `Mcp-Session-Id` | Streamable HTTP protocol state | No |
| Workflow Builder `sessions.id` | Optional goal/trace/lineage context | No |
| AI client thread ID | Local Codex/Claude/Kimi conversation | No |

Do not copy a transport session or AI client thread into
`WFB_MCP_SESSION_ID`. The clients intentionally do not infer one identity from
another.

## Target boundary

Cross-target workflow routing and cluster-wide preview discovery are disabled.
Do not forward a dev workspace key to another target. Connect directly to the
intended target's MCP endpoint with a key created in that target. The current
shared deployment/test lane is dev; other targets are opt-in.

## Troubleshooting

- `WFB_API_KEY is required`: set the environment variable or repair the
  1Password reference, then restart the MCP client.
- Authentication failed: rotate a workspace-bound key, or replace a legacy
  webhook key with a newly created workspace key.
- Wrong workspace: use the intended workspace's key and confirm it through
  `get_workflow_context` before saving.
- Session context rejected: unset `WFB_MCP_SESSION_ID`, or attach a session
  owned by the same user and workspace.
- A workflow save asks for `sessionId`: the client or instructions are stale;
  update them to the workspace-key contract and call the no-session tool.

Authoritative source: workflow-builder `docs/workflow-mcp-server.md` and
`services/workflow-mcp-server/src/{auth-context,context-tools,script-tools,workflow-tools}.ts`.
