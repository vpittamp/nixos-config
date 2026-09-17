---
name: software-factory
description: "Operate the Workflow Builder Delivery Board and software factory on dev — the issue-to-merged-PR lane. Use for board cards and phases, intake subscriptions and reconcile cadence, factory policy and auto-start, phase runs and attempts, the preview environment a build phase binds, and reading live board state. Use gitops for the stacks release lane and image pins, preview-environments for PreviewEnvironment lifecycles and DevelopmentRuns, and workflow-builder for dynamic-script workflows and durable agent sessions."
---

# Software Factory

The Delivery Board is the issue-to-merged-PR factory: GitHub issues and pull
requests become cards, and cards walk phases that dispatch agent runs.

`PittampalliOrg/workflow-builder` **`docs/delivery-board.md` is the source of
truth — read it first.** This skill carries the operational knowledge that the
document does not: how to read live state, and the traps that cost outages.

Resolve disagreements in this order: live database and cluster > application
code (`src/lib/domain/software-factory.ts`, `src/lib/server/application/`) >
`docs/delivery-board.md` > this skill.

## Two Boards, One Card Model

| Board    | Source                | Phases                                                          |
| -------- | ---------------------- | ----------------------------------------------------------------- |
| `work`   | GitHub **issues**     | `intake` → `triage` → `assessed` → `planning` → `planned` → `building` → `review` → `completing` → `done` |
| `review` | GitHub **pull requests** | `reviewing` / `rereviewing` → merged                          |

Phases are `resting` (waiting for an event) or `working` (an agent run is
dispatched). `failed` is **resting, not terminal** — a failed card can be sent
back to `triage`, `planning`, `building`, or `completing`.

Pull requests are dropped from the issues listing, because a PR filed as a Work
card is a card nobody can complete.

## Intake Is Subscription-Gated

A board does not track a repository because an authenticated webhook arrived
from it. `delivery_intake_subscriptions` is `(project_id, repo)` with
`takes_work` / `takes_review` lanes; a delivery for an unsubscribed repo is
acknowledged and dropped. **Check the subscription before calling missing intake
a bug.**

The reconciler re-reads the repository through an authenticated client and never
writes webhook payload contents into application state. It fails closed in three
distinguishable ways: closed → `done`/`canceled`; unreadable (502/403/timeout)
→ **leaves the card alone**, reports `unreadable`, marks the pass `degraded`;
404 → also leaves it alone, because a vanished issue needs a person.

### Cadence, and why it is the whole latency

The reconcile job is a **Dapr Job** (`delivery-board-reconcile`) upserted at pod
boot, configured by env on the workflow-builder Deployment:

| Env                                  | Note                                              |
| ------------------------------------ | --------------------------------------------------- |
| `DELIVERY_BOARD_RECONCILE_ENABLED`   | must be `"true"`; code default is OFF               |
| `DELIVERY_BOARD_RECONCILE_SCHEDULE`  | `/^@every\s+\d+(ms\|s\|m\|h)$/`; code default `@every 15m` |
| `DELIVERY_BOARD_RECONCILE_LIMIT`     | default 50                                          |

The design says the webhook makes the board *fast* and the timer makes it
*correct*. **On this fleet the fast path does not exist**: the
`PittampalliOrg/workflow-builder` `issues` webhook delivers to
`argo-events-hub`, and nothing delivers to the BFF's own
`/api/internal/github/webhook`. The timer is therefore the *only* path that
notices a new issue, and **its interval is the intake latency** — measured at
8m30s on a 15m schedule before dev was moved to `@every 1m`. If you are asked
why a fresh issue has no card, check the last tick time before anything else.

A pass is cheap: it reads the still-open items (`unchanged=2` on a board with
163 closed cards), not the whole history.

Verify a schedule change actually took: both pods must log
`[delivery-board] scheduled Dapr Job 'delivery-board-reconcile' (@every 1m)`,
and tick timestamps must be that far apart. `POST
/api/internal/delivery-board/reconcile` drives the same pass by hand.

## Policy And Auto-Start

Policy is one JSON row per project in **`factory_policies`** (migration 0194;
it replaced `delivery_board_automation`, which 0194 drops — a stale local copy
of that older migration file will mislead you). Read and write it with the
`get_software_factory` and `set_factory_policy` MCP tools rather than SQL.

```json
{"version":1,
 "phases":{"work.triage":"manual","work.planning":"automatic","work.building":"automatic",
           "work.completing":"automatic","review.reviewing":"automatic","review.rereviewing":"automatic"},
 "acceptWork":true,"approvePlans":true,"mergePullRequests":true,
 "completionEvidence":"deployment","builderProfile":"dapr-agent-py",
 "maxDispatchAttempts":5,"maxReworkAttempts":3,"phaseTimeoutSeconds":3600,
 "verification":"advisory"}
```

**"Auto-start" is not a switch — it is the `phases` map.** A single phase left
`"manual"` stops every card at that phase while everything downstream looks
correctly configured. `work.triage: "manual"` is the usual culprit: cards pile
up in `intake` and the board looks broken. Set the phase to `"automatic"`.

