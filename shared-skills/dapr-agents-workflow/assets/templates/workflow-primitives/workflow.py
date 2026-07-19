"""Dapr Workflow primitives, isolated from agents.

Shows the three control-flow shapes you compose in any orchestrator:
  1. task chaining       — feed each activity's result into the next
  2. fan-out / fan-in    — when_all over a list of parallel activities
  3. human-in-the-loop   — when_any(external_event, timer) approval gate

To turn any activity into an agent step, replace `yield ctx.call_activity(...)`
with `yield call_agent(ctx, "<agent_name>", input=..., app_id="<app-id>")`.

Run:  dapr run --app-id worker --resources-path ./components -- python3 workflow.py
      (copy assets/components/agent-workflow.yaml into ./components next to this file)
"""

from datetime import timedelta

import dapr.ext.workflow as wf

wfr = wf.WorkflowRuntime()


# ---- activities: ALL non-determinism (I/O, LLM calls, clocks, randomness) lives here ----
@wfr.activity(name="enrich")
def enrich(ctx: wf.WorkflowActivityContext, item: dict) -> dict:
    return {**item, "score": len(item.get("text", ""))}


@wfr.activity(name="summarize")
def summarize(ctx: wf.WorkflowActivityContext, items: list) -> str:
    return f"processed {len(items)} items, total score {sum(i['score'] for i in items)}"


@wfr.activity(name="notify")
def notify(ctx: wf.WorkflowActivityContext, msg: str) -> str:
    print(f"[notify] {msg}")
    return "sent"


# ---- the workflow: a deterministic generator. NEVER do I/O or use a clock here. ----
@wfr.workflow(name="pipeline")
def pipeline(ctx: wf.DaprWorkflowContext, batch: list):
    # 2) fan-out: schedule one activity per item WITHOUT yielding, then fan-in with when_all
    parallel = [ctx.call_activity(enrich, input=item) for item in batch]
    enriched = yield wf.when_all(parallel)

    # 1) chaining: feed the aggregated result into the next activity
    summary = yield ctx.call_activity(summarize, input=enriched)

    # 3) human-in-the-loop: wait for an approval event OR time out after 1 hour.
    #    Create both tasks first, then race them with when_any (do not yield each).
    approval = ctx.wait_for_external_event(
        "approval"
    )  # raised via client.raise_workflow_event
    timeout = ctx.create_timer(timedelta(hours=1))
    winner = yield wf.when_any([approval, timeout])

    if winner == timeout:
        return {"status": "timed_out", "summary": summary}

    # decision is exactly the dict passed to raise_workflow_event(..., data={...}).
    decision = approval.get_result()
    if not decision.get("approved", False):
        return {
            "status": "rejected",
            "summary": summary,
        }  # gate the downstream work off the decision

    yield ctx.call_activity(notify, input=f"approved: {summary}")
    return {"status": "approved", "decision": decision, "summary": summary}


def main():
    wfr.start()
    client = wf.DaprWorkflowClient()
    iid = client.schedule_new_workflow(
        workflow=pipeline,
        input=[{"text": "alpha"}, {"text": "beta"}, {"text": "gamma"}],
    )
    # Elsewhere (e.g. an HTTP handler or a separate CLI) a human approves/rejects:
    #   client.raise_workflow_event(iid, "approval", data={"approved": True})
    state = client.wait_for_workflow_completion(iid, timeout_in_seconds=120)
    print(state.serialized_output if state else "no result")
    wfr.shutdown()


if __name__ == "__main__":
    main()
