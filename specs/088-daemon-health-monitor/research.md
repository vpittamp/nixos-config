# Research: Daemon Health Monitoring System

**Feature**: 088-daemon-health-monitor
**Date**: 2025-11-22
**Purpose**: Document technical decisions for implementing centralized service health monitoring

## Executive Summary

This feature will enhance the existing `monitoring_data.py --mode health` infrastructure to query systemd service health via `systemctl show` commands, categorize services into Core/UI/System/Optional groups, and provide restart capabilities with appropriate sudo handling. The research validates that systemctl provides all required metrics (status, uptime, memory, restarts) without needing JSON output (parse KEY=VALUE format instead).

## Research Areas

### 1. systemctl Command Patterns

**Decision**: Use `systemctl show <service> -p <properties> --value` for health queries

**Rationale**:
- No JSON output available from systemctl (must parse KEY=VALUE format)
- `--value` flag returns raw values without KEY= prefix for simpler parsing
- `-p` flag allows querying specific properties to reduce output size
- Querying multiple properties at once minimizes subprocess overhead

**Command Pattern**:
```bash
# User service (most GUI/desktop services)
systemctl --user show eww-top-bar.service \
  -p LoadState,ActiveState,SubState,UnitFileState,MainPID,MemoryCurrent,ActiveEnterTimestamp,NRestarts,TriggeredBy \
  --no-pager

# System service (i3-project-daemon)
systemctl show i3-project-daemon.service \
  -p LoadState,ActiveState,SubState,UnitFileState,MainPID,MemoryCurrent,ActiveEnterTimestamp,NRestarts,TriggeredBy \
  --no-pager
```

**Properties to Query**:
| Property | Purpose | Format |
|----------|---------|--------|
| `LoadState` | Service definition loaded? | `loaded`, `not-found`, `error`, `masked` |
| `ActiveState` | High-level status | `active`, `inactive`, `failed`, `activating` |
| `SubState` | Low-level status | `running`, `dead`, `exited`, `failed` |
| `UnitFileState` | Enabled/disabled state | `enabled`, `disabled`, `static`, `masked` |
| `MainPID` | Process ID (0 = not running) | Integer |
| `MemoryCurrent` | Memory usage in bytes | Integer (convert to MB: `/1024/1024`) |
| `ActiveEnterTimestamp` | When service became active | `Sat 2025-11-22 10:54:38 EST` |
| `NRestarts` | Restart counter | Integer |
| `TriggeredBy` | Socket activation | `i3-project-daemon.socket` or empty |

**Parsing Pattern**:
```python
import subprocess

result = subprocess.run(
    ["systemctl", "--user", "show", "eww-top-bar.service",
     "-p", "ActiveState,MainPID,MemoryCurrent", "--no-pager"],
    capture_output=True,
    text=True,
    timeout=2
)

# Parse KEY=VALUE output
properties = {}
for line in result.stdout.strip().split("\n"):
    if "=" in line:
        key, value = line.split("=", 1)
        properties[key] = value

active_state = properties.get("ActiveState", "unknown")
main_pid = int(properties.get("MainPID", "0"))
memory_mb = int(properties.get("MemoryCurrent", "0")) / 1024 / 1024
```

**Alternatives Considered**:
- ❌ `systemctl status <service>`: Human-readable output, inconsistent format, harder to parse
- ❌ `systemctl --output=json`: Not supported by systemctl show command
- ❌ D-Bus API: Overcomplicated for simple status queries, would require python-dbus dependency

---

### 2. Socket-Activated Service Detection

**Decision**: Check `TriggeredBy` property to identify socket-activated services

**Rationale**:
- Socket-activated services (like i3-project-daemon) may show as inactive even when healthy (socket is listening)
- Must query both service and socket status for accurate health assessment
- `TriggeredBy` property indicates which socket unit activates the service

**Detection Pattern**:
```python
# Query service for socket activation
result = subprocess.run(
    ["systemctl", "show", "i3-project-daemon.service",
     "-p", "TriggeredBy", "--value", "--no-pager"],
    capture_output=True,
    text=True
)

triggered_by = result.stdout.strip()  # Returns "i3-project-daemon.socket" or ""

if triggered_by:
    # This is a socket-activated service
    # Query socket status instead
    socket_result = subprocess.run(
        ["systemctl", "show", triggered_by,
         "-p", "ActiveState,ListenStream", "--no-pager"],
        capture_output=True,
        text=True
    )
    # Socket ActiveState=active means service is healthy (ready to accept connections)
```

