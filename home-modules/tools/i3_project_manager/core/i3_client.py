"""i3 IPC client for querying window manager state.

This module provides async wrappers around i3ipc.aio for querying:
- Window tree (GET_TREE)
- Workspaces (GET_WORKSPACES)
- Outputs/monitors (GET_OUTPUTS)
- Window marks (GET_MARKS)
- Sending commands (RUN_COMMAND)

All queries follow Principle XI: i3 IPC as authoritative source.

T093: i3 IPC logging for debugging and diagnostics.
"""

import asyncio
import logging
from typing import Any, Dict, List, Optional, Tuple

import i3ipc.aio


# Get logger for this module
logger = logging.getLogger('i3pm.i3_client')


class I3Error(Exception):
    """Exception raised for i3 IPC errors."""

    pass


class I3Client:
    """Async wrapper for i3ipc queries.

    Provides high-level methods for querying i3 window manager state
    following the principle that i3 IPC is the authoritative source.
    """

    def __init__(self):
        """Initialize i3 client."""
        self._connection: Optional[i3ipc.aio.Connection] = None

    async def connect(self) -> None:
        """Connect to i3 IPC socket.

        Raises:
            I3Error: If connection fails

        T093: Log connection attempts
        """
        try:
            logger.debug("Connecting to i3 IPC socket")
            self._connection = await i3ipc.aio.Connection().connect()
            logger.info("Connected to i3 IPC")
        except Exception as e:
            logger.error(f"Failed to connect to i3 IPC: {e}")
            raise I3Error(f"Failed to connect to i3: {e}")

    async def close(self) -> None:
        """Close i3 connection."""
        if self._connection:
            # i3ipc doesn't have explicit close, connection auto-closes
            self._connection = None

    async def get_tree(self) -> i3ipc.aio.Con:
        """Get i3 window tree (GET_TREE).

        Returns:
            Root container with full window hierarchy

        Raises:
            I3Error: If query fails

        T093: Log IPC queries
        """
        if not self._connection:
            await self.connect()

        try:
            logger.debug("IPC query: GET_TREE")
            tree = await self._connection.get_tree()
            logger.debug(f"GET_TREE returned tree with {len(list(tree.leaves()))} leaf nodes")
            return tree
        except Exception as e:
            logger.error(f"GET_TREE failed: {e}")
            raise I3Error(f"Failed to get window tree: {e}")

    async def get_workspaces(self) -> List[Dict[str, Any]]:
        """Get all workspaces (GET_WORKSPACES).

        Returns:
            List of workspace dicts with keys: num, name, output, visible, focused

        Raises:
            I3Error: If query fails

        T093: Log IPC queries
        """
        if not self._connection:
            await self.connect()

        try:
            logger.debug("IPC query: GET_WORKSPACES")
            workspaces = await self._connection.get_workspaces()
            logger.debug(f"GET_WORKSPACES returned {len(workspaces)} workspace(s)")
            return [
                {
                    "num": ws.num,
                    "name": ws.name,
                    "output": ws.output,
                    "visible": ws.visible,
                    "focused": ws.focused,
                }
                for ws in workspaces
            ]
        except Exception as e:
            logger.error(f"GET_WORKSPACES failed: {e}")
            raise I3Error(f"Failed to get workspaces: {e}")

    async def get_outputs(self) -> List[Dict[str, Any]]:
        """Get all outputs/monitors (GET_OUTPUTS).

        Returns:
            List of output dicts with keys: name, active, primary, rect

        Raises:
            I3Error: If query fails

        T093: Log IPC queries
        """
        if not self._connection:
            await self.connect()

        try:
            logger.debug("IPC query: GET_OUTPUTS")
            outputs = await self._connection.get_outputs()
            active_outputs = [out for out in outputs if out.active]
            logger.debug(f"GET_OUTPUTS returned {len(active_outputs)} active output(s)")
            return [
                {
                    "name": out.name,
                    "active": out.active,
                    "primary": out.primary,
                    "rect": {
                        "x": out.rect.x,
                        "y": out.rect.y,
                        "width": out.rect.width,
                        "height": out.rect.height,
                    },
                }
                for out in active_outputs
            ]
        except Exception as e:
            logger.error(f"GET_OUTPUTS failed: {e}")
            raise I3Error(f"Failed to get outputs: {e}")

    async def get_marks(self) -> List[str]:
        """Get all window marks (GET_MARKS).

        Returns:
            List of mark strings

        Raises:
            I3Error: If query fails

        T093: Log IPC queries
        """
        if not self._connection:
            await self.connect()

        try:
            logger.debug("IPC query: GET_MARKS")
            marks = await self._connection.get_marks()
            logger.debug(f"GET_MARKS returned {len(marks)} mark(s)")
            return marks
        except Exception as e:
            logger.error(f"GET_MARKS failed: {e}")
            raise I3Error(f"Failed to get marks: {e}")

    async def command(self, cmd: str) -> List[Dict[str, Any]]:
        """Send command to i3 (RUN_COMMAND).

        Args:
            cmd: i3 command string

        Returns:
            List of command result dicts with 'success' key

        Raises:
            I3Error: If command fails

        T093: Log IPC commands
        """
        if not self._connection:
            await self.connect()

        try:
            logger.debug(f"IPC command: {cmd}")
            results = await self._connection.command(cmd)
            success_count = sum(1 for r in results if r.success)
            logger.debug(f"RUN_COMMAND completed: {success_count}/{len(results)} succeeded")
            return [{"success": r.success, "error": getattr(r, "error", None)} for r in results]
        except Exception as e:
            logger.error(f"RUN_COMMAND failed for '{cmd}': {e}")
            raise I3Error(f"Failed to execute command '{cmd}': {e}")

    # Helper methods for common queries

    async def get_windows_by_mark(self, mark: str) -> List[Dict[str, Any]]:
        """Get all windows with a specific mark.

        Args:
            mark: Mark to filter by (e.g., "project:nixos")

        Returns:
            List of window dicts with keys: id, window_class, title, workspace, marks, rect

        Raises:
            I3Error: If query fails
        """
        tree = await self.get_tree()
        windows = []

        def find_windows(con):
            """Recursively find windows with mark."""
            if con.window and mark in con.marks:
                windows.append(
                    {
                        "id": con.window,
                        "window_class": con.window_class,
                        "title": con.name,
                        "workspace": con.workspace().name if con.workspace() else None,
                        "marks": con.marks,
                        "rect": {
                            "x": con.rect.x,
                            "y": con.rect.y,
                            "width": con.rect.width,
                            "height": con.rect.height,
                        },
                    }
                )
            for child in con.nodes + con.floating_nodes:
                find_windows(child)

        find_windows(tree)
        return windows

    async def get_workspace_to_output_map(self) -> Dict[int, str]:
        """Get mapping of workspace numbers to output names.

        Returns:
            Dict mapping workspace number to output name (e.g., {1: "eDP-1", 2: "HDMI-1"})

        Raises:
            I3Error: If query fails
        """
        workspaces = await self.get_workspaces()
        return {ws["num"]: ws["output"] for ws in workspaces if ws["num"] is not None}

    async def assign_logical_outputs(self) -> Dict[str, str]:
        """Map logical output roles (primary/secondary/tertiary) to physical outputs.

        Returns:
            Dict mapping role to output name (e.g., {"primary": "eDP-1", "secondary": "HDMI-1"})

        The mapping is based on:
        1. Primary flag from i3
        2. Position (leftmost = primary, then by x coordinate)

        Raises:
            I3Error: If query fails
        """
        outputs = await self.get_outputs()

        if not outputs:
            return {}

        # Sort outputs: primary first, then by x position
        def sort_key(out):
            primary_weight = 0 if out["primary"] else 1
            return (primary_weight, out["rect"]["x"])

        sorted_outputs = sorted(outputs, key=sort_key)

        role_map = {}
        roles = ["primary", "secondary", "tertiary"]

        for i, output in enumerate(sorted_outputs[:3]):  # Max 3 roles
            role_map[roles[i]] = output["name"]

        return role_map

    async def focus_workspace(self, workspace: int) -> bool:
        """Focus a workspace by number.

        Args:
            workspace: Workspace number (1-10)

        Returns:
            True if successful

        Raises:
            I3Error: If command fails
        """
        results = await self.command(f"workspace {workspace}")
        return all(r["success"] for r in results)

    async def move_window_to_workspace(self, window_id: int, workspace: int) -> bool:
        """Move a window to a workspace.

        Args:
            window_id: Window ID
            workspace: Target workspace number

        Returns:
            True if successful

        Raises:
            I3Error: If command fails
        """
        results = await self.command(f"[id={window_id}] move container to workspace {workspace}")
        return all(r["success"] for r in results)

    async def close_window(self, window_id: int) -> bool:
        """Close a window gracefully.

        Args:
            window_id: Window ID to close

        Returns:
            True if successful

        Raises:
            I3Error: If command fails
        """
        results = await self.command(f"[id={window_id}] kill")
        return all(r["success"] for r in results)

    async def mark_window(self, window_id: int, mark: str) -> bool:
        """Add a mark to a window.

        Args:
            window_id: Window ID
            mark: Mark to add (e.g., "project:nixos")

        Returns:
            True if successful

        Raises:
            I3Error: If command fails
        """
        results = await self.command(f"[id={window_id}] mark --add {mark}")
        return all(r["success"] for r in results)

    async def unmark_window(self, window_id: int, mark: str) -> bool:
        """Remove a mark from a window.

        Args:
            window_id: Window ID
            mark: Mark to remove

        Returns:
            True if successful

        Raises:
            I3Error: If command fails
        """
        results = await self.command(f"[id={window_id}] unmark {mark}")
        return all(r["success"] for r in results)

    async def send_tick(self, payload: str) -> bool:
        """Send a tick event (used for triggering daemon actions).

        Args:
            payload: Tick payload (e.g., "project:nixos" to switch projects)

        Returns:
            True if successful

        Raises:
            I3Error: If command fails
        """
        results = await self.command(f"nop {payload}")
        return all(r["success"] for r in results)

    async def __aenter__(self):
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.close()


# Convenience function for one-off queries
async def query_i3(func):
    """Execute a query function with auto-managed i3 connection.

    Args:
        func: Async function that takes I3Client as argument

    Returns:
        Result of func

    Example:
        ```python
        workspaces = await query_i3(lambda i3: i3.get_workspaces())
        ```
    """
    async with I3Client() as client:
        return await func(client)
