"""Sway IPC helper for window discovery.

This module provides utilities for querying Sway to find window information,
particularly for correlating AI sessions with their originating terminal windows.

Feature 135: Added PID-based window correlation via I3PM_* environment variables.
"""

import asyncio
import json
import logging
import os
import socket
import subprocess
from glob import glob
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)

_DISCOVERED_TMUX_PROJECT_HINT_CACHE = {
    "mtime_ns": None,
    "size": None,
    "mapping": {},
}

_TMUX_LIST_PANES_FORMAT = (
    "#{pane_tty}\t#{session_name}\t#{window_index}:#{window_name}\t"
    "#{pane_id}\t#{pane_index}\t#{pane_pid}\t#{pane_title}\t#{pane_active}\t#{window_active}"
)


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


def _extract_context_key_from_marks(marks: list) -> Optional[str]:
    """Extract context key from mark in format: ctx:<qualified>::<mode>::<connection>."""
    for mark in marks:
        if not isinstance(mark, str):
            continue
        if mark.startswith("ctx:"):
            value = mark[4:].strip()
            if value:
                return value
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


def get_window_context_by_id(window_id: int) -> dict[str, Optional[str]]:
    """Resolve canonical I3PM context from the owning terminal window process.

    This is more reliable than reading I3PM_* variables from child CLI processes
    because tmux can preserve stale environment values across panes/sessions.
    """
    context: dict[str, Optional[str]] = {
        "project": None,
        "execution_mode": None,
        "connection_key": None,
        "context_key": None,
        "remote_target": None,
    }

    tree = sway_ipc(4)  # GET_TREE
    if not tree:
        return context

    window = _find_window_by_id(tree, window_id)
    if not isinstance(window, dict):
        return context

    marks = window.get("marks", [])
    if isinstance(marks, list):
        project_from_marks = _extract_project_from_marks(marks)
        context_from_marks = _extract_context_key_from_marks(marks)
        if project_from_marks:
            context["project"] = project_from_marks
        if context_from_marks:
            context["context_key"] = context_from_marks

    window_pid = window.get("pid")
    if not isinstance(window_pid, int) or window_pid <= 1:
        return context

    i3pm_env = get_process_i3pm_env(window_pid)
    if not i3pm_env:
        return context

    project_name = str(i3pm_env.get("I3PM_PROJECT_NAME") or "").strip()
    if project_name:
        context["project"] = context["project"] or project_name

    execution_mode = str(
        i3pm_env.get("I3PM_CONTEXT_VARIANT")
        or i3pm_env.get("I3PM_EXECUTION_MODE")
        or ""
    ).strip()
    if execution_mode:
        context["execution_mode"] = execution_mode

    connection_key = str(i3pm_env.get("I3PM_CONNECTION_KEY") or "").strip()
    if connection_key:
        context["connection_key"] = connection_key

    context_key = str(i3pm_env.get("I3PM_CONTEXT_KEY") or "").strip()
    if context_key:
        context["context_key"] = context_key

    remote_user = str(i3pm_env.get("I3PM_REMOTE_USER") or "").strip()
    remote_host = str(i3pm_env.get("I3PM_REMOTE_HOST") or "").strip()
    remote_port = str(i3pm_env.get("I3PM_REMOTE_PORT") or "").strip() or "22"
    if remote_host:
        context["remote_target"] = (
            f"{remote_user}@{remote_host}:{remote_port}"
            if remote_user
            else f"{remote_host}:{remote_port}"
        )

    return context


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


def get_process_env_values(
    pid: int,
    *,
    include_keys: tuple[str, ...] = (),
    include_prefixes: tuple[str, ...] = (),
) -> dict[str, str]:
    """Read selected environment variables from a process."""
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
                if (
                    key in include_keys
                    or any(key.startswith(prefix) for prefix in include_prefixes)
                ):
                    result[key] = value
            except ValueError:
                continue
        if result:
            logger.debug(f"PID {pid} env values: {list(result.keys())}")
        return result
    except (PermissionError, FileNotFoundError, ProcessLookupError) as e:
        logger.debug(f"Cannot read PID {pid} environ: {e}")
        return {}


