# gitops skill

Comprehensive operational knowledge for the **PittampalliOrg/stacks** hub-and-spoke gitops system, packaged as a single Claude Code / Codex / Gemini skill with progressive disclosure.

## What it covers

- **Image promotion lifecycle** — the two image-pin systems (release-pins vs active-development), how outer-loop and inner-loop Tekton pipelines interact, direct-main vs PR-mode release handoffs, post-push ryzen/dev verification, and branch reconciliation between `origin/main` and `gitea-ryzen/main`.
- **Deployment visibility** — workflow-builder admin Deployments inventory, including desired images, live images, drift, promotion SHAs, and build metadata.
- **Workflow-builder MCP/auth runtime** — ActivePieces piece MCP KService reconciliation, searchable MCP catalog, OAuth connection binding, AgentRuntime bootstrap, Dapr statestore durability checks, and stale sidecar readiness recovery.
- **GitOps Promoter operations** — controller upgrades, hub `stacks-environments` promotion, and the ArgoCD UI extension used to visualize Promoter resources.
- **ArgoCD health/drift review** — fleet-wide OutOfSync/Degraded triage, keep/remove decisions for legacy resources, and stable handling of controller default drift.
- **App placement policy** — which apps belong on hub, per-spoke, or ryzen-local.
- **Recovery runbooks** — stuck PromotionStrategy, db-migrate Job finalizer hangs, Tailscale Funnel orphan tags, device-backed Tailscale Ingress DNS/status issues, ProxyGroup service-host VIPs, missing ghcr.io tags.
- **Spoke cluster access** — Tailscale primary path + Crossplane-managed kubeconfig fallback.
- **Secret rotation** — KeyVault → ExternalSecret → pod env chain, including the ESO refresh ↔ pod restart race.

## Layout

```
shared-skills/gitops/
├── SKILL.md                          ← entry doc (decision tree, matrix, gotchas)
├── agents/openai.yaml                ← Codex UI metadata
├── reference/
│   ├── architecture.md               ← cluster model, two-image-pin flow, branch model
│   ├── app-placement.md              ← hub-vs-spoke placement policy
│   ├── access-paths.md               ← how to reach hub/spokes/ArgoCD/registries
│   └── secret-flow.md                ← KV → ESO → pod chain + per-spoke key naming
└── runbooks/
    ├── promote-image-to-spokes.md
    ├── bump-image-pin-not-in-release-pins.md  ← browserstation, chrome-sandbox, AGENT_RUNTIME_*_DEFAULT_IMAGE
    ├── upsert-workflow-json.md                ← workflow JSON spec → DB UPDATE (image rebuild does not roll specs)
    ├── reconcile-branches.md
    ├── mirror-image-gitea-to-ghcr.md
    ├── manage-gitops-promoter.md          ← controller upgrades + ArgoCD Promoter UI extension
    ├── review-argocd-app-health.md        ← OutOfSync/Degraded fleet review + legacy cleanup decisions
    ├── recover-stuck-promotion.md
    ├── recover-stuck-job-finalizer.md
    ├── debug-funnel-orphan-tag.md          ← covers BOTH funnel-NXDOMAIN and EL-202-no-PipelineRun modes
    ├── debug-device-backed-tailscale-ingress.md ← app Ingress DNS suffix/status/stale tailnet records
    ├── debug-proxygroup-service-host.md    ← service-host VIPs such as argocd-hub and gitops-inventory-hub
    ├── fix-drizzle-migration.md            ← drizzle-kit silent journal-skip + dual atlas/drizzle dirs
    ├── debug-workflow-builder-mcp-auth.md  ← ActivePieces MCP auth/catalog/AgentRuntime/Dapr bootstrap triage
    ├── debug-dapr-sidecar-stale-readiness.md ← `daprd` readiness false / workflow-builder pod `1/2`
    ├── track-promotion-state.md            ← PromotionStrategy + ChangeTransferPolicy CLI cheat-sheet
    ├── access-spoke-cluster-fallback.md
    └── rotate-oauth-secret.md
```

Each runbook follows the same shape: **Symptoms** → **Diagnostic** → **Fix steps** → **Verify**.

## How it's wired into the agent toolchain

This directory is the canonical source. Per-agent discovery directories link to it as git-tracked symlinks:

- `nixos-config/main/.claude/skills/gitops` → `../../shared-skills/gitops` (auto-discovered by `claude-code.nix` via `builtins.readDir`)
- `nixos-config/main/.codex/skills/gitops` → `../../shared-skills/gitops` (auto-discovered by `codex.nix`; `materializeCodexSkills` activation copies symlinks → real files at home-manager activation)
- `nixos-config/main/.gemini/skills/gitops` → `../../shared-skills/gitops` (auto-discovered by `gemini-cli.nix`)

No `.nix` module changes are required to add or remove a skill — Nix reads each agent's `.skills/` directory at home-manager build time. To add a new skill, drop a directory in `shared-skills/<name>/` and create the three discovery symlinks.

## Source-of-truth relationship to stacks/docs

The runbook content was seeded from these docs in `PittampalliOrg/stacks/main/`:

| Skill file | Stacks-docs source |
|---|---|
| `reference/architecture.md` | `docs/outer-loop-promotion.md`, `docs/gitops-architecture-overview.md` |
| `reference/app-placement.md` | `docs/hub-spoke-app-placement.md` |
| `reference/access-paths.md` | `docs/spoke-cluster-access.md`, `docs/hub-and-spoke-quickstart.md`, `docs/tailscale-naming.md` |
| `reference/secret-flow.md` | `docs/oauth-rotation.md`, `packages/components/hub-spoke-appsets/apps/spoke-workloads-appset.yaml` |
| `runbooks/*.md` | `docs/outer-loop-promotion.md` "Recovery Runbooks", `docs/oauth-rotation.md`, `docs/spoke-cluster-access.md`, `packages/components/hub-management/manifests/gitops-promoter/gitops-deployment-inventory.yaml`, `packages/components/hub-management/manifests/argocd-gitops-promoter-ui/`, recent ArgoCD health cleanups |

The stacks docs remain the canonical living reference. **The skill is a periodic snapshot** with a curated decision tree on top — re-sync after any major recovery procedure change in stacks.

## Updating

1. Edit the relevant `.md` files under `shared-skills/gitops/`.
2. Validate frontmatter (`SKILL.md` must parse as YAML in the leading `---`-delimited block).
3. `sudo nixos-rebuild switch --flake .#<target>` (`ryzen` or `thinkpad`) — the changes flow through home-manager to each agent's discovery directory.
4. Test in a fresh agent session by triggering the skill with a phrase from `description`.

When the underlying stacks system changes (new failure modes, new image pinning paths, new spoke onboarding pattern, or a legacy app is removed), update both the stacks docs **and** this skill.
