"""
Project JSON Editor Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Handles CRUD operations for project JSON files at ~/.config/i3/projects/*.json
"""

import json
import shutil
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

from ..models.project_config import ProjectConfig, WorktreeConfig


def get_bare_repository_path(directory: str) -> Optional[str]:
    """
    Feature 097 Option A: Get the bare repository path (GIT_COMMON_DIR) for a directory.

    Git worktrees share a common directory (the bare repo or main repo's .git).
    This function returns the absolute path to that common directory, which is
    the canonical identifier for all worktrees belonging to the same repository.

    Args:
        directory: Path to check (any worktree or repo directory)

    Returns:
        Absolute path to the bare repository, or None if not a git repo
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            return None

        common_dir = result.stdout.strip()

        # The result might be relative, resolve to absolute
        if not common_dir.startswith("/"):
            # Get repo root to resolve relative path
            root_result = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=5
            )
            if root_result.returncode == 0:
                repo_root = root_result.stdout.strip()
                common_dir = str(Path(repo_root) / common_dir)

        # Normalize and remove trailing /.git if present
        # For bare repos like /path/to/repo.git, keep as-is
        # For regular repos, --git-common-dir returns /path/to/repo/.git
        if common_dir.endswith("/.git"):
            common_dir = common_dir[:-5]

        return common_dir
    except (subprocess.TimeoutExpired, OSError):
        return None


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
        List all projects and worktrees, organized by parent repository.

        Feature 097 T074: Organizes worktrees by their parent repository for
        efficient UI grouping in the monitoring panel.

        Feature 097 Option A: Uses bare repository path (GIT_COMMON_DIR) for
        accurate grouping, not another worktree's path.

        Returns:
            Dict with:
            - main_projects: List of non-worktree projects (with bare_repo_path added)
            - worktrees: List of worktree projects with parent_project field
            - worktrees_by_parent: Dict mapping bare repo path to list of worktrees
            - orphaned_worktrees: List of worktrees with no matching main project
        """
        main_projects = []
        worktrees = []
        worktrees_by_parent: Dict[str, list] = {}

        # First pass: collect all projects and identify worktrees
        for project_file in self.projects_dir.glob("*.json"):
            try:
                with open(project_file, 'r') as f:
                    data = json.load(f)

                # Feature 097 T074: Detect worktrees by:
                # 1. Explicit parent_project field (new format)
                # 2. worktree.repository_path field (legacy format from Feature 079)
                is_worktree = False
                parent_repo_path = None

                if "parent_project" in data:
                    # New format: explicit parent project name
                    is_worktree = True
                    parent_repo_path = data.get("parent_project")
                elif "worktree" in data and isinstance(data["worktree"], dict):
                    # Legacy format: worktree object with repository_path
                    worktree_info = data["worktree"]
                    if "repository_path" in worktree_info:
                        is_worktree = True
                        parent_repo_path = worktree_info["repository_path"]
                        # Add derived parent_project for UI consistency
                        data["parent_project"] = parent_repo_path

                if is_worktree:
                    worktrees.append(data)
                    # Group by parent repository path
                    if parent_repo_path:
                        if parent_repo_path not in worktrees_by_parent:
                            worktrees_by_parent[parent_repo_path] = []
                        worktrees_by_parent[parent_repo_path].append(data)
                else:
                    main_projects.append(data)
            except (json.JSONDecodeError, IOError) as e:
                # Skip invalid files
                continue

        # Feature 097 Option A: Compute bare_repo_path for each main project
        # This allows matching worktrees to main projects by their shared bare repo
        # When multiple main projects share the same bare repo (e.g., multiple worktrees
        # registered as "main" projects), prefer the one with the shortest directory path
        # (typically the "main" branch worktree like /etc/nixos)
        bare_repo_to_main_project: Dict[str, Dict] = {}
        for project in main_projects:
            directory = project.get("directory")
            if directory and Path(directory).exists():
                bare_repo = get_bare_repository_path(directory)
                if bare_repo:
                    project["bare_repo_path"] = bare_repo
                    # Only update if no existing entry, or this one has shorter path
                    existing = bare_repo_to_main_project.get(bare_repo)
                    if not existing or len(directory) < len(existing.get("directory", "")):
                        bare_repo_to_main_project[bare_repo] = project

        # Feature 097 Option A: Identify orphaned worktrees (no matching main project)
        # The worktree's repository_path may be another worktree path (legacy behavior)
        # We need to resolve it to the actual bare repo path for matching
        orphaned_worktrees = []
        for worktree in worktrees:
            parent_repo = worktree.get("parent_project")
            if parent_repo:
                # Resolve the stored repository_path to its bare repo
                # This handles both:
                # - Legacy: repository_path points to another worktree (e.g., /etc/nixos)
                # - New: repository_path already points to bare repo (e.g., /home/user/repo.git)
                resolved_bare_repo = None
                if Path(parent_repo).exists():
                    resolved_bare_repo = get_bare_repository_path(parent_repo)
                else:
                    # Path might already be a bare repo path
                    resolved_bare_repo = parent_repo

                # Check if any main project shares this bare repo
                if resolved_bare_repo and resolved_bare_repo in bare_repo_to_main_project:
                    # Found matching main project - update parent_project to use directory
                    main_proj = bare_repo_to_main_project[resolved_bare_repo]
                    worktree["parent_project"] = main_proj.get("directory")
                else:
                    # No matching main project found - this is orphaned
                    orphaned_worktrees.append(worktree)

        # Sort main projects alphabetically
        main_projects_sorted = sorted(main_projects, key=lambda p: p.get("name", ""))

        # Sort worktrees by parent, then by name within each parent group
        # Use "or" to handle None values (key exists but value is None)
        worktrees_sorted = sorted(
            worktrees,
            key=lambda w: (w.get("parent_project") or "", w.get("name") or "")
        )

        # Sort worktrees within each parent group
        for parent_path in worktrees_by_parent:
            worktrees_by_parent[parent_path] = sorted(
                worktrees_by_parent[parent_path],
                key=lambda w: w.get("name", "")
            )

        # Sort orphaned worktrees alphabetically
        orphaned_worktrees_sorted = sorted(
            orphaned_worktrees,
            key=lambda w: w.get("name", "")
        )

        return {
            "main_projects": main_projects_sorted,
            "worktrees": worktrees_sorted,
            "worktrees_by_parent": worktrees_by_parent,
            "orphaned_worktrees": orphaned_worktrees_sorted,
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
            # Feature 096 T007: Check for conflict BEFORE write (not after)
            # Conflict = file was modified by another process between our read and now
            file_mtime_before_write = project_file.stat().st_mtime
            has_conflict = file_mtime_before_write != file_mtime_before

            # Write updated config
            # Feature 094: Use by_alias=True to serialize "working_dir" as "directory" for backward compatibility
            with open(project_file, 'w') as f:
                json.dump(validated.model_dump(exclude_none=True, by_alias=True), f, indent=2)

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
