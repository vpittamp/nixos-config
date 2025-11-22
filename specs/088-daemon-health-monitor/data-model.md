# Data Model: Daemon Health Monitoring System

**Feature**: 088-daemon-health-monitor
**Version**: 1.0
**Date**: 2025-11-22

## Overview

This document defines the data structures for centralized daemon health monitoring. The model consists of three primary entities: ServiceHealth (individual service state), ServiceCategory (logical grouping), and SystemHealth (overall health summary).

## Entity Definitions

### ServiceHealth

Represents the health state and metrics for a single systemd service.

**Purpose**: Track status, resource usage, and restart history for each monitored daemon.

**Schema**:
```python
from typing import Optional, Literal
from pydantic import BaseModel, Field

class ServiceHealth(BaseModel):
    """Health state for a single systemd service."""

    # Identity
    service_name: str = Field(
        ...,
        description="Systemd service name (e.g., 'eww-top-bar.service')",
        example="eww-top-bar.service"
    )
    display_name: str = Field(
        ...,
        description="Human-friendly display name",
        example="Eww Top Bar"
    )
    category: Literal["core", "ui", "system", "optional"] = Field(
        ...,
        description="Service category for grouping and prioritization"
    )
    description: str = Field(
        ...,
        description="Brief description of service purpose",
        example="System metrics and status bar"
    )

    # Service Configuration
    is_user_service: bool = Field(
        ...,
        description="True if user service (systemctl --user), False if system service",
        example=True
    )
    is_socket_activated: bool = Field(
        default=False,
        description="True if service uses socket activation"
    )
    socket_name: Optional[str] = Field(
        default=None,
        description="Associated socket unit name if socket_activated=True",
        example="i3-project-daemon.socket"
    )

    # Conditional Service Support
    is_conditional: bool = Field(
        default=False,
        description="True if service is mode-dependent (e.g., WayVNC)"
    )
    condition_profiles: Optional[list[str]] = Field(
        default=None,
        description="Monitor profiles where this service should be active",
        example=["single", "dual", "triple"]
    )

    # Systemd State Properties
    load_state: Literal["loaded", "not-found", "error", "masked", "unknown"] = Field(
        ...,
        description="Whether service definition was loaded by systemd"
    )
    active_state: Literal["active", "inactive", "failed", "activating", "deactivating", "unknown"] = Field(
        ...,
        description="High-level activation state"
    )
    sub_state: Literal["running", "dead", "exited", "failed", "start", "stop", "unknown"] = Field(
        ...,
        description="Low-level state (type-dependent)"
    )
    unit_file_state: Literal["enabled", "disabled", "static", "masked", "not-found", "unknown"] = Field(
        ...,
        description="Enable/disable state"
    )

    # Health Classification
    health_state: Literal["healthy", "degraded", "critical", "disabled", "unknown"] = Field(
        ...,
        description="Computed health indicator based on systemd states and metrics"
    )

    # Process Information
    main_pid: int = Field(
        default=0,
        description="Main process ID (0 if not running)"
    )

    # Resource Metrics
    uptime_seconds: int = Field(
        default=0,
        description="Seconds since service entered active state (0 if inactive)"
    )
    memory_usage_mb: float = Field(
        default=0.0,
        description="Current memory usage in megabytes"
    )
    restart_count: int = Field(
        default=0,
        description="Number of restarts since service started (NRestarts property)"
    )

    # Timestamps
    last_active_time: Optional[str] = Field(
        default=None,
        description="Human-readable timestamp when service last became active (ActiveEnterTimestamp)",
        example="Sat 2025-11-22 10:54:38 EST"
    )

    # UI Helper Fields
    status_icon: str = Field(
        default="?",
        description="Icon to display in UI (✓/⚠/✗/○/?)",
        example="✓"
    )
    uptime_friendly: str = Field(
        default="",
        description="Human-friendly uptime string (e.g., '5h 23m')",
        example="5h 23m"
    )
    can_restart: bool = Field(
        default=True,
        description="Whether restart button should be shown (false if disabled/not-found)"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "service_name": "eww-top-bar.service",
                "display_name": "Eww Top Bar",
                "category": "ui",
                "description": "System metrics and status bar",
                "is_user_service": True,
                "is_socket_activated": False,
                "socket_name": None,
                "is_conditional": False,
                "condition_profiles": None,
                "load_state": "loaded",
                "active_state": "active",
                "sub_state": "running",
                "unit_file_state": "enabled",
                "health_state": "healthy",
                "main_pid": 4351,
                "uptime_seconds": 1245,
                "memory_usage_mb": 165.3,
                "restart_count": 0,
                "last_active_time": "Sat 2025-11-22 10:54:38 EST",
                "status_icon": "✓",
                "uptime_friendly": "20m",
                "can_restart": True
            }
        }
```