**Socket Properties**:
- `ActiveState`: active = socket listening
- `ListenStream`: Socket path (e.g., `/run/i3-project-daemon/ipc.sock`)
- `Triggers`: Service activated by this socket

**Health Logic for Socket-Activated Services**:
1. If `TriggeredBy` is set → socket-activated service
2. Query socket unit (e.g., `i3-project-daemon.socket`)
3. If socket `ActiveState=active` → service healthy (even if service itself is inactive)
4. If socket `ActiveState!=active` → service unhealthy

---

### 3. Conditional Service Detection

**Decision**: Read `~/.config/sway/monitor-profile.current` to determine active monitor profile and filter service list accordingly

**Rationale**:
- WayVNC services are only active in headless mode or hybrid modes (local+1vnc, local+2vnc)
- In `local-only` profile on M1, WayVNC should show as "disabled" not "critical"
- Prevents false positives for mode-dependent services

**Monitor Profile Detection**:
```python
from pathlib import Path

# Read current monitor profile
profile_file = Path.home() / ".config/sway/monitor-profile.current"
if profile_file.exists():
    current_profile = profile_file.read_text().strip()
else:
    current_profile = "unknown"

# Determine which services should be active
if current_profile == "local-only":
    # M1 in local-only mode - WayVNC disabled
    wayvnc_enabled = False
elif current_profile in ["local+1vnc", "local+2vnc"]:
    # M1 in hybrid modes - WayVNC enabled
    wayvnc_enabled = True
elif current_profile in ["single", "dual", "triple"]:
    # Hetzner headless modes - WayVNC always enabled
    wayvnc_enabled = True
else:
    # Unknown profile - assume enabled (conservative)
    wayvnc_enabled = True
```

**Conditional Service Registry Pattern**:
```python
def get_monitored_services(monitor_profile: str) -> List[ServiceDefinition]:
    """Return list of services to monitor based on current monitor profile."""

    # Core services (always monitored)
    services = [
        {"name": "i3-project-daemon", "category": "core", "is_user": False},
        {"name": "workspace-preview-daemon", "category": "core", "is_user": True},
        # ... other core services
    ]

    # Conditional services (only in specific modes)
    if monitor_profile in ["single", "dual", "triple", "local+1vnc", "local+2vnc"]:
        services.extend([
            {"name": "wayvnc@HEADLESS-1", "category": "optional", "is_user": True},
            {"name": "wayvnc@HEADLESS-2", "category": "optional", "is_user": True},
        ])

    return services
```

**Alternative Detection Methods Considered**:
- ❌ Check service `UnitFileState`: Would show "disabled" but doesn't explain why (false negative)
- ❌ Hardcode per-platform: Doesn't handle M1 hybrid mode transitions
- ✅ **Monitor profile file**: Authoritative source for current mode, already maintained by Feature 084

---

### 4. Service Categorization Logic

**Decision**: Categorize services into 4 groups based on functional role and criticality

**Categories**:

| Category | Criteria | Examples | Color |
|----------|----------|----------|-------|
| **Core Daemons** | Critical background processes, system breaks without them | i3-project-daemon, workspace-preview-daemon, sway-tree-monitor | Red if failed |
| **UI Services** | User-facing widgets/panels, workflow impacted if down | eww-top-bar, eww-workspace-bar, eww-monitoring-panel, swaync | Orange if failed |
| **System Services** | System-level services (non-user), important but not critical | sway-config-manager, i3wsr | Yellow if failed |
| **Optional Services** | Mode-dependent or enhancement services | wayvnc@*, tailscale-rtp-default-sink | Gray if disabled |

**Rationale**:
- Users need to prioritize which failed services to restart first
- Visual grouping helps identify systemic issues (all UI services down = rebuild problem)
- Category determines urgency of restart action

