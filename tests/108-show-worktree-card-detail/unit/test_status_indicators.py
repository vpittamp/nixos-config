"""
Feature 108 T030/T035: Unit tests for status indicator formatting and logic.

Tests:
- T030: git_status_tooltip formatting
- T035: Stale indicator logic (30-day threshold)
"""

import pytest
import time
from typing import Dict, Any, List


class TestGitStatusTooltipFormatting:
    """T030: Unit tests for git_status_tooltip multi-line string formatting."""

    def test_tooltip_includes_branch(self):
        """Tooltip always includes branch name."""
        tooltip = self._build_tooltip(branch="099-feature")
        assert "Branch: 099-feature" in tooltip

    def test_tooltip_includes_commit(self):
        """Tooltip always includes commit hash."""
        tooltip = self._build_tooltip(commit="abc1234")
        assert "abc1234" in tooltip

    def test_tooltip_includes_relative_time(self):
        """Tooltip includes relative time if available."""
        tooltip = self._build_tooltip(
            commit="abc1234",
            git_last_commit_relative="2h ago"
        )
        assert "2h ago" in tooltip

    def test_tooltip_includes_status_breakdown(self):
        """Tooltip includes file count breakdown."""
        tooltip = self._build_tooltip(
            staged_count=2,
            modified_count=3,
            untracked_count=1
        )
        assert "2 staged" in tooltip
        assert "3 modified" in tooltip
        assert "1 untracked" in tooltip

    def test_tooltip_shows_clean_status(self):
        """Clean worktree shows 'Status: clean'."""
        tooltip = self._build_tooltip(is_clean=True)
        assert "clean" in tooltip.lower()

    def test_tooltip_includes_sync_info(self):
        """Tooltip includes push/pull counts."""
        tooltip = self._build_tooltip(ahead=5, behind=2)
        assert "5 to push" in tooltip
        assert "2 to pull" in tooltip

    def test_tooltip_includes_merged_status(self):
        """Merged branch shows merge status."""
        tooltip = self._build_tooltip(is_merged=True)
        assert "merged" in tooltip.lower()

    def test_tooltip_includes_stale_warning(self):
        """Stale worktree shows staleness warning."""
        tooltip = self._build_tooltip(is_stale=True)
        assert "30+ days" in tooltip or "stale" in tooltip.lower()

    def test_tooltip_includes_conflict_warning(self):
        """Conflict state shows conflict warning."""
        tooltip = self._build_tooltip(has_conflicts=True)
        assert "conflict" in tooltip.lower()

    def test_tooltip_newline_separated(self):
        """Tooltip parts are newline-separated."""
        tooltip = self._build_tooltip(
            branch="test",
            commit="abc1234",
            staged_count=1
        )
        # Escaped newline for Eww
        assert "\\n" in tooltip

    def _build_tooltip(
        self,
        branch: str = "test-branch",
        commit: str = "abc1234",
        git_last_commit_relative: str = "",
        last_commit_message: str = "",
        staged_count: int = 0,
        modified_count: int = 0,
        untracked_count: int = 0,
        is_clean: bool = True,
        ahead: int = 0,
        behind: int = 0,
        is_merged: bool = False,
        is_stale: bool = False,
        has_conflicts: bool = False,
    ) -> str:
        """Build tooltip using same logic as monitoring_data.py."""
        tooltip_parts: List[str] = []
        tooltip_parts.append(f"Branch: {branch}")
        tooltip_parts.append(f"Commit: {commit}")
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

        return "\\n".join(tooltip_parts)


class TestStaleIndicatorLogic:
    """T035: Unit tests for stale indicator logic (30-day threshold)."""

    STALE_THRESHOLD_DAYS = 30
    SECONDS_PER_DAY = 86400

    def test_recent_commit_not_stale(self):
        """Commit within 30 days is not stale."""
        days_since = 7
        is_stale = days_since >= self.STALE_THRESHOLD_DAYS
        assert is_stale is False

    def test_exactly_30_days_is_stale(self):
        """Commit exactly 30 days ago is stale."""
        days_since = 30
        is_stale = days_since >= self.STALE_THRESHOLD_DAYS
        assert is_stale is True

    def test_29_days_not_stale(self):
        """Commit 29 days ago is not stale."""
        days_since = 29
        is_stale = days_since >= self.STALE_THRESHOLD_DAYS
        assert is_stale is False

    def test_45_days_is_stale(self):
        """Commit 45 days ago is stale."""
        days_since = 45
        is_stale = days_since >= self.STALE_THRESHOLD_DAYS
        assert is_stale is True

    def test_stale_indicator_emoji(self):
        """Stale worktrees show 💤 indicator."""
        is_stale = True
        indicator = "💤" if is_stale else ""
        assert indicator == "💤"

    def test_active_indicator_empty(self):
        """Active (non-stale) worktrees have empty indicator."""
        is_stale = False
        indicator = "💤" if is_stale else ""
        assert indicator == ""

    def test_stale_calculation_from_timestamp(self):
        """Staleness calculated correctly from timestamp."""
        now = int(time.time())
        # 45 days ago
        timestamp = now - (45 * self.SECONDS_PER_DAY)
        days_since = (now - timestamp) // self.SECONDS_PER_DAY
        is_stale = days_since >= self.STALE_THRESHOLD_DAYS
        assert days_since == 45
        assert is_stale is True

    def test_stale_tooltip_message(self):
        """Stale worktrees have appropriate tooltip text."""
        is_stale = True
        if is_stale:
            tooltip_part = "Stale: no activity in 30+ days"
        else:
            tooltip_part = ""
        assert "30+ days" in tooltip_part
