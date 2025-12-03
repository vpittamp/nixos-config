# Feature 111: Unit tests for WorktreeRelationship model
"""Tests for the WorktreeRelationship dataclass."""

import time
import pytest


class TestWorktreeRelationship:
    """Tests for WorktreeRelationship model."""

    def test_create_relationship(self):
        """Test creating a WorktreeRelationship instance."""
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        rel = WorktreeRelationship(
            source_branch="111-visual-map",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=2,
            is_diverged=True,
            computed_at=int(time.time()),
        )

        assert rel.source_branch == "111-visual-map"
        assert rel.target_branch == "main"
        assert rel.merge_base_commit == "abc1234"
        assert rel.ahead_count == 5
        assert rel.behind_count == 2
        assert rel.is_diverged is True

    def test_is_stale_fresh(self):
        """Test is_stale returns False for fresh relationship."""
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        rel = WorktreeRelationship(
            source_branch="111-visual-map",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=0,
            is_diverged=False,
            computed_at=int(time.time()),
        )

        assert rel.is_stale(ttl_seconds=300) is False

    def test_is_stale_expired(self):
        """Test is_stale returns True for expired relationship."""
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        # Set computed_at to 10 minutes ago
        rel = WorktreeRelationship(
            source_branch="111-visual-map",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=0,
            is_diverged=False,
            computed_at=int(time.time()) - 600,  # 10 minutes ago
        )

        assert rel.is_stale(ttl_seconds=300) is True  # 5 minute TTL

    def test_sync_label_ahead_only(self):
        """Test sync_label with only ahead commits."""
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        rel = WorktreeRelationship(
            source_branch="111-visual-map",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=0,
            is_diverged=False,
            computed_at=int(time.time()),
        )

        assert rel.sync_label == "↑5"

    def test_sync_label_behind_only(self):
        """Test sync_label with only behind commits."""
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        rel = WorktreeRelationship(
            source_branch="111-visual-map",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=0,
            behind_count=3,
            is_diverged=False,
            computed_at=int(time.time()),
        )

        assert rel.sync_label == "↓3"

    def test_sync_label_diverged(self):
        """Test sync_label with both ahead and behind commits."""
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        rel = WorktreeRelationship(
            source_branch="111-visual-map",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=3,
            is_diverged=True,
            computed_at=int(time.time()),
        )

        assert rel.sync_label == "↑5 ↓3"

    def test_sync_label_in_sync(self):
        """Test sync_label when branch is in sync."""
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        rel = WorktreeRelationship(
            source_branch="111-visual-map",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=0,
            behind_count=0,
            is_diverged=False,
            computed_at=int(time.time()),
        )

        assert rel.sync_label == ""
