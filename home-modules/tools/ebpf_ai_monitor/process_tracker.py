"""Process tracking and window ID resolution.

This module provides functionality for:
- Scanning /proc for existing AI processes on startup
- Finding terminal (Ghostty) via Sway marks and project correlation
- Resolving Sway window ID from terminal PID
- Extracting project name from process environment

Architecture (with tmux and Sway marks):
    Sway → Ghostty (with mark scoped:terminal:PROJECT:WINDOW_ID)
          → bash → tmux client
    tmux server (daemon) → bash → claude (uses pts/X)

    Window resolution strategy:
    1. Query Sway for all Ghostty windows and their marks
    2. Get project from claude's I3PM_PROJECT_NAME or tmux session name
    3. Match claude to Ghostty based on project name from mark
    4. Fallback to TTY-based resolution if marks unavailable
"""

import json
import logging
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .models import MonitoredProcess, ProcessState

logger = logging.getLogger(__name__)


def scan_proc_for_processes(target_names: set[str]) -> list[dict]:
    """Scan /proc for processes matching target names.

    Args:
        target_names: Set of process names to find (e.g., {"claude", "codex"}).

    Returns:
        List of dicts with 'pid' and 'comm' keys for matching processes.
    """
    found = []
    proc_path = Path("/proc")

    for entry in proc_path.iterdir():
        if not entry.name.isdigit():
            continue

        pid = int(entry.name)
        comm_file = entry / "comm"

        try:
            comm = comm_file.read_text().strip()
            if comm in target_names:
                found.append({"pid": pid, "comm": comm})
                logger.debug("Found target process: PID=%d, comm=%s", pid, comm)
        except (FileNotFoundError, PermissionError):
            # Process may have exited or we don't have permission
            continue

    logger.info("Found %d target processes", len(found))
    return found


def get_parent_chain(pid: int, max_depth: int = 20) -> list[int]:
    """Walk process tree to build parent chain.

    Args:
        pid: Starting process ID.
        max_depth: Maximum depth to traverse (prevents infinite loops).

    Returns:
        List of PIDs from pid up to init (1), e.g., [12345, 12340, 1].
    """
    chain = []
    current_pid = pid

    for _ in range(max_depth):
        chain.append(current_pid)

        if current_pid == 1:
            break

        stat_file = Path(f"/proc/{current_pid}/stat")
        try:
            stat_content = stat_file.read_text()
            # Format: pid (comm) state ppid ...
            # comm can contain spaces and parentheses, so find last )
            match = re.search(r"\)\s+\S+\s+(\d+)", stat_content)
            if match:
                parent_pid = int(match.group(1))
                current_pid = parent_pid
            else:
                logger.warning("Could not parse stat for PID %d", current_pid)
                break
        except (FileNotFoundError, PermissionError):
            logger.debug("Cannot read stat for PID %d", current_pid)
            break

    return chain


def get_process_comm(pid: int) -> Optional[str]:
    """Get process name from /proc/<pid>/comm.

    Args:
        pid: Process ID.

    Returns:
        Process name or None if not readable.
    """
    try:
        return Path(f"/proc/{pid}/comm").read_text().strip()
    except (FileNotFoundError, PermissionError):
        return None


def find_ghostty_pid(parent_chain: list[int]) -> Optional[int]:
    """Find Ghostty terminal PID in parent chain.

    Args:
        parent_chain: List of PIDs from process up to init.

    Returns:
        PID of Ghostty process or None if not found.
    """
    for pid in parent_chain:
        comm = get_process_comm(pid)
        if comm == "ghostty":
            logger.debug("Found Ghostty at PID %d in parent chain", pid)
            return pid
    return None


