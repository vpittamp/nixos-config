# Bump a runtime image outside release pins

## Scope

Use this for dev runtime images selected from literal workflow-builder
Deployment env vars rather than `release-pins/workflow-builder-images.yaml`:

- `AGENT_RUNTIME_DEFAULT_IMAGE` (`dapr-agent-py-sandbox`)
- `AGENT_RUNTIME_BROWSER_USE_DEFAULT_IMAGE` (`browser-use-agent-sandbox`)
- `AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE` (`claude-agent-py-sandbox`)

The custom `AgentRuntime` CRD and Kopf controller are retired. Never patch an
`AgentRuntime` or look for `agent-runtime-<slug>` Deployments.

## Change

1. Confirm `ghcr.io/pittampalliorg/<image>:git-<sha>` exists.
2. Update the matching literal in
   `packages/components/workloads/workflow-builder/manifests/Deployment-workflow-builder.yaml`.
3. Validate the dev render and merge through `main`.
4. Follow the active dev Source Hydrator/Promoter lane; do not deploy Ryzen or
   dormant staging unless explicitly requested.

`kustomize.images` rewrites container image fields, not string values stored in
environment variables, which is why release-pin changes alone do not move this
runtime selection.

## Verify

```bash
kubectl --context admin@dev -n workflow-builder rollout status deploy/workflow-builder
kubectl --context admin@dev -n workflow-builder exec deploy/workflow-builder -- \
  printenv AGENT_RUNTIME_DEFAULT_IMAGE \
           AGENT_RUNTIME_BROWSER_USE_DEFAULT_IMAGE \
           AGENT_RUNTIME_CLAUDE_DEFAULT_IMAGE
```

Launch a **fresh session** and inspect the new Sandbox pod image:

```bash
kubectl --context admin@dev -n workflow-builder get sandbox,pods
kubectl --context admin@dev -n workflow-builder get pod <session-pod> \
  -o jsonpath='{.spec.containers[*].image}{"\n"}'
```

The BFF reads the runtime image at session launch. An already-running session
does not change, and retrying its spawn does not refresh bootstrap credentials
or image selection. For the static benchmark/coding pool, roll its Deployment
image separately and verify run metadata reports the expected runtime/model.

Do not live-patch child Applications or workloads as the normal fix. If the dev
Application is stuck, use the promotion/recovery runbooks and restore the
declarative path.
