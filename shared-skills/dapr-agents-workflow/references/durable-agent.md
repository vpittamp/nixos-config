# DurableAgent — anatomy, components, serving

`dapr-agents` GA **v1.0.3** (`uv add dapr-agents` or `pip install dapr-agents>=1.0.3`).
Built ON Dapr Workflow: every agent turn/tool call is checkpointed, so an agent survives
process restarts and resumes deterministically.

## Agent vs DurableAgent

The stateless `Agent` class is **deprecated since v1.0.0-rc.1** and will be removed.
**Use `DurableAgent` for everything.** It adds workflow-backed execution, persistent state
across sessions/failures, automatic retry/recovery, and deterministic checkpointing.

## Constructor (keyword-only)

```python
from dapr_agents import DurableAgent
```

`DurableAgent.__init__` is keyword-only. The commonly-used parameters:

| param | type | notes |
|---|---|---|
| `name` | `str` | the agent's identity; also the key for `call_agent(ctx, name, ...)` |
| `role` | `str` | short persona, e.g. "Weather Assistant" |
| `goal` | `str` | one-line objective |
| `instructions` | `Iterable[str]` | system guidance lines |
| `llm` | `ChatClientBase` | a chat client (see below). Optional for ROUNDROBIN/RANDOM orchestrators |
| `tools` | `Optional[Iterable[Any]]` | `@tool` fns, `AgentTool`s, plain callables, or **other DurableAgents** (peer delegation) |
| `memory` | `AgentMemoryConfig` | conversation history store |
| `state` | `AgentStateConfig` | durable workflow/actor state store |
| `pubsub` | `AgentPubSubConfig` | only for autonomous multi-agent (Pattern B) |
| `registry` | `AgentRegistryConfig` | only for autonomous multi-agent (Pattern B) |
| `execution` | `AgentExecutionConfig` | max_iterations, tool_choice, orchestration_mode |

(Also accepts `profile, system_prompt, prompt_template, style_guidelines, executor,
retry_policy, hooks, configuration, agent_metadata, …` — rarely needed.)

> Passing a `DurableAgent` inside `tools=[...]` is special-cased: it becomes a callable
> **sub-agent** (peer delegation), not a function tool.

## Config objects and their import paths

```python
from dapr_agents.agents.configs import (
    AgentMemoryConfig, AgentStateConfig, AgentExecutionConfig,
    AgentPubSubConfig, AgentRegistryConfig, OrchestrationMode,
)
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.storage.daprstores.stateservice import StateStoreService
```

```python
memory = AgentMemoryConfig(store=ConversationDaprStateMemory(store_name="agent-memory"))
state  = AgentStateConfig(store=StateStoreService(store_name="agent-workflow"))
```

`AgentExecutionConfig` (dataclass) defaults: `max_iterations=10`, `tool_choice="auto"`,
`tool_execution_mode=ToolExecutionMode.PARALLEL`, `orchestration_mode=None`.

## LLM clients

```python
from dapr_agents.llm import OpenAIChatClient, DaprChatClient   # also HFHubChatClient, MistralChatClient, NVIDIAChatClient
```

Two ways to reach a model:

1. **Provider-direct (GA, recommended):** `llm=OpenAIChatClient()` (reads `OPENAI_API_KEY`).
   No Dapr component needed.
2. **Via the Dapr Conversation API (ALPHA):** `llm=DaprChatClient(component_name="llm-provider")`,
   backed by a `conversation.*` component (see `assets/components/llm-provider.yaml`). The
   Conversation building block is still **ALPHA** — fine for local/dev, prefer provider-direct
   for production until it GAs.

## Components for ONE DurableAgent

| component file | type | needed when | special |
|---|---|---|---|
| `agent-workflow.yaml` | `state.redis` | **always** — durable workflow state | **`actorStateStore: "true"`** |
| `agent-memory.yaml` | `state.redis` | the agent sets `memory=` (recommended for chat agents; optional — `memory` defaults to `None`) | — |
| `llm-provider.yaml` | `conversation.openai` | the agent uses `DaprChatClient` (skip if provider-direct) | ALPHA building block |

Only `agent-workflow.yaml` is unconditionally required. Autonomous multi-agent (Pattern B)
adds `agent-pubsub.yaml` (`pubsub.redis`) and `agentregistrystore.yaml` (`state.redis`). See
`references/multi-agent-orchestration.md`.

## Serving an agent — `AgentRunner` (the lifecycle owner)

`DurableAgent` has **no `.start()` method**. The runtime is owned by `AgentRunner`.

```python
from dapr_agents import AgentRunner           # = dapr_agents.workflow.runners.AgentRunner
runner = AgentRunner()
```

Three serving idioms — pick by how the agent is triggered:

| method | use when | keeps process alive how |
|---|---|---|
| `runner.serve(agent, port=8001)` | HTTP entrypoint (POST `/agent/run`); also registers the workflow runtime so it is callable by `call_agent` | blocks on uvicorn |
| `runner.subscribe(agent)` | pub/sub worker (autonomous multi-agent member) — no HTTP | `await wait_for_shutdown()` |
| `runner.workflow(agent)` | pure workflow target, no HTTP/pub-sub | `await wait_for_shutdown()` |

`wait_for_shutdown` is imported from `dapr_agents.workflow.utils.core`. Always pair serving
with `finally: runner.shutdown(agent)`.

`serve()` signature (keyword-only after the agent):
```python
serve(agent, *, app=None, host="0.0.0.0", port=8001, expose_entry=True,
      entry_path="/agent/run", status_path="/agent/instances/{instance_id}",
      workflow_component="dapr", delivery_mode="sync", queue_maxsize=1024) -> FastAPI
```
Pass your own `app=FastAPI()` to mount the agent into an existing app (then you run uvicorn).

**Triggering a served agent:** `POST {port}/agent/run` with body `{"task": "<prompt>"}` →
`{"instance_id": ..., "status_url": ...}`. The agent reads `message["task"]`. Poll the
status at `GET {port}/agent/instances/{instance_id}`.

## Addressability: `name` vs `app_id`

These are **two different identifiers** and confusing them is the top integration bug:

- **agent `name`** (`DurableAgent(name="triage_agent")`) → the workflow name used by
  `call_agent(ctx, "triage_agent", ...)`.
- **Dapr `appID`** (in `dapr.yaml`, e.g. `triage-agent`) → the routing address passed as
  `call_agent(..., app_id="triage-agent")`.

## Sources (verified against upstream, 2026-06)

- docs.dapr.io › Dapr Agents (core-concepts, getting-started)
- `dapr/dapr-agents` main: `agents/durable.py`, `agents/configs.py`, `workflow/runners/agent.py`,
  `quickstarts/{02,03,04,06}_*`, `quickstarts/resources/*.yaml`
