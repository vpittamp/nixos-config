# Sway IPC Commands: Interactive Workspace Menu

**Feature**: 059-interactive-workspace-menu | **Date**: 2025-11-12 | **Contract Type**: Sway IPC

## Overview

This document defines the Sway IPC commands used for workspace navigation and window management in the interactive workspace menu feature.

---

## Command 1: Kill Window by Container ID

**Purpose**: Close a window selected via Delete key in the preview card.

**IPC Command**:
```
[con_id=<container_id>] kill
```

**Parameters**:
- `container_id`: Integer - Sway container ID from `tree.find_by_id()` or window data

**Request Example** (via i3ipc-python):
```python
await sway_conn.command(f'[con_id={window_id}] kill')
```

**Response** (CommandReply):
```python
[
    CommandReply(
        success=True,  # Command executed successfully
        error=None,    # No error message
        parse_error=False,
        ipc_data={...}
    )
]
```

**Error Responses**:

| Error Type | `success` | `error` | Cause |
|------------|----------|---------|-------|
| Container not found | `False` | `"No container matches specified criteria"` | Window already closed or invalid ID |
| Parse error | `False` | `"Expected..."` | Invalid command syntax (bug) |
| Permission denied | `False` | `"Permission denied"` | Insufficient privileges (rare) |

**Usage Pattern**:

```python
async def send_kill_command(sway_conn, container_id: int) -> dict:
    """Send kill command to Sway, handling errors."""
    try:
        results = await sway_conn.command(f'[con_id={container_id}] kill')

        for reply in results:
            if not reply.success:
                error_msg = reply.error if hasattr(reply, 'error') else "Unknown error"
                return {"success": False, "error": f"Kill failed: {error_msg}"}

        return {"success": True, "message": "Kill command sent"}

    except Exception as e:
        return {"success": False, "error": f"Exception: {str(e)}"}
```

**Performance**:
- Command execution: 50-100ms
- Does NOT guarantee window closed (async operation)
- Must poll tree to verify close (see validation pattern below)

---

## Command 2: Focus Workspace by Number

**Purpose**: Navigate to workspace when user presses Enter on a workspace heading.

**IPC Command**:
```
workspace number <workspace_num>
```

**Parameters**:
- `workspace_num`: Integer - Workspace number (1-70)

**Request Example**:
```python
await sway_conn.command(f'workspace number {workspace_num}')
```

**Response** (CommandReply):
```python
[
    CommandReply(
        success=True,
        error=None,
        parse_error=False,
        ipc_data={...}
    )
]
```

**Error Responses**:

| Error Type | `success` | `error` | Cause |
|------------|----------|---------|-------|
| Invalid workspace | `False` | `"Invalid workspace..."` | workspace_num < 1 or > 70 |
| Parse error | `False` | `"Expected..."` | Invalid command syntax |

**Usage Pattern**:

```python
async def navigate_to_workspace(sway_conn, workspace_num: int) -> dict:
    """Navigate to workspace, handling errors."""
    # Validate workspace number
    if not 1 <= workspace_num <= 70:
        return {"success": False, "error": f"Invalid workspace {workspace_num} (must be 1-70)"}

    try:
        results = await sway_conn.command(f'workspace number {workspace_num}')

        for reply in results:
            if not reply.success:
                error_msg = reply.error if hasattr(reply, 'error') else "Unknown error"
                return {"success": False, "error": error_msg}

        return {"success": True, "workspace_num": workspace_num}

    except Exception as e:
        return {"success": False, "error": f"Exception: {str(e)}"}
```

**Performance**:
- Command execution: 20-50ms
- Workspace switch is synchronous (completes before response)

---

## Command 3: Focus Window by Container ID

**Purpose**: Navigate to workspace and focus specific window when user presses Enter on a window item.

**IPC Command**:
```
[con_id=<container_id>] focus
```

**Parameters**:
- `container_id`: Integer - Sway container ID of window to focus

**Request Example**:
```python
await sway_conn.command(f'[con_id={window_id}] focus')
```

**Response** (CommandReply):
```python
[
    CommandReply(
        success=True,
        error=None,
        parse_error=False,
        ipc_data={...}
    )
]
```

**Error Responses**:

| Error Type | `success` | `error` | Cause |
|------------|----------|---------|-------|
| Container not found | `False` | `"No container matches..."` | Window closed or invalid ID |
| Parse error | `False` | `"Expected..."` | Invalid syntax |

**Usage Pattern**:

```python
async def focus_window(sway_conn, window_id: int) -> dict:
    """Focus window, handling errors."""
    try:
        results = await sway_conn.command(f'[con_id={window_id}] focus')

        for reply in results:
            if not reply.success:
                error_msg = reply.error if hasattr(reply, 'error') else "Unknown error"
                return {"success": False, "error": error_msg}

        return {"success": True, "window_id": window_id}

    except Exception as e:
        return {"success": False, "error": f"Exception: {str(e)}"}
```

**Performance**:
- Command execution: 20-50ms
- Focus + workspace switch (if needed) is synchronous

