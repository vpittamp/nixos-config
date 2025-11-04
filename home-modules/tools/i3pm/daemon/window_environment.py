"""
Environment variable-based window matching implementation.

This module provides functions for:
- Reading process environment variables from /proc
- Querying window environment with parent traversal
- Validating environment variable completeness
- Logging environment-based identification
- Coverage validation across all windows

Replaces legacy window class/title-based identification with deterministic
environment variable-based approach.
"""

import asyncio
import logging
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .models import WindowEnvironment, EnvironmentQueryResult, CoverageReport, MissingWindowInfo, PerformanceBenchmark

logger = logging.getLogger(__name__)

# Performance metrics tracking (T035)
_query_latencies = []  # Circular buffer for last 100 queries
_query_count = 0


def _track_query_latency(latency_ms: float):
    """
    Track query latency for periodic statistics logging.

    Maintains circular buffer of last 100 query latencies and logs
    statistics every 100 queries.

    Args:
        latency_ms: Query latency in milliseconds
    """
    global _query_latencies, _query_count

    # Add to circular buffer (max 100 samples)
    _query_latencies.append(latency_ms)
    if len(_query_latencies) > 100:
        _query_latencies.pop(0)

    _query_count += 1

    # Log statistics every 100 queries
    if _query_count % 100 == 0:
        sorted_latencies = sorted(_query_latencies)
        n = len(sorted_latencies)

        avg_ms = sum(_query_latencies) / n
        p95_ms = sorted_latencies[int(n * 0.95)]
        max_ms = max(_query_latencies)

        logger.info(
            f"Performance stats (last {n} queries): "
            f"avg={avg_ms:.2f}ms, p95={p95_ms:.2f}ms, max={max_ms:.2f}ms"
        )


def read_process_environ(pid: int) -> Dict[str, str]:
    """
    Read and parse environment variables from /proc/<pid>/environ.

    Args:
        pid: Process ID to read environment from

    Returns:
        Dictionary of environment variables (key=value pairs)
        Empty dict if process not found, permission denied, or other error

    Example:
        >>> env = read_process_environ(12345)
        >>> print(env.get("PATH"))
        /usr/bin:/bin
    """
    try:
        environ_path = Path(f"/proc/{pid}/environ")
        if not environ_path.exists():
            return {}

        # Read as binary to handle potential non-UTF8 bytes
        with open(environ_path, "rb") as f:
            data = f.read()

        # Decode with error handling (ignore invalid UTF-8 sequences)
        text = data.decode("utf-8", errors="ignore")

        # Parse null-separated key=value pairs
        env_dict = {}
        for line in text.split("\0"):
            if "=" in line:
                key, value = line.split("=", 1)
                env_dict[key] = value

        return env_dict

    except FileNotFoundError:
        # Process doesn't exist
        return {}
    except PermissionError:
        # No permission to read process environment
        logger.warning(f"Permission denied reading /proc/{pid}/environ")
        return {}
    except OSError as e:
        # Other OS errors
        logger.warning(f"OS error reading /proc/{pid}/environ: {e}")
        return {}


def get_parent_pid(pid: int) -> Optional[int]:
    """
    Get parent process ID from /proc/<pid>/stat.

    Args:
        pid: Process ID to get parent for

    Returns:
        Parent PID or None if error

    Example:
        >>> ppid = get_parent_pid(12345)
        >>> print(f"Parent PID: {ppid}")
    """
    try:
        stat_path = Path(f"/proc/{pid}/stat")
        if not stat_path.exists():
            return None

        with open(stat_path, "r") as f:
            stat = f.read()

        # Parse stat format: pid (comm) state ppid ...
        # Need to handle process name with spaces/parentheses
        # Strategy: find last ')' and split from there
        rparen_idx = stat.rfind(")")
        if rparen_idx == -1:
            return None

        # Fields after process name (comm)
        fields = stat[rparen_idx + 1:].strip().split()
        if len(fields) < 2:
            return None

        # PPID is the second field (index 1) after process name
        return int(fields[1])

    except (FileNotFoundError, ValueError, IndexError, OSError):
        return None


