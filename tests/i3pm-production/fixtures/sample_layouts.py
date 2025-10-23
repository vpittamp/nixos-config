"""
Sample layout fixtures for testing

Feature 030: Production Readiness
Task T021: Sample layout fixtures

Provides realistic layout data matching i3 layout format
for testing layout capture, save, and restore.
"""

from datetime import datetime
from pathlib import Path


def simple_layout():
    """
    Simple layout: 1 monitor, 2 workspaces, 3 windows

    Workspace 1: Terminal (focused) + VS Code (split)
    Workspace 2: Firefox (single window)
    """
    return {
        "name": "simple-layout",
        "project": "nixos",
        "created_at": datetime.now().isoformat(),
        "monitor_config": {
            "monitors": [
                {
                    "name": "HDMI-0",
                    "width": 1920,
                    "height": 1080,
                    "x": 0,
                    "y": 0,
                    "primary": True,
                }
            ]
        },
        "workspace_layouts": [
            {
                "workspace": "1",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 1,
                        "window_class": "Ghostty",
                        "window_instance": "ghostty",
                        "title": "Terminal",
                        "launch_command": "ghostty",
                        "geometry": {
                            "x": 0,
                            "y": 0,
                            "width": 960,
                            "height": 1080
                        },
                        "marks": ["project:nixos"],
                        "floating": False,
                    },
                    {
                        "id": 2,
                        "window_class": "Code",
                        "window_instance": "code",
                        "title": "VS Code - nixos",
                        "launch_command": "code /etc/nixos",
                        "geometry": {
                            "x": 960,
                            "y": 0,
                            "width": 960,
                            "height": 1080
                        },
                        "marks": ["project:nixos"],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "2",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 3,
                        "window_class": "firefox",
                        "window_instance": "Navigator",
                        "title": "Mozilla Firefox",
                        "launch_command": "firefox",
                        "geometry": {
                            "x": 0,
                            "y": 0,
                            "width": 1920,
                            "height": 1080
                        },
                        "marks": [],
                        "floating": False,
                    }
                ]
            }
        ],
        "metadata": {
            "total_windows": 3,
            "total_workspaces": 2,
            "total_monitors": 1,
        }
    }


def complex_layout():
    """
    Complex layout: 1 monitor, 3 workspaces, nested splits, floating windows

    Workspace 1: Terminal + VS Code (horizontal split)
    Workspace 2: Firefox + Slack (vertical split) + floating Calculator
    Workspace 3: Spotify (fullscreen)
    """
    return {
        "name": "complex-layout",
        "project": "nixos",
        "created_at": datetime.now().isoformat(),
        "monitor_config": {
            "monitors": [
                {
                    "name": "HDMI-0",
                    "width": 2560,
                    "height": 1440,
                    "x": 0,
                    "y": 0,
                    "primary": True,
                }
            ]
        },
        "workspace_layouts": [
            {
                "workspace": "1",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 1,
                        "window_class": "Ghostty",
                        "window_instance": "ghostty",
                        "title": "Terminal",
                        "launch_command": "ghostty",
                        "geometry": {
                            "x": 0,
                            "y": 0,
                            "width": 1280,
                            "height": 1440
                        },
                        "marks": ["project:nixos"],
                        "floating": False,
                    },
                    {
                        "id": 2,
                        "window_class": "Code",
                        "window_instance": "code",
                        "title": "VS Code",
                        "launch_command": "code",
                        "geometry": {
                            "x": 1280,
                            "y": 0,
                            "width": 1280,
                            "height": 1440
                        },
                        "marks": ["project:nixos"],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "2",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 3,
                        "window_class": "firefox",
                        "window_instance": "Navigator",
                        "title": "Firefox",
                        "launch_command": "firefox",
                        "geometry": {
                            "x": 0,
                            "y": 0,
                            "width": 2560,
                            "height": 720
                        },
                        "marks": [],
                        "floating": False,
                    },
                    {
                        "id": 4,
                        "window_class": "Slack",
                        "window_instance": "slack",
                        "title": "Slack",
                        "launch_command": "slack",
                        "geometry": {
                            "x": 0,
                            "y": 720,
                            "width": 2560,
                            "height": 720
                        },
                        "marks": [],
                        "floating": False,
                    },
                    {
                        "id": 5,
                        "window_class": "gnome-calculator",
                        "window_instance": "gnome-calculator",
                        "title": "Calculator",
                        "launch_command": "gnome-calculator",
                        "geometry": {
                            "x": 1000,
                            "y": 500,
                            "width": 560,
                            "height": 440
                        },
                        "marks": [],
                        "floating": True,
                    }
                ]
            },
            {
                "workspace": "3",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 6,
                        "window_class": "spotify",
                        "window_instance": "spotify",
                        "title": "Spotify",
                        "launch_command": "spotify",
                        "geometry": {
                            "x": 0,
                            "y": 0,
                            "width": 2560,
                            "height": 1440
                        },
                        "marks": [],
                        "floating": False,
                    }
                ]
            }
        ],
        "metadata": {
            "total_windows": 6,
            "total_workspaces": 3,
            "total_monitors": 1,
            "floating_windows": 1,
        }
    }


