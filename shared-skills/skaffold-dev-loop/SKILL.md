---
name: skaffold-dev-loop
description: "Run or repair the explicit ryzen-only Skaffold loop for Workflow Builder services. Use when the user names ryzen, skaffold, dev:skaffold, deploy:skaffold, HMR, Argo pause/resume, GHCR push, or commit-pin. Use gitops for normal dev-cluster delivery and preview-environments for preview-vCluster development."
---

# Skaffold Dev Loop

This is a specialized `ryzen` loop. Generic requests to deploy or verify
Workflow Builder belong to the dev GitOps lane, not this skill.

## Model

Ryzen runs local autonomous ArgoCD and reconciles `packages/overlays/ryzen` from
GitHub `main`. Skaffold temporarily overrides selected workload Deployments for
file sync and HMR. Repository wrappers pause the corresponding local ArgoCD
Applications, preserve the workload on exit, and resume reconciliation.

There are two distinct operations:

- **Inner loop:** build a development image, deploy it to ryzen, and sync source
  into the running pod.
- **Outer loop:** build/push a production image and commit the ryzen image pin to
  `stacks/main` through the repository's commit-pin helper.

## Preflight

Work from a clean Workflow Builder worktree and run the read-only doctor first:

```bash
cd /home/vpittamp/repos/PittampalliOrg/workflow-builder/main
pnpm skaffold:doctor
pnpm --silent skaffold:doctor -- --json
```

Confirm the kubectl context is `admin@ryzen`, GHCR authentication works, local
ryzen Applications are healthy and unpaused, and the requested service is in
the module registry. Read `scripts/_modules.sh` and the wrapper before changing
module ownership or app mappings.

## Inner Loop

Use wrappers, not bare `skaffold dev`:

```bash
pnpm dev:skaffold
pnpm dev:skaffold:orchestrator
bash scripts/skaffold-dev.sh <service> [<service>...]
```

The wrapper owns:

1. Mapping modules to local `ryzen-<service>` Applications.
2. Setting `argocd.argoproj.io/skip-reconcile=true`.
3. Registry and Skaffold profile selection.
4. `--cleanup=false` so the service is not deleted on exit.
5. Trap-based ArgoCD resume and hard refresh.

After the loop starts, verify an edited synced file appears in the pod and the
service reloads. On exit, verify the skip-reconcile annotation is gone and
ArgoCD restores the committed image.

If a killed session leaves an app paused, recover from the Workflow Builder
root with the repository hook:

```bash
ARGO_APPS=ryzen-<service> bash skaffold/hooks/argo-resume.sh
```

## Outer Loop

Use the repository wrapper:

```bash
pnpm deploy:skaffold
pnpm deploy:skaffold:orchestrator
bash scripts/skaffold-deploy.sh <service> [<service>...]
```

The wrapper builds and pushes the image, parses its immutable reference, and
calls `skaffold/hooks/commit-pin.sh`. The pin helper uses its own cache clone,
updates the owning ryzen pin, runs the stacks renderer for generated
Workflow Builder pin components, pushes `main`, and hard-refreshes the local
Application. Do not edit the generated component by hand.

When GitHub's dev outer loop already built a just-merged service SHA, do not
rebuild the same mutable `git-<sha>` tag on ryzen: two builders can produce
different digests and invalidate release provenance. Commit-pin the existing
GHCR image reference instead, using the helper's supported `SKAFFOLD_IMAGE`
input.

## Verification

For inner-loop completion, prove:

- The selected pod is Ready with its Dapr sidecar where required.
- File sync and HMR/reload work for an actual edit.
- The local ArgoCD Application was paused only for the session.
- Exit resumes reconciliation and restores the committed image.

For outer-loop completion, prove:

- GHCR contains the built tag and expected digest.
- The pin commit exists on `stacks/main` and generated files match their
  renderer.
- `root-ryzen` and `ryzen-<service>` are `Synced`/`Healthy`.
- The live Deployment image matches the committed pin.
- The user-facing route or API behavior works.

## Safety Rules

- Never run bare `skaffold dev` or `skaffold run`; the wrappers encode ArgoCD,
  registry, cleanup, and pin invariants.
- Never use this loop against dev, hub, or staging.
- Never force-reset the user's primary stacks checkout; commit-pin owns a
  dedicated cache clone.
- Never leave `skip-reconcile=true` after the session.
- Never hand-edit generated ryzen image components.
- Do not run broad `ALL` loops without checking resource headroom.

## Canonical Sources

- `skaffold.yaml`
- `skaffold/dev/`
- `scripts/_modules.sh`
- `scripts/skaffold-{doctor,status,dev,deploy}.sh`
- `skaffold/hooks/{argo-pause,argo-resume,commit-pin}.sh`
- stacks `scripts/gitops/render-workflow-builder-release-overlays.sh`
- stacks `packages/overlays/ryzen/`
