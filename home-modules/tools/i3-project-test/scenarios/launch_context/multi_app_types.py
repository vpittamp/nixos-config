"""Scenario test for multiple application types correlation.

Feature 041: IPC Launch Context - T035 (User Story 4)

Test Goal: Validate that correlation works across different application types
(VS Code, terminal, browser) using application class matching, regardless of timing.

Independent Test: Launch VS Code for "nixos" and Alacritty terminal for "stacks"
within 0.1 seconds, verify each window matches its correct project based on
application class.

Acceptance Scenarios:
- Scenario 1: Launch VS Code + terminal simultaneously, verify correct class matching
- Scenario 2: Verify terminal only matches terminal launches (not VS Code)
- Scenario 3: Test windows appearing in any order still match correctly
- Target: 100% class-based disambiguation
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


class TestMultiAppTypes:
    """Scenario tests for multiple application types (User Story 4)."""

    def test_scenario_1_vscode_and_terminal_simultaneous(self):
        """
        Acceptance Scenario 1: Launch VS Code + terminal simultaneously, verify correct class matching.

        Timeline:
        - t=0.0s: Launch VS Code for "nixos" project
        - t=0.1s: Launch Alacritty terminal for "stacks" project
        - t=0.5s: VS Code window appears (class="Code")
        - t=0.6s: Terminal window appears (class="Alacritty")

        Expected:
        - VS Code window matches nixos launch (class match)
        - Terminal window matches stacks launch (class match)
        - No cross-matching between different app types
        """
        asyncio.run(self._test_vscode_and_terminal_simultaneous())

    async def _test_vscode_and_terminal_simultaneous(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # t=0.0s: Launch VS Code for "nixos"
        launch_vscode = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch_vscode)

        # t=0.1s: Launch terminal for "stacks"
        launch_terminal = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 0.1,
            expected_class="Alacritty",
        )
        await registry.add(launch_terminal)

        # Verify both launches are pending
        stats = registry.get_stats()
        assert stats.total_pending == 2
        assert stats.unmatched_pending == 2

        # t=0.5s: VS Code window appears (class="Code")
        window_vscode = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",  # Matches vscode expected_class
            window_pid=12347,
            workspace_number=2,
            timestamp=base_time + 0.5,
        )

        matched_vscode = await registry.find_match(window_vscode)
        assert matched_vscode is not None, "VS Code window should match a pending launch"
        assert matched_vscode.project_name == "nixos", "VS Code should match nixos launch (class=Code)"
        assert matched_vscode.app_name == "vscode"

        # Calculate confidence for verification
        confidence_vscode, signals_vscode = calculate_confidence(launch_vscode, window_vscode)
        # Code: class (0.5) + time <1s (0.3) + workspace match (0.2) = 1.0 (EXACT)
        assert confidence_vscode >= 0.8, f"Expected HIGH/EXACT confidence, got {confidence_vscode}"

        # t=0.6s: Terminal window appears (class="Alacritty")
        window_terminal = LaunchWindowInfo(
            window_id=94532735639729,
            window_class="Alacritty",  # Matches terminal expected_class
            window_pid=12348,
            workspace_number=3,
            timestamp=base_time + 0.6,
        )

        matched_terminal = await registry.find_match(window_terminal)
        assert matched_terminal is not None, "Terminal window should match remaining pending launch"
        assert matched_terminal.project_name == "stacks", "Terminal should match stacks launch (class=Alacritty)"
        assert matched_terminal.app_name == "terminal"

        # Calculate confidence for verification
        confidence_terminal, signals_terminal = calculate_confidence(launch_terminal, window_terminal)
        # Alacritty: class (0.5) + time <1s (0.3) + workspace match (0.2) = 1.0 (EXACT)
        assert confidence_terminal >= 0.8, f"Expected HIGH/EXACT confidence, got {confidence_terminal}"

        # Verify both launches now matched
        stats_final = registry.get_stats()
        assert stats_final.total_matched == 2
        assert stats_final.unmatched_pending == 0

        print("✅ Scenario 1: VS Code + terminal simultaneous - both matched correctly via class")

    def test_scenario_2_terminal_only_matches_terminal_launches(self):
        """
        Acceptance Scenario 2: Verify terminal only matches terminal launches (not VS Code).

        Setup:
        - Launch VS Code for "nixos" (expected_class="Code")
        - Launch terminal for "stacks" (expected_class="Alacritty")
        - Terminal window appears (class="Alacritty")

        Expected:
        - Terminal window matches stacks launch (class="Alacritty")
        - Terminal window does NOT match nixos launch (class mismatch: "Code" != "Alacritty")
        - Confidence for wrong class is 0.0
        """
        asyncio.run(self._test_terminal_only_matches_terminal())

    async def _test_terminal_only_matches_terminal(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # Launch VS Code for "nixos"
        launch_vscode = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch_vscode)

        # Launch terminal for "stacks"
        launch_terminal = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 0.1,
            expected_class="Alacritty",
        )
        await registry.add(launch_terminal)

        # Terminal window appears (class="Alacritty")
        window_terminal = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Alacritty",
            window_pid=12347,
            workspace_number=3,
            timestamp=base_time + 0.5,
        )

        # Verify class mismatch with VS Code launch
        conf_vscode, sig_vscode = calculate_confidence(launch_vscode, window_terminal)
        assert conf_vscode == 0.0, "Terminal (Alacritty) should NOT match VS Code launch (Code) - confidence=0.0"

        # Verify class match with terminal launch
        conf_terminal, sig_terminal = calculate_confidence(launch_terminal, window_terminal)
        assert conf_terminal >= 0.6, f"Terminal (Alacritty) should match terminal launch (Alacritty) - confidence={conf_terminal}"

        # find_match should select terminal launch (only valid match)
        matched = await registry.find_match(window_terminal)
        assert matched is not None
        assert matched.project_name == "stacks", "Terminal should match stacks launch, NOT nixos"
        assert matched.app_name == "terminal"

        print("✅ Scenario 2: Terminal only matches terminal launches (class-based disambiguation)")

    def test_scenario_3_windows_appearing_any_order(self):
        """
        Acceptance Scenario 3: Test windows appearing in any order still match correctly.

        Setup:
        - Launch VS Code for "nixos" at t=0.0s (expected_class="Code")
        - Launch terminal for "stacks" at t=0.1s (expected_class="Alacritty")
        - Launch Firefox for "personal" at t=0.2s (expected_class="firefox")
        - Windows appear in reverse order: Firefox, terminal, VS Code

        Expected:
        - Each window matches its correct launch based on class
        - Order of window appearance doesn't affect matching
        - 100% class-based disambiguation
        """
        asyncio.run(self._test_windows_appearing_any_order())

    async def _test_windows_appearing_any_order(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # t=0.0s: Launch VS Code for "nixos"
        launch_vscode = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=base_time,
            expected_class="Code",
        )
        await registry.add(launch_vscode)

        # t=0.1s: Launch terminal for "stacks"
        launch_terminal = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12346,
            workspace_number=3,
            timestamp=base_time + 0.1,
            expected_class="Alacritty",
        )
        await registry.add(launch_terminal)

        # t=0.2s: Launch Firefox for "personal"
        launch_firefox = PendingLaunch(
            app_name="firefox",
            project_name="personal",
            project_directory=Path("/home/user/personal"),
            launcher_pid=12347,
            workspace_number=4,
            timestamp=base_time + 0.2,
            expected_class="firefox",
        )
        await registry.add(launch_firefox)

        # Verify all 3 launches pending
        stats_initial = registry.get_stats()
        assert stats_initial.total_pending == 3
        assert stats_initial.unmatched_pending == 3

        # t=0.4s: Firefox window appears FIRST (reverse order)
        window_firefox = LaunchWindowInfo(
            window_id=1,
            window_class="firefox",
            window_pid=100,
            workspace_number=4,
            timestamp=base_time + 0.4,
        )

        matched_firefox = await registry.find_match(window_firefox)
        assert matched_firefox is not None
        assert matched_firefox.project_name == "personal", "Firefox should match personal launch"
        assert matched_firefox.app_name == "firefox"

        # t=0.5s: Terminal window appears SECOND
        window_terminal = LaunchWindowInfo(
            window_id=2,
            window_class="Alacritty",
            window_pid=101,
            workspace_number=3,
            timestamp=base_time + 0.5,
        )

        matched_terminal = await registry.find_match(window_terminal)
        assert matched_terminal is not None
        assert matched_terminal.project_name == "stacks", "Terminal should match stacks launch"
        assert matched_terminal.app_name == "terminal"

        # t=0.6s: VS Code window appears LAST
        window_vscode = LaunchWindowInfo(
            window_id=3,
            window_class="Code",
            window_pid=102,
            workspace_number=2,
            timestamp=base_time + 0.6,
        )

        matched_vscode = await registry.find_match(window_vscode)
        assert matched_vscode is not None
        assert matched_vscode.project_name == "nixos", "VS Code should match nixos launch"
        assert matched_vscode.app_name == "vscode"

        # Verify all 3 launches now matched
        stats_final = registry.get_stats()
        assert stats_final.total_matched == 3
        assert stats_final.unmatched_pending == 0

        print("✅ Scenario 3: Windows appearing in reverse order - all matched correctly via class")

    def test_scenario_4_same_app_different_projects(self):
        """
        Test same application type for different projects.

        Setup:
        - Launch VS Code for "nixos" on workspace 2
        - Launch VS Code for "stacks" on workspace 3 (0.2s later)
        - Both have same expected_class="Code"

        Expected:
        - Workspace signal becomes tiebreaker
        - Window on workspace 2 matches nixos launch
        - Window on workspace 3 matches stacks launch
        """
        asyncio.run(self._test_same_app_different_projects())

    async def _test_same_app_different_projects(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # Launch VS Code for "nixos" on workspace 2
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

        # Launch VS Code for "stacks" on workspace 3
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

        # Window appears on workspace 3 (should match stacks due to workspace signal)
        window = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12347,
            workspace_number=3,
            timestamp=base_time + 0.5,
        )

        # Calculate confidence for both launches
        conf_nixos, sig_nixos = calculate_confidence(launch_nixos, window)
        conf_stacks, sig_stacks = calculate_confidence(launch_stacks, window)

        # nixos: class (0.5) + time <1s (0.3) = 0.8 (no workspace match)
        # stacks: class (0.5) + time <1s (0.3) + workspace (0.2) = 1.0 (workspace match)
        assert conf_nixos == 0.8, f"Expected nixos confidence 0.8, got {conf_nixos}"
        assert conf_stacks == 1.0, f"Expected stacks confidence 1.0, got {conf_stacks}"

        # find_match should select stacks (higher confidence due to workspace)
        matched = await registry.find_match(window)
        assert matched is not None
        assert matched.project_name == "stacks", "Should match stacks due to workspace signal"

        print("✅ Scenario 4: Same app type, different projects - workspace signal acts as tiebreaker")

    def test_scenario_5_100_percent_class_disambiguation(self):
        """
        Verify 100% class-based disambiguation accuracy.

        Setup:
        - Launch 5 different app types within 0.5s
        - Windows appear in random order

        Expected:
        - All 5 windows match correct launches
        - 100% accuracy via class matching
        """
        asyncio.run(self._test_100_percent_class_disambiguation())

    async def _test_100_percent_class_disambiguation(self):
        registry = LaunchRegistry(timeout=5.0)
        base_time = time.time()

        # Define 5 different app types
        apps = [
            {"name": "vscode", "class": "Code", "project": "nixos", "ws": 2},
            {"name": "terminal", "class": "Alacritty", "project": "stacks", "ws": 3},
            {"name": "firefox", "class": "firefox", "project": "personal", "ws": 4},
            {"name": "slack", "class": "Slack", "project": "work", "ws": 5},
            {"name": "obsidian", "class": "obsidian", "project": "notes", "ws": 6},
        ]

        # Launch all apps within 0.5s
        for i, app in enumerate(apps):
            launch = PendingLaunch(
                app_name=app["name"],
                project_name=app["project"],
                project_directory=Path(f"/tmp/{app['project']}"),
                launcher_pid=12340 + i,
                workspace_number=app["ws"],
                timestamp=base_time + (i * 0.1),
                expected_class=app["class"],
            )
            await registry.add(launch)

        # Verify all 5 pending
        stats_initial = registry.get_stats()
        assert stats_initial.total_pending == 5

        # Windows appear in randomized order (e.g., 2, 4, 0, 3, 1)
        window_order = [2, 4, 0, 3, 1]  # Indices into apps array

        successful_matches = 0
        for idx in window_order:
            app = apps[idx]
            window = LaunchWindowInfo(
                window_id=100 + idx,
                window_class=app["class"],
                window_pid=200 + idx,
                workspace_number=app["ws"],
                timestamp=base_time + 1.0 + (idx * 0.1),
            )

            matched = await registry.find_match(window)
            if matched and matched.project_name == app["project"]:
                successful_matches += 1

        # Verify 100% accuracy
        accuracy = (successful_matches / len(apps)) * 100
        assert accuracy == 100.0, f"Expected 100% class-based disambiguation, got {accuracy}%"

        # Verify all matched
        stats_final = registry.get_stats()
        assert stats_final.total_matched == 5
        assert stats_final.unmatched_pending == 0

        print(f"✅ Scenario 5: 100% class-based disambiguation accuracy - {successful_matches}/{len(apps)} matched")


def run_all_scenarios():
    """Run all multi-app type scenarios."""
    test = TestMultiAppTypes()

    print("\n" + "=" * 70)
    print("User Story 4: Multiple Application Types - Scenario Tests")
    print("=" * 70 + "\n")

    try:
        test.test_scenario_1_vscode_and_terminal_simultaneous()
        test.test_scenario_2_terminal_only_matches_terminal_launches()
        test.test_scenario_3_windows_appearing_any_order()
        test.test_scenario_4_same_app_different_projects()
        test.test_scenario_5_100_percent_class_disambiguation()

        print("\n" + "=" * 70)
        print("✅ All User Story 4 scenarios PASSED")
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