def get_controlling_tty(pid: int) -> Optional[str]:
    """Get the controlling terminal (tty) device for a process.

    Args:
        pid: Process ID.

    Returns:
        TTY device path (e.g., "/dev/pts/5") or None if not found.
    """
    try:
        # /proc/<pid>/fd/0 is stdin, which points to the tty
        fd0_link = Path(f"/proc/{pid}/fd/0")
        if fd0_link.exists():
            target = os.readlink(fd0_link)
            if target.startswith("/dev/pts/") or target.startswith("/dev/tty"):
                logger.debug("PID %d has controlling tty: %s", pid, target)
                return target
    except (FileNotFoundError, PermissionError, OSError) as e:
        logger.debug("Cannot read fd/0 for PID %d: %s", pid, e)

    # Fallback: check /proc/<pid>/stat for tty_nr
    try:
        stat_content = Path(f"/proc/{pid}/stat").read_text()
        # Format: pid (comm) state ppid pgrp session tty_nr ...
        # tty_nr is field 7 (0-indexed: 6)
        match = re.search(r"\)\s+\S+\s+\d+\s+\d+\s+\d+\s+(\d+)", stat_content)
        if match:
            tty_nr = int(match.group(1))
            if tty_nr > 0:
                # Convert tty_nr to device path
                # Major 136 = pts, minor is the pts number
                major = (tty_nr >> 8) & 0xFF
                minor = tty_nr & 0xFF
                if major == 136:  # pts
                    return f"/dev/pts/{minor}"
    except (FileNotFoundError, PermissionError):
        pass

    return None


def find_ghostty_by_tty(tty_path: str) -> Optional[int]:
    """Find Ghostty process that owns a specific TTY.

    When processes run inside tmux, their parent chain goes through
    the tmux server, not through Ghostty. But Ghostty still owns the
    pts device that the tmux client uses.

    Args:
        tty_path: Path to the tty device (e.g., "/dev/pts/5").

    Returns:
        PID of Ghostty process that owns this TTY, or None.
    """
    proc_path = Path("/proc")

    for entry in proc_path.iterdir():
        if not entry.name.isdigit():
            continue

        pid = int(entry.name)
        comm = get_process_comm(pid)

        if comm != "ghostty":
            continue

        # Check if this Ghostty's fd/0 or any fd points to the target tty
        fd_dir = entry / "fd"
        try:
            for fd_entry in fd_dir.iterdir():
                try:
                    target = os.readlink(fd_entry)
                    if target == tty_path:
                        logger.debug(
                            "Found Ghostty PID %d owning tty %s (fd %s)",
                            pid, tty_path, fd_entry.name
                        )
                        return pid
                except (OSError, FileNotFoundError):
                    continue
        except (PermissionError, FileNotFoundError):
            continue

    logger.debug("No Ghostty found owning tty %s", tty_path)
    return None


def get_tmux_socket_path() -> Optional[str]:
    """Get the tmux socket path for the target user.

    When running as root (e.g., eBPF service), we need to explicitly
    specify the user's tmux socket to query their sessions.

    On NixOS with systemd, tmux uses XDG_RUNTIME_DIR for the socket:
        /run/user/<uid>/tmux-<uid>/default

    Environment variables:
        EBPF_TMUX_SOCKET: Explicit override (for non-standard configurations)
        EBPF_MONITOR_USER: Target user to monitor

    Returns:
        Path to tmux socket or None if not found.
    """
    # Check for explicit socket path override (for non-NixOS or custom configs)
    explicit_socket = os.environ.get("EBPF_TMUX_SOCKET", "")
    if explicit_socket:
        if Path(explicit_socket).exists():
            logger.debug("Using explicit tmux socket: %s", explicit_socket)
            return explicit_socket
        logger.warning("EBPF_TMUX_SOCKET set but not found: %s", explicit_socket)

    target_user = os.environ.get("EBPF_MONITOR_USER", "")
    if not target_user:
        # Not running as service, tmux will use default socket
        return None

    try:
        import pwd
        user_info = pwd.getpwnam(target_user)
        uid = user_info.pw_uid
    except KeyError:
        logger.debug("User '%s' not found for tmux socket lookup", target_user)
        return None

    # NixOS with systemd: XDG_RUNTIME_DIR is /run/user/<uid>
    # tmux socket path: /run/user/<uid>/tmux-<uid>/default
    socket_path = Path(f"/run/user/{uid}/tmux-{uid}/default")
    if socket_path.exists():
        logger.debug("Found tmux socket: %s", socket_path)
        return str(socket_path)

    logger.debug(
        "tmux socket not found for user %s (uid %d) at %s",
        target_user, uid, socket_path
    )
    return None


