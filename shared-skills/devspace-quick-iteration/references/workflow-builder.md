# Workflow-Builder DevSpace Reference

## Paths

Workflow-builder repo:

```bash
cd /home/vpittamp/repos/PittampalliOrg/workflow-builder/main
```

Shared devcontainer source:

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main/devcontainers
```

## Render And Start

Render the SWE-bench profile without starting replacements:

```bash
bash scripts/devspace-dev-ryzen.sh --profile swebench-dev --render
```

Start the profile:

```bash
bash scripts/devspace-dev-ryzen.sh --profile swebench-dev
```

Use the explicit Dapr-agent profile only after confirming the cluster has a long-lived `dapr-agent-py` Deployment:

```bash
kubectl get deployment -n workflow-builder dapr-agent-py
bash scripts/devspace-dev-ryzen.sh --profile swebench-dev-with-dapr-agent-py --render
```

## Expected Ryzen Registry

Pods on ryzen should pull shared DevSpace images from:

```text
gitea.cnoe.localtest.me:9443/giteaadmin
```

Inspect before rebuilding:

```bash
skopeo inspect --tls-verify=false docker://gitea.cnoe.localtest.me:9443/giteaadmin/nodejs-22-devspace:latest
skopeo inspect --tls-verify=false docker://gitea.cnoe.localtest.me:9443/giteaadmin/python-312-devspace:latest
```

If the render shows `gitea.cnoe.localtest.me:8443` for shared devcontainers, fix the wrapper/config default before starting DevSpace. If a pod tries the Tailscale Gitea registry and Gitea returns an upload or offset error while pushing, prefer the local `:9443` registry path for this inner loop.

## Live Preflight

The wrapper should perform this before pausing ArgoCD or scaling production deployments:

```bash
kubectl get deployment -n workflow-builder workflow-builder
kubectl get deployment -n workflow-builder workflow-orchestrator
kubectl get deployment -n workflow-builder function-router
kubectl get deployment -n workflow-builder swebench-coordinator
```

For the default ryzen `swebench-dev` profile, do not require `dapr-agent-py`; it is not part of the current long-lived ryzen app set.

## Cleanup Recovery

After an interrupted DevSpace session, verify every selected app:

```bash
kubectl get deployment -n workflow-builder workflow-builder workflow-orchestrator function-router swebench-coordinator
kubectl get deployment,pod -n workflow-builder -l devspace.sh/replaced=true
kubectl get application -n argocd workflow-builder workflow-orchestrator function-router swebench-coordinator \
  -o custom-columns=NAME:.metadata.name,SKIP:.metadata.annotations.argocd\\.argoproj\\.io/skip-reconcile
```

Production Deployments should be ready, DevSpace replacement resources should be gone, and `skip-reconcile` should be empty for every selected ArgoCD app before another attempt.
