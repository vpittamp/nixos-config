"""
Test utility functions for environment variable-based window matching tests.

This module provides helper functions for:
- Reading process environment variables from /proc
- Finding windows by window class
- Launching test applications with environment
- Cleaning up test processes

These utilities are imported by test modules and shared across unit, integration,
performance, and scenario tests.
"""

import os
import signal
import subprocess
import time
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from i3ipc.aio import Connection


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

        # Decode with error handling
        text = data.decode("utf-8", errors="ignore")

        # Parse null-separated key=value pairs
        env_dict = {}
        for line in text.split("\0"):
            if "=" in line:
                key, value = line.split("=", 1)
                env_dict[key] = value

        return env_dict

    except FileNotFoundError:
        return {}
    except PermissionError:
        return {}
    except OSError:
        return {}


async def find_windows_by_class(conn: Connection, window_class: str) -> List:
    """
    Find all windows matching the given window class using Sway IPC.

    Args:
        conn: Async i3ipc Connection to Sway
        window_class: Window class to search for (e.g., "Code", "FFPWA-01...")

    Returns:
        List of window nodes matching the class

    Example:
        >>> windows = await find_windows_by_class(conn, "Code")
        >>> print(f"Found {len(windows)} VS Code windows")
    """
    tree = await conn.get_tree()

    def find_recursive(node, matches):
        """Recursively search tree for windows."""
        # Check if this is a window node
        if node.type == "con" and node.window:
            # Check both window_class (X11) and app_id (Wayland)
            if (hasattr(node, "window_class") and node.window_class == window_class) or \
               (hasattr(node, "app_id") and node.app_id == window_class):
                matches.append(node)

        # Recurse into child nodes
        if hasattr(node, "nodes"):
            for child in node.nodes:
                find_recursive(child, matches)
        if hasattr(node, "floating_nodes"):
            for child in node.floating_nodes:
                find_recursive(child, matches)

    matches = []
    find_recursive(tree, matches)
    return matches


def launch_test_app(
    cmd: List[str],
    env_vars: Optional[Dict[str, str]] = None,
    wait_for_startup: float = 0.5
) -> subprocess.Popen:
    """
    Launch a test application with custom environment variables.

    Args:
        cmd: Command to execute as list (e.g., ["sleep", "60"])
        env_vars: Optional dict of environment variables to inject
        wait_for_startup: Seconds to wait after launch (default: 0.5)

    Returns:
        Popen object for the launched process

    Example:
        >>> proc = launch_test_app(
        ...     ["sleep", "60"],
        ...     env_vars={"I3PM_APP_ID": "test-123", "I3PM_APP_NAME": "test-app"}
        ... )
        >>> print(proc.pid)
        12345
    """
    # Merge environment variables
    env = os.environ.copy()
    if env_vars:
        env.update(env_vars)

    # Launch process
    proc = subprocess.Popen(
        cmd,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True  # Prevent signal propagation
    )

    # Wait for process to initialize
    if wait_for_startup > 0:
        time.sleep(wait_for_startup)

    return proc


def cleanup_test_processes(processes: List[subprocess.Popen], timeout: float = 5.0):
    """
    Cleanup test processes by sending SIGTERM, then SIGKILL if needed.

    Args:
        processes: List of Popen objects to terminate
        timeout: Seconds to wait for graceful termination before SIGKILL

    Example:
        >>> processes = [proc1, proc2, proc3]
        >>> cleanup_test_processes(processes)
    """
    for proc in processes:
        try:
            # Send SIGTERM for graceful shutdown
            proc.terminate()

            try:
                # Wait for process to exit
                proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                # Force kill if not terminated
                proc.kill()
                proc.wait()

        except ProcessLookupError:
            # Process already terminated
            pass
        except OSError:
            # Other errors (e.g., permission denied)
            pass


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
        parts = stat.split(")")
        if len(parts) < 2:
            return None

        # Fields after process name
        fields = parts[1].strip().split()
        if len(fields) < 2:
            return None

        # PPID is the second field (index 1) after process name
        return int(fields[1])

    except (FileNotFoundError, ValueError, IndexError, OSError):
        return None


def create_process_hierarchy(
    depth: int = 3,
    env_vars: Optional[Dict[str, str]] = None
) -> Tuple[subprocess.Popen, List[int]]:
    """
    Create a process hierarchy for testing parent traversal.

    Args:
        depth: How many levels deep to create (default: 3 for grandchild)
        env_vars: Environment variables to set on root process

    Returns:
        Tuple of (root_process, [all_pids]) where all_pids includes all descendants

    Example:
        >>> root, pids = create_process_hierarchy(3, {"I3PM_APP_ID": "test"})
        >>> print(f"Created hierarchy with PIDs: {pids}")
        Created hierarchy with PIDs: [12345, 12346, 12347]
    """
    # Merge environment
    env = os.environ.copy()
    if env_vars:
        env.update(env_vars)

    # Build nested shell command that spawns children
    # Each level spawns the next with a sleep to keep alive
    if depth == 1:
        cmd = ["sleep", "60"]
    elif depth == 2:
        cmd = ["sh", "-c", "sleep 60 & wait"]
    else:  # depth >= 3
        # Create multi-level nesting
        nested_cmd = "sleep 60"
        for _ in range(depth - 1):
            nested_cmd = f"sh -c '{nested_cmd}' & wait"
        cmd = ["sh", "-c", nested_cmd]

    # Launch root process
    root_proc = subprocess.Popen(
        cmd,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True
    )

    # Wait for process tree to stabilize
    time.sleep(0.5)

    # Collect all PIDs in hierarchy
    pids = [root_proc.pid]

    # Get child PIDs (simple approach - find processes with our PID as parent)
    try:
        import psutil
        process = psutil.Process(root_proc.pid)
        for child in process.children(recursive=True):
            pids.append(child.pid)
    except ImportError:
        # Fallback: just use root PID if psutil not available
        pass

    return root_proc, pids
