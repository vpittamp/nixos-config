# Cross-cutting architecture

The shared machinery every cluster build/recreate relies on. Per-cluster specifics
live in `hub.md`, `ryzen.md`, `dev.md`; failure modes in
`../runbooks/recovery-and-gotchas.md`.

All file paths are relative to `/home/vpittamp/repos/PittampalliOrg/stacks/main`.

---

## 1. Topology

One **hub** (Talos/Hetzner, 5 nodes, Flannel CNI, k8s v1.32.0) runs the **argocd-agent
principal** (single pane, ns `argocd`) and the central Tekton build pool. Each spoke
runs a **local ArgoCD + an agent** that dials the principal outbound over tailnet mTLS;
the hub authors/aggregates `Application`s while the spoke's local controller does the
actual reconcile. (See §3a for the control-plane semantics — managed vs autonomous.)

- **hub**: management plane (principal) + builds. 3x cpx41 control-plane + 2x ccx33
  build nodes (labeled/tainted `stacks.io/build-pool=hub`).
- **ryzen**: bare-metal Talos-in-Docker local-dev spoke on the ryzen workstation
  (3 nodes, Talos v1.13.2 / k8s v1.36.0). Imperatively bootstrapped. **Autonomous** agent.
- **dev**: disposable Hetzner Talos spoke (3 cpx41 CP + 6 cpx51 workers labeled
  `stacks.io/swebench-pool=dev-benchmark` **AND `node-role.kubernetes.io/worker=`** — both by
  `provision-spoke.sh` §8.6, which selects non-control-plane nodes via `kubectl get nodes
  -l '!node-role.kubernetes.io/control-plane'` and labels them with admin kubectl. WHY in the
  script not `machine.nodeLabels`: the `node-role.kubernetes.io/*` label is blocked from
  kubelet self-set by NodeRestriction; the SWE-bench Kueue `dev-benchmark` ResourceFlavor
  AND-matches BOTH labels, so a missing one = sandbox unschedulable). **Script-provisioned +
  agent-enrolled** — the same imperative path as hub & ryzen (Crossplane was REMOVED in Phase D;
  see §3b). **Managed** agent.

---

## 2. GitOps branch flow (the #1 operational gotcha)

```
        drySource (main)
                |  ArgoCD source-hydrator renders packages/overlays/<env>   (hub + dev/staging ONLY)
                v
        env/<env>-next         (hydrateTo)
                |  GitOps Promoter PR  (autoMerge:false on hub -> human merges)
                v
        env/<env>              (syncSource)  <-- ArgoCD actually syncs from here

   ryzen: NO hydrator/Promoter — its LOCAL ArgoCD root-ryzen reconciles
          packages/overlays/ryzen @ main DIRECTLY (live kustomize)
```