**Service Registry with Categories**:
```python
SERVICE_REGISTRY = {
    "core": [
        {
            "name": "i3-project-daemon",
            "display_name": "i3 Project Daemon",
            "is_user": False,
            "socket_activated": True,
            "socket_name": "i3-project-daemon.socket",
            "description": "Window management and project context daemon",
        },
        {
            "name": "workspace-preview-daemon",
            "display_name": "Workspace Preview Daemon",
            "is_user": True,
            "socket_activated": False,
            "description": "Workspace preview data provider for Eww workspace bar",
        },
        {
            "name": "sway-tree-monitor",
            "display_name": "Sway Tree Monitor",
            "is_user": True,
            "socket_activated": False,
            "description": "Real-time Sway tree diff monitoring daemon",
        },
    ],
    "ui": [
        {
            "name": "eww-top-bar",
            "display_name": "Eww Top Bar",
            "is_user": True,
            "socket_activated": False,
            "description": "System metrics and status bar",
        },
        {
            "name": "eww-workspace-bar",
            "display_name": "Eww Workspace Bar",
            "is_user": True,
            "socket_activated": False,
            "description": "Workspace navigation and project preview bar",
        },
        {
            "name": "eww-monitoring-panel",
            "display_name": "Eww Monitoring Panel",
            "is_user": True,
            "socket_activated": False,
            "description": "Window/project/health monitoring panel",
        },
        {
            "name": "eww-quick-panel",
            "display_name": "Eww Quick Panel",
            "is_user": True,
            "socket_activated": False,
            "description": "Quick settings panel",
        },
        {
            "name": "swaync",
            "display_name": "SwayNC",
            "is_user": True,
            "socket_activated": False,
            "description": "Notification center",
        },
        {
            "name": "sov",
            "display_name": "Sway Overview (sov)",
            "is_user": True,
            "socket_activated": False,
            "description": "Workspace overview visualization",
        },
        {
            "name": "elephant",
            "display_name": "Elephant Launcher",
            "is_user": True,
            "socket_activated": False,
            "description": "Application launcher (Walker backend)",
        },
    ],
    "system": [
        {
            "name": "sway-config-manager",
            "display_name": "Sway Config Manager",
            "is_user": True,
            "socket_activated": False,
            "description": "Hot-reloadable Sway configuration manager",
        },
        {
            "name": "i3wsr",
            "display_name": "i3wsr",
            "is_user": True,
            "socket_activated": False,
            "description": "Dynamic workspace renaming based on applications",
        },
    ],
    "optional": [
        {
            "name": "wayvnc@HEADLESS-1",
            "display_name": "WayVNC (Display 1)",
            "is_user": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["single", "dual", "triple", "local+1vnc", "local+2vnc"],
            "description": "VNC server for virtual display 1",
        },
        {
            "name": "wayvnc@HEADLESS-2",
            "display_name": "WayVNC (Display 2)",
            "is_user": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["dual", "triple", "local+2vnc"],
            "description": "VNC server for virtual display 2",
        },
        {
            "name": "wayvnc@HEADLESS-3",
            "display_name": "WayVNC (Display 3)",
            "is_user": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["triple"],
            "description": "VNC server for virtual display 3 (Hetzner only)",
        },
        {
            "name": "tailscale-rtp-default-sink",
            "display_name": "Tailscale RTP Audio Sink",
            "is_user": True,
            "socket_activated": False,
            "conditional": True,
            "condition_profiles": ["single", "dual", "triple"],
            "description": "Set PipeWire default sink to Tailscale RTP (headless only)",
        },
    ],
}
```

---

### 5. Service Restart Patterns

**Decision**: Use Eww button onclick with systemctl restart, prompt for sudo when needed

**User Service Restart (No Sudo)**:
```bash
# Eww button onclick attribute
onclick="systemctl --user restart eww-top-bar.service && notify-send 'Service Restarted' 'eww-top-bar.service is now active'"
```

**System Service Restart (With Sudo)**:
```bash
# Launch terminal with sudo prompt
onclick="alacritty -e sudo systemctl restart i3-project-daemon.service"
```

**Rationale**:
- User services can be restarted without sudo (most services)
- System services require sudo (only i3-project-daemon in our list)
- Terminal-based sudo provides secure password prompt
- notify-send provides feedback for successful restarts

**Alternative Approaches Considered**:
- ❌ `pkexec systemctl restart`: Requires PolicyKit configuration, overengineered for one service
- ❌ Pre-configured sudo NOPASSWD: Security risk, violates principle of least privilege
- ✅ **Terminal with sudo**: Familiar UX, secure, minimal configuration

