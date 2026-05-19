# Contract: Eww defpoll → Python Backend Script

**Feature**: 085-sway-monitoring-widget
**Contract**: Eww `defpoll` → `monitoring_data.py` execution
**Date**: 2025-11-20

## Overview

This contract defines how the Eww widget polls the Python backend script for monitoring data updates.

The script is invoked periodically via Eww's `defpoll` mechanism and outputs JSON to stdout for consumption by Yuck widgets.

---

## Invocation

### Eww Configuration

```yuck
;; Poll monitoring data every 10 seconds (fallback mechanism)
(defpoll monitoring_data
  :interval "10s"
  :initial '{"status":"loading","monitors":[],"window_count":0}'
  `python3 ${monitoring_data_script}`)

;; Event-driven primary updates (pushed by daemon)
(defvar panel_state '{"status":"ok","monitors":[],"window_count":0}')
```

### Script Path

**Nix Variable** (in `eww-monitoring-panel.nix`):
```nix
monitoring_data_script = "${pkgs.python3}/bin/python3 -m monitoring_data";
```

**Resolved Path**: `/nix/store/.../bin/python3 -m monitoring_data`

**Working Directory**: Eww config directory (`~/.config/eww-monitoring-panel`)

---

## Script Requirements

### Execution Mode
- **Entry point**: `if __name__ == "__main__":`
- **Output**: Single-line JSON to stdout
- **Exit code**: 0 on success, 1 on error
- **Timeout**: Must complete within 5 seconds (Eww subprocess timeout)

### Performance Targets
| Metric | Target | Rationale |
|--------|--------|-----------|
| Execution time | <50ms | Avoid blocking Eww event loop |
| Output size | <100KB | Minimize JSON parsing overhead |
| Memory usage | <15MB peak | Keep Eww daemon memory footprint low |

---

## Output Format

### Success Response

**Structure**: Single-line JSON (no formatting/whitespace)

**Schema**:
```json
{"status":"ok","monitors":[...],"monitor_count":2,"workspace_count":8,"window_count":25,"timestamp":1700000000.123,"error":null}
```

**Fields**:
- `status`: Always `"ok"` on success
- `monitors`: Array of MonitorInfo objects (see data-model.md)
- `monitor_count`: Total number of monitors
- `workspace_count`: Total number of workspaces
- `window_count`: Total number of windows
- `timestamp`: Unix timestamp (float, seconds since epoch)
- `error`: Always `null` on success

**Example** (formatted for readability):
```json
{
  "status": "ok",
  "monitors": [
    {
      "name": "eDP-1",
      "active": true,
      "focused": true,
      "workspaces": [
        {
          "number": 1,
          "name": "1: Terminal",
          "visible": true,
          "focused": true,
          "monitor": "eDP-1",
          "window_count": 2,
          "windows": [
            {
              "id": 123456,
              "app_name": "ghostty",
              "title": "bash",
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
  "monitor_count": 1,
  "workspace_count": 1,
  "window_count": 2,
  "timestamp": 1700000000.123,
  "error": null
}
```

### Error Response

**Structure**: Single-line JSON with error details

**Schema**:
```json
{"status":"error","monitors":[],"monitor_count":0,"workspace_count":0,"window_count":0,"timestamp":1700000000.456,"error":"Daemon socket not found"}
```

**Fields**:
- `status`: Always `"error"` on failure
- `monitors`: Empty array
- `monitor_count`, `workspace_count`, `window_count`: All 0
- `timestamp`: Unix timestamp when error occurred
- `error`: Human-readable error message

**Example Error Messages**:
```json
// Daemon not running
{"status":"error","error":"Daemon socket not found: /run/user/1000/i3-project-daemon/ipc.sock\nIs the daemon running? Check: systemctl --user status i3-project-event-listener"}

// Timeout
{"status":"error","error":"Request timeout: method 'get_window_tree' took too long"}

// Unexpected error
{"status":"error","error":"Unexpected error: KeyError('outputs')"}
```

---

## Eww Integration

### Variable Binding

```yuck
;; Bind defpoll output to monitoring_data variable
(defpoll monitoring_data :interval "10s" `python3 ${script}`)

;; Access fields in widgets
(label :text {monitoring_data.window_count})  ; → "25"
(label :text {monitoring_data.status})        ; → "ok" or "error"
```

### Conditional Rendering

```yuck
(defwidget monitoring-panel []
  (box :class "panel"
    (if (== (monitoring_data.status) "ok")
      (monitoring-content :data monitoring_data)
      (error-message :text (monitoring_data.error)))))
```

### Null Safety

```yuck
;; Elvis operator provides default for missing fields
(for monitor in {monitoring_data.monitors ?: []}
  (label :text {monitor.name}))
```

---

## Performance Characteristics

### Polling Overhead

**Defpoll interval**: 10 seconds
**CPU usage**: ~0.09-0.18% average (9-18ms every 10s)

**Calculation**:
- Script execution: 9-18ms per invocation
- Interval: 10,000ms
- CPU usage: (9-18ms / 10,000ms) × 100% = 0.09-0.18%