def get_process_i3pm_env(pid: int) -> dict[str, str]:
    """Read I3PM_* environment variables from a process.

    This enables deterministic window correlation by reading the environment
    variables injected by app-launcher-wrapper.sh into the AI CLI process.

    Args:
        pid: Process ID to read environment from

    Returns:
        Dict of I3PM_* variable name to value, empty dict on error
    """
    return get_process_env_values(pid, include_prefixes=("I3PM_",))


def _normalize_project_path(value: Optional[str]) -> Optional[str]:
    raw = str(value or "").strip()
    if not raw:
        return None
    expanded = os.path.expanduser(raw)
    if not os.path.isabs(expanded):
        return None
    return os.path.normpath(expanded)


def _project_from_path(path_value: Optional[str]) -> Optional[str]:
    """Best-effort derive <account>/<repo>:<branch> from a repos path."""
    normalized = _normalize_project_path(path_value)
    if not normalized:
        return None
    try:
        parts = [segment for segment in normalized.split(os.sep) if segment]
        for idx, segment in enumerate(parts):
            if segment != "repos":
                continue
            if idx + 3 >= len(parts):
                continue
            account = parts[idx + 1].strip()
            repo = parts[idx + 2].strip()
            branch = parts[idx + 3].strip()
            if not account or not repo or not branch:
                continue
            return f"{account}/{repo}:{branch}"
    except Exception:
        return None
    return None


def _project_session_suffix(project_name: Optional[str]) -> str:
    """Convert qualified project name to the common tmux session suffix."""
    name = str(project_name or "").strip()
    if ":" not in name:
        return ""
    repo_part, branch = name.split(":", 1)
    repo_name = repo_part.split("/")[-1].strip()
    if not repo_name or not branch:
        return ""
    return f"{repo_name}/{branch}"


def _normalize_tmux_session_key(value: Optional[str]) -> str:
    try:
        from i3_project_manager.core.identity import normalize_session_name_key

        return normalize_session_name_key(value)
    except ImportError:
        raw = str(value or "").strip().lower()
        return "".join(ch if ch.isalnum() else "-" for ch in raw).strip("-")


def _tmux_session_project_hints() -> dict[str, str]:
    """Map normalized tmux session names to unique discovered worktree projects."""
    repos_file = os.path.expanduser("~/.config/i3/repos.json")
    if not os.path.exists(repos_file):
        _DISCOVERED_TMUX_PROJECT_HINT_CACHE.update({
            "mtime_ns": None,
            "size": None,
            "mapping": {},
        })
        return {}

    try:
        stat_result = os.stat(repos_file)
    except OSError:
        return {}

    cached_mapping = _DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("mapping")
    if (
        _DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("mtime_ns") == stat_result.st_mtime_ns
        and _DISCOVERED_TMUX_PROJECT_HINT_CACHE.get("size") == stat_result.st_size
        and isinstance(cached_mapping, dict)
    ):
        return dict(cached_mapping)

    try:
        with open(repos_file, "r") as f:
            payload = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}

    repositories = payload.get("repositories", []) if isinstance(payload, dict) else []
    grouped: dict[str, set[str]] = {}
    for repo in repositories if isinstance(repositories, list) else []:
        if not isinstance(repo, dict):
            continue
        account = str(repo.get("account") or "").strip()
        repo_name = str(repo.get("name") or "").strip()
        if not account or not repo_name:
            continue
        worktrees = repo.get("worktrees", [])
        for worktree in worktrees if isinstance(worktrees, list) else []:
            if not isinstance(worktree, dict):
                continue
            branch = str(worktree.get("branch") or "").strip()
            if not branch:
                continue
            qualified_name = f"{account}/{repo_name}:{branch}"
            suffix_key = _normalize_tmux_session_key(_project_session_suffix(qualified_name))
            if not suffix_key:
                continue
            grouped.setdefault(suffix_key, set()).add(qualified_name)

    mapping = {
        session_key: sorted(qualified_names)[0]
        for session_key, qualified_names in grouped.items()
        if len(qualified_names) == 1
    }
    _DISCOVERED_TMUX_PROJECT_HINT_CACHE.update({
        "mtime_ns": stat_result.st_mtime_ns,
        "size": stat_result.st_size,
        "mapping": dict(mapping),
    })
    return mapping


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


