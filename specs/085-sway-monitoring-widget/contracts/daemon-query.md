# Contract: Python Backend → i3pm Daemon Query

**Feature**: 085-sway-monitoring-widget
**Contract**: `monitoring_data.py` → `i3pm daemon` (via DaemonClient)
**Date**: 2025-11-20

## Overview

This contract defines the communication protocol between the Python backend script (`monitoring_data.py`) and the i3pm daemon for querying window/workspace/project state.

The backend script reuses the existing `DaemonClient` from Feature 025, ensuring consistency with established patterns.

---

## Request

### Method
`get_window_tree()` (async)

### Protocol
- **Transport**: Unix domain socket (`/run/user/$UID/i3-project-daemon/ipc.sock`)
- **Format**: JSON-RPC 2.0
- **Timeout**: 2.0 seconds (configurable in DaemonClient)

### Parameters
None - queries current state

### Example Invocation

```python
from i3_project_manager.core.daemon_client import DaemonClient, DaemonError

async def query_state():
    client = DaemonClient(timeout=2.0)
    await client.connect()
    tree_data = await client.get_window_tree()
    await client.close()
    return tree_data
```

---

## Response

### Success (HTTP 200 equivalent)

**Structure**: Nested dictionary matching Sway IPC `GET_TREE` format, enriched with project associations

**Schema**:
```python
{
  "outputs": [
    {
      "name": str,           # "eDP-1", "HDMI-A-1", "HEADLESS-1"
      "active": bool,        # True if monitor is enabled
      "focused": bool,       # True if monitor has focused workspace
      "workspaces": [
        {
          "num": int,        # Workspace number (1-70)
          "name": str,       # "1: Terminal" (may include i3wsr labels)
          "visible": bool,   # True if workspace currently visible
          "focused": bool,   # True if workspace has keyboard focus
          "output": str,     # Monitor name where workspace lives
          "windows": [
            {
              "id": int,           # Sway container ID
              "app_name": str,     # Application name from registry
              "title": str,        # Window title
              "project": str,      # Project name (empty string if global)
              "scope": str,        # "scoped" or "global"
              "icon_path": str,    # Absolute path to icon
              "workspace": int,    # Workspace number
              "floating": bool,    # True if floating window
              "hidden": bool,      # True if in scratchpad
              "focused": bool      # True if has keyboard focus
            }
          ]
        }
      ]
    }
  ],
  "total_windows": int,        # Count across all workspaces
  "total_workspaces": int      # Count across all monitors
}
```

**Example**:
```json
{
  "outputs": [
    {
      "name": "eDP-1",
      "active": true,
      "focused": true,
      "workspaces": [
        {
          "num": 1,
          "name": "1: Terminal",
          "visible": true,
          "focused": true,
          "output": "eDP-1",
          "windows": [
            {
              "id": 123456,
              "app_name": "ghostty",
              "title": "bash: ~/nixos",
              "project": "nixos",
              "scope": "scoped",
              "icon_path": "/etc/nixos/assets/icons/terminal.svg",
              "workspace": 1,
              "floating": false,
              "hidden": false,
              "focused": true
            }
          ]
        }
      ]
    }
  ],
  "total_windows": 1,
  "total_workspaces": 1
}
```

### Error Cases

#### 1. Daemon Not Running
**Scenario**: Daemon socket not found
**Exception**: `DaemonError`
**Message**: `"Daemon socket not found: /run/user/1000/i3-project-daemon/ipc.sock"`

**Handling**:
```python
try:
    tree_data = await client.get_window_tree()
except DaemonError as e:
    return {
        "status": "error",
        "outputs": [],
        "total_windows": 0,
        "error": str(e)
    }
```

#### 2. Timeout
**Scenario**: Daemon doesn't respond within timeout period
**Exception**: `DaemonError`
**Message**: `"Request timeout: method 'get_window_tree' took too long"`

**Handling**: Same as above (return error state)

#### 3. Connection Lost
**Scenario**: Daemon closes connection mid-query
**Exception**: `DaemonError` or `ConnectionResetError`
**Message**: `"Communication error: Connection closed by daemon"`

**Handling**: Same as above (return error state)

---

## Performance Expectations

### Latency
| Windows | Query Time | Evidence |
|---------|-----------|----------|
| 10      | 2-3ms     | Feature 072 measurements |
| 30      | 3-5ms     | Feature 072 measurements |
| 50      | 5-8ms     | Feature 072 measurements |
| 100     | 8-12ms    | Feature 072 measurements |

**Baseline**: Feature 072 measured ~5ms for 100 windows via daemon IPC

### Connection Overhead
- Socket open: 5-10ms
- Socket close: 1ms
- **Total overhead**: 6-11ms per invocation (stateless approach)

### Total Execution Time
For stateless backend script with 30 windows:
- Connection: 5-10ms
- Query: 3-5ms
- Close: 1ms
- **Total**: 9-16ms ✅ Under 50ms target

