#!/usr/bin/env python3
"""Minimal MCP server that exposes i3pm desktop actions through the daemon."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
from difflib import SequenceMatcher
from typing import Any, Dict, List, Optional, Tuple


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
        "Return the live i3pm desktop context for the current worktree, focused window, workspace, scratchpad, and Herdr sessions.",
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


def _as_list(value: Any) -> List[Any]:
    return value if isinstance(value, list) else []


def _as_dict(value: Any) -> Dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _window_id(window: Dict[str, Any]) -> int:
    for key in ("window_id", "id", "con_id"):
        try:
            value = int(window.get(key) or 0)
        except (TypeError, ValueError):
            value = 0
        if value > 0:
            return value
    return 0


def _window_search_text(window: Dict[str, Any]) -> str:
    parts = [
        window.get("title"),
        window.get("app_name"),
        window.get("app_key"),
        window.get("window_class"),
        window.get("project"),
        window.get("workspace"),
        window.get("output"),
        window.get("context_key"),
    ]
    return " ".join(str(part or "").strip().lower() for part in parts if str(part or "").strip())


def _window_score(query: str, window: Dict[str, Any], active_context_key: str) -> float:
    normalized_query = str(query or "").strip().lower()
    if not normalized_query:
        return 0.0
    if normalized_query.isdigit() and _window_id(window) == int(normalized_query):
        return 1000.0

    score = 0.0
    for field_name, weight in (
        ("title", 180.0),
        ("app_name", 220.0),
        ("window_class", 200.0),
        ("workspace", 120.0),
        ("project", 120.0),
    ):
        field_value = str(window.get(field_name) or "").strip().lower()
        if not field_value:
            continue
        if field_value == normalized_query:
            score = max(score, 700.0 + weight)
        elif normalized_query in field_value:
            score = max(score, 520.0 + weight)
        else:
            score = max(score, SequenceMatcher(None, normalized_query, field_value).ratio() * weight)

    search_text = _window_search_text(window)
    if search_text and normalized_query in search_text:
        score = max(score, 480.0)
    elif search_text:
        score = max(score, SequenceMatcher(None, normalized_query, search_text).ratio() * 140.0)

    if active_context_key and str(window.get("context_key") or "").strip() == active_context_key:
        score += 90.0
    if bool(window.get("focused", False)):
        score += 30.0
    if bool(window.get("visible", False)):
        score += 20.0
    if bool(window.get("hidden", False)):
        score -= 40.0
    return score


def _active_context_key(snapshot: Dict[str, Any]) -> str:
    return str(_as_dict(snapshot.get("active_context")).get("context_key") or "").strip()


def _tracked_windows(snapshot: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [
        dict(item)
        for item in _as_list(snapshot.get("tracked_windows"))
        if isinstance(item, dict) and _window_id(item) > 0
    ]


def _visible_windows(snapshot: Dict[str, Any], *, current_context_only: bool = True) -> List[Dict[str, Any]]:
    active_context_key = _active_context_key(snapshot)
    windows = [
        window
        for window in _tracked_windows(snapshot)
        if bool(window.get("visible", False)) and not bool(window.get("hidden", False))
    ]
    if current_context_only and active_context_key:
        scoped = [
            window for window in windows
            if str(window.get("context_key") or "").strip() == active_context_key
        ]
        if scoped:
            return scoped
    return windows


def _focused_window(snapshot: Dict[str, Any]) -> Dict[str, Any]:
    focused_window_id = int(snapshot.get("focused_window_id") or 0)
    for window in _tracked_windows(snapshot):
        if _window_id(window) == focused_window_id or bool(window.get("focused", False)):
            return window
    visible = _visible_windows(snapshot, current_context_only=False)
    return visible[0] if visible else {}


def _workspace_summary(snapshot: Dict[str, Any], focused_window: Dict[str, Any]) -> Dict[str, Any]:
    current_workspace = str(focused_window.get("workspace") or "").strip()
    current_output = str(focused_window.get("output") or "").strip()
    workspace_count = 0
    for output in _as_list(snapshot.get("outputs")):
        if not isinstance(output, dict):
            continue
        workspaces = _as_list(output.get("workspaces"))
        workspace_count += len(workspaces)
        for workspace in workspaces:
            if not isinstance(workspace, dict) or not bool(workspace.get("focused", False)):
                continue
            if not current_output:
                current_output = str(output.get("name") or "").strip()
            if not current_workspace:
                current_workspace = str(workspace.get("name") or workspace.get("num") or "").strip()
    return {
        "current_workspace": current_workspace,
        "current_output": current_output,
        "workspace_count": workspace_count,
        "active_outputs": _as_list(snapshot.get("active_outputs")),
    }


def _build_desktop_context(snapshot: Dict[str, Any], *, include_processes: bool = False, process_limit: int = 8) -> Dict[str, Any]:
    focused = _focused_window(snapshot)
    visible = _visible_windows(snapshot)
    sessions = [
        dict(session)
        for session in _as_list(snapshot.get("sessions"))
        if isinstance(session, dict)
    ]
    workspace = _workspace_summary(snapshot, focused)
    return {
        "success": True,
        "active_context": _as_dict(snapshot.get("active_context")),
        "focused_window": focused,
        "visible_windows": visible,
        "visible_window_count": len(visible),
        "workspace": workspace,
        "scratchpad": _as_dict(snapshot.get("scratchpad")),
        "active_terminal": _as_dict(snapshot.get("active_terminal")),
        "sessions": sessions,
        "current_ai_session_key": str(snapshot.get("current_ai_session_key") or ""),
        "runtime": {
            "daemon_health": "ok",
            "tracked_window_count": len(_tracked_windows(snapshot)),
            "visible_window_count": len(visible),
            "workspace_count": int(workspace.get("workspace_count") or 0),
            "active_output_count": len(_as_list(workspace.get("active_outputs"))),
            "herdr_session_count": len(sessions),
            "launch_stats": _as_dict(snapshot.get("launch_stats")),
        },
        "top_processes": _processes(process_limit) if include_processes else [],
    }


def _resolve_window_target(snapshot: Dict[str, Any], arguments: Dict[str, Any]) -> Dict[str, Any]:
    window_id = int(arguments.get("window_id") or 0)
    query = str(arguments.get("query") or "").strip()
    current_context_only = bool(arguments.get("current_context_only", True))
    windows = _visible_windows(snapshot, current_context_only=current_context_only)
    if not windows and current_context_only:
        windows = _visible_windows(snapshot, current_context_only=False)

    if window_id > 0:
        for window in windows:
            if _window_id(window) == window_id:
                return {"matched": True, "ambiguous": False, "window": window, "candidates": [window]}
        return {"matched": False, "ambiguous": False, "window": None, "candidates": []}

    if not query:
        return {"matched": False, "ambiguous": False, "window": None, "candidates": []}

    active_context_key = _active_context_key(snapshot)
    ranked: List[Tuple[float, Dict[str, Any]]] = []
    for window in windows:
        score = _window_score(query, window, active_context_key)
        if score > 0:
            ranked.append((score, window))
    ranked.sort(key=lambda item: item[0], reverse=True)
    if not ranked:
        return {"matched": False, "ambiguous": False, "window": None, "candidates": []}

    top_score, top_window = ranked[0]
    ambiguous = False
    if len(ranked) > 1:
        ambiguous = top_score < 250.0 or abs(top_score - ranked[1][0]) < 55.0
    return {
        "matched": True,
        "ambiguous": ambiguous,
        "window": top_window,
        "candidates": [window for _score, window in ranked[:5]],
    }


def _window_focus_params(window: Dict[str, Any]) -> Dict[str, Any]:
    execution_mode = str(window.get("execution_mode") or "").strip().lower()
    connection_key = str(window.get("connection_key") or "").strip()
    target_variant = "ssh" if execution_mode == "ssh" else "local"
    return {
        "window_id": _window_id(window),
        "project_name": str(window.get("project") or ""),
        "target_variant": target_variant,
        "connection_key": connection_key,
    }


def _processes(limit: int = 8) -> List[Dict[str, Any]]:
    process_limit = max(1, min(int(limit or 8), 20))
    try:
        result = subprocess.run(
            ["ps", "-eo", "pid=,pcpu=,pmem=,comm=,args=", "--sort=-pcpu"],
            capture_output=True,
            text=True,
            timeout=2.0,
            check=True,
        )
    except Exception:
        return []

    rows: List[Dict[str, Any]] = []
    for line in result.stdout.splitlines():
        parts = str(line or "").strip().split(None, 4)
        if len(parts) < 5:
            continue
        try:
            rows.append({
                "pid": int(parts[0]),
                "cpu_percent": float(parts[1]),
                "memory_percent": float(parts[2]),
                "command": parts[3],
                "argv": parts[4],
            })
        except (TypeError, ValueError):
            continue
        if len(rows) >= process_limit:
            break
    return rows


def _app_score(query: str, app: Dict[str, Any]) -> float:
    normalized_query = str(query or "").strip().lower()
    if not normalized_query:
        return 0.0
    score = 0.0
    for key in ("name", "display_name", "expected_class", "description"):
        field = str(app.get(key) or "").strip().lower()
        if not field:
            continue
        if field == normalized_query:
            score = max(score, 700.0)
        elif normalized_query in field:
            score = max(score, 500.0)
        else:
            score = max(score, SequenceMatcher(None, normalized_query, field).ratio() * 140.0)
    return score


def _resolve_app_target(client: DaemonRpcClient, query: str) -> Dict[str, Any]:
    normalized_query = str(query or "").strip()
    if not normalized_query:
        return {"matched": False, "ambiguous": False, "app": None, "candidates": []}
    registry = _as_dict(client.request("daemon.apps", {}))
    apps = [
        dict(app)
        for app in _as_list(registry.get("applications"))
        if isinstance(app, dict)
    ]
    ranked = [(_app_score(normalized_query, app), app) for app in apps]
    ranked = [(score, app) for score, app in ranked if score > 0]
    ranked.sort(key=lambda item: item[0], reverse=True)
    if not ranked:
        return {"matched": False, "ambiguous": False, "app": None, "candidates": []}
    top_score, top_app = ranked[0]
    ambiguous = False
    if len(ranked) > 1:
        ambiguous = top_score < 200.0 or abs(top_score - ranked[1][0]) < 45.0
    return {
        "matched": True,
        "ambiguous": ambiguous,
        "app": top_app,
        "candidates": [app for _score, app in ranked[:5]],
    }


def _action_result(
    *,
    action_kind: str,
    success: bool,
    execution_status: str,
    result_summary: str,
    target_type: str = "",
    target_id: Any = "",
    target_label: str = "",
    resolution: Optional[Dict[str, Any]] = None,
    action_result: Optional[Dict[str, Any]] = None,
    snapshot: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "success": success,
        "action_kind": action_kind,
        "target_type": target_type,
        "target_id": target_id,
        "target_label": target_label,
        "execution_status": execution_status,
        "result_summary": result_summary,
        "resolution": resolution or {},
    }
    if action_result is not None:
        payload["action_result"] = action_result
    if snapshot is not None:
        payload["snapshot"] = snapshot
    return payload


def summarize_result(tool_name: str, result: Dict[str, Any]) -> str:
    if tool_name == "get_desktop_context":
        runtime = _as_dict(result.get("runtime"))
        context = _as_dict(result.get("active_context"))
        focused = _as_dict(result.get("focused_window"))
        workspace = _as_dict(result.get("workspace"))
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
        snapshot = _as_dict(client.request("runtime.snapshot", {}))
        result = _build_desktop_context(
            snapshot,
            include_processes=bool(arguments.get("include_processes", False)),
            process_limit=int(arguments.get("process_limit") or 8),
        )
        return build_tool_result(name, result)

    if name == "list_windows":
        snapshot = _as_dict(client.request("runtime.snapshot", {}))
        query = str(arguments.get("query") or "").strip().lower()
        windows = _visible_windows(
            snapshot,
            current_context_only=bool(arguments.get("current_context_only", True)),
        )
        if query:
            windows = [window for window in windows if query in _window_search_text(window)]
        result = _action_result(
            action_kind="list_windows",
            success=True,
            execution_status="executed",
            result_summary=f"Found {len(windows)} visible windows",
            target_type="window_list",
            target_label=f"{len(windows)} windows",
            resolution={"windows": windows},
        )
        return build_tool_result(name, result)

    if name == "list_processes":
        limit = arguments.get("limit")
        processes = _processes(int(limit or 8))
        result = _action_result(
            action_kind="list_processes",
            success=True,
            execution_status="executed",
            result_summary=f"Found {len(processes)} running processes",
            target_type="process_list",
            target_label=f"{len(processes)} processes",
            resolution={"processes": processes},
        )
        return build_tool_result(name, result)

    if name == "focus_window":
        snapshot = _as_dict(client.request("runtime.snapshot", {}))
        resolved = _resolve_window_target(snapshot, arguments)
        window = resolved.get("window") if isinstance(resolved.get("window"), dict) else None
        if not resolved.get("matched") or window is None:
            result = _action_result(
                action_kind="focus_window",
                success=False,
                execution_status="target_not_found",
                result_summary="No matching window found",
                target_type="window",
                resolution=resolved,
            )
        elif bool(resolved.get("ambiguous", False)):
            result = _action_result(
                action_kind="focus_window",
                success=False,
                execution_status="needs_disambiguation",
                result_summary="Window target is ambiguous",
                target_type="window",
                resolution=resolved,
            )
        else:
            action_result = _as_dict(client.request("window.focus_fast", _window_focus_params(window)))
            if (
                action_result.get("success") is False
                and action_result.get("fallback_method") == "window.focus"
            ):
                action_result = _as_dict(client.request("window.focus", _window_focus_params(window)))
            target_id = _window_id(window)
            target_label = str(window.get("title") or window.get("app_name") or f"window {target_id}")
            result = _action_result(
                action_kind="focus_window",
                success=bool(action_result.get("success", True)),
                execution_status="executed" if bool(action_result.get("success", True)) else "failed",
                result_summary=str(action_result.get("message") or f"Focused '{target_label}'"),
                target_type="window",
                target_id=target_id,
                target_label=target_label,
                resolution=resolved,
                action_result=action_result,
            )
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "focus_workspace":
        workspace = str(arguments.get("workspace") or "").strip()
        if not workspace:
            raise RuntimeError("workspace is required")
        action_result = _as_dict(client.request("workspace.focus_fast", {"workspace": workspace}))
        if action_result.get("success") is False:
            action_result = _as_dict(client.request("workspace.focus", {"workspace": workspace}))
        result = _action_result(
            action_kind="focus_workspace",
            success=bool(action_result.get("success", True)),
            execution_status="executed" if bool(action_result.get("success", True)) else "failed",
            result_summary=str(action_result.get("message") or f"Focused workspace {workspace}"),
            target_type="workspace",
            target_id=workspace,
            target_label=workspace,
            action_result=action_result,
        )
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "switch_context":
        qualified_name = str(arguments.get("qualified_name") or "").strip()
        if not qualified_name:
            raise RuntimeError("qualified_name is required")
        action_result = _as_dict(client.request("context.ensure", {
            "qualified_name": qualified_name,
            "target_variant": str(arguments.get("target_variant") or "").strip(),
        }))
        result = _action_result(
            action_kind="switch_context",
            success=bool(action_result.get("success", True)),
            execution_status="executed" if bool(action_result.get("success", True)) else "failed",
            result_summary=f"Switched to {qualified_name}" if bool(action_result.get("switched", False)) else f"Context already at {qualified_name}",
            target_type="context",
            target_id=qualified_name,
            target_label=qualified_name,
            action_result=action_result,
        )
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "toggle_scratchpad":
        action_result = _as_dict(client.request("scratchpad.toggle", {
            "context_key": str(arguments.get("context_key") or ""),
            "project_name": str(arguments.get("qualified_name") or arguments.get("project_name") or ""),
        }))
        result = _action_result(
            action_kind="toggle_scratchpad",
            success=bool(action_result.get("success", True)),
            execution_status="executed" if bool(action_result.get("success", True)) else "failed",
            result_summary=str(action_result.get("message") or action_result.get("state") or "Toggled scratchpad"),
            target_type="scratchpad",
            action_result=action_result,
        )
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "launch_app":
        app_query = str(arguments.get("app_name") or "").strip()
        resolved = _resolve_app_target(client, app_query)
        app = resolved.get("app") if isinstance(resolved.get("app"), dict) else None
        if not resolved.get("matched") or app is None:
            result = _action_result(
                action_kind="launch_app",
                success=False,
                execution_status="target_not_found",
                result_summary="No matching application found",
                target_type="application",
                resolution=resolved,
            )
        elif bool(resolved.get("ambiguous", False)):
            result = _action_result(
                action_kind="launch_app",
                success=False,
                execution_status="needs_disambiguation",
                result_summary="Application target is ambiguous",
                target_type="application",
                resolution=resolved,
            )
        else:
            app_name = str(app.get("name") or "").strip()
            action_result = _as_dict(client.request("launch.open", {
                "app_name": app_name,
                "qualified_name": str(arguments.get("qualified_name") or arguments.get("project_name") or ""),
                "target_variant": str(arguments.get("target_variant") or "").strip(),
            }))
            result = _action_result(
                action_kind="launch_app",
                success=bool(action_result.get("success", True)),
                execution_status="executed" if bool(action_result.get("success", True)) else "failed",
                result_summary=str(action_result.get("message") or action_result.get("status") or f"Launched {app_name}"),
                target_type="application",
                target_id=app_name,
                target_label=str(app.get("display_name") or app_name),
                resolution=resolved,
                action_result=action_result,
            )
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "cycle_display_layout":
        action_result = _as_dict(client.request("display.cycle", {}))
        result = _action_result(
            action_kind="cycle_display_layout",
            success=bool(action_result.get("success", True)),
            execution_status="executed" if bool(action_result.get("success", True)) else "failed",
            result_summary=str(action_result.get("message") or "Cycled display layout"),
            target_type="display_layout",
            target_label="next display layout",
            action_result=action_result,
        )
        return build_tool_result(name, result, is_error=not bool(result.get("success", False)))

    if name == "close_window":
        if not bool(arguments.get("confirm", False)):
            result = _action_result(
                action_kind="close_window",
                success=False,
                execution_status="approval_required",
                result_summary="Window close requires confirm=true.",
                target_type="window",
            )
            return build_tool_result(name, result, is_error=True)
        snapshot = _as_dict(client.request("runtime.snapshot", {}))
        resolved = _resolve_window_target(snapshot, arguments)
        window = resolved.get("window") if isinstance(resolved.get("window"), dict) else None
        if not resolved.get("matched") or window is None:
            result = _action_result(
                action_kind="close_window",
                success=False,
                execution_status="target_not_found",
                result_summary="No matching window found",
                target_type="window",
                resolution=resolved,
            )
        elif bool(resolved.get("ambiguous", False)):
            result = _action_result(
                action_kind="close_window",
                success=False,
                execution_status="needs_disambiguation",
                result_summary="Window target is ambiguous",
                target_type="window",
                resolution=resolved,
            )
        else:
            action_result = _as_dict(client.request("window.action", {
                "window_id": _window_id(window),
                "action": "kill",
                "project_name": str(window.get("project") or ""),
                "connection_key": str(window.get("connection_key") or ""),
            }))
            target_id = _window_id(window)
            target_label = str(window.get("title") or window.get("app_name") or f"window {target_id}")
            result = _action_result(
                action_kind="close_window",
                success=bool(action_result.get("success", True)),
                execution_status="executed" if bool(action_result.get("success", True)) else "failed",
                result_summary=str(action_result.get("message") or f"Closed '{target_label}'"),
                target_type="window",
                target_id=target_id,
                target_label=target_label,
                resolution=resolved,
                action_result=action_result,
            )
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