def get_process_tty_path(pid: int) -> Optional[str]:
    """Return controlling PTY path for a process when available."""
    try:
        proc_stat = Path(f"/proc/{pid}/stat").read_text()
        last_paren = proc_stat.rfind(")")
        if last_paren == -1:
            return None
        stat_fields = proc_stat[last_paren + 2:].split()
        if len(stat_fields) < 5:
            return None

        tty_nr = int(stat_fields[4])
        if tty_nr == 0:
            return None

        major = (tty_nr >> 8) & 0xFFF
        minor = tty_nr & 0xFF
        if major == 136:
            return f"/dev/pts/{minor}"
    except Exception as e:
        logger.debug(f"get_process_tty_path failed for PID {pid}: {e}")
    return None


async def get_tmux_context_for_pid(pid: int) -> dict[str, Any]:
    """Return tmux session/window/pane metadata for a process when available."""
    tty_path = get_process_tty_path(pid)
    context = {
        "tmux_session": None,
        "tmux_window": None,
        "tmux_pane": None,
        "pane_pid": None,
        "pane_title": None,
        "pane_active": None,
        "window_active": None,
        "pty": tty_path,
    }
    if not tty_path:
        return context

    try:
        panes = await list_tmux_panes()
        for pane in panes:
            pane_tty = str(pane.get("pty") or "").strip()
            if pane_tty != tty_path:
                continue

            context["tmux_session"] = pane.get("tmux_session")
            context["tmux_window"] = pane.get("tmux_window")
            context["tmux_pane"] = pane.get("tmux_pane")
            context["pane_pid"] = pane.get("pane_pid")
            context["pane_title"] = pane.get("pane_title")
            context["pane_active"] = pane.get("pane_active")
            context["window_active"] = pane.get("window_active")
            return context
    except FileNotFoundError:
        return context
    except Exception as e:
        logger.debug(f"get_tmux_context_for_pid failed: {e}")

    return context