**Field Derivation**:

- `health_state`: Computed from `load_state`, `active_state`, `sub_state`, `unit_file_state`, `restart_count`
- `uptime_seconds`: Calculated from `ActiveEnterTimestamp` and current time
- `uptime_friendly`: Formatted from `uptime_seconds` (e.g., "5h 23m")
- `memory_usage_mb`: Converted from `MemoryCurrent` (bytes) via `/1024/1024`
- `status_icon`: Mapped from `health_state` (healthy→✓, degraded→⚠, critical→✗, disabled→○, unknown→?)
- `can_restart`: `False` if `health_state` in ["disabled", "unknown"] and `load_state` == "not-found"

**Validation Rules**:
- `service_name` MUST end with `.service`
- `socket_name` MUST end with `.socket` if provided
- `uptime_seconds` MUST be 0 if `active_state != "active"`
- `main_pid` MUST be 0 if `active_state != "active"`

---

### ServiceCategory

Represents a logical grouping of services for UI organization and health summarization.

**Purpose**: Group services by functional role (Core/UI/System/Optional) and compute category-level health metrics.

**Schema**:
```python
class ServiceCategory(BaseModel):
    """Logical grouping of services with health summary."""

    category_name: Literal["core", "ui", "system", "optional"] = Field(
        ...,
        description="Category identifier"
    )
    display_name: str = Field(
        ...,
        description="Human-friendly category name for UI",
        example="Core Daemons"
    )
    services: list[ServiceHealth] = Field(
        default_factory=list,
        description="Services in this category"
    )

    # Computed Metrics
    total_count: int = Field(
        default=0,
        description="Total number of services in category"
    )
    healthy_count: int = Field(
        default=0,
        description="Number of services in healthy state"
    )
    degraded_count: int = Field(
        default=0,
        description="Number of services in degraded state"
    )
    critical_count: int = Field(
        default=0,
        description="Number of services in critical state"
    )
    disabled_count: int = Field(
        default=0,
        description="Number of services in disabled state"
    )
    unknown_count: int = Field(
        default=0,
        description="Number of services in unknown state"
    )

    # Category Health Summary
    category_health: Literal["healthy", "degraded", "critical", "disabled", "mixed"] = Field(
        default="healthy",
        description="Overall category health state"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "category_name": "ui",
                "display_name": "UI Services",
                "services": [],  # List of ServiceHealth objects
                "total_count": 6,
                "healthy_count": 6,
                "degraded_count": 0,
                "critical_count": 0,
                "disabled_count": 0,
                "unknown_count": 0,
                "category_health": "healthy"
            }
        }
```

**Category Health Computation**:
```python
def compute_category_health(services: list[ServiceHealth]) -> str:
    """Compute overall category health from service health states."""
    if not services:
        return "disabled"

    health_counts = {
        "critical": sum(1 for s in services if s.health_state == "critical"),
        "degraded": sum(1 for s in services if s.health_state == "degraded"),
        "unknown": sum(1 for s in services if s.health_state == "unknown"),
        "disabled": sum(1 for s in services if s.health_state == "disabled"),
        "healthy": sum(1 for s in services if s.health_state == "healthy"),
    }

    # Priority: critical > degraded > unknown > mixed > healthy > disabled
    if health_counts["critical"] > 0:
        return "critical"
    if health_counts["degraded"] > 0:
        return "degraded"
    if health_counts["unknown"] > 0:
        return "mixed"  # Some services unknown
    if health_counts["disabled"] == len(services):
        return "disabled"  # All disabled
    if health_counts["healthy"] == len(services):
        return "healthy"  # All healthy
    return "mixed"  # Mix of healthy/disabled
```

