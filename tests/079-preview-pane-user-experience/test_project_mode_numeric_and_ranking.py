"""
Regression tests for ':' project mode numeric filtering and ranking.

Focus:
- Digits typed after entering project mode (':') should be treated as filter input,
  not workspace digits.
- Numeric-only queries should filter by branch_number and use recency as a tie-breaker.
"""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path

import pytest


def _load_local_daemon_package() -> str:
    """Load i3-project-event-daemon as a synthetic package for relative imports."""
    pkg_name = "_i3_project_daemon_local"
    if pkg_name in sys.modules:
        return pkg_name

    repo_root = Path(__file__).resolve().parents[2]
    daemon_dir = repo_root / "home-modules" / "desktop" / "i3-project-event-daemon"

    spec = importlib.util.spec_from_file_location(
        pkg_name,
        daemon_dir / "__init__.py",
        submodule_search_locations=[str(daemon_dir)],
    )
    assert spec and spec.loader

    pkg = importlib.util.module_from_spec(spec)
    sys.modules[pkg_name] = pkg
    spec.loader.exec_module(pkg)
    return pkg_name


@pytest.mark.asyncio
async def test_workspace_mode_add_char_accepts_digits_in_project_mode():
    pkg_name = _load_local_daemon_package()
    workspace_mode = importlib.import_module(f"{pkg_name}.workspace_mode")

    manager = workspace_mode.WorkspaceModeManager(
        i3_connection=object(),
        config_dir=str(Path.cwd()),
        state_manager=None,
        workspace_tracker=None,
        ipc_server=None,
    )
    manager._state.active = True  # Avoid needing an i3 connection for enter_mode()

    # Enter project mode and type a digit filter
    await manager.add_char(":")
    accumulated = await manager.add_char("7")

    assert accumulated == "7"
    assert manager.state.input_type == "project"


@pytest.mark.asyncio
async def test_workspace_mode_digit_routes_to_project_filter_when_in_project_mode(monkeypatch):
    pkg_name = _load_local_daemon_package()
    ipc_server = importlib.import_module(f"{pkg_name}.ipc_server")

    class DummyState:
        input_type = "project"

    class DummyManager:
        state = DummyState()

        async def add_char(self, char: str) -> str:
            return f"proj:{char}"

        async def add_digit(self, digit: str) -> str:  # pragma: no cover
            raise AssertionError("add_digit should not be called in project mode")

    class DummyStateManager:
        workspace_mode_manager = DummyManager()

    server = ipc_server.IPCServer(state_manager=DummyStateManager())

    async def _noop_log(*_args, **_kwargs):
        return None

    monkeypatch.setattr(server, "_log_ipc_event", _noop_log)

    result = await server._workspace_mode_digit({"digit": "7"})
    assert result == {"accumulated_chars": "proj:7"}


def _mk_project(name: str, full_branch_name: str) -> "ProjectListItem":
    repo_root = Path(__file__).resolve().parents[2]
    daemon_path = repo_root / "home-modules" / "desktop" / "i3-project-event-daemon"
    sys.path.insert(0, str(daemon_path))
    from models.project_filter import ProjectListItem  # noqa: E402

    return ProjectListItem(
        name=name,
        display_name="Display",
        icon="🌿",
        is_worktree=True,
        directory_exists=True,
        relative_time="never",
        full_branch_name=full_branch_name,
    )


def test_numeric_filter_prefers_exact_branch_number(monkeypatch):
    repo_root = Path(__file__).resolve().parents[2]
    daemon_path = repo_root / "home-modules" / "desktop" / "i3-project-event-daemon"
    sys.path.insert(0, str(daemon_path))

    import project_filter_service  # noqa: E402

    monkeypatch.setattr(project_filter_service, "load_project_usage", lambda: {})

    p079 = _mk_project("acct/repo:079-preview-pane-user-experience", "079-preview-pane-user-experience")
    p179 = _mk_project("acct/repo:179-some-other-feature", "179-some-other-feature")

    results = project_filter_service.filter_projects([p079, p179], "079")
    assert [p.name for p in results] == [p079.name]
    assert results[0].match_score == 1000


def test_numeric_filter_uses_usage_as_tiebreak(monkeypatch):
    repo_root = Path(__file__).resolve().parents[2]
    daemon_path = repo_root / "home-modules" / "desktop" / "i3-project-event-daemon"
    sys.path.insert(0, str(daemon_path))

    import project_filter_service  # noqa: E402

    p079 = _mk_project("acct/repo:079-preview-pane-user-experience", "079-preview-pane-user-experience")
    p179 = _mk_project("acct/repo:179-some-other-feature", "179-some-other-feature")

    usage = {
        p079.name: {"last_used_at": 100, "use_count": 1},
        p179.name: {"last_used_at": 200, "use_count": 1},
    }
    monkeypatch.setattr(project_filter_service, "load_project_usage", lambda: usage)

    # Both branch numbers end with "79" -> same match_score; most recent should sort first.
    results = project_filter_service.filter_projects([p079, p179], "79")
    assert [p.name for p in results] == [p179.name, p079.name]