def find_tmux_session_for_tty(tty_path: str) -> Optional[str]:
    """Query tmux to find which session contains a pane with this TTY.

    When running as root (eBPF service), uses the target user's tmux socket.

    Args:
        tty_path: Path to the tty device (e.g., "/dev/pts/2").

    Returns:
        tmux session name or None if not found.
    """
    try:
        # Build tmux command, optionally with explicit socket path
        cmd = ["tmux"]
        socket_path = get_tmux_socket_path()
        if socket_path:
            cmd.extend(["-S", socket_path])
        cmd.extend(["list-panes", "-a", "-F", "#{pane_tty} #{session_name}"])

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            logger.debug("tmux list-panes failed: %s", result.stderr)
            return None

        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split(' ', 1)
            if len(parts) == 2:
                pane_tty, session_name = parts
                if pane_tty == tty_path:
                    logger.debug(
                        "Found tmux session '%s' for tty %s",
                        session_name, tty_path
                    )
                    return session_name
    except subprocess.TimeoutExpired:
        logger.debug("tmux list-panes timed out")
    except FileNotFoundError:
        logger.debug("tmux not found")

    return None


def find_ghostty_by_session_name(session_name: str) -> Optional[int]:
    """Find Ghostty process running a tmux session with matching name.

    When using sesh, Ghostty is launched with:
        ghostty -e sesh connect <session_name>

    Args:
        session_name: tmux session name (often a project path).

    Returns:
        PID of Ghostty process or None.
    """
    proc_path = Path("/proc")

    for entry in proc_path.iterdir():
        if not entry.name.isdigit():
            continue

        pid = int(entry.name)
        comm = get_process_comm(pid)

        if comm != "ghostty":
            continue

        # Check command line for session name
        try:
            cmdline = (entry / "cmdline").read_bytes()
            # cmdline is null-separated
            cmdline_str = cmdline.replace(b'\x00', b' ').decode('utf-8', errors='replace')

            # Look for sesh connect <session_name> or tmux patterns
            if session_name in cmdline_str:
                logger.debug(
                    "Found Ghostty PID %d with session '%s' in cmdline",
                    pid, session_name
                )
                return pid
        except (FileNotFoundError, PermissionError):
            continue

    logger.debug("No Ghostty found for session '%s'", session_name)
    return None


@dataclass
class GhosttyWindow:
    """Information about a Ghostty window from Sway."""

    window_id: int
    pid: int
    project: Optional[str] = None  # Project from unified mark
    marks: list[str] = None  # All marks on window

    def __post_init__(self):
        if self.marks is None:
            self.marks = []


def parse_project_from_mark(mark: str) -> Optional[str]:
    """Parse project name from a unified Sway mark.

    Mark format: SCOPE:APP_NAME:PROJECT:WINDOW_ID
    Examples:
    - scoped:terminal:vpittamp/nixos-config:main:12345 → vpittamp/nixos-config:main
    - scoped:code:myproject:67890 → myproject
    - global:firefox:nixos:99999 → nixos

    Args:
        mark: Sway mark string.

    Returns:
        Project name or None if mark is not in unified format.
    """
    # Must start with valid scope
    if not mark.startswith("scoped:") and not mark.startswith("global:"):
        return None

    parts = mark.split(":")

    # Unified format requires at least 4 parts: SCOPE:APP:PROJECT:WINDOW_ID
    # Project names may contain colons (e.g., vpittamp/nixos-config:main)
    if len(parts) < 4:
        return None

    # Validate last part is numeric (window_id)
    if not parts[-1].isdigit():
        return None

    # Project is everything between app_name (parts[1]) and window_id (parts[-1])
    project = ":".join(parts[2:-1])
    return project if project else None


