---
name: ryzen-spoke-bootstrap
description: Use this skill when creating, recreating, or repairing the ryzen local development cluster as a hub-managed spoke of the talos-hub ArgoCD. Covers the talosctl + helm + kubectl bootstrap flow (replacing the retired idpbuilder path), hub-side cluster Secret + Tailscale operator-managed egress, Azure Workload Identity JWKS sync, image source migration to ghcr.io, and the spoke-ryzen Application sync chain on hub.
---

# Ryzen Spoke Bootstrap

## What this skill covers

Bootstrap a fresh ryzen Talos Docker cluster so the hub ArgoCD (running on talos-hub at Hetzner) can register it as a spoke and apply all workloads (workflow-builder, dapr, observability, etc.) via cluster Secret + bearer token. This replaces the retired idpbuilder-based standalone-ryzen flow.

**Quick reference for the steady-state architecture**: `references/desired-state.md` — describes the component inventory, networking paths, GitOps source-of-truth, and what a healthy ryzen cluster looks like. Read this first if you're trying to understand the current system without going through the full bootstrap.

**Automation backlog**: `references/automation-backlog.md` — friction log from the 2026-05-28 recreate, prioritized list of script-level fixes (P0 = `register-spoke-with-hub.sh`, P0 = move `sync-jwks-to-azure.sh` into main, P0 = `cleanup-tailnet-devices.sh`, etc.). Reduces manual steps from ~10 to ~3 on next recreate.

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

### 2. Run the bootstrap script (does everything end-to-end)

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
bash deployment/scripts/bootstrap-spoke-cluster.sh                # fresh cluster
bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate     # destroy + recreate
bash deployment/scripts/bootstrap-spoke-cluster.sh --no-register  # bootstrap only, skip hub registration
```

The script does, in order:
0. (If `--recreate`) Auto-load `TS_OAUTH_*` from KV if env vars unset, then run `cleanup-tailnet-devices.sh` to delete stale devices, `talosctl cluster destroy`, and `kubectl config delete-{context,cluster,user}` for the old context
1. `talosctl cluster create docker --name ryzen --subnet 10.6.0.0/24 --workers 2 --memory-controlplanes 4GiB --memory-workers 13GiB --cpus-workers 5 --exposed-ports 9443:443/tcp --config-patch <OIDC issuer URL>`
2. Helm install cert-manager (jetstack 1.14.4)
3. Helm install external-secrets (0.9.13)
4. Helm install azure-workload-identity-webhook (uses `AZURE_TENANT_ID`)
5. Helm install tailscale-operator (chart v1.98.x: `apiServerProxyConfig.mode=true` + `allowImpersonation=true`)
6. Label `tailscale` + `local-path-storage` namespaces with `pod-security.kubernetes.io/enforce=privileged` so the operator's proxy pods + provisioner can launch
7. `kubectl apply -k packages/overlays/ryzen-spoke-registration` → SA `argocd-hub-spoke-sa` + ClusterRoleBinding (cluster-admin) + the `tailscale.com/expose: true` Service that registers `ryzen-api-v3` on the tailnet
8. Wait for `ryzen-api-v3` to appear on the tailnet
9. **Auto-invoke `register-spoke-with-hub.sh`** — see step 3 below

### 3. Hub registration (automated)

The bootstrap script calls `deployment/scripts/register-spoke-with-hub.sh` automatically at step 9. It performs (idempotently — safe to re-run on failure):

1. Verify local kube-api reachable on `admin@<cluster>` context
2. `kubectl create token argocd-hub-spoke-sa --duration=8760h` (1-year token)
3. Extract `kube-root-ca.crt`, base64-encode
4. `az keyvault secret set` for `ARGOCD-CLUSTER-<NAME>-{TOKEN,CA}`
5. `kubectl annotate externalsecret argocd-cluster-<name> force-sync=<ts>` on hub to trigger ESO refresh
6. `bash deployment/scripts/sync-jwks-to-azure.sh` to upload the new Talos signing key to the Azure storage account that backs the OIDC issuer
7. Poll `kubectl get clustersecretstore azure-keyvault-store` until Ready (timeout 30 min — first sync after JWKS update waits on Azure AD federated-credential cache)
8. `kubectl rollout restart deploy -n headlamp hub-headlamp hub-headlamp-embedded` so Headlamp re-renders its in-memory kubeconfig with the new ryzen token
9. Verify `argocd cluster list` shows the spoke as Successful

To run the registration step manually (e.g., after `--no-register` bootstrap or to re-register an existing cluster):
```bash
CLUSTER_NAME=ryzen bash deployment/scripts/register-spoke-with-hub.sh
```

### 4. Verify (Phase F in `references/desired-state.md`)

Run the checks in `references/desired-state.md` "What a healthy state looks like" section. The most important:

```bash
# All ryzen-* apps on hub Synced + Healthy (excluding known-Degraded like gitea-secretstore, nginx-tls-secret)
ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-config get app -n argocd | grep '^ryzen-' | grep -v 'Synced.*Healthy'"

# Talos worker memory limit
ssh vpittamp@ryzen "docker stats --no-stream --format '{{.Name}}: {{.MemUsage}}' | grep ryzen-worker"
# expect ~12.7GiB / 12.7GiB limits

# Kueue benchmark-fast nominal memory
ssh vpittamp@ryzen "kubectl get clusterqueue benchmark-fast -o jsonpath='{.spec.resourceGroups[0].flavors[0].resources[1].nominalQuota}'"
# expect: 9Gi
```

### 5. Push spoke-ryzen Application + bootstrap-merge env/hub PR

The hub's `spoke-ryzen` Application (in `packages/components/hub-management/...`) hydrates `packages/overlays/ryzen` from GitHub `inner-loop` branch to `env/spokes-ryzen`. Hub's ArgoCD then applies the rendered Application CRDs to its own argocd namespace, each with `destination.name: ryzen`. From there, hub's controller propagates workloads to ryzen via the cluster Secret.

When ryzen-related changes are committed to `main`, the GitOps Promoter creates `env/hub-next → env/hub` PRs. **These need merging** for hub to pick up changes affecting its own state (cluster Secrets, ApplicationSet definitions, etc.). If Promoter is stuck, see `references/promoter-stuck.md` — usually a `gh pr create` + merge unblocks it.

Spokes-level workloads (`packages/overlays/ryzen`) are picked up by hub's spoke-ryzen Application directly from `inner-loop` — no Promoter needed for those.

### 6. Post-bootstrap one-time data migrations

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
