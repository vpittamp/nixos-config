---
name: devspace-quick-iteration
description: Manage PittampalliOrg DevSpace quick-iteration loops on ryzen and similar Kubernetes-backed development environments. Use when starting, rendering, debugging, or cleaning up DevSpace profiles; resolving DevSpace prompts, ImagePullBackOff, missing shared devcontainer images, ArgoCD pause/resume drift, profile-selected Deployment preflight, or workflow-builder DevSpace loops such as openshell-inner-loop and swebench-dev.
---

# DevSpace Quick Iteration

## Operating Model

Use DevSpace as a Kubernetes-backed inner loop for services that must run against the real ryzen cluster shape. Treat it as a controlled replacement of selected long-lived Deployments, not as a generic local `pnpm dev` or `uvicorn` session.

Prefer repo-owned wrapper scripts over direct `devspace dev` commands. The wrapper should own kube context, namespace, noninteractive variables, profile defaults, deployment preflight, ArgoCD pause/resume, and cleanup behavior.

For ryzen workflow-builder work, the expected context is `admin@ryzen` and the namespace is `workflow-builder`. Avoid relying on DevSpace's cached namespace or context when switching between `kind-ryzen`, `admin@ryzen`, and `default`.

## Default Workflow

1. Inspect the repo wrapper and `devspace.yaml` before changing behavior.
2. Render the selected profile noninteractively before starting DevSpace.
3. Verify every profile-selected production Deployment exists in the target namespace before any ArgoCD pause or scale-down action.
4. Start the wrapper only after render and preflight are clean.
5. If startup fails, restore ArgoCD reconciliation and production replicas for every selected app before retrying.

Use this shape when a wrapper is available:

```bash
bash scripts/devspace-dev-ryzen.sh --profile swebench-dev --render
bash scripts/devspace-dev-ryzen.sh --profile swebench-dev
```

## Profile Rules

Profile app lists must reflect live long-lived Deployments in the selected cluster. Do not include a service just because it exists in another repo, old profile, or future plan.

For workflow-builder on ryzen:

| Profile | Selected production Deployments | Use |
| --- | --- | --- |
| `openshell-inner-loop` | `workflow-builder`, `workflow-orchestrator`, `function-router` | App/orchestrator/router iteration |
| `swebench-dev` | `workflow-builder`, `workflow-orchestrator`, `function-router`, `swebench-coordinator` | SWE-bench UI, coordinator, and evaluator dispatch iteration |
| `swebench-dev-with-dapr-agent-py` | `swebench-dev` plus `dapr-agent-py` | Only for clusters where `dapr-agent-py` is a long-lived Deployment |

If a selected Deployment is missing, fail before side effects. Do not pause ArgoCD or scale down partial selections.

## Variables And Images

DevSpace variables that otherwise prompt must have explicit wrapper defaults or explicit `--var` values. The render path must complete without interactive prompts.

For ryzen shared devcontainer image pulls, use the registry that pods can pull from:

```text
gitea.cnoe.localtest.me:9443/giteaadmin
```

Common shared images:

```text
gitea.cnoe.localtest.me:9443/giteaadmin/nodejs-22-devspace:latest
gitea.cnoe.localtest.me:9443/giteaadmin/python-312-devspace:latest
```

If DevSpace reports `ImagePullBackOff`, inspect the rendered image reference first. Do not rebuild or repush until you know whether the pod is pulling from `:8443`, `:9443`, the Tailscale Gitea hostname, or another registry.

## Devspace YAML Changes

Keep `devspace.yaml` changes scoped:

- Add only environment overrides that differ from the base Deployment.
- Prefer inheriting base Deployment env and secrets.
- Keep profile-specific app lists explicit and readable.
- Keep cleanup symmetric with startup: every app paused or scaled down must be resumed and restored.
- Avoid adding broad duplicate env blocks to paper over missing runtime configuration.

## ArgoCD And Cleanup

DevSpace startup commonly pauses ArgoCD and scales down production Deployments. A failed or interrupted session can leave the cluster half-replaced. Before retrying, check both production and DevSpace replacement resources.

Typical checks:

```bash
kubectl get deployment -n workflow-builder workflow-builder workflow-orchestrator function-router swebench-coordinator
kubectl get deployment,pod -n workflow-builder -l devspace.sh/replaced=true
kubectl get application -n argocd workflow-builder workflow-orchestrator function-router swebench-coordinator \
  -o custom-columns=NAME:.metadata.name,SKIP:.metadata.annotations.argocd\\.argoproj\\.io/skip-reconcile
```

If cleanup must be manual, restore every selected app, not just the foreground service. Prefer the repo wrapper or `devspace purge` when it performs the full cleanup for the selected profile.

### ⚠️ The devspace-purge trap (memorize)

`devspace purge` (or otherwise dropping the DevSpace replacement) **reverts the service to whatever its declarative Deployment image pin says — which can be an OLD commit.** Any fix that was only file-synced into the long-lived `*-devspace-*` pod (never built into the pinned image) is **silently lost** the moment devspace is purged. Concretely: after a purge, the `workflow-builder` BFF runs the image in `active-development/manifests/workflow-builder/kustomization.yaml` (e.g. it reverted to `git-ce17229b` while the env-spec-exact fix lived only in the synced source). A fix is **not live after a purge until it is in the pinned image.**

Rule: when a fix was delivered via devspace sync and devspace is then purged (e.g. "purged devspace to let the new image be used"), do **not** assume the fix is still active. Verify the live pod's image commit and grep the built bundle before claiming it deployed:

```bash
kubectl -n workflow-builder get deploy workflow-builder -o jsonpath='{.spec.template.spec.containers[?(@.name=="workflow-builder")].image}'
# then, in the pod, confirm the change is in the built server bundle, e.g.:
kubectl -n workflow-builder exec deploy/workflow-builder -c workflow-builder -- sh -lc 'grep -rl "<signature-of-the-fix>" build .svelte-kit 2>/dev/null | head'
```

If the fix isn't in the pinned image, deliver it as an image (GHCR-pin repoint + `idpbuilder stacks sync` — see the `gitops` skill's 2026-05-19 update), not via re-syncing devspace.

## Verification Checklist

Before calling the task done:

- Render succeeds without prompts.
- Preflight reports all selected production Deployments before side effects.
- Rendered devcontainer image repositories match the live pullable ryzen registry.
- Startup reaches an active DevSpace session or the failure has been traced to a concrete pull, readiness, or app error.
- Cleanup leaves selected production Deployments ready and ArgoCD reconciliation unpaused.

Load `references/workflow-builder.md` for concrete workflow-builder commands and recovery examples.
