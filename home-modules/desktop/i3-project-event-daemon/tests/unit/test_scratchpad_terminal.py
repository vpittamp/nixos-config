"""Unit tests for current scratchpad terminal identity model."""

from __future__ import annotations

import time
from pathlib import Path

import pytest
from pydantic import ValidationError

from i3_project_daemon.models.scratchpad import ScratchpadTerminal


def make_terminal(
    project_name: str = "vpittamp/nixos-config:main",
    *,
    pid: int = 12345,
    window_id: int = 67890,
    working_dir: Path = Path("/tmp"),
    context_key: str | None = None,
) -> ScratchpadTerminal:
    resolved_context_key = f"{project_name}::local::local@host" if context_key is None else context_key
    return ScratchpadTerminal(
        project_name=project_name,
        pid=pid,
        window_id=window_id,
        mark=ScratchpadTerminal.create_mark(project_name, window_id),
        working_dir=working_dir,
        context_key=resolved_context_key,
        execution_mode="local",
        connection_key="local@host",
        tmux_session_name="sp-test",
    )


def test_valid_terminal_creation_requires_context_identity() -> None:
    terminal = make_terminal("my-project", working_dir=Path("/home/user/projects/my-project"))

    assert terminal.project_name == "my-project"
    assert terminal.window_id == 67890
    assert terminal.context_key == "my-project::local::local@host"
    assert terminal.mark == "scoped:scratchpad-terminal:my-project:67890"
    assert terminal.execution_mode == "local"
    assert terminal.last_shown_at is None
    assert isinstance(terminal.created_at, float)
    assert terminal.created_at <= time.time()


def test_project_name_validation_accepts_legacy_and_qualified_names() -> None:
    valid_names = [
        "project",
        "my-project",
        "my_project",
        "project123",
        "vpittamp/nixos-config:main",
    ]
    for name in valid_names:
        assert make_terminal(name).project_name == name

    for name in ["my project", "project!", "test@env", ""]:
        with pytest.raises(ValidationError):
            make_terminal(name)


def test_required_identity_fields_are_validated() -> None:
    with pytest.raises(ValidationError):
        ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=67890,
            mark=ScratchpadTerminal.create_mark("test", 67890),
            working_dir=Path("/tmp"),
        )

    with pytest.raises(ValidationError):
        make_terminal("test", context_key="")


def test_pid_window_id_mark_and_working_dir_validation() -> None:
    assert make_terminal("test", pid=1, window_id=1).pid == 1

    with pytest.raises(ValidationError):
        make_terminal("test", pid=0)
    with pytest.raises(ValidationError):
        make_terminal("test", window_id=0)
    with pytest.raises(ValidationError):
        ScratchpadTerminal(
            project_name="test",
            pid=12345,
            window_id=67890,
            mark="scratchpad:test",
            working_dir=Path("/tmp"),
            context_key="test::local::local@host",
        )
    with pytest.raises(ValidationError):
        make_terminal("test", working_dir=Path("relative/path"))


def test_create_mark_uses_unified_scoped_window_mark() -> None:
    assert ScratchpadTerminal.create_mark("my-project", 42) == "scoped:scratchpad-terminal:my-project:42"
    assert (
        ScratchpadTerminal.create_mark("vpittamp/nixos-config:main", 42)
        == "scoped:scratchpad-terminal:vpittamp/nixos-config:main:42"
    )


def test_mark_shown_and_to_dict_include_context_fields() -> None:
    terminal = make_terminal("test-project", working_dir=Path("/home/user/test-project"))
    before_mark = time.time()
    terminal.mark_shown()
    after_mark = time.time()

    result = terminal.to_dict()

    assert before_mark <= terminal.last_shown_at <= after_mark
    assert result["project_name"] == "test-project"
    assert result["mark"] == "scoped:scratchpad-terminal:test-project:67890"
    assert result["working_dir"] == "/home/user/test-project"
    assert result["context_key"] == "test-project::local::local@host"
    assert result["execution_mode"] == "local"
    assert result["connection_key"] == "local@host"
    assert result["tmux_session_name"] == "sp-test"
    assert isinstance(result["created_at"], float)
    assert isinstance(result["last_shown_at"], float)


def test_is_process_running_uses_psutil(monkeypatch: pytest.MonkeyPatch) -> None:
    terminal = make_terminal("test")

    import psutil

    monkeypatch.setattr(psutil, "pid_exists", lambda pid: pid == 12345)
    assert terminal.is_process_running() is True

    monkeypatch.setattr(psutil, "pid_exists", lambda _pid: False)
    assert terminal.is_process_running() is False
