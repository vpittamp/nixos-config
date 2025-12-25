"""Window filtering utilities for Feature 037.

This module provides workspace tracking and window filtering utilities for
automatic project-scoped window management.

Key functions:
- WorkspaceTracker: Manages window-workspace-map.json state file
- get_window_i3pm_env: Reads I3PM_* variables from /proc
- get_scratchpad_windows: Queries i3 IPC for scratchpad windows
- validate_workspace_exists: Checks workspace existence via GET_WORKSPACES
- build_batch_move_command: Builds efficient batch i3 commands
"""

import asyncio
import json
import logging
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime

try:
    import i3ipc.aio
except ImportError:
    import i3ipc as i3ipc_sync
    i3ipc.aio = None

from .config import atomic_write_json  # Feature 137: Atomic file writes

logger = logging.getLogger(__name__)


class WorkspaceTracker:
    """Manages persistent window workspace tracking for restoration.

    State file schema (Feature 038 - v1.1):
    {
        "version": "1.1",
        "last_updated": 1730000000.123,
        "windows": {
            "123456": {
                "workspace_number": 2,
                "floating": false,
                "project_name": "nixos",
                "app_name": "vscode",
                "window_class": "Code",
                "last_seen": 1730000000.123,
                "geometry": null,
                "original_scratchpad": false
            }
        }
    }
    """

    def __init__(self, state_file: Path = Path.home() / ".config/i3/window-workspace-map.json"):
        """Initialize workspace tracker.

        Args:
            state_file: Path to window-workspace-map.json
        """
        self.state_file = state_file
        self.windows: Dict[int, Dict] = {}
        self.version = "1.1"  # Feature 038: Updated to v1.1 for geometry and original_scratchpad fields
        self.last_updated = time.time()
        self._lock = asyncio.Lock()

    async def load(self) -> None:
        """Load state from disk.

        Creates empty state file if it doesn't exist.
        Logs warning and reinitializes if file is corrupted.
        """
        async with self._lock:
            if not self.state_file.exists():
                logger.info("Window workspace map not found, creating new one")
                await self._save_unlocked()
                return

            try:
                with self.state_file.open("r") as f:
                    data = json.load(f)

                # Validate version (support both 1.0 and 1.1 for backward compatibility)
                version = data.get("version", "1.0")
                if version not in ["1.0", "1.1"]:
                    logger.warning(f"Unsupported window-workspace-map version: {version}, reinitializing")
                    await self._save_unlocked()
                    return

                # Load windows (keys are strings in JSON, convert to int)
                # Feature 038: v1.0 files will be automatically upgraded to v1.1 on next save
                # Missing geometry/original_scratchpad fields get default values in get_window_workspace()
                self.windows = {int(k): v for k, v in data.get("windows", {}).items()}
                self.last_updated = data.get("last_updated", time.time())

                logger.info(f"Loaded {len(self.windows)} window tracking entries (schema v{version})")

            except (json.JSONDecodeError, ValueError, KeyError) as e:
                logger.error(f"Failed to load window-workspace-map.json: {e}")
                logger.info("Backing up corrupted file and reinitializing")

                # Backup corrupted file
                backup_file = self.state_file.with_suffix(".json.bak")
                self.state_file.rename(backup_file)

                # Reinitialize
                self.windows = {}
                await self._save_unlocked()

    async def save(self) -> None:
        """Save state to disk using atomic write (temp file + rename)."""
        async with self._lock:
            await self._save_unlocked()

    async def _save_unlocked(self) -> None:
        """Internal save without lock (assumes caller holds lock)."""
        self.last_updated = time.time()

        # Build JSON data
        data = {
            "version": self.version,
            "last_updated": self.last_updated,
            "windows": {str(k): v for k, v in self.windows.items()},
        }

        # Feature 137: Use atomic write with fsync for durability
        try:
            await asyncio.to_thread(atomic_write_json, self.state_file, data)
        except Exception as e:
            logger.error(f"Failed to save window-workspace-map.json: {e}")
            raise

    async def track_window(
        self,
        window_id: int,
        workspace_number: int,
        floating: bool,
        project_name: str,
        app_name: str,
        window_class: str,
        geometry: Optional[Dict] = None,
        original_scratchpad: bool = False,
    ) -> None:
        """Track window workspace assignment.

        Args:
            window_id: i3 container ID
            workspace_number: Workspace number (1-70, or -1 for scratchpad)
            floating: True if floating window
            project_name: Project name from I3PM_PROJECT_NAME
            app_name: App name from I3PM_APP_NAME
            window_class: X11 window class
            geometry: Window geometry dict with x, y, width, height (for floating windows), or None
            original_scratchpad: True if window was in scratchpad before project filtering
        """
        async with self._lock:
            self.windows[window_id] = {
                "workspace_number": workspace_number,
                "floating": floating,
                "project_name": project_name,
                "app_name": app_name,
                "window_class": window_class,
                "last_seen": time.time(),
                "geometry": geometry,  # Feature 038: Window geometry for floating windows
                "original_scratchpad": original_scratchpad,  # Feature 038: Scratchpad origin flag
            }

        # Save asynchronously (don't block)
        asyncio.create_task(self.save())

    async def get_window_workspace(self, window_id: int) -> Optional[Dict]:
        """Get tracked workspace and state for window.

        Args:
            window_id: i3 container ID

        Returns:
            Window state dict with workspace_number, floating, geometry, original_scratchpad, etc.
            Returns None if not tracked.

            For backward compatibility with old JSON files:
            - geometry defaults to None if missing
            - original_scratchpad defaults to False if missing
        """
        async with self._lock:
            if window_id in self.windows:
                entry = self.windows[window_id]
                # Feature 038: Return full state dict with backward-compatible defaults
                return {
                    "workspace_number": entry.get("workspace_number", 1),
                    "floating": entry.get("floating", False),
                    "project_name": entry.get("project_name", ""),
                    "app_name": entry.get("app_name", ""),
                    "window_class": entry.get("window_class", ""),
                    "last_seen": entry.get("last_seen", time.time()),
                    "geometry": entry.get("geometry", None),  # Backward compatible default
                    "original_scratchpad": entry.get("original_scratchpad", False),  # Backward compatible default
                }
            return None

    async def remove_window(self, window_id: int) -> None:
        """Remove window from tracking (e.g., on window close).

        Args:
            window_id: i3 container ID
        """
        async with self._lock:
            if window_id in self.windows:
                del self.windows[window_id]

        # Save asynchronously
        asyncio.create_task(self.save())

    async def cleanup_stale_entries(self, i3_conn, max_age_days: int = 30) -> int:
        """Remove stale tracking entries (garbage collection).

        Args:
            i3_conn: i3 IPC connection
            max_age_days: Remove entries older than this many days

        Returns:
            Number of entries removed
        """
        # Get all current window IDs from i3 tree
        tree = await i3_conn.get_tree()
        current_window_ids = set()

        def collect_window_ids(con):
            if con.window:
                current_window_ids.add(con.id)
            for child in con.nodes:
                collect_window_ids(child)
            for child in con.floating_nodes:
                collect_window_ids(child)

        collect_window_ids(tree)

        # Find stale entries
        now = time.time()
        max_age_seconds = max_age_days * 86400
        stale_window_ids = []

        async with self._lock:
            for window_id, entry in list(self.windows.items()):
                # Remove if window doesn't exist in i3 tree
                if window_id not in current_window_ids:
                    stale_window_ids.append(window_id)
                    continue

                # Remove if entry is too old
                age_seconds = now - entry.get("last_seen", now)
                if age_seconds > max_age_seconds:
                    stale_window_ids.append(window_id)

            # Remove stale entries
            for window_id in stale_window_ids:
                del self.windows[window_id]

        if stale_window_ids:
            logger.info(f"Cleaned up {len(stale_window_ids)} stale window tracking entries")
            await self.save()

        return len(stale_window_ids)

    async def get_project_windows(self, project_name: str) -> List[Tuple[int, Dict]]:
        """Get all tracked windows for a project.

        Args:
            project_name: Project to filter by

        Returns:
            List of (window_id, entry_dict) tuples
        """
        async with self._lock:
            return [
                (window_id, entry.copy())
                for window_id, entry in self.windows.items()
                if entry.get("project_name") == project_name
            ]


