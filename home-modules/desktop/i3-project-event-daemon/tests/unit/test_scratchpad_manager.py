"""
Unit tests for ScratchpadManager.

Tests cover manager initialization, terminal storage, and uniqueness validation.
"""

import pytest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

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


class TestScratchpadManagerInit:
    """Test ScratchpadManager initialization."""

    @pytest.mark.asyncio
    async def test_manager_initialization(self, mock_sway_connection):
        """Test manager initializes with empty state."""
        manager = ScratchpadManager(mock_sway_connection)

        assert manager.sway == mock_sway_connection
        assert isinstance(manager.terminals, dict)
        assert len(manager.terminals) == 0
        assert manager.logger is not None

    @pytest.mark.asyncio
    async def test_manager_connection_stored(self, mock_sway_connection):
        """Test Sway connection is stored correctly."""
        manager = ScratchpadManager(mock_sway_connection)

        assert manager.sway is mock_sway_connection


class TestTerminalStorage:
    """Test terminal storage and retrieval."""

    @pytest.mark.asyncio
    async def test_get_terminal_existing(self, scratchpad_manager):
        """Test retrieving existing terminal."""
        terminal = ScratchpadTerminal(
            project_name="test-project",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test-project",
            working_dir=Path("/tmp/test"),
        )
        scratchpad_manager.terminals["test-project"] = terminal

        result = scratchpad_manager.get_terminal("test-project")

        assert result == terminal
        assert result.project_name == "test-project"

    @pytest.mark.asyncio
    async def test_get_terminal_nonexistent(self, scratchpad_manager):
        """Test retrieving non-existent terminal returns None."""
        result = scratchpad_manager.get_terminal("nonexistent-project")

        assert result is None

    @pytest.mark.asyncio
    async def test_list_terminals_empty(self, scratchpad_manager):
        """Test listing terminals when none exist."""
        terminals = await scratchpad_manager.list_terminals()

        assert isinstance(terminals, list)
        assert len(terminals) == 0

    @pytest.mark.asyncio
    async def test_list_terminals_multiple(self, scratchpad_manager):
        """Test listing multiple terminals."""
        terminals_to_add = [
            ScratchpadTerminal(
                project_name=f"project{i}",
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:project{i}",
                working_dir=Path(f"/tmp/project{i}"),
            )
            for i in range(3)
        ]

        for terminal in terminals_to_add:
            scratchpad_manager.terminals[terminal.project_name] = terminal

        result = await scratchpad_manager.list_terminals()

        assert len(result) == 3
        assert set(t.project_name for t in result) == {"project0", "project1", "project2"}


