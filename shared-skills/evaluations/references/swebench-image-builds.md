# SWE-bench Image Builds And Cache Strategy

Use this when a SWE-bench run waits in preflight, exact-ready coverage is low,
hub Tekton is building `swe-env-*` images, or the user asks how image building
and caching should work for benchmark capacity.

## Image Categories

There are two separate image lanes:

- Runtime images from the workflow-builder repo: `workflow-builder`,
  `swebench-coordinator`, `swebench-evaluator`, `dapr-agent-py`,
  `dapr-agent-py-sandbox`, and `dapr-agent-py-testing-sandbox`. These are built
  by the hub GitHub webhook lane, pushed to GHCR, and delivered through stacks
  release metadata or explicit active-development pins.
- SWE-bench inference environment images: per repo/base/version/env-spec images
  built by hub Tekton PipelineRuns named `swe-env-<envSpecHash-prefix>`. These
  are selected by benchmark preflight and recorded as exact-ready static
  ConfigMap entries or dynamic `environment_image_builds` rows.

Do not look for Buildah pods on dev for preflight image work. Dev benchmark
runs should either consume exact-ready images or wait on hub Tekton to validate
and publish them.

The supported SWE-bench inference path is the organic harness-generated image
path. Do not use Epoch/prebuilt SWE-bench images as a drop-in replacement unless
a fresh compatibility canary proves the image layout, workspace profile step,
agent start, LLM/tool loop, evaluator harness, and cleanup path all work. The
2026-05-27 Epoch experiment failed at OpenShell sandbox readiness/workspace
profile, so stale Epoch-derived rows and PipelineRuns should be deleted rather
than allowed to satisfy exact-ready selection.

## Exact-Ready Rule

Capacity runs should use distinct exact-ready SWE-bench_Verified instances.
Exact-ready means the selected instance has a validated image for the current
environment identity:

- static ConfigMap pins are ready when suite, repo, base commit, version, and
  image digest match the current environment;
- dynamic DB build rows are ready only when `env_spec_hash` equals the current
  `buildSwebenchEnvironmentSpec()` hash;
- repo/version/base-commit-only matches are not enough.

If a random run is `queued`, no instance workflows have session IDs, and hub has
active `swe-env-*` PipelineRuns, the benchmark is waiting for exact-ready image
coverage. That is not an inference-concurrency failure.

## Cache Strategy

The hub Buildah lane uses a shared PVC cache for SWE-bench environment builds.
The cache is valuable, but it is not a substitute for exact-ready validation:
only reuse an image after the environment identity matches.

Current cache safety rules:

- use the `envSpecHash` as the de-duplication key so repeated preflight requests
  converge on the same logical build;
- include or verify the build source/strategy when reusing an existing
  `swe-env-*` PipelineRun. A stale experimental PipelineRun can collide on the
  same env hash prefix; if its params mention `epoch-research`, `prebuiltImage`,
  or `swe-bench.eval`, treat it as incompatible with the organic lane;
- keep the Buildah cache lock self-healing. A retry pod can inherit the parent
  TaskRun name after an OOMKill, so the lock holder may appear to be the retry
  itself. The lock acquisition path must allow same-TaskRun takeover;
- keep Pipeline `finally:` cleanup for cache locks, and keep stale-lock age low
  enough that a dead build cannot block follow-up work for hours;
- prefer raising build memory before raising parallelism. OOMKilled builds are
  slower than conservative parallelism because they poison the cache lock path;
- avoid repeatedly selecting instances that trigger cold builds when the goal is
  inference capacity. First prove infra with existing exact-ready coverage, then
  run a separate image-coverage campaign.

Useful future improvements:

- record per-build cache-hit/miss, wall time, peak memory, and image size in a
  queryable store such as ClickHouse;
- pre-warm high-value repo/version bases before large capacity runs;
- expose exact-ready counts by suite/repo/version in the launch preview;
- schedule build workers and benchmark workers separately so image work cannot
  steal capacity from an active benchmark checkpoint.

Capacity throttles are not image failures. If the validation script records a
synthetic `dynamic_build_capacity_exhausted` result, classify it as a controller
throttle artifact and keep the row out of coverage/failure counts. The durable
fix is to make the script sleep/retry without persisting a failed build row.

## Debug Checklist