async def get_window_environment(
    window_id: int,
    pid: int,
    max_traversal_depth: int = 3
) -> EnvironmentQueryResult:
    """
    Query window environment with parent process traversal.

    Reads I3PM_* environment variables from process and parent processes
    (up to max_traversal_depth levels) to handle cases where GUI process
    is launched by wrapper script.

    Args:
        window_id: Sway window ID
        pid: Process ID to start query from
        max_traversal_depth: Maximum parent levels to traverse (default: 3)

    Returns:
        EnvironmentQueryResult with window_id, requested_pid, actual_pid,
        traversal_depth, environment (WindowEnvironment or None), error,
        query_time_ms

    Example:
        >>> result = await get_window_environment(94532735639728, 12345)
        >>> if result.environment:
        ...     print(f"Found environment at depth {result.traversal_depth}")
    """
    start_time = time.perf_counter()

    # Try to read environment from requested PID
    current_pid = pid
    traversal_depth = 0

    for depth in range(max_traversal_depth + 1):
        # Read environment variables
        env_vars = read_process_environ(current_pid)

        # Try to parse WindowEnvironment
        window_env = WindowEnvironment.from_env_dict(env_vars)

        if window_env is not None:
            # Found valid environment!
            end_time = time.perf_counter()
            query_time_ms = (end_time - start_time) * 1000.0

            # Track query latency for periodic statistics (T035)
            _track_query_latency(query_time_ms)

            # Comprehensive logging of environment query results (T058)
            logger.debug(
                f"Environment query result - "
                f"window_id={window_id}, "
                f"pid={pid}, "
                f"actual_pid={current_pid}, "
                f"traversal_depth={depth}, "
                f"app_name={window_env.app_name!r}, "
                f"app_id={window_env.app_id!r}, "
                f"project_name={window_env.project_name!r}, "
                f"scope={window_env.scope!r}, "
                f"query_time_ms={query_time_ms:.3f}"
            )

            if depth > 0:
                logger.info(
                    f"Found environment for window {window_id} at parent depth {depth} "
                    f"(pid {current_pid}, original pid {pid}) - "
                    f"app_name={window_env.app_name!r}, project={window_env.project_name!r}"
                )

            return EnvironmentQueryResult(
                window_id=window_id,
                requested_pid=pid,
                actual_pid=current_pid,
                traversal_depth=depth,
                environment=window_env,
                error=None,
                query_time_ms=query_time_ms
            )

        # No valid environment yet - try parent if not at max depth
        if depth < max_traversal_depth:
            parent_pid = get_parent_pid(current_pid)
            if parent_pid is None or parent_pid <= 1:
                # No parent or reached init - stop traversal
                break
            current_pid = parent_pid
        else:
            break

    # Failed to find environment
    end_time = time.perf_counter()
    query_time_ms = (end_time - start_time) * 1000.0

    # Track failed query latency (T035, T058)
    _track_query_latency(query_time_ms)

    # Comprehensive logging for missing environment variables (T058)
    logger.warning(
        f"No I3PM_* environment found for window {window_id} (pid {pid}) "
        f"after traversing {traversal_depth} parent levels - "
        f"query_time_ms={query_time_ms:.3f}"
    )

    # Log which specific environment variables were checked (T058)
    final_env = read_process_environ(pid)
    missing_vars = []
    if "I3PM_APP_ID" not in final_env:
        missing_vars.append("I3PM_APP_ID")
    if "I3PM_APP_NAME" not in final_env:
        missing_vars.append("I3PM_APP_NAME")
    if "I3PM_SCOPE" not in final_env:
        missing_vars.append("I3PM_SCOPE")

    if missing_vars:
        logger.debug(
            f"Missing required environment variables for window {window_id}: "
            f"{', '.join(missing_vars)}"
        )

    return EnvironmentQueryResult(
        window_id=window_id,
        requested_pid=pid,
        actual_pid=None,
        traversal_depth=traversal_depth,
        environment=None,
        error="no_environment_found",
        query_time_ms=query_time_ms
    )


