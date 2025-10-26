"""
Window filter service
Feature 035: Registry-Centric Project & Workspace Management

Reads /proc/<pid>/environ to determine window-to-project association.
Replaces tag-based filtering with environment variable approach.
"""

import logging
import subprocess
import time
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
    target_workspace: Optional[int] = None  # I3PM_TARGET_WORKSPACE - preferred workspace number (Feature 039 T060)


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


def get_parent_pid(pid: int) -> Optional[int]:
    """
    Get parent process ID from /proc/<pid>/stat.

    Feature 039 T071: Parent process traversal for environment inheritance.

    Args:
        pid: Child process ID

    Returns:
        Parent process ID or None if not available
    """
    try:
        stat_path = Path(f"/proc/{pid}/stat")
        stat_data = stat_path.read_text()

        # /proc/<pid>/stat format: pid (comm) state ppid ...
        # Extract ppid (4th field)
        parts = stat_data.split()
        if len(parts) >= 4:
            ppid = int(parts[3])
            return ppid if ppid > 1 else None  # Don't traverse to init (PID 1)

        return None

    except (FileNotFoundError, ValueError, IndexError) as e:
        logger.debug(f"Failed to get parent PID for {pid}: {e}")
        return None


def read_process_environ_with_fallback(pid: int, max_depth: int = 3) -> Dict[str, str]:
    """
    Read process environment with parent process fallback.

    Feature 039 T071: If child process has no I3PM_* variables, traverse
    up to parent process to find them (handles edge cases where child
    doesn't inherit environment).

    Args:
        pid: Process ID
        max_depth: Maximum parent traversal depth (default 3)

    Returns:
        Environment dictionary (may be empty if no I3PM vars found)
    """
    current_pid = pid
    depth = 0

    while current_pid and depth < max_depth:
        try:
            env = read_process_environ(current_pid)

            # Check if environment has I3PM variables
            if "I3PM_APP_ID" in env or "I3PM_APP_NAME" in env:
                if current_pid != pid:
                    logger.debug(
                        f"Found I3PM environment in parent PID {current_pid} "
                        f"(traversed {depth} levels from PID {pid})"
                    )
                return env

            # Try parent process
            parent_pid = get_parent_pid(current_pid)
            if parent_pid == current_pid:
                break  # Avoid infinite loop

            current_pid = parent_pid
            depth += 1

        except (FileNotFoundError, PermissionError):
            # Process exited or permission denied
            break

    # No I3PM environment found
    logger.debug(f"No I3PM environment found for PID {pid} (traversed {depth} parents)")
    return {}


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
        # Feature 039 T060: Parse I3PM_TARGET_WORKSPACE as integer
        target_workspace = None
        if "I3PM_TARGET_WORKSPACE" in env:
            try:
                target_workspace = int(env["I3PM_TARGET_WORKSPACE"])
            except ValueError:
                logger.warning(
                    f"Invalid I3PM_TARGET_WORKSPACE value: {env['I3PM_TARGET_WORKSPACE']}, "
                    "expected integer"
                )

        return WindowEnvironment(
            app_id=env["I3PM_APP_ID"],
            app_name=env["I3PM_APP_NAME"],
            project_name=env.get("I3PM_PROJECT_NAME", ""),
            project_dir=env.get("I3PM_PROJECT_DIR", ""),
            scope=env.get("I3PM_SCOPE", "global"),
            active=env.get("I3PM_ACTIVE", "false").lower() == "true",
            launch_time=env.get("I3PM_LAUNCH_TIME", ""),
            launcher_pid=env.get("I3PM_LAUNCHER_PID", ""),
            target_workspace=target_workspace,
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
    workspace_tracker=None,  # Optional WorkspaceTracker for Feature 038
) -> Dict[str, int]:
    """
    Filter windows based on project association via i3 window marks

    Shows windows that match the active project, hides windows from other projects.
    Windows without project marks are treated as global (always visible).

    Feature 038: Preserves window state (tiling/floating, workspace, geometry, scratchpad origin)

    Args:
        conn: i3ipc async connection
        active_project: Active project name or None for global mode
        workspace_tracker: WorkspaceTracker instance for state persistence (Feature 038)

    Returns:
        Dictionary with "visible", "hidden", "errors" counts
    """
    # Feature 038 T042: Performance measurement
    operation_start = time.perf_counter()

    tree = await conn.get_tree()
    windows = tree.leaves()

    visible_count = 0
    hidden_count = 0
    error_count = 0

    logger.info(f"Filtering {len(windows)} windows for project '{active_project or 'none'}'")

    for window in windows:
        # Feature 038 T042: Per-window performance tracking
        window_start = time.perf_counter()

        window_id = window.window  # X11 window ID

        # Get project from window marks (format: project:PROJECT_NAME:WINDOW_ID)
        window_project = None
        for mark in window.marks:
            if mark.startswith("project:"):
                mark_parts = mark.split(":")
                window_project = mark_parts[1] if len(mark_parts) >= 2 else None
                break

        # Determine visibility
        should_show = False
        if window_project is None:
            # No project mark → global scope → always visible
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): global (no project mark)")
        elif active_project is None:
            # No active project → hide scoped windows
            should_show = False
            logger.debug(f"Window {window_id} ({window.window_class}): hide (no active project)")
        elif window_project == active_project:
            # Project match → show
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): show (project match: {window_project})")
        else:
            # Different project → hide
            should_show = False
            logger.debug(
                f"Window {window_id} ({window.window_class}): hide "
                f"(project mismatch: {window_project} != {active_project})"
            )

        # Apply visibility
        try:
            if should_show:
                # Check if window is currently in scratchpad
                workspace = window.workspace()
                in_scratchpad = workspace and workspace.name == "__i3_scratch"

                logger.debug(
                    f"Window {window_id} should show: workspace={workspace.name if workspace else 'None'}, "
                    f"in_scratchpad={in_scratchpad}"
                )

                if in_scratchpad:
                    # Feature 038: Restore window to exact workspace with correct floating state
                    logger.info(f"Restoring window {window_id} ({window.window_class}) from scratchpad")

                    # Load saved state if workspace_tracker available
                    saved_state = None
                    if workspace_tracker:
                        saved_state = await workspace_tracker.get_window_workspace(window_id)

                    if saved_state:
                        # Restore to exact workspace number (not current!)
                        workspace_num = saved_state.get("workspace_number", 1)
                        is_floating = saved_state.get("floating", False)
                        original_scratchpad = saved_state.get("original_scratchpad", False)

                        # Feature 038 P3: Don't restore windows originally in scratchpad
                        if original_scratchpad:
                            logger.debug(f"Window {window_id} was originally in scratchpad, leaving hidden")
                            continue  # Skip restoration

                        logger.info(
                            f"Restoring window {window_id} to workspace {workspace_num}, "
                            f"floating={is_floating}"
                        )

                        # Move to exact workspace number (Feature 038 US3)
                        await conn.command(f'[id={window_id}] move workspace number {workspace_num}')

                        # Restore floating state (Feature 038 US1)
                        if is_floating:
                            await conn.command(f'[id={window_id}] floating enable')

                            # Feature 038 US2: Restore geometry for floating windows
                            geometry = saved_state.get("geometry")
                            if geometry and all(k in geometry for k in ["x", "y", "width", "height"]):
                                # Apply geometry restoration (position and size)
                                logger.debug(
                                    f"Restoring geometry for window {window_id}: "
                                    f"position=({geometry['x']}, {geometry['y']}), "
                                    f"size={geometry['width']}x{geometry['height']}"
                                )

                                # Note: Must enable floating BEFORE applying geometry (T024)
                                # Resize and move in single command for atomicity
                                await conn.command(
                                    f'[id={window_id}] '
                                    f'resize set {geometry["width"]} px {geometry["height"]} px, '
                                    f'move position {geometry["x"]} px {geometry["y"]} px'
                                )
                        else:
                            await conn.command(f'[id={window_id}] floating disable')
                    else:
                        # Fallback: restore to workspace 1 if no saved state
                        logger.warning(f"No saved state for window {window_id}, restoring to workspace 1")
                        await conn.command(f'[id={window_id}] move workspace number 1')
                else:
                    logger.debug(f"Window {window_id} already visible")

                visible_count += 1
            else:
                # Feature 038: Capture window state BEFORE hiding
                workspace = window.workspace()
                logger.debug(
                    f"Hiding window {window_id} ({window.window_class}): "
                    f"current workspace={workspace.name if workspace else 'None'}"
                )

                # Capture state for Feature 038 (US1, US2, US3, US4)
                if workspace_tracker and workspace:
                    # Get current window state
                    workspace_num = workspace.num if workspace.num is not None else 1
                    is_original_scratchpad = workspace.name == "__i3_scratch"

                    # Feature 038 FIX: Check if we already have saved state for this window
                    # If so, preserve the ORIGINAL floating state (don't re-capture after scratchpad moves)
                    saved_state = await workspace_tracker.get_window_workspace(window_id)
                    if saved_state and not is_original_scratchpad:
                        # Preserve original floating state from first capture
                        is_floating = saved_state.get("floating", False)
                        geometry = saved_state.get("geometry", None)
                        logger.debug(
                            f"Window {window_id} already tracked, preserving original state: "
                            f"floating={is_floating}, has_geometry={geometry is not None}"
                        )
                    else:
                        # First capture OR window is from scratchpad - capture current state
                        is_floating = window.floating in ["user_on", "auto_on"]

                        # Feature 038 US2: Capture geometry for floating windows
                        geometry = None
                        if is_floating and window.rect:
                            geometry = {
                                "x": window.rect.x,
                                "y": window.rect.y,
                                "width": window.rect.width,
                                "height": window.rect.height,
                            }
                            logger.debug(
                                f"Captured geometry for floating window {window_id}: "
                                f"x={geometry['x']}, y={geometry['y']}, "
                                f"width={geometry['width']}, height={geometry['height']}"
                            )

                    # Get window class and project name for tracking
                    window_class = window.window_class or "unknown"
                    window_project = window_project or "unknown"  # From earlier parsing

                    logger.info(
                        f"Capturing state for window {window_id}: workspace={workspace_num}, "
                        f"floating={is_floating}, original_scratchpad={is_original_scratchpad}, "
                        f"has_geometry={geometry is not None}, "
                        f"preserved_state={saved_state is not None}"
                    )

                    # Save state with geometry for floating windows
                    await workspace_tracker.track_window(
                        window_id=window_id,
                        workspace_number=workspace_num,
                        floating=is_floating,
                        project_name=window_project,
                        app_name=window_class,  # Use window_class as fallback
                        window_class=window_class,
                        geometry=geometry,  # Feature 038 US2: Geometry for floating windows
                        original_scratchpad=is_original_scratchpad,
                    )

                # Move to scratchpad
                await conn.command(f'[id={window_id}] move scratchpad')
                hidden_count += 1
        except Exception as e:
            logger.error(f"Failed to update window {window_id} visibility: {e}")
            error_count += 1
        finally:
            # Feature 038 T042: Log per-window timing (target <50ms per window)
            window_duration_ms = (time.perf_counter() - window_start) * 1000
            if window_duration_ms > 50:
                logger.warning(
                    f"Window {window_id} filter operation took {window_duration_ms:.1f}ms (target <50ms)"
                )
            else:
                logger.debug(f"Window {window_id} processed in {window_duration_ms:.1f}ms")

    # Feature 038 T042: Overall operation performance
    operation_duration_ms = (time.perf_counter() - operation_start) * 1000
    avg_per_window_ms = operation_duration_ms / len(windows) if windows else 0

    logger.info(
        f"Window filtering complete: {visible_count} visible, {hidden_count} hidden, "
        f"{error_count} errors | Total: {operation_duration_ms:.1f}ms, "
        f"Avg: {avg_per_window_ms:.1f}ms/window"
    )

    return {
        "visible": visible_count,
        "hidden": hidden_count,
        "errors": error_count,
        "duration_ms": operation_duration_ms,
        "avg_per_window_ms": avg_per_window_ms,
    }