async def _get_window_pid_via_xprop(window_xid: int) -> Optional[int]:
    """Get process ID for window using xprop as fallback.

    Args:
        window_xid: X11 window ID

    Returns:
        Process ID or None if not available

    Note:
        Uses subprocess.run to execute xprop command.
        Performance: ~10-20ms per call (cached by OS).
    """
    try:
        # Run xprop in subprocess (i3 process ensures xprop is available)
        proc = await asyncio.create_subprocess_exec(
            "xprop", "-id", str(window_xid), "_NET_WM_PID",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=1.0)

        if proc.returncode != 0:
            logger.debug(f"xprop failed for window {window_xid}: {stderr.decode()}")
            return None

        # Parse output: "_NET_WM_PID(CARDINAL) = 12345"
        output = stdout.decode().strip()
        if " = " in output:
            pid_str = output.split(" = ")[1]
            return int(pid_str)

        logger.debug(f"Could not parse xprop output for window {window_xid}: {output}")
        return None

    except asyncio.TimeoutError:
        logger.warning(f"xprop timeout for window {window_xid}")
        return None
    except (ValueError, IndexError) as e:
        logger.warning(f"Failed to parse PID from xprop output: {e}")
        return None
    except FileNotFoundError:
        logger.error("xprop command not found. Install x11-utils or xorg-xprop package.")
        return None