**Category Display Names**:
- `core` → "Core Daemons"
- `ui` → "UI Services"
- `system` → "System Services"
- `optional` → "Optional Services"

---

### SystemHealth

Represents overall system health summary and metadata.

**Purpose**: Provide top-level health metrics for quick assessment and timestamp for staleness detection.

**Schema**:
```python
class SystemHealth(BaseModel):
    """Overall system health summary."""

    # Query Metadata
    timestamp: float = Field(
        ...,
        description="Unix timestamp when health data was collected",
        example=1732291478.5
    )
    timestamp_friendly: str = Field(
        ...,
        description="Human-friendly timestamp (e.g., 'Just now', '5 seconds ago')",
        example="Just now"
    )
    monitoring_functional: bool = Field(
        default=True,
        description="Whether health monitoring system itself is functional"
    )
    current_monitor_profile: str = Field(
        default="unknown",
        description="Active monitor profile from ~/.config/sway/monitor-profile.current",
        example="local+1vnc"
    )

    # Service Counts
    total_services: int = Field(
        default=0,
        description="Total number of services being monitored"
    )
    healthy_count: int = Field(
        default=0,
        description="Number of services in healthy state"
    )
    degraded_count: int = Field(
        default=0,
        description="Number of services in degraded state"
    )
    critical_count: int = Field(
        default=0,
        description="Number of services in critical state"
    )
    disabled_count: int = Field(
        default=0,
        description="Number of services in disabled state"
    )
    unknown_count: int = Field(
        default=0,
        description="Number of services in unknown state"
    )

    # Category Data
    categories: list[ServiceCategory] = Field(
        default_factory=list,
        description="Service categories with health details"
    )

    # Overall Health State
    system_health: Literal["healthy", "degraded", "critical", "mixed"] = Field(
        default="healthy",
        description="Overall system health based on all services"
    )

    # Error Handling
    error: Optional[str] = Field(
        default=None,
        description="Error message if health query failed"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "timestamp": 1732291478.5,
                "timestamp_friendly": "Just now",
                "monitoring_functional": True,
                "current_monitor_profile": "local+1vnc",
                "total_services": 17,
                "healthy_count": 15,
                "degraded_count": 0,
                "critical_count": 1,
                "disabled_count": 1,
                "unknown_count": 0,
                "categories": [],  # List of ServiceCategory objects
                "system_health": "degraded",
                "error": None
            }
        }
```

**System Health Computation**:
```python
def compute_system_health(categories: list[ServiceCategory]) -> str:
    """Compute overall system health from category health states."""
    if not categories:
        return "critical"

    # Aggregate all category health states
    category_healths = [c.category_health for c in categories]

    # Priority: critical > degraded > mixed > healthy
    if "critical" in category_healths:
        return "critical"
    if "degraded" in category_healths:
        return "degraded"
    if "mixed" in category_healths:
        return "mixed"
    if all(h == "disabled" for h in category_healths):
        return "mixed"  # All disabled = unusual state
    return "healthy"
```

---

## Data Flow

### Query → Transform → Display Pipeline

```
1. Query systemctl (subprocess)
   ↓
2. Parse KEY=VALUE output → ServiceHealth objects
   ↓
3. Group by category → ServiceCategory objects
   ↓
4. Aggregate metrics → SystemHealth object
   ↓
5. Serialize to JSON → Eww defpoll consumption
   ↓
6. Render in Health tab UI
```

### Example Data Flow

**Input** (systemctl show output):
```
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=4351
MemoryCurrent=165249024
ActiveEnterTimestamp=Sat 2025-11-22 10:54:38 EST
NRestarts=0
TriggeredBy=
```

**Transform** (ServiceHealth):
```python
ServiceHealth(
    service_name="eww-top-bar.service",
    display_name="Eww Top Bar",
    category="ui",
    description="System metrics and status bar",
    is_user_service=True,
    is_socket_activated=False,
    load_state="loaded",
    active_state="active",
    sub_state="running",
    unit_file_state="enabled",
    health_state="healthy",  # Computed
    main_pid=4351,
    uptime_seconds=1245,  # Computed from timestamp
    memory_usage_mb=157.5,  # Computed from bytes
    restart_count=0,
    last_active_time="Sat 2025-11-22 10:54:38 EST",
    status_icon="✓",  # Computed
    uptime_friendly="20m",  # Computed
    can_restart=True
)
```

