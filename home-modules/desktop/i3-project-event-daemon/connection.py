"""i3 IPC connection manager with resilient reconnection.

Handles i3 IPC connection, automatic reconnection, and state rebuilding.
"""

import asyncio
import logging
from typing import Optional, Callable, Awaitable
from i3ipc import aio
from i3ipc.events import IpcBaseEvent

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
        self.conn: Optional[aio.Connection] = None
        self.is_shutting_down = False
        self.reconnect_delay = 0.1  # Initial delay: 100ms

    async def connect_with_retry(self, max_attempts: int = 10) -> aio.Connection:
        """Connect to i3 with exponential backoff retry.

        Args:
            max_attempts: Maximum connection attempts

        Returns:
            Connected i3ipc.aio.Connection

        Raises:
            ConnectionError: If connection fails after max attempts
        """
        attempt = 0
        delay = self.reconnect_delay

        while attempt < max_attempts:
            try:
                logger.info(f"Attempting to connect to i3 (attempt {attempt + 1}/{max_attempts})")

                # Create async connection
                self.conn = await aio.Connection(auto_reconnect=True).connect()

                # Test connection by getting version
                version = await self.conn.get_version()
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

    async def subscribe_events(self) -> None:
        """Subscribe to all required i3 IPC events.

        This must be called AFTER connecting and BEFORE starting the main loop.
        """
        if not self.conn:
            logger.error("Cannot subscribe to events: not connected")
            return

        try:
            # Subscribe to all event types we'll be handling
            # This is required for i3ipc.aio - it's not automatic
            # IMPORTANT: Subscribe to generic events (WINDOW, WORKSPACE) not specific ones (WINDOW_NEW)!
            # i3ipc library dispatches to specific handlers (window::new, window::title) automatically
            from i3ipc import Event

            await self.conn.subscribe([
                Event.TICK,
                Event.WINDOW,      # Dispatches to window::new, window::title, window::focus, etc.
                Event.WORKSPACE,   # Dispatches to workspace::init, workspace::empty, etc.
                Event.OUTPUT,      # Dispatches to output::(added|removed|changed) - Feature 033
                Event.SHUTDOWN,
            ])

            logger.info("Subscribed to i3 IPC event stream (tick, window, workspace, output, shutdown)")

        except Exception as e:
            logger.error(f"Failed to subscribe to events: {e}")
            raise

    async def rebuild_state(self) -> None:
        """Rebuild daemon state from i3 tree marks.

        Called after connecting/reconnecting to i3.
        """
        if not self.conn:
            logger.error("Cannot rebuild state: not connected")
            return

        try:
            logger.info("Rebuilding state from i3 tree...")

            # Get entire window tree (async)
            tree = await self.conn.get_tree()

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

            # Get workspaces (async)
            workspaces = await self.conn.get_workspaces()

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

    async def handle_shutdown_event(self, conn: aio.Connection, event: IpcBaseEvent) -> None:
        """Handle i3 shutdown/restart events.

        Distinguishes between i3 restart (reconnect) vs exit (shutdown daemon).

        Args:
            conn: i3 async connection
            event: Shutdown event from i3
        """
        try:
            # Check shutdown type
            change = event.change

            if change == "restart":
                logger.info("i3 is restarting - will auto-reconnect")
                # i3ipc.aio auto_reconnect will handle this
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
        handler: Callable[[aio.Connection, IpcBaseEvent], Awaitable[None]],
    ) -> None:
        """Subscribe to i3 events with async handler.

        Args:
            event_type: Event type to subscribe to (window, workspace, tick, shutdown)
            handler: Async handler function for events
        """
        if not self.conn:
            logger.error("Cannot subscribe: not connected")
            return

        # Register handler for this event type
        # i3ipc.aio natively supports async handlers
        self.conn.on(event_type, handler)
        logger.debug(f"Registered handler for {event_type} events")

    async def main(self) -> None:
        """Run the i3 async event loop.

        This blocks until i3 connection is closed or daemon is shut down.
        """
        if not self.conn:
            logger.error("Cannot run main loop: not connected")
            return

        try:
            # Run i3 async main loop (native async, no executor needed)
            # This will process events until connection closes
            await self.conn.main()

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
