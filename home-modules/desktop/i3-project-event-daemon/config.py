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

from .models import ApplicationClassification, ActiveProjectState

# Initialize logger first (before any usage)
logger = logging.getLogger(__name__)

# Import Project from i3pm
try:
    from i3_project_manager.core.models import Project
except ImportError:
    logger.warning("i3pm not installed, using minimal project loading")
    Project = None  # type: ignore


def load_project_configs(config_dir: Path) -> Dict[str, "Project"]:
    """Load all project configurations from JSON files using i3pm.

    Args:
        config_dir: Directory containing project JSON files (~/.config/i3/projects)

    Returns:
        Dictionary mapping project names to Project objects (from i3pm)

    Raises:
        ValueError: If project configurations are invalid
    """
    projects: Dict[str, "Project"] = {}

    if not config_dir.exists():
        logger.warning(f"Project config directory does not exist: {config_dir}")
        config_dir.mkdir(parents=True, exist_ok=True)
        return projects

    # Use i3pm's Project.list_all() method for consistent loading
    if Project:
        try:
            all_projects = Project.list_all(config_dir)
            for project in all_projects:
                projects[project.name] = project
                logger.debug(f"Loaded project: {project.name}")
            logger.info(f"Loaded {len(projects)} project(s) via i3pm")
        except Exception as e:
            logger.error(f"Failed to load projects via i3pm: {e}")
    else:
        logger.error("i3pm not available, cannot load projects")

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

        # Support two JSON formats:
        # 1. New format: {"scoped_classes": [...], "global_classes": [...]}
        # 2. Legacy format: {"classes": [{"class": "Foo", "scoped": true},...]}
        if "scoped_classes" in data or "global_classes" in data:
            # New format
            scoped_classes = set(data.get("scoped_classes", []))
            global_classes = set(data.get("global_classes", []))
        elif "classes" in data:
            # Legacy format - convert from class objects
            scoped_classes = set()
            global_classes = set()
            for class_config in data.get("classes", []):
                class_name = class_config.get("class", "")
                is_scoped = class_config.get("scoped", False)
                if class_name:
                    if is_scoped:
                        scoped_classes.add(class_name)
                    else:
                        global_classes.add(class_name)
        else:
            # Neither format found - return empty
            logger.warning(f"Unknown app-classes.json format, using empty classification")
            scoped_classes = set()
            global_classes = set()

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
