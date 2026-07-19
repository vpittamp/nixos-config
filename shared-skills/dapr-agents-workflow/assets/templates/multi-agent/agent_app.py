"""Pattern B — a single team-member agent (one process per member).

The same file boots any team member; AGENT_NAME selects the identity. Each member
subscribes to its own request topic and the shared broadcast topic, and joins the
team via the shared team_name in the registry. Pub/sub workers use subscribe()
(no HTTP entrypoint) and stay alive with wait_for_shutdown().
"""

import asyncio
import os

from dapr_agents import DurableAgent, AgentRunner
from dapr_agents.llm import OpenAIChatClient
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.agents.configs import (
    AgentMemoryConfig,
    AgentPubSubConfig,
    AgentRegistryConfig,
    AgentStateConfig,
)
from dapr_agents.storage.daprstores.stateservice import StateStoreService
from dapr_agents.workflow.utils.core import wait_for_shutdown


name = os.environ["AGENT_NAME"]  # e.g. "frodo"
role = os.environ.get("AGENT_ROLE", name.title())

agent = DurableAgent(
    name=name,
    role=role,
    goal=os.environ.get("AGENT_GOAL", "Collaborate with the team to solve the task."),
    instructions=[
        os.environ.get("AGENT_INSTRUCTIONS", "Answer in character, concisely.")
    ],
    llm=OpenAIChatClient(),
    # Members keep conversation memory (the upstream example does); orchestrators usually don't.
    memory=AgentMemoryConfig(
        store=ConversationDaprStateMemory(store_name="agent-memory")
    ),
    pubsub=AgentPubSubConfig(
        pubsub_name="agent-pubsub",
        agent_topic=f"fellowship.{name}.requests",  # this member's direct topic
        broadcast_topic="fellowship.broadcast",  # shared team channel
    ),
    state=AgentStateConfig(
        store=StateStoreService(
            store_name="agent-workflow", key_prefix=f"fellowship.{name}:"
        ),
    ),
    registry=AgentRegistryConfig(
        store=StateStoreService(store_name="agentregistrystore"),
        team_name="fellowship",  # MUST match the orchestrator's team_name
    ),
)


async def main():
    runner = AgentRunner()
    try:
        runner.subscribe(agent)  # wire pub/sub handlers (no HTTP server)
        await wait_for_shutdown()  # keep the process alive
    finally:
        runner.shutdown(agent)


if __name__ == "__main__":
    asyncio.run(main())