def find_sway_socket() -> Optional[str]:
    """Find the Sway IPC socket for the configured user.

    The socket is typically at /run/user/<uid>/sway-ipc.<pid>.<random>.sock
    We need to find it dynamically since the suffix changes each session.

    Returns:
        Path to the Sway socket or None if not found.
    """
    # Get user from environment (set by NixOS service)
    target_user = os.environ.get("EBPF_MONITOR_USER", "")
    if not target_user:
        logger.debug("EBPF_MONITOR_USER not set, trying common locations")
        # Try to find any user's Sway socket
        for uid in range(1000, 1100):  # Common user UIDs
            run_dir = Path(f"/run/user/{uid}")
            if run_dir.exists():
                for sock in run_dir.glob("sway-ipc.*.sock"):
                    logger.debug("Found Sway socket: %s", sock)
                    return str(sock)
        return None

    # Get UID for user
    try:
        import pwd
        user_info = pwd.getpwnam(target_user)
        uid = user_info.pw_uid
    except KeyError:
        logger.error("User '%s' not found", target_user)
        return None

    # Find socket in user's run directory
    run_dir = Path(f"/run/user/{uid}")
    if not run_dir.exists():
        logger.error("Run directory not found: %s", run_dir)
        return None

    for sock in run_dir.glob("sway-ipc.*.sock"):
        logger.debug("Found Sway socket for user %s: %s", target_user, sock)
        return str(sock)

    logger.warning("No Sway socket found for user %s in %s", target_user, run_dir)
    return None


def get_all_ghostty_windows() -> list[GhosttyWindow]:
    """Query Sway for all Ghostty windows with their marks.

    Returns:
        List of GhosttyWindow instances with window_id, pid, project, and marks.
    """
    # Find Sway socket if SWAYSOCK not already set
    env = os.environ.copy()
    if "SWAYSOCK" not in env:
        socket_path = find_sway_socket()
        if socket_path:
            env["SWAYSOCK"] = socket_path
        else:
            logger.error("Cannot find Sway socket - swaymsg will fail")
            return []

    try:
        result = subprocess.run(
            ["swaymsg", "-t", "get_tree"],
            capture_output=True,
            text=True,
            timeout=5,
            env=env,
        )
        if result.returncode != 0:
            logger.error("swaymsg get_tree failed: %s", result.stderr)
            return []

        tree = json.loads(result.stdout)
        ghostty_windows = []

        def walk_tree(node: dict) -> None:
            """Recursively walk Sway tree to find Ghostty windows."""
            # Check if this is a Ghostty window
            app_id = node.get("app_id", "")
            pid = node.get("pid", 0)
            window_id = node.get("id", 0)

            if app_id == "com.mitchellh.ghostty" and pid > 0:
                marks = node.get("marks", [])
                project = None

                # Try to extract project from unified marks
                for mark in marks:
                    project = parse_project_from_mark(mark)
                    if project:
                        break

                ghostty_windows.append(
                    GhosttyWindow(
                        window_id=window_id,
                        pid=pid,
                        project=project,
                        marks=marks,
                    )
                )
                logger.debug(
                    "Found Ghostty: window_id=%d, pid=%d, project=%s, marks=%s",
                    window_id, pid, project, marks
                )

            # Recurse into child nodes
            for child in node.get("nodes", []):
                walk_tree(child)
            for child in node.get("floating_nodes", []):
                walk_tree(child)

        walk_tree(tree)
        logger.info("Found %d Ghostty windows via Sway", len(ghostty_windows))
        return ghostty_windows

    except subprocess.TimeoutExpired:
        logger.error("swaymsg timed out")
        return []
    except json.JSONDecodeError as e:
        logger.error("Failed to parse Sway tree: %s", e)
        return []
    except FileNotFoundError:
        logger.error("swaymsg not found - is Sway running?")
        return []


