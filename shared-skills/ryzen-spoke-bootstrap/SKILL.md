---
name: ryzen-spoke-bootstrap
description: Use this skill when creating, recreating, or repairing the ryzen local development cluster as a hub-managed spoke of the talos-hub ArgoCD. Covers the talosctl + helm + kubectl bootstrap flow (replacing the retired idpbuilder path), hub-side cluster Secret + Tailscale operator-managed egress, Azure Workload Identity JWKS sync, image source migration to ghcr.io, and the spoke-ryzen Application sync chain on hub.
---

# Ryzen Spoke Bootstrap

## What this skill covers

Bootstrap a fresh ryzen Talos Docker cluster so the hub ArgoCD (running on talos-hub at Hetzner) can register it as a spoke and apply all workloads (workflow-builder, dapr, observability, etc.) via cluster Secret + bearer token. This replaces the retired idpbuilder-based standalone-ryzen flow.

**Quick reference for the steady-state architecture**: `references/desired-state.md` — describes the component inventory, networking paths, GitOps source-of-truth, and what a healthy ryzen cluster looks like. Read this first if you're trying to understand the current system without going through the full bootstrap.

**Architecture (post-A6, May 2026):**
- Ryzen: Talos Docker cluster, no local ArgoCD, no local Gitea, no local Tekton
- Hub: sole ArgoCD instance; renders `packages/overlays/ryzen` and applies Application CRDs to its own argocd namespace, each with `destination.name: ryzen`
- Hub→ryzen: Tailscale operator-managed egress proxy bridges hub's pods to ryzen's kube-apiserver via tailnet device `ryzen-api-v3`
- Images: cluster pulls from `ghcr.io/pittampalliorg/*`; Skaffold's outer-loop also pushes to ghcr.io
- Secrets: ESO syncs from Azure Key Vault (`keyvault-thcmfmoo5oeow`) via Azure Workload Identity

## Workflow

### 1. Prerequisites check

```bash
# Required tools on the workstation
for cmd in talosctl helm kubectl docker az tailscale; do
  command -v "$cmd" >/dev/null || echo "MISSING: $cmd"
done

# Required env vars (one-time setup; see references/secrets-checklist.md)
echo "TS_OAUTH_CLIENT_ID=${TS_OAUTH_CLIENT_ID:?missing}"
echo "TS_OAUTH_CLIENT_SECRET=${TS_OAUTH_CLIENT_SECRET:?missing}"
echo "AZURE_TENANT_ID=${AZURE_TENANT_ID:?missing}"
echo "AZURE_CLIENT_ID=${AZURE_CLIENT_ID:?missing}"  # 137fbb08-... for ESO

# Azure login active
az account show --query name -o tsv  # expected: "Subscription 2"
```

If recreating an existing cluster, run the destroy + cleanup steps before bootstrap — see `references/recreate-runbook.md`.

### 2. Run the bootstrap script

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
bash deployment/scripts/bootstrap-spoke-cluster.sh
```

The script does, in order:
1. `talosctl cluster create docker --name ryzen --subnet 10.6.0.0/24 --workers 2 --memory-controlplanes 6GiB --cpus-controlplanes 4.0 --memory-workers 10GiB --cpus-workers 5.0 --exposed-ports 9443:443/tcp --config-patch ...`
2. Helm install cert-manager (jetstack 1.14.4) — Tailscale operator prereq
3. Helm install external-secrets (0.9.13)
4. Helm install azure-workload-identity-webhook (uses `AZURE_TENANT_ID`)
5. Helm install tailscale-operator (uses `TS_OAUTH_*`)
6. `kubectl apply -k packages/overlays/ryzen-spoke-registration` → ProxyGroup + ProxyClass + ServiceAccount `argocd-hub-spoke-sa` + ClusterRoleBinding (cluster-admin) + token-extractor Job

### 3. Register the cluster with hub (operator runbook)

Extract a long-lived bearer token + the cluster CA, push to Azure Key Vault, refresh hub's ESO so the `cluster-ryzen` Secret on hub gets the right credentials:

```bash
# Long-lived (8760h = 1 year) token for the cluster-admin SA
TOKEN=$(kubectl --context admin@ryzen create token argocd-hub-spoke-sa -n kube-system --duration=8760h)
CA=$(kubectl --context admin@ryzen get configmap kube-root-ca.crt -n kube-system -o jsonpath='{.data.ca\.crt}' | base64 -w 0)
az keyvault secret set --vault-name keyvault-thcmfmoo5oeow --name ARGOCD-CLUSTER-RYZEN-TOKEN --value "$TOKEN"
az keyvault secret set --vault-name keyvault-thcmfmoo5oeow --name ARGOCD-CLUSTER-RYZEN-CA --value "$CA"

