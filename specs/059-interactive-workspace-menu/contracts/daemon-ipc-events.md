# Daemon IPC Events: Interactive Workspace Menu

**Feature**: 059-interactive-workspace-menu | **Date**: 2025-11-12 | **Contract Type**: Daemon IPC

## Overview

This document defines the IPC events exchanged between the i3pm daemon and workspace-preview-daemon for arrow key navigation, Enter key selection, and Delete key window closing.

---

## Event Flow Architecture

```
Sway Keybinding (workspace mode)
  → i3pm CLI command: `i3pm workspace-preview nav up`
  → i3pm daemon emits IPC event
  → workspace-preview-daemon consumes event
  → Updates selection state
  → Emits JSON to Eww via stdout
  → Eww deflisten updates preview card
```

---

## Event 1: Arrow Key Navigation

**Purpose**: Notify workspace-preview-daemon that user pressed Up/Down arrow key.

**Event Name**: `arrow_key_nav`

**Direction**: i3pm daemon → workspace-preview-daemon

**Payload**:

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `direction` | `Literal["up", "down"]` | Navigation direction | Must be "up" or "down" |
| `mode` | `str` | Preview mode when key was pressed | "all_windows", "filtered_workspace", "project" |
| `timestamp_ms` | `int` | Unix timestamp in milliseconds | `timestamp_ms > 0` |

**JSON Schema**:

```json
{
  "method": "event",
  "params": {
    "type": "arrow_key_nav",
    "payload": {
      "direction": "down",
      "mode": "all_windows",
      "timestamp_ms": 1699891234567
    }
  }
}
```

**Example Usage** (i3pm daemon sends event):

```python
# In i3pm daemon - emit arrow key event
def emit_arrow_key_event(direction: str, mode: str) -> None:
    """Emit arrow key navigation event to workspace-preview-daemon."""
    event = {
        "method": "event",
        "params": {
            "type": "arrow_key_nav",
            "payload": {
                "direction": direction,  # "up" or "down"
                "mode": mode,            # "all_windows", "filtered_workspace", etc.
                "timestamp_ms": int(time.time() * 1000)
            }
        }
    }

    # Send via IPC socket to workspace-preview-daemon
    send_ipc_event(event)
```

**Example Handling** (workspace-preview-daemon receives event):

```python
# In workspace-preview-daemon - handle arrow key event
def handle_arrow_key_event(payload: dict, list_model: PreviewListModel) -> None:
    """Handle arrow key navigation event."""
    direction = payload.get('direction')
    mode = payload.get('mode')

    if mode != "all_windows":
        # Only handle navigation in all_windows mode for Feature 059
        return

    if direction == "down":
        list_model.navigate_down()
    elif direction == "up":
        list_model.navigate_up()

    # Re-emit preview with updated selection
    emit_preview_with_selection(list_model)
```

**Performance**:
- Event emission: <5ms
- Event handling + JSON output: <20ms
- **Total latency**: <25ms (keyboard press to selection update)

---

## Event 2: Enter Key Selection

**Purpose**: Notify workspace-preview-daemon that user pressed Enter to navigate to selected item.

**Event Name**: `enter_key_select`

**Direction**: i3pm daemon → workspace-preview-daemon

**Payload**:

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `mode` | `str` | Preview mode when Enter was pressed | "all_windows", "filtered_workspace", "project" |
| `accumulated_digits` | `str \| None` | Digits typed before Enter (for fallback) | May be empty string or None |
| `timestamp_ms` | `int` | Unix timestamp in milliseconds | `timestamp_ms > 0` |

**JSON Schema**:

```json
{
  "method": "event",
  "params": {
    "type": "enter_key_select",
    "payload": {
      "mode": "all_windows",
      "accumulated_digits": "",
      "timestamp_ms": 1699891234567
    }
  }
}
```

**Example Usage** (i3pm daemon sends event):

```python
# In i3pm daemon - emit Enter key event
def emit_enter_key_event(mode: str, accumulated_digits: str) -> None:
    """Emit Enter key selection event."""
    event = {
        "method": "event",
        "params": {
            "type": "enter_key_select",
            "payload": {
                "mode": mode,
                "accumulated_digits": accumulated_digits,  # "" if none
                "timestamp_ms": int(time.time() * 1000)
            }
        }
    }

    send_ipc_event(event)
```

**Example Handling** (workspace-preview-daemon receives event):

