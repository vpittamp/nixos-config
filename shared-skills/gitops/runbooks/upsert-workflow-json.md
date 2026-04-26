# Runbook: Deploy a workflow JSON spec change to dev / staging

## Symptoms / when to use

You edited `services/<agent>/<name>.workflow.json` in workflow-builder (changed `maxTurns`, prompt, `agentKwargs`, schema, etc.), pushed to `origin/main`, hub Tekton built a new workflow-builder image, and dev pulled the new image — but **the new workflow behavior didn't take effect.**

This is by design: the workflow-builder production Dockerfile copies `src/` and `drizzle/` only. `services/` is excluded. Workflow JSONs live in the postgres `workflows.spec` JSONB column on each spoke and are loaded at execution time from the DB, not the filesystem. Image rebuilds do not roll workflow spec changes.

## Diagnostic — confirm the spoke DB is stale

Use the BFF pod's `DATABASE_URL`:

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl exec -n workflow-builder deploy/workflow-builder \
  -c workflow-builder -- node -e "
  const p=require('postgres');
  const sql=p(process.env.DATABASE_URL,{ssl:false});
  sql\`select id, updated_at,
        spec->'do'->0->'<step-name>'->'with'->'maxTurns' as max,
        spec->'do'->0->'<step-name>'->'with' ? 'agentKwargs' as has_kwargs
        from workflows where id='<workflow-id>'\`
    .then(r=>{console.log(JSON.stringify(r,null,2));sql.end();});
"
```

If `updated_at` is older than your local file edit and the projected fields don't match, the spoke is stale.

## Fix steps — direct SQL UPDATE (recommended)

Copy the new JSON into the BFF pod and UPDATE the row. The script `scripts/<workflow>.mjs --user-email …` exists for this purpose but requires `services/` to be in the pod, which the production image doesn't have. Direct UPDATE is faster:

```bash
# 1. Copy the JSON into the BFF pod
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl cp \
  /home/vpittamp/repos/PittampalliOrg/workflow-builder/main/services/<agent>/<name>.workflow.json \
  workflow-builder/$(KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl get pod -n workflow-builder \
    -l app=workflow-builder -o jsonpath='{.items[0].metadata.name}'):/tmp/wf.json \
  -c workflow-builder

# 2. UPDATE the row from inside the pod
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl exec -n workflow-builder deploy/workflow-builder \
  -c workflow-builder -- node -e "
  const fs = require('fs');
  const p  = require('postgres');
  const wf = JSON.parse(fs.readFileSync('/tmp/wf.json','utf-8'));
  const sql = p(process.env.DATABASE_URL,{ssl:false});
  sql\`update workflows set spec = \${sql.json(wf.spec)},
                            nodes = \${sql.json(wf.nodes)},
                            edges = \${sql.json(wf.edges)},
                            name = \${wf.name},
                            description = \${wf.description},
                            visibility = \${wf.visibility},
                            updated_at = now()
       where id = \${wf.id}
       returning id, updated_at,
                 spec->'do'->0->'<step>'->'with'->'maxTurns' as max\`
    .then(r=>{console.log(JSON.stringify(r,null,2)); sql.end();});
"

# 3. Cleanup
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl exec -n workflow-builder deploy/workflow-builder \
  -c workflow-builder -- rm -f /tmp/wf.json
```

The columns to update are typically `spec`, `nodes`, `edges`, `name`, `description`, `visibility`. Don't touch `id`, `user_id`, `project_id`, `created_at`. Schema:

```
id, name, description, user_id, project_id, nodes (jsonb), edges (jsonb),
visibility, engine_type, dapr_workflow_name, dapr_orchestrator_url,
created_at, updated_at, spec_version, spec (jsonb), …
```

## Verify

1. **DB row updated** — re-run the diagnostic query; new `max`/`has_kwargs` values should match the file.
2. **Next execution uses new spec** — trigger a fresh execution (via internal token, see below). The orchestrator loads the spec at execution time so the new behavior applies on the very next run; no pod restart needed.
3. **Optional**: if there's a Dapr workflow conversation history mismatch error after a wholesale spec change (see gotchas), restart the workflow-orchestrator + agent-runtime deployments to clear stale durable-task state:
   ```bash
   KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl rollout restart deploy -n workflow-builder \
     workflow-orchestrator agent-runtime-<slug>
   ```

## Trigger a verification execution from inside the pod

The internal API takes `X-Internal-Token` (env `INTERNAL_API_TOKEN` is on the BFF pod). Run the request from inside the pod so the token never leaves:

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl exec -n workflow-builder deploy/workflow-builder \
  -c workflow-builder -- node -e "
  const http = require('http');
  const data = JSON.stringify({
    workflowId:'<workflow-id>',
    triggerData: { url:'https://example.com', task:'…' }
  });
  const req = http.request({
    hostname:'localhost', port:3000,
    path:'/api/internal/agent/workflows/execute',
    method:'POST',
    headers:{
      'X-Internal-Token': process.env.INTERNAL_API_TOKEN,
      'Content-Type':'application/json',
      'Content-Length': data.length
    }
  }, res => { let body=''; res.on('data',c=>body+=c); res.on('end',()=>console.log(res.statusCode, body)); });
  req.on('error', e => console.error(e.message));
  req.write(data); req.end();
"
```

Returns `{ executionId, instanceId, status:'running' }`. Poll `workflow_executions` table by `id = '<executionId>'` for `status`/`phase`/`error`.

## Why this exists

Workflow specs are versioned at the row level (one workflow row per ID). The repo files are the **source of authorship** but the runtime source of truth is the DB. There is currently no GitOps loop that propagates `services/<agent>/*.workflow.json` to spoke databases automatically. If you want a workflow spec to be deployed alongside an image rollout, you must either:

1. Add a Sync hook Job to the Argo Application that runs the upsert against `DATABASE_URL`, OR
2. Run the SQL UPDATE manually after image rollout (this runbook).

The repo files exist primarily so developers can edit JSON locally, validate it offline, and review changes in PRs. Production state lives in the DB.
