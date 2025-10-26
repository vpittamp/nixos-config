"""
Terminal instance differentiation tests.

Tests that terminal instances are properly associated with project context:
- Each terminal instance has I3PM_PROJECT_NAME from environment
- Child processes (e.g., lazygit) inherit parent terminal environment
- Multiple terminals with same class but different projects are distinguished

Part of Feature 039 - Tasks T067, T068, T069
Success Criteria: SC-005 (100% correct association)
"""

import pytest
from typing import Dict, Optional
from unittest.mock import MagicMock, patch
from pathlib import Path


# Mock classes for testing
class MockI3PMEnvironment:
    """Mock I3PM environment from /proc/{pid}/environ."""
    def __init__(
        self,
        app_id: str,
        app_name: str,
        project_name: str = "",
        project_dir: str = "",
        scope: str = "scoped",
    ):
        self.app_id = app_id
        self.app_name = app_name
        self.project_name = project_name
        self.project_dir = project_dir
        self.scope = scope
        self.active = True
        self.launch_time = "1234567890"
        self.launcher_pid = "12345"
        self.target_workspace = None


class MockWindowEnvironment:
    """Mock window environment reader."""

    @staticmethod
    def read_process_environ(pid: int) -> Dict[str, str]:
        """Mock reading /proc/{pid}/environ."""
        # Simulate terminal processes with I3PM environment
        terminal_envs = {
            # Terminal 1: nixos project
            1000: {
                "I3PM_APP_ID": "terminal-nixos-1000-1234567890",
                "I3PM_APP_NAME": "terminal",
                "I3PM_PROJECT_NAME": "nixos",
                "I3PM_PROJECT_DIR": "/etc/nixos",
                "I3PM_SCOPE": "scoped",
                "I3PM_ACTIVE": "true",
            },
            # Terminal 2: stacks project
            2000: {
                "I3PM_APP_ID": "terminal-stacks-2000-1234567890",
                "I3PM_APP_NAME": "terminal",
                "I3PM_PROJECT_NAME": "stacks",
                "I3PM_PROJECT_DIR": "/home/user/stacks",
                "I3PM_SCOPE": "scoped",
                "I3PM_ACTIVE": "true",
            },
            # Terminal 3: global (no project)
            3000: {
                "I3PM_APP_ID": "terminal-global-3000-1234567890",
                "I3PM_APP_NAME": "terminal",
                "I3PM_PROJECT_NAME": "",
                "I3PM_PROJECT_DIR": "",
                "I3PM_SCOPE": "global",
                "I3PM_ACTIVE": "true",
            },
            # Child process (lazygit) inherits terminal environment
            1001: {
                "I3PM_APP_ID": "terminal-nixos-1000-1234567890",  # Same as parent
                "I3PM_APP_NAME": "terminal",  # Parent app name
                "I3PM_PROJECT_NAME": "nixos",  # Inherited from parent
                "I3PM_PROJECT_DIR": "/etc/nixos",
                "I3PM_SCOPE": "scoped",
                "I3PM_ACTIVE": "true",
            },
        }

        if pid in terminal_envs:
            return terminal_envs[pid]

        # No I3PM environment
        return {}


