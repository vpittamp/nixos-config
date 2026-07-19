# Action Catalog & Slug Routing

Scope: how the orchestrator routes a `call: <slug>` to a backing service, and how to discover what slugs are actually available at runtime. Read this before guessing a slug — the catalog API is the source of truth.

## Slug routing table

The orchestrator dispatches based on the slug *prefix*. Source: `services/workflow-orchestrator/workflows/sw_workflow.py` + CLAUDE.md routing table.

| Prefix | Target | Dispatch | Examples |
| --- | --- | --- | --- |
| `durable/run` | Runtime-registry-selected per-session Dapr app id (or the explicit static benchmark pool) | **Native Dapr child workflow** named `session_workflow`; bypasses function-router. `with.agentRef.id` resolves the saved agent/runtime, and the BFF launches the per-session `Sandbox`. A missing runtime selection uses the registry's `defaultRuntimeId` (`dapr-agent-py`) compatibility path. There is no `agent-runtime-<slug>` Deployment or `AgentRuntime` CR. | Every agent turn |
| `system/*` | fn-system | Dapr invoke → function-router → fn-system | `system/http-request`, `system/database-query`, `system/condition` |
| `workspace/*` | openshell-agent-runtime | Dapr invoke → function-router | `workspace/profile`, `workspace/clone`, `workspace/command`, `workspace/file`, `workspace/cleanup` |
| `browser/*` | openshell-agent-runtime | Dapr invoke → function-router | `browser/profile`, `browser/clone`, `browser/command`, `browser/capture-flow`, `browser/validate` |
| `openshell/*` | openshell-agent-runtime | Dapr invoke → function-router | OpenShell runtime helper routes |
| `code/*` | code-runtime | Dapr invoke → function-router | `code/typescript-function`, `code/python-function` |
| `*` (default fall-through) | per-piece `ap-<piece>-service` (piece-runtime) | Dapr invoke → function-router (`function-registry` `_default` `{type: activepieces}` computes `ap-<piece>-service`) → piece-runtime `POST /execute` | `github/create-issue`, `slack/send-message`, etc. |

`function-router` is the credential-reference forwarder + Knative proxy for everything **except** `durable/run`. For AP routes it computes the per-piece `ap-<piece>-service` (one converged `piece-mcp-server` image parameterized by `PIECE_NAME`) and **forwards only `X-Connection-External-Id`** (writing the `credential_access_logs` audit, source `reference_forwarded`); the piece-runtime self-resolves plaintext by GETting the BFF `/api/internal/connections/<id>/decrypt`. function-router never holds plaintext, and AES-256-CBC decryption lives ONLY in the BFF (`src/lib/server/security/encryption.ts`). Slug routing inside function-router is governed by the `function-registry` ConfigMap in stacks (`packages/components/workloads/function-router/manifests/ConfigMap-function-registry.yaml`) — that's authoritative. (`fn-activepieces` was deleted — its app-scoped `ap_<piece>_<action>` activities were never deployed.)

## Rejected legacy slugs

The orchestrator's `_REMOVED_AGENT_ACTION_TYPES` set raises `Removed SW 1.0 agent action` at call dispatch. It is **exactly these eight slugs**:

- `claude/run`
- `openshell/run`, `openshell/session-start`
- `openshell-langgraph/run`, `openshell-langgraph-observable/run`
- `dapr-agent-py/run`
- `dapr-swe/run`
- `durable/plan`

Legacy `mastra/*` and `agent/*` slugs are **not** in that set — they do NOT raise the "Removed" error. They fall through to the default route (function-router → `function-registry` `_default` `{type: activepieces}`, which computes a per-piece `ap-<piece>-service`) and fail there as an unknown piece/action (a different, less obvious error). Don't use them. (The repo's CLAUDE.md still lists `mastra/*`/`agent/*` as "rejected"; the `_REMOVED_AGENT_ACTION_TYPES` code in `sw_workflow.py` is authoritative.)

Every agent execution today goes through `durable/run` with `with.agentRef`. There is no other agent dispatch path.

## Discovering available actions at runtime

Use the action-catalog API rather than guessing. Source: `src/lib/server/action-catalog/index.ts`.

| Endpoint | Returns |
| --- | --- |
| `GET /api/action-catalog` | `ActionCatalogSnapshot` — every action flattened into one list: orchestrator + fn-system introspection plus DB-backed AP piece actions (from `piece_metadata`). Each item has `id`, `name`, `displayName`, `description`, `pieceName`, `actionName`, `kind` (`sw-function` / `dapr-activity` / `dapr-workflow`), `visibility` (`public-callable` / `inspect-only`), `inputSchema`, `outputSchema`, and a suggested `taskConfig` (drop-in `with` block). |
| `GET /api/action-catalog/[actionId]` | `ActionCatalogDetail` — full schema + auth info for a single action. |

