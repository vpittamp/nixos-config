"""
Data models for environment variable-based window matching.

This module defines the core data structures for:
- WindowEnvironment: Parsed I3PM_* environment variables
- EnvironmentQueryResult: Result of environment variable query
- CoverageReport: Environment variable coverage validation result
- PerformanceBenchmark: Performance benchmark results
- MissingWindowInfo: Information about windows without environment variables

These models replace window class/title-based identification with deterministic
environment variable-based identification.
"""

from dataclasses import dataclass, field
from typing import Optional, Literal, List, Dict
from datetime import datetime
import statistics


@dataclass
class WindowEnvironment:
    """
    Parsed I3PM_* environment variables from window process.

    This dataclass provides deterministic window identification and project
    association without relying on non-deterministic window class, title,
    or app_id properties.

    Example:
        >>> env_vars = read_process_environ(window.pid)
        >>> window_env = WindowEnvironment.from_env_dict(env_vars)
        >>> if window_env.should_be_visible("nixos"):
        ...     # Show window
    """

    # Required identifiers
    app_id: str  # I3PM_APP_ID - unique window instance identifier
    app_name: str  # I3PM_APP_NAME - application type identifier
    scope: Literal["global", "scoped"]  # I3PM_SCOPE - visibility scope

    # Optional project association
    project_name: str = ""  # I3PM_PROJECT_NAME
    project_dir: str = ""  # I3PM_PROJECT_DIR
    project_display_name: str = ""  # I3PM_PROJECT_DISPLAY_NAME
    project_icon: str = ""  # I3PM_PROJECT_ICON

    # Optional metadata
    active: bool = True  # I3PM_ACTIVE (default: true)
    target_workspace: Optional[int] = None  # I3PM_TARGET_WORKSPACE
    expected_class: str = ""  # I3PM_EXPECTED_CLASS
    launcher_pid: Optional[int] = None  # I3PM_LAUNCHER_PID
    launch_time: Optional[int] = None  # I3PM_LAUNCH_TIME
    i3_socket: str = ""  # I3SOCK

    def __post_init__(self):
        """Validate environment variables after initialization."""
        if not self.app_id:
            raise ValueError("app_id cannot be empty")
        if not self.app_name:
            raise ValueError("app_name cannot be empty")
        if self.scope not in ("global", "scoped"):
            raise ValueError(f"Invalid scope: {self.scope}, must be 'global' or 'scoped'")
        if self.target_workspace is not None:
            if not (1 <= self.target_workspace <= 70):
                raise ValueError(f"target_workspace must be 1-70, got {self.target_workspace}")

    @classmethod
    def from_env_dict(cls, env: Dict[str, str]) -> Optional["WindowEnvironment"]:
        """
        Parse WindowEnvironment from environment variable dictionary.

        Args:
            env: Dictionary of environment variables from /proc/<pid>/environ

        Returns:
            WindowEnvironment instance or None if required variables missing

        Example:
            >>> env = read_process_environ(12345)
            >>> window_env = WindowEnvironment.from_env_dict(env)
        """
        # Check for required variables
        if "I3PM_APP_ID" not in env or "I3PM_APP_NAME" not in env or "I3PM_SCOPE" not in env:
            return None

        # Parse optional integer fields
        target_workspace = None
        if "I3PM_TARGET_WORKSPACE" in env:
            try:
                target_workspace = int(env["I3PM_TARGET_WORKSPACE"])
            except ValueError:
                pass

        launcher_pid = None
        if "I3PM_LAUNCHER_PID" in env:
            try:
                launcher_pid = int(env["I3PM_LAUNCHER_PID"])
            except ValueError:
                pass

        launch_time = None
        if "I3PM_LAUNCH_TIME" in env:
            try:
                launch_time = int(env["I3PM_LAUNCH_TIME"])
            except ValueError:
                pass

        # Parse boolean active field
        active = True
        if "I3PM_ACTIVE" in env:
            active = env["I3PM_ACTIVE"].lower() in ("true", "1", "yes")

        try:
            return cls(
                app_id=env["I3PM_APP_ID"],
                app_name=env["I3PM_APP_NAME"],
                scope=env["I3PM_SCOPE"],  # type: ignore
                project_name=env.get("I3PM_PROJECT_NAME", ""),
                project_dir=env.get("I3PM_PROJECT_DIR", ""),
                project_display_name=env.get("I3PM_PROJECT_DISPLAY_NAME", ""),
                project_icon=env.get("I3PM_PROJECT_ICON", ""),
                active=active,
                target_workspace=target_workspace,
                expected_class=env.get("I3PM_EXPECTED_CLASS", ""),
                launcher_pid=launcher_pid,
                launch_time=launch_time,
                i3_socket=env.get("I3SOCK", ""),
            )
        except ValueError:
            # Validation failed
            return None

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

        Example:
            >>> if window_env.should_be_visible("nixos"):
            ...     # Window should be visible
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


@dataclass
class EnvironmentQueryResult:
    """
    Result of querying window environment variables.

    This dataclass tracks the result of reading /proc/<pid>/environ for a
    window, including parent process traversal and performance metrics.

    Example:
        >>> result = await get_window_environment(window_id, pid)
        >>> if result.environment:
        ...     print(f"Found environment at depth {result.traversal_depth}")
    """

    window_id: int  # Sway window ID
    requested_pid: int  # PID requested for query
    actual_pid: Optional[int] = None  # PID where environment found (may be parent)
    traversal_depth: int = 0  # Number of parent levels traversed
    environment: Optional[WindowEnvironment] = None  # Parsed environment or None
    error: Optional[str] = None  # Error message if query failed
    query_time_ms: float = 0.0  # Time taken for query in milliseconds


