"""A standalone MCP server exposing tools over stdio.

This uses the EXTERNAL `mcp` package (Model Context Protocol SDK), not dapr-agents.
The agent (mcp_agent.py) spawns this file as a subprocess and imports its tools.
"""

import random

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("WeatherServer")


@mcp.tool()
async def get_weather(location: str) -> str:
    """Get weather information for a specific location."""
    return f"{location}: {random.randint(60, 80)}F."


@mcp.tool()
async def get_forecast(location: str, days: int = 3) -> str:
    """Get a multi-day weather forecast for a location."""
    return f"{location}: {days}-day outlook — mild, occasional clouds."


if __name__ == "__main__":
    mcp.run("stdio")  # transport: "stdio" (also "sse" / "streamable-http")
