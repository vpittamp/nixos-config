"""Integration tests for LaunchRegistry.

Feature 041: IPC Launch Context - T018

These tests validate the LaunchRegistry service including:
- add() creates pending launch
- find_match() returns correct launch
- Expiration cleanup (launches older than 5s removed)
- get_stats() returns accurate counters

TDD: These tests validate the implemented LaunchRegistry.
"""

import asyncio
import time
from pathlib import Path

import pytest

# Import from the daemon package
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))

from models import PendingLaunch, LaunchWindowInfo, LaunchRegistryStats
from services.launch_registry import LaunchRegistry


class TestLaunchRegistryBasics:
    """Test basic LaunchRegistry operations."""

    @pytest.mark.asyncio
    async def test_initialization(self):
        """Test LaunchRegistry initializes with correct defaults."""
        registry = LaunchRegistry(timeout=5.0)

        stats = registry.get_stats()

        assert stats.total_pending == 0
        assert stats.unmatched_pending == 0
        assert stats.total_notifications == 0
        assert stats.total_matched == 0
        assert stats.total_expired == 0
        assert stats.total_failed_correlation == 0

    @pytest.mark.asyncio
    async def test_add_creates_pending_launch(self):
        """Test add() creates a pending launch entry."""
        registry = LaunchRegistry(timeout=5.0)

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="Code",
        )

        launch_id = await registry.add(launch)

        # Verify launch ID format
        assert launch_id.startswith("vscode-")
        assert str(launch.timestamp) in launch_id

        # Verify stats updated
        stats = registry.get_stats()
        assert stats.total_pending == 1
        assert stats.unmatched_pending == 1
        assert stats.total_notifications == 1

    @pytest.mark.asyncio
    async def test_add_multiple_launches(self):
        """Test add() handles multiple pending launches."""
        registry = LaunchRegistry(timeout=5.0)

        # Add first launch
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="Code",
        )
        await registry.add(launch1)

        # Add second launch
        await asyncio.sleep(0.01)  # Small delay for unique timestamp
        launch2 = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=time.time(),
            expected_class="Alacritty",
        )
        await registry.add(launch2)

        # Verify both tracked
        stats = registry.get_stats()
        assert stats.total_pending == 2
        assert stats.unmatched_pending == 2
        assert stats.total_notifications == 2


class TestLaunchRegistryMatching:
    """Test LaunchRegistry find_match() correlation."""

    @pytest.mark.asyncio
    async def test_find_match_returns_correct_launch(self):
        """Test find_match() returns the best matching launch."""
        registry = LaunchRegistry(timeout=5.0)

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
        await registry.add(launch)

        # Window appears 0.5s later
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time + 0.5,
        )

        match = await registry.find_match(window)

        # Should find the matching launch
        assert match is not None
        assert match.app_name == "vscode"
        assert match.project_name == "nixos"
        assert match.matched is True

        # Verify stats updated
        stats = registry.get_stats()
        assert stats.total_matched == 1

    @pytest.mark.asyncio
    async def test_find_match_marks_as_matched(self):
        """Test find_match() marks launch as matched to prevent double-matching."""
        registry = LaunchRegistry(timeout=5.0)

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
        await registry.add(launch)

        window1 = LaunchWindowInfo(
            window_id=1,
            window_class="Code",
            window_pid=100,
            workspace_number=2,
            timestamp=launch_time + 0.5,
        )

        window2 = LaunchWindowInfo(
            window_id=2,
            window_class="Code",
            window_pid=101,
            workspace_number=2,
            timestamp=launch_time + 1.0,
        )

        # First match should succeed
        match1 = await registry.find_match(window1)
        assert match1 is not None
        assert match1.app_name == "vscode"

        # Second match should fail (already matched)
        match2 = await registry.find_match(window2)
        assert match2 is None

        # Stats should show 1 match, 1 failed
        stats = registry.get_stats()
        assert stats.total_matched == 1
        assert stats.total_failed_correlation == 1

    @pytest.mark.asyncio
    async def test_find_match_with_multiple_candidates(self):
        """Test find_match() selects highest confidence match."""
        registry = LaunchRegistry(timeout=5.0)

        base_time = time.time() - 5.0  # Use past time

        # Add two launches for same app but different projects
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,  # Older launch
            expected_class="Code",
        )
        await registry.add(launch1)

        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 2.0,  # Newer launch
            expected_class="Code",
        )
        await registry.add(launch2)

        # Window appears 0.5s after launch2 on workspace 3
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12347,
            workspace_number=3,
            timestamp=base_time + 2.5,
        )

        match = await registry.find_match(window)

        # Should match launch2 (better timing + workspace match)
        assert match is not None
        assert match.project_name == "stacks"
        assert match.workspace_number == 3

    @pytest.mark.asyncio
    async def test_find_match_no_candidates(self):
        """Test find_match() returns None when no pending launches."""
        registry = LaunchRegistry(timeout=5.0)

        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=time.time(),
        )

        match = await registry.find_match(window)

        assert match is None

        # Should increment failed correlation counter
        stats = registry.get_stats()
        assert stats.total_failed_correlation == 1

    @pytest.mark.asyncio
    async def test_find_match_class_mismatch(self):
        """Test find_match() returns None when window class doesn't match."""
        registry = LaunchRegistry(timeout=5.0)

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
        await registry.add(launch)

        # Window with different class
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Alacritty",  # Mismatch
            window_pid=12346,
            workspace_number=2,
            timestamp=launch_time + 0.5,
        )

        match = await registry.find_match(window)

        assert match is None
        stats = registry.get_stats()
        assert stats.total_failed_correlation == 1


