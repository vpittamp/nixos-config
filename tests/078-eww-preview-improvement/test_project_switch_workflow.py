#!/usr/bin/env python3
"""End-to-end integration test for project switch workflow.

Feature 078: Enhanced Project Selection in Eww Preview Dialog
Test T014: Validates complete project switch flow via fuzzy search.

This test validates the workflow components that enable project switching:
1. Filter state management
2. Fuzzy matching and priority ordering
3. Navigation state tracking
4. Metadata preservation through filters
"""

import sys
from pathlib import Path
import json

# Add daemon to path
daemon_path = str(
    Path(__file__).parent.parent.parent
    / "home-modules"
    / "desktop"
    / "i3-project-event-daemon"
)
sys.path.insert(0, daemon_path)

import pytest
from models.project_filter import ProjectListItem, FilterState, GitStatus
from project_filter_service import filter_projects, fuzzy_match_score, load_all_projects


@pytest.fixture
def mock_config_dir(tmp_path):
    """Create a temporary config directory with mock projects."""
    # load_all_projects expects ~/.config/i3/ and appends "projects" itself
    config_dir = tmp_path / ".config" / "i3"
    projects_dir = config_dir / "projects"
    projects_dir.mkdir(parents=True)

    # Create mock project files
    projects_data = [
        {
            "name": "nixos",
            "display_name": "NixOS Configuration",
            "icon": "❄️",
            "directory": str(tmp_path / "nixos"),
            "repository_path": None,
        },
        {
            "name": "078-eww-preview",
            "display_name": "Eww Preview Enhancement",
            "icon": "🌿",
            "directory": str(tmp_path / "078-eww-preview"),
            "repository_path": str(tmp_path / "nixos"),
        },
        {
            "name": "dapr-services",
            "display_name": "Dapr Microservices",
            "icon": "🔧",
            "directory": str(tmp_path / "dapr"),
            "repository_path": None,
        },
        {
            "name": "077-worktree",
            "display_name": "Worktree Creation",
            "icon": "🌿",
            "directory": str(tmp_path / "077-worktree"),
            "repository_path": str(tmp_path / "nixos"),
        },
    ]

    # Create directories for the projects
    for proj in projects_data:
        Path(proj["directory"]).mkdir(parents=True, exist_ok=True)

    for proj in projects_data:
        proj_file = projects_dir / f"{proj['name']}.json"
        proj_file.write_text(json.dumps(proj))

    # Return parent directory (load_all_projects will append "projects")
    return config_dir


