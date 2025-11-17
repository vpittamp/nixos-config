#!/usr/bin/env python3
"""Active i3pm project monitoring for Eww top bar widgets

Reads active project from i3pm state file and outputs JSON for deflisten consumption.

Output format:
{
  "project": "my-project",  // or "Global" if no active project
  "active": true,           // true if project is active, false if in global mode
  "branch_number": "079",   // extracted numeric prefix (or null)
  "icon": "🌿",             // project icon
  "is_worktree": true,      // true if worktree project
  "formatted_label": "079 - my-project"  // formatted display name
}

Usage:
  python3 active-project.py

Exits with code 0 on normal termination, 1 on errors.

Feature 079: US7 - Top Bar Enhancement (T050, T051)
"""

import json
import re
import time
from pathlib import Path
from typing import Optional


# i3pm active project state file
ACTIVE_PROJECT_FILE = Path.home() / ".config" / "i3" / "active-project.json"
# i3pm project configuration directory
PROJECT_CONFIG_DIR = Path.home() / ".config" / "i3" / "projects"


class ActiveProjectMonitor:
    """Monitor i3pm active project via state file"""

    def __init__(self):
        self.project = "Global"
        self.active = False
        self.branch_number = None
        self.icon = "📁"
        self.is_worktree = False
        self.formatted_label = "Global"

    def _read_project_file(self) -> Optional[dict]:
        """Read active project from state file"""
        try:
            if not ACTIVE_PROJECT_FILE.exists():
                return None

            with open(ACTIVE_PROJECT_FILE, "r") as f:
                data = json.load(f)

            if not data or "project_name" not in data:
                return None

            return data

        except (json.JSONDecodeError, Exception):
            return None

    def _read_project_metadata(self, project_name: str) -> Optional[dict]:
        """Read project JSON file for metadata (T051)"""
        try:
            project_file = PROJECT_CONFIG_DIR / f"{project_name}.json"
            if not project_file.exists():
                return None

            with open(project_file, "r") as f:
                return json.load(f)

        except (json.JSONDecodeError, Exception):
            return None

    def _extract_branch_number(self, worktree_data: dict) -> Optional[str]:
        """Extract numeric prefix from branch name (T051)"""
        if not worktree_data:
            return None

        branch = worktree_data.get("branch", "")
        match = re.match(r'^(\d+)-', branch)
        if match:
            return match.group(1)
        return None

    def _update_state(self):
        """Update active project state from file"""
        result = self._read_project_file()

        if result and result.get("project_name"):
            project_name = result["project_name"]
            self.project = project_name
            self.active = True

            # Feature 079: T051 - Extract branch metadata from project JSON
            metadata = self._read_project_metadata(project_name)
            if metadata:
                self.icon = metadata.get("icon", "📁")
                self.is_worktree = "worktree" in metadata

                if self.is_worktree:
                    worktree_data = metadata.get("worktree", {})
                    self.branch_number = self._extract_branch_number(worktree_data)
                else:
                    self.branch_number = None

                # T053: Formatted label "{icon} {branch_number} - {display_name}"
                display_name = metadata.get("display_name", project_name)
                if self.branch_number:
                    self.formatted_label = f"{self.branch_number} - {display_name}"
                else:
                    self.formatted_label = display_name
            else:
                # Fallback if metadata not available
                self.icon = "📁"
                self.is_worktree = False
                self.branch_number = None
                self.formatted_label = project_name
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
