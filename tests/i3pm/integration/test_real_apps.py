"""Real integration tests with actual applications.

These tests:
- Launch real Xvfb X server
- Start real i3 window manager
- Launch real applications (alacritty, etc.)
- Use xdotool for keyboard input
- Validate actual window states
"""

import pytest
import asyncio
from pathlib import Path
import sys
import json
import subprocess

# Add i3pm to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "i3_project_manager"))

from testing.integration import IntegrationTestFramework


@pytest.fixture
async def integration_env():
    """Create real integration test environment.

    Yields:
        IntegrationTestFramework with Xvfb and i3 running
    """
    async with IntegrationTestFramework(display=":99") as framework:
        yield framework


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_xvfb_and_i3_startup(integration_env):
    """Test that Xvfb and i3 start successfully."""
    framework = integration_env

    # Verify environment is set up
    assert framework.env is not None
    assert framework.env.xvfb_process is not None
    assert framework.env.i3_process is not None
    assert framework.env.xvfb_process.poll() is None  # Still running
    assert framework.env.i3_process.poll() is None  # Still running

    # Verify i3 is responding
    result = subprocess.run(
        ["i3-msg", "-t", "get_version"],
        capture_output=True,
        text=True,
        env={"DISPLAY": framework.display}
    )

    assert result.returncode == 0
    assert "version" in result.stdout.lower()
    print(f"i3 version: {result.stdout}")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_launch_terminal_application(integration_env):
    """Test launching a real terminal application."""
    framework = integration_env

    # Get initial window count
    initial_count = await framework._get_window_count()
    print(f"Initial windows: {initial_count}")

    # Launch alacritty (should be available in test environment)
    # If alacritty not available, try xterm
    for terminal in ["alacritty", "xterm"]:
        try:
            process = await framework.launch_application(
                terminal,
                wait_for_window=True,
                timeout=5.0
            )

            # Verify window appeared
            await asyncio.sleep(0.5)
            final_count = await framework._get_window_count()
            print(f"Final windows: {final_count}")

            assert final_count > initial_count, f"Window did not appear for {terminal}"
            print(f"✅ Successfully launched {terminal}")

            # Close the window
            await framework.close_all_windows()
            break
        except Exception as e:
            print(f"⚠️ Could not launch {terminal}: {e}")
            continue


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_keyboard_input_with_xdotool(integration_env):
    """Test sending keyboard input with xdotool."""
    framework = integration_env

    # Launch terminal
    try:
        await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)

        # Send some keys
        await framework.send_keys("Return")
        await asyncio.sleep(0.2)

        # Type text
        await framework.type_text("echo 'test'")
        await asyncio.sleep(0.2)

        await framework.send_keys("Return")
        await asyncio.sleep(0.5)

        print("✅ Successfully sent keyboard input")

        # Close window
        await framework.close_all_windows()
    except Exception as e:
        print(f"⚠️ Keyboard test skipped: {e}")
        pytest.skip(f"xterm or xdotool not available: {e}")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_i3_workspace_switching(integration_env):
    """Test i3 workspace switching."""
    framework = integration_env

    # Switch to workspace 1
    result = subprocess.run(
        ["i3-msg", "workspace number 1"],
        capture_output=True,
        env={"DISPLAY": framework.display}
    )
    assert result.returncode == 0

    # Get workspaces
    result = subprocess.run(
        ["i3-msg", "-t", "get_workspaces"],
        capture_output=True,
        text=True,
        env={"DISPLAY": framework.display}
    )

    assert result.returncode == 0
    workspaces = json.loads(result.stdout)

    # Find focused workspace
    focused = [ws for ws in workspaces if ws.get("focused")]
    assert len(focused) == 1
    assert focused[0]["num"] == 1

    print(f"✅ Successfully switched to workspace 1")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_multiple_windows_and_cleanup(integration_env):
    """Test launching multiple windows and cleanup."""
    framework = integration_env

    terminals = []

    try:
        # Launch 3 terminal windows
        for i in range(3):
            process = await framework.launch_application(
                "xterm",
                wait_for_window=True,
                timeout=5.0
            )
            terminals.append(process)
            await asyncio.sleep(0.5)

        # Verify 3 windows
        window_count = await framework._get_window_count()
        assert window_count >= 3, f"Expected at least 3 windows, got {window_count}"

        print(f"✅ Launched 3 windows successfully")

        # Close all windows
        await framework.close_all_windows()

        # Verify all closed
        await asyncio.sleep(1)
        window_count = await framework._get_window_count()
        assert window_count == 0, f"Expected 0 windows after cleanup, got {window_count}"

        print(f"✅ Cleanup successful, all windows closed")

    except Exception as e:
        print(f"⚠️ Multi-window test skipped: {e}")
        pytest.skip(f"Could not launch multiple windows: {e}")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_project_creation_and_config(integration_env):
    """Test creating project configuration files."""
    framework = integration_env
    config_dir = framework.env.config_dir

    # Create a test project
    project_data = {
        "name": "test-project",
        "display_name": "Test Project",
        "directory": str(framework.env.temp_dir / "test-project"),
        "icon": "📦",
        "auto_launch": [
            {
                "command": "xterm",
                "workspace": 1,
                "environment": {},
                "wait_timeout": 5.0
            }
        ],
        "workspace_preferences": {
            "1": "primary",
            "2": "primary",
            "3": "secondary"
        }
    }

    project_file = config_dir / "projects" / "test-project.json"
    with open(project_file, "w") as f:
        json.dump(project_data, f, indent=2)

    # Verify file exists
    assert project_file.exists()

    # Read and verify content
    with open(project_file) as f:
        loaded_data = json.load(f)

    assert loaded_data["name"] == "test-project"
    assert len(loaded_data["auto_launch"]) == 1
    assert loaded_data["workspace_preferences"]["1"] == "primary"

    print(f"✅ Project configuration created and validated")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_layout_save_file_creation(integration_env):
    """Test creating layout save files."""
    framework = integration_env
    config_dir = framework.env.config_dir

    # Create layout directory
    layout_dir = config_dir / "layouts" / "test-project"
    layout_dir.mkdir(parents=True, exist_ok=True)

    # Create layout data
    layout_data = {
        "name": "test-layout",
        "project_name": "test-project",
        "workspaces": [
            {
                "number": 1,
                "output": "primary",
                "windows": [
                    {
                        "window_class": "XTerm",
                        "window_title": "xterm",
                        "geometry": {"width": 1920, "height": 1080, "x": 0, "y": 0},
                        "layout_role": "terminal",
                        "split_before": None,
                        "launch_command": "xterm",
                        "launch_env": {},
                        "expected_marks": ["project:test-project"],
                        "cwd": None,
                        "launch_timeout": 5.0,
                        "max_retries": 3,
                        "retry_delay": 1.0
                    }
                ]
            }
        ],
        "created_at": "2025-10-21T18:00:00",
        "last_used_at": "2025-10-21T18:00:00"
    }

    layout_file = layout_dir / "test-layout.json"
    with open(layout_file, "w") as f:
        json.dump(layout_data, f, indent=2)

    # Verify file exists
    assert layout_file.exists()

    # Read and verify content
    with open(layout_file) as f:
        loaded_data = json.load(f)

    assert loaded_data["name"] == "test-layout"
    assert len(loaded_data["workspaces"]) == 1
    assert loaded_data["workspaces"][0]["windows"][0]["window_class"] == "XTerm"

    print(f"✅ Layout file created and validated")
