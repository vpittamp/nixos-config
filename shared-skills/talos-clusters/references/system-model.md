# Pittampalli Talos Cluster System Model

Use this when changing or debugging Talos clusters in `PittampalliOrg/stacks`.

## Hub vs Spoke Topology

The hub is a 5-node Hetzner/Talos cluster (Talos `v1.12.x`, Kubernetes
`v1.32.0`, Flannel CNI, kube-proxy enabled): 3x cpx41 control-plane/management +
2x ccx33 dedicated build nodes (labeled/tainted `stacks.io/build-pool=hub`). It
is provisioned IMPERATIVELY (`docs/hub-cluster-setup.md`), NOT by a
TalosSpokeClusterClaim. It runs Crossplane, ArgoCD, source-hydrator, GitOps
Promoter, the Tailscale operator, hub Tekton, and External Secrets Operator. The
hub keeps Azure Workload Identity + Key Vault (`keyvault-thcmfmoo5oeow`) as the
canonical secret source for the whole fleet.

Spokes differ by how they are provisioned:

- `dev` and `staging` are Crossplane-driven Hetzner Talos spokes
  (TalosSpokeClusterClaim -> XR -> Composition). This skill is about these.
- `ryzen` is a bare-metal Talos-in-Docker spoke bootstrapped imperatively
  (`deployment/scripts/bootstrap-spoke-cluster.sh`); it is NOT a claim spoke.
  Use the `ryzen-spoke-bootstrap` skill for it.

The Crossplane spoke control path is:

1. Edit and commit a spoke claim/composition in `stacks` (on `main`; dev/staging
   track `main`, ryzen tracks `inner-loop`).
2. Hub Argo applies Crossplane providers, XRDs, compositions, and claims. The
   `crossplane-hcloud-compositions` Application auto-syncs from `main` with
   selfHeal, so live claim patches can be overwritten by Git in flight.
3. Crossplane (provider-hetzner + provider-terraform with the talos provider)
   creates HCloud network/firewall/servers and runs a Terraform module for Talos
   machine secrets/config/apply/bootstrap, writing a `<spoke>-kubeconfig`
   connection Secret.
4. Onboarding jobs register the spoke with hub ArgoCD, create spoke bootstrap
   resources + the Tailscale operator OAuth Secret, wire the Tailscale-native
   secret transport, and authenticate the Kubernetes API ProxyGroup.
5. Source-hydrator renders the spoke overlay and Promoter merges the generated
   branch (`env/spokes-<name>-next` -> `env/spokes-<name>`).
6. Hub ArgoCD syncs the spoke workload Applications to the new cluster.

## Crossplane Provisioning Pipeline

`Composition-talospokecluster.yaml` drives a function-sequencer ordered fan-out.
Approximate group order (verify against the live composition before editing):

- group-1-network: Network / Subnet / Firewall (opens 6443, 50000, 4789, 41641,
  22, icmp).
- group-2-servers: control-plane + worker servers booted from the Hetzner ISO id
  in the claim (`isoId`), debian-12 base, `ignoreRemoteFirewallIds`.
- group-3-talos-workspace: provider-terraform Inline module (talos provider):
  `talos_machine_secrets` -> `talos_machine_configuration` (cp/worker; CNI
  none/Cilium on dev/staging, proxy disabled, etcd+kubelet on the spoke subnet,
  worker `nodeLabels`) -> `talos_machine_configuration_apply` ->
  `talos_machine_bootstrap` -> `talos_cluster_kubeconfig`. The module sets only
  `install.disk=/dev/sda` + `wipe=true`; the INSTALLED Talos version comes from
  `talos_version` (= claim `talos.version`) which derives `install.image`.
- group-4-iso-detach: a long-running converger Job (hetznercloud/cli) that polls
  the Talos API :50000 on each node, detaches the ISO, and resets. It can run
  for tens of minutes and gate later groups' readiness reporting (a benign
  source of claim `Ready=False`).
