"""Expert agent — a reasoning DurableAgent (no tools) served as its own Dapr app.

Reached by the orchestrator via app-id "expert-agent" / agent name "expert_agent".
"""

from dapr_agents import DurableAgent, AgentRunner
from dapr_agents.llm import OpenAIChatClient
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.agents.configs import AgentMemoryConfig, AgentStateConfig
from dapr_agents.storage.daprstores.stateservice import StateStoreService


expert_agent = DurableAgent(
    name="expert_agent",  # MUST match call_agent(ctx, "expert_agent", ...)
    role="Support Resolution Expert",
    goal="Recommend a concrete next step given a triage summary and the request.",
    instructions=[
        "Read the triage summary and the customer's request.",
        "Return a single, actionable recommendation in plain language.",
    ],
    llm=OpenAIChatClient(),
    memory=AgentMemoryConfig(store=ConversationDaprStateMemory(store_name="agent-memory")),
    state=AgentStateConfig(store=StateStoreService(store_name="agent-workflow")),
)


if __name__ == "__main__":
    runner = AgentRunner()
    try:
        runner.serve(expert_agent, port=8002)
    finally:
        runner.shutdown(expert_agent)
