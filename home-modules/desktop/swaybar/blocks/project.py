"""i3pm project indicator status block."""

import json
import subprocess
import logging
from typing import Optional

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)


def get_active_worktree() -> Optional[dict]:
    """Get active worktree from the daemon-backed i3pm CLI."""
    try:
        result = subprocess.run(
            ["i3pm", "context", "current", "--json"],
            capture_output=True,
            text=True,
            timeout=1.5,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        data = json.loads(result.stdout)
        if not isinstance(data, dict) or not data.get("qualified_name"):
            return None
        return data
    except Exception as e:
        logger.error(f"Failed to read active worktree: {e}")
        return None


def create_project_block(config: Config) -> Optional[StatusBlock]:
    """Create project indicator status block.

    Feature 101: Uses active-worktree.json for project display.

    Args:
        config: Status generator configuration

    Returns:
        StatusBlock or None if no active project
    """
    worktree_data = get_active_worktree()

    if not worktree_data:
        # No active project - don't show the block
        return None

    # Extract display info from worktree data
    branch = str(worktree_data.get("branch") or "")
    repo_name = str(worktree_data.get("repo_name") or worktree_data.get("qualified_name") or "")
    branch_prefix = branch.split("-", 1)[0]
    branch_number = branch_prefix if branch_prefix.isdigit() else None

    # Format display name: "101 - repo_name" or just "repo_name" for main
    if branch_number:
        display_name = f"{branch_number} - {repo_name}"
    else:
        display_name = repo_name if repo_name else branch

    # Icon based on branch type
    if branch == "main" or branch == "master":
        icon = "📦"  # Main/master branch
    else:
        icon = "🌿"  # Feature/worktree branch

    # Format: icon + display name
    full_text = f"{icon} {display_name}"

    # Color scheme - use accent color for active project
    color = "#89b4fa"  # Catppuccin Mocha blue

    return StatusBlock(
        full_text=full_text,
        name="project",
        color=color,
        markup="pango",
        separator=True,
        separator_block_width=15
    )
