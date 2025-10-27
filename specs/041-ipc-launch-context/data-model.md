# Data Model: IPC Launch Context

**Feature**: 041-ipc-launch-context
**Date**: 2025-10-27
**Version**: 1.0

## Overview

This document defines the Pydantic data models and entity relationships for the IPC launch notification system. All models use strict type validation and follow the Python development standards from Constitution Principle X.

---

## Core Entities

### 1. PendingLaunch

Represents an application launch awaiting correlation with a new window.

**Lifecycle**: Created on `notify_launch` IPC call → Matched to window within 5 seconds → Removed on expiration or match

```python
from pydantic import BaseModel, Field, validator
from pathlib import Path
from typing import Optional

class PendingLaunch(BaseModel):
    """
    Represents a pending application launch awaiting window correlation.

    A pending launch is created when the launcher wrapper notifies the daemon
    that an application is about to start. The daemon uses this context to
    correlate the next matching window to the correct project.
    """

    # Core identification
    app_name: str = Field(
        ...,
        description="Application name from registry (e.g., 'vscode', 'terminal')"
    )
    project_name: str = Field(
        ...,
        description="Project name for this launch (e.g., 'nixos', 'stacks')"
    )
    project_directory: Path = Field(
        ...,
        description="Absolute path to project directory"
    )

    # Launch metadata
    launcher_pid: int = Field(
        ...,
        gt=0,
        description="Process ID of the launcher wrapper script"
    )
    workspace_number: int = Field(
        ...,
        ge=1,
        le=70,
        description="Target workspace number for the application"
    )
    timestamp: float = Field(
        ...,
        description="Unix timestamp (seconds.microseconds) when launch notification sent"
    )

    # Correlation context
    expected_class: str = Field(
        ...,
        description="Window class expected for this application (from app registry)"
    )

    # State tracking
    matched: bool = Field(
        default=False,
        description="True if this launch has been matched to a window"
    )

    @validator('project_directory')
    def validate_directory_exists(cls, v):
        """Validate project directory exists (optional - may be created later)."""
        # Note: Not enforcing existence to support project creation workflows
        return v.resolve()  # Normalize to absolute path

    @validator('timestamp')
    def validate_timestamp_recent(cls, v):
        """Validate timestamp is not in the future (allows small clock skew)."""
        import time
        now = time.time()
        if v > now + 1.0:  # Allow 1 second clock skew
            raise ValueError(f"Launch timestamp {v} is in the future (now={now})")
        return v

    def age(self, current_time: float) -> float:
        """Calculate age of this pending launch in seconds."""
        return current_time - self.timestamp

    def is_expired(self, current_time: float, timeout: float = 5.0) -> bool:
        """Check if this launch has exceeded the correlation timeout."""
        return self.age(current_time) > timeout

    def __str__(self) -> str:
        return (
            f"PendingLaunch(app={self.app_name}, project={self.project_name}, "
            f"workspace={self.workspace_number}, age={self.age(time.time()):.2f}s)"
        )

    class Config:
        # Allow Path objects in JSON serialization
        json_encoders = {
            Path: str
        }
```

**Validation Rules**:
- `launcher_pid` must be positive integer
- `workspace_number` must be 1-70 (i3 workspace range)
- `timestamp` must not be >1s in the future (clock skew tolerance)
- `project_directory` normalized to absolute path

**Invariants**:
- Once `matched=True`, the launch should not be matched again
- Launches with `age() > 5.0` should be removed from registry

---

### 2. WindowInfo

Represents a newly created window requiring correlation to a pending launch.

**Lifecycle**: Extracted from i3 window::new event → Used for correlation query → Discarded after match attempt

```python
from pydantic import BaseModel, Field

class WindowInfo(BaseModel):
    """
    Information about a newly created window for correlation.

    Extracted from i3 window::new event container properties. Used to
    find the best matching pending launch based on application class,
    timing, and workspace location.
    """

    # Window identity
    window_id: int = Field(
        ...,
        description="i3 window/container ID (unique)"
    )
    window_class: str = Field(
        ...,
        description="X11 window class (e.g., 'Code', 'Alacritty')"
    )

    # Process context
    window_pid: Optional[int] = Field(
        None,
        description="Process ID of window's owning process (may be None for some windows)"
    )

    # Location context
    workspace_number: int = Field(
        ...,
        ge=1,
        le=70,
        description="Workspace number where window appeared"
    )

    # Timing
    timestamp: float = Field(
        ...,
        description="Unix timestamp when window::new event received"
    )

    def __str__(self) -> str:
        return (
            f"WindowInfo(id={self.window_id}, class={self.window_class}, "
            f"workspace={self.workspace_number}, pid={self.window_pid})"
        )
```

