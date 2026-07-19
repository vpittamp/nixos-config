# Pittampalli Talos Cluster System Model

Use this when changing or debugging Talos clusters in `PittampalliOrg/stacks`.

## Hub vs Spoke Topology

The hub is a 5-node Hetzner/Talos cluster (Talos `v1.12.x`, Kubernetes
`v1.32.0`, Flannel CNI, kube-proxy enabled): 3x cpx41 control-plane/management +
2x ccx33 dedicated build nodes (labeled/tainted `stacks.io/build-pool=hub`). It
is provisioned IMPERATIVELY (`docs/hub-cluster-setup.md`). It runs the
**argocd-agent v0.9.0 PRINCIPAL** (single ArgoCD pane, ns `argocd`),
source-hydrator, GitOps Promoter, the Tailscale operator, hub Tekton, and
External Secrets Operator. As of 2026-06 the hub's 21 ExternalSecrets resolve from
the **`onepassword-store`** ClusterSecretStore (ESO `onepasswordSDK` provider ->
the dedicated **`hub-eso`** 1Password vault); root-of-trust is one scoped
read-only 1Password Service-Account token (`hub-eso-reader`) in Secret
`onepassword-sa-token` (ns `external-secrets`), persisted at
`op://CLI/<id>/credential` and read at recreate via the operator's developer SA
token (`op read`). **Azure Workload Identity + Key Vault
(`keyvault-thcmfmoo5oeow`) + the AD App + the OIDC/JWKS federation are DORMANT
(not deleted)**; `sync-jwks-to-azure.sh` is NO LONGER in the hub recreate path (it
is a SPOKE-only tool now). **Crossplane was removed in Phase D** — it is no longer
a fleet dependency.

Spokes differ by how they are provisioned, but all three use imperative scripts:

- `dev` is a SCRIPT-provisioned Hetzner Talos spoke
  (`deployment/scripts/talos-hetzner/` + `argocd-agent/enroll-dev-agent.sh`).
  This skill is about it. It runs a LOCAL ArgoCD + a MANAGED argocd-agent.
- `ryzen` is a bare-metal Talos-in-Docker spoke bootstrapped imperatively; it
  runs a LOCAL ArgoCD + an AUTONOMOUS argocd-agent. Use the
  `ryzen-spoke-bootstrap` skill for it.

The control plane is **argocd-agent v0.9.0**: the hub runs the principal, each
spoke runs a local ArgoCD + an agent that dials the principal OUTBOUND over
tailnet mTLS (8443). The single hub pane aggregates spoke status.

- **dev = MANAGED agent**: the hub authors `Application` objects in ns `dev`
  (== agent name); the principal pushes them to the dev agent; dev's local
  controller reconciles `env/spokes-dev`. Single pane:
  `kubectl --context hub-cluster -n dev get applications`.
- **ryzen = AUTONOMOUS agent**: reconciles its own apps; the hub aggregates
  status.
- Sync OPERATIONS run on the SPOKE's LOCAL controller. The hub pane shows
  sync+health but NOT operation lifecycle — "Unknown operation status" on the hub
  is architectural and benign.

## Script-Based Provisioning (current)

dev is provisioned + enrolled by three imperative scripts in `stacks`, run in
order — the SAME path hub and ryzen already use. There is no
TalosSpokeClusterClaim, Composition, or group-N function. The authoritative
end-to-end runbook is `cluster-desired-state` `runbooks/recreate-dev.md`.

1. `deployment/scripts/talos-hetzner/provision-spoke.sh` — Hetzner network +
   firewall + servers (boots the PUBLIC Talos `1.12.4` amd64 ISO; firewall opens
   6443, 50000, 4789/udp, 41641/udp, 22, ICMP), `talosctl gen/apply/bootstrap`,
   kubeconfig, Cilium CNI (`cni: none`), disk-first boot after install.
   Bootstraps k8s `1.35` (the `1.12.4` ISO REJECTS `1.36`), then in-place
   `talosctl upgrade-k8s` to the target. `--destroy` tears it down. Fully
   env-parameterized (`CLUSTER_NAME`, `LOCATION`, `CP_COUNT`/`CP_TYPE`,
   `WORKER_COUNT`/`WORKER_TYPE`, `NETWORK_CIDR`/`SUBNET_CIDR`/`NETWORK_ZONE`,
   `TALOS_VERSION`, `K8S_VERSION`, `BOOTSTRAP_K8S_VERSION`, `ISO_ID`,
   `WORKER_NODE_LABELS`, `INSTALL_CNI`, `CILIUM_VERSION`); defaults reproduce live
   dev (3x cpx41 CP + 6x cpx51 workers, `hil`, `10.0.1.0/24`).
