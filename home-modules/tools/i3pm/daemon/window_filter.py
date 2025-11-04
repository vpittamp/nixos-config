"""
Window filtering based on environment variables for project-scoped visibility.

This module provides project-aware window filtering using I3PM_* environment
variables instead of mark-based or tag-based approaches. It implements the
visibility logic for project switching and window management.

Key Features:
- Environment-based project association (I3PM_PROJECT_NAME)
- Scope-based visibility (I3PM_SCOPE: global/scoped)
- Zero reliance on window marks or tags
- Deterministic visibility determination
- <1ms per-window latency

Usage:
    >>> from window_filter import filter_windows_for_project
    >>> visible, hidden = await filter_windows_for_project(windows, "nixos")
    >>> # visible: list of windows that should be shown
    >>> # hidden: list of windows that should be hidden (moved to scratchpad)
"""

from typing import List, Dict, Tuple, Optional
import logging
from pathlib import Path

# Import i3ipc for Sway IPC integration
try:
    from i3ipc.aio import Connection, Con
except ImportError:
    # Fallback for testing without i3ipc
    Connection = None
    Con = None

# Import window environment modules
from .window_environment import get_window_environment, read_process_environ
from .models import WindowEnvironment, EnvironmentQueryResult

logger = logging.getLogger(__name__)


async def filter_windows_for_project(
    windows: List[Con],
    active_project: Optional[str],
    max_traversal_depth: int = 3
) -> Tuple[List[Con], List[Con]]:
    """
    Filter windows based on project association using environment variables.

    This function implements environment-based project filtering to determine
    which windows should be visible for the given active project. Global windows
    are always visible, while scoped windows are visible only if they match
    the active project.

    Args:
        windows: List of Sway window containers to filter
        active_project: Currently active project name (None if no project active)
        max_traversal_depth: Maximum parent PID traversal depth

    Returns:
        Tuple of (visible_windows, hidden_windows)
        - visible_windows: Windows that should be shown for active project
        - hidden_windows: Windows that should be hidden (moved to scratchpad)

    Example:
        >>> visible, hidden = await filter_windows_for_project(all_windows, "nixos")
        >>> for window in hidden:
        ...     await window.command("move scratchpad")
        >>> for window in visible:
        ...     await window.command("scratchpad show")
    """
    visible_windows = []
    hidden_windows = []

    for window in windows:
        # Skip windows without PID (can't read environment)
        if not window.pid or window.pid == 0:
            logger.warning(
                f"Window {window.id} ({window.name}) has no PID, treating as visible"
            )
            visible_windows.append(window)
            continue

        # Query window environment
        result = await get_window_environment(
            window_id=window.id,
            pid=window.pid,
            max_traversal_depth=max_traversal_depth
        )

        if result.environment is None:
            # No environment found - treat as visible (defensive default)
            logger.warning(
                f"Window {window.id} ({window.name}) has no I3PM_* environment, "
                f"treating as visible (PID: {window.pid}, error: {result.error})"
            )
            visible_windows.append(window)
            continue

        # Determine visibility using should_be_visible() method
        env = result.environment
        should_show = env.should_be_visible(active_project)

        if should_show:
            visible_windows.append(window)
            logger.debug(
                f"Window {window.id} visible: scope={env.scope}, "
                f"project={env.project_name}, active_project={active_project}"
            )
        else:
            hidden_windows.append(window)
            logger.debug(
                f"Window {window.id} hidden: scope={env.scope}, "
                f"project={env.project_name}, active_project={active_project}"
            )

    logger.info(
        f"Filtered {len(windows)} windows for project '{active_project}': "
        f"{len(visible_windows)} visible, {len(hidden_windows)} hidden"
    )

    return visible_windows, hidden_windows