| Cluster | drySource branch | hydrateTo | syncSource (ArgoCD reads) | Promoter? |
|---|---|---|---|---|
| hub | `main` | `env/hub-next` | `env/hub` path `hub-apps/` | yes (`stacks-environments`, manual merge) |
| dev | `main` | `env/spokes-dev-next` | `env/spokes-dev` path `dev-apps` | yes |
| staging _(dormant — no cluster, 2026-06)_ | `main` | `env/spokes-staging-next` | `env/spokes-staging` | paused (PR #2436) |
| ryzen | **`main`** (reconciled directly by local ArgoCD) | — (no hydrator) | `packages/overlays/ryzen` @ `main` (live kustomize) | **no** |

> Staging has no cluster currently; `workflow-builder-release` was reduced to dev-only (PR #2436) and the outer-loop renders dev-only (PR #2437). Promotion model = ryzen (direct `main`) + dev. The staging row is kept (dormant scaffolding) for fast re-enable.

**Consequences:**
- A push to `main` reaches **hub** only after the `env/hub-next -> env/hub` Promoter
  PR is merged (autoMerge:false). It reaches **dev/staging** after their
  `env/spokes-<env>-next -> env/spokes-<env>` PR. It reaches **ryzen** as soon as
  ryzen's local ArgoCD re-compares (commit/merge to `main`; force an immediate
  re-compare with `deployment/scripts/ryzen-sync.sh`). There is no `inner-loop`
  branch (retired) and no `env/spokes-ryzen`.
- **ryzen reconciles `main` directly** — there is no hydrator on the ryzen lane, so the
  empty-`drySource.kustomize` hydrator-stall bug never applies to ryzen; a frozen ryzen
  is fixed by a `root-ryzen` hard-refresh, not an `inner-loop` advance.
- The hub source-hydrator does NOT auto hard-refresh
  (`timeout.hard.reconciliation:0s`). If the drySHA is stale, remove
  `/status/sourceHydrator/currentOperation` + `lastSuccessfulOperation` and annotate
  a hard-refresh (see `gitops` skill).

Verify branch freshness:
```bash
kubectl --context admin@ryzen -n argocd get application root-ryzen -o jsonpath='{.status.sync.revision}'  # vs origin/main
git -C /home/vpittamp/repos/PittampalliOrg/stacks/main rev-parse origin/main                              # latest main HEAD
git ls-remote origin env/hub env/spokes-dev                                                               # branches advancing
```

---

## 3a. argocd-agent control plane (v0.8.1)

The control plane is **argocd-agent v0.8.1**, not a hub-reconciles-everything model.

- **Hub = principal** (ns `argocd`). It is the single pane: `kubectl -n <agent> get
  applications` on the hub shows every spoke's apps.
- **Each spoke = a local ArgoCD + an agent** that dials the principal **OUTBOUND over
  tailnet mTLS on `:8443`** (the hub never dials INTO the spoke for ArgoCD).
- **dev = MANAGED agent.** The hub authors the `Application` objects in ns `dev`
  (the namespace == the agent name); the principal pushes them to the dev agent; dev's
  LOCAL controller reconciles. Authoring on the hub, reconcile on the spoke.
- **ryzen = AUTONOMOUS agent.** It reconciles its own apps; the hub only aggregates
  status.
- **Sync OPERATIONS run on the spoke's local controller.** The hub pane therefore shows
  sync state + health but NOT operation lifecycle — `"Unknown operation status"` on the
  hub is **architectural and benign**, not a stuck op.
- The principal manifests live in
  `packages/components/hub-management/manifests/argocd-agent-principal/`. Each spoke is
  attached via the `cluster-<spoke>` agent-mapping Secret (§3, below) — there is NO
  hub->spoke kube-API reach for ArgoCD on a managed agent.

## 3b. Crossplane (REMOVED in Phase D)

Crossplane is **no longer in the provisioning or registration path** for any cluster.
dev was the only live composite (`TalosSpokeClusterClaim-dev`); its registration role
(the group-5 `spoke-register` job that wrote the hub cluster-Secret) is **gone**. dev,
ryzen, and the hub are now **all script-provisioned + agent-enrolled** — the same
imperative path (no `TalosSpokeClusterClaim`, no Composition/group-N functions). The
`packages/components/crossplane-hetzner-talos/` manifests may still sit on disk as inert
history, but they are not wired into the dev overlay and do not register dev.

The dev provision + enroll scripts (the SAME shape as hub/ryzen) — the entry point is the
**orchestrator** `deployment/scripts/talos-hetzner/recreate-dev.sh`, which wraps data
backup/restore (`environment_image_builds` / agents / workflows) + `provision-spoke.sh` +
`bootstrap-spoke-deps.sh` + `argocd-agent/enroll-dev-agent.sh` + the verify gate. Use it as
the dev rebuild entry point. The wrapped steps:
1. `deployment/scripts/talos-hetzner/provision-spoke.sh` — Hetzner + Talos. PUBLIC ISO
   (Talos 1.12.4 amd64); k8s **1.35** (the 1.12.4 ISO REJECTS 1.36); Cilium CNI
   (`cni: none` in the machine config); disk-first boot after install. Has a `--destroy`
   mode.
2. `deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh` — cert-manager v1.14.4 +
   ESO 2.4.1 (controller-only) + Tailscale operator + the spoke->hub ESO transport
   (§4). Also seeds privileged namespaces, but that is now a **REDUNDANT backstop**:
   privileged PodSecurity is PRIMARILY declarative — `managedNamespaceMetadata` on the
   `CreateNamespace` Helm apps + privileged-labelled `Namespace` manifests (PR #2359).
3. `deployment/scripts/argocd-agent/enroll-dev-agent.sh` — the managed-agent enroll:
   mint the agent mTLS cert on the hub and deliver it via ESO; create the `cluster-dev`
   agent-mapping Secret (`?agentName=dev`); create the `AppProject`; create the
   principal-egress Service; add the CoreDNS principal rewrite; and stage the hub
   Headlamp read SA Secret (§7a).

> **Recreate hardening (PR #2395).** Four hands-off-recreate fixes: (1)
> `bootstrap-spoke-cluster.sh` self-defaults `TS_OPERATOR_CHART_VERSION` (it's
> STANDALONE — does not source `lib/common.sh` where the 1.96.5 pin lives — so the
> var was unbound under `set -u` and aborted ryzen AFTER destroy); (2) a repo-server
> cold-start hard-refresh of `root-ryzen` after the local repo-server is Available
> (`enroll-ryzen-agent.sh` step 6b + `bootstrap-spoke-cluster.sh` step 10) to clear the
> ~5min ComparisonError stall; (3) `enroll-{dev,ryzen}-agent.sh` step 5b restarts the hub
> Headlamp Deployments after staging the read Secret (§7a) so its init-container rebuilds
> the kubeconfig against the new endpoint; (4) `provision-spoke.sh --destroy` deletes
> Hetzner servers in parallel (~156s -> ~20s). Full detail in
> `runbooks/recovery-and-gotchas.md`.

## 3. Contract 1 — the argocd cluster-Secret (agent mapping)

Post-cutover, the `cluster-<spoke>` Secret in ns `argocd` is an **agent MAPPING** to the
in-cluster resource-proxy, NOT a direct server endpoint + bearer token:

```
server:   https://argocd-agent-resource-proxy:9090?agentName=<spoke>
tlsClientConfig: embedded mTLS certData / keyData / caData    # NO bearerToken
```

This replaced the old direct-server + bearerToken cluster-Secret. The principal routes
to the right agent by the `agentName` query param; the embedded mTLS is the agent
client cert. (Headlamp can NOT use this Secret to reach the spoke — it carries no
bearerToken — so Headlamp gets its own dedicated read Secret; see §7a.)

It still carries the appset-driver labels/annotations:

- Labels: `argocd.argoproj.io/secret-type=cluster`, `stacks.io/hub-managed=true`,
  `stacks.io/cluster-role=spoke`, `stacks.io/platform=talos`. Add
  `workload.stacks.io/workflow-builder=true` to make the workloads-appset generate a
  `spoke-<name>-workflow-builder` app (dev/staging do; **ryzen intentionally omits
  it** — its overlay composes workflow-builder-system directly).
- Annotations: `spoke-cluster=<name>`, `stacks.io/source-branch=<branch>`
  (dev/staging default `main`; ryzen is NOT driven by this appset so the annotation
  is moot for it), `stacks.io/auth-mode=<mode>`.

How each cluster supplies it:
- **dev**: `deployment/scripts/argocd-agent/enroll-dev-agent.sh` mints the agent mTLS
  cert (delivered via ESO) and creates the `cluster-dev` resource-proxy mapping
  (`server: https://argocd-agent-resource-proxy:9090?agentName=dev`, embedded
  certData/keyData/caData, **no bearerToken**). This replaced the old group-5
  spoke-register job + `ExternalSecret-cluster-talos.yaml` direct-IP+token Secret.
- **ryzen** (AUTONOMOUS agent): `cluster-ryzen` is the argocd-agent MAPPING
  (`server: https://argocd-agent-resource-proxy:9090?agentName=ryzen`, embedded mTLS,
  **no bearerToken**), written by `argocd-agentctl agent create ryzen` from
  `deployment/scripts/argocd-agent/enroll-ryzen-agent.sh` (invoked by
  `bootstrap-spoke-cluster.sh --recreate`). `ExternalSecret-cluster-ryzen.yaml`
  (materializing `server: https://ryzen.tail286401.ts.net:6443` from KV
  `ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}`, `insecure:false` + `caData`, real SA `bearerToken`)
  is now **VESTIGIAL — used ONLY by Headlamp** (§7a), not by ArgoCD sync (the agent
  reconciles locally and dials the principal outbound, §3a). The old static
  `Secret-cluster-ryzen.yaml` was DELETED (PR #2308); the ryzen host TCP passthrough (§5)
  remains the Headlamp/break-glass kube endpoint.

The **spoke-clusters-appset** (cluster generator,
`packages/components/hub-spoke-appsets/apps/spoke-clusters-appset.yaml`) templates a
`spoke-<name>` Application:
```yaml
targetRevision: '{{- $sb := index .metadata.annotations "stacks.io/source-branch" -}}{{- if $sb -}}{{ $sb }}{{- else -}}main{{- end -}}'
syncSource:  { targetBranch: 'env/spokes-{{index .metadata.annotations "spoke-cluster"}}' }
hydrateTo:   { targetBranch: '<...>-next for dev/staging, else env/spokes-<name>' }
```
> GOTCHA: a SECOND copy at `packages/components/hub-base/apps/spoke-clusters-appset.yaml`
> hardcodes `targetRevision: main` and has the buggy empty `kustomize: {}`
> (hydrator-stall trap). The hub uses the **hub-spoke-appsets** copy (referenced by
> `packages/overlays/hub/kustomization.yaml`). Edit that one, not hub-base's.
>
> NOTE: this appset drives **dev/staging only**. **ryzen is AUTONOMOUS** — its own
> local ArgoCD runs a `root-ryzen` app-of-apps (from the `ryzen-agent-bootstrap`
> component, applied by `enroll-ryzen-agent.sh`) that reconciles `packages/overlays/ryzen`
> @ `main` directly. The hub neither hydrates nor renders ryzen's apps; it only sees a
> push-mirrored status in ns `ryzen`.

---

## 4. Contract 2 — hub-canonical -> Tailscale secret transport

The hub stays canonical via **1Password** (`onepassword-store` ClusterSecretStore, ESO
`onepasswordSDK` provider -> the `hub-eso` vault) since the 2026-06 AWI->1Password
migration. Azure KV `keyvault-thcmfmoo5oeow` + Workload Identity is now DORMANT (not
deleted). Spokes are UNAFFECTED — they read the hub-mirrored Secrets via the ESO
kubernetes-provider `hub-secrets-store` over Tailscale regardless of how the hub
populates them. Contract spec: `packages/components/spoke-tailscale-secrets/CONTRACT.md`.

**Hub side** (GitOps, `packages/components/hub-management/manifests/spoke-secrets/`):
- `Namespace-spoke-secrets.yaml`.
- `ExternalSecret-<cluster>-shared-secrets.yaml` — mirrors every secret the
  cluster consumes from `onepassword-store` into Secret `<cluster>-shared-secrets`
  (dev ~79-80 keys, ryzen ~77 keys, incl. `*-DEV` / `*-RYZEN` OAuth overrides).
- `RBAC-spoke-secrets-reader.yaml` — dual-path: ServiceAccount `spoke-secrets-reader`
  (bearer-token, the active standalone-Ingress path) AND Group
  `tailscale:spoke-secrets-reader` (impersonation, ProxyGroup path). Both scoped to
  get/list/watch secrets in `spoke-secrets` only + cluster-wide create on
  selfsubjectrules/accessreviews (ESO store validation, else NotReady).
- `Ingress-k8s-api-hub-ingress.yaml` — standalone Tailscale Ingress **device**
  `k8s-api-hub-ingress` (ns default, `defaultBackend kubernetes:443`, LE cert).
  Chosen over the ProxyGroup VIPService because the VIP route never propagates into
  a spoke egress netmap; the standalone device does.

**Spoke side**
(`packages/components/spoke-tailscale-secrets/manifests/spoke-transport/`):
- `ClusterSecretStore-hub-secrets-store.yaml` — ESO kubernetes provider, server
  `https://k8s-api-hub-ingress.tail286401.ts.net`, **`caBundle` hard-coded to ISRG
  Root X1** (REQUIRED — the hub Ingress device's LE serving cert chains to ISRG Root
  X1; still required on ESO v2.4.1, validated), bearerToken = SA token minted onto
  the spoke as Secret `external-secrets/hub-secrets-token` (key `token`). The manifest
  is `apiVersion: external-secrets.io/v1` (fleet migrated off v1beta1 2026-05-30;
  see `runbooks/recovery-and-gotchas.md` §L).
- `Service-k8s-api-hub-egress.yaml` — ExternalName egress (operator rewrites
  `.spec.externalName` at runtime; the `dev-spoke-transport` app shows this Service
  permanently OutOfSync/Healthy — EXPECTED, do not chase).
- **Spoke CoreDNS rewrite** (re-applied every recreate — Talos resets the Corefile):
  `rewrite name exact k8s-api-hub-ingress.tail286401.ts.net k8s-api-hub-egress.tailscale.svc.cluster.local`
  after the `ready` plugin line, then rollout-restart coredns.

Delivery differs by cluster:
- **dev/staging**: GitOps via `packages/overlays/dev` listing
  `components: [../../components/spoke-tailscale-secrets]` (the `spoke-transport` App).
- **ryzen**: IMPERATIVE — `packages/overlays/ryzen` does NOT list
  `spoke-tailscale-secrets`; the static half is applied by
  `deployment/scripts/lib/spoke-transport-bootstrap.sh` (invoked from
  `bootstrap-spoke-cluster.sh`) using `deployment/manifests/spoke-transport/`.

ACL grants (`policy.hujson`):
- ryzen->hub ESO read: `src tag:k8s -> dst tag:k8s impersonate.groups=[tailscale:spoke-secrets-reader]`.
- hub->ryzen ArgoCD: now plain tailnet TCP to the ryzen host serve (`tag:k8s -> tag:k8s`,
  port 6443); the SA bearer token (not impersonation) authenticates. The legacy
  `tag:k8s -> tag:k8s-operator app tailscale.com/cap/kubernetes
  impersonate.groups=[system:masters]` grant only applies to the deprecated `--ts-acl-mode`
  operator-proxy path (§5).

---

## 5. hub -> spoke connectivity (ryzen = Tailscale host TCP passthrough)

**dev needs NO hub->spoke kube-API reach for ArgoCD.** dev is a MANAGED argocd-agent
(§3a): its agent dials the principal OUTBOUND (gRPC mTLS, `:8443`) and reconciles
locally, so the `cluster-dev` Secret is the resource-proxy agent mapping (§3), not a
server endpoint. The dev cluster's **direct public IP** `https://<ip>:6443` + a
read-only SA token is used ONLY by **Headlamp** (the hub dashboard, §7a), not by ArgoCD.

ryzen reaches its Talos kube-apiserver **DIRECTLY over Tailscale via the ryzen HOST
device** (`ryzen.tail286401.ts.net`, `100.96.102.1`, `tag:k8s`) running
`tailscale serve --bg --tcp=6443` as a **raw TCP passthrough** to the Talos apiserver.
This is the CANONICAL, durable path — it drops the Tailscale operator apiserver-proxy
(and its per-hostname Let's Encrypt cert) entirely. No SNI workaround.

- **Host serve.** nixos-config `services.tailscaleK8sApiserver` defines a
  `tailscale-serve-k8s-apiserver` oneshot unit that auto-discovers the Talos-in-Docker
  apiserver host port and runs `tailscale serve --bg --tcp=6443`. The stacks bootstrap
  restarts this unit after each cluster create (Docker re-maps the port).
- **End-to-end TLS, no termination.** Raw TCP passthrough does NOT terminate TLS, so
  the **Talos apiserver's own serving cert reaches the hub end-to-end** and the hub does
  a **FULL TLS verify (`insecure:false`)** against the Talos CA. The apiserver cert
  carries `cluster.apiServer.certSANs: [ryzen.tail286401.ts.net, 100.96.102.1]`
  (added by the bootstrap `--config-patch`). No `serverName` / no SNI hack.
- **Auth = per-recreate ServiceAccount bearer token (Headlamp/break-glass only).** An SA
  token + Talos CA are minted into KV (`ARGOCD-CLUSTER-RYZEN-{TOKEN,CA}`); the
  `ExternalSecret-cluster-ryzen.yaml` materializes a Headlamp-only Secret: `server:
  https://ryzen.tail286401.ts.net:6443`, `insecure:false` + `caData`, `bearerToken`.
  This is NO LONGER ArgoCD's path — ArgoCD reaches ryzen via the argocd-agent mapping
  (§3). The old `register-spoke-with-hub.sh` is **RETIRED and no longer called** by
  `bootstrap-spoke-cluster.sh`; the `--ts-acl-mode` / `--ts-host-passthrough` flags are
  **VESTIGIAL** (parsed for compat, ignored). The static `Secret-cluster-ryzen.yaml` was
  deleted (PR #2308).
- **Hub egress + CoreDNS.** `ryzen-api-egress` ExternalName Service (ns `tailscale`,
  annotation `tailscale.com/tailnet-fqdn: ryzen.tail286401.ts.net`, port `6443`) is
  defined inline in `packages/components/hub-management/apps/headlamp.yaml`
  (extraManifests). A self-healing hub CoreDNS rewrite
  `ryzen.tail286401.ts.net -> ryzen-api-egress.tailscale.svc.cluster.local`
  (maintained by `CronJob-coredns-spoke-rewrites`) routes the name to the in-cluster egress.

**WHY this replaced the operator apiserver-proxy** (the operator's per-hostname Let's
Encrypt cert + recreate churn -> LE rate-limit -> 0-healthy fleet): the full
cert-avoidance rationale, the three historical cert incidents, and the current
LE-free design (host passthrough, tailnet LoadBalancer Services, per-cluster operator
hostname, the single stable hub-Ingress LE cert, stale-device cleanup) are CANONICAL in
`references/tailscale-and-certs.md`. PRs #2305 / #2307.

Verify by confirming the materialized cluster-Secret `server` and ryzen app health:
```bash
kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret cluster-ryzen \
  -o jsonpath='{.data.server}' | base64 -d    # https://ryzen.tail286401.ts.net:6443
# optional full verify (real TLS, no --insecure):
kubectl --server=https://ryzen.tail286401.ts.net:6443 \
  --certificate-authority=<Talos CA> --token=<SA token> get nodes
```
The old SNI `curl --connect-to ... :443` check is obsolete.

> LEGACY: `--ts-acl-mode` (operator apiserver-proxy + impersonation +
> `OPERATOR_HOSTNAME=ryzen-operator`) still exists for other Tailscale-proxy spokes but is
> **deprecated for ryzen**. dev/staging use the direct public IP, not the proxy.

---

## 6. Per-cluster ExternalSecret parameterization

Shared workload manifests hardcode `remoteRef.key=ryzen-shared-secrets`. Each
non-ryzen cluster must re-point its workload ExternalSecrets onto its OWN mirror:

- **dev** (and staging): `scripts/gitops/render-workflow-builder-release-overlays.sh`
  loops dev+staging, reads release-pins
  `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml`,
  and writes `packages/components/workloads/workflow-builder-system-overlays/<cluster>/kustomization.yaml`.
  All dev-specific repoints are GATED `[ "${cluster}" = "dev" ]` so staging stays
  byte-identical. Helpers:
  - `emit_es_key_repoint <es> <indices>` — key-only swap to `dev-shared-secrets`.
  - `emit_es_store_repoint <es> <orig-key>` — switch store->`hub-secrets-store`,
    key->`dev-shared-secrets`, add `property=<orig-key>` (for ESes retired off azure
    like `github-clone-credentials`, `gitea-registry-credentials`).
  - `emit_oauth_op` — `workflow-builder-secrets` OAuth -> `*-DEV` via property.
  Regenerate after any release-pin/ES change; CI uses `--check`. **Parameterized for new envs**
  (2026-06): the env loop is `${WFB_RENDER_ENVS:-dev staging}` and `cluster_upper` is derived with
  `tr` — adding an env = add its name + the principal `allowed-namespaces` + the spoke-cluster
  annotation; dev/staging output stays byte-identical.
  - **Managed-agent namespace delivery** (the fix that made wfb actually reach the dev managed
    agent, `reference_dev_managed_agent_wfb_delivery`): the principal only pushes Applications in
    `allowed-namespaces=<spoke>` (hub ns `dev`), but the base workflow-builder Application manifests
    hardcode `metadata.namespace: argocd`. The render-script now adds `op: add /metadata/namespace
    value: ${cluster}` to the global Application patch, AND the bridge `spoke-workloads-appset`
    `destination.namespace` is `{{index .metadata.annotations "spoke-cluster"}}` (was `argocd`). Both
    are required (the child manifest's explicit namespace overrides the parent destNs). The workload
    Service destination stays `{name:<cluster>, namespace: workflow-builder}` — only the Application
    OBJECT's namespace moves to the spoke pane.
  - **`workflow-builder-secrets` is its OWN ArgoCD Application** (`reference_argocd_es_array_add_drop`):
    split out of the workload app into `Application-workflow-builder-secrets.yaml` WITHOUT
    `RespectIgnoreDifferences`. WHY: appending a `.spec.data` key to that ExternalSecret left ArgoCD
    stuck OutOfSync forever (upstream argo-cd #11876/#25284 — `RespectIgnoreDifferences` + the global
    array-`[]` `jqPathExpressions` strips the appended element before apply). The ES has no
    runtime-managed fields so it never needed the syncOption; `deletionPolicy: Retain` keeps the
    materialized Secret during the move. The per-spoke OAuth repoints moved with it.
- **ryzen**: re-pointed inline in `packages/overlays/ryzen/kustomization.yaml`:
  - `workflow-builder-secrets` data[9,10,21,22] -> `*-RYZEN` OAuth keys via op:test+op:replace.
  - `github-clone-credentials` + `gitea-registry-credentials` -> `hub-secrets-store`,
    key `ryzen-shared-secrets`, `/property` added.

---

## 7. Contract 3 — web exposure + persistent self-signed CA

workflow-builder is reachable at `https://workflow-builder-{dev,ryzen,staging}.tail286401.ts.net`
over a **Tailscale L4 LoadBalancer**, with HTTPS terminated **in-cluster** by a per-pod
nginx `tls-terminator` sidecar serving a **persistent self-signed `*.tail286401.ts.net`
wildcard**. NO Let's Encrypt, NO Tailscale Ingress. PR #2319.

> **Why this replaced the old LE Tailscale Ingress** (per-hostname Let's Encrypt cert ->
> recreate churn -> LE 5-certs/168h limit -> 429 -> unreachable; the dev/staging overlays
> now `$patch:delete` the old workflow-builder/mcp-gateway Tailscale Ingresses; ryzen's
> brief plain-HTTP LB, PRs #2314/#2316, was also superseded): the full cert-avoidance
> rationale is CANONICAL in `references/tailscale-and-certs.md`. The mechanism (chain,
> CA, sidecar, LB) below stays here.

The end-to-end chain:

```
Azure KV  TAILNET-DEV-CA-CRT / TAILNET-DEV-CA-KEY   ("PittampalliOrg Tailnet Dev CA", 10-yr, offline-generated once)
        |  hub ExternalSecret-tailnet-ca.yaml  (CLUSTER-NEUTRAL mirror)
        v
hub ns spoke-secrets  Secret `tailnet-ca`           (namespace-wide spoke-secrets-reader Role -> every spoke reads the SAME key)
        |  spoke ExternalSecret over hub-secrets-store (Contract 2 transport)
        v
spoke cert-manager  Secret `tailnet-dev-ca`         (CA restored on the spoke)
        |  CA ClusterIssuer `tailnet-dev-ca`
        v
`*.tail286401.ts.net` wildcard Certificate          (in the workflow-builder ns)
        |  mounted by the tls-terminator nginx sidecar
        v
Tailscale L4 LoadBalancer Service -> sidecar :443 (HTTPS) -> workflow-builder
```

**Pieces:**
- **CA in KV.** `TAILNET-DEV-CA-CRT` / `TAILNET-DEV-CA-KEY` — generated once offline,
  10-year, stable across cluster recreation. Same CA on every cluster, so clients trust
  it ONCE and the trust survives recreation.
- **Hub mirror** (`packages/components/hub-management/manifests/spoke-secrets/ExternalSecret-tailnet-ca.yaml`):
  mirrors the CA CLUSTER-NEUTRALLY into ns `spoke-secrets` Secret `tailnet-ca`. The
  `spoke-secrets-reader` Role is namespace-wide, so there is **no per-cluster CA key**.
  (ignoreDifferences for the ESO-added fields, PR #2322.)
- **Spoke restore** (`packages/components/tailnet-ca`, delivered via
  `packages/base/apps/tailnet-ca.yaml` — **spoke-only**; the hub does NOT consume
  `packages/base`): an ExternalSecret (`hub-secrets-store`) restores the CA into
  `cert-manager/tailnet-dev-ca`; the `tailnet-dev-ca` **CA `ClusterIssuer`** signs the
  `*.tail286401.ts.net` wildcard Certificate (`Certificate-tailnet-wildcard.yaml`, in the
  workflow-builder ns).
- **L4 LoadBalancer + sidecar.** `type: LoadBalancer`, `loadBalancerClass: tailscale`,
  annotation `tailscale.com/hostname`, 443->https-tls. The nginx `tls-terminator` sidecar
  + its ConfigMap live in `packages/components/workloads/workflow-builder/manifests/`
  (Deployment sidecar + `ConfigMap-workflow-builder-tls-terminator.yaml`). Service files:
  base `packages/base/manifests/tailscale-ingresses/Service-workflow-builder-tailnet.yaml`
  (dev/staging, CLUSTER-templated); ryzen `packages/components/workloads/workflow-builder-tailnet-lb/`.
- **mcp-gateway is in-cluster ONLY** now (dropped from the tailnet). `MCP_GATEWAY_BASE_URL`
  -> `http://mcp-gateway.workflow-builder.svc.cluster.local:8080`. `ORIGIN` /
  `APP_PUBLIC_URL` stay `https://workflow-builder-<cluster>.tail286401.ts.net` (ryzen's
  #2316 http flip was reverted).
- **Workstation trust** (vpittamp/nixos-config, commit 44ba6324): to open the URLs without
  a cert warning clients must trust the CA — `modules/services/cluster-certs.nix`
  (`security.pki.certificates` for system/curl/git) AND `home-modules/tools/chromium.nix`
  (`home.activation` certutil seed of `~/.pki/nssdb` — REQUIRED because `security.pki` does
  NOT cover Chrome's own NSS db on NixOS). The old `CNOE Local Development CA`
  (`*.cnoe.localtest.me`) idpbuilder trust may still be present as a dormant leftover
  (idpbuilder/local-gitea is retired); it is no longer used by any current path.

---

## 7a. Headlamp spoke access (dedicated read Secrets, not the agent mapping)

The hub Headlamp dashboard CANNOT use the `cluster-<spoke>` argocd-agent mapping Secret
to reach a spoke — post-cutover that Secret carries **no bearerToken** (§3), so a
Headlamp restart would otherwise drop all spokes. Instead Headlamp reads **dedicated
`headlamp.dev/cluster=true` Secrets** carrying each spoke's REAL endpoint + a read-only
SA token + CA (PRs #2366/#2368):

- **dev**: real endpoint = the cluster's **direct public IP** `https://<ip>:6443`
  + read-only SA token. `enroll-dev-agent.sh` stages the hub
  `headlamp-cluster-<spoke>` Secret.
- The spoke read SA itself is **GitOps** — `base/manifests/headlamp-reader` (reaches dev
  via `overlays/dev` -> `talos` -> `base`).
- The two hub generators (`headlamp` + `headlamp-embedded`) select the
  `headlamp.dev/cluster=true` label.

---

## 8. Where everything lives (file map)

```
packages/overlays/hub/kustomization.yaml                 # hub root composition + cluster-config
packages/overlays/ryzen/kustomization.yaml               # ryzen overlay (namePrefix ryzen-, ES repoints, kueue patch)
packages/overlays/dev/kustomization.yaml                 # dev overlay (inherits ../talos)
packages/components/hub-base/                             # hub- infra apps, ProxyGroup-kube-apiserver.yaml
packages/components/hub-management/                       # Promoter, headlamp, argocd-agent-principal/, spoke-credentials/, spoke-secrets/
  .../manifests/argocd-agent-principal/                  # the hub PRINCIPAL (single pane) + resource-proxy TLS
  .../manifests/ryzen-agent-bootstrap/                   # ryzen autonomous-agent bootstrap kustomize component (applied by enroll-ryzen-agent.sh)
  .../manifests/kube-system-fixups/                      # self-healing CronJob: re-applies Flannel --iface + CoreDNS anti-affinity Talos drops
  .../spoke-credentials/ExternalSecret-cluster-ryzen.yaml # ryzen Headlamp-only Secret (VESTIGIAL for ArgoCD; KV ARGOCD-CLUSTER-RYZEN-*, host TCP passthrough). cluster-ryzen ArgoCD mapping is written by argocd-agentctl, not this.
  # dev registration is NO LONGER an ExternalSecret/Crossplane job — cluster-dev is the
  #   resource-proxy agent mapping created by deployment/scripts/argocd-agent/enroll-dev-agent.sh
  .../spoke-secrets/{Namespace,ExternalSecret-<c>-shared-secrets,RBAC-spoke-secrets-reader,Ingress-k8s-api-hub-ingress}.yaml
  .../spoke-secrets/ExternalSecret-tailnet-ca.yaml        # Contract 3: cluster-neutral CA mirror -> Secret tailnet-ca
  .../manifests/tailnet-device-sweeper/CronJob-tailnet-device-sweeper.yaml  # offline stale-device hygiene backstop (every 15m)
  .../apps/headlamp.yaml                                  # ryzen-api-egress Service (inline extraManifests)
packages/components/tailnet-ca/manifests/{ExternalSecret-tailnet-ca,ClusterIssuer-tailnet-ca}.yaml  # spoke CA restore + CA ClusterIssuer
packages/base/apps/tailnet-ca.yaml                       # spoke-only tailnet-ca App (hub does NOT consume packages/base)
packages/base/manifests/tailscale-ingresses/Service-workflow-builder-tailnet.yaml  # dev/staging L4 LB (CLUSTER-templated, 443->https-tls)
packages/components/workloads/workflow-builder-tailnet-lb/                # ryzen L4 LB Service
packages/components/workloads/workflow-builder/manifests/{ConfigMap-workflow-builder-tls-terminator,Certificate-tailnet-wildcard}.yaml  # nginx sidecar + wildcard cert
packages/components/hub-spoke-appsets/apps/{spoke-clusters,spoke-workloads}-appset.yaml
packages/components/spoke-tailscale-secrets/             # CONTRACT.md + spoke-transport manifests
packages/components/profiles/local-core-ryzen/           # ryzen profile (Contour+Kourier, AWI/profile exclusions)
# packages/components/crossplane-hetzner-talos/ is INERT history — Crossplane was REMOVED
#   in Phase D; it no longer provisions or registers dev (or any cluster). See §3b.
packages/components/tailscale-serve/manifests/tailscale-operator/Deployment-operator.yaml  # hardcodes OPERATOR_HOSTNAME=ryzen-operator; non-ryzen clusters MUST override (dev: PR #2364)
deployment/scripts/talos-hetzner/recreate-dev.sh        # dev: ORCHESTRATOR rebuild entry point (data backup/restore + provision + deps + enroll-dev-agent + verify)
deployment/scripts/talos-hetzner/provision-spoke.sh      # dev: Hetzner + Talos provision (public 1.12.4 ISO, k8s 1.35, Cilium); --destroy mode
deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh # dev: cert-manager + ESO 2.4.1 + Tailscale operator + spoke->hub ESO transport
deployment/scripts/argocd-agent/enroll-dev-agent.sh      # dev: managed-agent enroll (agent mTLS cert, cluster-dev mapping, AppProject, principal egress, CoreDNS, hub Headlamp SA)
deployment/scripts/argocd-agent/enroll-ryzen-agent.sh    # ryzen: autonomous-agent enroll (mint agent mTLS cert, apply ryzen-agent-bootstrap component incl. root-ryzen @ main, argocd-agentctl agent create ryzen -> cluster-ryzen mapping, stage Headlamp Secret, hard-refresh root-ryzen)
deployment/scripts/bootstrap-spoke-cluster.sh            # ryzen imperative bootstrap; --recreate calls enroll-ryzen-agent.sh (register-spoke-with-hub.sh RETIRED; --ts-acl-mode/--ts-host-passthrough vestigial)
deployment/scripts/recreate-hub.sh                       # hub: rebuild/recover (--verify-only/--seed-secret/--fixups/--dry-run-clone/--in-place --confirm-wipe; never hcloud-deletes the 5 ash servers; seeds onepassword-sa-token via op read)
deployment/scripts/hub-verify-gate.sh                    # hub: 9-check read-only convergence gate
deployment/scripts/lib/spoke-transport-bootstrap.sh      # ryzen imperative transport apply
scripts/gitops/render-workflow-builder-release-overlays.sh
policy.hujson                                            # Tailscale ACL grants
```

## Access

```bash
# hub
kubectl --kubeconfig ~/.kube/hub-config ...          # context admin@hub-cluster; from ryzen host no ssh wrapper
# remote VIP: context hub-cluster (k8s-api-hub.tail286401.ts.net)
# ryzen
kubectl --context admin@ryzen ...
# dev (direct public IP; refresh after recreate — provision-spoke.sh writes the kubeconfig)
kubectl --context admin@dev ...
# break-glass: dev's admin kubeconfig is emitted locally by provision-spoke.sh (no longer a
# crossplane-system <spoke>-XXXXX-kubeconfig Secret on the hub — Crossplane was removed, §3b).
```
