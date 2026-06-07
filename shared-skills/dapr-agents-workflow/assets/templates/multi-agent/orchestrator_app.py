"""Pattern B — Autonomous multi-agent orchestration.

A DurableAgent acts as the orchestrator. It does NOT call agents explicitly; instead
it sets an orchestration MODE and coordinates a team over pub/sub. Team members are
discovered through a shared registry (team_name), and the orchestrator drives turns.

Modes (dapr_agents.agents.configs.OrchestrationMode):
  - ROUNDROBIN : cycle through team members in a fixed order
  - RANDOM     : pick a member at random, avoiding the immediate previous speaker
  - AGENT      : an LLM plans which member should act next (REQUIRES llm=...)

Run:  dapr run -f dapr.yaml
"""

from dapr_agents import DurableAgent, AgentRunner
from dapr_agents.llm import OpenAIChatClient  # noqa: F401  (needed only for AGENT mode)
from dapr_agents.agents.configs import (
    AgentExecutionConfig,
    AgentPubSubConfig,
    AgentRegistryConfig,
    AgentStateConfig,
    OrchestrationMode,
)
from dapr_agents.storage.daprstores.stateservice import StateStoreService


orchestrator = DurableAgent(
    name="FellowshipRoundRobin",
    # For AGENT (LLM-planned) mode, uncomment the next line:
    # llm=OpenAIChatClient(),
    pubsub=AgentPubSubConfig(
        pubsub_name="agent-pubsub",
        agent_topic="fellowship.orchestrator.requests",
        broadcast_topic="fellowship.broadcast",
    ),
    state=AgentStateConfig(
        store=StateStoreService(store_name="agent-workflow", key_prefix="fellowship:"),
    ),
    registry=AgentRegistryConfig(
        store=StateStoreService(store_name="agentregistrystore"),
        team_name="fellowship",  # team members share this exact name
    ),
    execution=AgentExecutionConfig(
        # max_iterations = TOTAL turns (one member dispatched per turn), NOT rounds.
        # For N members and R full rounds, set max_iterations = N * R (here 3 members x ... ).
        max_iterations=6,
        orchestration_mode=OrchestrationMode.ROUNDROBIN,  # or RANDOM / AGENT
    ),
    # The orchestrator excludes ITSELF (and any other orchestrator) from the round-robin
    # roster, so it is never scheduled as a debater — only the team members rotate.
)


if __name__ == "__main__":
    runner = AgentRunner()
    try:
        # HTTP entrypoint to kick off a team run. Trigger it with:
        #   curl -s -X POST http://localhost:8004/agent/run \
        #        -H 'content-type: application/json' -d '{"task": "<the prompt/topic>"}'
        # The response carries an instance_id + status_url; the orchestrator reads message["task"].
        runner.serve(orchestrator, port=8004)
    finally:
        runner.shutdown(orchestrator)
