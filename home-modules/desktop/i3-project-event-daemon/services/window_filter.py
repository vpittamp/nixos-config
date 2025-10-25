"""
Window filter service
Feature 035: Registry-Centric Project & Workspace Management

Reads /proc/<pid>/environ to determine window-to-project association.
Replaces tag-based filtering with environment variable approach.
"""

import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Dict

logger = logging.getLogger(__name__)


@dataclass
class WindowEnvironment:
    """Parsed I3PM_* environment variables from process"""

    app_id: str  # I3PM_APP_ID - unique instance identifier
    app_name: str  # I3PM_APP_NAME - registry application name
    project_name: str  # I3PM_PROJECT_NAME - project name or empty string
    project_dir: str  # I3PM_PROJECT_DIR - project directory or empty string
    scope: str  # I3PM_SCOPE - "scoped" or "global"
    active: bool  # I3PM_ACTIVE - true if project was active at launch
    launch_time: str  # I3PM_LAUNCH_TIME - unix timestamp
    launcher_pid: str  # I3PM_LAUNCHER_PID - wrapper script PID


def read_process_environ(pid: int) -> Dict[str, str]:
    """
    Read environment variables from /proc/<pid>/environ

    Args:
        pid: Process ID

    Returns:
        Dictionary of environment variables

    Raises:
        PermissionError: If cannot read /proc/<pid>/environ (different user)
        FileNotFoundError: If process does not exist
    """
    environ_path = Path(f"/proc/{pid}/environ")

    try:
        # Read null-terminated environment strings
        with open(environ_path, "rb") as f:
            environ_data = f.read()

        # Split on null bytes and parse key=value pairs
        env_dict = {}
        for pair in environ_data.split(b"\0"):
            if b"=" in pair:
                key, value = pair.split(b"=", 1)
                try:
                    env_dict[key.decode("utf-8")] = value.decode("utf-8")
                except UnicodeDecodeError:
                    # Skip variables with invalid UTF-8
                    logger.debug(f"Skipping env var with invalid UTF-8 in PID {pid}")
                    continue

        logger.debug(f"Read {len(env_dict)} environment variables from PID {pid}")
        return env_dict

    except PermissionError as e:
        logger.warning(f"Permission denied reading /proc/{pid}/environ: {e}")
        raise
    except FileNotFoundError as e:
        logger.debug(f"Process {pid} not found (may have exited): {e}")
        raise


def get_window_pid(window_id: int) -> Optional[int]:
    """
    Get process ID for window using xprop

    i3ipc library's node.pid is unreliable (often returns None).
    xprop provides direct access to _NET_WM_PID property.

    Args:
        window_id: X11 window ID

    Returns:
        Process ID or None if not available

    Performance: ~10-20ms per call
    """
    try:
        result = subprocess.run(
            ["xprop", "-id", str(window_id), "_NET_WM_PID"],
            capture_output=True,
            text=True,
            timeout=1.0,  # 1 second timeout
        )

        if result.returncode != 0:
            logger.debug(f"xprop failed for window {window_id}: {result.stderr}")
            return None

        # Parse output: "_NET_WM_PID(CARDINAL) = 12345"
        output = result.stdout.strip()
        if " = " in output:
            pid_str = output.split(" = ")[1]
            return int(pid_str)

        logger.debug(f"Could not parse xprop output for window {window_id}: {output}")
        return None

    except subprocess.TimeoutExpired:
        logger.warning(f"xprop timeout for window {window_id}")
        return None
    except (ValueError, IndexError) as e:
        logger.warning(f"Failed to parse PID from xprop output: {e}")
        return None
    except FileNotFoundError:
        logger.error("xprop command not found. Install x11-utils package.")
        return None


