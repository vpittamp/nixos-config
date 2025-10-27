"""Sequential application launches test scenario.

Feature 041: IPC Launch Context - T019

This scenario validates the core User Story 1: Sequential Application Launches
- Target: 100% correct assignment for sequential launches (>2 seconds apart)
- Target: HIGH confidence (0.8+) for correlations

Acceptance Criteria:
- AS1: Launch VS Code for "nixos", verify window marked with "nixos"
- AS2: Switch to "stacks", launch VS Code, verify window marked with "stacks"
- AS3: Verify both windows have independent, correct project assignments
"""

import asyncio
import time
from pathlib import Path
from typing import List

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"))

from models import PendingLaunch, LaunchWindowInfo, CorrelationResult
from services.launch_registry import LaunchRegistry
from services.window_correlator import calculate_confidence


class SequentialLaunchesBasic:
    """
    Test basic sequential launches with >2 second delay.

    This is the MVP scenario for User Story 1. It validates that when applications
    are launched sequentially with sufficient time between them (>2 seconds), each
    window is correctly correlated to its launch notification and assigned the
    correct project.

    Scenario ID: launch_context_001
    Priority: P1 (MVP)
    """

    scenario_id = "launch_context_001"
    name = "Sequential Application Launches"
    description = "Launch two VS Code instances for different projects 3+ seconds apart"
    priority = 1
    timeout_seconds = 30.0

    def __init__(self):
        """Initialize scenario."""
        self.registry: LaunchRegistry = None
        self.test_results: List[dict] = []

    async def setup(self) -> None:
        """Initialize launch registry for testing."""
        # Create launch registry with 5-second timeout
        self.registry = LaunchRegistry(timeout=5.0)
        print(f"✓ Initialized LaunchRegistry with 5-second timeout")

    async def execute(self) -> None:
        """Execute sequential launch scenario."""
        print("\n=== Acceptance Scenario 1: Launch VS Code for nixos ===")

        # Simulate launcher wrapper sending notification for first launch
        launch1_time = time.time()
        launch1 = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch1_time,
            expected_class="Code",
        )

        launch1_id = await self.registry.add(launch1)
        print(f"  → Registered launch notification: {launch1_id}")
        print(f"     Project: nixos, Workspace: 2, Expected class: Code")

        # Simulate VS Code window appearing 0.8s later (typical startup time)
        await asyncio.sleep(0.1)  # Small delay for realism in test
        window1_time = launch1_time + 0.8
        window1 = LaunchWindowInfo(
            window_id=94532735639728,
            window_class="Code",
            window_pid=12346,
            workspace_number=2,
            timestamp=window1_time,
        )

        print(f"  → Window created: ID={window1.window_id}, class={window1.window_class}")

        # Find matching launch
        match1 = await self.registry.find_match(window1)

        if match1 is None:
            raise AssertionError("AS1 FAILED: No match found for first VS Code window")

        # Calculate confidence
        confidence1, signals1 = calculate_confidence(match1, window1)

        print(f"  → Matched to project: {match1.project_name}")
        print(f"  → Confidence: {confidence1:.2f} (target: >= 0.8 for HIGH)")

        # Validate AS1: Correct project assignment with HIGH confidence
        assert match1.project_name == "nixos", f"AS1 FAILED: Expected project 'nixos', got '{match1.project_name}'"
        assert confidence1 >= 0.8, f"AS1 FAILED: Confidence {confidence1:.2f} < 0.8 (HIGH threshold)"

        self.test_results.append({
            "scenario": "AS1",
            "project": match1.project_name,
            "confidence": confidence1,
            "window_id": window1.window_id,
            "passed": True
        })

        print(f"  ✓ AS1 PASSED: Window correctly assigned to 'nixos' with HIGH confidence ({confidence1:.2f})")

        # Wait 3+ seconds before second launch (sequential launches)
        print(f"\n  ⏱  Waiting 3 seconds for sequential launch...")
        await asyncio.sleep(3.0)

        print("\n=== Acceptance Scenario 2: Launch VS Code for stacks ===")

        # Simulate launcher wrapper sending notification for second launch
        launch2_time = time.time()
        launch2 = PendingLaunch(
            app_name="vscode",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=12347,
            workspace_number=3,
            timestamp=launch2_time,
            expected_class="Code",
        )

        launch2_id = await self.registry.add(launch2)
        print(f"  → Registered launch notification: {launch2_id}")
        print(f"     Project: stacks, Workspace: 3, Expected class: Code")

        # Simulate VS Code window appearing 0.9s later
        await asyncio.sleep(0.1)
        window2_time = launch2_time + 0.9
        window2 = LaunchWindowInfo(
            window_id=94532735639800,
            window_class="Code",
            window_pid=12348,
            workspace_number=3,
            timestamp=window2_time,
        )

        print(f"  → Window created: ID={window2.window_id}, class={window2.window_class}")

        # Find matching launch
        match2 = await self.registry.find_match(window2)

        if match2 is None:
            raise AssertionError("AS2 FAILED: No match found for second VS Code window")

        # Calculate confidence
        confidence2, signals2 = calculate_confidence(match2, window2)

        print(f"  → Matched to project: {match2.project_name}")
        print(f"  → Confidence: {confidence2:.2f} (target: >= 0.8 for HIGH)")

        # Validate AS2: Correct project assignment with HIGH confidence
        assert match2.project_name == "stacks", f"AS2 FAILED: Expected project 'stacks', got '{match2.project_name}'"
        assert confidence2 >= 0.8, f"AS2 FAILED: Confidence {confidence2:.2f} < 0.8 (HIGH threshold)"

        self.test_results.append({
            "scenario": "AS2",
            "project": match2.project_name,
            "confidence": confidence2,
            "window_id": window2.window_id,
            "passed": True
        })

        print(f"  ✓ AS2 PASSED: Window correctly assigned to 'stacks' with HIGH confidence ({confidence2:.2f})")

    async def validate(self) -> None:
        """Validate scenario results."""
        print("\n=== Acceptance Scenario 3: Verify Independent Assignments ===")

        # Check that both windows were assigned correctly
        assert len(self.test_results) == 2, "Expected 2 successful correlations"

        result1 = self.test_results[0]
        result2 = self.test_results[1]

        # Verify independence: different projects
        assert result1["project"] != result2["project"], \
            "AS3 FAILED: Both windows assigned to same project (not independent)"

        # Verify both achieved HIGH confidence
        assert result1["confidence"] >= 0.8, \
            f"AS3 FAILED: First window confidence {result1['confidence']:.2f} < 0.8"
        assert result2["confidence"] >= 0.8, \
            f"AS3 FAILED: Second window confidence {result2['confidence']:.2f} < 0.8"

        # Check registry stats
        stats = self.registry.get_stats()

        print(f"  → Total notifications: {stats.total_notifications}")
        print(f"  → Total matched: {stats.total_matched}")
        print(f"  → Match rate: {stats.match_rate:.1f}%")

        # Validate 100% match rate (User Story 1 target)
        assert stats.match_rate == 100.0, \
            f"AS3 FAILED: Match rate {stats.match_rate:.1f}% < 100% (target for sequential launches)"

        print(f"  ✓ AS3 PASSED: Both windows have independent, correct assignments")
        print(f"  ✓ Match rate: 100% (2/2 launches successfully correlated)")

        # Summary
        print("\n=== Scenario Summary ===")
        print(f"  Scenario: {self.name}")
        print(f"  Result: ✓ ALL ACCEPTANCE CRITERIA PASSED")
        print(f"  Window 1: nixos @ {result1['confidence']:.2f} confidence (HIGH)")
        print(f"  Window 2: stacks @ {result2['confidence']:.2f} confidence (HIGH)")
        print(f"  Match rate: 100%")
        print(f"  Status: User Story 1 MVP validated ✓")

    async def cleanup(self) -> None:
        """Clean up test resources."""
        # Registry will be garbage collected
        print(f"\n✓ Scenario cleanup complete")


async def run_scenario():
    """Run the sequential launches scenario."""
    scenario = SequentialLaunchesBasic()

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
        print(f"✓ SCENARIO PASSED")
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
