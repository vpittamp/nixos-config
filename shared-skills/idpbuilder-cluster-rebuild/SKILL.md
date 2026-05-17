---
name: idpbuilder-cluster-rebuild
description: Use this skill when recreating or updating the authoritative ryzen local development Kubernetes cluster with the vpittamp idpbuilder fork and Talos Docker, including Dockerless Talos-parity runs through rootful Podman, destructive rebuilds, GitOps bootstrap, Azure Workload Identity/JWKS, Gitea image seeding, Tailscale ingress/API recovery, readiness timing, and kubeconfig sync to local or ThinkPad workstations.
---

# Idpbuilder Cluster Rebuild

## Workflow

Use this skill for ryzen local-cluster rebuilds and idpbuilder-based cluster updates. Ryzen is now the Talos Docker local development cluster, not the former kind cluster. The preferred Dockerless parity path runs the Talos Docker provider against rootful Podman's Docker-compatible socket; rootless Podman is explicitly unsupported for this provider. Keep the live cluster, the stacks repo, the Nix profile, and the idpbuilder fork aligned; do not treat GitOps manifests as proof that a rebuild succeeded until the readiness cohorts pass.

1. Inspect the current worktree and live state before mutating anything:
   - stacks repo: `/home/vpittamp/repos/PittampalliOrg/stacks/main`
   - idpbuilder fork: `/home/vpittamp/repos/vpittamp/idpbuilder/main`
   - optional Nix config: `/home/vpittamp/repos/vpittamp/nixos-config/main`
2. Confirm the active binary is the Nix-provided fork. If `~/.local/bin/idpbuilder` shadows the profile binary, move the stale binary aside instead of using it:
   ```bash
   command -v idpbuilder
   idpbuilder stacks create --help
   idpbuilder stacks sync --help | rg -- '--watch|--debounce|--cache-dir|--reset-local-history|--container-engine|--seed-image-push-engine'
   ```
   To update the binary on ryzen, update the flake input in `nixos-config/main`, build it, and rebuild without `--impure`:
   ```bash
   nix flake lock --update-input idpbuilder-src
   nix build .#idpbuilder --no-link
   sudo nixos-rebuild switch --flake .#ryzen
   ```
3. For Dockerless Talos parity, target rootful Podman explicitly. Do not rely on silent fallback to Docker:
   ```bash
   export DOCKER_HOST=unix:///run/podman/podman.sock
   podman info --format '{{.Host.Security.Rootless}}'  # expected: false
   idpbuilder stacks create --help | rg -- '--container-engine|--seed-image-push-engine'
   ```
   If `podman info` reports rootless mode or `DOCKER_HOST` is unset/not a Podman socket, stop and fix the host setup first.
4. Prefer the idpbuilder path. The fork defaults to `--provider talos-docker`, `--cluster-name ryzen`, `--profile ryzen`, and `--overlay packages/overlays/ryzen`; keep those defaults unless you are explicitly testing a legacy path:
   ```bash
   idpbuilder stacks create --recreate --seed-images --seed-images-mode release-pins --skip-tekton-builds --refresh-kubeconfig --container-engine podman --seed-image-push-engine skopeo
   ```
5. Snapshot local manifest changes into the in-cluster Gitea repo without recreating. Use the same container engine flags as the create path so cleanup and Talos socket behavior stay consistent:
   ```bash
   idpbuilder stacks sync --container-engine podman --seed-image-push-engine skopeo
   ```
   The sync path maintains a persistent cache clone at `${XDG_CACHE_HOME:-~/.cache}/idpbuilder/stacks-sync/<cluster>/<owner>/<repo>`, commits only when the rendered tree changes, pushes without force by default, and rewrites release-pinned workflow-builder image references only inside the sync tree. A no-op should print `No changes to sync`.
6. For continuous local iteration, prefer the long-lived sync watcher:
   ```bash
   idpbuilder stacks sync --watch --debounce 2s --container-engine podman --seed-image-push-engine skopeo
   ```
   `dev-watch-only` and `deployment/scripts/devenv-up.sh --watch` should use this direct watch path when supported; the old `watchexec` loop is only a compatibility fallback.
7. If ThinkPad needs access, add:
   ```bash
   --push-kubeconfig-host thinkpad
   ```
8. Track readiness and timing with:
   ```bash
   deployment/scripts/cluster-readiness.sh check --cohort inner-loop
   deployment/scripts/cluster-readiness.sh check --cohort all
   deployment/scripts/cluster-readiness.sh summary
   deployment/scripts/cluster-readiness.sh compare-baseline
   ```

