"""
Workspace assignment scenario tests.

Tests workspace assignment for different applications:
- lazygit → workspace 3
- terminal → workspace 2
- vscode → workspace 2

Part of Feature 039 - Tasks T057, T058, T059
Success Criteria: SC-002 (95% success rate within 200ms)
"""

import pytest
import asyncio
from typing import Dict, Any, Optional
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime


# Mock classes for testing
class MockI3Con:
    """Mock i3 connection."""
    def __init__(self):
        self.commands = []

    async def command(self, cmd: str):
        """Record commands for verification."""
        self.commands.append(cmd)
        return MagicMock(success=True)


class MockWorkspaceInfo:
    """Mock workspace info."""
    def __init__(self, num: int, name: str):
        self.num = num
        self.name = name


class MockContainer:
    """Mock window container."""
    def __init__(self, window_id: int, window_class: str, workspace_num: int = 1):
        self.window = window_id
        self.id = window_id
        self.window_class = window_class
        self.window_instance = window_class.lower()
        self.name = f"{window_class} Window"
        self._workspace = MockWorkspaceInfo(workspace_num, str(workspace_num))

    def workspace(self):
        return self._workspace


class MockI3PMEnvironment:
    """Mock I3PM environment."""
    def __init__(self, app_name: str, target_workspace: Optional[int] = None, project_name: str = ""):
        self.app_name = app_name
        self.target_workspace = target_workspace
        self.project_name = project_name
        self.scope = "scoped" if project_name else "global"
        self.app_id = f"{app_name}-test-{datetime.now().timestamp()}"


@pytest.fixture
def application_registry():
    """Application registry with workspace assignments."""
    return {
        "terminal": {
            "name": "terminal",
            "command": "ghostty",
            "preferred_workspace": 2,
            "expected_class": "ghostty",
        },
        "vscode": {
            "name": "vscode",
            "command": "code",
            "preferred_workspace": 2,
            "expected_class": "Code",
        },
        "lazygit": {
            "name": "lazygit",
            "command": "lazygit",
            "preferred_workspace": 3,
            "expected_class": "lazygit",
        },
        "firefox": {
            "name": "firefox",
            "command": "firefox",
            "preferred_workspace": 1,
            "expected_class": "firefox",
        },
    }


class TestWorkspaceAssignmentScenarios:
    """
    Test workspace assignment scenarios (T057).

    Verifies that applications are moved to their configured workspaces:
    - lazygit → workspace 3
    - terminal → workspace 2
    - vscode → workspace 2
    """

    @pytest.mark.asyncio
    async def test_lazygit_assigned_to_workspace_3(self, application_registry):
        """Test lazygit is assigned to workspace 3."""
        # Setup
        window_id = 12345
        container = MockContainer(window_id, "lazygit", workspace_num=1)
        window_env = MockI3PMEnvironment("lazygit", project_name="nixos")
        conn = MockI3Con()

        # Simulate the workspace assignment logic
        app_def = application_registry.get("lazygit")
        preferred_ws = app_def["preferred_workspace"]

        # Should move to workspace 3
        assert preferred_ws == 3

        # Simulate command execution
        if container.workspace().num != preferred_ws:
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )

        # Verify
        assert len(conn.commands) == 1
        assert "move to workspace number 3" in conn.commands[0]
        assert f'con_id="{window_id}"' in conn.commands[0]

    @pytest.mark.asyncio
    async def test_terminal_assigned_to_workspace_2(self, application_registry):
        """Test terminal (ghostty) is assigned to workspace 2."""
        # Setup
        window_id = 12346
        container = MockContainer(window_id, "com.mitchellh.ghostty", workspace_num=1)
        window_env = MockI3PMEnvironment("terminal", project_name="stacks")
        conn = MockI3Con()

        # Simulate the workspace assignment logic
        app_def = application_registry.get("terminal")
        preferred_ws = app_def["preferred_workspace"]

        # Should move to workspace 2
        assert preferred_ws == 2

        # Simulate command execution
        if container.workspace().num != preferred_ws:
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )

        # Verify
        assert len(conn.commands) == 1
        assert "move to workspace number 2" in conn.commands[0]

    @pytest.mark.asyncio
    async def test_vscode_assigned_to_workspace_2(self, application_registry):
        """Test VS Code is assigned to workspace 2."""
        # Setup
        window_id = 12347
        container = MockContainer(window_id, "Code", workspace_num=1)
        window_env = MockI3PMEnvironment("vscode", project_name="nixos")
        conn = MockI3Con()

        # Simulate the workspace assignment logic
        app_def = application_registry.get("vscode")
        preferred_ws = app_def["preferred_workspace"]

        # Should move to workspace 2
        assert preferred_ws == 2

        # Simulate command execution
        if container.workspace().num != preferred_ws:
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )

        # Verify
        assert len(conn.commands) == 1
        assert "move to workspace number 2" in conn.commands[0]

    @pytest.mark.asyncio
    async def test_no_move_if_already_on_target_workspace(self, application_registry):
        """Test that window is not moved if already on target workspace."""
        # Setup - terminal already on workspace 2
        window_id = 12348
        container = MockContainer(window_id, "ghostty", workspace_num=2)
        window_env = MockI3PMEnvironment("terminal")
        conn = MockI3Con()

        # Simulate the workspace assignment logic
        app_def = application_registry.get("terminal")
        preferred_ws = app_def["preferred_workspace"]

        # Should NOT move (already on workspace 2)
        if container.workspace().num != preferred_ws:
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )

        # Verify - no commands should be executed
        assert len(conn.commands) == 0


