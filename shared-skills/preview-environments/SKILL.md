---
name: preview-environments
description: "Operate and prove Workflow Builder PreviewEnvironment lifecycles on the dev cluster. Use for system-live combined infrastructure and application development, app-live or candidate profiles, preview-host-development, Dapr Agents builders, greenfield service registration, HMR, the development/debug page, consolidated host runs, MCP preview actions, sleep/wake, durable evidence, and 12-check teardown. Use workflow-builder for ordinary workflow authoring and gitops for persistent delivery."
---

# Preview Environments

`PreviewEnvironment` is a dev-cluster vCluster lifecycle. It is not an agent
Sandbox, a persistent environment, or the ryzen Skaffold loop.

## Start From Current Sources

Read:

- Workflow Builder `docs/preview-environments.md`
- Workflow Builder `docs/preview-environment-agent-development.md`
- Workflow Builder `docs/host-preview-development-lifecycle.md`
- Workflow Builder `docs/execution-evidence.md`
- stacks `docs/preview-environment-architecture.md`
- stacks `docs/host-driven-preview-development.md`
- stacks `docs/preview-environment-runbook.md`

Then inspect the current catalog, application ports/adapters, workflow fixtures,
CRD, runner, policies, and validators. Do not rely on remembered service lists,
capacity counts, image digests, Dapr versions, or run IDs.

## Authority And Architecture

- `PreviewEnvironment` status and controller-owned resources are lifecycle
  truth. Workflow output and logs are evidence.
- The host derives repositories, complete revisions, workspace, target,
  identity, credentials, and policy.
- One immutable tuple binds request ID, platform revision, source revision,
  catalog digest, services, paths, and lifecycle.
- The application core is hexagonal: `DevelopmentChangeSet`,
  `PreviewGeneration`, and `DevelopmentTarget` depend on observation, target,
  impact, and activity ports. Kubernetes, Git, Dapr, HTTP, UI, and MCP are
  adapters.
- Presentation code must not receive namespaces, database URLs, NATS subjects,
  preview credentials, or Kubernetes clients.
- Promotion creates a draft source artifact. Persistent delivery remains a
  separately reviewed GitOps flow.

## Choose A Profile

| Need | Profile |
| --- | --- |
| Infrastructure and application changes in one generation | `system-live` |
| Application-only HMR or PR preview | `app-live` |
| Immutable namespaced stacks validation | `manifest-candidate` |
| Talos/CNI/CSI/host network/storage/Tailscale/argocd-agent | `host-candidate` |

`host-candidate` uses a disposable physical cluster and its dedicated adapter;
it is not a vCluster mode. Hub management, Source Hydrator, and GitOps Promoter
changes have no preview lane.

## Preferred MCP Flow

1. `list_preview_services` and `list_preview_environments`.
2. `launch_system_preview_environment` for combined work, including only
   admitted namespaced `candidatePaths`; use `launch_preview_environment` for
   application-only work.
3. Poll `get_preview_environment` and
   `get_preview_development_system` until the exact generation is Ready.
4. Start `preview-host-development` through
   `start_dev_environment_session`. The simplest target is
   `previewTarget: { previewName }`; the server resolves the origin and pins the
   complete tuple.
5. Follow the host execution with ordinary workflow/session/trace tools and
   the host run page. Use `debug_preview_environment` and
   `query_preview_traces` for tuple-scoped preview diagnostics.
6. For terminal history, allow the telemetry grace and use
   `list_execution_evidence`, `get_execution_evidence`, and one bounded package
   part or telemetry query.
7. Re-read the generation before teardown. Pass its exact request ID and source
   revision to `teardown_preview_environment`, then poll the signed ticket with
   `get_preview_teardown_status` until `12/12`.

Honor server-issued `nextActions`, `telemetry.refreshAfterMs`, pagination, and
generation-fence warnings. `get_preview_development_run` resolves only the
preview-local compatibility child; host attach activity comes from
`get_preview_development_system`.

## Target Strategies

| Target | Strategy |
| --- | --- |
| Cataloged preview Deployment | `deployment-service:hot-reload` |
| Registered `development-module` reference app | `greenfield-module:hot-reload` |
| `dapr-agent-py` | `session-runtime:new-session` |

Dapr workflow history is immutable. For `dapr-agent-py` code, build and pin the
runtime image/config, launch the matching generation, and start a fresh
session. Never document or attempt direct source HMR into an existing Dapr
workflow.

An arbitrary new app needs one-time platform registration: source and
production/dev Dockerfiles, health contract, catalog sync/capture metadata,
preview Deployment/Service, route, and NetworkPolicy. Deliver that registration
first; after it appears in `list_preview_services`, ordinary hot reload applies.

