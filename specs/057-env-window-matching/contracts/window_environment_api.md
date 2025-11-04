# API Contract: Window Environment Service

**Feature**: 057-env-window-matching
**Version**: 1.0.0
**Status**: Draft

## Overview

This document defines the API contract for the Window Environment Service, which provides environment variable-based window identification and project association.

---

## Core Functions

### `read_process_environ(pid: int) -> Dict[str, str]`

Read environment variables from /proc/<pid>/environ.

**Signature**:
```python
def read_process_environ(pid: int) -> Dict[str, str]:
    """
    Read environment variables from /proc/<pid>/environ.

    Args:
        pid: Process ID

    Returns:
        Dictionary of environment variable name → value
        Empty dict if process doesn't exist or permission denied

    Raises:
        No exceptions raised - errors handled internally with empty dict return
    """
```

**Input**:
- `pid` (int): Process ID from window properties (>= 1)

**Output**:
- `Dict[str, str]`: Environment variable mapping
  - Keys: Variable names (e.g., "I3PM_APP_ID", "I3PM_PROJECT_NAME")
  - Values: Variable values (strings)
  - Empty dict if process exited, permission denied, or parse error

**Performance**:
- Average latency: <0.5ms
- p95 latency: <1.5ms
- p99 latency: <3ms

**Error Handling**:
- `FileNotFoundError`: Process exited → return {}
- `PermissionError`: Access denied → return {}
- `UnicodeDecodeError`: Invalid UTF-8 → skip invalid variables with `errors='ignore'`
- Other exceptions → log warning, return {}

**Example**:
```python
env_vars = read_process_environ(833032)
# Returns:
{
    "I3PM_APP_ID": "claude-pwa-nixos-833032-1762201416",
    "I3PM_APP_NAME": "claude-pwa",
    "I3PM_PROJECT_NAME": "nixos",
    "I3PM_SCOPE": "scoped",
    # ... additional variables
}
```

---

### `get_window_environment(window_id: int, pid: int) -> EnvironmentQueryResult`

Get environment variables for a window with parent PID traversal fallback.

**Signature**:
```python
async def get_window_environment(
    window_id: int,
    pid: int,
    max_depth: int = 3
) -> EnvironmentQueryResult:
    """
    Get environment variables for window with parent traversal fallback.

    Args:
        window_id: Sway/i3 window ID
        pid: Process ID from window properties
        max_depth: Maximum parent traversal depth (default: 3)

    Returns:
        EnvironmentQueryResult with WindowEnvironment or error details
    """
```

**Input**:
- `window_id` (int): Sway/i3 window ID (from window::new event)
- `pid` (int): Process ID from window properties
- `max_depth` (int, optional): Maximum parent levels to traverse (default: 3)

**Output**:
- `EnvironmentQueryResult`:
  - `window_id`: Same as input
  - `requested_pid`: Original PID
  - `actual_pid`: PID where variables found (may differ if traversal occurred)
  - `traversal_depth`: Number of parent levels traversed (0 = direct PID)
  - `environment`: WindowEnvironment object or None
  - `error`: Error message if query failed
  - `query_time_ms`: Query latency in milliseconds

**Performance**:
- Average (no traversal): <0.5ms
- Average (with traversal): <2ms
- p95 (with traversal): <5ms
- p99 (with traversal): <10ms

**Traversal Logic**:
1. Try direct PID → if I3PM_APP_ID found, return immediately
2. Get parent PID from /proc/<pid>/stat → try parent
3. Repeat up to `max_depth` levels
4. If no variables found after traversal, return None

**Example**:
```python
result = await get_window_environment(
    window_id=94532735639728,
    pid=833032
)

if result.success:
    print(f"App: {result.environment.app_name}")  # "claude-pwa"
    print(f"Depth: {result.traversal_depth}")     # 0 (direct PID)
```

---

### `WindowEnvironment.from_env_dict(env_dict: Dict[str, str]) -> WindowEnvironment | None`

Parse environment variable dictionary into WindowEnvironment object.

**Signature**:
```python
@classmethod
def from_env_dict(cls, env_dict: Dict[str, str]) -> Optional["WindowEnvironment"]:
    """
    Create WindowEnvironment from environment variable dictionary.

    Args:
        env_dict: Dictionary from read_process_environ()

    Returns:
        WindowEnvironment object if I3PM_APP_ID and I3PM_APP_NAME present
        None if required variables missing

    Raises:
        ValueError: If variables present but invalid (e.g., scope not global/scoped)
    """
```

**Input**:
- `env_dict` (Dict[str, str]): Environment variables from read_process_environ()

**Output**:
- `WindowEnvironment | None`:
  - Returns WindowEnvironment if required variables present
  - Returns None if I3PM_APP_ID or I3PM_APP_NAME missing