def multi_workspace_layout():
    """
    Multi-workspace layout: 1 monitor, 5 workspaces, project-scoped windows

    Designed for testing project switching and window visibility.
    """
    return {
        "name": "multi-workspace-layout",
        "project": "nixos",
        "created_at": datetime.now().isoformat(),
        "monitor_config": {
            "monitors": [
                {
                    "name": "HDMI-0",
                    "width": 1920,
                    "height": 1080,
                    "x": 0,
                    "y": 0,
                    "primary": True,
                }
            ]
        },
        "workspace_layouts": [
            {
                "workspace": "1",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 1,
                        "window_class": "Ghostty",
                        "window_instance": "ghostty",
                        "title": "Terminal - NixOS",
                        "launch_command": "ghostty",
                        "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                        "marks": ["project:nixos", "scoped"],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "2",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 2,
                        "window_class": "Code",
                        "window_instance": "code",
                        "title": "VS Code - NixOS",
                        "launch_command": "code /etc/nixos",
                        "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                        "marks": ["project:nixos", "scoped"],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "3",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 3,
                        "window_class": "Ghostty",
                        "window_instance": "ghostty",
                        "title": "Terminal - Stacks",
                        "launch_command": "ghostty",
                        "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                        "marks": ["project:stacks", "scoped"],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "4",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 4,
                        "window_class": "Code",
                        "window_instance": "code",
                        "title": "VS Code - Stacks",
                        "launch_command": "code /home/user/stacks",
                        "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                        "marks": ["project:stacks", "scoped"],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "5",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 5,
                        "window_class": "firefox",
                        "window_instance": "Navigator",
                        "title": "Firefox",
                        "launch_command": "firefox",
                        "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                        "marks": [],  # Global window - no project mark
                        "floating": False,
                    }
                ]
            }
        ],
        "metadata": {
            "total_windows": 5,
            "total_workspaces": 5,
            "total_monitors": 1,
            "projects": ["nixos", "stacks"],
            "scoped_windows": 4,
            "global_windows": 1,
        }
    }