```python
# In workspace-preview-daemon - handle Enter key event
async def handle_enter_key_event(
    payload: dict,
    list_model: PreviewListModel,
    sway_conn
) -> dict:
    """Handle Enter key selection event."""
    mode = payload.get('mode')
    accumulated_digits = payload.get('accumulated_digits', "")

    if mode != "all_windows":
        # Delegate to existing Feature 072 handler
        return

    # Check if selection exists
    selected_item = list_model.get_selected_item()

    if selected_item is None:
        # No selection - fallback to digit navigation (Feature 042)
        if accumulated_digits:
            workspace_num = int(accumulated_digits)
            return await navigate_to_workspace(sway_conn, workspace_num)
        else:
            return {"success": False, "error": "No selection and no digits typed"}

    # Navigate based on selected item type
    if selected_item.is_workspace_heading():
        # Navigate to workspace
        return await navigate_to_workspace(sway_conn, selected_item.workspace_num)
    elif selected_item.is_window():
        # Focus window (auto-switches to workspace)
        return await focus_window(sway_conn, selected_item.window_id)
```

**Performance**:
- Event emission: <5ms
- Event handling: <10ms
- Sway IPC command: 20-50ms
- **Total latency**: <65ms (Enter press to workspace switch)

---

## Event 3: Delete Key Window Close

**Purpose**: Notify workspace-preview-daemon that user pressed Delete to close selected window.

**Event Name**: `delete_key_close`

**Direction**: i3pm daemon → workspace-preview-daemon

**Payload**:

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `mode` | `str` | Preview mode when Delete was pressed | "all_windows", "filtered_workspace", etc. |
| `timestamp_ms` | `int` | Unix timestamp in milliseconds | `timestamp_ms > 0` |

**JSON Schema**:

```json
{
  "method": "event",
  "params": {
    "type": "delete_key_close",
    "payload": {
      "mode": "all_windows",
      "timestamp_ms": 1699891234567
    }
  }
}
```

**Example Usage** (i3pm daemon sends event):

```python
# In i3pm daemon - emit Delete key event
def emit_delete_key_event(mode: str) -> None:
    """Emit Delete key window close event."""
    event = {
        "method": "event",
        "params": {
            "type": "delete_key_close",
            "payload": {
                "mode": mode,
                "timestamp_ms": int(time.time() * 1000)
            }
        }
    }

    send_ipc_event(event)
```

**Example Handling** (workspace-preview-daemon receives event):

```python
# In workspace-preview-daemon - handle Delete key event
async def handle_delete_key_event(
    payload: dict,
    list_model: PreviewListModel,
    sway_conn
) -> dict:
    """Handle Delete key window close event."""
    mode = payload.get('mode')

    if mode != "all_windows":
        return

    # Check if selection exists and is a window
    selected_item = list_model.get_selected_item()

    if selected_item is None:
        return {"success": False, "error": "No selection"}

    if selected_item.is_workspace_heading():
        # Cannot close workspace headings
        logger.warning(f"Attempted to close workspace heading {selected_item.workspace_num}")
        return {"success": False, "error": "Cannot close workspace headings"}

    # Close window with verification
    result = await close_window_with_verification(
        sway_conn,
        selected_item.window_id,
        timeout_ms=500
    )

    if result["success"]:
        # Remove item from list model
        list_model.items.remove(selected_item)
        list_model.clamp_selection()  # Adjust selection index

        # Re-emit preview with updated list
        emit_preview_with_selection(list_model)

    else:
        # Show notification on close failure
        await show_notification(
            title="Window Close Blocked",
            message=result.get("warning", result.get("error")),
            urgency="low" if "timeout" in result.get("error", "") else "normal"
        )

    return result
```

**Performance**:
- Event emission: <5ms
- Event handling: <10ms
- Window close workflow: 60-90ms (success) or 500ms (timeout)
- **Total latency**: <105ms (success) or <515ms (timeout)

---

## Event 4: Digit Typed (Selection Reset)

**Purpose**: Notify workspace-preview-daemon that user typed a digit, which should reset selection to first item.

**Event Name**: `digit_typed`

**Direction**: i3pm daemon → workspace-preview-daemon

**Payload**:

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `digit` | `int` | Digit that was typed (0-9) | `0 <= digit <= 9` |
| `accumulated_digits` | `str` | All digits typed so far | Non-empty string |
| `mode` | `str` | Preview mode | "all_windows", "filtered_workspace", etc. |
| `timestamp_ms` | `int` | Unix timestamp in milliseconds | `timestamp_ms > 0` |

**JSON Schema**:

```json
{
  "method": "event",
  "params": {
    "type": "digit_typed",
    "payload": {
      "digit": 2,
      "accumulated_digits": "23",
      "mode": "filtered_workspace",
      "timestamp_ms": 1699891234567
    }
  }
}
```

**Example Handling** (workspace-preview-daemon receives event):