## Rebuild Rules

- Use destructive recreation for ryzen when the user leans that way. Preserve unrelated repo changes, but expect the old kind cluster and the temporary `ryzen-talos` cluster name to be disposable legacy state.
- Use `--container-engine podman --seed-image-push-engine skopeo` for the current Dockerless Talos-parity setup. This keeps `talosctl cluster create docker` but points it at rootful Podman through `DOCKER_HOST`, avoiding Docker daemon and Docker CLI dependencies.
- Use normal `idpbuilder stacks sync` for local GitOps updates. It preserves linear local Gitea history with descendant commits, skips commit/push/Argo refresh when the tree is unchanged, and should be the implementation behind `cluster-update --container-engine podman --seed-image-push-engine skopeo`.
- Use `idpbuilder stacks sync --reset-local-history` only as an explicit recovery action when local Gitea history is unrelated, missing, or corrupted. Normal syncs should fail with `Refusing non-fast-forward push; run with --reset-local-history to replace local Gitea history` rather than force-pushing.
- Do not use rootless Podman with `--provider talos-docker`. Rootless experiments belong on the `kind` provider, or on a future Talos QEMU path if that provider is implemented.
- On NixOS, the expected Podman host setup enables `virtualisation.podman`, keeps `dockerCompat = false`, adds `vpittamp` to the `podman` group, disables the container PID cap with `containers.pids_limit = -1`, and allows Podman bridge DNS in the firewall. After changing group membership, start a fresh login/session or use an equivalent group-refresh path before depending on direct socket access.
- Clean Tailscale before and after delete. Stale device names cause `-1`/`-2` suffixes, and stale API service-host records can block ProxyGroup readiness.
- Treat `ryzen-api.tail286401.ts.net` as the current ryzen kube-apiserver ProxyGroup endpoint. Let `deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh` discover `ProxyGroup/k8s-api-cluster.spec.kubeAPIServer.hostname`; do not pass or document the old `ryzen-k8s-api` service name.
- Bootstrap images from GHCR release pins into local Gitea before Argo syncs active-development workloads. Do not depend on fresh Gitea already having ryzen image tags, and do not require spoke-local Tekton to produce first-boot images.
- Keep image copy and manifest rewrite targets distinct: seed/copy to `gitea.cnoe.localtest.me:8443/giteaadmin`, but rewrite active-development manifests to `gitea-ryzen.tail286401.ts.net/giteaadmin`.
- For large or fragile image copies, the Tailscale Gitea endpoint can be more reliable than a port-forward. Use `gitea-ryzen.tail286401.ts.net/giteaadmin` with `--tls-verify=false` when local certificate verification blocks `skopeo copy`.
- Prefer bounded image seeding parallelism. `seed-ryzen-images.sh` defaults to four jobs; use `--jobs 1` only when reproducing serial behavior.
- Keep `openshell-sandbox` and `openshell-sandbox-xlsx` in critical image seeding while workflow-builder/OpenShell sandbox template env vars reference them. They are large, but they are used by the default runtime contract.
- Keep hub Tekton as the build plane. Do not reintroduce spoke-local Buildah/Tekton as a prerequisite for the initial ryzen desired state.
- Use Azure Workload Identity/JWKS readiness as a gate before workloads that need External Secrets.
- Refresh kubeconfigs after recreate; use Tailscale SSH/SCP for ThinkPad transfer before retrying `tailscale file cp`.
- Stable Tailscale app names remain `*-ryzen` even though the cluster implementation is Talos Docker. Do not rename ingress hosts to `*-ryzen-talos`.
- Ryzen is disposable enough that its Tailscale Ingress ProxyClass can use the `development` class during repeated rebuilds to avoid Let's Encrypt production exact-hostname rate limits. Browser-trusted prod certs require switching back to the production ProxyClass after the rate limit clears.
- Only set or update readiness baselines for clean runs. A run that needed imperative recovery, timed out before desired state, or required manual image rewrite should be recorded as evidence, not promoted as a baseline.
- The developer bootstrap path should not trigger 1Password UI prompts. The idpbuilder fork initializes local passwords as `developer` by using the local ArgoCD auth path (`ARGOCD_AUTH_1PASSWORD=disabled`, `ARGOCD_LOCAL_PASSWORD=developer`) during `argocd-init`.

## References

- Read `references/rebuild-runbook.md` before performing or planning a recreate.
- Read `references/failure-modes.md` when a rebuild stalls, a Tailscale name is suffixed, an image is missing from Gitea, Argo hooks are stuck, External Secrets are not synced, or kubeconfig transfer fails.
