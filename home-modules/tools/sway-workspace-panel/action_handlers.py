"""Window action handlers for Feature 073: Eww Interactive Menu Stabilization.

This module implements per-window actions that can be performed from the workspace
preview menu:
- Close window (Delete key)
- Move window to another workspace (M key + digits + Enter)
- Toggle floating/tiling mode (F key)
- Focus window in split container
- Mark/unmark windows

All actions include debouncing protection to prevent duplicate operations from
rapid keypresses.

Architecture:
- Async handlers using i3ipc.aio for Sway IPC communication
- 100ms debounce window per (action_type, window_id) pair
- ActionResult return type with success/error reporting
- Notification support for user-visible errors

Performance:
- <500ms window close operation (FR-002)
- <100ms keyboard event passthrough
- Debounce check adds <2ms overhead
"""

from __future__ import annotations

import asyncio
import sys
import time
from typing import Dict, Tuple, Optional
from enum import Enum

from pydantic import BaseModel, Field
import i3ipc.aio


def log_action(message: str, level: str = "INFO") -> None:
    """Log action handler events to stderr for daemon monitoring.

    Args:
        message: Log message
        level: Log level (INFO, WARN, ERROR)
    """
    print(f"[ACTION_HANDLER] [{level}] {message}", file=sys.stderr, flush=True)


class ActionType(Enum):
    """Window action types supported by the menu.

    Each action type has a corresponding handler function and keyboard binding.
    """
    CLOSE = "close"  # Delete key - kill window
    MOVE = "move"  # M key + workspace number - move to workspace
    FLOAT_TOGGLE = "float_toggle"  # F key - toggle floating/tiling
    FOCUS = "focus"  # Enter key - focus window in split
    MARK = "mark"  # Mark window for later operations
    UNMARK = "unmark"  # Remove window mark


class ActionErrorCode(Enum):
    """Error codes for action failures.

    Used for user notifications and debugging.
    """
    WINDOW_NOT_FOUND = "window_not_found"  # Container ID no longer exists
    WINDOW_REFUSED_CLOSE = "window_refused_close"  # Unsaved changes dialog
    INVALID_WORKSPACE = "invalid_workspace"  # Workspace number out of range (not 1-70)
    DEBOUNCE_REJECTED = "debounce_rejected"  # Action too soon after previous
    IPC_TIMEOUT = "ipc_timeout"  # Sway IPC command timeout
    PERMISSION_DENIED = "permission_denied"  # Sway rejected command


class ActionResult(BaseModel):
    """Result of a window action operation.

    Returned by all async handler functions for consistent error handling.
    """
    success: bool = Field(..., description="Whether action completed successfully")
    action_type: ActionType = Field(..., description="Type of action attempted")
    window_id: Optional[int] = Field(default=None, description="Target window container ID")
    error_code: Optional[ActionErrorCode] = Field(default=None, description="Error code if failed")
    error_message: Optional[str] = Field(default=None, description="Human-readable error")
    latency_ms: float = Field(..., ge=0, description="Time taken to execute action")

    class Config:
        """Pydantic configuration."""
        use_enum_values = True


