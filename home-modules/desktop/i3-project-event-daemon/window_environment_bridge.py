"""
Integration bridge between Feature 057 environment-based modules and existing daemon.

This module provides backward-compatible interfaces that allow the existing
handlers.py to gradually adopt environment-based window identification while
maintaining compatibility with legacy class-based code.

Migration Strategy:
1. Phase 1: Use this bridge for new code paths (environment-first)
2. Phase 2: Refactor existing handlers to prefer environment over class
3. Phase 3: Remove legacy class-based fallbacks

Usage in handlers.py:
    from .window_environment_bridge import get_window_app_info, should_window_be_visible

    # Instead of class-based matching:
    # window_class = get_window_class(container)
    # app_name = match_by_class(window_class)

    # Use environment-based:
    app_info = await get_window_app_info(container)
    if app_info:
        app_name = app_info['app_name']
        project_name = app_info['project_name']
"""

import sys
import logging
from pathlib import Path
from typing import Optional, Dict, Any

# Add daemon modules to path
daemon_modules_path = Path(__file__).parent.parent.parent / "tools" / "i3pm" / "daemon"
if str(daemon_modules_path) not in sys.path:
    sys.path.insert(0, str(daemon_modules_path))

# Import Feature 057 modules
try:
    from window_environment import get_window_environment, read_process_environ
    from models import WindowEnvironment, EnvironmentQueryResult
    from window_filter import filter_windows_for_project, apply_project_filtering
    ENV_MODULES_AVAILABLE = True
except ImportError as e:
    logging.warning(f"Feature 057 environment modules not available: {e}")
    ENV_MODULES_AVAILABLE = False
    # Define fallback types
    WindowEnvironment = None
    EnvironmentQueryResult = None

logger = logging.getLogger(__name__)


async def get_window_app_info(container, max_traversal_depth: int = 3) -> Optional[Dict[str, Any]]:
    """
    Get application information from window environment variables.

    This is the primary entry point for environment-based window identification.
    Falls back to None if environment variables are not available, allowing
    callers to use legacy class-based matching as fallback.

    Args:
        container: i3ipc window container
        max_traversal_depth: Maximum parent PID levels to traverse

    Returns:
        Dictionary with application info or None:
        - app_id: Unique window instance identifier (I3PM_APP_ID)
        - app_name: Application type (I3PM_APP_NAME)
        - scope: Visibility scope (I3PM_SCOPE: global/scoped)
        - project_name: Associated project (I3PM_PROJECT_NAME)
        - project_dir: Project directory (I3PM_PROJECT_DIR)
        - target_workspace: Preferred workspace (I3PM_TARGET_WORKSPACE)
        - expected_class: Expected window class for validation (I3PM_EXPECTED_CLASS)
        - query_time_ms: Query latency in milliseconds
        - traversal_depth: Parent PID levels traversed
        - source: "environment" (for logging/debugging)

    Example:
        >>> app_info = await get_window_app_info(container)
        >>> if app_info:
        ...     logger.info(f"Window {container.id}: app={app_info['app_name']}, "
        ...                 f"project={app_info['project_name']}")
        ... else:
        ...     # Fallback to legacy class matching
        ...     window_class = get_window_class(container)
    """
    if not ENV_MODULES_AVAILABLE:
        return None

    # Check if window has PID
    if not hasattr(container, 'pid') or container.pid is None or container.pid == 0:
        logger.debug(
            f"Window {container.id} has no PID, cannot query environment variables"
        )
        return None

    # Query environment variables
    try:
        result: EnvironmentQueryResult = await get_window_environment(
            window_id=container.id,
            pid=container.pid,
            max_traversal_depth=max_traversal_depth
        )

        if result.environment is None:
            logger.debug(
                f"Window {container.id} (PID {container.pid}): "
                f"No I3PM_* environment found (error: {result.error})"
            )
            return None

        env = result.environment

        # Build app info dictionary
        app_info = {
            "app_id": env.app_id,
            "app_name": env.app_name,
            "scope": env.scope,
            "project_name": env.project_name,
            "project_dir": env.project_dir,
            "project_display_name": env.project_display_name,
            "project_icon": env.project_icon,
            "target_workspace": env.target_workspace,
            "expected_class": env.expected_class,
            "active": env.active,
            "launcher_pid": env.launcher_pid,
            "launch_time": env.launch_time,
            # Metadata
            "query_time_ms": result.query_time_ms,
            "traversal_depth": result.traversal_depth,
            "actual_pid": result.actual_pid,
            "source": "environment",
        }

        logger.debug(
            f"Window {container.id} environment: app={env.app_name}, "
            f"project={env.project_name}, scope={env.scope}, "
            f"query_time={result.query_time_ms:.2f}ms"
        )

        return app_info

    except Exception as e:
        logger.error(
            f"Error querying environment for window {container.id} (PID {container.pid}): {e}",
            exc_info=True
        )
        return None


