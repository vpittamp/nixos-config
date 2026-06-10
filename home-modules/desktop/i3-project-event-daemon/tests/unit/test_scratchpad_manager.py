"""Unit tests for current ScratchpadManager storage helpers."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock

import pytest

from i3_project_daemon.models.scratchpad import ScratchpadTerminal
from i3_project_daemon.services.scratchpad_manager import (
    ScratchpadManager,
    build_ghostty_bash_lc_command,
)


def make_terminal(
    project_name: str,
    *,
    pid: int = 12345,
    window_id: int = 67890,
    context_key: str | None = None,
) -> ScratchpadTerminal:
    resolved_context_key = context_key or f"{project_name}::local::local@host"
    return ScratchpadTerminal(
        project_name=project_name,
        pid=pid,
        window_id=window_id,
        mark=ScratchpadTerminal.create_mark(project_name, window_id),
        working_dir=Path(f"/tmp/{project_name.replace('/', '-').replace(':', '-')}"),
        context_key=resolved_context_key,
        execution_mode="local",
        connection_key="local@host",
    )


@pytest.fixture
def mock_sway_connection() -> AsyncMock:
    mock_conn = AsyncMock()
    mock_conn.command = AsyncMock(return_value=None)
    mock_conn.get_tree = AsyncMock()
    return mock_conn


@pytest.fixture
def scratchpad_manager(mock_sway_connection: AsyncMock) -> ScratchpadManager:
    return ScratchpadManager(mock_sway_connection)


def test_manager_initialization(mock_sway_connection: AsyncMock) -> None:
    manager = ScratchpadManager(mock_sway_connection)

    assert manager.sway == mock_sway_connection
    assert manager.terminals == {}
    assert manager.logger is not None


def test_ghostty_command_uses_key_value_title_and_quotes_inner_command() -> None:
    cmd = build_ghostty_bash_lc_command("Scratchpad Terminal", "echo 'hello world'")

    assert "ghostty --title='Scratchpad Terminal'" in cmd
    assert "--title " not in cmd
    assert "bash -lc " in cmd
    assert "echo 'hello world'" not in cmd


def test_get_terminal_uses_context_key(scratchpad_manager: ScratchpadManager) -> None:
    terminal = make_terminal(
        "vpittamp/nixos-config:main",
        context_key="vpittamp/nixos-config:main::local::local@host",
    )
    scratchpad_manager.terminals[terminal.context_key] = terminal

    assert scratchpad_manager.get_terminal(terminal.context_key) == terminal
    assert scratchpad_manager.get_terminal("vpittamp/nixos-config:main") is None


@pytest.mark.asyncio
async def test_list_terminals_returns_all_tracked_contexts(scratchpad_manager: ScratchpadManager) -> None:
    terminals = [
        make_terminal("project0", pid=10000, window_id=20000),
        make_terminal("project1", pid=10001, window_id=20001),
        make_terminal(
            "project1",
            pid=10002,
            window_id=20002,
            context_key="project1::ssh::vpittamp@ryzen:22",
        ),
    ]
    for terminal in terminals:
        scratchpad_manager.terminals[terminal.context_key] = terminal

    result = await scratchpad_manager.list_terminals()

    assert len(result) == 3
    assert {terminal.context_key for terminal in result} == {
        "project0::local::local@host",
        "project1::local::local@host",
        "project1::ssh::vpittamp@ryzen:22",
    }


def test_context_keys_allow_independent_terminals_for_same_project(
    scratchpad_manager: ScratchpadManager,
) -> None:
    local_terminal = make_terminal(
        "project",
        pid=10001,
        window_id=20001,
        context_key="project::local::local@host",
    )
    remote_terminal = make_terminal(
        "project",
        pid=10002,
        window_id=20002,
        context_key="project::ssh::vpittamp@ryzen:22",
    )

    scratchpad_manager.terminals[local_terminal.context_key] = local_terminal
    scratchpad_manager.terminals[remote_terminal.context_key] = remote_terminal

    assert len(scratchpad_manager.terminals) == 2
    assert scratchpad_manager.get_terminal(local_terminal.context_key) == local_terminal
    assert scratchpad_manager.get_terminal(remote_terminal.context_key) == remote_terminal


def test_terminal_removal_by_context_key(scratchpad_manager: ScratchpadManager) -> None:
    terminal = make_terminal("removable-project")
    scratchpad_manager.terminals[terminal.context_key] = terminal

    assert scratchpad_manager.get_terminal(terminal.context_key) is terminal

    del scratchpad_manager.terminals[terminal.context_key]

    assert scratchpad_manager.get_terminal(terminal.context_key) is None
    assert terminal.context_key not in scratchpad_manager.terminals


def test_terminal_state_is_independent(scratchpad_manager: ScratchpadManager) -> None:
    terminal1 = make_terminal("project1", pid=10001, window_id=20001)
    terminal2 = make_terminal("project2", pid=10002, window_id=20002)
    scratchpad_manager.terminals[terminal1.context_key] = terminal1
    scratchpad_manager.terminals[terminal2.context_key] = terminal2

    terminal1.mark_shown()

    assert terminal1.last_shown_at is not None
    assert terminal2.last_shown_at is None