```python
# In workspace-preview-daemon - handle digit typed event
def handle_digit_typed_event(payload: dict, list_model: PreviewListModel) -> None:
    """Handle digit typed event - reset selection to first item."""
    accumulated_digits = payload.get('accumulated_digits')

    # Filter preview to workspace number (existing Feature 072 behavior)
    # ...

    # Reset selection to first item in filtered list
    list_model.reset_selection()

    # Re-emit preview with updated filter and selection
    emit_preview_with_selection(list_model)
```

**Performance**:
- Event emission: <5ms
- Event handling + filter update: <30ms
- **Total latency**: <35ms (digit press to filter update)

---

## Event 5: Mode Exit (Clear Selection)

**Purpose**: Notify workspace-preview-daemon that workspace mode exited (Escape pressed or navigation completed).

**Event Name**: `mode_exit`

**Direction**: i3pm daemon → workspace-preview-daemon

**Payload**:

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `reason` | `Literal["escape", "navigation_complete", "cancel"]` | Why mode exited | Must be one of three values |
| `timestamp_ms` | `int` | Unix timestamp in milliseconds | `timestamp_ms > 0` |

**JSON Schema**:

```json
{
  "method": "event",
  "params": {
    "type": "mode_exit",
    "payload": {
      "reason": "navigation_complete",
      "timestamp_ms": 1699891234567
    }
  }
}
```

**Example Handling** (workspace-preview-daemon receives event):

```python
# In workspace-preview-daemon - handle mode exit event
def handle_mode_exit_event(payload: dict, list_model: PreviewListModel) -> None:
    """Handle workspace mode exit event - clear selection and hide preview."""
    reason = payload.get('reason')

    # Clear selection state
    list_model.current_selection_index = None

    # Hide preview card
    output = {
        "visible": False,
        "type": "all_windows",
        "workspace_groups": [],
        "selection_state": {
            "selected_index": None,
            "item_type": "workspace_heading",
            "workspace_num": None,
            "window_id": None,
            "visible": False
        }
    }

    print(json.dumps(output), flush=True)

    logger.info(f"Preview hidden: {reason}")
```

**Performance**:
- Event emission: <5ms
- Event handling: <10ms
- **Total latency**: <15ms (mode exit to preview hidden)

---

## Event Summary Table

| Event Name | Direction | Purpose | Latency |
|-----------|-----------|---------|---------|
| `arrow_key_nav` | i3pm → preview-daemon | Update selection on Up/Down | <25ms |
| `enter_key_select` | i3pm → preview-daemon | Navigate to selected item | <65ms |
| `delete_key_close` | i3pm → preview-daemon | Close selected window | <105ms (success), <515ms (timeout) |
| `digit_typed` | i3pm → preview-daemon | Reset selection on digit filter | <35ms |
| `mode_exit` | i3pm → preview-daemon | Clear selection on mode exit | <15ms |

---

## IPC Transport

**Protocol**: Unix domain socket (existing i3pm daemon IPC)

**Socket Path**: `/run/i3-project-daemon/ipc.sock` (Feature 015 infrastructure)

**Message Format**: JSON-RPC 2.0 style (method + params)

**Connection**: Long-lived connection with keep-alive

**Error Handling**:
- Reconnect with exponential backoff on disconnection
- Log dropped events (DEBUG level)
- Degrade gracefully if daemon unavailable (skip selection updates)

---

## Testing Contract Compliance

### Unit Tests (pytest)

```python
# Test event serialization
def test_arrow_key_event_serialization():
    """Test arrow key event matches JSON schema."""
    event = {
        "method": "event",
        "params": {
            "type": "arrow_key_nav",
            "payload": {
                "direction": "down",
                "mode": "all_windows",
                "timestamp_ms": 1699891234567
            }
        }
    }

    # Validate against schema
    assert event["params"]["type"] == "arrow_key_nav"
    assert event["params"]["payload"]["direction"] in ["up", "down"]
    assert isinstance(event["params"]["payload"]["timestamp_ms"], int)
```

### Integration Tests (sway-test)

```json
{
  "name": "Arrow key navigation updates selection",
  "actions": [
    {"type": "enter_workspace_mode"},
    {"type": "send_ipc_event", "params": {
      "method": "event",
      "params": {
        "type": "arrow_key_nav",
        "payload": {"direction": "down", "mode": "all_windows", "timestamp_ms": 123}
      }
    }},
    {"type": "wait", "params": {"duration_ms": 50}}
  ],
  "expectedState": {
    "preview_visible": true,
    "selection_index": 1
  }
}
```

---

**Next**: Create quickstart.md with user workflows and performance metrics.
