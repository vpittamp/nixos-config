"""Monitoring Panel Publisher for event-driven panel state updates.

This module publishes window/project state to the Eww monitoring panel
widget via `eww update`, achieving <100ms update latency.

Version: 1.0.0 (2025-11-20)
Feature: 085-sway-monitoring-widget
"""

import asyncio
import json
import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Eww configuration directory (monitoring panel)
EWW_MONITORING_PANEL_DIR = Path.home() / ".config" / "eww-monitoring-panel"

# Eww variable name for panel state
PANEL_STATE_VAR = "panel_state"


async def _rpc_request(method: str, params: Optional[dict] = None, timeout: float = 2.0) -> dict:
    """Send a JSON-RPC request to the daemon user socket."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    socket_path = os.environ.get("I3PM_DAEMON_SOCKET", f"{runtime_dir}/i3-project-daemon/ipc.sock")
    request_id = int(time.time() * 1000)

    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
        "id": request_id,
    }

    reader: asyncio.StreamReader
    writer: asyncio.StreamWriter
    reader, writer = await asyncio.wait_for(
        asyncio.open_unix_connection(path=socket_path),
        timeout=timeout,
    )

    try:
        writer.write((json.dumps(payload) + "\n").encode("utf-8"))
        await asyncio.wait_for(writer.drain(), timeout=timeout)
        raw = await asyncio.wait_for(reader.readline(), timeout=timeout)
        if not raw:
            raise RuntimeError(f"Empty response from daemon for method '{method}'")

        response = json.loads(raw.decode("utf-8", errors="ignore"))
        if not isinstance(response, dict):
            raise RuntimeError(f"Malformed daemon response for method '{method}'")

        error = response.get("error")
        if isinstance(error, dict):
            message = error.get("message") or "unknown error"
            raise RuntimeError(f"RPC {method} failed: {message}")

        result = response.get("result")
        if isinstance(result, dict):
            return result
        raise RuntimeError(f"Unexpected RPC result type for method '{method}'")
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass


def update_panel_state(state_json: str, config_dir: Optional[Path] = None) -> bool:
    """Push monitoring panel state to Eww via CLI.

    Args:
        state_json: JSON string containing MonitoringPanelState
        config_dir: Optional Eww config directory

    Returns:
        True if update succeeded
    """
    eww_config = config_dir or EWW_MONITORING_PANEL_DIR

    try:
        result = subprocess.run(
            ["eww", "--config", str(eww_config), "update", f"{PANEL_STATE_VAR}={state_json}"],
            check=False,
            capture_output=True,
            timeout=2.0,
            text=True
        )

        if result.returncode != 0:
            logger.warning(f"Eww monitoring panel update failed (exit {result.returncode}): {result.stderr}")
            return False

        logger.debug(f"Updated Eww monitoring panel: {len(state_json)} bytes")
        return True

    except subprocess.TimeoutExpired:
        logger.warning(f"Eww monitoring panel update timeout after 2s")
        return False
    except FileNotFoundError:
        logger.error("eww command not found in PATH")
        return False
    except Exception as e:
        logger.error(f"Unexpected error updating Eww monitoring panel: {e}")
        return False


async def publish_monitoring_state(conn, config_dir: Optional[Path] = None) -> bool:
    """Query daemon for window tree and publish to monitoring panel.

    Reuses the same data transformation logic as the backend script,
    but pushes updates via event-driven mechanism instead of polling.

    Args:
        conn: Not used (kept for API compatibility) - queries daemon directly
        config_dir: Optional Eww config directory

    Returns:
        True if published successfully
    """
    try:
        from typing import Any, Dict, List

        # Helper functions (same as monitoring_data.py)
        def transform_window(window: Dict[str, Any], badge_state: Dict[str, Any]) -> Dict[str, Any]:
            """Transform daemon window to Eww-friendly schema.

            Args:
                window: Window data from daemon
                badge_state: Badge state mapping window IDs to badge info (Feature 095)
            """
            window_id = str(window.get("id", 0))
            badge = badge_state.get(window_id, {})

            return {
                "id": window.get("id", 0),
                "app_name": window.get("class", window.get("app_id", "unknown")),
                "title": window.get("title", "")[:50],  # Truncate to 50 chars
                "project": window.get("project", ""),
                "scope": "scoped" if any(str(m).startswith("scoped:") for m in window.get("marks", [])) else "global",
                "icon_path": window.get("icon_path", ""),
                "workspace": window.get("workspace", 1),
                "floating": window.get("floating", False),
                "hidden": window.get("hidden", False),
                "focused": window.get("focused", False),
                # Feature 095: Visual notification badges
                "badge": badge if badge else None,
            }

        def transform_workspace(workspace: Dict[str, Any], monitor_name: str, badge_state: Dict[str, Any]) -> Dict[str, Any]:
            """Transform daemon workspace to Eww-friendly schema.

            Args:
                workspace: Workspace data from daemon
                monitor_name: Name of the monitor this workspace belongs to
                badge_state: Badge state mapping window IDs to badge info (Feature 095)
            """
            windows = workspace.get("windows", [])
            transformed_windows = [transform_window(w, badge_state) for w in windows]

            return {
                "number": workspace.get("num", workspace.get("number", 1)),
                "name": workspace.get("name", ""),
                "visible": workspace.get("visible", False),
                "focused": workspace.get("focused", False),
                "monitor": monitor_name,
                "window_count": len(transformed_windows),
                "windows": transformed_windows,
            }

        def transform_monitor(output: Dict[str, Any], badge_state: Dict[str, Any]) -> Dict[str, Any]:
            """Transform daemon output to Eww-friendly schema.

            Args:
                output: Output data from daemon
                badge_state: Badge state mapping window IDs to badge info (Feature 095)
            """
            monitor_name = output.get("name", "unknown")
            workspaces = output.get("workspaces", [])
            transformed_workspaces = [transform_workspace(ws, monitor_name, badge_state) for ws in workspaces]
            has_focused = any(ws["focused"] for ws in transformed_workspaces)

            return {
                "name": monitor_name,
                "active": output.get("active", True),
                "focused": has_focused,
                "workspaces": transformed_workspaces,
            }

        # Query daemon for window tree (returns dict structures, not Con objects)
        tree_data = await _rpc_request("get_window_tree", {}, timeout=2.0)

        # Feature 095: Query badge state for visual notification badges
        badge_response = await _rpc_request("get_badge_state", {}, timeout=2.0)
        badge_state = badge_response.get("badges", {}) if isinstance(badge_response, dict) else {}
        if not isinstance(badge_state, dict):
            badge_state = {}
        logger.debug(f"[Feature 095] Retrieved badge state: {len(badge_state)} badges")

        # Extract outputs from tree and transform with badge state
        outputs = tree_data.get("outputs", [])
        monitors = [transform_monitor(output, badge_state) for output in outputs]

        # Calculate summary counts
        monitor_count = len(monitors)
        workspace_count = sum(len(m["workspaces"]) for m in monitors)
        window_count = sum(ws["window_count"] for m in monitors for ws in m["workspaces"])

        # Build state JSON
        state = {
            "status": "ok",
            "monitors": monitors,
            "monitor_count": monitor_count,
            "workspace_count": workspace_count,
            "window_count": window_count,
            "timestamp": time.time(),
            "error": None,
        }

        # Publish to Eww
        state_json = json.dumps(state, separators=(",", ":"))
        success = update_panel_state(state_json, config_dir)

        if success:
            logger.info(f"[Feature 085] Published monitoring panel state: "
                       f"monitors={monitor_count}, workspaces={workspace_count}, windows={window_count}")

        return success

    except Exception as e:
        logger.error(f"[Feature 085] Failed to publish monitoring state: {e}", exc_info=True)
        return False


class MonitoringPanelPublisher:
    """Service class for publishing monitoring panel state to Eww.

    Subscribes to window events and publishes updates within <100ms.
    """

    def __init__(self, config_dir: Optional[Path] = None):
        """Initialize publisher.

        Args:
            config_dir: Optional Eww config directory
        """
        self.config_dir = config_dir or EWW_MONITORING_PANEL_DIR

    async def publish(self, conn) -> bool:
        """Publish current monitoring state.

        Args:
            conn: i3ipc.aio.Connection to Sway IPC

        Returns:
            True if published successfully
        """
        return await publish_monitoring_state(conn, self.config_dir)

    async def on_window_event(self, conn, event) -> None:
        """Handle window events (new, close, move, focus).

        Args:
            conn: i3ipc.aio.Connection to Sway IPC
            event: i3ipc window event
        """
        logger.debug(f"[Feature 085] Window event: {event.change}")
        await self.publish(conn)

    async def on_workspace_event(self, conn, event) -> None:
        """Handle workspace events (focus, init, empty).

        Args:
            conn: i3ipc.aio.Connection to Sway IPC
            event: i3ipc workspace event
        """
        logger.debug(f"[Feature 085] Workspace event: {event.change}")
        await self.publish(conn)