def validate_window_environment(env_vars: Dict[str, str]) -> List[str]:
    """
    Validate I3PM_* environment variable completeness and correctness.

    Args:
        env_vars: Dictionary of environment variables from /proc/<pid>/environ

    Returns:
        List of error strings (empty list if valid)

    Validation Rules:
        - I3PM_APP_ID must be non-empty
        - I3PM_APP_NAME must be non-empty
        - I3PM_SCOPE must be "global" or "scoped"
        - I3PM_TARGET_WORKSPACE must be 1-70 if present
        - I3PM_PROJECT_NAME and I3PM_PROJECT_DIR should be consistent

    Example:
        >>> errors = validate_window_environment(env_vars)
        >>> if errors:
        ...     print(f"Validation failed: {errors}")
    """
    errors = []

    # Check required fields
    if "I3PM_APP_ID" not in env_vars:
        errors.append("Missing required variable: I3PM_APP_ID")
    elif not env_vars["I3PM_APP_ID"]:
        errors.append("I3PM_APP_ID cannot be empty")

    if "I3PM_APP_NAME" not in env_vars:
        errors.append("Missing required variable: I3PM_APP_NAME")
    elif not env_vars["I3PM_APP_NAME"]:
        errors.append("I3PM_APP_NAME cannot be empty")

    if "I3PM_SCOPE" not in env_vars:
        errors.append("Missing required variable: I3PM_SCOPE")
    elif env_vars["I3PM_SCOPE"] not in ("global", "scoped"):
        errors.append(f"Invalid I3PM_SCOPE: {env_vars['I3PM_SCOPE']}, must be 'global' or 'scoped'")

    # Validate optional fields if present
    if "I3PM_TARGET_WORKSPACE" in env_vars:
        try:
            workspace = int(env_vars["I3PM_TARGET_WORKSPACE"])
            if not (1 <= workspace <= 70):
                errors.append(f"I3PM_TARGET_WORKSPACE must be 1-70, got {workspace}")
        except ValueError:
            errors.append(f"I3PM_TARGET_WORKSPACE must be an integer, got '{env_vars['I3PM_TARGET_WORKSPACE']}'")

    # Check project name/dir consistency
    has_project_name = "I3PM_PROJECT_NAME" in env_vars and env_vars["I3PM_PROJECT_NAME"]
    has_project_dir = "I3PM_PROJECT_DIR" in env_vars and env_vars["I3PM_PROJECT_DIR"]

    if has_project_name and not has_project_dir:
        errors.append("I3PM_PROJECT_NAME is set but I3PM_PROJECT_DIR is missing")
    elif has_project_dir and not has_project_name:
        errors.append("I3PM_PROJECT_DIR is set but I3PM_PROJECT_NAME is missing")

    return errors


def log_environment_query_result(result: EnvironmentQueryResult) -> None:
    """
    Log environment query result with appropriate log level.

    Logs:
    - Traversal depth when > 0
    - Warnings for missing I3PM_* variables
    - Errors for /proc access failures
    - Performance metrics when query_time_ms > 10ms

    Args:
        result: EnvironmentQueryResult from get_window_environment()

    Example:
        >>> result = await get_window_environment(window_id, pid)
        >>> log_environment_query_result(result)
    """
    # Track latency for statistics (T035)
    _track_query_latency(result.query_time_ms)

    if result.environment:
        # Success - log info if traversal was needed
        if result.traversal_depth > 0:
            logger.info(
                f"Window {result.window_id}: Found environment at parent depth "
                f"{result.traversal_depth} (pid {result.actual_pid})"
            )

        # Log performance warning if slow
        if result.query_time_ms > 10.0:
            logger.warning(
                f"Window {result.window_id}: Environment query took {result.query_time_ms:.2f}ms "
                f"(threshold: 10ms)"
            )

        # Log environment summary
        env = result.environment
        logger.debug(
            f"Window {result.window_id}: app_name={env.app_name}, "
            f"app_id={env.app_id[:30]}..., scope={env.scope}, "
            f"project={env.project_name or 'none'}"
        )

    else:
        # Failed to find environment - log warning
        logger.warning(
            f"Window {result.window_id}: No I3PM_* environment found (pid {result.requested_pid}, "
            f"error: {result.error}, traversal_depth: {result.traversal_depth})"
        )

        # Log performance even for failures
        if result.query_time_ms > 10.0:
            logger.warning(
                f"Window {result.window_id}: Failed environment query took {result.query_time_ms:.2f}ms"
            )


