"""i3pm project indicator status block.

Feature 101: Uses active-worktree.json as single source of truth.
"""

import json
import logging
import re
from pathlib import Path
from typing import Optional

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)


def get_active_worktree() -> Optional[dict]:
    """Get active worktree from i3pm state file.

    Feature 101: Uses active-worktree.json as single source of truth.

    Returns:
        Dict with worktree data or None if no active project
    """
    active_worktree_file = Path.home() / ".config" / "i3" / "active-worktree.json"

    try:
        if not active_worktree_file.exists():
            logger.debug("No active worktree file found")
            return None

        with open(active_worktree_file, "r") as f:
            data = json.load(f)

        if not data or "qualified_name" not in data:
            logger.debug("No qualified_name in active worktree file")
            return None

        return data

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse active worktree JSON: {e}")
        return None
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
    branch = worktree_data.get("branch", "")
    repo_name = worktree_data.get("repo_name", "")

    # Extract branch number if present (e.g., "101-feature" -> "101")
    branch_number = None
    match = re.match(r'^(\d+)-', branch)
    if match:
        branch_number = match.group(1)

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
