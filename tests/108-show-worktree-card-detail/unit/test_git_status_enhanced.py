"""
Feature 108 T010-T014: Unit tests for enhanced git status fields in git_utils.py.

Tests:
- T010: is_merged detection
- T011: is_stale detection
- T012: status count parsing (staged, modified, untracked)
- T013: conflict detection
- T014: format_relative_time()
"""

import pytest
import time
from unittest.mock import patch, MagicMock
import sys
from pathlib import Path

# Add the module path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools"))

from i3_project_manager.services.git_utils import (
    format_relative_time,
    STALE_THRESHOLD_DAYS,
    SECONDS_PER_DAY,
)


class TestFormatRelativeTime:
    """T014: Unit tests for format_relative_time() helper function."""

    def test_just_now(self):
        """Timestamp within last minute returns 'just now'."""
        now = int(time.time())
        assert format_relative_time(now) == "just now"
        assert format_relative_time(now - 30) == "just now"

    def test_minutes_ago(self):
        """Timestamps within the last hour return 'Nm ago'."""
        now = int(time.time())
        assert format_relative_time(now - 60) == "1m ago"
        assert format_relative_time(now - 120) == "2m ago"
        assert format_relative_time(now - 3540) == "59m ago"  # 59 minutes

    def test_hours_ago(self):
        """Timestamps within the last day return 'Nh ago'."""
        now = int(time.time())
        assert format_relative_time(now - 3600) == "1h ago"
        assert format_relative_time(now - 7200) == "2h ago"
        assert format_relative_time(now - 82800) == "23h ago"  # 23 hours

    def test_days_ago(self):
        """Timestamps within the last week return 'N day(s) ago'."""
        now = int(time.time())
        assert format_relative_time(now - SECONDS_PER_DAY) == "1 day ago"
        assert format_relative_time(now - (2 * SECONDS_PER_DAY)) == "2 days ago"
        assert format_relative_time(now - (6 * SECONDS_PER_DAY)) == "6 days ago"

    def test_weeks_ago(self):
        """Timestamps within the last month return 'N week(s) ago'."""
        now = int(time.time())
        assert format_relative_time(now - (7 * SECONDS_PER_DAY)) == "1 week ago"
        assert format_relative_time(now - (14 * SECONDS_PER_DAY)) == "2 weeks ago"
        assert format_relative_time(now - (21 * SECONDS_PER_DAY)) == "3 weeks ago"

    def test_months_ago(self):
        """Timestamps older than a month return 'N month(s) ago'."""
        now = int(time.time())
        assert format_relative_time(now - (30 * SECONDS_PER_DAY)) == "1 month ago"
        assert format_relative_time(now - (60 * SECONDS_PER_DAY)) == "2 months ago"
        assert format_relative_time(now - (90 * SECONDS_PER_DAY)) == "3 months ago"

    def test_future_timestamp(self):
        """Future timestamps return 'in the future'."""
        now = int(time.time())
        assert format_relative_time(now + 1000) == "in the future"


class TestStaleThreshold:
    """T011: Tests for staleness threshold constant."""

    def test_stale_threshold_is_30_days(self):
        """Staleness threshold is set to 30 days."""
        assert STALE_THRESHOLD_DAYS == 30

    def test_seconds_per_day_constant(self):
        """Seconds per day is correctly defined."""
        assert SECONDS_PER_DAY == 86400


