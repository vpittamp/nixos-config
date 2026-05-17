# Idpbuilder Ryzen Rebuild Runbook

## Preflight

Run these from `/home/vpittamp/repos/PittampalliOrg/stacks/main` unless noted.

```bash
git status --short
git -C /home/vpittamp/repos/vpittamp/idpbuilder/main status --short
idpbuilder stacks status --cluster-name ryzen || true
deployment/scripts/tailscale/cleanup-old-devices.sh --cluster ryzen --wait
```

Confirm the idpbuilder binary is the forked one when behavior matters:

```bash
command -v idpbuilder
idpbuilder stacks create --help
```

The expected steady state is the Nix profile binary, not a stale `~/.local/bin/idpbuilder`. On this system the Nix package is built from the local flake input `idpbuilder-src`, which points at `/home/vpittamp/repos/vpittamp/idpbuilder/main`.

Update the installed fork on ryzen without impurity:

```bash
cd /home/vpittamp/repos/vpittamp/nixos-config/main
nix flake lock --update-input idpbuilder-src
nix build .#idpbuilder --no-link
sudo nixos-rebuild switch --flake .#ryzen
command -v idpbuilder
```

Do not pass `--impure` to the NixOS rebuild. If the forked source needs to move, change the flake input or lockfile instead of relying on an impure path lookup.

## Recreate

Default destructive local rebuild:

```bash
idpbuilder stacks create \
  --recreate \
  --cluster-name ryzen \
  --seed-images \
  --seed-images-mode release-pins \
  --skip-tekton-builds \
  --refresh-kubeconfig
```

With ThinkPad kubeconfig sync:

```bash
idpbuilder stacks create \
  --recreate \
  --cluster-name ryzen \
  --seed-images \
  --seed-images-mode release-pins \
  --skip-tekton-builds \
  --refresh-kubeconfig \
  --push-kubeconfig-host thinkpad
```

Timed recreate with log capture:

```bash
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
log_dir="$HOME/.local/state/stacks/recreate-runs/logs"
mkdir -p "$log_dir"
log_file="$log_dir/timed-recreate-${run_id}.log"
TIMEFORMAT='real %3R\nuser %3U\nsys %3S'
{ time idpbuilder stacks create \
  --recreate \
  --cluster-name ryzen \
  --seed-images \
  --seed-images-mode release-pins \
  --skip-tekton-builds \
  --refresh-kubeconfig \
  --push-kubeconfig-host thinkpad; } 2>&1 | tee "$log_file"
```

The current recreate path can run two Tailscale cleanup grace waits: one after deleting stale devices and another immediately before cluster creation. Expect this to add about four minutes when both waits are enabled; if the second cleanup finds nothing, it is an optimization target rather than a failure.

The local developer bootstrap path should establish local credentials as `developer` and must not prompt for 1Password. If a run opens a 1Password UI around ArgoCD initialization, inspect the idpbuilder fork and `deployment/scripts/argocd-auth.sh`; the expected path is `ARGOCD_AUTH_1PASSWORD=disabled` with `ARGOCD_LOCAL_PASSWORD=developer`.

## Readiness Cohorts

The readiness profile lives at `deployment/config/readiness/kind-ryzen.yaml`.

- `bootstrap`: kind API, nodes, Gitea registry, and ArgoCD.
- `gitops-core`: local-core GitOps, Azure WI, External Secrets, Dapr slim runtime, Tailscale operator, and platform dependencies.
- `inner-loop`: workflow-builder system, OpenShell runtime, runtime images, Tekton runtime tasks, and SWE-bench services.
- `access`: canonical Tailscale names, ProxyGroup API service, and local kubeconfig.
- `observability`: ryzen telemetry client path.
- `all`: every non-optional ArgoCD Application.

Useful commands:

```bash
deployment/scripts/cluster-readiness.sh wait --cohort bootstrap
deployment/scripts/cluster-readiness.sh wait --cohort inner-loop
deployment/scripts/cluster-readiness.sh check --cohort all
deployment/scripts/cluster-readiness.sh summary
deployment/scripts/cluster-readiness.sh set-baseline
deployment/scripts/cluster-readiness.sh compare-baseline
```

Only call `set-baseline` after a clean recreate that reaches desired state without imperative recovery. Use failed or recovered runs for improvement notes, not as the timing baseline.

Recent clean-run reference:

```text
total wall time: 19m20s
bootstrap: 846s
gitops-core: 1018s
inner-loop: 1033s
observability: 1129s
all: 1130s
seed-bootstrap-images: 349s
```

Image seeding remains the largest bootstrap phase. It currently runs serially; parallel copy is a valid optimization target, but keep dependency ordering and registry load in mind.

## Image Seeding

Initial image seed source:

```text
packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml
```

Dry-run the seed plan:

```bash
deployment/scripts/bootstrap/seed-ryzen-images.sh --dry-run --mode critical
```

Verify seeded Gitea images:

```bash
deployment/scripts/bootstrap/seed-ryzen-images.sh --verify-only --mode critical
```

The seed script has two registry concerns:

- `DEST_REGISTRY` / `--dest-registry`: where images are copied during bootstrap. Default: `gitea.cnoe.localtest.me:8443/giteaadmin`.
- `REWRITE_REGISTRY` / `--rewrite-registry`: what active-development Kustomize image transforms should reference. Default: `gitea-ryzen.tail286401.ts.net/giteaadmin`.

The seed script writes both provenance tags from release pins and `:latest`
compatibility aliases for critical images, because several runtime paths still
reference `latest` outside Kustomize image transformers.

Keep the manifest rewrite target on the Tailscale Gitea hostname for active-development manifests. For node pulls of seeded bootstrap images, the current registry-auth fix uses a hostname mirror endpoint for `gitea.cnoe.localtest.me:8443`; verify `/etc/containerd/certs.d/gitea.cnoe.localtest.me:8443/hosts.toml` on kind nodes before changing that contract.

Do not suppress these critical sandbox images while their runtime references remain:

- `openshell-sandbox`
- `openshell-sandbox-xlsx`
- `dapr-agent-py-sandbox`

`openshell-sandbox` is large, but it backs the default workflow-builder/OpenShell sandbox template mappings.

## Kubeconfig

Refresh local contexts:

```bash
deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh --cluster ryzen
```

Strictly verify the Tailscale context:

```bash
deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh --cluster ryzen --strict-remote-verify
```

Refresh and push to ThinkPad:

```bash
deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh --cluster ryzen --push-host thinkpad
```

Expected contexts:

```bash
kubectl --context kind-ryzen get nodes
kubectl --context ryzen-cluster get nodes
```

The refresh script should discover `ProxyGroup/k8s-api-cluster.spec.kubeAPIServer.hostname` and currently generate `https://ryzen-api.tail286401.ts.net`. Do not assume `ryzen-k8s-api.tail286401.ts.net`; it can be temporarily unusable after repeated rebuilds due to Let's Encrypt exact-name certificate rate limits.

`argocd-server-tls` and `argocd-webhook-setup` can remain `OutOfSync` but `Healthy` because External Secret generated fields drift. Treat that as a cleanup item, not a blocker for the all-cohort readiness gate.
