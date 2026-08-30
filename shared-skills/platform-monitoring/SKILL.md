---
name: platform-monitoring
description: "Read, prove, and repair the dev platform's own signals. Use for the GitOps activity-event pipeline and its ingest routes, development notification kinds (ci_failed, build_failed, pin_drift, argocd_health, argocd_sync), ArgoCD notification delivery and subscriptions, Drasi continuous queries, reactions, incidents and CDC replication slots, the /admin/gitops and /admin/drasi surfaces, event retention and prune rules, and answering why a failure went unnoticed. Use gitops for delivery itself, kubernetes-capacity for quota and pressure, workflow-builder for a single run's trace, and agent-session-recovery for session forensics."
---

# Platform Monitoring

This skill owns the signals the platform emits about itself: whether a failure
is visible at all, where it surfaces, how long it survives, and how to repair
the pipeline that carries it. Delivery mechanics belong to `gitops`; a single
run's trace belongs to `workflow-builder`.

Treat every claim here as falsifiable from the cluster and the database. A
signal you have not observed arriving is not a signal.

## The One Pipeline

Everything converges on one table and one client-side derivation:

1. **Producers.** Hub Argo Events streams GitHub webhook deliveries, Tekton
   `PipelineRun`/`TaskRun` transitions, GitOps Promoter state, and the
   deployment inventory. The hub `argocd-notifications-controller` sends
   Application health/sync conditions. Drasi's Kubernetes observer and
   Postgres CDC feed the continuous queries.
2. **Relay.** All hub-side producers post to `gitops-event-relay` (hub
   namespace `argo-events`), which forwards to the dev BFF.
3. **Ingest.** `POST /api/internal/gitops/events/ingest` writes
   `gitops_activity_events`; Drasi's Http reaction posts incidents to
   `POST /api/internal/drasi/incidents/ingest` and publishes on the
   `workflow.triggers` event bus.
4. **Derivation.** `src/lib/gitops/development-notifications.ts` maps rows to
   notification kinds entirely client-side; `src/lib/gitops/activity-tone.ts`
   colours the feed.
5. **Surfaces.** The notification bell and toasts, the `/admin/gitops`
   activity feed and fleet-drift matrix, and the `/admin/drasi` tabs
   (Activity, Data Sources, Incidents, Notifications).

Consequence worth internalising: **the bell is a page, not a pager.** Nothing
here wakes a human. If an incident must interrupt someone, that is a gap to
design, not something to assume.

## Notification Kinds

| Kind | Raised from | First action |
| --- | --- | --- |
| `ci_failed` | `github.check_run` / `github.workflow_run` / `github.status` | Read the failing check run on the PR head. |
| `build_failed` | `tekton.pipelinerun` reaching a failed phase (hub outer-loop and dev-image lanes) | Read the PipelineRun on hub; failed runs are retained 7 days. The commit also carries a `hub/build-<image>` status. |
| `pin_drift` | the fleet-drift lane: a release pin behind repository `main` past the configured threshold, or the dev-image lane ahead of the app lane | Check whether a build failed or a webhook delivery was lost before assuming a stuck sync. |
| `argocd_health` | ArgoCD trigger `on-health-degraded` | Open the named Application; child health does not propagate to the hub root app. |
| `argocd_sync` | `on-sync-failed` (error) and `on-sync-status-unknown` (warning) | Same, plus check the repo revision the app is trying to reach. |

`on-out-of-sync` and `on-deployed` are deliberately feed-only: they are
frequent and self-healing, so they inform the activity feed without raising a
notification.

ArgoCD subscriptions are a **label**, not per-app annotations: hub-side child
Applications carrying `notifications.stacks.io/spoke=dev` are subscribed
through one `subscriptions` block in `argocd-notifications-cm`. Adding a spoke
app to the notification set means stamping that label, not editing the
ConfigMap. Expect a one-time `on-deployed` burst the first time the label
lands, because the engine has no first-sight suppression.

## Retention And The Purge Rule

The dev CronJob `gitops-event-prune` calls the prune route every five minutes
with a fourteen-day retention. The route applies two rules, and the difference
between them matters:

- Legacy high-volume ArgoCD **watch** noise — rows with `source = 'argocd'` and
  **no** `correlation.notificationTrigger` — is swept regardless of age.
- Everything else, including every ArgoCD **notification** row, expires only at
  the ordinary retention cutoff.

Never widen that sweep back to an unconditional `source = 'argocd'` delete. It
was unconditional once: notifications were delivered correctly and then erased
within five minutes, so the feed and the bell could never show one, and the
whole channel looked broken while the controller and relay logs said it was
working. If ArgoCD signals "stop arriving", check the purge predicate before
you suspect the controller.

## Drasi On Dev

Drasi watches the platform's own state and raises incidents. Two facts shape
every interaction with it:

- **Dev has no Drasi CRDs.** Resources live in the ConfigMap
  `drasi-workflow-monitoring-resources-*` in namespace `drasi-system` and are
  applied by `drasi-resource-reconciler`. Edit the source in stacks
  (`packages/components/addons/drasi-dev/manifests/workflow-monitoring/`), not
  the cluster.
