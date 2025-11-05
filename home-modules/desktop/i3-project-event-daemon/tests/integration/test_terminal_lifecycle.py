"""
Integration tests for scratchpad terminal lifecycle.

Tests cover terminal launch, validation, state queries, toggle operations,
and interaction with Sway IPC.
"""

import pytest
import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import time

from services.scratchpad_manager import ScratchpadManager, read_process_environ
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


class TestTerminalLaunch:
    """Test terminal launch lifecycle."""

    @pytest.mark.asyncio
    async def test_launch_terminal_success(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test successful terminal launch."""
        project_name = "test-project"

        # Mock process creation
        mock_proc = AsyncMock()
        mock_proc.pid = 99999

        # Mock window appearance in Sway tree
        mock_window = MagicMock()
        mock_window.id = 123456
        mock_window.pid = 99999
        mock_window.app_id = "Alacritty"
        mock_window.marks = []

        mock_tree = MagicMock()
        mock_tree.descendants = MagicMock(return_value=[mock_window])
        mock_sway_connection.get_tree.return_value = mock_tree

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            terminal = await scratchpad_manager.launch_terminal(project_name, temp_project_dir)

        assert terminal.project_name == project_name
        assert terminal.pid == 99999
        assert terminal.window_id == 123456
        assert terminal.mark == f"scratchpad:{project_name}"
        assert terminal.working_dir == temp_project_dir
        assert project_name in scratchpad_manager.terminals

        # Verify Sway commands were called (mark + configure)
        assert mock_sway_connection.command.call_count >= 2

    @pytest.mark.asyncio
    async def test_launch_terminal_duplicate_project(self, scratchpad_manager, temp_project_dir):
        """Test launching terminal for project that already has one."""
        project_name = "test-project"

        # Create existing terminal
        existing_terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=11111,
            window_id=22222,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = existing_terminal

        # Attempt to launch duplicate
        with pytest.raises(ValueError, match="already exists"):
            await scratchpad_manager.launch_terminal(project_name, temp_project_dir)

    @pytest.mark.asyncio
    async def test_launch_terminal_nonexistent_directory(self, scratchpad_manager):
        """Test launching terminal with nonexistent working directory."""
        project_name = "test-project"
        nonexistent_dir = Path("/nonexistent/path/to/project")

        with pytest.raises(ValueError, match="does not exist"):
            await scratchpad_manager.launch_terminal(project_name, nonexistent_dir)

    @pytest.mark.asyncio
    async def test_launch_terminal_environment_variables(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test terminal launch injects correct environment variables."""
        project_name = "test-project"

        # Mock process creation
        mock_proc = AsyncMock()
        mock_proc.pid = 99999

        # Mock window appearance
        mock_window = MagicMock()
        mock_window.id = 123456
        mock_window.pid = 99999
        mock_window.app_id = "Alacritty"

        mock_tree = MagicMock()
        mock_tree.descendants = MagicMock(return_value=[mock_window])
        mock_sway_connection.get_tree.return_value = mock_tree

        captured_env = None

        async def capture_env(*args, **kwargs):
            nonlocal captured_env
            captured_env = kwargs.get("env", {})
            return mock_proc

        with patch("asyncio.create_subprocess_exec", side_effect=capture_env):
            await scratchpad_manager.launch_terminal(project_name, temp_project_dir)

        # Verify environment variables
        assert captured_env is not None
        assert captured_env["I3PM_SCRATCHPAD"] == "true"
        assert captured_env["I3PM_PROJECT_NAME"] == project_name
        assert captured_env["I3PM_WORKING_DIR"] == str(temp_project_dir)
        assert captured_env["I3PM_APP_NAME"] == "scratchpad-terminal"
        assert captured_env["I3PM_SCOPE"] == "scoped"
        assert "I3PM_APP_ID" in captured_env
        assert captured_env["I3PM_APP_ID"].startswith(f"scratchpad-{project_name}-")

    @pytest.mark.asyncio
    async def test_launch_terminal_window_timeout(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test terminal launch fails if window doesn't appear within timeout."""
        project_name = "test-project"

        # Mock process creation
        mock_proc = AsyncMock()
        mock_proc.pid = 99999

        # Mock empty Sway tree (window never appears)
        mock_tree = MagicMock()
        mock_tree.descendants = MagicMock(return_value=[])
        mock_sway_connection.get_tree.return_value = mock_tree

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            with pytest.raises(RuntimeError, match="did not appear within timeout"):
                await scratchpad_manager.launch_terminal(project_name, temp_project_dir)

        # Verify terminal was NOT added to state
        assert project_name not in scratchpad_manager.terminals


class TestTerminalValidation:
    """Test terminal validation logic."""

    @pytest.mark.asyncio
    async def test_validate_terminal_success(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test validation of healthy terminal."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process running
        with patch("psutil.pid_exists", return_value=True):
            # Mock window exists in Sway tree
            mock_window = MagicMock()
            mock_window.id = 123456
            mock_window.marks = [f"scratchpad:{project_name}"]

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            result = await scratchpad_manager.validate_terminal(project_name)

        assert result is True
        assert project_name in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_validate_terminal_missing(self, scratchpad_manager):
        """Test validation of non-existent terminal."""
        result = await scratchpad_manager.validate_terminal("nonexistent-project")
        assert result is False

    @pytest.mark.asyncio
    async def test_validate_terminal_process_dead(self, scratchpad_manager, temp_project_dir):
        """Test validation removes terminal with dead process."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process NOT running
        with patch("psutil.pid_exists", return_value=False):
            result = await scratchpad_manager.validate_terminal(project_name)

        assert result is False
        assert project_name not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_validate_terminal_window_missing(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test validation removes terminal with missing window."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process running but window missing
        with patch("psutil.pid_exists", return_value=True):
            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=None)
            mock_sway_connection.get_tree.return_value = mock_tree

            result = await scratchpad_manager.validate_terminal(project_name)

        assert result is False
        assert project_name not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_validate_terminal_mark_repair(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test validation repairs missing window mark."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process running, window exists but mark missing
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = 123456
            mock_window.marks = []  # Mark missing

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            result = await scratchpad_manager.validate_terminal(project_name)

        assert result is True
        # Verify mark command was called to repair
        mock_sway_connection.command.assert_called_once()
        assert "mark" in mock_sway_connection.command.call_args[0][0]


class TestTerminalToggle:
    """Test terminal toggle (show/hide) operations."""

    @pytest.mark.asyncio
    async def test_get_terminal_state_visible(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test getting state of visible terminal."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock validation success and visible window
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = 123456
            mock_window.marks = [f"scratchpad:{project_name}"]
            mock_window.parent = MagicMock()
            mock_window.parent.name = "workspace_1"  # Not scratchpad

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            state = await scratchpad_manager.get_terminal_state(project_name)

        assert state == "visible"

    @pytest.mark.asyncio
    async def test_get_terminal_state_hidden(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test getting state of hidden terminal."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock validation success and hidden window
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = 123456
            mock_window.marks = [f"scratchpad:{project_name}"]
            mock_window.parent = MagicMock()
            mock_window.parent.name = "__i3_scratch"  # In scratchpad

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            state = await scratchpad_manager.get_terminal_state(project_name)

        assert state == "hidden"

    @pytest.mark.asyncio
    async def test_toggle_terminal_hide(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test toggling visible terminal to hidden."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock validation and visible state
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = 123456
            mock_window.marks = [f"scratchpad:{project_name}"]
            mock_window.parent = MagicMock()
            mock_window.parent.name = "workspace_1"

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            result = await scratchpad_manager.toggle_terminal(project_name)

        assert result == "hidden"
        # Verify "move scratchpad" command was called
        mock_sway_connection.command.assert_called()
        assert "move scratchpad" in mock_sway_connection.command.call_args[0][0]

    @pytest.mark.asyncio
    async def test_toggle_terminal_show(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test toggling hidden terminal to visible."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock validation and hidden state
        with patch("psutil.pid_exists", return_value=True):
            mock_window = MagicMock()
            mock_window.id = 123456
            mock_window.marks = [f"scratchpad:{project_name}"]
            mock_window.parent = MagicMock()
            mock_window.parent.name = "__i3_scratch"

            mock_tree = MagicMock()
            mock_tree.find_by_id = MagicMock(return_value=mock_window)
            mock_sway_connection.get_tree.return_value = mock_tree

            before_toggle = time.time()
            result = await scratchpad_manager.toggle_terminal(project_name)
            after_toggle = time.time()

        assert result == "shown"
        # Verify "scratchpad show" command was called
        mock_sway_connection.command.assert_called()
        assert "scratchpad show" in mock_sway_connection.command.call_args[0][0]

        # Verify last_shown_at was updated
        assert terminal.last_shown_at is not None
        assert before_toggle <= terminal.last_shown_at <= after_toggle

    @pytest.mark.asyncio
    async def test_toggle_terminal_missing(self, scratchpad_manager):
        """Test toggling non-existent terminal."""
        with pytest.raises(ValueError, match="No scratchpad terminal found"):
            await scratchpad_manager.toggle_terminal("nonexistent-project")

    @pytest.mark.asyncio
    async def test_toggle_terminal_invalid(self, scratchpad_manager, temp_project_dir):
        """Test toggling invalid terminal (dead process)."""
        project_name = "test-project"

        # Create terminal
        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=99999,
            window_id=123456,
            mark=f"scratchpad:{project_name}",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals[project_name] = terminal

        # Mock process NOT running
        with patch("psutil.pid_exists", return_value=False):
            with pytest.raises(ValueError, match="invalid"):
                await scratchpad_manager.toggle_terminal(project_name)


class TestTerminalCleanup:
    """Test terminal cleanup operations."""

    @pytest.mark.asyncio
    async def test_cleanup_invalid_terminals(self, scratchpad_manager, temp_project_dir, mock_sway_connection):
        """Test cleanup removes only invalid terminals."""
        # Create multiple terminals
        terminals = {
            "valid-project": ScratchpadTerminal(
                project_name="valid-project",
                pid=11111,
                window_id=22222,
                mark="scratchpad:valid-project",
                working_dir=temp_project_dir,
            ),
            "dead-process": ScratchpadTerminal(
                project_name="dead-process",
                pid=33333,
                window_id=44444,
                mark="scratchpad:dead-process",
                working_dir=temp_project_dir,
            ),
            "missing-window": ScratchpadTerminal(
                project_name="missing-window",
                pid=55555,
                window_id=66666,
                mark="scratchpad:missing-window",
                working_dir=temp_project_dir,
            ),
        }
        scratchpad_manager.terminals = terminals

        # Mock validation results
        def mock_pid_exists(pid):
            if pid == 11111:
                return True  # valid-project
            elif pid == 33333:
                return False  # dead-process
            elif pid == 55555:
                return True  # missing-window
            return False

        with patch("psutil.pid_exists", side_effect=mock_pid_exists):
            # Mock Sway tree
            mock_window_valid = MagicMock()
            mock_window_valid.id = 22222
            mock_window_valid.marks = ["scratchpad:valid-project"]

            def mock_find_by_id(window_id):
                if window_id == 22222:
                    return mock_window_valid
                return None  # missing-window returns None

            mock_tree = MagicMock()
            mock_tree.find_by_id = mock_find_by_id
            mock_sway_connection.get_tree.return_value = mock_tree

            count = await scratchpad_manager.cleanup_invalid_terminals()

        assert count == 2  # dead-process and missing-window
        assert "valid-project" in scratchpad_manager.terminals
        assert "dead-process" not in scratchpad_manager.terminals
        assert "missing-window" not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_list_terminals(self, scratchpad_manager, temp_project_dir):
        """Test listing all terminals."""
        # Create terminals
        terminal1 = ScratchpadTerminal(
            project_name="project1",
            pid=11111,
            window_id=22222,
            mark="scratchpad:project1",
            working_dir=temp_project_dir,
        )
        terminal2 = ScratchpadTerminal(
            project_name="project2",
            pid=33333,
            window_id=44444,
            mark="scratchpad:project2",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals["project1"] = terminal1
        scratchpad_manager.terminals["project2"] = terminal2

        terminals = await scratchpad_manager.list_terminals()

        assert len(terminals) == 2
        assert terminal1 in terminals
        assert terminal2 in terminals

    @pytest.mark.asyncio
    async def test_get_terminal(self, scratchpad_manager, temp_project_dir):
        """Test retrieving specific terminal."""
        terminal = ScratchpadTerminal(
            project_name="test-project",
            pid=99999,
            window_id=123456,
            mark="scratchpad:test-project",
            working_dir=temp_project_dir,
        )
        scratchpad_manager.terminals["test-project"] = terminal

        result = scratchpad_manager.get_terminal("test-project")
        assert result == terminal

        result = scratchpad_manager.get_terminal("nonexistent")
        assert result is None


class TestProcessEnvironReader:
    """Test process environment variable reader."""

    def test_read_process_environ(self, tmp_path):
        """Test reading environment variables from /proc/{pid}/environ."""
        # Create mock environ file
        environ_content = b"HOME=/home/user\x00PATH=/usr/bin:/bin\x00I3PM_PROJECT_NAME=test\x00"
        mock_proc_dir = tmp_path / "proc" / "12345"
        mock_proc_dir.mkdir(parents=True)
        environ_file = mock_proc_dir / "environ"
        environ_file.write_bytes(environ_content)

        with patch("pathlib.Path", return_value=environ_file):
            env = read_process_environ(12345)

        assert env["HOME"] == "/home/user"
        assert env["PATH"] == "/usr/bin:/bin"
        assert env["I3PM_PROJECT_NAME"] == "test"

    def test_read_process_environ_missing_process(self):
        """Test reading environ for non-existent process."""
        with pytest.raises(ProcessLookupError):
            read_process_environ(9999999)
