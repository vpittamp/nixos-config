# Failure signals and rollout diagnosis


- `hub/build-<image>` and `hub/build-dev-images` are posted from the push
  lanes' `finally` on the merged commit. Failure there means the build broke on
  `main` — the run is kept 7 days.
- The BFF raises `build_failed` and `pin_drift` notifications from
  `tekton.pipelinerun` activity events (`src/lib/server/application/adapters/environment-image-builds.ts`,
  `gitops-activity-events.ts`).
- ArgoCD notifications: the **hub** `argocd-notifications-controller`
  (`packages/components/hub-management/manifests/argocd-notifications/`) posts
  through the in-cluster `gitops-event-relay` webhook service to the dev BFF
  (`POST /api/internal/gitops/events/ingest`). Rows land as activityType
  `argocd.application`; the bell
  renders them as `argocd_health` / `argocd_sync`. Subscription scope is the
  label **`notifications.stacks.io/spoke=dev`** on the hub-side `dev-*` child
  Applications and the two dev roots — those are the truthful objects, because
  the agent pushes spoke health into them and child health does not propagate to
  a root. Triggers: `on-health-degraded`, `on-sync-failed`,
  `on-sync-status-unknown`, `on-out-of-sync`, `on-deployed`.

The pipeline carrying those signals — `gitops_activity_events` ingest, the five
notification kinds, ArgoCD subscription-by-label and delivery, retention and the
conditional ArgoCD purge, Drasi continuous queries and the CDC replication-slot
failure mode, and the `/admin/gitops` and `/admin/drasi` surfaces — belongs to
**`platform-monitoring`**. Go there when a signal never arrived at all; what
follows is the delivery view.

**"My change is not on dev" — diagnose in this order:**

1. **Merged?** `git log origin/main` in the app repo, and confirm the queue
   actually merged rather than dropping the entry.
2. **Built?** `hub/image-build` on the merge SHA, then the PipelineRun. No run at
   all points at webhook loss (below), not at a build failure.
3. **Failed?** `hub/build-<image>` / `hub/build-dev-images` on the commit.
4. **Pinned?** Did the push lane write the pin to `stacks/main`? A merge-queue
   run builds the image but **never writes release pins** — only a push-lane run
   proves the push arrived.
5. **Promoted?** Hydrator status, Promoter CRs/PRs, current `env/spokes-dev`.
6. **Synced?** Target Application source/revision/health, and
   `.status.operationState.message` — a failing sync hook parks the entire app
   sync while it reads `OutOfSync` + `Healthy`, which looks benign.
7. **Pinned pointer?** If the change is under the preview platform, see
   *dev-preview-platform Pointer* — that app is pinned to an exact SHA and will
   report `Synced`/`Healthy` on old content.
8. **Live?** Deployment image and env, pod readiness, `daprd` state, then the
   authenticated user path.

