"""
Unit tests for ScratchpadTerminal model and ScratchpadManager.

Tests validation, state management, and lifecycle operations WITHOUT Sway IPC.

Feature 062 - Project-Scoped Scratchpad Terminal
"""

import pytest
import time
from pathlib import Path
from pydantic import ValidationError
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from models.scratchpad import ScratchpadTerminal


class TestScratchpadTerminalModel:
    """Test ScratchpadTerminal Pydantic model validation and methods."""

    def test_valid_terminal_creation(self, mock_project_name, mock_working_dir):
        """Test creating valid scratchpad terminal instance."""
        terminal = ScratchpadTerminal(
            project_name=mock_project_name,
            pid=12345,
            window_id=94489280339584,
            mark=f"scratchpad:{mock_project_name}",
            working_dir=mock_working_dir,
        )

        assert terminal.project_name == mock_project_name
        assert terminal.pid == 12345
        assert terminal.window_id == 94489280339584
        assert terminal.mark == f"scratchpad:{mock_project_name}"
        assert terminal.working_dir == mock_working_dir
        assert terminal.created_at > 0
        assert terminal.last_shown_at is None

    def test_project_name_validation_alphanumeric(self):
        """Test project name must be alphanumeric with hyphens/underscores."""
        # Valid names
        valid_names = ["nixos", "test-project", "my_project", "Project123"]
        for name in valid_names:
            terminal = ScratchpadTerminal(
                project_name=name,
                pid=1,
                window_id=1,
                mark=f"scratchpad:{name}",
                working_dir=Path("/tmp"),
            )
            assert terminal.project_name == name

        # Invalid names
        invalid_names = ["project name", "test@project", "my/project", "test.project"]
        for name in invalid_names:
            with pytest.raises(ValidationError):
                ScratchpadTerminal(
                    project_name=name,
                    pid=1,
                    window_id=1,
                    mark=f"scratchpad:{name}",
                    working_dir=Path("/tmp"),
                )

    def test_working_dir_must_be_absolute(self):
        """Test working directory must be absolute path."""
        # Relative path should fail
        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="test",
                pid=1,
                window_id=1,
                mark="scratchpad:test",
                working_dir=Path("relative/path"),
            )

        # Absolute path should succeed
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=1,
            window_id=1,
            mark="scratchpad:test",
            working_dir=Path("/absolute/path"),
        )
        assert terminal.working_dir.is_absolute()

    def test_mark_format_validation(self):
        """Test mark must match pattern 'scratchpad:*'."""
        # Valid mark
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=1,
            window_id=1,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
        )
        assert terminal.mark == "scratchpad:test"

        # Invalid mark format
        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="test",
                pid=1,
                window_id=1,
                mark="invalid-mark",
                working_dir=Path("/tmp"),
            )

    def test_create_mark_class_method(self):
        """Test mark generation from project name."""
        assert ScratchpadTerminal.create_mark("nixos") == "scratchpad:nixos"
        assert ScratchpadTerminal.create_mark("dotfiles") == "scratchpad:dotfiles"
        assert ScratchpadTerminal.create_mark("global") == "scratchpad:global"

    def test_mark_shown_updates_timestamp(self, mock_working_dir):
        """Test mark_shown() updates last_shown_at timestamp."""
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=1,
            window_id=1,
            mark="scratchpad:test",
            working_dir=mock_working_dir,
        )

        assert terminal.last_shown_at is None

        time_before = time.time()
        terminal.mark_shown()
        time_after = time.time()

        assert terminal.last_shown_at is not None
        assert time_before <= terminal.last_shown_at <= time_after

    def test_to_dict_serialization(self, mock_working_dir):
        """Test conversion to dictionary for JSON serialization."""
        terminal = ScratchpadTerminal(
            project_name="nixos",
            pid=12345,
            window_id=94489280339584,
            mark="scratchpad:nixos",
            working_dir=mock_working_dir,
            created_at=1730815200.123,
            last_shown_at=1730815300.456,
        )

        result = terminal.to_dict()

        assert result["project_name"] == "nixos"
        assert result["pid"] == 12345
        assert result["window_id"] == 94489280339584
        assert result["mark"] == "scratchpad:nixos"
        assert result["working_dir"] == str(mock_working_dir)
        assert result["created_at"] == 1730815200.123
        assert result["last_shown_at"] == 1730815300.456


class TestScratchpadManager:
    """Test ScratchpadManager lifecycle and state management (mocked IPC)."""

    # Tests will be added in Phase 3 (User Story 1 implementation)
    pass
