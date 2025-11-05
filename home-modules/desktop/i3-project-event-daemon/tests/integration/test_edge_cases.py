"""
Integration tests for edge cases and error handling.

Tests terminal process death handling and cleanup operations.
"""

import pytest
import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

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
def project_dirs(tmp_path):
    """Create temporary project directories."""
    projects = {}
    for i in range(5):
        project_dir = tmp_path / f"project{i}"
        project_dir.mkdir()
        projects[f"project{i}"] = project_dir
    return projects


class TestProcessDeathHandling:
    """Test handling of terminal process death."""

    @pytest.mark.asyncio
    async def test_detect_dead_process(self, scratchpad_manager, project_dirs):
        """Test detection of dead terminal process."""
        project_name = "project0"
        project_dir = project_dirs[project_name]

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Initially running
        with patch("psutil.pid_exists", return_value=True):
            assert terminal.is_process_running()

        # Process dies
        with patch("psutil.pid_exists", return_value=False):
            assert not terminal.is_process_running()

    @pytest.mark.asyncio
    async def test_validation_removes_dead_terminal(
        self, scratchpad_manager, project_dirs
    ):
        """Test that validation removes terminal with dead process."""
        project_name = "project0"
        project_dir = project_dirs[project_name]

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Process dies
        with patch("psutil.pid_exists", return_value=False):
            is_valid = await scratchpad_manager.validate_terminal(project_name)

        # Verify terminal removed
        assert is_valid is False
        assert project_name not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_toggle_fails_with_dead_process(
        self, scratchpad_manager, project_dirs
    ):
        """Test that toggle operation fails if process is dead."""
        project_name = "project0"
        project_dir = project_dirs[project_name]

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Process dies
        with patch("psutil.pid_exists", return_value=False):
            # Attempt to toggle
            with pytest.raises(ValueError, match="invalid"):
                await scratchpad_manager.toggle_terminal(project_name)

    @pytest.mark.asyncio
    async def test_concurrent_process_deaths(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test handling multiple concurrent process deaths."""
        # Add multiple terminals
        for i in range(5):
            project_name = f"project{i}"
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dirs[project_name],
            )
            scratchpad_manager.terminals[project_name] = terminal

        # Mock: project0 and project2 die, others survive
        def mock_pid_exists(pid):
            return pid not in [10000, 10002]  # project0 and project2 dead

        with patch("psutil.pid_exists", side_effect=mock_pid_exists):
            # Run cleanup
            cleaned = await scratchpad_manager.cleanup_invalid_terminals()

        # Verify correct terminals removed
        assert cleaned == 2
        assert "project0" not in scratchpad_manager.terminals
        assert "project1" in scratchpad_manager.terminals
        assert "project2" not in scratchpad_manager.terminals
        assert "project3" in scratchpad_manager.terminals
        assert "project4" in scratchpad_manager.terminals


class TestWindowMissingHandling:
    """Test handling of missing Sway windows."""

    @pytest.mark.asyncio
    async def test_detect_missing_window(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test detection of missing Sway window."""
        project_name = "project0"
        project_dir = project_dirs[project_name]

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process running but window missing
        with patch("psutil.pid_exists", return_value=True):
            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=None)  # Window not found
            mock_sway_connection.get_tree.return_value = mock_tree

            is_valid = await scratchpad_manager.validate_terminal(project_name)

        # Verify terminal removed
        assert is_valid is False
        assert project_name not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_missing_mark_repair(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test automatic repair of missing window mark."""
        project_name = "project0"
        project_dir = project_dirs[project_name]

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process running, window exists but mark missing
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = terminal.window_id
            mock_window.marks = []  # Mark missing

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            is_valid = await scratchpad_manager.validate_terminal(project_name)

        # Verify terminal still valid and mark command issued
        assert is_valid is True
        assert project_name in scratchpad_manager.terminals
        mock_sway_connection.command.assert_called_once()
        assert "mark" in mock_sway_connection.command.call_args[0][0]


class TestCleanupOperations:
    """Test cleanup operations."""

    @pytest.mark.asyncio
    async def test_cleanup_empty_state(self, scratchpad_manager):
        """Test cleanup with no terminals."""
        cleaned = await scratchpad_manager.cleanup_invalid_terminals()
        assert cleaned == 0

    @pytest.mark.asyncio
    async def test_cleanup_all_valid(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test cleanup when all terminals are valid."""
        # Add terminals
        for i in range(3):
            project_name = f"project{i}"
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dirs[project_name],
            )
            scratchpad_manager.terminals[project_name] = terminal

        # Mock all valid
        with patch("psutil.pid_exists", return_value=True):
            def mock_find_by_id(window_id):
                mock_window = MagicMock()
                mock_window.id = window_id
                mock_window.marks = [f"scratchpad:project{window_id - 20000}"]
                return mock_window

            mock_tree = MagicMock()
            mock_tree.find_by_id = mock_find_by_id
            mock_sway_connection.get_tree.return_value = mock_tree

            cleaned = await scratchpad_manager.cleanup_invalid_terminals()

        # Verify nothing cleaned up
        assert cleaned == 0
        assert len(scratchpad_manager.terminals) == 3

    @pytest.mark.asyncio
    async def test_cleanup_all_invalid(
        self, scratchpad_manager, project_dirs
    ):
        """Test cleanup when all terminals are invalid."""
        # Add terminals
        for i in range(3):
            project_name = f"project{i}"
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dirs[project_name],
            )
            scratchpad_manager.terminals[project_name] = terminal

        # Mock all processes dead
        with patch("psutil.pid_exists", return_value=False):
            cleaned = await scratchpad_manager.cleanup_invalid_terminals()

        # Verify all cleaned up
        assert cleaned == 3
        assert len(scratchpad_manager.terminals) == 0

    @pytest.mark.asyncio
    async def test_cleanup_selective(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test selective cleanup (some valid, some invalid)."""
        # Add terminals
        for i in range(5):
            project_name = f"project{i}"
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dirs[project_name],
            )
            scratchpad_manager.terminals[project_name] = terminal

        # Mock: even PIDs valid, odd PIDs invalid
        def mock_pid_exists(pid):
            return (pid % 2) == 0

        with patch("psutil.pid_exists", side_effect=mock_pid_exists):
            # Mock windows for valid terminals
            def mock_find_by_id(window_id):
                # Even window IDs have windows
                if (window_id % 2) == 0:
                    mock_window = MagicMock()
                    mock_window.id = window_id
                    mock_window.marks = [f"scratchpad:project{window_id - 20000}"]
                    return mock_window
                return None

            mock_tree = MagicMock()
            mock_tree.find_by_id = mock_find_by_id
            mock_sway_connection.get_tree.return_value = mock_tree

            cleaned = await scratchpad_manager.cleanup_invalid_terminals()

        # Verify selective cleanup
        assert cleaned == 3  # project1, project2, project3
        assert len(scratchpad_manager.terminals) == 2  # project0, project4

    @pytest.mark.asyncio
    async def test_cleanup_idempotent(
        self, scratchpad_manager, project_dirs
    ):
        """Test that cleanup is idempotent (can be called multiple times)."""
        # Add terminals
        for i in range(3):
            project_name = f"project{i}"
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dirs[project_name],
            )
            scratchpad_manager.terminals[project_name] = terminal

        # Mock all processes dead
        with patch("psutil.pid_exists", return_value=False):
            # First cleanup
            cleaned1 = await scratchpad_manager.cleanup_invalid_terminals()
            # Second cleanup
            cleaned2 = await scratchpad_manager.cleanup_invalid_terminals()
            # Third cleanup
            cleaned3 = await scratchpad_manager.cleanup_invalid_terminals()

        # Verify results
        assert cleaned1 == 3  # Removed 3 terminals
        assert cleaned2 == 0  # Nothing to remove
        assert cleaned3 == 0  # Nothing to remove
        assert len(scratchpad_manager.terminals) == 0


class TestErrorConditions:
    """Test error handling and edge conditions."""

    @pytest.mark.asyncio
    async def test_launch_with_nonexistent_directory(
        self, scratchpad_manager
    ):
        """Test launching terminal with non-existent working directory."""
        nonexistent = Path("/nonexistent/path/to/project")

        with pytest.raises(ValueError, match="does not exist"):
            await scratchpad_manager.launch_terminal("test-project", nonexistent)

    @pytest.mark.asyncio
    async def test_toggle_nonexistent_terminal(self, scratchpad_manager):
        """Test toggling terminal that doesn't exist."""
        with pytest.raises(ValueError, match="No scratchpad terminal found"):
            await scratchpad_manager.toggle_terminal("nonexistent-project")

    @pytest.mark.asyncio
    async def test_get_state_nonexistent_terminal(self, scratchpad_manager):
        """Test getting state of non-existent terminal."""
        state = await scratchpad_manager.get_terminal_state("nonexistent-project")
        assert state is None

    @pytest.mark.asyncio
    async def test_get_terminal_nonexistent(self, scratchpad_manager):
        """Test retrieving non-existent terminal."""
        terminal = scratchpad_manager.get_terminal("nonexistent-project")
        assert terminal is None

    @pytest.mark.asyncio
    async def test_launch_directory_is_file(self, scratchpad_manager, tmp_path):
        """Test launching terminal with file path instead of directory."""
        file_path = tmp_path / "not_a_directory.txt"
        file_path.write_text("test")

        with pytest.raises(ValueError, match="does not exist"):
            await scratchpad_manager.launch_terminal("test-project", file_path)

    @pytest.mark.asyncio
    async def test_concurrent_cleanup_operations(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test concurrent cleanup operations don't cause issues."""
        # Add terminals
        for i in range(5):
            project_name = f"project{i}"
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dirs[project_name],
            )
            scratchpad_manager.terminals[project_name] = terminal

        # Mock some processes dead
        def mock_pid_exists(pid):
            return pid not in [10001, 10003]

        with patch("psutil.pid_exists", side_effect=mock_pid_exists):
            def mock_find_by_id(window_id):
                if window_id not in [20001, 20003]:
                    mock_window = MagicMock()
                    mock_window.id = window_id
                    mock_window.marks = [f"scratchpad:project{window_id - 20000}"]
                    return mock_window
                return None

            mock_tree = MagicMock()
            mock_tree.find_by_id = mock_find_by_id
            mock_sway_connection.get_tree.return_value = mock_tree

            # Run multiple concurrent cleanups
            results = await asyncio.gather(
                scratchpad_manager.cleanup_invalid_terminals(),
                scratchpad_manager.cleanup_invalid_terminals(),
                scratchpad_manager.cleanup_invalid_terminals(),
            )

        # Verify results (first cleanup removes terminals, others find nothing)
        assert sum(results) == 2  # Only first cleanup finds terminals
        assert len(scratchpad_manager.terminals) == 3
