# Verify in UI

Scope: a short checklist for confirming a freshly-inserted workflow is visible + runnable in the workflow-builder UI. Run this after every upsert.

## Pre-flight (before opening the browser)

```bash
# 1. The BFF pod is running (don't `pnpm dev` — it's Skaffold-synced)
kubectl -n workflow-builder get deploy/workflow-builder

# 2. The row exists with a non-NULL project_id
kubectl -n workflow-builder exec deploy/workflow-builder -- \
  psql "$DATABASE_URL" -c "SELECT id, name, project_id, engine_type, length(spec::text) AS spec_bytes FROM workflows WHERE id='<id>';"

# 3. The orchestrator can reach the BFF (peer-discovery sanity check)
kubectl -n workflow-builder logs deploy/workflow-orchestrator --tail=20 | grep -i error
```

If `project_id` is NULL, the workflow won't appear in any workspace. Backfill it before continuing (see `references/troubleshooting.md` § DB scoping).

If `spec_bytes = 0` or NULL, you only ran the POST and skipped the PUT. Run the PUT (or rerun `scripts/upsert-workflow.py`).

## Open the canvas

URL pattern: `https://workflow-builder-{cluster}.tail286401.ts.net/workspaces/<workspace-slug>/workflows/<workflow-id>` for promoted spokes; on ryzen typically `https://workflow-builder-ryzen.tail286401.ts.net/...`.

Exposure (as of PR #2319): the app is reached over a Tailscale **L4 LoadBalancer Service** (`type: LoadBalancer`, `loadBalancerClass: tailscale`, `tailscale.com/hostname` annotation — NO Let's Encrypt / Tailscale Ingress); HTTPS is terminated **in-cluster** by a per-pod nginx `tls-terminator` sidecar serving a persistent self-signed wildcard `*.tail286401.ts.net` (signed by the `tailnet-dev-ca` ClusterIssuer; CA `"PittampalliOrg Tailnet Dev CA"`). Clients must trust that CA to avoid a cert warning (nixos-config seeds it system-wide + into Chrome's NSS db). For canonical hostnames see `Service-workflow-builder-tailnet.yaml` (dev/staging, in `packages/base/manifests/tailscale-ingresses/`) and `packages/components/workloads/workflow-builder-tailnet-lb/` (ryzen) in stacks — there is no longer an `Ingress-workflow-builder.yaml`.

If a browser gets a **502 while `curl` returns 302**, the tls-terminator nginx header buffers overflowed on SvelteKit's large auth Set-Cookie headers — fixed via the sidecar ConfigMap proxy-buffer bump (PR #2327); verify HTTPS exposure with a real browser, not bare curl.

Look for:

| ✅ Good | ❌ Bad |
| --- | --- |
| Canvas shows `Start → <your tasks> → End` | Canvas is empty or only shows `Start → End` |
| Each task node shows the right slug + label | Nodes are blank or labeled `call` for everything |
| Edges follow the topological order | Edges loop or disconnect |
| Properties panel (right) shows the task's `taskConfig` | Properties panel is empty |

If the canvas is empty after a direct DB insert, the most likely cause is a `nodes`/`edges` ↔ `spec` mismatch. Either re-derive `nodes`/`edges` from the spec via the BFF Save action, or rerun the upsert script (which keeps them aligned).

## Test the trigger dialog

Click **Execute** at the top of the canvas. The dialog should render form fields matching `spec.input.schema.document.properties`.

| ✅ Good | ❌ Bad |
| --- | --- |
| Each declared property has a labeled input | Dialog says "no inputs required" but you declared some |
| Defaults pre-populate | Inputs are blank when you set defaults |
| Required fields gate the Submit button | Submit fires with empty required fields |
| `format: uri` shows a URL input; `enum` shows a dropdown | All inputs are plain strings |

If the dialog is wrong, the trigger schema probably uses the alternate placement (`spec.document['x-workflow-builder'].input.schema`) and the adapter didn't normalize. Move it to `spec.input.schema.document` (the canonical placement) and re-upsert.

## Run a smoke execution

1. Fill in trigger inputs (or accept defaults).
2. Click **Submit** in the Execute dialog.
3. UI redirects to `/workspaces/<slug>/workflows/<id>/runs/<execId>`.
4. Watch the run page:
   - Each task node turns blue (running) → green (success) or red (failed) in real time.
   - Step output panel shows live stdout from the task.
   - For `durable/run`, the agent's transcript streams in.

## Watch the cluster side

In a second terminal:

```bash
# Workflow execution row appears
kubectl -n workflow-builder exec deploy/workflow-builder -- \
  psql "$DATABASE_URL" -c "SELECT id, status, started_at FROM workflow_executions WHERE workflow_id='<id>' ORDER BY started_at DESC LIMIT 1;"

# Orchestrator logs the dispatch
kubectl -n workflow-builder logs deploy/workflow-orchestrator -f | grep -E "exec|run|error" | head -50

# For a durable/run step: a per-session agent-sandbox pod is Kueue-admitted, then starts
kubectl -n workflow-builder get workloads -w        # Kueue admission of the session workload
kubectl -n workflow-builder get sandbox             # ephemeral agent-sandbox CR(s), self-reaped on session end
# then tail the session-sandbox pod once it reaches Running:
kubectl -n workflow-builder logs <session-sandbox-pod> -c <runtime-container> -f
```

## Common discrepancies

| You see in UI | But cluster says | Diagnosis |
| --- | --- | --- |
| Run status: "running" forever | `dapr workflow get` shows no recent activity | Replay chatter — usually NOT stuck. Before intervening, confirm the per-session agent-sandbox pod reached `Running` (`kubectl get sandbox -n workflow-builder` + the pod) and the session's `updated_at` is advancing. See `references/troubleshooting.md` § Replay chatter. |
| Run failed at task N | Orchestrator log shows `KeyError` on a task output | `${ .<task>.<x> }` references something not in the actual output. Add an `output: { as: { ... } }` to task N to shape the output predictably. |
| Run failed with no error | Step output panel is empty | Look at orchestrator logs at the timestamp of the failure — parse errors get swallowed. |
| Canvas renders but Execute is greyed out | `engineType !== 'dapr'` | Only `engineType: "dapr"` is currently runnable. Re-upsert with `engineType: "dapr"`. |

## Smoke test recipe (copy-paste)

```bash
# After upsert
WF_ID="<paste from script output>"

# 1. Confirm row + project scoping
kubectl -n workflow-builder exec deploy/workflow-builder -- \
  psql "$DATABASE_URL" -c "
    SELECT id, name, engine_type, project_id, length(spec::text) AS spec_bytes
      FROM workflows WHERE id='$WF_ID';"

# 2. Watch logs while you click Execute in the UI
kubectl -n workflow-builder logs deploy/workflow-orchestrator -f --tail=10
```

If the row exists, `spec_bytes > 0`, `project_id` is not null, and the orchestrator log shows a parse-then-dispatch line, the workflow is ready to run.