# Refresh ESO so cluster-ryzen Secret on hub gets the new token
ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-kubeconfig annotate externalsecret argocd-cluster-ryzen -n argocd force-sync=$(date +%s) --overwrite"
```

### 4. Sync the Azure Workload Identity JWKS

Talos's kube-apiserver issuer key changes every time the cluster is recreated. Azure AD won't accept federated tokens until the new JWKS is uploaded to the OIDC issuer storage account:

```bash
bash /home/vpittamp/repos/PittampalliOrg/stacks/122-crawl4ai/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh
```

After this, wait 1-5 minutes for Azure AD's federated-credential cache to refresh, then verify ESO's ClusterSecretStore becomes Ready:

```bash
kubectl get clustersecretstore azure-keyvault-store -o jsonpath='{.status.conditions[0].status},{.status.conditions[0].reason}'
# expected: True,Valid (initially: False,InvalidProviderConfig — wait + retry)
```

### 5. Verify hub→ryzen connectivity

```bash
# Hub's cluster Secret should have the right URL
ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-kubeconfig get secret cluster-ryzen -n argocd -o jsonpath='{.data.server}' | base64 -d"
# expected: https://ryzen-api-egress.tailscale.svc.cluster.local

# argocd CLI should see ryzen Connected
ssh vpittamp@ryzen "argocd --server argocd-hub.tail286401.ts.net cluster list"
# expected: row for "ryzen" with ServerVersion populated
```

If the hub-side `ryzen-api-egress` Service has stale tailnet-target (pointing at an old device hostname from a previous cluster), see `references/tailscale-egress-fix.md`.

### 6. Push spoke-ryzen Application + bootstrap-merge env/hub PR

The hub's `spoke-ryzen` Application (in `packages/components/hub-management/...`) hydrates `packages/overlays/ryzen` from GitHub `inner-loop` branch to `env/spokes-ryzen`. Hub's ArgoCD then applies the rendered Application CRDs to its own argocd namespace, each with `destination.name: ryzen`. From there, hub's controller propagates workloads to ryzen via the cluster Secret.

When ryzen-related changes are committed to `main`, the GitOps Promoter creates `env/hub-next → env/hub` PRs. **These need merging** for hub to pick up changes affecting its own state (cluster Secrets, ApplicationSet definitions, etc.). If Promoter is stuck, see `references/promoter-stuck.md` — usually a `gh pr create` + merge unblocks it.

Spokes-level workloads (`packages/overlays/ryzen`) are picked up by hub's spoke-ryzen Application directly from `inner-loop` — no Promoter needed for those.

### 7. Post-bootstrap one-time data migrations

Some workloads on ryzen need data restored from dev:

```bash
# environment_image_builds table (216 rows for SWE-bench env image catalog)
kubectl --context dev exec -n workflow-builder postgresql-0 -- pg_dump -U postgres -d workflow_builder \
  -t environment_image_builds --data-only --column-inserts > /tmp/eib.sql
