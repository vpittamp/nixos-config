"""Unit tests for event_correlator module.

Feature 029: Linux System Log Integration - User Story 3
Tests: T056-T058

Run with:
    pytest tests/i3-project-daemon/unit/test_event_correlator.py -v
"""

import pytest
from datetime import datetime, timedelta
from pathlib import Path
import sys

# Add the daemon module to the path
daemon_path = Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_path))

from event_correlator import EventCorrelator, CorrelationFactors, WEIGHTS, CONFIDENCE_THRESHOLD
from models import EventEntry


class TestConfidenceScoring:
    """Test T056: Confidence scoring with known factor values."""

    def setup_method(self):
        """Set up test fixtures."""
        self.correlator = EventCorrelator()

    def test_perfect_match_all_factors(self):
        """Test perfect match: all factors = 1.0 should give confidence = 1.0."""
        factors = CorrelationFactors(
            timing_score=1.0,
            hierarchy_score=1.0,
            name_score=1.0,
            workspace_score=1.0
        )
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence == 1.0, "Perfect match should give 100% confidence"

    def test_no_match_all_factors(self):
        """Test no match: all factors = 0.0 should give confidence = 0.0."""
        factors = CorrelationFactors(
            timing_score=0.0,
            hierarchy_score=0.0,
            name_score=0.0,
            workspace_score=0.0
        )
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence == 0.0, "No match should give 0% confidence"

    def test_weighted_formula_timing_only(self):
        """Test weighted formula: only timing factor (40% weight)."""
        factors = CorrelationFactors(
            timing_score=1.0,  # 40% weight
            hierarchy_score=0.0,
            name_score=0.0,
            workspace_score=0.0
        )
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence == 0.40, f"Timing only should give 40% confidence, got {confidence}"

    def test_weighted_formula_hierarchy_only(self):
        """Test weighted formula: only hierarchy factor (30% weight)."""
        factors = CorrelationFactors(
            timing_score=0.0,
            hierarchy_score=1.0,  # 30% weight
            name_score=0.0,
            workspace_score=0.0
        )
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence == 0.30, f"Hierarchy only should give 30% confidence, got {confidence}"

    def test_weighted_formula_name_only(self):
        """Test weighted formula: only name similarity (20% weight)."""
        factors = CorrelationFactors(
            timing_score=0.0,
            hierarchy_score=0.0,
            name_score=1.0,  # 20% weight
            workspace_score=0.0
        )
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence == 0.20, f"Name only should give 20% confidence, got {confidence}"

    def test_weighted_formula_workspace_only(self):
        """Test weighted formula: only workspace match (10% weight)."""
        factors = CorrelationFactors(
            timing_score=0.0,
            hierarchy_score=0.0,
            name_score=0.0,
            workspace_score=1.0  # 10% weight
        )
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence == 0.10, f"Workspace only should give 10% confidence, got {confidence}"

    def test_combined_timing_and_name(self):
        """Test combined factors: timing (0.8) + name (0.9) = 0.50."""
        factors = CorrelationFactors(
            timing_score=0.8,   # 0.8 * 0.40 = 0.32
            hierarchy_score=0.0,
            name_score=0.9,     # 0.9 * 0.20 = 0.18
            workspace_score=0.0
        )
        # Expected: 0.32 + 0.18 = 0.50
        confidence = self.correlator._calculate_confidence(factors)
        assert abs(confidence - 0.50) < 0.01, f"Expected 0.50, got {confidence}"

    def test_above_threshold(self):
        """Test confidence above threshold (60%)."""
        factors = CorrelationFactors(
            timing_score=0.9,   # 0.9 * 0.40 = 0.36
            hierarchy_score=0.8,  # 0.8 * 0.30 = 0.24
            name_score=0.5,     # 0.5 * 0.20 = 0.10
            workspace_score=1.0  # 1.0 * 0.10 = 0.10
        )
        # Expected: 0.36 + 0.24 + 0.10 + 0.10 = 0.80
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence >= CONFIDENCE_THRESHOLD, f"Should be above threshold, got {confidence}"
        assert abs(confidence - 0.80) < 0.01, f"Expected 0.80, got {confidence}"

    def test_below_threshold(self):
        """Test confidence below threshold (60%)."""
        factors = CorrelationFactors(
            timing_score=0.5,   # 0.5 * 0.40 = 0.20
            hierarchy_score=0.0,
            name_score=0.6,     # 0.6 * 0.20 = 0.12
            workspace_score=1.0  # 1.0 * 0.10 = 0.10
        )
        # Expected: 0.20 + 0.12 + 0.10 = 0.42
        confidence = self.correlator._calculate_confidence(factors)
        assert confidence < CONFIDENCE_THRESHOLD, f"Should be below threshold, got {confidence}"
        assert abs(confidence - 0.42) < 0.01, f"Expected 0.42, got {confidence}"


