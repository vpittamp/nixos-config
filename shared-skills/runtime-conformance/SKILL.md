---
name: runtime-conformance
description: "Verify, admit, and swap DurableSessionRuntime agent runtimes in Workflow Builder. Use for the runtime conformance suite (static pytest lane, live dev-cluster lane, gate.py, results file, generated contract table), flipping conformanceVerified in the runtime registry, the swap-safety `conformance` error and its AGENT_RUNTIME_ALLOW_UNVERIFIED_RUNTIME override, the runtime-conformance-gate CI job, and adding a new runtime to the registry. Use workflow-builder for ordinary runs and agent-session-recovery for post-loss forensics."
---

# Runtime Conformance

The DurableSessionRuntime contract (`docs/durable-session-runtime-contract.md`
§1-5) is proven per runtime by a two-lane suite. `conformanceVerified: true` in
`services/shared/runtime-registry.json` is the swap-safety admission bit and is
flipped ONLY on gate-checked `static=PASS` AND `live=PASS`.

## Start From Source

```bash
WFB_ROOT=/home/vpittamp/repos/PittampalliOrg/workflow-builder/main
git -C "$WFB_ROOT" fetch origin
git -C "$WFB_ROOT" show origin/main:docs/durable-session-runtime-contract.md
```

Read `docs/durable-session-runtime-contract.md` ("Conformance suite",
"Unverified-runtime refusal") and `services/shared/runtime_conformance/`
before touching a check. Never restate the contract from memory.

## Contract As Code

`services/shared/runtime_conformance/` (stdlib only; each host service reaches
it via `sys.path`, no service imports another):

- `contract.py` — `DISPATCH_WORKFLOW_NAME = "session_workflow"` (dispatched)
  and `BRIDGE_GATE_TOKEN = "agent_workflow"` (bridge-eligibility sentinel).
  Two different strings with two roles; conflating them deadlocks
  `CreateWorkflowInstance`. Runtime-owned return keys are
  `success`/`sessionId` plus `output|content`; `agentRuntime` is stamped by the
  orchestrator bridge, so the suite checks it on the bridge-resolved result,
  never on the raw runtime return. Mandatory event vocabulary:
  `session.status_running`, a terminal `session.status_*`, `agent.message`,
  `agent.tool_use`, `agent.tool_result`. Lifecycle: `GET
  /api/v2/agent-runs/{id}/status?summary=true` returns `runtimeStatus` +
  `runtime_status`; a missing id is 404 with detail exactly
  `Agent run not found`; `?includeOutput=true` adds `output` for TERMINAL runs
  only; terminate and delete are idempotent on gone ids; pause/resume delegate
  to the Dapr client.
- `results.py` — `ResultsFile` / `CheckResult`, lanes `static` and `live`.
  Verdict: PASS iff every check PASS; SKIPPED iff any SKIPPED and none FAIL;
  otherwise FAIL; MISSING with no results.

If a constant and the doc disagree, the doc wins: fix the constant, never
loosen a check in an adapter.

## Static Lane

One pytest adapter per host service exercises that service's real code with
only the Dapr sidecar stubbed:

| Host service                 | Runtimes served                                                               |
| ---------------------------- | ----------------------------------------------------------------------------- |
| `services/dapr-agent-py`     | `dapr-agent-py`, `dapr-agent-py-local`, `cua-agent-py`, `cua-browser-agent-py` |
| `services/cli-agent-py`      | `claude-code-cli`, `claude-code-cli-glm`, `codex-cli`, `kimi-code-cli`, `agy-cli` |
| `services/browser-use-agent` | `browser-use-agent`                                                           |

Each is `tests/conformance/test_runtime_contract.py` and writes the file named
by `RUNTIME_CONFORMANCE_RESULTS`.

```bash
cd "$WFB_ROOT"
# NixOS host only: the dapr/grpc wheels need libstdc++ on the loader path.
# Without it cli-agent-py falls back to its dapr stub, records
# dispatch.workflow_registered as SKIPPED, and the gate reports drift.
export LD_LIBRARY_PATH=/nix/store/0iv8glcslgfcgn371lbjr5jjw5a6cqir-gcc-15.3.0-lib/lib
pnpm conformance:static   # == bash scripts/runtime-conformance/run-static.sh
pnpm conformance:gate
```