- Onboarding (group-5 spoke-register, group-7 spoke-bootstrap, group-9
  proxygroup-auth; group-6 hub-connectivity + group-8 hub-argocd are
  dependency-ordered): see the onboarding-job notes below.

### Onboarding job images (AWI removal in progress)

- group-5 spoke-register now runs `alpine/k8s:1.36.0` (NO `az`): waits for the
  spoke API, mints an `argocd-remote-manager` SA + token, writes the
  `cluster-<spoke>` argocd Secret directly to the hub, then wires the
  Tailscale-native transport glue (scoped hub token -> spoke
  `external-secrets/hub-secrets-token`; CoreDNS rewrite inserted via `jq`, NOT
  `awk`, because the slim image lacks awk).
- group-7 spoke-bootstrap still runs `mcr.microsoft.com/azure-cli:latest` and
  still uses `az keyvault secret show` to mint the Tailscale operator OAuth
  Secret. This is the LAST Azure tendril in dev provisioning and is deferred.
- group-9 proxygroup-auth (`alpine/k8s:1.36.0` + tailscale TF provider): cleans
  stale ArgoCD apps / Tailscale Services / stale devices, generates a
  pre-authorized auth key, creates the spoke ProxyGroup `k8s-api-<spoke>`, waits
  for the StatefulSet, injects `TS_AUTHKEY`.

## Important Resources

Hub kubeconfig:

```bash
~/.kube/hub-config
```

Crossplane namespace:

```bash
crossplane-system
```

Claim kind:

```yaml
apiVersion: platform.pittampalli.io/v1alpha1
kind: TalosSpokeClusterClaim
```

Dev claim shape captured from the rebuild:

```yaml
parameters:
  clusterName: dev
  location: hil
  networkZone: us-west
  controlPlane:
    count: 3
    serverType: cpx41
  workers:
    count: 6
    serverType: cpx51
    nodeLabels:
      stacks.io/swebench-pool: dev-benchmark
  talos:
    # version drives install.image (the Talos WRITTEN TO DISK). Target is 1.13.2.
    # The booted Hetzner ISO is 1.12.4 regardless; maintenance mode validates
    # kubernetesVersion against the RUNNING 1.12.4 ISO, so bootstrap k8s on 1.35
    # first, then raise to 1.36. See "ISO vs Kubernetes Version Constraint".
    version: "1.13.2" # Verify live OS-IMAGE via kubectl get nodes -o wide.
    kubernetesVersion: "1.36.0" # transiently 1.35.0 during first bootstrap.
    isoId: "125127" # Hetzner public catalog = Talos 1.12.4 ISO only.
  onboarding:
    enableOnboarding: true
    tailnetDomain: tail286401.ts.net
    tailnet: vpittamp.github
    azureKeyVaultName: keyvault-thcmfmoo5oeow
    repoUrl: https://github.com/PittampalliOrg/stacks.git
    overlayPath: packages/overlays/dev
```

## ISO vs Kubernetes Version Constraint

The Hetzner public catalog ships only a Talos `1.12.4` ISO (no custom-ISO upload
API; a custom ISO requires a support ticket with a `factory.talos.dev` URL).
Two version selectors interact:

- `install.image` (derived from claim `talos.version`) sets the Talos version
  WRITTEN TO DISK. A claim of `talos.version: 1.13.2` installs Talos `1.13.x`
  even though nodes boot the `1.12.4` ISO.
- The maintenance-mode node validates the REQUESTED `kubernetesVersion` against
  the RUNNING ISO Talos (`1.12.4`) BEFORE the new Talos is on disk.

So a one-shot `talos.version: 1.13.2` + `kubernetesVersion: 1.36` claim cannot
bootstrap. Supported recovery (full sequence in
`runbooks/resize-or-upgrade.md`): patch the LIVE claim to
`kubernetesVersion: 1.35.0` (keep `version: 1.13.2`), let it bootstrap, then
raise `kubernetesVersion` back to `1.36.0`. Confirm with the OS-IMAGE column of
`kubectl get nodes -o wide` (expect Talos `1.13.x`), not the claim value.

