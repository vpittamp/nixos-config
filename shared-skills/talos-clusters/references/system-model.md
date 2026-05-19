# Pittampalli Talos Cluster System Model

Use this when changing or debugging Talos clusters in `PittampalliOrg/stacks`.

## Architecture

The hub is a Hetzner/Talos Kubernetes cluster. It runs Crossplane, ArgoCD,
source-hydrator, GitOps Promoter, Tailscale operator, and hub Tekton. Dev and
staging are spokes. Their infrastructure is created from Crossplane claims on
the hub, then their workload Applications are registered into hub ArgoCD.

The expected control path is:

1. Edit and commit a spoke claim/composition in `stacks`.
2. Hub Argo applies Crossplane providers, XRDs, compositions, and claims.
3. Crossplane creates HCloud network/firewall/servers and a Terraform Workspace
   for Talos config/bootstrap.
4. Onboarding jobs register the spoke with hub ArgoCD and key vault, create
   spoke bootstrap resources, and authenticate the Kubernetes API ProxyGroup.
5. Source-hydrator renders the spoke overlay and Promoter merges the generated
   branch.
6. Hub ArgoCD syncs the spoke workload Applications to the new cluster.

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
    version: "1.12.4" # Verify live node OS; ISO/defaults may install newer Talos.
    kubernetesVersion: "1.35.0"
    isoId: "125127"
  onboarding:
    enableOnboarding: true
    tailnetDomain: tail286401.ts.net
    tailnet: vpittamp.github
    azureKeyVaultName: keyvault-thcmfmoo5oeow
    repoUrl: https://github.com/PittampalliOrg/stacks.git
    overlayPath: packages/overlays/dev
```

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
packages/overlays/dev/
packages/overlays/staging/
packages/base/manifests/tailscale-ingresses/
packages/components/hub-base/manifests/ProxyGroup-kube-apiserver.yaml
docs/recreate-disposable-dev.md
docs/tailscale-naming.md
docs/tailscale-hostname-reuse-strategy.md
```

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

The dev Kubernetes `1.35.0` rebuild succeeded because the manual cluster was
replaced by a committed claim and the runtime restoration moved into idempotent
repo fixtures. The risky parts were not Talos bootstrap itself; they were
ownership boundaries and generated configuration:

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
