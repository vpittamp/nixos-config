# Agent-attached MCP connections

Scope: MCP servers and tools made available to an agent during `durable/run`.
This is not the external `workflow-mcp-server` authoring API. For workspace
authentication, workflow saves, and the optional Workflow Builder session
header, read `workflow-mcp-server.md`.

## Mental model

```text
project mcp_connection rows + agent config.mcpServers
        |
        v
workflow-builder BFF resolves servers and allowed tools at session launch
        |
        v
per-session Sandbox receives DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON
        |
        v
dapr-agent-py / claude-agent-py connects to each selected MCP server
```

There is no `AgentRuntime` CR, per-agent Deployment, controller injection, or
wake annotation. Non-browser runtimes launch as per-session `Sandbox` pods;
`browser-use-agent` uses the browser warm-pool path.

## Tool selection

The current UI is **Tools & Integrations** with an attach-list and an
include-all toggle. The old `auto | project | explicit` mode documentation is
retired.

Allowed tools are narrowed at two levels:

1. `mcp_connection.metadata.toolSelection` is the project ceiling.
2. The matching agent `config.mcpServers[].allowedTools` is the agent selection.

The effective set is the agent selection intersected with the project ceiling.
An absent `allowedTools` inherits the ceiling. An explicit `allowedTools: []` is
fail-closed: the resolver omits that MCP server and suppresses project-mode
auto-inclusion of the same server. A non-empty selection is also sent as the
`?tools=` filter, so the intersection is enforced at discovery and runtime
rather than being UI-only.

Use include-all only when the agent truly needs every enabled project MCP.
Each ActivePieces KService can scale to zero, and attaching the full catalog can
turn one agent launch into several serial cold starts. For smokes and focused
agents, turn include-all off and attach only the required servers/tools.

## ActivePieces credentials

Project ActivePieces MCP rows use reference-forwarding:

```text
mcp_connection.connection_external_id
        -> app_connection.external_id (encrypted credential)
agent request sends X-Connection-External-Id
        -> ap-<piece>-service /mcp
        -> BFF internal decrypt API
```

The BFF is the only decryptor. Do not place OAuth tokens or decrypted JSON in
agent config, workflow specs, KService env, or GitOps manifests. Caller-facing
Knative URLs have no container port, for example:

```text
http://ap-microsoft-outlook-service.workflow-builder.svc.cluster.local/mcp
```

Do not append `:3100`; that is the container port behind Knative.

## Launch and refresh behavior

Save or publish the agent after changing its integrations, then launch a new
session. The BFF resolves the selected servers and stamps the per-session
Sandbox bootstrap JSON. A running agent process does not automatically acquire
a changed MCP client configuration.

The same connection rules apply whether an agent is started directly or from a
workflow `durable/run` step. The workflow's `agentRef` selects the agent; it
does not copy credentials into the workflow.

## Browser and vision tools

Browser actions and MCP tools control the browser or retrieve DOM state. They
are not a substitute for image input. Kimi K3 can reason over screenshots only
when the runtime preserves structured image parts and sends supported
`image_url` objects or base64 `data:image/...` URLs containing the pixels.
Never serialize a multimodal content array into a string.

Keep browser-use-agent, BrowserStation, or Playwright for navigation,
interaction, screenshots, video, and layout inspection. Use K3 as the visual
reasoner over the resulting image bytes. Do not restore GLM-era compensating
browser tools that existed only because the model could not see.

## Dev diagnostics

The active shared target is dev. Do not sync or test Ryzen unless explicitly
requested.

```bash
kubectl --context dev -n workflow-builder get sandbox,pods
kubectl --context dev -n workflow-builder get cm activepieces-mcp-catalog -o yaml
kubectl --context dev -n workflow-builder get ksvc \
  -l app.kubernetes.io/managed-by=activepieces-mcp-reconciler
```

For the newly launched session, inspect the Sandbox pod and runtime logs:

```bash
kubectl --context dev -n workflow-builder get pod <session-pod> -o json \
  | jq '.spec.containers[] | {name, env}'
kubectl --context dev -n workflow-builder logs <session-pod> -c <runtime-container> \
  | rg 'mcp-bootstrap|connected|Registered|Missing credentials|X-Connection'
```

Expected evidence:

- selected MCP servers appear in the session bootstrap;
- the URL is the no-port Knative service URL;
- OAuth-backed entries carry `X-Connection-External-Id`;
- runtime logs show successful connection and tool registration;
- the effective tool list matches the project ceiling intersected with the agent
  selection, and an explicit empty selection omits the server.

If the KService is absent, debug the `activepieces-mcps` reconciler and DB row.
If the KService exists but the next Sandbox lacks it, re-save/publish the agent
and inspect BFF MCP resolution. If credentials fail, repair the
`app_connection` binding; do not copy the token into config.

Use the `gitops` runbook `debug-workflow-builder-mcp-auth.md` when the failure is
deployment-level rather than workflow authoring.