**Validation Rules**:
- `window_id` must be unique i3 container ID
- `workspace_number` must be 1-70
- `window_class` is required for correlation (cannot be empty)

**Notes**:
- `window_pid` may be None for windows that don't report PID via `_NET_WM_PID`
- PID is NOT used for correlation (defeats purpose of IPC launch context)

---

### 3. CorrelationResult

Represents the outcome of correlating a window to a pending launch.

**Lifecycle**: Created by correlation algorithm → Returned to window event handler → Used for project assignment decision

```python
from pydantic import BaseModel, Field
from typing import Optional
from enum import Enum

class ConfidenceLevel(str, Enum):
    """Correlation confidence levels (from FR-015)."""
    EXACT = "EXACT"      # 1.0
    HIGH = "HIGH"        # 0.8+
    MEDIUM = "MEDIUM"    # 0.6+
    LOW = "LOW"          # 0.3+
    NONE = "NONE"        # 0.0

class CorrelationResult(BaseModel):
    """
    Result of correlating a window to a pending launch.

    Indicates whether a match was found and the confidence level. Used
    to decide if the window should be assigned to the launch's project.
    """

    # Match outcome
    matched: bool = Field(
        ...,
        description="True if a pending launch was matched to the window"
    )

    # Matched launch details (if matched=True)
    project_name: Optional[str] = Field(
        None,
        description="Project name from matched launch (None if no match)"
    )
    app_name: Optional[str] = Field(
        None,
        description="Application name from matched launch (None if no match)"
    )

    # Correlation quality
    confidence: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Correlation confidence score (0.0 to 1.0)"
    )
    confidence_level: ConfidenceLevel = Field(
        ...,
        description="Categorical confidence level"
    )

    # Correlation signals used
    signals_used: dict = Field(
        default_factory=dict,
        description="Signals that contributed to correlation (for debugging)"
    )

    @classmethod
    def no_match(cls, window_class: str, reason: str) -> "CorrelationResult":
        """Factory method for failed correlation."""
        return cls(
            matched=False,
            project_name=None,
            app_name=None,
            confidence=0.0,
            confidence_level=ConfidenceLevel.NONE,
            signals_used={
                "window_class": window_class,
                "failure_reason": reason
            }
        )

    @classmethod
    def from_launch(
        cls,
        launch: PendingLaunch,
        confidence: float,
        signals: dict
    ) -> "CorrelationResult":
        """Factory method for successful correlation."""
        # Determine confidence level
        if confidence >= 1.0:
            level = ConfidenceLevel.EXACT
        elif confidence >= 0.8:
            level = ConfidenceLevel.HIGH
        elif confidence >= 0.6:
            level = ConfidenceLevel.MEDIUM
        elif confidence >= 0.3:
            level = ConfidenceLevel.LOW
        else:
            level = ConfidenceLevel.NONE

        return cls(
            matched=True,
            project_name=launch.project_name,
            app_name=launch.app_name,
            confidence=confidence,
            confidence_level=level,
            signals_used=signals
        )

    def should_assign_project(self) -> bool:
        """
        Determine if confidence is sufficient for project assignment.

        Threshold: MEDIUM (0.6) or higher (from FR-016).
        """
        return self.confidence >= 0.6

    def __str__(self) -> str:
        if self.matched:
            return (
                f"CorrelationResult(matched={self.matched}, "
                f"project={self.project_name}, confidence={self.confidence:.2f} [{self.confidence_level}])"
            )
        else:
            reason = self.signals_used.get("failure_reason", "unknown")
            return f"CorrelationResult(matched=False, reason={reason})"
```

**Validation Rules**:
- `confidence` must be 0.0 to 1.0
- If `matched=True`, `project_name` and `app_name` must not be None
- `confidence_level` must match confidence value ranges

**Decision Threshold**:
- `confidence >= 0.6` (MEDIUM) required for project assignment (FR-016)
- Below threshold: window receives no project assignment

---

### 4. LaunchRegistryStats

Statistics about launch registry state for diagnostics and monitoring.