`run-static.sh` runs every service in its own uv environment (it owns the
per-service `uv run` extras), merges the fresh files into
`services/shared/runtime-conformance-results.json` with `merge.py --lane
static`, then runs the gate with `--write-doc`. A FAIL is recorded and shown by
the gate; pytest itself only exits non-zero on a harness error or a regression
of a runtime already marked `conformanceVerified`.

## Gate

```bash
python3 scripts/runtime-conformance/gate.py \
  --results services/shared/runtime-conformance-results.json \
  --registry services/shared/runtime-registry.json \
  --static-dir <fresh dir of per-service static jsons> \
  --doc docs/durable-session-runtime-contract.md [--write-doc]
```

Always prints the per-runtime table (every canonical registry id with
static/live verdict), then fails on:

1. with `--static-dir`: a fresh static verdict differs from the committed
   static section (fix: rerun `pnpm conformance:static`, commit the file);
2. any `conformanceVerified: true` runtime whose committed verdicts are not
   `static=PASS` AND `live=PASS` (SKIPPED/FAIL/MISSING never count);
3. the doc's generated table between `<!-- runtime-conformance:begin -->` /
   `<!-- runtime-conformance:end -->` differs from the rendered one
   (`--write-doc` rewrites it instead of failing). Never hand-edit the table.

CI: `.github/workflows/pr-checks.yml` job `runtime-conformance-gate`
(`needs: agent-runtime-tests`) downloads the `runtime-conformance-<service>`
artifacts and runs the gate. Required PR checks are `checks` and
`orchestrator-tests`; the `preview/gate` context is red by design on
trust-root paths (`.github/workflows`, unmatched paths) and is not a gate
failure.

## Live Lane (dev)

`scripts/runtime-conformance/live.py` exercises one real `durable/run` child
per runtime against dev and records the same check ids from live evidence
(status route on the host, bogus-id lifecycle probes, parent terminal status,
`includeOutput` or orchestrator history for the return dict, `session_events`
for vocabulary and childInput acceptance).

1. Launch one run per runtime with Workflow MCP `run_workflow_script` on the
   saved workflow `runtime-conformance-live` (args `{agent, label,
   holdSeconds}`). Resolve current saved proof agents by their immutable
   runtime id; both `dapr-agent-py` variants must resolve to `harness`, while
   `gvisor-cli-proof-{claude,codex,kimi,agy}` resolve to `per-session-pod`.
   `holdSeconds` keeps the pod open while the runner probes it.
2. Run ONE PROCESS PER EXERCISED RUNTIME, IN PARALLEL, each into its own
   scratch results file. Per-session hosts are reaped at terminal, so a serial
   runner arrives after the pod is gone.

   ```bash
   python3 scripts/runtime-conformance/live.py \
     --registry services/shared/runtime-registry.json \
     --results "$SCRATCH/live-<runtimeId>.json" --commit "$(git rev-parse HEAD)" \
     --execution <runtimeId>=<workflowExecutionId> \
     --skip <otherRuntimeId>="<reason>" ...
   ```

   The runner writes a `live.exercised` SKIPPED entry for EVERY registry
   runtime it was not given, so pointing `--results` at the committed file
   from several processes clobbers each other's rows.
3. Merge only the exercised runtime's `live` entries into the committed file
   through the `ResultsFile` API (`load`, `lane("live")[rid]`, `save(path,
   commit=...)`), then run the gate with `--write-doc`.

Transport used by the runner (the `session-host-transport.ts` rule): from the
BFF pod's daprd, `http://localhost:3500/v1.0/invoke/<app-id>/method/...` for
harness hosts; pod IP `:8002` (direct-host) only for dedicated
`agent-session-*` per-session pods. After a host is reaped the
child's return dict is read from the parent's orchestrator history rows in
`wfstate_state` (`encode(value,'escape')`, then unescape). A transport loss
mid-probe records SKIPPED, never a verdict.

## Flipping `conformanceVerified`

Only when the committed file shows `static=PASS` AND `live=PASS` for that id:

1. Set `conformanceVerified: true` in `services/shared/runtime-registry.json`
   (the canonical file; the copies are generated).
2. `node scripts/sync-runtime-registry.mjs`.
3. Run the gate with `--write-doc`.
4. Commit registry + generated copies + results file + doc together.

A SKIPPED or FAIL runtime is never verified. The unflip is the same commit set.

## Admission (swap safety)

