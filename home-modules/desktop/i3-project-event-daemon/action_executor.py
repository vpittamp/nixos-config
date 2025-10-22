"""Action execution engine for window rules.

Feature 024: Dynamic Window Management System

This module executes structured actions (WorkspaceAction, MarkAction, FloatAction,
LayoutAction) on windows based on matched rules. Each action corresponds to i3 IPC
commands and is executed asynchronously.

Performance Target: < 25ms per action execution
"""

import logging
import time
from typing import List, Optional, Tuple, TYPE_CHECKING

from i3ipc import aio

from .rule_action import (
    RuleAction,
    WorkspaceAction,
    MarkAction,
    FloatAction,
    LayoutAction,
)
from .models import WindowInfo
from .workspace_manager import validate_target_workspace  # Feature 024: R010

if TYPE_CHECKING:
    from .event_buffer import EventBuffer

logger = logging.getLogger(__name__)


async def execute_workspace_action(
    conn: aio.Connection,
    container_id: int,
    action: WorkspaceAction,
    focus: bool = False,
) -> Tuple[bool, Optional[str]]:
    """Execute workspace action: move window to target workspace.

    Feature 024: R011 - Validates workspace is on active output before moving.

    Corresponds to i3 command:
        [con_id=<container_id>] move container to workspace number <target>

    Args:
        conn: i3 async IPC connection
        container_id: i3 container ID (not X11 window ID)
        action: WorkspaceAction with target workspace
        focus: If True, switch workspace focus after move

    Returns:
        Tuple of (success: bool, error_message: Optional[str])

    Performance: Target < 25ms (includes validation overhead)

    Example:
        >>> action = WorkspaceAction(target=2)
        >>> success, error = await execute_workspace_action(conn, 12345, action, focus=True)
        >>> success
        True
    """
    try:
        start_time = time.perf_counter()

        # Feature 024: R011 - Validate workspace before moving
        valid, validation_error = await validate_target_workspace(conn, action.target)

        if not valid:
            # Workspace is on inactive output - log warning but don't fail
            # (fallback: window will stay on current workspace)
            logger.warning(
                f"Workspace validation failed for {action.target}: {validation_error}. "
                f"Window will remain on current workspace."
            )
            # Return success=False to indicate action didn't execute as intended
            return (False, validation_error)

        # Move container to workspace
        cmd = f'[con_id="{container_id}"] move container to workspace number {action.target}'
        result = await conn.command(cmd)

        # Check for errors in command result
        if result and len(result) > 0 and not result[0].success:
            error_msg = result[0].error or "Unknown error moving to workspace"
            logger.warning(
                f"Failed to move container {container_id} to workspace {action.target}: {error_msg}"
            )
            return (False, error_msg)

        # Optionally focus workspace
        if focus:
            focus_cmd = f"workspace number {action.target}"
            await conn.command(focus_cmd)

        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"Moved container {container_id} to workspace {action.target} (focus={focus}) in {duration_ms:.1f}ms"
        )

        return (True, None)

    except Exception as e:
        logger.error(
            f"Error executing workspace action on container {container_id}: {e}"
        )
        return (False, str(e))


async def execute_mark_action(
    conn: aio.Connection,
    window_id: int,
    action: MarkAction,
) -> Tuple[bool, Optional[str]]:
    """Execute mark action: add i3 mark to window.

    Corresponds to i3 command:
        [id=<window_id>] mark --add "<value>"

    Args:
        conn: i3 async IPC connection
        window_id: X11 window ID
        action: MarkAction with mark value

    Returns:
        Tuple of (success: bool, error_message: Optional[str])

    Performance: Target < 25ms

    Example:
        >>> action = MarkAction(value="terminal")
        >>> success, error = await execute_mark_action(conn, 98765, action)
        >>> success
        True
    """
    try:
        start_time = time.perf_counter()

        # Add mark to window
        cmd = f'[id={window_id}] mark --add "{action.value}"'
        result = await conn.command(cmd)

        # Check for errors
        if result and len(result) > 0 and not result[0].success:
            error_msg = result[0].error or "Unknown error adding mark"
            logger.warning(
                f"Failed to add mark '{action.value}' to window {window_id}: {error_msg}"
            )
            return (False, error_msg)

        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"Added mark '{action.value}' to window {window_id} in {duration_ms:.1f}ms"
        )

        return (True, None)

    except Exception as e:
        logger.error(f"Error executing mark action on window {window_id}: {e}")
        return (False, str(e))


async def execute_float_action(
    conn: aio.Connection,
    container_id: int,
    action: FloatAction,
) -> Tuple[bool, Optional[str]]:
    """Execute float action: set window floating state.

    Corresponds to i3 commands:
        [con_id=<container_id>] floating enable   (if enable=True)
        [con_id=<container_id>] floating disable  (if enable=False)

    Args:
        conn: i3 async IPC connection
        container_id: i3 container ID
        action: FloatAction with enable flag

    Returns:
        Tuple of (success: bool, error_message: Optional[str])

    Performance: Target < 25ms

    Example:
        >>> action = FloatAction(enable=True)
        >>> success, error = await execute_float_action(conn, 12345, action)
        >>> success
        True
    """
    try:
        start_time = time.perf_counter()

        # Set floating state
        state = "enable" if action.enable else "disable"
        cmd = f'[con_id="{container_id}"] floating {state}'
        result = await conn.command(cmd)

        # Check for errors
        if result and len(result) > 0 and not result[0].success:
            error_msg = result[0].error or "Unknown error setting floating state"
            logger.warning(
                f"Failed to set floating {state} on container {container_id}: {error_msg}"
            )
            return (False, error_msg)

        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"Set floating {state} on container {container_id} in {duration_ms:.1f}ms"
        )

        return (True, None)

    except Exception as e:
        logger.error(f"Error executing float action on container {container_id}: {e}")
        return (False, str(e))