## HCloud Placement

For the Hetzner Talos spokes, check both server-type availability and network
zone before editing a claim:

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
packages/components/crossplane-hetzner-talos/
  apps/
    crossplane-hcloud-providers.yaml
    crossplane-hcloud-compositions.yaml
  manifests/crossplane-hcloud-providers/
    Provider-*.yaml
    ProviderConfig-*.yaml
    ExternalSecret-hcloud-api-token.yaml
  manifests/crossplane-hcloud-compositions/
    CompositeResourceDefinition-talospokecluster.yaml
    Composition-talospokecluster.yaml
    TalosSpokeClusterClaim-dev.yaml
packages/overlays/dev/        # components: [../../components/spoke-tailscale-secrets]
packages/overlays/staging/
packages/base/manifests/tailscale-ingresses/
packages/components/hub-base/manifests/ProxyGroup-kube-apiserver.yaml
# AWI -> Tailscale spoke secret transport
packages/components/spoke-tailscale-secrets/
  CONTRACT.md
  apps/spoke-transport.yaml
  manifests/spoke-transport/ClusterSecretStore-hub-secrets-store.yaml  # caBundle = ISRG Root X1 (required by ESO v0.9.13)
  manifests/spoke-transport/Service-k8s-api-hub-egress.yaml
packages/components/hub-management/manifests/spoke-secrets/
  Namespace-spoke-secrets.yaml
  ExternalSecret-dev-shared-secrets.yaml      # from azure-keyvault-store, hub-canonical
  ExternalSecret-ryzen-shared-secrets.yaml
  RBAC-spoke-secrets-reader.yaml
  Ingress-k8s-api-hub-ingress.yaml            # standalone Tailscale Ingress DEVICE (not a ProxyGroup VIP)
scripts/gitops/render-workflow-builder-release-overlays.sh  # per-cluster ES repoints (dev-gated)
docs/recreate-disposable-dev.md
docs/crossplane-spoke-onboarding.md
docs/tailscale-naming.md
docs/tailscale-hostname-reuse-strategy.md
```

## Spoke Secret Transport (AWI -> Tailscale)

Dev/staging spokes no longer authenticate to Azure. They read hub-mirrored
secrets over Tailscale:

- The hub mirrors every spoke-consumed Key Vault secret into ns `spoke-secrets`
  as a Secret `<cluster>-shared-secrets` (via an ExternalSecret on
  `azure-keyvault-store`). The hub stays the canonical AWI + Key Vault source.
- The spoke resolves a `hub-secrets-store` ClusterSecretStore (ESO kubernetes
  provider) that reads ns `spoke-secrets` on the hub through the standalone
  Tailscale Ingress DEVICE `k8s-api-hub-ingress.tail286401.ts.net` (LE cert
  chaining to ISRG Root X1; the store's `caBundle` is hard-set to ISRG Root X1,
  REQUIRED by ESO v0.9.13). A scoped read-only bearer token (SA
  `spoke-secrets-reader`) authorizes it. A spoke CoreDNS rewrite maps the
  Ingress FQDN to `k8s-api-hub-egress.tailscale.svc.cluster.local`.
- For dev, `scripts/gitops/render-workflow-builder-release-overlays.sh` injects
  dev-gated kustomize patches repointing workload ExternalSecrets'
  `remoteRef.key` to `dev-shared-secrets` on `secretStoreRef: hub-secrets-store`
  (shared workload manifests otherwise hardcode `ryzen-shared-secrets`).
- A recreate must have the hub mirror + the `spoke-secrets-reader` RBAC + the
  CoreDNS rewrite working; `azure-keyvault-store` on the spoke is gone. Verify
  `kubectl get clustersecretstore hub-secrets-store` is Ready on the spoke.

## Naming Models

ProxyGroup service-hosts create Tailscale Services, e.g. `dev-api-v2`. They need
tailnet policy `autoApprovers.services["svc:<hostname>"]` and the right
ProxyGroup device tags/grants.

Device-backed Tailscale Ingresses create tailnet devices, e.g.
`workflow-builder-dev`, `mcp-gateway-dev`, and `openshell-dev`. Do not add
`svc:*` approvals for these; stale service-host records can reserve the desired
name and force the real device to register as `<name>-1`.

## Headlamp Hub Connection

Hub Headlamp reads ArgoCD cluster secrets and generates its kubeconfig in an
init container. The generated file lives in pod-local storage, so a changed
`cluster-<spoke>` secret does not automatically update an already-running
Headlamp pod.

After recreating dev or changing the Argo cluster secret, verify the secret and
restart Headlamp:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n argocd get secret cluster-dev \
  -o jsonpath='{.data.server}' | base64 -d
kubectl --kubeconfig ~/.kube/hub-config -n headlamp rollout restart deploy/hub-headlamp
kubectl --kubeconfig ~/.kube/hub-config -n headlamp rollout status deploy/hub-headlamp
```

