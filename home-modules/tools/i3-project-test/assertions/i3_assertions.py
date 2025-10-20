"""i3 IPC assertions for test scenarios.

This module provides assertion functions for validating i3 window manager state via i3 IPC.
"""

import logging
from typing import Any, Dict, List, Optional

import i3ipc.aio


logger = logging.getLogger(__name__)


class I3Assertions:
    """Assertions for i3 IPC state validation."""

    def __init__(self):
        """Initialize i3 assertions."""
        self.i3: Optional[i3ipc.aio.Connection] = None

    async def connect(self) -> None:
        """Connect to i3 IPC.

        Raises:
            RuntimeError: If unable to connect
        """
        try:
            self.i3 = await i3ipc.aio.Connection().connect()
            logger.info("Connected to i3 IPC")
        except Exception as e:
            raise RuntimeError(f"Failed to connect to i3 IPC: {e}")

    async def disconnect(self) -> None:
        """Disconnect from i3 IPC."""
        if self.i3:
            self.i3.main_quit()
            self.i3 = None
            logger.info("Disconnected from i3 IPC")

    async def assert_workspace_visible(self, workspace_name: str) -> None:
        """Assert that a workspace is visible.

        Args:
            workspace_name: Name of workspace to check

        Raises:
            AssertionError: If workspace is not visible
        """
        if not self.i3:
            await self.connect()

        workspaces = await self.i3.get_workspaces()
        workspace = next((w for w in workspaces if w.name == workspace_name), None)

        if workspace is None:
            available = [w.name for w in workspaces]
            raise AssertionError(
                f"Workspace '{workspace_name}' not found. Available: {available}"
            )

        if not workspace.visible:
            raise AssertionError(
                f"Workspace '{workspace_name}' exists but is not visible"
            )

        logger.info(f"✓ Workspace '{workspace_name}' is visible")

    async def assert_workspace_on_output(
        self,
        workspace_name: str,
        output_name: str,
    ) -> None:
        """Assert that a workspace is assigned to a specific output.

        Args:
            workspace_name: Name of workspace
            output_name: Expected output name

        Raises:
            AssertionError: If workspace is not on expected output
        """
        if not self.i3:
            await self.connect()

        workspaces = await self.i3.get_workspaces()
        workspace = next((w for w in workspaces if w.name == workspace_name), None)

        if workspace is None:
            raise AssertionError(f"Workspace '{workspace_name}' not found")

        if workspace.output != output_name:
            raise AssertionError(
                f"Expected workspace '{workspace_name}' on output '{output_name}', "
                f"but it's on '{workspace.output}'"
            )

        logger.info(f"✓ Workspace '{workspace_name}' is on output '{output_name}'")

    async def assert_output_active(self, output_name: str) -> None:
        """Assert that an output is active.

        Args:
            output_name: Name of output to check

        Raises:
            AssertionError: If output is not active
        """
        if not self.i3:
            await self.connect()

        outputs = await self.i3.get_outputs()
        output = next((o for o in outputs if o.name == output_name), None)

        if output is None:
            available = [o.name for o in outputs]
            raise AssertionError(
                f"Output '{output_name}' not found. Available: {available}"
            )

        if not output.active:
            raise AssertionError(f"Output '{output_name}' exists but is not active")

        logger.info(f"✓ Output '{output_name}' is active")

    async def assert_output_exists(self, output_name: str) -> None:
        """Assert that an output exists.

        Args:
            output_name: Name of output to check

        Raises:
            AssertionError: If output doesn't exist
        """
        if not self.i3:
            await self.connect()

        outputs = await self.i3.get_outputs()
        output = next((o for o in outputs if o.name == output_name), None)

        if output is None:
            available = [o.name for o in outputs]
            raise AssertionError(
                f"Output '{output_name}' not found. Available: {available}"
            )

        logger.info(f"✓ Output '{output_name}' exists")

    async def assert_window_exists(self, window_id: int) -> None:
        """Assert that a window exists in i3 tree.

        Args:
            window_id: Window ID to check

        Raises:
            AssertionError: If window doesn't exist
        """
        if not self.i3:
            await self.connect()

        tree = await self.i3.get_tree()
        window = tree.find_by_id(window_id)

        if window is None:
            raise AssertionError(f"Window {window_id} not found in i3 tree")

        logger.info(f"✓ Window {window_id} exists in i3 tree")

    async def assert_mark_exists(self, mark: str) -> None:
        """Assert that a mark exists in i3.

        Args:
            mark: Mark to check for

        Raises:
            AssertionError: If mark doesn't exist
        """
        if not self.i3:
            await self.connect()

        marks = await self.i3.get_marks()

        if mark not in marks:
            raise AssertionError(
                f"Mark '{mark}' not found. Available marks: {marks}"
            )

        logger.info(f"✓ Mark '{mark}' exists")

    async def get_outputs(self) -> List[Dict[str, Any]]:
        """Get list of outputs from i3.

        Returns:
            List of output dictionaries

        Raises:
            RuntimeError: If unable to get outputs
        """
        if not self.i3:
            await self.connect()

        try:
            outputs = await self.i3.get_outputs()
            return [
                {
                    "name": o.name,
                    "active": o.active,
                    "primary": o.primary,
                    "rect": {
                        "x": o.rect.x,
                        "y": o.rect.y,
                        "width": o.rect.width,
                        "height": o.rect.height,
                    },
                }
                for o in outputs
            ]
        except Exception as e:
            raise RuntimeError(f"Failed to get outputs: {e}")

    async def get_workspaces(self) -> List[Dict[str, Any]]:
        """Get list of workspaces from i3.

        Returns:
            List of workspace dictionaries

        Raises:
            RuntimeError: If unable to get workspaces
        """
        if not self.i3:
            await self.connect()

        try:
            workspaces = await self.i3.get_workspaces()
            return [
                {
                    "num": w.num,
                    "name": w.name,
                    "output": w.output,
                    "visible": w.visible,
                    "focused": w.focused,
                    "urgent": w.urgent,
                }
                for w in workspaces
            ]
        except Exception as e:
            raise RuntimeError(f"Failed to get workspaces: {e}")

    async def get_tree(self) -> Dict[str, Any]:
        """Get complete i3 tree.

        Returns:
            i3 tree as dictionary

        Raises:
            RuntimeError: If unable to get tree
        """
        if not self.i3:
            await self.connect()

        try:
            tree = await self.i3.get_tree()
            return tree.ipc_data
        except Exception as e:
            raise RuntimeError(f"Failed to get i3 tree: {e}")

    async def get_marks(self) -> List[str]:
        """Get list of marks from i3.

        Returns:
            List of mark strings

        Raises:
            RuntimeError: If unable to get marks
        """
        if not self.i3:
            await self.connect()

        try:
            return await self.i3.get_marks()
        except Exception as e:
            raise RuntimeError(f"Failed to get marks: {e}")

    async def __aenter__(self):
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.disconnect()
