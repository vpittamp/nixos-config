#!/usr/bin/env python3
"""Active i3pm project monitoring for Eww top bar widgets

Feature 101: Reads active project from active-worktree.json (single source of truth).

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
"""

import json
import re
import time
from pathlib import Path
from typing import Optional


# Feature 101: active-worktree.json is the single source of truth
ACTIVE_WORKTREE_FILE = Path.home() / ".config" / "i3" / "active-worktree.json"


class ActiveProjectMonitor:
    """Monitor i3pm active project via state file"""

    def __init__(self):
        self.project = "Global"
        self.active = False
        self.branch_number = None
        self.icon = "📁"
        self.is_worktree = False
        self.formatted_label = "Global"

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

    def _update_state(self):
        """Update active project state from file"""
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

        self._output_state()

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
        """Poll state file for active project updates"""
        # Output initial state
        self._update_state()

        # Poll every 2 seconds for project changes
        while True:
            time.sleep(2)
            self._update_state()


if __name__ == "__main__":
    monitor = ActiveProjectMonitor()
    monitor.run()
