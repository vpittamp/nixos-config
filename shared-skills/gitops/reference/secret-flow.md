# Secret flow: KeyVault → ESO → K8s Secret → pod env

## The chain

```
Azure KeyVault                  ExternalSecrets Operator           K8s Secret              Pod env
keyvault-thcmfmoo5oeow    →     ExternalSecret CR with        →    workflow-builder-  →    envFrom
(per-spoke entries:             refreshInterval: 1h                secrets                  (read at start)
 *-CLIENT-ID-DEV,               Pulls each remoteRef.key
 *-CLIENT-SECRET-DEV, …)        and writes to .data
                                Triggers on:
                                 - schedule (1h)
                                 - annotation force-sync=<ts>
```

## Per-spoke secret naming

Each spoke gets its own copy of every credential it needs. The `spoke-workloads` ApplicationSet template (`packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml`) patches the `workflow-builder-secrets` ExternalSecret to substitute the per-spoke KeyVault key:

| Generic env var (in pod) | KeyVault key | Notes |
|---|---|---|
| `GITHUB_CLIENT_ID` | `GITHUB-OAUTH-CLIENT-ID-{DEV,STAGING,RYZEN}` | Social login (Sign in with GitHub) |
| `GITHUB_CLIENT_SECRET` | `GITHUB-OAUTH-CLIENT-SECRET-{DEV,STAGING,RYZEN}` | Social login |
| `GOOGLE_CLIENT_ID` | `GOOGLE-OAUTH-CLIENT-ID-{DEV,STAGING}` | Social login (no ryzen entry) |
| `GOOGLE_CLIENT_SECRET` | `GOOGLE-OAUTH-CLIENT-SECRET-{DEV,STAGING}` | Social login |
| `OAUTH_APP_GITHUB_CLIENT_ID` | `OAUTH-APP-GITHUB-CLIENT-ID-{DEV,STAGING,RYZEN}` | Per-piece OAuth (different app, used by integration "Connect to GitHub" feature) |
| `OAUTH_APP_GITHUB_CLIENT_SECRET` | `OAUTH-APP-GITHUB-CLIENT-SECRET-{DEV,STAGING,RYZEN}` | Same |
| `INTERNAL_API_TOKEN` | `INTERNAL-API-TOKEN` | Shared, not per-spoke |
| `BROWSERSTATION_API_KEY` | `BROWSERSTATION-API-KEY` | Shared |
| `DAPR_POSTGRES_CONNECTION_STRING` | `WORKFLOW-BUILDER-DATABASE-URL` | Shared |
| `WORKFLOW_BUILDER_*` (many) | various | See ExternalSecret on each spoke for the full data list |

There's also a separate set for the third-party piece OAuth apps (`OAUTH_APP_NOTION_*`, `OAUTH_APP_MICROSOFT_*`, `OAUTH_APP_LINKEDIN_*`) which are typically **not** per-spoke.

## Per-spoke OAuth Apps on GitHub

Each spoke has its own OAuth App registration (because each spoke has a distinct callback URL):

| Spoke | OAuth App name (vpittamp account) | Callback URL |
|---|---|---|
| dev | `workflow-builder-dev` (id 3532146) | `https://workflow-builder-dev.tail286401.ts.net/api/v1/auth/social/github/callback` |
| staging | `workflow-builder-staging` (id 3532148) | `https://workflow-builder-staging.tail286401.ts.net/api/v1/auth/social/github/callback` |
| ryzen | (corresponding ryzen app) | `https://workflow-builder-ryzen.tail286401.ts.net/api/v1/auth/social/github/callback` |

Find them at https://github.com/settings/developers → OAuth Apps.

There are also separate "Workflow Connections (Dev/Prod/Ryzen/Staging)" apps for the per-piece OAuth (the second column above).

## Common diagnostic: `attributes.updated` mismatch

If `*-CLIENT-ID-*` and `*-CLIENT-SECRET-*` were updated more than a few minutes apart in KeyVault, someone rotated the OAuth App but only updated one half. This is the most common cause of `[OAuth] github exchange failed: Error: The client_id and/or client_secret passed are incorrect`.