`src/lib/server/agents/swap-safety.ts`: a target runtime without
`conformanceVerified` is a drop with `capability: "conformance"` and severity
`error` (a third severity beside `reject` and `warn`; a missing field reads as
`false`). The `durable/run` bridge answers HTTP 409 and the direct-spawn gate
throws the same text:

```
Runtime "<id>" is not conformance-verified (services/shared/runtime-conformance-results.json); set AGENT_RUNTIME_ALLOW_UNVERIFIED_RUNTIME=true or agentConfig.allowUnverifiedRuntime=true to override
```

- Overrides: operator-wide env `AGENT_RUNTIME_ALLOW_UNVERIFIED_RUNTIME=true`
  or per-dispatch `agentConfig.allowUnverifiedRuntime: true` (literal boolean;
  the string `"true"` does not count).
- An override never hides the drop: the verdict degrades to `warn`, the drop
  stays recorded at severity `error`, and a `runtime.swap_degraded` session
  event is emitted.
- `AGENT_RUNTIME_REJECT_LOSSY_SWAP` does not gate `error`; a `reject` (lossy
  swap with rejection enabled) still outranks it.

## Current State

Verified: `dapr-agent-py`, `dapr-agent-py-local`,
`claude-code-cli`, `codex-cli`, `kimi-code-cli`, `agy-cli`.

Unverified, with cause:

| Runtime                                | Why                                                                                              |
| -------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `claude-code-cli-glm`                  | live SKIPPED: zai credential expired                                                             |
| `cua-agent-py`, `cua-browser-agent-py` | live SKIPPED: `AGENT_RUNTIME_CUA_DEFAULT_IMAGE` unset on dev                                     |
| `browser-use-agent`                    | static FAIL: not auto-turn; violates §2 top-level `maxIterations` (`input.child_input_accepted`) and §5 `includeOutput` (`lifecycle.include_output_terminal_only`) |

Re-read the generated table in the contract doc for the live value; the list
above is the state as of 2026-08-29.

## Add A New Runtime

1. Registry entry in `services/shared/runtime-registry.json` with
   `conformanceVerified: false`, `dispatchWorkflowName`/`bridgeGateToken`, the
   `appIdConfigKey`, family, host mode, and honest capability flags.
2. `node scripts/sync-runtime-registry.mjs` (drift tests assert the copies).
3. Static suite: add the runtime to the `tests/conformance/` adapter of the
   host service that serves it (new service: new adapter + `conftest.py`
   wired to `services/shared/runtime_conformance`, and add it to
   `run-static.sh` and the `agent-runtime-tests` CI matrix so a
   `runtime-conformance-<service>` artifact exists).
4. `pnpm conformance:static`; commit the results file and regenerated doc.
   The new row must show `static=PASS`, `live=MISSING/SKIPPED`, verified `no`.
5. CI green on `checks`, `orchestrator-tests`, `runtime-conformance-gate`.
6. Live lane on dev: a proof agent for the runtime, one `runtime-conformance-live`
   run, one `live.py` process, merge, gate.
7. Flip `conformanceVerified` per the section above.

## Rules

- Never change runtime behavior to pass a check unless the contract already
  requires it; a real deviation is recorded as FAIL with the code-level reason
  in `evidence`.
- Amend contract text only with a stated rationale, and update `contract.py`
  in the same change.
- A skipped or failing runtime is never verified; SKIPPED is "not exercised",
  not "passed".
- `conformanceVerified` is distinct from `capabilitiesVerified` (capability
  flag honesty, `core/conformance.py`); do not flip one on evidence for the
  other.
- Never hand-edit `runtime-conformance-results.json` or the generated table.
- Never direct-patch the registry on the cluster; registry changes ship
  through source and GitOps.

## Canonical Sources

- `docs/durable-session-runtime-contract.md`
- `services/shared/runtime_conformance/` (`contract.py`, `results.py`)
- `services/shared/runtime-registry.json`,
  `services/shared/runtime-conformance-results.json`
- `scripts/runtime-conformance/{run-static.sh,merge.py,gate.py,live.py}`
- `services/{dapr-agent-py,cli-agent-py,browser-use-agent}/tests/conformance/`
- `src/lib/server/agents/swap-safety.ts`
- `.github/workflows/pr-checks.yml` (`agent-runtime-tests`,
  `runtime-conformance-gate`)