class TestTimingProximity:
    """Test T057: Timing proximity calculation."""

    def setup_method(self):
        """Set up test fixtures."""
        self.correlator = EventCorrelator()
        self.window_time = datetime.now()

    def test_simultaneous_spawn(self):
        """Test process spawned at same time as window (t=0ms)."""
        process_time = self.window_time
        score = self.correlator._calculate_timing_score(
            self.window_time,
            process_time,
            max_window_ms=5000.0
        )
        assert score == 1.0, f"Simultaneous spawn should give score 1.0, got {score}"

    def test_spawn_within_500ms(self):
        """Test process spawned 500ms after window."""
        process_time = self.window_time + timedelta(milliseconds=500)
        score = self.correlator._calculate_timing_score(
            self.window_time,
            process_time,
            max_window_ms=5000.0
        )
        # 500ms within 5000ms window: 1 - (500/5000) = 0.90
        expected = 0.90
        assert abs(score - expected) < 0.01, f"Expected {expected}, got {score}"

    def test_spawn_at_2500ms(self):
        """Test process spawned 2500ms (2.5s) after window."""
        process_time = self.window_time + timedelta(milliseconds=2500)
        score = self.correlator._calculate_timing_score(
            self.window_time,
            process_time,
            max_window_ms=5000.0
        )
        # 2500ms within 5000ms window: 1 - (2500/5000) = 0.50
        expected = 0.50
        assert abs(score - expected) < 0.01, f"Expected {expected}, got {score}"

    def test_spawn_at_5000ms_boundary(self):
        """Test process spawned exactly at 5-second boundary."""
        process_time = self.window_time + timedelta(milliseconds=5000)
        score = self.correlator._calculate_timing_score(
            self.window_time,
            process_time,
            max_window_ms=5000.0
        )
        # 5000ms within 5000ms window: 1 - (5000/5000) = 0.00
        assert score == 0.0, f"Boundary should give score 0.0, got {score}"

    def test_spawn_beyond_window(self):
        """Test process spawned beyond 5-second window."""
        process_time = self.window_time + timedelta(milliseconds=6000)
        score = self.correlator._calculate_timing_score(
            self.window_time,
            process_time,
            max_window_ms=5000.0
        )
        assert score == 0.0, f"Beyond window should give score 0.0, got {score}"

    def test_spawn_before_window_small_tolerance(self):
        """Test process spawned 500ms before window (within 1s tolerance)."""
        process_time = self.window_time - timedelta(milliseconds=500)
        score = self.correlator._calculate_timing_score(
            self.window_time,
            process_time,
            max_window_ms=5000.0
        )
        # Within 1s tolerance: 1 - (500/5000) = 0.90
        expected = 0.90
        assert abs(score - expected) < 0.01, f"Expected {expected}, got {score}"

    def test_spawn_before_window_beyond_tolerance(self):
        """Test process spawned >1s before window (beyond tolerance)."""
        process_time = self.window_time - timedelta(milliseconds=1500)
        score = self.correlator._calculate_timing_score(
            self.window_time,
            process_time,
            max_window_ms=5000.0
        )
        assert score == 0.0, f"Before window beyond tolerance should give 0.0, got {score}"


