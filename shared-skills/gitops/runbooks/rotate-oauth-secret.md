# Runbook: rotate a per-environment OAuth client secret

Use this when a workflow-builder social-login or piece OAuth callback reaches the
provider but the server-side code exchange fails because the stored client secret
no longer matches the provider.

The active secret root is the hub's `hub-eso` 1Password vault. Do not update the
dormant Azure Key Vault copy and assume it will reach a spoke.

## 1. Identify the exact mapping

Before changing anything, inspect the active overlay and hub mirror manifest:

```bash
rg -n "GITHUB-OAUTH-CLIENT-(ID|SECRET)" \
  packages/components/workloads/workflow-builder-system-overlays/dev/kustomization.yaml \
  packages/components/hub-management/manifests/spoke-secrets/ExternalSecret-dev-shared-secrets.yaml
```

For GitHub social login on dev, the active 1Password item/property is
`GITHUB-OAUTH-CLIENT-SECRET-DEV`, mapped through `dev-shared-secrets` to pod env
`GITHUB_CLIENT_SECRET`. Piece OAuth credentials use separate
`OAUTH-APP-...-DEV` entries. Do not rotate one when the failing callback uses the
other.

## 2. Generate the provider secret

Open the OAuth application for the target environment, verify its callback URL,
and generate a new client secret. For dev GitHub social login the callback is:

```text
https://workflow-builder-dev.tail286401.ts.net/api/v1/auth/social/github/callback
```

Keep the new value out of terminal history and chat transcripts.

## 3. Update 1Password

Update the matching item in the `hub-eso` vault. The expected value is its
`password` field because hub ExternalSecrets reference paths such as
`GITHUB-OAUTH-CLIENT-SECRET-DEV/password`. Use the 1Password UI or an authenticated
`op item edit`; verify the item name and vault before submitting.

Do not change the client ID unless the OAuth application itself changed. Do not
edit the generated hub or spoke Kubernetes Secrets by hand.

## 4. Refresh both ESO hops

The two hops are asynchronous. Refresh and confirm the hub mirror first, then the
spoke workload Secret.

```bash
# Hub 1Password -> hub spoke mirror.
kubectl --context hub-cluster -n spoke-secrets annotate externalsecret \
  dev-shared-secrets force-sync="$(date +%s)" --overwrite
kubectl --context hub-cluster -n spoke-secrets wait \
  --for=condition=Ready externalsecret/dev-shared-secrets --timeout=120s

# Hub mirror -> dev workload Secret.
kubectl --context admin@dev -n workflow-builder annotate externalsecret \
  workflow-builder-secrets force-sync="$(date +%s)" --overwrite
kubectl --context admin@dev -n workflow-builder wait \
  --for=condition=Ready externalsecret/workflow-builder-secrets --timeout=120s
```

If `admin@dev` is not installed locally, use the script-generated dev kubeconfig
from the cluster access runbook. `Ready=True` alone does not prove the new value
arrived, so compare a local SHA-256 digest without printing the secret:

```bash
read -rsp 'New OAuth secret: ' NEW_SECRET; echo
printf %s "$NEW_SECRET" | sha256sum
kubectl --context admin@dev -n workflow-builder get secret workflow-builder-secrets \
  -o jsonpath='{.data.GITHUB_CLIENT_SECRET}' | base64 -d | sha256sum
unset NEW_SECRET
```

The digests must match before the rollout. This avoids restarting a pod between
the two ESO writes and accidentally loading the old value.

## 5. Roll and verify

```bash
kubectl --context admin@dev -n workflow-builder rollout restart deploy/workflow-builder
kubectl --context admin@dev -n workflow-builder rollout status deploy/workflow-builder
```

Complete a browser login through the target hostname. Inspect the BFF logs if the
callback still fails, but never print the full client secret from pod env.

After the new credential is proven, remove obsolete provider-side client secrets.
Rotating dev does not require touching dormant staging or opt-in Ryzen.

## Failure branches

- Hub mirror does not refresh: inspect `onepassword-store` and the 1Password item
  path.
- `hub-secrets-store` is not ready on dev: repair the spoke-to-hub Tailscale ESO
  transport before retrying.
- Destination digest is old: confirm the dev overlay points at the expected
  `*-DEV` property and force the two hops again in order.
- Provider still rejects the exchange with matching digest: recheck OAuth app,
  callback URL, client ID, and whether the callback belongs to social login or a
  piece connection.

See `reference/secret-flow.md` for the complete transport and
`runbooks/access-spoke-cluster-fallback.md` for kubeconfig recovery.
