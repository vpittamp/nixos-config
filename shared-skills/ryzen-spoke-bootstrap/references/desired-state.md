# Current desired state for ryzen (post-A6, May 2026)

This is the authoritative description of "what a freshly-bootstrapped ryzen cluster should look like when everything is working". Use it to sanity-check after a cluster recreate, and to understand the architecture without reading every commit.

> **AGENT-ERA NOTE (argocd-agent cutover, 2026-06):** ryzen is now an AUTONOMOUS argocd-agent —
> it runs a LOCAL ArgoCD that reconciles its own apps and an agent that dials the hub principal
> OUTBOUND over tailnet mTLS (8443). The **hub→ryzen kube-API sync material below is PRE-AGENT**
> (the `cluster-ryzen` apiserver-proxy bearer Secret, the HUB CoreDNS rewrite to `ryzen-api-egress`,
> the `tag:k8s → tag:k8s-operator` impersonate-system:masters grant) and is RETIRED for sync. The
> `cluster-ryzen` Secret is now an agent MAPPING (`server: https://argocd-agent-resource-proxy:9090?agentName=ryzen`,
> embedded mTLS, NO bearerToken). That hub→spoke kube path survives ONLY as the kube endpoint
> **Headlamp** uses. The ryzen→hub ESO transport is unaffected. Defer to the `cluster-desired-state`
> skill for the authoritative current model.

## Cluster shape

- **Talos Docker**, 3 nodes (`ryzen-controlplane-1` + `ryzen-worker-1/2`), OS-IMAGE Talos `v1.13.2`, k8s `v1.36.0`, containerd 2.2.3, subnet `10.6.0.0/24`.
- **HAS a LOCAL ArgoCD** (autonomous argocd-agent — ryzen reconciles its own apps via `root-ryzen` @ `main`), no local Tekton. **No local gitea** — ryzen uses GitHub + GHCR (the idpbuilder/gitea path is RETIRED); there is NO `gitea` namespace (verified live: ns `gitea` = NotFound).
- **Ingress is Contour + Kourier (+ Knative serving net-kourier), NOT ingress-nginx** (verified live: projectcontour + kourier-system + knative-serving pods running; zero nginx-controller pods).
- **No Azure on the spoke** — `azure-workload-identity-system` ns is empty; the only ClusterSecretStores are `argocd`, `default-namespace`, and `hub-secrets-store`.
- The local kubectl context is `admin@ryzen`; hub kubeconfig (for admin work against hub from the ryzen host) is at `~/.kube/hub-config` and `~/.kube/hub-kubeconfig` (the latter via the spoke-egress).
- Worker nodes have `stacks.io/swebench-pool=dev-benchmark` + `node-role.kubernetes.io/worker=` labels (applied automatically by bootstrap-spoke-cluster.sh).

## Component inventory

