"""
Terminal Launcher Service

Handles terminal emulator selection (Ghostty primary, Alacritty fallback),
unified launcher integration, and launch notification payload generation.

Feature 062 - Project-Scoped Scratchpad Terminal
"""

import subprocess
import logging
import os
import time
import uuid
from pathlib import Path
from typing import Dict, Tuple, Optional


logger = logging.getLogger(__name__)


def select_terminal_emulator() -> Tuple[str, str]:
    """
    Select terminal emulator with Ghostty as primary and Alacritty as fallback.

    Returns:
        Tuple of (command_name, expected_class) where:
            - command_name: Executable name ("ghostty" or "alacritty")
            - expected_class: Expected app_id/class for window matching

    Priority:
        1. Ghostty (if available)
        2. Alacritty (fallback)

    Raises:
        RuntimeError: If neither terminal emulator is available
    """
    # Try Ghostty first
    try:
        result = subprocess.run(
            ["command", "-v", "ghostty"],
            capture_output=True,
            check=True,
            text=True,
        )
        logger.info("Selected Ghostty as terminal emulator")
        return ("ghostty", "com.mitchellh.ghostty")
    except subprocess.CalledProcessError:
        logger.debug("Ghostty not found, trying Alacritty fallback")

    # Fallback to Alacritty
    try:
        result = subprocess.run(
            ["command", "-v", "alacritty"],
            capture_output=True,
            check=True,
            text=True,
        )
        logger.info("Selected Alacritty as terminal emulator (Ghostty unavailable)")
        return ("alacritty", "Alacritty")
    except subprocess.CalledProcessError:
        logger.error("Neither Ghostty nor Alacritty found in PATH")
        raise RuntimeError(
            "No terminal emulator available. "
            "Please install ghostty or alacritty."
        )


def build_launch_command(
    terminal_cmd: str,
    working_dir: Path,
    project_name: str,
) -> list[str]:
    """
    Build terminal launch command with working directory parameter.

    Args:
        terminal_cmd: Terminal emulator command ("ghostty" or "alacritty")
        working_dir: Working directory for terminal
        project_name: Project identifier for environment variables

    Returns:
        List of command arguments for unified launcher

    Example for Ghostty:
        ["ghostty", "--working-directory=/etc/nixos"]

    Example for Alacritty:
        ["alacritty", "--working-directory", "/etc/nixos"]
    """
    working_dir_str = str(working_dir)

    if terminal_cmd == "ghostty":
        return ["ghostty", f"--working-directory={working_dir_str}"]
    elif terminal_cmd == "alacritty":
        return ["alacritty", "--working-directory", working_dir_str]
    else:
        raise ValueError(f"Unknown terminal emulator: {terminal_cmd}")


def create_launch_notification_payload(
    project_name: str,
    expected_class: str,
    workspace_number: int = 1,
) -> Dict[str, any]:
    """
    Create launch notification payload for Feature 041 (launch context).

    The payload is sent to the daemon's launch registry BEFORE launching
    the terminal, enabling high-accuracy window correlation (Tier 0).

    Args:
        project_name: Project identifier or "global"
        expected_class: Expected app_id for window matching
        workspace_number: Target workspace (default: 1)

    Returns:
        Dictionary with launch notification fields:
            - launch_id: Unique UUID for this launch
            - app_name: Always "scratchpad-terminal"
            - project_name: Project identifier
            - expected_class: Terminal emulator app_id
            - workspace_number: Target workspace
            - timestamp: Current Unix timestamp
            - correlation_timeout: Timeout for window correlation (2.0s)

    Example:
        {
            "launch_id": "550e8400-e29b-41d4-a716-446655440000",
            "app_name": "scratchpad-terminal",
            "project_name": "nixos",
            "expected_class": "com.mitchellh.ghostty",
            "workspace_number": 1,
            "timestamp": 1730815200.123,
            "correlation_timeout": 2.0
        }
    """
    return {
        "launch_id": str(uuid.uuid4()),
        "app_name": "scratchpad-terminal",
        "project_name": project_name,
        "expected_class": expected_class,
        "workspace_number": workspace_number,
        "timestamp": time.time(),
        "correlation_timeout": 2.0,  # 2 second timeout per FR-019
    }