async def validate_environment_coverage(i3_connection) -> CoverageReport:
    """
    Validate environment variable coverage across all windows.

    Queries Sway IPC for all windows and checks which ones have I3PM_*
    environment variables. Generates comprehensive coverage report.

    Args:
        i3_connection: Async i3ipc connection (i3ipc.aio.Connection)

    Returns:
        CoverageReport with coverage statistics and missing window details

    Example:
        >>> from i3ipc.aio import Connection
        >>> async with Connection() as i3:
        ...     report = await validate_environment_coverage(i3)
        ...     print(f"Coverage: {report.coverage_percentage:.1f}% - {report.status}")
    """
    # Query all windows from Sway tree
    tree = await i3_connection.get_tree()
    all_windows = tree.leaves()

    total_windows = len(all_windows)
    windows_with_env = 0
    windows_without_env = 0
    missing_windows = []

    # Check each window for I3PM_* environment variables
    for window in all_windows:
        # Skip windows without PIDs (special windows, scratchpad, etc.)
        if window.pid is None or window.pid == 0:
            # Count as missing with reason "no_pid"
            missing_windows.append(MissingWindowInfo(
                window_id=window.id,
                window_class=_get_window_class(window),
                window_title=window.name or "(no title)",
                pid=0,
                reason="no_pid"
            ))
            windows_without_env += 1
            continue

        # Try to read process environment
        try:
            env_vars = read_process_environ(window.pid)

            # Check if I3PM_APP_ID is present (primary indicator)
            if "I3PM_APP_ID" in env_vars and env_vars["I3PM_APP_ID"]:
                windows_with_env += 1
            else:
                # Missing I3PM_* variables
                # Determine reason
                reason = "no_variables"
                if not env_vars:
                    # Empty environment - could be permission or process exited
                    # Try to check if process still exists
                    proc_path = Path(f"/proc/{window.pid}")
                    if not proc_path.exists():
                        reason = "process_exited"
                    else:
                        reason = "permission_denied"

                missing_windows.append(MissingWindowInfo(
                    window_id=window.id,
                    window_class=_get_window_class(window),
                    window_title=window.name or "(no title)",
                    pid=window.pid,
                    reason=reason
                ))
                windows_without_env += 1

        except Exception as e:
            # Unexpected error reading environment
            logger.error(f"Error reading environment for window {window.id} (PID {window.pid}): {e}")
            missing_windows.append(MissingWindowInfo(
                window_id=window.id,
                window_class=_get_window_class(window),
                window_title=window.name or "(no title)",
                pid=window.pid,
                reason=f"error: {type(e).__name__}"
            ))
            windows_without_env += 1

    # Calculate coverage percentage
    if total_windows > 0:
        coverage_percentage = (windows_with_env / total_windows) * 100.0
    else:
        coverage_percentage = 0.0

    # Determine status
    status = "PASS" if coverage_percentage == 100.0 else "FAIL"

    # Create report
    report = CoverageReport(
        total_windows=total_windows,
        windows_with_env=windows_with_env,
        windows_without_env=windows_without_env,
        coverage_percentage=coverage_percentage,
        missing_windows=missing_windows,
        status=status,
        timestamp=datetime.now()
    )

    # Log summary
    logger.info(
        f"Environment coverage validation: {coverage_percentage:.1f}% "
        f"({windows_with_env}/{total_windows} windows) - {status}"
    )

    if windows_without_env > 0:
        logger.warning(
            f"Found {windows_without_env} windows without I3PM_* variables: "
            f"{[w.window_class for w in missing_windows[:5]]}"
        )

    return report


