"""Sway IPC helper for window discovery.

This module provides utilities for querying Sway to find window information,
particularly for correlating AI sessions with their originating terminal windows.

Feature 135: Added PID-based window correlation via I3PM_* environment variables.
"""

import json
import logging
import os
import socket
from glob import glob
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


def get_sway_socket() -> Optional[str]:
    """Find the Sway IPC socket path.

    Returns:
        Socket path if found, None otherwise
    """
    # First try SWAYSOCK environment variable
    swaysock = os.environ.get("SWAYSOCK")
    if swaysock and os.path.exists(swaysock):
        return swaysock

    # Fallback: search for socket in runtime dir
    uid = os.getuid()
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    pattern = os.path.join(runtime_dir, "sway-ipc.*.sock")
    sockets = glob(pattern)

    if sockets:
        return sockets[0]

    return None


def sway_ipc(msg_type: int, payload: str = "") -> Optional[dict]:
    """Send a message to Sway and receive response.

    Args:
        msg_type: IPC message type (0=RUN_COMMAND, 4=GET_TREE, etc.)
        payload: Optional command payload

    Returns:
        Parsed JSON response or None on error
    """
    socket_path = get_sway_socket()
    if not socket_path:
        logger.debug("Sway socket not found")
        return None

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect(socket_path)

        # Build IPC message: magic + length + type + payload
        payload_bytes = payload.encode("utf-8")
        msg = b"i3-ipc" + len(payload_bytes).to_bytes(4, "little") + msg_type.to_bytes(4, "little") + payload_bytes
        sock.sendall(msg)

        # Read response header
        header = sock.recv(14)
        if len(header) < 14:
            return None

        # Parse header: magic (6) + length (4) + type (4)
        resp_len = int.from_bytes(header[6:10], "little")

        # Read response body
        body = b""
        while len(body) < resp_len:
            chunk = sock.recv(resp_len - len(body))
            if not chunk:
                break
            body += chunk

        sock.close()
        return json.loads(body.decode("utf-8"))
    except Exception as e:
        logger.debug(f"Sway IPC error: {e}")
        return None


def get_focused_window_id() -> Optional[int]:
    """Get the Sway container ID of the currently focused window.

    Returns:
        Window container ID (con_id) or None if not found
    """
    tree = sway_ipc(4)  # GET_TREE = 4
    if not tree:
        return None

    return _find_focused_window(tree)


def _find_focused_window(node: dict) -> Optional[int]:
    """Recursively find the focused window in the Sway tree.

    Args:
        node: Sway tree node

    Returns:
        Container ID of focused window or None
    """
    # Check if this node is a focused window (has pid means it's a window)
    if node.get("focused") and node.get("pid"):
        return node.get("id")

    # Recurse into child nodes
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        result = _find_focused_window(child)
        if result:
            return result

    return None


def get_focused_terminal_window_id() -> Optional[int]:
    """Get the container ID of the focused terminal window.

    Specifically looks for Ghostty or other terminal emulators.
    Falls back to any focused window if no terminal is focused.

    Returns:
        Window container ID or None
    """
    tree = sway_ipc(4)
    if not tree:
        return None

    focused = _find_focused_window_with_app(tree)
    if focused:
        return focused.get("id")

    return None


def get_focused_window_info() -> tuple[Optional[int], Optional[str]]:
    """Get focused window ID and project from marks.

    Returns:
        Tuple of (window_id, project) - project extracted from scoped marks
    """
    tree = sway_ipc(4)
    if not tree:
        return None, None

    window = _find_focused_window_with_app(tree)
    if not window:
        return None, None

    window_id = window.get("id")
    project = _extract_project_from_marks(window.get("marks", []))

    return window_id, project


def _extract_project_from_marks(marks: list) -> Optional[str]:
    """Extract project name from Sway window marks.

    Looks for scoped marks in format: scoped:app_type:owner/repo:branch:window_id
    Returns: owner/repo:branch

    Args:
        marks: List of window mark strings

    Returns:
        Project name or None
    """
    for mark in marks:
        if isinstance(mark, str) and mark.startswith("scoped:"):
            # Format: scoped:type:owner/repo:branch:id
            parts = mark.split(":")
            if len(parts) >= 4:
                # parts[2] = owner/repo, parts[3] = branch
                return f"{parts[2]}:{parts[3]}"
    return None


