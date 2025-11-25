"""
Project JSON Editor Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Handles CRUD operations for project JSON files at ~/.config/i3/projects/*.json
"""

import json
import shutil
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

from ..models.project_config import ProjectConfig, WorktreeConfig


class ProjectEditor:
    """Service for managing project JSON files"""

    def __init__(self, projects_dir: Optional[Path] = None):
        """
        Initialize project editor

        Args:
            projects_dir: Directory containing project JSON files (default: ~/.config/i3/projects/)
        """
        self.projects_dir = projects_dir or Path.home() / ".config/i3/projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)

    def create_project(self, config: ProjectConfig) -> Dict[str, Any]:
        """
        Create new project JSON file

        Args:
            config: Validated ProjectConfig model

        Returns:
            Result dict with status and file path

        Raises:
            ValueError: If project already exists or validation fails
        """
        project_file = self.projects_dir / f"{config.name}.json"

        if project_file.exists():
            raise ValueError(f"Project '{config.name}' already exists")

        # Convert Pydantic model to dict, excluding None values for remote if not used
        # Feature 094: Use by_alias=True to serialize "working_dir" as "directory" for backward compatibility
        data = config.model_dump(exclude_none=True, by_alias=True)

        # Write JSON with pretty formatting
        with open(project_file, 'w') as f:
            json.dump(data, f, indent=2)

        return {
            "status": "success",
            "path": str(project_file),
            "project_name": config.name
        }

    def read_project(self, name: str) -> Dict[str, Any]:
        """
        Read project configuration from JSON file

        Args:
            name: Project name

        Returns:
            Project configuration dict

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        project_file = self.projects_dir / f"{name}.json"

        if not project_file.exists():
            raise FileNotFoundError(f"Project '{name}' not found")

        with open(project_file, 'r') as f:
            return json.load(f)

    def list_projects(self) -> Dict[str, Any]:
        """
        List all projects and worktrees

        Returns:
            Dict with main_projects and worktrees lists
        """
        main_projects = []
        worktrees = []

        for project_file in self.projects_dir.glob("*.json"):
            try:
                with open(project_file, 'r') as f:
                    data = json.load(f)

                # Check if worktree by presence of parent_project field
                if "parent_project" in data:
                    worktrees.append(data)
                else:
                    main_projects.append(data)
            except (json.JSONDecodeError, IOError) as e:
                # Skip invalid files
                continue

        return {
            "main_projects": sorted(main_projects, key=lambda p: p.get("name", "")),
            "worktrees": sorted(worktrees, key=lambda w: w.get("parent_project", ""))
        }

    def edit_project(self, name: str, updates: Dict[str, Any]) -> Dict[str, Any]:
        """
        Update existing project configuration

        Args:
            name: Project name
            updates: Dict of fields to update

        Returns:
            Result dict with status and conflict detection

        Raises:
            FileNotFoundError: If project doesn't exist
            ValueError: If validation fails
        """
        project_file = self.projects_dir / f"{name}.json"

        if not project_file.exists():
            raise FileNotFoundError(f"Project '{name}' not found")

        # Get file modification time before read (for conflict detection)
        file_mtime_before = project_file.stat().st_mtime

        # Read current config
        with open(project_file, 'r') as f:
            current_data = json.load(f)

        # Apply updates
        updated_data = {**current_data, **updates}

        # Validate with Pydantic (skip uniqueness check for existing project)
        # Feature 094: Pass context to skip name uniqueness validator during edit
        validation_context = {"edit_mode": True}

        # Determine if worktree or regular project
        if "parent_project" in updated_data:
            validated = WorktreeConfig.model_validate(updated_data, context=validation_context)
        else:
            validated = ProjectConfig.model_validate(updated_data, context=validation_context)

        # Create backup
        backup_file = project_file.with_suffix('.json.bak')
        shutil.copy2(project_file, backup_file)

        try:
            # Write updated config
            # Feature 094: Use by_alias=True to serialize "working_dir" as "directory" for backward compatibility
            with open(project_file, 'w') as f:
                json.dump(validated.model_dump(exclude_none=True, by_alias=True), f, indent=2)

            # Check for conflict (file modified between read and write)
            file_mtime_after = project_file.stat().st_mtime
            has_conflict = (file_mtime_after != file_mtime_before and
                          file_mtime_before != file_mtime_after)

            return {
                "status": "success",
                "conflict": has_conflict,
                "path": str(project_file)
            }
        except Exception as e:
            # Restore backup on error
            shutil.copy2(backup_file, project_file)
            raise

    def delete_project(self, name: str, force: bool = False) -> Dict[str, Any]:
        """
        Delete project JSON file

        Args:
            name: Project name
            force: If True, skip worktree check

        Returns:
            Result dict with status

        Raises:
            FileNotFoundError: If project doesn't exist
            ValueError: If project has active worktrees (per FR-P-015)
        """
        project_file = self.projects_dir / f"{name}.json"

        if not project_file.exists():
            raise FileNotFoundError(f"Project '{name}' not found")

        # Check if project has worktrees
        if not force:
            worktrees = [w for w in self.list_projects()["worktrees"]
                        if w.get("parent_project") == name]
            if worktrees:
                worktree_names = [w["name"] for w in worktrees]
                raise ValueError(
                    f"Cannot delete project '{name}' with active worktrees: {', '.join(worktree_names)}. "
                    f"Delete worktrees first or use force=True."
                )

        # Create backup before deletion
        backup_file = project_file.with_suffix('.json.deleted')
        shutil.copy2(project_file, backup_file)

        # Delete project file
        project_file.unlink()

        return {
            "status": "success",
            "path": str(project_file),
            "backup": str(backup_file)
        }

    def get_file_mtime(self, name: str) -> float:
        """
        Get file modification timestamp for conflict detection

        Args:
            name: Project name

        Returns:
            Modification timestamp (seconds since epoch)

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        project_file = self.projects_dir / f"{name}.json"

        if not project_file.exists():
            raise FileNotFoundError(f"Project '{name}' not found")

        return project_file.stat().st_mtime
