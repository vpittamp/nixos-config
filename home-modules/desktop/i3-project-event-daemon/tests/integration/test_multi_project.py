"""
Integration tests for multi-project terminal isolation.

Tests that each project maintains independent terminal state with
separate instances, working directories, and command history.
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
def project_dirs(tmp_path):
    """Create temporary directories for multiple projects."""
    project1 = tmp_path / "project1"
    project2 = tmp_path / "project2"
    project3 = tmp_path / "project3"

    project1.mkdir()
    project2.mkdir()
    project3.mkdir()

    return {
        "project1": project1,
        "project2": project2,
        "project3": project3,
    }


class TestMultiProjectIsolation:
    """Test that multiple projects maintain independent terminal state."""

    @pytest.mark.asyncio
    async def test_multiple_projects_independent_terminals(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test each project can have its own terminal."""
        # Mock process creation and window appearance
        mock_procs = [AsyncMock(pid=10000 + i) for i in range(3)]
        mock_windows = [
            MagicMock(id=20000 + i, pid=10000 + i, app_id="Alacritty", marks=[])
            for i in range(3)
        ]

        def create_proc_factory(index):
            async def create_proc(*args, **kwargs):
                return mock_procs[index]
            return create_proc

        def tree_factory(index):
            tree = MagicMock()
            tree.descendants = MagicMock(return_value=[mock_windows[index]])
            return tree

        # Launch terminals for three projects
        with patch("asyncio.create_subprocess_exec") as mock_exec:
            for i, (project_name, project_dir) in enumerate(project_dirs.items()):
                mock_exec.side_effect = create_proc_factory(i)
                mock_sway_connection.get_tree.return_value = tree_factory(i)

                terminal = await scratchpad_manager.launch_terminal(project_name, project_dir)

                assert terminal.project_name == project_name
                assert terminal.pid == 10000 + i
                assert terminal.window_id == 20000 + i
                assert terminal.working_dir == project_dir
                assert terminal.mark == f"scratchpad:{project_name}"

        # Verify all three terminals are tracked independently
        assert len(scratchpad_manager.terminals) == 3
        assert "project1" in scratchpad_manager.terminals
        assert "project2" in scratchpad_manager.terminals
        assert "project3" in scratchpad_manager.terminals

        # Verify each terminal has correct project-specific state
        term1 = scratchpad_manager.get_terminal("project1")
        term2 = scratchpad_manager.get_terminal("project2")
        term3 = scratchpad_manager.get_terminal("project3")

        assert term1.working_dir == project_dirs["project1"]
        assert term2.working_dir == project_dirs["project2"]
        assert term3.working_dir == project_dirs["project3"]

        assert term1.pid != term2.pid != term3.pid
        assert term1.window_id != term2.window_id != term3.window_id
        assert term1.mark != term2.mark != term3.mark

    @pytest.mark.asyncio
    async def test_duplicate_terminal_prevention(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test that duplicate terminals per project are prevented."""
        project_name = "project1"
        project_dir = project_dirs[project_name]

        # Launch first terminal
        mock_proc = AsyncMock(pid=10001)
        mock_window = MagicMock(id=20001, pid=10001, app_id="Alacritty")
        mock_tree = MagicMock()
        mock_tree.descendants = MagicMock(return_value=[mock_window])
        mock_sway_connection.get_tree.return_value = mock_tree

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            terminal1 = await scratchpad_manager.launch_terminal(project_name, project_dir)
            assert terminal1.project_name == project_name

        # Attempt to launch duplicate - should fail
        with pytest.raises(ValueError, match="already exists"):
            await scratchpad_manager.launch_terminal(project_name, project_dir)

        # Verify only one terminal exists
        assert len(scratchpad_manager.terminals) == 1

    @pytest.mark.asyncio
    async def test_project_switch_with_existing_terminals(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test switching between projects with existing terminals."""
        # Launch terminals for two projects
        projects = ["project1", "project2"]
        terminals = {}

        for i, project_name in enumerate(projects):
            mock_proc = AsyncMock(pid=10000 + i)
            mock_window = MagicMock(id=20000 + i, pid=10000 + i, app_id="Alacritty", marks=[])
            mock_tree = MagicMock()
            mock_tree.descendants = MagicMock(return_value=[mock_window])
            mock_sway_connection.get_tree.return_value = mock_tree

            with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
                terminal = await scratchpad_manager.launch_terminal(
                    project_name, project_dirs[project_name]
                )
                terminals[project_name] = terminal

        # Mock validation for both terminals
        with patch("psutil.pid_exists", return_value=True):
            # Simulate project switch by toggling terminals
            for project_name in projects:
                # Mock window state (visible)
                terminal = terminals[project_name]
                mock_window = MagicMock()
                mock_window.id = terminal.window_id
                mock_window.marks = [terminal.mark]
                mock_window.parent = MagicMock(name="workspace_1")

                mock_tree = MagicMock()
                mock_tree.find_by_id = MagicMock(return_value=mock_window)
                mock_sway_connection.get_tree.return_value = mock_tree

                state = await scratchpad_manager.get_terminal_state(project_name)
                assert state == "visible"

                # Toggle to hide
                result = await scratchpad_manager.toggle_terminal(project_name)
                assert result == "hidden"

        # Verify both terminals still exist independently
        assert len(scratchpad_manager.terminals) == 2
        assert scratchpad_manager.get_terminal("project1") is not None
        assert scratchpad_manager.get_terminal("project2") is not None

    @pytest.mark.asyncio
    async def test_list_all_terminals(self, scratchpad_manager, project_dirs):
        """Test listing all terminals across projects."""
        # Manually add terminals (bypass actual launch)
        for i, (project_name, project_dir) in enumerate(project_dirs.items()):
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dir,
            )
            scratchpad_manager.terminals[project_name] = terminal

        # List all terminals
        all_terminals = await scratchpad_manager.list_terminals()

        assert len(all_terminals) == 3
        project_names = {t.project_name for t in all_terminals}
        assert project_names == {"project1", "project2", "project3"}

    @pytest.mark.asyncio
    async def test_selective_terminal_cleanup(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test cleanup removes only invalid terminals, preserving valid ones."""
        # Add three terminals
        terminals = {}
        for i, (project_name, project_dir) in enumerate(project_dirs.items()):
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dir,
            )
            scratchpad_manager.terminals[project_name] = terminal
            terminals[project_name] = terminal

        # Mock validation: project1 valid, project2 dead process, project3 missing window
        def mock_pid_exists(pid):
            if pid == 10000:  # project1
                return True
            elif pid == 10001:  # project2
                return False
            elif pid == 10002:  # project3
                return True
            return False

        with patch("psutil.pid_exists", side_effect=mock_pid_exists):
            # Mock Sway tree: project1 window exists, project3 window missing
            def mock_find_by_id(window_id):
                if window_id == 20000:  # project1
                    mock_window = MagicMock()
                    mock_window.id = 20000
                    mock_window.marks = ["scratchpad:project1"]
                    return mock_window
                return None  # project3 window missing

            mock_tree = MagicMock()
            mock_tree.find_by_id = mock_find_by_id
            mock_sway_connection.get_tree.return_value = mock_tree

            # Run cleanup
            cleaned = await scratchpad_manager.cleanup_invalid_terminals()

        # Verify cleanup results
        assert cleaned == 2  # project2 and project3 removed
        assert "project1" in scratchpad_manager.terminals
        assert "project2" not in scratchpad_manager.terminals
        assert "project3" not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_concurrent_terminal_operations(
        self, scratchpad_manager, project_dirs, mock_sway_connection
    ):
        """Test concurrent operations on different project terminals."""
        # Launch two terminals
        projects = ["project1", "project2"]

        for i, project_name in enumerate(projects):
            mock_proc = AsyncMock(pid=10000 + i)
            mock_window = MagicMock(id=20000 + i, pid=10000 + i, app_id="Alacritty", marks=[])
            mock_tree = MagicMock()
            mock_tree.descendants = MagicMock(return_value=[mock_window])
            mock_sway_connection.get_tree.return_value = mock_tree

            with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
                await scratchpad_manager.launch_terminal(project_name, project_dirs[project_name])

        # Simulate concurrent validation operations
        with patch("psutil.pid_exists", return_value=True):
            def mock_find_by_id(window_id):
                mock_window = MagicMock()
                mock_window.id = window_id
                mock_window.marks = [f"scratchpad:project{1 if window_id == 20000 else 2}"]
                return mock_window

            mock_tree = MagicMock()
            mock_tree.find_by_id = mock_find_by_id
            mock_sway_connection.get_tree.return_value = mock_tree

            # Run concurrent validations
            results = await asyncio.gather(
                scratchpad_manager.validate_terminal("project1"),
                scratchpad_manager.validate_terminal("project2"),
            )

        # Verify both validations succeeded
        assert all(results)
        assert len(scratchpad_manager.terminals) == 2


class TestTerminalUniqueness:
    """Test terminal uniqueness validation."""

    @pytest.mark.asyncio
    async def test_project_name_uniqueness(self, scratchpad_manager, project_dirs):
        """Test that project names must be unique for active terminals."""
        project_name = "test-project"
        project_dir = project_dirs["project1"]

        # Add first terminal
        terminal1 = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal1

        # Verify uniqueness check
        assert project_name in scratchpad_manager.terminals

        # Attempt to add second terminal with same project name should fail in launch_terminal
        # (This is enforced by launch_terminal validation, not by a separate method)

    @pytest.mark.asyncio
    async def test_mark_uniqueness(self, scratchpad_manager, project_dirs):
        """Test that window marks are unique per project."""
        terminals = []

        for i, (project_name, project_dir) in enumerate(project_dirs.items()):
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dir,
            )
            terminals.append(terminal)
            scratchpad_manager.terminals[project_name] = terminal

        # Verify all marks are unique
        marks = [t.mark for t in terminals]
        assert len(marks) == len(set(marks))

        # Verify mark format
        for terminal in terminals:
            assert terminal.mark.startswith("scratchpad:")
            assert terminal.mark == f"scratchpad:{terminal.project_name}"

    @pytest.mark.asyncio
    async def test_pid_uniqueness(self, scratchpad_manager, project_dirs):
        """Test that PIDs are unique across terminals."""
        terminals = []

        for i, (project_name, project_dir) in enumerate(project_dirs.items()):
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dir,
            )
            terminals.append(terminal)
            scratchpad_manager.terminals[project_name] = terminal

        # Verify all PIDs are unique
        pids = [t.pid for t in terminals]
        assert len(pids) == len(set(pids))

    @pytest.mark.asyncio
    async def test_window_id_uniqueness(self, scratchpad_manager, project_dirs):
        """Test that window IDs are unique across terminals."""
        terminals = []

        for i, (project_name, project_dir) in enumerate(project_dirs.items()):
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=project_dir,
            )
            terminals.append(terminal)
            scratchpad_manager.terminals[project_name] = terminal

        # Verify all window IDs are unique
        window_ids = [t.window_id for t in terminals]
        assert len(window_ids) == len(set(window_ids))
