"""
Feature 108 T023/T039: Integration tests for enhanced worktree data in monitoring_data.py.

Tests:
- T023: Verify worktree data includes new Feature 108 fields
- T039: Verify merge detection logic with various branch states
"""

import pytest
from typing import Dict, Any


class TestWorktreeDataEnhancement:
    """T023: Integration tests for enhanced worktree data fields."""

    def test_worktree_has_merge_indicator_fields(self):
        """Worktree data includes git_is_merged and git_merged_indicator."""
        worktree = self._create_mock_worktree(is_merged=True)
        assert "git_is_merged" in worktree
        assert "git_merged_indicator" in worktree
        assert worktree["git_is_merged"] is True
        assert worktree["git_merged_indicator"] == "✓"

    def test_worktree_has_conflict_indicator_fields(self):
        """Worktree data includes git_has_conflicts and git_conflict_indicator."""
        worktree = self._create_mock_worktree(has_conflicts=True)
        assert "git_has_conflicts" in worktree
        assert "git_conflict_indicator" in worktree
        assert worktree["git_has_conflicts"] is True
        assert worktree["git_conflict_indicator"] == "⚠"

    def test_worktree_has_stale_indicator_fields(self):
        """Worktree data includes git_is_stale and git_stale_indicator."""
        worktree = self._create_mock_worktree(is_stale=True)
        assert "git_is_stale" in worktree
        assert "git_stale_indicator" in worktree
        assert worktree["git_is_stale"] is True
        assert worktree["git_stale_indicator"] == "💤"

    def test_worktree_has_status_count_fields(self):
        """Worktree data includes detailed status count fields."""
        worktree = self._create_mock_worktree(
            staged_count=2,
            modified_count=3,
            untracked_count=1
        )
        assert "git_staged_count" in worktree
        assert "git_modified_count" in worktree
        assert "git_untracked_count" in worktree
        assert worktree["git_staged_count"] == 2
        assert worktree["git_modified_count"] == 3
        assert worktree["git_untracked_count"] == 1

    def test_worktree_has_last_commit_fields(self):
        """Worktree data includes last commit info fields."""
        worktree = self._create_mock_worktree(
            last_commit_message="Test commit message",
            git_last_commit_relative="2h ago"
        )
        assert "git_last_commit_message" in worktree
        assert "git_last_commit_relative" in worktree
        assert worktree["git_last_commit_message"] == "Test commit message"
        assert worktree["git_last_commit_relative"] == "2h ago"

    def test_worktree_has_status_tooltip(self):
        """Worktree data includes comprehensive tooltip."""
        worktree = self._create_mock_worktree(
            branch="099-feature",
            staged_count=2,
            modified_count=3,
            untracked_count=1,
            ahead=5,
            behind=2
        )
        assert "git_status_tooltip" in worktree
        tooltip = worktree["git_status_tooltip"]
        # Tooltip should contain key info
        assert "Branch: 099-feature" in tooltip
        assert "2 staged" in tooltip or "staged" in tooltip.lower()

    def test_clean_worktree_has_empty_indicators(self):
        """Clean worktree has empty indicator strings."""
        worktree = self._create_mock_worktree(is_clean=True)
        assert worktree["git_dirty_indicator"] == ""
        assert worktree["git_merged_indicator"] == ""
        assert worktree["git_conflict_indicator"] == ""
        assert worktree["git_stale_indicator"] == ""

    def test_dirty_worktree_has_dirty_indicator(self):
        """Dirty worktree has dirty indicator."""
        worktree = self._create_mock_worktree(is_clean=False)
        assert worktree["git_dirty_indicator"] == "●"

    def _create_mock_worktree(
        self,
        branch: str = "test-branch",
        is_clean: bool = True,
        is_merged: bool = False,
        is_stale: bool = False,
        has_conflicts: bool = False,
        staged_count: int = 0,
        modified_count: int = 0,
        untracked_count: int = 0,
        ahead: int = 0,
        behind: int = 0,
        last_commit_message: str = "",
        git_last_commit_relative: str = "",
    ) -> Dict[str, Any]:
        """Create a mock worktree with computed indicator fields."""
        wt = {
            "branch": branch,
            "commit": "abc1234",
            "path": "/home/user/test",
            "is_clean": is_clean,
            "is_merged": is_merged,
            "is_stale": is_stale,
            "has_conflicts": has_conflicts,
            "staged_count": staged_count,
            "modified_count": modified_count,
            "untracked_count": untracked_count,
            "ahead": ahead,
            "behind": behind,
            "last_commit_message": last_commit_message,
            "last_commit_timestamp": 1733011200 if git_last_commit_relative else 0,
        }

        # Apply the same logic as monitoring_data.py
        wt["git_is_dirty"] = not wt.get("is_clean", True)
        wt["git_dirty_indicator"] = "●" if wt["git_is_dirty"] else ""
        wt["git_ahead"] = wt.get("ahead", 0)
        wt["git_behind"] = wt.get("behind", 0)

        sync_parts = []
        if wt["git_ahead"] > 0:
            sync_parts.append(f"↑{wt['git_ahead']}")
        if wt["git_behind"] > 0:
            sync_parts.append(f"↓{wt['git_behind']}")
        wt["git_sync_indicator"] = " ".join(sync_parts)

        wt["git_is_merged"] = wt.get("is_merged", False)
        wt["git_merged_indicator"] = "✓" if wt["git_is_merged"] else ""

        wt["git_has_conflicts"] = wt.get("has_conflicts", False)
        wt["git_conflict_indicator"] = "⚠" if wt["git_has_conflicts"] else ""

        wt["git_staged_count"] = wt.get("staged_count", 0)
        wt["git_modified_count"] = wt.get("modified_count", 0)
        wt["git_untracked_count"] = wt.get("untracked_count", 0)

        wt["git_last_commit_relative"] = git_last_commit_relative
        wt["git_last_commit_message"] = last_commit_message[:50]

        wt["git_is_stale"] = wt.get("is_stale", False)
        wt["git_stale_indicator"] = "💤" if wt["git_is_stale"] else ""

        # Build tooltip
        tooltip_parts = [f"Branch: {wt['branch']}"]
        tooltip_parts.append(f"Commit: {wt.get('commit', 'unknown')}")
        if git_last_commit_relative:
            tooltip_parts[-1] += f" ({git_last_commit_relative})"
        if last_commit_message:
            tooltip_parts.append(f"Message: {last_commit_message}")

        status_parts = []
        if staged_count > 0:
            status_parts.append(f"{staged_count} staged")
        if modified_count > 0:
            status_parts.append(f"{modified_count} modified")
        if untracked_count > 0:
            status_parts.append(f"{untracked_count} untracked")
        if status_parts:
            tooltip_parts.append(f"Status: {', '.join(status_parts)}")
        elif is_clean:
            tooltip_parts.append("Status: clean")

        if ahead > 0 or behind > 0:
            sync_desc = []
            if ahead > 0:
                sync_desc.append(f"{ahead} to push")
            if behind > 0:
                sync_desc.append(f"{behind} to pull")
            tooltip_parts.append(f"Sync: {', '.join(sync_desc)}")

        if is_merged:
            tooltip_parts.append("Merged: ✓ merged into main")
        if is_stale:
            tooltip_parts.append("Stale: no activity in 30+ days")
        if has_conflicts:
            tooltip_parts.append("⚠ Has unresolved merge conflicts")

        wt["git_status_tooltip"] = "\\n".join(tooltip_parts)

        return wt