def _find_focused_window_with_app(node: dict) -> Optional[dict]:
    """Find focused window and return full node info.

    Args:
        node: Sway tree node

    Returns:
        Full window node dict or None
    """
    if node.get("focused") and node.get("pid"):
        return node

    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        result = _find_focused_window_with_app(child)
        if result:
            return result

    return None


def window_exists(window_id: int) -> bool:
    """Check if a Sway window with the given ID exists.

    Args:
        window_id: Sway container ID to check

    Returns:
        True if window exists, False otherwise
    """
    tree = sway_ipc(4)  # GET_TREE = 4
    if not tree:
        # Can't connect to Sway - assume window exists to avoid false cleanups
        return True

    return _find_window_by_id(tree, window_id) is not None


def get_all_window_ids() -> set[int]:
    """Get all current Sway window IDs.

    Returns:
        Set of all window container IDs
    """
    tree = sway_ipc(4)  # GET_TREE = 4
    if not tree:
        return set()

    ids: set[int] = set()
    _collect_window_ids(tree, ids)
    return ids


def _find_window_by_id(node: dict, window_id: int) -> Optional[dict]:
    """Recursively find a window by ID in the Sway tree.

    Args:
        node: Sway tree node
        window_id: Target window ID

    Returns:
        Window node dict or None
    """
    if node.get("id") == window_id and node.get("pid"):
        return node

    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        result = _find_window_by_id(child, window_id)
        if result:
            return result

    return None


def _collect_window_ids(node: dict, ids: set[int]) -> None:
    """Recursively collect all window IDs from Sway tree.

    Args:
        node: Sway tree node
        ids: Set to add IDs to
    """
    if node.get("pid"):  # Has pid means it's a window
        ids.add(node.get("id"))

    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        _collect_window_ids(child, ids)


# =============================================================================
# Feature 135: PID-based window correlation via I3PM_* environment variables
# =============================================================================


def get_process_i3pm_env(pid: int) -> dict[str, str]:
    """Read I3PM_* environment variables from a process.

    This enables deterministic window correlation by reading the environment
    variables injected by app-launcher-wrapper.sh into the AI CLI process.

    Args:
        pid: Process ID to read environment from

    Returns:
        Dict of I3PM_* variable name to value, empty dict on error
    """
    environ_path = Path(f"/proc/{pid}/environ")
    if not environ_path.exists():
        logger.debug(f"Process {pid} environ not found")
        return {}

    try:
        environ_data = environ_path.read_bytes()
        result = {}
        for entry in environ_data.split(b"\x00"):
            if not entry:
                continue
            try:
                decoded = entry.decode("utf-8", errors="replace")
                if "=" not in decoded:
                    continue
                key, value = decoded.split("=", 1)
                if key.startswith("I3PM_"):
                    result[key] = value
            except ValueError:
                continue
        if result:
            logger.debug(f"PID {pid} I3PM env: {list(result.keys())}")
        return result
    except (PermissionError, FileNotFoundError, ProcessLookupError) as e:
        logger.debug(f"Cannot read PID {pid} environ: {e}")
        return {}


def find_window_by_i3pm_env(
    i3pm_env: dict[str, str]
) -> tuple[Optional[int], Optional[str]]:
    """Find Sway window matching I3PM environment variables.

    Correlates I3PM_PROJECT_NAME with window marks to find the correct
    window for an AI CLI session.

    Args:
        i3pm_env: Dict of I3PM_* environment variables

    Returns:
        Tuple of (window_id, project_name). Both may be None if no match.
    """
    tree = sway_ipc(4)  # GET_TREE
    if not tree:
        return None, None

    project_name = i3pm_env.get("I3PM_PROJECT_NAME", "")
    worktree_branch = i3pm_env.get("I3PM_WORKTREE_BRANCH", "")

    # If no project context, can't correlate
    if not project_name and not worktree_branch:
        logger.debug("No I3PM_PROJECT_NAME or I3PM_WORKTREE_BRANCH in env")
        return None, project_name or None

    def search_tree(node: dict) -> Optional[dict]:
        """Recursively search for window with matching project marks."""
        # Check if this window's marks contain our project
        marks = node.get("marks", [])
        for mark in marks:
            if isinstance(mark, str) and mark.startswith("scoped:"):
                # Format: scoped:type:owner/repo:branch:id
                parts = mark.split(":")
                if len(parts) >= 4:
                    # parts[2] = owner/repo, parts[3] = branch
                    mark_project = f"{parts[2]}:{parts[3]}"
                    # Match against project_name or worktree_branch
                    if project_name and project_name in mark_project:
                        return node
                    if worktree_branch and worktree_branch in mark_project:
                        return node

        # Recurse into children
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            result = search_tree(child)
            if result:
                return result
        return None

    window = search_tree(tree)
    if window:
        window_id = window.get("id")
        # Extract full project name from marks for consistency
        found_project = _extract_project_from_marks(window.get("marks", []))
        logger.debug(f"Found window {window_id} for project {found_project}")
        return window_id, found_project or project_name

    logger.debug(f"No window found for project {project_name}")
    return None, project_name or None


