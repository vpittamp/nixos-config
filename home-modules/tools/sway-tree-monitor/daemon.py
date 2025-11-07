"""Sway Tree Diff Monitor Daemon

Background daemon that monitors Sway tree changes, computes diffs,
and serves data via JSON-RPC 2.0.

Performance targets:
- <10ms diff computation (p95)
- <25MB memory usage
- <2% CPU usage average
"""

import asyncio
import logging
import sys
import time
from pathlib import Path
from typing import Optional

from i3ipc import aio
from i3ipc import Event

from .models import TreeSnapshot, WindowContext
from .diff.differ import TreeDiffer
from .buffer.event_buffer import TreeEventBuffer
from .rpc.server import RPCServer


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SwayTreeMonitorDaemon:
    """
    Main daemon for Sway tree diff monitoring.

    Responsibilities:
    - Subscribe to Sway events
    - Capture tree snapshots
    - Compute tree diffs
    - Store events in circular buffer
    - Serve data via JSON-RPC
    """

    def __init__(
        self,
        buffer_size: int = 500,
        socket_path: Optional[Path] = None,
        persistence_dir: Optional[Path] = None
    ):
        """
        Initialize daemon.

        Args:
            buffer_size: Maximum events in circular buffer (default: 500)
            socket_path: Unix socket path for RPC server
            persistence_dir: Directory for event persistence
        """
        self.buffer = TreeEventBuffer(
            max_size=buffer_size,
            persistence_dir=persistence_dir
        )
        self.differ = TreeDiffer()
        self.rpc_server = RPCServer(
            socket_path=socket_path,
            event_buffer=self.buffer,
            differ=self.differ
        )

        self.connection: Optional[aio.Connection] = None
        self.previous_snapshot: Optional[TreeSnapshot] = None
        self._snapshot_counter = 0
        self._start_time = time.time()
        self._running = False

    async def start(self):
        """
        Start the daemon.

        - Connects to Sway IPC
        - Subscribes to events
        - Starts RPC server
        - Enters main event loop
        """
        logger.info("Starting Sway Tree Monitor Daemon")

        try:
            # Connect to Sway
            self.connection = await aio.Connection(auto_reconnect=True).connect()
            logger.info("Connected to Sway IPC")

            # Capture initial snapshot
            await self._capture_initial_snapshot()

            # Subscribe to Sway events
            self._subscribe_to_events()
            logger.info("Subscribed to Sway events")

            # Start RPC server
            await self.rpc_server.start()
            logger.info(f"RPC server listening on {self.rpc_server.socket_path}")

            # Mark as running
            self._running = True
            logger.info("Daemon started successfully")

            # Enter main event loop
            await self.connection.main()

        except Exception as e:
            logger.error(f"Fatal error in daemon: {e}", exc_info=True)
            raise

    async def stop(self):
        """Graceful shutdown"""
        logger.info("Stopping daemon...")
        self._running = False

        # Stop RPC server
        await self.rpc_server.stop()

        # Optionally persist buffer
        if self.buffer.persistence_dir:
            await self.buffer.save_to_disk()
            logger.info("Buffer persisted to disk")

        logger.info("Daemon stopped")

    async def _capture_initial_snapshot(self):
        """Capture initial tree state on startup"""
        tree = await self.connection.get_tree()
        # Convert Con object to dict
        tree_dict = tree.ipc_data
        snapshot = await self._create_snapshot(tree_dict, "daemon::startup")
        self.previous_snapshot = snapshot
        logger.info(f"Captured initial snapshot (ID: {snapshot.snapshot_id})")

    def _subscribe_to_events(self):
        """Subscribe to relevant Sway events"""
        # Window events
        self.connection.on(Event.WINDOW_NEW, self._on_window_event)
        self.connection.on(Event.WINDOW_CLOSE, self._on_window_event)
        self.connection.on(Event.WINDOW_FOCUS, self._on_window_event)
        self.connection.on(Event.WINDOW_MOVE, self._on_window_event)

        # Workspace events
        self.connection.on(Event.WORKSPACE_FOCUS, self._on_workspace_event)
        self.connection.on(Event.WORKSPACE_INIT, self._on_workspace_event)
        self.connection.on(Event.WORKSPACE_EMPTY, self._on_workspace_event)

        # Binding events (for user action correlation - User Story 2)
        # self.connection.on(Event.BINDING, self._on_binding_event)  # TODO: Phase 4

    async def _on_window_event(self, connection: aio.Connection, event: Event):
        """Handle window events"""
        event_type = f"window::{event.change}"
        await self._process_tree_change(event_type, event)

    async def _on_workspace_event(self, connection: aio.Connection, event: Event):
        """Handle workspace events"""
        event_type = f"workspace::{event.change}"
        await self._process_tree_change(event_type, event)

    async def _process_tree_change(self, event_type: str, sway_event: Event):
        """
        Process a tree change event.

        Core workflow:
        1. Capture new tree snapshot
        2. Compute diff from previous snapshot
        3. Create TreeEvent
        4. Store in buffer

        Args:
            event_type: Formatted event type (e.g., "window::new")
            sway_event: Raw Sway event
        """
        try:
            start_time = time.time()

            # Get current tree
            tree = await self.connection.get_tree()
            # Convert Con object to dict
            tree_dict = tree.ipc_data

            # Create snapshot
            snapshot = await self._create_snapshot(tree_dict, event_type)

            # Compute diff
            if self.previous_snapshot:
                diff = self.differ.compute_diff(self.previous_snapshot, snapshot)
            else:
                # First event, no previous snapshot
                # Create empty diff
                from .models import TreeDiff
                diff = TreeDiff(
                    diff_id=0,
                    before_snapshot_id=0,
                    after_snapshot_id=snapshot.snapshot_id,
                    node_changes=[],
                    computation_time_ms=0.0
                )

            # Create TreeEvent
            # Note: Correlation will be added in Phase 4 (User Story 2)
            from .models import TreeEvent
            event = TreeEvent(
                event_id=0,  # Will be assigned by buffer
                timestamp_ms=snapshot.timestamp_ms,
                event_type=event_type,
                snapshot=snapshot,
                diff=diff,
                correlations=[],  # TODO: Phase 4
                sway_change=sway_event.change if hasattr(sway_event, 'change') else '',
                container_id=sway_event.container.id if hasattr(sway_event, 'container') else None
            )

            # Store in buffer
            await self.buffer.add_event(event)

            # Update previous snapshot
            self.previous_snapshot = snapshot

            # Log performance
            total_time_ms = (time.time() - start_time) * 1000
            logger.debug(
                f"Processed {event_type}: "
                f"diff={diff.computation_time_ms:.2f}ms, "
                f"total={total_time_ms:.2f}ms, "
                f"changes={diff.total_changes}"
            )

        except Exception as e:
            logger.error(f"Error processing tree change: {e}", exc_info=True)

    async def _create_snapshot(self, tree_data: dict, event_source: str) -> TreeSnapshot:
        """
        Create TreeSnapshot from Sway tree.

        Args:
            tree_data: Raw tree from i3ipc
            event_source: Event type that triggered this snapshot

        Returns:
            TreeSnapshot with enriched data
        """
        from .diff.hasher import compute_tree_hash
        import time

        self._snapshot_counter += 1

        # Compute root hash
        root_hash = compute_tree_hash(tree_data)

        # Create snapshot
        # Note: Enrichment (I3PM_* env vars) will be added in Phase 5 (User Story 3)
        snapshot = TreeSnapshot(
            snapshot_id=self._snapshot_counter,
            timestamp_ms=int(time.time() * 1000),
            tree_data=tree_data,
            enriched_data={},  # TODO: Phase 5
            root_hash=root_hash,
            event_source=event_source
        )

        return snapshot

    def get_status(self) -> dict:
        """
        Get daemon status.

        Returns:
            Dictionary with daemon metrics
        """
        uptime = time.time() - self._start_time

        return {
            'version': '1.0.0',
            'uptime_seconds': int(uptime),
            'running': self._running,
            'buffer': self.buffer.stats(),
            'differ': self.differ.stats(),
            'snapshots_captured': self._snapshot_counter,
        }


async def main():
    """
    Main entry point for daemon.

    Usage:
        python -m sway_tree_monitor.daemon
    """
    import os

    # Determine socket path
    runtime_dir = os.getenv('XDG_RUNTIME_DIR', '/run/user/1000')
    socket_path = Path(runtime_dir) / 'sway-tree-monitor.sock'

    # Determine persistence directory
    data_home = os.getenv('XDG_DATA_HOME', Path.home() / '.local' / 'share')
    persistence_dir = Path(data_home) / 'sway-tree-monitor'

    # Create daemon
    daemon = SwayTreeMonitorDaemon(
        buffer_size=500,
        socket_path=socket_path,
        persistence_dir=persistence_dir
    )

    # Handle shutdown signals
    import signal

    def signal_handler(sig, frame):
        logger.info(f"Received signal {sig}, shutting down...")
        asyncio.create_task(daemon.stop())

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start daemon
    try:
        await daemon.start()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.error(f"Daemon failed: {e}", exc_info=True)
        sys.exit(1)
    finally:
        await daemon.stop()


if __name__ == '__main__':
    asyncio.run(main())
