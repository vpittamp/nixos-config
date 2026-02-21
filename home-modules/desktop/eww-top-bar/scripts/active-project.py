#!/usr/bin/env python3
"""Active i3pm project monitoring for Eww top bar widgets

Feature 101: Reads active project from active-worktree.json (single source of truth).
Feature 123: Uses inotify for instant file change detection (no polling overhead).

Output format:
{
  "project": "vpittamp/nixos-config:main",  // qualified name or "Global"
  "active": true,           // true if project is active, false if in global mode
  "branch_number": "079",   // extracted numeric prefix (or null)
  "icon": "🌿",             // project icon
  "is_worktree": true,      // true if worktree project (always true in Feature 101)
  "formatted_label": "079 - nixos-config",  // formatted display name
  "remote_enabled": false,  // true when active worktree is configured as SSH project
  "remote_target": "",      // formatted target like user@host:port
  "remote_target_short": "",// formatted target without port
  "remote_directory": "",   // remote working directory
  "remote_directory_display": "" // home-shortened display path
}

Usage:
  python3 active-project.py

Exits with code 0 on normal termination, 1 on errors.

Feature 079: US7 - Top Bar Enhancement (T050, T051)
Feature 101: Migrate to active-worktree.json as single source of truth
Feature 123: Convert from 2s polling to inotify-based file watching
"""

import json
import os
import re
import select
import subprocess
import struct
import sys
from pathlib import Path
from typing import Any, Dict, Iterator, Optional

# Feature 101: active-worktree.json is the single source of truth
ACTIVE_WORKTREE_FILE = Path.home() / ".config" / "i3" / "active-worktree.json"

# inotify constants
IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800

# Watch for file modifications (covers atomic saves via rename)
WATCH_MASK = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE_SELF


class InotifyWatcher:
    """Simple inotify wrapper for watching file changes."""

    def __init__(self):
        self.fd = None
        self.wd = None
        self.poll = None

    def start(self, path: Path) -> bool:
        """Start watching a file. Returns True if successful."""
        try:
            import ctypes
            import ctypes.util

            # Load libc
            libc_name = ctypes.util.find_library('c')
            if not libc_name:
                return False
            libc = ctypes.CDLL(libc_name, use_errno=True)

            # Initialize inotify
            self.fd = libc.inotify_init1(0)  # 0 = blocking mode
            if self.fd < 0:
                return False

            # Watch the parent directory (for atomic saves that create new file)
            watch_path = str(path.parent).encode('utf-8')
            self.wd = libc.inotify_add_watch(self.fd, watch_path, WATCH_MASK)
            if self.wd < 0:
                os.close(self.fd)
                self.fd = None
                return False

            # Set up poll for timeout support
            self.poll = select.poll()
            self.poll.register(self.fd, select.POLLIN)
            self._target_filename = path.name

            return True
        except Exception:
            return False

    def wait(self, timeout_ms: int = 30000) -> bool:
        """Wait for file change. Returns True if file changed, False on timeout."""
        if self.poll is None:
            return False

        try:
            events = self.poll.poll(timeout_ms)
            if not events:
                return False  # Timeout

            # Read and process inotify events
            data = os.read(self.fd, 4096)
            offset = 0
            while offset < len(data):
                # inotify_event structure: wd(4) + mask(4) + cookie(4) + len(4) + name(len)
                wd, mask, cookie, length = struct.unpack_from('iIII', data, offset)
                offset += 16
                if length > 0:
                    name = data[offset:offset + length].rstrip(b'\x00').decode('utf-8', errors='replace')
                    offset += length
                    # Check if this event is for our target file
                    if name == self._target_filename:
                        return True
                else:
                    # Event without name (e.g., IN_DELETE_SELF)
                    return True

            return False
        except Exception:
            return False

    def stop(self):
        """Stop watching."""
        if self.fd is not None:
            try:
                os.close(self.fd)
            except Exception:
                pass
            self.fd = None
            self.wd = None
            self.poll = None


