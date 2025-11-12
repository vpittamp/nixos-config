# Data Model: Environment Variable-Based Window Matching

**Feature**: 057-env-window-matching
**Date**: 2025-11-03
**Status**: Phase 1

## Overview

This document defines the data models for environment variable-based window matching. The core abstraction is `WindowEnvironment`, which represents parsed I3PM_* environment variables from a window's process.

---

## Core Entities

### WindowEnvironment

Parsed I3PM_* environment variables from a window's process (/proc/<pid>/environ).

**Purpose**: Provides deterministic window identification and project association without relying on window class, title, or app_id properties.

**Fields**:

| Field | Type | Required | Description | Example |
|-------|------|----------|-------------|---------|
| `app_id` | `str` | Yes | Unique window instance identifier | `"claude-pwa-nixos-833032-1762201416"` |
| `app_name` | `str` | Yes | Application type identifier | `"claude-pwa"`, `"vscode"`, `"terminal"` |
| `project_name` | `str` | No | Project identifier (empty if no active project) | `"nixos"`, `"stacks"`, `""` |
| `project_dir` | `str` | No | Project working directory | `"/etc/nixos"`, `""` |
| `project_display_name` | `str` | No | Human-readable project name | `"NixOS"`, `""` |
| `project_icon` | `str` | No | Project icon emoji | `"❄️"`, `""` |
| `scope` | `Literal["global", "scoped"]` | Yes | Window visibility scope | `"global"`, `"scoped"` |
| `active` | `bool` | No | Is this application actively used? | `True`, `False` |
| `target_workspace` | `int \| None` | No | Preferred workspace assignment | `52`, `None` |
| `expected_class` | `str` | No | Expected window class (for validation) | `"FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5"` |
| `launcher_pid` | `int \| None` | No | PID of launcher process | `833032` |
| `launch_time` | `int \| None` | No | Unix timestamp of application launch | `1762201416` |
| `i3_socket` | `str` | No | Sway/i3 IPC socket path | `"/run/user/1000/sway-ipc.1000.3281.sock"` |

**Validation Rules**:
- `app_id` MUST NOT be empty
- `app_name` MUST NOT be empty
- `scope` MUST be either `"global"` or `"scoped"`
- `target_workspace` MUST be >= 1 and <= 70 if present
- `project_name` MAY be empty (indicates no active project)
- `project_dir`, `project_display_name`, `project_icon` SHOULD be empty if `project_name` is empty

**Python Implementation**:
```python
from dataclasses import dataclass
from typing import Optional, Literal

@dataclass
class WindowEnvironment:
    """Parsed I3PM_* environment variables from window process."""

    # Required identifiers
    app_id: str                                  # I3PM_APP_ID
    app_name: str                                # I3PM_APP_NAME
    scope: Literal["global", "scoped"]           # I3PM_SCOPE

    # Optional project association
    project_name: str = ""                       # I3PM_PROJECT_NAME
    project_dir: str = ""                        # I3PM_PROJECT_DIR
    project_display_name: str = ""               # I3PM_PROJECT_DISPLAY_NAME
    project_icon: str = ""                       # I3PM_PROJECT_ICON

    # Optional metadata
    active: bool = True                          # I3PM_ACTIVE (default: true)
    target_workspace: Optional[int] = None       # I3PM_TARGET_WORKSPACE
    expected_class: str = ""                     # I3PM_EXPECTED_CLASS
    launcher_pid: Optional[int] = None           # I3PM_LAUNCHER_PID
    launch_time: Optional[int] = None            # I3PM_LAUNCH_TIME
    i3_socket: str = ""                          # I3SOCK

    def __post_init__(self):
        """Validate environment variables after initialization."""
        if not self.app_id:
            raise ValueError("app_id cannot be empty")
        if not self.app_name:
            raise ValueError("app_name cannot be empty")
        if self.scope not in ("global", "scoped"):
            raise ValueError(f"Invalid scope: {self.scope}")
        if self.target_workspace is not None:
            if not (1 <= self.target_workspace <= 70):
                raise ValueError(f"target_workspace must be 1-70, got {self.target_workspace}")

    @property
    def has_project(self) -> bool:
        """Check if window is associated with a project."""
        return bool(self.project_name)

    @property
    def is_global(self) -> bool:
        """Check if window has global scope (visible across all projects)."""
        return self.scope == "global"

    @property
    def is_scoped(self) -> bool:
        """Check if window has scoped visibility (project-specific)."""
        return self.scope == "scoped"

    def matches_project(self, project_name: str) -> bool:
        """Check if window belongs to specified project."""
        return self.project_name == project_name

    def should_be_visible(self, active_project: Optional[str]) -> bool:
        """
        Determine if window should be visible given active project context.

        Args:
            active_project: Currently active project name (None if no project active)

        Returns:
            True if window should be visible, False if should be hidden
        """
        # Global windows are always visible
        if self.is_global:
            return True

        # Scoped windows visible only in matching project
        if self.is_scoped:
            # No project active - hide scoped windows
            if active_project is None:
                return False
            # Window belongs to active project - show it
            return self.matches_project(active_project)

        # Fallback: show window (defensive default)
        return True
```

