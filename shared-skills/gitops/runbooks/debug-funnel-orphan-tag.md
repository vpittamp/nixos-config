# Runbook: Debug Tailscale Funnel orphan tag (webhook → hub Tekton broken)

## Symptoms / when to use

GitHub webhook deliveries to the hub Tekton outer-loop never trigger a build. Concrete symptoms:

- `gh api repos/PittampalliOrg/workflow-builder/hooks/<id>/deliveries` shows recent deliveries with `status_code: 0` and `duration ~0.02s` (no response body received)
- No PipelineRuns on hub Tekton: `kubectl --kubeconfig ~/.kube/hub-config get pipelineruns -A --sort-by=.metadata.creationTimestamp | tail`
- Ryzen has built and committed `chore(dev-images): deploy ... to ryzen` commits on `gitea-ryzen/main` but the matching tag never appeared on ghcr.io
- `dig @1.1.1.1 tekton-hub.tail286401.ts.net` returns NXDOMAIN

The webhook path is: GitHub → Tailscale Funnel public DNS (`tekton-hub.tail286401.ts.net`) → `ts-tekton-github-triggers` operator-managed proxy pod → `el-github-outer-loop` Service → EventListener → PipelineRun. When Funnel's public DNS is missing, GitHub can't connect at all.

The almost-always cause: the proxy pod is tagged with a tag that's no longer in `policy.hujson` ("orphan tag"). Tailscale's control plane drops the funnel cap silently — the operator pod still claims `Funnel on` locally, but no public DNS gets registered.

## Diagnostic — confirm the orphan-tag pattern

```bash
# 1. Find the proxy pod
kubectl --kubeconfig ~/.kube/hub-config get pods -n tailscale | grep tekton-github
# ts-tekton-github-triggers-<suffix>-0   1/1     Running   ...

# 2. Check the device's tags vs CapMap
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale ts-tekton-github-triggers-<suffix>-0 -- \
  tailscale status --json | jq '.Self | {Tags, CapMap: (.CapMap | keys)}'

# Healthy: Tags ["tag:k8s"] (or another funnel-allowed tag), CapMap includes "funnel" + "https://tailscale.com/cap/funnel-ports?ports=..."
# Broken:  Tags ["tag:ts-hub-webhook"] (or some legacy tag), CapMap missing "funnel"

# 3. Confirm the operator pod thinks Funnel is on (it WILL even when broken — that's the gotcha)
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale ts-tekton-github-triggers-<suffix>-0 -- \
  tailscale funnel status
# Will print "Funnel on" and the upstream proxy line

# 4. Cross-check policy.hujson — is the device's Tag in the funnel grant?
grep -A 4 'Allow Funnel' /path/to/stacks/main/policy.hujson
# "target": ["tag:k8s-services", "tag:k8s", "tag:aperture", ...],
# If the device's Tag isn't in the target list, that's the orphan
```

## Fix steps — Option A: re-add the orphan tag to policy (quick, no proxy churn)

Edit `policy.hujson` in the stacks repo:

1. Add the orphan tag under `tagOwners` (so it's a valid tag again):

```hujson
"tag:ts-hub-webhook": [
  "tag:k8s-operator",
  "vpittamp@github"
]
```

2. Add it to the funnel `nodeAttrs` `target` list:

```hujson
"nodeAttrs": [
  {
    "target": ["tag:k8s-services", "tag:k8s", "tag:aperture", "tag:ts-hub-webhook"],
    "attr": ["funnel"]
  }
]
```

3. Commit + push to `origin/main`. The `Tailscale ACL GitOps` GHA (`.github/workflows/tailscale-acl.yml`) syncs to the tailnet within ~30 seconds.

4. Restart the proxy pod to refresh Funnel registration:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n tailscale delete pod ts-tekton-github-triggers-<suffix>-0
```

5. Inside the new pod, cycle funnel to force public DNS re-registration:

```bash
NEW_POD=$(kubectl --kubeconfig ~/.kube/hub-config get pods -n tailscale | grep tekton-github | awk '{print $1}')
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale $NEW_POD -- tailscale funnel --bg off
sleep 2
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale $NEW_POD -- \
  tailscale funnel --https 443 --bg http://10.111.137.150:8080
```

(The upstream IP is the `el-github-outer-loop` Service ClusterIP — get it via `kubectl get svc el-github-outer-loop -n tekton-pipelines -o jsonpath='{.spec.clusterIP}'`.)

## Fix steps — Option B: re-create the proxy with the current tag scheme (clean, disruptive)

The Tailscale operator's `PROXY_TAGS=tag:k8s` (already in funnel grant). Deleting the proxy's StatefulSet + secret causes the operator to recreate it with the current tag — but issues a new TLS cert and brings the funnel down for ~1-2 minutes. Only do this when it's safe.

```bash
# Identify the StatefulSet and its secret
kubectl --kubeconfig ~/.kube/hub-config get sts,secret -n tailscale | grep tekton-github

# Delete both — operator will recreate
kubectl --kubeconfig ~/.kube/hub-config -n tailscale delete sts ts-tekton-github-triggers-<suffix>
kubectl --kubeconfig ~/.kube/hub-config -n tailscale delete secret ts-tekton-github-triggers-<suffix>-0
```

## Verify

```bash
# Public DNS resolves
dig @1.1.1.1 tekton-hub.tail286401.ts.net | grep "^tekton-hub"
# tekton-hub.tail286401.ts.net.  300  IN  A  209.177.145.X

# CapMap on proxy pod includes funnel
kubectl --kubeconfig ~/.kube/hub-config exec -n tailscale <proxy-pod> -- \
  tailscale status --json | jq '.Self.CapMap | has("funnel")'
# true

# Trigger a redelivery from GitHub (will return 202 if EventListener accepts; the gh redelivery may
# strip X-GitHub-Event header so a PipelineRun won't actually start, but a 202 response confirms the path works)
LATEST_ID=$(gh api 'repos/PittampalliOrg/workflow-builder/hooks/<id>/deliveries?per_page=1' --jq '.[0].id')
gh api -X POST "repos/PittampalliOrg/workflow-builder/hooks/<id>/deliveries/$LATEST_ID/attempts"
sleep 5
gh api 'repos/PittampalliOrg/workflow-builder/hooks/<id>/deliveries?per_page=1' \
  --jq '.[0] | {status_code, duration}'
# {status_code: 202, duration: <small>}

# Best end-to-end test: a fresh real push to PittampalliOrg/workflow-builder. Should produce
# a new PipelineRun on hub Tekton within ~30s.
kubectl --kubeconfig ~/.kube/hub-config get pipelineruns -A --sort-by=.metadata.creationTimestamp | tail
```

## Why this happens

`policy.hujson` controls tailnet ACLs. When a tag is removed from `tagOwners` (e.g. as part of a cleanup commit consolidating to the new `tag:k8s` / `tag:k8s-services` scheme), Tailscale's control plane treats devices that still carry the removed tag as having an undefined tag and drops their grants. The operator pod doesn't notice — it caches the local serve config including `AllowFunnel: true`. From the outside, the device disappears from public DNS and connections time out.

A historical example: commit `1d3301c6` ("chore: persist local stacks changes", 2026-03-15) removed `tag:ts-hub-webhook`, `tag:ts-hub-ui`, `tag:ts-spoke-ui`, `tag:ts-ingress-proxy`, `tag:spoke-api`, `tag:spoke-ingress` all in one cleanup. Any Tailscale operator-managed proxy provisioned before that commit could have orphan tags.

## Cleanup follow-up

If you used Option A, the orphan tag is back in policy as a transitional measure. Plan to re-create the proxy with `PROXY_TAGS=tag:k8s` (current operator default) and remove the orphan tag from policy when convenient.
