"""Scenario test for rapid application launches.

Feature 041: IPC Launch Context - T026 (User Story 2)

Test Goal: Handle power-user workflows where multiple applications are launched
rapidly (<0.5 seconds apart) with correct disambiguation using correlation signals.

Independent Test: Launch VS Code for "nixos" and "stacks" within 0.2 seconds,
verify both windows receive correct project assignments with at least 95% accuracy.

Acceptance Scenarios:
- Scenario 1: Launch VS Code 0.2s apart, verify both matched correctly
- Scenario 2: Verify correlation uses timing, workspace, and class signals
- Scenario 3: Test out-of-order window appearance (first-match-wins)

Target: 95% correct assignment, MEDIUM or HIGH confidence
"""

import asyncio
import time
from pathlib import Path
import sys

# Import daemon modules
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))

from models import PendingLaunch, LaunchWindowInfo, ConfidenceLevel
from services.launch_registry import LaunchRegistry
from services.window_correlator import calculate_confidence


class TestRapidLaunches:
    """Scenario tests for rapid application launches (User Story 2)."""

    def test_scenario_1_rapid_launches_0_2s_apart(self):
        """
        Acceptance Scenario 1: Launch VS Code 0.2s apart, verify both matched correctly.

        Timeline:
        - t=0.0s: Launch VS Code for "nixos" project
        - t=0.2s: Launch VS Code for "stacks" project
        - t=0.5s: First VS Code window appears (for "stacks" - most recent)
        - t=0.7s: Second VS Code window appears (for "nixos" - older)

        Expected:
        - Both windows receive correct project assignment
        - Correlation uses timing and workspace signals
        - First-match-wins prevents double-matching
        """
        asyncio.run(self._test_rapid_launches_0_2s_apart())

    async def _test_rapid_launches_0_2s_apart(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # t=0.0s: Launch VS Code for "nixos" on workspace 2
        launch_nixos = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch_nixos)

        # t=0.2s: Launch VS Code for "stacks" on workspace 3
        launch_stacks = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 0.2,
            expected_class="Code",
        )
        await registry.add(launch_stacks)

        # Verify both launches are pending
        stats = registry.get_stats()
        assert stats.total_pending == 2
        assert stats.unmatched_pending == 2

        # t=0.5s: First VS Code window appears on workspace 3 (should match "stacks")
        window1 = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12347,
            workspace_number=3,  # Matches stacks workspace
            timestamp=base_time + 0.5,
        )

        matched1 = await registry.find_match(window1)
        assert matched1 is not None, "First window should match a pending launch"
        assert matched1.project_name == "stacks", "First window should match 'stacks' (better timing + workspace match)"

        # Calculate confidence for verification
        confidence1, signals1 = calculate_confidence(launch_stacks, window1)
        # stacks: class (0.5) + time <1s (0.3) + workspace match (0.2) = 1.0 (EXACT)
        assert confidence1 >= 0.8, f"Expected HIGH/EXACT confidence, got {confidence1}"

        # Verify matched flag set
        assert matched1.matched is True

        # t=0.7s: Second VS Code window appears on workspace 2 (should match "nixos")
        window2 = LaunchWindowInfo(
            window_id=94532735639729,
            window_class="Code",
            window_pid=12348,
            workspace_number=2,  # Matches nixos workspace
            timestamp=base_time + 0.7,
        )

        matched2 = await registry.find_match(window2)
        assert matched2 is not None, "Second window should match remaining pending launch"
        assert matched2.project_name == "nixos", "Second window should match 'nixos'"

        # Calculate confidence for verification
        confidence2, signals2 = calculate_confidence(launch_nixos, window2)
        # nixos: class (0.5) + time <1s (0.3) + workspace match (0.2) = 1.0 (EXACT)
        assert confidence2 >= 0.8, f"Expected HIGH/EXACT confidence, got {confidence2}"

        # Verify both launches now matched
        stats_final = registry.get_stats()
        assert stats_final.total_matched == 2
        assert stats_final.unmatched_pending == 0

        print("✅ Scenario 1: Rapid launches 0.2s apart - both matched correctly")

    def test_scenario_2_correlation_uses_multiple_signals(self):
        """
        Acceptance Scenario 2: Verify correlation uses timing, workspace, and class signals.

        Setup:
        - Launch two VS Code instances rapidly
        - One matches workspace, one doesn't
        - Verify workspace signal affects confidence scoring

        Expected:
        - Higher confidence for workspace match
        - Correct match even with similar timing
        """
        asyncio.run(self._test_correlation_multiple_signals())

    async def _test_correlation_multiple_signals(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # Launch 1: VS Code for "nixos" on workspace 2
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch1)

        # Launch 2: VS Code for "stacks" on workspace 3 (0.1s later)
        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 0.1,
            expected_class="Code",
        )
        await registry.add(launch2)

        # Window appears on workspace 3 (0.25s after base_time)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12347,
            workspace_number=3,  # Matches launch2
            timestamp=base_time + 0.25,
        )

        # Calculate confidence for both launches
        conf1, sig1 = calculate_confidence(launch1, window)
        conf2, sig2 = calculate_confidence(launch2, window)

        # launch1: class (0.5) + time <1s (0.3) = 0.8 (no workspace match)
        # launch2: class (0.5) + time <1s (0.3) + workspace (0.2) = 1.0 (workspace match)
        assert conf1 == 0.8, f"Expected launch1 confidence 0.8, got {conf1}"
        assert conf2 == 1.0, f"Expected launch2 confidence 1.0, got {conf2}"

        # find_match should select launch2 (higher confidence)
        matched = await registry.find_match(window)
        assert matched is not None
        assert matched.project_name == "stacks", "Should match launch2 due to workspace signal"

        print("✅ Scenario 2: Correlation uses timing, workspace, and class signals correctly")

    def test_scenario_3_out_of_order_window_appearance(self):
        """
        Acceptance Scenario 3: Test out-of-order window appearance (first-match-wins).

        Setup:
        - Launch app1 at t=0.0s (older)
        - Launch app2 at t=0.3s (newer)
        - Window for app2 appears first at t=0.4s
        - Window for app1 appears second at t=0.6s

        Expected:
        - app2 window matches app2 launch (first-match-wins)
        - app1 window matches app1 launch (remaining match)
        - No double-matching or mis-assignment
        """
        asyncio.run(self._test_out_of_order_appearance())

    async def _test_out_of_order_appearance(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # t=0.0s: Launch VS Code for "nixos" on workspace 2
        launch_nixos = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch_nixos)

        # t=0.3s: Launch VS Code for "stacks" on workspace 3
        launch_stacks = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 0.3,
            expected_class="Code",
        )
        await registry.add(launch_stacks)

        # t=0.4s: Window for stacks appears FIRST (on workspace 3)
        window_stacks = LaunchWindowInfo(
            window_id=1,
            window_class="Code",
            window_pid=12347,
            workspace_number=3,  # Matches stacks
            timestamp=base_time + 0.4,
        )

        matched_stacks = await registry.find_match(window_stacks)
        assert matched_stacks is not None
        assert matched_stacks.project_name == "stacks", "Stacks window should match stacks launch"
        assert matched_stacks.matched is True

        # t=0.6s: Window for nixos appears SECOND (on workspace 2)
        window_nixos = LaunchWindowInfo(
            window_id=2,
            window_class="Code",
            window_pid=12348,
            workspace_number=2,  # Matches nixos
            timestamp=base_time + 0.6,
        )

        matched_nixos = await registry.find_match(window_nixos)
        assert matched_nixos is not None
        assert matched_nixos.project_name == "nixos", "Nixos window should match nixos launch"
        assert matched_nixos.matched is True

        # Verify no double-matching
        assert launch_nixos.matched is True
        assert launch_stacks.matched is True

        # Verify final stats
        stats = registry.get_stats()
        assert stats.total_matched == 2
        assert stats.unmatched_pending == 0

        print("✅ Scenario 3: Out-of-order window appearance handled correctly (first-match-wins)")

    def test_scenario_4_accuracy_threshold_95_percent(self):
        """
        Verify 95% accuracy target for rapid launches.

        Run 20 rapid launch pairs, verify at least 19/20 (95%) match correctly.
        """
        asyncio.run(self._test_accuracy_threshold())

    async def _test_accuracy_threshold(self):
        """Test accuracy across multiple rapid launch scenarios."""
        total_tests = 20
        successful_matches = 0

        for i in range(total_tests):
            registry = LaunchRegistry(timeout=5.0)
            # Use fresh timestamps for each test iteration
            base_time = time.time()

            # Launch two apps 0.2s apart
            launch1 = PendingLaunch(
                app_name="vscode",
                project_name="project_a",
                project_directory=Path("/tmp/project_a"),
                launcher_pid=10000 + i * 2,
                workspace_number=2,
                timestamp=base_time,
                expected_class="Code",
            )
            await registry.add(launch1)

            launch2 = PendingLaunch(
                app_name="vscode",
                project_name="project_b",
                project_directory=Path("/tmp/project_b"),
                launcher_pid=10000 + i * 2 + 1,
                workspace_number=3,
                timestamp=base_time + 0.2,
                expected_class="Code",
            )
            await registry.add(launch2)

            # Windows appear in order (0.3s, 0.5s)
            # Use small delays to simulate realistic timing
            window1 = LaunchWindowInfo(
                window_id=100000 + i * 2,
                window_class="Code",
                window_pid=20000 + i * 2,
                workspace_number=3,  # Matches launch2
                timestamp=base_time + 0.3,
            )

            window2 = LaunchWindowInfo(
                window_id=100000 + i * 2 + 1,
                window_class="Code",
                window_pid=20000 + i * 2 + 1,
                workspace_number=2,  # Matches launch1
                timestamp=base_time + 0.5,
            )

            # Match windows
            matched1 = await registry.find_match(window1)
            matched2 = await registry.find_match(window2)

            # Check if both matched correctly
            if (
                matched1 is not None
                and matched1.project_name == "project_b"
                and matched2 is not None
                and matched2.project_name == "project_a"
            ):
                successful_matches += 2  # Both correct

        accuracy = successful_matches / (total_tests * 2) * 100
        assert accuracy >= 95.0, f"Expected ≥95% accuracy, got {accuracy:.1f}%"

        print(f"✅ Scenario 4: Accuracy threshold met - {accuracy:.1f}% ({successful_matches}/{total_tests * 2})")

    def test_scenario_5_extremely_rapid_0_05s_apart(self):
        """
        Stress test: Launch two apps 0.05s apart (50ms).

        Even with extremely rapid launches, correlation should work correctly
        using timing precision and workspace signals.
        """
        asyncio.run(self._test_extremely_rapid())

    async def _test_extremely_rapid(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # Launch 1: t=0.0s
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch1)

        # Launch 2: t=0.05s (50ms later)
        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 0.05,
            expected_class="Code",
        )
        await registry.add(launch2)

        # Window 1 appears at t=0.1s on workspace 3 (matches launch2)
        window1 = LaunchWindowInfo(
            window_id=1,
            window_class="Code",
            window_pid=100,
            workspace_number=3,
            timestamp=base_time + 0.1,
        )

        matched1 = await registry.find_match(window1)
        assert matched1 is not None
        # Should match launch2 due to workspace match + closer timing
        # launch1: 0.1s delta, no workspace = 0.5 + 0.3 = 0.8
        # launch2: 0.05s delta, workspace match = 0.5 + 0.3 + 0.2 = 1.0
        assert matched1.project_name == "stacks"

        # Window 2 appears at t=0.15s on workspace 2 (matches launch1)
        window2 = LaunchWindowInfo(
            window_id=2,
            window_class="Code",
            window_pid=101,
            workspace_number=2,
            timestamp=base_time + 0.15,
        )

        matched2 = await registry.find_match(window2)
        assert matched2 is not None
        assert matched2.project_name == "nixos"

        print("✅ Scenario 5: Extremely rapid launches (50ms apart) handled correctly")


def run_all_scenarios():
    """Run all rapid launch scenarios."""
    test = TestRapidLaunches()

    print("\n" + "=" * 70)
    print("User Story 2: Rapid Application Launches - Scenario Tests")
    print("=" * 70 + "\n")

    try:
        test.test_scenario_1_rapid_launches_0_2s_apart()
        test.test_scenario_2_correlation_uses_multiple_signals()
        test.test_scenario_3_out_of_order_window_appearance()
        test.test_scenario_4_accuracy_threshold_95_percent()
        test.test_scenario_5_extremely_rapid_0_05s_apart()

        print("\n" + "=" * 70)
        print("✅ All User Story 2 scenarios PASSED")
        print("=" * 70)
        return True

    except AssertionError as e:
        print(f"\n❌ Scenario test failed: {e}")
        return False


if __name__ == "__main__":
    success = run_all_scenarios()
    exit(0 if success else 1)