2. `deployment/scripts/talos-hetzner/bootstrap-spoke-deps.sh` — cert-manager
   v1.14.4 + ESO 2.4.1 (controller-only) + the Tailscale operator + the
   spoke->hub ESO transport (via `lib/spoke-transport-bootstrap.sh`). It also
   seeds privileged namespaces, but that is now a REDUNDANT backstop: privileged
   PodSecurity is PRIMARILY declarative (`managedNamespaceMetadata` on
   CreateNamespace Helm apps + privileged-labelled Namespace manifests, PR
   #2359). The transport is a prereq for enrollment (the agent mTLS cert + repo
   cred arrive via ESO).
3. `deployment/scripts/argocd-agent/enroll-dev-agent.sh` — managed-agent enroll
   (replaces the old group-8 "role B" registration). See next section.

## argocd-agent Managed-Agent Enrollment

`enroll-dev-agent.sh dev` does the following on the hub + spoke:

- Mints the **agent mTLS cert** on the hub and stages it for ESO delivery to the
  spoke (NOT pki-propagated — delivered over the kept spoke->hub transport).
- Applies the `dev-agent-bootstrap` agent stack on the spoke (managed mode).
- Creates the `cluster-dev` Secret on the hub via `argocd-agentctl agent create`:
  an **AGENT MAPPING**, not a direct-server kubeconfig. Its `server` is
  `https://argocd-agent-resource-proxy:9090?agentName=dev` (the in-cluster
  resource-proxy), with embedded mTLS `certData`/`keyData`/`caData` and **NO
  bearerToken**. This replaced the old direct-server + bearerToken cluster Secret.
- Creates the AppProject, the principal-egress Service, and a CoreDNS principal
  rewrite.
- Stages the hub Headlamp read SA Secret (`headlamp-cluster-dev`, labeled
  `headlamp.dev/cluster=true`) so Headlamp can reach dev via its real endpoint +
  a read-only SA token — Headlamp does NOT use the bearerToken-less agent mapping.

Outbound-only: there is NO hub->spoke kube-API reach for ArgoCD (gRPC outbound
to the principal only).

## HISTORICAL: Crossplane era (removed Phase D)

Before Phase D, dev (and a never-fully-live `staging`) were Crossplane composites:
`TalosSpokeClusterClaim` -> XR -> `Composition-talospokecluster.yaml`, driven by
a function-sequencer ordered fan-out (group-1-network, group-2-servers,
group-3-talos-workspace via provider-terraform + the talos provider,
group-4-iso-detach, and onboarding groups 5/6/7/8/9 — spoke-register, hub
connectivity, spoke-bootstrap, hub-argocd registration "role B", proxygroup-auth).
The `crossplane-hcloud-compositions` Application auto-synced claims from `main`
with selfHeal. **All of this is gone.** Crossplane is no longer installed as a
fleet dependency; the one live composite (`dev`) was orphaned (kept running) and
its registration role ("role B") was deleted. The three scripts above replace the
entire pipeline. The historical onboarding also had a last Azure tendril
(group-7 spoke-bootstrap using `az keyvault secret show` for the Tailscale OAuth
Secret); the script path now sources Tailscale OAuth creds from env / 1Password /
Key Vault directly. (The Crossplane-era `recreate-crossplane-spoke.md` runbook was
removed; the authoritative recreate runbook is `cluster-desired-state`
`runbooks/recreate-dev.md`.)

## ISO vs Kubernetes Version Constraint

The Hetzner public catalog ships only a Talos `1.12.4` ISO (no custom-ISO upload
API; a custom ISO requires a support ticket with a `factory.talos.dev` URL).
Two version selectors interact:

