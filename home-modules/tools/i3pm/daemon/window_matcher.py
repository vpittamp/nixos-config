"""
Environment-based window matching implementation.

This module provides window matching and identification using I3PM_* environment
variables instead of legacy class-based matching. Replaces multi-level fallback
logic with deterministic environment variable lookup.

Key Functions:
- match_window(): Primary entry point for window identification
- get_window_identity(): Extract window identity from environment
- match_window_to_app(): Match window to registered application

Architecture:
- Uses get_window_environment() for /proc filesystem reads
- No window class normalization or fuzzy matching
- Deterministic identification via I3PM_APP_NAME and I3PM_APP_ID
"""

import logging
from typing import Optional, Dict, Tuple
from i3ipc.aio import Con

from .models import WindowEnvironment, EnvironmentQueryResult
from .window_environment import get_window_environment, log_environment_query_result

logger = logging.getLogger(__name__)


async def match_window(window: Con) -> Optional[Dict[str, str]]:
    """
    Match window using environment-based identification.

    This is the primary entry point for window matching. Replaces legacy
    class-based matching with deterministic environment variable lookup.

    Args:
        window: i3ipc window container (Con object)

    Returns:
        Dictionary with window identity information:
        - app_name: Application type identifier
        - app_id: Unique window instance identifier
        - project_name: Associated project (if scoped)
        - scope: "global" or "scoped"
        Or None if window has no PID or no environment found

    Example:
        >>> window_info = await match_window(window)
        >>> if window_info:
        ...     print(f"App: {window_info['app_name']}, ID: {window_info['app_id']}")
    """
    # Check if window has PID
    if not window.pid:
        logger.debug(f"Window {window.id} has no PID - cannot read environment")
        return None

    # Query environment with parent traversal
    result = await get_window_environment(
        window_id=window.id,
        pid=window.pid,
        max_traversal_depth=3
    )

    # Log the result
    log_environment_query_result(result)

    # Check if environment was found
    if result.environment is None:
        logger.warning(
            f"Window {window.id} (pid {window.pid}): No I3PM_* environment found, "
            f"cannot identify window"
        )
        return None

    # Extract identity from environment
    env = result.environment
    identity = {
        "app_name": env.app_name,
        "app_id": env.app_id,
        "scope": env.scope,
        "project_name": env.project_name if env.has_project else "",
        "target_workspace": env.target_workspace,
        "expected_class": env.expected_class,
        "traversal_depth": result.traversal_depth,
        "query_time_ms": result.query_time_ms
    }

    logger.info(
        f"Window {window.id} identified: app_name={env.app_name}, "
        f"app_id={env.app_id[:30]}..., scope={env.scope}, "
        f"project={env.project_name or 'none'}"
    )

    return identity


async def get_window_identity(window: Con) -> Tuple[Optional[str], Optional[str]]:
    """
    Get window identity (app_name, app_id) from environment variables.

    Simplified interface that returns just the core identity tuple.
    Used when you only need app_name and app_id without full context.

    Args:
        window: i3ipc window container

    Returns:
        Tuple of (app_name, app_id) or (None, None) if not found

    Example:
        >>> app_name, app_id = await get_window_identity(window)
        >>> if app_name:
        ...     print(f"Window is {app_name} instance {app_id}")
    """
    identity = await match_window(window)
    if identity is None:
        return None, None

    return identity["app_name"], identity["app_id"]


async def match_window_to_app(
    window: Con,
    app_registry: Dict[str, Dict]
) -> Optional[Dict[str, str]]:
    """
    Match window to registered application using environment variables.

    Uses I3PM_APP_NAME from environment to look up application in registry.
    No class-based matching or fuzzy logic - direct environment variable lookup.

    Args:
        window: i3ipc window container
        app_registry: Dictionary of registered applications
                     (keyed by app_name from app-registry-data.nix)

    Returns:
        Application definition from registry or None if not found

    Example:
        >>> app_def = await match_window_to_app(window, app_registry)
        >>> if app_def:
        ...     print(f"Matched to: {app_def['display_name']}")
    """
    # Get window identity from environment
    identity = await match_window(window)
    if identity is None:
        return None

    app_name = identity["app_name"]

    # Look up in registry
    if app_name not in app_registry:
        logger.warning(
            f"Window {window.id}: app_name '{app_name}' not found in registry "
            f"(window may be unregistered or using custom launcher)"
        )
        return None

    app_def = app_registry[app_name]
    logger.debug(
        f"Window {window.id}: Matched to registered app '{app_name}' "
        f"({app_def.get('display_name', app_name)})"
    )

    return app_def


def validate_window_class(window: Con, expected_class: str) -> bool:
    """
    Validate window class matches expected class (for debugging/validation).

    This function is for VALIDATION only - not used for identification.
    Helps debug cases where I3PM_EXPECTED_CLASS doesn't match actual window class.

    Args:
        window: i3ipc window container
        expected_class: Expected window class from I3PM_EXPECTED_CLASS

    Returns:
        True if classes match, False otherwise

    Example:
        >>> if not validate_window_class(window, env.expected_class):
        ...     logger.warning(f"Class mismatch: expected {env.expected_class}")
    """
    # Get actual window class (X11) or app_id (Wayland)
    actual_class = getattr(window, "window_class", None) or getattr(window, "app_id", None)

    if actual_class is None:
        logger.debug(f"Window {window.id}: No window_class or app_id property")
        return False

    if actual_class != expected_class:
        logger.warning(
            f"Window {window.id}: Class mismatch - "
            f"expected '{expected_class}', got '{actual_class}'"
        )
        return False

    return True


async def get_window_project_association(window: Con) -> Optional[str]:
    """
    Get project association from window environment.

    Reads I3PM_PROJECT_NAME from environment variables. Used for
    project-based window filtering and visibility control.

    Args:
        window: i3ipc window container

    Returns:
        Project name or None if window has no project association

    Example:
        >>> project = await get_window_project_association(window)
        >>> if project:
        ...     print(f"Window belongs to project: {project}")
    """
    identity = await match_window(window)
    if identity is None:
        return None

    project_name = identity.get("project_name", "")
    return project_name if project_name else None


async def should_window_be_visible(
    window: Con,
    active_project: Optional[str]
) -> bool:
    """
    Determine if window should be visible in given project context.

    Uses WindowEnvironment.should_be_visible() logic:
    - Global windows: always visible
    - Scoped windows: visible only in matching project

    Args:
        window: i3ipc window container
        active_project: Currently active project name (None if no project)

    Returns:
        True if window should be visible, False if should be hidden

    Example:
        >>> if await should_window_be_visible(window, "nixos"):
        ...     # Show window
        ... else:
        ...     # Hide window to scratchpad
    """
    # Query environment
    if not window.pid:
        # No PID - cannot determine, default to visible
        return True

    result = await get_window_environment(
        window_id=window.id,
        pid=window.pid,
        max_traversal_depth=3
    )

    if result.environment is None:
        # No environment - cannot determine, default to visible (defensive)
        logger.warning(
            f"Window {window.id}: No environment found, defaulting to visible"
        )
        return True

    # Use WindowEnvironment logic
    return result.environment.should_be_visible(active_project)


# Backward compatibility aliases (if migrating from old code)
# These can be removed once all references are updated
async def get_window_app_name(window: Con) -> Optional[str]:
    """Backward compatibility: Get app_name from environment."""
    app_name, _ = await get_window_identity(window)
    return app_name


async def get_window_app_id(window: Con) -> Optional[str]:
    """Backward compatibility: Get app_id from environment."""
    _, app_id = await get_window_identity(window)
    return app_id