def _get_ppid(pid: int) -> Optional[int]:
    """Get parent PID of a process.

    Args:
        pid: Process ID to query

    Returns:
        Parent PID if found, None otherwise
    """
    try:
        stat_path = Path(f"/proc/{pid}/stat")
        if not stat_path.exists():
            return None

        stat_content = stat_path.read_text()
        # Format: pid (comm) state ppid ...
        # The comm field can contain spaces and parentheses, so we find the last ')'
        last_paren = stat_content.rfind(")")
        if last_paren == -1:
            return None

        fields = stat_content[last_paren + 2 :].split()
        if len(fields) >= 2:
            return int(fields[1])  # ppid is the second field after (comm)
    except (OSError, ValueError, IndexError):
        pass
    return None


def _get_all_sway_pids(tree: dict) -> dict[int, int]:
    """Get mapping of all PIDs to window IDs in Sway tree.

    Args:
        tree: Sway tree from GET_TREE

    Returns:
        Dict mapping PID to window container ID
    """
    pid_to_window: dict[int, int] = {}

    def collect_pids(node: dict) -> None:
        pid = node.get("pid")
        window_id = node.get("id")
        node_type = node.get("type")
        # Include both regular and floating windows (scratchpad, hidden, etc.)
        if pid and window_id and node_type in ("con", "floating_con"):
            pid_to_window[pid] = window_id

        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            collect_pids(child)

    collect_pids(tree)
    return pid_to_window


def find_window_by_pid(target_pid: int) -> Optional[int]:
    """Find Sway window by walking up the process tree.

    Feature 135: Fixed to walk up the process tree because Claude Code
    runs INSIDE the terminal (as a child process), not AS the terminal.
    Sway's window PID is the terminal's PID (e.g., Ghostty), not Claude Code's PID.

    Process hierarchy: Terminal (Sway sees this) → Shell → Claude Code (target_pid)

    NOTE: This doesn't work with tmux! The tmux server is a detached daemon,
    not a child of the terminal. Use find_window_by_i3pm_app_id() instead.

    Args:
        target_pid: Process ID to search for (may be a child of the terminal)

    Returns:
        Window container ID if found, None otherwise
    """
    tree = sway_ipc(4)  # GET_TREE
    if not tree:
        return None

    # Get all Sway window PIDs
    sway_pids = _get_all_sway_pids(tree)
    if not sway_pids:
        logger.debug("No Sway window PIDs found")
        return None

    # Walk up the process tree from target_pid to find an ancestor in sway_pids
    current_pid = target_pid
    visited = set()  # Prevent infinite loops

    while current_pid and current_pid > 1 and current_pid not in visited:
        visited.add(current_pid)

        # Check if current PID is a Sway window
        if current_pid in sway_pids:
            window_id = sway_pids[current_pid]
            logger.debug(
                f"Found window {window_id} for PID {target_pid} via ancestor PID {current_pid}"
            )
            return window_id

        # Walk up to parent
        current_pid = _get_ppid(current_pid)

    logger.debug(f"No Sway window found for PID {target_pid} in process tree")
    return None


