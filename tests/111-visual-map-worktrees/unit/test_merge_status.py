# Feature 111: Unit tests for get_merge_ready_status()
"""Tests for checking if a branch is ready to merge.

User Story 4: Merge Flow Visualization
- Check if branch is clean (no uncommitted changes)
- Check if branch is up-to-date with main
- Determine merge readiness status
"""

import pytest


class TestGetMergeReadyStatus:
    """Tests for get_merge_ready_status function."""

    def test_ready_clean_and_synced(self):
        """Test branch is ready when clean and synced with main."""
        from i3_project_manager.services.git_utils import get_merge_ready_status

        result = get_merge_ready_status(
            is_clean=True,
            ahead_of_main=5,
            behind_main=0,
        )

        assert result["is_ready"] is True
        assert result["status"] == "ready"
        assert result["reason"] is None

    def test_not_ready_dirty(self):
        """Test branch is not ready when it has uncommitted changes."""
        from i3_project_manager.services.git_utils import get_merge_ready_status

        result = get_merge_ready_status(
            is_clean=False,
            ahead_of_main=5,
            behind_main=0,
        )

        assert result["is_ready"] is False
        assert result["status"] == "dirty"
        assert "uncommitted" in result["reason"].lower()

    def test_not_ready_behind_main(self):
        """Test branch is not ready when behind main."""
        from i3_project_manager.services.git_utils import get_merge_ready_status

        result = get_merge_ready_status(
            is_clean=True,
            ahead_of_main=5,
            behind_main=10,
        )

        assert result["is_ready"] is False
        assert result["status"] == "behind"
        assert "10" in result["reason"]  # Shows how far behind

    def test_not_ready_dirty_and_behind(self):
        """Test branch shows dirty status first when both dirty and behind."""
        from i3_project_manager.services.git_utils import get_merge_ready_status

        result = get_merge_ready_status(
            is_clean=False,
            ahead_of_main=5,
            behind_main=10,
        )

        # Dirty takes priority over behind
        assert result["is_ready"] is False
        assert result["status"] == "dirty"

    def test_no_changes(self):
        """Test branch with no commits ahead of main."""
        from i3_project_manager.services.git_utils import get_merge_ready_status

        result = get_merge_ready_status(
            is_clean=True,
            ahead_of_main=0,
            behind_main=0,
        )

        assert result["is_ready"] is False
        assert result["status"] == "no_changes"
        assert "nothing to merge" in result["reason"].lower()

    def test_merge_readiness_info(self):
        """Test that merge readiness includes commit count info."""
        from i3_project_manager.services.git_utils import get_merge_ready_status

        result = get_merge_ready_status(
            is_clean=True,
            ahead_of_main=7,
            behind_main=0,
        )

        assert result["is_ready"] is True
        assert result["commits_to_merge"] == 7
