"""
Load testing profiles for performance testing

Feature 030: Production Readiness
Task T022: Load testing profiles

Provides configurations for testing daemon performance
with varying numbers of windows and workspaces.
"""

from typing import Dict, Any, List
from datetime import datetime


def _generate_windows(count: int, workspace: str = "1", output: str = "HDMI-0") -> List[Dict[str, Any]]:
    """
    Generate N windows for load testing

    Args:
        count: Number of windows to generate
        workspace: Workspace name
        output: Output name

    Returns:
        List of window dictionaries
    """
    windows = []

    # Distribute windows across common application types
    app_types = [
        ("Ghostty", "ghostty", "Terminal", "ghostty"),
        ("Code", "code", "VS Code", "code"),
        ("firefox", "Navigator", "Firefox", "firefox"),
        ("Slack", "slack", "Slack", "slack"),
        ("discord", "discord", "Discord", "discord"),
        ("spotify", "spotify", "Spotify", "spotify"),
        ("Thunderbird", "Mail", "Thunderbird", "thunderbird"),
        ("obsidian", "obsidian", "Obsidian", "obsidian"),
    ]

    for i in range(count):
        app_type = app_types[i % len(app_types)]
        window_class, window_instance, title_prefix, command = app_type

        window = {
            "id": i + 1,
            "window_class": window_class,
            "window_instance": window_instance,
            "title": f"{title_prefix} {i + 1}",
            "launch_command": command,
            "geometry": {
                "x": (i % 4) * 480,  # 4 columns
                "y": (i // 4) * 270,  # Multiple rows
                "width": 480,
                "height": 270,
            },
            "marks": [f"project:test-{i % 3}"] if i % 3 == 0 else [],  # 1/3 windows have project marks
            "floating": i % 10 == 0,  # 10% floating windows
        }

        windows.append(window)

    return windows


def small_load_profile() -> Dict[str, Any]:
    """
    Small load profile: 50 windows, 5 workspaces, 1 monitor

    Use for: Basic performance testing, smoke tests
    Expected performance: <10ms per operation
    """
    windows_per_workspace = 10
    workspace_count = 5

    workspace_layouts = []

    for ws_num in range(1, workspace_count + 1):
        start_id = (ws_num - 1) * windows_per_workspace
        windows = _generate_windows(windows_per_workspace, workspace=str(ws_num))

        # Update window IDs to be unique across workspaces
        for i, window in enumerate(windows):
            window["id"] = start_id + i + 1

        workspace_layouts.append({
            "workspace": str(ws_num),
            "output": "HDMI-0",
            "windows": windows,
        })

    return {
        "name": "small-load-50-windows",
        "project": "load-test",
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
        "workspace_layouts": workspace_layouts,
        "metadata": {
            "total_windows": 50,
            "total_workspaces": 5,
            "total_monitors": 1,
            "windows_per_workspace": windows_per_workspace,
            "load_profile": "small",
            "expected_performance": "< 10ms per operation",
        }
    }


def medium_load_profile() -> Dict[str, Any]:
    """
    Medium load profile: 100 windows, 10 workspaces, 2 monitors

    Use for: Typical production usage simulation
    Expected performance: <50ms per operation
    """
    windows_per_workspace = 10
    workspace_count = 10

    workspace_layouts = []

    for ws_num in range(1, workspace_count + 1):
        start_id = (ws_num - 1) * windows_per_workspace

        # Alternate between two monitors
        output = "HDMI-0" if ws_num <= 5 else "DP-0"

        windows = _generate_windows(windows_per_workspace, workspace=str(ws_num), output=output)

        # Update window IDs to be unique across workspaces
        for i, window in enumerate(windows):
            window["id"] = start_id + i + 1

        workspace_layouts.append({
            "workspace": str(ws_num),
            "output": output,
            "windows": windows,
        })

    return {
        "name": "medium-load-100-windows",
        "project": "load-test",
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
        "workspace_layouts": workspace_layouts,
        "metadata": {
            "total_windows": 100,
            "total_workspaces": 10,
            "total_monitors": 2,
            "windows_per_workspace": windows_per_workspace,
            "load_profile": "medium",
            "expected_performance": "< 50ms per operation",
        }
    }


def large_load_profile() -> Dict[str, Any]:
    """
    Large load profile: 500 windows, 50 workspaces, 3 monitors

    Use for: Stress testing, performance limits, memory profiling
    Expected performance: <200ms per operation
    """
    windows_per_workspace = 10
    workspace_count = 50

    workspace_layouts = []

    for ws_num in range(1, workspace_count + 1):
        start_id = (ws_num - 1) * windows_per_workspace

        # Distribute across three monitors
        if ws_num <= 17:
            output = "HDMI-0"
        elif ws_num <= 34:
            output = "DP-0"
        else:
            output = "DP-1"

        windows = _generate_windows(windows_per_workspace, workspace=str(ws_num), output=output)

        # Update window IDs to be unique across workspaces
        for i, window in enumerate(windows):
            window["id"] = start_id + i + 1

        workspace_layouts.append({
            "workspace": str(ws_num),
            "output": output,
            "windows": windows,
        })

    return {
        "name": "large-load-500-windows",
        "project": "load-test",
        "created_at": datetime.now().isoformat(),
        "monitor_config": {
            "monitors": [
                {
                    "name": "HDMI-0",
                    "width": 3840,
                    "height": 2160,
                    "x": 0,
                    "y": 0,
                    "primary": True,
                },
                {
                    "name": "DP-0",
                    "width": 2560,
                    "height": 1440,
                    "x": 3840,
                    "y": 0,
                    "primary": False,
                },
                {
                    "name": "DP-1",
                    "width": 1920,
                    "height": 1080,
                    "x": 6400,
                    "y": 0,
                    "primary": False,
                }
            ]
        },
        "workspace_layouts": workspace_layouts,
        "metadata": {
            "total_windows": 500,
            "total_workspaces": 50,
            "total_monitors": 3,
            "windows_per_workspace": windows_per_workspace,
            "load_profile": "large",
            "expected_performance": "< 200ms per operation",
            "memory_limit": "< 100MB",
            "cpu_limit": "< 50%",
        }
    }


def get_profile_by_name(name: str) -> Dict[str, Any]:
    """
    Get load profile by name

    Args:
        name: Profile name ("small", "medium", "large")

    Returns:
        Load profile dictionary

    Raises:
        ValueError: If profile name is invalid
    """
    profiles = {
        "small": small_load_profile,
        "medium": medium_load_profile,
        "large": large_load_profile,
    }

    if name not in profiles:
        raise ValueError(f"Invalid profile name: {name}. Valid options: {list(profiles.keys())}")

    return profiles[name]()


def get_all_profiles() -> List[Dict[str, Any]]:
    """
    Get all load profiles

    Returns:
        List of all load profile dictionaries
    """
    return [
        small_load_profile(),
        medium_load_profile(),
        large_load_profile(),
    ]


# Profile metadata for test selection
PROFILE_METADATA = {
    "small": {
        "windows": 50,
        "workspaces": 5,
        "monitors": 1,
        "description": "Basic performance testing and smoke tests",
        "expected_time": "< 10ms per operation",
    },
    "medium": {
        "windows": 100,
        "workspaces": 10,
        "monitors": 2,
        "description": "Typical production usage simulation",
        "expected_time": "< 50ms per operation",
    },
    "large": {
        "windows": 500,
        "workspaces": 50,
        "monitors": 3,
        "description": "Stress testing and performance limits",
        "expected_time": "< 200ms per operation",
    },
}