def find_window_by_i3pm_app_id(i3pm_env: dict[str, str]) -> Optional[int]:
    """Find Sway window by querying daemon with I3PM_APP_ID correlation.

    Feature 135: For tmux users, process tree walking doesn't work because
    the tmux server is a detached daemon. Instead, we use the I3PM_APP_ID
    which contains a unique timestamp that was matched when the window
    was first created.

    The daemon stores correlation_launch_id = {app_name}-{timestamp} when
    matching windows to launches. We query the daemon to find the window.

    Args:
        i3pm_env: Dict of I3PM_* environment variables from the CLI process

    Returns:
        Window container ID if found, None otherwise
    """
    app_id = i3pm_env.get("I3PM_APP_ID", "")
    if not app_id:
        logger.debug("No I3PM_APP_ID in environment")
        return None

    # Parse I3PM_APP_ID: {app_name}-{project}-{launcher_pid}-{timestamp}
    # Example: terminal-vpittamp/nixos-config:135-branch-894125-1766520745
    # The timestamp is the LAST numeric segment (can be float like 1766520745.123456)
    parts = app_id.rsplit("-", 2)  # Split from right to get timestamp and launcher_pid
    if len(parts) < 3:
        logger.debug(f"Invalid I3PM_APP_ID format: {app_id}")
        return None

    # parts[-1] is timestamp, parts[-2] is launcher_pid
    # parts[0] is "app_name-project" combined
    try:
        timestamp_str = parts[-1]
        # Handle float timestamps (e.g., 1766520745.123456)
        timestamp = float(timestamp_str)
    except ValueError:
        logger.debug(f"Invalid timestamp in I3PM_APP_ID: {app_id}")
        return None

    # Extract app_name from the beginning
    # Format: terminal-project-pid-timestamp
    # The app_name is everything before the first dash, OR we use I3PM_APP_NAME
    app_name = i3pm_env.get("I3PM_APP_NAME", "")
    if not app_name:
        # Fallback: extract from app_id (first segment before -)
        app_name = app_id.split("-")[0]

    # Build correlation_launch_id: {app_name}-{timestamp}
    # The daemon uses integer timestamp in launch_id
    correlation_launch_id = f"{app_name}-{int(timestamp)}"

    logger.debug(f"Looking for window with correlation_launch_id={correlation_launch_id}")

    # Query daemon via IPC to find window with this correlation_launch_id
    window_id = _query_daemon_for_window(correlation_launch_id)
    if window_id:
        logger.debug(f"Found window {window_id} via daemon correlation_launch_id lookup")
        return window_id

    # Fallback: search by project in marks (less precise but works)
    logger.debug("Daemon lookup failed, falling back to project-based search")
    return None


def _query_daemon_for_window(correlation_launch_id: str) -> Optional[int]:
    """Query i3pm daemon to find window by correlation_launch_id.

    Args:
        correlation_launch_id: Launch ID in format {app_name}-{timestamp}

    Returns:
        Window ID if found, None otherwise
    """
    import socket as sock

    # Find daemon socket
    uid = os.getuid()
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    socket_path = os.path.join(runtime_dir, "i3-project-daemon", "ipc.sock")

    if not os.path.exists(socket_path):
        logger.debug(f"Daemon socket not found: {socket_path}")
        return None

    try:
        # Build JSON-RPC request to get all windows and find matching one
        request = json.dumps({
            "jsonrpc": "2.0",
            "method": "get_windows",
            "params": {},
            "id": 1
        })

        # Send request
        client = sock.socket(sock.AF_UNIX, sock.SOCK_STREAM)
        client.settimeout(2.0)
        client.connect(socket_path)
        client.sendall(request.encode("utf-8"))
        client.shutdown(sock.SHUT_WR)

        # Read response
        response_data = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            response_data += chunk
        client.close()

        response = json.loads(response_data.decode("utf-8"))

        if "error" in response:
            logger.debug(f"Daemon error: {response['error']}")
            return None

        # get_windows returns basic info, we need get_window_state for correlation
        # For now, fall back to mark-based search
        windows = response.get("result", {}).get("windows", [])
        logger.debug(f"Got {len(windows)} windows from daemon")

        # TODO: Enhance daemon to expose correlation_launch_id in get_windows
        # or add a new method: get_window_by_launch_id
        # For now, we can't match by correlation_launch_id without more daemon work

        return None

    except Exception as e:
        logger.debug(f"Failed to query daemon: {e}")
        return None


