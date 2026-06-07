"""A DurableAgent whose tools come from an MCP server (stdio transport).

Flow: MCPClient() -> connect_* -> get_all_tools() -> DurableAgent(tools=...) -> serve().
MCP tools arrive as AgentTool objects with names prefixed by the server_name,
e.g. "local_get_weather". They behave exactly like @tool functions on the agent.
"""

import asyncio
import sys

from dapr_agents import DurableAgent, AgentRunner
from dapr_agents.llm import OpenAIChatClient
from dapr_agents.tool.mcp import MCPClient
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.agents.configs import AgentMemoryConfig, AgentStateConfig
from dapr_agents.storage.daprstores.stateservice import StateStoreService


async def load_mcp_tools() -> list:
    client = MCPClient()  # add allowed_tools={"get_weather"} to load only some
    await client.connect_stdio(
        server_name="local",
        command=sys.executable,
        args=["mcp_tools.py"],
    )
    # For a remote server instead:
    #   await client.connect_streamable_http(server_name="remote", url="http://host/mcp")
    #   await client.connect_sse(server_name="remote", url="http://host/sse")
    return client.get_all_tools()   # -> List[AgentTool]


def build_agent(tools: list) -> DurableAgent:
    return DurableAgent(
        name="WeatherAgent",
        role="Weather Assistant",
        goal="Answer weather questions using the available MCP tools.",
        instructions=["Use the tools to answer; reply in one sentence."],
        llm=OpenAIChatClient(),
        tools=tools,                       # MCP tools injected here
        memory=AgentMemoryConfig(store=ConversationDaprStateMemory(store_name="agent-memory")),
        state=AgentStateConfig(store=StateStoreService(store_name="agent-workflow")),
    )


if __name__ == "__main__":
    mcp_tools = asyncio.run(load_mcp_tools())
    agent = build_agent(mcp_tools)
    runner = AgentRunner()
    try:
        runner.serve(agent, port=8001)
    finally:
        runner.shutdown(agent)