- `install.image` (from `provision-spoke.sh`'s `TALOS_VERSION`, written into the
  generated machine config) sets the Talos version WRITTEN TO DISK.
  `TALOS_VERSION=1.13.2` installs Talos `1.13.x` even though nodes boot the
  `1.12.4` ISO.
- The maintenance-mode node validates the REQUESTED `kubernetesVersion` against
  the RUNNING ISO Talos (`1.12.4`) BEFORE the new Talos is on disk.

So a one-shot Talos `1.13.2` + k8s `1.36` install cannot bootstrap. The script
handles this automatically: it bootstraps at `BOOTSTRAP_K8S_VERSION=1.35.0`
(installs Talos `v1.13.2` via `install.image`), then `talosctl upgrade-k8s --to
${K8S_VERSION}` once the installed `1.13.2` is running (full sequence in
`runbooks/resize-or-upgrade.md`). Confirm with the OS-IMAGE column of
`kubectl get nodes -o wide` (expect Talos `1.13.x`).

## HCloud Placement

For the Hetzner Talos spokes, check both server-type availability and network
zone before setting `provision-spoke.sh`'s `LOCATION`/`NETWORK_ZONE`/type vars:

```bash
hcloud location list -o columns=name,description,country,city,network_zone
for type in cpx41 cpx51 cpx42 cpx62; do
  hcloud server-type describe "$type" -o json | jq -r \
    --arg type "$type" '"\($type): " + ([.locations[]?.name] | join(","))'
done
```

Current lessons:

- `ash` and `hil` are the US locations; `ash` uses `us-east` and `hil` uses
  `us-west`.
- `cpx41` and `cpx51` are the expected dev control-plane and worker types.
- `cpx42` and `cpx62` were not available in US locations during the dev
  rebuild and should not be substituted unless `hcloud` confirms support.
- Capacity failures such as `resource_unavailable` are a placement signal, not a
  Talos failure. Move to another acceptable US location, such as `hil`, only
  after the user accepts that placement.

## File Map