def should_window_be_visible(
    app_info: Optional[Dict[str, Any]],
    active_project: Optional[str]
) -> bool:
    """
    Determine if window should be visible based on environment variables.

    Uses environment-based visibility logic:
    - Global scope (I3PM_SCOPE=global): Always visible
    - Scoped scope (I3PM_SCOPE=scoped): Visible only if I3PM_PROJECT_NAME matches active project

    Args:
        app_info: Application info from get_window_app_info()
        active_project: Currently active project name (None if no project)

    Returns:
        True if window should be visible, False if should be hidden

    Example:
        >>> app_info = await get_window_app_info(container)
        >>> if app_info:
        ...     visible = should_window_be_visible(app_info, "nixos")
        ...     if not visible:
        ...         await container.command("move scratchpad")
    """
    if not ENV_MODULES_AVAILABLE or app_info is None:
        # No environment info - default to visible (defensive)
        return True

    scope = app_info.get("scope")
    project_name = app_info.get("project_name", "")

    # Global windows always visible
    if scope == "global":
        return True

    # Scoped windows visible only in matching project
    if scope == "scoped":
        if active_project is None:
            # No active project - hide scoped windows
            return False
        # Show if project matches
        return project_name == active_project

    # Unknown scope - default to visible (defensive)
    logger.warning(f"Unknown scope '{scope}' in app_info, defaulting to visible")
    return True


def get_preferred_workspace_from_environment(
    app_info: Optional[Dict[str, Any]]
) -> Optional[int]:
    """
    Get preferred workspace number from environment variables.

    Extracts I3PM_TARGET_WORKSPACE from application info, providing a
    deterministic workspace assignment without class-based registry lookups.

    Args:
        app_info: Application info from get_window_app_info()

    Returns:
        Workspace number (1-70) or None if not specified

    Example:
        >>> app_info = await get_window_app_info(container)
        >>> preferred_ws = get_preferred_workspace_from_environment(app_info)
        >>> if preferred_ws:
        ...     await container.command(f"move to workspace number {preferred_ws}")
    """
    if app_info is None:
        return None

    target_workspace = app_info.get("target_workspace")

    # Validate workspace range
    if target_workspace is not None:
        if not isinstance(target_workspace, int):
            logger.warning(
                f"Invalid target_workspace type: {type(target_workspace)}, "
                f"expected int"
            )
            return None
        if not (1 <= target_workspace <= 70):
            logger.warning(
                f"Invalid target_workspace value: {target_workspace}, "
                f"must be 1-70"
            )
            return None

    return target_workspace


def validate_window_class_match(
    app_info: Optional[Dict[str, Any]],
    actual_window_class: str
) -> Dict[str, Any]:
    """
    Validate that actual window class matches expected class from environment.

    This is a diagnostic function to detect mismatches between I3PM_EXPECTED_CLASS
    and the actual window class, helping identify apps that need config updates.

    Args:
        app_info: Application info from get_window_app_info()
        actual_window_class: Actual window class from get_window_class(container)

    Returns:
        Dictionary with validation results:
        - matches: bool - Whether classes match
        - expected: str - Expected class from I3PM_EXPECTED_CLASS
        - actual: str - Actual window class
        - app_name: str - Application name for context

    Example:
        >>> app_info = await get_window_app_info(container)
        >>> window_class = get_window_class(container)
        >>> validation = validate_window_class_match(app_info, window_class)
        >>> if not validation['matches']:
        ...     logger.warning(f"Class mismatch for {validation['app_name']}: "
        ...                    f"expected {validation['expected']}, got {validation['actual']}")
    """
    if app_info is None:
        return {
            "matches": False,
            "expected": "",
            "actual": actual_window_class,
            "app_name": "",
            "reason": "no_environment_info",
        }

    expected_class = app_info.get("expected_class", "")
    app_name = app_info.get("app_name", "")

    # Empty expected_class means no validation needed
    if not expected_class:
        return {
            "matches": True,
            "expected": "",
            "actual": actual_window_class,
            "app_name": app_name,
            "reason": "no_expected_class_specified",
        }

    matches = expected_class == actual_window_class

    return {
        "matches": matches,
        "expected": expected_class,
        "actual": actual_window_class,
        "app_name": app_name,
        "reason": "match" if matches else "mismatch",
    }


# Backward compatibility aliases for gradual migration
get_app_info_from_environment = get_window_app_info
check_window_visibility = should_window_be_visible
get_target_workspace_from_env = get_preferred_workspace_from_environment