async def list_tmux_panes() -> list[dict[str, Any]]:
    """Return live tmux pane metadata keyed by tmux-native pane identity."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "tmux",
            "list-panes",
            "-a",
            "-F",
            _TMUX_LIST_PANES_FORMAT,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=2.0)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            logger.debug("list_tmux_panes: tmux list-panes timed out")
            return []
        if proc.returncode != 0:
            return []
    except FileNotFoundError:
        return []
    except Exception as exc:
        logger.debug("list_tmux_panes failed: %s", exc)
        return []

    return _parse_tmux_panes_output(stdout.decode("utf-8"))


def list_tmux_panes_sync() -> list[dict[str, Any]]:
    """Return live tmux pane metadata synchronously for hot UI/export paths."""
    try:
        proc = subprocess.run(
            ["tmux", "list-panes", "-a", "-F", _TMUX_LIST_PANES_FORMAT],
            capture_output=True,
            text=True,
            timeout=2.0,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []
    except Exception as exc:
        logger.debug("list_tmux_panes_sync failed: %s", exc)
        return []
    if proc.returncode != 0:
        return []
    return _parse_tmux_panes_output(proc.stdout)


def _parse_tmux_panes_output(stdout_text: str) -> list[dict[str, Any]]:
    """Parse `tmux list-panes` output into normalized pane dictionaries."""
    panes: list[dict[str, Any]] = []
    for line in stdout_text.strip().splitlines():
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) != 9:
            continue
        pane_tty, session_name, window_ref, pane_id, pane_index, pane_pid_raw, pane_title, pane_active_raw, window_active_raw = parts
        try:
            pane_pid = int(str(pane_pid_raw or "").strip()) if str(pane_pid_raw or "").strip() else None
        except ValueError:
            pane_pid = None
        pane_active = str(pane_active_raw or "").strip() == "1"
        window_active = str(window_active_raw or "").strip() == "1"
        panes.append({
            "tmux_session": str(session_name or "").strip() or None,
            "tmux_window": str(window_ref or "").strip() or None,
            "tmux_pane": str(pane_id or pane_index or "").strip() or None,
            "pane_index": str(pane_index or "").strip() or None,
            "pane_pid": pane_pid,
            "pane_title": str(pane_title or "").strip() or None,
            "pane_active": pane_active,
            "window_active": window_active,
            "pty": str(pane_tty or "").strip() or None,
        })
    return panes


def tmux_target_exists(
    *,
    tmux_session: Optional[str] = None,
    tmux_window: Optional[str] = None,
    tmux_pane: Optional[str] = None,
    pty: Optional[str] = None,
) -> bool:
    """Return whether the claimed tmux target exists in the live tmux server."""
    if not (tmux_session or tmux_window or tmux_pane or pty):
        return False

    try:
        proc = subprocess.run(
            [
                "tmux",
                "list-panes",
                "-a",
                "-F",
                "#{session_name}\t#{window_index}:#{window_name}\t#{pane_id}\t#{pane_tty}",
            ],
            capture_output=True,
            text=True,
            timeout=2.0,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False

    if proc.returncode != 0:
        return False

    expected_session = str(tmux_session or "").strip()
    expected_window = str(tmux_window or "").strip()
    expected_pane = str(tmux_pane or "").strip()
    expected_pty = str(pty or "").strip()

    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 4:
            continue
        live_session, live_window, live_pane, live_pty = (
            str(parts[0] or "").strip(),
            str(parts[1] or "").strip(),
            str(parts[2] or "").strip(),
            str(parts[3] or "").strip(),
        )
        if expected_session and live_session != expected_session:
            continue
        if expected_window and live_window != expected_window:
            continue
        if expected_pane and live_pane != expected_pane:
            continue
        if expected_pty and live_pty != expected_pty:
            continue
        return True

    return False


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


async def query_daemon_for_terminal_anchor(terminal_anchor_id: str) -> Optional[dict]:
    """Query daemon for canonical terminal anchor state."""
    anchor = str(terminal_anchor_id or "").strip()
    if not anchor:
        return None

    uid = os.getuid()
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    socket_path = os.path.join(runtime_dir, "i3-project-daemon", "ipc.sock")
    if not os.path.exists(socket_path):
        logger.debug(f"Daemon socket not found: {socket_path}")
        return None

    try:
        request = json.dumps({
            "jsonrpc": "2.0",
            "method": "get_terminal_anchor",
            "params": {
                "terminal_anchor_id": anchor,
            },
            "id": 1,
        })
        reader, writer = await asyncio.wait_for(
            asyncio.open_unix_connection(socket_path),
            timeout=2.0,
        )
        try:
            writer.write(request.encode("utf-8"))
            writer.write_eof()
            await writer.drain()
            response_data = await asyncio.wait_for(reader.read(), timeout=2.0)
            response = json.loads(response_data.decode("utf-8"))
            if "error" in response:
                logger.debug(f"query_daemon_for_terminal_anchor: daemon error={response['error']}")
                return None
            return response.get("result", {})
        finally:
            writer.close()
            await writer.wait_closed()
    except Exception as e:
        logger.debug(f"query_daemon_for_terminal_anchor failed: {e}")
        return None


async def find_window_via_tmux_client(
    target_pid: int,
    *,
    tmux_ctx: Optional[dict[str, Optional[str]]] = None,
) -> Optional[int]:
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
    try:
        tmux_ctx = tmux_ctx or await get_tmux_context_for_pid(target_pid)
        target_pts = tmux_ctx.get("pty")
        if not target_pts:
            return None

        # Step 2: Find which tmux session owns this PTY
        session_name = tmux_ctx.get("tmux_session")

        if not session_name:
            logger.debug(f"No tmux session found for PTY {target_pts}")
            return None

        # Step 3: Find which tmux client is attached to this session
        proc = await asyncio.create_subprocess_exec(
            "tmux",
            "list-clients",
            "-F",
            "#{client_pid} #{session_name}",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=2.0)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            logger.debug("tmux command timed out")
            return None

        if proc.returncode != 0:
            return None

        client_pid = None
        stdout_text = stdout.decode('utf-8')
        for line in stdout_text.strip().split("\n"):
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
    except Exception as e:
        logger.debug(f"find_window_via_tmux_client failed: {e}")
        return None