def _get_window_class(window) -> str:
    """
    Get window class for reporting (handles Wayland app_id vs X11 class).

    Args:
        window: i3ipc window object

    Returns:
        Window class/app_id as string

    Example:
        >>> cls = _get_window_class(window)
        >>> print(f"Window class: {cls}")
    """
    # Try Wayland app_id first
    if hasattr(window, 'app_id') and window.app_id:
        return window.app_id

    # Fallback to X11 window class
    if hasattr(window, 'window_class') and window.window_class:
        return window.window_class

    # Last resort: try window properties
    if hasattr(window, 'window_properties'):
        props = window.window_properties
        if hasattr(props, 'class_') and props.class_:
            return props.class_

    return "(unknown)"


async def benchmark_environment_queries(
    sample_size: int = 1000
) -> PerformanceBenchmark:
    """
    Benchmark performance of environment variable queries.

    Creates test processes and measures read_process_environ() latency to
    validate that performance meets <10ms p95 target.

    Args:
        sample_size: Number of test samples to measure (default: 1000)

    Returns:
        PerformanceBenchmark with statistics and PASS/FAIL status

    Example:
        >>> benchmark = await benchmark_environment_queries(sample_size=1000)
        >>> print(f"p95 latency: {benchmark.p95_ms:.2f}ms - {benchmark.status}")
    """
    import subprocess
    import os

    logger.info(f"Starting environment query benchmark with {sample_size} samples")

    processes = []
    latencies_ms = []

    try:
        # Create test processes with I3PM_* environment variables
        test_env = os.environ.copy()
        test_env.update({
            "I3PM_APP_ID": "benchmark-test",
            "I3PM_APP_NAME": "benchmark",
            "I3PM_SCOPE": "global",
            "I3PM_PROJECT_NAME": "test",
        })

        # Spawn test processes (limit to 100 concurrent to avoid overwhelming system)
        batch_size = min(100, sample_size)
        for batch_start in range(0, sample_size, batch_size):
            batch_end = min(batch_start + batch_size, sample_size)
            current_batch_size = batch_end - batch_start

            # Spawn batch of processes
            batch_processes = []
            for _ in range(current_batch_size):
                proc = subprocess.Popen(
                    ["sleep", "30"],
                    env=test_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                batch_processes.append(proc)

            processes.extend(batch_processes)

            # Wait briefly for processes to stabilize
            await asyncio.sleep(0.1)

            # Measure latency for each process in batch
            for proc in batch_processes:
                start_time = time.perf_counter()
                env_vars = read_process_environ(proc.pid)
                end_time = time.perf_counter()

                latency_ms = (end_time - start_time) * 1000.0
                latencies_ms.append(latency_ms)

                # Verify environment was read successfully
                if "I3PM_APP_ID" not in env_vars:
                    logger.warning(f"Failed to read environment for PID {proc.pid}")

        # Calculate statistics
        sorted_latencies = sorted(latencies_ms)
        n = len(sorted_latencies)

        average_ms = sum(latencies_ms) / n
        p50_ms = sorted_latencies[int(n * 0.50)]
        p95_ms = sorted_latencies[int(n * 0.95)]
        p99_ms = sorted_latencies[int(n * 0.99)]
        max_ms = max(latencies_ms)
        min_ms = min(latencies_ms)

        # Determine status based on p95 threshold
        status = "PASS" if p95_ms < 10.0 else "FAIL"

        # Create benchmark result
        benchmark = PerformanceBenchmark(
            operation="read_process_environ",
            sample_size=n,
            average_ms=average_ms,
            p50_ms=p50_ms,
            p95_ms=p95_ms,
            p99_ms=p99_ms,
            max_ms=max_ms,
            min_ms=min_ms,
            status=status,
        )

        # Log results
        logger.info(
            f"Benchmark complete: {sample_size} samples, "
            f"avg={average_ms:.3f}ms, p95={p95_ms:.3f}ms, status={status}"
        )

        return benchmark

    except Exception as e:
        logger.error(f"Error during benchmark: {e}")
        raise

    finally:
        # Cleanup: Terminate all test processes
        for proc in processes:
            try:
                proc.terminate()
                try:
                    proc.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
            except ProcessLookupError:
                pass  # Process already exited
