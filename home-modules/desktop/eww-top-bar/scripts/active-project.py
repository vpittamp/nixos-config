#!/usr/bin/env python3
"""Active i3pm project monitoring for Eww top bar widgets

Listens to i3pm daemon IPC socket for project switch events and outputs JSON
with active project name for deflisten consumption.

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
import os
import socket
import sys
import time
from pathlib import Path
from typing import Optional


# i3pm daemon IPC socket path (from i3pm daemon configuration)
IPC_SOCKET_PATH = Path("/run/user") / str(os.getuid()) / "i3-project-daemon" / "ipc.sock"


class ActiveProjectMonitor:
    """Monitor i3pm active project via IPC socket"""

    def __init__(self):
        self.project = "Global"
        self.active = False

        if not IPC_SOCKET_PATH.exists():
            print(json.dumps({"project": "Global", "active": False, "error": "i3pm daemon not running"}), flush=True)
            sys.exit(1)

    def _query_daemon(self) -> Optional[dict]:
        """Query i3pm daemon for current project state"""
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.settimeout(1.0)  # 1 second timeout
                sock.connect(str(IPC_SOCKET_PATH))

                # Send query command (JSON-RPC style)
                query = json.dumps({"command": "get_active_project"})
                sock.sendall(query.encode() + b"\n")

                # Receive response
                response = sock.recv(4096).decode()
                return json.loads(response)
        except (socket.error, json.JSONDecodeError, Exception) as e:
            # Daemon unavailable or error - fallback to global mode
            return None

    def _update_state(self):
        """Update active project state from daemon"""
        result = self._query_daemon()

        if result and result.get("success"):
            project_name = result.get("project", "")
            self.active = bool(project_name)
            self.project = project_name if project_name else "Global"
        else:
            # Fallback: no active project
            self.active = False
            self.project = "Global"

        self._output_state()

    def _output_state(self):
        """Output current project state as JSON"""
        state = {
            "project": self.project,
            "active": self.active
        }
        print(json.dumps(state), flush=True)

    def run(self):
        """Poll daemon for active project updates"""
        # Output initial state
        self._update_state()

        # Poll every 2 seconds for project changes
        # Note: This is polling-based since i3pm daemon doesn't provide event streaming yet
        # Future: Implement deflisten with daemon event stream for real-time updates
        while True:
            time.sleep(2)
            self._update_state()


if __name__ == "__main__":
    monitor = ActiveProjectMonitor()
    monitor.run()
