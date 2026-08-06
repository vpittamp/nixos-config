# DevelopmentRun Contract

Use this reference when operating or changing the canonical preview development
path. Source types and live receipts remain authoritative.

## Public Operations

| Operation | Purpose |
| --- | --- |
| `development_run_start` | Compile and persist immutable run authority. |
| `development_run_get` | Return plan, phase, gates, receipts, and next actions. |
| `development_run_apply` | Apply one compiler-owned semantic generation. |
| `development_run_follow_output` | Read bounded exact-generation signals. |
| `development_run_verify` | Run impact-derived policy gates. |
| `development_run_submit` | Preflight and create policy-owned linked delivery. |
| `development_run_cancel` | Stop the run and execute compiler-owned cleanup. |
| `development_run_checkpoint` | Persist a point on the same run. |
| `development_run_fork` | Create a new run with explicit parent provenance. |
| `development_run_handoff` | Attach an authorized persistent session to the run. |
| `development_run_reproduce` | Start from sealed evidence and declared baselines. |

Every mutation requires an idempotency key. A duplicate returns the original
receipt. The server owns environment tuple, repositories, revisions, adapters,
runtime identities, workspace, credentials, delivery coordinates, and policy.

## Internal Workflow Boundary

The seeded `preview-host-development` workflow is not a launch surface. It
accepts only:

- `development/workspace-seed`
- `development/execute-phase` with `prepare`, `apply`, `observe`, `verify`,
  `deliver`, or `cleanup`

Receiver routes, SEA adoption, and dev-sync scripts are internal adapters.
Adding a target extends the catalog/adapter registry, not the public schema.

## Durable Identity

Every receipt and output cursor binds at least:

- DevelopmentRun ID and workflow execution ID
- PreviewEnvironment UID, request ID, platform SHA, source SHA, and catalog
  digest
- ChangeSet and Generation
- DevelopmentPlan and adapter provenance
- selected target and builder profile
- idempotency key and command sequence

Never correlate by display name alone. Recreating a preview name creates a new
generation and invalidates old cursors and capability leaves.

## Output Contract

Signals are `process-log`, `compiler-diagnostic`, `health`, `trace`,
`prompt-content`, `tool-content`, `metric`, `browser-console`,
`browser-network`, and `deployment`. Reads use opaque cursors, maximum item and
byte bounds, and exact signal selection. A cursor cannot cross generation or
signal selection.

Expected prompt and tool content remains visible. Redaction is limited to
credential-shaped fields and embedded credential values. Missing output should
be fixed at the adapter or telemetry boundary, not normalized into unbounded
pod-log access.

For supervised delivery, one composite content digest covers the primary
checkout and every imported repository. The watcher writes the same membership
and verdict into each checkout. `await-sync` from the edited checkout must prove
that exact digest before observation; it is read-only and never creates another
apply path.

## Terminal Contract

Success means required gates and delivery receipts passed, persistent changes
were built and reconciled when applicable, runtime behavior was verified on a
fresh generation/session, terminal evidence sealed, and cleanup completed.
`COMPLETED` workflow status, a green pod, or a created PR is insufficient alone.

An infrastructure no-op does not acquire ownership or run readiness. Cleanup
orders application adoption release before infrastructure restoration and must
restore the exact baseline before ArgoCD resumes.
