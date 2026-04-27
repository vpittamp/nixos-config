# Agent Task (`durable/run`)

Scope: the body shape for `call: durable/run` — the only agent-dispatch path in the system. Read this before adding an agent step. Source of truth: `src/lib/types/agent-graph.ts:65-80` (TS type) and the production fixtures in `scripts/fixtures/sample-workflows.json`.

## TL;DR

```json
{
  "summarize": {
    "call": "durable/run",
    "with": {
      "agentRef": { "id": "<agent.id>", "slug": "<agent.slug>" },
      "prompt": "${ \"Summarize this in two sentences: \" + .fetch.body }",
      "mode": "execute_direct",
      "maxTurns": 10,
      "workspaceRef": "local",
      "stopCondition": "Stop after producing the summary."
    }
  }
}
```

That's a complete, runnable agent step. The fields are explained below.

## Two equivalent `with` shapes

Both are accepted at runtime — the canvas marks the node `type: "agent"` based purely on `call === "durable/run"` (`isAgentTaskConfig` in `agent-graph.ts:401-407` is just that check).

**Flat** (preferred — what the simple browser-use template uses):

```json
{ "call": "durable/run", "with": { "agentRef": {...}, "prompt": "...", "mode": "execute_direct", ... } }
```

**Nested** (used by the office sample fixtures — wraps the agent body inside `with.body`):

```json
{
  "call": "durable/run",
  "with": {
    "body": { "agentRef": {...}, "prompt": "...", "overrides": { "maxTurns": 30 } },
    "mode": "execute_direct",
    "sandboxName": "${ .workspace_profile.sandboxName }",
    "workspaceRef": "${ .workspace_profile.workspaceRef }",
    "sandboxPolicy": { "keepAfterRun": true, "mode": "per-run", "template": "dapr-agent", "ttlSeconds": 7200 }
  }
}
```

When in doubt, use the flat shape. The `normalizeAgentTaskConfig` helper (`agent-graph.ts:409-453`) actually mirrors flat fields into a `body` field anyway, so both are interchangeable from the orchestrator's view.

## Body fields

From `AgentTaskBody` (`src/lib/types/agent-graph.ts:65-80`):

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `agentRef.id` | Recommended | `string` | The DB `agents.id`. Resolves to `agent-runtime-<agent.slug>` Dapr app-id. **Without this, the orchestrator falls back to legacy `dapr-agent-py` — almost certainly not what you want.** |
| `agentRef.version` | No | `number` | Pin a specific agent version. Defaults to current. |
| `prompt` | Yes | `string` | The user prompt to the agent. Use jq full-string interpolation: `"${ \"Look at \" + .trigger.url }"`. |
| `mode` | Yes | `"execute_direct"` | Literal enum value. Only mode supported today. |
| `maxTurns` | No | `number` | Default 50. Set lower for tight workflows; higher for complex multi-step agents. |
| `timeoutMinutes` | No | `number` | Per-execution timeout. Default 60. |
| `stopCondition` | No | `string` | Natural-language exit criterion the agent's stop hook checks. E.g. "Stop after the final response includes TASK COMPLETE." |
| `requireFileChanges` | No | `boolean` | If true, fail the run when the agent didn't modify any files. Useful for coding agents. |
| `workspaceRef` | No | `string` | `"local"` (per-call ephemeral), or a workspace ID, or `${ .workspace_profile.workspaceRef }` for sandbox bridging. |
| `sandboxName` | No | `string` | Override sandbox name. Used with `${ .workspace_profile.sandboxName }` for bridging. |
| `cwd` | No | `string` | Working directory inside the sandbox. Default `/sandbox`. |
| `agentRuntime` | Sometimes | `string` | Auto-derived from agentRef. Set explicitly for legacy slugs. |
| `agentGraph` | Auto-filled | `AgentGraphDefinition` | Custom decision graph (rarely set by hand). `normalizeAgentTaskConfig` injects a default. |
| `environmentRef` | No | `EnvironmentRef` | Override the environment (sandbox config). Default uses the agent's published environment. |
| `overrides` | No | `AgentOverrides` | Per-call overrides: `sandboxPolicy`, `tools`, `maxTurns`, `timeoutMinutes`, `cwd`. |
| `mcpServers` | No | `McpServer[]` | Per-call MCP server list. Can be direct endpoints or unresolved project references such as `{ "pieceName": "microsoft-outlook" }`. Layered on top of the agent's startup/project config. **Playwright stdio entries are auto-rewritten** — see below. |
| `hooks` | No | `HooksSettings` | Per-call hook config (PreToolUse, PostToolUse, etc.). Per `docs/hooks-and-plugins.md`. |
| `plugins` | No | `string[]` | Plugin IDs to enable for this call. |

## How `agentRef.id` resolves to a pod

1. `with.agentRef.id` is the DB `agents.id`.
2. The session-spawn handler resolves to `agents.runtime_app_id` (set at agent-publish time by `src/lib/server/agents/registry-sync.ts`, which derives `agent-runtime-<slug>` from `agents.slug`).
3. The orchestrator yields `ctx.call_child_workflow("session_workflow", app_id="agent-runtime-<slug>", ...)`.
4. The Dapr placement service routes the child workflow to the per-agent pod.
5. The Kopf controller wakes the pod (scales 0→1) via the `agents.x-k8s.io/wake` annotation if needed.
6. Pod runs the turn, returns, scales back to 0 after `idleTtlSeconds` (default 1800).

