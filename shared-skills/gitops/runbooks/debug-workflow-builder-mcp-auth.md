# Debug Workflow Builder MCP authentication

Scope: two distinct paths that share the `workflow-mcp-server` name but have
different ownership and credential contracts:

1. external Workflow MCP authoring/execution; and
2. MCP tools attached to an agent during `durable/run`.

The active shared target is dev. Do not deploy, sync, or test Ryzen unless the
user explicitly requests it.

## Path A: external Workflow MCP

### Contract

External clients connect to:

```text
https://workflow-builder-mcp-dev.tail286401.ts.net/mcp
Authorization: Bearer <workspace wfb_... key>
```

The user creates the key at
`/workspaces/<workspace-slug>/settings/keys`. Call
`get_workflow_context` first. It confirms the authenticated workspace, scopes,
capabilities, and optional attached Workflow Builder session.

Workflow reads, saves, validation, and execution are owned by that workspace
and do not take a `sessionId` tool argument. `X-Wfb-Session-Id` is optional,
verified goal/trace/lineage context for API-key clients; it is not a credential.
Platform-spawned agents receive a signed session token automatically. Team role
and recursion depth come from signed claims, never caller-supplied headers.
An already-running session keeps its existing bootstrap: `spawnSessionWorkflow`
returns early on retry and does not refresh the token. Start a fresh session
after a staged Workflow MCP credential/auth rollout.

Dev may temporarily set `WORKFLOW_MCP_LEGACY_RUNTIME_COMPAT_UNTIL` to an
absolute cutoff no more than 48 hours ahead. This is a route-opt-in bridge for
selected direct internal BFF operations owned by already-running pre-token
sessions. The BFF rechecks ownership, nonterminal session state, and current
membership, then grants only the minimal resource-specific scope. It grants no
team capability or arbitrary script depth. The flag is not an external MCP
authentication mechanism, and `X-Wfb-Session-Id` alone remains invalid at the
Workflow MCP endpoint. New sessions must use signed credentials; remove the
flag after the migration window.

Do not confuse Workflow Builder `sessions.id` with Streamable HTTP
`Mcp-Session-Id` or an AI-client thread ID.

Cross-target routing and cluster-wide preview discovery are disabled. Never
forward a dev workspace key to another target; connect directly with a key
created in that target.

### Diagnose

Confirm the managed dev Applications from the hub, then the dev workloads:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n dev get applications \
  | rg 'workflow-builder|activepieces|knative'
kubectl --context admin@dev -n workflow-builder get deploy \
  workflow-builder workflow-mcp-server
kubectl --context admin@dev -n workflow-builder get service \
  workflow-mcp-server workflow-mcp-server-tailnet
```

The MCP Deployment has two replicas with surge-only rollouts to protect
long-lived Streamable HTTP clients. It receives explicit `DATABASE_URL` and
`INTERNAL_API_TOKEN` secret references. It must not receive the BFF JWT or
Workflow MCP signing key:

```bash
kubectl --context admin@dev -n workflow-builder get deploy workflow-mcp-server \
  -o json | jq '.spec.replicas, .spec.template.spec.containers[] | select(.name=="workflow-mcp-server") | .env'
```

Inspect both sides of principal resolution:

```bash
kubectl --context admin@dev -n workflow-builder logs deploy/workflow-builder \
  --since=20m | rg 'workflow-mcp|principal|api.key|workspace'
kubectl --context admin@dev -n workflow-builder logs deploy/workflow-mcp-server \
  --since=20m --all-pods | rg 'auth|principal|workspace|session|scope|error'
```

Interpretation:

- unauthenticated or wrong workspace: create/rotate the key in the intended
  workspace and restart the MCP client;
- session rejected but workflow CRUD works: unset `WFB_MCP_SESSION_ID`, or use
  a session owned by the same user/workspace;
- save tool asks for `sessionId`: the client/server image or its instructions
  are stale; current save ownership comes from the workspace principal;
- one client remains broken after a rollout: restart that MCP client so it
  establishes a new Streamable HTTP session against the current replicas.

Roll out BFF token issuance and, only if required, the bounded dev compatibility
flag before MCP enforcement. Existing CLI processes cannot receive a new signed
bootstrap configuration in place; restart or drain them during the cutover,
then remove the flag. Do not publish these client/operator instructions ahead
of the matching workflow-builder and stacks rollout.

## Path B: agent-attached MCP tools

### Contract

```text
workflow-builder DB
  mcp_connection.connection_external_id
  app_connection.external_id
        |
        v