async def get_window_i3pm_env(window_id: int, pid: Optional[int] = None, window_xid: Optional[int] = None) -> Dict[str, str]:
    """Read I3PM_* environment variables from window's process.

    Args:
        window_id: i3 container ID (for logging)
        pid: Process ID (optional, will use xprop fallback if None)
        window_xid: X11 window ID (required if pid is None for xprop fallback)

    Returns:
        Dict of I3PM_* environment variables (empty dict if process not found)

    Environment variables:
        I3PM_APP_ID: Unique instance identifier
        I3PM_APP_NAME: Application name from registry
        I3PM_PROJECT_NAME: Project name (empty string = global)
        I3PM_SCOPE: "scoped" or "global"
        ... (see Feature 035 data-model.md)

    Note:
        i3ipc library's node.pid is unreliable (often returns None).
        When pid is None, uses xprop to query _NET_WM_PID property via X11 window ID.
    """
    # If no PID from i3, try xprop fallback
    if not pid:
        logger.debug(f"Window {window_id} missing i3 PID, window_xid={window_xid}")
        if window_xid:
            logger.info(f"Window {window_id} has no i3 PID, trying xprop fallback for X11 window {window_xid}")
            pid = await _get_window_pid_via_xprop(window_xid)
            if pid:
                logger.info(f"✓ Got PID {pid} via xprop for window {window_id}")
            else:
                logger.warning(f"Window {window_id} (X11 {window_xid}) has no PID via xprop, treating as global")
                return {}
        else:
            logger.warning(f"Window {window_id} has no PID and no X11 window ID (i3_id={window_id}, xid={window_xid}), treating as global")
            return {}

    environ_path = Path(f"/proc/{pid}/environ")

    try:
        # Try direct read first (works for same namespace)
        # If permission denied, treat as global (different namespace/process)
        with environ_path.open("rb") as f:
            environ_bytes = f.read()

        # Parse environment (null-separated key=value pairs)
        environ_str = environ_bytes.decode("utf-8", errors="ignore")
        env_pairs = [item.split("=", 1) for item in environ_str.split("\0") if "=" in item]
        env_vars = dict(env_pairs)

        # Extract I3PM_* variables
        i3pm_vars = {k: v for k, v in env_vars.items() if k.startswith("I3PM_")}

        if not i3pm_vars:
            logger.debug(f"Window {window_id} (PID {pid}) has no I3PM_* variables, treating as global")

        return i3pm_vars

    except asyncio.TimeoutError:
        logger.warning(f"Timeout reading environ for PID {pid}")
        return {}

    except Exception as e:
        logger.warning(f"Failed to read /proc/{pid}/environ for window {window_id}: {e}")
        return {}