**Output** (JSON for Eww):
```json
{
  "status": "ok",
  "health": {
    "timestamp": 1732291478.5,
    "timestamp_friendly": "Just now",
    "monitoring_functional": true,
    "current_monitor_profile": "local+1vnc",
    "total_services": 17,
    "healthy_count": 16,
    "degraded_count": 0,
    "critical_count": 1,
    "disabled_count": 0,
    "unknown_count": 0,
    "categories": [
      {
        "category_name": "ui",
        "display_name": "UI Services",
        "total_count": 6,
        "healthy_count": 6,
        "category_health": "healthy",
        "services": [
          {
            "service_name": "eww-top-bar.service",
            "display_name": "Eww Top Bar",
            "health_state": "healthy",
            "status_icon": "✓",
            "uptime_friendly": "20m",
            "memory_usage_mb": 157.5
          }
        ]
      }
    ],
    "system_health": "degraded"
  },
  "timestamp": 1732291478.5,
  "timestamp_friendly": "Just now",
  "error": null
}
```

---

## Relationships

```
SystemHealth (1)
    ├── categories: List[ServiceCategory] (4)
    │   ├── ServiceCategory "core" (1)
    │   │   └── services: List[ServiceHealth] (3)
    │   ├── ServiceCategory "ui" (1)
    │   │   └── services: List[ServiceHealth] (6)
    │   ├── ServiceCategory "system" (1)
    │   │   └── services: List[ServiceHealth] (2)
    │   └── ServiceCategory "optional" (1)
    │       └── services: List[ServiceHealth] (4)
    └── error: Optional[str]
```

---

## Usage Example

```python
from i3_project_manager.cli.monitoring_data import query_health_data
import asyncio

async def main():
    # Query health data
    health_response = await query_health_data()

    # Access system-level metrics
    print(f"System Health: {health_response['health']['system_health']}")
    print(f"Total Services: {health_response['health']['total_services']}")
    print(f"Critical Services: {health_response['health']['critical_count']}")

    # Access category-level metrics
    for category in health_response['health']['categories']:
        print(f"\n{category['display_name']} ({category['category_health']})")
        print(f"  Healthy: {category['healthy_count']}/{category['total_count']}")

        # Access individual service health
        for service in category['services']:
            if service['health_state'] == 'critical':
                print(f"  ✗ {service['display_name']} - {service['active_state']}")

asyncio.run(main())
```

**Output**:
```
System Health: degraded
Total Services: 17
Critical Services: 1

Core Daemons (healthy)
  Healthy: 3/3

UI Services (healthy)
  Healthy: 6/6

System Services (degraded)
  Healthy: 1/2
  ✗ Sway Config Manager - failed

Optional Services (disabled)
  Healthy: 0/4
```

---

## State Transitions

### Service Health State Machine

```
[Service Created]
       ↓
    disabled ←─────────────┐
       ↓                   │
    (systemctl enable)     │
       ↓                   │
    inactive              │
       ↓                   │
    (systemctl start)     │
       ↓                   │
    activating            │
       ↓                   │
    healthy ←──────────┐   │
       ↓               │   │
    (high restarts)    │   │
       ↓               │   │
    degraded           │   │
       ↓               │   │
    (service fails)    │   │
       ↓               │   │
    critical           │   │
       ↓               │   │
    (auto-restart)────┘   │
       ↓                   │
    (systemctl disable)───┘
```

### Category Health Aggregation

```
All services healthy → category "healthy"
Any service degraded → category "degraded"
Any service critical → category "critical"
Mix of states        → category "mixed"
All disabled         → category "disabled"
```

---

## Implementation Notes

1. **Immutability**: ServiceHealth objects are immutable (Pydantic frozen=True recommended for production)
2. **Caching**: Health data refreshes every 5s via Eww defpoll (no caching needed in Python)
3. **Error Handling**: If systemctl query fails, populate `error` field and set `monitoring_functional=False`
4. **Performance**: Batch systemctl queries to minimize subprocess overhead
5. **Backward Compatibility**: N/A - new feature, no legacy data format to support