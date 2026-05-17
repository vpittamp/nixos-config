---
name: idpbuilder-cluster-rebuild
description: Use this skill when recreating or updating the authoritative ryzen local development Kubernetes cluster with the vpittamp idpbuilder fork and Talos Docker, including destructive rebuilds, GitOps bootstrap, Azure Workload Identity/JWKS, Gitea image seeding, Tailscale ingress/API recovery, readiness timing, and kubeconfig sync to local or ThinkPad workstations.
---

# Idpbuilder Cluster Rebuild

## Workflow

Use this skill for ryzen local-cluster rebuilds and idpbuilder-based cluster updates. Ryzen is now the Talos Docker local development cluster, not the former kind cluster. Keep the live cluster, the stacks repo, and the idpbuilder fork aligned; do not treat GitOps manifests as proof that a rebuild succeeded until the readiness cohorts pass.

1. Inspect the current worktree and live state before mutating anything:
   - stacks repo: `/home/vpittamp/repos/PittampalliOrg/stacks/main`
   - idpbuilder fork: `/home/vpittamp/repos/vpittamp/idpbuilder/main`
   - optional Nix config: `/home/vpittamp/repos/vpittamp/nixos-config/main`
2. Confirm the active binary is the Nix-provided fork. If `~/.local/bin/idpbuilder` shadows the profile binary, move the stale binary aside instead of using it:
   ```bash
   command -v idpbuilder
   idpbuilder stacks create --help
   ```
   To update the binary on ryzen, update the flake input in `nixos-config/main`, build it, and rebuild without `--impure`:
   ```bash
   nix flake lock --update-input idpbuilder-src
   nix build .#idpbuilder --no-link
   sudo nixos-rebuild switch --flake .#ryzen
   ```
3. Prefer the idpbuilder path. The fork defaults to `--provider talos-docker`, `--cluster-name ryzen`, `--profile ryzen`, and `--overlay packages/overlays/ryzen`; keep those defaults unless you are explicitly testing a legacy path:
   ```bash
   idpbuilder stacks create --recreate --seed-images --seed-images-mode release-pins --skip-tekton-builds --refresh-kubeconfig
   ```
4. Snapshot local manifest changes into the in-cluster Gitea repo without recreating:
   ```bash
   idpbuilder stacks sync
   ```
   The sync path rewrites release-pinned workflow-builder image references to local Gitea references for ryzen.
5. If ThinkPad needs access, add:
   ```bash
   --push-kubeconfig-host thinkpad
   ```
6. Track readiness and timing with:
   ```bash
   deployment/scripts/cluster-readiness.sh check --cohort inner-loop
   deployment/scripts/cluster-readiness.sh check --cohort all
   deployment/scripts/cluster-readiness.sh summary
   deployment/scripts/cluster-readiness.sh compare-baseline
   ```

## Rebuild Rules

- Use destructive recreation for ryzen when the user leans that way. Preserve unrelated repo changes, but expect the old kind cluster and the temporary `ryzen-talos` cluster name to be disposable legacy state.
- Clean Tailscale before and after delete. Stale device names cause `-1`/`-2` suffixes, and stale API service-host records can block ProxyGroup readiness.
- Treat `ryzen-api.tail286401.ts.net` as the current ryzen kube-apiserver ProxyGroup endpoint. Let `deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh` discover `ProxyGroup/k8s-api-cluster.spec.kubeAPIServer.hostname`; do not pass or document the old `ryzen-k8s-api` service name.
- Bootstrap images from GHCR release pins into local Gitea before Argo syncs active-development workloads. Do not depend on fresh Gitea already having ryzen image tags, and do not require spoke-local Tekton to produce first-boot images.
- Keep image copy and manifest rewrite targets distinct: seed/copy to `gitea.cnoe.localtest.me:8443/giteaadmin`, but rewrite active-development manifests to `gitea-ryzen.tail286401.ts.net/giteaadmin`.
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