activepieces-mcps reconciler
  -> activepieces-mcp-catalog
  -> ap-<piece>-service KServices
        |
        v
BFF session launch resolves agent config.mcpServers + allowedTools
  -> per-session Sandbox DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON
        |
        v
runtime sends X-Connection-External-Id to /mcp
  -> piece-runtime calls BFF internal decrypt API
```

There is no `AgentRuntime` CR, `agent-runtime-controller`, per-agent Deployment,
registry wake annotation, or per-agent state store. Those instructions are
retired. The BFF launches per-session `Sandbox` pods selected through the
runtime registry; browser-use-agent uses its warm-pool carve-out.

The auth boundary is the connection external ID. Keep OAuth tokens out of
GitOps, workflow JSON, and KService env. Caller-facing Knative URLs must not
include container port `:3100`.

### Diagnose catalog and credentials

```bash
kubectl --context admin@dev -n workflow-builder get cm activepieces-mcp-catalog \
  -o jsonpath='{.data.servers\.json}' | jq .
kubectl --context admin@dev -n workflow-builder get ksvc \
  -l app.kubernetes.io/managed-by=activepieces-mcp-reconciler
kubectl --context admin@dev -n workflow-builder get jobs \
  -l app.kubernetes.io/name=activepieces-mcp-reconciler \
  --sort-by=.metadata.creationTimestamp
```

Query the DB from an approved application/admin path and confirm enabled
`mcp_connection` rows bind the expected active `app_connection.external_id`.
Do not extract or print decrypted credential values.

Save/publish the agent after an integration change and launch a fresh session.
Then inspect the new Sandbox and runtime log:

```bash
kubectl --context admin@dev -n workflow-builder get sandbox,pods
kubectl --context admin@dev -n workflow-builder logs <session-pod> \
  -c <runtime-container> --tail=250 \
  | rg 'mcp-bootstrap|connected|Registered|Missing credentials|X-Connection'
```

Expected bootstrap entries use a no-port URL such as:

```text
http://ap-microsoft-outlook-service.workflow-builder.svc.cluster.local/mcp
```

and include `X-Connection-External-Id` for the selected user connection.

### Tool selection

The effective tool list is the project
`mcp_connection.metadata.toolSelection` ceiling intersected with the matching
agent `config.mcpServers[].allowedTools`. An absent agent `allowedTools` permits
the project ceiling; `[]` permits none. The UI uses an attach-list plus
include-all toggle. The retired `auto | project | explicit` modes are not the
current authoring model.

If startup is slow, check whether include-all attached several scale-to-zero
piece KServices. Prefer an explicit small attach-list for focused agents.

### Dapr durability

Exactly one actor state store must be visible to each workflow sidecar:

```bash
kubectl --context admin@dev -n workflow-builder get component \
  workflowstatestore dapr-agent-py-statestore -o yaml \
  | rg 'name:|actorStateStore|scopes:'
```

`workflowstatestore` is the only `actorStateStore=true` component.
`dapr-agent-py-statestore` remains `actorStateStore=false` for agent application
state. Do not create per-agent components.

## Fix patterns

- Missing KService/catalog entry: repair the DB row or
  `activepieces-mcps` reconciler; do not hand-create a permanent KService.
- Stale Sandbox bootstrap: save/publish the agent and launch a new session;
  inspect BFF MCP resolution if it is still absent.
- Legacy `:3100` URL: fix the resolver/config source and relaunch the session.
- Missing credential: repair the `app_connection` binding; do not inline the
  token.
- First-call timeout: retry with a suitable timeout before changing manifests;
  catalog KServices intentionally scale to zero.

## Verify

- dev Applications and Deployments are Synced/Healthy and Available;
- `get_workflow_context` returns the expected workspace for the external key;
- workflow save/run works without a Workflow Builder session;
- the intended piece appears in the catalog and has a Ready KService;
- a newly launched Sandbox receives only the intended servers/tools;
- runtime logs show MCP connection and tool registration;
- the authenticated agent reaches idle and emits assistant/tool events.
