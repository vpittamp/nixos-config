"""
App detection service for idempotent layout restoration

Feature 075: Idempotent Layout Restoration
Tasks: T006-T009 (Core Detection System)

This module provides app detection by reading I3PM_APP_NAME from window environments.
Detection is O(W) where W = number of windows, typically <10ms for 16 windows.
"""

import asyncio
import logging
import time
from pathlib import Path
from typing import Optional

from i3ipc.aio import Connection

logger = logging.getLogger(__name__)


async def detect_running_apps() -> set[str]:
    """Detect running apps by reading I3PM_APP_NAME from window environments.

    Feature 075: T006 (Core Detection System)

    This function:
    1. Queries Sway tree for all windows with PIDs
    2. Reads /proc/<pid>/environ for each window
    3. Extracts I3PM_APP_NAME from environment variables
    4. Returns set of unique app names

    Performance: <10ms for 16 windows (validated in research phase)
    Accuracy: 100% for apps launched via app-registry wrapper

    Returns:
        set[str]: Unique app names currently running (e.g., {"terminal", "lazygit", "chatgpt-pwa"})

    Errors:
        - FileNotFoundError: Process died between tree query and environ read (skipped gracefully)
        - PermissionError: Cannot read process environ (skipped gracefully)

    Example:
        >>> running = await detect_running_apps()
        >>> print(running)
        {'terminal', 'chatgpt-pwa', 'lazygit'}
    """
    start_time = time.time()

    # Connect to Sway IPC and get window tree
    conn = await Connection(auto_reconnect=True).connect()
    tree = await conn.get_tree()

    running_apps = set()
    windows_scanned = 0

    # Walk tree to find all windows with PIDs
    def walk_tree(node):
        """Recursively walk Sway tree to find leaf nodes (windows) with PIDs"""
        nonlocal windows_scanned

        # Leaf node with PID = actual window
        if node.pid and node.pid > 0:
            windows_scanned += 1
            app_name = _read_app_name_from_environ(node.pid)
            if app_name:
                running_apps.add(app_name)

        # Recurse into children
        for child in (node.nodes + node.floating_nodes):
            walk_tree(child)

    walk_tree(tree)

    # Calculate detection time
    elapsed_ms = (time.time() - start_time) * 1000

    # T009: Log detection metrics
    logger.debug(
        f"detect_running_apps: scanned {windows_scanned} windows, "
        f"found {len(running_apps)} unique apps in {elapsed_ms:.2f}ms"
    )
    logger.info(f"Running apps detected: {sorted(running_apps)}")

    return running_apps


def _read_app_name_from_environ(pid: int) -> Optional[str]:
    """Read I3PM_APP_NAME from process environment.

    Feature 075: T007-T008 (Error handling)

    Args:
        pid: Process ID to inspect

    Returns:
        App name from I3PM_APP_NAME environment variable, or None if:
        - Process has died (FileNotFoundError)
        - Permission denied (PermissionError)
        - I3PM_APP_NAME not set in environment
        - Environment file is malformed

    Example:
        >>> app_name = _read_app_name_from_environ(224082)
        >>> print(app_name)
        'lazygit'
    """
    try:
        # T007: Handle dead processes gracefully
        environ_path = Path(f"/proc/{pid}/environ")
        environ_bytes = environ_path.read_bytes()

        # Parse null-terminated environment strings
        environ_text = environ_bytes.decode('utf-8', errors='ignore')
        env_vars = {}

        for entry in environ_text.split('\0'):
            if '=' in entry:
                key, value = entry.split('=', 1)
                env_vars[key] = value

        # Return I3PM_APP_NAME if present
        return env_vars.get('I3PM_APP_NAME')

    except FileNotFoundError:
        # T007: Process died between tree query and environ read - skip gracefully
        logger.debug(f"Process {pid} environment not found (process may have died)")
        return None

    except PermissionError:
        # T008: Permission denied reading process environ - skip gracefully
        logger.warning(f"Permission denied reading environment for PID {pid}")
        return None

    except Exception as e:
        # Unexpected error - log but don't crash
        logger.error(f"Unexpected error reading environment for PID {pid}: {e}")
        return None
