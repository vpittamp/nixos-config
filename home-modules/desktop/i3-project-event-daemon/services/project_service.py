"""
ProjectService for project CRUD operations and active project state management.

Feature 058: Python Backend Consolidation
Provides single source of truth for project state, preventing race conditions.
"""

from pathlib import Path
from typing import List, Optional, Dict
from datetime import datetime
import logging

from ..models.project import Project, ActiveProjectState

logger = logging.getLogger(__name__)


class ProjectService:
    """Service for managing projects and active project state."""

    def __init__(self, config_dir: Path, state_manager=None):
        """
        Initialize ProjectService.

        Args:
            config_dir: Path to i3 config directory (e.g., ~/.config/i3)
            state_manager: Optional StateManager instance for in-memory state synchronization
        """
        self.config_dir = config_dir
        self.projects_dir = config_dir / "projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)
        self.state_manager = state_manager

    def create(
        self,
        name: str,
        directory: str,
        display_name: str,
        icon: str = "📁"
    ) -> Project:
        """
        Create a new project.

        Args:
            name: Unique project identifier (alphanumeric + dash/underscore)
            directory: Absolute path to project directory (must exist)
            display_name: Human-readable project name
            icon: Project icon (emoji or text)

        Returns:
            Created Project instance

        Raises:
            FileExistsError: If project with same name already exists
            ValueError: If directory validation fails (not absolute, doesn't exist, not a directory)
        """
        project_file = self.projects_dir / f"{name}.json"

        if project_file.exists():
            raise FileExistsError(f"Project already exists: {name}")

        # Pydantic validation handles directory checks
        project = Project(
            name=name,
            directory=directory,
            display_name=display_name,
            icon=icon,
            created_at=datetime.now(),
            updated_at=datetime.now()
        )

        # Save to file
        project.save_to_file(self.config_dir)

        logger.info(f"Created project: {name} at {directory}")
        return project

    def list(self) -> List[Project]:
        """
        List all projects sorted by name.

        Returns:
            List of Project instances
        """
        return Project.list_all(self.config_dir)

    def get(self, name: str) -> Project:
        """
        Get project by name.

        Args:
            name: Project name

        Returns:
            Project instance

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        return Project.load_from_file(self.config_dir, name)

    def update(
        self,
        name: str,
        directory: Optional[str] = None,
        display_name: Optional[str] = None,
        icon: Optional[str] = None
    ) -> Project:
        """
        Update project metadata.

        Args:
            name: Project to update
            directory: New directory path (optional)
            display_name: New display name (optional)
            icon: New icon (optional)

        Returns:
            Updated Project instance

        Raises:
            FileNotFoundError: If project doesn't exist
            ValueError: If new directory validation fails
        """
        # Load existing project
        project = Project.load_from_file(self.config_dir, name)

        # Update fields
        if directory is not None:
            project.directory = directory  # Pydantic will validate
        if display_name is not None:
            project.display_name = display_name
        if icon is not None:
            project.icon = icon

        # Update timestamp
        project.updated_at = datetime.now()

        # Save updated project
        project.save_to_file(self.config_dir)

        logger.info(f"Updated project: {name}")
        return project

    def delete(self, name: str) -> bool:
        """
        Delete a project.

        Args:
            name: Project to delete

        Returns:
            True if deleted successfully

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        project_file = self.projects_dir / f"{name}.json"

        if not project_file.exists():
            raise FileNotFoundError(f"Project not found: {name}")

        # Remove project file
        project_file.unlink()

        # If this was the active project, clear active state
        active_state = ActiveProjectState.load(self.config_dir)
        if active_state.project_name == name:
            active_state.project_name = None
            active_state.save(self.config_dir)
            logger.info(f"Cleared active project state (deleted project was active)")

        logger.info(f"Deleted project: {name}")
        return True

    def get_active(self) -> Optional[str]:
        """
        Get currently active project name.

        Returns:
            Project name if active, None if in global mode
        """
        state = ActiveProjectState.load(self.config_dir)
        return state.project_name

    async def set_active(self, name: Optional[str]) -> Dict[str, Optional[str]]:
        """
        Set active project (or clear to global mode).

        Args:
            name: Project name to activate, or None for global mode

        Returns:
            Dict with 'previous' and 'current' project names

        Raises:
            FileNotFoundError: If project name provided but doesn't exist
        """
        # Load current state
        current_state = ActiveProjectState.load(self.config_dir)
        previous = current_state.project_name

        # Validate project exists (if not None)
        if name is not None:
            # Will raise FileNotFoundError if doesn't exist
            self.get(name)

        # Update active state
        current_state.project_name = name
        current_state.save(self.config_dir)

        # Synchronize in-memory state (Feature 058: Fix for intent-first priority)
        # CRITICAL: handlers.py reads state_manager.state.active_project, so we must
        # update it here to keep disk and memory in sync!
        if self.state_manager:
            await self.state_manager.set_active_project(name)

        logger.info(f"Set active project: {name} (previous: {previous})")

        return {
            "previous": previous,
            "current": name
        }
