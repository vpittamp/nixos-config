"""
ProjectService for project CRUD operations and active project state management.

Feature 058: Python Backend Consolidation
Feature 097: Git-Based Project Discovery and Management
Provides single source of truth for project state, preventing race conditions.
"""

from pathlib import Path
from typing import List, Optional, Dict, Set
from datetime import datetime
import logging

from ..models.project import Project, ActiveProjectState
from ..models.discovery import (
    DiscoveredRepository,
    DiscoveredWorktree,
    GitHubRepo,
    GitMetadata,
    ProjectStatus,
    SourceType,
    BranchMetadata,
    parse_branch_metadata,
)

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

    # =========================================================================
    # Feature 097: Discovery Integration
    # =========================================================================

    def get_existing_names(self) -> Set[str]:
        """Get set of all existing project names.

        Returns:
            Set of project name strings
        """
        return {p.name for p in self.list()}

    def find_by_directory(self, directory: str) -> Optional[Project]:
        """Find a project by its directory path.

        Args:
            directory: Absolute path to search for

        Returns:
            Project if found, None otherwise
        """
        normalized = str(Path(directory).resolve())
        for project in self.list():
            if str(Path(project.directory).resolve()) == normalized:
                return project
        return None

    async def create_or_update_from_discovery(
        self,
        discovered: DiscoveredRepository,
    ) -> Project:
        """Create a new project or update existing from discovered repository.

        Feature 097: Creates projects from git discovery results.

        Args:
            discovered: DiscoveredRepository or DiscoveredWorktree instance

        Returns:
            Created or updated Project instance
        """
        # Check if project already exists by directory
        existing = self.find_by_directory(discovered.path)

        if existing:
            # Update existing project with new metadata
            return await self._update_from_discovery(existing, discovered)
        else:
            # Create new project
            return await self._create_from_discovery(discovered)

    async def _create_from_discovery(
        self,
        discovered: DiscoveredRepository,
    ) -> Project:
        """Create a new project from discovery result.

        Feature 097: Creates projects from git discovery results.
        Feature 098: Adds parent project resolution and branch metadata parsing.

        Args:
            discovered: DiscoveredRepository instance

        Returns:
            Created Project instance
        """
        # Determine source type
        source_type = SourceType.LOCAL
        if isinstance(discovered, DiscoveredWorktree) or discovered.is_worktree:
            source_type = SourceType.WORKTREE

        # Create display name from project name
        display_name = discovered.name.replace("-", " ").replace("_", " ").title()

        now = datetime.now()

        # Feature 098: Resolve parent project name from parent_repo_path
        parent_project_name: Optional[str] = None
        if source_type == SourceType.WORKTREE and discovered.parent_repo_path:
            parent_project = self.find_by_directory(discovered.parent_repo_path)
            if parent_project:
                parent_project_name = parent_project.name
                logger.info(
                    f"[Feature 098] Resolved parent project: {discovered.parent_repo_path} -> {parent_project_name}"
                )
            else:
                logger.warning(
                    f"[Feature 098] Parent project not found for path: {discovered.parent_repo_path}. "
                    "Parent project must be discovered first."
                )

        # Feature 098: Parse branch metadata from git branch name
        branch_metadata: Optional[BranchMetadata] = None
        if discovered.git_metadata and discovered.git_metadata.current_branch:
            branch_metadata = parse_branch_metadata(discovered.git_metadata.current_branch)
            if branch_metadata:
                logger.info(
                    f"[Feature 098] Parsed branch metadata: "
                    f"number={branch_metadata.number}, type={branch_metadata.type}, "
                    f"full_name={branch_metadata.full_name}"
                )

                # Feature 098: Create enhanced display name for worktrees with branch numbers
                if branch_metadata.number and source_type == SourceType.WORKTREE:
                    # Extract description part after number (e.g., "integrate-new-project" from "098-integrate-new-project")
                    branch_desc = branch_metadata.full_name
                    if branch_desc.startswith(f"{branch_metadata.number}-"):
                        branch_desc = branch_desc[len(branch_metadata.number) + 1:]
                    # Remove type prefix if present (e.g., "feature-" from "feature-auth")
                    if branch_metadata.type and branch_desc.startswith(f"{branch_metadata.type}-"):
                        branch_desc = branch_desc[len(branch_metadata.type) + 1:]
                    # Format: "098 - Integrate New Project"
                    display_name = f"{branch_metadata.number} - {branch_desc.replace('-', ' ').replace('_', ' ').title()}"

        project = Project(
            name=discovered.name,
            directory=discovered.path,
            display_name=display_name,
            icon=discovered.inferred_icon,
            created_at=now,
            updated_at=now,
            scoped_classes=[],
            source_type=source_type,
            status=ProjectStatus.ACTIVE,
            git_metadata=discovered.git_metadata,
            discovered_at=now,
            # Feature 098: New fields
            parent_project=parent_project_name,
            branch_metadata=branch_metadata,
        )

        # Save to file
        project.save_to_file(self.config_dir)

        logger.info(
            f"[Feature 097] Created project from discovery: {discovered.name} "
            f"(source_type={source_type.value})"
        )

        return project

    async def _update_from_discovery(
        self,
        existing: Project,
        discovered: DiscoveredRepository,
    ) -> Project:
        """Update existing project with fresh discovery metadata.

        Args:
            existing: Existing Project instance
            discovered: DiscoveredRepository with new metadata

        Returns:
            Updated Project instance
        """
        # Update git metadata from fresh discovery
        existing.git_metadata = discovered.git_metadata
        existing.updated_at = datetime.now()

        # Restore from missing status if directory now exists
        if existing.status == ProjectStatus.MISSING:
            existing.status = ProjectStatus.ACTIVE
            logger.info(f"[Feature 097] Project {existing.name} restored from missing status")

        # Update icon if it changed (language detection)
        if existing.icon != discovered.inferred_icon and existing.icon == "📁":
            existing.icon = discovered.inferred_icon

        # Save updated project
        existing.save_to_file(self.config_dir)

        logger.info(f"[Feature 097] Updated project: {existing.name}")

        return existing

    async def mark_missing(self, name: str) -> Project:
        """Mark a project as missing (directory no longer exists).

        Feature 097: Preserves project when directory is temporarily unavailable.

        Args:
            name: Project name to mark as missing

        Returns:
            Updated Project instance

        Raises:
            FileNotFoundError: If project doesn't exist
        """
        project = Project.load_from_file(self.config_dir, name)

        if project.status != ProjectStatus.MISSING:
            project.status = ProjectStatus.MISSING
            project.updated_at = datetime.now()
            project.save_to_file(self.config_dir)

            logger.info(f"[Feature 097] Marked project as missing: {name}")

        return project

    async def check_and_mark_missing_projects(self) -> List[str]:
        """Check all projects and mark any with missing directories.

        Feature 097: Called during discovery to detect removed repositories.

        Returns:
            List of project names that were marked as missing
        """
        marked_missing = []

        for project in self.list():
            # Skip already missing or remote projects
            if project.status == ProjectStatus.MISSING:
                continue
            if project.source_type == SourceType.REMOTE:
                continue

            # Check if directory exists
            if not Path(project.directory).exists():
                await self.mark_missing(project.name)
                marked_missing.append(project.name)

        return marked_missing

    async def create_from_github_repo(
        self,
        gh_repo: "GitHubRepo",
    ) -> Project:
        """Create a remote-only project from a GitHub repository.

        Feature 097 T046: Create remote projects for uncloned GitHub repos.

        Args:
            gh_repo: GitHub repository information

        Returns:
            Created Project instance with source_type=REMOTE
        """
        from ..models.discovery import GitHubRepo  # noqa: F811

        now = datetime.now()

        # Use clone URL as "directory" for remote projects
        directory = gh_repo.clone_url

        # Create display name from repo name
        display_name = gh_repo.name.replace("-", " ").replace("_", " ").title()

        # Infer icon from language
        from ..services.discovery_service import infer_icon_from_language
        icon = infer_icon_from_language(gh_repo.primary_language)

        # Create git metadata from GitHub repo info
        git_metadata = GitMetadata(
            current_branch="main",  # Default, not known for uncloned repos
            commit_hash="0000000",  # Not known for uncloned repos
            is_clean=True,
            has_untracked=False,
            ahead_count=0,
            behind_count=0,
            remote_url=gh_repo.clone_url,
            primary_language=gh_repo.primary_language,
            last_commit_date=gh_repo.pushed_at,
        )

        project = Project(
            name=gh_repo.name,
            directory=directory,
            display_name=display_name,
            icon=icon,
            created_at=now,
            updated_at=now,
            scoped_classes=[],
            source_type=SourceType.REMOTE,
            status=ProjectStatus.ACTIVE,
            git_metadata=git_metadata,
            discovered_at=now,
        )

        # Save to file
        project.save_to_file(self.config_dir)

        logger.info(
            f"[Feature 097] Created remote project from GitHub: {gh_repo.name}"
        )

        return project