async def get_scratchpad_windows(i3_conn) -> List:
    """Query i3 IPC for all scratchpad windows.

    Args:
        i3_conn: i3 IPC connection

    Returns:
        List of i3 Con objects in scratchpad
    """
    tree = await i3_conn.get_tree()
    scratchpad_windows = []

    def find_scratchpad(con):
        # Scratchpad is a special workspace named "__i3_scratch"
        if con.name == "__i3_scratch":
            # Collect all windows in scratchpad
            # Feature 046: Include both X11 (window.window) and Wayland (window.app_id) windows
            for window in con.floating_nodes:
                if window.window is not None or (hasattr(window, 'app_id') and window.app_id):
                    scratchpad_windows.append(window)
        for child in con.nodes:
            find_scratchpad(child)

    find_scratchpad(tree)

    return scratchpad_windows


async def validate_workspace_exists(i3_conn, workspace_number: int) -> bool:
    """Check if workspace exists using GET_WORKSPACES IPC.

    Args:
        i3_conn: i3 IPC connection
        workspace_number: Workspace number to validate (1-70)

    Returns:
        True if workspace exists (has an output assignment)
    """
    # Get all workspaces
    workspaces = await i3_conn.get_workspaces()

    # Check if workspace number exists
    for ws in workspaces:
        # Workspace name is "N" or "N:name"
        ws_num_str = ws.num if hasattr(ws, 'num') else ws.name.split(":", 1)[0]
        try:
            if int(ws_num_str) == workspace_number:
                return True
        except ValueError:
            continue

    return False


def build_batch_move_command(commands: List[str]) -> str:
    """Build efficient batch i3 command from list of commands.

    Args:
        commands: List of i3 commands (e.g., '[con_id="123"] move scratchpad')

    Returns:
        Single command string with ';' separators for batch execution

    Example:
        >>> build_batch_move_command([
        ...     '[con_id="123"] move scratchpad',
        ...     '[con_id="456"] move scratchpad',
        ... ])
        '[con_id="123"] move scratchpad; [con_id="456"] move scratchpad'
    """
    return "; ".join(commands)


async def hide_windows_batch(
    i3_conn,
    window_ids: List[int],
    workspace_tracker: WorkspaceTracker,
) -> Tuple[int, List[str]]:
    """Hide multiple windows in single batch operation.

    Args:
        i3_conn: i3 IPC connection
        window_ids: List of window container IDs to hide
        workspace_tracker: WorkspaceTracker instance for saving positions

    Returns:
        (hidden_count, errors) tuple

    Side effects:
        - Updates workspace_tracker with current positions
        - Moves windows to scratchpad via i3 IPC
    """
    if not window_ids:
        return (0, [])

    # Get current i3 tree to find window positions
    tree = await i3_conn.get_tree()
    window_map = {}

    def collect_windows(con):
        # Feature 046: Check for both X11 (con.window) and Wayland (con.app_id) windows
        if con.id in window_ids and (con.window is not None or (hasattr(con, 'app_id') and con.app_id)):
            # Find workspace
            workspace = con
            while workspace and workspace.type != "workspace":
                workspace = workspace.parent
            if workspace:
                window_map[con.id] = {
                    "workspace_number": workspace.num,
                    "floating": con.type == "floating_con",
                    "window_class": con.window_class or "Unknown",
                }
        for child in con.nodes:
            collect_windows(child)
        for child in con.floating_nodes:
            collect_windows(child)

    collect_windows(tree)

    # Track window positions before hiding
    for window_id in window_ids:
        if window_id in window_map:
            info = window_map[window_id]

            # Read I3PM_* environment variables
            try:
                window_con = None
                # Find window con to get PID
                def find_window(con):
                    nonlocal window_con
                    if con.id == window_id:
                        window_con = con
                        return
                    for child in con.nodes:
                        find_window(child)
                    for child in con.floating_nodes:
                        find_window(child)

                find_window(tree)

                if window_con:
                    i3pm_env = await get_window_i3pm_env(window_id, window_con.pid, window_con.window)
                    project_name = i3pm_env.get("I3PM_PROJECT_NAME", "")
                    app_name = i3pm_env.get("I3PM_APP_NAME", "unknown")
                else:
                    project_name = ""
                    app_name = "unknown"

                await workspace_tracker.track_window(
                    window_id=window_id,
                    workspace_number=info["workspace_number"],
                    floating=info["floating"],
                    project_name=project_name,
                    app_name=app_name,
                    window_class=info["window_class"],
                )

            except Exception as e:
                logger.error(f"Failed to track window {window_id}: {e}")

    # Build batch hide command
    hide_commands = [f'[con_id="{window_id}"] move scratchpad' for window_id in window_ids]
    batch_command = build_batch_move_command(hide_commands)

    # Execute batch command
    errors = []
    try:
        result = await i3_conn.command(batch_command)
        # Check for individual command failures
        for i, reply in enumerate(result):
            if not reply.success:
                window_id = window_ids[i]
                errors.append(f"Failed to hide window {window_id}: {reply.error}")

    except Exception as e:
        logger.error(f"Batch hide command failed: {e}")
        errors.append(str(e))
        return (0, errors)

    hidden_count = len(window_ids) - len(errors)
    return (hidden_count, errors)


