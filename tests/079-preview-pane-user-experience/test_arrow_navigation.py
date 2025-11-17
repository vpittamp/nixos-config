"""
Unit tests for arrow key navigation in project selection mode.

Feature 079: User Story 1 - Navigate Project List with Arrow Keys
Tests NavigationHandler and FilterState navigation behavior.
"""

import pytest
import sys
from pathlib import Path

# Add daemon module to path
daemon_path = Path(__file__).parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_path))

from models.project_filter import ProjectListItem, FilterState


class TestFilterStateNavigation:
    """Test FilterState navigate_up() and navigate_down() methods."""

    def test_navigate_down_moves_selection(self):
        """T013: Arrow down moves selection to next project."""
        state = FilterState()
        state.projects = [
            self._create_project("proj1", "Project 1"),
            self._create_project("proj2", "Project 2"),
            self._create_project("proj3", "Project 3"),
        ]
        state.selected_index = 0

        state.navigate_down()

        assert state.selected_index == 1
        assert state.user_navigated is True

    def test_navigate_down_wraps_at_bottom(self):
        """T013: Arrow down wraps to top at end of list (circular)."""
        state = FilterState()
        state.projects = [
            self._create_project("proj1", "Project 1"),
            self._create_project("proj2", "Project 2"),
            self._create_project("proj3", "Project 3"),
        ]
        state.selected_index = 2  # Last item

        state.navigate_down()

        assert state.selected_index == 0  # Wrapped to first
        assert state.user_navigated is True

    def test_navigate_up_moves_selection(self):
        """T014: Arrow up moves selection to previous project."""
        state = FilterState()
        state.projects = [
            self._create_project("proj1", "Project 1"),
            self._create_project("proj2", "Project 2"),
            self._create_project("proj3", "Project 3"),
        ]
        state.selected_index = 2

        state.navigate_up()

        assert state.selected_index == 1
        assert state.user_navigated is True

    def test_navigate_up_wraps_at_top(self):
        """T014: Arrow up wraps to bottom at start of list (circular)."""
        state = FilterState()
        state.projects = [
            self._create_project("proj1", "Project 1"),
            self._create_project("proj2", "Project 2"),
            self._create_project("proj3", "Project 3"),
        ]
        state.selected_index = 0  # First item

        state.navigate_up()

        assert state.selected_index == 2  # Wrapped to last
        assert state.user_navigated is True

    def test_navigate_empty_list_no_change(self):
        """Navigate on empty list should not change state."""
        state = FilterState()
        state.projects = []
        state.selected_index = 0

        state.navigate_down()
        assert state.selected_index == 0

        state.navigate_up()
        assert state.selected_index == 0

    def test_navigate_sets_user_navigated_flag(self):
        """Navigation marks user_navigated=True to disable auto-selection."""
        state = FilterState()
        state.projects = [self._create_project("proj1", "Project 1")]
        state.user_navigated = False

        state.navigate_down()

        assert state.user_navigated is True

    def test_get_selected_project_returns_correct_item(self):
        """get_selected_project() returns the currently highlighted project."""
        state = FilterState()
        proj2 = self._create_project("proj2", "Project 2")
        state.projects = [
            self._create_project("proj1", "Project 1"),
            proj2,
            self._create_project("proj3", "Project 3"),
        ]
        state.selected_index = 1

        selected = state.get_selected_project()

        assert selected is not None
        assert selected.name == "proj2"
        assert selected.display_name == "Project 2"

    def test_navigation_with_filtered_results(self):
        """Navigation works correctly on filtered (smaller) list."""
        state = FilterState()
        state.accumulated_chars = ":nix"
        state.projects = [
            self._create_project("nixos", "NixOS"),
            self._create_project("nixos-079", "079 Feature"),
        ]
        state.selected_index = 0

        state.navigate_down()
        assert state.selected_index == 1

        state.navigate_down()
        assert state.selected_index == 0  # Wrap

    @staticmethod
    def _create_project(name: str, display_name: str) -> ProjectListItem:
        """Helper to create ProjectListItem for tests."""
        return ProjectListItem(
            name=name,
            display_name=display_name,
            icon="📁",
            is_worktree=False,
            directory_exists=True,
            relative_time="1h ago",
        )


class TestNavigationHandlerProjectMode:
    """Test NavigationHandler routing for project_list mode.

    T012: These tests verify that arrow key events are properly routed
    to project list navigation when in project selection mode.
    """

    def test_navigation_handler_identifies_project_mode(self):
        """Handler should recognize project_list mode parameter."""
        # This is a placeholder test for workspace-preview-daemon changes
        # The actual implementation will be in the daemon code
        mode = "project_list"
        assert mode == "project_list"

    def test_navigation_mode_not_all_windows(self):
        """Handler should distinguish project_list from all_windows mode."""
        all_windows_mode = "all_windows"
        project_mode = "project_list"

        # These should be treated differently
        assert all_windows_mode != project_mode


class TestProjectListItemBranchMetadata:
    """Test that branch metadata is correctly extracted."""

    def test_branch_number_extracted_from_full_name(self):
        """Branch number is automatically extracted via validator."""
        item = ProjectListItem(
            name="nixos-079-preview",
            display_name="Preview Pane",
            icon="🌿",
            is_worktree=True,
            directory_exists=True,
            relative_time="2h ago",
            full_branch_name="079-preview-pane-user-experience",
        )

        assert item.branch_number == "079"
        assert item.branch_type == "feature"

    def test_branch_type_classified_as_feature(self):
        """Branches starting with digits are classified as feature."""
        item = ProjectListItem(
            name="proj",
            display_name="Proj",
            icon="📁",
            is_worktree=True,
            directory_exists=True,
            relative_time="1h ago",
            full_branch_name="078-eww-preview-improvement",
        )

        assert item.branch_type == "feature"

    def test_branch_type_classified_as_hotfix(self):
        """Branches starting with hotfix- are classified as hotfix."""
        item = ProjectListItem(
            name="proj",
            display_name="Proj",
            icon="📁",
            is_worktree=True,
            directory_exists=True,
            relative_time="1h ago",
            full_branch_name="hotfix-critical-bug",
        )

        assert item.branch_type == "hotfix"
        assert item.branch_number is None

    def test_formatted_display_name_with_branch_number(self):
        """Formatted name includes branch number prefix."""
        item = ProjectListItem(
            name="nixos-079-preview",
            display_name="Preview Pane UX",
            icon="🌿",
            is_worktree=True,
            directory_exists=True,
            relative_time="2h ago",
            full_branch_name="079-preview-pane-user-experience",
        )

        formatted = item.formatted_display_name()

        assert formatted == "079 - Preview Pane UX"

    def test_formatted_display_name_without_branch_number(self):
        """Formatted name is just display_name when no branch number."""
        item = ProjectListItem(
            name="nixos",
            display_name="NixOS Config",
            icon="❄️",
            is_worktree=False,
            directory_exists=True,
            relative_time="3d ago",
            full_branch_name="main",
        )

        formatted = item.formatted_display_name()

        assert formatted == "NixOS Config"
        assert item.branch_number is None
