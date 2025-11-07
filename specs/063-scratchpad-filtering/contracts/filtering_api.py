"""
Filtering API Contract - Scratchpad Terminal Filtering

This contract defines the public API for consistent window filtering across
all i3pm daemon code paths (ipc_server.py, window_filter.py, handlers.py).

Target audience: Python 3.11+ developers working on i3pm daemon
Contract version: 1.0.0
"""

from dataclasses import dataclass
from typing import List, Optional
from enum import Enum


# ============================================================================
# Enumerations
# ============================================================================

class WindowScope(Enum):
    """Window visibility scope during project switching."""
    SCOPED = "scoped"  # Hidden when not in active project
    GLOBAL = "global"  # Always visible regardless of project


class FilteringCodePath(Enum):
    """Code path that made a filtering decision (for audit trail)."""
    IPC_SERVER = "ipc_server"  # JSON-RPC switch_project method
    WINDOW_FILTER = "window_filter"  # filter_windows_by_project helper
    HANDLERS_TICK = "handlers_tick"  # TICK event handler


# ============================================================================
# Data Models
# ============================================================================

@dataclass
class WindowEnvironment:
    """
    Validated I3PM environment variables from window process.

    Source: /proc/<pid>/environ

    Validation:
    - app_id MUST be non-empty
    - app_name MUST be non-empty
    - scope MUST be WindowScope enum value
    - If is_scratchpad=True, app_name MUST be "scratchpad-terminal"
    - If is_scratchpad=True, project_name MUST be present
    """

    app_id: str  # I3PM_APP_ID (e.g., "scratchpad-nixos-1699564800")
    app_name: str  # I3PM_APP_NAME (e.g., "scratchpad-terminal", "vscode")
    scope: WindowScope  # I3PM_SCOPE

    project_name: Optional[str]  # I3PM_PROJECT_NAME (None for global apps)
    project_dir: Optional[str]  # I3PM_PROJECT_DIR

    is_scratchpad: bool  # I3PM_SCRATCHPAD == "true"
    working_dir: Optional[str]  # I3PM_WORKING_DIR (scratchpad-specific)

    validated_at: float  # Timestamp when environment was read
    validation_source: str  # "proc_environ" | "cache"

    @classmethod
    def from_pid(cls, pid: int) -> Optional["WindowEnvironment"]:
        """
        Read and parse I3PM environment variables from process.

        Args:
            pid: Process ID to read environment from

        Returns:
            WindowEnvironment if valid I3PM_* variables found, None otherwise

        Raises:
            ValueError: If environment variables present but invalid format
        """
        raise NotImplementedError

    @property
    def is_scoped(self) -> bool:
        """Window is project-scoped (filtered during project switches)."""
        return self.scope == WindowScope.SCOPED

    @property
    def is_global(self) -> bool:
        """Window is global (always visible regardless of project)."""
        return self.scope == WindowScope.GLOBAL

    def matches_project(self, project_name: str) -> bool:
        """
        Check if window belongs to the given project.

        Args:
            project_name: Project name to match against

        Returns:
            True if window belongs to project, False otherwise
        """
        return self.project_name == project_name


@dataclass
class WindowFilterCriteria:
    """
    Unified filtering criteria for determining window visibility.

    Used by all three code paths to ensure consistent filtering decisions.

    Evaluation order:
    1. Check for project mark (project:{name}:)
    2. Check for scratchpad mark (scratchpad:{name})
    3. If no marks, check environment variables via PID
    4. Default: global (don't hide)
    """

    active_project: str  # Current project name
    window_id: int  # Sway window container ID
    window_marks: List[str]  # Sway window marks
    window_pid: Optional[int]  # Process ID (for environment lookup)

    evaluated_at: float  # Timestamp when criteria was evaluated
    code_path: FilteringCodePath  # Which code path is evaluating

    def should_hide(self) -> bool:
        """
        Determine if window should be hidden for active_project.

        Returns:
            True if window should be hidden, False if window should remain visible

        Implementation note:
        - MUST prioritize mark-based evaluation (fast path)
        - SHOULD only read environment if marks missing (slow path)
        - MUST return False for global windows (always visible)
        """
        raise NotImplementedError

    def get_window_project(self) -> Optional[str]:
        """
        Extract project name from marks or environment.

        Returns:
            Project name if window is project-scoped, None if global

        Implementation note:
        - Check marks first (fast)
        - Fall back to environment variables if marks missing
        """
        raise NotImplementedError

    def is_scratchpad_terminal(self) -> bool:
        """
        Check if window is a scratchpad terminal.

        Returns:
            True if window is a scratchpad terminal, False otherwise

        Implementation note:
        - Check for "scratchpad:{project}" mark first (fast)
        - Fall back to environment I3PM_SCRATCHPAD == "true"
        """
        raise NotImplementedError