- **Queries are versioned by name.** A behaviour change means a new `-vN`
  identifier, and the NetworkPolicy must be updated in the same change or the
  new query cannot reach its sources.

Continuous queries and their windows: workflow-execution start-orphaned (30 m),
Kueue workload-orphaned (5 m), Kueue admission-urgent (3 m), and Dapr resource
drift (60 s, restricted to the `dapr.io` group). Incident detectors the BFF
admits include those plus the CDC slot watchdog, the heartbeat watchdog, the
Kueue admission-stalled lane, the Dapr resource warning lane, and the
ClickHouse telemetry stalled-reminder-storm lane.

## CDC Is The Fragile Part

Drasi consumes Postgres changes through two logical replication slots,
`rg_workflow_builder_postgres_v3` and `rg_workflow_builder_k8s_observations_v4`.
If a slot goes inactive long enough to fall past `max_slot_wal_keep_size`, the
server invalidates it and **every continuous query goes silent** while every
other surface still looks healthy.

Recognise it by: both slots `active = f` with `wal_status = lost`; the
reactivator pods restarting with "Unable to obtain valid replication slot";
`drasi-cdc-health` at `0/1`; and — the only ambient sign — the dev Application
`dev-drasi-workflow-monitoring` sitting in `Progressing`.

The observer-freshness heartbeat does **not** prove consumption on its own: the
observations table keeps being written directly, so producer freshness stays
green through a total CDC outage. That is how a 22-hour silence went unnoticed.
A CDC slot check now runs inside the heartbeat lane and raises
`drasi-cdc-slot-lost`; treat that reason as "queries are blind", not as a
warning.

Recovery, proven end to end:

```bash
# 1. drop the invalidated slots (a lost slot is inactive, so this is safe)
kubectl --context dev exec -n workflow-builder postgresql-cnpg-1 -c postgres -- \
  psql -U postgres -d workflow_builder -Atc \
  "select pg_drop_replication_slot('rg_workflow_builder_postgres_v3'); \
   select pg_drop_replication_slot('rg_workflow_builder_k8s_observations_v4');"

# 2. restart BOTH reactivators BY NAME (their labels are not app=<name>)
kubectl --context dev -n drasi-system get pods | grep reactivator
kubectl --context dev -n drasi-system delete pod <postgres-v3-reactivator> <k8s-observations-v4-reactivator>

# 3. re-bootstrap the queries, which otherwise keep stale state
kubectl --context dev -n drasi-system rollout restart deploy/default-query-host
```

Debezium recreates both slots within about fifteen seconds and streams from the
latest LSN, so there is no snapshot and no backfill of the silent window — data
lost to the outage stays lost. Verify all four of: slots `active = t` with
`wal_status = reserved`, `drasi-cdc-health` `1/1`, the Application `Healthy`,
and each query logging `Status updated to Running` in `default-query-host`.

## Verification Recipes

Prove a signal arrived rather than assuming it did:

```bash
# notification rows, newest first (source, trigger, app, time)
kubectl --context dev exec -n workflow-builder postgresql-cnpg-1 -c postgres -- \
  psql -U postgres -d workflow_builder -Atc \
  "select source, activity_type, coalesce(correlation->>'notificationTrigger','-'), \
          resource_name, observed_at from gitops_activity_events \
   where activity_type = 'argocd.application' order by observed_at desc limit 5"

# durability: re-run after five minutes; rows must survive the prune tick
# CDC slot health
kubectl --context dev exec -n workflow-builder postgresql-cnpg-1 -c postgres -- \
  psql -U postgres -d workflow_builder -Atc \
  "select slot_name, active, wal_status from pg_replication_slots where slot_name like 'rg_%'"

# subscribed spoke applications
kubectl --context hub-cluster get application -A -l notifications.stacks.io/spoke=dev --no-headers | wc -l
```

To exercise the ArgoCD path without harming anything, change a **git-declared**
annotation value on one hub-side dev child Application (an *extra* annotation
will not register as drift under the three-way diff). Self-heal reverts it
within seconds and one `on-out-of-sync` row lands. Do not degrade a workload to
manufacture a health event.

## What Is Still Silent

State these plainly rather than implying full coverage:

- No post-merge smoke or canary runs on dev; a rollout that is healthy but
  wrong produces no signal.
- Only labelled hub-side dev child Applications are subscribed; anything
  outside that selector is invisible to the notification lane.
- Preview-local activity does not reach the host feed.
- Nothing pages a human; every surface here is pull-based.

## Safety

- This skill is read-mostly. Never delete or edit activity rows, incidents, or
  Drasi resources by hand to make a surface look correct.
- Never restart `default-query-host`, the reactivators, or the relay while a
  proof, benchmark, or evaluation campaign depends on the signals they carry.
- Fix monitoring in stacks and workflow-builder source, then let delivery carry
  it; a live patch to a Drasi ConfigMap or a notification ConfigMap is
  diagnostic only and will be reverted by its owner.
- When a signal is missing, prove which hop dropped it — producer, relay,
  ingest, row, derivation, surface — before changing anything. Each hop has its
  own log or query above.
