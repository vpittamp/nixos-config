# Multi-agent orchestration — the two approaches

Dapr Agents gives you **two distinct ways** to coordinate multiple agents. Choosing the
right one is the most important design decision. They are not interchangeable.

|                           | **Pattern A — Workflow-orchestrated**                                 | **Pattern B — Autonomous (agent-to-agent)**                  |
| ------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------ |
| Who decides the next step | a deterministic Dapr Workflow you write                               | the framework, by orchestration mode + the agents themselves |
| Control flow              | explicit (`call_agent`, `when_all`, `wait_for_external_event`)        | implicit (round-robin / random / LLM-planned turns)          |
| Transport between agents  | child-workflow calls (`call_agent` → `call_child_workflow`)           | **pub/sub** topics + a shared registry                       |
| Components                | state stores only (no pub/sub)                                        | adds `pubsub.redis` + a registry state store                 |
| Best for                  | known DAGs, fan-out/fan-in, human approval gates, auditable pipelines | open-ended collaboration, debate, emergent task routing      |
| Canonical example         | quickstart `06_workflow_agents`                                       | `examples/04-multi-agent-workflows` ("The Fellowship")       |

---

## Pattern A — Workflow-orchestrated agents

A plain `WorkflowRuntime` workflow (see `references/workflow-primitives.md`) drives the run
and invokes agents as **durable child workflows**:

```python
import dapr.ext.workflow as wf
from dapr_agents.workflow.utils.core import call_agent

@wfr.workflow(name="support_workflow")
def support_workflow(ctx: wf.DaprWorkflowContext, request: dict):
    triage = yield call_agent(ctx, "triage_agent", input=request, app_id="triage-agent")
    rec    = yield call_agent(ctx, "expert_agent", input={"triage": triage}, app_id="expert-agent")
    return rec
```

`call_agent(ctx, name, input, *, app_id=None, instance_id=None, framework=None, registry=None)`
— **must be `yield`ed**; it wraps `ctx.call_child_workflow(agent_workflow_id(name), input, app_id=app_id)`.
Each call is durable and retriable. Combine with `wf.when_all([...])` to run agents in parallel,
and `ctx.wait_for_external_event(...)` for a human approval gate between agent steps.

> **`call_agent` returns a DICT, not a string** — the agent's final assistant message,
> shape `{"role": "assistant", "content": "...", "name": ...}`. Read `result.get("content")`
> for the text. If you need structured fields out of an agent, have that agent emit structured
> output rather than parsing prose from `content`.

Outside a workflow (e.g. an HTTP handler or a script), use the synchronous helper:

```python
from dapr_agents.workflow.utils.core import trigger_agent
result = trigger_agent("WeatherAgent", input={...}, app_id="weather-agent", timeout_in_seconds=120)
```

The agents themselves are ordinary DurableAgents served with `runner.serve(agent, port=...)`
(or `runner.workflow(agent)`). No pub/sub, no registry. See the
`assets/templates/workflow-orchestrated/` template set.

---

## Pattern B — Autonomous multi-agent orchestration

> **Current 1.0.x API:** the old standalone classes `RoundRobinOrchestrator`,
> `RandomOrchestrator`, and `LLMOrchestrator` were **REMOVED**. There is no orchestrator
> class to instantiate. You configure an **orchestration MODE** on a `DurableAgent`.

```python
from dapr_agents.agents.configs import OrchestrationMode, AgentExecutionConfig
# OrchestrationMode.ROUNDROBIN | OrchestrationMode.RANDOM | OrchestrationMode.AGENT
```

| mode         | behavior                                                         | needs `llm=` on the orchestrator? |
| ------------ | ---------------------------------------------------------------- | --------------------------------- |
| `ROUNDROBIN` | cycle team members in a fixed (sorted) order                     | no                                |
| `RANDOM`     | pick a member at random, avoiding the immediate previous speaker | no                                |
| `AGENT`      | an LLM plans which member acts next (plan-based)                 | **yes**                           |

### Orchestrator agent

