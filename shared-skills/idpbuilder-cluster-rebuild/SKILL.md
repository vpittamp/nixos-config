---
name: idpbuilder-cluster-rebuild
description: Use this skill when recreating or updating the ryzen local development Kubernetes cluster with the vpittamp idpbuilder fork, including destructive rebuilds, GitOps bootstrap, Azure Workload Identity/JWKS, Gitea image seeding, Tailscale cleanup or service-host recovery, readiness timing, and kubeconfig sync to local or ThinkPad workstations.
---

# Idpbuilder Cluster Rebuild

## Workflow

Use this skill for ryzen local-cluster rebuilds and idpbuilder-based cluster updates. Keep the live cluster, the stacks repo, and the idpbuilder fork aligned; do not treat GitOps manifests as proof that a rebuild succeeded until the readiness cohorts pass.

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
3. Prefer the idpbuilder path:
   ```bash
   idpbuilder stacks create --recreate --cluster-name ryzen --seed-images --seed-images-mode release-pins --skip-tekton-builds --refresh-kubeconfig
   ```
4. If ThinkPad needs access, add:
   ```bash
   --push-kubeconfig-host thinkpad
   ```
5. Track readiness and timing with:
   ```bash
   deployment/scripts/cluster-readiness.sh check --cohort all
   deployment/scripts/cluster-readiness.sh summary
   deployment/scripts/cluster-readiness.sh compare-baseline
   ```

## Rebuild Rules

- Use destructive recreation for ryzen when the user leans that way. Preserve unrelated repo changes, but expect the old kind cluster to be disposable.
- Clean Tailscale before and after delete. Stale device names cause `-1`/`-2` suffixes, and stale API service-host records can block ProxyGroup readiness.
- Treat `ryzen-api.tail286401.ts.net` as the current ryzen kube-apiserver ProxyGroup endpoint. `ryzen-k8s-api` can hit Let's Encrypt exact-name rate limits after repeated destructive rebuilds, so do not hard-code it in new kubeconfigs or docs.
- Bootstrap images from GHCR release pins into local Gitea before Argo syncs active-development workloads. Do not depend on fresh Gitea already having ryzen image tags, and do not require spoke-local Tekton to produce first-boot images.
- Keep image copy and manifest rewrite targets distinct: seed/copy to `gitea.cnoe.localtest.me:8443/giteaadmin`, but rewrite active-development manifests to `gitea-ryzen.tail286401.ts.net/giteaadmin`. Fresh kind node pulls now rely on the hostname registry mirror installed by `deployment/scripts/setup-registry-auth.sh`, not a raw registry IP mirror.
- Keep `openshell-sandbox` and `openshell-sandbox-xlsx` in critical image seeding while workflow-builder/OpenShell sandbox template env vars reference them. They are large, but they are used by the default runtime contract.
- Keep hub Tekton as the build plane. Do not reintroduce spoke-local Buildah/Tekton as a prerequisite for the initial ryzen desired state.
- Use Azure Workload Identity/JWKS readiness as a gate before workloads that need External Secrets.
- Refresh kubeconfigs after recreate; use Tailscale SSH/SCP for ThinkPad transfer before retrying `tailscale file cp`.
- Only set or update readiness baselines for clean runs. A run that needed imperative recovery, timed out before desired state, or required manual image rewrite should be recorded as evidence, not promoted as a baseline.
- The developer bootstrap path should not trigger 1Password UI prompts. The idpbuilder fork initializes local passwords as `developer` by using the local ArgoCD auth path (`ARGOCD_AUTH_1PASSWORD=disabled`, `ARGOCD_LOCAL_PASSWORD=developer`) during `argocd-init`.

## References

- Read `references/rebuild-runbook.md` before performing or planning a recreate.
- Read `references/failure-modes.md` when a rebuild stalls, a Tailscale name is suffixed, an image is missing from Gitea, Argo hooks are stuck, External Secrets are not synced, or kubeconfig transfer fails.