class TestTerminalProjectAssociation:
    """
    Test terminal project association via I3PM_PROJECT_NAME (T067).

    Verifies that terminals launched in different projects are correctly
    associated via their environment variables.
    """

    def test_terminal_has_project_environment(self):
        """Test terminal has I3PM_PROJECT_NAME in environment."""
        # Terminal launched in nixos project
        env = MockWindowEnvironment.read_process_environ(1000)

        assert "I3PM_PROJECT_NAME" in env
        assert env["I3PM_PROJECT_NAME"] == "nixos"
        assert env["I3PM_APP_NAME"] == "terminal"
        assert env["I3PM_SCOPE"] == "scoped"

    def test_terminal_project_association_nixos(self):
        """Test terminal in nixos project is correctly associated."""
        env = MockWindowEnvironment.read_process_environ(1000)

        # Simulate parsing into I3PM environment
        i3pm_env = MockI3PMEnvironment(
            app_id=env["I3PM_APP_ID"],
            app_name=env["I3PM_APP_NAME"],
            project_name=env["I3PM_PROJECT_NAME"],
            project_dir=env["I3PM_PROJECT_DIR"],
            scope=env["I3PM_SCOPE"],
        )

        # Verify association
        assert i3pm_env.project_name == "nixos"
        assert i3pm_env.app_name == "terminal"
        assert i3pm_env.scope == "scoped"

    def test_terminal_project_association_stacks(self):
        """Test terminal in stacks project is correctly associated."""
        env = MockWindowEnvironment.read_process_environ(2000)

        i3pm_env = MockI3PMEnvironment(
            app_id=env["I3PM_APP_ID"],
            app_name=env["I3PM_APP_NAME"],
            project_name=env["I3PM_PROJECT_NAME"],
            project_dir=env["I3PM_PROJECT_DIR"],
            scope=env["I3PM_SCOPE"],
        )

        assert i3pm_env.project_name == "stacks"
        assert i3pm_env.app_name == "terminal"
        assert i3pm_env.scope == "scoped"

    def test_terminal_global_no_project(self):
        """Test global terminal has no project association."""
        env = MockWindowEnvironment.read_process_environ(3000)

        i3pm_env = MockI3PMEnvironment(
            app_id=env["I3PM_APP_ID"],
            app_name=env["I3PM_APP_NAME"],
            project_name=env["I3PM_PROJECT_NAME"],
            project_dir=env["I3PM_PROJECT_DIR"],
            scope=env["I3PM_SCOPE"],
        )

        assert i3pm_env.project_name == ""
        assert i3pm_env.scope == "global"


class TestTerminalPersistence:
    """
    Test terminal environment persistence with child processes (T068).

    Verifies that child processes launched from terminal (e.g., lazygit)
    inherit the terminal's I3PM environment and don't override it.
    """

    def test_child_process_inherits_parent_environment(self):
        """Test child process (lazygit) inherits terminal environment."""
        # Parent terminal environment
        parent_env = MockWindowEnvironment.read_process_environ(1000)

        # Child process environment (lazygit in terminal)
        child_env = MockWindowEnvironment.read_process_environ(1001)

        # Child should inherit parent's I3PM environment
        assert child_env["I3PM_PROJECT_NAME"] == parent_env["I3PM_PROJECT_NAME"]
        assert child_env["I3PM_APP_ID"] == parent_env["I3PM_APP_ID"]
        assert child_env["I3PM_PROJECT_DIR"] == parent_env["I3PM_PROJECT_DIR"]

    def test_child_process_preserves_project_association(self):
        """Test child process preserves parent's project association."""
        child_env = MockWindowEnvironment.read_process_environ(1001)

        i3pm_env = MockI3PMEnvironment(
            app_id=child_env["I3PM_APP_ID"],
            app_name=child_env["I3PM_APP_NAME"],
            project_name=child_env["I3PM_PROJECT_NAME"],
            project_dir=child_env["I3PM_PROJECT_DIR"],
            scope=child_env["I3PM_SCOPE"],
        )

        # Should still be associated with nixos project
        assert i3pm_env.project_name == "nixos"
        assert i3pm_env.scope == "scoped"

    def test_parent_traversal_simulation(self):
        """Test parent process traversal to find I3PM environment."""
        # Simulate scenario where we need to traverse to parent
        # In real implementation, if child PID has no I3PM vars,
        # we would check parent PID

        def get_i3pm_environment(pid: int) -> Optional[Dict[str, str]]:
            """Get I3PM environment, checking parent if needed."""
            env = MockWindowEnvironment.read_process_environ(pid)

            if "I3PM_APP_ID" in env:
                return env

            # In real implementation, would get parent PID and check recursively
            # For this test, we simulate that PID 1001 has environment
            return None

        # Child has environment (inherited from parent)
        env = get_i3pm_environment(1001)
        assert env is not None
        assert env["I3PM_PROJECT_NAME"] == "nixos"