The orchestrator/services also expose the raw introspection endpoints the catalog pulls from:

- `workflow-orchestrator:8080/api/metadata/actions` and `/api/v2/runtime/introspect`
- `fn-system:8080/api/metadata/actions` and `/api/runtime/introspect`

The AP slice of the catalog is **DB-backed from `piece_metadata`** (there is no `fn-activepieces` introspection endpoint anymore — that service was deleted).

When the user asks "what action does X?", call `/api/action-catalog?q=<keyword>` first, copy the suggested `taskConfig`, and adapt it. Don't infer from memory.

## Activepieces piece slugs

AP pieces use the slug shape `<piece>/<action>`, e.g. `github/create-issue`, `slack/send-message`. function-router routes the slug's `<piece>` prefix to the converged per-piece **piece-runtime** Knative Service `ap-<piece>-service` (one `piece-mcp-server` image parameterized by `PIECE_NAME`), where it runs as a deterministic Dapr activity (`POST /execute`). The all-catalog reconciler (`activepieces-mcps`) provisions ~47 `ap-<piece>-service` from enabled `mcp_connection` rows + pinned pieces, so **new pieces are automatic — no manual per-piece add**. To add/build a NEW piece into the piece-runtime image (vs just enabling an already-bundled one):

1. Add the npm dep to `services/piece-mcp-server/`.
2. Register it in `services/piece-mcp-server/`'s `piece-registry`.
3. Rebuild the `piece-mcp-server` image.
4. Re-sync piece metadata (the catalog is DB-backed from `piece_metadata`).

(`fn-activepieces` was deleted — the old `installed-pieces.ts` + `services/fn-activepieces/**` edit steps are obsolete.)

## Activepieces credentials

AP actions need an `app_connection`. The user creates connections via `/connections` in the UI; they're AES-256-CBC encrypted at rest in the `app_connections` table. Credentials use **reference-forwarding**: at execution time function-router forwards only `X-Connection-External-Id` (writing the `credential_access_logs` audit, source `reference_forwarded`) — it does NOT fetch or hold plaintext. The per-piece **piece-runtime** (`ap-<piece>-service`) self-resolves the plaintext by GETting the BFF `/api/internal/connections/<id>/decrypt`, where the BFF performs the actual AES-256-CBC decryption (the BFF is the SOLE decryptor). The same reference-forwarding path applies to AP **MCP tools** as well as deterministic activities. The orchestrator never sees plaintext. Auth types: `OAUTH2`, `SECRET_TEXT`, `BASIC_AUTH`, `CUSTOM_AUTH`.

For the spec, reference connections by `connectionId` in `with.auth`:

```json
{
  "send_msg": {
    "call": "slack/send-message",
    "with": {
      "auth": { "connectionId": "${ .connections.slack_main }" },
      "channel": "#alerts",
      "text": "${ .summarize.result }"
    }
  }
}
```

`${ .connections.<name> }` is resolved by the BFF's connection-ref injector (see `src/lib/server/workflow-connections.ts`). The user must have created a connection with the matching alias.

## ActivePieces as MCP tools

Do not confuse AP action slugs with piece MCP servers:

| Path | Use when | Auth path |
| --- | --- | --- |
| `<piece>/<action>` task slug | The workflow spec should call one specific AP action as a task | function-router forwards `X-Connection-External-Id` (audit `reference_forwarded`) to the per-piece `ap-<piece>-service` `POST /execute`, which self-resolves plaintext via the BFF `/decrypt` |
| `mcp_connection` + piece MCP tools | The agent should see a piece's actions as tools during `durable/run` | agent sends `X-Connection-External-Id` to the same `ap-<piece>-service` `/mcp`, which self-resolves via the BFF `/decrypt` |

Both paths hit the SAME converged piece-runtime (`ap-<piece>-service`, the `piece-mcp-server` image) — `/execute` for deterministic activities, `/mcp` for agent tools. For agent tool use, prefer the MCP path and read `references/mcp-connections.md`. For deterministic workflow steps, prefer an explicit AP action slug.

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

In a new dynamic script, branch with ordinary JavaScript. This
`system/condition`/SW `switch` guidance is only for a frozen legacy definition.

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

### `browser/validate` (boot a dev server + capture screenshots)