@dataclass
class MissingWindowInfo:
    """
    Information about a window without I3PM_* environment variables.

    Used in coverage reports to identify windows that lack required
    environment variable injection.

    Example:
        >>> missing = MissingWindowInfo(
        ...     window_id=12345,
        ...     window_class="Firefox",
        ...     window_title="Mozilla Firefox",
        ...     pid=67890,
        ...     reason="no_variables"
        ... )
    """

    window_id: int  # Sway window ID
    window_class: str  # Window class (X11) or app_id (Wayland)
    window_title: str  # Window title
    pid: Optional[int]  # Process ID (None if not available)
    reason: str  # Why variables are missing (e.g., "no_variables", "parse_error")


@dataclass
class CoverageReport:
    """
    Report on environment variable coverage across all windows.

    Validates that all launched applications have I3PM_* environment
    variables injected. Used for quality assurance and debugging.

    Example:
        >>> report = await validate_environment_coverage()
        >>> if report.status == "PASS":
        ...     print(f"Coverage: {report.coverage_percentage:.1f}%")
    """

    total_windows: int  # Total windows checked
    windows_with_env: int  # Windows with valid I3PM_* variables
    windows_without_env: int  # Windows missing I3PM_* variables
    coverage_percentage: float  # Percentage with environment (0-100)
    missing_windows: List[MissingWindowInfo] = field(default_factory=list)
    status: str = "UNKNOWN"  # "PASS" if 100%, "FAIL" otherwise
    timestamp: datetime = field(default_factory=datetime.now)

    def __post_init__(self):
        """Calculate derived fields."""
        # Ensure windows_without_env matches missing_windows count
        self.windows_without_env = len(self.missing_windows)

        # Calculate coverage percentage
        if self.total_windows > 0:
            self.coverage_percentage = (self.windows_with_env / self.total_windows) * 100.0
        else:
            self.coverage_percentage = 100.0  # No windows = 100% coverage

        # Determine status
        if self.coverage_percentage >= 100.0:
            self.status = "PASS"
        else:
            self.status = "FAIL"


@dataclass
class PerformanceBenchmark:
    """
    Performance benchmark results for environment variable queries.

    Tracks latency statistics for /proc/<pid>/environ reads to validate
    performance requirements (<10ms p95 target).

    Example:
        >>> benchmark = PerformanceBenchmark.from_samples("environ_query", [0.5, 0.8, 1.2, ...])
        >>> if benchmark.status == "PASS":
        ...     print(f"p95: {benchmark.p95_ms:.2f}ms")
    """

    operation: str  # Operation being benchmarked
    sample_size: int  # Number of samples collected
    average_ms: float  # Average latency in milliseconds
    p50_ms: float  # 50th percentile (median)
    p95_ms: float  # 95th percentile
    p99_ms: float  # 99th percentile
    max_ms: float  # Maximum latency
    min_ms: float  # Minimum latency
    status: str = "UNKNOWN"  # "PASS" if meets target, "FAIL" otherwise

    @classmethod
    def from_samples(
        cls,
        operation: str,
        latencies_ms: List[float],
        target_p95_ms: float = 10.0
    ) -> "PerformanceBenchmark":
        """
        Create benchmark from raw latency samples.

        Args:
            operation: Name of operation being benchmarked
            latencies_ms: List of latency measurements in milliseconds
            target_p95_ms: Target p95 latency (default: 10ms)

        Returns:
            PerformanceBenchmark instance with statistics

        Example:
            >>> samples = [0.5, 0.8, 1.2, 1.5, 0.9, ...]
            >>> benchmark = PerformanceBenchmark.from_samples("read_environ", samples)
        """
        if not latencies_ms:
            # No samples - return empty benchmark
            return cls(
                operation=operation,
                sample_size=0,
                average_ms=0.0,
                p50_ms=0.0,
                p95_ms=0.0,
                p99_ms=0.0,
                max_ms=0.0,
                min_ms=0.0,
                status="NO_SAMPLES"
            )

        # Calculate statistics
        sample_size = len(latencies_ms)
        average_ms = statistics.mean(latencies_ms)
        p50_ms = statistics.median(latencies_ms)

        # Percentiles
        sorted_latencies = sorted(latencies_ms)
        p95_index = int(0.95 * len(sorted_latencies))
        p99_index = int(0.99 * len(sorted_latencies))
        p95_ms = sorted_latencies[min(p95_index, len(sorted_latencies) - 1)]
        p99_ms = sorted_latencies[min(p99_index, len(sorted_latencies) - 1)]

        max_ms = max(latencies_ms)
        min_ms = min(latencies_ms)

        # Determine status based on target
        status = "PASS" if p95_ms < target_p95_ms else "FAIL"

        return cls(
            operation=operation,
            sample_size=sample_size,
            average_ms=average_ms,
            p50_ms=p50_ms,
            p95_ms=p95_ms,
            p99_ms=p99_ms,
            max_ms=max_ms,
            min_ms=min_ms,
            status=status
        )
