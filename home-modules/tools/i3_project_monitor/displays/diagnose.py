"""Diagnostic snapshot display mode.

Captures complete system state for post-mortem debugging and analysis.
"""

import asyncio
import json
import logging
import os
import platform
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

from i3ipc import aio as i3ipc_aio

from ..daemon_client import DaemonClient
from .base import BaseDisplay

logger = logging.getLogger(__name__)


class DiagnoseDisplay(BaseDisplay):
    """Diagnostic snapshot capture display.

    Captures comprehensive system state including:
    - Daemon state and statistics
    - All projects and windows
    - Recent event buffer
    - i3 tree structure
    - Output configuration (GET_OUTPUTS)
    - Workspace assignments (GET_WORKSPACES)
    - System metadata
    """

    def __init__(
        self,
        client: DaemonClient,
        output_file: Optional[Path] = None,
        include_events: bool = True,
        event_limit: int = 500,
        include_tree: bool = True,
        include_monitors: bool = True,
    ):
        """Initialize diagnostic display.

        Args:
            client: Daemon client instance
            output_file: Optional output file path (default: stdout)
            include_events: Include event buffer in snapshot
            event_limit: Number of events to include
            include_tree: Include i3 tree dump
            include_monitors: Include monitor client list
        """
        super().__init__(client)
        self.output_file = output_file
        self.include_events = include_events
        self.event_limit = event_limit
        self.include_tree = include_tree
        self.include_monitors = include_monitors

    async def run(self) -> None:
        """Capture diagnostic snapshot and output to file or stdout."""
        try:
            snapshot = await self._capture_snapshot()
            output = json.dumps(snapshot, indent=2, default=str)

            if self.output_file:
                self.output_file.parent.mkdir(parents=True, exist_ok=True)
                self.output_file.write_text(output)
                print(f"Diagnostic snapshot written to: {self.output_file}")
            else:
                print(output)

        except Exception as e:
            logger.error(f"Failed to capture diagnostic snapshot: {e}", exc_info=True)
            raise

    async def _capture_snapshot(self) -> Dict[str, Any]:
        """Capture complete diagnostic snapshot.

        Returns:
            Complete diagnostic snapshot dictionary
        """
        start_time = datetime.now()

        # Capture all data in parallel where possible
        daemon_data_task = self._capture_daemon_state()
        i3_data_task = self._capture_i3_state()
        metadata_task = self._capture_metadata()

        daemon_data = await daemon_data_task
        i3_data = await i3_data_task
        metadata = await metadata_task

        end_time = datetime.now()
        duration_ms = (end_time - start_time).total_seconds() * 1000

        return {
            "schema_version": "1.0.0",
            "timestamp": start_time.isoformat(),
            "capture_duration_ms": duration_ms,
            "daemon_state": daemon_data.get("daemon_state", {}),
            "projects": daemon_data.get("projects", []),
            "windows": daemon_data.get("windows", []),
            "events": daemon_data.get("events", []),
            "event_stats": daemon_data.get("event_stats", {}),
            "monitors": daemon_data.get("monitors", []),
            "i3_state": i3_data,
            "metadata": metadata,
        }

    async def _capture_daemon_state(self) -> Dict[str, Any]:
        """Capture daemon state using get_diagnostic_state JSON-RPC method.

        Returns:
            Daemon diagnostic data
        """
        try:
            params = {
                "include_events": self.include_events,
                "event_limit": self.event_limit,
                "include_tree": False,  # We'll get tree from i3 directly
                "include_monitors": self.include_monitors,
            }

            result = await self.client.request("get_diagnostic_state", params)
            return result

        except Exception as e:
            logger.error(f"Failed to capture daemon state: {e}")
            return {
                "error": str(e),
                "daemon_state": {},
                "projects": [],
                "windows": [],
                "events": [],
                "event_stats": {},
                "monitors": [],
            }

    async def _capture_i3_state(self) -> Dict[str, Any]:
        """Capture i3 state directly via IPC.

        Returns:
            Dictionary with outputs, workspaces, tree, and marks
        """
        try:
            # Connect to i3 directly
            i3 = await i3ipc_aio.Connection().connect()

            # Query i3 state in parallel
            outputs_task = i3.get_outputs()
            workspaces_task = i3.get_workspaces()
            tree_task = i3.get_tree() if self.include_tree else None
            marks_task = i3.get_marks()

            outputs = await outputs_task
            workspaces = await workspaces_task
            tree = await tree_task if tree_task else None
            marks = await marks_task

            # Convert i3ipc objects to dictionaries
            return {
                "outputs": [self._output_to_dict(o) for o in outputs],
                "workspaces": [self._workspace_to_dict(w) for w in workspaces],
                "tree": self._tree_to_dict(tree) if tree else None,
                "marks": marks,
            }

        except Exception as e:
            logger.error(f"Failed to capture i3 state: {e}")
            return {
                "error": str(e),
                "outputs": [],
                "workspaces": [],
                "tree": None,
                "marks": [],
            }

    async def _capture_metadata(self) -> Dict[str, Any]:
        """Capture system metadata.

        Returns:
            Metadata dictionary
        """
        try:
            # Get i3 version
            i3_version = "unknown"
            try:
                i3 = await i3ipc_aio.Connection().connect()
                version_info = await i3.get_version()
                i3_version = version_info.human_readable
            except Exception as e:
                logger.warning(f"Failed to get i3 version: {e}")

            return {
                "i3_version": i3_version,
                "python_version": platform.python_version(),
                "hostname": platform.node(),
                "user": os.environ.get("USER", "unknown"),
                "display": os.environ.get("DISPLAY", "unknown"),
                "xdg_runtime_dir": os.environ.get("XDG_RUNTIME_DIR", "unknown"),
                "platform": platform.platform(),
                "architecture": platform.machine(),
            }

        except Exception as e:
            logger.error(f"Failed to capture metadata: {e}")
            return {"error": str(e)}

    def _output_to_dict(self, output: Any) -> Dict[str, Any]:
        """Convert i3ipc Output to dictionary.

        Args:
            output: i3ipc Output object

        Returns:
            Dictionary representation
        """
        return {
            "name": output.name,
            "active": output.active,
            "primary": output.primary,
            "current_workspace": output.current_workspace,
            "rect": {
                "x": output.rect.x,
                "y": output.rect.y,
                "width": output.rect.width,
                "height": output.rect.height,
            } if output.rect else None,
        }

    def _workspace_to_dict(self, workspace: Any) -> Dict[str, Any]:
        """Convert i3ipc Workspace to dictionary.

        Args:
            workspace: i3ipc Workspace object

        Returns:
            Dictionary representation
        """
        return {
            "num": workspace.num,
            "name": workspace.name,
            "output": workspace.output,
            "visible": workspace.visible,
            "focused": workspace.focused,
            "urgent": workspace.urgent,
            "rect": {
                "x": workspace.rect.x,
                "y": workspace.rect.y,
                "width": workspace.rect.width,
                "height": workspace.rect.height,
            } if workspace.rect else None,
        }

    def _tree_to_dict(self, node: Any) -> Dict[str, Any]:
        """Convert i3ipc tree node to dictionary recursively.

        Args:
            node: i3ipc Con (container) object

        Returns:
            Dictionary representation
        """
        if node is None:
            return None

        result = {
            "id": node.id,
            "type": node.type,
            "name": node.name,
            "window": node.window,
            "window_class": getattr(node, "window_class", None),
            "window_instance": getattr(node, "window_instance", None),
            "marks": node.marks if hasattr(node, "marks") else [],
            "focused": node.focused,
            "layout": node.layout,
            "orientation": getattr(node, "orientation", None),
            "urgent": node.urgent,
            "rect": {
                "x": node.rect.x,
                "y": node.rect.y,
                "width": node.rect.width,
                "height": node.rect.height,
            } if node.rect else None,
        }

        # Recursively convert children
        if hasattr(node, "nodes") and node.nodes:
            result["nodes"] = [self._tree_to_dict(child) for child in node.nodes]

        if hasattr(node, "floating_nodes") and node.floating_nodes:
            result["floating_nodes"] = [self._tree_to_dict(child) for child in node.floating_nodes]

        return result


