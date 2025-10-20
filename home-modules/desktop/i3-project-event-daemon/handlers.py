"""Event handlers for i3 window/workspace/tick events.

This module contains all event handlers that process i3 IPC events.
"""

import asyncio
import logging
from datetime import datetime
from typing import Optional
import i3ipc

from .state import StateManager
from .models import WindowInfo, WorkspaceInfo, ApplicationClassification
from .config import save_active_project, load_active_project
from pathlib import Path

logger = logging.getLogger(__name__)


# ============================================================================
# USER STORY 1 (P1): Real-time Project State Updates
# ============================================================================


async def on_tick(
    conn: i3ipc.Connection,
    event: i3ipc.TickEvent,
    state_manager: StateManager,
    config_dir: Path,
) -> None:
    """Handle tick events for project switch notifications (T007).

    Args:
        conn: i3 IPC connection
        event: Tick event containing payload
        state_manager: State manager instance
        config_dir: Configuration directory path
    """
    try:
        payload = event.payload
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

    except Exception as e:
        logger.error(f"Error handling tick event: {e}")
        await state_manager.increment_error_count()


async def _switch_project(
    project_name: str, state_manager: StateManager, conn: i3ipc.Connection, config_dir: Path
) -> None:
    """Switch to a new project (hide old, show new).

    Args:
        project_name: Name of project to switch to
        state_manager: State manager instance
        conn: i3 connection
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
    state_manager: StateManager, conn: i3ipc.Connection, config_dir: Path
) -> None:
    """Clear active project (global mode).

    Args:
        state_manager: State manager instance
        conn: i3 connection
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


async def hide_window(conn: i3ipc.Connection, window_id: int) -> None:
    """Hide a window by moving it to scratchpad (T008).

    Args:
        conn: i3 connection
        window_id: Window ID to hide
    """
    try:
        conn.command(f"[id={window_id}] move scratchpad")
        logger.debug(f"Hid window {window_id}")
    except Exception as e:
        logger.error(f"Failed to hide window {window_id}: {e}")


async def show_window(conn: i3ipc.Connection, window_id: int, workspace: str) -> None:
    """Show a window by moving it to a workspace (T008).

    Args:
        conn: i3 connection
        window_id: Window ID to show
        workspace: Workspace to move window to
    """
    try:
        conn.command(f"[id={window_id}] move container to workspace {workspace}")
        logger.debug(f"Showed window {window_id} on workspace {workspace}")
    except Exception as e:
        logger.error(f"Failed to show window {window_id}: {e}")


async def hide_project_windows(conn: i3ipc.Connection, windows: list[WindowInfo]) -> None:
    """Batch hide windows belonging to a project (T008).

    Args:
        conn: i3 connection
        windows: List of WindowInfo objects to hide
    """
    for window_info in windows:
        await hide_window(conn, window_info.window_id)


async def show_project_windows(conn: i3ipc.Connection, windows: list[WindowInfo]) -> None:
    """Batch show windows belonging to a project (T008).

    Args:
        conn: i3 connection
        windows: List of WindowInfo objects to show
    """
    for window_info in windows:
        await show_window(conn, window_info.window_id, window_info.workspace)


# ============================================================================
# USER STORY 2 (P2): Automatic Window Tracking
# ============================================================================


async def on_window_new(
    conn: i3ipc.Connection,
    event: i3ipc.WindowEvent,
    state_manager: StateManager,
    app_classification: ApplicationClassification,
) -> None:
    """Handle window::new events - auto-mark new windows (T014).

    Args:
        conn: i3 connection
        event: Window event
        state_manager: State manager
        app_classification: Application classification config
    """
    try:
        container = event.container
        active_project = await state_manager.get_active_project()

        # Check if we should mark this window
        if not active_project:
            logger.debug(f"No active project, not marking window {container.window}")
            return

        window_class = container.window_class or "unknown"
        if window_class not in app_classification.scoped_classes:
            logger.debug(f"Window class {window_class} is not scoped, not marking")
            return

        # Apply project mark
        mark = f"project:{active_project}"
        conn.command(f'[id={container.window}] mark --add "{mark}"')
        logger.info(f"Marked window {container.window} with {mark}")

        # Add to state (mark event will update this)
        window_info = WindowInfo(
            window_id=container.window,
            con_id=container.id,
            window_class=window_class,
            window_title=container.name or "",
            window_instance=container.window_instance or "",
            app_identifier=window_class,
            project=active_project,
            marks=[mark],
            workspace=container.workspace().name if container.workspace() else "",
            created=datetime.now(),
        )
        await state_manager.add_window(window_info)

    except Exception as e:
        logger.error(f"Error handling window::new event: {e}")
        await state_manager.increment_error_count()


async def on_window_mark(
    conn: i3ipc.Connection, event: i3ipc.WindowEvent, state_manager: StateManager
) -> None:
    """Handle window::mark events - track mark changes (T015).

    Args:
        conn: i3 connection
        event: Window event
        state_manager: State manager
    """
    try:
        container = event.container
        window_id = container.window

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
        logger.error(f"Error handling window::mark event: {e}")
        await state_manager.increment_error_count()


async def on_window_close(
    conn: i3ipc.Connection, event: i3ipc.WindowEvent, state_manager: StateManager
) -> None:
    """Handle window::close events - remove from tracking (T016).

    Args:
        conn: i3 connection
        event: Window event
        state_manager: State manager
    """
    try:
        window_id = event.container.window
        await state_manager.remove_window(window_id)
        logger.debug(f"Removed closed window {window_id}")

    except Exception as e:
        logger.error(f"Error handling window::close event: {e}")
        await state_manager.increment_error_count()


async def on_window_focus(
    conn: i3ipc.Connection, event: i3ipc.WindowEvent, state_manager: StateManager
) -> None:
    """Handle window::focus events - update focus timestamp (T017).

    Args:
        conn: i3 connection
        event: Window event
        state_manager: State manager
    """
    try:
        window_id = event.container.window
        await state_manager.update_window(window_id, last_focus=datetime.now())
        logger.debug(f"Updated focus timestamp for window {window_id}")

    except Exception as e:
        logger.error(f"Error handling window::focus event: {e}")
        await state_manager.increment_error_count()


# ============================================================================
# USER STORY 3 (P3): Workspace State Monitoring
# ============================================================================


async def on_workspace_init(
    conn: i3ipc.Connection, event: i3ipc.WorkspaceEvent, state_manager: StateManager
) -> None:
    """Handle workspace::init events - track new workspaces (T023).

    Args:
        conn: i3 connection
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
    conn: i3ipc.Connection, event: i3ipc.WorkspaceEvent, state_manager: StateManager
) -> None:
    """Handle workspace::empty events - remove empty workspaces (T024).

    Args:
        conn: i3 connection
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
    conn: i3ipc.Connection, event: i3ipc.WorkspaceEvent, state_manager: StateManager
) -> None:
    """Handle workspace::move events - update workspace output (T025).

    Args:
        conn: i3 connection
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