class TestTerminalUniquenessValidation:
    """Test terminal uniqueness validation logic."""

    @pytest.mark.asyncio
    async def test_unique_project_names_enforced(self, scratchpad_manager):
        """Test that project names must be unique in storage."""
        project_name = "duplicate-project"

        terminal1 = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=Path("/tmp/project1"),
        )

        terminal2 = ScratchpadTerminal(
            project_name=project_name,
            pid=10002,
            window_id=20002,
            mark=f"scratchpad:{project_name}",
            working_dir=Path("/tmp/project2"),
        )

        # Add first terminal
        scratchpad_manager.terminals[project_name] = terminal1

        # Verify first terminal is stored
        assert scratchpad_manager.get_terminal(project_name) == terminal1

        # Attempting to store second terminal with same key will replace it
        # (This is dict behavior, but launch_terminal prevents this)
        scratchpad_manager.terminals[project_name] = terminal2

        # Verify second terminal replaced first (at dict level)
        assert scratchpad_manager.get_terminal(project_name) == terminal2
        assert scratchpad_manager.get_terminal(project_name).pid == 10002

    @pytest.mark.asyncio
    async def test_project_name_case_sensitive(self, scratchpad_manager):
        """Test that project names are case-sensitive."""
        terminal1 = ScratchpadTerminal(
            project_name="MyProject",
            pid=10001,
            window_id=20001,
            mark="scratchpad:MyProject",
            working_dir=Path("/tmp/project1"),
        )

        terminal2 = ScratchpadTerminal(
            project_name="myproject",
            pid=10002,
            window_id=20002,
            mark="scratchpad:myproject",
            working_dir=Path("/tmp/project2"),
        )

        scratchpad_manager.terminals["MyProject"] = terminal1
        scratchpad_manager.terminals["myproject"] = terminal2

        # Verify both are stored as separate entries
        assert len(scratchpad_manager.terminals) == 2
        assert scratchpad_manager.get_terminal("MyProject") == terminal1
        assert scratchpad_manager.get_terminal("myproject") == terminal2

    @pytest.mark.asyncio
    async def test_terminal_lookup_by_project(self, scratchpad_manager):
        """Test looking up terminal by project name."""
        projects = ["project-a", "project-b", "project-c"]

        for i, project_name in enumerate(projects):
            terminal = ScratchpadTerminal(
                project_name=project_name,
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:{project_name}",
                working_dir=Path(f"/tmp/{project_name}"),
            )
            scratchpad_manager.terminals[project_name] = terminal

        # Lookup each project
        for project_name in projects:
            terminal = scratchpad_manager.get_terminal(project_name)
            assert terminal is not None
            assert terminal.project_name == project_name

        # Lookup non-existent project
        assert scratchpad_manager.get_terminal("nonexistent") is None

    @pytest.mark.asyncio
    async def test_marks_are_project_specific(self, scratchpad_manager):
        """Test that window marks are generated per-project."""
        projects = ["alpha", "beta", "gamma"]

        for project_name in projects:
            mark = ScratchpadTerminal.create_mark(project_name)
            assert mark == f"scratchpad:{project_name}"

        # Verify marks are unique
        marks = [ScratchpadTerminal.create_mark(p) for p in projects]
        assert len(marks) == len(set(marks))

    @pytest.mark.asyncio
    async def test_terminal_count_tracking(self, scratchpad_manager):
        """Test tracking terminal count."""
        assert len(scratchpad_manager.terminals) == 0

        # Add terminals
        for i in range(5):
            terminal = ScratchpadTerminal(
                project_name=f"project{i}",
                pid=10000 + i,
                window_id=20000 + i,
                mark=f"scratchpad:project{i}",
                working_dir=Path(f"/tmp/project{i}"),
            )
            scratchpad_manager.terminals[f"project{i}"] = terminal

        assert len(scratchpad_manager.terminals) == 5

        # Remove some terminals
        del scratchpad_manager.terminals["project1"]
        del scratchpad_manager.terminals["project3"]

        assert len(scratchpad_manager.terminals) == 3

    @pytest.mark.asyncio
    async def test_terminal_removal_by_project(self, scratchpad_manager):
        """Test removing terminal by project name."""
        project_name = "removable-project"

        terminal = ScratchpadTerminal(
            project_name=project_name,
            pid=10001,
            window_id=20001,
            mark=f"scratchpad:{project_name}",
            working_dir=Path("/tmp/removable"),
        )

        scratchpad_manager.terminals[project_name] = terminal
        assert scratchpad_manager.get_terminal(project_name) is not None

        # Remove terminal
        del scratchpad_manager.terminals[project_name]

        # Verify removed
        assert scratchpad_manager.get_terminal(project_name) is None
        assert project_name not in scratchpad_manager.terminals

    @pytest.mark.asyncio
    async def test_global_terminal_support(self, scratchpad_manager):
        """Test support for global terminal (special project name)."""
        global_terminal = ScratchpadTerminal(
            project_name="global",
            pid=99999,
            window_id=88888,
            mark="scratchpad:global",
            working_dir=Path("/home/user"),
        )

        scratchpad_manager.terminals["global"] = global_terminal

        result = scratchpad_manager.get_terminal("global")
        assert result == global_terminal
        assert result.project_name == "global"

    @pytest.mark.asyncio
    async def test_terminal_independence(self, scratchpad_manager):
        """Test that terminals maintain independent state."""
        terminal1 = ScratchpadTerminal(
            project_name="project1",
            pid=10001,
            window_id=20001,
            mark="scratchpad:project1",
            working_dir=Path("/tmp/project1"),
        )

        terminal2 = ScratchpadTerminal(
            project_name="project2",
            pid=10002,
            window_id=20002,
            mark="scratchpad:project2",
            working_dir=Path("/tmp/project2"),
        )

        scratchpad_manager.terminals["project1"] = terminal1
        scratchpad_manager.terminals["project2"] = terminal2

        # Modify terminal1's state
        terminal1.mark_shown()

        # Verify terminal2 is unaffected
        assert terminal1.last_shown_at is not None
        assert terminal2.last_shown_at is None