def find_all_terminal_windows_for_project(project_name: str) -> list[int]:
    """Find all terminal window IDs for a given project.

    Feature 135: Used to find candidate windows when multiple terminals
    exist for the same project. Returns all matches so caller can
    disambiguate using additional context.

    Args:
        project_name: Project name to search for (e.g., "vpittamp/nixos-config:branch")

    Returns:
        List of window IDs matching the project (may be empty)
    """
    tree = sway_ipc(4)  # GET_TREE
    if not tree:
        return []

    window_ids: list[int] = []

    def search_tree(node: dict) -> None:
        """Recursively search for terminal windows with matching project marks."""
        marks = node.get("marks", [])
        for mark in marks:
            if isinstance(mark, str) and mark.startswith("scoped:terminal:"):
                # Format: scoped:terminal:owner/repo:branch:id
                parts = mark.split(":")
                if len(parts) >= 4:
                    # parts[2] = owner/repo, parts[3] = branch
                    mark_project = f"{parts[2]}:{parts[3]}"
                    if project_name in mark_project or mark_project in project_name:
                        window_id = node.get("id")
                        if window_id:
                            window_ids.append(window_id)
                        break  # Don't add same window twice

        # Recurse into children
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            search_tree(child)

    search_tree(tree)
    logger.debug(f"Found {len(window_ids)} terminal windows for project {project_name}: {window_ids}")
    return window_ids


# =============================================================================
# Feature 135: Deterministic Window Correlation via Daemon IPC
# =============================================================================


def parse_correlation_key(
    i3pm_app_id: Optional[str], i3pm_app_name: Optional[str]
) -> Optional[str]:
    """Parse correlation key from I3PM environment variables.

    Extracts the unique correlation key used to match AI CLI sessions to
    their originating terminal windows. The key is "{app_name}-{timestamp}"
    where timestamp is the Unix epoch second when the terminal was launched.

    Args:
        i3pm_app_id: The I3PM_APP_ID env var, format: "{app}-{project}-{pid}-{timestamp}"
        i3pm_app_name: The I3PM_APP_NAME env var (e.g., "terminal")

    Returns:
        Correlation key like "terminal-1766520745" or None if parsing fails

    Example:
        >>> parse_correlation_key(
        ...     i3pm_app_id="terminal-vpittamp/nixos-config:135-branch-894125-1766520745",
        ...     i3pm_app_name="terminal"
        ... )
        'terminal-1766520745'
    """
    if not i3pm_app_id or not i3pm_app_name:
        return None

    # The timestamp is the LAST numeric segment of I3PM_APP_ID
    # Format: {app_name}-{project}-{launcher_pid}-{timestamp}
    # Split from the right to get timestamp and pid
    parts = i3pm_app_id.rsplit("-", 2)  # Split into at most 3 parts from right

    if len(parts) < 3:
        logger.debug(f"parse_correlation_key: Invalid I3PM_APP_ID format: {i3pm_app_id}")
        return None

    # parts[-1] is timestamp, parts[-2] is launcher_pid
    timestamp_str = parts[-1]

    try:
        # Handle float timestamps (e.g., 1766520745.123456) by truncating to int
        timestamp_float = float(timestamp_str)
        timestamp = int(timestamp_float)
        if timestamp <= 0:
            logger.debug(f"parse_correlation_key: Invalid timestamp <= 0: {timestamp}")
            return None
    except (ValueError, TypeError):
        logger.debug(f"parse_correlation_key: Non-numeric timestamp: {timestamp_str}")
        return None

    # Build correlation key using the app_name parameter
    correlation_key = f"{i3pm_app_name}-{timestamp}"
    logger.debug(f"parse_correlation_key: {i3pm_app_id} → {correlation_key}")
    return correlation_key


