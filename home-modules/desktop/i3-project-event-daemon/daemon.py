"""Main daemon entry point with systemd integration.

This module provides the main event loop and systemd integration
(sd_notify, watchdog, journald logging).
"""

import asyncio
import contextlib
import logging
import os
import signal
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List

try:
    from systemd import journal, daemon as sd_daemon
    SYSTEMD_AVAILABLE = True
except ImportError:
    SYSTEMD_AVAILABLE = False
    print("Warning: systemd-python not available, running without systemd integration", file=sys.stderr)

from .config import (
    load_project_configs,
    load_app_classification,
    load_application_registry,  # Feature 037 T027
    load_active_project,
    reload_window_rules,
    WindowRulesWatcher,
    OutputStatesWatcher,
    MonitorProfileWatcher,  # Feature 083: Profile file watcher
)
from .output_state_manager import (
    load_output_states,
    initialize_output_states,
    OUTPUT_STATES_PATH,
)
from .state import StateManager
from .connection import ResilientI3Connection
from .ipc_server import IPCServer
from .event_buffer import EventBuffer
from .window_rules import WindowRule
from .models import EventEntry
from .handlers import (
    on_tick,
    on_window_new,
    on_window_mark,
    on_window_close,
    on_window_focus,
    on_window_move,  # Feature 037 T020: Window move tracking
    on_window_title,
    on_workspace_init,
    on_workspace_empty,
    on_workspace_move,
    on_workspace_focus,  # Feature 074 T026: Workspace focus tracking
    on_output,  # Feature 024: R013
    on_mode,  # Feature 042: Workspace mode navigation
)
from .proc_monitor import ProcessMonitor  # Feature 029: Process monitoring
from .window_filtering import WorkspaceTracker  # Feature 037: Window filtering
from .services.scratchpad_manager import ScratchpadManager  # Feature 062: Scratchpad terminals
from .services.run_raise_manager import RunRaiseManager  # Feature 051: Run-raise-hide launching
from .services.mark_manager import MarkManager  # Feature 076: Mark-based app identification
from .services.tree_cache import initialize_tree_cache  # Feature 091: Tree caching
from .services.performance_tracker import initialize_performance_tracker  # Feature 091: Performance tracking
from .monitor_profile_service import MonitorProfileService  # Feature 083: Monitor profile management
from .eww_publisher import EwwPublisher  # Feature 083: Eww real-time updates
from .monitoring_panel_publisher import MonitoringPanelPublisher  # Feature 085: Monitoring panel updates
from datetime import datetime
import time

# Configure logging
logger = logging.getLogger(__name__)


@contextlib.contextmanager
def _suppress_stderr_fd():
    """Context manager to suppress stderr at the file descriptor level.

    This is needed because systemd-python writes directly to file descriptor 2 (stderr),
    bypassing Python's sys.stderr. The "no running event loop" warnings come from
    systemd-python's internal checks that write to C stderr.
    """
    # Save original stderr FD
    stderr_fd = sys.stderr.fileno()
    saved_stderr_fd = os.dup(stderr_fd)

    # Redirect stderr to /dev/null
    devnull_fd = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull_fd, stderr_fd)
    os.close(devnull_fd)

    try:
        yield
    finally:
        # Restore original stderr
        os.dup2(saved_stderr_fd, stderr_fd)
        os.close(saved_stderr_fd)


class DaemonHealthMonitor:
    """Manages systemd health notifications and watchdog pings."""

    def __init__(self) -> None:
        """Initialize health monitor."""
        self.watchdog_task: Optional[asyncio.Task] = None
        self.watchdog_interval: Optional[float] = None
        self._setup_watchdog()

    def _setup_watchdog(self) -> None:
        """Detect watchdog interval from systemd environment."""
        if not SYSTEMD_AVAILABLE:
            return

        # Get watchdog interval from systemd
        watchdog_usec = os.environ.get("WATCHDOG_USEC")
        if watchdog_usec:
            # Convert microseconds to seconds, ping at 1/3 interval for safety
            # CRITICAL FIX: Changed from 1/2 to 1/3 for better safety margin
            # If systemd expects ping every 20s, we ping every ~6.7s (3x buffer)
            self.watchdog_interval = int(watchdog_usec) / 3_000_000
            logger.info(f"Systemd watchdog enabled: {self.watchdog_interval:.1f}s interval (1/3 of timeout)")
        else:
            logger.debug("Systemd watchdog not configured")

    def notify_ready(self) -> None:
        """Send READY=1 signal to systemd."""
        if SYSTEMD_AVAILABLE:
            # Suppress stderr warnings from systemd.daemon.notify() at FD level
            with _suppress_stderr_fd():
                sd_daemon.notify("READY=1")
            logger.info("Sent READY=1 to systemd")
        else:
            logger.debug("Systemd not available, skipping READY notification")

    def notify_watchdog(self) -> None:
        """Send WATCHDOG=1 ping to systemd."""
        if SYSTEMD_AVAILABLE:
            # Suppress stderr warnings from systemd.daemon.notify() at FD level
            with _suppress_stderr_fd():
                sd_daemon.notify("WATCHDOG=1")
            logger.debug("Sent WATCHDOG=1 ping")

    def notify_stopping(self) -> None:
        """Send STOPPING=1 signal to systemd."""
        if SYSTEMD_AVAILABLE:
            # Suppress stderr warnings from systemd.daemon.notify() at FD level
            with _suppress_stderr_fd():
                sd_daemon.notify("STOPPING=1")
            logger.info("Sent STOPPING=1 to systemd")

    async def watchdog_loop(self) -> None:
        """Background task that sends watchdog pings."""
        if not self.watchdog_interval:
            logger.debug("Watchdog not enabled, skipping watchdog loop")
            return

        logger.info(f"Starting watchdog loop (interval: {self.watchdog_interval}s)")

        while True:
            await asyncio.sleep(self.watchdog_interval)
            self.notify_watchdog()