**Usage Examples**:
```python
# Parse from environment dict
env_vars = read_process_environ(window.pid)
window_env = WindowEnvironment.from_env_dict(env_vars)

# Check project association
if window_env.has_project:
    print(f"Window belongs to project: {window_env.project_name}")

# Determine visibility
if window_env.should_be_visible(active_project="nixos"):
    # Show window
else:
    # Hide window to scratchpad
```

---

### EnvironmentQueryResult

Result of querying environment variables for a window, including traversal metadata.

**Purpose**: Tracks where environment variables were found (direct PID vs parent PID) for debugging and validation.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `window_id` | `int` | Sway/i3 window ID |
| `requested_pid` | `int` | Original PID from window properties |
| `actual_pid` | `int` | PID where environment variables were found |
| `traversal_depth` | `int` | How many parent levels traversed (0 = direct PID) |
| `environment` | `WindowEnvironment \| None` | Parsed environment variables (None if not found) |
| `error` | `str \| None` | Error message if query failed |
| `query_time_ms` | `float` | Time taken to query environment (milliseconds) |

**Python Implementation**:
```python
from dataclasses import dataclass
from typing import Optional

@dataclass
class EnvironmentQueryResult:
    """Result of querying environment variables for a window."""

    window_id: int
    requested_pid: int
    actual_pid: int
    traversal_depth: int
    environment: Optional[WindowEnvironment]
    error: Optional[str] = None
    query_time_ms: float = 0.0

    @property
    def success(self) -> bool:
        """Check if environment variables were found."""
        return self.environment is not None

    @property
    def required_traversal(self) -> bool:
        """Check if parent PID traversal was needed."""
        return self.traversal_depth > 0

    @property
    def is_unmanaged(self) -> bool:
        """Check if window is unmanaged (no I3PM_* variables)."""
        return self.environment is None and self.error is None
```

**Usage**:
```python
result = await query_window_environment(window)

if result.success:
    print(f"Found environment at depth {result.traversal_depth}")
    print(f"App: {result.environment.app_name}")
elif result.error:
    print(f"Error: {result.error}")
else:
    print("Unmanaged window (no I3PM_* variables)")
```

---

### CoverageReport

Validation report showing percentage of windows with I3PM_* environment variables.

**Purpose**: Quantifies environment variable coverage to ensure 100% reliability before removing legacy matching code.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `total_windows` | `int` | Total number of windows checked |
| `windows_with_env` | `int` | Windows with I3PM_APP_ID present |
| `windows_without_env` | `int` | Windows missing I3PM_APP_ID |
| `coverage_percentage` | `float` | (windows_with_env / total_windows) * 100 |
| `missing_windows` | `list[MissingWindowInfo]` | Details of windows without environment |
| `status` | `Literal["PASS", "FAIL"]` | PASS if coverage == 100%, else FAIL |
| `timestamp` | `datetime` | When report was generated |

