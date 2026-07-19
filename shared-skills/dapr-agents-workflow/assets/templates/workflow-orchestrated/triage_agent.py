"""Triage agent — a DurableAgent served as its own Dapr app.

The orchestrator (workflow_app.py) reaches it by app-id "triage-agent" and by the
agent name "triage_agent". serve() also starts the workflow runtime, so the agent is
callable both over HTTP and as a child workflow.
"""

from dapr_agents import DurableAgent, AgentRunner, tool
from dapr_agents.llm import OpenAIChatClient
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.agents.configs import AgentMemoryConfig, AgentStateConfig
from dapr_agents.storage.daprstores.stateservice import StateStoreService


@tool
def get_customer_info(customer_name: str) -> str:
    """Get customer account information by name."""  # docstring is REQUIRED for @tool
    db = {"alice": "Alice — Premium plan, 5 active services, joined 2021"}
    return db.get(customer_name.lower(), f"{customer_name} — Standard plan")


triage_agent = DurableAgent(
    name="triage_agent",  # MUST match call_agent(ctx, "triage_agent", ...)
    role="Support Triage Assistant",
    goal="Gather customer information and produce a concise triage summary.",
    instructions=[
        "Call get_customer_info with the customer name.",
        "Summarize plan, tenure, and the reported issue for the expert.",
    ],
    llm=OpenAIChatClient(),  # provider-direct (GA). Or DaprChatClient(component_name="llm-provider").
    tools=[get_customer_info],
    memory=AgentMemoryConfig(
        store=ConversationDaprStateMemory(store_name="agent-memory")
    ),
    state=AgentStateConfig(store=StateStoreService(store_name="agent-workflow")),
)


if __name__ == "__main__":
    runner = AgentRunner()
    try:
        runner.serve(
            triage_agent, port=8001
        )  # HTTP + workflow runtime; blocks on uvicorn
    finally:
        runner.shutdown(triage_agent)
