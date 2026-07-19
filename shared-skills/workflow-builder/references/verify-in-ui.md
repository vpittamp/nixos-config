# Verify in UI

Scope: a short checklist for confirming a freshly saved workflow is visible and runnable in the workflow-builder UI. Run this after every save.

## Pre-flight (before opening the browser)

```bash
# 1. The dev BFF pod is running
kubectl --context dev -n workflow-builder get deploy/workflow-builder

# 2. The orchestrator can reach the BFF (peer-discovery sanity check)
kubectl --context dev -n workflow-builder logs deploy/workflow-orchestrator --tail=20 | grep -i error
```

From the authenticated MCP client, call `get_workflow_context`, then
`get_workflow` for the saved id/name. The workflow must resolve in the expected
workspace and include the saved spec. If it does not, repeat the MCP/BFF save;
do not inspect or repair the workflow table directly.

## Open the canvas

Current shared target: `https://workflow-builder-dev.tail286401.ts.net/workspaces/<workspace-slug>/workflows/<workflow-id>`. Do not switch the test to Ryzen unless the user explicitly requests Ryzen.

Exposure: the app is reached over a Tailscale **L4 LoadBalancer Service** (`type: LoadBalancer`, `loadBalancerClass: tailscale`, `tailscale.com/hostname` annotation; no Let's Encrypt/Tailscale Ingress). HTTPS is terminated in-cluster by the per-pod nginx `tls-terminator` using the persistent tailnet wildcard certificate. Clients must trust the `PittampalliOrg Tailnet Dev CA`. See the stacks workflow-builder Service/Deployment manifests for the current contract.

If a browser gets a **502 while `curl` returns 302**, the tls-terminator nginx header buffers overflowed on SvelteKit's large auth Set-Cookie headers — fixed via the sidecar ConfigMap proxy-buffer bump (PR #2327); verify HTTPS exposure with a real browser, not bare curl.

Look for:

| ✅ Good | ❌ Bad |
| --- | --- |
| Canvas shows `Start → <your tasks> → End` | Canvas is empty or only shows `Start → End` |
| Each task node shows the right slug + label | Nodes are blank or labeled `call` for everything |
| Edges follow the topological order | Edges loop or disconnect |
| Properties panel (right) shows the task's `taskConfig` | Properties panel is empty |

If the canvas is empty after an API/import save, the most likely cause is a
`nodes`/`edges` vs `spec` mismatch. Re-derive the graph through the BFF Save
action or rerun the API-only upsert helper. Do not repair the row directly.

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
# Orchestrator logs the dispatch; the run page/API is the execution projection.
kubectl --context admin@dev -n workflow-builder logs deploy/workflow-orchestrator -f | grep -E "exec|run|error" | head -50

# For a durable/run step: a per-session agent-sandbox pod is Kueue-admitted, then starts
kubectl --context admin@dev -n workflow-builder get workloads -w
kubectl --context admin@dev -n workflow-builder get sandbox
# then tail the session-sandbox pod once it reaches Running:
kubectl --context admin@dev -n workflow-builder logs <session-sandbox-pod> -c <runtime-container> -f
```

## Common discrepancies

| You see in UI | But cluster says | Diagnosis |
| --- | --- | --- |
| Run status: "running" forever | `dapr workflow get` shows no recent activity | Replay chatter — usually NOT stuck. Before intervening, confirm the per-session agent-sandbox pod reached `Running` (`kubectl get sandbox -n workflow-builder` + the pod) and the session's `updated_at` is advancing. See `references/troubleshooting.md` § Replay chatter. |
| Run failed at task N | Orchestrator log shows `KeyError` on a task output | `${ .<task>.<x> }` references something not in the actual output. Add an `output: { as: { ... } }` to task N to shape the output predictably. |
| Run failed with no error | Step output panel is empty | Look at orchestrator logs at the timestamp of the failure — parse errors get swallowed. |
| Canvas renders but Execute is greyed out | Unsupported or invalid engine/spec | Current runnable engines include `dapr` and `dynamic-script`. Validate the saved spec and use the engine matching its document shape. |

## Smoke test recipe (copy-paste)

```bash
# After `get_workflow_context` + `get_workflow` confirms the workspace-owned save,
# watch logs while you click Execute in the UI.
kubectl --context admin@dev -n workflow-builder logs deploy/workflow-orchestrator -f --tail=10
```

If the MCP/BFF read returns the saved definition and the orchestrator log shows
a parse-then-dispatch line, the workflow is ready to run.
