# i3pm CLI - Monitoring Data Backend

## Feature 088: Daemon Health Monitoring System

This module provides comprehensive health monitoring for all critical NixOS/home-manager services.

## Health Query Mode

### Usage

```bash
# One-shot query (returns JSON and exits)
monitoring-data-backend --mode health

# Streaming mode (continuous updates via deflisten)
monitoring-data-backend --listen
```

### Response Schema

#### Success Response

```json
{
  "status": "ok",
  "health": {
    "timestamp": 1732291234.567,
    "timestamp_friendly": "2025-11-22 14:30:34",
    "monitoring_functional": true,
    "current_monitor_profile": "local-only",
    "total_services": 17,
    "healthy_count": 15,
    "degraded_count": 1,
    "critical_count": 0,
    "disabled_count": 1,
    "unknown_count": 0,
    "system_health": "degraded",
    "categories": [
      {
        "category_name": "core",
        "display_name": "Core Daemons",
        "services": [
          {
            "service_name": "i3-project-daemon.service",
            "display_name": "i3 Project Daemon",
            "category": "core",
            "description": "Window management and project context daemon",
            "is_user_service": false,
            "is_socket_activated": true,
            "socket_name": "i3-project-daemon.socket",
            "is_conditional": false,
            "condition_profiles": null,
            "load_state": "loaded",
            "active_state": "inactive",
            "sub_state": "dead",
            "unit_file_state": "static",
            "health_state": "healthy",
            "main_pid": 0,
            "uptime_seconds": 0,
            "memory_usage_mb": 0.0,
            "restart_count": 0,
            "last_active_time": null,
            "status_icon": "✓",
            "uptime_friendly": "0s",
            "can_restart": true
          }
        ],
        "total_count": 3,
        "healthy_count": 3,
        "degraded_count": 0,
        "critical_count": 0,
        "disabled_count": 0,
        "unknown_count": 0,
        "category_health": "healthy"
      }
    ],
    "error": null
  },
  "timestamp": 1732291234.567,
  "timestamp_friendly": "2025-11-22 14:30:34",
  "error": null
}
```

#### Error Response

```json
{
  "status": "error",
  "health": {
    "timestamp": 1732291234.567,
    "timestamp_friendly": "2025-11-22 14:30:34",
    "monitoring_functional": false,
    "current_monitor_profile": "unknown",
    "total_services": 0,
    "healthy_count": 0,
    "degraded_count": 0,
    "critical_count": 0,
    "disabled_count": 0,
    "unknown_count": 0,
    "categories": [],
    "system_health": "critical",
    "error": "Health query failed: Exception: systemctl not found"
  },
  "timestamp": 1732291234.567,
  "timestamp_friendly": "2025-11-22 14:30:34",
  "error": "Health query failed: Exception: systemctl not found"
}
```

## Health States

| State | Icon | Color | Description |
|-------|------|-------|-------------|
| `healthy` | ✓ | Green | Service is active and running normally |
| `degraded` | ⚠ | Yellow | Service is active but has restarted 3+ times |
| `critical` | ✗ | Red | Service is failed or broken |
| `disabled` | ○ | Gray | Service is intentionally disabled |
| `unknown` | ? | Orange | Service state cannot be determined |

## Service Fields

### Core Fields
- `service_name`: systemd service unit name (e.g., "eww-top-bar.service")
- `display_name`: Human-readable name (e.g., "Eww Top Bar")
- `category`: Service category ("core", "ui", "system", "optional")
- `description`: Brief description of service function

### Service Type
- `is_user_service`: Boolean - user service (--user) vs system service
- `is_socket_activated`: Boolean - socket-activated service
- `socket_name`: Socket unit name if socket-activated
- `is_conditional`: Boolean - depends on monitor profile
- `condition_profiles`: List of profiles where service should be active

### Systemd State
- `load_state`: systemd LoadState (loaded, not-found, error)
- `active_state`: systemd ActiveState (active, inactive, failed)
- `sub_state`: systemd SubState (running, dead, failed)
- `unit_file_state`: systemd UnitFileState (enabled, disabled, static)

