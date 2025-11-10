"""Event handlers for i3 window/workspace/tick events.

This module contains all event handlers that process i3 IPC events.
Feature 061: Unified mark format (project:NAME:ID).
"""

import asyncio
import logging
import time
from datetime import datetime
from typing import Optional, TYPE_CHECKING, List, Dict
from i3ipc import aio, TickEvent, WindowEvent, WorkspaceEvent, OutputEvent

from .state import StateManager
from .models import WindowInfo, WorkspaceInfo, ApplicationClassification, EventEntry
from .config import save_active_project, load_active_project
from .pattern_resolver import classify_window, Classification
from .window_rules import WindowRule
from .action_executor import apply_rule_actions  # Feature 024
from pathlib import Path

if TYPE_CHECKING:
    from .event_buffer import EventBuffer

logger = logging.getLogger(__name__)


# ============================================================================
# Feature 001: Output Event Debouncing for Monitor Changes
# ============================================================================

# Global debounce state for output events
_output_debounce_task: Optional[asyncio.Task] = None
_output_debounce_timer: float = 0.5  # 500ms debounce


# ============================================================================
# Feature 053 Phase 6: Comprehensive Event Logging Utilities
# ============================================================================


def log_event_entry(event_type: str, event_data: Dict, level: str = "DEBUG") -> None:
    """Log comprehensive event details for debugging (Feature 053 Phase 6).

    Provides structured logging for all Sway/i3 events including:
    - Event type and timestamp
    - Window properties (class, title, ID, PID)
    - Workspace information (number, name, output)
    - Project context
    - Application classification

    Args:
        event_type: Type of event (window::new, workspace::init, output, etc.)
        event_data: Dictionary of event-specific data
        level: Log level (DEBUG, INFO, WARNING, ERROR)
    """
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

    # Build log message with comprehensive details
    log_parts = [
        f"[{timestamp}]",
        f"EVENT: {event_type}",
    ]

    # Add all event-specific data
    for key, value in event_data.items():
        if value is not None:
            log_parts.append(f"{key}={value}")

    log_message = " | ".join(log_parts)

    # Log at appropriate level
    log_func = getattr(logger, level.lower(), logger.debug)
    log_func(log_message)


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


async def _delayed_property_recheck(
    conn: aio.Connection,
    window_id: int,
    original_class: str,
    application_registry: Optional[Dict],
    workspace_tracker,
    window_env,
    matched_launch,
) -> None:
    """Feature 053: Delayed property re-check for native Wayland apps (US1 T035-T038).

    Native Wayland apps (PWAs, native apps) may have empty app_id during the window::new event.
    This function re-checks window properties after 100ms delay to allow them to populate,
    then retries workspace assignment if properties are now available.

    Args:
        conn: i3 async connection
        window_id: Window container ID
        original_class: Original window class from initial event
        application_registry: Application registry for workspace lookup
        workspace_tracker: WorkspaceTracker for tracking assignment
        window_env: Window environment variables (if available)
        matched_launch: Matched launch notification (if available)
    """
    try:
        # Wait 100ms for properties to populate
        await asyncio.sleep(0.1)

        # Re-fetch window from tree
        tree = await conn.get_tree()
        fresh_container = tree.find_by_id(window_id)

        if not fresh_container:
            logger.warning(f"Window {window_id} no longer exists after delayed property re-check")
            return

        # Check if app_id is now populated
        new_class = get_window_class(fresh_container)

        if new_class and new_class != "unknown" and new_class != original_class:
            logger.info(
                f"✓ Property re-check successful: Window {window_id} app_id populated "
                f"(was '{original_class}' → now '{new_class}')"
            )

            # Retry workspace assignment with populated properties
            preferred_ws = None
            assignment_source = None

            # Priority 0: Launch notification (highest priority)
            if matched_launch and hasattr(matched_launch, 'workspace_number') and matched_launch.workspace_number:
                preferred_ws = matched_launch.workspace_number
                assignment_source = "launch_notification (delayed)"

            # Priority 1: Environment variable
            elif window_env and hasattr(window_env, 'target_workspace') and window_env.target_workspace:
                preferred_ws = window_env.target_workspace
                assignment_source = "I3PM_TARGET_WORKSPACE (delayed)"

            # Priority 2: I3PM_APP_NAME registry
            elif window_env and window_env.app_name and application_registry:
                app_def = application_registry.get(window_env.app_name)
                if app_def and "preferred_workspace" in app_def:
                    preferred_ws = app_def["preferred_workspace"]
                    assignment_source = f"registry[{window_env.app_name}] (delayed)"

            # Priority 3: Class-based registry matching
            elif application_registry:
                from .services.window_identifier import match_with_registry

                app_match = match_with_registry(
                    actual_class=new_class,
                    actual_instance=fresh_container.window_instance or "",
                    application_registry=application_registry
                )

                if app_match and "preferred_workspace" in app_match:
                    preferred_ws = app_match["preferred_workspace"]
                    app_name = app_match.get("_matched_app_name", "unknown")
                    match_type = app_match.get("_match_type", "unknown")
                    assignment_source = f"registry[{app_name}] via class-match ({match_type}, delayed)"

            if preferred_ws:
                # BUGFIX T070: Check if window is actually on target workspace
                # workspace() method returns focused workspace, not window's actual workspace
                # Solution: Check if window's parent is the target workspace
                is_on_target_workspace = (
                    fresh_container.parent and
                    fresh_container.parent.type == "workspace" and
                    fresh_container.parent.num == preferred_ws
                )

                if not is_on_target_workspace:
                    # Move window to preferred workspace
                    await conn.command(
                        f'[con_id="{window_id}"] move to workspace number {preferred_ws}'
                    )

                    # Track assignment
                    if workspace_tracker:
                        is_floating = fresh_container.floating == "user_on" or fresh_container.floating == "auto_on"
                        await workspace_tracker.track_window(
                            window_id=window_id,
                            workspace_number=preferred_ws,
                            floating=is_floating,
                            project_name=window_env.project_name if window_env and window_env.project_name else "",
                            app_name=window_env.app_name if window_env else "",
                            window_class=new_class,
                        )
                        await workspace_tracker.save()

                    logger.info(
                        f"✓ Delayed assignment: Moved window {window_id} ({new_class}) to "
                        f"workspace {preferred_ws} (source: {assignment_source})"
                    )
                else:
                    logger.debug(
                        f"Window {window_id} ({new_class}) already on preferred workspace {preferred_ws}"
                    )
            else:
                logger.debug(
                    f"No workspace assignment found for window {window_id} ({new_class}) "
                    f"after delayed property re-check"
                )
        else:
            logger.debug(
                f"Property re-check: Window {window_id} app_id still not populated "
                f"(remains '{new_class}')"
            )

    except Exception as e:
        logger.error(f"Error in delayed property re-check for window {window_id}: {e}", exc_info=True)


# Feature 033: Debouncing state for output change handler
_output_change_task: Optional[asyncio.Task] = None
_last_output_event_time: float = 0.0

# Feature 037 T016: Request queue for sequential project switch processing
_project_switch_queue: Optional[asyncio.Queue] = None
_project_switch_worker_task: Optional[asyncio.Task] = None


async def _project_switch_worker(
    conn: aio.Connection,
    state_manager: StateManager,
    config_dir: Path,
    workspace_tracker,
) -> None:
    """Background worker that processes project switch requests sequentially.

    This ensures rapid project switches are handled one at a time, preventing
    race conditions and overlapping window filtering operations.

    Args:
        conn: i3 async connection
        state_manager: State manager instance
        config_dir: Config directory
        workspace_tracker: WorkspaceTracker for window filtering
    """
    global _project_switch_queue

    logger.info("Project switch worker started")

    while True:
        try:
            # Wait for next switch request
            project_name = await _project_switch_queue.get()

            logger.debug(f"Processing queued switch request: {project_name}")

            # Process the switch
            await _switch_project(project_name, state_manager, conn, config_dir, workspace_tracker)

            # Mark task as done
            _project_switch_queue.task_done()

        except asyncio.CancelledError:
            logger.info("Project switch worker cancelled")
            break
        except Exception as e:
            logger.error(f"Error in project switch worker: {e}", exc_info=True)
            # Continue processing even if one switch fails


def initialize_project_switch_queue(
    conn: aio.Connection,
    state_manager: StateManager,
    config_dir: Path,
    workspace_tracker,
) -> None:
    """Initialize the project switch request queue and worker task.

    Args:
        conn: i3 async connection
        state_manager: State manager instance
        config_dir: Config directory
        workspace_tracker: WorkspaceTracker for window filtering
    """
    global _project_switch_queue, _project_switch_worker_task

    if _project_switch_queue is None:
        _project_switch_queue = asyncio.Queue(maxsize=10)  # Limit to 10 pending switches
        logger.info("Project switch queue initialized (max size: 10)")

    if _project_switch_worker_task is None or _project_switch_worker_task.done():
        _project_switch_worker_task = asyncio.create_task(
            _project_switch_worker(conn, state_manager, config_dir, workspace_tracker)
        )
        logger.info("Project switch worker task created")


