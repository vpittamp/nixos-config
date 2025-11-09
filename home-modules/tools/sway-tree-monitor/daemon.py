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
from typing import Optional, Dict

from i3ipc import aio
from i3ipc import Event

from .models import TreeSnapshot, WindowContext, UserAction, ActionType
from .diff.differ import TreeDiffer
from .buffer.event_buffer import TreeEventBuffer
from .rpc.server import RPCServer
from .correlation.tracker import CorrelationTracker
from .correlation.scoring import update_correlation_with_scoring
from .correlation.cascade import CascadeTracker


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
        self.correlation_tracker = CorrelationTracker(
            correlation_window_ms=500,
            retention_period_ms=5000
        )
        self.cascade_tracker = CascadeTracker(
            cascade_window_ms=500
        )
        self.rpc_server = RPCServer(
            socket_path=socket_path,
            event_buffer=self.buffer,
            differ=self.differ,
            daemon=self  # Pass daemon reference for sync marker access
        )

        self.connection: Optional[aio.Connection] = None
        self.previous_snapshot: Optional[TreeSnapshot] = None
        self._snapshot_counter = 0
        self._start_time = time.time()
        self._running = False

        # Sync marker tracking (Feature 069 - tick-event-based sync)
        self._pending_sync_markers: Dict[str, asyncio.Event] = {}
        self._sync_marker_lock = asyncio.Lock()

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
            # Register event handlers with .on()
            self._subscribe_to_events()
            # NOTE: Even though conn.on() may call ensure_future(subscribe()),
            # those are async tasks that may not execute before main() starts.
            # Explicitly subscribing ensures we're subscribed before the event
            # loop starts processing events. (Pattern from i3pm daemon line 465-469)
            await self.connection.subscribe(['window', 'workspace', 'binding', 'tick'])
            logger.info("Event handlers registered and explicitly subscribed")

            # Start RPC server
            await self.rpc_server.start()
            logger.info(f"RPC server listening on {self.rpc_server.socket_path}")

            # Start background tasks (Phase 6 - Performance)
            asyncio.create_task(self._periodic_cache_cleanup())
            asyncio.create_task(self._periodic_memory_monitor())
            logger.info("Background tasks started (cache cleanup, memory monitoring)")

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
        self.connection.on(Event.BINDING, self._on_binding_event)

        # Tick events (for sync marker support - Feature 069)
        self.connection.on(Event.TICK, self._on_tick_event)

    async def _on_window_event(self, connection: aio.Connection, event: Event):
        """Handle window events"""
        event_type = f"window::{event.change}"
        logger.info(f"Window event received: {event_type}")
        await self._process_tree_change(event_type, event)

    async def _on_workspace_event(self, connection: aio.Connection, event: Event):
        """Handle workspace events"""
        event_type = f"workspace::{event.change}"
        logger.info(f"Workspace event received: {event_type}")
        await self._process_tree_change(event_type, event)

    async def _on_binding_event(self, connection: aio.Connection, event: Event):
        """
        Handle binding events (user keypresses).

        This tracks user actions for correlation with tree changes.
        The action is stored with timestamp and will be matched with
        tree events that occur within 500ms.

        Args:
            connection: i3ipc connection
            event: Binding event with command, input_type, etc.
        """
        logger.info(f"Binding event received")
        try:
            # Extract binding info
            command = event.binding.command if hasattr(event, 'binding') else ""
            symbol = event.binding.symbol if hasattr(event, 'binding') else ""
            timestamp_ms = int(time.time() * 1000)

            # Infer action type from command
            action_type = self._infer_action_type(command)

            # Generate unique action ID (monotonic counter would be better, but this works)
            action_id = int(timestamp_ms * 1000)  # Microsecond precision

            # Create UserAction
            action = UserAction(
                action_id=action_id,
                timestamp_ms=timestamp_ms,
                action_type=action_type,
                binding_symbol=symbol,
                binding_command=command
            )

            # Track for correlation
            self.correlation_tracker.track_action(action)

            logger.debug(f"Tracked user action: {action_type.name} - {symbol} → {command}")

        except Exception as e:
            logger.error(f"Error handling binding event: {e}", exc_info=True)

    def _infer_action_type(self, command: str) -> ActionType:
        """
        Infer ActionType from Sway binding command.

        All Sway binding events return ActionType.BINDING.
        The specific command details are stored in the binding_command field.

        Args:
            command: Sway binding command

        Returns:
            ActionType.BINDING for all binding events
        """
        # All binding events use BINDING type
        # Command details are preserved in the UserAction.binding_command field
        return ActionType.BINDING

    async def _on_tick_event(self, connection: aio.Connection, event: Event):
        """
        Handle tick events (Feature 069 - sync marker support).

        Tick events are used for synchronization - when a sync marker is sent
        via `swaymsg -- tick <marker_id>`, Sway processes all pending commands
        and then sends this tick event with the marker_id as payload.

        This allows tests to wait for workspace assignments and other IPC
        commands to complete before checking state.

        Args:
            connection: i3ipc connection
            event: Tick event with payload containing marker ID
        """
        try:
            # Extract payload (marker ID)
            payload = event.payload if hasattr(event, 'payload') else ''

            if not payload:
                logger.debug("Received tick event with empty payload")
                return

            logger.debug(f"Tick event received: payload={payload}")

            # Check if this is a pending sync marker
            async with self._sync_marker_lock:
                if payload in self._pending_sync_markers:
                    # Signal the waiting task
                    event_obj = self._pending_sync_markers[payload]
                    event_obj.set()
                    logger.debug(f"Sync marker completed: {payload}")
                else:
                    logger.debug(f"Tick event payload not a pending sync marker: {payload}")

        except Exception as e:
            logger.error(f"Error handling tick event: {e}", exc_info=True)

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
        logger.info(f"Processing tree change: {event_type}")
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

            # Correlate with user actions
            # Find user actions that may have caused this event
            correlations = self.correlation_tracker.correlate_event(
                event_id=0,  # Will be assigned by buffer
                event_type=event_type,
                event_timestamp_ms=snapshot.timestamp_ms,
                affected_window_ids=None  # TODO: Extract from diff in Phase 5
            )

            # Check if this event is part of a cascade chain
            cascade_depth = self.cascade_tracker.add_to_cascade(
                event_id=0,  # Will be assigned by buffer
                event_timestamp_ms=snapshot.timestamp_ms
            )
            if cascade_depth is None:
                cascade_depth = 0  # Primary effect

            # Refine confidence scores using multi-factor scoring
            refined_correlations = []
            competing_actions = len(correlations) - 1  # Other correlations are competing
            for correlation in correlations:
                refined = update_correlation_with_scoring(
                    correlation=correlation,
                    event_type=event_type,
                    competing_actions=competing_actions,
                    cascade_depth=cascade_depth
                )
                refined_correlations.append(refined)

            # If this event has a high-confidence correlation, start a cascade chain
            if refined_correlations and refined_correlations[0].confidence >= 0.7:
                self.cascade_tracker.start_cascade(primary_event_id=0)  # Will be assigned by buffer

            # Create TreeEvent with correlations
            from .models import TreeEvent
            event = TreeEvent(
                event_id=0,  # Will be assigned by buffer
                timestamp_ms=snapshot.timestamp_ms,
                event_type=event_type,
                snapshot=snapshot,
                diff=diff,
                correlations=refined_correlations,
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

    def _enrich_window_contexts(self, tree_data: dict) -> dict:
        """
        Enrich window contexts with I3PM_* environment variables and marks.

        Traverses the tree, extracts window PIDs, reads /proc/<pid>/environ,
        and parses window marks for project associations.

        Args:
            tree_data: Raw Sway tree

        Returns:
            Dict[window_id, WindowContext] mapping
        """
        enriched_data = {}

        def traverse(node: dict):
            """Recursively traverse tree nodes"""
            node_type = node.get('type')

            # Process window nodes (con, floating_con)
            if node_type in ('con', 'floating_con'):
                window_id = node.get('id')
                pid = node.get('pid')

                if window_id and pid:
                    # Read environment variables
                    env_vars = self._read_window_environ(pid)

                    # Extract project marks
                    marks = node.get('marks', [])
                    project_marks, app_marks = self._extract_marks(marks)

                    # Create WindowContext
                    context = WindowContext(
                        window_id=window_id,
                        pid=pid,
                        i3pm_app_id=env_vars.get('I3PM_APP_ID'),
                        i3pm_app_name=env_vars.get('I3PM_APP_NAME'),
                        i3pm_project_name=env_vars.get('I3PM_PROJECT_NAME'),
                        i3pm_scope=env_vars.get('I3PM_SCOPE'),
                        project_marks=project_marks,
                        app_marks=app_marks
                    )

                    enriched_data[window_id] = context

            # Recurse into child nodes
            for child in node.get('nodes', []):
                traverse(child)
            for child in node.get('floating_nodes', []):
                traverse(child)

        traverse(tree_data)
        return enriched_data

    def _read_window_environ(self, pid: int) -> dict:
        """
        Read I3PM_* environment variables from process.

        Reads /proc/<pid>/environ and extracts I3PM_* variables.

        Args:
            pid: Process ID

        Returns:
            Dictionary of I3PM_* environment variables
        """
        env_vars = {}
        environ_path = Path(f'/proc/{pid}/environ')

        try:
            if environ_path.exists():
                # Read environ file (null-delimited)
                environ_data = environ_path.read_bytes()
                environ_str = environ_data.decode('utf-8', errors='ignore')

                # Split by null bytes
                for line in environ_str.split('\0'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        # Only store I3PM_* variables
                        if key.startswith('I3PM_'):
                            env_vars[key] = value

        except (FileNotFoundError, PermissionError, Exception) as e:
            # Process may have exited or no permissions
            logger.debug(f"Could not read environ for PID {pid}: {e}")

        return env_vars

    def _extract_marks(self, marks: list) -> tuple:
        """
        Extract project and app marks from window marks.

        Parses marks for patterns:
        - project:* → project marks
        - app:* → app marks

        Args:
            marks: List of window marks from Sway

        Returns:
            Tuple of (project_marks, app_marks)
        """
        project_marks = []
        app_marks = []

        for mark in marks:
            if mark.startswith('project:'):
                project_marks.append(mark)
            elif mark.startswith('app:'):
                app_marks.append(mark)

        return project_marks, app_marks

    async def _create_snapshot(self, tree_data: dict, event_source: str) -> TreeSnapshot:
        """
        Create TreeSnapshot from Sway tree with enriched context.

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

        # Enrich window contexts (Phase 5 - User Story 3)
        enriched_data = self._enrich_window_contexts(tree_data)

        # Create snapshot
        snapshot = TreeSnapshot(
            snapshot_id=self._snapshot_counter,
            timestamp_ms=int(time.time() * 1000),
            tree_data=tree_data,
            enriched_data=enriched_data,
            root_hash=root_hash,
            event_source=event_source
        )

        return snapshot

    async def _periodic_cache_cleanup(self):
        """
        Periodic cache cleanup task (Phase 6 - T053).

        Runs every 60 seconds to evict expired hash cache entries.
        """
        while self._running:
            try:
                await asyncio.sleep(60)  # 60 second interval

                if not self._running:
                    break

                # Clean up expired cache entries
                expired_count = self.differ.cleanup_cache()

                if expired_count > 0:
                    logger.debug(f"Cache cleanup: removed {expired_count} expired entries")

            except Exception as e:
                logger.error(f"Error in cache cleanup task: {e}", exc_info=True)

    async def _periodic_memory_monitor(self):
        """
        Periodic memory monitoring task (Phase 6 - T055).

        Logs memory usage every 5 minutes for performance tracking.
        """
        while self._running:
            try:
                await asyncio.sleep(300)  # 5 minute interval

                if not self._running:
                    break

                # Get memory usage
                import os
                import resource

                # Process memory (RSS in KB)
                rusage = resource.getrusage(resource.RUSAGE_SELF)
                memory_kb = rusage.ru_maxrss

                # Convert to MB
                memory_mb = memory_kb / 1024

                # Get component sizes
                buffer_stats = self.buffer.stats()
                differ_stats = self.differ.stats()
                correlation_stats = self.correlation_tracker.stats()

                logger.info(
                    f"Memory usage: {memory_mb:.1f}MB | "
                    f"Buffer: {buffer_stats['size']}/{buffer_stats['max_size']} | "
                    f"Cache: {differ_stats['cache']['size']} entries | "
                    f"Correlations: {correlation_stats['active_action_windows']} actions"
                )

                # Warn if exceeding target
                if memory_mb > 25:
                    logger.warning(
                        f"Memory usage ({memory_mb:.1f}MB) exceeds target (25MB)"
                    )

            except Exception as e:
                logger.error(f"Error in memory monitor task: {e}", exc_info=True)

    def get_status(self) -> dict:
        """
        Get daemon status with CPU/memory metrics (Phase 6 - T056).

        Returns:
            Dictionary with daemon metrics including performance data
        """
        import os
        import resource

        uptime = time.time() - self._start_time

        # Get memory usage (RSS in KB)
        rusage = resource.getrusage(resource.RUSAGE_SELF)
        memory_kb = rusage.ru_maxrss
        memory_mb = memory_kb / 1024

        # Get CPU times
        user_time = rusage.ru_utime  # User CPU time
        sys_time = rusage.ru_stime  # System CPU time
        total_cpu_time = user_time + sys_time

        # Calculate average CPU percentage
        cpu_percent = (total_cpu_time / uptime * 100) if uptime > 0 else 0.0

        return {
            'version': '1.0.0',
            'uptime_seconds': int(uptime),
            'running': self._running,
            'buffer': self.buffer.stats(),
            'differ': self.differ.stats(),
            'correlation_tracker': self.correlation_tracker.stats(),
            'cascade_tracker': self.cascade_tracker.stats(),
            'snapshots_captured': self._snapshot_counter,
            'performance': {
                'memory_mb': round(memory_mb, 2),
                'memory_kb': memory_kb,
                'cpu_percent': round(cpu_percent, 2),
                'user_cpu_seconds': round(user_time, 2),
                'system_cpu_seconds': round(sys_time, 2),
            }
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
