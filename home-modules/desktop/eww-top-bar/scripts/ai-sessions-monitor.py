#!/usr/bin/env python3
"""AI Sessions monitoring for Eww top bar widgets (Feature 119)

Watches badge files written by the eBPF AI monitor and streams state changes
to Eww via deflisten for near-realtime visual indicator updates.

Badge files are at: $XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json

Output format (JSON per line):
{
  "sessions": [
    {
      "id": "12345",
      "state": "working",
      "source": "claude-code",
      "project": "nixos-config:main",
      "needs_attention": false
    }
  ],
  "has_working": true
}

States:
- working: AI is processing (teal pulsating glow)
- stopped + needs_attention: AI finished, user should return (peach highlight)
- stopped + !needs_attention: AI idle (muted)

Usage:
  python3 ai-sessions-monitor.py

Exits with code 0 on normal termination, 1 on errors.
"""

import json
import os
import sys
from pathlib import Path
from typing import Optional

try:
    from gi.repository import GLib, Gio
except ImportError:
    # Fallback output if GLib not available
    print(json.dumps({"sessions": [], "has_working": False, "error": "GLib not available"}))
    sys.exit(1)


class AISessionsMonitor:
    """Monitor AI session badge files using GLib file monitoring"""

    def __init__(self):
        # Determine badge directory
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        self.badge_dir = Path(runtime_dir) / "i3pm-badges"

        self.monitors: dict[str, Gio.FileMonitor] = {}
        self.last_state: Optional[str] = None

        # Ensure badge directory exists
        if not self.badge_dir.exists():
            self.badge_dir.mkdir(parents=True, exist_ok=True)

        # Setup directory monitor
        self._setup_directory_monitor()

        # Emit initial state
        self._emit_state()

    def _setup_directory_monitor(self):
        """Setup GLib file monitor on badge directory"""
        try:
            directory = Gio.File.new_for_path(str(self.badge_dir))
            self.dir_monitor = directory.monitor_directory(
                Gio.FileMonitorFlags.NONE,
                None
            )
            self.dir_monitor.connect("changed", self._on_directory_changed)
        except Exception as e:
            print(json.dumps({"sessions": [], "has_working": False, "error": f"Monitor setup failed: {e}"}), flush=True)
            sys.exit(1)

    def _on_directory_changed(self, monitor, file, other_file, event_type):
        """Handle directory change events"""
        # React to file creation, modification, deletion
        if event_type in (
            Gio.FileMonitorEvent.CREATED,
            Gio.FileMonitorEvent.CHANGED,
            Gio.FileMonitorEvent.DELETED,
            Gio.FileMonitorEvent.CHANGES_DONE_HINT,
        ):
            # Debounce: only emit if state actually changed
            self._emit_state()

    def _read_badge_file(self, badge_path: Path) -> Optional[dict]:
        """Read and parse a single badge file"""
        try:
            content = badge_path.read_text()
            data = json.loads(content)
            return {
                "id": badge_path.stem,  # window_id from filename
                "state": data.get("state", "stopped"),
                "source": data.get("source", "unknown"),
                "project": data.get("project", ""),
                "needs_attention": data.get("needs_attention", False),
                "count": data.get("count", 1),
            }
        except (json.JSONDecodeError, OSError):
            return None

    def _collect_sessions(self) -> dict:
        """Read all badge files and build sessions state"""
        sessions = []
        has_working = False

        if self.badge_dir.exists():
            for badge_file in sorted(self.badge_dir.glob("*.json")):
                session = self._read_badge_file(badge_file)
                if session:
                    sessions.append(session)
                    if session["state"] == "working":
                        has_working = True

        return {
            "sessions": sessions,
            "has_working": has_working,
        }

    def _emit_state(self):
        """Emit current state as JSON if changed"""
        state = self._collect_sessions()
        state_json = json.dumps(state, separators=(",", ":"))

        # Only emit if state changed (debounce)
        if state_json != self.last_state:
            self.last_state = state_json
            print(state_json, flush=True)

    def run(self):
        """Start GLib main loop to listen for file events"""
        loop = GLib.MainLoop()
        try:
            loop.run()
        except KeyboardInterrupt:
            loop.quit()


if __name__ == "__main__":
    monitor = AISessionsMonitor()
    monitor.run()
