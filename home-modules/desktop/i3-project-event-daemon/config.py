"""Configuration loader for i3 project event daemon.

Handles loading and saving project configurations, application classification,
and active project state from JSON files.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional
import tempfile
import os

from .models import ProjectConfig, ApplicationClassification, ActiveProjectState

logger = logging.getLogger(__name__)


def load_project_configs(config_dir: Path) -> Dict[str, ProjectConfig]:
    """Load all project configurations from JSON files.

    Args:
        config_dir: Directory containing project JSON files (~/.config/i3/projects)

    Returns:
        Dictionary mapping project names to ProjectConfig objects

    Raises:
        ValueError: If project configurations are invalid
    """
    projects: Dict[str, ProjectConfig] = {}

    if not config_dir.exists():
        logger.warning(f"Project config directory does not exist: {config_dir}")
        config_dir.mkdir(parents=True, exist_ok=True)
        return projects

    for json_file in config_dir.glob("*.json"):
        try:
            with open(json_file, "r") as f:
                data = json.load(f)

            # Parse datetime fields
            created = (
                datetime.fromisoformat(data["created"])
                if "created" in data
                else datetime.now()
            )
            last_active = (
                datetime.fromisoformat(data["last_active"])
                if "last_active" in data and data["last_active"]
                else None
            )

            # Create ProjectConfig
            project = ProjectConfig(
                name=data["name"],
                display_name=data.get("display_name", data["name"]),
                icon=data.get("icon", "📁"),
                directory=Path(data["directory"]),
                created=created,
                last_active=last_active,
            )

            projects[project.name] = project
            logger.debug(f"Loaded project: {project.name} from {json_file}")

        except (KeyError, ValueError, json.JSONDecodeError) as e:
            logger.error(f"Failed to load project config from {json_file}: {e}")
            continue

    logger.info(f"Loaded {len(projects)} project(s)")
    return projects


def load_app_classification(config_file: Path) -> ApplicationClassification:
    """Load application classification from JSON file.

    Args:
        config_file: Path to app-classes.json

    Returns:
        ApplicationClassification object with scoped and global class sets

    Raises:
        ValueError: If configuration is invalid (overlap between sets)
    """
    if not config_file.exists():
        logger.warning(f"Application classification file does not exist: {config_file}")
        # Return default classification
        return ApplicationClassification(
            scoped_classes={"Code", "ghostty", "Alacritty", "Yazi"},
            global_classes={"firefox", "chromium-browser", "k9s"},
        )

    try:
        with open(config_file, "r") as f:
            data = json.load(f)

        scoped_classes = set(data.get("scoped_classes", []))
        global_classes = set(data.get("global_classes", []))

        classification = ApplicationClassification(
            scoped_classes=scoped_classes, global_classes=global_classes
        )

        logger.info(
            f"Loaded application classification: "
            f"{len(scoped_classes)} scoped, {len(global_classes)} global"
        )
        return classification

    except (json.JSONDecodeError, ValueError) as e:
        logger.error(f"Failed to load application classification: {e}")
        raise


def save_active_project(state: ActiveProjectState, config_file: Path) -> None:
    """Save active project state to JSON file (atomic write).

    Uses temp file + rename pattern to prevent corruption.

    Args:
        state: Active project state to save
        config_file: Path to active-project.json
    """
    try:
        # Ensure parent directory exists
        config_file.parent.mkdir(parents=True, exist_ok=True)

        # Prepare data
        data = {
            "project_name": state.project_name,
            "activated_at": state.activated_at.isoformat(),
            "previous_project": state.previous_project,
        }

        # Atomic write using temp file + rename
        fd, temp_path = tempfile.mkstemp(
            dir=config_file.parent, prefix=".active-project-", suffix=".json"
        )

        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())  # Ensure data is written to disk

            # Atomic rename
            os.rename(temp_path, config_file)
            logger.debug(f"Saved active project state: {state.project_name}")

        except Exception:
            # Clean up temp file on error
            if Path(temp_path).exists():
                os.unlink(temp_path)
            raise

    except Exception as e:
        logger.error(f"Failed to save active project state: {e}")
        raise


def load_active_project(config_file: Path) -> Optional[ActiveProjectState]:
    """Load active project state from JSON file.

    Args:
        config_file: Path to active-project.json

    Returns:
        ActiveProjectState object or None if file doesn't exist
    """
    if not config_file.exists():
        logger.debug(f"Active project file does not exist: {config_file}")
        return None

    try:
        with open(config_file, "r") as f:
            data = json.load(f)

        state = ActiveProjectState(
            project_name=data.get("project_name"),
            activated_at=datetime.fromisoformat(data["activated_at"]),
            previous_project=data.get("previous_project"),
        )

        logger.info(f"Loaded active project: {state.project_name}")
        return state

    except (json.JSONDecodeError, KeyError, ValueError) as e:
        logger.error(f"Failed to load active project state: {e}")
        return None
