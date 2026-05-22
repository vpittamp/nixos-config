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
idpbuilder stacks sync --help | rg -- '--watch|--debounce|--cache-dir|--reset-local-history|--refresh-mode|--sync-wait-timeout|--print-refresh-plan|--container-engine|--seed-image-push-engine|--seed-images'
```

The expected steady state is the Nix profile binary, not a stale `~/.local/bin/idpbuilder`. On this system the Nix package is built from the local flake input `idpbuilder-src`, which points at `/home/vpittamp/repos/vpittamp/idpbuilder/main`.

Update the installed fork on ryzen without impurity:

```bash
cd /home/vpittamp/repos/vpittamp/nixos-config/main
nix flake lock --update-input idpbuilder-src
nix build .#idpbuilder --no-link
sudo nixos-rebuild switch --flake .#ryzen
command -v idpbuilder
idpbuilder stacks create --help | rg -- '--container-engine|--seed-image-push-engine'
idpbuilder stacks sync --help | rg -- '--watch|--debounce|--cache-dir|--reset-local-history|--refresh-mode|--sync-wait-timeout|--print-refresh-plan|--container-engine|--seed-image-push-engine|--seed-images'
```

Do not pass `--impure` to the NixOS rebuild. If the forked source needs to move, change the flake input or lockfile instead of relying on an impure path lookup. Do not leave a temporary `nix profile` idpbuilder overlay in place; the declarative profile should provide the active binary after rebuild.

For the current Dockerless Talos-parity setup, verify rootful Podman before create or sync:

```bash
export DOCKER_HOST=unix:///run/podman/podman.sock
podman info --format '{{.Host.Security.Rootless}}'  # expected: false
idpbuilder stacks create --help | rg -- '--container-engine|--seed-image-push-engine'
```

If this reports `true`, do not continue with `--provider talos-docker`. The Talos Docker provider needs rootful Podman on the Docker-compatible socket. Keep `virtualisation.podman.dockerCompat = false`; the idpbuilder flags select Podman explicitly rather than replacing the Docker CLI globally.

## Recreate

Default destructive local rebuild. The idpbuilder fork defaults to the authoritative ryzen Talos Docker setup: `--provider talos-docker`, `--cluster-name ryzen`, `--profile ryzen`, and `--overlay packages/overlays/ryzen`.

```bash
idpbuilder stacks create \
  --recreate \
  --seed-images \
  --seed-images-mode release-pins \
  --skip-tekton-builds \
  --refresh-kubeconfig \
  --container-engine podman \
  --seed-image-push-engine skopeo
```

With ThinkPad kubeconfig sync:

```bash
idpbuilder stacks create \
  --recreate \
  --seed-images \
  --seed-images-mode release-pins \
  --skip-tekton-builds \
  --refresh-kubeconfig \
  --push-kubeconfig-host thinkpad \
  --container-engine podman \
  --seed-image-push-engine skopeo
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
  --seed-images \
  --seed-images-mode release-pins \
  --skip-tekton-builds \
  --refresh-kubeconfig \
  --push-kubeconfig-host thinkpad \
  --container-engine podman \
  --seed-image-push-engine skopeo; } 2>&1 | tee "$log_file"