```bash
az keyvault secret show --vault-name keyvault-thcmfmoo5oeow \
  --name GITHUB-OAUTH-CLIENT-ID-DEV     --query attributes.updated -o tsv
az keyvault secret show --vault-name keyvault-thcmfmoo5oeow \
  --name GITHUB-OAUTH-CLIENT-SECRET-DEV --query attributes.updated -o tsv
```

If they're hours/days apart → the secret in KeyVault doesn't match the OAuth App's current secret on GitHub. Generate a new one on GitHub and update KeyVault. See `runbooks/rotate-oauth-secret.md`.

## The ESO ↔ pod restart race condition

This bites every time it's not respected. The chain has FOUR steps and they are NOT atomic:

1. `az keyvault secret set ...`  — KeyVault updated **immediately**
2. ESO sees the change on next refresh — defaults to `refreshInterval: 1h`, but you can force with `kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite`
3. ESO writes the new value to the K8s Secret (`workflow-builder-secrets`) — happens **after** the force-sync annotation is processed, takes seconds
4. Pod reads env from K8s Secret — **only at pod start**. Existing pods see the OLD value until restart.

If you trigger the rollout (`kubectl rollout restart`) at the same moment as step 3, the new pod can race-read the K8s Secret while ESO is still writing — getting the stale value.

**The rule:** between force-sync and rollout-restart, **verify the K8s Secret head matches the new value**:

```bash
kubectl -n workflow-builder annotate externalsecret workflow-builder-secrets \
  force-sync=$(date +%s) --overwrite

# Wait until this matches the first 8 chars of what you just set in KV:
kubectl -n workflow-builder get secret workflow-builder-secrets \
  -o jsonpath='{.data.GITHUB_CLIENT_SECRET}' | base64 -d | head -c 8

# THEN restart:
kubectl -n workflow-builder rollout restart deploy/workflow-builder
```

## ExternalSecret status fields

```bash
kubectl -n workflow-builder get externalsecret workflow-builder-secrets \
  -o jsonpath='refresh: {.status.refreshTime}{"\nstate: "}{.status.conditions[0].type}={.status.conditions[0].status}{"\n"}'
```

Healthy state is `Ready=True` with a recent `refreshTime`. If `Ready=False`, ESO is failing to fetch from KeyVault — check the operator pod logs in `external-secrets` namespace.

## Image pull secrets

Separate from app secrets. Two flavours:
- `ghcr-pull-credentials` — workload-namespace ExternalSecret, written by ESO from KeyVault. Allows pods to pull from `ghcr.io/pittampalliorg/<image>` (private/public).
- `gitea-registry-credentials` (in `tekton-pipelines` ns on hub) — Tekton task auth for pushing to gitea-ryzen.
- `ghcr-push-credentials` (in `tekton-pipelines` ns on hub) — Tekton task auth for pushing to ghcr.io. Org-scoped PAT. Use this same secret for manual `skopeo copy` to ghcr.io (see `runbooks/mirror-image-gitea-to-ghcr.md`).

## Hub-side secrets cheat sheet

Most operational secrets live in `tekton-pipelines` (build pipelines) or `argocd` (cluster certs):

```bash
kubectl --kubeconfig ~/.kube/hub-config get secrets -n tekton-pipelines | \
  grep -E "ghcr|gitea|webhook"
# ghcr-push-credentials                kubernetes.io/dockerconfigjson
# gitea-registry-credentials           kubernetes.io/dockerconfigjson
# github-webhook-secret                Opaque

kubectl --kubeconfig ~/.kube/hub-config get secrets -n argocd | grep -E "cluster-|admin"
# argocd-initial-admin-secret          Opaque
# cluster-dev / cluster-staging / cluster-ryzen   Opaque (cluster registration)
```

**Treat any extracted credential as transient** — `shred -u` after use. The Crossplane spoke kubeconfigs and the ghcr-push docker config are admin-equivalent.
