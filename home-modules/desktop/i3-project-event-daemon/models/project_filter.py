"""
Pydantic models for project filtering and fuzzy search.

Feature 078: Enhanced Project Selection in Eww Preview Dialog
Feature 079: Preview Pane User Experience (branch number, worktree hierarchy)
Provides data models for fuzzy matching, filter state management, and project list items.
"""

from pydantic import BaseModel, Field, field_validator, model_validator
from typing import Optional, List
from datetime import datetime
import re


class MatchPosition(BaseModel):
    """Character position range where a match occurred.

    Feature 078: Used for highlighting matched characters in project names.
    """
    start: int = Field(..., ge=0, description="Start index of match (inclusive)")
    end: int = Field(..., ge=0, description="End index of match (exclusive)")


class GitStatus(BaseModel):
    """Git repository status for worktree projects.

    Feature 078: Git status indicators (clean/dirty, ahead/behind).
    """
    is_clean: bool = Field(..., description="No uncommitted changes")
    ahead_count: int = Field(default=0, ge=0, description="Commits ahead of remote")
    behind_count: int = Field(default=0, ge=0, description="Commits behind remote")


class ProjectListItem(BaseModel):
    """Single project entry in the filtered list with match metadata.

    Feature 078: Used for UI rendering in project selection mode.
    Feature 079: Enhanced with branch number and type for worktree hierarchy.
    Contains project metadata plus fuzzy match scoring information.
    """
    name: str = Field(..., min_length=1, description="Project identifier (e.g., '078-eww-preview-improvement')")
    display_name: str = Field(..., min_length=1, description="Human-readable project name")
    icon: str = Field(..., min_length=1, description="Emoji icon for the project")
    is_worktree: bool = Field(..., description="True if project is a git worktree")
    parent_project_name: Optional[str] = Field(default=None, description="Parent project name (for worktrees)")
    directory_exists: bool = Field(..., description="True if project directory exists on filesystem")
    relative_time: str = Field(..., description="Relative time since last activity (e.g., '2h ago')")

    # Feature 079: Branch metadata for numeric prefix filtering and hierarchy display
    branch_number: Optional[str] = Field(default=None, description="Extracted numeric prefix (e.g., '079')")
    branch_type: str = Field(default="main", description="Branch classification: 'feature', 'main', 'hotfix', 'release'")
    full_branch_name: str = Field(default="", description="Full git branch name (e.g., '079-preview-pane-user-experience')")

    # Git status (only for worktrees with git metadata)
    git_status: Optional[GitStatus] = Field(default=None, description="Git status indicators")

    # Match scoring for fuzzy search
    match_score: int = Field(default=0, ge=0, le=1100, description="Fuzzy match score (higher is better)")
    match_positions: List[MatchPosition] = Field(default_factory=list, description="Character positions where query matched")

    # Selection state for UI
    selected: bool = Field(default=False, description="True if this project is currently highlighted")

    @model_validator(mode='after')
    def extract_branch_metadata(self) -> 'ProjectListItem':
        """Extract branch number and classify branch type from full_branch_name.

        Feature 079: Automatic metadata extraction for numeric prefix filtering.
        """
        if self.full_branch_name and not self.branch_number:
            # Extract numeric prefix (e.g., '079' from '079-preview-pane-user-experience')
            match = re.match(r'^(\d+)-', self.full_branch_name)
            if match:
                self.branch_number = match.group(1)

        # Classify branch type based on naming pattern
        if self.full_branch_name:
            if re.match(r'^\d+-', self.full_branch_name):
                self.branch_type = "feature"
            elif self.full_branch_name.startswith("hotfix-"):
                self.branch_type = "hotfix"
            elif self.full_branch_name.startswith("release-"):
                self.branch_type = "release"
            elif self.branch_type == "main":
                # Keep default "main" for main/master branches
                pass

        return self

    def formatted_display_name(self) -> str:
        """Return formatted name with branch number if present.

        Feature 079: Display as '079 - Preview Pane UX' for deterministic filtering.
        """
        if self.branch_number:
            return f"{self.branch_number} - {self.display_name}"
        return self.display_name

    def indentation_level(self) -> int:
        """Calculate indentation level for hierarchy display.

        Feature 079: US5 - T038 - Worktree hierarchy indentation.
        Returns:
            0 for root projects (no parent)
            1 for worktrees with parent
            0 for orphan worktrees (parent not loaded)
        """
        if self.is_worktree and self.parent_project_name:
            return 1
        return 0

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "name": "078-eww-preview-improvement",
                    "display_name": "eww preview improvement",
                    "icon": "🌿",
                    "is_worktree": True,
                    "parent_project_name": "nixos",
                    "directory_exists": True,
                    "relative_time": "2h ago",
                    "git_status": {
                        "is_clean": True,
                        "ahead_count": 0,
                        "behind_count": 0
                    },
                    "match_score": 500,
                    "match_positions": [{"start": 0, "end": 3}],
                    "selected": True
                },
                {
                    "name": "nixos",
                    "display_name": "NixOS",
                    "icon": "❄️",
                    "is_worktree": False,
                    "parent_project_name": None,
                    "directory_exists": True,
                    "relative_time": "3d ago",
                    "git_status": None,
                    "match_score": 0,
                    "match_positions": [],
                    "selected": False
                }
            ]
        }


