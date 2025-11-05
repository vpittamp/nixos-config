"""
Unit tests for ScratchpadTerminal model.

Tests cover model validation, mark generation, and state management.
"""

import pytest
from pathlib import Path
from pydantic import ValidationError
import time

from models.scratchpad import ScratchpadTerminal


class TestScratchpadTerminalValidation:
    """Test ScratchpadTerminal model validation."""

    def test_valid_terminal_creation(self):
        """Test creating a valid scratchpad terminal."""
        terminal = ScratchpadTerminal(
            project_name="my-project",
            pid=12345,
            window_id=67890,
            mark="scratchpad:my-project",
            working_dir=Path("/home/user/projects/my-project"),
        )

        assert terminal.project_name == "my-project"
        assert terminal.pid == 12345
        assert terminal.window_id == 67890
        assert terminal.mark == "scratchpad:my-project"
        assert terminal.working_dir == Path("/home/user/projects/my-project")
        assert terminal.last_shown_at is None
        assert isinstance(terminal.created_at, float)
        assert terminal.created_at <= time.time()

    def test_project_name_validation_alphanumeric(self):
        """Test project name must be alphanumeric with optional hyphens/underscores."""
        # Valid names
        valid_names = ["project", "my-project", "my_project", "project123", "test-env_2"]
        for name in valid_names:
            terminal = ScratchpadTerminal(
                project_name=name,
                pid=12345,
                window_id=67890,
                mark=f"scratchpad:{name}",
                working_dir=Path("/tmp"),
            )
            assert terminal.project_name == name

        # Invalid names
        invalid_names = ["my project", "project!", "test@env", "test/path", ""]
        for name in invalid_names:
            with pytest.raises(ValidationError):
                ScratchpadTerminal(
                    project_name=name,
                    pid=12345,
                    window_id=67890,
                    mark=f"scratchpad:{name}",
                    working_dir=Path("/tmp"),
                )

    def test_project_name_length_validation(self):
        """Test project name length constraints."""
        # Too short (empty after validation)
        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="",
                pid=12345,
                window_id=67890,
                mark="scratchpad:",
                working_dir=Path("/tmp"),
            )

        # Too long (>100 chars)
        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="a" * 101,
                pid=12345,
                window_id=67890,
                mark="scratchpad:" + "a" * 101,
                working_dir=Path("/tmp"),
            )

        # Max length (100 chars)
        terminal = ScratchpadTerminal(
            project_name="a" * 100,
            pid=12345,
            window_id=67890,
            mark="scratchpad:" + "a" * 100,
            working_dir=Path("/tmp"),
        )
        assert len(terminal.project_name) == 100

    def test_pid_validation(self):
        """Test PID must be positive integer."""
        # Valid PIDs
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=1,
            window_id=67890,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
        )
        assert terminal.pid == 1

        # Invalid PIDs
        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="test",
                pid=0,
                window_id=67890,
                mark="scratchpad:test",
                working_dir=Path("/tmp"),
            )

        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="test",
                pid=-1,
                window_id=67890,
                mark="scratchpad:test",
                working_dir=Path("/tmp"),
            )

    def test_window_id_validation(self):
        """Test window ID must be positive integer."""
        # Valid window IDs
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=1,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
        )
        assert terminal.window_id == 1

        # Invalid window IDs
        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="test",
                pid=12345,
                window_id=0,
                mark="scratchpad:test",
                working_dir=Path("/tmp"),
            )

        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="test",
                pid=12345,
                window_id=-1,
                mark="scratchpad:test",
                working_dir=Path("/tmp"),
            )

    def test_mark_pattern_validation(self):
        """Test mark must follow 'scratchpad:*' pattern."""
        # Valid marks
        valid_marks = ["scratchpad:test", "scratchpad:my-project", "scratchpad:global"]
        for mark in valid_marks:
            terminal = ScratchpadTerminal(
                project_name="test",
                pid=12345,
                window_id=67890,
                mark=mark,
                working_dir=Path("/tmp"),
            )
            assert terminal.mark == mark

        # Invalid marks
        invalid_marks = ["test", "scratchpad:", "scratch:test", "scratchpad"]
        for mark in invalid_marks:
            with pytest.raises(ValidationError):
                ScratchpadTerminal(
                    project_name="test",
                    pid=12345,
                    window_id=67890,
                    mark=mark,
                    working_dir=Path("/tmp"),
                )

    def test_working_dir_validation(self):
        """Test working directory must be absolute path."""
        # Valid absolute paths
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test",
            working_dir=Path("/home/user/project"),
        )
        assert terminal.working_dir == Path("/home/user/project")

        # Invalid relative paths
        with pytest.raises(ValidationError):
            ScratchpadTerminal(
                project_name="test",
                pid=12345,
                window_id=67890,
                mark="scratchpad:test",
                working_dir=Path("relative/path"),
            )


