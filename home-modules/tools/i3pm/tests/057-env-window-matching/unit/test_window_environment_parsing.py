"""
Unit tests for WindowEnvironment parsing from environment dictionaries.

Tests the WindowEnvironment.from_env_dict() classmethod's ability to:
- Parse I3PM_* environment variables correctly
- Validate required fields
- Apply defaults for optional fields
- Raise ValueError on invalid scope
- Raise ValueError on invalid workspace range
"""

import pytest
from home_modules.tools.i3pm.daemon.models import WindowEnvironment


class TestWindowEnvironmentParsing:
    """Test suite for WindowEnvironment.from_env_dict() parsing."""

    def test_parse_required_fields_only(self):
        """Test parsing with only required fields."""
        env = {
            "I3PM_APP_ID": "test-app-id-123",
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "global"
        }

        window_env = WindowEnvironment.from_env_dict(env)

        assert window_env is not None
        assert window_env.app_id == "test-app-id-123"
        assert window_env.app_name == "test-app"
        assert window_env.scope == "global"

        # Optional fields should have defaults
        assert window_env.project_name == ""
        assert window_env.project_dir == ""
        assert window_env.active is True
        assert window_env.target_workspace is None

    def test_parse_all_fields(self):
        """Test parsing with all fields present."""
        env = {
            "I3PM_APP_ID": "vscode-nixos-12345-1234567890",
            "I3PM_APP_NAME": "vscode",
            "I3PM_SCOPE": "scoped",
            "I3PM_PROJECT_NAME": "nixos",
            "I3PM_PROJECT_DIR": "/etc/nixos",
            "I3PM_PROJECT_DISPLAY_NAME": "NixOS",
            "I3PM_PROJECT_ICON": "❄️",
            "I3PM_ACTIVE": "true",
            "I3PM_TARGET_WORKSPACE": "52",
            "I3PM_EXPECTED_CLASS": "Code",
            "I3PM_LAUNCHER_PID": "12345",
            "I3PM_LAUNCH_TIME": "1234567890",
            "I3SOCK": "/run/user/1000/sway-ipc.sock"
        }

        window_env = WindowEnvironment.from_env_dict(env)

        assert window_env is not None
        assert window_env.app_id == "vscode-nixos-12345-1234567890"
        assert window_env.app_name == "vscode"
        assert window_env.scope == "scoped"
        assert window_env.project_name == "nixos"
        assert window_env.project_dir == "/etc/nixos"
        assert window_env.project_display_name == "NixOS"
        assert window_env.project_icon == "❄️"
        assert window_env.active is True
        assert window_env.target_workspace == 52
        assert window_env.expected_class == "Code"
        assert window_env.launcher_pid == 12345
        assert window_env.launch_time == 1234567890
        assert window_env.i3_socket == "/run/user/1000/sway-ipc.sock"

    def test_missing_required_app_id(self):
        """Test that missing I3PM_APP_ID returns None."""
        env = {
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "global"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        assert window_env is None

    def test_missing_required_app_name(self):
        """Test that missing I3PM_APP_NAME returns None."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_SCOPE": "global"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        assert window_env is None

    def test_missing_required_scope(self):
        """Test that missing I3PM_SCOPE returns None."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "test-app"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        assert window_env is None

    def test_invalid_scope_value(self):
        """Test that invalid scope value returns None (fails validation)."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "invalid-scope"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        # Should return None because validation fails
        assert window_env is None

    def test_scope_global(self):
        """Test parsing with global scope."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "firefox",
            "I3PM_SCOPE": "global"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        assert window_env is not None
        assert window_env.scope == "global"
        assert window_env.is_global is True
        assert window_env.is_scoped is False

    def test_scope_scoped(self):
        """Test parsing with scoped scope."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "terminal",
            "I3PM_SCOPE": "scoped"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        assert window_env is not None
        assert window_env.scope == "scoped"
        assert window_env.is_global is False
        assert window_env.is_scoped is True

    def test_target_workspace_valid_range(self):
        """Test valid target workspace values (1-70)."""
        for workspace in [1, 35, 70]:
            env = {
                "I3PM_APP_ID": "test-id",
                "I3PM_APP_NAME": "test-app",
                "I3PM_SCOPE": "global",
                "I3PM_TARGET_WORKSPACE": str(workspace)
            }

            window_env = WindowEnvironment.from_env_dict(env)
            assert window_env is not None
            assert window_env.target_workspace == workspace

    def test_target_workspace_invalid_below_range(self):
        """Test invalid target workspace below range (< 1)."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "global",
            "I3PM_TARGET_WORKSPACE": "0"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        # Should return None because validation fails
        assert window_env is None

    def test_target_workspace_invalid_above_range(self):
        """Test invalid target workspace above range (> 70)."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "global",
            "I3PM_TARGET_WORKSPACE": "71"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        # Should return None because validation fails
        assert window_env is None

    def test_target_workspace_non_numeric(self):
        """Test non-numeric target workspace value."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "global",
            "I3PM_TARGET_WORKSPACE": "not-a-number"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        # Should still succeed, but target_workspace should be None
        assert window_env is not None
        assert window_env.target_workspace is None

    def test_active_boolean_parsing_true(self):
        """Test parsing I3PM_ACTIVE as boolean - true values."""
        for true_value in ["true", "True", "TRUE", "1", "yes", "Yes", "YES"]:
            env = {
                "I3PM_APP_ID": "test-id",
                "I3PM_APP_NAME": "test-app",
                "I3PM_SCOPE": "global",
                "I3PM_ACTIVE": true_value
            }

            window_env = WindowEnvironment.from_env_dict(env)
            assert window_env is not None
            assert window_env.active is True, f"Failed for value: {true_value}"

    def test_active_boolean_parsing_false(self):
        """Test parsing I3PM_ACTIVE as boolean - false values."""
        for false_value in ["false", "False", "FALSE", "0", "no", "No", "NO"]:
            env = {
                "I3PM_APP_ID": "test-id",
                "I3PM_APP_NAME": "test-app",
                "I3PM_SCOPE": "global",
                "I3PM_ACTIVE": false_value
            }

            window_env = WindowEnvironment.from_env_dict(env)
            assert window_env is not None
            assert window_env.active is False, f"Failed for value: {false_value}"

    def test_active_default_value(self):
        """Test that I3PM_ACTIVE defaults to True when not present."""
        env = {
            "I3PM_APP_ID": "test-id",
            "I3PM_APP_NAME": "test-app",
            "I3PM_SCOPE": "global"
        }

        window_env = WindowEnvironment.from_env_dict(env)
        assert window_env is not None
        assert window_env.active is True


class TestWindowEnvironmentHelperMethods:
    """Test suite for WindowEnvironment helper methods."""

    def test_has_project_with_project(self):
        """Test has_project() when project is set."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="test-app",
            scope="scoped",
            project_name="nixos"
        )

        assert window_env.has_project is True

    def test_has_project_without_project(self):
        """Test has_project() when project is empty."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="test-app",
            scope="global",
            project_name=""
        )

        assert window_env.has_project is False

    def test_matches_project_true(self):
        """Test matches_project() with matching project."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="test-app",
            scope="scoped",
            project_name="nixos"
        )

        assert window_env.matches_project("nixos") is True

    def test_matches_project_false(self):
        """Test matches_project() with non-matching project."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="test-app",
            scope="scoped",
            project_name="nixos"
        )

        assert window_env.matches_project("stacks") is False

    def test_should_be_visible_global_always_visible(self):
        """Test should_be_visible() for global scope (always visible)."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="firefox",
            scope="global"
        )

        # Global windows visible in any project
        assert window_env.should_be_visible("nixos") is True
        assert window_env.should_be_visible("stacks") is True
        assert window_env.should_be_visible(None) is True

    def test_should_be_visible_scoped_matching_project(self):
        """Test should_be_visible() for scoped window in matching project."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="terminal",
            scope="scoped",
            project_name="nixos"
        )

        # Visible when active project matches
        assert window_env.should_be_visible("nixos") is True

    def test_should_be_visible_scoped_non_matching_project(self):
        """Test should_be_visible() for scoped window in non-matching project."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="terminal",
            scope="scoped",
            project_name="nixos"
        )

        # Hidden when active project doesn't match
        assert window_env.should_be_visible("stacks") is False

    def test_should_be_visible_scoped_no_active_project(self):
        """Test should_be_visible() for scoped window with no active project."""
        window_env = WindowEnvironment(
            app_id="test-id",
            app_name="terminal",
            scope="scoped",
            project_name="nixos"
        )

        # Hidden when no project is active
        assert window_env.should_be_visible(None) is False
