#!/usr/bin/env python3
"""Integration tests for project list rendering.

Feature 078: Enhanced Project Selection in Eww Preview Dialog
Test T013: Integration test for project list rendering.
"""

import sys
from pathlib import Path

# Add daemon to path FIRST (has models/ package)
daemon_path = str(Path(__file__).parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon")
sys.path.insert(0, daemon_path)

import pytest
import json
from models.project_filter import (
    ProjectListItem,
    FilterState,
    GitStatus,
)

# Now add workspace panel (has models.py module)
workspace_panel_path = str(Path(__file__).parent.parent.parent / "home-modules" / "tools" / "sway-workspace-panel")
sys.path.insert(0, workspace_panel_path)

# Import workspace panel models with explicit module import
import importlib.util
spec = importlib.util.spec_from_file_location(
    "workspace_panel_models",
    Path(workspace_panel_path) / "models.py"
)
workspace_panel_models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workspace_panel_models)

# Extract the classes we need
ProjectListPreview = workspace_panel_models.ProjectListPreview
ProjectListEntry = workspace_panel_models.ProjectListEntry
ProjectGitStatus = workspace_panel_models.ProjectGitStatus


class TestFilterStateToPreviewConversion:
    """Test conversion from daemon FilterState to Eww preview data."""

    def test_empty_filter_state_produces_valid_preview(self):
        """Empty filter state should produce valid preview structure."""
        filter_state = FilterState(
            accumulated_chars="",
            selected_index=0,
            user_navigated=False,
            projects=[],
        )

        # Convert to preview data
        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars=filter_state.accumulated_chars,
            selected_index=filter_state.selected_index,
            total_count=len(filter_state.projects),
            projects=[],
            empty=len(filter_state.projects) == 0,
        )

        assert preview.type == "project_list"
        assert preview.accumulated_chars == ""
        assert preview.selected_index == 0
        assert preview.total_count == 0
        assert preview.empty is True

    def test_single_project_renders_correctly(self):
        """Single project should render with all metadata."""
        project = ProjectListItem(
            name="nixos",
            display_name="NixOS",
            icon="❄️",
            is_worktree=False,
            parent_project_name=None,
            directory_exists=True,
            relative_time="3d ago",
            git_status=None,
            match_score=0,
            match_positions=[],
            selected=True,
        )

        filter_state = FilterState(
            accumulated_chars="",
            selected_index=0,
            projects=[project],
        )

        # Convert to Eww entry
        entry = ProjectListEntry(
            name=project.name,
            display_name=project.display_name,
            icon=project.icon,
            is_worktree=project.is_worktree,
            parent_project_name=project.parent_project_name,
            directory_exists=project.directory_exists,
            relative_time=project.relative_time,
            git_status=None,
            selected=project.selected,
        )

        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars=filter_state.accumulated_chars,
            selected_index=filter_state.selected_index,
            total_count=1,
            projects=[entry],
            empty=False,
        )

        assert preview.total_count == 1
        assert preview.projects[0].name == "nixos"
        assert preview.projects[0].selected is True
        assert preview.empty is False

    def test_worktree_with_git_status_renders(self):
        """Worktree project with git status should render correctly."""
        project = ProjectListItem(
            name="078-eww-preview-improvement",
            display_name="eww preview improvement",
            icon="🌿",
            is_worktree=True,
            parent_project_name="nixos",
            directory_exists=True,
            relative_time="2h ago",
            git_status=GitStatus(
                is_clean=True,
                ahead_count=0,
                behind_count=0,
            ),
            match_score=500,
            match_positions=[],
            selected=False,
        )

        # Convert git status
        git_status_eww = None
        if project.git_status:
            git_status_eww = ProjectGitStatus(
                is_clean=project.git_status.is_clean,
                ahead_count=project.git_status.ahead_count,
                behind_count=project.git_status.behind_count,
            )

        entry = ProjectListEntry(
            name=project.name,
            display_name=project.display_name,
            icon=project.icon,
            is_worktree=project.is_worktree,
            parent_project_name=project.parent_project_name,
            directory_exists=project.directory_exists,
            relative_time=project.relative_time,
            git_status=git_status_eww,
            selected=project.selected,
        )

        assert entry.is_worktree is True
        assert entry.parent_project_name == "nixos"
        assert entry.git_status is not None
        assert entry.git_status.is_clean is True
        assert entry.git_status.ahead_count == 0

    def test_dirty_worktree_with_ahead_behind(self):
        """Dirty worktree with ahead/behind should render correctly."""
        project = ProjectListItem(
            name="077-worktree-creation",
            display_name="worktree creation",
            icon="🌿",
            is_worktree=True,
            parent_project_name="nixos",
            directory_exists=True,
            relative_time="1d ago",
            git_status=GitStatus(
                is_clean=False,
                ahead_count=3,
                behind_count=1,
            ),
            selected=True,
        )

        git_status_eww = ProjectGitStatus(
            is_clean=project.git_status.is_clean,
            ahead_count=project.git_status.ahead_count,
            behind_count=project.git_status.behind_count,
        )

        entry = ProjectListEntry(
            name=project.name,
            display_name=project.display_name,
            icon=project.icon,
            is_worktree=project.is_worktree,
            parent_project_name=project.parent_project_name,
            directory_exists=project.directory_exists,
            relative_time=project.relative_time,
            git_status=git_status_eww,
            selected=project.selected,
        )

        assert entry.git_status.is_clean is False
        assert entry.git_status.ahead_count == 3
        assert entry.git_status.behind_count == 1

    def test_missing_directory_warning(self):
        """Missing directory should set warning flag."""
        project = ProjectListItem(
            name="missing-project",
            display_name="Missing Project",
            icon="⚠️",
            is_worktree=False,
            parent_project_name=None,
            directory_exists=False,
            relative_time="unknown",
            git_status=None,
            selected=False,
        )

        entry = ProjectListEntry(
            name=project.name,
            display_name=project.display_name,
            icon=project.icon,
            is_worktree=project.is_worktree,
            parent_project_name=project.parent_project_name,
            directory_exists=project.directory_exists,
            relative_time=project.relative_time,
            git_status=None,
            selected=project.selected,
        )

        assert entry.directory_exists is False

    def test_filter_chars_displayed(self):
        """Accumulated filter chars should be in preview."""
        filter_state = FilterState(
            accumulated_chars="nix",
            selected_index=0,
            projects=[],
        )

        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars=filter_state.accumulated_chars,
            selected_index=filter_state.selected_index,
            total_count=0,
            projects=[],
            empty=True,
        )

        assert preview.accumulated_chars == "nix"

    def test_selection_index_preserved(self):
        """Selected index should be preserved in preview."""
        projects = [
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
                selected=False,
            ),
            ProjectListItem(
                name="dapr",
                display_name="Dapr",
                icon="🔧",
                is_worktree=False,
                directory_exists=True,
                relative_time="1d ago",
                selected=True,  # Second item selected
            ),
        ]

        filter_state = FilterState(
            accumulated_chars="",
            selected_index=1,
            projects=projects,
        )

        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars=filter_state.accumulated_chars,
            selected_index=filter_state.selected_index,
            total_count=len(projects),
            projects=[
                ProjectListEntry(
                    name=p.name,
                    display_name=p.display_name,
                    icon=p.icon,
                    is_worktree=p.is_worktree,
                    parent_project_name=p.parent_project_name,
                    directory_exists=p.directory_exists,
                    relative_time=p.relative_time,
                    git_status=None,
                    selected=p.selected,
                )
                for p in projects
            ],
            empty=False,
        )

        assert preview.selected_index == 1
        assert preview.projects[0].selected is False
        assert preview.projects[1].selected is True