**Automatic Workspace Switching**:
- Sway automatically switches to workspace containing the window
- No need to query workspace number first
- Focus command handles workspace navigation implicitly

---

## Validation Pattern: Verify Window Closed

**Purpose**: Poll Sway tree to verify window actually closed after `kill` command (windows may block close request).

**IPC Query**:
```
GET_TREE
```

**Request Example**:
```python
tree = await sway_conn.get_tree()
window = tree.find_by_id(container_id)

if window is None:
    # Window closed successfully
    return True
else:
    # Window still exists (close blocked or slow)
    return False
```

**Polling Pattern**:

```python
import asyncio
import time

async def wait_for_window_close(
    sway_conn,
    container_id: int,
    timeout_ms: int = 500,
    poll_interval_ms: int = 50
) -> tuple[bool, int]:
    """Poll tree to verify window closed within timeout.

    Returns:
        (closed: bool, duration_ms: int)
    """
    start_time = time.perf_counter()
    timeout_sec = timeout_ms / 1000.0
    poll_interval_sec = poll_interval_ms / 1000.0

    while (time.perf_counter() - start_time) < timeout_sec:
        tree = await sway_conn.get_tree()
        window = tree.find_by_id(container_id)

        if window is None:
            # Window closed
            duration_ms = (time.perf_counter() - start_time) * 1000
            return True, duration_ms

        # Still exists, wait before next poll
        await asyncio.sleep(poll_interval_sec)

    # Timeout - window still exists
    return False, timeout_ms
```

**Performance**:
- GET_TREE query: 5-15ms per poll
- Poll interval: 50ms (balance between responsiveness and CPU)
- Total timeout: 500ms (8-10 polls)
- Expected: 60-90ms for successful close, 500ms for blocked close

---

## Integrated Close Workflow

**Complete window close with verification**:

```python
async def close_window_with_verification(
    sway_conn,
    container_id: int,
    timeout_ms: int = 500
) -> dict:
    """Close window and verify it closed successfully.

    Returns:
        {
            "success": bool,
            "message": str,
            "error": str | None,
            "warning": str | None,
            "close_duration_ms": int
        }
    """
    start_time = time.perf_counter()

    # Step 1: Validate window exists
    tree = await sway_conn.get_tree()
    window = tree.find_by_id(container_id)

    if not window:
        return {
            "success": True,
            "message": "Window already closed",
            "close_duration_ms": 0
        }

    # Step 2: Send kill command
    try:
        results = await sway_conn.command(f'[con_id={container_id}] kill')

        for reply in results:
            if not reply.success:
                error_msg = reply.error if hasattr(reply, 'error') else "Unknown"
                return {
                    "success": False,
                    "error": f"Kill command failed: {error_msg}",
                    "close_duration_ms": 0
                }
    except Exception as e:
        return {
            "success": False,
            "error": f"Exception: {str(e)}",
            "close_duration_ms": 0
        }

    # Step 3: Wait for window to close
    remaining_timeout = timeout_ms - ((time.perf_counter() - start_time) * 1000)
    closed, duration_ms = await wait_for_window_close(
        sway_conn,
        container_id,
        timeout_ms=int(remaining_timeout),
        poll_interval_ms=50
    )

    total_duration_ms = (time.perf_counter() - start_time) * 1000

    if closed:
        return {
            "success": True,
            "message": "Window closed successfully",
            "close_duration_ms": total_duration_ms
        }
    else:
        return {
            "success": False,
            "error": "Window did not close within timeout",
            "warning": "Application may have unsaved changes or be unresponsive",
            "close_duration_ms": total_duration_ms
        }
```

---

## Performance Summary

| Command | Execution Time | Notes |
|---------|---------------|-------|
| `[con_id=N] kill` | 50-100ms | Async - doesn't wait for close |
| `workspace number N` | 20-50ms | Synchronous workspace switch |
| `[con_id=N] focus` | 20-50ms | Synchronous focus + workspace switch |
| `GET_TREE` query | 5-15ms | For validation/polling |
| **Full close workflow** | **60-90ms** (success) | **500ms** (timeout) |

---

## Error Handling Best Practices

1. **Always check `CommandReply.success`** before assuming command executed
2. **Read `CommandReply.error`** for user-facing error messages
3. **Validate window exists** before sending commands (avoid error logs)
4. **Poll tree to verify close** - don't trust `success=True` alone for kills
5. **Use 500ms timeout** for close verification (balance patience vs UX)
6. **Log timeouts as WARNING** (not ERROR) - expected for unsaved changes
7. **Show user notifications** for blocked closes with actionable guidance

---

## Example Error Messages for User Display

| Scenario | User Message |
|----------|-------------|
| Window already closed | _No message - silent success_ |
| Kill command failed | "Failed to close window: [error]" |
| Close timeout (unsaved changes) | "The application may have unsaved changes. Please check the window and try closing again." |
| Window not found | "Window no longer exists (already closed)" |

---

**Next**: Daemon IPC events contract
