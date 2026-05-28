# Current desired state for ryzen (post-A6, May 2026)

This is the authoritative description of "what a freshly-bootstrapped ryzen cluster should look like when everything is working". Use it to sanity-check after a cluster recreate, and to understand the architecture without reading every commit.

## Cluster shape

- **Talos Docker**, 1 control plane + 2 workers, subnet `10.6.0.0/24`.
- **No local ArgoCD**, no local Gitea, no local Tekton.
- The local kubectl context is `admin@ryzen`; hub kubeconfig (for admin work against hub from the ryzen host) is at `~/.kube/hub-config` and `~/.kube/hub-kubeconfig` (the latter via the spoke-egress).
- Worker nodes have `stacks.io/swebench-pool=dev-benchmark` + `node-role.kubernetes.io/worker=` labels (applied automatically by bootstrap-spoke-cluster.sh).

## Component inventory

| Component | Version / Source | Notes |
|---|---|---|
| Talos | `talosctl cluster create docker` default | signing key rotates on every recreate → JWKS sync required |
| cert-manager | jetstack chart `v1.14.4` | Tailscale operator dependency |
| external-secrets | chart `0.9.13` | resolves ClusterSecretStore `azure-keyvault-store` via Azure Workload Identity |
| Azure Workload Identity webhook | chart from `azure.github.io/azure-workload-identity/charts` | uses `AZURE_TENANT_ID` |
| Tailscale operator | chart from `pkgs.tailscale.com/helmcharts`, `apiServerProxyConfig.mode=auth` | exposes ryzen kube-api as device `ryzen-api-v3.tail286401.ts.net` |
| local-path-provisioner | `apps/local-path-provisioner.yaml` (ArgoCD-managed) | host-path StorageClass for PVCs |
| ArgoCD (HUB only) | controller `v3.4.2`, chart `9.5.15` | exec.enabled=true for web terminal |
| GitOps Promoter (HUB only) | controller `v0.30.0`, chart `0.9.2` | manages `env/hub-next → env/hub` and `env/spokes-{dev,staging}-next → env/spokes-{dev,staging}` PRs |

## Networking + access paths

| From | To | Path |
|---|---|---|
| Hub `argocd-application-controller` | ryzen kube-api | ExternalName Service `ryzen-api-egress.tailscale.svc.cluster.local` → operator-rendered egress pod → tailnet device `ryzen-api-v3` |
| Hub Headlamp | ryzen kube-api | same `ryzen-api-egress` Service, separate kubeconfig from initContainer |
| Browser | workflow-builder UI on ryzen | Tailscale Ingress (class `tailscale`) → device `workflow-builder-ryzen.tail286401.ts.net` → ryzen Service `workflow-builder:3000` |
| Ryzen pods | hub Postgres / ClickHouse / MLflow / Headlamp / ArgoCD | tailnet egress ExternalName Services in ryzen's `tailscale` namespace (`*-hub-egress`, `*-hub-node`) |
| Ryzen pods | dev/staging Postgres | tailnet egress Services in ryzen's `tailscale` namespace (`*-workflow-builder-postgres-egress`) |

## GitOps source-of-truth

```
GitHub PittampalliOrg/stacks
├── main                                              ← canonical for hub + dev + staging
├── inner-loop                                        ← canonical for ryzen-only image bumps
├── env/hub-next  ──Promoter PR──▶  env/hub          ← what hub root-application syncs from
├── env/spokes-dev-next ──Promoter──▶ env/spokes-dev ← dev cluster source
├── env/spokes-staging-next ──Promoter──▶ env/spokes-staging
└── env/spokes-ryzen                                  ← hydrated from inner-loop, NO Promoter
```

- Hub's `spoke-ryzen` Application uses `sourceHydrator.drySource.targetRevision: inner-loop` and writes to `env/spokes-ryzen`.
- All `ryzen-*` Application CRDs live on **hub** in the `argocd` namespace with `destination.name: ryzen`. There are no Application CRDs on ryzen itself.

## Image registries