A card stops on its own at any phase requiring `accept` or `merge` approval;
neither is delegable. `merge` is read from the pull request, never inferred from
"closed", so a closed-unmerged PR cannot record it.

The domain refuses an automatic entry into a working phase unless
`autoStartRuns` is true — and it **fails closed on an unreadable setting**, so
"off" and "I could not read it" look identical from outside. Read the row.

## The Build Phase Binds A Preview Environment

`building` provisions a preview environment named
`factory-<cardId lowercased, non-alphanumerics stripped, 20 chars>`
(`factoryPreviewEnvironmentName`) and waits for it. This is where cards stall
most often, and the stall is usually **not** about the card.

- `DEAD_PREVIEW_PHASES` = `failed, terminating, absent, slept, expired`
  (`software-factory.ts`). A phase in that set makes the factory null its
  binding and call `ensure()` again.
- **Trap — the BFF and the cluster can disagree.** `get_preview_environment` has
  been observed reporting `phase: "failed"` at the same moment the hub
  `PreviewEnvironment` CR read `Provisioning` / `Ready=False /
  WaitingForApplication`. Because `failed` is a dead phase, the factory re-binds
  a still-provisioning environment instead of waiting for it. **Always read the
  hub CR before believing a "failed" preview**, and note the CR lives in
  namespace `preview-system` on hub — a namespace-less `kubectl get` returns
  `NotFound` and looks like a deleted environment.
- **Trap — fresh preview vclusters race their own CRDs.** A per-card vcluster
  starts empty; if the workflow-builder Application syncs before agent-sandbox
  is installed, Argo fails with `failed to discover server resources for group
  version extensions.agents.x-k8s.io/v1alpha1` and retries with backoff. A
  long-lived warm-pool environment on the same profile is `Synced/Healthy`,
  which is the fastest way to tell a provisioning race from a real gap: compare
  the two vclusters' pods for `agent-sandbox-controller`.

## Reading Live State

Board state is in the dev `workflow_builder` database. Prefer the MCP tools
(`get_software_factory`, `get_factory_item`) — `get_software_factory` can exceed
the tool-result limit, so slice the saved file rather than re-calling it.

For direct reads, **the app pod has no `psql`**. Use the app's own driver, which
also keeps `DATABASE_URL` inside the pod:

```bash
POD=$(kubectl --context dev -n workflow-builder get pods -l app=workflow-builder \
      -o jsonpath='{.items[0].metadata.name}')
cat > /tmp/q.mjs <<'JS'
import postgres from "/app/node_modules/postgres/src/index.js";   // ESM ignores NODE_PATH
const sql = postgres(process.env.DATABASE_URL, { max: 1, ssl: false });
console.log(JSON.stringify(await sql`select source_number, board, phase from delivery_cards
  where source_kind='issue' and phase not in ('done','canceled')`, null, 1));
await sql.end();
JS
kubectl --context dev -n workflow-builder exec -i "pod/$POD" -c workflow-builder -- \
  sh -c 'cat > /tmp/q.mjs && node /tmp/q.mjs' < /tmp/q.mjs
```

Three details that each cost a failed attempt: `/app` is **read-only** but
`/tmp` is writable; ESM resolution ignores `NODE_PATH`, so import the driver by
absolute path; and `postgresql-cnpg-app` points at database `app`, which is
empty — `DATABASE_URL` is the right one.

Tables worth knowing: `delivery_cards`, `delivery_card_events` (append-only,
`seq`-ordered), `delivery_intake_subscriptions`, `factory_policies`,
`factory_ticks` (per-tick result JSON — **the fastest way to see why a card is
not moving**), `factory_attempts`.

A tick result reads like
`{"state":"attention","cardId":"…","reason":"…","pollSeconds":15}`. `attention`
means the factory wants a person; the `reason` names the blocker verbatim.

## Traps

- A card in `building` with `phase_run_execution_id = null` for minutes is
  almost always blocked on its preview environment, not on an agent.
- `created=0` on a tick with a new issue open means the repo is unsubscribed,
  the lane is off (`takes_work`), or the issue arrived after the pass — check in
  that order.
- A pass that could not list the repository still refreshes existing cards and
  reports `listingError`; `summarizeReconcile()` marks it `degraded`. **A
  degraded pass is not proof of board freshness.**
- Enabling automation applies to *every* open card, not just the one in front of
  you. Check what else is resting in `intake` before flipping a phase.

## Canonical Sources

`PittampalliOrg/workflow-builder`: `docs/delivery-board.md` (SSOT);
`src/lib/domain/{software-factory,delivery-board,delivery-intake}.ts`;
`src/lib/server/application/{software-factory,delivery-intake,delivery-journey}.ts`;
`src/lib/server/application/adapters/delivery-intake-job-deps.ts`;
`src/routes/api/internal/delivery-board/reconcile/+server.ts`;
`drizzle/0187_delivery_board.sql` through `drizzle/0196_factory_events_notify.sql`.

`PittampalliOrg/stacks`:
`packages/components/workloads/workflow-builder/manifests/Deployment-workflow-builder.yaml`
(the `DELIVERY_BOARD_RECONCILE_*` env).
