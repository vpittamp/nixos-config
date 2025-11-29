"""
Window filter service
Feature 035: Registry-Centric Project & Workspace Management
Feature 091: Optimize i3pm Project Switching Performance

Reads /proc/<pid>/environ to determine window-to-project association.
Replaces tag-based filtering with environment variable approach.

Feature 091: Parallel command execution using asyncio.gather() for <200ms project switching.
"""

import asyncio
import logging
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Dict
from datetime import datetime

# Feature 091: Import performance optimization services
from ..models.window_command import WindowCommand, CommandBatch, CommandType
from ..models.performance_metrics import OperationMetrics, ProjectSwitchMetrics
from .command_batch import CommandBatchService
from .tree_cache import TreeCacheService, get_tree_cache
from .performance_tracker import PerformanceTrackerService, get_performance_tracker

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
    Feature 091: Parallel command execution for <200ms project switching

    Args:
        conn: i3ipc async connection
        active_project: Active project name or None for global mode
        workspace_tracker: WorkspaceTracker instance for state persistence (Feature 038)

    Returns:
        Dictionary with "visible", "hidden", "errors" counts
    """
    # Feature 091: Performance measurement with high precision
    operation_start = time.perf_counter()
    operation_start_dt = datetime.now()

    # Feature 091: Use tree cache to eliminate duplicate queries
    tree_cache = get_tree_cache()
    if tree_cache:
        tree = await tree_cache.get_tree()
        cache_hits = 1 if tree_cache.is_cached else 0
        cache_misses = 0 if tree_cache.is_cached else 1
    else:
        # Fallback: Direct get_tree() if cache not initialized
        tree = await conn.get_tree()
        cache_hits = 0
        cache_misses = 1

    windows = tree.leaves()

    # Feature 046: Include scratchpad windows for restoration
    scratchpad = tree.scratchpad()
    scratchpad_windows = []
    if scratchpad:
        scratchpad_windows = scratchpad.floating_nodes
        logger.debug(f"Found {len(scratchpad_windows)} windows in scratchpad")
        windows.extend(scratchpad_windows)

    logger.info(
        f"[Feature 091] Filtering {len(windows)} windows "
        f"({len(windows) - len(scratchpad_windows)} visible + {len(scratchpad_windows)} scratchpad) "
        f"for project '{active_project or 'none'}'"
    )

    # Feature 091: Build command lists for parallel execution
    hide_commands: list[WindowCommand] = []
    restore_batches: list[CommandBatch] = []
    windows_to_track: list[tuple] = []  # (window_id, workspace_num, is_floating, geometry, window_project, window_class, is_original_scratchpad)

    visible_count = 0
    hidden_count = 0
    error_count = 0

    # Phase 1: Classify windows and build command lists (no execution yet)
    for window in windows:
        window_id = window.id

        # Get project and scope from window marks
        # Note: PROJECT may contain colons for worktree qualified names
        # e.g., "scratchpad:vpittamp/nixos-config:101-worktree-click-switch"
        # e.g., "scoped:vpittamp/nixos-config:101-worktree-click-switch:21"
        window_project = None
        window_scope = None
        for mark in window.marks:
            if mark.startswith("scratchpad:"):
                # Feature 062: Scratchpad terminals are project-scoped
                # Format: scratchpad:PROJECT where PROJECT may contain colons
                # e.g., "scratchpad:vpittamp/nixos-config:main"
                # Feature 101: Extract full qualified name after "scratchpad:"
                window_project = mark[len("scratchpad:"):]
                window_scope = "scoped"
                logger.debug(f"Window {window_id} is scratchpad terminal for project: {window_project}")
                break
            elif mark.startswith("scoped:") or mark.startswith("global:"):
                # Format: SCOPE:PROJECT:WINDOW_ID where PROJECT may contain colons
                # e.g., "scoped:vpittamp/nixos-config:101-worktree-click-switch:21"
                mark_parts = mark.split(":")
                window_scope = mark_parts[0]
                # Feature 101: Join parts 1 through n-1 to preserve worktree qualified name
                if len(mark_parts) >= 4:
                    # Worktree format: scope:account/repo:branch:window_id
                    window_project = ":".join(mark_parts[1:-1])
                elif len(mark_parts) >= 3:
                    # Legacy format: scope:project:window_id
                    window_project = mark_parts[1]
                break

        # Determine visibility
        should_show = False
        if window_project is None:
            # No project mark → global scope → always visible
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): global (no project mark)")
        elif window_scope == "global":
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): global (explicit scope)")
        elif active_project is None:
            should_show = False
            logger.debug(f"Window {window_id} ({window.window_class}): hide (no active project)")
        elif window_project == active_project:
            should_show = True
            logger.debug(f"Window {window_id} ({window.window_class}): show (project match: {window_project})")
        else:
            should_show = False
            logger.debug(
                f"Window {window_id} ({window.window_class}): hide "
                f"(project mismatch: {window_project} != {active_project})"
            )

        # Build commands (Feature 091: defer execution for parallel batch)
        try:
            if should_show:
                # Check if window is currently in scratchpad
                workspace = window.workspace()
                in_scratchpad = workspace and workspace.name == "__i3_scratch"

                if in_scratchpad:
                    # Feature 091: Build restore command batch
                    logger.info(f"Building restore commands for window {window_id} ({window.window_class})")

                    # Load saved state if workspace_tracker available
                    saved_state = None
                    if workspace_tracker:
                        saved_state = await workspace_tracker.get_window_workspace(window_id)

                    if saved_state:
                        workspace_num = saved_state.get("workspace_number", 1)
                        is_floating = saved_state.get("floating", False)
                        original_scratchpad = saved_state.get("original_scratchpad", False)

                        # Feature 038 P3: Skip windows originally in scratchpad
                        if original_scratchpad:
                            logger.debug(f"Window {window_id} was originally in scratchpad, skipping")
                            continue

                        geometry = saved_state.get("geometry") if is_floating else None

                        # Feature 091: Use CommandBatch factory for restoration
                        batch = CommandBatch.from_window_state(
                            window_id=window_id,
                            workspace_num=workspace_num,
                            is_floating=is_floating,
                            geometry=geometry,
                        )
                        restore_batches.append(batch)
                        logger.debug(
                            f"Queued restore batch for window {window_id}: workspace={workspace_num}, "
                            f"floating={is_floating}, has_geometry={geometry is not None}"
                        )
                    else:
                        # Fallback: restore to workspace 1
                        logger.warning(f"No saved state for window {window_id}, restoring to workspace 1")
                        batch = CommandBatch.from_window_state(
                            window_id=window_id,
                            workspace_num=1,
                            is_floating=False,
                            geometry=None,
                        )
                        restore_batches.append(batch)
                else:
                    logger.debug(f"Window {window_id} already visible")

                visible_count += 1
            else:
                # Feature 091: Build hide command and capture state
                workspace = window.workspace()

                # Capture state for Feature 038
                if workspace_tracker and workspace:
                    workspace_num = workspace.num if workspace.num is not None else 1

                    # Feature 062: Scratchpad terminals should NEVER be marked as original_scratchpad
                    has_scratchpad_mark = any(mark.startswith("scratchpad:") for mark in window.marks)
                    is_original_scratchpad = (workspace.name == "__i3_scratch") and not has_scratchpad_mark

                    # Feature 038 FIX: Preserve original state if already tracked
                    saved_state = await workspace_tracker.get_window_workspace(window_id)
                    if saved_state and not is_original_scratchpad:
                        is_floating = saved_state.get("floating", False)
                        geometry = saved_state.get("geometry", None)
                    else:
                        is_floating = window.floating in ["user_on", "auto_on"]
                        geometry = None
                        if is_floating and window.rect:
                            geometry = {
                                "x": window.rect.x,
                                "y": window.rect.y,
                                "width": window.rect.width,
                                "height": window.rect.height,
                            }

                    window_class = window.window_class or "unknown"
                    window_project_name = window_project or "unknown"

                    # Queue state tracking (will be executed before hide commands)
                    windows_to_track.append((
                        window_id,
                        workspace_num,
                        is_floating,
                        geometry,
                        window_project_name,
                        window_class,
                        is_original_scratchpad,
                    ))

                # Feature 091: Queue hide command for parallel execution
                hide_cmd = WindowCommand(
                    window_id=window_id,
                    command_type=CommandType.MOVE_SCRATCHPAD,
                    params={},
                )
                hide_commands.append(hide_cmd)
                hidden_count += 1
                logger.debug(f"Queued hide command for window {window_id}")
        except Exception as e:
            logger.error(f"Failed to process window {window_id}: {e}")
            error_count += 1

    # Feature 091: Phase 2 - Execute commands in parallel batches
    classification_duration_ms = (time.perf_counter() - operation_start) * 1000
    logger.info(
        f"[Feature 091] Phase 1 complete ({classification_duration_ms:.1f}ms): "
        f"{len(hide_commands)} hide commands, {len(restore_batches)} restore batches queued"
    )

    # Track state for windows being hidden (must happen before hide commands)
    if workspace_tracker and windows_to_track:
        for window_data in windows_to_track:
            (window_id, workspace_num, is_floating, geometry,
             window_project_name, window_class, is_original_scratchpad) = window_data
            await workspace_tracker.track_window(
                window_id=window_id,
                workspace_number=workspace_num,
                floating=is_floating,
                project_name=window_project_name,
                app_name=window_class,
                window_class=window_class,
                geometry=geometry,
                original_scratchpad=is_original_scratchpad,
            )

    # Feature 091: Initialize command batch service
    batch_service = CommandBatchService(conn)
    hide_metrics = None
    restore_metrics = None

    # Execute hide commands in parallel
    if hide_commands:
        hide_start = time.perf_counter()
        hide_results, hide_metrics = await batch_service.execute_parallel(
            hide_commands, operation_type="hide"
        )
        hide_duration_ms = (time.perf_counter() - hide_start) * 1000
        hide_metrics.cache_hits = cache_hits
        hide_metrics.cache_misses = cache_misses

        hide_failures = sum(1 for r in hide_results if not r.success)
        if hide_failures > 0:
            error_count += hide_failures
            logger.warning(f"[Feature 091] {hide_failures}/{len(hide_commands)} hide commands failed")

    # Execute restore commands in parallel (as batched commands)
    if restore_batches:
        restore_start = time.perf_counter()

        # Feature 091: Execute all restore batches in parallel using asyncio.gather()
        # Each batch contains sequential commands for ONE window (move, floating, resize, position)
        # But we execute ALL window batches concurrently for maximum performance
        restore_tasks = [batch_service.execute_batch(batch) for batch in restore_batches]
        restore_results_with_metrics = await asyncio.gather(*restore_tasks, return_exceptions=True)

        # Extract results and handle exceptions
        restore_results = []
        for i, result_tuple in enumerate(restore_results_with_metrics):
            if isinstance(result_tuple, Exception):
                logger.error(f"[Feature 091] Restore batch {i} failed: {result_tuple}")
                restore_results.append(
                    type('Result', (), {'success': False, 'error': str(result_tuple)})()
                )
            else:
                result, _ = result_tuple
                restore_results.append(result)

        restore_duration_ms = (time.perf_counter() - restore_start) * 1000

        # Create restore metrics
        restore_metrics = OperationMetrics(
            operation_type="restore",
            start_time=datetime.now(),
            end_time=datetime.now(),
            duration_ms=restore_duration_ms,
            window_count=len(restore_batches),
            command_count=sum(len(b.commands) for b in restore_batches),
            parallel_batches=len(restore_batches),
            cache_hits=cache_hits,
            cache_misses=cache_misses,
        )

        restore_failures = sum(1 for r in restore_results if not r.success)
        if restore_failures > 0:
            error_count += restore_failures
            logger.warning(f"[Feature 091] {restore_failures}/{len(restore_batches)} restore batches failed")

    # Calculate total performance
    operation_duration_ms = (time.perf_counter() - operation_start) * 1000
    operation_end_dt = datetime.now()

    # Feature 091: Track performance metrics
    if hide_metrics or restore_metrics:
        switch_metrics = ProjectSwitchMetrics(
            project_from=None,  # Set by caller if available
            project_to=active_project,
            total_duration_ms=operation_duration_ms,
            hide_metrics=hide_metrics,
            restore_metrics=restore_metrics,
            timestamp=operation_end_dt,
        )

        # Record in performance tracker if available
        perf_tracker = get_performance_tracker()
        if perf_tracker:
            perf_tracker.record_switch(switch_metrics)

    logger.info(
        f"[Feature 091] Window filtering complete: {visible_count} visible, {hidden_count} hidden, "
        f"{error_count} errors | Total: {operation_duration_ms:.1f}ms "
        f"({'✓ TARGET MET' if operation_duration_ms < 200 else '✗ SLOW'})"
    )

    return {
        "visible": visible_count,
        "hidden": hidden_count,
        "errors": error_count,
        "duration_ms": operation_duration_ms,
        "avg_per_window_ms": operation_duration_ms / len(windows) if windows else 0,
    }