```python
from pydantic import BaseModel, Field

class LaunchRegistryStats(BaseModel):
    """
    Statistics about the launch registry for diagnostics.

    Provides insight into pending launches, match rates, and expiration
    for debugging and system monitoring.
    """

    # Current state
    total_pending: int = Field(
        ...,
        ge=0,
        description="Number of pending launches awaiting correlation"
    )
    unmatched_pending: int = Field(
        ...,
        ge=0,
        description="Number of pending launches not yet matched"
    )

    # Historical counters (since daemon start)
    total_notifications: int = Field(
        default=0,
        ge=0,
        description="Total launch notifications received"
    )
    total_matched: int = Field(
        default=0,
        ge=0,
        description="Total successful correlations"
    )
    total_expired: int = Field(
        default=0,
        ge=0,
        description="Total launches that expired without matching"
    )
    total_failed_correlation: int = Field(
        default=0,
        ge=0,
        description="Total windows that appeared without matching launch"
    )

    # Computed metrics
    @property
    def match_rate(self) -> float:
        """Percentage of notifications that resulted in successful matches."""
        if self.total_notifications == 0:
            return 0.0
        return (self.total_matched / self.total_notifications) * 100

    @property
    def expiration_rate(self) -> float:
        """Percentage of notifications that expired without matching."""
        if self.total_notifications == 0:
            return 0.0
        return (self.total_expired / self.total_notifications) * 100

    def __str__(self) -> str:
        return (
            f"LaunchRegistryStats(pending={self.total_pending}, "
            f"matched={self.total_matched}, expired={self.total_expired}, "
            f"match_rate={self.match_rate:.1f}%)"
        )
```

**Usage**:
- Exposed via daemon IPC query endpoint: `get_launch_stats`
- Used by monitoring tools and diagnostic commands
- Provides visibility into correlation success rates

---

## Entity Relationships

```
┌─────────────────────────┐
│   Launch Notification   │  (IPC from launcher wrapper)
│   (JSON-RPC method)     │
└───────────┬─────────────┘
            │
            ↓ Creates
┌─────────────────────────┐
│    PendingLaunch        │
│  - app_name             │
│  - project_name         │
│  - timestamp            │  ──┐
│  - expected_class       │    │ Stored in
│  - matched: false       │    │
└─────────────────────────┘    │
                               │
                         ┌─────▼──────────────┐
                         │  LaunchRegistry    │
                         │  (in-memory dict)  │
                         └─────┬──────────────┘
                               │
            ┌──────────────────┘
            │ Queries for match
┌───────────▼─────────────┐
│   window::new event     │  (i3 IPC subscription)
│   (from i3 WM)          │
└───────────┬─────────────┘
            │
            ↓ Extracts
┌─────────────────────────┐
│      WindowInfo         │
│  - window_class         │
│  - workspace_number     │
│  - timestamp            │
└───────────┬─────────────┘
            │
            ↓ Input to correlation
┌─────────────────────────┐
│  Correlation Algorithm  │
│  - find_match()         │
│  - calculate_confidence │
└───────────┬─────────────┘
            │
            ↓ Returns
┌─────────────────────────┐
│   CorrelationResult     │
│  - matched: bool        │
│  - project_name         │
│  - confidence           │
└───────────┬─────────────┘
            │
            ↓ if confidence >= 0.6
┌─────────────────────────┐
│  Window → Project       │
│  Assignment             │
│  (i3 mark command)      │
└─────────────────────────┘
```

**Key Flows**:

1. **Launch Notification Flow**:
   - Wrapper sends `notify_launch` IPC → daemon creates `PendingLaunch` → stores in registry

2. **Window Correlation Flow**:
   - i3 sends `window::new` event → daemon extracts `WindowInfo` → queries registry → returns `CorrelationResult` → assigns project if confidence ≥ 0.6

3. **Expiration Flow**:
   - Every new notification triggers cleanup → old launches (age > 5s) removed → logged as expired

---

## State Transitions

### PendingLaunch State Machine

```
    ┌──────────────┐
    │   Created    │  matched = false, age = 0s
    └──────┬───────┘
           │
           ├─────────────────────────────┐
           │                             │
           ↓ window appears              ↓ age > 5s
    ┌──────────────┐              ┌──────────────┐
    │   Matched    │              │   Expired    │
    │ matched=true │              │  (removed)   │
    └──────────────┘              └──────────────┘
```

**Invariant**: A `PendingLaunch` can only transition to **Matched** OR **Expired**, never both.

---

## Validation & Error Handling

### Field Validation Errors

All models use Pydantic validators to enforce constraints. Invalid data raises `ValidationError` with detailed field-level errors.

