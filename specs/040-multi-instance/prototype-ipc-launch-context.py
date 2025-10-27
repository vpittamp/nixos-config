#!/usr/bin/env python3
"""
Prototype: IPC Launch Context for Multi-Instance App Tracking

This prototype demonstrates how launch context tracking can solve the
multi-instance app problem without relying on process environments.
"""

import asyncio
import time
from dataclasses import dataclass
from typing import Optional, List, Dict
from enum import Enum


class MatchConfidence(Enum):
    """Confidence levels for window-to-launch correlation"""
    EXACT = 1.0      # PID match + timestamp within 1s
    HIGH = 0.8       # App class match + timestamp within 2s + workspace match
    MEDIUM = 0.6     # App class match + timestamp within 5s
    LOW = 0.3        # App class match only
    NONE = 0.0       # No match


@dataclass
class LaunchNotification:
    """Record of app launch from wrapper script"""
    app_name: str           # "vscode", "terminal", etc.
    project_name: str       # "nixos", "stacks", etc.
    project_dir: str        # "/etc/nixos", etc.
    launcher_pid: int       # PID of launcher process
    workspace: Optional[int]  # Target workspace (if known)
    timestamp: float        # time.time() when launched
    matched: bool = False   # Whether this launch has been matched to a window

    def age(self) -> float:
        """How long ago was this launch?"""
        return time.time() - self.timestamp

    def is_expired(self, timeout: float = 5.0) -> bool:
        """Has this launch timed out?"""
        return self.age() > timeout


@dataclass
class WindowInfo:
    """Information about a new window"""
    window_id: int
    window_class: str       # "Code", "Alacritty", etc.
    window_pid: Optional[int]  # PID of window process (may be shared)
    workspace: int          # Current workspace number
    timestamp: float        # When window was created


