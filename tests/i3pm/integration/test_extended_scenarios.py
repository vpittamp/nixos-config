"""Extended integration test scenarios with longer execution times.

These tests are designed for live viewing via VNC with deliberate pauses
to allow observation of each step.
"""

import pytest
import asyncio
from pathlib import Path
import sys
import json
import subprocess
import os

# Add i3pm to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "i3_project_manager"))

from testing.integration import IntegrationTestFramework

# Demo mode - adds longer delays for viewing
DEMO_MODE = os.getenv('DEMO_MODE', 'true').lower() == 'true'
DEMO_DELAY = float(os.getenv('DEMO_DELAY', '3.0'))  # 3 second delays by default


async def demo_pause(message: str = None, delay: float = None):
    """Pause for demonstration with optional message."""
    if not DEMO_MODE:
        return

    if message:
        print(f"\n{'='*60}")
        print(f"  {message}")
        print(f"{'='*60}\n")

    await asyncio.sleep(delay or DEMO_DELAY)


@pytest.fixture
async def integration_env():
    """Create integration test environment."""
    async with IntegrationTestFramework(display=":99") as framework:
        yield framework


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_progressive_window_launching(integration_env):
    """Test launching windows progressively with visual delays.

    Duration: ~30s in demo mode
    """
    framework = integration_env

    await demo_pause("TEST: Progressive Window Launching")

    print("\nStep 1: Launching first window...")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await demo_pause("First window launched - observe it appearing", 4.0)

    print("\nStep 2: Launching second window...")
    proc2 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await demo_pause("Second window launched - observe tiling", 4.0)

    print("\nStep 3: Launching third window...")
    proc3 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await demo_pause("Third window launched - observe layout changes", 4.0)

    # Verify all windows present
    window_count = await framework._get_window_count()
    assert window_count >= 3, f"Expected at least 3 windows, got {window_count}"

    await demo_pause("All 3 windows visible - maintaining for observation", 5.0)

    print("\nStep 4: Closing windows one by one...")
    await framework.close_all_windows()
    await demo_pause("Windows closed - observe cleanup", 3.0)

    print("\n✅ Progressive window launching test complete")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_workspace_navigation(integration_env):
    """Test workspace switching with visual delays.

    Duration: ~40s in demo mode
    """
    framework = integration_env

    await demo_pause("TEST: Workspace Navigation")

    print("\nStep 1: Launching window on workspace 1...")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await demo_pause("Window on workspace 1", 3.0)

    print("\nStep 2: Switching to workspace 2...")
    result = subprocess.run(
        ["i3-msg", "workspace number 2"],
        capture_output=True,
        env={**os.environ, "DISPLAY": framework.display}
    )
    await demo_pause("Switched to workspace 2 - observe empty workspace", 4.0)

    print("\nStep 3: Launching window on workspace 2...")
    proc2 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await demo_pause("Window on workspace 2", 3.0)

    print("\nStep 4: Switching back to workspace 1...")
    subprocess.run(
        ["i3-msg", "workspace number 1"],
        capture_output=True,
        env={**os.environ, "DISPLAY": framework.display}
    )
    await demo_pause("Back to workspace 1 - first window should reappear", 4.0)

    print("\nStep 5: Switching to workspace 2 again...")
    subprocess.run(
        ["i3-msg", "workspace number 2"],
        capture_output=True,
        env={**os.environ, "DISPLAY": framework.display}
    )
    await demo_pause("Back to workspace 2 - second window visible", 4.0)

    print("\nStep 6: Cleaning up...")
    await framework.close_all_windows()
    await demo_pause("Cleanup complete", 2.0)

    print("\n✅ Workspace navigation test complete")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_project_lifecycle_demo(integration_env):
    """Test complete project lifecycle with visual delays.

    Duration: ~50s in demo mode
    """
    framework = integration_env
    config_dir = framework.env.config_dir

    await demo_pause("TEST: Project Lifecycle Demo")

    # Step 1: Create project
    print("\nStep 1: Creating project 'demo-project'...")
    project_name = "demo-project"
    project_dir = framework.env.temp_dir / project_name
    project_dir.mkdir(exist_ok=True)

    project_data = {
        "name": project_name,
        "display_name": "Demo Project",
        "directory": str(project_dir),
        "icon": "🎬",
        "auto_launch": [
            {"command": "xterm", "workspace": 1, "environment": {}, "wait_timeout": 5.0}
        ]
    }

    project_file = config_dir / "projects" / f"{project_name}.json"
    with open(project_file, "w") as f:
        json.dump(project_data, f, indent=2)

    await demo_pause(f"Project '{project_name}' created", 3.0)

    # Step 2: Launch application
    print("\nStep 2: Launching application in project context...")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await demo_pause("Application launched - window visible", 4.0)

    # Step 3: Save layout
    print("\nStep 3: Saving workspace layout...")
    layout_dir = config_dir / "layouts" / project_name
    layout_dir.mkdir(parents=True, exist_ok=True)

    layout_data = {
        "name": "demo-layout",
        "project_name": project_name,
        "workspaces": [
            {
                "number": 1,
                "output": "primary",
                "windows": [
                    {
                        "window_class": "XTerm",
                        "layout_role": "terminal",
                        "launch_command": "xterm",
                        "cwd": str(project_dir),
                        "launch_timeout": 5.0,
                        "max_retries": 3,
                        "retry_delay": 1.0
                    }
                ]
            }
        ],
        "created_at": "2025-10-21T19:00:00",
        "last_used_at": "2025-10-21T19:00:00"
    }

    layout_file = layout_dir / "demo-layout.json"
    with open(layout_file, "w") as f:
        json.dump(layout_data, f, indent=2)

    await demo_pause("Layout saved", 3.0)

    # Step 4: Close windows
    print("\nStep 4: Closing all windows (simulating project switch)...")
    await framework.close_all_windows()
    await demo_pause("Windows closed - workspace empty", 4.0)

    # Step 5: Restore layout
    print("\nStep 5: Restoring layout...")
    with open(layout_file) as f:
        loaded_layout = json.load(f)

    for ws in loaded_layout["workspaces"]:
        for window_config in ws["windows"]:
            proc = await framework.launch_application(
                window_config["launch_command"],
                wait_for_window=True,
                timeout=window_config["launch_timeout"]
            )
            await asyncio.sleep(0.5)

    await demo_pause("Layout restored - windows back", 5.0)

    # Step 6: Verify
    window_count = await framework._get_window_count()
    assert window_count >= 1, "Layout not restored"

    print(f"\nStep 6: Verified - {window_count} window(s) restored")
    await demo_pause("Verification complete", 3.0)

    # Cleanup
    await framework.close_all_windows()
    print("\n✅ Project lifecycle demo complete")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_multi_window_complex_layout(integration_env):
    """Test complex layout with multiple windows and arrangements.

    Duration: ~45s in demo mode
    """
    framework = integration_env

    await demo_pause("TEST: Complex Multi-Window Layout")

    print("\nStep 1: Launching 5 windows progressively...")
    processes = []

    for i in range(5):
        print(f"  Launching window {i+1}/5...")
        proc = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
        processes.append(proc)
        await demo_pause(f"Window {i+1} added - observe layout adaptation", 3.0)

    # Verify all windows
    window_count = await framework._get_window_count()
    assert window_count >= 5, f"Expected at least 5 windows, got {window_count}"

    await demo_pause("All 5 windows visible - complex layout", 5.0)

    print("\nStep 2: Closing windows in reverse order...")
    for i in range(5):
        await framework.close_all_windows()
        break  # Close all at once for demo

    await demo_pause("All windows closed", 3.0)

    print("\n✅ Complex layout test complete")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_rapid_window_cycling(integration_env):
    """Test rapid window creation and destruction.

    Duration: ~35s in demo mode
    """
    framework = integration_env

    await demo_pause("TEST: Rapid Window Cycling")

    for cycle in range(3):
        print(f"\n=== Cycle {cycle + 1}/3 ===")

        print("Opening windows...")
        procs = []
        for i in range(3):
            proc = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
            procs.append(proc)
            await asyncio.sleep(0.5)

        await demo_pause(f"Cycle {cycle + 1}: 3 windows open", 3.0)

        print("Closing windows...")
        await framework.close_all_windows()
        await demo_pause(f"Cycle {cycle + 1}: windows closed", 2.0)

    print("\n✅ Rapid cycling test complete")


if __name__ == "__main__":
    """Allow running directly for quick testing."""
    import sys

    print("Running extended integration test scenarios...")
    print("These tests include visual delays for live viewing.\n")
    print(f"DEMO_MODE: {DEMO_MODE}")
    print(f"DEMO_DELAY: {DEMO_DELAY}s\n")

    # Run with pytest
    sys.exit(pytest.main([
        __file__,
        "-v",
        "-s",
        "-m", "integration",
        "--tb=short"
    ]))