def get_process_project(pid: int) -> Optional[str]:
    """Get project name for a process from tmux session or I3PM_PROJECT_NAME.

    Tries multiple strategies in order of accuracy:
    1. Query tmux for session name (most accurate - reflects actual terminal)
    2. Read I3PM_PROJECT_NAME from process environ (may be inherited/stale)

    Args:
        pid: Process ID.

    Returns:
        Project name or None if not determinable.
    """
    # Strategy 1: Get tmux session name (most accurate)
    # Tmux session names reflect the actual project the terminal is in,
    # while I3PM_PROJECT_NAME may be inherited from parent shell
    tty_path = get_controlling_tty(pid)
    if tty_path:
        session_name = find_tmux_session_for_tty(tty_path)
        if session_name:
            logger.debug(
                "Got project from tmux session for PID %d: %s",
                pid, session_name
            )
            return session_name

    # Strategy 2: Check process environ for I3PM_PROJECT_NAME (fallback)
    project = read_environ_var(pid, "I3PM_PROJECT_NAME")
    if project:
        logger.debug("Got project from I3PM_PROJECT_NAME for PID %d: %s", pid, project)
        return project

    return None


def normalize_project_name(project: str) -> tuple[str, str]:
    """Extract repo and branch from project name in various formats.

    Handles:
    - tmux format: "repo/branch" (e.g., "nixos-config/120-improve-git-changes")
    - Sway mark format: "account/repo:branch" (e.g., "vpittamp/nixos-config:main")
    - scratchpad format: "scratchpad-account/repo_branch"

    Returns:
        Tuple of (repo, branch) for comparison.
    """
    # Handle scratchpad format: scratchpad-account/repo_branch
    if project.startswith("scratchpad-"):
        # Remove prefix and extract repo_branch
        rest = project[len("scratchpad-"):]
        # Format: account/repo_branch - split on last underscore for branch
        if "_" in rest:
            parts = rest.rsplit("_", 1)
            if "/" in parts[0]:
                # account/repo_branch → repo, branch
                repo = parts[0].split("/")[-1]
                branch = parts[1]
                return (repo, branch)

    # Handle Sway mark format: account/repo:branch
    if "/" in project and ":" in project:
        # Split on : to get account/repo and branch
        parts = project.rsplit(":", 1)
        if len(parts) == 2:
            account_repo = parts[0]
            branch = parts[1]
            # Extract just repo name
            repo = account_repo.split("/")[-1]
            return (repo, branch)

    # Handle tmux format: repo/branch
    if "/" in project:
        parts = project.split("/", 1)
        if len(parts) == 2:
            return (parts[0], parts[1])

    # Fallback: return as-is
    return (project, "")


def find_ghostty_by_project(target_project: str) -> Optional[GhosttyWindow]:
    """Find Ghostty window matching a target project.

    Matches project names with flexibility for different formats:
    - Exact match
    - Normalized match (repo + branch comparison)
    - Partial match (substring)

    Args:
        target_project: Project name to find (tmux session name or qualified name).

    Returns:
        GhosttyWindow with matching project or None.
    """
    ghostty_windows = get_all_ghostty_windows()
    target_repo, target_branch = normalize_project_name(target_project)

    for gw in ghostty_windows:
        if not gw.project:
            continue

        # Exact match
        if gw.project == target_project:
            logger.info(
                "Exact project match: %s → Ghostty window %d (pid %d)",
                target_project, gw.window_id, gw.pid
            )
            return gw

        # Normalized match: compare repo and branch components
        gw_repo, gw_branch = normalize_project_name(gw.project)
        if target_repo and gw_repo and target_branch and gw_branch:
            if target_repo == gw_repo and target_branch == gw_branch:
                logger.info(
                    "Normalized project match: %s (%s/%s) → %s → Ghostty window %d (pid %d)",
                    target_project, target_repo, target_branch, gw.project, gw.window_id, gw.pid
                )
                return gw

        # Partial match: check if one is substring of the other
        if target_project in gw.project or gw.project in target_project:
            logger.info(
                "Partial project match: %s ↔ %s → Ghostty window %d (pid %d)",
                target_project, gw.project, gw.window_id, gw.pid
            )
            return gw

    logger.debug("No Ghostty found for project: %s (normalized: %s/%s)",
                 target_project, target_repo, target_branch)
    return None


