#!/usr/bin/env python3
"""Minimal MCP server that exposes i3pm desktop actions through the daemon."""

from __future__ import annotations

import json
import os
import socket
import sys
from typing import Any, Dict, Optional


SERVER_NAME = "i3pm-desktop"
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSION = "2024-11-05"


class DaemonRpcClient:
    def __init__(self, socket_path: Optional[str] = None) -> None:
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        self.socket_path = socket_path or f"{runtime_dir}/i3-project-daemon/ipc.sock"
        self._request_id = 0

    def request(self, method: str, params: Optional[Dict[str, Any]] = None) -> Any:
        self._request_id += 1
        payload = {
            "jsonrpc": "2.0",
            "id": self._request_id,
            "method": method,
            "params": params or {},
        }
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.connect(self.socket_path)
            conn.sendall((json.dumps(payload) + "\n").encode("utf-8"))
            buffer = b""
            while b"\n" not in buffer:
                chunk = conn.recv(65536)
                if not chunk:
                    raise RuntimeError("Daemon closed connection before responding")
                buffer += chunk
        raw_line = buffer.split(b"\n", 1)[0].decode("utf-8")
        response = json.loads(raw_line)
        if "error" in response:
            error = response["error"] or {}
            raise RuntimeError(str(error.get("message") or "daemon request failed"))
        return response.get("result")


def _tool(name: str, description: str, properties: Dict[str, Any], required: Optional[list[str]] = None) -> Dict[str, Any]:
    return {
        "name": name,
        "description": description,
        "inputSchema": {
            "type": "object",
            "properties": properties,
            "required": required or [],
            "additionalProperties": False,
        },
    }


TOOLS = [
    _tool(
        "get_desktop_context",
        "Return the live i3pm desktop context for the current worktree, focused window, workspace, scratchpad, and AI sessions.",
        {
            "include_processes": {"type": "boolean", "description": "Include a small top-process list."},
            "process_limit": {"type": "integer", "description": "Maximum number of processes to include.", "minimum": 1, "maximum": 20},
        },
    ),
    _tool(
        "list_windows",
        "List visible windows for the active context. Use query to filter by app name, title, workspace, or project.",
        {
            "query": {"type": "string", "description": "Optional fuzzy window filter."},
            "current_context_only": {"type": "boolean", "description": "Limit matching to the active i3pm context.", "default": True},
        },
    ),
    _tool(
        "list_processes",
        "List top running processes on this host.",
        {
            "limit": {"type": "integer", "description": "Maximum number of processes to include.", "minimum": 1, "maximum": 20},
        },
    ),
    _tool(
        "focus_window",
        "Focus a window by fuzzy query or exact window id. Safe to run automatically.",
        {
            "query": {"type": "string", "description": "Window title, app, workspace, or project query."},
            "window_id": {"type": "integer", "description": "Exact window id, if known."},
            "current_context_only": {"type": "boolean", "description": "Limit matching to the active i3pm context.", "default": True},
        },
    ),
    _tool(
        "focus_workspace",
        "Switch to a Sway workspace by number or name.",
        {
            "workspace": {"type": "string", "description": "Workspace number or name."},
        },
        ["workspace"],
    ),
    _tool(
        "switch_context",
        "Switch the active i3pm worktree context.",
        {
            "qualified_name": {"type": "string", "description": "Qualified worktree name like account/repo:branch."},
            "target_variant": {"type": "string", "enum": ["local", "ssh"], "description": "Optional execution mode override."},
        },
        ["qualified_name"],
    ),
    _tool(
        "toggle_scratchpad",
        "Toggle the project scratchpad terminal for the current or specified context.",
        {
            "qualified_name": {"type": "string", "description": "Optional qualified worktree name."},
            "context_key": {"type": "string", "description": "Optional explicit context key."},
        },
    ),
    _tool(
        "launch_app",
        "Launch or focus an application from the i3pm app registry.",
        {
            "app_name": {"type": "string", "description": "Registry app name or fuzzy app query."},
            "qualified_name": {"type": "string", "description": "Optional worktree target for scoped apps."},
            "target_variant": {"type": "string", "enum": ["local", "ssh"], "description": "Optional execution mode override."},
        },
        ["app_name"],
    ),
    _tool(
        "cycle_display_layout",
        "Cycle to the next configured display layout.",
        {},
    ),
    _tool(
        "close_window",
        "Close a window by fuzzy query or exact id. This is destructive and requires confirm=true.",
        {
            "query": {"type": "string", "description": "Window title, app, workspace, or project query."},
            "window_id": {"type": "integer", "description": "Exact window id, if known."},
            "current_context_only": {"type": "boolean", "description": "Limit matching to the active i3pm context.", "default": True},
            "confirm": {"type": "boolean", "description": "Must be true to actually close the window."},
        },
    ),
]


