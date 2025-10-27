#!/usr/bin/env python3
"""
Scenario Test: Workspace-Based Disambiguation (User Story 5)

Tests workspace location as an additional correlation signal to improve matching
confidence when multiple launches of the same app type exist.

Acceptance Scenarios:
1. Window appears on expected workspace → verify confidence boost
2. Two launches 0.5s apart with workspace as tiebreaker → correct assignment
3. Workspace mismatch reduces confidence but doesn't prevent matching → MEDIUM confidence

Target: Workspace match increases confidence by 0.2
"""

import asyncio
import time
import pytest
from pathlib import Path

# Test infrastructure imports
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "fixtures"))
from launch_fixtures import create_pending_launch, create_window_info, MockIPCServer

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "assertions"))
from launch_assertions import LaunchAssertions

# Daemon imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))
from services.launch_registry import LaunchRegistry
from services.window_correlator import calculate_confidence
from models import PendingLaunch, LaunchWindowInfo


@pytest.mark.asyncio
async def test_workspace_match_increases_confidence():
    """
    Acceptance Scenario 1: Window appears on expected workspace, verify confidence boost.

    Expected: Workspace match adds +0.2 to confidence score.
    """
    # Setup: Launch on workspace 2
    launch_time = time.time()
    launch_data = create_pending_launch(
        app_name="vscode",
        project_name="nixos",
        workspace_number=2,
        expected_class="Code",
        timestamp=launch_time
    )
    launch = PendingLaunch(**launch_data)

    # Window appears on same workspace (match)
    window_match_data = create_window_info(
        window_class="Code",
        workspace_number=2,  # MATCH
        timestamp=launch_time + 0.5  # 0.5s delta
    )
    window_match = LaunchWindowInfo(**window_match_data)

    # Window appears on different workspace (mismatch)
    window_mismatch_data = create_window_info(
        window_class="Code",
        workspace_number=3,  # MISMATCH
        timestamp=launch_time + 0.5  # Same time delta
    )
    window_mismatch = LaunchWindowInfo(**window_mismatch_data)

    # Calculate confidence with workspace match
    confidence_match, signals_match = calculate_confidence(launch, window_match)

    # Calculate confidence without workspace match
    confidence_mismatch, signals_mismatch = calculate_confidence(launch, window_mismatch)

    # Verify workspace match adds +0.2
    boost = confidence_match - confidence_mismatch
    assert abs(boost - 0.2) < 0.01, (
        f"Workspace match should add +0.2 to confidence, "
        f"got {boost:.2f} (match={confidence_match:.2f}, mismatch={confidence_mismatch:.2f})"
    )

    # Verify both are still valid matches (above 0.6 threshold)
    # Base: class match (0.5) + time delta <1s (0.3) = 0.8
    # With workspace: 0.8 + 0.2 = 1.0
    # Without workspace: 0.8
    assert confidence_match >= 0.6, f"Match confidence {confidence_match:.2f} should be >= 0.6"
    assert confidence_mismatch >= 0.6, f"Mismatch confidence {confidence_mismatch:.2f} should be >= 0.6"

    print(f"✅ Workspace match boost verified: +{boost:.2f}")
    print(f"   With workspace match: {confidence_match:.2f}")
    print(f"   Without workspace match: {confidence_mismatch:.2f}")


@pytest.mark.asyncio
async def test_workspace_as_tiebreaker():
    """
    Acceptance Scenario 2: Two launches 0.5s apart with workspace as tiebreaker.

    Expected: When two launches are similar, workspace match determines winner.
    """
    registry = LaunchRegistry(timeout=5.0)

    # Launch 1: VS Code on workspace 2 for nixos
    launch1_time = time.time()
    launch1_data = create_pending_launch(
        app_name="vscode",
        project_name="nixos",
        workspace_number=2,
        expected_class="Code",
        timestamp=launch1_time
    )
    launch1 = PendingLaunch(**launch1_data)
    await registry.add(launch1)

    # Launch 2: VS Code on workspace 3 for stacks (0.5s later)
    launch2_time = launch1_time + 0.5
    launch2_data = create_pending_launch(
        app_name="vscode",
        project_name="stacks",
        workspace_number=3,
        expected_class="Code",
        timestamp=launch2_time
    )
    launch2 = PendingLaunch(**launch2_data)
    await registry.add(launch2)

    # Window appears on workspace 2 (matches launch1's workspace)
    window_data = create_window_info(
        window_class="Code",
        workspace_number=2,  # Matches launch1
        timestamp=launch2_time + 0.5  # After both launches
    )
    window = LaunchWindowInfo(**window_data)

    # Find match - should prefer launch1 due to workspace match
    result = await registry.find_match(window)

    assert result is not None, "Should find a match"
    assert result.project_name == "nixos", (
        f"Workspace tiebreaker should select launch1 (nixos), got {result.project_name}"
    )

    # Calculate confidence to verify workspace signal was used
    confidence, signals = calculate_confidence(result, window)
    assert confidence >= 0.8, (
        f"Confidence should be HIGH with workspace match, got {confidence:.2f}"
    )

    # Verify signals show workspace was a factor
    assert "workspace_match" in signals, "Signals should include workspace_match"
    assert signals["workspace_match"] is True, "Workspace should match"

    print(f"✅ Workspace tiebreaker test passed")
    print(f"   Selected: {result.project_name} (workspace {launch1.workspace_number})")
    print(f"   Confidence: {confidence:.2f}")