class LaunchContextTracker:
    """
    Tracks app launches and correlates them with window creation events.

    This is the core of the IPC approach - it maintains a registry of recent
    launches and uses multiple signals to match windows to their launch context.
    """

    def __init__(self, timeout: float = 5.0):
        self.pending_launches: List[LaunchNotification] = []
        self.timeout = timeout
        self.matched_windows: Dict[int, str] = {}  # window_id → project_name

    async def notify_launch(
        self,
        app_name: str,
        project_name: str,
        project_dir: str,
        launcher_pid: int,
        workspace: Optional[int] = None,
    ) -> None:
        """
        Wrapper script notifies daemon of imminent app launch.

        Called from app-launcher-wrapper.sh via:
            i3pm daemon notify-launch vscode nixos /etc/nixos 12345 2
        """
        launch = LaunchNotification(
            app_name=app_name,
            project_name=project_name,
            project_dir=project_dir,
            launcher_pid=launcher_pid,
            workspace=workspace,
            timestamp=time.time(),
        )

        self.pending_launches.append(launch)
        print(f"📋 Launch notification: {app_name} for project {project_name} (launcher PID: {launcher_pid})")

        # Clean up expired launches
        await self._cleanup_expired()

    async def match_window(self, window: WindowInfo) -> tuple[Optional[str], MatchConfidence]:
        """
        Match new window to pending launch using multiple correlation signals.

        Returns: (project_name, confidence)
        """
        print(f"\n🔍 Matching window {window.window_id} (class={window.window_class}, PID={window.window_pid})")

        best_match: Optional[LaunchNotification] = None
        best_confidence = MatchConfidence.NONE

        for launch in self.pending_launches:
            if launch.matched:
                continue  # Already matched to another window

            confidence = self._calculate_confidence(window, launch)

            print(f"  → Launch {launch.app_name}:{launch.project_name} "
                  f"(age={launch.age():.2f}s, confidence={confidence.name})")

            if confidence.value > best_confidence.value:
                best_match = launch
                best_confidence = confidence

        if best_match and best_confidence.value >= MatchConfidence.MEDIUM.value:
            # Found good match
            best_match.matched = True
            self.matched_windows[window.window_id] = best_match.project_name

            print(f"  ✅ MATCHED to {best_match.project_name} (confidence: {best_confidence.name})")
            return best_match.project_name, best_confidence

        # No good match found
        print(f"  ❌ No confident match found (best: {best_confidence.name})")
        return None, best_confidence

    def _calculate_confidence(
        self,
        window: WindowInfo,
        launch: LaunchNotification,
    ) -> MatchConfidence:
        """
        Calculate match confidence using multiple signals.

        Signals:
        1. App class match (required baseline)
        2. Time delta (how recent was launch?)
        3. Workspace match (did window appear on expected workspace?)
        4. PID relationship (is window PID child of launcher PID?)
        """
        # Map app registry names to window classes
        APP_CLASS_MAP = {
            "vscode": "Code",
            "terminal": "Alacritty",
            "firefox": "firefox",
            "chromium": "Chromium",
        }

        expected_class = APP_CLASS_MAP.get(launch.app_name, launch.app_name)

        # Signal 1: App class must match (required)
        if window.window_class != expected_class:
            return MatchConfidence.NONE

        age = launch.age()

        # Signal 2: Time delta scoring
        if age > 5.0:
            # Too old, expired
            return MatchConfidence.NONE
        elif age <= 1.0:
            # Very recent launch
            time_score = 1.0
        elif age <= 2.0:
            time_score = 0.8
        elif age <= 5.0:
            time_score = 0.6
        else:
            time_score = 0.0

        # Signal 3: Workspace match
        workspace_match = (
            launch.workspace is not None
            and window.workspace == launch.workspace
        )

        # Signal 4: PID relationship (for apps that spawn child processes)
        pid_related = False  # TODO: Implement PID tree checking
        # Could check if window.window_pid is descendant of launch.launcher_pid

        # Combine signals into confidence score
        if time_score >= 0.8 and workspace_match:
            return MatchConfidence.HIGH
        elif time_score >= 0.6 and workspace_match:
            return MatchConfidence.HIGH
        elif time_score >= 0.8:
            return MatchConfidence.MEDIUM
        elif time_score >= 0.6:
            return MatchConfidence.MEDIUM
        else:
            return MatchConfidence.LOW

    async def _cleanup_expired(self):
        """Remove expired launches from tracking"""
        before = len(self.pending_launches)
        self.pending_launches = [
            l for l in self.pending_launches
            if not l.is_expired(self.timeout)
        ]
        after = len(self.pending_launches)

        if before != after:
            print(f"🧹 Cleaned up {before - after} expired launches ({after} remaining)")

    def get_stats(self) -> dict:
        """Get tracker statistics"""
        return {
            "pending_launches": len(self.pending_launches),
            "matched_launches": sum(1 for l in self.pending_launches if l.matched),
            "matched_windows": len(self.matched_windows),
        }


# =============================================================================
# Prototype Test Scenarios
# =============================================================================