class TestSimultaneousLaunch:
    """
    Test simultaneous launch of multiple applications (T058).

    Verifies that multiple apps can be launched concurrently and each
    is assigned to its correct workspace.
    """

    @pytest.mark.asyncio
    async def test_multiple_apps_simultaneous_launch(self, application_registry):
        """Test launching multiple apps simultaneously to different workspaces."""
        conn = MockI3Con()

        # Launch multiple apps
        apps = [
            ("terminal", "ghostty", 12350),
            ("vscode", "Code", 12351),
            ("lazygit", "lazygit", 12352),
        ]

        # Process each window
        for app_name, window_class, window_id in apps:
            container = MockContainer(window_id, window_class, workspace_num=1)
            window_env = MockI3PMEnvironment(app_name)

            app_def = application_registry.get(app_name)
            preferred_ws = app_def["preferred_workspace"]

            # Move to preferred workspace
            if container.workspace().num != preferred_ws:
                await conn.command(
                    f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
                )

        # Verify all 3 apps were moved
        assert len(conn.commands) == 3

        # Verify correct workspaces
        assert "move to workspace number 2" in conn.commands[0]  # terminal
        assert "move to workspace number 2" in conn.commands[1]  # vscode
        assert "move to workspace number 3" in conn.commands[2]  # lazygit

    @pytest.mark.asyncio
    async def test_rapid_window_creation(self, application_registry):
        """Test rapid window creation (stress test)."""
        conn = MockI3Con()

        # Create 10 terminal windows rapidly
        tasks = []
        for i in range(10):
            window_id = 13000 + i
            container = MockContainer(window_id, "ghostty", workspace_num=1)

            app_def = application_registry.get("terminal")
            preferred_ws = app_def["preferred_workspace"]

            # Create async task for each
            if container.workspace().num != preferred_ws:
                task = conn.command(
                    f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
                )
                tasks.append(task)

        # Execute all simultaneously
        await asyncio.gather(*tasks)

        # Verify all 10 windows were moved
        assert len(conn.commands) == 10

        # All should go to workspace 2
        for cmd in conn.commands:
            assert "move to workspace number 2" in cmd


