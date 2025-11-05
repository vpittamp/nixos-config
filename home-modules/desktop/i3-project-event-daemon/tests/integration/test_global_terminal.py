"""
Integration tests for global terminal behavior.

Tests the special "global" terminal that works without a project context.
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
def home_dir(tmp_path):
    """Create temporary home directory."""
    home = tmp_path / "home" / "user"
    home.mkdir(parents=True)
    return home


class TestGlobalTerminal:
    """Test global terminal (no project context)."""

    @pytest.mark.asyncio
    async def test_launch_global_terminal(
        self, scratchpad_manager, home_dir, mock_sway_connection
    ):
        """Test launching terminal with project_name='global'."""
        # Mock process creation and window appearance
        mock_proc = AsyncMock(pid=99999)
        mock_window = MagicMock(id=88888, pid=99999, app_id="Alacritty", marks=[])
        mock_tree = MagicMock()
        mock_tree.descendants = MagicMock(return_value=[mock_window])
        mock_sway_connection.get_tree.return_value = mock_tree

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            terminal = await scratchpad_manager.launch_terminal("global", home_dir)

        assert terminal.project_name == "global"
        assert terminal.pid == 99999
        assert terminal.window_id == 88888
        assert terminal.mark == "scratchpad:global"
        assert terminal.working_dir == home_dir

    @pytest.mark.asyncio
    async def test_global_terminal_independent_from_projects(
        self, scratchpad_manager, home_dir, tmp_path, mock_sway_connection
    ):
        """Test that global terminal is independent from project terminals."""
        # Create project directory
        project_dir = tmp_path / "my-project"
        project_dir.mkdir()

        # Launch global terminal
        mock_proc_global = AsyncMock(pid=99999)
        mock_window_global = MagicMock(id=88888, pid=99999, app_id="Alacritty", marks=[])
        mock_tree_global = MagicMock()
        mock_tree_global.descendants = MagicMock(return_value=[mock_window_global])
        mock_sway_connection.get_tree.return_value = mock_tree_global

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc_global):
            global_terminal = await scratchpad_manager.launch_terminal("global", home_dir)

        # Launch project terminal
        mock_proc_project = AsyncMock(pid=10001)
        mock_window_project = MagicMock(id=20001, pid=10001, app_id="Alacritty", marks=[])
        mock_tree_project = MagicMock()
        mock_tree_project.descendants = MagicMock(return_value=[mock_window_project])
        mock_sway_connection.get_tree.return_value = mock_tree_project

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc_project):
            project_terminal = await scratchpad_manager.launch_terminal("my-project", project_dir)

        # Verify both terminals exist independently
        assert len(scratchpad_manager.terminals) == 2
        assert "global" in scratchpad_manager.terminals
        assert "my-project" in scratchpad_manager.terminals

        # Verify different PIDs and working directories
        assert global_terminal.pid != project_terminal.pid
        assert global_terminal.working_dir != project_terminal.working_dir
        assert global_terminal.mark != project_terminal.mark

    @pytest.mark.asyncio
    async def test_global_terminal_toggle(
        self, scratchpad_manager, home_dir, mock_sway_connection
    ):
        """Test toggling global terminal."""
        # Create global terminal
        terminal = ScratchpadTerminal(
            project_name="global",
            pid=99999,
            window_id=88888,
            mark="scratchpad:global",
            working_dir=home_dir,
        )
        scratchpad_manager.terminals["global"] = terminal

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
            result = await scratchpad_manager.toggle_terminal("global")
            assert result == "hidden"

            # Mock window hidden
            mock_window.parent = MagicMock(name="__i3_scratch")
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            # Toggle to show
            result = await scratchpad_manager.toggle_terminal("global")
            assert result == "shown"

    @pytest.mark.asyncio
    async def test_global_terminal_uses_home_directory(
        self, scratchpad_manager, home_dir, mock_sway_connection
    ):
        """Test that global terminal typically uses home directory."""
        mock_proc = AsyncMock(pid=99999)
        mock_window = MagicMock(id=88888, pid=99999, app_id="Alacritty", marks=[])
        mock_tree = MagicMock()
        mock_tree.descendants = MagicMock(return_value=[mock_window])
        mock_sway_connection.get_tree.return_value = mock_tree

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            terminal = await scratchpad_manager.launch_terminal("global", home_dir)

        # Verify working directory is home
        assert terminal.working_dir == home_dir

    @pytest.mark.asyncio
    async def test_only_one_global_terminal_allowed(
        self, scratchpad_manager, home_dir, mock_sway_connection
    ):
        """Test that only one global terminal can exist."""
        # Launch first global terminal
        mock_proc = AsyncMock(pid=99999)
        mock_window = MagicMock(id=88888, pid=99999, app_id="Alacritty", marks=[])
        mock_tree = MagicMock()
        mock_tree.descendants = MagicMock(return_value=[mock_window])
        mock_sway_connection.get_tree.return_value = mock_tree

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            terminal1 = await scratchpad_manager.launch_terminal("global", home_dir)

        # Attempt to launch second global terminal
        with pytest.raises(ValueError, match="already exists"):
            await scratchpad_manager.launch_terminal("global", home_dir)

    @pytest.mark.asyncio
    async def test_global_terminal_in_status_output(self, scratchpad_manager, home_dir):
        """Test that global terminal appears in status queries."""
        # Add global terminal
        global_terminal = ScratchpadTerminal(
            project_name="global",
            pid=99999,
            window_id=88888,
            mark="scratchpad:global",
            working_dir=home_dir,
        )
        scratchpad_manager.terminals["global"] = global_terminal

        # Add project terminal
        project_terminal = ScratchpadTerminal(
            project_name="my-project",
            pid=10001,
            window_id=20001,
            mark="scratchpad:my-project",
            working_dir=Path("/tmp/my-project"),
        )
        scratchpad_manager.terminals["my-project"] = project_terminal

        # List all terminals
        all_terminals = await scratchpad_manager.list_terminals()

        assert len(all_terminals) == 2
        project_names = {t.project_name for t in all_terminals}
        assert "global" in project_names
        assert "my-project" in project_names

    @pytest.mark.asyncio
    async def test_global_terminal_cleanup(
        self, scratchpad_manager, home_dir, mock_sway_connection
    ):
        """Test that global terminal can be cleaned up if invalid."""
        # Add global terminal
        global_terminal = ScratchpadTerminal(
            project_name="global",
            pid=99999,
            window_id=88888,
            mark="scratchpad:global",
            working_dir=home_dir,
        )
        scratchpad_manager.terminals["global"] = global_terminal

        # Mock process dead
        with patch("psutil.pid_exists", return_value=False):
            cleaned = await scratchpad_manager.cleanup_invalid_terminals()

        # Verify global terminal was cleaned up
        assert cleaned == 1
        assert "global" not in scratchpad_manager.terminals