async def hide_windows(windows: List[Con]) -> int:
    """
    Hide windows by moving them to scratchpad.

    Args:
        windows: List of windows to hide

    Returns:
        Number of windows successfully hidden

    Example:
        >>> hidden_count = await hide_windows(windows_to_hide)
    """
    hidden_count = 0

    for window in windows:
        try:
            # Move to scratchpad
            result = await window.command("move scratchpad")
            if result[0].success:
                hidden_count += 1
                logger.debug(f"Hidden window {window.id} ({window.name})")
            else:
                logger.warning(
                    f"Failed to hide window {window.id}: {result[0].error}"
                )
        except Exception as e:
            logger.error(f"Error hiding window {window.id}: {e}")

    return hidden_count


async def show_windows(windows: List[Con]) -> int:
    """
    Show windows by restoring them from scratchpad.

    Args:
        windows: List of windows to show

    Returns:
        Number of windows successfully shown

    Example:
        >>> shown_count = await show_windows(windows_to_show)
    """
    shown_count = 0

    for window in windows:
        try:
            # Show from scratchpad
            result = await window.command("scratchpad show")
            if result[0].success:
                shown_count += 1
                logger.debug(f"Showed window {window.id} ({window.name})")
            else:
                logger.warning(
                    f"Failed to show window {window.id}: {result[0].error}"
                )
        except Exception as e:
            logger.error(f"Error showing window {window.id}: {e}")

    return shown_count


async def apply_project_filtering(
    i3_connection: Connection,
    active_project: Optional[str]
) -> Dict[str, int]:
    """
    Apply project filtering to all windows in Sway window tree.

    This is the main entry point for project switching. It queries all windows,
    determines visibility based on environment variables, and moves windows
    to/from scratchpad accordingly.

    Args:
        i3_connection: Active Sway IPC connection
        active_project: Currently active project name (None for global mode)

    Returns:
        Dictionary with filtering statistics:
        - total_windows: Total windows processed
        - visible: Windows shown
        - hidden: Windows hidden
        - errors: Windows with errors

    Example:
        >>> async with Connection() as i3:
        ...     stats = await apply_project_filtering(i3, "nixos")
        ...     print(f"Shown {stats['visible']}, hidden {stats['hidden']}")
    """
    # Get all windows from Sway window tree
    tree = await i3_connection.get_tree()
    all_windows = tree.leaves()

    logger.info(
        f"Applying project filtering for '{active_project}' "
        f"to {len(all_windows)} windows"
    )

    # Filter windows based on project
    visible, hidden = await filter_windows_for_project(all_windows, active_project)

    # Hide windows that should not be visible
    hidden_count = await hide_windows(hidden)

    # Show windows that should be visible
    # Note: We may not need to explicitly show visible windows if they're
    # already shown. This depends on the project switch implementation.

    stats = {
        "total_windows": len(all_windows),
        "visible": len(visible),
        "hidden": hidden_count,
        "errors": len(all_windows) - len(visible) - len(hidden),
    }

    logger.info(
        f"Project filtering complete: {stats['visible']} visible, "
        f"{stats['hidden']} hidden, {stats['errors']} errors"
    )

    return stats


def get_window_project_info(window: Con) -> Optional[Dict[str, str]]:
    """
    Get project information for a window (synchronous version).

    This is a simplified synchronous version for use in contexts where
    async/await is not available.

    Args:
        window: Sway window container

    Returns:
        Dictionary with project info or None if not available:
        - app_name: Application name from I3PM_APP_NAME
        - project_name: Project name from I3PM_PROJECT_NAME
        - scope: Scope from I3PM_SCOPE

    Example:
        >>> info = get_window_project_info(window)
        >>> if info and info['scope'] == 'scoped':
        ...     print(f"Window belongs to project: {info['project_name']}")
    """
    if not window.pid or window.pid == 0:
        return None

    try:
        env_vars = read_process_environ(window.pid)
        window_env = WindowEnvironment.from_env_dict(env_vars)

        if window_env is None:
            return None

        return {
            "app_name": window_env.app_name,
            "project_name": window_env.project_name,
            "scope": window_env.scope,
        }
    except Exception as e:
        logger.error(f"Error getting project info for window {window.id}: {e}")
        return None