1. Check the benchmark run state and whether any instance workflows have started.
2. Check hub Tekton for active or failed `swe-env-*` PipelineRuns.
3. Check whether the PipelineRun spec/params match the current organic build
   source. Delete stale Epoch/prebuilt PipelineRuns and DB rows before
   submitting organic builds for the same env hash.
4. If a PipelineRun is stuck, inspect the build pod for cache-lock wait,
   OOMKilled containers, image-push errors, or short-name base-image failures.
5. After a successful build, verify workflow-builder sees the refreshed
   inference-environments ConfigMap or matching dynamic build row.
6. Re-run launch preview before creating a larger cohort; do not assume a build
   that completed after preview is already visible to the BFF pod.

## Background Build Campaign

For long-running coverage work, run the queueing loop as a Kubernetes Job in
`dev/workflow-builder` using the workflow-builder image and service account.
That Job is only the controller; with
`SWEBENCH_INFERENCE_BUILD_SUBMISSION_MODE=hub` and
`SWEBENCH_INFERENCE_BUILD_HUB_KUBECONFIG` configured, actual build PipelineRuns
are created on the hub cluster.

Use a small observed cap such as `SWEBENCH_INFERENCE_BUILD_MAX_ACTIVE=2` until
hub metrics support a change. Before raising it, check hub build-node
DiskPressure/MemoryPressure/PIDPressure, Tekton/Kueue admission, cache PVC
placement, and completed/failed TaskRuns. Do not delete active build pods or
cache PVCs as a normal cleanup step.

The controller loop should target exact-ready coverage, for example:

```bash
node scripts/queue-swebench-environment-validation.bundle.js \
  --suite SWE-bench_Verified \
  --limit 500 \
  --target-validated 200 \
  --loop \
  --poll-seconds 300 \
  --exact-for-random-runs \
  --api-url http://workflow-builder.workflow-builder.svc.cluster.local:3000 \
  --apply
```

Early in a campaign, monitor the Job logs and hub `swe-env-*` PipelineRuns until
at least one fresh organic image validates. Then launch a tiny personal-user
canary against only those new images.

## Stale Experimental Data Cleanup

If Epoch/prebuilt data was tested and then abandoned, remove both hub Tekton
objects and DB rows so future previews cannot accidentally reuse them.

Hub cleanup pattern:

```bash
kubectl --context hub -n tekton-pipelines get pipelineruns -o json |
  jq -r '.items[]
    | select((.metadata.name | startswith("swe-env-"))
      and ((.spec.params // []) | tostring | test("epoch-research|prebuiltImage|swe-bench.eval")))
    | .metadata.name' |
  xargs -r kubectl --context hub -n tekton-pipelines delete pipelinerun
```

DB cleanup pattern from the workflow-builder pod:

```sql
delete from environment_image_builds
where suite = 'SWE-bench_Verified'
  and (
    spec::text like '%epoch-research%'
    or spec::text like '%prebuiltImage%'
    or spec::text like '%swe-bench.eval%'
  );
```

After cleanup, verify the DB count for those patterns is zero and the hub query
returns no `swe-env-*` PipelineRuns.

## Compatibility Canary

After fresh images validate, run a two-instance SWE-bench canary under the
personal user/project when the user asks for personal-account validation. Keep
it short, such as `maxTurns=5`, because this is an image/runtime compatibility
test, not a model-quality test.

Passing criteria:

- preview selects only the freshly validated exact-ready instances;
- OpenShell sandboxes become ready;
- sessions are created and record LLM/tool activity;
- evaluator prepare/run/finalize pods complete;
- run reaches terminal state with zero infra errors;
- leases are released and OpenShell sandboxes are cleaned up.

Unresolved harness results are acceptable for this canary. The evidence that
matters is image compatibility through inference and evaluation. The
2026-05-27 personal-user canary `r30r9I76rLiwv-BGz9VL5` validated this path for
two new organic Django images with `maxTurns=5`: both inferred, both evaluated,
zero infra/image/sandbox errors, and all leases/sandboxes cleaned up.

Ryzen can consume the same validated organic SWE-bench inference images because
the selector resolves digest-pinned GHCR refs from the same exact-ready
metadata. The ryzen canary `MPIlRkKWC7UdvHgwFQEiR` selected three existing
organic Astropy images, ran effective concurrency 2 after the full-instance
capacity fix, reached 10 LLM/tool calls on all three instances, evaluated, and
released all leases. Use this as the compatibility proof for reusing dev/hub
organic images on ryzen.