```python
orchestrator = DurableAgent(
    name="FellowshipRoundRobin",
    # llm=OpenAIChatClient(),                 # ONLY for AGENT mode
    pubsub=AgentPubSubConfig(
        pubsub_name="agent-pubsub",
        agent_topic="fellowship.orchestrator.requests",
        broadcast_topic="fellowship.broadcast",
    ),
    state=AgentStateConfig(store=StateStoreService(store_name="agent-workflow", key_prefix="fellowship:")),
    registry=AgentRegistryConfig(store=StateStoreService(store_name="agentregistrystore"), team_name="fellowship"),
    execution=AgentExecutionConfig(max_iterations=4, orchestration_mode=OrchestrationMode.ROUNDROBIN),
)
runner = AgentRunner(); runner.serve(orchestrator, port=8004)
```

### Team-member agents

Each member is a DurableAgent with the **same `team_name`**, its own request topic, and the
shared broadcast topic, served with `runner.subscribe(agent)`:

```python
agent = DurableAgent(
    name="frodo",
    role="Ring-bearer",
    llm=OpenAIChatClient(),
    pubsub=AgentPubSubConfig(pubsub_name="agent-pubsub",
                             agent_topic="fellowship.frodo.requests",
                             broadcast_topic="fellowship.broadcast"),
    state=AgentStateConfig(store=StateStoreService(store_name="agent-workflow", key_prefix="fellowship.frodo:")),
    registry=AgentRegistryConfig(store=StateStoreService(store_name="agentregistrystore"), team_name="fellowship"),
)
runner = AgentRunner(); runner.subscribe(agent); await wait_for_shutdown()
```

### Kicking off a run

Trigger the orchestrator over its HTTP entrypoint (from `serve()`):

```bash
curl -s -X POST http://localhost:8004/agent/run \
     -H 'content-type: application/json' -d '{"task": "Debate: is remote work better?"}'
# -> {"instance_id": "...", "status_url": "/agent/instances/..."}
```

The body field is **`task`** (the orchestrator reads `message["task"]`). The same
`POST /agent/run` + `{"task": ...}` contract triggers any HTTP-served agent.

### How coordination works (verified against the upstream example)

- **Discovery:** every agent that shares a `team_name` is registered in `agentregistrystore`;
  that is how the orchestrator builds its roster.
- **The orchestrator is NOT in its own roster.** Roster construction filters with
  `exclude_self=True, exclude_orchestrator=True`, so the orchestrator (and any other
  orchestrator on the team) is never scheduled as a member — only the worker agents rotate.
- **`max_iterations` = TOTAL turns, not rounds.** One member is dispatched per turn
  (`agent_index = (turn - 1) % len(members)`), and the loop runs `turn` from 1 to
  `max_iterations`. For **N** members and **R** full rounds, set `max_iterations = N * R`.
- **Turn-to-turn context is threaded by the orchestrator**, not via pub/sub: each member's
  `task` is built as `"Task: …\n\nPrevious response from <prev>:\n<content>\n\nContinue…"`.
  The `broadcast_topic` is a _separate_ channel used to share the final message with the whole
  team, not to hand off each turn.
- **Message flow:** two routes —
  1. _orchestrated_: client → orchestrator's topic → selection logic → a member's topic → member;
  2. _direct_: client → a member's topic → that member.
- **Topics:** members subscribe to `fellowship.<name>.requests` and the shared
  `fellowship.broadcast`.
- **Memory is optional.** In the upstream example, _members_ set
  `memory=AgentMemoryConfig(...)` but the _orchestrator_ does not (`memory` defaults to `None`).
  Ship `agent-memory.yaml` only if some agent actually sets `memory=`.

### Config object field notes (verified)

- `AgentPubSubConfig(pubsub_name: str, agent_topic: Optional[str]=None, broadcast_topic: Optional[str]=None)`
- `AgentRegistryConfig(store: StateStoreService, team_name: Optional[str]=None)`

See `assets/templates/multi-agent/` for the full runnable set.

## Sources (verified against upstream, 2026-06)

- `dapr/dapr-agents` main: `agents/configs.py` (`OrchestrationMode`, `AgentExecutionConfig`,
  `AgentPubSubConfig`, `AgentRegistryConfig`), `agents/orchestration/*` (internal strategies),
  `agents/orchestrators/__init__.py` (records the class removal),
  `examples/04-multi-agent-workflows/` (services + `dapr-roundrobin.yaml` / `dapr-random.yaml` / `dapr-agent.yaml`),
  `workflow/utils/core.py` (`call_agent`, `trigger_agent`).