class ScoredMatch(BaseModel):
    """Result of fuzzy matching algorithm.

    Feature 078: Intermediate result from fuzzy match scoring before conversion to ProjectListItem.
    """
    project_name: str = Field(..., description="Project name that was matched")
    score: int = Field(..., ge=0, le=1100, description="Match score (higher is better)")
    match_positions: List[MatchPosition] = Field(default_factory=list, description="Character positions where query matched")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "project_name": "nixos",
                    "score": 1000,
                    "match_positions": [{"start": 0, "end": 5}]
                },
                {
                    "project_name": "078-eww-preview-improvement",
                    "score": 500,
                    "match_positions": [{"start": 0, "end": 3}]
                }
            ]
        }


class FilterState(BaseModel):
    """Track filter input and selection state for project mode.

    Feature 078: Maintains the current state of project selection mode including:
    - Accumulated filter characters
    - Current selection index
    - Whether user has manually navigated (affects auto-selection behavior)
    - Filtered project list
    """
    accumulated_chars: str = Field(default="", description="Filter characters typed by user")
    selected_index: int = Field(default=0, ge=0, description="Index of currently selected project")
    user_navigated: bool = Field(default=False, description="True if user has used arrow keys (disables auto-selection)")
    projects: List[ProjectListItem] = Field(default_factory=list, description="Filtered project list")

    def reset(self) -> None:
        """Reset to initial state (when exiting project mode)."""
        self.accumulated_chars = ""
        self.selected_index = 0
        self.user_navigated = False
        self.projects = []

    def add_char(self, char: str) -> None:
        """Add character to filter string.

        Args:
            char: Single character to append (should be lowercase alphanumeric or hyphen)
        """
        self.accumulated_chars += char
        # If user hasn't manually navigated, auto-select best match (index 0)
        if not self.user_navigated:
            self.selected_index = 0

    def remove_char(self) -> None:
        """Remove last character from filter string (backspace)."""
        if self.accumulated_chars:
            self.accumulated_chars = self.accumulated_chars[:-1]
        if not self.user_navigated:
            self.selected_index = 0

    def navigate_up(self) -> None:
        """Move selection up with circular wrapping."""
        if not self.projects:
            return
        self.user_navigated = True
        self.selected_index = (self.selected_index - 1) % len(self.projects)

    def navigate_down(self) -> None:
        """Move selection down with circular wrapping."""
        if not self.projects:
            return
        self.user_navigated = True
        self.selected_index = (self.selected_index + 1) % len(self.projects)

    def get_selected_project(self) -> Optional[ProjectListItem]:
        """Get currently selected project or None if list is empty."""
        if not self.projects or self.selected_index >= len(self.projects):
            return None
        return self.projects[self.selected_index]

    def update_projects(self, projects: List[ProjectListItem]) -> None:
        """Update filtered project list, maintaining selection if possible.

        Args:
            projects: New filtered project list (sorted by score or recency)
        """
        self.projects = projects
        # Clamp selection index to valid range
        if self.selected_index >= len(projects):
            self.selected_index = max(0, len(projects) - 1)
        # Update selected flags on all items
        for i, project in enumerate(self.projects):
            project.selected = (i == self.selected_index)

    def group_by_parent(self) -> List[dict]:
        """Group projects into parent-children hierarchy.

        Feature 079: US5 - T037/T039 - Worktree hierarchy grouping.

        Returns:
            List of dicts with 'parent' (ProjectListItem) and 'children' (List[ProjectListItem])
            Root projects have empty children list.
            Worktrees with loaded parent are children of their parent.
            Orphan worktrees (parent not loaded) become their own group.
        """
        if not self.projects:
            return []

        # Build parent map: parent_name -> list of children
        parent_to_children: dict = {}
        root_projects: List[ProjectListItem] = []
        orphan_worktrees: List[ProjectListItem] = []

        # Identify root projects
        root_names = {p.name for p in self.projects if not p.is_worktree}

        for project in self.projects:
            if not project.is_worktree:
                # Root project
                root_projects.append(project)
                if project.name not in parent_to_children:
                    parent_to_children[project.name] = []
            elif project.parent_project_name and project.parent_project_name in root_names:
                # Worktree with loaded parent
                if project.parent_project_name not in parent_to_children:
                    parent_to_children[project.parent_project_name] = []
                parent_to_children[project.parent_project_name].append(project)
            else:
                # Orphan worktree (parent not loaded or None)
                orphan_worktrees.append(project)

        # Build grouped structure preserving order
        groups = []

        # Add root projects with their children
        for root in root_projects:
            children = parent_to_children.get(root.name, [])
            groups.append({
                "parent": root,
                "children": children
            })

        # Add orphan worktrees as standalone groups
        for orphan in orphan_worktrees:
            groups.append({
                "parent": orphan,
                "children": []
            })

        return groups

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "examples": [
                {
                    "accumulated_chars": "",
                    "selected_index": 0,
                    "user_navigated": False,
                    "projects": []
                },
                {
                    "accumulated_chars": "nix",
                    "selected_index": 0,
                    "user_navigated": False,
                    "projects": [
                        {
                            "name": "nixos",
                            "display_name": "NixOS",
                            "icon": "❄️",
                            "is_worktree": False,
                            "parent_project_name": None,
                            "directory_exists": True,
                            "relative_time": "3d ago",
                            "git_status": None,
                            "match_score": 500,
                            "match_positions": [{"start": 0, "end": 3}],
                            "selected": True
                        }
                    ]
                }
            ]
        }
