"""i3 Project Event Listener Daemon

Event-driven project management for i3 window manager.

This package provides:
- Real-time window/workspace event processing
- Automatic window marking with project context
- IPC server for CLI tool queries
- Persistent project state management

Version: 1.0.0
"""

__version__ = "1.0.0"
__all__ = [
    "models",
    "config",
    "state",
    "connection",
    "handlers",
    "app_identifier",
    "ipc_server",
    "daemon",
]
