# Feature 111: Unit tests for WorktreeRelationshipCache
"""Tests for the relationship cache with TTL."""

import time
import pytest


class TestWorktreeRelationshipCache:
    """Tests for WorktreeRelationshipCache class."""

    def test_cache_set_and_get(self):
        """Test setting and getting cached relationship."""
        from i3_project_manager.services.git_utils import WorktreeRelationshipCache
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        cache = WorktreeRelationshipCache(ttl_seconds=300)

        rel = WorktreeRelationship(
            source_branch="feature",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=0,
            is_diverged=False,
            computed_at=int(time.time()),
        )

        cache.set("/repo", "feature", "main", rel)
        result = cache.get("/repo", "feature", "main")

        assert result is not None
        assert result.source_branch == "feature"
        assert result.ahead_count == 5

    def test_cache_miss(self):
        """Test cache miss for non-existent relationship."""
        from i3_project_manager.services.git_utils import WorktreeRelationshipCache

        cache = WorktreeRelationshipCache(ttl_seconds=300)

        result = cache.get("/repo", "nonexistent", "main")

        assert result is None

    def test_cache_stale_entry(self):
        """Test that stale entries are not returned."""
        from i3_project_manager.services.git_utils import WorktreeRelationshipCache
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        cache = WorktreeRelationshipCache(ttl_seconds=300)

        # Create relationship with old timestamp
        rel = WorktreeRelationship(
            source_branch="feature",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=0,
            is_diverged=False,
            computed_at=int(time.time()) - 600,  # 10 minutes ago
        )

        # Manually insert into cache (bypassing set which updates timestamp)
        key = cache._make_key("/repo", "feature", "main")
        cache._cache[key] = rel

        result = cache.get("/repo", "feature", "main")

        assert result is None  # Should be None because it's stale

    def test_cache_invalidate_repo(self):
        """Test invalidating all entries for a repository."""
        from i3_project_manager.services.git_utils import WorktreeRelationshipCache
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        cache = WorktreeRelationshipCache(ttl_seconds=300)

        # Add multiple relationships for same repo
        for branch in ["feature1", "feature2", "feature3"]:
            rel = WorktreeRelationship(
                source_branch=branch,
                target_branch="main",
                merge_base_commit="abc1234",
                ahead_count=1,
                behind_count=0,
                is_diverged=False,
                computed_at=int(time.time()),
            )
            cache.set("/repo", branch, "main", rel)

        # Verify they're cached
        assert cache.get("/repo", "feature1", "main") is not None
        assert cache.get("/repo", "feature2", "main") is not None

        # Invalidate the repo
        cache.invalidate_repo("/repo")

        # Verify all are gone
        assert cache.get("/repo", "feature1", "main") is None
        assert cache.get("/repo", "feature2", "main") is None
        assert cache.get("/repo", "feature3", "main") is None

    def test_cache_clear(self):
        """Test clearing entire cache."""
        from i3_project_manager.services.git_utils import WorktreeRelationshipCache
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        cache = WorktreeRelationshipCache(ttl_seconds=300)

        # Add relationships for different repos
        for repo in ["/repo1", "/repo2"]:
            rel = WorktreeRelationship(
                source_branch="feature",
                target_branch="main",
                merge_base_commit="abc1234",
                ahead_count=1,
                behind_count=0,
                is_diverged=False,
                computed_at=int(time.time()),
            )
            cache.set(repo, "feature", "main", rel)

        # Clear cache
        cache.clear()

        # Verify all are gone
        assert cache.get("/repo1", "feature", "main") is None
        assert cache.get("/repo2", "feature", "main") is None

    def test_cache_key_normalization(self):
        """Test that cache keys are normalized properly."""
        from i3_project_manager.services.git_utils import WorktreeRelationshipCache
        from i3_project_manager.models.worktree_relationship import WorktreeRelationship

        cache = WorktreeRelationshipCache(ttl_seconds=300)

        rel = WorktreeRelationship(
            source_branch="feature",
            target_branch="main",
            merge_base_commit="abc1234",
            ahead_count=5,
            behind_count=0,
            is_diverged=False,
            computed_at=int(time.time()),
        )

        # Set with one path format
        cache.set("/home/user/repo", "feature", "main", rel)

        # Get with same path (should work due to normalization)
        result = cache.get("/home/user/repo", "feature", "main")

        assert result is not None