async def query_daemon_for_window_by_launch_id(
    app_name: str, timestamp: int
) -> Optional[dict]:
    """Query i3pm daemon to find window by correlation launch ID.

    Feature 135: Uses the new get_window_by_launch_id IPC method to perform
    a deterministic lookup of the terminal window where an AI CLI is running.

    Args:
        app_name: Application name (e.g., "terminal", "vscode")
        timestamp: Unix timestamp (seconds) from I3PM_APP_ID

    Returns:
        Dict with window info on success:
        {
            "window_id": int,
            "project_name": str | None,
            "correlation_confidence": float,
            "matched_at": float
        }
        Or {"window_id": None, "error": "not_found", "message": str} if not found.
        Or None if daemon unavailable.

    Raises:
        ValueError: If app_name format is invalid
    """
    import asyncio
    import re

    # Validate app_name format
    if not app_name or not re.match(r"^[a-zA-Z][a-zA-Z0-9_-]*$", str(app_name)):
        raise ValueError(f"Invalid app_name: {app_name}")

    if timestamp is None:
        raise ValueError("timestamp is required")

    # Find daemon socket
    uid = os.getuid()
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    socket_path = os.path.join(runtime_dir, "i3-project-daemon", "ipc.sock")

    if not os.path.exists(socket_path):
        logger.debug(f"Daemon socket not found: {socket_path}")
        return None

    try:
        # Build JSON-RPC request
        request = json.dumps({
            "jsonrpc": "2.0",
            "method": "get_window_by_launch_id",
            "params": {
                "app_name": app_name,
                "timestamp": int(timestamp),
            },
            "id": 1,
        })

        # Use async socket operations to avoid blocking the event loop
        # This is critical when the daemon server runs on the same event loop (e.g., tests)
        reader, writer = await asyncio.wait_for(
            asyncio.open_unix_connection(socket_path),
            timeout=2.0  # SC-003: Keep socket timeout reasonable
        )

        try:
            # Send request
            writer.write(request.encode("utf-8"))
            writer.write_eof()
            await writer.drain()

            # Read response
            response_data = await asyncio.wait_for(
                reader.read(),
                timeout=2.0
            )

            response = json.loads(response_data.decode("utf-8"))

            if "error" in response:
                error = response["error"]
                # Check if it's a JSON-RPC error vs a "not found" result
                if isinstance(error, dict) and "code" in error:
                    logger.debug(f"Daemon IPC error: {error}")
                    return None

            result = response.get("result", {})
            logger.debug(f"query_daemon_for_window_by_launch_id: result={result}")
            return result
        finally:
            writer.close()
            await writer.wait_closed()

    except asyncio.TimeoutError:
        logger.debug(f"query_daemon_for_window_by_launch_id: timeout connecting to daemon")
        return None
    except Exception as e:
        logger.debug(f"query_daemon_for_window_by_launch_id failed: {e}")
        return None