```text
# Script-based provisioning (current; replaces crossplane-hetzner-talos)
deployment/scripts/talos-hetzner/
  recreate-dev.sh             # dev ORCHESTRATOR: backup/restore (environment_image_builds/agents/workflows) + provision + bootstrap-deps + enroll-dev-agent + verify gate
  provision-spoke.sh          # Hetzner+Talos: network/firewall/servers, talosctl gen/apply/bootstrap, Cilium, k8s upgrade; --destroy
  bootstrap-spoke-deps.sh     # cert-manager + ESO + Tailscale operator + spoke->hub ESO transport
  lib/spoke-transport-bootstrap.sh
  README.md
deployment/scripts/argocd-agent/
  enroll-dev-agent.sh         # managed-agent enroll: agent mTLS cert, cluster-dev mapping, AppProject, egress Svc, CoreDNS, Headlamp Secret
  enroll-ryzen-agent.sh       # autonomous-agent enroll (ryzen): mint agent mTLS cert, apply ryzen-agent-bootstrap component, argocd-agentctl agent create ryzen (cluster-ryzen mapping), stage Headlamp Secret, advance inner-loop
  # register-spoke-with-hub.sh is RETIRED — replaced by enroll-{dev,ryzen}-agent.sh
deployment/scripts/
  recreate-hub.sh             # hub recreate: --verify-only / --seed-secret / --fixups / --dry-run-clone / --in-place --confirm-wipe; NEVER hcloud-deletes the 5 ash servers; --in-place = rolling talosctl reset reusing hub-secrets.yaml, bootstrap ONE CP, seed onepassword-sa-token via op read (NOT JWKS)
  hub-verify-gate.sh          # 9-check read-only hub convergence gate
packages/components/hub-management/manifests/
  ryzen-agent-bootstrap/      # kustomize component applied by enroll-ryzen-agent.sh (agent-autonomous bundle + params mode=autonomous + cluster-ryzen-local alias + stacks-repo-read + cert ExternalSecrets + root-ryzen app-of-apps)
  kube-system-fixups/         # self-healing CronJob re-applying Flannel --iface + CoreDNS anti-affinity patches Talos does not persist
packages/overlays/dev/        # components: [../../components/spoke-tailscale-secrets]; dev-operator hostname override (PR #2364)
packages/base/manifests/tailscale-ingresses/
  Service-workflow-builder-tailnet.yaml       # L4 Tailscale LoadBalancer (NOT Ingress, NO LE); dev/staging
packages/base/apps/tailnet-ca.yaml            # spoke-only app delivering packages/components/tailnet-ca
packages/components/tailnet-ca/               # ES restores hub tailnet-ca -> cert-manager/tailnet-dev-ca + ClusterIssuer
packages/components/workloads/workflow-builder-tailnet-lb/   # ryzen L4 LoadBalancer Service
packages/components/workloads/workflow-builder/manifests/
  ConfigMap-workflow-builder-tls-terminator.yaml   # nginx sidecar config (proxy buffers tuned, PR #2327)
  Certificate-tailnet-wildcard.yaml                # *.tail286401.ts.net signed by tailnet-dev-ca
packages/components/hub-base/manifests/ProxyGroup-kube-apiserver.yaml
# AWI -> Tailscale spoke secret transport
packages/components/spoke-tailscale-secrets/
  CONTRACT.md
  apps/spoke-transport.yaml
  manifests/spoke-transport/ClusterSecretStore-hub-secrets-store.yaml  # caBundle = ISRG Root X1 (required; still on ESO v2.4.1; manifest is external-secrets.io/v1)
  manifests/spoke-transport/Service-k8s-api-hub-egress.yaml
packages/components/hub-management/manifests/spoke-secrets/
  Namespace-spoke-secrets.yaml
  ExternalSecret-dev-shared-secrets.yaml      # from onepassword-store (Azure dormant), hub-canonical
  ExternalSecret-ryzen-shared-secrets.yaml
  ExternalSecret-tailnet-ca.yaml              # CLUSTER-NEUTRAL tailnet-ca (shared by all spokes)
  RBAC-spoke-secrets-reader.yaml
  Ingress-k8s-api-hub-ingress.yaml            # standalone Tailscale Ingress DEVICE — the ONE remaining LE cert (single stable hostname)
packages/base/manifests/headlamp-reader/headlamp-reader.yaml  # spoke read-only SA (reaches hub Headlamp via headlamp.dev/cluster Secret)
scripts/gitops/render-workflow-builder-release-overlays.sh  # per-cluster ES repoints (dev-gated)
docs/recreate-disposable-dev.md
docs/tailscale-naming.md
docs/tailscale-hostname-reuse-strategy.md
# Authoritative end-to-end + Tailscale/cert detail: cluster-desired-state skill
#   runbooks/recreate-dev.md  +  references/architecture.md
```

### Recent hardening fixes (PR #2395)

Four recreate-hardening fixes landed on these scripts (validated: ryzen
`bootstrap-spoke-cluster.sh --recreate` = 13m9s hands-off 64/65; dev
`recreate-dev.sh` = 20m32s hands-off):

- `bootstrap-spoke-cluster.sh` is STANDALONE (does NOT source `lib/common.sh`),
  so `TS_OPERATOR_CHART_VERSION` was unbound under `set -u` and ryzen recreate
  ABORTED at the tailscale-operator helm install (post-destroy = ryzen DOWN).
  Now self-defaulted (`:-1.96.5`); keep in lockstep with `lib/common.sh`.
- `enroll-ryzen-agent.sh` step 6b waits for the local `argocd-repo-server` then
  hard-refreshes `root-ryzen` (cold-start dial-`:8081` ComparisonError that the
  controller would not re-queue for ~5min); `bootstrap-spoke-cluster.sh` step 10
  hard-refreshes again after the inner-loop advance.
- `enroll-{dev,ryzen}-agent.sh` step 5b now `rollout restart`s hub Headlamp
  after staging the `headlamp-cluster-<spoke>` Secret (stale pre-recreate pod).
- `provision-spoke.sh --destroy` deletes Hetzner servers in parallel (~156s -> ~20s).

Full gotcha detail: `cluster-desired-state` `runbooks/recovery-and-gotchas.md`.

## Spoke Secret Transport (AWI -> Tailscale)

