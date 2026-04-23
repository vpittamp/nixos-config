# Runbook: Rotate a per-spoke OAuth client secret

## Symptoms / when to use

User reports "Sign in with GitHub" or "Sign in with Google" fails on `https://workflow-builder-{env}.tail286401.ts.net`. Pod logs (`kubectl -n workflow-builder logs deploy/workflow-builder -c workflow-builder`) show:

```
[OAuth] github exchange failed: Error: The client_id and/or client_secret passed are incorrect.
```

The OAuth init redirect to `github.com/login/oauth/authorize?client_id=…` succeeds (GitHub recognizes the client_id), the user authorizes, GitHub redirects back with `?code=…&state=…`, but the **server-side** exchange of code → access_token fails because the secret in the pod doesn't match the secret GitHub has on file.

## Diagnostic

```bash
# 1. Compare KeyVault timestamps for ID vs SECRET. They should be within seconds of each other.
az keyvault secret show --vault-name keyvault-thcmfmoo5oeow \
  --name GITHUB-OAUTH-CLIENT-ID-DEV     --query attributes.updated -o tsv
az keyvault secret show --vault-name keyvault-thcmfmoo5oeow \
  --name GITHUB-OAUTH-CLIENT-SECRET-DEV --query attributes.updated -o tsv

# Hours/days apart → the OAuth App was rotated on GitHub but only one half was updated in KeyVault.
```

(For staging or ryzen, replace the `-DEV` suffix.)

## Fix steps

### 1. Generate a new client secret on GitHub

1. Go to https://github.com/settings/developers → OAuth Apps
2. Click the OAuth App for the broken environment:
   - dev → `workflow-builder-dev` (id 3532146)
   - staging → `workflow-builder-staging` (id 3532148)
   - ryzen → corresponding ryzen app
3. Verify the **Authorization callback URL** is `https://workflow-builder-{env}.tail286401.ts.net/api/v1/auth/social/github/callback` — fix it if not
4. Click **Generate a new client secret** (GitHub will require sudo / passkey re-auth)
5. **Copy the secret immediately** — GitHub only shows it once

### 2. Push to KeyVault

```bash
az keyvault secret set \
  --vault-name keyvault-thcmfmoo5oeow \
  --name GITHUB-OAUTH-CLIENT-SECRET-DEV \
  --value '<new secret>' \
  --output none
```

### 3. Force ESO refresh — but mind the race

The pod reads `GITHUB_CLIENT_SECRET` from the K8s Secret `workflow-builder-secrets` via `envFrom` at pod-start time. ExternalSecrets Operator (ESO) syncs KeyVault → K8s Secret on its own schedule (default `refreshInterval: 1h`). To make the rotation take effect immediately:

```bash
# Get spoke kubeconfig (see access-spoke-cluster-fallback.md)
kubectl --kubeconfig ~/.kube/hub-config get secret <spoke>-XXXXX-kubeconfig -n crossplane-system \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/<spoke>-kubeconfig
chmod 600 /tmp/<spoke>-kubeconfig

# 1. Annotate the ExternalSecret to force-sync
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  annotate externalsecret workflow-builder-secrets \
  force-sync=$(date +%s) --overwrite
```

### 4. **WAIT** for the K8s Secret to actually contain the new value before restarting

This is the step that bites if you skip it. ESO writes asynchronously; if the pod restarts at the same moment ESO is mid-write, the new pod can race-read the K8s Secret and get the OLD value. Verify the K8s Secret head matches the new value first:

```bash
# Compare to the first 8 chars of what you just pushed to KV
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  get secret workflow-builder-secrets \
  -o jsonpath='{.data.GITHUB_CLIENT_SECRET}' | base64 -d | head -c 8
echo
# If this doesn't match, wait a few seconds and re-check.
```

### 5. THEN restart the Deployment

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  rollout restart deploy/workflow-builder
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  rollout status deploy/workflow-builder
```

### 6. Verify the pod env head matches

```bash
KUBECONFIG=/tmp/<spoke>-kubeconfig kubectl -n workflow-builder \
  exec deploy/workflow-builder -c workflow-builder -- \
  sh -c 'echo "ID=$GITHUB_CLIENT_ID"; echo "SECRET_HEAD=${GITHUB_CLIENT_SECRET:0:8}"'
```

`SECRET_HEAD` should match the first 8 chars of the new secret.

### 7. Shred the kubeconfig

```bash
shred -u /tmp/<spoke>-kubeconfig
```

### 8. Browser test

Go to `https://workflow-builder-{env}.tail286401.ts.net`, click "Sign in with GitHub", complete the GitHub authorize prompt. Should land you logged in (no `?error=exchange_failed`).

### 9. (Optional cleanup) Delete old client secrets on GitHub

After verifying the new secret works, return to the OAuth App page and delete any leftover old client secrets shown alongside the new one.

## Why each spoke has its own OAuth App

A single OAuth App can only have one Authorization callback URL. Each spoke has a distinct hostname (`workflow-builder-{env}.tail286401.ts.net`), so each needs a distinct app. This also means rotating the dev secret doesn't affect staging or ryzen, and the blast radius of a leaked secret is one environment.

## Related

- `reference/secret-flow.md` — the full KV → ESO → pod chain and per-spoke key naming
- `runbooks/access-spoke-cluster-fallback.md` — how to get the spoke kubeconfig

## Same procedure for other OAuth secrets

The procedure is identical for any of the per-spoke KeyVault keys, just substitute the names:

- Google social login: `GOOGLE-OAUTH-CLIENT-ID-DEV` / `GOOGLE-OAUTH-CLIENT-SECRET-DEV` (no ryzen entry — Google social login isn't enabled on ryzen)
- GitHub OAuth piece (different from social login): `OAUTH-APP-GITHUB-CLIENT-ID-{DEV,STAGING,RYZEN}` / `-SECRET-`

The pod env names map differently (`GOOGLE_CLIENT_ID`, `OAUTH_APP_GITHUB_CLIENT_ID`, etc.) but the ESO/restart race applies the same way.