@pytest.mark.asyncio
async def test_workspace_mismatch_does_not_block_correlation():
    """
    Acceptance Scenario 3: Workspace mismatch reduces confidence but doesn't prevent matching.

    Expected: Window on wrong workspace still matches if other signals are strong enough.
    """
    # Launch on workspace 2
    launch_time = time.time()
    launch_data = create_pending_launch(
        app_name="vscode",
        project_name="nixos",
        workspace_number=2,
        expected_class="Code",
        timestamp=launch_time
    )
    launch = PendingLaunch(**launch_data)

    # Window appears on workspace 3 (mismatch) but quickly (<1s)
    window_data = create_window_info(
        window_class="Code",
        workspace_number=3,  # MISMATCH
        timestamp=launch_time + 0.5  # 0.5s delta (strong signal)
    )
    window = LaunchWindowInfo(**window_data)

    # Calculate confidence
    confidence, signals = calculate_confidence(launch, window)

    # Should still match despite workspace mismatch
    # Base: class match (0.5) + time delta <1s (0.3) = 0.8
    # No workspace bonus: 0.8
    assert confidence >= 0.6, (
        f"Workspace mismatch should not block correlation, "
        f"got confidence {confidence:.2f} (expected >= 0.6)"
    )

    # Should be MEDIUM or HIGH confidence
    from models import ConfidenceLevel
    if confidence >= 0.8:
        expected_level = ConfidenceLevel.HIGH
    elif confidence >= 0.6:
        expected_level = ConfidenceLevel.MEDIUM
    else:
        expected_level = ConfidenceLevel.LOW

    assert expected_level in [ConfidenceLevel.MEDIUM, ConfidenceLevel.HIGH], (
        f"Expected MEDIUM or HIGH confidence, got {expected_level}"
    )

    print(f"✅ Workspace mismatch test passed")
    print(f"   Confidence: {confidence:.2f} ({expected_level})")
    print(f"   Still correlates despite workspace mismatch")


@pytest.mark.asyncio
async def test_workspace_match_with_weak_timing():
    """
    Edge case: Workspace match can compensate for weaker timing signal.

    Window appears 2-5s after launch, workspace match pushes confidence over threshold.
    """
    # Launch on workspace 2
    launch_time = time.time()
    launch_data = create_pending_launch(
        app_name="vscode",
        project_name="nixos",
        workspace_number=2,
        expected_class="Code",
        timestamp=launch_time
    )
    launch = PendingLaunch(**launch_data)

    # Window appears 3s later (weak timing signal)
    window_data = create_window_info(
        window_class="Code",
        workspace_number=2,  # Workspace MATCH
        timestamp=launch_time + 3.0  # 3s delta (0.1 timing bonus)
    )
    window = LaunchWindowInfo(**window_data)

    # Calculate confidence
    confidence, signals = calculate_confidence(launch, window)

    # Expected: class (0.5) + time 2-5s (0.1) + workspace (0.2) = 0.8 (HIGH)
    assert confidence >= 0.6, (
        f"Workspace match should compensate for weak timing, got {confidence:.2f}"
    )

    # Should reach MEDIUM or HIGH confidence with workspace boost
    assert confidence >= 0.7, (
        f"Expected >= 0.7 with workspace boost, got {confidence:.2f}"
    )

    print(f"✅ Workspace compensation test passed")
    print(f"   Time delta: 3.0s (weak)")
    print(f"   Workspace match: Yes")
    print(f"   Final confidence: {confidence:.2f}")


@pytest.mark.asyncio
async def test_workspace_signals_in_correlation_result():
    """
    Verify that workspace match/mismatch is reported in signals_used.

    Used for debugging and `i3pm diagnose window` command.
    """
    registry = LaunchRegistry(timeout=5.0)

    # Launch on workspace 2
    launch_time = time.time()
    launch_data = create_pending_launch(
        app_name="vscode",
        project_name="nixos",
        workspace_number=2,
        expected_class="Code",
        timestamp=launch_time
    )
    launch = PendingLaunch(**launch_data)
    await registry.add(launch)

    # Window appears on workspace 2 (match)
    window_data = create_window_info(
        window_class="Code",
        workspace_number=2,
        timestamp=launch_time + 0.5
    )
    window = LaunchWindowInfo(**window_data)

    # Find match
    result = await registry.find_match(window)

    assert result is not None, "Should find a match"

    # Calculate confidence to get signals
    confidence, signals = calculate_confidence(result, window)

    # Verify signals contain workspace information
    assert "workspace_match" in signals, "Should report workspace_match"
    assert "launch_workspace" in signals, "Should report launch workspace"
    assert "window_workspace" in signals, "Should report window workspace"

    assert signals["workspace_match"] is True, "Workspace should match"
    assert signals["launch_workspace"] == 2, "Launch workspace should be 2"
    assert signals["window_workspace"] == 2, "Window workspace should be 2"

    print(f"✅ Workspace signals test passed")
    print(f"   Signals: {signals}")


if __name__ == "__main__":
    """Run tests standalone for quick validation."""
    print("=" * 60)
    print("User Story 5: Workspace-Based Disambiguation")
    print("=" * 60)

    asyncio.run(test_workspace_match_increases_confidence())
    print()

    asyncio.run(test_workspace_as_tiebreaker())
    print()

    asyncio.run(test_workspace_mismatch_does_not_block_correlation())
    print()

    asyncio.run(test_workspace_match_with_weak_timing())
    print()

    asyncio.run(test_workspace_signals_in_correlation_result())
    print()

    print("=" * 60)
    print("✅ All User Story 5 tests passed!")
    print("=" * 60)
