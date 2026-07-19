# Reference: hub vs spoke app placement

Use this policy when deciding where a new app belongs in the stacks hub-and-spoke model.

## Centralize on hub

Run an app once on the hub when its primary job is cross-cluster coordination, release management, lifecycle management, or operator visibility:

- ArgoCD, GitOps Promoter, source-hydrator configuration, and Promoter UI.
- Hub Tekton outer-loop builds (GitHub → GHCR via the `github-outer-loop` EventListener), webhook handling, GHCR release automation, and release metadata validation. (The gitea dev-image build lane + gitea registry were retired.)
- Scripted Talos/Hetzner lifecycle automation and argocd-agent enrollment support. Crossplane spoke lifecycle is retired.
- Deployment inventory and release dashboards.
- NocoDB, Redash, and similar cross-cluster management/reporting UIs.
- Shared portal or identity services such as Backstage and Keycloak, if re-enabled.
- Long-retention observability storage and fleet-wide query UIs, when spokes can forward telemetry reliably.

## Keep per-spoke

Run an app per spoke when it is part of workload runtime, owns environment data, or must keep working if hub connectivity is degraded:

- workflow-builder and runtime services.
- Dapr runtime, workflow runtime sidecars, and app-local data-plane components.
- cert-manager, External Secrets Operator using the hub-secrets transport, CNI, ingress controller, and storage provisioner.
- OpenShell/agent sandbox CRDs and controllers that are required by runtime workloads (`agent-sandbox-crds`, `agent-sandbox`, `openshell-agent-runtime`).
- Tailscale operator resources needed for that cluster's ingress, egress, and Kubernetes API access.
- Per-environment databases, queues, caches, migrations, and local runtime state.
- Spoke-local observability agents and collectors.

## Keep ryzen-local

Ryzen is intentionally not a promoted release stage. Keep these local unless there is a separate release use case:

- Ryzen image tags committed straight to `main` (delivered via GHCR; the local Gitea registry is retired).
- Skaffold hot-reload flow and ryzen-only iteration tooling.
- Local-only build helpers that exist to shorten the edit-build-test loop.
- Apps that require workstation-local services or KIND-specific infrastructure.

## Placement rules

- If operators use it to manage multiple clusters, put the service on hub and add spoke agents/access grants only where needed.
- If production traffic depends on it during a hub outage, put it on each spoke.
- If it contains environment data, prefer per-spoke unless the product explicitly needs shared state.
- If it exists only for local development velocity, keep it ryzen-local and out of GitOps Promoter.
- If it affects active dev release state, route it through GitHub, Source Hydrator, and GitOps Promoter. Staging is dormant until explicitly re-enabled.
- If it is an image build workload, default it to the hub build pool. Spokes may own image tags and runtime manifests, but they should not run Buildah unless the task is explicitly local-only.
- If an app is legacy, remove it declaratively and let Argo prune. AutoKube is currently legacy/removed; do not repair it unless it is explicitly reintroduced.