class TestNameSimilarity:
    """Test T058: Name similarity scoring."""

    def setup_method(self):
        """Set up test fixtures."""
        self.correlator = EventCorrelator()

    def test_exact_match(self):
        """Test exact name match."""
        score = self.correlator._calculate_name_similarity("code", "code")
        assert score == 1.0, f"Exact match should give 1.0, got {score}"

    def test_exact_match_case_insensitive(self):
        """Test exact match with different case."""
        score = self.correlator._calculate_name_similarity("Code", "code")
        assert score == 1.0, f"Case-insensitive match should give 1.0, got {score}"

    def test_substring_match(self):
        """Test substring match (e.g., 'code' in 'code-server')."""
        score = self.correlator._calculate_name_similarity("code", "code-server")
        assert score == 0.7, f"Substring match should give 0.7, got {score}"

    def test_known_ide_pattern_code_rust_analyzer(self):
        """Test known IDE pattern: Code → rust-analyzer."""
        score = self.correlator._calculate_name_similarity("Code", "rust-analyzer")
        assert score == 0.8, f"Known IDE pattern should give 0.8, got {score}"

    def test_known_ide_pattern_code_typescript_ls(self):
        """Test known IDE pattern: Code → typescript-language-server."""
        score = self.correlator._calculate_name_similarity("code", "typescript-language-server")
        assert score == 0.8, f"Known IDE pattern should give 0.8, got {score}"

    def test_known_ide_pattern_nvim_gopls(self):
        """Test known IDE pattern: nvim → gopls."""
        score = self.correlator._calculate_name_similarity("nvim", "gopls")
        assert score == 0.8, f"Known IDE pattern should give 0.8, got {score}"

    def test_fuzzy_similarity_high(self):
        """Test fuzzy similarity for similar names."""
        score = self.correlator._calculate_name_similarity("firefox", "firefox-bin")
        # Substring match takes precedence (0.7)
        assert score >= 0.7, f"Similar names should have high score, got {score}"

    def test_fuzzy_similarity_low(self):
        """Test fuzzy similarity for dissimilar names."""
        score = self.correlator._calculate_name_similarity("code", "systemd")
        # No known pattern, no substring, fuzzy only (scaled to max 0.6)
        assert score < 0.3, f"Dissimilar names should have low score, got {score}"

    def test_no_match(self):
        """Test completely different names."""
        score = self.correlator._calculate_name_similarity("abc", "xyz")
        assert score < 0.2, f"No match should give very low score, got {score}"


class TestWorkspaceMatching:
    """Test workspace co-location scoring."""

    def setup_method(self):
        """Set up test fixtures."""
        self.correlator = EventCorrelator()

    def test_same_workspace(self):
        """Test same workspace match."""
        score = self.correlator._calculate_workspace_score("1:code", "1:code")
        assert score == 1.0, f"Same workspace should give 1.0, got {score}"

    def test_different_workspace(self):
        """Test different workspaces."""
        score = self.correlator._calculate_workspace_score("1:code", "2:browser")
        assert score == 0.0, f"Different workspaces should give 0.0, got {score}"

    def test_empty_workspaces(self):
        """Test empty workspace names."""
        score = self.correlator._calculate_workspace_score("", "")
        assert score == 0.0, f"Empty workspaces should give 0.0, got {score}"

    def test_one_empty_workspace(self):
        """Test one empty workspace."""
        score = self.correlator._calculate_workspace_score("1:code", "")
        assert score == 0.0, f"One empty workspace should give 0.0, got {score}"


class TestProcessHierarchy:
    """Test process hierarchy detection."""

    def setup_method(self):
        """Set up test fixtures."""
        self.correlator = EventCorrelator()

    def test_get_parent_pid_for_init(self):
        """Test getting parent PID for init process (PID 1)."""
        # Init's parent should be 0
        parent = self.correlator._get_parent_pid(1)
        assert parent == 0, f"Init's parent should be 0, got {parent}"

    def test_get_parent_pid_for_current_process(self):
        """Test getting parent PID for current Python process."""
        import os
        current_pid = os.getpid()
        parent = self.correlator._get_parent_pid(current_pid)
        assert parent is not None, "Should be able to get parent PID"
        assert parent > 0, f"Parent PID should be positive, got {parent}"

    def test_get_parent_pid_invalid(self):
        """Test getting parent PID for invalid PID."""
        parent = self.correlator._get_parent_pid(999999999)
        assert parent is None, f"Invalid PID should return None, got {parent}"

    def test_get_process_ancestry(self):
        """Test getting process ancestry chain."""
        import os
        current_pid = os.getpid()
        ancestry = self.correlator._get_process_ancestry(current_pid, max_depth=5)

        assert len(ancestry) > 0, "Ancestry should not be empty"
        assert ancestry[0] == current_pid, "First in ancestry should be current PID"
        # Should eventually reach init or systemd
        assert 1 in ancestry or any(pid == 1 for pid in ancestry), \
            "Ancestry should eventually reach init/systemd"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