def parse_window_environment(env: Dict[str, str]) -> Optional[WindowEnvironment]:
    """
    Parse I3PM_* environment variables into structured data

    Args:
        env: Environment dictionary from /proc/<pid>/environ

    Returns:
        WindowEnvironment if I3PM_* variables present, None otherwise
    """
    # Check for required I3PM_* variables
    if "I3PM_APP_ID" not in env or "I3PM_APP_NAME" not in env:
        return None

    try:
        return WindowEnvironment(
            app_id=env["I3PM_APP_ID"],
            app_name=env["I3PM_APP_NAME"],
            project_name=env.get("I3PM_PROJECT_NAME", ""),
            project_dir=env.get("I3PM_PROJECT_DIR", ""),
            scope=env.get("I3PM_SCOPE", "global"),
            active=env.get("I3PM_ACTIVE", "false").lower() == "true",
            launch_time=env.get("I3PM_LAUNCH_TIME", ""),
            launcher_pid=env.get("I3PM_LAUNCHER_PID", ""),
        )
    except (KeyError, ValueError) as e:
        logger.warning(f"Failed to parse I3PM environment variables: {e}")
        return None


async def get_window_environment(window_id: int) -> Optional[WindowEnvironment]:
    """
    Get I3PM environment variables for a window

    Combines get_window_pid() and read_process_environ() with error handling.

    Args:
        window_id: X11 window ID

    Returns:
        WindowEnvironment if available, None otherwise (fallback to global scope)
    """
    # Get PID via xprop
    pid = get_window_pid(window_id)
    if pid is None:
        logger.debug(f"No PID found for window {window_id}, assuming global scope")
        return None

    # Read /proc environment
    try:
        env = read_process_environ(pid)
    except (PermissionError, FileNotFoundError):
        logger.debug(f"Cannot read environment for PID {pid}, assuming global scope")
        return None

    # Parse I3PM_* variables
    window_env = parse_window_environment(env)
    if window_env is None:
        logger.debug(f"No I3PM variables found for PID {pid}, assuming global scope")
        return None

    logger.info(
        f"Window {window_id} (PID {pid}): app={window_env.app_name}, "
        f"project={window_env.project_name or 'none'}, scope={window_env.scope}"
    )
    return window_env


async def filter_windows_by_project(
    conn,  # i3ipc.aio.Connection
    active_project: Optional[str],
) -> Dict[str, int]:
    """
    Filter windows based on project association via /proc environment reading

    Shows windows that match the active project, hides windows from other projects.
    Global scope windows are always visible.

    Args:
        conn: i3ipc async connection
        active_project: Active project name or None for global mode

    Returns:
        Dictionary with "visible", "hidden", "errors" counts
    """
    tree = await conn.get_tree()
    windows = tree.leaves()

    visible_count = 0
    hidden_count = 0
    error_count = 0

    logger.info(f"Filtering {len(windows)} windows for project '{active_project or 'none'}'")

    for window in windows:
        window_id = window.window  # X11 window ID

        # Get window environment
        window_env = await get_window_environment(window_id)

        # Determine visibility
        should_show = False
        if window_env is None:
            # No I3PM environment → global scope → always visible
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): global (no I3PM)")
        elif window_env.scope == "global":
            # Global scope apps always visible
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): global scope")
        elif active_project is None:
            # No active project → hide scoped windows
            should_show = False
            logger.debug(f"Window {window_id} ({window.window_class}): hide (no active project)")
        elif window_env.project_name == active_project:
            # Project match → show
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): show (project match)")
        else:
            # Different project → hide
            should_show = False
            logger.debug(
                f"Window {window_id} ({window.window_class}): hide "
                f"(project mismatch: {window_env.project_name} != {active_project})"
            )

        # Apply visibility
        try:
            if should_show:
                # Ensure window is not in scratchpad
                if "[__i3_scratch]" in [w.name for w in window.workspace()]:
                    await conn.command(f'[id={window_id}] move workspace current')
                visible_count += 1
            else:
                # Move to scratchpad to hide
                await conn.command(f'[id={window_id}] move scratchpad')
                hidden_count += 1
        except Exception as e:
            logger.error(f"Failed to update window {window_id} visibility: {e}")
            error_count += 1

    logger.info(
        f"Window filtering complete: {visible_count} visible, {hidden_count} hidden, "
        f"{error_count} errors"
    )

    return {
        "visible": visible_count,
        "hidden": hidden_count,
        "errors": error_count,
    }