---

## Retry Strategy

**Policy**: No retries in backend script

**Rationale**:
- Eww defpoll provides built-in retry mechanism (next poll at interval)
- Daemon downtime is transient (systemd auto-restart within seconds)
- Keeps script execution time predictable
- Avoids blocking Eww's event loop

**Recovery**:
1. Script returns error JSON immediately
2. Eww continues polling at 10s interval
3. Next poll attempts fresh connection
4. Daemon recovery happens automatically on next poll

---

## Error Handling Pattern

```python
async def query_monitoring_data() -> dict:
    """Query daemon with graceful error handling"""
    try:
        client = DaemonClient(timeout=2.0)
        await client.connect()
        tree_data = await client.get_window_tree()
        await client.close()

        return {
            "status": "ok",
            "outputs": tree_data.get("outputs", []),
            "total_windows": tree_data.get("total_windows", 0),
            "timestamp": time.time()
        }
    except DaemonError as e:
        # Expected errors: socket not found, timeout, connection lost
        return {
            "status": "error",
            "outputs": [],
            "total_windows": 0,
            "error": str(e),
            "timestamp": time.time()
        }
    except Exception as e:
        # Unexpected errors: log and return generic error
        logging.error(f"Unexpected error querying daemon: {e}")
        return {
            "status": "error",
            "outputs": [],
            "total_windows": 0,
            "error": f"Unexpected error: {e}",
            "timestamp": time.time()
        }
```

---

## Data Transformations

### Daemon Response → Eww JSON

The backend script transforms daemon output to match Eww-friendly schema:

**Transformations**:
1. **Field renaming**: `num` → `number`, `output` → `monitor`
2. **Metadata addition**: Add `monitor_count`, `workspace_count`, `window_count`, `timestamp`
3. **Status flag**: Add `status: "ok"/"error"` field
4. **Title truncation**: Limit `window.title` to 50 chars (Eww rendering performance)
5. **Default values**: Ensure all optional fields have defaults (`floating: false`, `hidden: false`)

**Example Transformation**:
```python
def transform_window(window_data: dict) -> dict:
    """Transform daemon window data to Eww schema"""
    return {
        "id": window_data["id"],
        "app_name": window_data.get("app_name", "unknown"),
        "title": window_data.get("title", "")[:50],  # Truncate
        "project": window_data.get("project", ""),
        "scope": window_data.get("scope", "global"),
        "icon_path": window_data.get("icon_path", "/default/icon.svg"),
        "workspace": window_data.get("workspace", 1),
        "floating": window_data.get("floating", False),
        "hidden": window_data.get("hidden", False),
        "focused": window_data.get("focused", False)
    }
```

---

## Testing Strategy

### Unit Tests (pytest)

```python
@pytest.mark.asyncio
async def test_query_success(mock_daemon_client):
    """Test successful daemon query"""
    # Mock DaemonClient.get_window_tree()
    mock_daemon_client.get_window_tree.return_value = {
        "outputs": [...],
        "total_windows": 10
    }

    result = await query_monitoring_data()

    assert result["status"] == "ok"
    assert result["total_windows"] == 10
    assert "timestamp" in result

@pytest.mark.asyncio
async def test_query_daemon_unavailable(mock_daemon_client):
    """Test daemon not running error handling"""
    mock_daemon_client.connect.side_effect = DaemonError("Socket not found")

    result = await query_monitoring_data()

    assert result["status"] == "error"
    assert "Socket not found" in result["error"]
    assert result["total_windows"] == 0

@pytest.mark.asyncio
async def test_query_timeout(mock_daemon_client):
    """Test timeout error handling"""
    mock_daemon_client.get_window_tree.side_effect = DaemonError("Timeout")

    result = await query_monitoring_data()

    assert result["status"] == "error"
    assert "Timeout" in result["error"]
```

### Integration Tests (with live daemon)

```bash
# Start i3pm daemon
systemctl --user start i3-project-event-listener

# Run backend script
python3 monitoring_data.py | jq .

# Expected: JSON with status: "ok" and window data
```

---

## Dependencies

### Python Modules
- `asyncio`: Async/await support for DaemonClient
- `json`: JSON serialization/deserialization
- `time`: Unix timestamp generation
- `i3_project_manager.core.daemon_client`: DaemonClient, DaemonError classes

### System Requirements
- i3pm daemon running (`i3-project-event-listener.service`)
- Unix domain socket accessible at `/run/user/$UID/i3-project-daemon/ipc.sock`

---

## References

- **Feature 025**: `windows_cmd.py` - Stateless daemon query pattern
- **DaemonClient API**: `home-modules/tools/i3_project_manager/core/daemon_client.py`
- **Daemon Protocol**: JSON-RPC 2.0 over Unix domain sockets
- **Sway IPC**: GET_TREE format (enriched with project associations by daemon)
