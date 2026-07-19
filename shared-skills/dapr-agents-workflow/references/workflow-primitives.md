# Dapr Workflow — Python API surface

Dapr's deterministic orchestration engine. This reference matches
`dapr-ext-workflow` **1.18.x**, imported as `dapr.ext.workflow`. Everything in this file is the foundation both for
plain workflows and for the workflow-orchestrated agent pattern (Pattern A).

> Install the version required by the target project's lockfile. Do not mix the
> stable package with a development runtime from another API line.

## Imports

```python
import dapr.ext.workflow as wf
# exported names: WorkflowRuntime, DaprWorkflowClient, DaprWorkflowContext,
# WorkflowActivityContext, RetryPolicy, when_all, when_any, WorkflowState, WorkflowStatus
```

`when_all` / `when_any` are **module-level functions** (`wf.when_all([...])`), NOT methods
on the context. This is the single most common mistake.

## Authoring: runtime + decorators

```python
wfr = wf.WorkflowRuntime()

@wfr.workflow(name="my_workflow")            # name is optional but recommended
def my_workflow(ctx: wf.DaprWorkflowContext, wf_input):
    ...

@wfr.activity(name="my_activity")            # name optional
def my_activity(ctx: wf.WorkflowActivityContext, activity_input):
    ...

wfr.start()      # begins processing; call once at app startup
wfr.shutdown()   # at app exit
```

- A **workflow** is a generator: it `yield`s tasks and is **replayed** from the start on
  every event. A workflow function may run many times for one logical instance.
- An **activity** runs exactly the side-effecting work. It is _not_ replayed the way the
  workflow body is — its recorded result is replayed instead.

## The determinism contract (the #1 source of bugs)

Because the workflow body replays, it MUST be deterministic:

- **No I/O, network, DB, file, or LLM calls in the workflow body.** Put them in activities
  (or, for agents, in `call_agent`). The workflow only _orchestrates_.
- **No `datetime.now()`, `random`, `uuid4()`, env reads, or global mutable state** in the body.
  Use `ctx.current_utc_datetime` for time and `ctx.create_timer(...)` for delays.
- **Always `yield` a scheduled task** (`call_activity`, `call_child_workflow`, `call_agent`,
  `create_timer`, `when_all/when_any`). An unyielded task is never awaited.
- Inputs/outputs must be **JSON-serializable** (dataclasses/pydantic that serialize cleanly are fine).

## DaprWorkflowContext — the orchestration primitives

| Call                                                                                 | Purpose                                                                                       |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| `yield ctx.call_activity(fn, input=...)`                                             | run an activity, get its result                                                               |
| `yield ctx.call_child_workflow(wf_fn, input=..., instance_id=..., retry_policy=...)` | run a sub-workflow (this is what `call_agent` wraps)                                          |
| `task = ctx.wait_for_external_event(name)`                                           | a future that completes when an event is raised                                               |
| `task = ctx.create_timer(timedelta(...))`                                            | a durable timer future                                                                        |
| `yield wf.when_all([t1, t2, ...])`                                                   | fan-in: wait for ALL, returns a list of results                                               |
| `yield wf.when_any([t1, t2])`                                                        | race: returns the FIRST task that completes                                                   |
| `ctx.current_utc_datetime`                                                           | deterministic "now" (safe in the body)                                                        |
| `ctx.instance_id`                                                                    | this instance's id                                                                            |
| `ctx.is_replaying`                                                                   | True while replaying — gate non-durable side effects (e.g. logging) on `not ctx.is_replaying` |

### Three canonical shapes

**Chaining** — feed each result into the next:

```python
@wfr.workflow(name="chain")
def chain(ctx, wf_input):
    a = yield ctx.call_activity(step1, input=wf_input)
    b = yield ctx.call_activity(step2, input=a)
    try:
        c = yield ctx.call_activity(step3, input=b)
    except Exception as e:
        yield ctx.call_activity(error_handler, input=str(e))
        raise
    return c
```

**Fan-out / fan-in** — build the task list first, then `when_all`:

```python
parallel = [ctx.call_activity(work, input=item) for item in batch]
outputs = yield wf.when_all(parallel)        # list of results, order preserved
total = sum(outputs)
```

**Human-in-the-loop** — race an external event against a timeout:

```python
approval = ctx.wait_for_external_event("approval")
timeout = ctx.create_timer(timedelta(hours=1))
winner = yield wf.when_any([approval, timeout])
if winner == timeout:
    return "timed out"
decision = approval.get_result()   # the payload from raise_workflow_event
```

## Retries

```python
policy = wf.RetryPolicy(
    first_retry_interval=timedelta(seconds=1),
    max_number_of_attempts=5,
    backoff_coefficient=2.0,
    max_retry_interval=timedelta(seconds=30),
)
yield ctx.call_activity(flaky, input=x, retry_policy=policy)
yield ctx.call_child_workflow(child, input=x, retry_policy=policy)
```

## DaprWorkflowClient — lifecycle management (from outside the workflow)

```python
client = wf.DaprWorkflowClient()
iid = client.schedule_new_workflow(workflow=my_workflow, input=data, instance_id="optional-id")
client.wait_for_workflow_start(iid, timeout_in_seconds=30)
state = client.wait_for_workflow_completion(iid, timeout_in_seconds=120)
client.get_workflow_state(iid)
client.raise_workflow_event(iid, "approval", data={"ok": True})   # drives wait_for_external_event
client.pause_workflow(iid)
client.resume_workflow(iid)
client.terminate_workflow(iid)
client.purge_workflow(iid)        # purge requires a terminal state; recursive=True by default
```

`terminate` _requests_ shutdown — it is not proof the instance is terminal. Poll
`get_workflow_state` until terminal before `purge`.

## State store requirement

Dapr Workflow runs on **actors**, so the app's daprd needs a state store with
`actorStateStore: "true"`. A sidecar refuses to start if it sees **more than one** such
component — keep exactly one (here, `agent-workflow.yaml`). See `assets/components/`.

## Sources (verified against upstream, 2026-06)

- docs.dapr.io › Python Workflow SDK + Workflow building block + workflow-patterns
- `dapr/python-sdk` `ext/dapr-ext-workflow` (`__init__.py`, `dapr_workflow_client.py`, `examples/workflow/`)
