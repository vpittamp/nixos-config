#!/usr/bin/env python3
"""
polybar-i3-project-indicator.py - Polybar module for i3 project indicator

Subscribes to i3 tick events and updates display text when project changes.
This provides real-time project indicator updates without polling.

Usage:
    polybar-i3-project-indicator.py

Output format (polybar):
    %{F#FFFFFF} NixOS%{F-}      # When project is active
    %{F#888888}[no project]%{F-}  # When no project is active
"""

import sys
import json
import subprocess
import os
from pathlib import Path

# Configuration
PROJECT_DIR = Path.home() / ".config" / "i3" / "projects"
ACTIVE_PROJECT_FILE = Path.home() / ".config" / "i3" / "active-project"

# Polybar colors
COLOR_ACTIVE = "#FFFFFF"      # White for active project
COLOR_INACTIVE = "#888888"    # Gray for no project


def get_project_display_name(project_name):
    """Get display name and icon from project JSON."""
    project_file = PROJECT_DIR / f"{project_name}.json"

    if not project_file.exists():
        return project_name, ""

    try:
        with open(project_file, 'r') as f:
            data = json.load(f)
            display_name = data.get("project", {}).get("displayName", project_name)
            icon = data.get("project", {}).get("icon", "")
            return display_name, icon
    except (json.JSONDecodeError, IOError):
        return project_name, ""


def format_output(project_name):
    """Format polybar output string."""
    if not project_name or project_name.strip() == "":
        return f"%{{F{COLOR_INACTIVE}}}[no project]%{{F-}}"

    display_name, icon = get_project_display_name(project_name)

    if icon:
        text = f"{icon} {display_name}"
    else:
        text = display_name

    return f"%{{F{COLOR_ACTIVE}}}{text}%{{F-}}"


def get_current_project():
    """Read current project from active-project file."""
    if not ACTIVE_PROJECT_FILE.exists():
        return ""

    try:
        with open(ACTIVE_PROJECT_FILE, 'r') as f:
            return f.read().strip()
    except IOError:
        return ""


def main():
    """Main loop: subscribe to i3 tick events and update display."""
    # Print initial state
    current_project = get_current_project()
    print(format_output(current_project), flush=True)

    # Subscribe to tick events
    try:
        process = subprocess.Popen(
            ["i3-msg", "-t", "subscribe", "-m", '["tick"]'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )

        for line in process.stdout:
            try:
                event = json.loads(line)

                # Check if this is a project tick event
                if event.get("change") == "tick":
                    payload = event.get("payload", "")

                    # Project tick events have format "project:NAME" or "project:none"
                    if payload.startswith("project:"):
                        project_name = payload[8:]  # Remove "project:" prefix

                        if project_name == "none":
                            project_name = ""

                        # Update display
                        print(format_output(project_name), flush=True)

            except json.JSONDecodeError:
                # Skip invalid JSON lines
                continue
            except Exception as e:
                print(f"Error processing event: {e}", file=sys.stderr)
                continue

    except KeyboardInterrupt:
        # Graceful shutdown
        pass
    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