def summarize_result(tool_name: str, result: Dict[str, Any]) -> str:
    if tool_name == "get_desktop_context":
        runtime = result.get("runtime") or {}
        context = result.get("active_context") or {}
        focused = result.get("focused_window") or {}
        workspace = result.get("workspace") or {}
        return (
            f"Context: {context.get('qualified_name') or 'global'} | "
            f"Focused window: {focused.get('title') or focused.get('app_name') or 'none'} | "
            f"Workspace: {workspace.get('current_workspace') or 'unknown'} | "
            f"Visible windows: {runtime.get('visible_window_count') or result.get('visible_window_count') or 0}"
        )

    if result.get("result_summary"):
        return str(result["result_summary"])

    action_result = result.get("action_result")
    if isinstance(action_result, dict):
        for key in ("message", "status", "error"):
            value = action_result.get(key)
            if value:
                return str(value)
    return f"{tool_name} completed"


def build_tool_result(tool_name: str, result: Dict[str, Any], *, is_error: bool = False) -> Dict[str, Any]:
    return {
        "content": [
            {
                "type": "text",
                "text": summarize_result(tool_name, result),
            }
        ],
        "structuredContent": result,
        "isError": is_error,
    }


def dispatch_tool(client: DaemonRpcClient, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    if name == "get_desktop_context":
        result = client.request("assistant.desktop.snapshot", arguments)
        return build_tool_result(name, result)

    if name == "list_windows":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "list_windows",
            **arguments,
        })
        return build_tool_result(name, result)

    if name == "list_processes":
        limit = arguments.get("limit")
        result = client.request("assistant.desktop.execute", {
            "action_kind": "list_processes",
            "process_limit": limit,
        })
        return build_tool_result(name, result)

    if name == "focus_window":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "focus_window",
            **arguments,
        })
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "focus_workspace":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "focus_workspace",
            **arguments,
        })
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "switch_context":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "switch_context",
            **arguments,
        })
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "toggle_scratchpad":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "toggle_scratchpad",
            **arguments,
        })
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "launch_app":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "launch_app",
            **arguments,
        })
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "cycle_display_layout":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "cycle_display_layout",
        })
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "close_window":
        result = client.request("assistant.desktop.execute", {
            "action_kind": "close_window",
            **arguments,
        })
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    raise RuntimeError(f"Unknown tool: {name}")


def send_response(response: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()


def handle_request(client: DaemonRpcClient, request: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    method = request.get("method")
    request_id = request.get("id")
    params = request.get("params") if isinstance(request.get("params"), dict) else {}

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        }

    if method == "notifications/initialized":
        return None

    if method == "ping":
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {},
        }

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {"tools": TOOLS},
        }

    if method == "tools/call":
        tool_name = str(params.get("name") or "").strip()
        arguments = params.get("arguments") if isinstance(params.get("arguments"), dict) else {}
        result = dispatch_tool(client, tool_name, arguments)
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": result,
        }

    if method == "resources/list":
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {"resources": []},
        }

    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def main() -> int:
    client = DaemonRpcClient()
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            response = handle_request(client, request)
            if response is not None:
                send_response(response)
        except Exception as error:
            request_id = None
            try:
                request_id = request.get("id")  # type: ignore[name-defined]
            except Exception:
                request_id = None
            send_response({
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {
                    "code": -32000,
                    "message": str(error),
                },
            })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
