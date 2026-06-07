# Tools and MCP

Two ways to give an agent capabilities: native **function tools** (`@tool`) and external
**MCP tools** (`MCPClient`). Both end up as `AgentTool` objects in `tools=[...]`.

## Function tools — the `@tool` decorator

```python
from dapr_agents import tool

@tool
def get_customer_info(customer_name: str) -> str:
    """Get customer account information by name."""   # docstring is REQUIRED
    ...
```

- Import: `from dapr_agents import tool`.
- Signature: `tool(func=None, *, args_model: Optional[Type[BaseModel]] = None) -> AgentTool`.
- **The docstring is mandatory** — `ToolHelper.check_docstring` raises `ToolError` without one.
  The docstring becomes the tool's `description` shown to the LLM.
- **Schema is inferred from type hints** when `args_model` is omitted: every parameter becomes
  a required field unless it has a default. Async and sync functions both work.
- Attach by passing to the agent: `DurableAgent(..., tools=[get_customer_info])`.

Explicit Pydantic schema (optional — overrides inference):
```python
from pydantic import BaseModel, Field

class CloneArgs(BaseModel):
    repo_url: str = Field(description="HTTPS repository URL")
    dest: str = Field(description="Destination directory")

@tool(args_model=CloneArgs)
def git_clone(repo_url: str, dest: str) -> str:
    """Clone a git repository."""
    ...
```

### `AgentTool` (the underlying object)

A pydantic `BaseModel` with `name`, `description`, `args_model`, `func`, `source` (`"local"`,
`"mcp"`, …). `AgentTool.from_func(fn)` converts a plain callable; the agent's executor also
auto-wraps any bare callable you pass in `tools=[...]`. You rarely construct it directly —
`@tool` is the ergonomic path.

## MCP tools — `MCPClient`

Connect to external Model Context Protocol servers and surface their tools to the agent.
MCP support is **GA in v1.0.3**.

```python
from dapr_agents.tool.mcp import MCPClient

client = MCPClient()                      # optional: persistent_connections=True, allowed_tools={"get_weather"}
await client.connect_stdio(server_name="local", command=sys.executable, args=["mcp_tools.py"])
tools = client.get_all_tools()            # -> List[AgentTool]
agent = DurableAgent(..., tools=tools)
```

### Transports (four)

| method | for |
|---|---|
| `connect_stdio(server_name, command, args=None, env=None, cwd=None)` | subprocess MCP servers |
| `connect_sse(server_name, url, headers=None, timeout=None, sse_read_timeout=None)` | Server-Sent Events |
| `connect_streamable_http(server_name, url, headers=None, timeout=None, terminate_on_close=None)` | streamable HTTP |
| `connect_many(server_configs: list)` | many servers at once (each dict has `server_name` + `transport` + transport args) |

All are async. `get_all_tools() -> List[AgentTool]` returns tools from every connected server,
each **name-prefixed by its `server_name`** (e.g. `local_get_weather`) to avoid collisions.

`MCPClient` is an async context manager — use `async with MCPClient() as client:` or call
`await client.close()` when done. `allowed_tools={...}` loads only the named tools.

### Defining your own MCP server

MCP servers use the **external `mcp` package** (not dapr-agents):
```python
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("WeatherServer")

@mcp.tool()
async def get_weather(location: str) -> str:
    """Get weather information for a specific location."""
    ...

if __name__ == "__main__":
    mcp.run("stdio")     # or "sse" / "streamable-http"
```

See `assets/templates/mcp-agent/` for the full client+server pair.

## End-to-end (MCP → agent)

```python
async def load_tools():
    client = MCPClient()
    await client.connect_stdio(server_name="local", command=sys.executable, args=["mcp_tools.py"])
    return client.get_all_tools()

tools = asyncio.run(load_tools())
agent = DurableAgent(name="WeatherAgent", role="...", llm=OpenAIChatClient(), tools=tools, ...)
AgentRunner().serve(agent, port=8001)
```

## Sources (verified against upstream, 2026-06)

- `dapr/dapr-agents` main: `tool/base.py` (`tool`, `AgentTool`), `tool/utils/tool.py`
  (`ToolHelper.infer_func_schema`, `check_docstring`), `tool/executor.py`,
  `tool/mcp/{__init__,client,transport}.py`, `quickstarts/mcp_tools.py`,
  `examples/06-agent-mcp-client-stdio/agent.py`.