**Example**:
```python
# Invalid workspace number
try:
    launch = PendingLaunch(
        app_name="vscode",
        project_name="nixos",
        workspace_number=100,  # Invalid: must be 1-70
        # ... other fields ...
    )
except ValidationError as e:
    # e.errors() returns:
    # [{'loc': ('workspace_number',), 'msg': 'ensure this value is less than or equal to 70', 'type': 'value_error.number.not_le'}]
```

### Correlation Failure Cases

The `CorrelationResult.no_match()` factory captures failure reasons for debugging:

```python
# No pending launches
CorrelationResult.no_match(
    window_class="Code",
    reason="no_pending_launches"
)

# Class mismatch (all launches are different apps)
CorrelationResult.no_match(
    window_class="Code",
    reason="no_class_match"
)

# All matches below confidence threshold
CorrelationResult.no_match(
    window_class="Code",
    reason="confidence_below_threshold (best=0.4)"
)
```

---

## JSON Serialization

All models serialize to JSON via Pydantic's `.dict()` and `.json()` methods.

**Example**:
```python
launch = PendingLaunch(
    app_name="vscode",
    project_name="nixos",
    project_directory=Path("/etc/nixos"),
    launcher_pid=12345,
    workspace_number=2,
    timestamp=1698765432.123,
    expected_class="Code"
)

# Serialize to dict
launch_dict = launch.dict()
# {
#   "app_name": "vscode",
#   "project_name": "nixos",
#   "project_directory": "/etc/nixos",  # Path → str
#   "launcher_pid": 12345,
#   "workspace_number": 2,
#   "timestamp": 1698765432.123,
#   "expected_class": "Code",
#   "matched": false
# }

# Serialize to JSON string
launch_json = launch.json()
```

**Path Handling**: `Path` objects automatically converted to strings via `json_encoders` configuration.

---

## Testing Considerations

### Mock Data Factories

```python
# test fixtures
def create_pending_launch(
    app_name: str = "vscode",
    project_name: str = "nixos",
    timestamp: float = None,
    **kwargs
) -> PendingLaunch:
    """Factory for creating test PendingLaunch instances."""
    if timestamp is None:
        timestamp = time.time()

    return PendingLaunch(
        app_name=app_name,
        project_name=project_name,
        project_directory=Path("/tmp/test-project"),
        launcher_pid=99999,
        workspace_number=2,
        timestamp=timestamp,
        expected_class="Code",
        **kwargs
    )

def create_window_info(
    window_class: str = "Code",
    timestamp: float = None,
    **kwargs
) -> WindowInfo:
    """Factory for creating test WindowInfo instances."""
    if timestamp is None:
        timestamp = time.time()

    return WindowInfo(
        window_id=123456,
        window_class=window_class,
        window_pid=10000,
        workspace_number=2,
        timestamp=timestamp,
        **kwargs
    )
```

### Validation Test Cases

```python
def test_pending_launch_future_timestamp():
    """Test that future timestamps are rejected."""
    future_time = time.time() + 10.0
    with pytest.raises(ValidationError) as exc:
        PendingLaunch(
            app_name="vscode",
            timestamp=future_time,
            # ... other fields ...
        )
    assert "future" in str(exc.value).lower()

def test_correlation_result_confidence_threshold():
    """Test that confidence threshold correctly determines assignment."""
    # Below threshold
    result_low = CorrelationResult(
        matched=True,
        project_name="nixos",
        confidence=0.5,
        confidence_level=ConfidenceLevel.LOW
    )
    assert not result_low.should_assign_project()

    # At threshold
    result_medium = CorrelationResult(
        matched=True,
        project_name="nixos",
        confidence=0.6,
        confidence_level=ConfidenceLevel.MEDIUM
    )
    assert result_medium.should_assign_project()
```

---

## Performance Characteristics

| Model | Size (bytes) | Validation Cost | Notes |
|-------|--------------|-----------------|-------|
| PendingLaunch | ~150 | <0.1ms | Path resolution is main cost |
| WindowInfo | ~80 | <0.05ms | Simple field validation |
| CorrelationResult | ~120 | <0.05ms | Enum validation negligible |
| LaunchRegistryStats | ~60 | <0.01ms | Integer fields only |

**Memory overhead for 1000 pending launches**: ~150KB (well under 5MB constraint)

---

## Next Steps

See `contracts/` directory for:
- JSON-RPC IPC endpoint specifications (`notify_launch`, `get_launch_stats`)
- Daemon state query extensions
- Event payloads for testing framework
