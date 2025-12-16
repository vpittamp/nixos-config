# Data Model: Improve Socket Discovery and Service Reliability

**Feature Branch**: `121-improve-socket-discovery`
**Date**: 2025-12-16

## Entities

### SocketHealthStatus

Represents the health status of the Sway IPC socket connection.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| status | enum | Connection status | "healthy", "stale", "disconnected" |
| socket_path | string | Path to current socket | Must start with /run/user/ |
| last_validated | datetime | ISO8601 timestamp of last validation | Required |
| latency_ms | integer | Round-trip time for last health check | >= 0 |
| reconnection_count | integer | Number of reconnections since daemon start | >= 0 |
| uptime_seconds | float | Seconds since last successful connection | >= 0 |

**State Transitions**:
- `disconnected` → `healthy`: Successful connection established
- `healthy` → `stale`: Health check fails (socket exists but unresponsive)
- `stale` → `disconnected`: Socket file removed or reconnection initiated
- `disconnected` → `stale`: Socket exists but process not responding
- `stale` → `healthy`: Reconnection succeeds

### SwaySocket

Represents a Sway IPC socket file in the runtime directory.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| path | string | Full path to socket | /run/user/$UID/sway-ipc.$UID.$PID.sock |
| uid | integer | User ID extracted from filename | Must match current user |
| pid | integer | Process ID extracted from filename | Must be valid PID format |
| exists | boolean | Whether file exists | Derived from filesystem |
| process_alive | boolean | Whether PID references running process | Derived from /proc/$PID |
| process_is_sway | boolean | Whether process is actually sway | Derived from /proc/$PID/comm |

**Validation Rules**:
- Socket is "valid" if: `exists && process_alive && process_is_sway`
- Socket is "stale" if: `exists && (!process_alive || !process_is_sway)`

### ServiceTargetMapping

Configuration entity for systemd service target assignments.

| Service | Current Target | New Target | Rationale |
|---------|---------------|------------|-----------|
| i3-project-daemon | graphical-session.target | sway-session.target | Requires Sway IPC |
| eww-monitoring-panel | graphical-session.target | sway-session.target | Uses swaymsg for workspace data |
| sway-config-manager | graphical-session.target | sway-session.target | Directly uses swaymsg |
| i3wsr | graphical-session.target | sway-session.target | Sway workspace renamer |
| onepassword-autostart | graphical-session.target | (unchanged) | Not Sway-specific |
| tmux-ai-monitor | graphical-session.target | (unchanged) | Not Sway-specific |

## Relationships

```
┌─────────────────────┐
│  sway-session.target│
└─────────┬───────────┘
          │ WantedBy, PartOf, After
          ▼
┌─────────────────────┐     ┌─────────────────────┐
│ i3-project-daemon   │────▶│ SocketHealthStatus  │
└─────────────────────┘     └─────────────────────┘
          │                           │
          │ discovers                 │ validates
          ▼                           ▼
┌─────────────────────┐     ┌─────────────────────┐
│     SwaySocket      │◀────│ sway-socket-cleanup │
└─────────────────────┘     │      (timer)        │
                            └─────────────────────┘
```

## IPC Message Types

### get_socket_health (new)

**Request**:
```json
{
  "type": "get_socket_health"
}
```

**Response**:
```json
{
  "status": "healthy",
  "socket_path": "/run/user/1000/sway-ipc.1000.12345.sock",
  "last_validated": "2025-12-16T10:30:00Z",
  "latency_ms": 5,
  "reconnection_count": 0,
  "uptime_seconds": 3600
}
```

**Error Response** (when daemon has no Sway connection):
```json
{
  "status": "disconnected",
  "socket_path": null,
  "last_validated": null,
  "latency_ms": null,
  "reconnection_count": 3,
  "uptime_seconds": 0,
  "error": "No Sway IPC connection available"
}
```