```

The recreate path should only wait for Tailscale cleanup grace periods when it actually deleted stale devices or service-hosts. If a no-op cleanup waits anyway, treat that as a regression in the inner-loop rebuild path.

The local developer bootstrap path should establish local credentials as `developer` and must not prompt for 1Password. If a run opens a 1Password UI around ArgoCD initialization, inspect the idpbuilder fork and `deployment/scripts/argocd-auth.sh`; the expected path is `ARGOCD_AUTH_1PASSWORD=disabled` with `ARGOCD_LOCAL_PASSWORD=developer`.

## Sync Without Recreate

Use `stacks sync` after local manifest edits, release-pin rewrites, or Tailscale ingress fixes when the cluster itself does not need to be rebuilt:

```bash
idpbuilder stacks sync --container-engine podman --seed-image-push-engine skopeo --seed-images=false
```

The sync path snapshots the local stacks worktree into in-cluster Gitea and preserves active-development image pins by default. It uses the same default provider, profile, and overlay as `stacks create`. Seed-image rewrites are explicit bootstrap/recovery behavior: `stacks create` still seeds by default, while `stacks sync` requires `--seed-images=true` and warns when it rewrites active-development kustomizations.

Current sync behavior is cache-backed, not a fresh root commit per run:

- Cache clone: `${XDG_CACHE_HOME:-~/.cache}/idpbuilder/stacks-sync/<cluster>/<owner>/<repo>`, overridable with `--cache-dir`.
- Source selection preserves tracked files, tracked modifications, and untracked non-ignored files using Git's `ls-files --cached --others --exclude-standard` view.
- Deleted files are removed from the cache tree before commit.
- Seed-image rewrites, when explicitly enabled, happen only inside the sync/cache tree, never in the source worktree.
- A per-cluster/repo/branch lock is held for the full one-shot sync or watch lifetime. Lock contention should fail fast with cluster/repo/branch/cache context; stop the active watcher/sync or use a separate cache/branch intentionally.
- Unchanged sync trees skip commit, push, and ArgoCD refresh and should print `No changes to sync`.
- Changed sync trees push a normal descendant commit and then default to `--refresh-mode=affected`: compute affected ArgoCD Applications from live app sources plus local Kustomize dependency closures, hard-refresh only those apps, and wait for each refreshed app to observe the pushed commit.
- App-of-apps changes refresh `root-application` first, re-list live Applications, then refresh affected children. Raw manifest Application directories should include a `kustomization.yaml` when the ArgoCD Application uses `source.kustomize` options or patches.
- The Gitea system webhook to `http://argocd-server.argocd.svc.cluster.local/api/webhook` should exist and be active, but webhook-only refresh is not the ryzen hot path because the webhook payload repo URL does not match the internal repoURL used by Applications.

Useful refresh flags:

```bash
idpbuilder stacks sync --print-refresh-plan --container-engine podman --seed-image-push-engine skopeo --seed-images=false
idpbuilder stacks sync --refresh-mode=affected --sync-wait-timeout=3m --container-engine podman --seed-image-push-engine skopeo --seed-images=false
idpbuilder stacks sync --refresh-mode=all --container-engine podman --seed-image-push-engine skopeo --seed-images=false   # explicit recovery only
idpbuilder stacks sync --refresh-mode=none --container-engine podman --seed-image-push-engine skopeo --seed-images=false  # snapshot-only tests
```

The `cluster-update --container-engine podman --seed-image-push-engine skopeo` wrapper should delegate to this sync path and preserve those flags.

For continuous local iteration:

```bash
idpbuilder stacks sync --watch --debounce 2s --container-engine podman --seed-image-push-engine skopeo --seed-images=false
```

`dev-watch-only` and `deployment/scripts/devenv-up.sh --watch` should start the direct idpbuilder watcher when the installed binary supports it. The legacy `watchexec` repeated one-shot sync loop is only a fallback for old binaries. For a supervised opt-in watcher on ryzen, source `deployment/scripts/cluster-menu.sh` and use `cluster-watch-start`, `cluster-watch-status`, `cluster-watch-logs`, `cluster-watch-stop`, or `cluster-watch-enable`.

If local Gitea history is unrelated, missing, or corrupted, normal sync should refuse a non-fast-forward push. Use this only as an explicit recovery action:

```bash
idpbuilder stacks sync --reset-local-history --container-engine podman --seed-image-push-engine skopeo --seed-images=false
```

Expected quick checks:

```bash
cluster-update --container-engine podman --seed-image-push-engine skopeo
timeout 6 deployment/scripts/devenv-up.sh --watch
```

A no-op `cluster-update` should print `No changes to sync`. The timed watch check should show the direct idpbuilder watch path starting; timeout interruption is expected.

## Readiness Cohorts

The readiness profile lives at `deployment/config/readiness/ryzen.yaml`. The former `deployment/config/readiness/kind-ryzen.yaml` profile is legacy.