### Memory Usage

**Peak memory** (30 windows):
- Python interpreter: ~10MB
- Daemon client: ~2MB
- JSON output buffer: ~15KB
- **Total**: ~12MB peak per invocation

**Persistent memory**: None (script exits after output)

### Latency Breakdown

| Operation | Time | Cumulative |
|-----------|------|------------|
| Python startup | 20-30ms | 20-30ms |
| Import modules | 5-10ms | 25-40ms |
| Connect to daemon | 5-10ms | 30-50ms |
| Query window tree | 2-5ms | 32-55ms |
| Close connection | 1ms | 33-56ms |
| Format JSON | 1-2ms | 34-58ms |
| Print to stdout | <1ms | 35-59ms |

**Total**: 35-59ms for 20-30 windows ✅ Under 50ms target (typical), under 100ms target (worst case)

---

## Error Handling

### Script Exit Codes

| Exit Code | Meaning | Eww Behavior |
|-----------|---------|--------------|
| 0         | Success | Parse JSON, update variable |
| 1         | Error   | Use last valid value or initial |
| 130       | SIGINT  | Treat as transient error |

### Timeout Handling

**Eww subprocess timeout**: 5 seconds (default)

**Scenario**: Script takes longer than 5 seconds to execute
**Eww Action**: Kill subprocess, log warning, retain previous value
**Recovery**: Next defpoll invocation retries

### JSON Parse Errors

**Scenario**: Script outputs malformed JSON
**Eww Action**: Log error, retain previous value
**Example Log**: `eww: Failed to parse JSON from defpoll 'monitoring_data'`

---

## Testing Strategy

### Unit Tests (Python)

```python
def test_script_output_format():
    """Test script outputs valid single-line JSON"""
    result = subprocess.run(
        ["python3", "-m", "monitoring_data"],
        capture_output=True,
        text=True,
        timeout=5
    )

    assert result.returncode == 0
    data = json.loads(result.stdout)  # Must not raise
    assert "status" in data
    assert "monitors" in data

def test_script_execution_time():
    """Test script completes within 50ms target"""
    start = time.time()
    subprocess.run(["python3", "-m", "monitoring_data"], timeout=1)
    duration = (time.time() - start) * 1000  # Convert to ms

    assert duration < 50, f"Script took {duration}ms (target: <50ms)"
```

### Integration Tests (Eww)

```yuck
;; Test error state rendering
(defpoll test_error :interval "1s"
  `echo '{"status":"error","monitors":[],"error":"Test error"}'`)

(defwidget test-error-display []
  (box
    (if (== (test_error.status) "error")
      (label :text "✅ Error state rendered correctly")
      (label :text "❌ Error state not detected"))))
```

### Manual Testing

```bash
# Test script directly
python3 -m monitoring_data | jq .

# Expected output:
# {
#   "status": "ok",
#   "monitors": [...],
#   "window_count": 25
# }

# Test with Eww
eww --config ~/.config/eww-monitoring-panel open monitoring-panel

# Verify:
# - Panel shows window list
# - Data updates every 10 seconds
# - No lag or freezing
```

---

## Security Considerations

### Input Validation
- **None required**: Script takes no user input
- All data sourced from trusted i3pm daemon

### Output Sanitization
- **JSON escaping**: Python `json.dumps()` handles escaping automatically
- **Path traversal**: Icon paths validated by daemon (absolute paths only)
- **Command injection**: No shell execution in script (subprocess not used)

### Resource Limits
- **Memory**: Script exits after output (no persistent memory)
- **CPU**: Single-threaded, bounded execution time
- **File descriptors**: Opens 1 socket, closes after query

---

## Debugging

### Enable Debug Logging

```python
import logging
logging.basicConfig(level=logging.DEBUG)

# Logs connection attempts, query time, errors
```

### Manual Invocation

```bash
# Run script manually to see output
python3 -m monitoring_data

# Pipe to jq for pretty-printing
python3 -m monitoring_data | jq .

# Measure execution time
time python3 -m monitoring_data > /dev/null
```

### Eww Logs

```bash
# View Eww daemon logs (includes defpoll errors)
journalctl --user -u eww --since "1 hour ago" | grep monitoring_data

# Example errors:
# "Failed to parse JSON from defpoll 'monitoring_data'"
# "Subprocess 'monitoring_data' timed out after 5s"
```

---

## Migration from Existing Patterns

### Feature 060 Eww Top Bar (Defpoll Pattern)

**Similarities**:
- Both use defpoll for periodic updates
- Both execute Python scripts via subprocess
- Both output single-line JSON

**Differences**:
- Top bar: 2s interval (more frequent)
- Monitoring panel: 10s interval (less frequent, event-driven primary)
- Top bar: System metrics (CPU, memory)
- Monitoring panel: Window/project state

---

## References

- **Eww Documentation**: `defpoll` widget documentation
- **Feature 060**: Eww Top Bar - defpoll pattern example
- **Python json module**: `json.dumps()` for serialization
- **data-model.md**: MonitoringPanelState schema definition
