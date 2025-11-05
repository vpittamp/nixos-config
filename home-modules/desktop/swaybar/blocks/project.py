"""i3pm project indicator status block."""

import json
import logging
from pathlib import Path
from typing import Optional

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)


def get_active_project() -> Optional[dict]:
    """Get active project from i3pm daemon state.

    Returns:
        Dict with project_name or None if no active project
    """
    active_project_file = Path.home() / ".config" / "i3" / "active-project.json"

    try:
        if not active_project_file.exists():
            logger.debug("No active project file found")
            return None

        with open(active_project_file, "r") as f:
            data = json.load(f)

        if not data or "project_name" not in data:
            logger.debug("No project_name in active project file")
            return None

        return data

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse active project JSON: {e}")
        return None
    except Exception as e:
        logger.error(f"Failed to read active project: {e}")
        return None


def create_project_block(config: Config) -> Optional[StatusBlock]:
    """Create project indicator status block.

    Args:
        config: Status generator configuration

    Returns:
        StatusBlock or None if no active project
    """
    project_data = get_active_project()

    if not project_data:
        # No active project - don't show the block
        return None

    project_name = project_data.get("project_name", "unknown")

    # Icon for project indicator (folder/project icon)
    icon = "📁"  # Fallback emoji

    # Try to use Nerd Font icon if available
    try:
        icon = ""  # Nerd Font project icon
    except:
        pass

    # Format: icon + project name
    full_text = f"{icon} {project_name}"

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
