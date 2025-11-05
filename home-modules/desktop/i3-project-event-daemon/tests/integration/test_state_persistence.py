"""
Integration tests for terminal state persistence.

Tests that scratchpad terminals preserve process state, command history,
and running processes across hide/show operations.
"""

import pytest
import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import time

from services.scratchpad_manager import ScratchpadManager
from models.scratchpad import ScratchpadTerminal


@pytest.fixture
async def mock_sway_connection():
    """Create mock Sway IPC connection."""
    mock_conn = AsyncMock()
    mock_conn.command = AsyncMock(return_value=None)
    mock_conn.get_tree = AsyncMock()
    return mock_conn


@pytest.fixture
async def scratchpad_manager(mock_sway_connection):
    """Create ScratchpadManager with mock connection."""
    manager = ScratchpadManager(mock_sway_connection)
    return manager


@pytest.fixture
def temp_project_dir(tmp_path):
    """Create temporary project directory."""
    project_dir = tmp_path / "test-project"
    project_dir.mkdir()
    return project_dir


class TestProcessPersistence:
    """Test that running processes persist across hide/show operations."""

    @pytest.mark.asyncio
    async def test_long_running_process_preserved(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that long-running processes remain alive when terminal is hidden."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process running and window visible
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = terminal.window_id
            mock_window.marks = [terminal.mark]
            mock_window.parent = MagicMock(name="workspace_1")

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            # Verify process is running (initial state)
            assert terminal.is_process_running()

            # Toggle to hide
            result = await scratchpad_manager.toggle_terminal(project_name)
            assert result == "hidden"

            # Simulate time passing (terminal remains in scratchpad)
            await asyncio.sleep(0.1)

            # Verify process is still running
            assert terminal.is_process_running()

            # Mock window now in scratchpad
            mock_window.parent = MagicMock(name="__i3_scratch")
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            # Toggle to show
            result = await scratchpad_manager.toggle_terminal(project_name)
            assert result == "shown"

            # Verify process is still running after show
            assert terminal.is_process_running()

    @pytest.mark.asyncio
    async def test_process_state_check_before_toggle(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that toggle validates process state before operating."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process NOT running (dead)
        with patch("psutil.pid_exists", return_value=False):
            # Attempt to toggle should fail validation
            with pytest.raises(ValueError, match="invalid"):
                await scratchpad_manager.toggle_terminal(project_name)

    @pytest.mark.asyncio
    async def test_process_validation_removes_dead_terminals(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that validation removes terminals with dead processes."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Verify terminal exists
        assert project_name in scratchpad_manager.terminals

        # Mock process died
        with patch("psutil.pid_exists", return_value=False):
            # Run validation
            is_valid = await scratchpad_manager.validate_terminal(project_name)

        # Verify terminal was removed
        assert is_valid is False
        assert project_name not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_multiple_hide_show_cycles(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test multiple hide/show cycles preserve process state."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process running
        with patch("psutil.pid_exists", return_value=True):
            # Perform multiple toggle cycles
            for cycle in range(5):
                # Mock visible window
                mock_window = MagicMock()
                mock_window.id = terminal.window_id
                mock_window.marks = [terminal.mark]
                mock_window.parent = MagicMock(
                    name="workspace_1" if cycle % 2 == 0 else "__i3_scratch"
                )

                mock_tree = MagicMock()
                mock_tree.find_by_id = MagicMock(return_value=mock_window)
                mock_sway_connection.get_tree.return_value = mock_tree

                # Toggle
                result = await scratchpad_manager.toggle_terminal(project_name)

                # Verify state
                expected = "hidden" if cycle % 2 == 0 else "shown"
                assert result == expected

                # Verify process still running
                assert terminal.is_process_running()

        # Verify terminal still tracked after all cycles
        assert project_name in scratchpad_manager.terminals


class TestCommandHistoryPersistence:
    """Test command history persistence (shell-level, not directly tested but verified via process)."""

    @pytest.mark.asyncio
    async def test_terminal_maintains_same_pid(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that terminal maintains same PID across hide/show (implies history persists)."""
        project_name = "test-project"
        original_pid = 10001

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=original_pid,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Store original PID
        assert terminal.pid == original_pid

        # Mock process running and perform toggle cycles
        with patch("psutil.pid_exists", return_value=True):
            for i in range(3):
                mock_window = MagicMock()
                mock_window.id = terminal.window_id
                mock_window.marks = [terminal.mark]
                mock_window.parent = MagicMock(
                    name="__i3_scratch" if i % 2 == 0 else "workspace_1"
                )

                mock_tree = MagicMock()
                mock_tree.find_by_id = MagicMock(return_value=mock_window)
                mock_sway_connection.get_tree.return_value = mock_tree

                await scratchpad_manager.toggle_terminal(project_name)

                # Verify PID hasn't changed (same process, same history)
                assert terminal.pid == original_pid

    @pytest.mark.asyncio
    async def test_working_directory_preserved(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that working directory remains consistent."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        original_working_dir = terminal.working_dir

        # Perform multiple operations
        with patch("psutil.pid_exists", return_value=True):
            # Validate multiple times
            for _ in range(3):
                mock_window = MagicMock()
                mock_window.id = terminal.window_id
                mock_window.marks = [terminal.mark]

                mock_tree = MagicMock()
                mock_tree.find_by_id = MagicMock(return_value=mock_window)
                mock_sway_connection.get_tree.return_value = mock_tree

                is_valid = await scratchpad_manager.validate_terminal(project_name)
                assert is_valid

                # Verify working_dir hasn't changed
                assert terminal.working_dir == original_working_dir


class TestTimestampTracking:
    """Test timestamp tracking for terminal lifecycle events."""

    @pytest.mark.asyncio
    async def test_created_at_timestamp(self, temp_project_dir):
        """Test that created_at timestamp is set on creation."""
        before_creation = time.time()

        terminal = ScratchpadTerminal(
            project_name="test-project",
            pid=10001,
            window_id=20001,
            mark="scratchpad:test-project",
            working_dir=temp_project_dir,
        )

        after_creation = time.time()

        assert terminal.created_at is not None
        assert before_creation <= terminal.created_at <= after_creation

    @pytest.mark.asyncio
    async def test_last_shown_at_initially_none(self, temp_project_dir):
        """Test that last_shown_at is initially None."""
        terminal = ScratchpadTerminal(
            project_name="test-project",
            pid=10001,
            window_id=20001,
            mark="scratchpad:test-project",
            working_dir=temp_project_dir,
        )

        assert terminal.last_shown_at is None

    @pytest.mark.asyncio
    async def test_last_shown_at_updated_on_toggle_show(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that last_shown_at is updated when terminal is shown."""
        project_name = "test-project"

        # Create terminal (never shown)
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        assert terminal.last_shown_at is None

        # Mock process running, window hidden
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = terminal.window_id
            mock_window.marks = [terminal.mark]
            mock_window.parent = MagicMock(name="__i3_scratch")

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            # Toggle to show
            before_show = time.time()
            result = await scratchpad_manager.toggle_terminal(project_name)
            after_show = time.time()

            assert result == "shown"

        # Verify last_shown_at was updated
        assert terminal.last_shown_at is not None
        assert before_show <= terminal.last_shown_at <= after_show

    @pytest.mark.asyncio
    async def test_last_shown_at_not_updated_on_hide(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that last_shown_at is NOT updated when hiding terminal."""
        project_name = "test-project"

        # Create terminal and mark as shown
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        terminal.mark_shown()  # Set initial timestamp
        initial_timestamp = terminal.last_shown_at
        scratchpad_manager.terminals[project_name] = terminal

        # Wait a bit to ensure timestamp would be different if updated
        await asyncio.sleep(0.01)

        # Mock process running, window visible
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = terminal.window_id
            mock_window.marks = [terminal.mark]
            mock_window.parent = MagicMock(name="workspace_1")

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            # Toggle to hide
            result = await scratchpad_manager.toggle_terminal(project_name)
            assert result == "hidden"

        # Verify last_shown_at unchanged
        assert terminal.last_shown_at == initial_timestamp

    @pytest.mark.asyncio
    async def test_last_shown_at_tracks_most_recent_show(
        self, scratchpad_manager, temp_project_dir, mock_sway_connection
    ):
        """Test that last_shown_at tracks the most recent show operation."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        timestamps = []

        # Mock process running
        with patch("psutil.pid_exists", return_value=True):
            # Perform multiple show operations
            for i in range(3):
                # Mock hidden window
                mock_window = MagicMock()
                mock_window.id = terminal.window_id
                mock_window.marks = [terminal.mark]
                mock_window.parent = MagicMock(name="__i3_scratch")

                mock_tree = MagicMock()
                mock_tree.find_by_id = MagicMock(return_value=mock_window)
                mock_sway_connection.get_tree.return_value = mock_tree

                # Show terminal
                await scratchpad_manager.toggle_terminal(project_name)
                timestamps.append(terminal.last_shown_at)

                # Wait to ensure different timestamp
                await asyncio.sleep(0.01)

                # Mock visible window for next iteration
                mock_window.parent = MagicMock(name="workspace_1")
                mock_tree.find_by_id = MagicMock(return_value=mock_window)
                mock_sway_connection.get_tree.return_value = mock_tree

                # Hide terminal
                await scratchpad_manager.toggle_terminal(project_name)

        # Verify timestamps are increasing (each show updates to later time)
        assert timestamps[0] < timestamps[1] < timestamps[2]

    @pytest.mark.asyncio
    async def test_timestamp_serialization(self, temp_project_dir):
        """Test that timestamps are included in to_dict() serialization."""
        terminal = ScratchpadTerminal(
            project_name="test-project",
            pid=10001,
            window_id=20001,
            mark="scratchpad:test-project",
            working_dir=temp_project_dir,
        )
        terminal.mark_shown()

        result = terminal.to_dict()

        assert "created_at" in result
        assert "last_shown_at" in result
        assert isinstance(result["created_at"], float)
        assert isinstance(result["last_shown_at"], float)
        assert result["created_at"] <= result["last_shown_at"]