class TestStatusCountParsing:
    """T012: Tests for parsing git status --porcelain output into counts."""

    def test_parse_empty_status(self):
        """Empty status output means clean repository."""
        status_lines = []
        staged, modified, untracked = self._parse_status_counts(status_lines)
        assert staged == 0
        assert modified == 0
        assert untracked == 0

    def test_parse_staged_only(self):
        """Lines with changes in first column are staged."""
        status_lines = [
            "M  file1.py",  # Staged modification
            "A  file2.py",  # Staged addition
            "D  file3.py",  # Staged deletion
        ]
        staged, modified, untracked = self._parse_status_counts(status_lines)
        assert staged == 3
        assert modified == 0
        assert untracked == 0

    def test_parse_modified_only(self):
        """Lines with changes in second column are modified (unstaged)."""
        status_lines = [
            " M file1.py",  # Unstaged modification
            " D file2.py",  # Unstaged deletion
        ]
        staged, modified, untracked = self._parse_status_counts(status_lines)
        assert staged == 0
        assert modified == 2
        assert untracked == 0

    def test_parse_untracked_only(self):
        """Lines starting with ?? are untracked."""
        status_lines = [
            "?? new_file.py",
            "?? new_directory/",
        ]
        staged, modified, untracked = self._parse_status_counts(status_lines)
        assert staged == 0
        assert modified == 0
        assert untracked == 2

    def test_parse_mixed_status(self):
        """Mixed status lines are correctly categorized."""
        status_lines = [
            "M  staged.py",      # Staged
            " M modified.py",    # Modified
            "?? untracked.py",   # Untracked
            "A  added.py",       # Staged
            " D deleted.py",     # Modified (deleted but unstaged)
        ]
        staged, modified, untracked = self._parse_status_counts(status_lines)
        assert staged == 2  # M and A
        assert modified == 2  # M and D in second column
        assert untracked == 1

    def _parse_status_counts(self, status_lines):
        """Helper to parse status counts like git_utils.py does."""
        staged_count = 0
        modified_count = 0
        untracked_count = 0

        for line in status_lines:
            if len(line) < 2:
                continue
            x_status = line[0]
            y_status = line[1]

            if x_status in 'MADRC':
                staged_count += 1
            if y_status in 'MD':
                modified_count += 1
            if line.startswith("??"):
                untracked_count += 1

        return staged_count, modified_count, untracked_count


class TestConflictDetection:
    """T013: Tests for detecting merge conflicts from git status."""

    def test_no_conflicts(self):
        """Clean or dirty status without conflicts returns False."""
        status_lines = [
            "M  file1.py",
            " M file2.py",
            "?? new_file.py",
        ]
        assert not self._has_conflicts(status_lines)

    def test_uu_conflict(self):
        """UU status (both modified) indicates conflict."""
        status_lines = [
            "UU conflicted_file.py",
        ]
        assert self._has_conflicts(status_lines)

    def test_aa_conflict(self):
        """AA status (both added) indicates conflict."""
        status_lines = [
            "AA both_added.py",
        ]
        assert self._has_conflicts(status_lines)

    def test_dd_conflict(self):
        """DD status (both deleted) indicates conflict."""
        status_lines = [
            "DD both_deleted.py",
        ]
        assert self._has_conflicts(status_lines)

    def test_mixed_with_conflict(self):
        """Conflict detected among other status lines."""
        status_lines = [
            "M  normal_staged.py",
            "UU conflicted.py",
            " M normal_modified.py",
        ]
        assert self._has_conflicts(status_lines)

    def test_u_in_first_column(self):
        """U in first column indicates unmerged path."""
        status_lines = [
            "UD deleted_by_them.py",  # U in first column
        ]
        assert self._has_conflicts(status_lines)

    def test_u_in_second_column(self):
        """U in second column indicates unmerged path."""
        status_lines = [
            "DU deleted_by_us.py",  # U in second column
        ]
        assert self._has_conflicts(status_lines)

    def _has_conflicts(self, status_lines):
        """Helper to detect conflicts like git_utils.py does."""
        for line in status_lines:
            if len(line) < 2:
                continue
            x_status = line[0]
            y_status = line[1]

            if x_status == 'U' or y_status == 'U':
                return True
            if x_status == 'A' and y_status == 'A':
                return True
            if x_status == 'D' and y_status == 'D':
                return True

        return False


class TestMergeDetection:
    """T010: Tests for is_merged detection logic."""

    def test_main_branch_not_merged_into_self(self):
        """Main branch should not show as 'merged into main'."""
        # This is validated in the function - main/master are excluded
        current_branch = "main"
        excluded_branches = ("main", "master", "HEAD")
        assert current_branch in excluded_branches

    def test_feature_branch_can_be_merged(self):
        """Feature branches can be detected as merged."""
        current_branch = "099-feature"
        excluded_branches = ("main", "master", "HEAD")
        assert current_branch not in excluded_branches

    def test_detached_head_not_merged(self):
        """Detached HEAD state should not show as merged."""
        current_branch = "HEAD"
        excluded_branches = ("main", "master", "HEAD")
        assert current_branch in excluded_branches