class DebounceTracker:
    """Tracks recent actions to prevent duplicate operations from rapid keypresses.

    Strategy:
    - Track last action timestamp per (action_type, window_id) pair
    - Reject actions within 100ms of previous same action
    - Thread-safe via asyncio (single-threaded event loop)
    - Automatic cleanup of old entries (>10s) every 100 actions

    Performance:
    - O(1) lookup and insert
    - <2ms overhead per action check
    - Memory: ~50 bytes per tracked action

    Example:
        tracker = DebounceTracker(min_interval_ms=100)

        if tracker.should_allow(ActionType.CLOSE, window_id=12345):
            await handle_window_close(conn, 12345)
        else:
            # Rejected - too soon after previous close
            pass
    """

    def __init__(self, min_interval_ms: float = 100.0):
        """Initialize debounce tracker.

        Args:
            min_interval_ms: Minimum milliseconds between same actions (default 100ms)
        """
        self.min_interval_ms = min_interval_ms
        self._last_action_time: Dict[Tuple[ActionType, int], float] = {}
        self._action_count = 0  # For cleanup trigger

    def should_allow(self, action_type: ActionType, window_id: int) -> bool:
        """Check if action should be allowed based on debounce timing.

        Args:
            action_type: Type of action being attempted
            window_id: Target window container ID

        Returns:
            True if action should proceed, False if rejected (too soon)
        """
        key = (action_type, window_id)
        current_time = time.monotonic()

        # Check if action too soon after previous
        if key in self._last_action_time:
            elapsed_ms = (current_time - self._last_action_time[key]) * 1000
            if elapsed_ms < self.min_interval_ms:
                return False

        # Allow action and record timestamp
        self._last_action_time[key] = current_time

        # Periodic cleanup of old entries (>10s)
        self._action_count += 1
        if self._action_count >= 100:
            self._cleanup_old_entries(current_time)
            self._action_count = 0

        return True

    def _cleanup_old_entries(self, current_time: float) -> None:
        """Remove entries older than 10 seconds.

        Args:
            current_time: Current monotonic timestamp
        """
        cutoff = current_time - 10.0  # 10 seconds
        keys_to_remove = [
            key for key, timestamp in self._last_action_time.items()
            if timestamp < cutoff
        ]
        for key in keys_to_remove:
            del self._last_action_time[key]

    def reset(self) -> None:
        """Clear all debounce state.

        Useful for testing or daemon restarts.
        """
        self._last_action_time.clear()
        self._action_count = 0


# Global debounce tracker instance (singleton pattern)
_debounce_tracker = DebounceTracker(min_interval_ms=100.0)


async def handle_window_close(
    conn: i3ipc.aio.Connection,
    window_id: int,
    debounce_tracker: Optional[DebounceTracker] = None
) -> ActionResult:
    """Close a window via Sway IPC kill command.

    This is the primary action for User Story 1 (P1 priority). The window close
    operation must complete within 500ms (p95 latency) and handle errors gracefully
    when windows refuse to close (unsaved changes).

    Implementation:
    1. Check debounce - reject if <100ms since last close of this window
    2. Send Sway IPC command: `[con_id={window_id}] kill`
    3. Verify window closed within 500ms (optional verification)
    4. Return ActionResult with success/error status

    Error Handling:
    - WINDOW_NOT_FOUND: Container ID no longer exists (already closed)
    - WINDOW_REFUSED_CLOSE: Window has unsaved changes, shows dialog
    - IPC_TIMEOUT: Sway IPC command took >500ms
    - DEBOUNCE_REJECTED: Close attempted too soon after previous close

    Args:
        conn: Active i3ipc.aio connection to Sway
        window_id: Sway container ID of window to close
        debounce_tracker: Optional custom tracker (default: global singleton)

    Returns:
        ActionResult with success status, latency, and error details

    Example:
        result = await handle_window_close(conn, 12345)
        if not result.success:
            if result.error_code == ActionErrorCode.WINDOW_REFUSED_CLOSE:
                notify_user("Window refused to close (may have unsaved changes)")
    """
    start_time = time.monotonic()
    tracker = debounce_tracker or _debounce_tracker

    # Check debounce
    if not tracker.should_allow(ActionType.CLOSE, window_id):
        log_action(f"Close window {window_id} rejected - debounce (min {tracker.min_interval_ms}ms)", "WARN")
        return ActionResult(
            success=False,
            action_type=ActionType.CLOSE,
            window_id=window_id,
            error_code=ActionErrorCode.DEBOUNCE_REJECTED,
            error_message=f"Close rejected - too soon after previous close (min {tracker.min_interval_ms}ms)",
            latency_ms=0.0
        )

    try:
        # Send Sway IPC kill command
        # Note: Sway uses con_id (container ID) for precise targeting
        command = f"[con_id={window_id}] kill"
        log_action(f"Closing window {window_id}: {command}", "INFO")
        replies = await conn.command(command)

        # Check if command succeeded
        # Sway returns list of CommandReply objects, check first reply
        if not replies or not replies[0].success:
            error_msg = replies[0].error if replies else "Unknown IPC error"
            log_action(f"Close window {window_id} failed: {error_msg}", "ERROR")
            return ActionResult(
                success=False,
                action_type=ActionType.CLOSE,
                window_id=window_id,
                error_code=ActionErrorCode.WINDOW_NOT_FOUND,
                error_message=f"Sway IPC error: {error_msg}",
                latency_ms=(time.monotonic() - start_time) * 1000
            )

        # Success
        latency_ms = (time.monotonic() - start_time) * 1000
        log_action(f"Close window {window_id} succeeded ({latency_ms:.1f}ms)", "INFO")
        return ActionResult(
            success=True,
            action_type=ActionType.CLOSE,
            window_id=window_id,
            latency_ms=latency_ms
        )

    except asyncio.TimeoutError:
        log_action(f"Close window {window_id} timeout (>500ms)", "ERROR")
        return ActionResult(
            success=False,
            action_type=ActionType.CLOSE,
            window_id=window_id,
            error_code=ActionErrorCode.IPC_TIMEOUT,
            error_message="Sway IPC timeout (>500ms)",
            latency_ms=500.0
        )
    except Exception as e:
        log_action(f"Close window {window_id} unexpected error: {str(e)}", "ERROR")
        return ActionResult(
            success=False,
            action_type=ActionType.CLOSE,
            window_id=window_id,
            error_code=ActionErrorCode.WINDOW_NOT_FOUND,
            error_message=f"Unexpected error: {str(e)}",
            latency_ms=(time.monotonic() - start_time) * 1000
        )


