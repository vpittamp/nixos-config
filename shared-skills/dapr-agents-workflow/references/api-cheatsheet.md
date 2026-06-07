# Dapr Agents + Workflow — import & signature cheat-sheet

Quick lookup. All verified against `dapr/dapr-agents` main (GA **v1.0.3**, 2026-05-19) and
`dapr-ext-workflow` **1.17.x**. Re-verify before pinning long-term — these move fast.

## Versions

| package | version | install |
|---|---|---|
| `dapr-agents` | 1.0.3 (GA) | `uv add dapr-agents` / `pip install dapr-agents>=1.0.3` |
| `dapr-ext-workflow` | 1.17.x (stable; `-dev` = pre-release, avoid) | `pip install dapr-ext-workflow` |
| Dapr runtime / CLI | 1.17.x | `dapr init` (provides Redis + components dir) |

## Imports (the ones you actually use)

```python
# Workflow engine
import dapr.ext.workflow as wf
# wf.WorkflowRuntime, wf.DaprWorkflowClient, wf.DaprWorkflowContext,
# wf.WorkflowActivityContext, wf.RetryPolicy, wf.when_all, wf.when_any

# Agents (top-level)
from dapr_agents import DurableAgent, AgentRunner, tool, AgentTool
from dapr_agents.llm import OpenAIChatClient, DaprChatClient   # + HFHubChatClient, MistralChatClient, NVIDIAChatClient
from dapr_agents.memory import ConversationDaprStateMemory

# Config objects
from dapr_agents.agents.configs import (
    AgentMemoryConfig, AgentStateConfig, AgentExecutionConfig,
    AgentPubSubConfig, AgentRegistryConfig, OrchestrationMode,
)
from dapr_agents.storage.daprstores.stateservice import StateStoreService

# Workflow<->agent glue + lifecycle helper
from dapr_agents.workflow.utils.core import call_agent, trigger_agent, wait_for_shutdown

# MCP
from dapr_agents.tool.mcp import MCPClient
```

## Signatures

```python
# --- workflow authoring ---
@wfr.workflow(name=None)                      # wfr = wf.WorkflowRuntime()
@wfr.activity(name=None)
yield ctx.call_activity(fn, input=...)
yield ctx.call_child_workflow(wf_fn, input=..., instance_id=..., retry_policy=...)
ctx.wait_for_external_event(name) -> Task
ctx.create_timer(timedelta) -> Task
yield wf.when_all([...]) ; yield wf.when_any([...])
ctx.current_utc_datetime ; ctx.instance_id ; ctx.is_replaying

# --- workflow client ---
client.schedule_new_workflow(workflow, input=None, instance_id=None) -> str
client.wait_for_workflow_start(instance_id, timeout_in_seconds=...) -> state
client.wait_for_workflow_completion(instance_id, timeout_in_seconds=...) -> state
client.raise_workflow_event(instance_id, event_name, data=...)
client.terminate_workflow(id) ; client.purge_workflow(id)   # purge needs terminal state

# --- agent ---
DurableAgent(*, name, role, goal, instructions, llm=None, tools=None,
             memory=None, state=None, pubsub=None, registry=None, execution=None, ...)
AgentRunner().serve(agent, *, port=8001, app=None, host="0.0.0.0",
                    entry_path="/agent/run", delivery_mode="sync") -> FastAPI
AgentRunner().subscribe(agent)        # pub/sub worker; then await wait_for_shutdown()
AgentRunner().workflow(agent)         # pure workflow target; then await wait_for_shutdown()
AgentRunner().shutdown(agent)
# NOTE: DurableAgent has NO .start() — AgentRunner owns the lifecycle.

# --- workflow-orchestrated agents (Pattern A) ---
yield call_agent(ctx, name, input, *, app_id=None, instance_id=None)   # in a workflow
# -> returns a DICT (agent's final message): {"role","content","name"}; read .get("content")
trigger_agent(name, input, *, app_id=None, timeout_in_seconds=120)     # outside a workflow

# --- orchestration modes (Pattern B) ---
AgentExecutionConfig(max_iterations=10, tool_choice="auto", orchestration_mode=None)
# max_iterations = TOTAL turns (one member/turn), not rounds: N members x R rounds = N*R
OrchestrationMode.ROUNDROBIN | OrchestrationMode.RANDOM | OrchestrationMode.AGENT

# --- triggering an HTTP-served agent / orchestrator ---
# POST {serve port}/agent/run   body: {"task": "<prompt>"}   -> {"instance_id", "status_url"}

# --- tools ---
tool(func=None, *, args_model=None) -> AgentTool            # @tool ; docstring REQUIRED

# --- MCP ---
MCPClient(persistent_connections=False, allowed_tools=None)
await client.connect_stdio(server_name, command, args=None, env=None, cwd=None)
await client.connect_sse(server_name, url, headers=None, ...)
await client.connect_streamable_http(server_name, url, headers=None, ...)
client.get_all_tools() -> list[AgentTool]
```

## GA / ALPHA status

| surface | status |
|---|---|
| Dapr Workflow, DurableAgent, AgentRunner, orchestration modes, tools, MCP | **GA** (v1.0.3) |
| Dapr **Conversation API** (`conversation.*` component, `DaprChatClient`) | **ALPHA** — prefer provider-direct clients in prod |
| `dapr-ext-workflow-dev` package | pre-release — do not use for stable work |

## Removed / does-not-exist (do not generate these)

- ❌ `RoundRobinOrchestrator` / `RandomOrchestrator` / `LLMOrchestrator` classes — removed in
  v1.0.3. Use `OrchestrationMode` on a `DurableAgent` instead.
- ❌ `DurableAgent.start()` — no such method. Use `AgentRunner`.
- ❌ `Agent` class for new code — deprecated since v1.0.0-rc.1. Use `DurableAgent`.
