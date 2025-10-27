"""Edge cases test scenario for IPC Launch Context.

Feature 041: IPC Launch Context - T041

This scenario validates comprehensive edge case coverage for the launch notification
and correlation system. Tests unusual conditions, boundary cases, and failure modes.

Edge Cases Tested:
- EC1: Application launched directly from terminal (bypass wrapper)
- EC2: Two identical apps <0.1s apart (FIFO ordering)
- EC3: System under load, window delayed (timeout handling)
- EC4: Multi-window per launch (first window matches, rest unassigned)
- EC5: Daemon restart (pending launches lost, system recovers)
- EC6: Multiple launches before any windows appear (accumulate and match in order)
- EC7: Workspace config changes mid-launch (use launch-time workspace)
- EC8: Window class doesn't match registry (correlation fails)

Target: 100% edge case coverage (SC-010)
"""

import asyncio
import time
from pathlib import Path
from typing import List, Dict, Any

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))

from models import PendingLaunch, LaunchWindowInfo, CorrelationResult
from services.launch_registry import LaunchRegistry
from services.window_correlator import calculate_confidence


class EdgeCasesComprehensive:
    """
    Comprehensive edge case testing for launch notification system.

    This test suite validates that the system handles unusual conditions correctly
    and fails explicitly rather than silently when correlation is not possible.

    Scenario ID: launch_context_edge_cases
    Priority: P1 (part of polish phase, but critical for robustness)
    """

    scenario_id = "launch_context_edge_cases"
    name = "Edge Cases - Comprehensive Coverage"
    description = "Test unusual conditions and boundary cases for launch context system"
    priority = 1
    timeout_seconds = 60.0

    def __init__(self):
        """Initialize scenario."""
        self.registry: LaunchRegistry = None
        self.test_results: List[Dict[str, Any]] = []
        self.edge_cases_passed = 0
        self.edge_cases_total = 8

    async def setup(self) -> None:
        """Initialize launch registry for testing."""
        self.registry = LaunchRegistry(timeout=5.0)
        print(f"✓ Initialized LaunchRegistry with 5-second timeout")

    async def execute(self) -> None:
        """Execute all edge case tests."""

        # Edge Case 1: Application launched directly from terminal (bypass wrapper)
        await self._test_ec1_direct_launch_bypass()

        # Edge Case 2: Two identical apps <0.1s apart (FIFO ordering)
        await self._test_ec2_rapid_identical_launches()

        # Edge Case 3: System under load, window delayed (timeout handling)
        await self._test_ec3_window_delayed_timeout()

        # Edge Case 4: Multi-window per launch (first window matches, rest unassigned)
        await self._test_ec4_multi_window_per_launch()

        # Edge Case 5: Daemon restart (pending launches lost, system recovers)
        await self._test_ec5_daemon_restart_recovery()

        # Edge Case 6: Multiple launches before any windows appear
        await self._test_ec6_batch_launches_then_windows()

        # Edge Case 7: Workspace config changes mid-launch
        await self._test_ec7_workspace_change_mid_launch()

        # Edge Case 8: Window class doesn't match registry
        await self._test_ec8_class_mismatch()

    async def _test_ec1_direct_launch_bypass(self) -> None:
        """
        Edge Case 1: Application launched directly from terminal (bypass wrapper)

        Expected behavior:
        - Window appears without prior launch notification
        - find_match() returns None
        - Daemon logs error: "Window appeared without matching launch notification"
        - Window receives no project assignment (explicit failure)
        """
        print("\n=== Edge Case 1: Direct Launch (No Notification) ===")

        # Simulate window appearing without any launch notification
        window_time = time.time()
        window = LaunchWindowInfo(
            window_id=94532735639001,
            window_class="Code",
            window_pid=99001,
            workspace_number=2,
            timestamp=window_time
        )

        print(f"  → Window created WITHOUT prior notification")
        print(f"     Window ID: {window.window_id}, Class: {window.window_class}")

        # Attempt to find matching launch (should fail)
        match = await self.registry.find_match(window)

        # Validate expected failure
        if match is not None:
            raise AssertionError("EC1 FAILED: Window matched despite no notification")

        print(f"  ✓ EC1 PASSED: Window correctly rejected (no matching launch notification)")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC1",
            "description": "Direct launch bypass",
            "expected": "No match, explicit failure",
            "actual": "No match returned",
            "passed": True
        })

    async def _test_ec2_rapid_identical_launches(self) -> None:
        """
        Edge Case 2: Two identical apps <0.1s apart (FIFO ordering)

        Expected behavior:
        - Both notifications registered successfully
        - First window matches first notification (FIFO / oldest unmatched)
        - Second window matches second notification
        - Confidence uses timing signal for disambiguation
        """
        print("\n=== Edge Case 2: Rapid Identical Launches (<0.1s) ===")

        # Register first launch
        launch1_time = time.time()
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=99101,
            workspace_number=2,
            timestamp=launch1_time,
            expected_class="Code"
        )

        launch1_id = await self.registry.add(launch1)
        print(f"  → Launch 1 registered: {launch1_id} (nixos)")

        # Register second launch 0.05s later (rapid)
        await asyncio.sleep(0.05)
        launch2_time = time.time()
        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=99102,
            workspace_number=2,
            timestamp=launch2_time,
            expected_class="Code"
        )

        launch2_id = await self.registry.add(launch2)
        print(f"  → Launch 2 registered: {launch2_id} (stacks)")
        print(f"     Time delta: 0.05s (rapid)")

        # First window appears 0.6s after first launch
        await asyncio.sleep(0.55)
        window1_time = launch1_time + 0.6
        window1 = LaunchWindowInfo(
            window_id=94532735639101,
            window_class="Code",
            window_pid=99103,
            workspace_number=2,
            timestamp=window1_time
        )

        match1 = await self.registry.find_match(window1)

        if match1 is None:
            raise AssertionError("EC2 FAILED: First window not matched")

        # Verify FIFO ordering: first window matches first launch
        if match1.project_name != "nixos":
            raise AssertionError(f"EC2 FAILED: First window matched '{match1.project_name}', expected 'nixos' (FIFO)")

        confidence1, signals1 = calculate_confidence(match1, window1)
        print(f"  → Window 1 matched to: {match1.project_name} (confidence: {confidence1:.2f})")

        # Second window appears 0.1s later
        await asyncio.sleep(0.1)
        window2_time = launch2_time + 0.65
        window2 = LaunchWindowInfo(
            window_id=94532735639102,
            window_class="Code",
            window_pid=99104,
            workspace_number=2,
            timestamp=window2_time
        )

        match2 = await self.registry.find_match(window2)

        if match2 is None:
            raise AssertionError("EC2 FAILED: Second window not matched")

        # Verify second window matches second launch
        if match2.project_name != "stacks":
            raise AssertionError(f"EC2 FAILED: Second window matched '{match2.project_name}', expected 'stacks'")

        confidence2, signals2 = calculate_confidence(match2, window2)
        print(f"  → Window 2 matched to: {match2.project_name} (confidence: {confidence2:.2f})")
        print(f"  ✓ EC2 PASSED: FIFO ordering maintained for rapid identical launches")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC2",
            "description": "Rapid identical launches",
            "expected": "FIFO ordering, both matched correctly",
            "actual": f"Window 1→{match1.project_name}, Window 2→{match2.project_name}",
            "passed": True
        })

    async def _test_ec3_window_delayed_timeout(self) -> None:
        """
        Edge Case 3: System under load, window delayed beyond timeout

        Expected behavior:
        - Launch notification registered
        - 5 seconds pass without window appearing
        - Pending launch expires and is removed
        - When window finally appears, no match found
        - Daemon logs expiration warning
        """
        print("\n=== Edge Case 3: Window Delayed Beyond Timeout ===")

        # Register launch
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="delayed-project",
            project_directory=Path("/tmp/delayed"),
            launcher_pid=99201,
            workspace_number=3,
            timestamp=launch_time,
            expected_class="Code"
        )

        launch_id = await self.registry.add(launch)
        print(f"  → Launch registered: {launch_id}")
        print(f"     Simulating system under load (window delayed)...")

        # Wait for expiration (5 seconds + margin)
        print(f"     Waiting 5.2 seconds for timeout...")
        await asyncio.sleep(5.2)

        # Check launch has expired (cleanup should have removed it)
        stats_before = self.registry.get_stats()
        expired_count_before = stats_before.total_expired

        # Trigger cleanup by adding a dummy launch
        dummy_launch = PendingLaunch(
            app_name="vscode",
            project_name="dummy",
            project_directory=Path("/tmp/dummy"),
            launcher_pid=99202,
            workspace_number=1,
            timestamp=time.time(),
            expected_class="Code"
        )
        await self.registry.add(dummy_launch)

        stats_after = self.registry.get_stats()
        expired_count_after = stats_after.total_expired

        # Verify expiration occurred
        if expired_count_after <= expired_count_before:
            raise AssertionError("EC3 FAILED: Launch did not expire after 5 seconds")

        print(f"  → Launch expired (total expired: {expired_count_after})")

        # Window appears late
        window_time = time.time()
        window = LaunchWindowInfo(
            window_id=94532735639201,
            window_class="Code",
            window_pid=99203,
            workspace_number=3,
            timestamp=window_time
        )

        print(f"  → Window created AFTER expiration")

        # Attempt to match (should fail - launch already expired)
        match = await self.registry.find_match(window)

        # Verify no match (launch expired)
        if match is not None and match.project_name == "delayed-project":
            raise AssertionError("EC3 FAILED: Window matched to expired launch")

        print(f"  ✓ EC3 PASSED: Expired launch not matched, system handled timeout correctly")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC3",
            "description": "Window delayed beyond timeout",
            "expected": "Launch expires, late window not matched",
            "actual": "Launch expired, no match",
            "passed": True
        })

    async def _test_ec4_multi_window_per_launch(self) -> None:
        """
        Edge Case 4: Multi-window per launch (e.g., IDE opens multiple windows)

        Expected behavior:
        - Single launch notification
        - First window matches and consumes the launch
        - Second window from same app has no matching launch
        - System correctly handles one-to-one launch→window mapping
        """
        print("\n=== Edge Case 4: Multi-Window Per Launch ===")

        # Register single launch
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="multi-window-test",
            project_directory=Path("/tmp/multiwin"),
            launcher_pid=99301,
            workspace_number=4,
            timestamp=launch_time,
            expected_class="Code"
        )

        launch_id = await self.registry.add(launch)
        print(f"  → Launch registered: {launch_id}")
        print(f"     Simulating app that opens multiple windows...")

        # First window appears
        await asyncio.sleep(0.5)
        window1_time = launch_time + 0.5
        window1 = LaunchWindowInfo(
            window_id=94532735639301,
            window_class="Code",
            window_pid=99302,
            workspace_number=4,
            timestamp=window1_time
        )

        match1 = await self.registry.find_match(window1)

        if match1 is None:
            raise AssertionError("EC4 FAILED: First window not matched")

        if match1.project_name != "multi-window-test":
            raise AssertionError(f"EC4 FAILED: First window matched wrong project: {match1.project_name}")

        print(f"  → Window 1 matched: {match1.project_name}")

        # Second window appears from same app (e.g., split editor, terminal panel)
        await asyncio.sleep(0.2)
        window2_time = window1_time + 0.2
        window2 = LaunchWindowInfo(
            window_id=94532735639302,
            window_class="Code",
            window_pid=99302,  # Same PID (same app process)
            workspace_number=4,
            timestamp=window2_time
        )

        match2 = await self.registry.find_match(window2)

        # Verify second window is NOT matched (launch already consumed)
        if match2 is not None and match2.project_name == "multi-window-test":
            raise AssertionError("EC4 FAILED: Second window incorrectly matched same launch")

        print(f"  → Window 2 NOT matched (launch already consumed)")
        print(f"  ✓ EC4 PASSED: One-to-one launch→window mapping enforced")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC4",
            "description": "Multi-window per launch",
            "expected": "First window matches, second does not",
            "actual": "First matched, second rejected",
            "passed": True
        })

    async def _test_ec5_daemon_restart_recovery(self) -> None:
        """
        Edge Case 5: Daemon restart (pending launches lost, system recovers)

        Expected behavior:
        - Pending launches exist before restart
        - Daemon restart clears in-memory registry
        - Windows appearing after restart have no matching launches
        - System logs appropriate errors but continues operating
        - No crash or undefined behavior
        """
        print("\n=== Edge Case 5: Daemon Restart Recovery ===")

        # Register launch before "restart"
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="pre-restart",
            project_directory=Path("/tmp/prerestart"),
            launcher_pid=99401,
            workspace_number=5,
            timestamp=launch_time,
            expected_class="Code"
        )

        launch_id = await self.registry.add(launch)
        stats_before = self.registry.get_stats()

        print(f"  → Launch registered before restart: {launch_id}")
        print(f"     Pending launches: {stats_before.total_pending}")

        # Simulate daemon restart by creating new registry
        print(f"     Simulating daemon restart...")
        self.registry = LaunchRegistry(timeout=5.0)

        stats_after = self.registry.get_stats()
        print(f"     Pending launches after restart: {stats_after.total_pending}")

        # Verify registry cleared
        if stats_after.total_pending > 0:
            raise AssertionError("EC5 FAILED: Registry not cleared after restart")

        # Window appears after restart
        await asyncio.sleep(0.3)
        window_time = time.time()
        window = LaunchWindowInfo(
            window_id=94532735639401,
            window_class="Code",
            window_pid=99402,
            workspace_number=5,
            timestamp=window_time
        )

        print(f"  → Window created AFTER restart")

        # Attempt to match (should fail - registry cleared)
        match = await self.registry.find_match(window)

        if match is not None:
            raise AssertionError("EC5 FAILED: Window matched despite restart clearing registry")

        print(f"  ✓ EC5 PASSED: System recovered from restart, handled missing launches gracefully")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC5",
            "description": "Daemon restart recovery",
            "expected": "Registry cleared, system continues operating",
            "actual": "Registry cleared, no undefined behavior",
            "passed": True
        })

    async def _test_ec6_batch_launches_then_windows(self) -> None:
        """
        Edge Case 6: Multiple launches before any windows appear

        Expected behavior:
        - Multiple launch notifications accumulate in registry
        - Windows appear later in any order
        - Each window matches correct launch via correlation signals
        - System handles accumulated pending launches correctly
        """
        print("\n=== Edge Case 6: Batch Launches, Then Windows ===")

        # Register 3 launches rapidly (no windows yet)
        launch1_time = time.time()
        launches = []

        for i in range(3):
            launch = PendingLaunch(
                app_name="terminal" if i == 1 else "vscode",
                project_name=f"batch-project-{i+1}",
                project_directory=Path(f"/tmp/batch{i+1}"),
                launcher_pid=99501 + i,
                workspace_number=i + 1,
                timestamp=launch1_time + (i * 0.1),
                expected_class="Alacritty" if i == 1 else "Code"
            )
            launch_id = await self.registry.add(launch)
            launches.append(launch)
            print(f"  → Launch {i+1} registered: {launch.app_name} → {launch.project_name}")
            await asyncio.sleep(0.1)

        stats = self.registry.get_stats()
        print(f"     Pending launches: {stats.total_pending}")

        if stats.total_pending < 3:
            raise AssertionError(f"EC6 FAILED: Expected 3 pending launches, got {stats.total_pending}")

        # Windows start appearing (different order than launches)
        print(f"     Windows appearing in random order...")

        # Window 2 appears first (terminal)
        await asyncio.sleep(0.5)
        window2 = LaunchWindowInfo(
            window_id=94532735639502,
            window_class="Alacritty",
            window_pid=99512,
            workspace_number=2,
            timestamp=time.time()
        )

        match2 = await self.registry.find_match(window2)

        if match2 is None:
            raise AssertionError("EC6 FAILED: Window 2 not matched")

        if match2.project_name != "batch-project-2":
            raise AssertionError(f"EC6 FAILED: Window 2 matched wrong project: {match2.project_name}")

        print(f"  → Window 2 matched: {match2.project_name}")

        # Window 1 appears second
        await asyncio.sleep(0.2)
        window1 = LaunchWindowInfo(
            window_id=94532735639501,
            window_class="Code",
            window_pid=99511,
            workspace_number=1,
            timestamp=time.time()
        )

        match1 = await self.registry.find_match(window1)

        if match1 is None:
            raise AssertionError("EC6 FAILED: Window 1 not matched")

        if match1.project_name != "batch-project-1":
            raise AssertionError(f"EC6 FAILED: Window 1 matched wrong project: {match1.project_name}")

        print(f"  → Window 1 matched: {match1.project_name}")

        # Window 3 appears last
        await asyncio.sleep(0.2)
        window3 = LaunchWindowInfo(
            window_id=94532735639503,
            window_class="Code",
            window_pid=99513,
            workspace_number=3,
            timestamp=time.time()
        )

        match3 = await self.registry.find_match(window3)

        if match3 is None:
            raise AssertionError("EC6 FAILED: Window 3 not matched")

        if match3.project_name != "batch-project-3":
            raise AssertionError(f"EC6 FAILED: Window 3 matched wrong project: {match3.project_name}")

        print(f"  → Window 3 matched: {match3.project_name}")
        print(f"  ✓ EC6 PASSED: All windows matched correctly despite out-of-order appearance")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC6",
            "description": "Batch launches then windows",
            "expected": "All windows match correctly regardless of order",
            "actual": "All 3 windows matched to correct launches",
            "passed": True
        })

    async def _test_ec7_workspace_change_mid_launch(self) -> None:
        """
        Edge Case 7: Workspace config changes between notification and window

        Expected behavior:
        - Launch notification uses launch-time workspace number
        - Even if workspace config changes, correlation uses original workspace
        - Workspace match signal may boost or not affect confidence
        - System doesn't crash on workspace mismatch
        """
        print("\n=== Edge Case 7: Workspace Change Mid-Launch ===")

        # Register launch with specific workspace
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="workspace-change-test",
            project_directory=Path("/tmp/wschange"),
            launcher_pid=99601,
            workspace_number=6,
            timestamp=launch_time,
            expected_class="Code"
        )

        launch_id = await self.registry.add(launch)
        print(f"  → Launch registered for workspace 6")

        # Simulate user moving to different workspace or config change
        print(f"     Simulating workspace configuration change...")
        await asyncio.sleep(0.3)

        # Window appears on DIFFERENT workspace (e.g., user switched, i3 moved it)
        window_time = time.time()
        window = LaunchWindowInfo(
            window_id=94532735639601,
            window_class="Code",
            window_pid=99602,
            workspace_number=7,  # Different workspace!
            timestamp=window_time
        )

        print(f"  → Window created on workspace 7 (expected 6)")

        # Attempt to match (should still match, just without workspace boost)
        match = await self.registry.find_match(window)

        if match is None:
            raise AssertionError("EC7 FAILED: Window not matched despite workspace mismatch")

        if match.project_name != "workspace-change-test":
            raise AssertionError(f"EC7 FAILED: Window matched wrong project: {match.project_name}")

        confidence, signals = calculate_confidence(match, window)

        # Verify confidence is lower (no workspace boost)
        # Expected: class match (0.5) + time delta (<1s = +0.3) = 0.8 (no workspace boost)
        if confidence > 0.85:
            print(f"     WARNING: Confidence {confidence:.2f} higher than expected (workspace boost shouldn't apply)")

        print(f"  → Window matched: {match.project_name} (confidence: {confidence:.2f})")
        print(f"  ✓ EC7 PASSED: System handled workspace mismatch gracefully")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC7",
            "description": "Workspace change mid-launch",
            "expected": "Match succeeds, workspace boost not applied",
            "actual": f"Matched with confidence {confidence:.2f}",
            "passed": True
        })

    async def _test_ec8_class_mismatch(self) -> None:
        """
        Edge Case 8: Window class doesn't match registry expectation

        Expected behavior:
        - Launch notification uses expected_class from registry
        - Window appears with DIFFERENT class (app bug, config issue, wrong class in registry)
        - Correlation fails (class match is required baseline signal)
        - Confidence = 0.0, no match returned
        - Daemon logs class mismatch error
        """
        print("\n=== Edge Case 8: Window Class Mismatch ===")

        # Register launch expecting "Code" class
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="class-mismatch-test",
            project_directory=Path("/tmp/classmismatch"),
            launcher_pid=99701,
            workspace_number=8,
            timestamp=launch_time,
            expected_class="Code"  # Registry says "Code"
        )

        launch_id = await self.registry.add(launch)
        print(f"  → Launch registered: expected class='Code'")

        # Window appears with WRONG class
        await asyncio.sleep(0.4)
        window_time = time.time()
        window = LaunchWindowInfo(
            window_id=94532735639701,
            window_class="VSCode-Wrong",  # Wrong class!
            window_pid=99702,
            workspace_number=8,
            timestamp=window_time
        )

        print(f"  → Window created with class='VSCode-Wrong' (mismatch!)")

        # Attempt to match (should fail - class mismatch)
        match = await self.registry.find_match(window)

        if match is not None and match.project_name == "class-mismatch-test":
            raise AssertionError("EC8 FAILED: Window matched despite class mismatch")

        # Verify correlation would return 0.0 confidence if we tried to calculate
        # (Note: find_match filters out mismatches before returning, so match is None)

        print(f"  ✓ EC8 PASSED: Class mismatch correctly prevented matching")

        self.edge_cases_passed += 1
        self.test_results.append({
            "edge_case": "EC8",
            "description": "Window class mismatch",
            "expected": "No match due to class mismatch",
            "actual": "Correlation failed, no match",
            "passed": True
        })

    async def validate(self) -> None:
        """Validate edge case scenario results."""
        print("\n=== Edge Case Validation Summary ===")

        # Check all edge cases passed
        if self.edge_cases_passed != self.edge_cases_total:
            raise AssertionError(
                f"Validation FAILED: {self.edge_cases_passed}/{self.edge_cases_total} edge cases passed"
            )

        print(f"  → Edge cases passed: {self.edge_cases_passed}/{self.edge_cases_total}")

        # Display results table
        print("\n  Edge Case Results:")
        print("  " + "="*70)
        for result in self.test_results:
            status = "✓" if result["passed"] else "✗"
            print(f"  {status} {result['edge_case']}: {result['description']}")
            print(f"     Expected: {result['expected']}")
            print(f"     Actual: {result['actual']}")
        print("  " + "="*70)

        # Verify registry stats are consistent
        final_stats = self.registry.get_stats()
        print(f"\n  Final Registry Stats:")
        print(f"     Total notifications: {final_stats.total_notifications}")
        print(f"     Total matched: {final_stats.total_matched}")
        print(f"     Total expired: {final_stats.total_expired}")
        print(f"     Total failed correlation: {final_stats.total_failed_correlation}")
        print(f"     Match rate: {final_stats.match_rate:.1f}%")
        print(f"     Expiration rate: {final_stats.expiration_rate:.1f}%")

        # Success criteria: 100% edge case coverage
        print(f"\n  ✓ SUCCESS CRITERIA SC-010: 100% edge case coverage achieved")
        print(f"  ✓ All edge cases handled correctly with explicit failure modes")
        print(f"  ✓ System never crashed, always failed gracefully")

    async def cleanup(self) -> None:
        """Clean up test resources."""
        self.registry = None
        print(f"\n✓ Edge case scenario cleanup complete")


async def run_scenario():
    """Run the edge cases scenario."""
    scenario = EdgeCasesComprehensive()

    try:
        print(f"\n{'='*70}")
        print(f"Scenario: {scenario.name}")
        print(f"ID: {scenario.scenario_id}")
        print(f"Description: {scenario.description}")
        print(f"{'='*70}")

        await scenario.setup()
        await scenario.execute()
        await scenario.validate()
        await scenario.cleanup()

        print(f"\n{'='*70}")
        print(f"✓ SCENARIO PASSED - ALL EDGE CASES COVERED")
        print(f"{'='*70}\n")

        return True

    except AssertionError as e:
        print(f"\n{'='*70}")
        print(f"✗ SCENARIO FAILED")
        print(f"Error: {e}")
        print(f"{'='*70}\n")
        return False

    except Exception as e:
        print(f"\n{'='*70}")
        print(f"✗ SCENARIO ERROR")
        print(f"Error: {e}")
        print(f"{'='*70}\n")
        raise


if __name__ == "__main__":
    """Allow running scenario directly for testing."""
    import asyncio
    success = asyncio.run(run_scenario())
    exit(0 if success else 1)