@dataclass
class FilteringDecision:
    """
    Record of a filtering decision for debugging and validation.

    Used for audit trail, logging, and test verification.
    """

    # Input
    window_id: int
    window_marks: List[str]
    active_project: str
    code_path: FilteringCodePath

    # Decision
    should_hide: bool
    reason: str  # Human-readable reason (e.g., "scratchpad for different project")
    window_project: Optional[str]  # Project associated with window

    # Metadata
    decided_at: float
    environment_checked: bool  # True if /proc/<pid>/environ was read
    mark_checked: bool  # True if window marks were evaluated

    def to_log_message(self) -> str:
        """
        Format decision as log message.

        Returns:
            Formatted log message string

        Example:
            "[ipc_server] HIDE window 12345: scratchpad for different project"
        """
        action = "HIDE" if self.should_hide else "SHOW"
        return f"[{self.code_path.value}] {action} window {self.window_id}: {self.reason}"


# ============================================================================
# Public API Functions
# ============================================================================

def should_hide_window_for_project(
    window_marks: List[str],
    active_project: str,
    window_pid: Optional[int] = None,
) -> bool:
    """
    Determine if window should be hidden when switching to active_project.

    This is the SINGLE SOURCE OF TRUTH for filtering logic.
    ALL code paths MUST call this function to ensure consistency.

    Args:
        window_marks: Sway window marks (from window.marks)
        active_project: Name of project being switched to
        window_pid: Optional process ID for environment fallback

    Returns:
        True if window should be hidden, False if window should remain visible

    Example:
        >>> should_hide_window_for_project(
        ...     window_marks=["scratchpad:nixos"],
        ...     active_project="stacks",
        ... )
        True  # Different project, hide it

        >>> should_hide_window_for_project(
        ...     window_marks=["scratchpad:nixos"],
        ...     active_project="nixos",
        ... )
        False  # Same project, keep visible

    Performance:
        - Mark-based: < 1ms per window
        - Environment-based (fallback): < 5ms per window (with caching)
    """
    raise NotImplementedError


def parse_project_from_mark(mark: str) -> Optional[str]:
    """
    Extract project name from window mark.

    Supported formats:
        - "project:{name}:{window_id}"  → "{name}"
        - "scratchpad:{name}"           → "{name}"
        - Other marks                   → None

    Args:
        mark: Window mark string

    Returns:
        Project name if mark is project-scoped, None otherwise

    Example:
        >>> parse_project_from_mark("scratchpad:nixos")
        "nixos"

        >>> parse_project_from_mark("project:stacks:12345")
        "stacks"

        >>> parse_project_from_mark("some-other-mark")
        None
    """
    raise NotImplementedError


def validate_scratchpad_environment(env: WindowEnvironment) -> bool:
    """
    Validate that environment variables are correct for a scratchpad terminal.

    Checks:
        - I3PM_SCRATCHPAD == "true"
        - I3PM_APP_NAME == "scratchpad-terminal"
        - I3PM_PROJECT_NAME is present
        - I3PM_SCOPE == "scoped"

    Args:
        env: WindowEnvironment to validate

    Returns:
        True if environment is valid for scratchpad terminal, False otherwise

    Example:
        >>> env = WindowEnvironment.from_pid(12345)
        >>> validate_scratchpad_environment(env)
        True  # Valid scratchpad terminal
    """
    raise NotImplementedError


# ============================================================================
# Test Utilities
# ============================================================================

def create_mock_environment(
    project_name: str,
    is_scratchpad: bool = False,
    scope: WindowScope = WindowScope.SCOPED,
) -> WindowEnvironment:
    """
    Create mock WindowEnvironment for testing.

    Args:
        project_name: Project name to associate with window
        is_scratchpad: Whether window is a scratchpad terminal
        scope: Window scope (SCOPED or GLOBAL)

    Returns:
        Mock WindowEnvironment suitable for unit tests

    Example:
        >>> env = create_mock_environment("nixos", is_scratchpad=True)
        >>> env.app_name
        "scratchpad-terminal"
    """
    raise NotImplementedError


def create_mock_criteria(
    active_project: str,
    window_marks: List[str],
    window_pid: Optional[int] = None,
) -> WindowFilterCriteria:
    """
    Create mock WindowFilterCriteria for testing.

    Args:
        active_project: Current project name
        window_marks: Window marks to evaluate
        window_pid: Optional process ID

    Returns:
        Mock WindowFilterCriteria suitable for unit tests

    Example:
        >>> criteria = create_mock_criteria("nixos", ["scratchpad:nixos"])
        >>> criteria.should_hide()
        False  # Same project
    """
    raise NotImplementedError


# ============================================================================
# Contract Validation
# ============================================================================

def validate_filtering_consistency(
    window_id: int,
    window_marks: List[str],
    active_project: str,
    window_pid: Optional[int],
) -> List[FilteringDecision]:
    """
    Validate that all three code paths make the same filtering decision.

    Used in integration tests to ensure consistency.

    Args:
        window_id: Sway window container ID
        window_marks: Window marks
        active_project: Current project name
        window_pid: Process ID

    Returns:
        List of FilteringDecisions (one per code path)

    Raises:
        AssertionError: If code paths make different decisions

    Example:
        >>> decisions = validate_filtering_consistency(
        ...     window_id=12345,
        ...     window_marks=["scratchpad:nixos"],
        ...     active_project="stacks",
        ...     window_pid=67890,
        ... )
        >>> assert len(decisions) == 3
        >>> assert all(d.should_hide for d in decisions)  # All agree
    """
    raise NotImplementedError
