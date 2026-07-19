# Agent Task (`durable/run`)

Scope: the legacy SW 1.0 `call: durable/run` body retained for existing
definitions and migrations. New dynamic scripts dispatch agents with
`await agent(prompt, opts)` and should not introduce new `durable/run` nodes.

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

Both are accepted at runtime — the canvas marks the node `type: "agent"` based purely on `call === "durable/run"` (`isAgentTaskConfig` in `agent-graph.ts` (~L438) is just that check).

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

When in doubt, use the flat shape. The `normalizeAgentTaskConfig` helper (`agent-graph.ts`, ~L446) actually mirrors flat fields into a `body` field anyway, so both are interchangeable from the orchestrator's view.

## Body fields

From `AgentTaskBody` (`src/lib/types/agent-graph.ts:65-80`):

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `agentRef.id` | Recommended | `string` | The DB `agents.id`. Resolves to `agents.runtime_app_id` (the per-session runtime Dapr app-id). **Without this, the runtime registry falls back to its `defaultRuntimeId` (`dapr-agent-py`) — almost certainly not what you want.** |
| `agentRef.version` | No | `number` | Pin a specific agent version. Defaults to current. |
| `prompt` | Yes | `string` | The appended user prompt to the agent. Use SW jq full-string interpolation for runtime values: `"${ \"Look at \" + .trigger.url }"`. Prompt Workbench Mustache placeholders are preview-only in V1 and are not substituted here at runtime. |
| `mode` | Yes | `"execute_direct"` | Literal enum value. Only mode supported today. |
| `maxTurns` | No | `number` | Default 50. Set lower for tight workflows; higher for complex multi-step agents. |
| `timeoutMinutes` | No | `number` | Per-execution timeout. Default 60. |
| `stopCondition` | No | `string` | Natural-language exit criterion the agent's stop hook checks. E.g. "Stop after the final response includes TASK COMPLETE." |
| `requireFileChanges` | No | `boolean` | If true, fail the run when the agent didn't modify any files. Useful for coding agents. |
| `workspaceRef` | No | `string` | `"local"` (per-call ephemeral), or a workspace ID, or `${ .workspace_profile.workspaceRef }` for sandbox bridging. |
| `sandboxName` | No | `string` | Override sandbox name. Used with `${ .workspace_profile.sandboxName }` for bridging. |
| `cwd` | No | `string` | Working directory inside the sandbox. Default `/sandbox`. |
| `agentRuntime` | Sometimes | `string` | Auto-derived from `agentRef` / DB agent config. Set explicitly only when dispatch glue needs to force a runtime such as `claude-agent-py` for a benchmark or smoke path. |
| `agentGraph` | Auto-filled | `AgentGraphDefinition` | Custom decision graph (rarely set by hand). `normalizeAgentTaskConfig` injects a default. |
| `environmentRef` | No | `EnvironmentRef` | Override the environment (sandbox config). Default uses the agent's published environment. |
| `overrides` | No | `AgentOverrides` | Per-call overrides: `sandboxPolicy`, `tools`, `maxTurns`, `timeoutMinutes`, `cwd`. |
| `mcpServers` | No | `McpServer[]` | Per-call MCP server list. Can be direct endpoints or unresolved project references such as `{ "pieceName": "microsoft-outlook" }`. Layered on top of the agent's startup/project config. **Playwright stdio entries are auto-rewritten** — see below. |
| `hooks` | No | `HooksSettings` | Per-call hook config (PreToolUse, PostToolUse, etc.). Per `docs/hooks-and-plugins.md`. |
| `plugins` | No | `string[]` | Plugin IDs to enable for this call. |

## How `agentRef.id` resolves to a runtime

1. `with.agentRef.id` is the DB `agents.id`.
2. The session-spawn handler resolves to `agents.runtime_app_id` and the orchestrator resolves the runtime via `core/runtime_registry.resolve()` (the SSOT in `services/shared/runtime-registry.json`) — `dapr-agent-py`, `claude-agent-py`, `adk-agent-py`, or `browser-use-agent`.
3. The orchestrator yields `ctx.call_child_workflow("session_workflow", app_id="<runtime-app-id>", ...)`.
4. The BFF launches a **per-session ephemeral Sandbox pod** (upstream `kubernetes-sigs/agent-sandbox`, Kueue-admitted) running that runtime's image; SWE-bench pool agents instead route to the static `agent-runtime-pool-coding`. There is no `AgentRuntime` CR and no wake annotation — that CRD + the Kopf `agent-runtime-controller` are retired.
5. The Dapr placement service routes the child workflow to the launched Sandbox pod.
6. The pod runs the turn, returns, and the Sandbox self-reaps on session end.

If `agentRef.id` is missing OR resolves to an agent that hasn't been published, the registry falls back to its `defaultRuntimeId` (`dapr-agent-py`). Don't rely on this — it's a backwards-compat shim.