Dev/staging spokes no longer authenticate to Azure. They read hub-mirrored
secrets over Tailscale:

- The hub mirrors every spoke-consumed secret into ns `spoke-secrets` as a Secret
  `<cluster>-shared-secrets` (via an ExternalSecret on `onepassword-store`, the
  `hub-eso` 1Password vault; `azure-keyvault-store` is dormant). SPOKES ARE
  UNAFFECTED by how the hub populates these k8s Secrets — they read the
  hub-mirrored result over Tailscale via the ESO kubernetes-provider store below.
- The spoke resolves a `hub-secrets-store` ClusterSecretStore (ESO kubernetes
  provider) that reads ns `spoke-secrets` on the hub through the standalone
  Tailscale Ingress DEVICE `k8s-api-hub-ingress.tail286401.ts.net` (LE cert
  chaining to ISRG Root X1; the store's `caBundle` is hard-set to ISRG Root X1,
  REQUIRED; still on ESO v2.4.1). A scoped read-only bearer token (SA
  `spoke-secrets-reader`) authorizes it. A spoke CoreDNS rewrite maps the
  Ingress FQDN to `k8s-api-hub-egress.tailscale.svc.cluster.local`.
- For dev, `scripts/gitops/render-workflow-builder-release-overlays.sh` injects
  dev-gated kustomize patches repointing workload ExternalSecrets'
  `remoteRef.key` to `dev-shared-secrets` on `secretStoreRef: hub-secrets-store`
  (shared workload manifests otherwise hardcode `ryzen-shared-secrets`).
- This transport also delivers the **argocd-agent mTLS cert** and the repo cred
  to the spoke, so it is a prereq for `enroll-dev-agent.sh` (NEVER remove it).
  The `k8s-api-hub-ingress` LE cert is the ONE remaining LE cert in the fleet,
  but it is a SINGLE STABLE hostname (no per-spoke churn) so it never hits the
  rate limit.
- A recreate must have the hub mirror + the `spoke-secrets-reader` RBAC + the
  CoreDNS rewrite working; `azure-keyvault-store` on the spoke is gone. Verify
  `kubectl get clustersecretstore hub-secrets-store` is Ready on the spoke.

> Canonical Tailscale + cert-avoidance material (hub->ryzen raw-TCP passthrough,
> LE-churn history, Tailnet Dev CA, the spoke->hub transport) lives in the
> `cluster-desired-state` skill `references/architecture.md`. The summary below
> is a local convenience; defer to that doc, do not re-derive it.

## Tailnet Web Exposure (L4 LoadBalancer + in-cluster TLS)

