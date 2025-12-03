# Feature 111: Unit tests for get_merge_base function
"""Tests for git merge-base utility function."""

import pytest
from unittest.mock import patch, MagicMock


class TestGetMergeBase:
    """Tests for get_merge_base function."""

    def test_get_merge_base_success(self):
        """Test successful merge-base retrieval."""
        from i3_project_manager.services.git_utils import get_merge_base

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="abc1234def5678901234567890abcdef12345678\n",
            )

            result = get_merge_base("/path/to/repo", "feature-branch", "main")

            assert result == "abc1234"  # Should be truncated to 7 chars
            mock_run.assert_called_once()
            call_args = mock_run.call_args
            assert call_args[0][0] == ["git", "merge-base", "feature-branch", "main"]
            assert call_args[1]["cwd"] == "/path/to/repo"

    def test_get_merge_base_failure(self):
        """Test merge-base retrieval with git error."""
        from i3_project_manager.services.git_utils import get_merge_base

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=1,
                stdout="",
            )

            result = get_merge_base("/path/to/repo", "nonexistent", "main")

            assert result is None

    def test_get_merge_base_timeout(self):
        """Test merge-base retrieval with timeout."""
        from i3_project_manager.services.git_utils import get_merge_base
        import subprocess

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.TimeoutExpired(cmd="git", timeout=5)

            result = get_merge_base("/path/to/repo", "feature-branch", "main")

            assert result is None

    def test_get_merge_base_os_error(self):
        """Test merge-base retrieval with OS error."""
        from i3_project_manager.services.git_utils import get_merge_base

        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = OSError("git not found")

            result = get_merge_base("/path/to/repo", "feature-branch", "main")

            assert result is None