class TestLaunchRegistryExpiration:
    """Test LaunchRegistry expiration cleanup.

    Feature 041: IPC Launch Context - T030 (User Story 3)

    Tests for launch timeout handling:
    - _cleanup_expired() removes launches older than timeout
    - Launches with age > 5s are removed
    - Expired launches logged as warnings
    """

    @pytest.mark.asyncio
    async def test_cleanup_expired_launches(self):
        """Test _cleanup_expired() removes launches older than timeout."""
        registry = LaunchRegistry(timeout=1.0)  # 1-second timeout for faster test

        # Add launch (will be 1 second old by the time we check)
        old_time = time.time()
        old_launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=old_time,
            expected_class="Code",
        )
        # Manually add to bypass cleanup timing
        registry._launches[f"vscode-{old_time}"] = old_launch
        registry._total_notifications += 1

        # Wait for expiration
        await asyncio.sleep(1.1)

        # Add a new launch (triggers cleanup)
        new_launch = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=time.time(),
            expected_class="Alacritty",
        )
        await registry.add(new_launch)

        # Verify old launch was cleaned up
        stats = registry.get_stats()
        assert stats.total_pending == 1  # Only new launch
        assert stats.total_expired == 1

    @pytest.mark.asyncio
    async def test_cleanup_preserves_recent_launches(self):
        """Test _cleanup_expired() preserves launches within timeout."""
        registry = LaunchRegistry(timeout=5.0)

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="Code",
        )
        await registry.add(launch)

        # Add another launch (triggers cleanup)
        launch2 = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=time.time(),
            expected_class="Alacritty",
        )
        await registry.add(launch2)

        # Both should still be present
        stats = registry.get_stats()
        assert stats.total_pending == 2
        assert stats.total_expired == 0

    @pytest.mark.asyncio
    async def test_automatic_cleanup_on_add(self):
        """Test add() triggers automatic cleanup."""
        registry = LaunchRegistry(timeout=1.0)

        # Add old launch
        old_time = time.time() - 2.0
        old_launch = PendingLaunch(
            app_name="old_app",
            project_name="old_project",
            project_directory=Path("/tmp"),
            launcher_pid=11111,
            workspace_number=1,
            timestamp=old_time,
            expected_class="OldClass",
        )
        # Manually add to bypass cleanup for setup
        registry._launches[f"old_app-{old_time}"] = old_launch
        registry._total_notifications += 1

        # Now add a fresh launch (should trigger cleanup)
        fresh_launch = PendingLaunch(
            app_name="fresh_app",
            project_name="fresh_project",
            project_directory=Path("/etc/nixos"),
            launcher_pid=22222,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="FreshClass",
        )
        await registry.add(fresh_launch)

        # Old launch should be removed, fresh one should remain
        stats = registry.get_stats()
        assert stats.total_pending == 1  # Only fresh launch
        assert stats.total_expired == 1

    @pytest.mark.asyncio
    async def test_5_second_timeout_removes_old_launches(self):
        """Test launches older than 5 seconds are removed (default timeout).

        Feature 041: T030 - Explicit test for 5-second timeout requirement.
        """
        registry = LaunchRegistry(timeout=5.0)  # Default 5-second timeout

        # Add launch that's 6 seconds old
        old_time = time.time() - 6.0
        expired_launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=old_time,
            expected_class="Code",
        )
        # Manually add to bypass cleanup during setup
        registry._launches[f"vscode-{old_time}"] = expired_launch
        registry._total_notifications += 1

        # Add launch that's 4 seconds old (within timeout)
        recent_time = time.time() - 4.0
        recent_launch = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=recent_time,
            expected_class="Alacritty",
        )
        # Manually add
        registry._launches[f"terminal-{recent_time}"] = recent_launch
        registry._total_notifications += 1

        # Trigger cleanup by adding a new launch
        await registry.add(PendingLaunch(
            app_name="new_app",
            project_name="new_project",
            project_directory=Path("/tmp"),
            launcher_pid=99999,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="NewClass",
        ))

        # Verify expired launch removed, recent launch preserved
        stats = registry.get_stats()
        assert stats.total_pending == 2  # recent_launch + new_app
        assert stats.total_expired == 1  # expired_launch removed
        assert stats.total_notifications == 3

    @pytest.mark.asyncio
    async def test_expiration_within_5_plus_minus_0_5_seconds(self):
        """Test expiration accuracy within 5±0.5 seconds (SC-005).

        Feature 041: T030 - Validate expiration timing accuracy.
        """
        registry = LaunchRegistry(timeout=5.0)

        # Add launch
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
        await registry.add(launch)

        # Wait 4.5 seconds (within timeout - should NOT expire)
        await asyncio.sleep(4.5)

        # Trigger cleanup
        await registry.add(PendingLaunch(
            app_name="trigger",
            project_name="test",
            project_directory=Path("/tmp"),
            launcher_pid=99999,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="Test",
        ))

        # Should still have both launches
        stats = registry.get_stats()
        assert stats.total_expired == 0
        assert stats.total_pending == 2

        # Wait another 1 second (total 5.5s - should expire)
        await asyncio.sleep(1.0)

        # Trigger cleanup again
        await registry.add(PendingLaunch(
            app_name="trigger2",
            project_name="test2",
            project_directory=Path("/tmp"),
            launcher_pid=99998,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="Test2",
        ))

        # Now the original launch should be expired
        stats = registry.get_stats()
        assert stats.total_expired == 1
        assert stats.total_pending == 2  # trigger + trigger2 (original expired)

    @pytest.mark.asyncio
    async def test_expiration_logs_warning(self, caplog):
        """Test expired launches log warning messages (FR-009).

        Feature 041: T030 - Validate explicit failure logging.
        """
        import logging
        caplog.set_level(logging.WARNING)

        registry = LaunchRegistry(timeout=1.0)  # 1-second timeout for faster test

        # Add launch that will expire
        old_time = time.time() - 2.0
        expired_launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=old_time,
            expected_class="Code",
        )
        registry._launches[f"vscode-{old_time}"] = expired_launch
        registry._total_notifications += 1

        # Trigger cleanup (should log warning)
        await registry.add(PendingLaunch(
            app_name="new_app",
            project_name="new_project",
            project_directory=Path("/tmp"),
            launcher_pid=99999,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="NewClass",
        ))

        # Verify warning logged
        assert any("expired" in record.message.lower() for record in caplog.records)
        assert any("vscode" in record.message for record in caplog.records)
        assert any("nixos" in record.message for record in caplog.records)

        # Verify stats updated
        stats = registry.get_stats()
        assert stats.total_expired == 1