## Host-Driven Development

`preview-host-development` keeps one durable execution, agent sessions, one
JuiceFS checkout, checkpoints, usage, traces, capture, and promotion on host
dev. Only adopted services and sync receivers live in the vCluster.

The default profile is `dapr-agent-py-k3-host`. Automated official CLI profiles
are `claude-code-cli-host`, `codex-cli-host`, and `kimi-code-cli-host`;
`cli-fanout` runs them in that fixed order. Persistent profiles are
`claude-code-cli-interactive-host`, `codex-cli-interactive-host`,
`kimi-code-cli-interactive-host`, and `agy-cli-interactive-host`.

CLI OAuth, pods, native hooks, transcripts, and MCP sessions stay on physical
dev. Never copy them into a preview. Interactive profiles edit the host
checkout, call `wfb-preview-sync` after coherent generations, inspect the
preview through Playwright, and wait for the run page's fixed **Create draft
PR** or **Discard** action.

Operational invariants:

- Write the intent inside each service's catalog `syncPaths`.
- One service set uses one checkout and one atomic generation.
- Require one `APPLIED` receipt per selected service plus global convergence.
- Source-only HMR keeps adopted pod UIDs stable.
- Receiver compile, diff-scope, generation, health, and freeze decisions are
  authoritative.
- Release adoption on every terminal path and allow it to converge before
  another writer attaches.
- Preview-side fixes require a new generation; host-side fixes require a host
  rollout.

The preview-local `preview-development-lifecycle` remains a compatibility path
and now uses Dapr Agents profiles (`kimi-k3-juicefs`,
`dapr-agent-py-k3-code`, `dapr-agent-py-k3-ui`). Do not restore the retired
Pydantic AI runtime.

## Canonical User Surfaces

```text
/workspaces/<slug>/dev/system
/workspaces/<slug>/runs
/workspaces/<owning-workspace>/workflows/preview-host-development/runs/<executionId>
/workspaces/<slug>/evidence
```

The development page shows the immutable generation, target strategies, gates,
and host activity. The run detail's Live tab is primary. Canvas is optional
workflow-definition context and is not a Kubernetes topology. The Runs service
federates host, live preview-local, and sealed sources behind read-only ports;
the UI must stay source-neutral.

## Data And Evidence

- Product data is one disposable logical `preview_<name>` database on physical
  `preview-db` through `preview-db-pooler`; no CNPG database cluster/PVC runs in
  the vCluster.
- Preview-local Dapr and NATS state plus mutable workspaces are disposable.
- Host and preview-local terminal runs are sealed separately as
  `wfb.execution-evidence/v2` packages with long-retention telemetry.
- Preserve prompt/tool content. Mask credential-shaped fields and embedded
  credential values only.
- Incomplete required evidence blocks normal teardown. Failed-generation
  quarantine records explicit loss.

## Teardown

Never substitute raw deletion or namespace absence for the typed contract. The
current terminal result is all twelve checks true:

```text
runnerSucceeded previewEnvironmentAbsent applicationAbsent
agentRegistrationAbsent agentNamespacesAbsent databaseAbsent
natsStreamAbsent headlampRegistrationAbsent tailnetEgressAbsent
hostNamespaceAbsent storageScopeAbsent runnerIdentityAbsent
```

Read refusal details and use only the designed escape path. Stop a live
preview-local child through its preview surface. Let stale host projections
reconcile. Use supported failed-generation quarantine or explicit admin archive
loss only under its positive-host-evidence rules. Never remove finalizers to
skip ownership reconciliation.

## Validation

For Workflow Builder, run focused application-service, adapter, route, fixture,
catalog, and Workflow MCP tests. For stacks, select the changed boundary from
the runbook and include:

```bash
scripts/gitops/validate-preview-vcluster-surface.sh
scripts/gitops/validate-dev-preview-service-catalog.sh
scripts/gitops/validate-preview-application-policy.sh
scripts/gitops/validate-preview-vcluster-sync-contract.sh
deployment/scripts/tests/test-preview-job-launch-boundary.sh
```

Run the Dapr actor-store validator for any Component change. Runner/policy
changes require a rebuilt runner image, a bounded two-digest admission rotation,
rendered pins, and a new platform pointer; stacks text alone does not update an
image-baked runner.

## Safety

- Dev only; do not redirect a proof to ryzen.
- Use fresh worktrees from current `origin/main`; preserve dirty shared trees.
- Do not roll the response path or trigger conflicting Argo reconciliation
  during an active proof.
- Do not print workspace keys, preview credentials, kubeconfigs, broker leaves,
  OAuth, or decrypted secrets.
- Do not merge a proof artifact unless a separate reviewed delivery task owns
  that decision.
