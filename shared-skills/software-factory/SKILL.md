---
name: software-factory
description: "Operate the Workflow Builder Delivery Board on dev from issue intake through verified delivery and cleanup. Use for autonomous phase policy, delegated approvals, preview builds, evaluator repair, independent review, automated attestation/binding and live board state. Use gitops for the protected release/promotion lane and preview-environments for lifecycle operations."
---

# Software Factory

Operate the workspace Delivery Board from issue intake through protected source
delivery, verified deployment and cleanup. Prefer the typed Workflow MCP tools;
the factory's durable owner advances each item. This skill describes current
operations, not permission to start or mutate unrelated work.

## Read the current contract

Start with Workflow Builder `docs/delivery-board.md` and
`docs/software-factory.md`; use `docs/factory-runtime-completion.md` for host
review publication and Hub signing. Verify fresh repository revisions before
source claims. Resolve disagreements using live scoped evidence and current
application/domain code, then documentation, then this skill.

Call `get_workflow_context`, then `get_software_factory` before proposing a
repair. The authenticated workspace owns these operations; an MCP transport
session ID is not workflow authority. Inspect `get_factory_item({cardId})` for
the current attempt, owner decision, findings, review evidence and transitions.

## Normal autonomous lane

Work cards follow intake → triage → assessed → planning → planned → building →
review → completing → done. Review cards follow reviewing/rereviewing →
reviewed → merged or changes_requested. A failed card is resting and repairable;
it is not the same as canceled. Read the attempt's terminal outcome envelope,
not Dapr COMPLETED, to decide whether its work succeeded.

Intake requires a repository subscription with the work/review lanes enabled.
An authenticated webhook alone does not establish that subscription. Source
reconciliation ensures one durable item owner; it does not dispatch a second
owner. Before diagnosing missing intake, verify the selected repository/lane,
source readability and actual last reconciliation time. The declared reconcile
schedule and the received ticks are separate evidence.

Inspect the complete policy with `get_software_factory`. To change it, preserve
the current row and use `set_factory_policy`; do not invent fields from an old
example or write SQL. Separate switches authorize separate effects:

- `phases`: automatic/manual/disabled for each working phase. A single manual
  triage or planning phase can intentionally leave downstream work waiting.
- `acceptWork`: delegates acceptance of code tasks, including features and docs.
- `approvePlans`: delegates plan approval.
- `mergePullRequests`: lets the factory request protected merge admission after
  required evidence. It does not bypass independent review or GitHub rules.
- `resolveIssues`: governs supported non-code dispositions separately.
- `completionEvidence`: deployment for code that changes a running service;
  documentation uses its explicit reviewed-merge/no-runtime-change contract.
- `verification`: required or advisory evidence according to the selected plan.

Check other resting items before changing workspace-wide policy. Honor existing
user approval delegation; do not repeatedly request approval already granted.
For an unattended test, record any manual phase start, approval, retry or source
write as an intervention instead of labeling the assisted sequence autonomous.

## Runtime and implementation

The registry's `defaultRuntimeId` selects new work; `legacyDefaultRuntimeId`
preserves old records. As of the 2026-10-12 verified source, new work defaults
to `dapr-mastra`; Python remains explicitly selectable. Read `builderProfile`,
`phaseRuntime`, published role packages and effective agent configuration for
the particular attempt. Do not switch an existing durable history by changing
a default or treat a pod label as runtime identity.

The build phase owns a PreviewEnvironment and canonical DevelopmentRun. Read
its exact generation and readiness on the lifecycle authority before calling
a pending attempt stalled. Capacity admission, preview boot, application sync,
auth/exposure and execution progress are different waits. A successful launch
request or Ready pod does not prove all of them. Follow the current owner reason
and server refresh interval; do not launch another build while this one waits.

For browser acceptance, the route and data must belong to the signed-in preview
workspace. Registered factory-board fixtures exercise only their documented
routes and capabilities. For another UI, use its actual page and supported
preview-owned data with `fixture:null`; do not freeze criteria requiring rows,
runs or events that the fixture cannot produce. Keep internal state/timing and
absent data edge cases in meaningful unit/component controls. A critic's source
requirement failure returns to implementation for the same item; environment or
missing-proof failures remain incomplete with their actual cause.

## Independent review, attestation and delivery

Normal factory review supplies a typed verdict, exact reviewed head and retained
evidence. The admitted Hub source publisher posts the reviewer App attestation
and requests binding refresh. The normal owner handles queue admission; the
separately admitted Hub signer propagates eligible source verdicts to the exact
native merge group. The release publisher/reviewer/merger owns image delivery.
These are separate authorities and separately observable effects.

Do not run workstation attestation, manual binding refresh or queue signing for
a normal factory subject that has handed those writers to the Hub. Respect the
current writer interlock and subject-bound recovery authorization. Never
self-attest or turn a local source review into merge or deployment permission.
`factory:bypass` excludes factory intake for an authorized factory repair; it
does not waive independent review, required CI or protected landing.

Read current exact-head checks and current native queue membership. A source
SHA, temporary PR merge SHA and native queue group SHA are different subjects.
Reconcile historical pre-attestation binding failures against the actual latest
qualified check; do not resend an already successful write. Unknown write
effects require readback, not another write.

For deployment completion, join merged source → immutable build/digest →
committed release/promotion → named native application sync → owned workload
readiness/runtime image → the changed user path. Use the item's `releaseLane`
and the workspace `releaseChain` for diagnosis, keeping their exact subjects
and missing stages distinct. A merge, green build, advanced pin or healthy
parent application alone is insufficient. Use `gitops` for this boundary.

## Recovery and terminal cleanup

`repair_factory_item` is attempt-scoped: retry a failed latest attempt, reconcile
existing owner/delivery facts, or cancel through canonical lifecycle cleanup.
Choose the narrow supported action after reading the actual owner finding.
Do not force board or execution rows terminal, reset history or blanket retry
semantic refusals. Budgets are ceilings for specific work, not instructions to
repeat a failed prefix; inspect the effective limits before tuning them.

An active DevelopmentRun owns its builder session. Cancel the parent through
`development_run_cancel`; stopping one session is not canceling the workflow.
Do not reuse a deterministic instance ID until canonical closure is confirmed.
Credit valid checkpoint/recovery evidence where its source, protocol and
generation remain applicable; use the controller's typed handoff/reproduce
lane rather than claiming a generic restart restored a checkpoint.

Done and session-terminated projections do not prove physical resource absence.
Confirm current task-owned runtime/hands cleanup with canonical provider or
complete scoped native metadata. List snapshots must be complete and maintain
one revision within pagination; combine pre/post CR inventories and validate
native ownership. Unrelated cluster revision movement between separate complete
reads is not itself a task resource. Preserve evidence and archives. Shared
Mastra/Python harness Deployments and Hub/dev controllers are intentional
services, not per-run cleanup targets. Use `preview-environments` for signed
preview teardown and `agent-session-recovery` for durable run forensics.

## Evidence and targets

Maintain a stage ledger with exact source/review/build/generation/digest
subjects, outcomes, observation times, interventions and remaining gaps.
Reuse qualified evidence until a material change invalidates its claim; recheck
only the affected boundary. Preserve failed attempts and setup failures with
their real classifications. One successful observed chain establishes that
chain, not statistical reliability or every replay/fault guarantee.

Dev is the workload target and Hub owns management/delivery. Ryzen is retired.
Do not redirect this workflow to it or introduce a local workstation writer to
make an automated test appear successful.