async def shutdown_project_switch_queue() -> None:
    """Shutdown the project switch queue and worker task gracefully."""
    global _project_switch_worker_task, _project_switch_queue

    if _project_switch_worker_task and not _project_switch_worker_task.done():
        # Cancel worker task
        _project_switch_worker_task.cancel()

        try:
            await _project_switch_worker_task
        except asyncio.CancelledError:
            pass

        logger.info("Project switch worker task stopped")

    # Clear queue
    if _project_switch_queue:
        while not _project_switch_queue.empty():
            try:
                _project_switch_queue.get_nowait()
                _project_switch_queue.task_done()
            except asyncio.QueueEmpty:
                break


# ============================================================================
# USER STORY 1 (P1): Real-time Project State Updates
# ============================================================================


async def on_tick(
    conn: aio.Connection,
    event: TickEvent,
    state_manager: StateManager,
    config_dir: Path,
    event_buffer: Optional["EventBuffer"] = None,
    workspace_tracker=None,  # Feature 037: Window filtering
) -> None:
    """Handle tick events for project switch notifications (T007).

    Args:
        conn: i3 async IPC connection
        event: Tick event containing payload
        state_manager: State manager instance
        config_dir: Configuration directory path
        event_buffer: Event buffer for recording events (Feature 017)
        workspace_tracker: WorkspaceTracker instance for window filtering (Feature 037)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None

    try:
        payload = event.payload

        # Feature 053 Phase 6: Comprehensive tick event logging
        active_project = await state_manager.get_active_project()
        log_event_entry(
            "tick",
            {
                "payload": payload,
                "active_project": active_project or "none",
            },
            level="INFO" if payload.startswith("project:") else "DEBUG"
        )

        logger.info(f"✓ TICK EVENT RECEIVED: {payload}")  # Changed to INFO to ensure visibility
        logger.debug(f"Received tick event: {payload}")

        if payload.startswith("project:"):
            # Parse payload: "project:switch:nixos" or "project:clear" or "project:none"
            parts = payload.split(":", 2)

            if len(parts) == 3 and parts[1] == "switch":
                # Format: project:switch:<name>
                project_name = parts[2]
                # Feature 037 T016: Queue switch request for sequential processing
                if _project_switch_queue is not None:
                    try:
                        # Try to add to queue without blocking
                        _project_switch_queue.put_nowait(project_name)
                        logger.debug(f"Queued project switch request: {project_name} (queue size: {_project_switch_queue.qsize()})")
                    except asyncio.QueueFull:
                        logger.warning(f"Project switch queue is full, dropping request for {project_name}")
                else:
                    # Fallback to direct call if queue not initialized
                    logger.debug("Project switch queue not initialized, processing directly")
                    await _switch_project(project_name, state_manager, conn, config_dir, workspace_tracker)
            elif len(parts) == 2:
                # Format: project:clear or project:none or project:reload
                action = parts[1]
                if action in ("clear", "none"):
                    await _clear_project(state_manager, conn, config_dir)
                elif action == "reload":
                    logger.info("Reloading project configurations...")
                    # TODO: Implement config reload
                else:
                    logger.warning(f"Unknown project action: {action}")
            else:
                logger.warning(f"Invalid project tick payload format: {payload}")

        elif payload == "i3pm:reload-config":
            # Reload app classification config (T030 - Pattern-based classification)
            logger.info("Reloading app classification configuration...")
            try:
                from .config import load_app_classification
                config_file = config_dir / "app-classes.json"
                new_classification = load_app_classification(config_file)
                await state_manager.update_app_classification(new_classification)
                logger.info(f"✓ App classification reloaded: {len(new_classification.scoped_classes)} scoped, {len(new_classification.global_classes)} global")
            except Exception as e:
                logger.error(f"Failed to reload app classification: {e}")
                raise

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling tick event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer (Feature 017)
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="tick",
                timestamp=datetime.now(),
                source="i3",
                tick_payload=event.payload,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)


async def _switch_project(
    project_name: str,
    state_manager: StateManager,
    conn: aio.Connection,
    config_dir: Path,
    workspace_tracker=None,  # Feature 037: Window filtering
) -> None:
    """Switch to a new project (hide old, show new).

    Args:
        project_name: Name of project to switch to
        state_manager: State manager instance
        conn: i3 async connection
        config_dir: Config directory
        workspace_tracker: WorkspaceTracker for window filtering (Feature 037)
    """
    # Get current active project
    old_project = await state_manager.get_active_project()

    if old_project == project_name:
        logger.info(f"Already on project {project_name}")
        return

    # Feature 053 Phase 6: Comprehensive project switch logging
    log_event_entry(
        "project::switch",
        {
            "old_project": old_project or "none",
            "new_project": project_name,
        },
        level="INFO"
    )

    logger.info(f"TICK: Switching project: {old_project} → {project_name}")

    # Feature 037: Use mark-based window filtering (rebuild trigger: 2025-10-25-18:55)
    logger.info(f"TICK: Importing and calling mark-based filter_windows_by_project")
    from .services.window_filter import filter_windows_by_project
    start_time = time.perf_counter()

    logger.info(f"TICK: Calling filter_windows_by_project for '{project_name}'")
    filter_result = await filter_windows_by_project(conn, project_name, workspace_tracker)

    duration_ms = (time.perf_counter() - start_time) * 1000
    logger.info(
        f"TICK: Window filtering complete: {filter_result['visible']} visible, {filter_result['hidden']} hidden "
        f"({duration_ms:.1f}ms)"
    )

    if filter_result.get('errors', 0) > 0:
        logger.warning(f"TICK: Errors during filtering: {filter_result['errors']}")

    # Update active project
    await state_manager.set_active_project(project_name)

    # Save to config file
    from .models import ActiveProjectState

    state = ActiveProjectState(
        project_name=project_name,
    )
    save_active_project(state, config_dir / "active-project.json")


async def _clear_project(
    state_manager: StateManager, conn: aio.Connection, config_dir: Path
) -> None:
    """Clear active project (global mode).

    Args:
        state_manager: State manager instance
        conn: i3 async connection
        config_dir: Config directory
    """
    old_project = await state_manager.get_active_project()

    if not old_project:
        logger.info("Already in global mode")
        return

    logger.info(f"Clearing project {old_project} (entering global mode)")

    # Show all windows from old project
    old_windows = await state_manager.get_windows_by_project(old_project)
    await show_project_windows(conn, old_windows)

    # Update state
    await state_manager.set_active_project(None)

    # Save to config
    from .models import ActiveProjectState

    state = ActiveProjectState(
        project_name=None
    )
    save_active_project(state, config_dir / "active-project.json")


async def hide_window(conn: aio.Connection, window_id: int) -> None:
    """Hide a window by moving it to scratchpad (T008).

    Args:
        conn: i3 async connection
        window_id: Window ID to hide
    """
    try:
        # Feature 046: Use con_id for Sway compatibility
        await conn.command(f"[con_id={window_id}] move scratchpad")
        logger.debug(f"Hid window {window_id}")
    except Exception as e:
        logger.error(f"Failed to hide window {window_id}: {e}")


async def show_window(conn: aio.Connection, window_id: int, workspace: str) -> None:
    """Show a window by moving it to a workspace (T008).

    Args:
        conn: i3 async connection
        window_id: Window ID to show
        workspace: Workspace to move window to
    """
    try:
        # Feature 046: Use con_id for Sway compatibility
        await conn.command(f"[con_id={window_id}] move container to workspace {workspace}")
        logger.debug(f"Showed window {window_id} on workspace {workspace}")
    except Exception as e:
        logger.error(f"Failed to show window {window_id}: {e}")


async def hide_project_windows(conn: aio.Connection, windows: list[WindowInfo]) -> None:
    """Batch hide windows belonging to a project (T008).

    Args:
        conn: i3 async connection
        windows: List of WindowInfo objects to hide
    """
    for window_info in windows:
        await hide_window(conn, window_info.window_id)


async def show_project_windows(conn: aio.Connection, windows: list[WindowInfo]) -> None:
    """Batch show windows belonging to a project (T008).

    Args:
        conn: i3 async connection
        windows: List of WindowInfo objects to show
    """
    for window_info in windows:
        await show_window(conn, window_info.window_id, window_info.workspace)


# ============================================================================
# USER STORY 2 (P2): Automatic Window Tracking
# ============================================================================


async def on_window_new(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    app_classification: ApplicationClassification,
    event_buffer: Optional["EventBuffer"] = None,
    window_rules: Optional[List[WindowRule]] = None,
    ipc_server: Optional["IPCServer"] = None,
    application_registry: Optional[Dict[str, Dict]] = None,  # Feature 037 T026
    workspace_tracker=None,  # Feature 037 T026
) -> None:
    """Handle window::new events - auto-mark and classify new windows (T014, T023, T026).

    Uses the 4-level precedence classification system:
    1. Project scoped_classes (priority 1000)
    2. Window rules (priority 200-500)
    3. App classification patterns (priority 100)
    4. App classification lists (priority 50)

    Feature 037 T026-T029: Assigns windows to preferred workspace on launch.

    Args:
        conn: i3 async connection
        event: Window event
        state_manager: State manager
        app_classification: Application classification config
        event_buffer: Event buffer for recording events (Feature 017)
        window_rules: Window rules from window-rules.json (Feature 021)
        ipc_server: IPC server for broadcasting events to subscribed clients (Feature 025)
        application_registry: Application registry for workspace assignment (Feature 037 T027)
        workspace_tracker: WorkspaceTracker for tracking initial assignment (Feature 037 T026)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    container = event.container
    # Feature 046: Use node ID (container.id) for Sway/Wayland compatibility
    # (container.window is None for native Wayland apps, container.id works for both)
    window_id = container.id
    window_class = get_window_class(container)  # Feature 045: Sway-compatible
    window_title = container.name or ""

    # Feature 053 Phase 6: Comprehensive event logging
    current_ws = container.workspace()
    log_event_entry(
        "window::new",
        {
            "window_id": window_id,
            "window_class": window_class,
            "window_title": window_title[:50] if window_title else "",
            "window_instance": container.window_instance or "",
            "app_id": getattr(container, 'app_id', None),
            "workspace_num": current_ws.num if current_ws else "?",
            "workspace_name": current_ws.name if current_ws else "?",
            "output": current_ws.ipc_data.get("output", "?") if current_ws else "?",
            "pid": getattr(container, 'pid', None),
            "floating": container.floating,
            "x11_window": container.window,
        },
        level="INFO"
    )

    try:
        active_project = await state_manager.get_active_project()

        # Get active project's scoped classes
        active_project_scoped_classes = None
        if active_project and active_project in state_manager.state.projects:
            project = state_manager.state.projects[active_project]
            active_project_scoped_classes = project.scoped_classes

        # Classify window using 4-level precedence (Feature 021: T023)
        classification = classify_window(
            window_class=window_class,
            window_title=window_title,
            active_project_scoped_classes=active_project_scoped_classes,
            window_rules=window_rules,
            app_classification_patterns=None,  # TODO: Extract from app_classification
            app_classification_scoped=list(app_classification.scoped_classes),
            app_classification_global=list(app_classification.global_classes),
        )

        logger.info(
            f"Window {window_id} ({window_class}) classified as {classification.scope} "
            f"from {classification.source}"
            + (f", workspace={classification.workspace}" if classification.workspace else "")
        )

        # Feature 046: Extract window PID early (needed for environment reading and correlation)
        # For Sway/Wayland, container.pid is available directly
        # For i3/X11, need to use xprop with X11 window ID
        window_pid = None
        if hasattr(container, 'pid') and container.pid:
            # Sway/Wayland: PID available directly from container
            window_pid = container.pid
        elif container.window:
            # i3/X11: Use xprop with X11 window ID
            try:
                import subprocess
                result = subprocess.run(
                    ["xprop", "-id", str(container.window), "_NET_WM_PID"],
                    capture_output=True,
                    text=True,
                    timeout=0.5
                )
                if result.returncode == 0 and "_NET_WM_PID(CARDINAL)" in result.stdout:
                    window_pid = int(result.stdout.split("=")[-1].strip())
            except Exception:
                pass  # PID not available (timeout, xprop error)

        # Feature 035: Read I3PM_* environment variables from /proc/<pid>/environ
        # Feature 046: Refactored to use PID directly instead of xprop-based lookup
        from .services.window_filter import read_process_environ, parse_window_environment
        window_env = None
        is_scratchpad_terminal = False
        if window_pid:
            try:
                env = read_process_environ(window_pid)
                # Feature 062: Skip project marking for scratchpad terminals
                if env.get("I3PM_SCRATCHPAD") == "true":
                    is_scratchpad_terminal = True
                    logger.info(
                        f"Window {window_id} is scratchpad terminal for project '{env.get('I3PM_PROJECT_NAME', 'unknown')}', "
                        "skipping normal project marking (will be handled by scratchpad manager)"
                    )
                    # Don't return early - let window proceed through normal event handlers
                    # but skip project marking later
                window_env = parse_window_environment(env)
                if window_env:
                    logger.debug(
                        f"Window {window_id} has I3PM environment: "
                        f"app={window_env.app_name}, project={window_env.project_name}, "
                        f"scope={window_env.scope}"
                    )
            except (PermissionError, FileNotFoundError):
                logger.debug(f"Cannot read environment for PID {window_pid}, assuming global scope")
        else:
            logger.debug(f"No PID available for window {window_id}, cannot read environment")

        # Feature 039 T053: Extract comprehensive window identity information
        # This provides normalized class names and PWA detection for diagnostics
        from .services.window_identifier import get_window_identity
        window_identity = get_window_identity(
            actual_class=window_class,
            actual_instance=container.window_instance or "",
            window_title=window_title,
        )
        logger.debug(
            f"Window {window_id} identity: "
            f"class={window_identity['original_class']}, "
            f"instance={window_identity['original_instance']}, "
            f"normalized={window_identity['normalized_class']}, "
            f"is_pwa={window_identity['is_pwa']}"
        )

        # Feature 041 T020: IPC Launch Context - Window correlation
        # Correlate new window to pending launch notification using multi-signal algorithm
        from .models import LaunchWindowInfo
        correlated_project = None
        correlation_confidence = 0.0

        # Get current workspace number
        current_ws = container.workspace()
        workspace_number = current_ws.num if current_ws else 1

        # Create LaunchWindowInfo for correlation
        launch_window_info = LaunchWindowInfo(
            window_id=window_id,
            window_class=window_class,
            window_pid=window_pid,
            workspace_number=workspace_number,
            timestamp=time.time(),
        )

        # Query launch registry for matching pending launch
        matched_launch = await state_manager.launch_registry.find_match(launch_window_info)

        if matched_launch:
            # Successful correlation - use project from launch notification
            # T040: calculate_confidence now returns (confidence, signals) tuple
            from .services.window_correlator import calculate_confidence
            correlation_confidence, correlation_signals = calculate_confidence(matched_launch, launch_window_info)
            correlated_project = matched_launch.project_name

            # Determine confidence level for logging
            if correlation_confidence >= 1.0:
                confidence_level = "EXACT"
            elif correlation_confidence >= 0.8:
                confidence_level = "HIGH"
            elif correlation_confidence >= 0.6:
                confidence_level = "MEDIUM"
            else:
                confidence_level = "LOW"

            # T040: Enhanced logging with workspace match information
            workspace_match_str = ""
            if "workspace_match" in correlation_signals:
                workspace_match = correlation_signals["workspace_match"]
                launch_ws = correlation_signals.get("launch_workspace", "?")
                window_ws = correlation_signals.get("window_workspace", "?")
                boost = correlation_signals.get("workspace_bonus", 0.0)
                workspace_match_str = f", workspace_match={workspace_match} (launch={launch_ws}, window={window_ws}, boost={boost:.1f})"

            logger.info(
                f"✓ Correlated window {window_id} ({window_class}) to project '{correlated_project}' "
                f"with confidence {correlation_confidence:.2f} [{confidence_level}] "
                f"(app={matched_launch.app_name}{workspace_match_str})"
            )
        else:
            # No matching launch found - explicit failure (FR-008, FR-009)
            logger.warning(
                f"✗ Window {window_id} ({window_class}) appeared without matching launch notification. "
                f"No project assignment via launch correlation. "
                f"(workspace={workspace_number}, pid={window_pid})"
            )

        # Determine actual project using priority order (Feature 058 - Intent-first architecture):
        # Priority 1: Launch correlation (Feature 041 - explicit user action via walker)
        # Priority 2: Active project (Feature 058 - current user intent, fixes shared-PID apps)
        # Priority 3: I3PM environment (Feature 035 - fallback for non-walker launches)
        # Priority 4: No assignment (global scope)
        actual_project = None

        if correlated_project:
            # Priority 1: Use project from launch correlation
            actual_project = correlated_project
            logger.info(
                f"Window {window_id} assigned to project '{actual_project}' via launch correlation "
                f"(confidence={correlation_confidence:.2f})"
            )
        elif state_manager.state.active_project:
            # Priority 2: Use active project (current user intent)
            # This handles shared-PID apps (VS Code, Chrome, Electron) where environment
            # variables from the main process don't reflect the per-window project context.
            # Since all apps are launched via walker (which injects environment at launch),
            # active_project is the source of truth for user intent.
            actual_project = state_manager.state.active_project
            logger.info(
                f"Window {window_id} assigned to project '{actual_project}' from active project (user intent)"
            )
        elif window_env and window_env.project_name:
            # Priority 3: Use I3PM environment (fallback for non-walker launches)
            actual_project = window_env.project_name
            logger.info(
                f"Window {window_id} has I3PM environment: "
                f"app={window_env.app_name}, project={actual_project}, "
                f"scope={window_env.scope}, instance_id={window_env.app_id}"
            )
        else:
            # Priority 4: No project assignment → assume global scope
            actual_project = None
            logger.debug(f"Window {window_id} has no project assignment, assuming global scope")

        # Feature 038 ENHANCEMENT: VSCode-specific project detection from window title
        # VSCode windows share a single process, so I3PM environment doesn't distinguish
        # between multiple workspaces. Parse title to get the actual project directory.
        if window_class == "Code" and window_title:
            # VSCode title formats:
            #   No file: "PROJECT - HOSTNAME - Visual Studio Code"
            #   File open: "FILENAME - PROJECT - HOSTNAME - Visual Studio Code"
            # Strategy: Split by " - " and find first segment matching a known project
            segments = [seg.strip().lower() for seg in window_title.split(" - ")]
            title_project = None

            for segment in segments:
                if segment in state_manager.state.projects:
                    title_project = segment
                    logger.debug(f"Found project '{segment}' in VS Code title: {window_title}")
                    break

            if title_project and actual_project != title_project:
                logger.info(
                    f"VSCode window {window_id}: Overriding project from I3PM "
                    f"({actual_project}) to title-based ({title_project})"
                )
                actual_project = title_project

        # Feature 062: Skip marking for scratchpad terminals
        # They will be marked by the scratchpad manager with "scratchpad:PROJECT" format
        if is_scratchpad_terminal:
            logger.info(f"Skipping project mark for scratchpad terminal {window_id} (will be marked by scratchpad manager)")
            marks_list = []
            mark = None  # No mark applied yet
        else:
            # Apply project mark if we have a project assignment
            # Note: i3 marks must be UNIQUE - use format project:PROJECT:WINDOW_ID
            # Feature 041 T020: Mark windows from launch correlation
            # Feature 035: Mark windows from I3PM environment
            # Feature 061: Unified mark format - all windows use "project:" prefix
            should_mark = False
            mark_source = None

            if correlated_project and actual_project:
                # Project assigned via launch correlation
                should_mark = True
                mark_source = "launch correlation"
            elif window_env and actual_project:
                # Project assigned via I3PM environment (both scoped and global apps)
                should_mark = True
                mark_source = "I3PM environment"
            elif actual_project and classification.scope == "scoped":
                # Project assigned via active project (user intent) for scoped windows
                # This handles windows opened without launch notification or I3PM environment
                should_mark = True
                mark_source = "active project"

            # ALWAYS mark windows for consistency and debugging
            # Unified format: project:PROJECT:WINDOW_ID
            # - project: always literal "project" prefix
            # - PROJECT: project name or "none" if no active project
            # - WINDOW_ID: unique window identifier (container.id)
            # Scope info (scoped/global) is tracked separately in classification/state
            project_for_mark = actual_project or "none"
            mark = f"project:{project_for_mark}:{window_id}"

            # Feature 046: Use con_id for Sway/Wayland compatibility (window_id is now container.id)
            await conn.command(f'[con_id={window_id}] mark --add "{mark}"')

            if actual_project:
                logger.info(f"Marked window {window_id} with {mark} (from {mark_source or 'classification'})")
            else:
                logger.info(f"Marked window {window_id} with {mark} (no active project)")

            marks_list = [mark]

        # ALWAYS add window to state (for tracking), even if not marked
        # Feature 041 T022: Include correlation metadata if window was matched via launch
        window_info = WindowInfo(
            window_id=window_id,
            con_id=container.id,
            window_class=window_class,
            window_title=window_title,
            window_instance=container.window_instance or "",
            app_identifier=window_env.app_name if window_env else (matched_launch.app_name if matched_launch else window_class),
            project=actual_project,  # May be None for global windows
            marks=marks_list,
            workspace=container.workspace().name if container.workspace() else "",
            created=datetime.now(),
            # Feature 041 T022: Store correlation metadata if matched via launch
            # T040: Now using full signals from calculate_confidence including workspace details
            correlation_matched=bool(matched_launch),
            correlation_launch_id=f"{matched_launch.app_name}-{matched_launch.timestamp}" if matched_launch else None,
            correlation_confidence=correlation_confidence if matched_launch else None,
            correlation_confidence_level=confidence_level if matched_launch else None,
            correlation_signals=correlation_signals if matched_launch else None,
        )
        await state_manager.add_window(window_info)

        # Feature 037 T026-T029 + Feature 039 T060-T063 + Feature 056 REFACTORED: Workspace assignment
        #
        # SIMPLIFIED ARCHITECTURE:
        #   Firefox PWAs (FFPWA-*): Direct class-based lookup (deterministic)
        #   Non-PWAs: Priority system (1: Launch notification, 2: TARGET_WORKSPACE, 3: APP_NAME registry, 4: Class match)
        #
        # Feature 062/063: Skip workspace assignment for scratchpad terminals
        # Scratchpad terminals are managed by ScratchpadManager and should remain in scratchpad workspace
        preferred_ws = None
        assignment_source = None
        decision_tree = []  # Track assignment decision path for logging

        logger.debug(f"[WORKSPACE DEBUG] Window {window_id}: is_scratchpad_terminal={is_scratchpad_terminal}")

        if is_scratchpad_terminal:
            # Skip workspace assignment for scratchpad terminals
            logger.info(
                f"Skipping workspace assignment for scratchpad terminal {window_id} "
                f"(project={window_env.project_name if window_env else 'unknown'}, managed by scratchpad manager)"
            )
        else:
            # Normal workspace assignment logic for non-scratchpad windows
            # Firefox PWA: Direct class-based lookup (deterministic)
            if window_class and window_class.startswith("FFPWA-"):
                if application_registry:
                    for app_name, app_def in application_registry.items():
                        expected_class = app_def.get("expected_class", "")
                        if expected_class == window_class:
                            preferred_ws = app_def.get("preferred_workspace")
                            assignment_source = f"pwa_class_match[{app_name}]"
                            logger.info(
                                f"[PWA] Assigned window {window_id} to workspace {preferred_ws} "
                                f"via direct class match (class={window_class}, app={app_name})"
                            )
                            break

                    if not preferred_ws:
                        logger.warning(
                            f"[PWA] No registry match for Firefox PWA class {window_class}"
                        )

            # Priority 1: Launch notification workspace (Feature 053)
            # Use workspace from matched_launch if correlation succeeded
            # This provides <100ms assignment latency and 100% accuracy for walker-launched apps
            if not preferred_ws and matched_launch and hasattr(matched_launch, 'workspace_number') and matched_launch.workspace_number:
                preferred_ws = matched_launch.workspace_number
                assignment_source = "launch_notification"
                decision_tree.append({
                    "priority": 1,
                    "name": "launch_notification",
                    "matched": True,
                    "workspace": preferred_ws,
                    "details": {
                        "app_name": matched_launch.app_name if matched_launch else "unknown",
                        "confidence": f"{correlation_confidence:.2f}" if correlation_confidence else "n/a"
                    }
                })
                logger.info(
                    f"✓ Priority 1: Using launch notification workspace {preferred_ws} "
                    f"for window {window_id} ({window_class}) from app '{matched_launch.app_name}' "
                    f"[correlation_confidence={correlation_confidence:.2f}]"
                )
            elif not preferred_ws:
                # Priority 1 failed - record why
                reason = "no_launch_notification"
                if matched_launch:
                    if not hasattr(matched_launch, 'workspace_number'):
                        reason = "launch_missing_workspace_number"
                    elif not matched_launch.workspace_number:
                        reason = "launch_workspace_number_empty"
                decision_tree.append({
                    "priority": 1,
                    "name": "launch_notification",
                    "matched": False,
                    "reason": reason
                })

            if not preferred_ws and window_env:
                # Priority 2: I3PM_TARGET_WORKSPACE (Feature 039 T060)
                if hasattr(window_env, 'target_workspace') and window_env.target_workspace:
                    preferred_ws = window_env.target_workspace
                    assignment_source = "I3PM_TARGET_WORKSPACE"
                    decision_tree.append({
                        "priority": 2,
                        "name": "I3PM_TARGET_WORKSPACE",
                        "matched": True,
                        "workspace": preferred_ws,
                        "details": {}
                    })
                    logger.info(f"Using I3PM_TARGET_WORKSPACE={preferred_ws} for window {window_id}")
                else:
                    # Priority 2 failed
                    reason = "env_var_not_set" if not hasattr(window_env, 'target_workspace') else "env_var_empty"
                    decision_tree.append({
                        "priority": 2,
                        "name": "I3PM_TARGET_WORKSPACE",
                        "matched": False,
                        "reason": reason
                    })

                # Priority 3: I3PM_APP_NAME registry lookup (Feature 037)
                if not preferred_ws and window_env.app_name and application_registry:
                    app_name = window_env.app_name
                    app_def = application_registry.get(app_name)

                    if app_def and "preferred_workspace" in app_def:
                        preferred_ws = app_def["preferred_workspace"]
                        assignment_source = f"registry[{app_name}]"
                        decision_tree.append({
                            "priority": 3,
                            "name": "I3PM_APP_NAME_registry",
                            "matched": True,
                            "workspace": preferred_ws,
                            "details": {"app_name": app_name}
                        })
                    else:
                        # Priority 3 failed
                        reason = "app_not_in_registry"
                        if app_def and "preferred_workspace" not in app_def:
                            reason = "app_has_no_preferred_workspace"
                        decision_tree.append({
                            "priority": 3,
                            "name": "I3PM_APP_NAME_registry",
                            "matched": False,
                            "reason": reason,
                            "details": {"app_name": app_name if app_name else "none"}
                        })
                elif not preferred_ws:
                    # Priority 3 not attempted
                    reason = "no_window_env" if not window_env else "no_app_name"
                    if not application_registry:
                        reason = "no_registry_loaded"
                    decision_tree.append({
                        "priority": 3,
                        "name": "I3PM_APP_NAME_registry",
                        "matched": False,
                        "reason": reason
                    })
            elif not preferred_ws and not window_env:
                # Skip Priority 2 and 3 - no window_env
                decision_tree.append({
                    "priority": 2,
                    "name": "I3PM_TARGET_WORKSPACE",
                    "matched": False,
                    "reason": "no_window_env"
                })
                decision_tree.append({
                    "priority": 3,
                    "name": "I3PM_APP_NAME_registry",
                    "matched": False,
                    "reason": "no_window_env"
                })

            if not preferred_ws:
                # Priority 4: Class-based registry matching (fallback for apps without PID)
                # BUGFIX 039: When PID is unavailable (e.g., VS Code, Ghostty), use window class
                # to match against application registry and get preferred workspace
                if application_registry:
                    from .services.window_identifier import match_with_registry

                    app_match = match_with_registry(
                        actual_class=window_class,
                        actual_instance=container.window_instance or "",
                        application_registry=application_registry
                    )

                    if app_match and "preferred_workspace" in app_match:
                        preferred_ws = app_match["preferred_workspace"]
                        app_name = app_match.get("_matched_app_name", "unknown")
                        match_type = app_match.get("_match_type", "unknown")
                        assignment_source = f"registry[{app_name}] via class-match ({match_type})"
                        decision_tree.append({
                            "priority": 4,
                            "name": "class_registry_match",
                            "matched": True,
                            "workspace": preferred_ws,
                            "details": {
                                "app_name": app_name,
                                "match_type": match_type,
                                "window_class": window_class
                            }
                        })
                        logger.info(
                            f"Window {window_id} ({window_class}) matched to app {app_name} "
                            f"via {match_type}, assigning workspace {preferred_ws}"
                        )
                    else:
                        # Priority 4 failed
                        reason = "no_class_match_in_registry"
                        decision_tree.append({
                            "priority": 4,
                            "name": "class_registry_match",
                            "matched": False,
                            "reason": reason,
                            "details": {"window_class": window_class}
                        })
                else:
                    decision_tree.append({
                        "priority": 4,
                        "name": "class_registry_match",
                        "matched": False,
                        "reason": "no_registry_loaded"
                    })

            if preferred_ws:
                    # Feature 053 Phase 6: Log workspace assignment decision with full context including decision tree
                    import json
                    log_event_entry(
                        "workspace::assignment",
                        {
                            "window_id": container.id,
                            "window_class": window_class,
                            "target_workspace": preferred_ws,
                            "assignment_source": assignment_source,
                            "project": actual_project or "none",
                            "app_name": window_env.app_name if window_env else "none",
                            "correlation_confidence": f"{correlation_confidence:.2f}" if matched_launch else "n/a",
                            "decision_tree": json.dumps(decision_tree),  # Full decision path for debugging
                        },
                        level="INFO"
                    )

                    # Feature 053 Phase 6: Add workspace assignment to event buffer
                    if event_buffer:
                        assignment_entry = EventEntry(
                            event_id=event_buffer.event_counter,
                            event_type="workspace::assignment",
                            timestamp=datetime.now(),
                            source="daemon",
                            window_id=container.id,
                            window_class=window_class,
                            workspace_name=f"{preferred_ws}",  # Store as string
                            project_name=actual_project if actual_project else None,
                        )
                        await event_buffer.add_event(assignment_entry)

                    # BUGFIX 039 T066 + T070: Check if window is actually on target workspace
                    # Issue: workspace() method returns FOCUSED workspace, not window's actual workspace
                    # When window is created but not yet assigned (workspace: null in Sway tree),
                    # workspace() returns the focused workspace, causing false "already on workspace" detection
                    #
                    # Solution: Check if window's parent is the target workspace
                    # This correctly identifies unassigned windows (parent != target workspace)
                    #
                    # NOTE: Feature 039 architectural change - ALL workspace assignment now in daemon
                    # Previously GLOBAL apps used i3 for_window rules, SCOPED apps used daemon
                    # Now ALL apps use daemon for unified, dynamic, rebuildless workspace management
                    try:
                        tree = await conn.get_tree()
                        fresh_container = tree.find_by_id(container.id)

                        # Check if window's parent is the target workspace
                        # If parent is not a workspace or parent's num != target, window needs to be moved
                        is_on_target_workspace = (
                            fresh_container and
                            fresh_container.parent and
                            fresh_container.parent.type == "workspace" and
                            fresh_container.parent.num == preferred_ws
                        )

                        # T028: Move window if not already on preferred workspace
                        if not is_on_target_workspace:
                            # Move window to preferred workspace and focus it
                            # The focus command ensures Sway switches to the target workspace
                            # to show the newly launched window (respects focus_on_window_activation)
                            await conn.command(
                                f'[con_id="{container.id}"] move to workspace number {preferred_ws}; [con_id="{container.id}"] focus'
                            )

                            # Feature 056: Validate workspace assignment with retry (PWA race condition fix)
                            # PWAs may not be on any workspace yet (workspace_num=?) during window::new
                            # Wait for Sway to process the move, then verify it succeeded
                            await asyncio.sleep(0.1)  # 100ms delay for Sway to process the move

                            validation_tree = await conn.get_tree()
                            validated_container = validation_tree.find_by_id(container.id)

                            # Check if window's parent is the target workspace (consistent with T070 fix)
                            is_validated = (
                                validated_container and
                                validated_container.parent and
                                validated_container.parent.type == "workspace" and
                                validated_container.parent.num == preferred_ws
                            )

                            if not is_validated:
                                # Move failed - window still not on target workspace
                                # Retry once after another delay
                                current_ws_for_log = (
                                    validated_container.parent.num
                                    if validated_container and validated_container.parent and validated_container.parent.type == "workspace"
                                    else "none"
                                )
                                logger.warning(
                                    f"⚠ Workspace assignment validation failed: Window {window_id} not on "
                                    f"workspace {preferred_ws} after move (currently on {current_ws_for_log}). Retrying..."
                                )
                                await asyncio.sleep(0.1)  # Another 100ms delay
                                await conn.command(
                                    f'[con_id="{container.id}"] move to workspace number {preferred_ws}; [con_id="{container.id}"] focus'
                                )

                                # Final validation
                                await asyncio.sleep(0.05)  # Short delay before final check
                                final_tree = await conn.get_tree()
                                final_container = final_tree.find_by_id(container.id)

                                # Check if window's parent is the target workspace (T070)
                                is_finally_validated = (
                                    final_container and
                                    final_container.parent and
                                    final_container.parent.type == "workspace" and
                                    final_container.parent.num == preferred_ws
                                )

                                if not is_finally_validated:
                                    final_ws_for_log = (
                                        final_container.parent.num
                                        if final_container and final_container.parent and final_container.parent.type == "workspace"
                                        else "none"
                                    )
                                    logger.error(
                                        f"✗ Workspace assignment FAILED after retry: Window {window_id} "
                                        f"still not on workspace {preferred_ws} (currently on {final_ws_for_log})"
                                    )
                                else:
                                    logger.info(
                                        f"✓ Retry successful: Window {window_id} now on workspace {preferred_ws}"
                                    )

                            # T026: Track initial workspace assignment
                            if workspace_tracker:
                                from . import window_filtering
                                is_floating = container.floating == "user_on" or container.floating == "auto_on"

                                await workspace_tracker.track_window(
                                    window_id=container.id,
                                    workspace_number=preferred_ws,
                                    floating=is_floating,
                                    project_name=actual_project if actual_project else "",
                                    app_name=window_env.app_name if window_env else "",
                                    window_class=window_class,
                                )
                                await workspace_tracker.save()

                            # T029 + T064: Log workspace assignment with source (Feature 039)
                            # Get original workspace from parent before move
                            original_ws = (
                                fresh_container.parent.num
                                if fresh_container and fresh_container.parent and fresh_container.parent.type == "workspace"
                                else "none"
                            )
                            logger.info(
                                f"Moved window {window_id} ({window_class}) from workspace "
                                f"{original_ws} to preferred workspace {preferred_ws} "
                                f"(source: {assignment_source})"
                            )
                        else:
                            # Already on correct workspace
                            logger.debug(
                                f"Window {window_id} ({window_class}) already on preferred workspace {preferred_ws}"
                            )

                    except Exception as e:
                        logger.error(f"Failed to move window {window_id} to workspace {preferred_ws}: {e}")
            else:
                # Feature 053 Phase 6: Log when NO workspace assignment found (all priorities failed)
                import json
                log_event_entry(
                    "workspace::assignment_failed",
                    {
                        "window_id": container.id,
                        "window_class": window_class,
                        "project": actual_project or "none",
                        "decision_tree": json.dumps(decision_tree),  # Show why each priority failed
                    },
                    level="WARNING"
                )

                # Feature 053 Phase 6: Add workspace assignment failure to event buffer
                if event_buffer:
                    # Build error message from decision tree
                    failed_reasons = [f"P{d['priority']}:{d.get('reason', 'no_match')}" for d in decision_tree if not d.get('matched', False)]
                    error_summary = f"All priorities failed: {', '.join(failed_reasons)}"

                    failed_entry = EventEntry(
                        event_id=event_buffer.event_counter,
                        event_type="workspace::assignment_failed",
                        timestamp=datetime.now(),
                        source="daemon",
                        window_id=container.id,
                        window_class=window_class,
                        project_name=actual_project if actual_project else None,
                        error=error_summary,
                    )
                    await event_buffer.add_event(failed_entry)

            if not preferred_ws:
                # Feature 053: Delayed property re-check for native Wayland apps (US1 T035-T038)
                # Native Wayland apps (PWAs, native apps) may have empty app_id during window::new event
                # Schedule delayed re-check after 100ms to allow properties to populate
                app_id = getattr(container, 'app_id', None)
                if not app_id or app_id == "" or app_id == "unknown":
                    logger.debug(
                        f"Native Wayland window {window_id} ({window_class}) has no app_id, "
                        f"scheduling 100ms delayed property re-check"
                    )

                    # Schedule async task for delayed re-check
                    asyncio.create_task(
                        _delayed_property_recheck(
                            conn=conn,
                            window_id=window_id,
                            original_class=window_class,
                            application_registry=application_registry,
                            workspace_tracker=workspace_tracker,
                            window_env=window_env,
                            matched_launch=matched_launch,
                        )
                    )

        # Feature 024: Check if matched rule has structured actions
        if classification.matched_rule and hasattr(classification.matched_rule, 'actions') and classification.matched_rule.actions:
            # NEW FORMAT: Execute structured actions
            logger.info(f"Executing {len(classification.matched_rule.actions)} structured actions for window {window_id}")

            # Create WindowInfo for action execution
            window_info = WindowInfo(
                window_id=window_id,
                con_id=container.id,
                window_class=window_class,
                window_title=window_title,
                window_instance=container.window_instance or "",
                app_identifier=window_class,
                project=active_project,
                marks=[],
                workspace=container.workspace().name if container.workspace() else "",
                created=datetime.now(),
            )

            # Execute structured actions
            focus = getattr(classification.matched_rule, 'focus', False)
            await apply_rule_actions(
                conn,
                window_info,
                classification.matched_rule.actions,
                focus=focus,
                event_buffer=event_buffer,
            )
            logger.info(f"Structured actions executed (new format)")

        elif classification.workspace:
            # LEGACY FORMAT: workspace field on classification
            # Feature 046: Use con_id for Sway compatibility
            await conn.command(
                f'[con_id={window_id}] move container to workspace number {classification.workspace}'
            )
            logger.info(f"Moved window {window_id} to workspace {classification.workspace} (legacy format)")

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling window::new event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer (Feature 017)
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="window::new",
                timestamp=datetime.now(),
                source="i3",
                window_id=window_id,
                window_class=window_class,
                window_title=window_title,
                window_instance=container.window_instance or "",
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)
            # Note: event_buffer.add_event() broadcasts via broadcast_event_entry()