async def execute_layout_action(
    conn: aio.Connection,
    container_id: int,
    action: LayoutAction,
) -> Tuple[bool, Optional[str]]:
    """Execute layout action: set container layout mode.

    Corresponds to i3 command:
        [con_id=<container_id>] layout <mode>

    Args:
        conn: i3 async IPC connection
        container_id: i3 container ID
        action: LayoutAction with mode (tabbed, stacked, splitv, splith)

    Returns:
        Tuple of (success: bool, error_message: Optional[str])

    Performance: Target < 25ms

    Example:
        >>> action = LayoutAction(mode="tabbed")
        >>> success, error = await execute_layout_action(conn, 12345, action)
        >>> success
        True
    """
    try:
        start_time = time.perf_counter()

        # Set layout mode
        cmd = f'[con_id="{container_id}"] layout {action.mode}'
        result = await conn.command(cmd)

        # Check for errors
        if result and len(result) > 0 and not result[0].success:
            error_msg = result[0].error or "Unknown error setting layout"
            logger.warning(
                f"Failed to set layout {action.mode} on container {container_id}: {error_msg}"
            )
            return (False, error_msg)

        duration_ms = (time.perf_counter() - start_time) * 1000
        logger.debug(
            f"Set layout {action.mode} on container {container_id} in {duration_ms:.1f}ms"
        )

        return (True, None)

    except Exception as e:
        logger.error(
            f"Error executing layout action on container {container_id}: {e}"
        )
        return (False, str(e))


async def apply_rule_actions(
    conn: aio.Connection,
    window: WindowInfo,
    actions: List[RuleAction],
    focus: bool = False,
    event_buffer: Optional["EventBuffer"] = None,
) -> List[Tuple[RuleAction, bool, Optional[str]]]:
    """Execute all actions for a matched rule.

    Actions are executed in order. If one action fails, remaining actions
    are still executed (fail-safe approach).

    Args:
        conn: i3 async IPC connection
        window: Window information (WindowInfo with window_id and con_id)
        actions: List of actions to execute
        focus: If True, focus workspace after workspace actions
        event_buffer: Optional event buffer for tracking failures

    Returns:
        List of tuples: (action, success, error_message)

    Performance: Target < 25ms per action

    Example:
        >>> from .rule_action import WorkspaceAction, LayoutAction
        >>> actions = [WorkspaceAction(target=2), LayoutAction(mode="tabbed")]
        >>> results = await apply_rule_actions(conn, window, actions, focus=True)
        >>> all(success for _, success, _ in results)
        True
    """
    if not actions:
        logger.debug(f"No actions to apply for window {window.window_id}")
        return []

    results: List[Tuple[RuleAction, bool, Optional[str]]] = []
    start_time = time.perf_counter()

    logger.info(
        f"Applying {len(actions)} actions to window {window.window_id} "
        f"({window.window_class})"
    )

    for action in actions:
        action_start = time.perf_counter()

        try:
            # Dispatch action based on type
            if isinstance(action, WorkspaceAction):
                success, error = await execute_workspace_action(
                    conn, window.con_id, action, focus
                )
            elif isinstance(action, MarkAction):
                success, error = await execute_mark_action(
                    conn, window.window_id, action
                )
            elif isinstance(action, FloatAction):
                success, error = await execute_float_action(
                    conn, window.con_id, action
                )
            elif isinstance(action, LayoutAction):
                success, error = await execute_layout_action(
                    conn, window.con_id, action
                )
            else:
                # Unknown action type
                logger.warning(f"Unknown action type: {type(action)}")
                success = False
                error = f"Unknown action type: {type(action)}"

            results.append((action, success, error))

            action_duration = (time.perf_counter() - action_start) * 1000

            # Log status
            if success:
                logger.debug(
                    f"✓ Action {action.type} succeeded in {action_duration:.1f}ms"
                )
            else:
                logger.warning(
                    f"✗ Action {action.type} failed in {action_duration:.1f}ms: {error}"
                )

            # Warn if action exceeded performance target
            if action_duration > 25.0:
                logger.warning(
                    f"⚠ Action {action.type} exceeded 25ms target: {action_duration:.1f}ms"
                )

        except Exception as e:
            logger.error(f"Unexpected error executing action {action.type}: {e}")
            results.append((action, False, str(e)))

    # Total execution time
    total_duration = (time.perf_counter() - start_time) * 1000
    success_count = sum(1 for _, success, _ in results if success)
    failure_count = len(results) - success_count

    logger.info(
        f"Applied {len(actions)} actions in {total_duration:.1f}ms: "
        f"{success_count} succeeded, {failure_count} failed"
    )

    # Record failures in event buffer
    if event_buffer and failure_count > 0:
        # TODO: Add action failure tracking to event buffer (R021)
        pass

    return results