| Component | Version / Source | Notes |
|---|---|---|
| Talos | Talos `v1.13.2`, k8s `v1.36.0` | Talos-Docker, imperatively bootstrapped (NOT Crossplane) |
| cert-manager | jetstack chart `v1.14.4` | Tailscale operator dependency |
| external-secrets | chart `2.4.1` (was 0.9.13) | resolves ClusterSecretStore **`hub-secrets-store`** (kubernetes provider) over Tailscale — NOT `azure-keyvault-store`. ESO (now v2.4.1) still REQUIRES `caBundle=ISRG Root X1` on the store. Manifest is external-secrets.io/v1. |
| ~~Azure Workload Identity webhook~~ | — | NOT installed on the spoke (post-AWI-removal). As of 2026-06 the hub's secret root is **1Password** (`onepassword-store` CSS → hub-eso vault); the hub's AWI + Azure KV are DORMANT (not deleted), no longer the canonical source. |
| Tailscale operator | chart from `pkgs.tailscale.com/helmcharts`, `apiServerProxyConfig.mode=true` + `allowImpersonation=true` | `OPERATOR_HOSTNAME=ryzen-operator`, `APISERVER_PROXY=true`, exposes ryzen kube-api as device `ryzen-operator.tail286401.ts.net` |
| Contour + Kourier | ArgoCD-managed | ingress (NOT ingress-nginx); Knative serving uses net-kourier |
| local-path-provisioner | `apps/local-path-provisioner.yaml` (ArgoCD-managed) | host-path StorageClass for PVCs |
| tailnet-ca | spoke base app `packages/base/apps/tailnet-ca.yaml` → component `packages/components/tailnet-ca` (spoke-only — hub does not consume `packages/base`) | restores the shared self-signed CA into `cert-manager/tailnet-dev-ca` (ExternalSecret on `hub-secrets-store`), defines the `tailnet-dev-ca` CA `ClusterIssuer` that signs the `*.tail286401.ts.net` wildcard Certificate for the tls-terminator sidecar (PR #2319) |
| ArgoCD (HUB only) | controller `v3.4.x`, chart `9.5.x` | exec.enabled=true for web terminal |
| GitOps Promoter (HUB only) | controller `v0.30.0`, chart `0.9.2` | manages `env/hub-next → env/hub` and `env/spokes-{dev,staging}-next → env/spokes-{dev,staging}` PRs. NOTE: ryzen is NOT on the Promoter path at all — it reconciles `overlays/ryzen` @ `main` DIRECTLY (no `env/spokes-ryzen`, no source-hydrator). |

## Networking + access paths

**Two DISTINCT Tailscale paths — do not conflate:** (a) the LEGACY hub→ryzen kube path (pre-agent ArgoCD sync; now used ONLY by Headlamp — ryzen reconciles its own apps via the agent), and (b) ryzen→hub ESO secret fetch. Different devices, different CoreDNS rewrites, different clusters. Note: ArgoCD sync no longer traverses (a) — the agent dials the hub principal OUTBOUND over mTLS (8443).

| From | To | Path |
|---|---|---|
| ~~Hub `argocd-application-controller`~~ → now **Headlamp only** | ryzen kube-api | (LEGACY pre-agent sync path, now Headlamp-only) cluster Secret `server: https://ryzen-operator.tail286401.ts.net` (wire SNI = the operator's own hostname, strictly validated) → HUB CoreDNS rewrite `ryzen-operator.tail286401.ts.net → ryzen-api-egress.tailscale.svc.cluster.local` → ExternalName Service (`tailscale.com/tailnet-fqdn: ryzen-operator.tail286401.ts.net`) → operator-rendered egress pod → spoke operator apiserver-proxy. Auth = Tailscale-ACL impersonation (ACL `tag:k8s → tag:k8s-operator` impersonate system:masters). |
| ryzen argocd-agent | hub principal | OUTBOUND tailnet mTLS to the principal at `:8443` (agent dials out); ryzen's local ArgoCD reconciles the ryzen apps and pushes status to the hub pane. This is the ArgoCD control-plane path (replaces the legacy hub→ryzen row above). |
| **Ryzen ESO** (`hub-secrets-store`) | **hub kube-api** (ns `spoke-secrets`) | RYZEN CoreDNS rewrite `k8s-api-hub-ingress.tail286401.ts.net → k8s-api-hub-egress.tailscale.svc.cluster.local` → ryzen egress → standalone hub Tailscale **Ingress DEVICE** `k8s-api-hub-ingress` (NOT the k8s-api-hub ProxyGroup VIP) → hub kube-api. Auth = SA token (`external-secrets/hub-secrets-token`); ACL `tag:k8s → tag:k8s` impersonate `tailscale:spoke-secrets-reader`. `caBundle = ISRG Root X1`. |
| Hub Headlamp | ryzen kube-api | same `ryzen-api-egress` path, separate kubeconfig from initContainer |
| Browser | workflow-builder UI on ryzen | Tailscale **L4 LoadBalancer** Service (`type: LoadBalancer`, `loadBalancerClass: tailscale`, annotation `tailscale.com/hostname: workflow-builder-ryzen`, NO Let's Encrypt) → device `workflow-builder-ryzen.tail286401.ts.net` → per-pod nginx **`tls-terminator` sidecar** (terminates HTTPS with the self-signed `*.tail286401.ts.net` wildcard) → ryzen Service `workflow-builder:3000`. mcp-gateway is NO LONGER on the tailnet (in-cluster only). (PR #2319) |
| Ryzen pods | hub Postgres / ClickHouse / MLflow / Headlamp / ArgoCD | tailnet egress ExternalName Services in ryzen's `tailscale` namespace (`*-hub-egress`, `*-hub-node`) |
| Ryzen pods | dev/staging Postgres | tailnet egress Services in ryzen's `tailscale` namespace (`*-workflow-builder-postgres-egress`) |

## GitOps source-of-truth

```
GitHub PittampalliOrg/stacks
├── main                                              ← canonical for hub + dev + staging + RYZEN
├── env/hub-next  ──Promoter PR──▶  env/hub          ← what hub root-application syncs from
├── env/spokes-dev-next ──Promoter──▶ env/spokes-dev ← dev cluster source
└── env/spokes-staging-next ──Promoter──▶ env/spokes-staging

# ryzen reconciles packages/overlays/ryzen @ main DIRECTLY (live kustomize on its LOCAL
# ArgoCD) — NO inner-loop branch, NO source-hydrator, NO Promoter, NO env/spokes-ryzen.
```

- **AGENT-ERA (2026-06):** ryzen is an AUTONOMOUS agent running its OWN local ArgoCD. The `root-ryzen` app-of-apps reconciles `packages/overlays/ryzen` @ **`main`** DIRECTLY (live kustomize, applied by `enroll-ryzen-agent.sh`); the child `ryzen-*` Application CRDs live on ryzen's own `argocd` namespace, and the agent push-mirrors their status UP to the hub principal (hub ns `ryzen` — a status mirror, do NOT prune). The `inner-loop` branch and `env/spokes-ryzen` are RETIRED (deleted). PRE-AGENT, the hub rendered these CRDs in its `argocd` namespace with `destination.name: ryzen` and ryzen had no local ArgoCD — that model is retired for ryzen.

## Image registries

- All clusters pull from `ghcr.io/pittampalliorg/*`. Pre-A6 local Gitea registry on ryzen is retired.
- The `ghcr-pull-credentials` Secret is materialized into every workload namespace by ESO from KV secret `GITHUB-PAT` (NOT `GHCR-PAT` — that name doesn't exist).
- ImagePullSecret name in Pod specs: `ghcr-pull-credentials`. The `gitea-registry-creds` imagePullSecret was a dead reference (the Secret was never produced on any cluster) and was REMOVED fleet-wide from 23 manifests + 2 SAs (PR #2317) — do NOT re-add it. (`deployment/scripts/trigger-tekton-builds.sh` still uses `gitea-registry-creds` as a build-side PUSH credential — different thing, kept.)

## Secrets (post-bootstrap — hub-mirror→Tailscale transport)

The hub's secret root migrated **AWI→1Password (2026-06)**: the hub's 21 ExternalSecrets — including the `ryzen-shared-secrets` mirror — now resolve from the **`onepassword-store`** ClusterSecretStore (ESO onepasswordSDK provider → the **hub-eso** 1Password vault). The bootstrap root-of-trust is one scoped read-only 1Password Service-Account token (`hub-eso-reader`) in Secret `onepassword-sa-token` (ns external-secrets). **Azure Key Vault (`keyvault-thcmfmoo5oeow`) + AWI + the AD App + the OIDC/JWKS federation are DORMANT (not deleted).** The hub mirrors every ryzen-consumed secret into hub ns `spoke-secrets` as Secret **`ryzen-shared-secrets`** (~77 keys incl. the `*-RYZEN` OAuth overrides). Ryzen's ESO ClusterSecretStore `hub-secrets-store` reads that Secret over Tailscale and ESO on ryzen materializes the per-workload Secrets. The spoke transport is unchanged — ryzen reads the hub k8s Secret regardless of how the hub populates it, and never authenticates to Azure (or 1Password).

| Source | How it reaches ryzen |
|---|---|
| `cluster-ryzen` (hub registration) | AGENT MAPPING Secret in hub argocd ns, written by `argocd-agentctl agent create ryzen` (via `enroll-ryzen-agent.sh`) — `server: https://argocd-agent-resource-proxy:9090?agentName=ryzen`, embedded mTLS, NO bearerToken. (The pre-agent static apiserver-proxy bearer Secret `server: https://ryzen-operator...` + `bearerToken: "unused"` is RETIRED for sync; the older `ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}` ExternalSecret path was already retired.) |
| `GITHUB-PAT` | hub mirror key → `ryzen-shared-secrets` → ryzen ESO → `ghcr-pull-credentials` in all workload namespaces |
| `GITHUB-OAUTH-CLIENT-ID-RYZEN` / `-SECRET-RYZEN`, `OAUTH-APP-GITHUB-CLIENT-ID-RYZEN` / `-SECRET-RYZEN` | hub mirror → ryzen ESO. The ryzen overlay repoints `workflow-builder-secrets` data[9,10,21,22] to these `*-RYZEN` keys. |
| `OPENAI-API-KEY`, `ANTHROPIC-API-KEY`, etc. | resolved through `ryzen-shared-secrets` / `hub-secrets-store` for ryzen workloads; `mlflow-ai-gateway-secrets` is on the hub mlflow ns |
| Many others | see hub mirror `packages/components/hub-management/manifests/spoke-secrets/ExternalSecret-ryzen-shared-secrets.yaml` + the per-cluster ES repoints in `packages/overlays/ryzen/kustomization.yaml` |

## What a healthy state looks like

```bash
# All ryzen-* apps on hub Synced + Healthy
ssh vpittamp@ryzen "kubectl --kubeconfig ~/.kube/hub-kubeconfig get app -n argocd | grep '^ryzen-' | grep -v 'Synced.*Healthy'"
# expected: empty output

# Ryzen kube-api reachable from hub
ssh vpittamp@ryzen "argocd --server argocd-hub.tail286401.ts.net cluster list | grep ryzen"
# expected: ryzen ... Successful

# ClusterSecretStore Ready (the spoke uses hub-secrets-store over Tailscale — NOT azure-keyvault-store)
kubectl --context admin@ryzen get clustersecretstore hub-secrets-store
# Ready=True
kubectl --context admin@ryzen -n external-secrets get secret hub-secrets-token   # the scoped hub SA token
kubectl --context admin@ryzen get externalsecrets -A | grep -vE 'SecretSynced|Valid'  # expect empty
# Profile fit
kubectl --context admin@ryzen get pods -A | grep -iE 'contour|kourier|nginx'   # contour+kourier, ZERO nginx
kubectl --context admin@ryzen get ns gitea                                      # NotFound

# Workflow-builder UI reachable (HTTPS terminated by the in-cluster tls-terminator sidecar; -k because
# the wildcard is signed by the self-signed "PittampalliOrg Tailnet Dev CA")
curl -sk -o /dev/null -w "%{http_code}\n" https://workflow-builder-ryzen.tail286401.ts.net/
# expected: 302 (redirect to /auth/sign-in)
# NOTE: bare curl sends small headers — it can return 302 while a REAL browser gets a 502
# ("upstream sent too big header") from the sidecar's default proxy buffers. Verify with a
# browser too. See failure-modes.md "workflow-builder 502 for browsers only".

# SWE-bench can launch (BENCHMARK_ARGOCD env vars unset on ryzen workflow-builder)
ssh vpittamp@ryzen "kubectl get deploy workflow-builder -n workflow-builder -o yaml | grep BENCHMARK_ARGOCD"
# expected: empty (no env vars match)

# Worker nodes have the right labels
ssh vpittamp@ryzen "kubectl get nodes --selector=stacks.io/swebench-pool=dev-benchmark -o name | wc -l"
# expected: 2 (or N workers)
```

## Path to current state from a fresh box

1. **Pre-flight**: ensure prereqs from `SKILL.md` Step 1 — only `TS_OAUTH_*` is required. No `AZURE_*` / `az login` for a ryzen recreate.
2. **Cleanup any prior state** (if recreating): `recreate-runbook.md` covers Tailscale device cleanup (including the stale duplicate `ryzen-operator` device), kubeconfig cleanup, and the LEGACY hub-side egress repointing (now only relevant for the Headlamp kube endpoint).
3. **Bootstrap**: `bash deployment/scripts/bootstrap-spoke-cluster.sh --recreate` (in stacks repo; `--ts-acl-mode`/`--ts-host-passthrough` are vestigial). Script labels worker nodes for SWE-bench Kueue, installs cert-manager + ESO + Tailscale operator (NO AWI webhook on the spoke), pre-installs Kueue, applies the spoke-registration overlay, applies the imperative spoke-transport half (ClusterSecretStore `hub-secrets-store`, egress Service, `hub-secrets-token`, SPOKE CoreDNS rewrite), then ENROLLS the autonomous agent via `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh`.
4. **Agent enrollment** (SKILL.md Step 3): `enroll-ryzen-agent.sh` mints the agent mTLS cert, applies the `ryzen-agent-bootstrap` component (agent-autonomous bundle + `mode=autonomous` + `cluster-ryzen-local` alias + `stacks-repo-read` + cert ExternalSecrets + `root-ryzen` app-of-apps @ `main`), runs `argocd-agentctl agent create ryzen` (writes the `cluster-ryzen` agent mapping), stages the Headlamp Secret, and hard-refreshes `root-ryzen`. `register-spoke-with-hub.sh` is RETIRED.
5. **NO JWKS sync** for the ryzen path (spoke has no Azure). The hub's own secret root is 1Password now (AWI/Azure KV dormant), so JWKS-to-Azure is not in any current recreate path.
6. **Verify connectivity** (SKILL.md Step 4 checks) — `hub-secrets-store` Ready; ESes SecretSynced. (The `curl --connect-to` operator-SNI HTTP 200 check is now LEGACY — diagnostics for the Headlamp/ESO endpoint only, not the sync path.)
7. **Get content onto ryzen + (if hub-state changed) merge Promoter PR** (SKILL.md Step 5). Ryzen tracks `main` directly — commit/merge to `main`, then optionally force an immediate re-compare via `deployment/scripts/ryzen-sync.sh` (hard-refreshes `root-ryzen`). No `inner-loop` advance.
8. **Run data migrations** (SKILL.md Step 6).
9. **Restart Headlamp Deployments** so they pick up the new ryzen connection (failure-modes.md "Failed to get authentication information").

Total elapsed: ~8-10 min bootstrap + agent enrollment, plus ~5-10 min for the local ArgoCD to reconcile the ryzen apps, plus ~10 min if data migrations are needed.

## What's NOT documented here

This file is a stable-state reference. For day-to-day GitOps, see the `gitops` skill. For Skaffold inner-loop, see `skaffold-dev-loop`. For SWE-bench / workflow-builder evals, see `evaluations`. For Talos cluster manipulation outside ryzen (dev/staging Hetzner-Talos clusters), see `talos-clusters`.
