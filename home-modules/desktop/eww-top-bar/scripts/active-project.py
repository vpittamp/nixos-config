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
  "formatted_label": "079 - nixos-config"  // formatted display name
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
import struct
import sys
from pathlib import Path
from typing import Optional

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
        self._last_state_hash = None

    def _read_worktree_file(self) -> Optional[dict]:
        """Read active worktree from state file (Feature 101)"""
        try:
            if not ACTIVE_WORKTREE_FILE.exists():
                return None

            with open(ACTIVE_WORKTREE_FILE, "r") as f:
                data = json.load(f)

            if not data or "qualified_name" not in data:
                return None

            return data

        except (json.JSONDecodeError, Exception):
            return None

    def _extract_branch_number(self, branch: str) -> Optional[str]:
        """Extract numeric prefix from branch name (T051)"""
        if not branch:
            return None

        match = re.match(r'^(\d+)-', branch)
        if match:
            return match.group(1)
        return None

    def _update_state(self) -> bool:
        """Update active project state from file. Returns True if state changed."""
        worktree_data = self._read_worktree_file()

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
        else:
            # No active project - global mode
            self.project = "Global"
            self.active = False
            self.icon = "🌐"
            self.is_worktree = False
            self.branch_number = None
            self.formatted_label = "Global"

        # Check if state actually changed
        state_hash = (self.project, self.active, self.branch_number,
                      self.icon, self.is_worktree, self.formatted_label)
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
            "formatted_label": self.formatted_label
        }
        print(json.dumps(state), flush=True)

    def run(self):
        """Watch state file for active project updates using inotify."""
        # Output initial state
        self._update_state()
        self._output_state()

        # Try to use inotify for efficient file watching
        watcher = InotifyWatcher()
        use_inotify = watcher.start(ACTIVE_WORKTREE_FILE)

        if use_inotify:
            # Feature 123: Event-driven mode with inotify
            # 30s timeout as heartbeat (matches monitoring panel pattern)
            while True:
                changed = watcher.wait(timeout_ms=30000)
                if changed or self._update_state():
                    self._update_state()
                    self._output_state()
                # On timeout, just output current state as heartbeat
                elif not changed:
                    self._output_state()
        else:
            # Fallback: polling mode with longer interval (30s instead of 2s)
            import time
            while True:
                time.sleep(30)
                if self._update_state():
                    self._output_state()


if __name__ == "__main__":
    monitor = ActiveProjectMonitor()
    monitor.run()
