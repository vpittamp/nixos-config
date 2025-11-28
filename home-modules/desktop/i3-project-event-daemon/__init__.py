"""i3 Project Event Daemon

Event-driven i3 project management system.

This package provides a long-running daemon that:
- Maintains persistent IPC connection to i3 window manager
- Processes window/workspace events in real-time
- Automatically marks windows with project context
- Exposes IPC socket for CLI tool queries

Author: NixOS Configuration
License: MIT
Version: 1.0.0
"""

__version__ = "1.0.0"
# Rebuild trigger
# Version 1.13.0 - Feature 098: worktree.list IPC method enhancements
