"""
i3 IPC client wrapper using i3ipc.aio for async operations.
"""

import asyncio
from typing import Optional, List
import i3ipc.aio as i3ipc

try:
    from .models import Window
except ImportError:
    from models import Window


class I3Client:
    """Async wrapper for i3 IPC communication."""

    def __init__(self):
        self.conn: Optional[i3ipc.Connection] = None
        self._connected = False

    async def connect(self) -> None:
        """Establish connection to i3 IPC."""
        if self._connected:
            return

        try:
            self.conn = await i3ipc.Connection().connect()
            self._connected = True
        except Exception as e:
            raise ConnectionError(f"Failed to connect to i3 IPC: {e}")

    async def disconnect(self) -> None:
        """Close connection to i3 IPC."""
        if self.conn:
            self.conn.main_quit()
            self._connected = False
            self.conn = None

    async def get_tree(self):
        """Get i3 tree structure."""
        if not self._connected:
            await self.connect()
        return await self.conn.get_tree()

    async def get_windows(self) -> List[Window]:
        """Get all windows from i3 tree."""
        tree = await self.get_tree()
        windows = []

        def collect_windows(node):
            """Recursively collect window nodes."""
            if node.type == "con" and node.window:
                windows.append(Window.from_i3_container(node))
            for child in node.nodes:
                collect_windows(child)
            for child in node.floating_nodes:
                collect_windows(child)

        collect_windows(tree)
        return windows

    async def get_window_by_id(self, window_id: int) -> Optional[Window]:
        """Get a specific window by its i3 container ID."""
        windows = await self.get_windows()
        for window in windows:
            if window.id == window_id:
                return window
        return None

    async def subscribe_to_events(self, event_types: List[str], callback):
        """
        Subscribe to i3 events.

        Args:
            event_types: List of event types ("window", "workspace", "output", etc.)
            callback: Async function to call when events occur
        """
        if not self._connected:
            await self.connect()

        for event_type in event_types:
            if event_type == "window":
                self.conn.on("window", callback)
            elif event_type == "workspace":
                self.conn.on("workspace", callback)
            elif event_type == "output":
                self.conn.on("output", callback)

    async def wait_for_window_event(self, timeout: float = 10.0) -> Optional[Window]:
        """
        Wait for a window::new event and return the new window.

        Args:
            timeout: Maximum time to wait in seconds

        Returns:
            Window object if a new window appeared, None if timeout
        """
        if not self._connected:
            await self.connect()

        future = asyncio.Future()

        def on_window_event(conn, event):
            if event.change == "new" and not future.done():
                try:
                    window = Window.from_i3_container(event.container)
                    future.set_result(window)
                except Exception as e:
                    if not future.done():
                        future.set_exception(e)

        # Subscribe to window events
        self.conn.on("window", on_window_event)

        try:
            # Wait for event with timeout
            window = await asyncio.wait_for(future, timeout=timeout)
            return window
        except asyncio.TimeoutError:
            return None
        finally:
            # Unsubscribe
            self.conn.off(on_window_event)

    async def close_window(self, window_id: int) -> bool:
        """
        Close a window by its i3 container ID.

        Args:
            window_id: The i3 container ID

        Returns:
            True if successful, False otherwise
        """
        try:
            await self.conn.command(f'[con_id="{window_id}"] kill')
            return True
        except Exception:
            return False

    async def move_window_to_workspace(self, window_id: int, workspace: int) -> bool:
        """
        Move a window to a specific workspace.

        Args:
            window_id: The i3 container ID
            workspace: Target workspace number (1-9)

        Returns:
            True if successful, False otherwise
        """
        try:
            await self.conn.command(f'[con_id="{window_id}"] move container to workspace number {workspace}')
            return True
        except Exception:
            return False

    def __aenter__(self):
        """Async context manager entry."""
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.disconnect()
