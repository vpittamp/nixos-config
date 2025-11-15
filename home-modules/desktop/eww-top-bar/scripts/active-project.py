#!/usr/bin/env python3
"""Active i3pm project monitoring for Eww top bar widgets

Reads active project from i3pm state file and outputs JSON for deflisten consumption.

Output format:
{
  "project": "my-project",  // or "Global" if no active project
  "active": true            // true if project is active, false if in global mode
}

Usage:
  python3 active-project.py

Exits with code 0 on normal termination, 1 on errors.
"""

import json
import sys
import time
from pathlib import Path
from typing import Optional


# i3pm active project state file
ACTIVE_PROJECT_FILE = Path.home() / ".config" / "i3" / "active-project.json"


class ActiveProjectMonitor:
    """Monitor i3pm active project via state file"""

    def __init__(self):
        self.project = "Global"
        self.active = False

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

    def _update_state(self):
        """Update active project state from file"""
        result = self._read_project_file()

        if result and result.get("project_name"):
            self.project = result["project_name"]
            self.active = True
        else:
            # No active project - global mode
            self.project = "Global"
            self.active = False

        self._output_state()

    def _output_state(self):
        """Output current project state as JSON"""
        state = {
            "project": self.project,
            "active": self.active
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
