"""i3 IPC connection manager with resilient reconnection.

Handles i3 IPC connection, automatic reconnection, and state rebuilding.
"""

import asyncio
import logging
from typing import Optional, Callable, Awaitable
import i3ipc

from .state import StateManager

logger = logging.getLogger(__name__)


class ResilientI3Connection:
    """Manages i3 IPC connection with automatic reconnection and state recovery."""

    def __init__(self, state_manager: StateManager) -> None:
        """Initialize connection manager.

        Args:
            state_manager: StateManager instance for state rebuilding
        """
        self.state_manager = state_manager
        self.conn: Optional[i3ipc.Connection] = None
        self.is_shutting_down = False
        self.reconnect_delay = 0.1  # Initial delay: 100ms

    async def connect_with_retry(self, max_attempts: int = 10) -> i3ipc.Connection:
        """Connect to i3 with exponential backoff retry.

        Args:
            max_attempts: Maximum connection attempts

        Returns:
            Connected i3ipc.Connection

        Raises:
            ConnectionError: If connection fails after max attempts
        """
        attempt = 0
        delay = self.reconnect_delay

        while attempt < max_attempts:
            try:
                logger.info(f"Attempting to connect to i3 (attempt {attempt + 1}/{max_attempts})")

                # Create connection with auto-reconnect
                self.conn = i3ipc.Connection(auto_reconnect=True)

                # Test connection by getting version
                version = self.conn.get_version()
                logger.info(f"Connected to i3 version {version.human_readable}")

                # Rebuild state from marks
                await self.rebuild_state()

                # Reset reconnect delay on successful connection
                self.reconnect_delay = 0.1

                return self.conn

            except Exception as e:
                logger.warning(f"Connection attempt {attempt + 1} failed: {e}")
                attempt += 1

                if attempt < max_attempts:
                    logger.debug(f"Waiting {delay:.1f}s before retry...")
                    await asyncio.sleep(delay)

                    # Exponential backoff: double delay up to 5s max
                    delay = min(delay * 2, 5.0)

        raise ConnectionError(f"Failed to connect to i3 after {max_attempts} attempts")

    async def rebuild_state(self) -> None:
        """Rebuild daemon state from i3 tree marks.

        Called after connecting/reconnecting to i3.
        """
        if not self.conn:
            logger.error("Cannot rebuild state: not connected")
            return

        try:
            logger.info("Rebuilding state from i3 tree...")

            # Get entire window tree
            tree = self.conn.get_tree()

            # Rebuild window_map from marks
            await self.state_manager.rebuild_from_marks(tree)

            # Rebuild workspace_map
            await self._rebuild_workspaces()

            logger.info("State rebuild complete")

        except Exception as e:
            logger.error(f"Failed to rebuild state: {e}")
            raise

    async def _rebuild_workspaces(self) -> None:
        """Rebuild workspace_map from i3 workspace list."""
        if not self.conn:
            return

        try:
            from .models import WorkspaceInfo

            workspaces = self.conn.get_workspaces()

            for ws in workspaces:
                workspace_info = WorkspaceInfo(
                    name=ws.name,
                    num=ws.num,
                    output=ws.output,
                    rect_x=ws.rect.x,
                    rect_y=ws.rect.y,
                    rect_width=ws.rect.width,
                    rect_height=ws.rect.height,
                    visible=ws.visible,
                    focused=ws.focused,
                    urgent=ws.urgent,
                )
                await self.state_manager.add_workspace(workspace_info)

        except Exception as e:
            logger.error(f"Failed to rebuild workspaces: {e}")

    async def handle_shutdown_event(self, event: i3ipc.Event) -> None:
        """Handle i3 shutdown/restart events.

        Distinguishes between i3 restart (reconnect) vs exit (shutdown daemon).

        Args:
            event: Shutdown event from i3
        """
        try:
            # Check shutdown type
            change = event.change  # type: ignore

            if change == "restart":
                logger.info("i3 is restarting - will auto-reconnect")
                # i3ipc auto_reconnect will handle this
                # Just wait for connection to come back
                await asyncio.sleep(2)
                await self.rebuild_state()

            elif change == "exit":
                logger.info("i3 is exiting - shutting down daemon")
                self.is_shutting_down = True

            else:
                logger.warning(f"Unknown shutdown change: {change}")

        except Exception as e:
            logger.error(f"Error handling shutdown event: {e}")

    def subscribe(
        self,
        event_type: str,
        handler: Callable[[i3ipc.Connection, i3ipc.Event], Awaitable[None]],
    ) -> None:
        """Subscribe to i3 events.

        Args:
            event_type: Event type to subscribe to (window, workspace, tick, shutdown)
            handler: Async handler function for events
        """
        if not self.conn:
            logger.error("Cannot subscribe: not connected")
            return

        def sync_wrapper(conn: i3ipc.Connection, event: i3ipc.Event) -> None:
            """Wrapper to run async handler in event loop."""
            asyncio.create_task(handler(conn, event))

        self.conn.on(event_type, sync_wrapper)
        logger.debug(f"Subscribed to {event_type} events")

    async def main(self) -> None:
        """Run the i3 event loop.

        This blocks until i3 connection is closed or daemon is shut down.
        """
        if not self.conn:
            logger.error("Cannot run main loop: not connected")
            return

        try:
            # Run i3 main loop (blocking)
            # This will process events until connection closes
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self.conn.main)

        except Exception as e:
            if not self.is_shutting_down:
                logger.error(f"i3 event loop error: {e}")
                raise
            else:
                logger.info("i3 event loop stopped (shutdown)")

    def close(self) -> None:
        """Close the i3 connection."""
        if self.conn:
            try:
                # Note: i3ipc doesn't have an explicit close method
                # Connection will be cleaned up when object is destroyed
                self.conn = None
                logger.info("Closed i3 connection")
            except Exception as e:
                logger.error(f"Error closing connection: {e}")