async def verify_window_closed(
    conn: i3ipc.aio.Connection,
    window_id: int,
    timeout_ms: float = 500.0
) -> bool:
    """Verify a window was successfully closed by checking Sway tree.

    This is an optional verification step used in tests to ensure window close
    operations completed successfully. In production, we rely on Sway IPC command
    success status rather than polling the tree.

    Strategy:
    - Query Sway tree via GET_TREE IPC call
    - Search for container with matching ID
    - Return False if found, True if not found (closed)
    - Timeout after specified ms (default 500ms per FR-002)

    Args:
        conn: Active i3ipc.aio connection to Sway
        window_id: Sway container ID to check
        timeout_ms: Maximum time to wait for verification

    Returns:
        True if window no longer exists (successfully closed)
        False if window still exists or timeout occurred

    Example:
        await handle_window_close(conn, 12345)
        assert await verify_window_closed(conn, 12345, timeout_ms=500)
    """
    start_time = time.monotonic()
    timeout_seconds = timeout_ms / 1000.0

    while (time.monotonic() - start_time) < timeout_seconds:
        tree = await conn.get_tree()

        # Recursively search tree for window_id
        def find_window(container) -> bool:
            if container.id == window_id:
                return True
            for child in container.nodes + container.floating_nodes:
                if find_window(child):
                    return True
            return False

        if not find_window(tree):
            return True  # Window not found = successfully closed

        # Wait 50ms before next check
        await asyncio.sleep(0.05)

    return False  # Timeout - window still exists