async def restore_windows_batch(
    i3_conn,
    window_ids: List[int],
    workspace_tracker: WorkspaceTracker,
    fallback_workspace: int = 1,
) -> Tuple[int, List[str], List[str]]:
    """Restore multiple windows from scratchpad in single batch operation.

    Args:
        i3_conn: i3 IPC connection
        window_ids: List of window container IDs to restore
        workspace_tracker: WorkspaceTracker instance for loading positions
        fallback_workspace: Workspace to use if tracked workspace invalid

    Returns:
        (restored_count, errors, fallback_warnings) tuple

    Side effects:
        - Moves windows from scratchpad to tracked workspaces via i3 IPC
        - Updates workspace_tracker with restored positions
    """
    if not window_ids:
        return (0, [], [])

    restore_commands = []
    errors = []
    fallback_warnings = []

    for window_id in window_ids:
        # Get tracked workspace
        tracked = await workspace_tracker.get_window_workspace(window_id)

        if tracked:
            # Feature 038: get_window_workspace returns Dict, not tuple
            workspace_number = tracked.get("workspace_number", fallback_workspace)
            floating = tracked.get("floating", False)

            # Validate workspace exists
            if not await validate_workspace_exists(i3_conn, workspace_number):
                logger.warning(
                    f"Workspace {workspace_number} doesn't exist for window {window_id}, "
                    f"falling back to workspace {fallback_workspace}"
                )
                fallback_warnings.append(
                    f"Window {window_id}: WS {workspace_number} → WS {fallback_workspace} (fallback)"
                )
                workspace_number = fallback_workspace
        else:
            # No tracking info, use fallback
            workspace_number = fallback_workspace
            floating = False

        # Build restore command
        # Feature 046: For Sway scratchpad restoration, use 'scratchpad show' first
        # See: https://github.com/swaywm/sway/blob/master/sway/commands/scratchpad.c
        floating_cmd = "floating enable" if floating else "floating disable"
        restore_commands.append(
            f'[con_id="{window_id}"] scratchpad show, move workspace number {workspace_number}, {floating_cmd}'
        )

    # Execute batch restore command
    batch_command = build_batch_move_command(restore_commands)

    try:
        result = await i3_conn.command(batch_command)
        # Check for individual command failures
        for i, reply in enumerate(result):
            if not reply.success:
                window_id = window_ids[i]
                errors.append(f"Failed to restore window {window_id}: {reply.error}")

    except Exception as e:
        logger.error(f"Batch restore command failed: {e}")
        errors.append(str(e))
        return (0, errors, fallback_warnings)

    restored_count = len(window_ids) - len(errors)
    return (restored_count, errors, fallback_warnings)
# Force rebuild Tue Nov  4 05:29:55 AM EST 2025
# Force rebuild Tue Nov  4 05:50:56 AM EST 2025