class ActiveProjectMonitor:
    """Monitor i3pm active project via state file"""

    def __init__(self):
        self.project = "Global"
        self.active = False
        self.branch_number = None
        self.icon = "📁"
        self.is_worktree = False
        self.formatted_label = "Global"
        self.remote_enabled = False
        self.remote_target = ""
        self.remote_target_short = ""
        self.remote_directory = ""
        self.remote_directory_display = ""
        self.execution_mode = "global"
        self.host_alias = "global"
        self.connection_key = "global"
        self.identity_key = "global:global"
        self.context_key = ""
        self._last_state_hash = None
        self._cached_worktree_data: Optional[dict] = None
        self._cached_worktree_mtime_ns: int = 0

    def _format_remote_target(self, user: str, host: str, port: int) -> str:
        """Format SSH target for display."""
        if not host:
            return ""
        target = f"{user}@{host}" if user else host
        if port and port != 22:
            return f"{target}:{port}"
        return target

    def _normalize_connection_key(self, value: str) -> str:
        """Normalize host/connection key for stable context identity."""
        raw = str(value or "").strip().lower()
        if not raw:
            return "unknown"
        return re.sub(r"[^a-z0-9@._:-]+", "-", raw)

    def _local_host_alias(self) -> str:
        """Resolve host alias for local execution mode."""
        host = (
            os.environ.get("I3PM_LOCAL_HOST_ALIAS")
            or os.environ.get("HOSTNAME")
            or os.uname().nodename
        )
        return str(host).strip().lower() or "localhost"

    def _update_context_identity(self) -> None:
        """Recompute canonical identity fields for top-bar consumers."""
        if not self.active:
            self.execution_mode = "global"
            self.host_alias = "global"
            self.connection_key = "global"
            self.identity_key = "global:global"
            self.context_key = ""
            return

        if self.remote_enabled:
            self.execution_mode = "ssh"
            self.host_alias = self.remote_target_short or self.remote_target or "unknown"
            self.connection_key = self._normalize_connection_key(self.host_alias)
        else:
            self.execution_mode = "local"
            self.host_alias = self._local_host_alias()
            self.connection_key = f"local@{self._normalize_connection_key(self.host_alias)}"

        self.identity_key = f"{self.execution_mode}:{self.connection_key}"
        self.context_key = f"{self.project}::{self.execution_mode}::{self.connection_key}"

    def _read_worktree_file(self, force: bool = False) -> Optional[dict]:
        """Read active worktree from state file (Feature 101)"""
        try:
            if not ACTIVE_WORKTREE_FILE.exists():
                self._cached_worktree_data = None
                self._cached_worktree_mtime_ns = 0
                return None

            stat = ACTIVE_WORKTREE_FILE.stat()
            if (
                not force
                and self._cached_worktree_data is not None
                and stat.st_mtime_ns == self._cached_worktree_mtime_ns
            ):
                return self._cached_worktree_data

            with open(ACTIVE_WORKTREE_FILE, "r") as f:
                data = json.load(f)

            if not data or "qualified_name" not in data:
                self._cached_worktree_data = None
                self._cached_worktree_mtime_ns = stat.st_mtime_ns
                return None

            self._cached_worktree_data = data
            self._cached_worktree_mtime_ns = stat.st_mtime_ns
            return data

        except (json.JSONDecodeError, Exception):
            return None

    def _is_truthy(self, value: Any) -> bool:
        """Interpret booleans represented as Python/bool/string values."""
        if isinstance(value, bool):
            return value
        if value is None:
            return False
        return str(value).strip().lower() in {"1", "true", "yes", "on"}

    def _iter_tree_nodes(self, root: Dict[str, Any]) -> Iterator[Dict[str, Any]]:
        """Iterate over Sway tree nodes (including floating nodes)."""
        stack = [root]
        while stack:
            node = stack.pop()
            if not isinstance(node, dict):
                continue
            yield node
            children = node.get("nodes", [])
            floating = node.get("floating_nodes", [])
            if isinstance(children, list):
                stack.extend(reversed(children))
            if isinstance(floating, list):
                stack.extend(reversed(floating))

    def _project_from_marks(self, marks: Any) -> str:
        """
        Extract qualified project name from unified window marks.

        Mark format: scoped:<app_name>:<qualified_project_name>:<window_id>
        """
        if not isinstance(marks, list):
            return ""
        for mark in marks:
            if not isinstance(mark, str):
                continue
            parts = mark.split(":")
            if len(parts) < 4:
                continue
            if parts[0] not in {"scoped", "global"}:
                continue
            project_name = ":".join(parts[2:-1]).strip()
            if project_name:
                return project_name
        return ""

    def _read_process_env(self, pid: int) -> Dict[str, str]:
        """Read process environment from /proc/<pid>/environ."""
        if pid <= 1:
            return {}
        environ_path = Path("/proc") / str(pid) / "environ"
        if not environ_path.exists():
            return {}
        try:
            env_raw = environ_path.read_bytes()
        except (OSError, PermissionError):
            return {}

        env: Dict[str, str] = {}
        for entry in env_raw.split(b"\x00"):
            if b"=" not in entry:
                continue
            key_raw, value_raw = entry.split(b"=", 1)
            try:
                key = key_raw.decode("utf-8", errors="ignore")
                value = value_raw.decode("utf-8", errors="ignore")
            except Exception:
                continue
            if key:
                env[key] = value
        return env

    def _focused_project_runtime_context(self) -> Optional[Dict[str, Any]]:
        """
        Derive remote/local mode from the currently focused project-scoped window.

        This prevents stale active-worktree remote metadata from mislabeling
        the top bar when the focused project window is actually local.
        """
        try:
            result = subprocess.run(
                ["swaymsg", "-t", "get_tree", "-r"],
                capture_output=True,
                text=True,
                timeout=0.5,
                check=False,
            )
        except Exception:
            return None

        if result.returncode != 0 or not result.stdout.strip():
            return None

        try:
            tree = json.loads(result.stdout)
        except json.JSONDecodeError:
            return None

        focused_node = None
        for node in self._iter_tree_nodes(tree):
            if not node.get("focused", False):
                continue
            if node.get("pid") is None and node.get("window") is None and node.get("app_id") is None:
                continue
            focused_node = node
            break

        if not isinstance(focused_node, dict):
            return None

        pid_raw = focused_node.get("pid")
        try:
            pid = int(pid_raw) if pid_raw is not None else 0
        except (TypeError, ValueError):
            pid = 0

        env = self._read_process_env(pid)
        project_name = str(env.get("I3PM_PROJECT_NAME", "")).strip()
        if not project_name:
            project_name = self._project_from_marks(focused_node.get("marks", []))
        if not project_name:
            return None

        explicit_remote = "I3PM_REMOTE_ENABLED" in env
        remote_enabled = self._is_truthy(env.get("I3PM_REMOTE_ENABLED")) if explicit_remote else False

        remote_host = str(env.get("I3PM_REMOTE_HOST", "")).strip()
        remote_user = str(env.get("I3PM_REMOTE_USER", "")).strip()
        remote_port_raw = env.get("I3PM_REMOTE_PORT", "22")
        try:
            remote_port = int(remote_port_raw)
        except (TypeError, ValueError):
            remote_port = 22
        remote_dir = str(env.get("I3PM_REMOTE_DIR", "")).strip()

        remote_target = self._format_remote_target(remote_user, remote_host, remote_port)
        remote_target_short = f"{remote_user}@{remote_host}" if remote_user and remote_host else remote_host

        return {
            "project": project_name,
            "explicit_remote": explicit_remote,
            "remote_enabled": bool(remote_enabled and remote_host),
            "remote_target": remote_target,
            "remote_target_short": remote_target_short,
            "remote_directory": remote_dir,
            "remote_directory_display": remote_dir.replace(str(Path.home()), "~") if remote_dir else "",
        }

    def _extract_branch_number(self, branch: str) -> Optional[str]:
        """Extract numeric prefix from branch name (T051)"""
        if not branch:
            return None

        match = re.match(r'^(\d+)-', branch)
        if match:
            return match.group(1)
        return None

    def _update_state(self, force_read: bool = False) -> bool:
        """Update active project state from file. Returns True if state changed."""
        worktree_data = self._read_worktree_file(force=force_read)

        if worktree_data and worktree_data.get("qualified_name"):
            qualified_name = worktree_data["qualified_name"]
            self.project = qualified_name
            self.active = True

            # Feature 101: All projects are worktrees
            self.is_worktree = True

            # Extract branch info from worktree data
            branch = worktree_data.get("branch", "")
            self.branch_number = self._extract_branch_number(branch)

            # Use repo name as display name, branch for context
            repo_name = worktree_data.get("repo_name", "")
            if self.branch_number:
                self.formatted_label = f"{self.branch_number} - {repo_name}"
            else:
                # For main branch, just show repo name
                self.formatted_label = repo_name if repo_name else branch

            # Icon based on branch type
            if branch == "main" or branch == "master":
                self.icon = "📦"  # Main/master branch
            else:
                self.icon = "🌿"  # Feature/worktree branch

            remote = worktree_data.get("remote")
            remote_enabled = isinstance(remote, dict) and bool(remote.get("enabled"))
            if remote_enabled:
                host = str(remote.get("host") or "").strip()
                user = str(remote.get("user") or "").strip()
                port_raw = remote.get("port", 22)
                try:
                    port = int(port_raw)
                except (TypeError, ValueError):
                    port = 22
                remote_dir = str(remote.get("remote_dir") or remote.get("working_dir") or "").strip()

                self.remote_enabled = bool(host)
                self.remote_target = self._format_remote_target(user, host, port)
                self.remote_target_short = f"{user}@{host}" if user and host else host
                self.remote_directory = remote_dir
                self.remote_directory_display = (
                    remote_dir.replace(str(Path.home()), "~")
                    if remote_dir
                    else ""
                )
            else:
                self.remote_enabled = False
                self.remote_target = ""
                self.remote_target_short = ""
                self.remote_directory = ""
                self.remote_directory_display = ""

            # Prefer focused window runtime context for mode labeling when available.
            # This keeps the top bar aligned with the active window's local/SSH state.
            focused_ctx = self._focused_project_runtime_context()
            if (
                focused_ctx
                and focused_ctx.get("project") == self.project
                and bool(focused_ctx.get("explicit_remote"))
            ):
                self.remote_enabled = bool(focused_ctx.get("remote_enabled", False))
                self.remote_target = str(focused_ctx.get("remote_target", ""))
                self.remote_target_short = str(focused_ctx.get("remote_target_short", ""))
                self.remote_directory = str(focused_ctx.get("remote_directory", ""))
                self.remote_directory_display = str(
                    focused_ctx.get("remote_directory_display", "")
                )

            self._update_context_identity()
        else:
            # No active project - global mode
            self.project = "Global"
            self.active = False
            self.icon = "🌐"
            self.is_worktree = False
            self.branch_number = None
            self.formatted_label = "Global"
            self.remote_enabled = False
            self.remote_target = ""
            self.remote_target_short = ""
            self.remote_directory = ""
            self.remote_directory_display = ""
            self._update_context_identity()

        # Check if state actually changed
        state_hash = (self.project, self.active, self.branch_number,
                      self.icon, self.is_worktree, self.formatted_label,
                      self.remote_enabled, self.remote_target, self.remote_target_short,
                      self.remote_directory, self.remote_directory_display,
                      self.execution_mode, self.host_alias, self.connection_key,
                      self.identity_key, self.context_key)
        if state_hash == self._last_state_hash:
            return False

        self._last_state_hash = state_hash
        return True

    def _output_state(self):
        """Output current project state as JSON"""
        state = {
            "project": self.project,
            "active": self.active,
            "branch_number": self.branch_number,
            "icon": self.icon,
            "is_worktree": self.is_worktree,
            "formatted_label": self.formatted_label,
            "remote_enabled": self.remote_enabled,
            "remote_target": self.remote_target,
            "remote_target_short": self.remote_target_short,
            "remote_directory": self.remote_directory,
            "remote_directory_display": self.remote_directory_display,
            "execution_mode": self.execution_mode,
            "host_alias": self.host_alias,
            "connection_key": self.connection_key,
            "identity_key": self.identity_key,
            "context_key": self.context_key,
        }
        try:
            print(json.dumps(state), flush=True)
        except BrokenPipeError:
            # Eww can close the listener pipe during reload/restart.
            # Exit cleanly instead of emitting traceback noise.
            sys.exit(0)

    def run(self):
        """Watch state file for active project updates using inotify."""
        # Output initial state
        self._update_state(force_read=True)
        self._output_state()

        # Try to use inotify for efficient file watching
        watcher = InotifyWatcher()
        use_inotify = watcher.start(ACTIVE_WORKTREE_FILE)

        if use_inotify:
            # Feature 123: Event-driven mode with inotify
            # 2s timeout keeps focused-window mode (local vs SSH) responsive.
            while True:
                changed = watcher.wait(timeout_ms=2000)
                state_changed = self._update_state(force_read=changed)
                if changed or state_changed:
                    self._output_state()
        else:
            # Fallback polling mode mirrors the inotify heartbeat cadence.
            import time
            while True:
                time.sleep(2)
                if self._update_state(force_read=True):
                    self._output_state()


if __name__ == "__main__":
    monitor = ActiveProjectMonitor()
    monitor.run()