async def handle_window_move(
    conn: i3ipc.aio.Connection,
    window_id: int,
    target_workspace: int,
    debounce_tracker: Optional[DebounceTracker] = None
) -> ActionResult:
    """Move a window to a different workspace via Sway IPC move command.

    This is a sub-mode action for User Story 4 (P3 priority). The move workflow
    requires user to:
    1. Press M key to enter move sub-mode
    2. Type workspace number (1-70)
    3. Press Enter to confirm

    Implementation:
    1. Validate workspace number (1-70 range per spec)
    2. Check debounce - reject if <100ms since last move of this window
    3. Send Sway IPC command: `[con_id={window_id}] move container to workspace number {target_workspace}`
    4. Return ActionResult with success/error status

    Error Handling:
    - INVALID_WORKSPACE: Workspace number not in 1-70 range
    - WINDOW_NOT_FOUND: Container ID no longer exists
    - IPC_TIMEOUT: Sway IPC command took >500ms
    - DEBOUNCE_REJECTED: Move attempted too soon after previous move

    Args:
        conn: Active i3ipc.aio connection to Sway
        window_id: Sway container ID of window to move
        target_workspace: Destination workspace number (1-70)
        debounce_tracker: Optional custom tracker (default: global singleton)

    Returns:
        ActionResult with success status, latency, and error details

    Example:
        result = await handle_window_move(conn, 12345, target_workspace=23)
        if not result.success:
            if result.error_code == ActionErrorCode.INVALID_WORKSPACE:
                notify_user("Invalid workspace number")
    """
    start_time = time.monotonic()
    tracker = debounce_tracker or _debounce_tracker

    # Validate workspace number (1-70 per spec)
    if not (1 <= target_workspace <= 70):
        log_action(f"Move window {window_id} to WS {target_workspace} rejected - invalid workspace", "ERROR")
        return ActionResult(
            success=False,
            action_type=ActionType.MOVE,
            window_id=window_id,
            error_code=ActionErrorCode.INVALID_WORKSPACE,
            error_message=f"Invalid workspace number: {target_workspace} (must be 1-70)",
            latency_ms=(time.monotonic() - start_time) * 1000
        )

    # Check debounce
    if not tracker.should_allow(ActionType.MOVE, window_id):
        log_action(f"Move window {window_id} to WS {target_workspace} rejected - debounce", "WARN")
        return ActionResult(
            success=False,
            action_type=ActionType.MOVE,
            window_id=window_id,
            error_code=ActionErrorCode.DEBOUNCE_REJECTED,
            error_message=f"Move rejected - too soon after previous move (min {tracker.min_interval_ms}ms)",
            latency_ms=0.0
        )

    try:
        # Send Sway IPC move command
        command = f"[con_id={window_id}] move container to workspace number {target_workspace}"
        log_action(f"Moving window {window_id} to WS {target_workspace}: {command}", "INFO")
        replies = await conn.command(command)

        # Check if command succeeded
        if not replies or not replies[0].success:
            error_msg = replies[0].error if replies else "Unknown IPC error"
            log_action(f"Move window {window_id} to WS {target_workspace} failed: {error_msg}", "ERROR")
            return ActionResult(
                success=False,
                action_type=ActionType.MOVE,
                window_id=window_id,
                error_code=ActionErrorCode.WINDOW_NOT_FOUND,
                error_message=f"Sway IPC error: {error_msg}",
                latency_ms=(time.monotonic() - start_time) * 1000
            )

        # Success
        latency_ms = (time.monotonic() - start_time) * 1000
        log_action(f"Move window {window_id} to WS {target_workspace} succeeded ({latency_ms:.1f}ms)", "INFO")
        return ActionResult(
            success=True,
            action_type=ActionType.MOVE,
            window_id=window_id,
            latency_ms=latency_ms
        )

    except asyncio.TimeoutError:
        log_action(f"Move window {window_id} to WS {target_workspace} timeout (>500ms)", "ERROR")
        return ActionResult(
            success=False,
            action_type=ActionType.MOVE,
            window_id=window_id,
            error_code=ActionErrorCode.IPC_TIMEOUT,
            error_message="Sway IPC timeout (>500ms)",
            latency_ms=500.0
        )
    except Exception as e:
        log_action(f"Move window {window_id} to WS {target_workspace} unexpected error: {str(e)}", "ERROR")
        return ActionResult(
            success=False,
            action_type=ActionType.MOVE,
            window_id=window_id,
            error_code=ActionErrorCode.WINDOW_NOT_FOUND,
            error_message=f"Unexpected error: {str(e)}",
            latency_ms=(time.monotonic() - start_time) * 1000
        )