def dual_monitor_layout():
    """
    Dual monitor layout: 2 monitors, 6 workspaces, 10 windows

    Primary monitor (HDMI-0): Workspaces 1-3
    Secondary monitor (DP-0): Workspaces 4-6
    """
    return {
        "name": "dual-monitor-layout",
        "project": "nixos",
        "created_at": datetime.now().isoformat(),
        "monitor_config": {
            "monitors": [
                {
                    "name": "HDMI-0",
                    "width": 2560,
                    "height": 1440,
                    "x": 0,
                    "y": 0,
                    "primary": True,
                },
                {
                    "name": "DP-0",
                    "width": 1920,
                    "height": 1080,
                    "x": 2560,
                    "y": 0,
                    "primary": False,
                }
            ]
        },
        "workspace_layouts": [
            # Primary monitor workspaces
            {
                "workspace": "1",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 1,
                        "window_class": "Ghostty",
                        "window_instance": "ghostty",
                        "title": "Terminal",
                        "launch_command": "ghostty",
                        "geometry": {"x": 0, "y": 0, "width": 1280, "height": 1440},
                        "marks": ["project:nixos"],
                        "floating": False,
                    },
                    {
                        "id": 2,
                        "window_class": "Code",
                        "window_instance": "code",
                        "title": "VS Code",
                        "launch_command": "code /etc/nixos",
                        "geometry": {"x": 1280, "y": 0, "width": 1280, "height": 1440},
                        "marks": ["project:nixos"],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "2",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 3,
                        "window_class": "firefox",
                        "window_instance": "Navigator",
                        "title": "Firefox",
                        "launch_command": "firefox",
                        "geometry": {"x": 0, "y": 0, "width": 2560, "height": 1440},
                        "marks": [],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "3",
                "output": "HDMI-0",
                "windows": [
                    {
                        "id": 4,
                        "window_class": "Slack",
                        "window_instance": "slack",
                        "title": "Slack",
                        "launch_command": "slack",
                        "geometry": {"x": 0, "y": 0, "width": 2560, "height": 1440},
                        "marks": [],
                        "floating": False,
                    }
                ]
            },
            # Secondary monitor workspaces
            {
                "workspace": "4",
                "output": "DP-0",
                "windows": [
                    {
                        "id": 5,
                        "window_class": "discord",
                        "window_instance": "discord",
                        "title": "Discord",
                        "launch_command": "discord",
                        "geometry": {"x": 2560, "y": 0, "width": 960, "height": 1080},
                        "marks": [],
                        "floating": False,
                    },
                    {
                        "id": 6,
                        "window_class": "spotify",
                        "window_instance": "spotify",
                        "title": "Spotify",
                        "launch_command": "spotify",
                        "geometry": {"x": 3520, "y": 0, "width": 960, "height": 1080},
                        "marks": [],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "5",
                "output": "DP-0",
                "windows": [
                    {
                        "id": 7,
                        "window_class": "Thunderbird",
                        "window_instance": "Mail",
                        "title": "Thunderbird",
                        "launch_command": "thunderbird",
                        "geometry": {"x": 2560, "y": 0, "width": 1920, "height": 1080},
                        "marks": [],
                        "floating": False,
                    }
                ]
            },
            {
                "workspace": "6",
                "output": "DP-0",
                "windows": [
                    {
                        "id": 8,
                        "window_class": "obsidian",
                        "window_instance": "obsidian",
                        "title": "Obsidian",
                        "launch_command": "obsidian",
                        "geometry": {"x": 2560, "y": 0, "width": 960, "height": 1080},
                        "marks": ["project:nixos"],
                        "floating": False,
                    },
                    {
                        "id": 9,
                        "window_class": "gimp-2.10",
                        "window_instance": "gimp",
                        "title": "GIMP",
                        "launch_command": "gimp",
                        "geometry": {"x": 3520, "y": 0, "width": 960, "height": 540},
                        "marks": [],
                        "floating": False,
                    },
                    {
                        "id": 10,
                        "window_class": "Inkscape",
                        "window_instance": "org.inkscape.Inkscape",
                        "title": "Inkscape",
                        "launch_command": "inkscape",
                        "geometry": {"x": 3520, "y": 540, "width": 960, "height": 540},
                        "marks": [],
                        "floating": False,
                    }
                ]
            }
        ],
        "metadata": {
            "total_windows": 10,
            "total_workspaces": 6,
            "total_monitors": 2,
            "primary_monitor_workspaces": 3,
            "secondary_monitor_workspaces": 3,
        }
    }