- All clusters pull from `ghcr.io/pittampalliorg/*`. Pre-A6 local Gitea registry on ryzen is retired.
- The `ghcr-pull-credentials` Secret is materialized into every workload namespace by ESO from KV secret `GITHUB-PAT` (NOT `GHCR-PAT` — that name doesn't exist).
- ImagePullSecret name in Pod specs: `ghcr-pull-credentials` (note: NOT `gitea-registry-creds` even though some legacy Pod specs may still reference it as a fallback).

## Secrets (post-bootstrap, all materialized by ESO)

| KV secret name | Where it lands |
|---|---|
| `ARGOCD-CLUSTER-RYZEN-TOKEN` | `cluster-ryzen` Secret on hub's argocd ns (bearer token for ArgoCD to talk to ryzen kube-api) |
| `ARGOCD-CLUSTER-RYZEN-CA` | same Secret's `caData` field |
| `GITHUB-PAT` | `ghcr-pull-credentials` in all workload namespaces |
| `GITHUB-OAUTH-CLIENT-ID-RYZEN` / `-SECRET-RYZEN` | `workflow-builder-secrets.GITHUB_CLIENT_ID/SECRET` on ryzen |
| `OAUTH-APP-GITHUB-CLIENT-ID-RYZEN` / `-SECRET-RYZEN` | same Secret's `OAUTH_APP_GITHUB_*` keys |
| `OPENAI-API-KEY`, `ANTHROPIC-API-KEY`, etc. | `mlflow-ai-gateway-secrets` on hub mlflow ns |
| Many others | see `packages/components/hub-management/manifests/spoke-credentials/` and per-component ExternalSecret manifests |

## What a healthy state looks like

```bash
# All ryzen-* apps on hub Synced + Healthy
ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-kubeconfig get app -n argocd | grep '^ryzen-' | grep -v 'Synced.*Healthy'"
# expected: empty output

# Ryzen kube-api reachable from hub
ssh vpittamp@ryzen "argocd --server argocd-hub.tail286401.ts.net cluster list | grep ryzen"
# expected: ryzen ... Successful

# ClusterSecretStore Ready
kubectl get clustersecretstore azure-keyvault-store
# STATUS=Ready

# Workflow-builder UI reachable
curl -sk -o /dev/null -w "%{http_code}\n" https://workflow-builder-ryzen.tail286401.ts.net/
# expected: 302 (redirect to /auth/sign-in)

# SWE-bench can launch (BENCHMARK_ARGOCD env vars unset on ryzen workflow-builder)
ssh vpittamp@ryzen "kubectl get deploy workflow-builder -n workflow-builder -o yaml | grep BENCHMARK_ARGOCD"
# expected: empty (no env vars match)

# Worker nodes have the right labels
ssh vpittamp@ryzen "kubectl get nodes --selector=stacks.io/swebench-pool=dev-benchmark -o name | wc -l"
# expected: 2 (or N workers)
```

## Path to current state from a fresh box

1. **Pre-flight**: ensure prereqs from `SKILL.md` Step 1, including `TS_OAUTH_*`, `AZURE_*` env vars and `az login`.
2. **Cleanup any prior state** (if recreating): `recreate-runbook.md` covers Tailscale device cleanup, Service VIP deletion, hub-side egress repointing.
3. **Bootstrap**: `bash deployment/scripts/bootstrap-spoke-cluster.sh` (in stacks repo). Script labels worker nodes for SWE-bench Kueue, installs cert-manager + ESO + AWI + Tailscale operator, applies spoke-registration overlay.
4. **Register with hub**: extract bearer token (long-lived, 1y), push to KV, refresh hub's ESO so `cluster-ryzen` Secret is populated (SKILL.md Step 3).
5. **Sync JWKS to Azure** (SKILL.md Step 4) — mandatory after every cluster create; without it ESO is broken for ~5-15min while AAD caches.
6. **Verify connectivity** (SKILL.md Step 5).
7. **Push spoke-ryzen + merge Promoter PR** (SKILL.md Step 6).
8. **Run data migrations** (SKILL.md Step 7).
9. **Restart Headlamp Deployments** so they pick up the new ryzen bearer token (failure-modes.md "Failed to get authentication information").

Total elapsed: ~20-30 min for steps 1-7, plus ~10 min if data migrations are needed.

## What's NOT documented here

This file is a stable-state reference. For day-to-day GitOps, see the `gitops` skill. For Skaffold inner-loop, see `skaffold-dev-loop`. For SWE-bench / workflow-builder evals, see `evaluations`. For Talos cluster manipulation outside ryzen (dev/staging Hetzner-Talos clusters), see `talos-clusters`.
