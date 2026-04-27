# Runbook: Debug workflow-builder MCP/auth and agent bootstrap

## Symptoms

- A user adds an OAuth-backed MCP connection, sends an agent test message, and gets no response.
- The agent responds but cannot see the expected ActivePieces tools.
- A piece MCP health check works manually, but the agent runtime still has no tools.
- A Dapr agent session hangs after an AgentRuntime or MCP connection change.

## Mental model

```
workflow-builder DB
  app_connection.external_id
  mcp_connection.connection_external_id
      |
      v
activepieces-mcps reconciler
  reads enabled mcp_connection rows
  creates ap-<piece>-service KServices
  writes activepieces-mcp-catalog
      |
      v
Agent registry sync / publish
  writes AgentRuntime.spec.mcpServers
      |
      v
agent-runtime-controller
  writes DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON
      |
      v
dapr-agent-py
  sends X-Connection-External-Id to piece-mcp-server
      |
      v
piece-mcp-server
  calls workflow-builder internal decrypt API
```

The auth boundary is the connection external id. Do not move OAuth tokens into GitOps manifests, KService env, or workflow JSON. The KService may have a fallback `CONNECTION_EXTERNAL_ID`, but per-request `X-Connection-External-Id` is the correct path for user/project-specific credentials.

## Diagnostic

### 1. Confirm GitOps apps

```bash
# dev/staging are managed from hub ArgoCD.
kubectl --kubeconfig ~/.kube/hub-config -n argocd get app \
  dev-workflow-builder dev-activepieces-mcps dev-knative-serving \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision

# ryzen is local kind, but still managed by hub ArgoCD.
kubectl --context kind-ryzen -n argocd get app \
  workflow-builder activepieces-mcps knative-serving \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision
```

If `activepieces-mcps` is missing or unhealthy, fix that app before debugging the agent. It owns the generated piece MCP services and catalog.

### 2. Check the piece catalog and KServices

```bash
ctx=dev   # or kind-ryzen

kubectl --context "$ctx" -n workflow-builder get cm activepieces-mcp-catalog \
  -o jsonpath='{.data.servers\.json}' | jq .

kubectl --context "$ctx" -n workflow-builder get ksvc \
  -l app.kubernetes.io/managed-by=activepieces-mcp-reconciler \
  -o custom-columns=NAME:.metadata.name,INITIAL:.spec.template.metadata.annotations.autoscaling\\.knative\\.dev/initialScale,READY:.status.conditions[?(@.type==\"Ready\")].status,URL:.status.address.url
```

Expected piece URLs look like:

```text
http://ap-microsoft-outlook-service.workflow-builder.svc.cluster.local/mcp
```

There should be no explicit `:3100` in the caller-facing URL. Port 3100 is the container port behind Knative.

If a KService is missing, inspect the reconciler:

```bash
kubectl --context "$ctx" -n workflow-builder get cronjob activepieces-mcp-reconciler
kubectl --context "$ctx" -n workflow-builder get jobs \
  -l app.kubernetes.io/name=activepieces-mcp-reconciler --sort-by=.metadata.creationTimestamp
kubectl --context "$ctx" -n workflow-builder logs job/<latest-reconciler-job> --tail=200
```

### 3. Check DB binding

Run from a workflow-builder pod or another environment with `DATABASE_URL`:

```sql
select mc.id,
       mc.piece_name,
       mc.status,
       mc.connection_external_id,
       ac.status as app_connection_status
from mcp_connection mc
left join app_connection ac
  on ac.external_id = mc.connection_external_id
where mc.source_type = 'nimble_piece'
order by mc.updated_at desc;
```

For OAuth-backed pieces, `connection_external_id` should point to an active `app_connection.external_id`. If it is null, the reconciler may choose a fallback active connection for the KService, but the agent cannot reliably select the intended user's credential.

### 4. Check AgentRuntime bootstrap

Trigger registry sync or re-publish the agent after changing MCP connections. Then inspect the generated runtime Deployment:

```bash
slug=test1
ctx=dev

kubectl --context "$ctx" -n workflow-builder get deploy "agent-runtime-${slug}" -o json | \
  jq -r '
    .spec.template.spec.containers[]
    | select(.name=="dapr-agent-py")
    | .env[]
    | select(.name=="DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON")
    | .value
  ' | jq .
```

Expected entries include:

```json
{
  "name": "piece_microsoft-outlook",
  "transport": "streamable_http",
  "url": "http://ap-microsoft-outlook-service.workflow-builder.svc.cluster.local/mcp",
  "headers": {
    "X-Connection-External-Id": "conn_..."
  }
}
```

If the URL still has `:3100`, the AgentRuntime has stale config. Re-run registry sync from workflow-builder or re-publish the agent, then verify the Deployment rolled.

### 5. Wake the agent and read runtime logs

```bash
kubectl --context "$ctx" -n workflow-builder annotate agentruntime "agent-runtime-${slug}" \
  agents.x-k8s.io/wake="$(date +%s)" \
  agents.x-k8s.io/last-active="$(date +%s)" \
  --overwrite

kubectl --context "$ctx" -n workflow-builder logs deploy/"agent-runtime-${slug}" \
  -c dapr-agent-py --tail=250 | rg 'mcp-bootstrap|Loaded|Registered|Missing credentials|X-Connection'
```

Success looks like `[mcp-bootstrap] connected 1 server(s)` followed by tool registration. `Missing credentials` means the header/fallback connection id was absent or could not decrypt through the internal API.

## Fix patterns

- **Missing KService/catalog entry**: fix `activepieces-mcps` or the `mcp_connection` row; do not manually create permanent KServices outside GitOps.
- **Stale AgentRuntime bootstrap**: run the agent registry sync endpoint or re-publish the agent. Existing AgentRuntime CRs do not automatically refresh just because a DB row changed.
- **Legacy `:3100` URL**: normalize the URL in workflow-builder/orchestrator resolution, then refresh existing AgentRuntime CRs. Knative callers should use the KService URL without a port.
- **No OAuth credential**: create or repair the corresponding ActivePieces app connection, bind `mcp_connection.connection_external_id`, and retry. Keep credentials in `app_connection` storage and internal decrypt API flow.
- **Cold start timeout**: retry with a longer timeout before changing manifests. Generated piece MCP services intentionally use `initialScale: "0"`.

## Dapr durability checks

Durable agent sessions require the sidecar to see exactly one actor state store:

```bash
kubectl --context "$ctx" -n workflow-builder get component workflowstatestore -o yaml | rg 'name:|scopes:|workspace-runtime|workflow-orchestrator'
kubectl --context "$ctx" -n workflow-builder get component dapr-agent-py-statestore -o yaml | rg 'name:|scopes:|dapr-agent-py|agent-runtime'
```

`workflowstatestore` is for parent workflows. `dapr-agent-py-statestore` is centralized durable state for sandboxed per-agent runtimes, and the agent-runtime controller enrolls each per-agent Dapr app id into its scopes. Do not create per-agent state stores as a workaround; fix the shared Component scope.

## Verify

- `workflow-builder`, `activepieces-mcps`, and `knative-serving` are `Synced/Healthy`.
- The piece appears in `activepieces-mcp-catalog`.
- The KService is Ready and exposes `/mcp` through a no-port Knative URL.
- `DAPR_AGENT_PY_BOOTSTRAP_MCP_SERVERS_JSON` contains the piece server and `X-Connection-External-Id`.
- Runtime logs show MCP tools loaded.
- An authenticated agent session reaches `idle` and emits an assistant message or tool-use events.
