# Feature 111: Unit tests for get_branch_relationship function
"""Tests for branch relationship detection function."""

import pytest
from unittest.mock import patch, MagicMock


class TestGetBranchRelationship:
    """Tests for get_branch_relationship function."""

    def test_get_branch_relationship_ahead_only(self):
        """Test relationship when source is ahead of target."""
        from i3_project_manager.services.git_utils import get_branch_relationship

        with patch("subprocess.run") as mock_run:
            # First call: rev-list --left-right --count
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="0\t5\n",  # 0 behind, 5 ahead
            )

            with patch(
                "i3_project_manager.services.git_utils.get_merge_base"
            ) as mock_mb:
                mock_mb.return_value = "abc1234"

                result = get_branch_relationship("/repo", "feature", "main")

                assert result is not None
                assert result["ahead"] == 5
                assert result["behind"] == 0
                assert result["merge_base"] == "abc1234"
                assert result["diverged"] is False

    def test_get_branch_relationship_behind_only(self):
        """Test relationship when source is behind target."""
        from i3_project_manager.services.git_utils import get_branch_relationship

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="3\t0\n",  # 3 behind, 0 ahead
            )

            with patch(
                "i3_project_manager.services.git_utils.get_merge_base"
            ) as mock_mb:
                mock_mb.return_value = "abc1234"

                result = get_branch_relationship("/repo", "feature", "main")

                assert result is not None
                assert result["ahead"] == 0
                assert result["behind"] == 3
                assert result["diverged"] is False

    def test_get_branch_relationship_diverged(self):
        """Test relationship when branches have diverged."""
        from i3_project_manager.services.git_utils import get_branch_relationship

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="3\t5\n",  # 3 behind, 5 ahead
            )

            with patch(
                "i3_project_manager.services.git_utils.get_merge_base"
            ) as mock_mb:
                mock_mb.return_value = "abc1234"

                result = get_branch_relationship("/repo", "feature", "main")

                assert result is not None
                assert result["ahead"] == 5
                assert result["behind"] == 3
                assert result["diverged"] is True

    def test_get_branch_relationship_in_sync(self):
        """Test relationship when branches are in sync."""
        from i3_project_manager.services.git_utils import get_branch_relationship

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="0\t0\n",  # 0 behind, 0 ahead
            )

            with patch(
                "i3_project_manager.services.git_utils.get_merge_base"
            ) as mock_mb:
                mock_mb.return_value = "abc1234"

                result = get_branch_relationship("/repo", "feature", "main")

                assert result is not None
                assert result["ahead"] == 0
                assert result["behind"] == 0
                assert result["diverged"] is False

    def test_get_branch_relationship_git_error(self):
        """Test relationship when git command fails."""
        from i3_project_manager.services.git_utils import get_branch_relationship

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=1,
                stdout="",
            )

            result = get_branch_relationship("/repo", "nonexistent", "main")

            assert result is None

    def test_get_branch_relationship_invalid_output(self):
        """Test relationship with invalid git output."""
        from i3_project_manager.services.git_utils import get_branch_relationship

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="invalid\n",  # Not two numbers
            )

            result = get_branch_relationship("/repo", "feature", "main")

            assert result is None
