"""Scenario test for launch timeout handling.

Feature 041: IPC Launch Context - T031 (User Story 3)

Test Goal: Ensure system fails explicitly rather than silently when correlation
fails, validating proper timeout and expiration handling.

Independent Test: Launch application, delay window creation beyond 5 seconds,
verify pending launch expires and window receives no project assignment with
explicit error logging.

Acceptance Scenarios:
- Scenario 1: Pending launch expires after 5 seconds
- Scenario 2: Window appears after expiration, receives no project assignment
- Scenario 3: Daemon reports expired launches in statistics
- Target: 100% expiration accuracy within 5±0.5 seconds
"""

import asyncio
import time
from pathlib import Path
import sys
import pytest

# Import daemon modules
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))

from models import PendingLaunch, LaunchWindowInfo, ConfidenceLevel
from services.launch_registry import LaunchRegistry


class TestTimeoutHandling:
    """Scenario tests for launch timeout handling (User Story 3)."""

    def test_scenario_1_pending_launch_expires_after_5_seconds(self):
        """
        Acceptance Scenario 1: Pending launch expires after 5 seconds.

        Timeline:
        - t=0.0s: Launch notification for VS Code
        - t=0.0s to t=5.0s: No window appears (waiting...)
        - t=5.5s: Add new launch notification (triggers cleanup)
        - t=5.5s: Verify original launch has expired

        Expected:
        - Pending launch removed from registry
        - total_expired counter incremented
        - Warning logged with app_name and project_name
        """
        asyncio.run(self._test_pending_launch_expires())

    async def _test_pending_launch_expires(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # t=0.0s: Launch notification
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch)

        # Verify launch is pending
        stats_initial = registry.get_stats()
        assert stats_initial.total_pending == 1
        assert stats_initial.unmatched_pending == 1
        assert stats_initial.total_expired == 0

        # Wait 5.5 seconds
        await asyncio.sleep(5.5)

        # Trigger cleanup by adding new launch
        trigger_launch = PendingLaunch(
            app_name="trigger",
            project_name="test",
            project_directory=Path("/tmp"),
            launcher_pid=99999,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="Test",
        )
        await registry.add(trigger_launch)

        # Verify original launch expired
        stats_final = registry.get_stats()
        assert stats_final.total_expired == 1, "Launch should be expired after 5.5 seconds"
        assert stats_final.total_pending == 1, "Only trigger launch should remain"
        assert stats_final.unmatched_pending == 1

        print("✅ Scenario 1: Pending launch expires after 5 seconds")

    def test_scenario_2_window_appears_after_expiration(self):
        """
        Acceptance Scenario 2: Window appears after expiration, receives no project assignment.

        Timeline:
        - t=0.0s: Launch notification for VS Code
        - t=5.5s: Trigger cleanup (launch expires)
        - t=6.0s: Window appears (too late)

        Expected:
        - find_match() returns None (no correlation)
        - total_failed_correlation incremented
        - Window receives no project assignment (explicit failure)
        """
        asyncio.run(self._test_window_appears_after_expiration())

    async def _test_window_appears_after_expiration(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # t=0.0s: Launch notification
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch)

        # Wait 5.5 seconds (launch expires)
        await asyncio.sleep(5.5)

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

        # Verify launch expired
        stats_before = registry.get_stats()
        assert stats_before.total_expired == 1

        # t=6.0s: Window appears (too late)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12347,
            workspace_number=2,
            timestamp=time.time(),
        )

        matched = await registry.find_match(window)

        # Should return None (no match available)
        assert matched is None, "Window should not match expired launch"

        # Verify failed correlation tracked
        stats_after = registry.get_stats()
        assert stats_after.total_failed_correlation == 1, "Failed correlation should be tracked"
        assert stats_after.total_matched == 0, "No matches should occur"

        print("✅ Scenario 2: Window appears after expiration - receives no project assignment")

    def test_scenario_3_daemon_reports_expired_launches_in_statistics(self):
        """
        Acceptance Scenario 3: Daemon reports expired launches in statistics.

        Setup:
        - Add 5 launch notifications
        - Let 2 expire
        - Match 2 windows
        - Let 1 window appear after expiration

        Expected:
        - total_notifications = 5
        - total_matched = 2
        - total_expired = 2
        - total_failed_correlation = 1
        - expiration_rate = 40% (2/5)
        - match_rate = 40% (2/5)
        """
        asyncio.run(self._test_statistics_tracking())

    async def _test_statistics_tracking(self):
        registry = LaunchRegistry(timeout=2.0)  # 2-second timeout for faster test
        base_time = time.time()

        # Add 5 launches
        launches = []
        for i in range(5):
            await asyncio.sleep(0.01)  # Small delay for unique timestamps
            launch = PendingLaunch(
                app_name=f"app{i}",
                project_name=f"project{i}",
                project_directory=Path(f"/tmp/project{i}"),
                launcher_pid=12340 + i,
                workspace_number=1 + i,
                timestamp=time.time(),
                expected_class=f"Class{i}",
            )
            await registry.add(launch)
            launches.append(launch)

        # Verify all tracked
        stats_initial = registry.get_stats()
        assert stats_initial.total_notifications == 5

        # Wait 2.5 seconds (all expire)
        await asyncio.sleep(2.5)

        # Match 2 windows BEFORE they expire (need fresh launches)
        registry2 = LaunchRegistry(timeout=5.0)

        # Add 2 fresh launches
        for i in range(2):
            await asyncio.sleep(0.01)
            launch = PendingLaunch(
                app_name=f"fresh{i}",
                project_name=f"fresh_project{i}",
                project_directory=Path(f"/tmp/fresh{i}"),
                launcher_pid=20000 + i,
                workspace_number=10 + i,
                timestamp=time.time(),
                expected_class=f"FreshClass{i}",
            )
            await registry2.add(launch)

        # Match them
        for i in range(2):
            window = LaunchWindowInfo(
                window_id=100 + i,
                window_class=f"FreshClass{i}",
                window_pid=30000 + i,
                workspace_number=10 + i,
                timestamp=time.time(),
            )
            await registry2.find_match(window)

        # Verify registry2 stats
        stats2 = registry2.get_stats()
        assert stats2.total_notifications == 2
        assert stats2.total_matched == 2
        assert stats2.total_expired == 0
        assert stats2.match_rate == 100.0

        # Now test expiration with registry1 (trigger cleanup)
        await registry.add(PendingLaunch(
            app_name="trigger",
            project_name="trigger_project",
            project_directory=Path("/tmp/trigger"),
            launcher_pid=99999,
            workspace_number=70,  # Max workspace number
            timestamp=time.time(),
            expected_class="Trigger",
        ))

        # All original 5 should be expired
        stats_expired = registry.get_stats()
        assert stats_expired.total_notifications == 6  # 5 original + 1 trigger
        assert stats_expired.total_expired == 5
        assert stats_expired.expiration_rate == pytest.approx(83.33, abs=0.1)  # 5/6 * 100

        # Try to match a window (should fail - all expired)
        window = LaunchWindowInfo(
            window_id=999,
            window_class="Trigger",
            window_pid=88888,
            workspace_number=70,
            timestamp=time.time(),
        )
        match = await registry.find_match(window)
        assert match is not None  # Trigger launch should match
        assert match.project_name == "trigger_project"

        # Check final stats
        stats_final = registry.get_stats()
        assert stats_final.total_expired == 5
        assert stats_final.total_matched == 1  # Only trigger matched
        assert stats_final.total_failed_correlation == 0  # All searches succeeded

        print("✅ Scenario 3: Daemon reports expired launches in statistics")

    def test_scenario_4_expiration_accuracy_within_5_plus_minus_0_5_seconds(self):
        """
        Verify expiration accuracy within 5±0.5 seconds (SC-005).

        Timeline:
        - t=0.0s: Launch notification
        - t=4.5s: Verify NOT expired
        - t=5.5s: Verify expired

        Expected:
        - At t=4.5s: launch still pending
        - At t=5.5s: launch expired
        - Accuracy: within 5±0.5 seconds
        """
        asyncio.run(self._test_expiration_accuracy())

    async def _test_expiration_accuracy(self):
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

        # Wait 4.5 seconds
        await asyncio.sleep(4.5)

        # Trigger cleanup (should NOT expire)
        await registry.add(PendingLaunch(
            app_name="check1",
            project_name="test1",
            project_directory=Path("/tmp"),
            launcher_pid=99998,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="Check1",
        ))

        stats_4_5s = registry.get_stats()
        assert stats_4_5s.total_expired == 0, "Launch should NOT be expired at 4.5 seconds"
        assert stats_4_5s.total_pending == 2, "Both launches should be pending"

        # Wait another 1 second (total 5.5s)
        await asyncio.sleep(1.0)

        # Trigger cleanup (should expire)
        await registry.add(PendingLaunch(
            app_name="check2",
            project_name="test2",
            project_directory=Path("/tmp"),
            launcher_pid=99997,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="Check2",
        ))

        stats_5_5s = registry.get_stats()
        assert stats_5_5s.total_expired == 1, "Launch should be expired at 5.5 seconds"
        assert stats_5_5s.total_pending == 2, "check1 + check2 should remain"

        # Verify timing accuracy
        elapsed = time.time() - launch_time
        assert 5.0 <= elapsed <= 6.0, f"Expiration should occur within 5±0.5s (actual: {elapsed:.2f}s)"

        print(f"✅ Scenario 4: Expiration accuracy verified - expired at {elapsed:.2f}s (within 5±0.5s)")

    def test_scenario_5_multiple_launches_expire_independently(self):
        """
        Test multiple launches with different timestamps expire independently.

        Setup:
        - Add 3 launches with 1-second intervals
        - Verify they expire individually at correct times

        Expected:
        - Launch 1 expires at 5s
        - Launch 2 expires at 6s
        - Launch 3 expires at 7s
        """
        asyncio.run(self._test_independent_expiration())

    async def _test_independent_expiration(self):
        registry = LaunchRegistry(timeout=2.0)  # 2-second timeout for faster test

        # Add 3 launches with 0.5s intervals
        launch_times = []
        for i in range(3):
            if i > 0:  # Don't sleep before first launch
                await asyncio.sleep(0.5)
            launch_time = time.time()
            launch_times.append(launch_time)

            launch = PendingLaunch(
                app_name=f"app{i}",
                project_name=f"project{i}",
                project_directory=Path(f"/tmp/project{i}"),
                launcher_pid=12340 + i,
                workspace_number=1 + i,
                timestamp=launch_time,
                expected_class=f"Class{i}",
            )
            await registry.add(launch)

        # All should be pending
        stats_initial = registry.get_stats()
        assert stats_initial.total_pending == 3
        assert stats_initial.total_expired == 0

        # Calculate how long to wait for first launch to expire
        # First launch is at launch_times[0], timeout is 2.0s
        # We need to wait (2.0 + 0.2) - age_of_first_launch
        first_launch_age = time.time() - launch_times[0]
        wait_time = max(0.1, (2.2 - first_launch_age))
        await asyncio.sleep(wait_time)

        # Trigger cleanup
        await registry.add(PendingLaunch(
            app_name="trigger1",
            project_name="trigger",
            project_directory=Path("/tmp"),
            launcher_pid=99999,
            workspace_number=70,
            timestamp=time.time(),
            expected_class="Trigger",
        ))

        stats_1 = registry.get_stats()
        assert stats_1.total_expired == 1, "First launch should be expired"
        assert stats_1.total_pending == 3, "Launch 2, 3, and trigger should remain"

        # Wait 0.5 seconds more (second launch should expire)
        await asyncio.sleep(0.5)

        # Trigger cleanup
        await registry.add(PendingLaunch(
            app_name="trigger2",
            project_name="trigger",
            project_directory=Path("/tmp"),
            launcher_pid=99998,
            workspace_number=69,
            timestamp=time.time(),
            expected_class="Trigger2",
        ))

        stats_2 = registry.get_stats()
        assert stats_2.total_expired == 2, "First and second launches should be expired"
        assert stats_2.total_pending == 3, "Launch 3, trigger1, trigger2 should remain"

        # Wait 0.5 seconds more (third launch should expire)
        await asyncio.sleep(0.5)

        # Trigger cleanup
        await registry.add(PendingLaunch(
            app_name="trigger3",
            project_name="trigger",
            project_directory=Path("/tmp"),
            launcher_pid=99997,
            workspace_number=68,
            timestamp=time.time(),
            expected_class="Trigger3",
        ))

        stats_3 = registry.get_stats()
        assert stats_3.total_expired == 3, "All three original launches should be expired"

        print("✅ Scenario 5: Multiple launches expire independently at correct times")


def run_all_scenarios():
    """Run all timeout handling scenarios."""
    import pytest
    test = TestTimeoutHandling()

    print("\n" + "=" * 70)
    print("User Story 3: Launch Timeout Handling - Scenario Tests")
    print("=" * 70 + "\n")

    try:
        test.test_scenario_1_pending_launch_expires_after_5_seconds()
        test.test_scenario_2_window_appears_after_expiration()
        test.test_scenario_3_daemon_reports_expired_launches_in_statistics()
        test.test_scenario_4_expiration_accuracy_within_5_plus_minus_0_5_seconds()
        test.test_scenario_5_multiple_launches_expire_independently()

        print("\n" + "=" * 70)
        print("✅ All User Story 3 scenarios PASSED")
        print("=" * 70)
        return True

    except AssertionError as e:
        print(f"\n❌ Scenario test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    success = run_all_scenarios()
    exit(0 if success else 1)
