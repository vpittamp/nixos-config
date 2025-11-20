"""Monitoring Panel Publisher for event-driven panel state updates.

This module publishes window/project state to the Eww monitoring panel
widget via `eww update`, achieving <100ms update latency.

Version: 1.0.0 (2025-11-20)
Feature: 085-sway-monitoring-widget
"""

import json
import logging
import subprocess
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Eww configuration directory (monitoring panel)
EWW_MONITORING_PANEL_DIR = Path.home() / ".config" / "eww-monitoring-panel"

# Eww variable name for panel state
PANEL_STATE_VAR = "panel_state"


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
        conn: i3ipc.aio.Connection to Sway IPC
        config_dir: Optional Eww config directory

    Returns:
        True if published successfully
    """
    try:
        import time
        from typing import Any, Dict, List

        # Helper functions (same as monitoring_data.py)
        def transform_window(window: Dict[str, Any]) -> Dict[str, Any]:
            """Transform Sway window to Eww-friendly schema."""
            props = window.get("window_properties", {}) or {}
            return {
                "id": window.get("id", 0),
                "app_name": props.get("class", props.get("instance", "unknown")),
                "title": window.get("name", "")[:50],  # Truncate to 50 chars
                "project": window.get("marks", [""])[0].split("i3pm_project:")[1] if any("i3pm_project:" in m for m in window.get("marks", [])) else "",
                "scope": "scoped" if any("i3pm_scope:scoped" in m for m in window.get("marks", [])) else "global",
                "icon_path": "",
                "workspace": window.get("workspace", {}).get("num", 1) if isinstance(window.get("workspace"), dict) else 1,
                "floating": window.get("type") == "floating_con",
                "hidden": not window.get("visible", True),
                "focused": window.get("focused", False),
            }

        def transform_workspace(workspace: Dict[str, Any], monitor_name: str) -> Dict[str, Any]:
            """Transform Sway workspace to Eww-friendly schema."""
            windows = [w for w in workspace.get("nodes", []) if w.get("type") in ("con", "floating_con")]
            transformed_windows = [transform_window(w) for w in windows]

            return {
                "number": workspace.get("num", 1),
                "name": workspace.get("name", ""),
                "visible": workspace.get("visible", False),
                "focused": workspace.get("focused", False),
                "monitor": monitor_name,
                "window_count": len(transformed_windows),
                "windows": transformed_windows,
            }

        def transform_monitor(output: Dict[str, Any]) -> Dict[str, Any]:
            """Transform Sway output to Eww-friendly schema."""
            monitor_name = output.get("name", "unknown")

            # Get workspaces from output's workspace nodes
            workspace_nodes = []
            for node in output.get("nodes", []):
                if node.get("type") == "workspace":
                    workspace_nodes.append(node)

            transformed_workspaces = [transform_workspace(ws, monitor_name) for ws in workspace_nodes]
            has_focused = any(ws["focused"] for ws in transformed_workspaces)

            return {
                "name": monitor_name,
                "active": output.get("active", True),
                "focused": has_focused,
                "workspaces": transformed_workspaces,
            }

        # Query Sway tree
        tree = await conn.get_tree()

        # Extract outputs from tree
        outputs = [node for node in tree.get("nodes", []) if node.get("type") == "output" and node.get("name") not in ("__i3", "__i3_scratch")]
        monitors = [transform_monitor(output) for output in outputs]

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