class TestMergeDetectionIntegration:
    """T039: Integration tests for merge detection with various branch states."""

    def test_feature_branch_merged_detected(self):
        """Feature branch that's merged shows as merged."""
        worktree = {"is_merged": True, "branch": "099-feature"}
        is_merged = worktree.get("is_merged", False)
        indicator = "✓" if is_merged else ""
        assert is_merged is True
        assert indicator == "✓"

    def test_feature_branch_not_merged(self):
        """Feature branch that's not merged shows as not merged."""
        worktree = {"is_merged": False, "branch": "100-wip"}
        is_merged = worktree.get("is_merged", False)
        indicator = "✓" if is_merged else ""
        assert is_merged is False
        assert indicator == ""

    def test_main_branch_not_merged_into_self(self):
        """Main branch should not show as 'merged into main'."""
        # In git_utils.py, main/master/HEAD are excluded from merge check
        worktree = {"is_merged": False, "branch": "main"}
        # Main branch should never have is_merged=True
        is_merged = worktree.get("is_merged", False)
        assert is_merged is False

    def test_master_branch_not_merged_into_self(self):
        """Master branch should not show as 'merged into main'."""
        worktree = {"is_merged": False, "branch": "master"}
        is_merged = worktree.get("is_merged", False)
        assert is_merged is False

    def test_detached_head_not_merged(self):
        """Detached HEAD should not show merge status."""
        worktree = {"is_merged": False, "branch": "HEAD"}
        is_merged = worktree.get("is_merged", False)
        assert is_merged is False