**Enhanced Restart Script Pattern**:
```bash
# Script: restart-service.sh
#!/usr/bin/env bash
SERVICE="$1"
IS_USER="$2"

if [ "$IS_USER" = "true" ]; then
    systemctl --user restart "$SERVICE"
    STATUS=$?
else
    sudo systemctl restart "$SERVICE"
    STATUS=$?
fi

if [ $STATUS -eq 0 ]; then
    notify-send "Service Restarted" "$SERVICE is now active"
else
    notify-send -u critical "Restart Failed" "$SERVICE could not be restarted"
fi
```

**Eww Widget Integration**:
```yuck
(defwidget health-card-with-restart [service]
  (box :class "health-card"
    (label :text "''${service.display_name}")
    (label :class "health-status health-''${service.health_state}"
           :text "''${service.status}")
    (button :class "restart-btn"
            :visible {service.status != "active"}
            :onclick "restart-service.sh ''${service.name} ''${service.is_user}"
            "↻ Restart")))
```

---

### 6. Uptime Calculation

**Decision**: Use `ActiveEnterTimestamp` property and calculate difference from current time

**Python Implementation**:
```python
from datetime import datetime
import subprocess

# Query service start time
result = subprocess.run(
    ["systemctl", "--user", "show", "eww-top-bar.service",
     "-p", "ActiveEnterTimestamp", "--value", "--no-pager"],
    capture_output=True,
    text=True
)

timestamp_str = result.stdout.strip()  # "Sat 2025-11-22 10:54:38 EST"

if timestamp_str and timestamp_str != "":
    try:
        # Parse timestamp (requires %a %Y-%m-%d %H:%M:%S %Z format)
        start_time = datetime.strptime(timestamp_str, "%a %Y-%m-%d %H:%M:%S %Z")
        uptime_seconds = (datetime.now() - start_time).total_seconds()

        # Format as human-friendly string
        if uptime_seconds < 60:
            uptime_str = f"{int(uptime_seconds)}s"
        elif uptime_seconds < 3600:
            uptime_str = f"{int(uptime_seconds / 60)}m"
        elif uptime_seconds < 86400:
            hours = int(uptime_seconds / 3600)
            minutes = int((uptime_seconds % 3600) / 60)
            uptime_str = f"{hours}h {minutes}m"
        else:
            days = int(uptime_seconds / 86400)
            hours = int((uptime_seconds % 86400) / 3600)
            uptime_str = f"{days}d {hours}h"
    except ValueError:
        uptime_str = "unknown"
else:
    uptime_str = "not running"
```

**Edge Cases**:
- Service never started (timestamp empty) → "not running"
- Service inactive (timestamp exists but ActiveState != active) → "stopped"
- Service failed (timestamp exists) → show time since failure (InactiveEnterTimestamp)

---

### 7. Health State Classification

**Decision**: Map systemd states to 5-color health indicators

**Health State Mapping**:

| Health State | Color | Criteria | User Action |
|-------------|-------|----------|-------------|
| `healthy` | Green (#a6e3a1) | `ActiveState=active`, `SubState=running` | None |
| `degraded` | Yellow (#f9e2af) | `ActiveState=active`, `SubState!=running` or high restarts | Monitor |
| `critical` | Red (#f38ba8) | `ActiveState=failed` or `LoadState=error` | Restart immediately |
| `disabled` | Gray (#6c7086) | `UnitFileState=disabled/masked` (intentional) or conditional service not in current profile | None |
| `unknown` | Orange (#fab387) | `LoadState=not-found` or unexpected state | Investigate |

**Classification Logic**:
```python
def classify_health_state(
    load_state: str,
    active_state: str,
    sub_state: str,
    unit_file_state: str,
    restart_count: int,
    is_conditional: bool,
    should_be_active: bool
) -> str:
    """Classify service health state based on systemd properties."""

    # Not found or load error
    if load_state in ["not-found", "error"]:
        return "unknown"

    # Intentionally disabled or masked
    if unit_file_state in ["disabled", "masked"]:
        return "disabled"

    # Conditional service not active in current profile
    if is_conditional and not should_be_active:
        return "disabled"

    # Failed state
    if active_state == "failed":
        return "critical"

    # Active and running normally
    if active_state == "active" and sub_state == "running":
        # Check for excessive restarts (degraded health indicator)
        if restart_count >= 3:
            return "degraded"
        return "healthy"

    # Active but not running (e.g., oneshot completed)
    if active_state == "active" and sub_state in ["exited", "dead"]:
        return "healthy"  # Normal for oneshot services

    # Inactive (not started yet or stopped)
    if active_state == "inactive":
        return "disabled"

    # Activating or deactivating (transient state)
    if active_state in ["activating", "deactivating"]:
        return "degraded"

    # Unknown state
    return "unknown"
```

---

## Implementation Recommendations

### Query Performance Optimization

1. **Batch systemctl queries** for all services in one command:
   ```python
   # Instead of 17 separate systemctl calls:
   services = " ".join([f"{s['name']}.service" for s in all_services])
   result = subprocess.run(
       ["systemctl", "--user", "show"] + services.split() +
       ["-p", "ActiveState,MainPID,MemoryCurrent", "--no-pager"],
       capture_output=True,
       text=True,
       timeout=5
   )
   ```

2. **Cache monitor profile** (read once, not per service)

3. **Parallel queries for system vs user services**:
   ```python
   import concurrent.futures

   with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
       user_future = executor.submit(query_user_services, user_services)
       system_future = executor.submit(query_system_services, system_services)

       user_health = user_future.result()
       system_health = system_future.result()
   ```

### Error Handling

1. **Timeout protection**: All subprocess calls with `timeout=2-5s`
2. **Graceful degradation**: If systemctl fails, return empty health data with error message
3. **Missing properties**: Use `.get()` with defaults when parsing KEY=VALUE output

### Testing Strategy

1. **Unit tests**: Mock subprocess.run to test parsing logic with sample systemctl output
2. **Integration tests**: Query real services on test system, validate health classification
3. **Edge case tests**: Not-found services, socket-activated services, conditional services

---

## Open Questions & Decisions

### ✅ RESOLVED: How to handle legacy services?

**Decision**: Exclude from SERVICE_REGISTRY entirely, do not monitor

**Rationale**:
- Monitoring legacy services wastes resources and clutters UI
- Forward-only development principle (Constitution XII) mandates complete removal
- Example: If `i3-project-event-listener` references still exist, remove during implementation

### ✅ RESOLVED: Should we monitor onepassword-gui service?

**Decision**: NO - exclude from monitoring

**Rationale**:
- Not critical for system functionality (user can launch manually)
- Autostart service, not a daemon
- Adds noise to health tab without value

### ✅ RESOLVED: How to display health indicators in Eww?

**Decision**: Grouped health cards with category headers

**UI Layout**:
```
┌─ Health Tab ──────────────────────────┐
│ Core Daemons (3/3 healthy)            │
│ ┌──────────────────────────────────┐  │
│ │ ✓ i3 Project Daemon      [↻]    │  │
│ │ ✓ Workspace Preview      [↻]    │  │
│ │ ✓ Sway Tree Monitor      [↻]    │  │
│ └──────────────────────────────────┘  │
│                                        │
│ UI Services (6/6 healthy)              │
│ ┌──────────────────────────────────┐  │
│ │ ✓ Eww Top Bar            [↻]    │  │
│ │ ✓ Eww Workspace Bar      [↻]    │  │
│ │ ✓ Eww Monitoring Panel   [↻]    │  │
│ │ ✓ Eww Quick Panel        [↻]    │  │
│ │ ✓ SwayNC                 [↻]    │  │
│ │ ✓ Elephant Launcher      [↻]    │  │
│ └──────────────────────────────────┘  │
│                                        │
│ System Services (2/2 healthy)          │
│ ┌──────────────────────────────────┐  │
│ │ ✓ Sway Config Manager    [↻]    │  │
│ │ ✓ i3wsr                  [↻]    │  │
│ └──────────────────────────────────┘  │
│                                        │
│ Optional Services (2/2 disabled)       │
│ ┌──────────────────────────────────┐  │
│ │ ○ WayVNC (Display 1)     [↻]    │  │
│ │ ○ WayVNC (Display 2)     [↻]    │  │
│ └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

**Status Icons**:
- ✓ (green checkmark): healthy
- ⚠ (yellow warning): degraded
- ✗ (red X): critical
- ○ (gray circle): disabled
- ? (orange question): unknown

---

## Next Steps (Phase 1)

1. Create `data-model.md` with ServiceHealth, ServiceCategory, SystemHealth entities
2. Create contract schemas for systemctl output and health query response
3. Generate quickstart.md with user instructions
4. Update agent context with new technology decisions

**Total Research Time**: ~2 hours (systemctl investigation, service catalog, categorization design)