async def handle_window_float_toggle(
    conn: i3ipc.aio.Connection,
    window_id: int,
    debounce_tracker: Optional[DebounceTracker] = None
) -> ActionResult:
    """Toggle a window between floating and tiling modes via Sway IPC.

    This is an immediate action for User Story 4 (P3 priority). No sub-mode required -
    pressing F key immediately toggles the current window's floating state.

    Implementation:
    1. Check debounce - reject if <100ms since last toggle of this window
    2. Send Sway IPC command: `[con_id={window_id}] floating toggle`
    3. Return ActionResult with success/error status

    Error Handling:
    - WINDOW_NOT_FOUND: Container ID no longer exists
    - IPC_TIMEOUT: Sway IPC command took >500ms
    - DEBOUNCE_REJECTED: Toggle attempted too soon after previous toggle

    Args:
        conn: Active i3ipc.aio connection to Sway
        window_id: Sway container ID of window to toggle
        debounce_tracker: Optional custom tracker (default: global singleton)

    Returns:
        ActionResult with success status, latency, and error details

    Example:
        result = await handle_window_float_toggle(conn, 12345)
        if result.success:
            notify_user("Window floating state toggled")
    """
    start_time = time.monotonic()
    tracker = debounce_tracker or _debounce_tracker

    # Check debounce
    if not tracker.should_allow(ActionType.FLOAT_TOGGLE, window_id):
        return ActionResult(
            success=False,
            action_type=ActionType.FLOAT_TOGGLE,
            window_id=window_id,
            error_code=ActionErrorCode.DEBOUNCE_REJECTED,
            error_message=f"Float toggle rejected - too soon after previous toggle (min {tracker.min_interval_ms}ms)",
            latency_ms=0.0
        )

    try:
        # Send Sway IPC floating toggle command
        command = f"[con_id={window_id}] floating toggle"
        replies = await conn.command(command)

        # Check if command succeeded
        if not replies or not replies[0].success:
            error_msg = replies[0].error if replies else "Unknown IPC error"
            return ActionResult(
                success=False,
                action_type=ActionType.FLOAT_TOGGLE,
                window_id=window_id,
                error_code=ActionErrorCode.WINDOW_NOT_FOUND,
                error_message=f"Sway IPC error: {error_msg}",
                latency_ms=(time.monotonic() - start_time) * 1000
            )

        # Success
        latency_ms = (time.monotonic() - start_time) * 1000
        return ActionResult(
            success=True,
            action_type=ActionType.FLOAT_TOGGLE,
            window_id=window_id,
            latency_ms=latency_ms
        )

    except asyncio.TimeoutError:
        return ActionResult(
            success=False,
            action_type=ActionType.FLOAT_TOGGLE,
            window_id=window_id,
            error_code=ActionErrorCode.IPC_TIMEOUT,
            error_message="Sway IPC timeout (>500ms)",
            latency_ms=500.0
        )
    except Exception as e:
        return ActionResult(
            success=False,
            action_type=ActionType.FLOAT_TOGGLE,
            window_id=window_id,
            error_code=ActionErrorCode.WINDOW_NOT_FOUND,
            error_message=f"Unexpected error: {str(e)}",
            latency_ms=(time.monotonic() - start_time) * 1000
        )


async def handle_window_focus(
    conn: i3ipc.aio.Connection,
    window_id: int,
    debounce_tracker: Optional[DebounceTracker] = None
) -> ActionResult:
    """Focus a window in a split container via Sway IPC.

    This is an immediate action for User Story 4 (P3 priority). Useful when multiple
    windows are in the same workspace in split containers - pressing Enter focuses
    the selected window.

    Implementation:
    1. Check debounce - reject if <100ms since last focus of this window
    2. Send Sway IPC command: `[con_id={window_id}] focus`
    3. Return ActionResult with success/error status

    Error Handling:
    - WINDOW_NOT_FOUND: Container ID no longer exists
    - IPC_TIMEOUT: Sway IPC command took >500ms
    - DEBOUNCE_REJECTED: Focus attempted too soon after previous focus

    Args:
        conn: Active i3ipc.aio connection to Sway
        window_id: Sway container ID of window to focus
        debounce_tracker: Optional custom tracker (default: global singleton)

    Returns:
        ActionResult with success status, latency, and error details

    Example:
        result = await handle_window_focus(conn, 12345)
        if result.success:
            # Window now has keyboard focus
            pass
    """
    start_time = time.monotonic()
    tracker = debounce_tracker or _debounce_tracker

    # Check debounce
    if not tracker.should_allow(ActionType.FOCUS, window_id):
        return ActionResult(
            success=False,
            action_type=ActionType.FOCUS,
            window_id=window_id,
            error_code=ActionErrorCode.DEBOUNCE_REJECTED,
            error_message=f"Focus rejected - too soon after previous focus (min {tracker.min_interval_ms}ms)",
            latency_ms=0.0
        )

    try:
        # Send Sway IPC focus command
        command = f"[con_id={window_id}] focus"
        replies = await conn.command(command)

        # Check if command succeeded
        if not replies or not replies[0].success:
            error_msg = replies[0].error if replies else "Unknown IPC error"
            return ActionResult(
                success=False,
                action_type=ActionType.FOCUS,
                window_id=window_id,
                error_code=ActionErrorCode.WINDOW_NOT_FOUND,
                error_message=f"Sway IPC error: {error_msg}",
                latency_ms=(time.monotonic() - start_time) * 1000
            )

        # Success
        latency_ms = (time.monotonic() - start_time) * 1000
        return ActionResult(
            success=True,
            action_type=ActionType.FOCUS,
            window_id=window_id,
            latency_ms=latency_ms
        )

    except asyncio.TimeoutError:
        return ActionResult(
            success=False,
            action_type=ActionType.FOCUS,
            window_id=window_id,
            error_code=ActionErrorCode.IPC_TIMEOUT,
            error_message="Sway IPC timeout (>500ms)",
            latency_ms=500.0
        )
    except Exception as e:
        return ActionResult(
            success=False,
            action_type=ActionType.FOCUS,
            window_id=window_id,
            error_code=ActionErrorCode.WINDOW_NOT_FOUND,
            error_message=f"Unexpected error: {str(e)}",
            latency_ms=(time.monotonic() - start_time) * 1000
        )


