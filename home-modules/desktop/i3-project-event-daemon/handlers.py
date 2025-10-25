"""Event handlers for i3 window/workspace/tick events.

This module contains all event handlers that process i3 IPC events.
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

    logger.info(f"Switching project: {old_project} → {project_name}")

    # Feature 037: Use new window filtering if workspace_tracker is available
    if workspace_tracker:
        from . import window_filtering
        start_time = time.perf_counter()

        # Hide windows from old project (if any)
        windows_hidden = 0
        if old_project:
            # Get all visible windows for old project
            tree = await conn.get_tree()
            window_ids_to_hide = []

            async def collect_old_project_windows(con):
                if con.window and hasattr(con, 'id'):
                    i3pm_env = await window_filtering.get_window_i3pm_env(con.id, con.pid)
                    window_project = i3pm_env.get("I3PM_PROJECT_NAME", "")
                    scope = i3pm_env.get("I3PM_SCOPE", "global")

                    if window_project == old_project and scope == "scoped":
                        window_ids_to_hide.append(con.id)

                for child in con.nodes:
                    await collect_old_project_windows(child)
                for child in con.floating_nodes:
                    await collect_old_project_windows(child)

            await collect_old_project_windows(tree)

            # Hide windows in batch
            hidden_count, hide_errors = await window_filtering.hide_windows_batch(
                conn, window_ids_to_hide, workspace_tracker
            )
            windows_hidden = hidden_count
            if hide_errors:
                logger.warning(f"Errors hiding windows: {hide_errors}")

        # Restore windows for new project
        scratchpad_windows = await window_filtering.get_scratchpad_windows(conn)
        window_ids_to_restore = []

        for window in scratchpad_windows:
            i3pm_env = await window_filtering.get_window_i3pm_env(window.id, window.pid)
            window_project = i3pm_env.get("I3PM_PROJECT_NAME", "")

            if window_project == project_name:
                window_ids_to_restore.append(window.id)

        # Restore windows in batch
        restored_count, restore_errors, fallback_warnings = await window_filtering.restore_windows_batch(
            conn, window_ids_to_restore, workspace_tracker, fallback_workspace=1
        )

        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.info(
            f"Window filtering complete: hidden {windows_hidden}, restored {restored_count} "
            f"({duration_ms:.1f}ms)"
        )

        if restore_errors:
            logger.warning(f"Errors restoring windows: {restore_errors}")
        if fallback_warnings:
            logger.info(f"Workspace fallbacks: {fallback_warnings}")

    else:
        # Legacy path (Feature 035 and earlier): Use old hide/show methods
        logger.info("Using legacy window management (workspace_tracker not available)")

        # Hide windows from old project
        if old_project:
            old_windows = await state_manager.get_windows_by_project(old_project)
            await hide_project_windows(conn, old_windows)

        # Show windows from new project
        new_windows = await state_manager.get_windows_by_project(project_name)
        await show_project_windows(conn, new_windows)

    # Update active project
    await state_manager.set_active_project(project_name)

    # Save to config file
    from .models import ActiveProjectState

    state = ActiveProjectState(
        project_name=project_name,
        activated_at=datetime.now(),
        previous_project=old_project,
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
        project_name=None, activated_at=datetime.now(), previous_project=old_project
    )
    save_active_project(state, config_dir / "active-project.json")


async def hide_window(conn: aio.Connection, window_id: int) -> None:
    """Hide a window by moving it to scratchpad (T008).

    Args:
        conn: i3 async connection
        window_id: Window ID to hide
    """
    try:
        await conn.command(f"[id={window_id}] move scratchpad")
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
        await conn.command(f"[id={window_id}] move container to workspace {workspace}")
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
    window_id = container.window
    window_class = container.window_class or "unknown"
    window_title = container.name or ""

    # DEBUG: Log all window::new events
    logger.info(f"✓ WINDOW::NEW HANDLER CALLED: {window_id} ({window_class})")

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

        # Feature 035: Read I3PM_* environment variables from /proc/<pid>/environ
        # This enables deterministic window-to-project association
        from .services.window_filter import get_window_environment
        window_env = await get_window_environment(window_id)

        # If window has I3PM environment, use it for project association
        # This replaces tag-based filtering with environment-based approach
        actual_project = None
        if window_env and window_env.project_name:
            actual_project = window_env.project_name
            logger.info(
                f"Window {window_id} has I3PM environment: "
                f"app={window_env.app_name}, project={actual_project}, "
                f"scope={window_env.scope}, instance_id={window_env.app_id}"
            )
        else:
            # No I3PM environment → assume global scope
            actual_project = None
            logger.debug(f"Window {window_id} has no I3PM environment, assuming global scope")

        # If scoped and we have an actual project from environment, apply project mark
        if classification.scope == "scoped" and actual_project:
            mark = f"project:{actual_project}"
            await conn.command(f'[id={window_id}] mark --add "{mark}"')
            logger.info(f"Marked window {window_id} with {mark} (from I3PM environment)")

            # Add to state (mark event will update this)
            # Feature 035: Use actual_project from I3PM environment
            window_info = WindowInfo(
                window_id=window_id,
                con_id=container.id,
                window_class=window_class,
                window_title=window_title,
                window_instance=container.window_instance or "",
                app_identifier=window_env.app_name if window_env else window_class,
                project=actual_project,  # Use environment-determined project
                marks=[mark],
                workspace=container.workspace().name if container.workspace() else "",
                created=datetime.now(),
            )
            await state_manager.add_window(window_info)

        # Feature 037 T026-T029: Guaranteed workspace assignment on launch
        # If window has I3PM_APP_NAME, look up preferred workspace in registry
        if window_env and window_env.app_name and application_registry:
            app_name = window_env.app_name
            app_def = application_registry.get(app_name)

            if app_def and "preferred_workspace" in app_def:
                preferred_ws = app_def["preferred_workspace"]
                current_workspace = container.workspace()

                # T028: Check if window is already on preferred workspace
                if current_workspace and current_workspace.num != preferred_ws:
                    # Move window to preferred workspace
                    try:
                        await conn.command(
                            f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
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
                                app_name=app_name,
                                window_class=window_class,
                            )
                            await workspace_tracker.save()

                        # T029: Log workspace assignment
                        logger.info(
                            f"Moved window {window_id} ({window_class}/{app_name}) from workspace "
                            f"{current_workspace.num} to preferred workspace {preferred_ws}"
                        )

                    except Exception as e:
                        logger.error(f"Failed to move window {window_id} to workspace {preferred_ws}: {e}")
                else:
                    # Already on correct workspace, but still track it
                    if workspace_tracker and current_workspace:
                        from . import window_filtering
                        is_floating = container.floating == "user_on" or container.floating == "auto_on"

                        await workspace_tracker.track_window(
                            window_id=container.id,
                            workspace_number=current_workspace.num,
                            floating=is_floating,
                            project_name=actual_project if actual_project else "",
                            app_name=app_name,
                            window_class=window_class,
                        )
                        await workspace_tracker.save()

                        logger.debug(
                            f"Window {window_id} ({app_name}) already on preferred workspace {preferred_ws}"
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
            await conn.command(
                f'[id={window_id}] move container to workspace number {classification.workspace}'
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
) -> None:
    """Handle window::mark events - track mark changes (T015).

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
    window_id = container.window
    window_class = container.window_class or "unknown"

    try:
        # Extract project marks
        project_marks = [mark for mark in container.marks if mark.startswith("project:")]

        if project_marks:
            project_name = project_marks[0].split(":", 1)[1]
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
    window_id = container.window
    window_class = container.window_class or "unknown"
    window_title = container.name or ""

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
    window_id = container.window
    window_class = container.window_class or "unknown"

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
    window_id = container.window
    window_class = container.window_class or "unknown"

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
    window_class = container.window_class or "unknown"

    try:
        # Get workspace information
        workspace = container.workspace()
        if not workspace:
            logger.debug(f"Window {window_id} has no workspace, skipping tracking")
            return

        workspace_num = workspace.num
        is_floating = container.floating == "user_on" or container.floating == "auto_on"

        # Feature 037 T020: Update workspace tracker with new location
        if workspace_tracker:
            from . import window_filtering

            # Read I3PM environment variables to get project info
            i3pm_env = await window_filtering.get_window_i3pm_env(window_id, container.pid)
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


async def on_output(
    conn: aio.Connection,
    event: OutputEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
) -> None:
    """Handle output events - monitor connect/disconnect (Feature 024: R012).

    Detects when monitors are connected or disconnected and re-queries
    workspace distribution to ensure workspaces are properly assigned.

    Args:
        conn: i3 async connection
        event: Output event (mode change, connect, disconnect)
        state_manager: State manager
        event_buffer: Event buffer for recording events (Feature 017)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None

    try:
        # Re-query monitor/output configuration
        outputs = await conn.get_outputs()
        active_outputs = [o for o in outputs if o.active]

        logger.info(
            f"Output event detected: {len(active_outputs)} active outputs - "
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

        # Feature 033: Automatic workspace reassignment on monitor changes (T036-T038)
        await _schedule_workspace_reassignment(conn, active_outputs)

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