async def on_window_mark(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
    ipc_server: Optional["IPCServer"] = None,
    resilient_connection: Optional["ResilientI3Connection"] = None,
) -> None:
    """Handle window::mark events - track mark changes (T015).

    Args:
        conn: i3 async connection
        event: Window event
        state_manager: State manager
        event_buffer: Event buffer for recording events (Feature 017)
        ipc_server: IPC server for broadcasting events to subscribed clients (Feature 025)
        resilient_connection: Connection manager for checking startup scan flag
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    container = event.container
    # Feature 046: Use node ID (container.id) for Sway/Wayland compatibility
    # (container.window is None for native Wayland apps, container.id works for both)
    window_id = container.id
    window_class = get_window_class(container)  # Feature 045: Sway-compatible

    # Feature 053 Phase 6: Comprehensive window::mark event logging
    current_ws = container.workspace()
    log_event_entry(
        "window::mark",
        {
            "window_id": window_id,
            "window_class": window_class,
            "marks": ', '.join(container.marks) if container.marks else "none",
            "workspace_num": current_ws.num if current_ws else "?",
        },
        level="DEBUG"
    )

    try:
        # Skip processing if performing startup scan (prevents race conditions)
        if resilient_connection and resilient_connection.is_performing_startup_scan:
            logger.debug(f"Suppressing window::mark handler during startup scan for window {window_id}")
            return

        # Extract project marks (Feature 061: unified format project:PROJECT_NAME:WINDOW_ID)
        project_marks = [mark for mark in container.marks if mark.startswith("project:")]

        if project_marks:
            # Parse mark: "project:nixos:16777219" → extract "nixos"
            mark_parts = project_marks[0].split(":")
            project_name = mark_parts[1] if len(mark_parts) >= 2 else None
            await state_manager.update_window(window_id, project=project_name, marks=container.marks)
            logger.debug(f"Updated window {window_id} project to {project_name}")
        else:
            # Mark removed
            await state_manager.update_window(window_id, project=None, marks=container.marks)
            logger.debug(f"Removed project mark from window {window_id}")

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling window::mark event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer (Feature 017)
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="window::mark",
                timestamp=datetime.now(),
                source="i3",
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)
            # Note: event_buffer.add_event() broadcasts via broadcast_event_entry()


async def on_window_title(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
    app_classification: Optional["ApplicationClassification"] = None,
    window_rules: Optional[List["WindowRule"]] = None,
    ipc_server: Optional["IPCServer"] = None,
) -> None:
    """Handle window::title events - re-classify window when title changes (US2, T033).

    This is critical for PWA and terminal app classification:
    - PWA patterns (pwa:YouTube) match FFPWA-* class AND title keyword
    - Title patterns (title:^Yazi:) match window title for terminal apps
    - When title changes, classification may change (e.g., terminal opens yazi)

    Args:
        conn: i3 async connection
        event: Window event
        state_manager: State manager
        event_buffer: Event buffer for recording events
        app_classification: App classification config
        window_rules: Window rules for re-classification
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    container = event.container
    # Feature 046: Use node ID (container.id) for Sway/Wayland compatibility
    # (container.window is None for native Wayland apps, container.id works for both)
    window_id = container.id
    window_class = get_window_class(container)  # Feature 045: Sway-compatible
    window_title = container.name or ""

    # Feature 053 Phase 6: Comprehensive window::title event logging
    current_ws = container.workspace()
    log_event_entry(
        "window::title",
        {
            "window_id": window_id,
            "window_class": window_class,
            "new_title": window_title[:50] if window_title else "",
            "workspace_num": current_ws.num if current_ws else "?",
        },
        level="DEBUG"
    )

    try:
        # Get active project for classification
        active_project_name = await state_manager.get_active_project()
        active_project_scoped_classes = None

        if active_project_name and active_project_name in state_manager.state.projects:
            active_project = state_manager.state.projects[active_project_name]
            active_project_scoped_classes = active_project.scoped_classes

        # Re-classify window with new title
        from .pattern_resolver import classify_window

        classification = classify_window(
            window_class=window_class,
            window_title=window_title,
            active_project_scoped_classes=active_project_scoped_classes,
            window_rules=window_rules,
            app_classification_patterns=None,  # TODO: Add pattern support
            app_classification_scoped=list(app_classification.scoped_classes) if app_classification else None,
            app_classification_global=list(app_classification.global_classes) if app_classification else None,
        )

        logger.debug(
            f"Re-classified window {window_id} ({window_class}) "
            f"with title '{window_title}': {classification.scope} "
            f"(source: {classification.source}, workspace: {classification.workspace})"
        )

        # Update window state with new classification
        await state_manager.update_window(
            window_id,
            window_class=window_class,
            title=window_title,
        )

        # Feature 039 FIX: VS Code project mark update on title change
        # VS Code windows inherit I3PM environment from first launch, so title-based
        # project detection is needed when the window title updates
        if window_class == "Code" and window_title:
            # VSCode title formats:
            #   No file: "PROJECT - HOSTNAME - Visual Studio Code"
            #   File open: "FILENAME - PROJECT - HOSTNAME - Visual Studio Code"
            # Strategy: Split by " - " and find first segment matching a known project
            segments = [seg.strip().lower() for seg in window_title.split(" - ")]
            title_project = None

            for segment in segments:
                if segment in state_manager.state.projects:
                    title_project = segment
                    logger.debug(f"Found project '{segment}' in VS Code title: {window_title}")
                    break

            # Check if this matches a known project
            if title_project:
                # Get current project mark
                current_marks = container.marks or []
                # Feature 061: Unified format - only look for "project:" marks
                current_project_marks = [
                    m for m in current_marks
                    if m.startswith("project:")
                ]

                if current_project_marks:
                    # Extract current project from mark
                    # Format: "project:nixos:12345" -> project="nixos"
                    old_mark = current_project_marks[0]
                    mark_parts = old_mark.split(":")
                    current_project = mark_parts[1] if len(mark_parts) >= 2 else None

                    # Update mark if project changed
                    if current_project != title_project:
                        # Remove old mark
                        await conn.command(f'[con_id={window_id}] unmark "{old_mark}"')

                        # Add new mark with unified format
                        new_mark = f"project:{title_project}:{window_id}"
                        await conn.command(f'[con_id={window_id}] mark --add "{new_mark}"')

                        logger.info(
                            f"VSCode window {window_id}: Updated project mark from "
                            f"{current_project} to {title_project} (title-based detection)"
                        )

                        # Update state
                        await state_manager.update_window(
                            window_id,
                            project=title_project,
                            marks=[new_mark] + [m for m in current_marks if not m.startswith("project:")]
                        )

        # If workspace changed, move window
        if classification.workspace is not None:
            current_workspace = container.workspace().name if container.workspace() else None
            target_workspace = str(classification.workspace)

            if current_workspace != target_workspace:
                logger.info(
                    f"Moving window {window_id} to workspace {target_workspace} "
                    f"(title changed, new classification)"
                )
                await conn.command(f'[con_id="{container.id}"] move container to workspace {target_workspace}')

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling window::title event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="window::title",
                timestamp=datetime.now(),
                source="i3",
                window_id=window_id,
                window_class=window_class,
                window_title=window_title,
                window_instance=container.window_instance or "",
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)
            # Note: event_buffer.add_event() broadcasts via broadcast_event_entry()