- `bootstrap`: Talos Docker API, nodes, Gitea registry, and ArgoCD.
- `gitops-core`: local-core GitOps, Azure WI, External Secrets, Dapr slim runtime, Tailscale operator, and platform dependencies.
- `inner-loop`: workflow-builder system, OpenShell runtime, runtime images, Tekton runtime tasks, and SWE-bench services.
- `access`: canonical Tailscale names, ProxyGroup API service, and local kubeconfig.
- `observability`: ryzen telemetry client path.
- `all`: every non-optional ArgoCD Application.

Useful commands:

```bash
deployment/scripts/cluster-readiness.sh wait --cohort bootstrap
deployment/scripts/cluster-readiness.sh wait --cohort inner-loop
deployment/scripts/cluster-readiness.sh check --cohort inner-loop
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

Image seeding remains a major bootstrap phase. It now uses bounded parallelism by default; keep each image's pinned tag and `latest` alias ordered per image while allowing different images to copy concurrently.

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
deployment/scripts/bootstrap/seed-ryzen-images.sh --verify-only --mode critical --jobs 4 --no-latest-aliases --quiet
```

The seed script has two registry concerns:

- `DEST_REGISTRY` / `--dest-registry`: where images are copied during bootstrap. Default: `gitea.cnoe.localtest.me:8443/giteaadmin`.
- `REWRITE_REGISTRY` / `--rewrite-registry`: what active-development Kustomize image transforms should reference. Default: `gitea-ryzen.tail286401.ts.net/giteaadmin`.

The seed script writes both provenance tags from release pins and `:latest`
compatibility aliases for critical images, because several runtime paths still
reference `latest` outside Kustomize image transformers.

Keep the manifest rewrite target on the Tailscale Gitea hostname for active-development manifests. Talos Docker node pulls should continue to resolve `gitea.cnoe.localtest.me:8443` through the ryzen registry-auth path; do not replace this with a hard-coded pod IP.

When creating the cluster through rootful Podman, pass `--seed-image-push-engine skopeo`. This makes the bootstrap seeding path use skopeo copy against the local Gitea registry instead of depending on a Docker daemon or Docker CLI.

For large image mirrors or port-forward instability, copy through the Tailscale Gitea endpoint:

```bash
skopeo copy --dest-tls-verify=false docker://ghcr.io/pittampalliorg/<image>:<tag> docker://gitea-ryzen.tail286401.ts.net/giteaadmin/<image>:<tag>
```

Use `--tls-verify=false` or the destination-specific equivalent when local certificate verification blocks the copy. Keep both `openshell-sandbox` and `openshell-sandbox-xlsx` seeded while workflow-builder/OpenShell runtime configuration references them.

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
kubectl --context admin@ryzen get nodes
kubectl --context ryzen-cluster get nodes
```

The refresh script should discover `ProxyGroup/k8s-api-cluster.spec.kubeAPIServer.hostname` and currently generate `https://ryzen-api.tail286401.ts.net`. Do not assume `ryzen-k8s-api.tail286401.ts.net`; it can be temporarily unusable after repeated rebuilds due to Let's Encrypt exact-name certificate rate limits.

## Tailscale Ingresses

Stable ryzen app ingress names remain `*-ryzen`, for example `workflow-builder-ryzen.tail286401.ts.net`. Do not rename them to `*-ryzen-talos`; the Talos Docker implementation replaced the old cluster substrate, not the external service names.

Repeated destructive rebuilds can exhaust Let's Encrypt production exact-hostname issuance for disposable ryzen Ingresses. If canonical Tailscale Ingress devices are online but HTTPS provisioning stalls with a production certificate rate-limit error, use the `development` Tailscale ProxyClass for the ryzen minimal ingress set. This makes `curl -k https://workflow-builder-ryzen.tail286401.ts.net/` a valid smoke test while the browser-visible certificate is staging-issued. Switch back to the production ProxyClass only after the Let's Encrypt window clears and a browser-trusted cert is required.

`argocd-server-tls` and `argocd-webhook-setup` can remain `OutOfSync` but `Healthy` because External Secret generated fields drift. Treat that as a cleanup item, not a blocker for the all-cohort readiness gate.