async def test_scenario_1_sequential_launches():
    """
    Test Case 1: Sequential VS Code launches (normal case)

    User launches VS Code for nixos, waits, then launches for stacks.
    Expected: Both windows matched correctly with HIGH confidence.
    """
    print("\n" + "="*80)
    print("TEST SCENARIO 1: Sequential Launches (Normal Case)")
    print("="*80)

    tracker = LaunchContextTracker()

    # User launches VS Code for nixos project
    await tracker.notify_launch(
        app_name="vscode",
        project_name="nixos",
        project_dir="/etc/nixos",
        launcher_pid=12345,
        workspace=2,
    )

    # Window appears 0.5s later
    await asyncio.sleep(0.5)

    window1 = WindowInfo(
        window_id=100001,
        window_class="Code",
        window_pid=50000,
        workspace=2,
        timestamp=time.time(),
    )

    project1, conf1 = await tracker.match_window(window1)
    assert project1 == "nixos", f"Expected nixos, got {project1}"
    assert conf1 in [MatchConfidence.HIGH, MatchConfidence.MEDIUM], f"Expected HIGH/MEDIUM, got {conf1}"

    # User waits 2 seconds, then launches VS Code for stacks
    await asyncio.sleep(2)

    await tracker.notify_launch(
        app_name="vscode",
        project_name="stacks",
        project_dir="/home/user/stacks",
        launcher_pid=12346,
        workspace=2,
    )

    # Window appears 0.3s later
    await asyncio.sleep(0.3)

    window2 = WindowInfo(
        window_id=100002,
        window_class="Code",
        window_pid=50000,  # SAME PID (shared process)
        workspace=2,
        timestamp=time.time(),
    )

    project2, conf2 = await tracker.match_window(window2)
    assert project2 == "stacks", f"Expected stacks, got {project2}"
    assert conf2 in [MatchConfidence.HIGH, MatchConfidence.MEDIUM], f"Expected HIGH/MEDIUM, got {conf2}"

    print("\n✅ SCENARIO 1 PASSED: Sequential launches matched correctly")
    print(f"   Window 1: {project1} ({conf1.name})")
    print(f"   Window 2: {project2} ({conf2.name})")


async def test_scenario_2_rapid_launches():
    """
    Test Case 2: Rapid VS Code launches (challenging case)

    User launches VS Code for nixos and stacks within 0.1s.
    Expected: Ambiguity resolved by workspace matching.
    """
    print("\n" + "="*80)
    print("TEST SCENARIO 2: Rapid Launches (Challenging Case)")
    print("="*80)

    tracker = LaunchContextTracker()

    # User launches both VS Code windows rapidly
    await tracker.notify_launch(
        app_name="vscode",
        project_name="nixos",
        project_dir="/etc/nixos",
        launcher_pid=12345,
        workspace=2,
    )

    await asyncio.sleep(0.1)  # Very short delay

    await tracker.notify_launch(
        app_name="vscode",
        project_name="stacks",
        project_dir="/home/user/stacks",
        launcher_pid=12346,
        workspace=2,
    )

    # First window appears
    await asyncio.sleep(0.5)

    window1 = WindowInfo(
        window_id=100001,
        window_class="Code",
        window_pid=50000,
        workspace=2,
        timestamp=time.time(),
    )

    project1, conf1 = await tracker.match_window(window1)

    # Second window appears
    await asyncio.sleep(0.3)

    window2 = WindowInfo(
        window_id=100002,
        window_class="Code",
        window_pid=50000,  # Same PID
        workspace=2,
        timestamp=time.time(),
    )

    project2, conf2 = await tracker.match_window(window2)

    # In this case, we expect:
    # - Both windows matched (not None)
    # - Different projects (nixos and stacks, though order may vary)
    # - Medium/High confidence

    assert project1 is not None, "Window 1 should match"
    assert project2 is not None, "Window 2 should match"
    assert project1 != project2, f"Windows should match different projects: {project1} vs {project2}"

    matched_projects = {project1, project2}
    assert matched_projects == {"nixos", "stacks"}, f"Expected {{nixos, stacks}}, got {matched_projects}"

    print("\n✅ SCENARIO 2 PASSED: Rapid launches disambiguated")
    print(f"   Window 1: {project1} ({conf1.name})")
    print(f"   Window 2: {project2} ({conf2.name})")
    print(f"   Note: Order may vary, but both projects matched correctly")


