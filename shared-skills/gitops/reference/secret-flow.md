# Secret flow: 1Password -> hub mirror -> spoke ESO -> pod

Use this reference for the active hub and spoke secret path. Azure Key Vault and
Azure Workload Identity are dormant compatibility assets, not the current secret
root.

## Active chain

```text
1Password vault `hub-eso`
  -> hub ClusterSecretStore `onepassword-store`
  -> hub ExternalSecrets
  -> hub Secrets in namespace `spoke-secrets`
       (`dev-shared-secrets`, `ryzen-shared-secrets`, agent certs, tailnet CA)
  -> spoke ClusterSecretStore `hub-secrets-store`
       (ESO kubernetes provider over the Tailscale hub API path)
  -> workload ExternalSecret
  -> local Kubernetes Secret
  -> pod env / secretKeyRef at pod start
```

The hub bootstrap credential is the scoped read-only 1Password service-account
token in `external-secrets/onepassword-sa-token`. Spokes do not authenticate to
1Password or Azure. Their `hub-secrets-store` can read only the hub
`spoke-secrets` namespace through the scoped `spoke-secrets-reader` transport.

Source-of-truth manifests:

- `packages/components/hub-onepassword/ClusterSecretStore-onepassword-store.yaml`
- `packages/components/hub-management/manifests/spoke-secrets/`
- `packages/components/spoke-tailscale-secrets/manifests/spoke-transport/ClusterSecretStore-hub-secrets-store.yaml`
- `packages/components/workloads/workflow-builder-secrets/manifests/ExternalSecret-workflow-builder.yaml`
- `packages/components/workloads/workflow-builder/manifests/ExternalSecret-dapr-agent-py.yaml`

## Environment mapping

Workload manifests use `ryzen-shared-secrets` as their base remote object.
Environment overlays retarget that object and the indexed per-environment OAuth
properties. The active dev render points at `dev-shared-secrets` and properties
such as `GITHUB-OAUTH-CLIENT-ID-DEV`; Ryzen uses the corresponding Ryzen
properties. Staging mappings are retained but dormant.

Do not insert entries into the middle of
`ExternalSecret-workflow-builder.yaml`'s `spec.data`. The overlays use guarded,
index-based JSON6902 patches for environment-specific OAuth entries. Append new
entries and render the dev overlay to prove the indices still match.

Kimi follows the same path. The hub mirror exposes property `KIMI-API-KEY`, and
the Dapr agent ExternalSecret maps it to local key `KIMI_API_KEY`. Do not create
a second provider-specific credential or put the key in a ConfigMap.

## Refresh and rollout

There are two asynchronous ESO hops: 1Password -> hub mirror, then hub mirror ->
spoke Secret. Force and verify them in that order before restarting a consumer.

```bash
# Hub: materialize the changed 1Password item into the per-spoke mirror.
kubectl --context hub-cluster -n spoke-secrets annotate externalsecret \
  dev-shared-secrets force-sync="$(date +%s)" --overwrite
kubectl --context hub-cluster -n spoke-secrets get externalsecret \
  dev-shared-secrets

# Dev: materialize the hub mirror into the workload Secret.
kubectl --context admin@dev -n workflow-builder annotate externalsecret \
  workflow-builder-secrets force-sync="$(date +%s)" --overwrite
kubectl --context admin@dev -n workflow-builder get externalsecret \
  workflow-builder-secrets
```

Use the actual available kubeconfig context; do not assume `admin@dev` exists on
every workstation. Confirm both ExternalSecrets report `Ready=True` and verify a
non-secret checksum or a short, non-logged prefix of the destination value before
rolling the Deployment. Existing pods do not reread environment variables after
the Kubernetes Secret changes.

For `dapr-agent-py-secrets`, force that ExternalSecret instead of
`workflow-builder-secrets`. For image pull credentials, force the matching GHCR
ExternalSecret; they are separate from application secrets.

## Diagnostics

```bash
kubectl --context hub-cluster get clustersecretstore onepassword-store
kubectl --context hub-cluster -n spoke-secrets get externalsecret
kubectl --context admin@dev get clustersecretstore hub-secrets-store
kubectl --context admin@dev -n workflow-builder get externalsecret
```

Interpret failures by hop:

- `onepassword-store` not ready: repair the hub 1Password service-account token
  or provider reachability.
- Hub mirror not ready: inspect the item/key named by its `remoteRef`.
- `hub-secrets-store` not ready: repair the spoke-to-hub Tailscale transport,
  scoped reader token, CA, or CoreDNS rewrite.
- Workload ExternalSecret not ready: inspect its remote object/property mapping;
  do not bypass ESO by hand-editing the generated Secret.

Extracted credentials and generated admin kubeconfigs are transient sensitive
material. Avoid printing full values and remove temporary files after the
operation.