def find_ghostty_for_process(pid: int) -> Optional[int]:
    """Find Ghostty terminal for a process (handles tmux via Sway marks).

    This function tries multiple strategies in order of reliability:
    1. Project-based match via Sway marks (best for tmux/project setup)
    2. Check parent chain (direct terminal execution)
    3. Query tmux for session name, then find Ghostty by session
    4. Find via controlling TTY ownership (fallback)

    Args:
        pid: Process ID of the target process.

    Returns:
        PID of Ghostty terminal or None if not found.
    """
    # Strategy 1: Project-based match via Sway marks (most reliable for tmux)
    # Get the process's project from I3PM_PROJECT_NAME or tmux session
    target_project = get_process_project(pid)
    if target_project:
        logger.debug(
            "Process %d has project: %s, searching Ghostty windows via Sway marks",
            pid, target_project
        )
        ghostty_window = find_ghostty_by_project(target_project)
        if ghostty_window:
            logger.info(
                "Matched process %d to Ghostty via project '%s': window_id=%d, pid=%d",
                pid, target_project, ghostty_window.window_id, ghostty_window.pid
            )
            return ghostty_window.pid

    # Strategy 2: Check parent chain (fast path for direct execution)
    parent_chain = get_parent_chain(pid)
    ghostty_pid = find_ghostty_pid(parent_chain)
    if ghostty_pid:
        logger.debug("Found Ghostty PID %d in parent chain for PID %d", ghostty_pid, pid)
        return ghostty_pid

    # Strategy 3: Query tmux for session name (fallback for tmux setup)
    tty_path = get_controlling_tty(pid)
    if tty_path:
        session_name = find_tmux_session_for_tty(tty_path)
        if session_name:
            ghostty_pid = find_ghostty_by_session_name(session_name)
            if ghostty_pid:
                logger.debug(
                    "Found Ghostty PID %d via tmux session '%s'",
                    ghostty_pid, session_name
                )
                return ghostty_pid

        # Strategy 4: Find via controlling TTY ownership (fallback)
        ghostty_pid = find_ghostty_by_tty(tty_path)
        if ghostty_pid:
            logger.debug("Found Ghostty PID %d via TTY %s", ghostty_pid, tty_path)
            return ghostty_pid

    # Strategy 5: Session ID matching (last resort)
    try:
        stat_content = Path(f"/proc/{pid}/stat").read_text()
        match = re.search(r"\)\s+\S+\s+\d+\s+\d+\s+(\d+)", stat_content)
        if match:
            session_id = int(match.group(1))
            if session_id > 0:
                ghostty_pid = _find_ghostty_in_session(session_id)
                if ghostty_pid:
                    logger.debug(
                        "Found Ghostty PID %d via session %d",
                        ghostty_pid, session_id
                    )
                    return ghostty_pid
    except (FileNotFoundError, PermissionError):
        pass

    logger.warning(
        "No Ghostty found for PID %d (tried all strategies: "
        "project=%s, parent_chain, tmux, tty, session)",
        pid, target_project
    )
    return None