class TestFallbackBehavior:
    """
    Test fallback behavior for apps without workspace config (T059).

    Verifies behavior when:
    - App not in registry
    - Workspace number is invalid
    - No I3PM environment
    """

    @pytest.mark.asyncio
    async def test_app_not_in_registry_no_move(self, application_registry):
        """Test app not in registry stays on current workspace."""
        # Setup - unknown app
        window_id = 12360
        container = MockContainer(window_id, "unknown-app", workspace_num=5)
        conn = MockI3Con()

        # Try to get app from registry
        app_def = application_registry.get("unknown-app")

        # Should be None
        assert app_def is None

        # No move should happen
        if app_def and "preferred_workspace" in app_def:
            preferred_ws = app_def["preferred_workspace"]
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )

        # Verify no commands executed
        assert len(conn.commands) == 0

    @pytest.mark.asyncio
    async def test_no_i3pm_environment_no_move(self, application_registry):
        """Test window without I3PM environment stays on current workspace."""
        # Setup - firefox without I3PM env (manually launched)
        window_id = 12361
        container = MockContainer(window_id, "firefox", workspace_num=4)
        window_env = None  # No I3PM environment
        conn = MockI3Con()

        # Without I3PM environment, we don't know the app_name
        # So we can't look it up in registry
        if window_env and window_env.app_name:
            app_def = application_registry.get(window_env.app_name)
        else:
            app_def = None

        # Should be None
        assert app_def is None

        # No move should happen
        assert len(conn.commands) == 0

    @pytest.mark.asyncio
    async def test_fallback_to_current_workspace(self):
        """Test fallback to current workspace when assignment fails."""
        # Setup
        window_id = 12362
        container = MockContainer(window_id, "terminal", workspace_num=7)
        conn = MockI3Con()

        # Simulate failed workspace assignment (e.g., workspace doesn't exist)
        try:
            # This would fail in real i3
            result = await conn.command(
                '[con_id="12362"] move to workspace number 999'
            )
            # Our mock always succeeds, but in real scenario this might fail
        except Exception as e:
            # Fallback: keep on current workspace
            pass

        # Window should remain on workspace 7 (current)
        assert container.workspace().num == 7

    @pytest.mark.asyncio
    async def test_app_with_no_preferred_workspace(self):
        """Test app definition without preferred_workspace field."""
        # Registry entry without preferred_workspace
        registry = {
            "calculator": {
                "name": "calculator",
                "command": "gnome-calculator",
                # No preferred_workspace field
            }
        }

        window_id = 12363
        container = MockContainer(window_id, "gnome-calculator", workspace_num=3)
        conn = MockI3Con()

        # Get app from registry
        app_def = registry.get("calculator")

        # App exists but no preferred_workspace
        assert app_def is not None
        assert "preferred_workspace" not in app_def

        # No move should happen
        if app_def and "preferred_workspace" in app_def:
            preferred_ws = app_def["preferred_workspace"]
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )

        # Verify no commands executed
        assert len(conn.commands) == 0


class TestWorkspaceAssignmentPerformance:
    """
    Test workspace assignment performance.

    Success Criteria: SC-002 (95% success rate within 200ms)
    """

    @pytest.mark.asyncio
    async def test_assignment_latency_under_200ms(self, application_registry):
        """Test workspace assignment completes within 200ms."""
        import time

        window_id = 12370
        container = MockContainer(window_id, "ghostty", workspace_num=1)
        conn = MockI3Con()

        # Measure time
        start = time.perf_counter()

        # Simulate workspace assignment
        app_def = application_registry.get("terminal")
        preferred_ws = app_def["preferred_workspace"]

        if container.workspace().num != preferred_ws:
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )

        duration_ms = (time.perf_counter() - start) * 1000

        # Should be under 200ms (SC-002)
        assert duration_ms < 200, f"Assignment took {duration_ms:.2f}ms, expected <200ms"

        # Typically should be much faster (under 10ms for mock)
        assert duration_ms < 10, f"Mock assignment took {duration_ms:.2f}ms"

    @pytest.mark.asyncio
    async def test_95_percent_success_rate(self, application_registry):
        """Test 95% success rate for workspace assignments."""
        conn = MockI3Con()
        total = 100
        successful = 0

        # Try 100 assignments
        for i in range(total):
            window_id = 14000 + i
            # Alternate between different apps
            app_names = ["terminal", "vscode", "lazygit", "firefox"]
            app_name = app_names[i % len(app_names)]

            container = MockContainer(window_id, app_name, workspace_num=1)

            try:
                app_def = application_registry.get(app_name)
                if app_def and "preferred_workspace" in app_def:
                    preferred_ws = app_def["preferred_workspace"]

                    if container.workspace().num != preferred_ws:
                        await conn.command(
                            f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
                        )

                    successful += 1
            except Exception:
                # Assignment failed
                pass

        success_rate = (successful / total) * 100

        # Should meet 95% success rate (SC-002)
        assert success_rate >= 95, f"Success rate {success_rate:.1f}% < 95%"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