async def on_window_close(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
    ipc_server: Optional["IPCServer"] = None,
) -> None:
    """Handle window::close events - remove from tracking (T016).

    Args:
        conn: i3 async connection
        event: Window event
        state_manager: State manager
        event_buffer: Event buffer for recording events (Feature 017)
        ipc_server: IPC server for broadcasting events to subscribed clients (Feature 025)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    container = event.container
    # Feature 046: Use node ID (container.id) for Sway/Wayland compatibility
    # (container.window is None for native Wayland apps, container.id works for both)
    window_id = container.id
    window_class = get_window_class(container)  # Feature 045: Sway-compatible

    # Feature 053 Phase 6: Comprehensive window::close event logging
    current_ws = container.workspace()
    log_event_entry(
        "window::close",
        {
            "window_id": window_id,
            "window_class": window_class,
            "workspace_num": current_ws.num if current_ws else "?",
            "workspace_name": current_ws.name if current_ws else "?",
        },
        level="DEBUG"
    )

    try:
        await state_manager.remove_window(window_id)
        logger.debug(f"Removed closed window {window_id}")

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling window::close event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer (Feature 017)
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="window::close",
                timestamp=datetime.now(),
                source="i3",
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            event_buffer.add_event(entry)
            # Note: event_buffer.add_event() broadcasts via broadcast_event_entry()


async def on_window_focus(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
    ipc_server: Optional["IPCServer"] = None,
) -> None:
    """Handle window::focus events - update focus timestamp (T017).

    Args:
        conn: i3 async connection
        event: Window event
        state_manager: State manager
        event_buffer: Event buffer for recording events (Feature 017)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    container = event.container
    # Feature 046: Use node ID (container.id) for Sway/Wayland compatibility
    # (container.window is None for native Wayland apps, container.id works for both)
    window_id = container.id
    window_class = get_window_class(container)  # Feature 045: Sway-compatible

    # Feature 053 Phase 6: Comprehensive window::focus event logging
    current_ws = container.workspace()
    log_event_entry(
        "window::focus",
        {
            "window_id": window_id,
            "window_class": window_class,
            "workspace_num": current_ws.num if current_ws else "?",
            "workspace_name": current_ws.name if current_ws else "?",
        },
        level="DEBUG"
    )

    try:
        await state_manager.update_window(window_id, last_focus=datetime.now())
        logger.debug(f"Updated focus timestamp for window {window_id}")

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling window::focus event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer (Feature 017)
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="window::focus",
                timestamp=datetime.now(),
                source="i3",
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)
            # Note: event_buffer.add_event() broadcasts via broadcast_event_entry()