class DiagnoseDiffDisplay(BaseDisplay):
    """Diagnostic snapshot comparison display.

    Compares two diagnostic snapshots and shows differences.
    """

    def __init__(
        self,
        client: DaemonClient,
        snapshot1_path: Path,
        snapshot2_path: Path,
        output_file: Optional[Path] = None,
    ):
        """Initialize diff display.

        Args:
            client: Daemon client instance (unused, for compatibility)
            snapshot1_path: Path to first snapshot file
            snapshot2_path: Path to second snapshot file
            output_file: Optional output file path (default: stdout)
        """
        super().__init__(client)
        self.snapshot1_path = snapshot1_path
        self.snapshot2_path = snapshot2_path
        self.output_file = output_file

    async def run(self) -> None:
        """Compare snapshots and output differences."""
        try:
            # Load snapshots
            snapshot1 = json.loads(self.snapshot1_path.read_text())
            snapshot2 = json.loads(self.snapshot2_path.read_text())

            # Generate diff report
            diff_report = self._generate_diff(snapshot1, snapshot2)
            output = json.dumps(diff_report, indent=2, default=str)

            if self.output_file:
                self.output_file.parent.mkdir(parents=True, exist_ok=True)
                self.output_file.write_text(output)
                print(f"Diff report written to: {self.output_file}")
            else:
                print(output)

        except Exception as e:
            logger.error(f"Failed to compare snapshots: {e}", exc_info=True)
            raise

    def _generate_diff(self, snap1: Dict[str, Any], snap2: Dict[str, Any]) -> Dict[str, Any]:
        """Generate difference report between two snapshots.

        Args:
            snap1: First snapshot
            snap2: Second snapshot

        Returns:
            Diff report dictionary
        """
        return {
            "snapshot1": {
                "timestamp": snap1.get("timestamp"),
                "schema_version": snap1.get("schema_version"),
            },
            "snapshot2": {
                "timestamp": snap2.get("timestamp"),
                "schema_version": snap2.get("schema_version"),
            },
            "differences": {
                "daemon_state": self._diff_daemon_state(
                    snap1.get("daemon_state", {}),
                    snap2.get("daemon_state", {}),
                ),
                "projects": self._diff_lists(
                    snap1.get("projects", []),
                    snap2.get("projects", []),
                    key="name",
                ),
                "windows": self._diff_lists(
                    snap1.get("windows", []),
                    snap2.get("windows", []),
                    key="window_id",
                ),
                "outputs": self._diff_lists(
                    snap1.get("i3_state", {}).get("outputs", []),
                    snap2.get("i3_state", {}).get("outputs", []),
                    key="name",
                ),
                "workspaces": self._diff_lists(
                    snap1.get("i3_state", {}).get("workspaces", []),
                    snap2.get("i3_state", {}).get("workspaces", []),
                    key="name",
                ),
            },
        }

    def _diff_daemon_state(self, state1: Dict[str, Any], state2: Dict[str, Any]) -> Dict[str, Any]:
        """Compare daemon state between snapshots.

        Args:
            state1: First daemon state
            state2: Second daemon state

        Returns:
            Daemon state differences
        """
        changes = {}

        # Check for changed values
        for key in set(state1.keys()) | set(state2.keys()):
            val1 = state1.get(key)
            val2 = state2.get(key)

            if val1 != val2:
                changes[key] = {
                    "before": val1,
                    "after": val2,
                    "change": val2 - val1 if isinstance(val1, (int, float)) and isinstance(val2, (int, float)) else None,
                }

        return changes

    def _diff_lists(self, list1: list, list2: list, key: str) -> Dict[str, Any]:
        """Compare lists of items by key field.

        Args:
            list1: First list
            list2: Second list
            key: Key field to use for matching items

        Returns:
            List differences (added, removed, changed)
        """
        # Create lookup dictionaries
        dict1 = {item.get(key): item for item in list1 if key in item}
        dict2 = {item.get(key): item for item in list2 if key in item}

        keys1 = set(dict1.keys())
        keys2 = set(dict2.keys())

        return {
            "added": [dict2[k] for k in keys2 - keys1],
            "removed": [dict1[k] for k in keys1 - keys2],
            "changed": [
                {
                    "key": k,
                    "before": dict1[k],
                    "after": dict2[k],
                }
                for k in keys1 & keys2
                if dict1[k] != dict2[k]
            ],
            "count_change": len(list2) - len(list1),
        }