async def test_scenario_3_launch_timeout():
    """
    Test Case 3: Launch timeout (window takes too long)

    User launches VS Code but window doesn't appear for 6 seconds.
    Expected: Launch expires, window not matched (fallback to title parsing).
    """
    print("\n" + "="*80)
    print("TEST SCENARIO 3: Launch Timeout")
    print("="*80)

    tracker = LaunchContextTracker(timeout=5.0)

    await tracker.notify_launch(
        app_name="vscode",
        project_name="nixos",
        project_dir="/etc/nixos",
        launcher_pid=12345,
        workspace=2,
    )

    # Window takes too long to appear (6 seconds > 5s timeout)
    print("\n⏰ Waiting 6 seconds for window to appear...")
    await asyncio.sleep(6)

    window1 = WindowInfo(
        window_id=100001,
        window_class="Code",
        window_pid=50000,
        workspace=2,
        timestamp=time.time(),
    )

    project1, conf1 = await tracker.match_window(window1)

    assert project1 is None, f"Expected no match (expired), got {project1}"
    assert conf1 == MatchConfidence.NONE, f"Expected NONE confidence, got {conf1}"

    print("\n✅ SCENARIO 3 PASSED: Expired launch correctly rejected")
    print(f"   Window 1: {project1} ({conf1.name})")
    print(f"   → Daemon would fallback to title parsing or active project")


async def test_scenario_4_different_apps():
    """
    Test Case 4: Multiple different apps launched simultaneously

    User launches VS Code and Alacritty at same time.
    Expected: Both matched correctly by app class.
    """
    print("\n" + "="*80)
    print("TEST SCENARIO 4: Multiple Different Apps")
    print("="*80)

    tracker = LaunchContextTracker()

    # Launch both apps simultaneously
    await tracker.notify_launch(
        app_name="vscode",
        project_name="nixos",
        project_dir="/etc/nixos",
        launcher_pid=12345,
        workspace=2,
    )

    await tracker.notify_launch(
        app_name="terminal",
        project_name="stacks",
        project_dir="/home/user/stacks",
        launcher_pid=12346,
        workspace=1,
    )

    # Both windows appear around same time
    await asyncio.sleep(0.5)

    vscode_window = WindowInfo(
        window_id=100001,
        window_class="Code",
        window_pid=50000,
        workspace=2,
        timestamp=time.time(),
    )

    terminal_window = WindowInfo(
        window_id=100002,
        window_class="Alacritty",
        window_pid=50001,
        workspace=1,
        timestamp=time.time(),
    )

    project1, conf1 = await tracker.match_window(vscode_window)
    project2, conf2 = await tracker.match_window(terminal_window)

    assert project1 == "nixos", f"VS Code should match nixos, got {project1}"
    assert project2 == "stacks", f"Terminal should match stacks, got {project2}"
    assert conf1.value >= MatchConfidence.MEDIUM.value
    assert conf2.value >= MatchConfidence.MEDIUM.value

    print("\n✅ SCENARIO 4 PASSED: Different apps matched correctly")
    print(f"   VS Code: {project1} ({conf1.name})")
    print(f"   Terminal: {project2} ({conf2.name})")


async def main():
    """Run all test scenarios"""
    print("\n" + "="*80)
    print("IPC LAUNCH CONTEXT TRACKER - PROTOTYPE TESTS")
    print("="*80)

    try:
        await test_scenario_1_sequential_launches()
        await test_scenario_2_rapid_launches()
        await test_scenario_3_launch_timeout()
        await test_scenario_4_different_apps()

        print("\n" + "="*80)
        print("✅ ALL TESTS PASSED")
        print("="*80)
        print("\nNext steps:")
        print("1. Integrate LaunchContextTracker into daemon.py")
        print("2. Add IPC method: notify_launch(app, project, ...)")
        print("3. Enhance app-launcher-wrapper.sh to call notify_launch")
        print("4. Update on_window_new() handler to use match_window()")
        print("5. Implement PID tree checking for better correlation")
        print("6. Add fallback chain: IPC → title parsing → active project")

    except AssertionError as e:
        print(f"\n❌ TEST FAILED: {e}")
        raise


if __name__ == "__main__":
    asyncio.run(main())
