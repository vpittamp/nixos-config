"""
Tests for worktree environment variable injection.
Feature 079: Preview Pane User Experience - US8 (T056-T057)
"""

import pytest
import sys
from pathlib import Path

# Add daemon directory to path for imports
daemon_dir = Path(__file__).parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"
sys.path.insert(0, str(daemon_dir))

from models.worktree_environment import WorktreeEnvironment


class TestWorktreeEnvironmentToEnvDict:
    """T056: Unit test for WorktreeEnvironment.to_env_dict()"""

    def test_worktree_environment_includes_all_fields(self):
        """Verify all worktree fields are included in environment dict."""
        env = WorktreeEnvironment(
            is_worktree=True,
            parent_project="nixos",
            branch_type="feature",
            branch_number="079",
            full_branch_name="079-preview-pane-user-experience",
        )

        env_dict = env.to_env_dict()

        assert "I3PM_IS_WORKTREE" in env_dict
        assert "I3PM_PARENT_PROJECT" in env_dict
        assert "I3PM_BRANCH_TYPE" in env_dict
        assert "I3PM_BRANCH_NUMBER" in env_dict
        assert "I3PM_FULL_BRANCH_NAME" in env_dict

    def test_non_worktree_environment(self):
        """Verify non-worktree projects have is_worktree=false."""
        env = WorktreeEnvironment(
            is_worktree=False,
            parent_project=None,
            branch_type=None,
            branch_number=None,
            full_branch_name=None,
        )

        env_dict = env.to_env_dict()

        assert env_dict["I3PM_IS_WORKTREE"] == "false"
        # Optional fields should not be present when None
        assert "I3PM_PARENT_PROJECT" not in env_dict
        assert "I3PM_BRANCH_TYPE" not in env_dict

    def test_worktree_with_partial_metadata(self):
        """Verify worktree with missing optional fields."""
        env = WorktreeEnvironment(
            is_worktree=True,
            parent_project="dotfiles",
            branch_type=None,  # No branch type determined
            branch_number=None,  # Non-numbered branch
            full_branch_name="experimental-feature",
        )

        env_dict = env.to_env_dict()

        assert env_dict["I3PM_IS_WORKTREE"] == "true"
        assert env_dict["I3PM_PARENT_PROJECT"] == "dotfiles"
        assert env_dict["I3PM_FULL_BRANCH_NAME"] == "experimental-feature"
        assert "I3PM_BRANCH_TYPE" not in env_dict
        assert "I3PM_BRANCH_NUMBER" not in env_dict


class TestBooleanConversion:
    """T057: Unit test for boolean to string conversion ("true"/"false")"""

    def test_true_converts_to_string_true(self):
        """Boolean True should convert to string 'true'."""
        env = WorktreeEnvironment(
            is_worktree=True,
            parent_project="nixos",
            branch_type="feature",
            branch_number="079",
            full_branch_name="079-preview-pane-user-experience",
        )

        env_dict = env.to_env_dict()

        assert env_dict["I3PM_IS_WORKTREE"] == "true"
        assert isinstance(env_dict["I3PM_IS_WORKTREE"], str)

    def test_false_converts_to_string_false(self):
        """Boolean False should convert to string 'false'."""
        env = WorktreeEnvironment(
            is_worktree=False,
            parent_project=None,
            branch_type=None,
            branch_number=None,
            full_branch_name=None,
        )

        env_dict = env.to_env_dict()

        assert env_dict["I3PM_IS_WORKTREE"] == "false"
        assert isinstance(env_dict["I3PM_IS_WORKTREE"], str)

    def test_env_vars_are_all_strings(self):
        """All environment variable values must be strings."""
        env = WorktreeEnvironment(
            is_worktree=True,
            parent_project="nixos",
            branch_type="feature",
            branch_number="079",
            full_branch_name="079-preview-pane-user-experience",
        )

        env_dict = env.to_env_dict()

        for key, value in env_dict.items():
            assert isinstance(value, str), f"{key} value is not a string: {type(value)}"
