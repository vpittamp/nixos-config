# Regression acceptance: operator rules learned on dev (2026-10-28/29)

Use `get_factory_regression_authority(cardId)` then `accept_factory_regression` with the
snapshot's exact `revision`, `sourceRequestSha256`, `rootOriginInventorySha256`,
`verificationSpecSha256`, and one stable `idempotencyKey`. On a lost reply, read back the
authority before resending; never resend a changed request under the same key.

## Which card, which head

- Direct PR (review card, `authoritySource.kind = direct-pull-request`): `expectedHeadSha` is the
  PR head. The baseline is the snapshot's `baselineSha`, not the decision author's main.
- Approved plan (work card, `kind = approved-plan`): `expectedHeadSha` must be `null`
  (`regression-plan-owner-mismatch` otherwise). The decision must equal the plan's proposal
  byte-for-byte. The one admitted difference (D339) is a person qualifying the plan's bare
  selectors with its single control path. Anything else, including re-rooting control paths,
  dropping an obligation, or `not-required`, is refused `regression-approved-criteria-differ-from-plan`.
  A wrong or uncollectable plan contract is fixed only by re-planning (`start_factory_phase planning`),
  which rebuilds.
- A review card whose contract lives on its work card answers
  `regression-contract-on-linked-work-card`; accept on the work card.

## Shape rules (each was a real refusal)

- At most 32 cases + preservationCases, summed over all obligations. caseId ≤32 chars.
- D298: every controlPath needs ≥1 cause case AND ≥1 preservation case selecting it.
- A not-required `reason` is ≤400 characters.
- Control paths are REPO-ROOT relative for EVERY recipe. `pytest-9.1.1-sandbox-execution-api/v1`
  also takes repo-root controls (`services/sandbox-execution-api/...`); it only adds that
  service's import root. Since D397 (#4142), acceptance refuses a control that is neither a
  planned changePath nor present at the baseline. `src/routes/x.test.ts` for a
  function-router test resolves to nothing and fails at review with
  "regression candidate controls are missing/duplicated" (D397).
- `vitest-4.1.2-structured/v1` runs with `config:false` on the ROOT node graph. A test that
  imports a package installed only in a service's package.json (e.g. fastify for
  function-router routes) cannot be collected. Use a root-collectable control, or cite the CI
  job that runs it.
- `pytest-9.0.3-structured/v1` has no service import root. Orchestrator tests work because
  `services/workflow-orchestrator/tests/conftest.py` inserts its own paths; dapr-agent-py
  `from src...` tests do not collect.
