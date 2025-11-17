"""Mock models and fixtures for Feature 079 tests."""

from typing import List, Optional
from dataclasses import dataclass, field


@dataclass
class MockGitStatus:
    """Mock git status for testing."""
    dirty: bool = False
    ahead: int = 0
    behind: int = 0
    branch: str = ""


@dataclass
class MockProjectListItem:
    """Mock project list item for testing FilterState navigation."""
    name: str
    display_name: str
    icon: str = ""
    branch_number: Optional[str] = None
    branch_type: str = "main"
    full_branch_name: str = ""
    is_worktree: bool = False
    parent_project_name: Optional[str] = None
    git_status: Optional[MockGitStatus] = None
    match_score: int = 0
    match_positions: List[int] = field(default_factory=list)
    relative_time: str = ""
    path: str = ""

    def formatted_display_name(self) -> str:
        """Return formatted name with branch number if present."""
        if self.branch_number:
            return f"{self.branch_number} - {self.display_name}"
        return self.display_name


@dataclass
class MockFilterState:
    """Mock filter state for testing navigation."""
    accumulated_chars: str = ""
    selected_index: int = 0
    user_navigated: bool = False
    projects: List[MockProjectListItem] = field(default_factory=list)
    total_unfiltered_count: int = 0
    grouped_by_parent: bool = False
    expanded_parents: List[str] = field(default_factory=list)

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

    def get_selected_project(self) -> Optional[MockProjectListItem]:
        """Return currently selected project."""
        if 0 <= self.selected_index < len(self.projects):
            return self.projects[self.selected_index]
        return None


def create_mock_projects(count: int = 5) -> List[MockProjectListItem]:
    """Create a list of mock projects for testing."""
    projects = []
    for i in range(count):
        branch_num = f"{70 + i:03d}"
        projects.append(
            MockProjectListItem(
                name=f"nixos-{branch_num}-feature-{i}",
                display_name=f"Feature {i}",
                branch_number=branch_num,
                branch_type="feature",
                full_branch_name=f"{branch_num}-feature-{i}",
                is_worktree=True,
                parent_project_name="nixos",
                relative_time=f"{i}h ago",
                path=f"/home/vpittamp/nixos-{branch_num}-feature-{i}"
            )
        )
    return projects