async def handle_window_mark(
    conn: i3ipc.aio.Connection,
    window_id: int,
    mark_name: str,
    debounce_tracker: Optional[DebounceTracker] = None
) -> ActionResult:
    """Mark a window with a named identifier via Sway IPC.

    This is a sub-mode action for User Story 4 (P3 priority). The mark workflow
    requires user to:
    1. Press Shift+M key to enter mark sub-mode
    2. Type mark name (alphanumeric + underscore + hyphen)
    3. Press Enter to confirm

    Marks are useful for:
    - Quick window identification in layouts
    - Custom keyboard shortcuts to specific windows
    - Window grouping and organization

    Implementation:
    1. Check debounce - reject if <100ms since last mark of this window
    2. Send Sway IPC command: `[con_id={window_id}] mark {mark_name}`
    3. Return ActionResult with success/error status

    Error Handling:
    - WINDOW_NOT_FOUND: Container ID no longer exists
    - IPC_TIMEOUT: Sway IPC command took >500ms
    - DEBOUNCE_REJECTED: Mark attempted too soon after previous mark

    Args:
        conn: Active i3ipc.aio connection to Sway
        window_id: Sway container ID of window to mark
        mark_name: Name for the mark (alphanumeric + _ + -)
        debounce_tracker: Optional custom tracker (default: global singleton)

    Returns:
        ActionResult with success status, latency, and error details

    Example:
        result = await handle_window_mark(conn, 12345, mark_name="browser_main")
        if result.success:
            # Can now reference window via: [con_mark="browser_main"] command
            pass
    """
    start_time = time.monotonic()
    tracker = debounce_tracker or _debounce_tracker

    # Check debounce
    if not tracker.should_allow(ActionType.MARK, window_id):
        return ActionResult(
            success=False,
            action_type=ActionType.MARK,
            window_id=window_id,
            error_code=ActionErrorCode.DEBOUNCE_REJECTED,
            error_message=f"Mark rejected - too soon after previous mark (min {tracker.min_interval_ms}ms)",
            latency_ms=0.0
        )

    try:
        # Send Sway IPC mark command
        # Note: Sway replaces existing marks on the same window
        command = f'[con_id={window_id}] mark {mark_name}'
        replies = await conn.command(command)

        # Check if command succeeded
        if not replies or not replies[0].success:
            error_msg = replies[0].error if replies else "Unknown IPC error"
            return ActionResult(
                success=False,
                action_type=ActionType.MARK,
                window_id=window_id,
                error_code=ActionErrorCode.WINDOW_NOT_FOUND,
                error_message=f"Sway IPC error: {error_msg}",
                latency_ms=(time.monotonic() - start_time) * 1000
            )

        # Success
        latency_ms = (time.monotonic() - start_time) * 1000
        return ActionResult(
            success=True,
            action_type=ActionType.MARK,
            window_id=window_id,
            latency_ms=latency_ms
        )

    except asyncio.TimeoutError:
        return ActionResult(
            success=False,
            action_type=ActionType.MARK,
            window_id=window_id,
            error_code=ActionErrorCode.IPC_TIMEOUT,
            error_message="Sway IPC timeout (>500ms)",
            latency_ms=500.0
        )
    except Exception as e:
        return ActionResult(
            success=False,
            action_type=ActionType.MARK,
            window_id=window_id,
            error_code=ActionErrorCode.WINDOW_NOT_FOUND,
            error_message=f"Unexpected error: {str(e)}",
            latency_ms=(time.monotonic() - start_time) * 1000
        )
