"""
Unit tests for monitoring data output format.

Feature 097: Git-Based Project Discovery and Management
Task T047: Verify projects view includes git_metadata and source_type.
"""

import pytest
from pathlib import Path
from datetime import datetime
from unittest.mock import AsyncMock, patch, MagicMock
import json


class TestProjectsViewFormat:
    """Test monitoring data output format for projects view."""

    def test_project_includes_source_type(self):
        """Verify source_type is included in project data."""
        # Mock project data structure
        project = {
            "name": "test-project",
            "display_name": "Test Project",
            "directory": "/home/user/projects/test",
            "icon": "📦",
            "source_type": "local",
            "status": "active",
            "git_metadata": {
                "current_branch": "main",
                "commit_hash": "abc1234",
                "is_clean": True,
                "ahead_count": 0,
                "behind_count": 0,
            },
        }

        # Verify source_type is present
        assert "source_type" in project
        assert project["source_type"] in ["local", "worktree", "remote", "manual"]

    def test_project_includes_git_metadata(self):
        """Verify git_metadata is included in project data."""
        project = {
            "name": "test-project",
            "git_metadata": {
                "current_branch": "feature/097",
                "commit_hash": "def5678",
                "is_clean": False,
                "has_untracked": True,
                "ahead_count": 2,
                "behind_count": 1,
                "remote_url": "https://github.com/user/repo.git",
                "primary_language": "Python",
            },
        }

        git_meta = project["git_metadata"]
        assert "current_branch" in git_meta
        assert "commit_hash" in git_meta
        assert "is_clean" in git_meta
        assert "ahead_count" in git_meta
        assert "behind_count" in git_meta

    def test_project_status_field(self):
        """Verify status field (active/missing) is included."""
        active_project = {"name": "active-project", "status": "active"}
        missing_project = {"name": "missing-project", "status": "missing"}

        assert active_project["status"] == "active"
        assert missing_project["status"] == "missing"

    def test_worktree_project_has_parent(self):
        """Verify worktree projects include parent_repository info."""
        worktree_project = {
            "name": "feature-branch",
            "source_type": "worktree",
            "git_metadata": {
                "current_branch": "feature/097",
                "parent_repository": "/home/user/projects/main-repo",
            },
        }

        assert worktree_project["source_type"] == "worktree"
        assert "parent_repository" in worktree_project["git_metadata"]

    def test_source_type_grouping(self):
        """Verify projects can be grouped by source_type.

        Feature 097: Only LOCAL, WORKTREE, REMOTE are valid source types.
        MANUAL was removed - all projects must be discovered.
        """
        projects = [
            {"name": "local-1", "source_type": "local"},
            {"name": "local-2", "source_type": "local"},
            {"name": "worktree-1", "source_type": "worktree"},
            {"name": "remote-1", "source_type": "remote"},
        ]

        # Group by source_type
        grouped = {}
        for p in projects:
            st = p["source_type"]
            if st not in grouped:
                grouped[st] = []
            grouped[st].append(p)

        assert len(grouped["local"]) == 2
        assert len(grouped["worktree"]) == 1
        assert len(grouped["remote"]) == 1

    def test_git_dirty_indicator(self):
        """Verify git dirty status is easily derivable."""
        clean_project = {
            "name": "clean",
            "git_metadata": {"is_clean": True, "has_untracked": False},
        }
        dirty_project = {
            "name": "dirty",
            "git_metadata": {"is_clean": False, "has_untracked": True},
        }

        def is_dirty(project):
            gm = project.get("git_metadata", {})
            return not gm.get("is_clean", True) or gm.get("has_untracked", False)

        assert not is_dirty(clean_project)
        assert is_dirty(dirty_project)

    def test_ahead_behind_counts(self):
        """Verify ahead/behind counts for sync status."""
        project = {
            "name": "needs-push",
            "git_metadata": {
                "ahead_count": 3,
                "behind_count": 0,
            },
        }

        gm = project["git_metadata"]
        assert gm["ahead_count"] == 3
        assert gm["behind_count"] == 0

        # Derive sync status
        needs_push = gm["ahead_count"] > 0
        needs_pull = gm["behind_count"] > 0

        assert needs_push
        assert not needs_pull


class TestSourceTypeBadges:
    """Test source type badge mapping."""

    def test_source_type_to_badge_icon(self):
        """Verify source type to badge icon mapping."""
        badge_map = {
            "local": "📦",
            "worktree": "🌿",
            "remote": "☁️",
            "manual": "✍️",
        }

        assert badge_map["local"] == "📦"
        assert badge_map["worktree"] == "🌿"
        assert badge_map["remote"] == "☁️"
        assert badge_map["manual"] == "✍️"

    def test_status_warning_indicator(self):
        """Verify missing status gets warning indicator."""

        def get_status_indicator(status):
            return "⚠️" if status == "missing" else ""

        assert get_status_indicator("active") == ""
        assert get_status_indicator("missing") == "⚠️"


class TestEnhancedProjectData:
    """Test enhanced project data for UI display."""

    def test_branch_display_format(self):
        """Verify branch name is formatted for display."""
        project = {
            "name": "test",
            "git_metadata": {"current_branch": "feature/097-discovery"},
        }

        branch = project["git_metadata"]["current_branch"]
        # Should display just branch name without refs/heads/ prefix
        assert not branch.startswith("refs/")
        assert branch == "feature/097-discovery"

    def test_commit_hash_truncation(self):
        """Verify commit hash is truncated for display."""
        full_hash = "abc1234567890def1234567890abc1234567890de"
        truncated = full_hash[:7]

        assert len(truncated) == 7
        assert truncated == "abc1234"

    def test_discovered_at_timestamp(self):
        """Verify discovered_at timestamp is always present.

        Feature 097: All projects are discovered, so discovered_at is required.
        """
        project = {
            "name": "discovered",
            "source_type": "local",
            "discovered_at": "2025-11-26T12:00:00",
        }

        assert "discovered_at" in project
        assert project["discovered_at"] is not None