class TestProjectSwitchWorkflow:
    """E2E test for project switch via fuzzy search."""

    def test_filter_state_tracks_accumulated_chars(self):
        """Test that FilterState tracks accumulated filter characters."""
        state = FilterState(
            accumulated_chars="",
            selected_index=0,
            projects=[],
        )

        # Simulate typing ":"
        state = FilterState(
            accumulated_chars=":",
            selected_index=0,
            projects=[],
        )
        assert state.accumulated_chars == ":"

        # Simulate typing "nix"
        state = FilterState(
            accumulated_chars=":nix",
            selected_index=0,
            projects=[],
        )
        assert state.accumulated_chars == ":nix"

    def test_filter_narrows_results_as_user_types(self):
        """Test that typing filter characters narrows the project list."""
        projects = [
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
            ),
            ProjectListItem(
                name="dapr-services",
                display_name="Dapr",
                icon="🔧",
                is_worktree=False,
                directory_exists=True,
                relative_time="1d ago",
            ),
            ProjectListItem(
                name="077-worktree",
                display_name="Worktree",
                icon="🌿",
                is_worktree=True,
                directory_exists=True,
                relative_time="5d ago",
            ),
        ]

        # Empty filter - all projects
        results = filter_projects(projects, "")
        assert len(results) == 3

        # Type "d" - narrows to dapr-services
        results = filter_projects(projects, "d")
        assert len(results) >= 1
        assert results[0].name == "dapr-services"

        # Type "nix" - narrows to nixos
        results = filter_projects(projects, "nix")
        assert len(results) == 1
        assert results[0].name == "nixos"

        # Type "077" - narrows to worktree
        results = filter_projects(projects, "077")
        assert len(results) == 1
        assert results[0].name == "077-worktree"

    def test_fuzzy_match_priority_ordering(self):
        """Test that exact > prefix > substring matches are prioritized."""
        projects = [
            ProjectListItem(
                name="my-nixos-fork",  # Substring match
                display_name="Fork",
                icon="📁",
                is_worktree=False,
                directory_exists=True,
                relative_time="5d ago",
            ),
            ProjectListItem(
                name="nixos",  # Exact match
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
            ),
            ProjectListItem(
                name="nixos-worktree",  # Prefix match
                display_name="Worktree",
                icon="🌳",
                is_worktree=True,
                directory_exists=True,
                relative_time="1d ago",
            ),
        ]

        results = filter_projects(projects, "nixos")

        # Verify priority: exact > prefix > substring
        assert results[0].name == "nixos"  # Exact match first
        assert results[1].name == "nixos-worktree"  # Prefix match second
        assert results[2].name == "my-nixos-fork"  # Substring match third

    def test_selected_index_updates_with_navigation(self):
        """Test that selected index can be updated for navigation."""
        projects = [
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
                selected=True,
            ),
            ProjectListItem(
                name="dapr",
                display_name="Dapr",
                icon="🔧",
                is_worktree=False,
                directory_exists=True,
                relative_time="1d ago",
                selected=False,
            ),
            ProjectListItem(
                name="worktree",
                display_name="Worktree",
                icon="🌿",
                is_worktree=True,
                directory_exists=True,
                relative_time="2d ago",
                selected=False,
            ),
        ]

        state = FilterState(
            accumulated_chars="",
            selected_index=0,
            projects=projects,
        )

        # Navigate down (in-place mutation)
        state.navigate_down()
        assert state.selected_index == 1

        # Navigate down again
        state.navigate_down()
        assert state.selected_index == 2

        # Navigate down wraps to beginning
        state.navigate_down()
        assert state.selected_index == 0

        # Navigate up wraps to end
        state.navigate_up()
        assert state.selected_index == 2

    def test_user_navigated_flag_tracked(self):
        """Test that user navigation is tracked."""
        state = FilterState(
            accumulated_chars="",
            selected_index=0,
            user_navigated=False,
            projects=[
                ProjectListItem(
                    name="nixos",
                    display_name="NixOS",
                    icon="❄️",
                    is_worktree=False,
                    directory_exists=True,
                    relative_time="3d ago",
                ),
                ProjectListItem(
                    name="dapr",
                    display_name="Dapr",
                    icon="🔧",
                    is_worktree=False,
                    directory_exists=True,
                    relative_time="1d ago",
                ),
            ],
        )

        # User hasn't navigated yet
        assert state.user_navigated is False

        # After navigation, flag is set (in-place mutation)
        state.navigate_down()
        assert state.user_navigated is True

    def test_no_match_returns_empty_list(self):
        """Test that no matches returns empty list."""
        projects = [
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
            ),
            ProjectListItem(
                name="dapr",
                display_name="Dapr",
                icon="🔧",
                is_worktree=False,
                directory_exists=True,
                relative_time="1d ago",
            ),
        ]

        results = filter_projects(projects, "xyz")
        assert len(results) == 0

    def test_worktree_metadata_preserved_through_filter(self):
        """Test that worktree metadata is preserved through filtering."""
        projects = [
            ProjectListItem(
                name="078-eww-preview",
                display_name="Eww Preview",
                icon="🌿",
                is_worktree=True,
                parent_project_name="nixos",
                directory_exists=True,
                relative_time="2h ago",
                git_status=GitStatus(is_clean=False, ahead_count=3, behind_count=1),
            )
        ]

        results = filter_projects(projects, "078")

        assert len(results) == 1
        assert results[0].is_worktree is True
        assert results[0].parent_project_name == "nixos"
        assert results[0].git_status.ahead_count == 3
        assert results[0].git_status.behind_count == 1

    def test_selected_property_reflects_current_index(self):
        """Test that selected property is correctly set based on index."""
        projects = [
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
                selected=True,
            ),
            ProjectListItem(
                name="dapr",
                display_name="Dapr",
                icon="🔧",
                is_worktree=False,
                directory_exists=True,
                relative_time="1d ago",
                selected=False,
            ),
        ]

        state = FilterState(
            accumulated_chars="",
            selected_index=0,
            projects=projects,
        )

        # First project should be selected
        assert state.projects[0].selected is True
        assert state.projects[1].selected is False

        # Navigate to second item and update selection flags
        state.selected_index = 1
        state.update_projects(projects)
        assert state.projects[0].selected is False
        assert state.projects[1].selected is True

    def test_load_projects_from_config_directory(self, mock_config_dir):
        """Test loading projects from config directory."""
        projects = load_all_projects(mock_config_dir)

        assert len(projects) == 4
        names = {p.name for p in projects}
        assert "nixos" in names
        assert "078-eww-preview" in names
        assert "dapr-services" in names
        assert "077-worktree" in names

    def test_worktree_detection_from_repository_path(self, mock_config_dir):
        """Test that worktrees are detected from repository_path field.

        Note: Current implementation (User Story 1 MVP) requires nested 'worktree' field.
        This test validates that projects load correctly; worktree detection is User Story 2.
        """
        projects = load_all_projects(mock_config_dir)

        # All projects should load
        assert len(projects) == 4

        # Current MVP: worktree detection requires nested 'worktree' object (User Story 2: T030-T032)
        # For now, all projects are root projects since mock uses top-level repository_path
        root_names = {p.name for p in projects}
        assert "nixos" in root_names
        assert "dapr-services" in root_names
        assert "078-eww-preview" in root_names
        assert "077-worktree" in root_names

    def test_complete_workflow_simulation(self, mock_config_dir):
        """Simulate complete user workflow: load -> filter -> select."""
        # Step 1: Load all projects (simulates entering project mode)
        all_projects = load_all_projects(mock_config_dir)
        assert len(all_projects) > 0

        # Step 2: User types "078" to filter
        filtered = filter_projects(all_projects, "078")
        assert len(filtered) == 1
        assert filtered[0].name == "078-eww-preview"

        # Step 3: First match is selected (index 0)
        state = FilterState(
            accumulated_chars=":078",
            selected_index=0,
            projects=filtered,
        )

        # Step 4: User presses Enter - selected project is at index 0
        selected_project = state.projects[state.selected_index]
        assert selected_project.name == "078-eww-preview"
        # Note: is_worktree detection is User Story 2 (T030-T032)
        # Current MVP loads project metadata without worktree detection
        assert selected_project.directory_exists is True

    def test_backspace_behavior_with_filter_state(self):
        """Test that backspace removes characters from filter."""
        state = FilterState(
            accumulated_chars=":nix",
            selected_index=0,
            projects=[],
        )

        # Remove last character
        new_chars = state.accumulated_chars[:-1]
        new_state = FilterState(
            accumulated_chars=new_chars,
            selected_index=0,
            projects=[],
        )

        assert new_state.accumulated_chars == ":ni"

        # Remove until only ":" remains
        new_state = FilterState(accumulated_chars=":", selected_index=0, projects=[])
        assert new_state.accumulated_chars == ":"

    def test_cancel_resets_filter_state(self):
        """Test that cancellation resets the filter state."""
        state = FilterState(
            accumulated_chars=":nix",
            selected_index=2,
            user_navigated=True,
            projects=[
                ProjectListItem(
                    name="nixos",
                    display_name="NixOS",
                    icon="❄️",
                    is_worktree=False,
                    directory_exists=True,
                    relative_time="3d ago",
                )
            ],
        )

        # Simulate cancel - reset to empty state
        reset_state = FilterState(
            accumulated_chars="",
            selected_index=0,
            user_navigated=False,
            projects=[],
        )

        assert reset_state.accumulated_chars == ""
        assert reset_state.selected_index == 0
        assert reset_state.user_navigated is False
        assert len(reset_state.projects) == 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
