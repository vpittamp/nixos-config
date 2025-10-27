"""Unit tests for window-to-launch correlation algorithm.

Feature 041: IPC Launch Context - T017

These tests validate the calculate_confidence() function including:
- Class match required (return 0.0 if mismatch)
- Time delta scoring (<1s = 0.8+, <2s = 0.7+, <5s = 0.6+)
- Workspace match bonus (+0.2)
- Confidence threshold (0.6 minimum)

TDD: These tests should validate the implemented algorithm.
"""

import time
from pathlib import Path

import pytest

# Import from the daemon package
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))

from models import PendingLaunch, LaunchWindowInfo
from services.window_correlator import calculate_confidence


class TestCorrelationClassMatching:
    """Test correlation requires application class match."""

    def test_class_match_required_baseline(self):
        """Test class match provides 0.5 baseline confidence."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",  # Matching class
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time + 0.5,  # 0.5s after launch
        )

        confidence, signals = calculate_confidence(launch, window)

        # Should have baseline (0.5) + time bonus (0.3 for <1s) + workspace bonus (0.2) = 1.0
        assert confidence == 1.0

    def test_class_mismatch_returns_zero(self):
        """Test class mismatch returns 0.0 confidence regardless of other signals."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",  # Expects "Code"
        )

        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Alacritty",  # Different class
            window_pid=12346,
            workspace_number=2,  # Workspace matches
            timestamp=launch_time + 0.1,  # Very recent (would be +0.3)
        )

        confidence, signals = calculate_confidence(launch, window)

        # Should be 0.0 due to class mismatch, even with perfect timing and workspace
        assert confidence == 0.0

    def test_class_matching_case_sensitive(self):
        """Test class matching is case-sensitive."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="terminal",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=1,
            timestamp=launch_time,
            expected_class="Alacritty",
        )

        # Test lowercase version doesn't match
        window_lower = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="alacritty",  # Lowercase
            window_pid=12346,
            workspace_number=1,
            timestamp=launch_time + 0.1,
        )

        confidence_lower, signals_lower = calculate_confidence(launch, window_lower)
        assert confidence_lower == 0.0  # Should not match

        # Test correct case matches
        window_correct = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Alacritty",  # Correct case
            window_pid=12346,
            workspace_number=1,
            timestamp=launch_time + 0.1,
        )

        confidence_correct, signals_correct = calculate_confidence(launch, window_correct)
        assert confidence_correct > 0.0  # Should match


class TestCorrelationTimeDelta:
    """Test correlation time delta scoring."""

    def test_time_delta_very_recent_under_1s(self):
        """Test time delta <1s adds 0.3 (HIGH confidence)."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window appears 0.5 seconds after launch
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=3,  # Different workspace (no bonus)
            timestamp=launch_time + 0.5,
        )

        confidence, signals = calculate_confidence(launch, window)

        # baseline (0.5) + time (<1s = 0.3) = 0.8 (HIGH)
        assert confidence == 0.8

    def test_time_delta_recent_1s_to_2s(self):
        """Test time delta 1-2s adds 0.2 (MEDIUM-HIGH confidence)."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window appears 1.5 seconds after launch
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=3,  # Different workspace (no bonus)
            timestamp=launch_time + 1.5,
        )

        confidence, signals = calculate_confidence(launch, window)

        # baseline (0.5) + time (1-2s = 0.2) = 0.7
        assert confidence == 0.7

    def test_time_delta_within_window_2s_to_5s(self):
        """Test time delta 2-5s adds 0.1 (MEDIUM confidence)."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window appears 3 seconds after launch
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=3,  # Different workspace (no bonus)
            timestamp=launch_time + 3.0,
        )

        confidence, signals = calculate_confidence(launch, window)

        # baseline (0.5) + time (2-5s = 0.1) = 0.6 (MEDIUM threshold)
        assert confidence == 0.6

    def test_time_delta_boundary_exactly_1s(self):
        """Test time delta exactly 1.0s is in <1s category."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window appears exactly 1.0 second after launch (boundary)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=3,
            timestamp=launch_time + 1.0,
        )

        confidence, signals = calculate_confidence(launch, window)

        # At exactly 1.0s, should be in 1-2s category (not <1s)
        # baseline (0.5) + time (1-2s = 0.2) = 0.7
        assert confidence == 0.7

    def test_time_delta_boundary_exactly_5s(self):
        """Test time delta exactly 5.0s is outside correlation window."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window appears exactly 5.0 seconds after launch (boundary)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time + 5.0,
        )

        confidence, signals = calculate_confidence(launch, window)

        # At exactly 5.0s, outside window
        assert confidence == 0.0

    def test_time_delta_beyond_5s_returns_zero(self):
        """Test time delta >=5s returns 0.0 (expired)."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window appears 6 seconds after launch
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time + 6.0,
        )

        confidence, signals = calculate_confidence(launch, window)

        # Should be 0.0 due to expiration
        assert confidence == 0.0

    def test_time_delta_negative_returns_zero(self):
        """Test window appearing before launch returns 0.0 (clock skew)."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window appears BEFORE launch (clock skew or bug)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time - 1.0,  # 1 second before launch
        )

        confidence, signals = calculate_confidence(launch, window)

        # Should be 0.0 due to negative time delta
        assert confidence == 0.0