class TestMarkGeneration:
    """Test mark generation and validation."""

    def test_create_mark_basic(self):
        """Test basic mark generation."""
        mark = ScratchpadTerminal.create_mark("my-project")
        assert mark == "scratchpad:my-project"

    def test_create_mark_global(self):
        """Test mark generation for global terminal."""
        mark = ScratchpadTerminal.create_mark("global")
        assert mark == "scratchpad:global"

    def test_create_mark_with_hyphens_underscores(self):
        """Test mark generation with hyphens and underscores."""
        mark = ScratchpadTerminal.create_mark("test-env_2")
        assert mark == "scratchpad:test-env_2"

    def test_create_mark_consistency(self):
        """Test mark generation is consistent."""
        project_name = "my-project"
        mark1 = ScratchpadTerminal.create_mark(project_name)
        mark2 = ScratchpadTerminal.create_mark(project_name)
        assert mark1 == mark2


class TestTerminalState:
    """Test terminal state management methods."""

    def test_mark_shown_updates_timestamp(self):
        """Test mark_shown() updates last_shown_at."""
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
        )

        assert terminal.last_shown_at is None

        before_mark = time.time()
        terminal.mark_shown()
        after_mark = time.time()

        assert terminal.last_shown_at is not None
        assert before_mark <= terminal.last_shown_at <= after_mark

    def test_mark_shown_multiple_times(self):
        """Test mark_shown() can be called multiple times."""
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
        )

        terminal.mark_shown()
        first_shown = terminal.last_shown_at

        time.sleep(0.01)  # Small delay to ensure different timestamp

        terminal.mark_shown()
        second_shown = terminal.last_shown_at

        assert second_shown > first_shown

    def test_to_dict_serialization(self):
        """Test to_dict() produces correct dictionary."""
        terminal = ScratchpadTerminal(
            project_name="test-project",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test-project",
            working_dir=Path("/home/user/test-project"),
        )
        terminal.mark_shown()

        result = terminal.to_dict()

        assert result["project_name"] == "test-project"
        assert result["pid"] == 12345
        assert result["window_id"] == 67890
        assert result["mark"] == "scratchpad:test-project"
        assert result["working_dir"] == "/home/user/test-project"
        assert isinstance(result["created_at"], float)
        assert isinstance(result["last_shown_at"], float)

    def test_to_dict_with_null_last_shown(self):
        """Test to_dict() handles None last_shown_at."""
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
        )

        result = terminal.to_dict()
        assert result["last_shown_at"] is None

    def test_is_process_running_mock(self, monkeypatch):
        """Test is_process_running() method."""
        terminal = ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
        )

        # Mock psutil.pid_exists to return True
        import psutil
        monkeypatch.setattr(psutil, "pid_exists", lambda pid: pid == 12345)

        assert terminal.is_process_running() is True

        # Mock to return False
        monkeypatch.setattr(psutil, "pid_exists", lambda pid: False)
        assert terminal.is_process_running() is False