def build_launcher_environment(
    project_name: str,
    working_dir: Path,
    app_name: str = "scratchpad-terminal",
) -> Dict[str, str]:
    """
    Build environment variables for unified launcher invocation.

    These environment variables are injected by app-launcher-wrapper.sh
    and enable window identification via /proc/<pid>/environ (Feature 057).

    Args:
        project_name: Project identifier or "global"
        working_dir: Working directory path
        app_name: Application name (default: "scratchpad-terminal")

    Returns:
        Dictionary of I3PM_* environment variables

    Environment Variables:
        I3PM_SCRATCHPAD: "true" (marks as scratchpad terminal)
        I3PM_APP_NAME: "scratchpad-terminal"
        I3PM_PROJECT_NAME: Project identifier
        I3PM_WORKING_DIR: Working directory path
        I3PM_SCOPE: "scoped" (project-scoped window)
        I3PM_APP_ID: Unique app ID with timestamp

    Note:
        The unified launcher (app-launcher-wrapper.sh) will add additional
        environment variables like I3PM_LAUNCHER_PID, I3PM_LAUNCH_TIME, etc.
    """
    app_id = f"scratchpad-{project_name}-{int(time.time())}"

    return {
        "I3PM_SCRATCHPAD": "true",
        "I3PM_APP_NAME": app_name,
        "I3PM_PROJECT_NAME": project_name,
        "I3PM_WORKING_DIR": str(working_dir),
        "I3PM_SCOPE": "scoped",
        "I3PM_APP_ID": app_id,
    }


def build_unified_launcher_invocation(
    project_name: str,
    working_dir: Path,
    workspace_number: int = 1,
) -> Tuple[list[str], Dict[str, str], Dict[str, any]]:
    """
    Build complete unified launcher invocation with all parameters.

    This is the main integration point with Features 041 and 057.

    Args:
        project_name: Project identifier or "global"
        working_dir: Working directory for terminal
        workspace_number: Target workspace (default: 1)

    Returns:
        Tuple of (command_args, environment_vars, launch_notification):
            - command_args: Command to execute (app-launcher-wrapper.sh + params)
            - environment_vars: I3PM_* env vars to inject
            - launch_notification: Payload for launch registry

    Example Usage:
        cmd, env, notification = build_unified_launcher_invocation("nixos", Path("/etc/nixos"))
        # 1. Send notification to launch registry
        await send_launch_notification(notification)
        # 2. Execute command with environment
        proc = await asyncio.create_subprocess_exec(*cmd, env={**os.environ, **env})

    Raises:
        RuntimeError: If no terminal emulator is available
    """
    # Select terminal emulator
    terminal_cmd, expected_class = select_terminal_emulator()

    # Build terminal command
    terminal_args = build_launch_command(terminal_cmd, working_dir, project_name)

    # Build app-launcher-wrapper.sh invocation
    launcher_path = "/run/current-system/sw/bin/app-launcher-wrapper.sh"  # TODO: Get from config
    command_args = [
        launcher_path,
        "--app-name", "scratchpad-terminal",
        "--project-name", project_name,
        "--project-dir", str(working_dir),
        "--workspace", str(workspace_number),
        "--command", " ".join(terminal_args),
    ]

    # Build environment variables
    environment_vars = build_launcher_environment(project_name, working_dir)

    # Build launch notification
    launch_notification = create_launch_notification_payload(
        project_name,
        expected_class,
        workspace_number,
    )

    logger.debug(
        f"Built unified launcher invocation: "
        f"terminal={terminal_cmd}, project={project_name}, "
        f"working_dir={working_dir}, workspace={workspace_number}"
    )

    return (command_args, environment_vars, launch_notification)