def find_window_via_tmux_client(target_pid: int) -> Optional[int]:
    """Find Sway window by tracing through tmux client attachment.

    Feature 135: For tmux sessions that share the same I3PM_APP_ID (common when
    multiple sessions are created in the same tmux server), this function finds
    the correct window by:
    1. Finding which PTY the target process runs on
    2. Finding which tmux session owns that PTY
    3. Finding which tmux client is attached to that session
    4. Walking up from the client PID to find the Sway window

    This is necessary because:
    - Processes in tmux sessions are children of the tmux SERVER (detached daemon)
    - The tmux CLIENT is a child of the terminal (Ghostty)
    - Walking from the server doesn't find the terminal, but walking from client does

    Args:
        target_pid: Process ID of the AI CLI running inside tmux

    Returns:
        Sway window container ID, or None if not running in tmux or not found
    """
    import subprocess

    try:
        # Step 1: Get the TTY of the target process
        proc_stat = Path(f"/proc/{target_pid}/stat").read_text()
        # Field 7 is tty_nr (TTY device number)
        stat_fields = proc_stat.split()
        if len(stat_fields) < 7:
            return None
        tty_nr = int(stat_fields[6])
        if tty_nr == 0:
            # No TTY
            return None

        # Convert tty_nr to pts/X - major 136 = pts
        major = (tty_nr >> 8) & 0xff
        minor = tty_nr & 0xff
        if major != 136:  # Not a pts device
            return None
        target_pts = f"/dev/pts/{minor}"

        # Step 2: Find which tmux session owns this PTY
        result = subprocess.run(
            ["tmux", "list-panes", "-a", "-F", "#{pane_tty} #{session_name}"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if result.returncode != 0:
            return None

        session_name = None
        for line in result.stdout.strip().split("\n"):
            parts = line.split(" ", 1)
            if len(parts) == 2 and parts[0] == target_pts:
                session_name = parts[1]
                break

        if not session_name:
            logger.debug(f"No tmux session found for PTY {target_pts}")
            return None

        # Step 3: Find which tmux client is attached to this session
        result = subprocess.run(
            ["tmux", "list-clients", "-F", "#{client_pid} #{session_name}"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if result.returncode != 0:
            return None

        client_pid = None
        for line in result.stdout.strip().split("\n"):
            parts = line.split(" ", 1)
            if len(parts) == 2 and parts[1] == session_name:
                client_pid = int(parts[0])
                break

        if not client_pid:
            logger.debug(f"No tmux client attached to session {session_name}")
            return None

        # Step 4: Walk up from client PID to find the Sway window
        window_id = find_window_by_pid(client_pid)
        if window_id:
            logger.debug(
                f"find_window_via_tmux_client: PID {target_pid} → "
                f"session {session_name} → client {client_pid} → window {window_id}"
            )
        return window_id

    except FileNotFoundError:
        # Process doesn't exist
        return None
    except subprocess.TimeoutExpired:
        logger.debug("tmux command timed out")
        return None
    except Exception as e:
        logger.debug(f"find_window_via_tmux_client failed: {e}")
        return None


async def find_window_for_session(pid: int) -> Optional[int]:
    """Find the Sway window for an AI CLI session using deterministic correlation.

    Feature 135: This is the main entry point for session-to-window correlation.
    It reads I3PM environment from the CLI process and queries the daemon for
    the exact terminal window using the unique launch timestamp.

    Unlike the previous heuristic-based approaches, this method:
    - Uses deterministic correlation (no guessing)
    - Works correctly with multiple terminals for the same project
    - Works with tmux because it uses I3PM_APP_ID, not process tree
    - Has no fallback strategies - returns None if not found

    Args:
        pid: Process ID of the AI CLI (Claude Code, Codex, Gemini, etc.)

    Returns:
        Sway container ID (con_id) of the window, or None if:
        - Process doesn't exist
        - Process has no I3PM_* environment
        - Daemon is unavailable
        - No window matches the correlation key

    Performance: Target <100ms end-to-end (SC-002)
    """
    import time

    start_time = time.perf_counter()

    # Step 1: Read I3PM environment from the process
    i3pm_env = get_process_i3pm_env(pid)
    if not i3pm_env:
        logger.debug(f"find_window_for_session: No I3PM env for PID {pid}")
        return None

    app_id = i3pm_env.get("I3PM_APP_ID", "")
    app_name = i3pm_env.get("I3PM_APP_NAME", "")

    if not app_id or not app_name:
        logger.debug(
            f"find_window_for_session: Missing I3PM_APP_ID or I3PM_APP_NAME for PID {pid}"
        )
        return None

    # Step 2: Parse correlation key
    correlation_key = parse_correlation_key(app_id, app_name)
    if not correlation_key:
        logger.debug(f"find_window_for_session: Failed to parse correlation key for PID {pid}")
        return None

    # Extract timestamp from correlation key
    parts = correlation_key.rsplit("-", 1)
    if len(parts) != 2:
        logger.debug(f"find_window_for_session: Invalid correlation key format: {correlation_key}")
        return None

    try:
        timestamp = int(parts[1])
    except ValueError:
        logger.debug(f"find_window_for_session: Invalid timestamp in correlation key: {correlation_key}")
        return None

    # Step 3: Query daemon for window
    result = await query_daemon_for_window_by_launch_id(app_name, timestamp)
    if result is None:
        # Daemon unavailable - graceful degradation (SC-005)
        logger.debug(f"find_window_for_session: Daemon unavailable for PID {pid}")
        return None

    window_id = result.get("window_id")
    elapsed_ms = (time.perf_counter() - start_time) * 1000

    # For processes running in tmux, the I3PM-based correlation may be wrong
    # because multiple tmux sessions can share the same I3PM_APP_ID.
    # Try tmux client lookup as a more accurate method for tmux processes.
    tmux_window = find_window_via_tmux_client(pid)
    if tmux_window:
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        if tmux_window != window_id:
            logger.debug(
                f"find_window_for_session: tmux override: PID {pid} → window {tmux_window} "
                f"(I3PM suggested {window_id}, time={elapsed_ms:.2f}ms)"
            )
        else:
            logger.debug(
                f"find_window_for_session: PID {pid} → window {tmux_window} "
                f"(confirmed via tmux, time={elapsed_ms:.2f}ms)"
            )
        return tmux_window

    # Fall back to I3PM-based correlation if tmux lookup fails
    if window_id:
        logger.debug(
            f"find_window_for_session: PID {pid} → window {window_id} "
            f"(confidence={result.get('correlation_confidence')}, time={elapsed_ms:.2f}ms)"
        )
        if elapsed_ms > 100:
            logger.warning(f"find_window_for_session: Exceeded 100ms target: {elapsed_ms:.2f}ms")
        return window_id

    logger.debug(
        f"find_window_for_session: No window found for PID {pid}, "
        f"correlation_key={correlation_key}, time={elapsed_ms:.2f}ms"
    )
    return None