class TestLaunchRegistryStats:
    """Test LaunchRegistry statistics."""

    @pytest.mark.asyncio
    async def test_get_stats_returns_accurate_counters(self):
        """Test get_stats() returns accurate statistics."""
        registry = LaunchRegistry(timeout=5.0)

        # Add launches
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="Code",
        )
        await registry.add(launch1)

        await asyncio.sleep(0.01)
        launch2 = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=time.time(),
            expected_class="Alacritty",
        )
        await registry.add(launch2)

        # Match one window
        window = LaunchWindowInfo(
            window_id=1,
            window_class="Code",
            window_pid=100,
            workspace_number=2,
            timestamp=time.time(),
        )
        await registry.find_match(window)

        # Try to match non-existent class
        bad_window = LaunchWindowInfo(
            window_id=2,
            window_class="NonExistent",
            window_pid=101,
            workspace_number=5,
            timestamp=time.time(),
        )
        await registry.find_match(bad_window)

        # Check stats
        stats = registry.get_stats()
        assert stats.total_pending == 2
        assert stats.unmatched_pending == 1  # terminal still unmatched
        assert stats.total_notifications == 2
        assert stats.total_matched == 1
        assert stats.total_failed_correlation == 1
        assert stats.total_expired == 0

    @pytest.mark.asyncio
    async def test_get_stats_match_rate_calculation(self):
        """Test get_stats() calculates match_rate correctly."""
        registry = LaunchRegistry(timeout=5.0)

        # Add 3 launches
        for i in range(3):
            await asyncio.sleep(0.01)
            launch = PendingLaunch(
                app_name=f"app{i}",
                project_name=f"project{i}",
                project_directory=Path("/tmp"),
                launcher_pid=12340 + i,
                workspace_number=1 + i,
                timestamp=time.time(),
                expected_class=f"Class{i}",
            )
            await registry.add(launch)

        # Match 2 windows
        for i in range(2):
            window = LaunchWindowInfo(
                window_id=i,
                window_class=f"Class{i}",
                window_pid=100 + i,
                workspace_number=1 + i,
                timestamp=time.time(),
            )
            await registry.find_match(window)

        stats = registry.get_stats()
        assert stats.total_notifications == 3
        assert stats.total_matched == 2
        assert stats.match_rate == pytest.approx(66.67, abs=0.1)  # 2/3 * 100

    @pytest.mark.asyncio
    async def test_get_pending_launches_list(self):
        """Test get_pending_launches() returns correct data."""
        registry = LaunchRegistry(timeout=5.0)

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
        await registry.add(launch)

        launches = await registry.get_pending_launches(include_matched=False)

        assert len(launches) == 1
        assert launches[0]["app_name"] == "vscode"
        assert launches[0]["project_name"] == "nixos"
        assert launches[0]["expected_class"] == "Code"
        assert launches[0]["workspace_number"] == 2
        assert launches[0]["matched"] is False
        assert "age" in launches[0]
        assert "launch_id" in launches[0]

    @pytest.mark.asyncio
    async def test_get_pending_launches_filters_matched(self):
        """Test get_pending_launches() filters matched launches by default."""
        registry = LaunchRegistry(timeout=5.0)

        # Add launch
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
        await registry.add(launch)

        # Match it
        window = LaunchWindowInfo(
            window_id=1,
            window_class="Code",
            window_pid=100,
            workspace_number=2,
            timestamp=launch_time + 0.5,
        )
        await registry.find_match(window)

        # Should be filtered out by default
        launches_unmatched = await registry.get_pending_launches(include_matched=False)
        assert len(launches_unmatched) == 0

        # Should appear when include_matched=True
        launches_all = await registry.get_pending_launches(include_matched=True)
        assert len(launches_all) == 1
        assert launches_all[0]["matched"] is True