class TestPreviewJsonSerialization:
    """Test JSON serialization for Eww consumption."""

    def test_preview_serializes_to_valid_json(self):
        """Preview should serialize to valid JSON."""
        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars="nix",
            selected_index=0,
            total_count=1,
            projects=[
                ProjectListEntry(
                    name="nixos",
                    display_name="NixOS",
                    icon="❄️",
                    is_worktree=False,
                    parent_project_name=None,
                    directory_exists=True,
                    relative_time="3d ago",
                    git_status=None,
                    selected=True,
                )
            ],
            empty=False,
        )

        # Serialize to JSON
        json_str = preview.model_dump_json()
        parsed = json.loads(json_str)

        assert parsed["type"] == "project_list"
        assert parsed["accumulated_chars"] == "nix"
        assert parsed["selected_index"] == 0
        assert len(parsed["projects"]) == 1
        assert parsed["projects"][0]["name"] == "nixos"

    def test_git_status_serializes_correctly(self):
        """Git status should serialize with all fields."""
        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars="",
            selected_index=0,
            total_count=1,
            projects=[
                ProjectListEntry(
                    name="078-eww-preview-improvement",
                    display_name="eww preview improvement",
                    icon="🌿",
                    is_worktree=True,
                    parent_project_name="nixos",
                    directory_exists=True,
                    relative_time="2h ago",
                    git_status=ProjectGitStatus(
                        is_clean=True,
                        ahead_count=2,
                        behind_count=0,
                    ),
                    selected=True,
                )
            ],
            empty=False,
        )

        json_str = preview.model_dump_json()
        parsed = json.loads(json_str)

        git_status = parsed["projects"][0]["git_status"]
        assert git_status["is_clean"] is True
        assert git_status["ahead_count"] == 2
        assert git_status["behind_count"] == 0

    def test_null_parent_serializes_as_null(self):
        """Null parent project should serialize as JSON null."""
        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars="",
            selected_index=0,
            total_count=1,
            projects=[
                ProjectListEntry(
                    name="nixos",
                    display_name="NixOS",
                    icon="❄️",
                    is_worktree=False,
                    parent_project_name=None,
                    directory_exists=True,
                    relative_time="3d ago",
                    git_status=None,
                    selected=True,
                )
            ],
            empty=False,
        )

        json_str = preview.model_dump_json()
        parsed = json.loads(json_str)

        assert parsed["projects"][0]["parent_project_name"] is None
        assert parsed["projects"][0]["git_status"] is None

    def test_empty_project_list_serializes(self):
        """Empty project list should serialize correctly."""
        preview = ProjectListPreview(
            visible=True,
            type="project_list",
            accumulated_chars="xyz",
            selected_index=0,
            total_count=0,
            projects=[],
            empty=True,
        )

        json_str = preview.model_dump_json()
        parsed = json.loads(json_str)

        assert parsed["projects"] == []
        assert parsed["empty"] is True
        assert parsed["total_count"] == 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