class I3ProjectDaemon:
    """Main daemon class."""

    def __init__(self) -> None:
        """Initialize daemon."""
        self.config_dir = Path.home() / ".config" / "i3"
        self.state_manager: Optional[StateManager] = None
        self.connection: Optional[ResilientI3Connection] = None
        self.ipc_server: Optional[IPCServer] = None
        self.event_buffer: Optional[EventBuffer] = None  # Feature 017: Event storage
        self.health_monitor: Optional[DaemonHealthMonitor] = None
        self.shutdown_event = asyncio.Event()
        self.window_rules: List[WindowRule] = []  # Feature 021: Window rules cache
        self.rules_watcher: Optional[WindowRulesWatcher] = None  # Feature 021: File watcher
        self.output_states_watcher: Optional[OutputStatesWatcher] = None  # Output states file watcher
        self.proc_monitor: Optional[Any] = None  # Feature 029: Process monitoring
        self.application_registry: Dict[str, Dict] = {}  # Feature 037 T027: Application registry
        self.scratchpad_manager: Optional[ScratchpadManager] = None  # Feature 062: Scratchpad terminal manager
        self.mark_manager: Optional[MarkManager] = None  # Feature 076: Mark-based app identification
        self.monitor_profile_service: Optional[MonitorProfileService] = None  # Feature 083: Monitor profile management
        self.eww_publisher: Optional[EwwPublisher] = None  # Feature 083: Eww real-time updates
        self.monitoring_panel_publisher: Optional[MonitoringPanelPublisher] = None  # Feature 085: Monitoring panel updates
        self.monitor_profile_watcher: Optional[MonitorProfileWatcher] = None  # Feature 083: Profile file watcher
        self.tree_cache: Optional[Any] = None  # Feature 091: Tree cache service
        self.performance_tracker: Optional[Any] = None  # Feature 091: Performance tracker

    async def initialize(self) -> None:
        """Initialize daemon components."""
        start_time = time.perf_counter()
        logger.info("Initializing i3 project event daemon...")

        # Create state manager
        self.state_manager = StateManager()

        # Feature 037: Initialize workspace tracker for window filtering
        self.workspace_tracker = WorkspaceTracker()
        await self.workspace_tracker.load()
        logger.info("Workspace tracker initialized")

        # Create IPC server first (needed for event buffer callback)
        # Pass window_rules_getter for Feature 021: T025, T026
        # Pass workspace_tracker for Feature 037: Window filtering
        self.ipc_server = await IPCServer.from_systemd_socket(
            self.state_manager,
            event_buffer=None,
            window_rules_getter=lambda: self.window_rules,
            workspace_tracker=self.workspace_tracker
        )

        # Create event buffer with broadcast callback (Feature 017: T019)
        self.event_buffer = EventBuffer(max_size=500, broadcast_callback=self.ipc_server.broadcast_event_entry)
        logger.info("Event buffer initialized (500 events)")

        # Update IPC server with event buffer
        self.ipc_server.event_buffer = self.event_buffer

        # Load project configurations
        projects_dir = self.config_dir / "projects"
        projects = load_project_configs(projects_dir)
        self.state_manager.state.projects = projects
        logger.info(f"Loaded {len(projects)} project(s)")

        # Load application classification
        app_classes_file = self.config_dir / "app-classes.json"
        try:
            app_classification = load_app_classification(app_classes_file)
            self.state_manager.state.scoped_classes = app_classification.scoped_classes
            self.state_manager.state.global_classes = app_classification.global_classes
        except Exception as e:
            logger.error(f"Failed to load application classification: {e}")
            # Use defaults
            self.state_manager.state.scoped_classes = {"Code", "ghostty", "Alacritty", "Yazi"}
            self.state_manager.state.global_classes = {"firefox", "chromium-browser", "k9s"}

        # Feature 037 T027: Load application registry for workspace assignment
        app_registry_file = self.config_dir / "application-registry.json"
        self.application_registry = load_application_registry(app_registry_file)
        logger.info(f"Application registry loaded: {len(self.application_registry)} applications")

        # Load active project state
        active_project_file = self.config_dir / "active-project.json"
        active_state = load_active_project(active_project_file)
        if active_state:
            await self.state_manager.set_active_project(active_state.project_name)

        # Create connection manager
        self.connection = ResilientI3Connection(self.state_manager)

        # Connect to i3 with retry
        try:
            connect_start = time.perf_counter()
            await self.connection.connect_with_retry(max_attempts=10)
            self.state_manager.state.is_connected = True

            # Feature 037: Run garbage collection on workspace tracker
            if self.workspace_tracker:
                cleanup_count = await self.workspace_tracker.cleanup_stale_entries(
                    self.connection.conn, max_age_days=30
                )
                logger.info(f"Workspace tracker cleanup: {cleanup_count} stale entries removed")

            # Log daemon::connect event (unified event system)
            connect_duration_ms = (time.perf_counter() - connect_start) * 1000
            if self.event_buffer:
                i3_socket = os.environ.get("I3SOCK", "auto-detected")
                entry = EventEntry(
                    event_id=self.event_buffer.event_counter,
                    event_type="daemon::connect",
                    timestamp=datetime.now(),
                    source="daemon",
                    i3_socket=i3_socket,
                    processing_duration_ms=connect_duration_ms,
                )
                await self.event_buffer.add_event(entry)
                logger.info(f"Logged daemon::connect event (duration: {connect_duration_ms:.2f}ms)")
        except ConnectionError as e:
            logger.error(f"Failed to connect to i3: {e}")
            raise

        # NOTE: We DO NOT call subscribe_events() here!
        # i3ipc.aio.Connection.on() automatically subscribes to base events
        # when you register handlers (it extracts "window" from "window::new" and subscribes).
        # Calling subscribe() manually can cause conflicts.

        # Update IPC server with i3 connection (Feature 018)
        self.ipc_server.i3_connection = self.connection
        logger.info("IPC server updated with i3 connection")

        # Feature 091: Initialize tree cache and performance tracker
        self.tree_cache = initialize_tree_cache(self.connection.conn, ttl_ms=100.0)
        self.performance_tracker = initialize_performance_tracker(max_history=100, target_ms=200.0)
        logger.info("[Feature 091] Tree cache and performance tracker initialized")

        # Feature 042: Initialize workspace mode manager
        from .workspace_mode import WorkspaceModeManager
        self.workspace_mode_manager = WorkspaceModeManager(
            self.connection.conn,
            config_dir=self.config_dir,
            state_manager=self.state_manager,
            workspace_tracker=self.workspace_tracker,
            ipc_server=self.ipc_server  # Feature 058: IPC event broadcasting
        )
        self.state_manager.workspace_mode_manager = self.workspace_mode_manager
        logger.info("Workspace mode manager initialized")

        # Feature 062: Initialize scratchpad manager
        self.scratchpad_manager = ScratchpadManager(self.connection.conn)
        self.ipc_server.scratchpad_manager = self.scratchpad_manager
        logger.info("Scratchpad manager initialized")

        # Feature 051: Initialize run-raise manager
        self.run_raise_manager = RunRaiseManager(
            sway=self.connection.conn,
            workspace_tracker=self.workspace_tracker
        )
        self.ipc_server.run_raise_manager = self.run_raise_manager
        logger.info("Run-raise manager initialized")

        # Feature 076: Initialize mark manager
        self.mark_manager = MarkManager(self.connection.conn)
        self.ipc_server.mark_manager = self.mark_manager
        logger.info("Mark manager initialized")

        # Feature 083/084: Initialize EwwPublisher and MonitorProfileService
        self.eww_publisher = EwwPublisher()
        self.monitor_profile_service = MonitorProfileService(self.eww_publisher)
        profile_count = len(self.monitor_profile_service.list_profiles())
        if self.monitor_profile_service.is_hybrid_mode:
            logger.info(f"Feature 084: Monitor profile service initialized in hybrid mode with {profile_count} profiles")
        else:
            logger.info(f"Monitor profile service initialized with {profile_count} profiles")

        # Feature 085: Initialize MonitoringPanelPublisher
        self.monitoring_panel_publisher = MonitoringPanelPublisher()
        logger.info("Feature 085: Monitoring panel publisher initialized")

        # Feature 083: Setup monitor profile file watcher (T024)
        # Watches monitor-profile.current and triggers Eww updates on profile change
        from .monitor_profile_service import CURRENT_PROFILE_FILE

        def on_profile_change():
            """Callback for monitor-profile.current file changes."""
            logger.info("[Feature 083] Profile file changed, triggering profile switch handling")
            # Reload profile and schedule async profile change handling
            self.monitor_profile_service.reload_profiles()
            new_profile = self.monitor_profile_service.get_current_profile()
            loop = asyncio.get_event_loop()
            if self.connection and self.connection.conn and new_profile:
                # Use handle_profile_change which updates output-states.json and Eww
                loop.create_task(self._handle_profile_file_change(new_profile))

        async def async_handle_profile_change(profile_name: str):
            """Async wrapper for profile change handling."""
            if self.monitor_profile_service and self.connection:
                await self.monitor_profile_service.handle_profile_change(
                    self.connection.conn,
                    profile_name
                )

        # Store for later use in callback
        self._handle_profile_file_change = async_handle_profile_change

        self.monitor_profile_watcher = MonitorProfileWatcher(
            config_file=CURRENT_PROFILE_FILE,
            reload_callback=on_profile_change,
            debounce_ms=100  # Fast response for UI updates
        )
        self.monitor_profile_watcher.set_event_loop(asyncio.get_event_loop())
        self.monitor_profile_watcher.start()

        # Setup health monitor
        self.health_monitor = DaemonHealthMonitor()

        # Load window rules (Feature 021: T022)
        window_rules_file = self.config_dir / "window-rules.json"
        try:
            self.window_rules = reload_window_rules(window_rules_file)
            logger.info(f"Loaded {len(self.window_rules)} window rule(s)")
        except Exception as e:
            logger.warning(f"Failed to load window rules: {e}")
            self.window_rules = []

        # Setup window rules file watcher (Feature 021: T022)
        def on_rules_reload():
            """Callback for window rules file changes."""
            self.window_rules = reload_window_rules(window_rules_file, self.window_rules)

        self.rules_watcher = WindowRulesWatcher(
            config_file=window_rules_file,
            reload_callback=on_rules_reload,
            debounce_ms=100
        )
        # Set event loop for async debouncing
        self.rules_watcher.set_event_loop(asyncio.get_event_loop())
        # Start watching
        self.rules_watcher.start()

        # Setup output states file watcher
        # When output-states.json changes, trigger workspace reassignment
        def on_output_states_change():
            """Callback for output states file changes."""
            logger.info("Output states file changed, triggering workspace reassignment")
            # Schedule async workspace reassignment
            loop = asyncio.get_event_loop()
            if self.connection and self.connection.conn:
                loop.create_task(self._trigger_output_state_change())

        self.output_states_watcher = OutputStatesWatcher(
            config_file=OUTPUT_STATES_PATH,
            reload_callback=on_output_states_change,
            debounce_ms=200  # Slightly longer debounce for state file changes
        )
        self.output_states_watcher.set_event_loop(asyncio.get_event_loop())
        self.output_states_watcher.start()

        # Initialize output states file with current outputs
        if self.connection and self.connection.conn:
            try:
                outputs = await self.connection.conn.get_outputs()
                output_names = [o.name for o in outputs if o.active]
                initialize_output_states(output_names)
                logger.info(f"Initialized output states for {len(output_names)} outputs")
            except Exception as e:
                logger.warning(f"Failed to initialize output states: {e}")

        # Feature 029: T033 - Initialize process monitor
        self.proc_monitor = ProcessMonitor(poll_interval=0.5)
        logger.info("Process monitor initialized")

        logger.info("Daemon initialization complete")

        # Log daemon::start event (unified event system)
        duration_ms = (time.perf_counter() - start_time) * 1000
        if self.event_buffer:
            entry = EventEntry(
                event_id=self.event_buffer.event_counter,
                event_type="daemon::start",
                timestamp=datetime.now(),
                source="daemon",
                daemon_version="1.0.0",  # TODO: Get from package metadata
                processing_duration_ms=duration_ms,
            )
            await self.event_buffer.add_event(entry)
            logger.info(f"Logged daemon::start event (duration: {duration_ms:.2f}ms)")

    async def _trigger_output_state_change(self) -> None:
        """Trigger workspace reassignment after output states file change.

        This is called when output-states.json is modified (e.g., by toggle-output.sh).
        It performs the same workspace reassignment as the on_output handler.

        Feature 083: Also publishes to Eww for real-time top bar updates.
        """
        from .workspace_manager import assign_workspaces_with_monitor_roles

        if not self.connection or not self.connection.conn:
            logger.warning("Cannot trigger output state change: not connected")
            return

        try:
            # Get current outputs and enabled states
            outputs = await self.connection.conn.get_outputs()
            states = load_output_states()

            # Filter to only enabled outputs
            enabled_outputs = [
                o for o in outputs
                if o.active and states.is_output_enabled(o.name)
            ]

            enabled_count = len(enabled_outputs)
            total_count = len([o for o in outputs if o.active])
            enabled_names = [o.name for o in enabled_outputs]

            logger.info(
                f"Output state change detected: {enabled_count}/{total_count} outputs enabled"
            )

            # Use Feature 001's monitor role-based workspace assignment
            # This uses workspace-assignments.json instead of legacy workspace-monitor-mapping.json
            await assign_workspaces_with_monitor_roles(self.connection.conn)

            # Feature 083: Publish to Eww for real-time top bar updates
            if self.eww_publisher:
                profile_name = self.monitor_profile_service.get_current_profile() if self.monitor_profile_service else "unknown"
                await self.eww_publisher.publish_from_conn(
                    self.connection.conn,
                    profile_name or "unknown",
                    enabled_names
                )
                logger.info(f"[Feature 083] Published monitor state to Eww: profile={profile_name}, outputs={enabled_names}")

            # Log event
            if self.event_buffer:
                entry = EventEntry(
                    event_id=self.event_buffer.event_counter,
                    event_type="output::state_change",
                    timestamp=datetime.now(),
                    source="daemon",
                    output_count=enabled_count,
                )
                await self.event_buffer.add_event(entry)

        except Exception as e:
            logger.error(f"Failed to trigger output state change: {e}")

    async def register_event_handlers(self) -> None:
        """Register all i3 event handlers."""
        if not self.connection or not self.connection.conn:
            logger.error("Cannot register handlers: not connected")
            return

        logger.info("Registering event handlers...")

        # Get application classification for handlers
        from .models import ApplicationClassification
        from functools import partial

        app_classification = ApplicationClassification(
            scoped_classes=self.state_manager.state.scoped_classes,
            global_classes=self.state_manager.state.global_classes,
        )

        # Register handlers with partial application to bind extra arguments
        # i3ipc.aio will call these with (conn, event) and they'll forward to our handlers

        # USER STORY 1: Project switching via tick events
        # Feature 037: Pass workspace_tracker for window filtering
        self.connection.subscribe(
            "tick",
            partial(on_tick, state_manager=self.state_manager, config_dir=self.config_dir, event_buffer=self.event_buffer, workspace_tracker=self.workspace_tracker)
        )

        # USER STORY 2: Automatic window tracking (Feature 021: T023 - pass window_rules getter)
        # Use wrappers to get current window_rules (updated by file watcher)
        # CRITICAL: Wrappers must be async to await the async handlers!
        async def get_window_rules_wrapper_new(conn, event):
            """Wrapper to pass current window_rules to window::new handler."""
            return await on_window_new(
                conn, event,
                state_manager=self.state_manager,
                app_classification=app_classification,
                event_buffer=self.event_buffer,
                window_rules=self.window_rules,  # Gets current value from daemon
                ipc_server=self.ipc_server,  # Feature 025: broadcast events to subscribed clients
                application_registry=self.application_registry,  # Feature 037 T026: Workspace assignment
                workspace_tracker=self.workspace_tracker,  # Feature 037 T026: Track initial assignment
                mark_manager=self.mark_manager  # Feature 076: Mark-based app identification
            )

        async def get_window_rules_wrapper_title(conn, event):
            """Wrapper to pass current window_rules to window::title handler."""
            return await on_window_title(
                conn, event,
                state_manager=self.state_manager,
                app_classification=app_classification,
                event_buffer=self.event_buffer,
                window_rules=self.window_rules,  # Gets current value from daemon
                ipc_server=self.ipc_server  # Feature 025: broadcast events to subscribed clients
            )

        self.connection.subscribe("window::new", get_window_rules_wrapper_new)
        self.connection.subscribe(
            "window::mark",
            partial(on_window_mark, state_manager=self.state_manager, event_buffer=self.event_buffer, ipc_server=self.ipc_server, resilient_connection=self.connection)
        )
        self.connection.subscribe(
            "window::close",
            partial(on_window_close, state_manager=self.state_manager, event_buffer=self.event_buffer, ipc_server=self.ipc_server, mark_manager=self.mark_manager)  # Feature 076: T033
        )
        self.connection.subscribe(
            "window::focus",
            partial(on_window_focus, state_manager=self.state_manager, event_buffer=self.event_buffer, ipc_server=self.ipc_server)
        )

        # Feature 037 T020: Window move tracking for workspace persistence
        self.connection.subscribe(
            "window::move",
            partial(on_window_move, state_manager=self.state_manager, workspace_tracker=self.workspace_tracker, event_buffer=self.event_buffer, ipc_server=self.ipc_server)
        )

        # USER STORY 2: Title change re-classification (T033)
        self.connection.subscribe("window::title", get_window_rules_wrapper_title)

        # Feature 085: Monitoring panel event-driven updates (T020)
        # Subscribe to window events for monitoring panel state updates
        async def publish_monitoring_panel_update(conn, event):
            """Publish monitoring panel state on window events."""
            if self.monitoring_panel_publisher:
                await self.monitoring_panel_publisher.publish(conn)

        self.connection.subscribe("window::new", publish_monitoring_panel_update)
        self.connection.subscribe("window::close", publish_monitoring_panel_update)
        self.connection.subscribe("window::move", publish_monitoring_panel_update)
        self.connection.subscribe("window::floating", publish_monitoring_panel_update)
        logger.info("Feature 085: Monitoring panel subscribed to window events")

        # USER STORY 3: Workspace monitoring
        self.connection.subscribe(
            "workspace::init",
            partial(on_workspace_init, state_manager=self.state_manager)
        )
        self.connection.subscribe(
            "workspace::empty",
            partial(on_workspace_empty, state_manager=self.state_manager)
        )
        self.connection.subscribe(
            "workspace::move",
            partial(on_workspace_move, state_manager=self.state_manager)
        )
        # Feature 074: Session Management - Workspace focus tracking (T026, US1)
        self.connection.subscribe(
            "workspace::focus",
            partial(on_workspace_focus, state_manager=self.state_manager)
        )

        # Feature 085: Monitoring panel workspace event updates (T020)
        async def publish_monitoring_panel_workspace_update(conn, event):
            """Publish monitoring panel state on workspace events."""
            if self.monitoring_panel_publisher:
                await self.monitoring_panel_publisher.publish(conn)

        self.connection.subscribe("workspace::focus", publish_monitoring_panel_workspace_update)
        logger.info("Feature 085: Monitoring panel subscribed to workspace events")

        # Feature 091: Tree cache invalidation on state-changing events
        async def invalidate_tree_cache(conn, event):
            """Invalidate tree cache on relevant Sway events."""
            if self.tree_cache:
                event_type = f"{event.__class__.__name__.replace('Event', '').lower()}::{event.change}"
                self.tree_cache.invalidate_on_event(event_type)

        self.connection.subscribe("window::close", invalidate_tree_cache)
        self.connection.subscribe("window::move", invalidate_tree_cache)
        self.connection.subscribe("workspace::empty", invalidate_tree_cache)
        self.connection.subscribe("workspace::move", invalidate_tree_cache)
        logger.info("Feature 091: Tree cache invalidation subscribed to window/workspace events")

        # Feature 024: R013 - Multi-monitor output event handling
        # Feature 042: Also refresh workspace mode cache on output changes
        self.connection.subscribe(
            "output",
            partial(
                on_output,
                state_manager=self.state_manager,
                event_buffer=self.event_buffer,
                workspace_mode_manager=self.workspace_mode_manager
            )
        )
        logger.info("Subscribed to output events for monitor connect/disconnect detection")

        # Feature 042: Workspace mode navigation via Sway mode events
        self.connection.subscribe(
            "mode",
            partial(
                on_mode,
                workspace_mode_manager=self.workspace_mode_manager,
                ipc_server=self.ipc_server,
                event_buffer=self.event_buffer,
                state_manager=self.state_manager
            )
        )
        logger.info("Subscribed to mode events for workspace mode navigation")

        # Shutdown event (for i3 restart/exit)
        self.connection.subscribe("shutdown", self.connection.handle_shutdown_event)

        logger.info("Event handlers registered")

        # CRITICAL: Explicitly subscribe to events AFTER registering handlers
        # Even though conn.on() calls ensure_future(subscribe()), those are async tasks
        # that may not execute before main() starts. Explicitly subscribing ensures
        # we're subscribed before the event loop starts processing events.
        await self.connection.subscribe_events()
        logger.info("Explicit subscription completed")

        # Feature 037 T038: Perform startup scan to mark pre-existing windows
        # This must happen AFTER event subscription to ensure mark commands work properly
        await self.connection.perform_startup_scan()

        # Feature 037 T016: Initialize project switch request queue for sequential processing
        from .handlers import initialize_project_switch_queue
        initialize_project_switch_queue(
            self.connection.conn,
            self.state_manager,
            self.config_dir,
            self.workspace_tracker
        )
        logger.info("Project switch request queue initialized")

        # Feature 074: Session Management - Load persisted focus state (T025, US1)
        await self.state_manager.load_focus_state()

        # Feature 074: Session Management - Initialize auto-save and auto-restore managers (T099, US5-US6)
        self.state_manager.initialize_auto_save_manager(self.connection.conn, ipc_server=self.ipc_server)

    async def run(self) -> None:
        """Main event loop."""
        logger.info("Starting daemon event loop...")

        # Feature 083: Sync output-states.json with current profile on startup
        # This ensures output-states.json matches the profile if daemon starts after profile was set
        if self.monitor_profile_service and self.connection and self.connection.conn:
            try:
                profile_name = self.monitor_profile_service.get_current_profile()
                if profile_name:
                    logger.info(f"[Feature 083] Syncing output-states.json with current profile: {profile_name}")
                    await self.monitor_profile_service.handle_profile_change(
                        self.connection.conn,
                        profile_name
                    )
            except Exception as e:
                logger.warning(f"[Feature 083] Failed to sync output states on startup: {e}")

        # Feature 083: Publish initial monitor state to Eww
        if self.eww_publisher and self.connection and self.connection.conn:
            try:
                outputs = await self.connection.conn.get_outputs()
                states = load_output_states()
                enabled_outputs = [
                    o.name for o in outputs
                    if o.active and states.is_output_enabled(o.name)
                ]
                profile_name = self.monitor_profile_service.get_current_profile() if self.monitor_profile_service else "unknown"
                await self.eww_publisher.publish_from_conn(
                    self.connection.conn,
                    profile_name or "unknown",
                    enabled_outputs
                )
                logger.info(f"[Feature 083] Published initial monitor state to Eww: profile={profile_name}, outputs={enabled_outputs}")
            except Exception as e:
                logger.warning(f"[Feature 083] Failed to publish initial monitor state: {e}")

        # Signal READY to systemd (after full initialization completes)
        if self.health_monitor:
            self.health_monitor.notify_ready()

        # Start watchdog loop in background
        watchdog_task = None
        if self.health_monitor:
            watchdog_task = asyncio.create_task(self.health_monitor.watchdog_loop())

        # Feature 029: T033 - Start process monitoring
        if self.proc_monitor and self.event_buffer:
            async def proc_event_callback(event: EventEntry):
                """Callback to handle process events."""
                await self.event_buffer.add_event(event)
                logger.debug(f"Process event captured: {event.process_name} (PID {event.process_pid})")

            await self.proc_monitor.start(proc_event_callback)
            logger.info("Process monitoring started")

        # Feature 029: T046-T052 - Start periodic correlation detection
        correlation_task = None
        if self.ipc_server and self.event_buffer:
            async def run_correlation_detection():
                """Periodically detect correlations in recent events."""
                while True:
                    try:
                        await asyncio.sleep(10)  # Run every 10 seconds

                        # Get recent events (last 100)
                        events = self.event_buffer.get_events(limit=100)

                        # Run correlation detection
                        if self.ipc_server.event_correlator:
                            correlations = await self.ipc_server.event_correlator.detect_correlations(events)
                            if correlations:
                                logger.debug(f"Detected {len(correlations)} new correlations")
                    except asyncio.CancelledError:
                        break
                    except Exception as e:
                        logger.error(f"Error in correlation detection: {e}")

            correlation_task = asyncio.create_task(run_correlation_detection())
            logger.info("Correlation detection started")

        # Socket validation task - detect stale sockets after Sway restart
        socket_validation_task = None
        if self.connection:
            async def run_socket_validation():
                """Periodically validate Sway socket and reconnect if needed."""
                while True:
                    try:
                        await asyncio.sleep(30)  # Check every 30 seconds
                        if self.connection and not self.connection.is_shutting_down:
                            reconnected = await self.connection.validate_and_reconnect_if_needed()
                            if reconnected and self.ipc_server:
                                # Update IPC server with new connection
                                self.ipc_server.i3_connection = self.connection
                                logger.info("IPC server updated after socket reconnection")
                    except asyncio.CancelledError:
                        break
                    except Exception as e:
                        logger.warning(f"Error in socket validation: {e}")

            socket_validation_task = asyncio.create_task(run_socket_validation())
            logger.info("Socket validation task started (30s interval)")

        try:
            # Run i3 event loop (blocks until shutdown)
            if self.connection:
                await self.connection.main()

        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            raise

        finally:
            # Feature 029: Stop process monitoring
            if self.proc_monitor:
                await self.proc_monitor.stop()
                logger.info("Process monitoring stopped")

            # Feature 029: Stop correlation detection
            if correlation_task:
                correlation_task.cancel()
                try:
                    await correlation_task
                except asyncio.CancelledError:
                    pass
                logger.info("Correlation detection stopped")

            # Stop socket validation task
            if socket_validation_task:
                socket_validation_task.cancel()
                try:
                    await socket_validation_task
                except asyncio.CancelledError:
                    pass
                logger.info("Socket validation stopped")

            # Cancel watchdog task
            if watchdog_task:
                watchdog_task.cancel()
                try:
                    await watchdog_task
                except asyncio.CancelledError:
                    pass

    async def shutdown(self) -> None:
        """Graceful shutdown with timeouts to prevent hanging.

        CRITICAL FIX: All shutdown operations are wrapped in timeouts to prevent
        the daemon from hanging on shutdown and requiring SIGKILL from systemd.
        """
        logger.info("Shutting down daemon...")

        # Signal systemd we're stopping
        if self.health_monitor:
            self.health_monitor.notify_stopping()

        # Wrap all shutdown operations in overall timeout (10s total)
        try:
            # Feature 037 T016: Shutdown project switch queue (2s timeout)
            try:
                from .handlers import shutdown_project_switch_queue
                await asyncio.wait_for(shutdown_project_switch_queue(), timeout=2.0)
                logger.info("Project switch queue shutdown complete")
            except asyncio.TimeoutError:
                logger.warning("Project switch queue shutdown timed out after 2s (continuing)")
            except Exception as e:
                logger.error(f"Error shutting down project switch queue: {e}")

            # Stop window rules watcher (Feature 021: T022) - synchronous, fast
            if self.rules_watcher:
                try:
                    self.rules_watcher.stop()
                    logger.info("Window rules watcher stopped")
                except Exception as e:
                    logger.error(f"Error stopping rules watcher: {e}")

            # Stop IPC server (5s timeout)
            if self.ipc_server:
                try:
                    await asyncio.wait_for(self.ipc_server.stop(), timeout=5.0)
                    logger.info("IPC server stopped")
                except asyncio.TimeoutError:
                    logger.warning("IPC server shutdown timed out after 5s (continuing)")
                except Exception as e:
                    logger.error(f"Error stopping IPC server: {e}")

            # Close i3 connection - synchronous, usually fast
            if self.connection:
                try:
                    self.connection.close()
                    logger.info("i3 connection closed")
                except Exception as e:
                    logger.error(f"Error closing i3 connection: {e}")

        except Exception as e:
            logger.error(f"Error during shutdown: {e}")

        logger.info("Daemon shutdown complete")

    def setup_signal_handlers(self) -> None:
        """Setup signal handlers for graceful shutdown."""

        def shutdown_handler(signum, frame):
            """Handle SIGTERM/SIGINT for graceful shutdown."""
            logger.info(f"Received signal {signum}, initiating shutdown...")
            # CRITICAL FIX: Use call_soon_threadsafe() to safely interact with asyncio from signal handler
            # Signal handlers run in interrupt context and cannot safely call asyncio operations directly
            loop = asyncio.get_event_loop()
            loop.call_soon_threadsafe(self.shutdown_event.set)

        def debug_handler(signum, frame):
            """Handle USR1 for debugging (print diagnostics without shutdown)."""
            logger.info("=== DEBUG INFO (USR1) ===")
            logger.info(f"PID: {os.getpid()}")
            try:
                loop = asyncio.get_event_loop()
                tasks = asyncio.all_tasks(loop)
                logger.info(f"Active tasks: {len(tasks)}")
                for task in tasks:
                    logger.info(f"  Task: {task.get_name()}")
            except Exception as e:
                logger.error(f"Error getting debug info: {e}")
            logger.info("======================")

        signal.signal(signal.SIGTERM, shutdown_handler)
        signal.signal(signal.SIGINT, shutdown_handler)
        signal.signal(signal.SIGUSR1, debug_handler)


