"""Event handlers for i3 window/workspace/tick events.

This module contains all event handlers that process i3 IPC events.
"""

import asyncio
import logging
import time
from datetime import datetime
from typing import Optional, TYPE_CHECKING, List
from i3ipc import aio, TickEvent, WindowEvent, WorkspaceEvent

from .state import StateManager
from .models import WindowInfo, WorkspaceInfo, ApplicationClassification, EventEntry
from .config import save_active_project, load_active_project
from .pattern_resolver import classify_window, Classification
from .window_rules import WindowRule
from pathlib import Path

if TYPE_CHECKING:
    from .event_buffer import EventBuffer

logger = logging.getLogger(__name__)


# ============================================================================
# USER STORY 1 (P1): Real-time Project State Updates
# ============================================================================


async def on_tick(
    conn: aio.Connection,
    event: TickEvent,
    state_manager: StateManager,
    config_dir: Path,
    event_buffer: Optional["EventBuffer"] = None,
) -> None:
    """Handle tick events for project switch notifications (T007).

    Args:
        conn: i3 async IPC connection
        event: Tick event containing payload
        state_manager: State manager instance
        config_dir: Configuration directory path
        event_buffer: Event buffer for recording events (Feature 017)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None

    try:
        payload = event.payload
        logger.info(f"✓ TICK EVENT RECEIVED: {payload}")  # Changed to INFO to ensure visibility
        logger.debug(f"Received tick event: {payload}")

        if payload.startswith("project:"):
            project_name = payload.split(":", 1)[1]

            if project_name == "none":
                # Clear active project (global mode)
                await _clear_project(state_manager, conn, config_dir)
            elif project_name == "reload":
                # Reload project configs
                logger.info("Reloading project configurations...")
                # TODO: Implement config reload
            else:
                # Switch to specified project
                await _switch_project(project_name, state_manager, conn, config_dir)

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
                tick_payload=event.payload,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)


async def _switch_project(
    project_name: str, state_manager: StateManager, conn: aio.Connection, config_dir: Path
) -> None:
    """Switch to a new project (hide old, show new).

    Args:
        project_name: Name of project to switch to
        state_manager: State manager instance
        conn: i3 async connection
        config_dir: Config directory
    """
    # Get current active project
    old_project = await state_manager.get_active_project()

    if old_project == project_name:
        logger.info(f"Already on project {project_name}")
        return

    logger.info(f"Switching project: {old_project} → {project_name}")

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
) -> None:
    """Handle window::new events - auto-mark and classify new windows (T014, T023).

    Uses the 4-level precedence classification system:
    1. Project scoped_classes (priority 1000)
    2. Window rules (priority 200-500)
    3. App classification patterns (priority 100)
    4. App classification lists (priority 50)

    Args:
        conn: i3 async connection
        event: Window event
        state_manager: State manager
        app_classification: Application classification config
        event_buffer: Event buffer for recording events (Feature 017)
        window_rules: Window rules from window-rules.json (Feature 021)
    """
    start_time = time.perf_counter()
    error_msg: Optional[str] = None
    container = event.container
    window_id = container.window
    window_class = container.window_class or "unknown"
    window_title = container.name or ""

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

        # If scoped and we have an active project, apply project mark
        if classification.scope == "scoped" and active_project:
            mark = f"project:{active_project}"
            await conn.command(f'[id={window_id}] mark --add "{mark}"')
            logger.info(f"Marked window {window_id} with {mark}")

            # Add to state (mark event will update this)
            window_info = WindowInfo(
                window_id=window_id,
                con_id=container.id,
                window_class=window_class,
                window_title=window_title,
                window_instance=container.window_instance or "",
                app_identifier=window_class,
                project=active_project,
                marks=[mark],
                workspace=container.workspace().name if container.workspace() else "",
                created=datetime.now(),
            )
            await state_manager.add_window(window_info)

        # If rule specifies a workspace, move window to that workspace
        if classification.workspace:
            await conn.command(
                f'[id={window_id}] move container to workspace number {classification.workspace}'
            )
            logger.info(f"Moved window {window_id} to workspace {classification.workspace}")

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
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)


async def on_window_mark(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
) -> None:
    """Handle window::mark events - track mark changes (T015).

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
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)


async def on_window_title(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
    app_classification: Optional["ApplicationClassification"] = None,
    window_rules: Optional[List["WindowRule"]] = None,
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

        if active_project_name:
            active_project = await state_manager.get_project(active_project_name)
            if active_project:
                active_project_scoped_classes = active_project.scoped_classes

        # Re-classify window with new title
        from .pattern_resolver import classify_window

        app_patterns = app_classification.class_patterns if app_classification else None
        app_scoped = list(app_classification.scoped_classes) if app_classification else None
        app_global = list(app_classification.global_classes) if app_classification else None

        classification = classify_window(
            window_class=window_class,
            window_title=window_title,
            active_project_scoped_classes=active_project_scoped_classes,
            window_rules=window_rules,
            app_classification_patterns=app_patterns,
            app_classification_scoped=app_scoped,
            app_classification_global=app_global,
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
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
                details={"new_title": window_title} if window_title else None,
            )
            await event_buffer.add_event(entry)


async def on_window_close(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
) -> None:
    """Handle window::close events - remove from tracking (T016).

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
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            event_buffer.add_event(entry)


async def on_window_focus(
    conn: aio.Connection,
    event: WindowEvent,
    state_manager: StateManager,
    event_buffer: Optional["EventBuffer"] = None,
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
                window_id=window_id,
                window_class=window_class,
                workspace_name=container.workspace().name if container.workspace() else None,
                project_name=await state_manager.get_active_project(),
                processing_duration_ms=duration_ms,
                error=error_msg,
            )
            await event_buffer.add_event(entry)


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
