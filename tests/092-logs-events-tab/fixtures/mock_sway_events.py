"""
Mock Sway IPC event payloads for testing (Feature 092 - T015)

Provides sample event data for window::new, window::focus, window::close, workspace::focus.
"""

from typing import Dict, Any


# Window event: window::new
WINDOW_NEW_EVENT = {
    "change": "new",
    "container": {
        "id": 12345,
        "name": "Terminal - ~/projects/nixos",
        "type": "con",
        "border": "normal",
        "current_border_width": 2,
        "layout": "none",
        "orientation": "none",
        "percent": None,
        "rect": {"x": 0, "y": 0, "width": 800, "height": 600},
        "window_rect": {"x": 0, "y": 0, "width": 800, "height": 600},
        "deco_rect": {"x": 0, "y": 0, "width": 800, "height": 30},
        "geometry": {"x": 0, "y": 0, "width": 800, "height": 600},
        "window": 98765,
        "urgent": False,
        "marks": [],
        "focused": True,
        "focus": [],
        "nodes": [],
        "floating_nodes": [],
        "sticky": False,
        "fullscreen_mode": 0,
        "pid": 67890,
        "app_id": "terminal-nixos-123",
        "visible": True,
        "shell": "xdg_shell",
        "inhibit_idle": False,
        "idle_inhibitors": {"user": "none", "application": "none"},
        "window_properties": None,
        "window_type": None,
    }
}


# Window event: window::focus
WINDOW_FOCUS_EVENT = {
    "change": "focus",
    "container": {
        "id": 12346,
        "name": "VS Code - ~/projects/nixos",
        "type": "con",
        "pid": 54321,
        "app_id": "code",
        "focused": True,
        "urgent": False,
        "marks": [],
        "visible": True,
    }
}


# Window event: window::close
WINDOW_CLOSE_EVENT = {
    "change": "close",
    "container": {
        "id": 12345,
        "name": "Terminal - ~/projects/nixos",
        "type": "con",
        "app_id": "terminal-nixos-123",
    }
}


# Window event: window::move
WINDOW_MOVE_EVENT = {
    "change": "move",
    "container": {
        "id": 12347,
        "name": "Firefox",
        "type": "con",
        "app_id": "firefox",
        "focused": False,
        "workspace": {"num": 3, "name": "3"},
    }
}


# Window event: window::floating
WINDOW_FLOATING_EVENT = {
    "change": "floating",
    "container": {
        "id": 12348,
        "name": "Dialog Window",
        "type": "floating_con",
        "app_id": "dialog",
        "focused": True,
        "floating": "user_on",
    }
}


# Workspace event: workspace::focus
WORKSPACE_FOCUS_EVENT = {
    "change": "focus",
    "current": {
        "id": 200,
        "name": "3",
        "num": 3,
        "type": "workspace",
        "focused": True,
        "visible": True,
        "urgent": False,
        "output": "HEADLESS-1",
        "layout": "splith",
        "orientation": "horizontal",
        "nodes": [],
        "floating_nodes": [],
    },
    "old": {
        "id": 100,
        "name": "1",
        "num": 1,
        "type": "workspace",
        "focused": False,
        "visible": False,
        "urgent": False,
        "output": "HEADLESS-1",
    }
}


# Workspace event: workspace::init
WORKSPACE_INIT_EVENT = {
    "change": "init",
    "current": {
        "id": 300,
        "name": "5",
        "num": 5,
        "type": "workspace",
        "focused": True,
        "visible": True,
        "urgent": False,
        "output": "HEADLESS-2",
        "layout": "splith",
        "orientation": "horizontal",
        "nodes": [],
        "floating_nodes": [],
    }
}


# Workspace event: workspace::empty
WORKSPACE_EMPTY_EVENT = {
    "change": "empty",
    "current": {
        "id": 200,
        "name": "3",
        "num": 3,
        "type": "workspace",
        "focused": False,
        "visible": False,
        "urgent": False,
        "output": "HEADLESS-1",
        "nodes": [],
        "floating_nodes": [],
    }
}


# Output event: output::unspecified
OUTPUT_UNSPECIFIED_EVENT = {
    "change": "unspecified",
    "container": {
        "id": 400,
        "name": "HEADLESS-1",
        "type": "output",
        "active": True,
        "primary": False,
        "make": "Unknown",
        "model": "Unknown",
        "serial": "Unknown",
        "modes": [],
        "current_mode": {},
        "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
    }
}


# Comprehensive event list for integration tests
ALL_MOCK_EVENTS = [
    ("window", "new", WINDOW_NEW_EVENT),
    ("window", "focus", WINDOW_FOCUS_EVENT),
    ("window", "close", WINDOW_CLOSE_EVENT),
    ("window", "move", WINDOW_MOVE_EVENT),
    ("window", "floating", WINDOW_FLOATING_EVENT),
    ("workspace", "focus", WORKSPACE_FOCUS_EVENT),
    ("workspace", "init", WORKSPACE_INIT_EVENT),
    ("workspace", "empty", WORKSPACE_EMPTY_EVENT),
    ("output", "unspecified", OUTPUT_UNSPECIFIED_EVENT),
]