Prefer the endpoint ArgoCD is already using unless hub-to-ProxyGroup DNS has
been verified from inside hub pods. Headlamp may continue to show a direct HCloud
API endpoint even when the canonical external path is `dev-api-v2`.

## Break-Glass Access

Crossplane writes admin kubeconfigs into hub secrets named like
`<spoke>-<suffix>-kubeconfig`. Use the newest matching secret:

```bash
kubectl --kubeconfig ~/.kube/hub-config get secrets -n crossplane-system \
  --sort-by=.metadata.creationTimestamp | rg '<spoke>.*kubeconfig'
```

Extract to `/tmp`, use only for recovery, and delete it when done:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system get secret \
  <spoke>-XXXXX-kubeconfig -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/<spoke>-kubeconfig
chmod 600 /tmp/<spoke>-kubeconfig
shred -u /tmp/<spoke>-kubeconfig
```

## Dev Rebuild Reflection

The dev rebuild succeeded because the manual cluster was replaced by a committed
claim and the runtime restoration moved into idempotent repo fixtures. The risky
parts were not Talos bootstrap itself; they were ownership boundaries, generated
configuration, and the ISO-vs-Kubernetes-version constraint:

- The Hetzner `1.12.4` ISO cannot bootstrap a one-shot Talos `1.13.2` + k8s
  `1.36` claim. Bootstrap k8s on `1.35` first (with `version: 1.13.2` so
  `install.image` installs Talos `1.13.x`), then raise `kubernetesVersion` to
  `1.36`. See "ISO vs Kubernetes Version Constraint".
- Delete manual HCloud resources only after the claim is ready to recreate them.
- If the user narrows scope to dev only, remove staging from Git and live
  Crossplane/Argo ownership before pruning provider resources so staging is not
  reprovisioned.
- Check HCloud placement before selecting server types. `cpx41`/`cpx51` worked
  in `hil`; `cpx42`/`cpx62` were not US-placeable at the time of rebuild.
- Remove stale Argo cluster secrets that still point at old API/certs.
- Clean Tailscale devices/service-hosts before re-authenticating proxies.
- Sync or repair the spoke Tailscale operator if the ProxyGroup auth job waits
  on `proxygroups.tailscale.com`.
- A Terraform workspace can briefly fail while generated control-plane IP lists
  are empty. Inspect the next generation and varmap before recreating again.
- Crossplane claim `Ready=False` can persist from readiness aggregation even
  when individual jobs and the live spoke are healthy; inspect the component
  resources.
- Restart `hub-headlamp` after the Argo `cluster-dev` secret changes because the
  UI kubeconfig is generated at pod startup.
- Treat Argo app health as part of cluster readiness.
- Validate workflow-builder data and Dapr scopes before launching benchmark
  traffic.

For future rebuilds, spend most of the time on preflight inventory, stale-name
cleanup, and post-bootstrap validation. The Crossplane/Talos path should be
boring once the claim schema and composition are correct.