def find_ghostty_window_for_process(pid: int) -> Optional[GhosttyWindow]:
    """Find Ghostty window for a process, returning both PID and window ID.

    This is an optimized version of find_ghostty_for_process that returns
    the full GhosttyWindow object including window_id, avoiding redundant
    Sway queries.

    Args:
        pid: Process ID of the target process.

    Returns:
        GhosttyWindow or None if not found.
    """
    # Strategy 1: Project-based match via Sway marks (most reliable for tmux)
    target_project = get_process_project(pid)
    if target_project:
        logger.debug(
            "Process %d has project: %s, searching Ghostty windows via Sway marks",
            pid, target_project
        )
        ghostty_window = find_ghostty_by_project(target_project)
        if ghostty_window:
            logger.info(
                "Matched process %d to Ghostty via project '%s': window_id=%d, pid=%d",
                pid, target_project, ghostty_window.window_id, ghostty_window.pid
            )
            return ghostty_window

    # For other strategies, we need to find the Ghostty PID first,
    # then look up its window info from Sway
    ghostty_pid = find_ghostty_for_process(pid)
    if ghostty_pid:
        # Look up this Ghostty in our list of windows
        all_windows = get_all_ghostty_windows()
        for gw in all_windows:
            if gw.pid == ghostty_pid:
                return gw

        # If we found a Ghostty PID but it's not in Sway tree,
        # still try to get window ID via query
        window_id = get_sway_window_id(ghostty_pid)
        if window_id:
            return GhosttyWindow(
                window_id=window_id,
                pid=ghostty_pid,
                project=target_project,
                marks=[],
            )

    return None


def _find_ghostty_in_session(session_id: int) -> Optional[int]:
    """Find Ghostty process in a given session.

    Args:
        session_id: Process session ID.

    Returns:
        PID of Ghostty in this session, or None.
    """
    proc_path = Path("/proc")

    for entry in proc_path.iterdir():
        if not entry.name.isdigit():
            continue

        pid = int(entry.name)

        try:
            stat_content = (entry / "stat").read_text()
            comm = get_process_comm(pid)

            if comm != "ghostty":
                continue

            # Check if Ghostty is in the same session
            match = re.search(r"\)\s+\S+\s+\d+\s+\d+\s+(\d+)", stat_content)
            if match and int(match.group(1)) == session_id:
                return pid
        except (FileNotFoundError, PermissionError):
            continue

    return None


def get_sway_window_id(ghostty_pid: int) -> Optional[int]:
    """Query Sway IPC to find window ID for a Ghostty process.

    Args:
        ghostty_pid: PID of Ghostty terminal process.

    Returns:
        Sway container ID or None if not found.
    """
    # Find Sway socket if SWAYSOCK not already set
    env = os.environ.copy()
    if "SWAYSOCK" not in env:
        socket_path = find_sway_socket()
        if socket_path:
            env["SWAYSOCK"] = socket_path
        else:
            logger.error("Cannot find Sway socket - swaymsg will fail")
            return None

    try:
        result = subprocess.run(
            ["swaymsg", "-t", "get_tree"],
            capture_output=True,
            text=True,
            timeout=5,
            env=env,
        )
        if result.returncode != 0:
            logger.error("swaymsg failed: %s", result.stderr)
            return None

        tree = json.loads(result.stdout)
        return _find_window_in_tree(tree, ghostty_pid)

    except subprocess.TimeoutExpired:
        logger.error("swaymsg timed out")
        return None
    except json.JSONDecodeError as e:
        logger.error("Failed to parse Sway tree: %s", e)
        return None
    except FileNotFoundError:
        logger.error("swaymsg not found - is Sway running?")
        return None


def _find_window_in_tree(node: dict, target_pid: int) -> Optional[int]:
    """Recursively search Sway tree for window with matching PID.

    Args:
        node: Sway tree node (container).
        target_pid: PID to find.

    Returns:
        Container ID or None.
    """
    # Check if this node has the target PID
    if node.get("pid") == target_pid:
        return node.get("id")

    # Recurse into child nodes
    for child in node.get("nodes", []):
        result = _find_window_in_tree(child, target_pid)
        if result:
            return result

    for child in node.get("floating_nodes", []):
        result = _find_window_in_tree(child, target_pid)
        if result:
            return result

    return None


def read_environ_var(pid: int, var_name: str) -> Optional[str]:
    """Read an environment variable from /proc/<pid>/environ.

    Args:
        pid: Process ID.
        var_name: Environment variable name (e.g., "I3PM_PROJECT_NAME").

    Returns:
        Variable value or None if not found/readable.
    """
    environ_file = Path(f"/proc/{pid}/environ")
    try:
        # environ is null-separated
        content = environ_file.read_bytes()
        for entry in content.split(b"\x00"):
            try:
                decoded = entry.decode("utf-8", errors="replace")
                if decoded.startswith(f"{var_name}="):
                    value = decoded[len(var_name) + 1 :]
                    logger.debug("Found %s=%s for PID %d", var_name, value, pid)
                    return value
            except UnicodeDecodeError:
                continue
    except (FileNotFoundError, PermissionError):
        logger.debug("Cannot read environ for PID %d", pid)

    return None