async def on_window_move(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    workspace_tracker,  # Feature 037 T020: Workspace tracking
    event_buffer: Optional["EventBuffer"] = None,
    ipc_server: Optional["IPCServer"] = None,
) -> None:
    """Handle window::move events - track workspace changes for restoration.

    Feature 037 T020: When users manually move windows between workspaces,
    update the workspace tracker so windows return to their new locations
    when project is restored.

    Args:
        conn: i3 async connection
        event: Window event
        state_manager: State manager
        workspace_tracker: WorkspaceTracker for window filtering (Feature 037)
        event_buffer: Event buffer for recording events (Feature 017)
        ipc_server: IPC server for broadcasting events (Feature 025)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    container = event.container
    window_id = container.id
    window_class = get_window_class(container)  # Feature 045: Sway-compatible

    try:
        # Get workspace information
        workspace = container.workspace()
        if not workspace:
            logger.debug(f"Window {window_id} has no workspace, skipping tracking")
            return

        workspace_num = workspace.num
        is_floating = container.floating == "user_on" or container.floating == "auto_on"

        # Feature 053 Phase 6: Comprehensive window::move event logging
        log_event_entry(
            "window::move",
            {
                "window_id": window_id,
                "window_class": window_class,
                "target_workspace_num": workspace_num,
                "target_workspace_name": workspace.name,
                "floating": is_floating,
            },
            level="DEBUG"
        )

        # Feature 037 T020: Update workspace tracker with new location
        if workspace_tracker:
            from . import window_filtering

            # Read I3PM environment variables to get project info
            i3pm_env = await window_filtering.get_window_i3pm_env(window_id, container.pid, container.window)
            project_name = i3pm_env.get("I3PM_PROJECT_NAME", "")
            app_name = i3pm_env.get("I3PM_APP_NAME", "unknown")

            # Track the new workspace assignment
            await workspace_tracker.track_window(
                window_id=window_id,
                workspace_number=workspace_num,
                floating=is_floating,
                project_name=project_name,
                app_name=app_name,
                window_class=window_class,
            )

            # Save updated tracking immediately (T024 will add atomic writes)
            await workspace_tracker.save()

            logger.debug(
                f"Tracked window move: {window_id} ({window_class}) → workspace {workspace_num}, "
                f"floating={is_floating}, project={project_name}"
            )

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling window::move event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer (Feature 017)
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="window::move",
                timestamp=datetime.now(),
                source="i3",
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)
            # Note: event_buffer.add_event() broadcasts via broadcast_event_entry()


# ============================================================================
# USER STORY 3 (P3): Workspace State Monitoring
# ============================================================================


async def on_workspace_init(
    conn: aio.Connection, event: WorkspaceEvent, state_manager: StateManager
) -> None:
    """Handle workspace::init events - track new workspaces (T023).

    Args:
        conn: i3 async connection
        event: Workspace event
        state_manager: State manager
    """
    try:
        current = event.current

        # Feature 053 Phase 6: Comprehensive workspace event logging
        log_event_entry(
            "workspace::init",
            {
                "workspace_name": current.name,
                "workspace_num": current.num,
                "output": current.ipc_data.get("output", ""),
                "visible": True,
                "focused": True,
            },
            level="DEBUG"
        )

        workspace_info = WorkspaceInfo(
            name=current.name,
            num=current.num,
            output=current.ipc_data.get("output", ""),
            visible=True,
            focused=True,
        )
        await state_manager.add_workspace(workspace_info)
        logger.debug(f"Added workspace {current.name}")

    except Exception as e:
        logger.error(f"Error handling workspace::init event: {e}")
        await state_manager.increment_error_count()


async def on_workspace_empty(
    conn: aio.Connection, event: WorkspaceEvent, state_manager: StateManager
) -> None:
    """Handle workspace::empty events - remove empty workspaces (T024).

    Args:
        conn: i3 async connection
        event: Workspace event
        state_manager: State manager
    """
    try:
        current = event.current

        # Feature 053 Phase 6: Comprehensive workspace event logging
        log_event_entry(
            "workspace::empty",
            {
                "workspace_name": current.name,
                "workspace_num": current.num,
                "output": current.ipc_data.get("output", ""),
            },
            level="DEBUG"
        )

        await state_manager.remove_workspace(current.name)
        logger.debug(f"Removed workspace {current.name}")

    except Exception as e:
        logger.error(f"Error handling workspace::empty event: {e}")
        await state_manager.increment_error_count()


async def on_workspace_move(
    conn: aio.Connection, event: WorkspaceEvent, state_manager: StateManager
) -> None:
    """Handle workspace::move events - update workspace output (T025).

    Args:
        conn: i3 async connection
        event: Workspace event
        state_manager: State manager
    """
    try:
        current = event.current
        new_output = current.ipc_data.get("output", "")

        # Feature 053 Phase 6: Comprehensive workspace event logging
        old = event.old if hasattr(event, 'old') else None
        log_event_entry(
            "workspace::move",
            {
                "workspace_name": current.name,
                "workspace_num": current.num,
                "old_output": old.ipc_data.get("output", "?") if old else "?",
                "new_output": new_output,
                "visible": current.ipc_data.get("visible", False),
                "focused": current.ipc_data.get("focused", False),
            },
            level="INFO"
        )

        # Update workspace output
        # (StateManager doesn't have direct update method for workspaces, recreate)
        workspace_info = WorkspaceInfo(
            name=current.name,
            num=current.num,
            output=new_output,
            visible=current.ipc_data.get("visible", False),
            focused=current.ipc_data.get("focused", False),
        )
        await state_manager.add_workspace(workspace_info)
        logger.info(f"Workspace {current.name} moved to output {new_output}")

    except Exception as e:
        logger.error(f"Error handling workspace::move event: {e}")
        await state_manager.increment_error_count()


# ============================================================================
# Feature 024: Multi-Monitor Output Event Handling
# ============================================================================


async def _perform_workspace_reassignment(
    conn: aio.Connection,
    active_outputs: list,
) -> None:
    """Perform workspace reassignment after debounce delay.

    Feature 033: T036-T038
    Called after debounce_ms delay to reassign workspaces based on config.

    Args:
        conn: i3 async connection
        active_outputs: List of active outputs from i3
    """
    try:
        from .monitor_config_manager import MonitorConfigManager
        from .workspace_manager import get_monitor_configs, assign_workspaces_to_monitors

        # Load configuration
        config_manager = MonitorConfigManager()
        config = config_manager.load_config()

        # Check if auto-reassign is enabled
        if not config.enable_auto_reassign:
            logger.info("Auto-reassign disabled in config - skipping workspace redistribution")
            return

        # Get monitor configurations with assigned roles
        monitors = await get_monitor_configs(conn, config_manager)

        if not monitors:
            logger.warning("No active monitors found - skipping workspace reassignment")
            return

        monitor_count = len(monitors)
        logger.info(f"Reassigning workspaces for {monitor_count} monitor(s)")

        # Assign workspaces to monitors based on configuration
        await assign_workspaces_to_monitors(conn, monitors, config_manager=config_manager)

        # Get workspace distribution for logging
        distribution = config_manager.get_workspace_distribution(monitor_count)
        total_workspaces = sum(len(ws_list) for ws_list in distribution.values())

        logger.info(
            f"Workspace reassignment complete: {total_workspaces} workspaces "
            f"distributed across {monitor_count} monitor(s)"
        )

    except Exception as e:
        logger.error(f"Error during workspace reassignment: {e}")


async def _schedule_workspace_reassignment(
    conn: aio.Connection,
    active_outputs: list,
) -> None:
    """Schedule workspace reassignment with debouncing.

    Feature 033: T036 (debouncing)
    Ensures that rapid monitor changes don't trigger multiple reassignments.

    Args:
        conn: i3 async connection
        active_outputs: List of active outputs from i3
    """
    global _output_change_task, _last_output_event_time

    try:
        from .monitor_config_manager import MonitorConfigManager

        # Load configuration for debounce settings
        config_manager = MonitorConfigManager()
        config = config_manager.load_config()
        debounce_ms = config.debounce_ms

        # Update last event time
        _last_output_event_time = time.time()

        # Cancel existing task if one is pending
        if _output_change_task and not _output_change_task.done():
            _output_change_task.cancel()
            logger.debug(f"Cancelled pending workspace reassignment task")

        # Schedule new task after debounce delay
        async def _debounced_reassignment():
            await asyncio.sleep(debounce_ms / 1000.0)
            await _perform_workspace_reassignment(conn, active_outputs)

        _output_change_task = asyncio.create_task(_debounced_reassignment())
        logger.debug(f"Scheduled workspace reassignment after {debounce_ms}ms")

    except Exception as e:
        logger.error(f"Error scheduling workspace reassignment: {e}")


async def _debounced_workspace_reassignment(
    conn: aio.Connection,
    active_outputs: List,
) -> None:
    """Execute workspace reassignment after debounce delay (Feature 001: T033, T034).

    This function is called after the debounce timer expires. It triggers
    Feature 001's workspace-to-monitor assignment with automatic fallback logic.

    Args:
        conn: i3 async connection
        active_outputs: List of active outputs from Sway IPC
    """
    global _output_debounce_task

    try:
        # Wait for debounce timer (500ms)
        await asyncio.sleep(_output_debounce_timer)

        logger.info(
            f"[Feature 001] Debounce complete - Reassigning workspaces with {len(active_outputs)} active output(s)"
        )

        # Feature 001: Use monitor role-based workspace assignment
        from .workspace_manager import assign_workspaces_with_monitor_roles

        await assign_workspaces_with_monitor_roles(conn)

        logger.info("[Feature 001] Workspace reassignment complete")

    except Exception as e:
        logger.error(f"[Feature 001] Error in debounced workspace reassignment: {e}")
    finally:
        _output_debounce_task = None


async def on_output(
    conn: aio.Connection,
    event: OutputEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
    workspace_mode_manager=None,
) -> None:
    """Handle output events - monitor connect/disconnect (Feature 024: R012, Feature 001: US2).

    Detects when monitors are connected or disconnected and triggers debounced
    workspace reassignment using Feature 001's monitor role system.

    Args:
        conn: i3 async connection
        event: Output event (mode change, connect, disconnect)
        state_manager: State manager
        event_buffer: Event buffer for recording events (Feature 017)
        workspace_mode_manager: WorkspaceModeManager instance (Feature 042)
    """
    global _output_debounce_task

    start_time = time.perf_counter()
    error_msg: Optional[str] = None

    try:
        # Re-query monitor/output configuration
        outputs = await conn.get_outputs()
        active_outputs = [o for o in outputs if o.active]

        # Feature 053 Phase 6: Comprehensive output event logging
        log_event_entry(
            "output",
            {
                "active_outputs": len(active_outputs),
                "output_names": ', '.join(o.name for o in active_outputs),
                "total_outputs": len(outputs),
                "resolutions": ', '.join(
                    f"{o.name}:{o.rect.width}x{o.rect.height}"
                    for o in active_outputs
                ),
            },
            level="INFO"
        )

        logger.info(
            f"[Feature 001] Output event detected: {len(active_outputs)} active outputs - "
            f"{', '.join(o.name for o in active_outputs)}"
        )

        # Log configuration changes for debugging
        for output in outputs:
            if output.active:
                logger.debug(
                    f"  Active output: {output.name} ({output.rect.width}x{output.rect.height})"
                )
            else:
                logger.debug(f"  Inactive output: {output.name}")

        # Feature 042: Refresh workspace mode output cache on monitor changes
        if workspace_mode_manager:
            await workspace_mode_manager._refresh_output_cache()
            logger.debug("Workspace mode output cache refreshed")

        # Feature 001 T033: Cancel existing debounce task if present
        if _output_debounce_task and not _output_debounce_task.done():
            logger.debug("[Feature 001] Cancelling previous debounce task")
            _output_debounce_task.cancel()
            try:
                await _output_debounce_task
            except asyncio.CancelledError:
                pass

        # Feature 001 T034: Schedule debounced workspace reassignment
        logger.debug(f"[Feature 001] Scheduling workspace reassignment (debounce: {_output_debounce_timer * 1000:.0f}ms)")
        _output_debounce_task = asyncio.create_task(
            _debounced_workspace_reassignment(conn, active_outputs)
        )

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling output event: {e}")
        await state_manager.increment_error_count()

    finally:
        # Record event in buffer (Feature 017)
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="output",
                timestamp=datetime.now(),
                source="i3",
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)


async def on_mode(
    conn,
    event,
    workspace_mode_manager=None,
    ipc_server=None,
    event_buffer=None,
    state_manager=None,
):
    """Handle Sway mode change events (Feature 042).

    Args:
        conn: i3/Sway IPC connection
        event: Mode change event
        workspace_mode_manager: WorkspaceModeManager instance (Feature 042)
        ipc_server: IPC server for event broadcasting
        event_buffer: Event buffer for recording events
        state_manager: State manager
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    mode_name = event.change

    try:
        # Feature 053 Phase 6: Comprehensive mode event logging
        log_event_entry(
            "mode",
            {
                "mode_name": mode_name,
                "workspace_mode_active": workspace_mode_manager.state.active if workspace_mode_manager else False,
            },
            level="DEBUG"
        )

        logger.debug(f"Mode event: {mode_name}")

        # Feature 042: Workspace mode navigation
        if workspace_mode_manager and ipc_server:
            # Support both old (goto_workspace) and new (→ WS) mode names for compatibility
            if mode_name in ("goto_workspace", "→ WS"):
                logger.info("Entering workspace goto mode")
                await workspace_mode_manager.enter_mode("goto")
                event_payload = workspace_mode_manager.create_event("enter")
                await ipc_server.broadcast_event({"type": "workspace_mode", **event_payload.model_dump()})

            elif mode_name in ("move_workspace", "⇒ WS"):
                logger.info("Entering workspace move mode")
                await workspace_mode_manager.enter_mode("move")
                event_payload = workspace_mode_manager.create_event("enter")
                await ipc_server.broadcast_event({"type": "workspace_mode", **event_payload.model_dump()})

            elif mode_name == "default":
                # User exited workspace mode (Escape or successful execution)
                if workspace_mode_manager.state.active:
                    logger.info("Exiting workspace mode")
                    await workspace_mode_manager.cancel()
                    event_payload = workspace_mode_manager.create_event("exit")
                    await ipc_server.broadcast_event({"type": "workspace_mode", **event_payload.model_dump()})

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error handling mode event: {e}")
        if state_manager:
            await state_manager.increment_error_count()

    finally:
        # Record event in buffer
        if event_buffer:
            duration_ms = (time.perf_counter() - start_time) * 1000
            entry = EventEntry(
                event_id=event_buffer.event_counter,
                event_type="mode",
                timestamp=datetime.now(),
                source="i3",
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)
# Force rebuild Tue Nov  4 06:38:24 AM EST 2025