def setup_logging() -> None:
    """Setup logging to systemd journal or stderr."""
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)

    if SYSTEMD_AVAILABLE:
        # Use systemd journal handler
        # Suppress stderr output from journal handler creation at FD level
        with _suppress_stderr_fd():
            handler = journal.JournalHandler(SYSLOG_IDENTIFIER="i3-project-daemon")
    else:
        # Use stderr handler
        handler = logging.StreamHandler(sys.stderr)

    # Set format
    formatter = logging.Formatter(
        "%(levelname)s [%(name)s] %(message)s"
    )
    handler.setFormatter(formatter)
    root_logger.addHandler(handler)

    logger.info(f"Logging configured: level={log_level}")


async def main_async() -> int:
    """Async main function.

    Returns:
        Exit code (0 = success, non-zero = error)
    """
    daemon = I3ProjectDaemon()

    try:
        # Setup signal handlers
        daemon.setup_signal_handlers()

        # Initialize daemon
        await daemon.initialize()

        # Register event handlers (auto-subscribes via i3ipc.aio.Connection.on())
        await daemon.register_event_handlers()

        # Run main loop
        run_task = asyncio.create_task(daemon.run())
        shutdown_task = asyncio.create_task(daemon.shutdown_event.wait())

        # Wait for either run completion or shutdown signal
        done, pending = await asyncio.wait(
            [run_task, shutdown_task], return_when=asyncio.FIRST_COMPLETED
        )

        # Cancel pending tasks
        for task in pending:
            task.cancel()

        # Shutdown
        await daemon.shutdown()

        return 0

    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        return 1


def main() -> None:
    """Main entry point."""
    # Setup logging (FD-level stderr suppression is now handled in _suppress_stderr_fd())
    setup_logging()

    logger.info("i3 Project Event Daemon starting...")
    logger.info(f"PID: {os.getpid()}")
    logger.info(f"Config directory: {Path.home() / '.config' / 'i3'}")

    # Run async main
    try:
        exit_code = asyncio.run(main_async())
        sys.exit(exit_code)

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(0)

    except Exception as e:
        logger.error(f"Unhandled exception: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
# Rebuild trigger