**Python Implementation**:
```python
from dataclasses import dataclass, field
from datetime import datetime
from typing import Literal

@dataclass
class MissingWindowInfo:
    """Details of a window missing I3PM_* environment variables."""
    window_id: int
    window_class: str
    window_title: str
    pid: int
    reason: str  # "no_pid", "permission_denied", "process_exited", "no_variables"

@dataclass
class CoverageReport:
    """Validation report for environment variable coverage."""

    total_windows: int
    windows_with_env: int
    windows_without_env: int
    coverage_percentage: float
    missing_windows: list[MissingWindowInfo] = field(default_factory=list)
    status: Literal["PASS", "FAIL"] = "FAIL"
    timestamp: datetime = field(default_factory=datetime.now)

    @property
    def is_complete(self) -> bool:
        """Check if 100% coverage achieved."""
        return self.coverage_percentage == 100.0

    def summary(self) -> str:
        """Generate human-readable summary."""
        return (
            f"Coverage: {self.coverage_percentage:.1f}% "
            f"({self.windows_with_env}/{self.total_windows} windows) - "
            f"Status: {self.status}"
        )
```

---

### PerformanceBenchmark

Performance metrics for environment variable query operations.

**Purpose**: Validates that /proc filesystem reads meet <10ms latency target.

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `operation` | `str` | Operation being benchmarked |
| `sample_size` | `int` | Number of samples measured |
| `average_ms` | `float` | Average latency (milliseconds) |
| `p50_ms` | `float` | 50th percentile latency |
| `p95_ms` | `float` | 95th percentile latency |
| `p99_ms` | `float` | 99th percentile latency |
| `max_ms` | `float` | Maximum latency observed |
| `min_ms` | `float` | Minimum latency observed |
| `status` | `Literal["PASS", "FAIL"]` | PASS if p95 < 10ms, else FAIL |

**Python Implementation**:
```python
from dataclasses import dataclass
from typing import Literal
import statistics

@dataclass
class PerformanceBenchmark:
    """Performance metrics for environment variable operations."""

    operation: str
    sample_size: int
    average_ms: float
    p50_ms: float
    p95_ms: float
    p99_ms: float
    max_ms: float
    min_ms: float
    status: Literal["PASS", "FAIL"]

    @classmethod
    def from_samples(cls, operation: str, samples_ms: list[float]) -> "PerformanceBenchmark":
        """Create benchmark from latency samples."""
        sorted_samples = sorted(samples_ms)
        n = len(sorted_samples)

        return cls(
            operation=operation,
            sample_size=n,
            average_ms=statistics.mean(samples_ms),
            p50_ms=sorted_samples[int(n * 0.50)],
            p95_ms=sorted_samples[int(n * 0.95)],
            p99_ms=sorted_samples[int(n * 0.99)],
            max_ms=max(samples_ms),
            min_ms=min(samples_ms),
            status="PASS" if sorted_samples[int(n * 0.95)] < 10.0 else "FAIL",
        )

    def summary(self) -> str:
        """Generate human-readable summary."""
        return (
            f"{self.operation}: "
            f"avg={self.average_ms:.2f}ms, "
            f"p95={self.p95_ms:.2f}ms, "
            f"max={self.max_ms:.2f}ms - "
            f"{self.status}"
        )
```

---

## Entity Relationships

```
WindowEnvironment
├── Used by: WindowMatcher (for identification)
├── Used by: WindowFilter (for project filtering)
├── Used by: WorkspaceAssigner (for workspace assignment)
└── Populated from: /proc/<pid>/environ via EnvironmentQueryResult

EnvironmentQueryResult
├── Contains: WindowEnvironment
├── Produced by: query_window_environment()
└── Consumed by: Event handlers (window::new)

CoverageReport
├── Contains: list[MissingWindowInfo]
├── Produced by: validate_environment_coverage()
└── Consumed by: Validation tools, CI/CD checks

PerformanceBenchmark
├── Produced by: benchmark_environment_queries()
└── Consumed by: Performance tests, optimization decisions
```

---

## Data Flow

```
1. Window Created (Sway IPC event)
   ↓
2. Extract PID from window properties
   ↓
3. query_window_environment(window)
   ↓
4. read_process_environ(pid) → Dict[str, str]
   ↓
5. WindowEnvironment.from_env_dict(env_vars) → WindowEnvironment
   ↓
6. EnvironmentQueryResult(environment=window_env)
   ↓
7. Use WindowEnvironment for:
   - Window identification (app_name, app_id)
   - Project association (project_name, scope)
   - Workspace assignment (target_workspace)
   - Visibility control (should_be_visible())
```

