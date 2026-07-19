"""A single DurableAgent with one function tool, served over HTTP.

The simplest complete agent. Use it as the building block for both multi-agent
patterns. Run:  dapr run -f dapr.yaml   then POST to http://localhost:8001/agent/run
"""

from dapr_agents import DurableAgent, AgentRunner, tool
from dapr_agents.llm import OpenAIChatClient
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.agents.configs import AgentMemoryConfig, AgentStateConfig
from dapr_agents.storage.daprstores.stateservice import StateStoreService


@tool
def get_weather(location: str) -> str:
    """Get the current weather for a location."""  # docstring REQUIRED for @tool
    return f"{location}: 72F, sunny."


weather_agent = DurableAgent(
    name="WeatherAgent",
    role="Weather Assistant",
    goal="Answer weather questions using the get_weather tool.",
    instructions=["Use get_weather to answer, then reply in one sentence."],
    llm=OpenAIChatClient(),
    tools=[get_weather],
    memory=AgentMemoryConfig(
        store=ConversationDaprStateMemory(store_name="agent-memory")
    ),
    state=AgentStateConfig(store=StateStoreService(store_name="agent-workflow")),
)


if __name__ == "__main__":
    runner = AgentRunner()
    try:
        # Trigger a run:
        #   curl -s -X POST http://localhost:8001/agent/run \
        #        -H 'content-type: application/json' -d '{"task": "weather in Paris?"}'
        runner.serve(weather_agent, port=8001)
    finally:
        runner.shutdown(weather_agent)