def get_project_name(pid: int) -> str:
    """Get project name from I3PM_PROJECT_NAME environment variable.

    Args:
        pid: Process ID.

    Returns:
        Project name or empty string if not found.
    """
    return read_environ_var(pid, "I3PM_PROJECT_NAME") or ""


class ProcessTracker:
    """Combines process detection, window resolution, and project extraction.

    This class provides a high-level interface for:
    - Creating MonitoredProcess instances from PIDs
    - Scanning for existing AI processes on startup
    - Resolving window IDs for processes

    Example:
        >>> tracker = ProcessTracker(target_processes={"claude", "codex"})
        >>> processes = tracker.scan_existing()
        >>> for p in processes:
        ...     print(f"{p.comm} in window {p.window_id}")
    """

    def __init__(self, target_processes: set[str]):
        """Initialize process tracker.

        Args:
            target_processes: Set of process names to monitor.
        """
        self.target_processes = target_processes

    def scan_existing(self) -> list[MonitoredProcess]:
        """Scan for existing AI processes and create MonitoredProcess instances.

        Returns:
            List of MonitoredProcess for all found target processes
            with resolved window IDs.
        """
        found_procs = scan_proc_for_processes(self.target_processes)
        monitored = []

        for proc_info in found_procs:
            try:
                process = self.create_monitored_process(
                    pid=proc_info["pid"],
                    comm=proc_info["comm"],
                )
                if process:
                    monitored.append(process)
            except Exception as e:
                logger.warning(
                    "Failed to create MonitoredProcess for PID %d: %s",
                    proc_info["pid"],
                    e,
                )

        return monitored

    def create_monitored_process(
        self,
        pid: int,
        comm: str,
    ) -> Optional[MonitoredProcess]:
        """Create a MonitoredProcess instance with resolved window ID.

        Uses Sway marks and project correlation for reliable window resolution,
        especially for processes running inside tmux.

        Args:
            pid: Process ID.
            comm: Process name.

        Returns:
            MonitoredProcess instance or None if window ID cannot be resolved.
        """
        # Get parent chain (still useful for metadata)
        parent_chain = get_parent_chain(pid)
        if not parent_chain:
            logger.warning("Empty parent chain for PID %d", pid)
            return None

        # Find Ghostty window with both PID and window_id in one query
        ghostty_window = find_ghostty_window_for_process(pid)
        if ghostty_window is None:
            logger.warning(
                "No Ghostty window found for PID %d "
                "(tried Sway marks, parent chain, TTY, session)",
                pid
            )
            return None

        # Get project name from:
        # 1. GhosttyWindow.project (from Sway mark)
        # 2. Process environment (I3PM_PROJECT_NAME)
        project_name = ghostty_window.project or get_project_name(pid)

        logger.info(
            "Created MonitoredProcess: PID=%d, comm=%s, window=%d, project=%s, ghostty_pid=%d",
            pid, comm, ghostty_window.window_id, project_name or "<none>", ghostty_window.pid
        )

        return MonitoredProcess(
            pid=pid,
            comm=comm,
            window_id=ghostty_window.window_id,
            project_name=project_name,
            state=ProcessState.WORKING,
            parent_chain=parent_chain,
        )

    def resolve_window_id(self, pid: int) -> Optional[int]:
        """Resolve window ID for a process.

        Uses Sway marks and project correlation for reliable window resolution,
        especially for processes running inside tmux.

        Args:
            pid: Process ID.

        Returns:
            Sway window ID or None.
        """
        ghostty_window = find_ghostty_window_for_process(pid)
        if ghostty_window:
            return ghostty_window.window_id
        return None