class TestCorrelationWorkspaceBonus:
    """Test correlation workspace match bonus."""

    def test_workspace_match_adds_bonus(self):
        """Test workspace match adds +0.2 bonus."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window on matching workspace
        window_match = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,  # Matches launch workspace
            timestamp=launch_time + 0.5,
        )

        confidence_with_bonus, signals_with_bonus = calculate_confidence(launch, window_match)

        # baseline (0.5) + time (<1s = 0.3) + workspace (0.2) = 1.0
        assert confidence_with_bonus == 1.0

    def test_workspace_mismatch_no_bonus(self):
        """Test workspace mismatch gives no bonus (but doesn't prevent matching)."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window on different workspace
        window_nomatch = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=3,  # Different workspace
            timestamp=launch_time + 0.5,
        )

        confidence_no_bonus, signals_no_bonus = calculate_confidence(launch, window_nomatch)

        # baseline (0.5) + time (<1s = 0.3) = 0.8 (no workspace bonus)
        assert confidence_no_bonus == 0.8

    def test_workspace_bonus_difference(self):
        """Test workspace match vs mismatch shows 0.2 difference."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=5,
            timestamp=launch_time,
            expected_class="Code",
        )

        window_match = LaunchWindowInfo(
            window_id=1,
            window_class="Code",
            window_pid=100,
            workspace_number=5,  # Match
            timestamp=launch_time + 1.5,
        )

        window_nomatch = LaunchWindowInfo(
            window_id=2,
            window_class="Code",
            window_pid=101,
            workspace_number=7,  # No match
            timestamp=launch_time + 1.5,  # Same timing
        )

        confidence_match, signals_match = calculate_confidence(launch, window_match)
        confidence_nomatch, signals_nomatch = calculate_confidence(launch, window_nomatch)

        # Difference should be exactly 0.2 (workspace bonus)
        assert abs(confidence_match - confidence_nomatch - 0.2) < 0.001


class TestCorrelationConfidenceThreshold:
    """Test correlation confidence threshold and levels."""

    def test_confidence_medium_threshold_0_6(self):
        """Test MEDIUM threshold (0.6) is minimum for project assignment."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window with exactly 0.6 confidence: class (0.5) + time 2-5s (0.1) = 0.6
        window_medium = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=3,  # No workspace bonus
            timestamp=launch_time + 3.0,  # 3s = 0.1 time bonus
        )

        confidence, signals = calculate_confidence(launch, window_medium)

        # Should be exactly at MEDIUM threshold
        assert confidence == 0.6

    def test_confidence_high_level_0_8_plus(self):
        """Test HIGH confidence level (0.8+) achieved with <1s timing."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window with HIGH confidence: class (0.5) + time <1s (0.3) = 0.8
        window_high = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=3,  # No workspace bonus
            timestamp=launch_time + 0.5,  # <1s = 0.3 bonus
        )

        confidence, signals = calculate_confidence(launch, window_high)

        # Should be HIGH level (0.8+)
        assert confidence >= 0.8

    def test_confidence_exact_level_1_0(self):
        """Test EXACT confidence level (1.0) with all signals matching."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window with EXACT confidence: class (0.5) + time <1s (0.3) + workspace (0.2) = 1.0
        window_exact = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,  # Workspace matches
            timestamp=launch_time + 0.5,  # <1s timing
        )

        confidence, signals = calculate_confidence(launch, window_exact)

        # Should be EXACT level (1.0)
        assert confidence == 1.0

    def test_confidence_capped_at_1_0(self):
        """Test confidence is capped at 1.0 (no overflow)."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window with all positive signals
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time + 0.1,  # Very fast
        )

        confidence, signals = calculate_confidence(launch, window)

        # Should never exceed 1.0
        assert confidence <= 1.0


class TestCorrelationEdgeCases:
    """Test correlation edge cases and boundary conditions."""

    def test_zero_time_delta(self):
        """Test window appearing at exact same timestamp as launch."""
        launch_time = time.time()

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Window at exact same timestamp
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time,  # Exact same time
        )

        confidence, signals = calculate_confidence(launch, window)

        # 0s counts as <1s: baseline (0.5) + time (0.3) + workspace (0.2) = 1.0
        assert confidence == 1.0

    def test_multiple_launches_same_app(self):
        """Test correlation distinguishes between multiple launches of same app."""
        # Use a base time in the past to avoid timestamp validation issues
        current_time = time.time()
        launch_time = current_time - 5.0  # 5 seconds ago

        # First launch at t=0 (5 seconds ago)
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Second launch at t=2s (3 seconds ago)
        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=launch_time + 2.0,
            expected_class="Code",
        )

        # Window appears at t=2.5s (2.5 seconds ago, 0.5s after launch2)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12347,
            workspace_number=3,
            timestamp=launch_time + 2.5,
        )

        # Calculate confidence for both launches
        conf1 = calculate_confidence(launch1, window)
        conf2 = calculate_confidence(launch2, window)

        # launch2 should have higher confidence (better timing and workspace match)
        # launch1: class (0.5) + time 2-5s (0.1) = 0.6
        # launch2: class (0.5) + time <1s (0.3) + workspace (0.2) = 1.0
        assert conf1 == 0.6
        assert conf2 == 1.0
        assert conf2 > conf1

    def test_workspace_number_boundaries(self):
        """Test correlation works with workspace boundary values (1 and 70)."""
        launch_time = time.time()

        # Test workspace 1
        launch1 = PendingLaunch(
            app_name="terminal",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=1,
            timestamp=launch_time,
            expected_class="Alacritty",
        )

        window1 = LaunchWindowInfo(
            window_id=1,
            window_class="Alacritty",
            window_pid=100,
            workspace_number=1,
            timestamp=launch_time + 0.5,
        )

        conf1 = calculate_confidence(launch1, window1)
        assert conf1 == 1.0  # All signals match

        # Test workspace 70
        launch70 = PendingLaunch(
            app_name="terminal",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=70,
            timestamp=launch_time,
            expected_class="Alacritty",
        )

        window70 = LaunchWindowInfo(
            window_id=2,
            window_class="Alacritty",
            window_pid=101,
            workspace_number=70,
            timestamp=launch_time + 0.5,
        )

        conf70 = calculate_confidence(launch70, window70)
        assert conf70 == 1.0  # All signals match


class TestFirstMatchWinsStrategy:
    """Test first-match-wins strategy for rapid launches.

    Feature 041: IPC Launch Context - T025 (User Story 2)

    Tests for LaunchRegistry.find_match() behavior with multiple pending launches:
    - Highest confidence launch wins
    - Matched flag prevents double-matching
    - Timestamp ordering for tiebreaking
    """

    @pytest.mark.asyncio
    async def test_find_match_selects_highest_confidence(self):
        """Test find_match returns launch with highest confidence above threshold."""
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))
        from services.launch_registry import LaunchRegistry

        registry = LaunchRegistry(timeout=5.0)
        launch_time = time.time()

        # Add three launches for same app at different times
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time - 2.0,  # 2 seconds ago (LOW confidence)
            expected_class="Code",
        )

        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=launch_time - 0.5,  # 0.5 seconds ago (HIGH confidence)
            expected_class="Code",
        )

        launch3 = PendingLaunch(
            app_name="vscode",
            project_name="personal",
            project_directory=Path("/home/user/personal"),
            launcher_pid=12347,
            workspace_number=4,
            timestamp=launch_time - 1.5,  # 1.5 seconds ago (MEDIUM confidence)
            expected_class="Code",
        )

        await registry.add(launch1)
        await registry.add(launch2)
        await registry.add(launch3)

        # Window appears now on workspace 3 (matches launch2)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12348,
            workspace_number=3,
            timestamp=launch_time,
        )

        # Find match should return launch2 (highest confidence)
        matched_launch = await registry.find_match(window)

        assert matched_launch is not None
        assert matched_launch.project_name == "stacks"  # launch2
        assert matched_launch.matched is True  # Should be marked as matched

    @pytest.mark.asyncio
    async def test_find_match_prevents_double_matching(self):
        """Test matched flag prevents a launch from being matched twice."""
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))
        from services.launch_registry import LaunchRegistry

        registry = LaunchRegistry(timeout=5.0)
        launch_time = time.time()

        # Add single launch
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time - 0.5,
            expected_class="Code",
        )

        await registry.add(launch)

        # First window matches
        window1 = LaunchWindowInfo(
            window_id=1,
            window_class="Code",
            window_pid=100,
            workspace_number=2,
            timestamp=launch_time,
        )

        matched1 = await registry.find_match(window1)
        assert matched1 is not None
        assert matched1.project_name == "nixos"
        assert matched1.matched is True

        # Second window should NOT match same launch (already matched)
        window2 = LaunchWindowInfo(
            window_id=2,
            window_class="Code",
            window_pid=101,
            workspace_number=2,
            timestamp=launch_time + 0.1,
        )

        matched2 = await registry.find_match(window2)
        assert matched2 is None  # No unmatched launches available

    @pytest.mark.asyncio
    async def test_find_match_uses_timestamp_for_tiebreaking(self):
        """Test oldest unmatched launch wins when confidence is equal."""
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))
        from services.launch_registry import LaunchRegistry

        registry = LaunchRegistry(timeout=5.0)
        launch_time = time.time()

        # Add two launches with identical confidence potential
        # Both launched 1.5s ago, same class, different workspaces
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time - 2.0,  # Older
            expected_class="Code",
        )

        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=2,
            timestamp=launch_time - 1.0,  # Newer
            expected_class="Code",
        )

        await registry.add(launch1)
        await registry.add(launch2)

        # Window appears on workspace 5 (no workspace match for either)
        # Both will have same confidence: class (0.5) + time (varies)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12348,
            workspace_number=5,
            timestamp=launch_time,
        )

        # Should match launch2 (higher confidence due to better timing)
        matched_launch = await registry.find_match(window)

        assert matched_launch is not None
        # launch2 has better timing (1s vs 2s), so higher confidence
        assert matched_launch.project_name == "stacks"

    @pytest.mark.asyncio
    async def test_find_match_ignores_below_threshold(self):
        """Test find_match ignores launches below MEDIUM (0.6) threshold."""
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))
        from services.launch_registry import LaunchRegistry

        registry = LaunchRegistry(timeout=5.0)
        launch_time = time.time()

        # Add launch that will be below threshold
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time - 4.5,  # OLD: will give LOW confidence
            expected_class="Code",
        )

        await registry.add(launch)

        # Window appears now (4.5s after launch)
        # Confidence: class (0.5) + time 2-5s (0.1) = 0.6 (exactly at threshold)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12348,
            workspace_number=5,  # No workspace match
            timestamp=launch_time,
        )

        # Should match (exactly at 0.6 threshold)
        matched_launch = await registry.find_match(window)
        assert matched_launch is not None

        # Now test below threshold (5.0s or more)
        registry2 = LaunchRegistry(timeout=5.0)
        launch_below = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time - 5.0,  # Exactly 5.0s: outside correlation window
            expected_class="Code",
        )
        await registry2.add(launch_below)

        window_below = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12348,
            workspace_number=5,
            timestamp=launch_time,
        )

        # Should NOT match (5.0s gives confidence 0.0, below 0.6 threshold)
        matched_below = await registry2.find_match(window_below)
        assert matched_below is None

    @pytest.mark.asyncio
    async def test_find_match_with_no_pending_launches(self):
        """Test find_match returns None when registry is empty."""
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))
        from services.launch_registry import LaunchRegistry

        registry = LaunchRegistry(timeout=5.0)
        launch_time = time.time()

        # No launches added
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12348,
            workspace_number=2,
            timestamp=launch_time,
        )

        matched_launch = await registry.find_match(window)
        assert matched_launch is None

    @pytest.mark.asyncio
    async def test_find_match_with_different_app_classes(self):
        """Test find_match correctly matches by class when multiple app types pending."""
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))
        from services.launch_registry import LaunchRegistry

        registry = LaunchRegistry(timeout=5.0)
        launch_time = time.time()

        # Add launches for different app types
        launch_vscode = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time - 0.5,
            expected_class="Code",
        )

        launch_terminal = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=launch_time - 0.3,  # More recent
            expected_class="Alacritty",
        )

        await registry.add(launch_vscode)
        await registry.add(launch_terminal)

        # Terminal window appears
        window_terminal = LaunchWindowInfo(
            window_id=1,
            window_class="Alacritty",
            window_pid=100,
            workspace_number=3,
            timestamp=launch_time,
        )

        # Should match terminal launch (by class)
        matched = await registry.find_match(window_terminal)
        assert matched is not None
        assert matched.project_name == "stacks"
        assert matched.expected_class == "Alacritty"

        # VS Code window appears
        window_vscode = LaunchWindowInfo(
            window_id=2,
            window_class="Code",
            window_pid=101,
            workspace_number=2,
            timestamp=launch_time + 0.1,
        )

        # Should match VS Code launch
        matched_vscode = await registry.find_match(window_vscode)
        assert matched_vscode is not None
        assert matched_vscode.project_name == "nixos"
        assert matched_vscode.expected_class == "Code"