Spoke web apps on the tailnet no longer use a Tailscale-class Ingress with a
per-hostname Let's Encrypt cert (the old `ingressClassName: tailscale` +
ProxyClass `development-prod-cert`). Recreate churn exhausted LE's 5-certs/168h
limit and made the apps unreachable (429). The current uniform pattern (PR
#2319) is:

- A Tailscale **L4 LoadBalancer Service** (`type: LoadBalancer`,
  `loadBalancerClass: tailscale`, annotation `tailscale.com/hostname`, NO LE).
- **HTTPS terminated IN-CLUSTER** by a per-pod nginx `tls-terminator` sidecar
  serving a persistent self-signed wildcard `*.tail286401.ts.net`. Access stays
  `https://workflow-builder-{dev,ryzen,staging}.tail286401.ts.net`;
  `ORIGIN` / `APP_PUBLIC_URL` are unchanged.
- `mcp-gateway` is dropped from the tailnet (in-cluster only);
  `MCP_GATEWAY_BASE_URL` is
  `http://mcp-gateway.workflow-builder.svc.cluster.local:8080`.

Files: base
`packages/base/manifests/tailscale-ingresses/Service-workflow-builder-tailnet.yaml`
(dev/staging, CLUSTER-templated, 443->https-tls); ryzen
`packages/components/workloads/workflow-builder-tailnet-lb/`; the sidecar +
ConfigMap + wildcard Certificate in
`packages/components/workloads/workflow-builder/manifests/`
(`ConfigMap-workflow-builder-tls-terminator.yaml`,
`Certificate-tailnet-wildcard.yaml`). The dev/staging overlays
`$patch:delete` the old workflow-builder/mcp-gateway Tailscale Ingresses.

The wildcard cert is signed by a persistent self-signed CA shared across the
whole fleet (see "Tailnet Dev CA" below), so clients trust it once and the trust
survives cluster recreation.

### 502 "upstream sent too big header" gotcha (PR #2327)

The tls-terminator nginx default 8k proxy header buffer overflows on SvelteKit
auth's large `Set-Cookie` headers, returning **502 for BROWSERS while bare
`curl` (small headers) returns 302** — the curl 302 masks the browser failure.
Fix in the sidecar ConfigMap: `proxy_buffer_size 32k; proxy_buffers 8 32k;
proxy_busy_buffers_size 64k; large_client_header_buffers 4 32k`. Verify HTTPS
exposure with a real browser (or curl with full browser headers), and diagnose
via the sidecar nginx error log.

## Tailnet Dev CA (persistent self-signed CA contract)

A self-signed CA **"PittampalliOrg Tailnet Dev CA"** is generated once (offline,
10-year) and stored as `TAILNET-DEV-CA-CRT` / `TAILNET-DEV-CA-KEY` (canonical
source is now the `hub-eso` 1Password vault via `onepassword-store`; Azure Key
Vault is dormant). It is stable across cluster recreation. This is a
cross-cutting contract alongside the cluster-Secret and spoke-transport
contracts (PR #2319; CA `ignoreDifferences` + sweeper in PR #2322).

- The hub mirrors it CLUSTER-NEUTRALLY into ns `spoke-secrets` Secret
  `tailnet-ca` (via an ExternalSecret on `onepassword-store`)
  (`packages/components/hub-management/manifests/spoke-secrets/ExternalSecret-tailnet-ca.yaml`).
  The `spoke-secrets-reader` Role is namespace-wide, so every spoke reads the
  SAME key — there is no per-cluster CA key.
- Spoke base app `packages/components/tailnet-ca` (delivered via
  `packages/base/apps/tailnet-ca.yaml`, spoke-only — the hub does not consume
  `packages/base`): an ExternalSecret (`hub-secrets-store`) restores the CA into
  `cert-manager/tailnet-dev-ca`, and a `tailnet-dev-ca` CA `ClusterIssuer` signs
  the `*.tail286401.ts.net` wildcard Certificate (in the workflow-builder ns)
  consumed by the tls-terminator sidecar.
- Because the CA is identical on every cluster, clients trust it once and the
  trust survives recreation (an improvement over idpbuilder, which regenerates
  per-install). Workstation trust lives in `vpittamp/nixos-config`
  (`modules/services/cluster-certs.nix` for system/curl/git +
  `home-modules/tools/chromium.nix` for the Chrome NSS db seed, REQUIRED on
  NixOS because `security.pki` does not cover Chrome; commit 44ba6324).

## Naming Models

Device-backed Tailscale exposures create tailnet devices, e.g. the per-cluster
operator (`dev-operator`/`ryzen-operator`), `workflow-builder-dev`, and
`openshell-dev`. Stale device records can reserve the desired name and force the
real device to register as `<name>-1`. The shared `tailscale-operator` manifest
hardcodes `OPERATOR_HOSTNAME=ryzen-operator`; every NON-ryzen cluster MUST
override it (dev does via a dev-overlay `source.kustomize` patch, PR #2364) or
its operator collides. Clean stale `-N` proxy devices via the TS API
(operator-oauth `client_credentials` -> delete OFFLINE orphans; gated
poll-until-offline). See `runbooks/tailscale-name-recovery.md`.

> ProxyGroup service-hosts (e.g. the old `dev-api-v2` Tailscale Service that
> ArgoCD used to reach dev's API) are HISTORICAL for dev. argocd-agent reverses
> the direction: the dev agent dials the hub principal OUTBOUND, so there is no
> hub->dev ProxyGroup. The hub `ProxyGroup-kube-apiserver` and the
> `k8s-api-hub-ingress` DEVICE remain for the spoke->hub ESO transport.

`workflow-builder` is exposed via a Tailscale **L4 LoadBalancer Service**
(`type: LoadBalancer`, `loadBalancerClass: tailscale`,
`tailscale.com/hostname` annotation), NOT a Tailscale Ingress, and NOT Let's
Encrypt (PR #2319). It still registers a device hostname
(`workflow-builder-<spoke>`) and is still subject to `-1` suffix drift from stale
devices. `mcp-gateway` was DROPPED from the tailnet (in-cluster only) — do not
expect a `mcp-gateway-<spoke>` device. See "Tailnet Web Exposure" below.

## Headlamp Hub Connection

Hub Headlamp builds its kubeconfig from dedicated `headlamp.dev/cluster=true`
Secrets (per-spoke real endpoint + read-only SA token + CA) in an init container,
NOT the argocd-agent `cluster-<spoke>` mapping Secrets (which carry no
bearerToken post-cutover, so a Headlamp restart would otherwise drop all spokes —
PRs #2366/#2368). The generated file lives in pod-local storage, so a changed
`headlamp-cluster-<spoke>` Secret does not automatically update an
already-running Headlamp pod.

The spoke read SA = `packages/base/manifests/headlamp-reader` (GitOps, reaches
dev via overlays/dev -> talos -> base); `enroll-dev-agent.sh` stages the hub
`headlamp-cluster-<spoke>` Secret. For dev, Headlamp reaches the cluster via its
DIRECT PUBLIC IP (`https://<ip>:6443`) + the read-only SA token (there is no
hub->dev ArgoCD kube-API path).

After recreating dev or changing the Headlamp Secret, verify it and restart
Headlamp:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret headlamp-cluster-dev \
  -o jsonpath='{.data.server}' | base64 -d
kubectl --kubeconfig ~/.kube/hub-config -n headlamp rollout restart deploy/hub-headlamp
kubectl --kubeconfig ~/.kube/hub-config -n headlamp rollout status deploy/hub-headlamp
```

## Break-Glass Access

Crossplane no longer writes kubeconfig connection Secrets. `provision-spoke.sh`
emits an admin kubeconfig at the end of provisioning (see its output / the
README); keep it for recovery. For an already-running cluster, the spoke is also
reachable at its DIRECT PUBLIC IP (`https://<control-plane-ip>:6443`). Use only
for recovery and shred any extracted file when done (`shred -u /tmp/...`).

## Dev Rebuild Reflection

The dev rebuild and the subsequent Phase D de-Crossplaning both confirmed the
same lesson: the risky parts are NOT Talos bootstrap itself; they are ownership
boundaries, generated configuration, the ISO-vs-Kubernetes-version constraint,
and stale-name cleanup. With the script path these are all imperative and
inspectable:

- The Hetzner `1.12.4` ISO cannot bootstrap a one-shot Talos `1.13.2` + k8s
  `1.36`. The script bootstraps k8s on `1.35` first (with `TALOS_VERSION=1.13.2`
  so `install.image` installs Talos `1.13.x`), then `upgrade-k8s` to `1.36`. See
  "ISO vs Kubernetes Version Constraint".
- Delete old HCloud resources only after you are ready to recreate them
  (`provision-spoke.sh --destroy` for a script-provisioned spoke).
- Check HCloud placement before selecting server types. `cpx41`/`cpx51` worked
  in `hil`; `cpx42`/`cpx62` were not US-placeable at the time of rebuild.
- Clean Tailscale devices/service-hosts before re-authenticating the operator.
  Override the per-cluster operator hostname (`dev-operator`, not the hardcoded
  `ryzen-operator`) or it collides on the tailnet (PR #2364).
- Restart `hub-headlamp` after the `headlamp-cluster-dev` Secret changes because
  the UI kubeconfig is generated at pod startup.
- Treat the spoke's LOCAL ArgoCD app health as part of cluster readiness; the hub
  principal pane aggregates it. "Unknown operation status" on the hub is benign.
- Validate workflow-builder data and Dapr scopes before launching benchmark
  traffic.

For future rebuilds, spend most of the time on preflight inventory, stale-name
cleanup, and post-bootstrap validation. The three-script Talos path should be
boring once the script parameters and the spoke overlay are correct. The
authoritative end-to-end is `cluster-desired-state` `runbooks/recreate-dev.md`.