### Health Metrics (US2, US4)
- `health_state`: Computed health state (see Health States table)
- `main_pid`: Process ID (0 if not running)
- `uptime_seconds`: Seconds since service activation
- `uptime_friendly`: Human-readable uptime (e.g., "5h 23m")
- `memory_usage_mb`: Memory usage in megabytes
- `restart_count`: Number of times service has restarted
- `last_active_time`: Timestamp of last activation (for failed services)
- `status_icon`: Icon representing health state
- `can_restart`: Boolean - whether service can be restarted

## Monitor Profiles

Services are filtered based on the current monitor profile:

- **local-only**: M1 local display only (no VNC)
- **local+1vnc**: M1 local + 1 VNC virtual display
- **local+2vnc**: M1 local + 2 VNC virtual displays
- **single**: Hetzner single monitor (headless)
- **dual**: Hetzner dual monitor (headless)
- **triple**: Hetzner triple monitor (headless)

Conditional services (WayVNC, Tailscale RTP) are shown as "disabled" when not required by current profile.

## Logging

Logs are written to stderr with the following format:

```
[2025-11-22 14:30:34,567] INFO: Feature 088: Starting health query
[2025-11-22 14:30:34,789] INFO: Feature 088: Monitor profile: local-only
[2025-11-22 14:30:35,012] INFO: Feature 088: Health query complete - 17 services, system health: healthy
[2025-11-22 14:30:35,234] ERROR: Feature 088: Timeout querying wayvnc@HEADLESS-1.service
```

## Error Handling

- **Subprocess Timeout**: 2-second timeout on all systemctl calls
- **TimeoutExpired**: Returns error state with "unknown" health
- **Exception**: Returns not-found state for service
- **Query Failure**: Returns error response with monitoring_functional=false

## Integration

### Eww Widget

```yuck
;; One-shot polling (5s refresh)
(defpoll health_data
  :interval "5s"
  :initial "{\"status\":\"loading\"}"
  `monitoring-data-backend --mode health`)

;; Streaming mode (recommended - <100ms latency)
(deflisten health_data
  :initial "{\"status\":\"connecting\"}"
  `monitoring-data-backend --listen`)
```

### Manual Query

```bash
# Query health and format output
monitoring-data-backend --mode health | jq '.health.system_health'

# Filter critical services
monitoring-data-backend --mode health | jq '.health.categories[].services[] | select(.health_state == "critical")'

# Show services with high restart counts
monitoring-data-backend --mode health | jq '.health.categories[].services[] | select(.restart_count >= 3)'
```

## Service Registry

16 monitored services across 4 categories:

### Core Daemons (3)
- i3-project-daemon (socket-activated)
- workspace-preview-daemon
- sway-tree-monitor

### UI Services (7)
- eww-top-bar
- eww-workspace-bar
- eww-monitoring-panel
- eww-quick-panel
- swaync (notification center)
- sov (workspace overview)
- elephant (launcher)

### System Services (1)
- sway-config-manager

### Optional Services (4 - conditional)
- wayvnc@HEADLESS-1 (VNC display 1)
- wayvnc@HEADLESS-2 (VNC display 2)
- wayvnc@HEADLESS-3 (VNC display 3)
- tailscale-rtp-default-sink (audio routing)

## Restart Functionality (US3)

Services can be restarted via the `restart-service` command:

```bash
# Restart user service
restart-service eww-top-bar true

# Restart system service (requires sudo)
restart-service tailscaled.service false
```

Restart button is shown in UI when `can_restart` is true.

## See Also

- Feature 088 Specification: `/specs/088-daemon-health-monitor/spec.md`
- Implementation Plan: `/specs/088-daemon-health-monitor/plan.md`
- Data Model: `/specs/088-daemon-health-monitor/data-model.md`
- Quickstart Guide: `/specs/088-daemon-health-monitor/quickstart.md`