**Required Variables**:
- `I3PM_APP_ID`: Must be non-empty string
- `I3PM_APP_NAME`: Must be non-empty string
- `I3PM_SCOPE`: Must be "global" or "scoped"

**Optional Variables** (defaults if missing):
- `I3PM_PROJECT_NAME`: Defaults to ""
- `I3PM_PROJECT_DIR`: Defaults to ""
- `I3PM_PROJECT_DISPLAY_NAME`: Defaults to ""
- `I3PM_PROJECT_ICON`: Defaults to ""
- `I3PM_ACTIVE`: Defaults to "true" → bool(True)
- `I3PM_TARGET_WORKSPACE`: Defaults to None
- `I3PM_EXPECTED_CLASS`: Defaults to ""
- `I3PM_LAUNCHER_PID`: Defaults to None
- `I3PM_LAUNCH_TIME`: Defaults to None
- `I3SOCK`: Defaults to ""

**Validation**:
- Raises ValueError if `scope` not in ("global", "scoped")
- Raises ValueError if `target_workspace` not in range 1-70
- Raises ValueError if `app_id` or `app_name` empty

**Example**:
```python
env_vars = read_process_environ(833032)
window_env = WindowEnvironment.from_env_dict(env_vars)

if window_env:
    print(f"App: {window_env.app_name}")           # "claude-pwa"
    print(f"Project: {window_env.project_name}")   # "nixos"
    print(f"Scope: {window_env.scope}")            # "scoped"
else:
    print("No I3PM_* variables found")
```

---

## Validation Functions

### `validate_environment_coverage() -> CoverageReport`

Validate that all windows have I3PM_* environment variables.

**Signature**:
```python
async def validate_environment_coverage() -> CoverageReport:
    """
    Validate environment variable coverage across all windows.

    Returns:
        CoverageReport with coverage percentage and missing window details
    """
```

**Output**:
- `CoverageReport`:
  - `total_windows`: Total windows checked
  - `windows_with_env`: Windows with I3PM_APP_ID
  - `windows_without_env`: Windows missing I3PM_APP_ID
  - `coverage_percentage`: (windows_with_env / total_windows) * 100
  - `missing_windows`: List of MissingWindowInfo
  - `status`: "PASS" if coverage == 100%, else "FAIL"
  - `timestamp`: Report generation time

**Performance**:
- Expected latency: <100ms for 50 windows
- Expected latency: <500ms for 100 windows

**Usage**:
```python
report = await validate_environment_coverage()

print(f"Coverage: {report.coverage_percentage:.1f}%")
# Coverage: 100.0%

if report.status == "FAIL":
    for missing in report.missing_windows:
        print(f"Missing: {missing.window_class} - {missing.reason}")
```

---

### `validate_window_environment(env_dict: Dict[str, str]) -> list[str]`

Validate individual window environment for completeness.

**Signature**:
```python
def validate_window_environment(env_dict: Dict[str, str]) -> list[str]:
    """
    Validate I3PM_* environment variables are complete and valid.

    Args:
        env_dict: Environment variables from read_process_environ()

    Returns:
        List of validation error messages (empty if valid)
    """
```

**Input**:
- `env_dict` (Dict[str, str]): Environment variables

**Output**:
- `list[str]`: Validation errors (empty list if valid)

**Validation Rules**:
- I3PM_APP_ID must exist and be non-empty
- I3PM_APP_NAME must exist and be non-empty
- I3PM_SCOPE must exist and be "global" or "scoped"
- I3PM_TARGET_WORKSPACE must be 1-70 if present
- I3PM_PROJECT_NAME and I3PM_PROJECT_DIR must both be set or both empty

**Example**:
```python
env_vars = read_process_environ(pid)
errors = validate_window_environment(env_vars)

if errors:
    for error in errors:
        print(f"Validation error: {error}")
else:
    print("Environment valid")
```

---

## Performance Benchmarking

### `benchmark_environment_queries(sample_size: int = 1000) -> PerformanceBenchmark`

Benchmark /proc filesystem read performance.

**Signature**:
```python
async def benchmark_environment_queries(
    sample_size: int = 1000
) -> PerformanceBenchmark:
    """
    Benchmark environment variable query performance.

    Args:
        sample_size: Number of samples to measure (default: 1000)

    Returns:
        PerformanceBenchmark with latency percentiles
    """
```

**Input**:
- `sample_size` (int): Number of query iterations (default: 1000)

**Output**:
- `PerformanceBenchmark`:
  - `operation`: "read_process_environ"
  - `sample_size`: Number of samples
  - `average_ms`: Average latency
  - `p50_ms`, `p95_ms`, `p99_ms`: Percentile latencies
  - `max_ms`, `min_ms`: Extremes
  - `status`: "PASS" if p95 < 10ms, else "FAIL"

**Performance Target**:
- p95 latency < 10ms → PASS
- p95 latency >= 10ms → FAIL

