"""Pattern A — Workflow-orchestrated agents.

A DETERMINISTIC Dapr Workflow is the orchestrator. It invokes each agent as a
durable CHILD WORKFLOW via call_agent(...), so the whole multi-agent run is
checkpointed and retriable. This is the quickstart-06 shape.

Run the whole topology with:  dapr run -f dapr.yaml
"""

import dapr.ext.workflow as wf
from dapr_agents.workflow.utils.core import call_agent

wfr = wf.WorkflowRuntime()


@wfr.workflow(name="support_workflow")
def support_workflow(ctx: wf.DaprWorkflowContext, request: dict):
    # The workflow body is REPLAYED on every event — keep it deterministic:
    # no I/O, no clocks, no randomness here. All real work happens in the agents.

    # Step 1 — triage agent runs as a child workflow on Dapr app-id "triage-agent".
    # `name` ("triage_agent") must equal the DurableAgent(name=...) in triage_agent.py.
    # `app_id` ("triage-agent") must equal the appID in dapr.yaml. They are DIFFERENT ids.
    triage = yield call_agent(
        ctx, "triage_agent", input=request, app_id="triage-agent"
    )
    # call_agent returns the agent's final assistant message as a DICT:
    # {"role": "assistant", "content": "...", "name": ...}. Read .get("content").
    triage_text = triage.get("content", "") if isinstance(triage, dict) else triage

    # OPTIONAL human-in-the-loop gate between agents — uncomment to require approval.
    # See workflow-primitives/workflow.py for the full pattern and approve.py to raise it:
    #   approval = ctx.wait_for_external_event("approval")
    #   timeout = ctx.create_timer(timedelta(hours=1))
    #   if (yield wf.when_any([approval, timeout])) == timeout:
    #       return {"status": "timed_out", "triage": triage_text}
    #   if not approval.get_result().get("approved", False):
    #       return {"status": "rejected", "triage": triage_text}

    # Step 2 — expert agent, fed the triage result. Each yielded step is durable + retriable.
    recommendation = yield call_agent(
        ctx,
        "expert_agent",
        input={"triage": triage_text, "request": request},
        app_id="expert-agent",
    )

    return recommendation.get("content", "") if isinstance(recommendation, dict) else recommendation


def main():
    wfr.start()
    client = wf.DaprWorkflowClient()
    instance_id = client.schedule_new_workflow(
        workflow=support_workflow,
        input={"customer": "alice", "issue": "cannot log in"},
    )
    state = client.wait_for_workflow_completion(instance_id, timeout_in_seconds=120)
    print(state.serialized_output if state else "no result")
    wfr.shutdown()


if __name__ == "__main__":
    main()
