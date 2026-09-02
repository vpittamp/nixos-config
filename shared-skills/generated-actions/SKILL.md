---
name: generated-actions
description: "Create, validate, save, promote, or debug Workflow Builder generated actions backed by Kiota and OpenAPI. Use for thin gen/* operations, composite typed-client actions, kiota-mcp package handles, save_generated_action, generated-action runtime/proxy behavior, source seeding, and DevelopmentRun promotion. Use workflow-builder to call an existing catalog action and gitops for persistent delivery proof."
---

# Generated Actions

Generated actions turn an allowlisted OpenAPI operation into an immutable,
schema-validated `gen/*` action. Resolve the current contract from:

```bash
WFB_ROOT=/home/vpittamp/repos/PittampalliOrg/workflow-builder/main
STACKS_ROOT=/home/vpittamp/repos/PittampalliOrg/stacks/main
git -C "$WFB_ROOT" show origin/main:docs/generated-actions.md
```

The product document, `services/kiota-mcp`,
`services/generated-action-runtime`, generated-action application ports, and
current stacks manifests are authoritative. Do not infer live versions or tool
inventory from this skill.

## Choose The Path

| Need | Path |
| --- | --- |
| Call an existing action | Use `workflow-builder`: discover it with `list_available_actions { slug }`, then call `action(slug, input, { connection })`. |
| One OpenAPI operation | Thin action: package deterministically with `kiota_package_action`; no coding agent or DevelopmentRun is needed. |
| Compose several typed client calls | Composite action: use a canonical DevelopmentRun, `kiota_generate`, `kiota_package_composite`, live verification, catalog save, source capture, and `promote_run_to_pr`. |
| Diagnose image, pin, seed, or live runtime drift | Use `gitops` after identifying the generated-action boundary that failed. |

## Thin Action

1. Use `kiota_search` or an operator-approved HTTPS description URL.
2. Use `kiota_show` with narrow `includePaths` and an explicit `#METHOD`.
3. Call `kiota_package_action` with an immutable `gen/<api>/<operation>` slug
   and version. Keep the slice narrow enough to remain inside package bounds.
4. Pass the returned `packageUrl` handle to
   `save_generated_action`. Prefer the handle; do not paste a large generated
   client through a model turn. Use `packageJson` only for a genuinely small
   package, and never pass both fields.
5. Re-read the action with `list_available_actions { slug }`, validate the
   required input and connection policy, then run one representative script.

The same inputs must produce the same thin package. Do not hand-edit generated
client files or an action row. A behavioral change gets a new version.

## Composite Action

Use an `app-live` or `system-live` PreviewEnvironment plus a canonical
DevelopmentRun when an agent must write `main(input, ctx)` around a typed Kiota
client. Follow `preview-environments` for lifecycle and proof.

- Generate into the run's bounded checkout with `kiota_generate`; preserve
  `kiota-lock.json`, the sliced description, `action.json`, client files, and
  `src/main.ts` under `services/generated-actions/<api>/<operation>/`.
- Agent code receives only `ctx.fetch`, `ctx.callOperation`, `ctx.adapter`, and
  `ctx.baseUrl`. It must not read process credentials, database state, cluster
  APIs, or unrestricted network clients.
- Package with `kiota_package_composite`, save through the returned handle, and
  verify the catalog row and one real execution before promotion.
- Promote the DevelopmentRun's captured source version with
  `promote_run_to_pr`. When several unpromoted versions exist, inspect the
  returned list and pass the intended `artifactId` explicitly.
- Merge through the ordinary PR lifecycle. The committed package tree is the
  cross-cluster source of truth and the database seed hook reconciles it.

## Ports And Adapters

Preserve these ownership boundaries:

- `kiota-mcp` packages allowlisted descriptions. It has no database or provider
  credentials and is not an execution or delivery authority.
- The Workflow MCP save use case validates the package and writes the immutable
  catalog row through its persistence port. Never use direct SQL.
- `generated-action-runtime` validates input, materializes or interprets the
  package, fences target hosts to saved `auth.hosts`, and holds database access
  but no provider token.
- `generated-action-proxy` is the only generated-action process that may resolve
  a saved connection reference through the BFF. Scripts, packages, prompts,
  logs, and runtime input carry references, never plaintext credentials.
- `gen/*` intentionally uses the reference-forwarding ActivePieces router lane;
  do not replace it with credential materialization or an unregistered route.

## Validation

For every package:

1. Validate slug, version, input/output schemas, method/template, host allowlist,
   side-effect declaration, and OpenAPI provenance.
2. Run the focused `kiota-mcp` and `generated-action-runtime` tests affected by
   the change. For committed packages, run seed validation and
   `pnpm build:db-scripts`; include generated bundles only when the build changes
   them.
3. Prove catalog discovery and one execution using a connection reference when
   auth is required. Treat the runtime response and durable script journal as
   execution authority.
4. For persistent delivery, use `gitops` to prove reviewed source, hub build,
   image pins, hydration/promotion, ArgoCD reconciliation, seed completion, and
   the live user path.

## Never Do

- Never fetch a description outside the configured allowlist to make a test
  pass; use approved HTTPS input or the bounded inline-content escape hatch.
- Never mutate an already-used slug/version in place. Bump the version so
  replay identity remains stable.
- Never hand-write catalog rows, function-router state, release pins, or cluster
  workloads.
- Never expose OAuth tokens, API keys, internal tokens, database URLs, or
  Kubernetes credentials to generated code.
- Never use a generated-action PR as a second source-sync or GitOps writer.
