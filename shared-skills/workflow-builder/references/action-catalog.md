# Action Catalog & Slug Routing

Scope: how the orchestrator routes a `call: <slug>` to a backing service, and how to discover what slugs are actually available at runtime. Read this before guessing a slug — the catalog API is the source of truth.

## Slug routing table

The orchestrator dispatches based on the slug *prefix*. Source: `services/workflow-orchestrator/workflows/sw_workflow.py` + CLAUDE.md routing table.

| Prefix | Target | Dispatch | Examples |
| --- | --- | --- | --- |
| `durable/run` | `agent-runtime-<slug>` (per-agent pod) | **Native Dapr child workflow** (`session_workflow` → `agent_workflow`). Bypasses function-router entirely. Target app-id = `agent-runtime-<agent.slug>` resolved from `with.agentRef.id`. Falls back to legacy `dapr-agent-py` when neither `agentAppId` nor `agentSlug` is stamped. | Every agent turn |
| `system/*` | fn-system | Dapr invoke → function-router → fn-system | `system/http-request`, `system/database-query`, `system/condition` |
| `workspace/*` | openshell-agent-runtime | Dapr invoke → function-router | `workspace/profile`, `workspace/clone`, `workspace/command`, `workspace/file`, `workspace/cleanup` |
| `browser/*` | openshell-agent-runtime | Dapr invoke → function-router | `browser/profile`, `browser/clone`, `browser/command`, `browser/capture-flow`, `browser/validate` |
| `openshell/*` | openshell-agent-runtime | Dapr invoke → function-router | OpenShell runtime helper routes |
| `code/*` | code-runtime | Dapr invoke → function-router | `code/typescript-function`, `code/python-function` |
| `*` (default fall-through) | fn-activepieces | Dapr invoke → function-router (credential decrypt + AP piece executor) | `@activepieces/piece-slack/send_message`, etc. |

`function-router` is the credential broker + Knative proxy for everything **except** `durable/run`. Slug routing inside function-router is governed by the `function-registry` ConfigMap in stacks (`packages/components/active-development/manifests/function-router/ConfigMap-function-registry.yaml`) — that's authoritative.

## Rejected legacy slugs

The orchestrator parses the spec at startup and rejects these on sight with `Removed SW 1.0 agent action`:

- `claude/run`
- `openshell/run`, `openshell/session-start`
- `openshell-langgraph/run`, `openshell-langgraph-observable/run`
- `dapr-agent-py/run`
- `dapr-swe/run`
- `durable/plan`
- Any `mastra/*` slug
- Any `agent/*` slug

Every agent execution today goes through `durable/run` with `with.agentRef`. There is no other agent dispatch path.

## Discovering available actions at runtime

Use the action-catalog API rather than guessing. Source: `src/lib/server/action-catalog/index.ts`.

| Endpoint | Returns |
| --- | --- |
| `GET /api/action-catalog` | `ActionCatalogSnapshot` — every action in every backing service (workflow-orchestrator, fn-activepieces, fn-system) flattened into one list. Each item has `id`, `name`, `displayName`, `description`, `pieceName`, `actionName`, `kind` (`sw-function` / `dapr-activity` / `dapr-workflow`), `visibility` (`public-callable` / `inspect-only`), `inputSchema`, `outputSchema`, and a suggested `taskConfig` (drop-in `with` block). |
| `GET /api/action-catalog/[actionId]` | `ActionCatalogDetail` — full schema + auth info for a single action. |

The orchestrator also exposes the raw introspection endpoints these pull from:

- `workflow-orchestrator:8080/api/metadata/actions` and `/api/v2/runtime/introspect`
- `fn-activepieces:8080/api/metadata/actions` and `/api/runtime/introspect`
- `fn-system:8080/api/metadata/actions` and `/api/runtime/introspect`

When the user asks "what action does X?", call `/api/action-catalog?q=<keyword>` first, copy the suggested `taskConfig`, and adapt it. Don't infer from memory.

## Activepieces piece slugs

AP pieces use the slug shape `@activepieces/piece-<name>/<action>`, e.g. `@activepieces/piece-slack/send_message`. The 42 installed AP pieces are listed in `src/lib/server/integrations/activepieces/installed-pieces.ts`. Adding a new piece requires:

1. Add to `installed-pieces.ts`.
2. Add npm dep to `services/fn-activepieces/package.json`.
3. Add to `services/fn-activepieces/src/piece-registry.ts`.
4. Rebuild `fn-activepieces`.

If the user's piece isn't in the list, that's why their slug doesn't work.

## Activepieces credentials

AP actions need an `app_connection`. The user creates connections via `/connections` in the UI; they're AES-256-CBC encrypted at rest in the `app_connections` table. function-router decrypts them at execution time and passes plaintext to fn-activepieces — orchestrator never sees plaintext. Auth types: `OAUTH2`, `SECRET_TEXT`, `BASIC_AUTH`, `CUSTOM_AUTH`.

For the spec, reference connections by `connectionId` in `with.auth`:

```json
{
  "send_msg": {
    "call": "@activepieces/piece-slack/send_message",
    "with": {
      "auth": { "connectionId": "${ .connections.slack_main }" },
      "channel": "#alerts",
      "text": "${ .summarize.result }"
    }
  }
}
```

`${ .connections.<name> }` is resolved by the BFF's connection-ref injector (see `src/lib/server/workflow-connections/`). The user must have created a connection with the matching alias.

## Per-task patterns to know

### `system/http-request`

```json
{
  "fetch": {
    "call": "system/http-request",
    "with": {
      "url": "${ .trigger.url }",
      "method": "GET",
      "headers": { "User-Agent": "workflow-builder" },
      "body": null,
      "timeoutMs": 30000
    },
    "output": { "as": { "status": "${ .status }", "data": "${ .data }" } }
  }
}
```

### `system/condition` (a.k.a. branching outside `switch`)

```json
{
  "check": {
    "call": "system/condition",
    "with": { "expression": "${ .fetch.status == 200 }" }
  }
}
```

For real branching prefer SW 1.0 `switch` — `system/condition` just returns a boolean.

### `workspace/profile` (provision a sandbox workspace)

```json
{
  "workspace_profile": {
    "call": "workspace/profile",
    "with": {
      "rootPath": "/sandbox",
      "sandboxTemplate": "dapr-agent",
      "ttlSeconds": 7200,
      "keepAfterRun": true,
      "enabledTools": ["execute_command", "read_file", "write_file", "edit_file", "list_files", "mkdir", "file_stat"],
      "managedBy": "workflow-builder:sandbox-policy",
      "name": "workspace_profile"
    }
  }
}
```

`keepAfterRun: true` is required for downstream `durable/run` to share the same sandbox (see `references/agent-task.md` § Sandbox bridging) AND for the live-preview proxy to find the sandbox post-run.

### `durable/run` (agent step)

See `references/agent-task.md` for the full body shape.

## Where to add a new slug

1. **A new system action** — implement in `services/fn-system/`, register in its `runtime/introspect`, deploy.
2. **A new workspace/browser/openshell action** — implement in `services/openshell-agent-runtime/`, register the slug.
3. **A new code function slug** — `services/code-runtime/`.
4. **Routing change** — edit the `function-registry` ConfigMap in stacks (NOT directly on the cluster — go through GitOps; see the `gitops` skill).

## See also

- `references/sw-1.0-spec.md` — `call` + `with` field shapes.
- `references/agent-task.md` — `durable/run` body in depth.
- `references/cluster-topology.md` — how function-router fits in.