---

## State Transitions

### Window Lifecycle

```
1. Application Launch
   State: No window exists
   Action: Launcher wrapper injects I3PM_* environment variables
   Result: Process created with environment

2. Window Creation
   State: Window appears in Sway
   Action: window::new event → query environment
   Result: EnvironmentQueryResult with WindowEnvironment

3. Window Identification
   State: WindowEnvironment populated
   Action: Read app_name, app_id, project_name from environment
   Result: Window marked with project association

4. Project Switch
   State: Active project changes
   Action: Check window_env.should_be_visible(new_project)
   Result: Window shown or hidden based on scope and project

5. Window Close
   State: Window destroyed
   Action: Process exits, /proc/<pid> removed
   Result: Environment no longer queryable (graceful handling)
```

---

## Validation & Constraints

### Environment Variable Validation

```python
def validate_window_environment(env_dict: Dict[str, str]) -> list[str]:
    """
    Validate I3PM_* environment variables are complete and valid.

    Returns:
        List of validation error messages (empty if valid)
    """
    errors = []

    # Required variables
    if 'I3PM_APP_ID' not in env_dict or not env_dict['I3PM_APP_ID']:
        errors.append("Missing or empty I3PM_APP_ID")

    if 'I3PM_APP_NAME' not in env_dict or not env_dict['I3PM_APP_NAME']:
        errors.append("Missing or empty I3PM_APP_NAME")

    if 'I3PM_SCOPE' not in env_dict:
        errors.append("Missing I3PM_SCOPE")
    elif env_dict['I3PM_SCOPE'] not in ('global', 'scoped'):
        errors.append(f"Invalid I3PM_SCOPE: {env_dict['I3PM_SCOPE']}")

    # Workspace validation
    if 'I3PM_TARGET_WORKSPACE' in env_dict:
        try:
            ws = int(env_dict['I3PM_TARGET_WORKSPACE'])
            if not (1 <= ws <= 70):
                errors.append(f"I3PM_TARGET_WORKSPACE out of range: {ws}")
        except ValueError:
            errors.append(f"Invalid I3PM_TARGET_WORKSPACE (not an integer)")

    # Project consistency
    has_project_name = bool(env_dict.get('I3PM_PROJECT_NAME'))
    has_project_dir = bool(env_dict.get('I3PM_PROJECT_DIR'))

    if has_project_name != has_project_dir:
        errors.append(
            "Inconsistent project variables: "
            "I3PM_PROJECT_NAME and I3PM_PROJECT_DIR must both be set or both empty"
        )

    return errors
```

---

## Migration from Legacy Models

### Before (Legacy Window Identifier):

```python
# From window_identifier.py (DEPRECATED)
{
    "original_class": "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",
    "original_instance": "claude",
    "normalized_class": "ffpwa-01jcyf8z2m7r4n6qw9xkphvtb5",
    "normalized_instance": "claude",
    "title": "Claude — Mozilla Firefox",
    "is_pwa": True,
    "pwa_id": "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",
    "pwa_type": "firefox",
}
```

### After (Environment-Based):

```python
# WindowEnvironment (NEW)
WindowEnvironment(
    app_id="claude-pwa-nixos-833032-1762201416",
    app_name="claude-pwa",
    scope="scoped",
    project_name="nixos",
    project_dir="/etc/nixos",
    project_display_name="NixOS",
    project_icon="❄️",
    target_workspace=52,
    expected_class="FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",  # For validation only
)
```

**Key Differences**:
- No more class normalization (app_name is deterministic)
- No more PWA detection heuristics (app_name explicitly identifies PWAs)
- No more registry matching (app_name is the registry key)
- Direct project association (no mark-based inference)
- Unique instance ID (app_id replaces window ID for multi-instance tracking)

---

## Next Steps

**Phase 1 Data Model Complete** ✅

Proceed with:
1. API contracts for window environment services
2. Quickstart guide with usage examples
3. Agent context update
