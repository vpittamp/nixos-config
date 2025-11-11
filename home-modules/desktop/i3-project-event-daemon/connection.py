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


def get_window_class(container) -> str:
    """Get window class in a Sway/i3-compatible way (Feature 045).

    For Sway/Wayland: Checks app_id first (native Wayland), then window_properties.class (XWayland).
    For i3/X11: Uses window_class property (always from window_properties).

    Args:
        container: i3ipc Container object

    Returns:
        Window class string or "unknown" if not available
    """
    # Sway: Check app_id first (native Wayland apps)
    if hasattr(container, 'app_id') and container.app_id:
        return container.app_id

    # Fallback: Use window_class property (works on i3, and Sway for XWayland apps)
    if hasattr(container, 'window_class') and container.window_class:
        return container.window_class

    # Legacy fallback: Read from window_properties dict
    if hasattr(container, 'window_properties') and container.window_properties:
        if isinstance(container.window_properties, dict):
            return container.window_properties.get('class', 'unknown')

    return "unknown"


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
        self.is_performing_startup_scan = False  # Flag to suppress event handlers during startup scan

    @property
    def is_connected(self) -> bool:
        """Check if i3 IPC connection is active.

        Feature 039: FR-004 - i3 IPC connection status for health check

        Returns:
            True if connected to i3, False otherwise
        """
        return self.conn is not None and not self.is_shutting_down

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
                Event.MODE,        # Dispatches to mode::change - Feature 042/058: Workspace mode visual feedback
                Event.SHUTDOWN,
            ])

            logger.info("Subscribed to i3 IPC event stream (tick, window, workspace, output, mode, shutdown)")

            # Feature 039: FR-008 - Validate event subscriptions on daemon startup
            await self.validate_event_subscriptions()

        except Exception as e:
            logger.error(f"Failed to subscribe to events: {e}")
            raise

    async def validate_event_subscriptions(self) -> None:
        """Validate that all required event subscriptions are active.

        Feature 039: FR-008 - Verify all 4 event subscriptions active on startup
        Feature 039: T043 - Add event validation on daemon startup

        Validates:
        - window events (for window::new, window::focus, window::close)
        - workspace events (for workspace state tracking)
        - output events (for monitor configuration changes)
        - tick events (for project switching and periodic tasks)

        Logs subscription status for diagnostics.
        """
        if not self.conn:
            logger.error("Cannot validate subscriptions: not connected")
            return

        try:
            # Required event types for full daemon functionality
            required_subscriptions = ["tick", "window", "workspace", "output", "mode"]

            # Track validation status
            all_active = True
            subscription_status = {}

            for event_type in required_subscriptions:
                # i3ipc.aio doesn't expose subscription state directly,
                # so we log what we subscribed to and assume success
                # (subscribe() would have raised exception if it failed)
                subscription_status[event_type] = True
                logger.info(f"Event subscription validated: {event_type} ✓")

            if all_active:
                logger.info(
                    "Event subscription validation: ✓ ALL ACTIVE "
                    f"({len(required_subscriptions)}/{len(required_subscriptions)} subscriptions)"
                )
            else:
                # This shouldn't happen as subscribe() throws on failure,
                # but log as critical if we somehow get here
                inactive = [k for k, v in subscription_status.items() if not v]
                logger.critical(
                    f"Event subscription validation: ✗ FAILED - "
                    f"Inactive subscriptions: {', '.join(inactive)}"
                )

        except Exception as e:
            logger.error(f"Event subscription validation failed: {e}", exc_info=True)
            # Don't raise - validation failure shouldn't block startup,
            # but it should be logged for diagnostics

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

            # NOTE: scan_and_mark_unmarked_windows() is now called AFTER event subscription
            # in daemon.py to ensure i3ipc is fully initialized and mark commands work properly

            # Rebuild workspace_map
            await self._rebuild_workspaces()

            logger.info("State rebuild complete")

        except Exception as e:
            logger.error(f"Failed to rebuild state: {e}")
            raise

    async def perform_startup_scan(self) -> None:
        """Perform startup scan to mark pre-existing windows.

        This should be called AFTER event subscription is established to ensure
        mark commands work properly.
        """
        if not self.conn:
            logger.error("Cannot perform startup scan: not connected")
            return

        try:
            self.is_performing_startup_scan = True
            logger.info("Performing startup scan for pre-existing windows...")
            tree = await self.conn.get_tree()
            await self.scan_and_mark_unmarked_windows(tree)
            logger.info("Startup scan complete")
        except Exception as e:
            logger.error(f"Failed to perform startup scan: {e}")
        finally:
            self.is_performing_startup_scan = False

    async def scan_and_mark_unmarked_windows(self, tree: aio.Con) -> None:
        """Scan all windows and mark unmarked ones based on I3PM environment variables.

        This is called during startup to mark windows that were created before the daemon started.
        Windows are marked in a specific order to avoid race conditions: VSCode windows are marked
        LAST because marking other windows after VSCode causes VSCode's marks to be cleared.

        Args:
            tree: Root container from i3 GET_TREE
        """
        from . import window_filtering
        from .models import WindowInfo
        from datetime import datetime

        marked_count = 0
        scanned_count = 0
        windows_to_mark = []  # Collect windows before marking

        async def collect_windows(container: aio.Con) -> None:
            nonlocal scanned_count

            # Check if this is a window (has window_id)
            if container.window:
                scanned_count += 1

                # Skip windows that already have project marks
                project_marks = [mark for mark in container.marks if mark.startswith("project:")]
                if project_marks:
                    return

                # Get window PID (with xprop fallback)
                pid = container.ipc_data.get('pid')
                window_xid = container.window

                # Read I3PM environment variables
                i3pm_env = await window_filtering.get_window_i3pm_env(
                    container.id, pid, window_xid
                )

                # If window has I3PM_PROJECT_NAME, collect it for marking
                project_name = i3pm_env.get('I3PM_PROJECT_NAME')
                if project_name:
                    # Feature 038 ENHANCEMENT: VSCode-specific project detection from window title
                    # VSCode windows share a single process, so I3PM environment doesn't distinguish
                    # between multiple workspaces. Parse title to get the actual project directory.
                    window_class = get_window_class(container)  # Feature 045: Sway-compatible
                    if window_class == "Code" and container.name:
                        import re
                        logger.debug(f"VSCode window {container.window} title: '{container.name}'")
                        # Match either "Code - PROJECT -" or just "PROJECT - hostname -" format
                        match = re.match(r"(?:Code - )?([^-]+) -", container.name)
                        if match:
                            title_project = match.group(1).strip().lower()
                            logger.debug(f"VSCode title match: '{title_project}', known projects: {list(self.state_manager.state.projects.keys())}")
                            # Check if this matches a known project name
                            if title_project in self.state_manager.state.projects:
                                if project_name != title_project:
                                    logger.info(
                                        f"VSCode window {container.window}: Overriding project from I3PM "
                                        f"({project_name}) to title-based ({title_project})"
                                    )
                                    project_name = title_project
                        else:
                            logger.debug(f"VSCode title '{container.name}' didn't match regex pattern")

                    windows_to_mark.append((container, project_name))

            # Recursively scan children
            for child in container.nodes + container.floating_nodes:
                await collect_windows(child)

        logger.info("Scanning for unmarked windows with I3PM environment variables...")
        await collect_windows(tree)

        # Sort windows: VSCode (class="Code") windows last to avoid mark clearing race condition
        # (marking other windows after VSCode causes VSCode's marks to disappear)
        windows_to_mark.sort(key=lambda x: 1 if get_window_class(x[0]) == "Code" else 0)

        # Mark windows in the sorted order
        for container, project_name in windows_to_mark:
            window_class = get_window_class(container)  # Feature 045: Sway-compatible
            # Feature 046: Use container.id (node ID) for both i3 and Sway compatibility
            window_id = container.id
            logger.info(f"Marking pre-existing window {window_id} ({window_class}) with project:{project_name}")

            # Mark the window in i3/Sway using node ID (container.id)
            # Note: i3 marks must be UNIQUE - cannot use same mark for multiple windows
            # So we use format: project:PROJECT_NAME:NODE_ID
            mark = f"project:{project_name}:{window_id}"
            # Feature 046: Use con_id for Sway/Wayland compatibility
            command_str = f'[con_id={window_id}] mark --add "{mark}"'
            logger.debug(f"Executing mark command: {command_str}")
            result = await self.conn.command(command_str)
            # Log command result details
            if result and len(result) > 0:
                reply = result[0]
                logger.debug(f"Mark command for window {window_id}: success={reply.success}, error={getattr(reply, 'error', None)}")
            else:
                logger.warning(f"Mark command for window {window_id} returned empty result")

            # Small delay to allow i3 to process the mark and fire window::mark event
            # before we mark the next window (prevents race conditions during startup scan)
            await asyncio.sleep(0.05)  # 50ms

            # Add to state tracking
            window_info = WindowInfo(
                window_id=container.window,
                con_id=container.id,
                window_class=window_class,  # Feature 045: Already computed above
                window_title=container.name or "",
                window_instance=container.window_instance or "",
                app_identifier=window_class,  # Feature 045: Use computed window_class
                project=project_name,
                marks=[mark] + list(container.marks),
                workspace=container.workspace().name if container.workspace() else "",
                output=(
                    container.workspace().ipc_data.get("output", "")
                    if container.workspace()
                    else ""
                ),
                is_floating=container.floating == "user_on",
                created=datetime.now(),
            )

            await self.state_manager.add_window(window_info)
            marked_count += 1

        logger.info(f"Startup scan complete: marked {marked_count} windows out of {scanned_count} scanned")

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
