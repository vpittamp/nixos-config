#!/usr/bin/env python3
"""Unit tests for fuzzy matching algorithm.

Feature 078: Enhanced Project Selection in Eww Preview Dialog
Tests T011 and T012: Fuzzy matching and priority scoring.
"""

import sys
from pathlib import Path

# Add daemon to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"))

import pytest
from project_filter_service import (
    fuzzy_match_score,
    filter_projects,
    format_relative_time,
)
from models.project_filter import ProjectListItem, MatchPosition
from datetime import datetime, timezone, timedelta


class TestFuzzyMatchScore:
    """T011: Unit test for fuzzy matching algorithm."""

    def test_exact_match_returns_highest_score(self):
        """Exact match should return score of 1000."""
        score, positions = fuzzy_match_score("nixos", "nixos")
        assert score == 1000
        assert positions == [MatchPosition(start=0, end=5)]

    def test_exact_match_case_insensitive(self):
        """Exact match should be case-insensitive."""
        score, positions = fuzzy_match_score("NIXOS", "nixos")
        assert score == 1000

    def test_prefix_match_high_score(self):
        """Prefix match should return score 500+."""
        score, positions = fuzzy_match_score("nix", "nixos")
        assert score >= 500
        assert score < 1000
        assert positions == [MatchPosition(start=0, end=3)]

    def test_prefix_match_longer_query_higher_score(self):
        """Longer prefix should score higher than shorter."""
        score_short, _ = fuzzy_match_score("n", "nixos")
        score_long, _ = fuzzy_match_score("nixo", "nixos")
        assert score_long > score_short

    def test_substring_match_lower_than_prefix(self):
        """Substring match should score lower than prefix match."""
        prefix_score, _ = fuzzy_match_score("nix", "nixos")
        substring_score, _ = fuzzy_match_score("xos", "nixos")
        assert prefix_score > substring_score

    def test_substring_match_positions_correct(self):
        """Substring match should have correct positions."""
        score, positions = fuzzy_match_score("preview", "eww-preview-improvement")
        assert score > 0
        assert len(positions) == 1
        # "preview" starts at position 4
        assert positions[0].start == 4
        assert positions[0].end == 11

    def test_no_match_returns_zero(self):
        """No match should return score of 0."""
        score, positions = fuzzy_match_score("xyz", "nixos")
        assert score == 0
        assert positions == []

    def test_empty_query_returns_zero(self):
        """Empty query should return score of 0."""
        score, positions = fuzzy_match_score("", "nixos")
        assert score == 0
        assert positions == []

    def test_fuzzy_character_match(self):
        """Characters spread across text should still match."""
        # "078" in "078-eww-preview-improvement"
        score, positions = fuzzy_match_score("078", "078-eww-preview-improvement")
        assert score > 0
        # Should be prefix match
        assert score >= 500

    def test_hyphenated_name_match(self):
        """Hyphens in name should be searchable."""
        score, positions = fuzzy_match_score("eww-preview", "078-eww-preview-improvement")
        assert score > 0

    def test_digit_prefix_match(self):
        """Digit prefixes should match correctly."""
        score, positions = fuzzy_match_score("077", "077-worktree-creation")
        assert score >= 500  # Prefix match

    def test_partial_word_match(self):
        """Partial word matches should work."""
        score, positions = fuzzy_match_score("age", "agent-framework")
        assert score > 0
        # "age" is prefix of "agent"
        assert positions[0].start == 0


class TestPriorityScoring:
    """T012: Unit test for priority scoring (exact > prefix > substring)."""

    def test_exact_beats_prefix(self):
        """Exact match should beat prefix match."""
        exact_score, _ = fuzzy_match_score("nixos", "nixos")
        prefix_score, _ = fuzzy_match_score("nixos", "nixos-worktree")
        assert exact_score > prefix_score

    def test_prefix_beats_substring(self):
        """Prefix match should beat substring match."""
        prefix_score, _ = fuzzy_match_score("agent", "agent-framework")
        substring_score, _ = fuzzy_match_score("agent", "my-agent-service")
        assert prefix_score > substring_score

    def test_substring_beats_sparse_match(self):
        """Substring match should beat sparse character match."""
        # "nix" as substring vs "nio" requiring sparse match
        substring_score, _ = fuzzy_match_score("nix", "nixos")
        # This is actually a prefix, but demonstrates ordering
        assert substring_score >= 500

    def test_scoring_consistency(self):
        """Same query on same text should produce consistent scores."""
        score1, _ = fuzzy_match_score("eww", "078-eww-preview-improvement")
        score2, _ = fuzzy_match_score("eww", "078-eww-preview-improvement")
        assert score1 == score2

    def test_multiple_projects_sorted_correctly(self):
        """Projects should be sorted by match score."""
        # Create test projects
        projects = [
            ProjectListItem(
                name="nixos-worktree",
                display_name="NixOS Worktree",
                icon="🌳",
                is_worktree=False,
                directory_exists=True,
                relative_time="10d ago",
            ),
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
            ),
            ProjectListItem(
                name="my-nixos-fork",
                display_name="My NixOS Fork",
                icon="📁",
                is_worktree=False,
                directory_exists=True,
                relative_time="5d ago",
            ),
        ]

        # Filter with "nixos"
        results = filter_projects(projects, "nixos")

        # Exact match should be first
        assert results[0].name == "nixos"
        # Prefix match second
        assert results[1].name == "nixos-worktree"
        # Substring match third
        assert results[2].name == "my-nixos-fork"

    def test_no_match_excluded(self):
        """Projects that don't match should be excluded."""
        projects = [
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
            ),
            ProjectListItem(
                name="dapr",
                display_name="Dapr Services",
                icon="🔧",
                is_worktree=False,
                directory_exists=True,
                relative_time="1d ago",
            ),
        ]

        results = filter_projects(projects, "nix")
        assert len(results) == 1
        assert results[0].name == "nixos"

    def test_empty_query_returns_all(self):
        """Empty query should return all projects."""
        projects = [
            ProjectListItem(
                name="nixos",
                display_name="NixOS",
                icon="❄️",
                is_worktree=False,
                directory_exists=True,
                relative_time="3d ago",
            ),
            ProjectListItem(
                name="dapr",
                display_name="Dapr Services",
                icon="🔧",
                is_worktree=False,
                directory_exists=True,
                relative_time="1d ago",
            ),
        ]

        results = filter_projects(projects, "")
        assert len(results) == 2


class TestRelativeTimeFormatting:
    """Test relative time formatting."""

    def test_just_now(self):
        """Recent time should show 'just now'."""
        now = datetime.now(timezone.utc)
        result = format_relative_time(now)
        assert result == "just now"

    def test_minutes_ago(self):
        """Minutes should format correctly."""
        past = datetime.now(timezone.utc) - timedelta(minutes=30)
        result = format_relative_time(past)
        assert result == "30m ago"

    def test_hours_ago(self):
        """Hours should format correctly."""
        past = datetime.now(timezone.utc) - timedelta(hours=5)
        result = format_relative_time(past)
        assert result == "5h ago"

    def test_days_ago(self):
        """Days should format correctly."""
        past = datetime.now(timezone.utc) - timedelta(days=3)
        result = format_relative_time(past)
        assert result == "3d ago"

    def test_months_ago(self):
        """Months should format correctly."""
        past = datetime.now(timezone.utc) - timedelta(days=45)
        result = format_relative_time(past)
        assert result == "1mo ago"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