Used to validate a generated/built app by booting its dev server inside the workspace's sandbox, then driving Playwright through a sequence of `visit` / `click` steps that wait for selectors and take screenshots. Stores results in `workflow_browser_artifacts` (manifest) + `workflow_browser_artifact_blob_payloads` (PNG blobs).

```json
{
  "browser_validate_capture": {
    "call": "browser/validate",
    "with": {
      "workspaceRef": "${ .workspace_profile.workspaceRef }",
      "repoPath": "${ \"/sandbox/\" + (.trigger.repo // \"app\") }",
      "installCommand": "",
      "baseUrl": "http://127.0.0.1:0",
      "steps": [
        { "id": "initial",  "label": "Loaded",  "action": "visit", "path": "/", "waitForSelector": "canvas#canvas",          "pauseMs": 1500, "fullPage": true },
        { "id": "play",     "label": "Play",    "action": "click",              "selector": "button#btn-play",   "waitForSelector": "canvas#canvas", "pauseMs": 2000, "fullPage": true },
        { "id": "restart",  "label": "Restart", "action": "click",              "selector": "button#btn-restart", "waitForSelector": "canvas#canvas", "pauseMs": 1500, "fullPage": true }
      ],
      "captureMode": "demo",
      "captureVideo": true,
      "captureTrace": true,
      "viewportPreset": "desktop",
      "demoTitle":   "${ \"Demo: \" + .trigger.title }",
      "demoSummary": "Generated app captured by browser/validate.",
      "timeoutMs": 600000
    }
  }
}
```

**Critical: do NOT hardcode a port** in `devServerCommand` or `baseUrl`. The runtime calls `_allocate_local_port()` per run and **rewrites baseUrl to use the allocated port**. The readiness probe polls the *allocated* port — if your devServerCommand binds something else, the probe times out with `Dev server did not become ready` even though your server is up.

**The right shape — three options, in order of preference**:

1. **Omit `devServerCommand` entirely** (recommended; matches `services/dapr-agent-py/animation-3b1b-v2-managed.workflow.json`). The runtime's default `_local_devserver_runner(cwd, port)` auto-detects:
   - Next.js project → `next dev --host 0.0.0.0 --port {port}` (or pnpm/yarn variant)
   - Any `package.json` with a `dev` script → `npm run dev -- --host 0.0.0.0 --port {port}`
   - Plain `index.html` → `python3 -m http.server {port} --bind 0.0.0.0`
2. **Use `{port}` placeholder** when you need a non-default command:
   ```jsonc
   "devServerCommand": "npm run preview -- --host 0.0.0.0 --port {port}"
   ```
   Other recognized substitutions: `${PORT}`, `$PORT`, `{baseUrl}`. Plus `PORT` and `BASE_URL` env vars are set on the launched process.
3. **Set `baseUrl: "http://127.0.0.1:0"`** to make the placeholder explicit. The runtime overrides the port; any hostname/port you supply is just a template.

Notes:
- `installCommand: ""` skips install. For a Vite/Next/SvelteKit app generated by an agent, supply `"npm install --no-audit --no-fund --loglevel=warn"` instead.
- `--host 0.0.0.0` (or `--bind 0.0.0.0`) is required for the readiness probe; `127.0.0.1`-only listeners are not reachable from the probe namespace.
- `baseUrl` only matters for the host part — the port gets rewritten regardless.
- Runtime entrypoints are currently delivered from stacks in `packages/components/workloads/openshell-agent-runtime/manifests/ConfigMap-openshell-agent-runtime-script.yaml`; inspect the embedded `main.py` there rather than looking for a removed workflow-builder service directory.

### `durable/run` (agent step)

See `references/agent-task.md` for the full body shape.

## Where to add a new slug

1. **A new system action** — implement in `services/fn-system/`, register in its `runtime/introspect`, deploy.
2. **A new workspace/browser/openshell action** — implement it in the stacks-managed `ConfigMap-openshell-agent-runtime-script.yaml` runtime source and update/verify function-router routing and the BFF action catalog. Do not create a parallel workflow-builder service directory.
3. **A new code function slug** — `services/code-runtime/`.
4. **Routing change** — edit the `function-registry` ConfigMap in stacks (NOT directly on the cluster — go through GitOps; see the `gitops` skill).

## See also

- `references/sw-1.0-spec.md` — `call` + `with` field shapes.
- `references/agent-task.md` — `durable/run` body in depth.
- `references/mcp-connections.md` — AP pieces exposed as agent MCP tools.
- `references/cluster-topology.md` — how function-router fits in.
