# Feature 111: Unit tests for calculate_activity_level()
"""Tests for calculating activity level based on last commit age.

User Story 5: Branch Age and Activity Heatmap
- Calculate opacity (0.5-1.0) based on last commit age
- Fresh commits (today) = 1.0 opacity
- Stale branches (30+ days) = 0.5 opacity
"""

import pytest
import time


class TestCalculateActivityLevel:
    """Tests for calculate_activity_level function."""

    def test_recent_commit_full_opacity(self):
        """Test that very recent commit returns nearly 1.0 opacity."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        # Commit from 1 hour ago
        recent_timestamp = int(time.time()) - 3600

        result = calculate_activity_level(recent_timestamp)

        # Allow small floating-point variance for recent commits
        assert result["opacity"] >= 0.99
        assert result["is_stale"] is False

    def test_day_old_commit(self):
        """Test that 1-day old commit has high opacity."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        # Commit from 1 day ago
        one_day_ago = int(time.time()) - (24 * 3600)

        result = calculate_activity_level(one_day_ago)

        assert result["opacity"] >= 0.95
        assert result["is_stale"] is False

    def test_week_old_commit(self):
        """Test that 7-day old commit has moderate opacity."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        # Commit from 7 days ago
        week_ago = int(time.time()) - (7 * 24 * 3600)

        result = calculate_activity_level(week_ago)

        # Should be between 0.8 and 0.95
        assert 0.75 <= result["opacity"] <= 0.95
        assert result["is_stale"] is False

    def test_stale_threshold_boundary(self):
        """Test that 30-day old commit is at stale boundary."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        # Commit from exactly 30 days ago
        thirty_days_ago = int(time.time()) - (30 * 24 * 3600)

        result = calculate_activity_level(thirty_days_ago)

        assert result["is_stale"] is True
        assert result["opacity"] <= 0.6

    def test_very_stale_commit(self):
        """Test that 60+ day old commit has minimum opacity."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        # Commit from 60 days ago
        sixty_days_ago = int(time.time()) - (60 * 24 * 3600)

        result = calculate_activity_level(sixty_days_ago)

        assert result["opacity"] == 0.5
        assert result["is_stale"] is True

    def test_zero_timestamp(self):
        """Test handling of zero/missing timestamp."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        result = calculate_activity_level(0)

        # Should treat as very stale
        assert result["opacity"] == 0.5
        assert result["is_stale"] is True

    def test_future_timestamp(self):
        """Test handling of future timestamp (edge case)."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        # Commit "from the future"
        future_timestamp = int(time.time()) + 3600

        result = calculate_activity_level(future_timestamp)

        # Should treat as fresh
        assert result["opacity"] == 1.0
        assert result["is_stale"] is False

    def test_returns_days_since_commit(self):
        """Test that result includes days since last commit."""
        from i3_project_manager.services.worktree_map_service import (
            calculate_activity_level,
        )

        # Commit from 5 days ago
        five_days_ago = int(time.time()) - (5 * 24 * 3600)

        result = calculate_activity_level(five_days_ago)

        assert "days_since_commit" in result
        assert 4 <= result["days_since_commit"] <= 6  # Allow for timing variance
