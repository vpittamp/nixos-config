"""
Integration tests for workspace assignment functionality.

Tests the 4-tier workspace assignment priority system:
1. App-specific handlers (VS Code title parsing)
2. I3PM_TARGET_WORKSPACE environment variable
3. I3PM_APP_NAME registry lookup
4. Window class matching

Part of Feature 039 - Task T021
Success Criteria: SC-011 (10+ app types tested), SC-002 (95% success rate, <200ms latency)
"""

import pytest
import asyncio
from pathlib import Path
from typing import Dict, Any
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop"))

from i3_project_event_daemon.models import I3PMEnvironment, WindowIdentity


@pytest.mark.asyncio
class TestWorkspaceAssignment:
    """Integration tests for workspace assignment."""

    @pytest.fixture
    async def mock_daemon(self):
        """Mock daemon with application registry."""
        # Import mock daemon from fixtures
        from tests.i3_project_daemon.fixtures.mock_daemon import MockDaemon

        daemon = MockDaemon()
        await daemon.initialize()
        yield daemon
        await daemon.cleanup()

    @pytest.fixture
    def sample_registry(self) -> Dict[str, Any]:
        """Sample application registry with 10+ app types."""
        return {
            "terminal": {
                "name": "terminal",
                "display_name": "Ghostty Terminal",
                "command": "ghostty",
                "scope": "scoped",
                "preferred_workspace": 2,
                "expected_class": "com.mitchellh.ghostty",
                "expected_title_contains": None,
                "multi_instance": True
            },
            "vscode": {
                "name": "vscode",
                "display_name": "VS Code",
                "command": "code",
                "scope": "scoped",
                "preferred_workspace": 2,
                "expected_class": "Code",
                "expected_title_contains": "Visual Studio Code",
                "multi_instance": True
            },
            "lazygit": {
                "name": "lazygit",
                "display_name": "LazyGit",
                "command": "lazygit",
                "scope": "scoped",
                "preferred_workspace": 3,
                "expected_class": "com.mitchellh.ghostty",
                "expected_title_contains": "lazygit",
                "multi_instance": True
            },
            "yazi": {
                "name": "yazi",
                "display_name": "Yazi File Manager",
                "command": "yazi",
                "scope": "scoped",
                "preferred_workspace": 1,
                "expected_class": "com.mitchellh.ghostty",
                "expected_title_contains": "yazi",
                "multi_instance": True
            },
            "firefox": {
                "name": "firefox",
                "display_name": "Firefox Browser",
                "command": "firefox",
                "scope": "global",
                "preferred_workspace": 1,
                "expected_class": "firefox",
                "expected_title_contains": None,
                "multi_instance": False
            },
            "k9s": {
                "name": "k9s",
                "display_name": "K9s Kubernetes",
                "command": "k9s",
                "scope": "global",
                "preferred_workspace": 4,
                "expected_class": "com.mitchellh.ghostty",
                "expected_title_contains": "k9s",
                "multi_instance": False
            },
            "youtube-pwa": {
                "name": "youtube-pwa",
                "display_name": "YouTube PWA",
                "command": "firefox-pwa",
                "scope": "global",
                "preferred_workspace": 5,
                "expected_class": "FFPWA-01234567890",
                "expected_title_contains": "YouTube",
                "multi_instance": False
            },
            "google-chat-pwa": {
                "name": "google-chat-pwa",
                "display_name": "Google Chat PWA",
                "command": "firefox-pwa",
                "scope": "scoped",
                "preferred_workspace": 6,
                "expected_class": "FFPWA-chat12345",
                "expected_title_contains": "Chat",
                "multi_instance": False
            },
            "calculator": {
                "name": "calculator",
                "display_name": "Calculator",
                "command": "gnome-calculator",
                "scope": "global",
                "preferred_workspace": 7,
                "expected_class": "gnome-calculator",
                "expected_title_contains": None,
                "multi_instance": False
            },
            "file-manager": {
                "name": "file-manager",
                "display_name": "Dolphin File Manager",
                "command": "dolphin",
                "scope": "global",
                "preferred_workspace": 1,
                "expected_class": "dolphin",
                "expected_title_contains": None,
                "multi_instance": True
            }
        }

    async def test_priority_1_app_specific_handler_vscode(self, mock_daemon, sample_registry):
        """
        Test Priority 1: App-specific handler (VS Code title parsing).

        VS Code uses shared PID for all windows, so title parsing is more reliable
        than environment variables.
        """
        mock_daemon.set_registry(sample_registry)

        # Simulate VS Code window with project name in title
        window_id = 12345
        window_class = "Code"
        window_title = "stacks - nixos - Visual Studio Code"
        window_pid = 823199

        # Mock environment (same for all VS Code windows due to shared PID)
        i3pm_env = I3PMEnvironment(
            app_id="vscode-nixos-823199-1730000000",
            app_name="vscode",
            target_workspace=None,  # Not set for VS Code
            project_name="nixos",  # This might be wrong due to shared PID
            scope="scoped",
            launch_time=1730000000,
            launcher_pid=823150
        )

        # Test workspace assignment
        result = await mock_daemon.assign_workspace(
            window_id, window_class, window_title, window_pid, i3pm_env
        )

        # VS Code should use title-based project detection, not environment
        # Project "stacks" from title should override environment "nixos"
        assert result["success"] is True
        assert result["workspace"] == 2  # vscode preferred_workspace
        assert result["source"] == "app_specific_handler"
        assert result["project_override"] == "stacks"
        assert result["duration_ms"] < 200  # SC-002

    async def test_priority_2_i3pm_target_workspace(self, mock_daemon, sample_registry):
        """
        Test Priority 2: I3PM_TARGET_WORKSPACE environment variable.

        Direct workspace assignment bypasses registry lookup.
        """
        mock_daemon.set_registry(sample_registry)

        window_id = 12346
        window_class = "com.mitchellh.ghostty"
        window_title = "terminal"
        window_pid = 823200

        # Environment with explicit target workspace
        i3pm_env = I3PMEnvironment(
            app_id="terminal-stacks-823200-1730000001",
            app_name="terminal",
            target_workspace=3,  # Explicit assignment
            project_name="stacks",
            scope="scoped",
            launch_time=1730000001,
            launcher_pid=823151
        )

        result = await mock_daemon.assign_workspace(
            window_id, window_class, window_title, window_pid, i3pm_env
        )

        assert result["success"] is True
        assert result["workspace"] == 3  # Uses I3PM_TARGET_WORKSPACE
        assert result["source"] == "i3pm_target_workspace"
        assert result["duration_ms"] < 200

    async def test_priority_3_i3pm_app_name_lookup(self, mock_daemon, sample_registry):
        """
        Test Priority 3: I3PM_APP_NAME registry lookup.

        Fallback when no explicit target_workspace, looks up app in registry.
        """
        mock_daemon.set_registry(sample_registry)

        window_id = 12347
        window_class = "gnome-calculator"
        window_title = "Calculator"
        window_pid = 823201

        # Environment with app_name but no target_workspace
        i3pm_env = I3PMEnvironment(
            app_id="calculator-823201-1730000002",
            app_name="calculator",
            target_workspace=None,  # Not explicitly set
            project_name=None,  # Global app
            scope="global",
            launch_time=1730000002,
            launcher_pid=823152
        )

        result = await mock_daemon.assign_workspace(
            window_id, window_class, window_title, window_pid, i3pm_env
        )

        assert result["success"] is True
        assert result["workspace"] == 7  # calculator preferred_workspace from registry
        assert result["source"] == "i3pm_app_name_lookup"
        assert result["duration_ms"] < 200

    async def test_priority_4_window_class_matching(self, mock_daemon, sample_registry):
        """
        Test Priority 4: Window class matching (no environment variables).

        Last resort for manually launched applications.
        """
        mock_daemon.set_registry(sample_registry)

        window_id = 12348
        window_class = "firefox"
        window_title = "Mozilla Firefox"
        window_pid = 823202

        # No I3PM environment (manually launched)
        i3pm_env = None

        result = await mock_daemon.assign_workspace(
            window_id, window_class, window_title, window_pid, i3pm_env
        )

        assert result["success"] is True
        assert result["workspace"] == 1  # firefox preferred_workspace from registry
        assert result["source"] == "window_class_match"
        assert result["duration_ms"] < 200

    async def test_fallback_current_workspace(self, mock_daemon, sample_registry):
        """Test fallback to current workspace when no rules match."""
        mock_daemon.set_registry(sample_registry)

        window_id = 12349
        window_class = "unknown-app"
        window_title = "Unknown Application"
        window_pid = 823203

        # No environment
        i3pm_env = None

        # Mock current workspace
        mock_daemon.set_current_workspace(5)

        result = await mock_daemon.assign_workspace(
            window_id, window_class, window_title, window_pid, i3pm_env
        )

        assert result["success"] is True
        assert result["workspace"] == 5  # Falls back to current
        assert result["source"] == "fallback_current"
        assert result["duration_ms"] < 200

    async def test_multiple_apps_same_class_different_titles(self, mock_daemon, sample_registry):
        """
        Test differentiation of apps with same class but different titles.

        Example: terminal, lazygit, yazi, k9s all use ghostty class.
        """
        mock_daemon.set_registry(sample_registry)

        # Test lazygit
        result_lazygit = await mock_daemon.assign_workspace(
            12350,
            "com.mitchellh.ghostty",
            "lazygit",
            823204,
            I3PMEnvironment(
                app_id="lazygit-stacks-823204-1730000003",
                app_name="lazygit",
                target_workspace=None,
                project_name="stacks",
                scope="scoped",
                launch_time=1730000003,
                launcher_pid=823153
            )
        )

        # Test yazi
        result_yazi = await mock_daemon.assign_workspace(
            12351,
            "com.mitchellh.ghostty",
            "yazi",
            823205,
            I3PMEnvironment(
                app_id="yazi-stacks-823205-1730000004",
                app_name="yazi",
                target_workspace=None,
                project_name="stacks",
                scope="scoped",
                launch_time=1730000004,
                launcher_pid=823154
            )
        )

        # Test k9s
        result_k9s = await mock_daemon.assign_workspace(
            12352,
            "com.mitchellh.ghostty",
            "k9s",
            823206,
            I3PMEnvironment(
                app_id="k9s-823206-1730000005",
                app_name="k9s",
                target_workspace=None,
                project_name=None,
                scope="global",
                launch_time=1730000005,
                launcher_pid=823155
            )
        )

        assert result_lazygit["workspace"] == 3  # lazygit workspace
        assert result_yazi["workspace"] == 1  # yazi workspace
        assert result_k9s["workspace"] == 4  # k9s workspace

    async def test_performance_10_concurrent_assignments(self, mock_daemon, sample_registry):
        """
        Test performance with 10 concurrent workspace assignments.

        Success Criteria: SC-002 (95% success, <200ms each)
        """
        mock_daemon.set_registry(sample_registry)

        # Create 10 windows simultaneously
        tasks = []
        for i in range(10):
            app_name = list(sample_registry.keys())[i]
            app_config = sample_registry[app_name]

            i3pm_env = I3PMEnvironment(
                app_id=f"{app_name}-test-{823300 + i}-1730000100",
                app_name=app_name,
                target_workspace=None,
                project_name="test",
                scope=app_config["scope"],
                launch_time=1730000100,
                launcher_pid=823300 + i
            )

            task = mock_daemon.assign_workspace(
                13000 + i,
                app_config["expected_class"],
                f"{app_config['display_name']} Window",
                823300 + i,
                i3pm_env
            )
            tasks.append(task)

        # Execute all assignments concurrently
        results = await asyncio.gather(*tasks)

        # Verify success rate
        successful = sum(1 for r in results if r["success"])
        success_rate = successful / len(results)

        assert success_rate >= 0.95  # SC-002: 95% success rate

        # Verify latency
        max_latency = max(r["duration_ms"] for r in results)
        assert max_latency < 200  # SC-002: <200ms latency

    async def test_pwa_instance_differentiation(self, mock_daemon, sample_registry):
        """
        Test PWA instance differentiation by window class.

        YouTube PWA and Google Chat PWA have different expected_class values.
        """
        mock_daemon.set_registry(sample_registry)

        # YouTube PWA
        result_youtube = await mock_daemon.assign_workspace(
            12353,
            "FFPWA-01234567890",
            "YouTube",
            823207,
            I3PMEnvironment(
                app_id="youtube-pwa-823207-1730000006",
                app_name="youtube-pwa",
                target_workspace=None,
                project_name=None,
                scope="global",
                launch_time=1730000006,
                launcher_pid=823156
            )
        )

        # Google Chat PWA
        result_chat = await mock_daemon.assign_workspace(
            12354,
            "FFPWA-chat12345",
            "Google Chat",
            823208,
            I3PMEnvironment(
                app_id="google-chat-pwa-nixos-823208-1730000007",
                app_name="google-chat-pwa",
                target_workspace=None,
                project_name="nixos",
                scope="scoped",
                launch_time=1730000007,
                launcher_pid=823157
            )
        )

        assert result_youtube["workspace"] == 5  # YouTube workspace
        assert result_chat["workspace"] == 6  # Google Chat workspace
        assert result_youtube["source"] == "i3pm_app_name_lookup"
        assert result_chat["source"] == "i3pm_app_name_lookup"