- `regression-invocation-custody-unknown` / `regression-prior-invocation-custody-unknown`: an
  ambiguous RegressionProof effect. `repair_factory_item reconcile` does NOT cover regression
  custody (it handles publication and delivery projections).
  - Since D609 (wfb #4333), a NEW head lets `factory-policy:regressionSourceAdvanceSupersession` supersede the
    old invocation automatically, given positive closure evidence.
  - Otherwise the supported path is the native-ack import (`wfb-factory operator
    import-regression-native-read`), then an internal `reconcile-regression-invocation` disposition by a
    different principal, then `admit_factory_regression_profile_recovery`.
  - Capture the node's CRI shutdown acks before log rotation, roughly within an hour.
- A card that stalls on review: read its OWNER REASON (`factory_card_timeline`), never GitHub's
  `pr-reviewer/binding` text. `awaiting-regression-acceptance` looks like "awaiting reviewer" on GitHub.
- `regression-committed-baseline-overlaps-candidate`: main moved over the declaration's baseline.
  - Since D613 (wfb #4344), it re-baselines automatically when no control or selector file moved.
  - Otherwise merge main and regenerate the declaration right before marking ready.
- Risk tiers (D625, wfb #4355): required for factory-built work items and behaviour paths; advisory
  (a delegated not-required) for docs, tests and CI workflows.
- **R1 CI-gated regression proof (`D-L173`/`D-L175`/`D-L180`/`D-L181`/`D-L182`, wfb #4364, #4366, #4377):**
  - `.github/workflows/factory-regression-proof.yml` (`pull_request_target` + `merge_group` checking out `github.workflow_sha` on `arc-wfb-pr` runners) runs `node scripts/factory-regression-ci.mjs --enforce` and is a required status check (`factory-regression-proof`, `integration_id: 15368`) on `PittampalliOrg/workflow-builder` `main` (ruleset `21820326`).
  - Factory builds (`DevelopmentRun` `deliver` via D-L175/D646 and `FactorySource(operation="publish")` via D672) automatically materialize the approved plan's accepted `FactoryRegressionDecision` as `.factory/regressions/<64-hex-sha256>.json` on the delivered PR branch.
  - Direct PRs commit `.factory/regressions/<64-hex-sha256>.json` (computed via `node scripts/compute-regression-manifest-path.mjs <file>` with exact JSON bytes and no trailing newline) and are auto-accepted via `factory-policy:regressionCommitted`.
  - When a candidate carries a committed `.factory/regressions/<64-hex-sha256>.json` declaration and touches no protected regression-CI file, `retainedRegressionProgress.requests` sets `roles: []` (D666/D674) so neither the builder nor the reviewer runs redundant in-sandbox `RegressionProof` calls; `reviewing`/`rereviewing` closes `hostRegressionEvidence` from the verified `factory-regression-proof` CI receipt (`GithubFactoryRegressionCiProof`).
- **Two-Key Procedure for `FACTORY_REGRESSION_CI_PROTECTED_FILES` (`D-L181`):**
  - Any PR that modifies `scripts/factory-regression-ci.mjs`, `.github/workflows/factory-regression-proof.yml`, `services/shared/factory-regression-vitest-runner.mjs`, `services/shared/factory-regression-pytest-runner.py`, `src/lib/domain/factory-regression-ci.ts`, or `src/lib/server/application/adapters/github-factory-regression-ci-proof.ts` is refused `delegated-committed` (`regression-ci-protected-surface-modified-in-candidate`) and cannot self-certify via CI.
  - It requires **Key 1** (explicit `human`/`operator` `accept_factory_regression` recorded as an `INTERVENTION`) and **Key 2** (host OpenShell `RegressionProof` execution during `reviewing`/`rereviewing` with `roles: ['baseline', 'candidate', 'preservation']` verified from `wfb-run-archives` + independent reviewer attestation).
- **Baseline-safe regression test authoring (`D668`/`D668b`/`D679a`, wfb #4390, #4392, #4401):**
  - Cause cases implanted onto the baseline tree must fail by `AssertionError` (`outcome: 'failed'`), never module-load or `TypeError` (`baseline-error`).
  - Never use a top-level static `import` of a newly created module or newly added export in a cause-only test file (`regression-cause-static-new-module-import`), and guard nullable DOM/array lookups before `.click()` (`regression-cause-unguarded-lookup-click`). Use dynamic `await import('./new-module.js').catch(() => ({}))` inside the test body (`D679a` provides a virtual fallback resolver in Vite `COMPONENT_PROJECT` client mode so `.svelte` dynamic imports also reject at runtime on baseline).
- **`ci-code-repair` on `factory-regression-proof` failures (`D667`/`D675`/`D679b`/`D680`, wfb #4387, #4392, #4401, #4402):**
  - `classifyFactoryCiFailure` classifies `factory-regression-proof` `"refusalReason": "..."` logs as `verdict: 'code'` (D667), automatically dispatching a `ci-code-repair` `building` attempt with trailing `actions/upload-artifact` and `Post job cleanup.` output stripped from `logExcerpt` (D679b).
- Prove red-before with the REAL runner `services/shared/factory-regression-vitest-runner.mjs`, not a
  plain `vitest run`. Where the pinned toolchain is absent, point it at the worktree's vitest.
- Budgets: the default ceilings are sourceAdvances 6 / environmentRetries 2 (D643/D659). Raise them via
  `budgetCeilings` only when spent ≥ ceiling (`regression-approval-budget-below-spent`).

## Proving a decision before accepting

Run the real runners (`services/shared/factory-regression-{vitest,pytest}-runner.*`) on a
baseline tree (baseline + control files from head) and the head tree, with the lock-pinned
toolchain (`services/openshell-sandbox/factory-regression/node-pnpm-lock.yaml`,
`services/shared/factory-regression-pytest-requirements.lock`) under `env -i ... -I -B`.
Cause cases must fail by assertion on baseline and pass on head. Preservation cases must
pass on both.
