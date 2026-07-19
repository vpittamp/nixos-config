"""Out-of-band approval — the 'human clicks approve' side of a human-in-the-loop gate.

A real approval gate needs a SECOND entry point: the workflow waits on an external
event while a human (or another service) raises it from elsewhere. Run this from a
separate terminal once the workflow is parked at the gate:

    python3 approve.py <instance_id> true     # approve
    python3 approve.py <instance_id> false    # reject

(The orchestrator prints its instance_id when it schedules the run.)
"""

import sys

import dapr.ext.workflow as wf


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python3 approve.py <instance_id> [true|false]")
    instance_id = sys.argv[1]
    approved = (
        sys.argv[2].lower() in ("1", "true", "yes") if len(sys.argv) > 2 else True
    )

    client = wf.DaprWorkflowClient()
    # event name "approval" must match ctx.wait_for_external_event("approval") in the workflow.
    client.raise_workflow_event(instance_id, "approval", data={"approved": approved})
    print(f"raised approval={approved} for {instance_id}")


if __name__ == "__main__":
    main()
