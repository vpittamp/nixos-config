---
name: agent-session-recovery
description: "Recover and do forensics on Workflow Builder durable agent sessions and runs after a harness replica, orchestrator, executor sandbox, or completion-event loss on dev. Use for a stuck or divergent execution row, a lost child completion, the in-band repoll lane and workflow_script_calls journal, session_events and agent_py_state and wfstate_state forensics, host status probes, compaction checkpoints, and stop/purge/reset/resume lifecycle choices. Use workflow-builder for ordinary run debugging and runtime-conformance for runtime admission."
---

# Agent Session Recovery

Durable state is the authority; the execution row, the pod, and the Dapr
`runtimeStatus` are projections or transports. Read the durable state first,
judge outcome only by the terminal envelope, and intervene only through the
Lifecycle Controller.

## Start From Source

```bash
WFB_ROOT=/home/vpittamp/repos/PittampalliOrg/workflow-builder/main
git -C "$WFB_ROOT" fetch origin
git -C "$WFB_ROOT" show origin/main:docs/workflow-lifecycle-termination.md
git -C "$WFB_ROOT" show origin/main:docs/dapr-workflow-purge-runbook.md
```

Canonical: `docs/workflow-lifecycle-termination.md` (lifecycle SSOT),
`docs/dapr-workflow-purge-runbook.md` (break-glass), `docs/harness-host.md`
(harness and executor roles), `docs/context-strategy.md` (event log and
compaction projection), `docs/dynamic-script-workflows.md` ("lost child
completions").

## Recovery Classes (proven on dev)

| Loss                                   | What happens                                                                                                                                             | Evidence of a clean recovery                                                                                                                                                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (a) harness replica deleted mid-turn   | The same workflow instance resumes on another `dapr-agent-harness` replica within ~1s.                                                                    | `session_events.source_event_id` prefix changes pod (`dapr-agent-harness-<pod>:<epoch>:<n>`); `agent.iteration` count == `agent.llm_usage` count (no duplicate `call_llm`); a `compaction_error` from the dying pod is fenced and harmless. |
| (b) orchestrator rolled mid fan-out    | Execution id unchanged; children keep running on their own hosts; lost completion events are recovered in-band by the repoll lane.                         | `customStatus.repolled` / `repollProbes`; every `workflow_script_calls` row ends `done`, none `skipped`; parent `customStatus.terminal.outcome = success`; no stop/resume used.                                                     |
| (c) executor sandbox deleted mid-turn  | That one tool call errors (`Error: ... sandbox executor unavailable ...` in the tool result); the execution continues on the recreated pod (same FQDN, same token). | `GET /executor/healthz` on the new pod reports `workspaceReady`; later `agent.tool_result` rows succeed; same execution reaches terminal.                                                                                            |
| (d) lost terminal projection           | Execution row `running` while Dapr says terminal; the reconciler execution-liveness lane repairs it within a tick.                                        | `[session-reconciler] tick:` log shows `executionLivenessScanned`/`executionLivenessRepaired`; the row flips to the envelope's outcome, never to Dapr `COMPLETED` blindly.                                                          |

Judge outcome ONLY by `customStatus.terminal` (`{outcome, error, source}`) or
its mirror `terminalOutcome` (Workflow MCP `get_execution_status`). A
workflow that returns a failure payload is `COMPLETED` to Dapr; a repair
logged `unaudited-legacy` found no envelope and is a finding, not a repair.

Repoll lane (class b): while a cross-app `agent()` call is outstanding the
pump also waits on a durable timer `DYNAMIC_SCRIPT_CHILD_REPOLL_SECONDS`
(default 120); when it wins, one bounded activity `probe_outstanding_children`
invokes each child's `GET /api/v2/agent-runs/{childInstanceId}/status?summary=true&includeOutput=true`.
`COMPLETED` with output (or `FAILED`/`TERMINATED`) resolves the call;
`unknown` (404, transport error, `COMPLETED` without output) never does. The
lane is behind the Dapr patch marker `dynamic-script-child-repoll-v1`, so
histories recorded before it keep the legacy remediation
(stop `{mode:'terminate'}` + resume, or per-call skip).

Live proof: `scripts/probes/orchestrator-roll-proof.sh` (needs
`WFB_BASE_URL` and `WFB_API_KEY`; `--no-roll` is the control run;
`--execution-id` adopts a run launched elsewhere), or the saved workflow
`orchestrator-roll-proof` plus a manual
`kubectl --context dev -n workflow-builder rollout restart deploy/workflow-orchestrator`.
PASS = execution `success`, all journal rows `done`, none `skipped`, no
resume.

## Decision Table

| Symptom                                                            | Check first                                                                                                   | Action                                                                                                                                                              |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Row `running`, no new `session_events` for minutes                 | Host status probe (`runtimeStatus`), last event `source_event_id` pod, harness/executor pod state              | If host says terminal: wait one reconciler tick (class d). If host RUNNING: it is progressing; do nothing.                                                            |
| Row `running`, host 404 `Agent run not found`                      | Parent `wfstate_state` history for the child's completion row; `workflow_script_calls` status                 | Dynamic-script with repoll marker: wait for `repolled` to increment. Pre-marker history: stop `terminate` + `resume_workflow_execution` (re-runs only lost calls). |
| Fan-out `customStatus` frozen at stale `outstanding` after a roll  | `customStatus.repolled`/`repollProbes`, journal rows                                                          | Wait for the repoll timer (120s default); never relaunch.                                                                                                            |
| Tool result `sandbox executor unavailable`                         | `kubectl get pod agent-host-<gen>`; `/executor/healthz` `workspaceReady`                                      | None; class (c) continues on the recreated pod. Only escalate if the Sandbox CR itself is gone.                                                                      |
| `compaction_error` event, then turn continues on another pod       | `agent.iteration` vs `agent.llm_usage` counts; `_compaction:` key in `agent_py_state`                          | None; fenced by class (a). Duplicate `call_llm` would be the real finding.                                                                                           |
| Start returns 409 `instance_conflict_live`                         | Dapr says RUNNING/PENDING/SUSPENDED for a deterministic id whose row reads terminal                            | Investigate the divergence; stop with `purge` or `reset` on the prior occupant before reuse. Never `WORKFLOW_ALLOW_DESTRUCTIVE_ID_REUSE` as a shortcut.              |
| Agent lost context after compaction                                | `compaction_complete` (`mode: "projection"`, `eventSequenceCursor`), `ReadSessionEvents` in the roster line    | Under `event_log` the agent calls `read_session_events(after_sequence=…)` itself; verify the durable entry still holds pre-compaction messages.                       |
| Need verbatim tool output from a session                           | `session_events` shows capped output                                                                          | Use `trace_get_tool_calls` (DB view caps at 500 chars; tool clamp is 12,288 chars).                                                                                 |
| Row has NULL `dapr_instance_id`                                    | Age vs `EXECUTION_START_ORPHANED_STALE_SECONDS`; engine (`team-run`/`host` rows hold NULL by design)          | Leave it to the start-orphan sub-lane (dry-run by default); never brand or hand-fix.                                                                                 |

## Forensics Recipes (dev)

CNPG primary is `postgresql-cnpg-1`:

```bash
PSQL='kubectl --context dev -n workflow-builder exec postgresql-cnpg-1 -c postgres -- psql -U postgres -d workflow_builder -Atc'
```

Session for an execution:

```sql
select id, runtime_app_id, runtime_sandbox_name
  from sessions where id like 'dsw-%exec-<execId>%';
```

Timeline (which pod emitted each event):

```sql
select sequence, type, created_at, split_part(source_event_id, ':', 1)
  from session_events where session_id = '<sessionId>' order by sequence;
```

Types to expect: `session.status_rescheduled/running/idle/terminated`,
`session.instructions_applied`, `agent.tool_use/tool_result/message`,
`agent.llm_usage`, `agent.iteration`, `compaction_start/complete/error`,
`state_size`.

Fan-out journal (class b):

```sql
select call_id, seq, status, label, retries
  from workflow_script_calls where workflow_execution_id = '<execId>' order by seq;
```

Durable agent state (`agent_py_state`, keys are LOWERCASED, values bytea):

```sql
select key, convert_from(value, 'UTF8')
  from agent_py_state where key ilike '%_workflow_compaction:%<instance lower>%';   -- compaction checkpoint
select key, length(value)
  from agent_py_state where key ilike '%_workflow_<instance lower>%';               -- durable entry (append-only)
```

Deleting the `_compaction:` key restores the verbatim transcript; it is the
only reversible state edit in this skill.

Orchestrator history (`wfstate_state`), key
`workflow-orchestrator||dapr.internal.workflow-builder.workflow-orchestrator.workflow||<parentInstance>||history-N`:

```sql
select key, encode(value, 'escape')
  from wfstate_state where key like 'workflow-orchestrator||%<parentInstance>%history-%';
```

The child's raw return dict sits in the SubOrchestration completion row; the
`track_agent_run_completed` row carries `result`. `escape` renders `\` as
`\\` and non-printables as `\ooo`; undo both before parsing JSON.

Host status probe (from the BFF pod's daprd; pool, harness, testing hosts):

```bash
BFF=$(kubectl --context dev -n workflow-builder get pod -l app=workflow-builder -o jsonpath='{.items[0].metadata.name}')
kubectl --context dev -n workflow-builder exec "$BFF" -c workflow-builder -- node -e \
  "fetch('http://localhost:3500/v1.0/invoke/<app-id>/method/api/v2/agent-runs/<instance>/status?summary=true&includeOutput=true').then(async r=>console.log(r.status, await r.text()))"
```

Dedicated `agent-session-*` per-session pods are reached by pod IP `:8002`
instead. Per-session hosts are reaped at terminal: probe while the run is
running, and read the return dict from `wfstate_state` afterwards.

## Lifecycle Tools (Workflow MCP)

- `get_execution_status` — read `terminalOutcome`; the projected status is
  derived from it.
- `stop_workflow_execution` modes `terminate | interrupt | purge | reset`
  (request/confirm; 202 is progress, not success). `purge` or `reset` is what
  frees a deterministic instance id: Dapr >=1.18.2 rejects recreate while any
  child, recursively and cross-app, is non-terminal, and the orchestrator
  answers 409 `instance_conflict_live` instead of purging a live occupant.
- `resume_workflow_execution` — dynamic-script = resume-after-edit: the source
  must be terminal, unchanged calls resolve from the imported `done` journal,
  only changed or lost calls re-dispatch. This is the retry primitive; a
  relaunch pays for the whole prefix again and creates a second run.
- If the client's tool list lacks one of these, reconnect the MCP client
  before concluding the server lacks it.

## Traps

- `session_events` tool_result output is capped (500 chars in the DB view;
  12,288-char tool clamp). Verbatim evidence comes from `trace_get_tool_calls`.
- Dynamic-script `sleep()` takes SECONDS.
- Per-session hosts are reaped at terminal; a 404 after terminal is normal.
- A harness session persists an executor Sandbox name but that pod runs no
  workflow worker; its lifecycle goes through Dapr on the harness app-id, and
  a closed executor never means "session closed".
- `read_session_events` (event_log strategy, exempt from tool narrowing) lets
  the agent recover pre-compaction context itself; under `compaction` it is
  hidden and denied.
- Dapr state surgery (`DELETE FROM wfstate_state` + restart) is break-glass
  only, per `docs/dapr-workflow-purge-runbook.md`; the Lifecycle Controller
  cascade with purge-force is the vetted path.

## Never Do

- Never hand-edit `workflow_executions`, `sessions`, `workflow_script_calls`,
  or `agent_runs` rows to a terminal status; the reconciler and the envelope
  own that write.
- Never relaunch a run to "retry" a lost call; use `resume_workflow_execution`
  or wait for the repoll lane.
- Never delete a working harness replica, orchestrator pod, or executor
  sandbox to "fix" a stuck turn before reading the durable state (session
  timeline, journal, `wfstate_state` history, host status).
- Never restart the orchestrator while durable workflows are active unless the
  goal is a roll proof; replay order can diverge from persisted history on
  pre-marker runs.
- Never judge a run by Dapr `runtimeStatus`.
- Never reuse a deterministic instance id without `purge`/`reset` closure.

## Canonical Sources

- `docs/workflow-lifecycle-termination.md`
- `docs/dapr-workflow-purge-runbook.md`
- `docs/harness-host.md`
- `docs/context-strategy.md`
- `docs/dynamic-script-workflows.md`
- `scripts/probes/orchestrator-roll-proof.sh`
- `services/workflow-orchestrator/workflows/dynamic_script_workflow.py`
- `src/lib/server/lifecycle/`
- `src/lib/server/application/session-host-transport.ts`