## Runtime selection and model defaults

Agent runtime is selected by the agent row/config and the launch path, not by the workspace sandbox template. For SWE-bench and coding smokes, the reliable fields are DB/run metadata and workflow output:

- dapr-agent-py default: `modelSpec=kimi/kimi-k3`, component `llm-kimi-k3`, authenticated with `KIMI_API_KEY`. The model contract is a 1,048,576-token context window with reasoning fixed at `max`; the native adapter rejects any other `KIMI_REASONING_EFFORT`.
- Claude Agent SDK path: `agentRuntime=claude-agent-py`, `agentWorkflowMode=claude-agent-sdk`, model `anthropic/claude-opus-4-8`.
- GPT current default: modelSpec `openai/gpt-5.5` when the OpenAI component/env is available.
- Static pool path: `agents.runtime_app_id=agent-runtime-pool-coding`; this routes to the surviving static pool Deployment rather than a per-session Sandbox.
- Workspace/testbed template path: `sandboxTemplate: "dapr-agent"` can still be correct for `workspace/profile` even when the agent runtime is Claude.

For K3 structured output, object-shaped schemas use the synthetic `StructuredOutput` finalizer so normal browser/coding/MCP tools remain available before the final answer. Pydantic calls and non-object schemas retain native strict JSON Schema. For vision, pass structured `image_url` content or a supported base64 data URL containing the pixels; stringified multimodal arrays are not vision input.

When upgrading defaults, update workflow-builder model options and stacks runtime components/env pins together, then seed/launch under `vinod@pittampalli.com` in dev project `N1nbCo9zESa-S0UrzVrOw`. Do not deploy or test Ryzen unless explicitly requested.

### Two stamping paths (UI launch vs evaluations)

`body.agentRef` can be either a static `{id, version}` object OR a jq placeholder like `${ .trigger.agentRef }` — but only ONE of those works for any given launch path:

- **`/api/workflows/[id]/execute`** (regular UI / API launch): `resolveSpecAgentRefs` (`src/lib/server/agents/resolver.ts`) runs at workflow-LOAD time, BEFORE jq evaluates. It validates each `body.agentRef` is a real `{id, version}` shape; placeholder strings throw `AgentRefResolutionError`. So spec rows the UI launches must have **static** agentRef values.
- **Evaluations / code-eval / SWE-bench launches**: `service.ts:startEvaluationRunItemWorkflow` walks the spec via `stampAgentRefIntoDurableRunSteps` and replaces every `body.agentRef` with the live `{id, version}` BEFORE handing the spec to the orchestrator. Placeholder strings work here.

For a workflow you want runnable from BOTH paths, the simplest pattern is: hardcode a sensible default agentRef in the spec, expose it as a script CLI flag (`--agent-id`, `--agent-version`), and let evaluations callers stamp their own agentRef on top via the trigger. The `code-eval-item.workflow.json` + `scripts/upsert-3b1b-animation-workflow.ts` pair is the canonical example.

## Prompt preview, templating, and cache

The workflow agent-node panel's `Compiled Prompt` preview uses the shared Prompt Workbench preview component. It should show:

- The selected agent/version/config hash.
- The canonical template name/hash when available.
- The rendered system message from the saved agent instruction bundle.
- The `chat_history` placeholder.
- This node's `prompt` as the appended user message.

Runtime interpolation inside `durable/run.with.prompt` is SW 1.0 jq only. Use `${ .trigger.<field> }`, `${ .previous_task.output }`, or concatenation inside a single full-string jq expression. A Mustache value such as `{{runtime.cwd}}` or `{{args.ticket}}` in the node prompt is an authoring preview warning, not a runtime variable, and will be sent literally unless another runtime layer handles it.

For prompt caching, keep volatile node/run data in the appended user message where possible. Avoid stamping cwd, sandbox name, session id, run id, or workflow input into the agent's stable system prompt or preset text unless model behavior truly depends on it.

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

…and the launched Sandbox pod gets `chromium` + `playwright-mcp` sidecar containers mounted. The rewrite happens in BOTH session-spawn paths (direct UI sessions + workflow-driven sessions via `/api/internal/sessions/ensure-for-workflow`). You don't need to do anything — just specify the stdio preset and the platform handles the rest.

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

Critical: `workspace/profile.with.keepAfterRun: true` is required. Without it `_should_cleanup_workspaces` (in `sw_workflow.py`, def at ~L261) tears the sandbox down before the `durable/run` step starts.

## See also

- `references/cluster-topology.md` — what a per-session Sandbox pod looks like, the runtime registry SSOT, why it must be in the same namespace.
- `references/mcp-connections.md` — project MCP modes, ActivePieces auth binding, and bootstrap checks.
- `references/troubleshooting.md` — debug an agent that times out or never starts.
- `references/action-catalog.md` — how to discover which agents are published and runnable.