If `agentRef.id` is missing OR resolves to an agent that hasn't been published, the orchestrator falls back to legacy `dapr-agent-py`. Don't rely on this — it's a backwards-compat shim.

## How to find a real `agentRef.id`

```bash
curl -s http://workflow-builder:3000/api/agents | jq '.[] | {id, slug, name}'
```

Or directly:

```sql
SELECT id, slug, name FROM agents WHERE is_archived = false ORDER BY updated_at DESC LIMIT 10;
```

`/api/agents` filters out workflow-ephemeral agents (sessions created inline by `agentConfig` in a workflow, not user-published). Don't reference those — they don't have stable IDs.

## MCP servers (`mcpServers`)

Per-call MCP server config is layered on top of the agent's startup/project config. Read `references/mcp-connections.md` before adding OAuth-backed ActivePieces tools; most users should create a project MCP connection in the UI and let `mcpConnectionMode` resolve URL/auth instead of hardcoding secrets.

Direct stdio entry:

```json
{
  "name": "playwright",
  "transport": "stdio",
  "command": "npx",
  "args": ["@playwright/mcp@latest"]
}
```

OR HTTP/SSE:

```json
{ "name": "my-server", "transport": "streamable_http", "url": "https://my-server/mcp", "headers": { "Authorization": "Bearer ..." } }
```

Project-resolved ActivePieces piece:

```json
{ "pieceName": "microsoft-outlook" }
```

The resolver matches by `name`, `serverName`, `server_name`, `pieceName`, `serverKey`, or `displayName`, then fills the Knative URL and `X-Connection-External-Id` from the project's `mcp_connection` row. Generated piece MCP URLs should look like `http://ap-microsoft-outlook-service.workflow-builder.svc.cluster.local/mcp` with no explicit `:3100`.

### Playwright sidecar rewrite (important)

Per `src/lib/server/agents/mcp-sidecar.ts`: any entry matching Playwright (by name `"playwright"`, by URL containing `"playwright-mcp"`, or by args containing `"@playwright/mcp"`) is **automatically rewritten** to:

```json
{ "name": "playwright", "serverName": "playwright", "transport": "streamable_http", "url": "http://localhost:3100/mcp" }
```

…and the agent's `AgentRuntime` CR gets `browserSidecar.enabled=true`, which makes the controller mount `chromium` + `playwright-mcp` containers in the pod. The rewrite happens in BOTH session-spawn paths (direct UI sessions + workflow-driven sessions via `/api/internal/sessions/ensure-for-workflow`). You don't need to do anything — just specify the stdio preset and the platform handles the rest.

## Hooks + plugins (per-call)

Per `docs/hooks-and-plugins.md` — workflow-builder ports Claude Code's hooks/plugins to the Python Dapr agent. Per-call overlay:

```json
{
  "with": {
    "agentRef": { "id": "..." },
    "prompt": "...",
    "hooks": {
      "PreToolUse": [
        { "matcher": "Bash:rm.*", "hooks": [{ "type": "command", "command": "echo 'block rm'", "exitCode": 2 }] }
      ]
    },
    "plugins": ["claude-plugins-official:bash-safety"]
  }
}
```

Events fired in v1: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit`, `SessionStart`, `SessionEnd`, `Stop`, `Notification`. Hook types: `command` (subprocess) and `callback` (in-process Python).

## Sandbox bridging

Two `durable/run` steps can share a sandbox by chaining through a `workspace/profile` step:

```json
"do": [
  {
    "workspace_profile": {
      "call": "workspace/profile",
      "with": {
        "rootPath": "/sandbox",
        "sandboxTemplate": "dapr-agent",
        "ttlSeconds": 7200,
        "keepAfterRun": true,
        "enabledTools": ["execute_command", "read_file", "write_file", "edit_file", "list_files", "mkdir", "file_stat"]
      }
    }
  },
  {
    "code_step": {
      "call": "durable/run",
      "with": {
        "agentRef": { "id": "agt_coding" },
        "prompt": "Build the deck and save to /sandbox/out.pptx",
        "mode": "execute_direct",
        "sandboxName": "${ .workspace_profile.sandboxName }",
        "workspaceRef": "${ .workspace_profile.workspaceRef }",
        "cwd": "/sandbox",
        "maxTurns": 30
      }
    }
  }
]
```

Critical: `workspace/profile.with.keepAfterRun: true` is required. Without it `_should_cleanup_workspaces` (in `sw_workflow.py:130-180`) tears the sandbox down before the `durable/run` step starts.

## See also

- `references/cluster-topology.md` — what an `agent-runtime-<slug>` pod looks like, why it must be in the same namespace.
- `references/mcp-connections.md` — project MCP modes, ActivePieces auth binding, and bootstrap checks.
- `references/troubleshooting.md` — debug an agent that times out or never starts.
- `references/action-catalog.md` — how to discover which agents are published and runnable.