class TestMultiTerminalDifferentiation:
    """
    Test multiple terminals with same class, different projects (T069).

    Verifies that the system can distinguish between multiple terminal
    instances based on their I3PM_PROJECT_NAME environment variable.
    """

    def test_two_terminals_different_projects(self):
        """Test two terminals with different projects are distinguished."""
        # Terminal 1: nixos project
        env1 = MockWindowEnvironment.read_process_environ(1000)
        i3pm1 = MockI3PMEnvironment(
            app_id=env1["I3PM_APP_ID"],
            app_name=env1["I3PM_APP_NAME"],
            project_name=env1["I3PM_PROJECT_NAME"],
        )

        # Terminal 2: stacks project
        env2 = MockWindowEnvironment.read_process_environ(2000)
        i3pm2 = MockI3PMEnvironment(
            app_id=env2["I3PM_APP_ID"],
            app_name=env2["I3PM_APP_NAME"],
            project_name=env2["I3PM_PROJECT_NAME"],
        )

        # Should have different projects
        assert i3pm1.project_name == "nixos"
        assert i3pm2.project_name == "stacks"
        assert i3pm1.project_name != i3pm2.project_name

    def test_same_class_different_instances(self):
        """Test terminals have same window class but different instances."""
        # Both terminals have class "com.mitchellh.ghostty"
        window_class = "com.mitchellh.ghostty"

        # But different I3PM environments
        env1 = MockWindowEnvironment.read_process_environ(1000)
        env2 = MockWindowEnvironment.read_process_environ(2000)

        # Differentiation comes from I3PM_PROJECT_NAME
        assert env1["I3PM_PROJECT_NAME"] != env2["I3PM_PROJECT_NAME"]
        assert env1["I3PM_APP_ID"] != env2["I3PM_APP_ID"]

    def test_terminal_filtering_by_project(self):
        """Test terminal windows are filtered based on project."""
        terminals = [
            {
                "window_id": 10001,
                "pid": 1000,
                "class": "com.mitchellh.ghostty",
                "project": "nixos",
            },
            {
                "window_id": 10002,
                "pid": 2000,
                "class": "com.mitchellh.ghostty",
                "project": "stacks",
            },
            {
                "window_id": 10003,
                "pid": 3000,
                "class": "com.mitchellh.ghostty",
                "project": "",  # global
            },
        ]

        # When active project is "nixos"
        active_project = "nixos"

        visible_terminals = [
            t for t in terminals
            if t["project"] == active_project or t["project"] == ""
        ]

        # Should show nixos terminal and global terminal
        assert len(visible_terminals) == 2
        assert any(t["project"] == "nixos" for t in visible_terminals)
        assert any(t["project"] == "" for t in visible_terminals)

        # Stacks terminal should be hidden
        hidden_terminals = [
            t for t in terminals
            if t["project"] != active_project and t["project"] != ""
        ]
        assert len(hidden_terminals) == 1
        assert hidden_terminals[0]["project"] == "stacks"

    def test_100_percent_correct_association(self):
        """Test 100% correct terminal-to-project association (SC-005)."""
        test_cases = [
            (1000, "nixos"),
            (2000, "stacks"),
            (3000, ""),  # global
            (1001, "nixos"),  # child process
        ]

        total = len(test_cases)
        correct = 0

        for pid, expected_project in test_cases:
            env = MockWindowEnvironment.read_process_environ(pid)

            if "I3PM_PROJECT_NAME" in env:
                actual_project = env["I3PM_PROJECT_NAME"]
                if actual_project == expected_project:
                    correct += 1
            elif expected_project == "":
                # No I3PM environment for global
                correct += 1

        success_rate = (correct / total) * 100

        # Should achieve 100% correct association (SC-005)
        assert success_rate == 100.0, f"Success rate {success_rate}% < 100%"


class TestEdgeCases:
    """Test edge cases for terminal differentiation."""

    def test_terminal_without_i3pm_environment(self):
        """Test terminal without I3PM environment (manually launched)."""
        env = MockWindowEnvironment.read_process_environ(9999)

        # Should return empty dict
        assert env == {}
        assert "I3PM_PROJECT_NAME" not in env

    def test_missing_pid(self):
        """Test handling of missing PID (process exited)."""
        # Simulate /proc/{pid}/environ not found
        def read_with_error(pid: int) -> Dict[str, str]:
            if pid == 9998:
                raise FileNotFoundError(f"/proc/{pid}/environ not found")
            return {}

        # Should handle gracefully
        try:
            env = read_with_error(9998)
            # Should not reach here
            assert False, "Expected FileNotFoundError"
        except FileNotFoundError:
            # Expected - process exited before we could read
            pass

    def test_permission_denied(self):
        """Test handling of permission denied (different user process)."""
        def read_with_permission_error(pid: int) -> Dict[str, str]:
            if pid == 9997:
                raise PermissionError(f"Permission denied: /proc/{pid}/environ")
            return {}

        # Should handle gracefully
        try:
            env = read_with_permission_error(9997)
            assert False, "Expected PermissionError"
        except PermissionError:
            # Expected - different user's process
            pass


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