kubectl cp /tmp/eib.sql workflow-builder/postgresql-0:/tmp/eib.sql
kubectl exec -n workflow-builder postgresql-0 -- psql -U postgres -d workflow_builder -f /tmp/eib.sql
```

## When to use this skill

- Creating ryzen for the first time after the hub-managed migration
- Recreating ryzen (e.g., upgrading Talos version, recovering from corruption)
- Repairing the Tailscale egress when the hub-side proxy lost its target after device cleanup
- Diagnosing why hub's spoke-ryzen Application can't connect to ryzen

## When NOT to use this skill

- For day-to-day GitOps changes — those go through `inner-loop` branch + Promoter PRs (see `gitops` skill)
- For Skaffold inner-loop iteration — see `skaffold-dev-loop` skill
- For dev/staging spoke management — those are Crossplane-provisioned Hetzner Talos clusters with a different bootstrap path

## Critical files (in the stacks repo)

- `deployment/scripts/bootstrap-spoke-cluster.sh` — the canonical bootstrap entrypoint
- `packages/overlays/ryzen-spoke-registration/` — thin overlay applied during bootstrap (no Application CRDs)
- `packages/overlays/ryzen/` — full overlay reconciled by hub via spoke-ryzen
- `packages/components/profiles/local-core-ryzen/manifests/hub-spoke-registration/` — SA + CRB + token-extractor Job (referenced from spoke-registration overlay only; NOT from local-core-ryzen)
- `packages/components/hub-management/manifests/spoke-credentials/ExternalSecret-cluster-ryzen.yaml` — hub-side ES that materializes `cluster-ryzen` Secret with URL `ryzen-api-egress.tailscale.svc.cluster.local`
- `packages/components/hub-management/apps/headlamp.yaml` — contains the hub-side `ryzen-api-egress` Service with `tailscale.com/tailnet-fqdn: ryzen-api-v3.tail286401.ts.net` annotation

## Critical gotchas (failure modes documented in references/)

- **Talos signing key changes on recreate** → JWKS sync mandatory before ESO works
- **Azure AD federated-credential cache** can take 5-15 min after JWKS sync
- **Tailscale ProxyGroup creates a Service VIP, not a tailnet device** — hub-side egress with `tailscale.com/tailnet-fqdn` can't reach Service VIPs (undocumented in operator KB). The ryzen-spoke-registration overlay uses the older `tailscale.com/expose: "true"` pattern on a regular Service to register a regular tailnet device with hostname `ryzen-api-v3` — that works.
- **Stale Tailscale devices from previous clusters** can claim the `ryzen-api-v3` hostname, forcing the new operator to use `ryzen-api-v3-1`, `-2`, etc. Delete stale devices via Tailscale API before bootstrap.
- **Hub's `ryzen-api-egress` Service stays pinned to the OLD device** after recreate. Patch the annotation OR force the operator's StatefulSet pod to recreate.
- **PodSecurity admission** blocks Tailscale proxy + local-path-provisioner helper pods if their namespaces enforce `baseline:latest`. Label `tailscale` and `local-path-storage` namespaces `pod-security.kubernetes.io/enforce=privileged`.
- **GHCR_PAT username matters** — use `PittampalliOrg` (org name), not personal username, for image pulls. Source the PAT from KV secret `GITHUB-PAT` (NOT `GHCR-PAT` which doesn't exist).
- **SWE-bench sandbox pods stay Pending without worker node labels.** The Kueue ResourceFlavor `dev-benchmark` selects nodes by both `stacks.io/swebench-pool=dev-benchmark` AND `node-role.kubernetes.io/worker=""`. Pre-A6 KIND ryzen got these from kind-config kubeadm extraArgs; post-A6 Talos doesn't. `bootstrap-spoke-cluster.sh` now applies the labels after kube-api is up (commit 9871c7217); if you bootstrap with an older script, apply them manually.
- **Headlamp's per-cluster bearer tokens are baked into a kubeconfig at pod start.** The init container reads cluster Secrets ONCE and renders them into an emptyDir volume. If the ryzen cluster Secret is rotated (e.g., after recreate), restart both Headlamp Deployments (`hub-headlamp` + `hub-headlamp-embedded`) so the kubeconfig regenerates — otherwise the UI shows "Failed to get authentication information: ryzen".
- **ArgoCD 3.4 stricter ServerSideApply rejects unknown schema fields.** Examples we hit: `terminationGracePeriodSeconds` on Knative Service (gated behind a feature flag) and Tekton Pipelines/Tasks where the mutating webhook injects empty defaults (`computeResources: {}`, `metadata: {}`, etc.). Either remove the field from source or add `ignoreDifferences` with jq path expressions covering the operator-injected paths.