@pytest.mark.asyncio
class TestWorkspaceAssignmentEdgeCases:
    """Edge case tests for workspace assignment."""

    @pytest.fixture
    async def mock_daemon(self):
        from tests.i3_project_daemon.fixtures.mock_daemon import MockDaemon
        daemon = MockDaemon()
        await daemon.initialize()
        yield daemon
        await daemon.cleanup()

    async def test_workspace_out_of_range(self, mock_daemon):
        """Test handling of invalid workspace numbers."""
        mock_daemon.set_registry({
            "invalid-app": {
                "name": "invalid-app",
                "preferred_workspace": 99,  # Out of range (1-10)
                "expected_class": "invalid",
                "scope": "global"
            }
        })

        result = await mock_daemon.assign_workspace(
            12355, "invalid", "Invalid", 823209, None
        )

        # Should fall back to current workspace
        assert result["success"] is True
        assert result["source"] == "fallback_current"

    async def test_missing_registry(self, mock_daemon):
        """Test workspace assignment with no registry loaded."""
        # Don't set registry

        i3pm_env = I3PMEnvironment(
            app_id="terminal-823210-1730000008",
            app_name="terminal",
            target_workspace=3,  # Should still work
            project_name="test",
            scope="scoped",
            launch_time=1730000008,
            launcher_pid=823158
        )

        result = await mock_daemon.assign_workspace(
            12356, "ghostty", "terminal", 823210, i3pm_env
        )

        # Priority 2 should work without registry
        assert result["success"] is True
        assert result["workspace"] == 3
        assert result["source"] == "i3pm_target_workspace"

    async def test_window_pid_missing(self, mock_daemon):
        """Test handling when window PID cannot be determined."""
        mock_daemon.set_registry({
            "test-app": {
                "name": "test-app",
                "preferred_workspace": 5,
                "expected_class": "test",
                "scope": "global"
            }
        })

        # PID is 0 or None
        result = await mock_daemon.assign_workspace(
            12357, "test", "Test App", None, None
        )

        # Should still work using window class matching
        assert result["success"] is True
        assert result["workspace"] == 5
        assert result["source"] == "window_class_match"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