**Example**:
```python
benchmark = await benchmark_environment_queries(sample_size=1000)

print(benchmark.summary())
# read_process_environ: avg=0.42ms, p95=1.23ms, max=3.45ms - PASS
```

---

## CLI Commands

### `i3pm diagnose coverage`

Validate environment variable coverage for all windows.

**Command**:
```bash
i3pm diagnose coverage [--json]
```

**Arguments**:
- `--json`: Output as JSON instead of human-readable table

**Output** (human-readable):
```
Environment Variable Coverage Report
=====================================
Total Windows:        42
With I3PM_* Variables: 42
Coverage:             100.0%
Status:               PASS

No missing windows.
```

**Output** (JSON):
```json
{
  "total_windows": 42,
  "windows_with_env": 42,
  "windows_without_env": 0,
  "coverage_percentage": 100.0,
  "missing_windows": [],
  "status": "PASS",
  "timestamp": "2025-11-03T14:23:45.123456"
}
```

---

### `i3pm benchmark environ`

Benchmark environment variable query performance.

**Command**:
```bash
i3pm benchmark environ [--samples N] [--json]
```

**Arguments**:
- `--samples N`: Number of samples to measure (default: 1000)
- `--json`: Output as JSON instead of human-readable table

**Output** (human-readable):
```
Environment Query Performance Benchmark
========================================
Operation:     read_process_environ
Sample Size:   1000
Average:       0.42ms
p50 (Median):  0.35ms
p95:           1.23ms
p99:           2.87ms
Max:           4.56ms
Status:        PASS (p95 < 10ms)
```

**Output** (JSON):
```json
{
  "operation": "read_process_environ",
  "sample_size": 1000,
  "average_ms": 0.42,
  "p50_ms": 0.35,
  "p95_ms": 1.23,
  "p99_ms": 2.87,
  "max_ms": 4.56,
  "min_ms": 0.18,
  "status": "PASS"
}
```

---

### `i3pm windows --table` (enhanced)

Display window information including I3PM_* environment variables.

**Enhancement**: Add APP_ID column showing I3PM_APP_ID from environment.

**Command**:
```bash
i3pm windows --table
```

**Output**:
```
              ID |      PID | APP_ID                    | Class              | Title                               | WS   | Output       | Project      | Status     | Change
-----------------+----------+---------------------------+--------------------+-------------------------------------+------+--------------+--------------+------------+--------
             152 |   716344 | terminal-nixos-716243-... | Alacritty          | Alacritty                           | 1    | HEADLESS-1   | nixos:152    | ●🔸        |
        20971524 |  1188968 | vscode-nixos-1187796-1... | Code               | app-registry-data.nix (03ea3a1) ... | 2    | HEADLESS-1   | nixos:11     | 🔸         |
```

**New Column**:
- `APP_ID`: Shortened I3PM_APP_ID (first 25 chars + "..." if longer)
  - Full value available in JSON output or `i3pm diagnose window <id>`

---

## Error Codes

| Code | Name | Description | Resolution |
|------|------|-------------|------------|
| E001 | NO_PID | Window has no PID property | Skip window (likely special window like scratchpad) |
| E002 | PROCESS_EXITED | /proc/<pid> not found | Graceful - return empty environment |
| E003 | PERMISSION_DENIED | Cannot read /proc/<pid>/environ | Treat as unmanaged window, log warning |
| E004 | INVALID_UTF8 | Environment contains invalid UTF-8 | Skip invalid variables with `errors='ignore'` |
| E005 | MISSING_REQUIRED_VAR | I3PM_APP_ID or I3PM_APP_NAME missing | Return None from from_env_dict() |
| E006 | INVALID_SCOPE | I3PM_SCOPE not "global" or "scoped" | Raise ValueError |
| E007 | INVALID_WORKSPACE | I3PM_TARGET_WORKSPACE not in 1-70 | Raise ValueError |
| E008 | PARENT_TRAVERSAL_FAILED | No I3PM_* variables in 3-level chain | Treat as unmanaged window |

---

## Backward Compatibility

**Breaking Changes** (acceptable per Constitution Principle XII):
- `window_identifier.py` functions REMOVED (no legacy support)
- `get_window_identity()` REMOVED
- `match_window_class()` REMOVED
- `match_with_registry()` REMOVED
- `normalize_class()` REMOVED
- `match_pwa_instance()` REMOVED

**Migration Path**:
- All window identification via WindowEnvironment
- All project association via I3PM_PROJECT_NAME
- All scope determination via I3PM_SCOPE
- All workspace assignment via I3PM_TARGET_WORKSPACE

**No Fallback**: If I3PM_* variables missing, window is unmanaged (not identified via class matching).

---

## Next Steps

**Contracts Complete** ✅

Proceed with:
1. Quickstart guide with usage examples
2. Agent context update
3. Post-design constitution re-evaluation
