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
- Control paths are REPO-ROOT relative. All recipes run from the repository root except
  `pytest-9.1.1-sandbox-execution-api/v1` (service-rooted). `src/routes/x.test.ts` for a
  function-router test resolves to nothing and fails at review with
  "regression candidate controls are missing/duplicated" (D397).
- `vitest-4.1.2-structured/v1` runs with `config:false` on the ROOT node graph. A test that
  imports a package installed only in a service's package.json (e.g. fastify for
  function-router routes) cannot be collected. Use a root-collectable control, or cite the CI
  job that runs it.
- `pytest-9.0.3-structured/v1` has no service import root. Orchestrator tests work because
  `services/workflow-orchestrator/tests/conftest.py` inserts its own paths; dapr-agent-py
  `from src...` tests do not collect.
- `regression-invocation-custody-unknown`: reconcile the card (repair_factory_item reconcile)
  before accepting.
- Budgets: the default ceilings are sourceAdvances 3 / environmentRetries 2. Raise them via
  `budgetCeilings` only when spent ≥ ceiling (`regression-approval-budget-below-spent`).

## Proving a decision before accepting

Run the real runners (`services/shared/factory-regression-{vitest,pytest}-runner.*`) on a
baseline tree (baseline + control files from head) and the head tree, with the lock-pinned
toolchain (`services/openshell-sandbox/factory-regression/node-pnpm-lock.yaml`,
`services/shared/factory-regression-pytest-requirements.lock`) under `env -i ... -I -B`.
Cause cases must fail by assertion on baseline and pass on head. Preservation cases must
pass on both.
