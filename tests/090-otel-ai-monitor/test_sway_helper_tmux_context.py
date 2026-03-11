import importlib.util
import sys
from pathlib import Path

import pytest


def _load_otel_monitor_package():
    pkg_dir = (
        Path(__file__).resolve().parents[2]
        / "scripts"
        / "otel-ai-monitor"
    )
    spec = importlib.util.spec_from_file_location(
        "otel_ai_monitor",
        pkg_dir / "__init__.py",
        submodule_search_locations=[str(pkg_dir)],
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load otel_ai_monitor package")
    module = importlib.util.module_from_spec(spec)
    sys.modules["otel_ai_monitor"] = module
    spec.loader.exec_module(module)
    return module


_load_otel_monitor_package()
import otel_ai_monitor.sway_helper as sway_helper_module  # type: ignore  # noqa: E402


class _FakeProc:
    def __init__(self, stdout: bytes, returncode: int = 0):
        self._stdout = stdout
        self.returncode = returncode

    async def communicate(self):
        return self._stdout, b""


@pytest.mark.asyncio
async def test_get_tmux_context_for_pid_returns_session_window_and_pane(monkeypatch):
    monkeypatch.setattr(
        sway_helper_module,
        "get_process_tty_path",
        lambda _pid: "/dev/pts/5",
    )

    fake_output = (
        "/dev/pts/4\tother/main\t0\tbash\t%4\t0\n"
        "/dev/pts/5\tworkflow-builder/main\t1\tnode\t%5\t0\n"
    ).encode("utf-8")

    async def _fake_create_subprocess_exec(*_args, **_kwargs):
        return _FakeProc(stdout=fake_output, returncode=0)

    monkeypatch.setattr(
        sway_helper_module.asyncio,
        "create_subprocess_exec",
        _fake_create_subprocess_exec,
    )
    monkeypatch.setattr(
        sway_helper_module.asyncio,
        "wait_for",
        lambda coro, timeout: coro,
    )

    context = await sway_helper_module.get_tmux_context_for_pid(1234)

    assert context["pty"] == "/dev/pts/5"
    assert context["tmux_session"] == "workflow-builder/main"
    assert context["tmux_window"] == "1:node"
    assert context["tmux_pane"] == "%5"


@pytest.mark.asyncio
async def test_find_window_for_session_prefers_tmux_project_over_stale_i3pm_project(monkeypatch):
    monkeypatch.setattr(
        sway_helper_module,
        "get_process_i3pm_env",
        lambda _pid: {
            "I3PM_APP_ID": "terminal-vpittamp/nixos-config-main-1108845-1762351323",
            "I3PM_APP_NAME": "terminal",
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
        },
    )
    monkeypatch.setattr(
        sway_helper_module,
        "get_process_env_values",
        lambda _pid, include_keys=(), include_prefixes=(): (
            {"PWD": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main"}
            if "PWD" in include_keys
            else {}
        ),
    )
    monkeypatch.setattr(
        sway_helper_module,
        "parse_correlation_key",
        lambda _app_id, _app_name: "terminal-1762351323",
    )

    async def _fake_query(_app_name: str, _timestamp: int):
        return {"window_id": None, "correlation_confidence": "none"}

    async def _fake_tmux_context(_pid: int):
        return {
            "tmux_session": "workflow-builder/main",
            "tmux_window": "0:codex-raw",
            "tmux_pane": "%5",
            "pty": "/dev/pts/5",
        }

    async def _fake_tmux_client(_pid: int, *, tmux_ctx=None):
        assert tmux_ctx is not None
        assert tmux_ctx["tmux_session"] == "workflow-builder/main"
        return None

    project_queries: list[str] = []

    def _fake_find_all_terminal_windows(project_name: str):
        project_queries.append(project_name)
        if project_name == "PittampalliOrg/workflow-builder:main":
            return [2218]
        if project_name == "vpittamp/nixos-config:main":
            return [2212]
        return []

    monkeypatch.setattr(
        sway_helper_module,
        "query_daemon_for_window_by_launch_id",
        _fake_query,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "get_tmux_context_for_pid",
        _fake_tmux_context,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "find_window_via_tmux_client",
        _fake_tmux_client,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "_tmux_session_project_hints",
        lambda: {"workflow-builder-main": "PittampalliOrg/workflow-builder:main"},
    )
    monkeypatch.setattr(
        sway_helper_module,
        "find_all_terminal_windows_for_project",
        _fake_find_all_terminal_windows,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "get_focused_window_info",
        lambda: (None, None),
    )

    window_id = await sway_helper_module.find_window_for_session(1108845)

    assert window_id == 2218
    assert project_queries == ["PittampalliOrg/workflow-builder:main"]


@pytest.mark.asyncio
async def test_find_window_for_session_prefers_pwd_project_over_stale_i3pm_project(monkeypatch):
    monkeypatch.setattr(
        sway_helper_module,
        "get_process_i3pm_env",
        lambda _pid: {
            "I3PM_APP_ID": "terminal-vpittamp/nixos-config-main-1108845-1762351323",
            "I3PM_APP_NAME": "terminal",
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
        },
    )
    monkeypatch.setattr(
        sway_helper_module,
        "get_process_env_values",
        lambda _pid, include_keys=(), include_prefixes=(): (
            {"PWD": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main"}
            if "PWD" in include_keys
            else {}
        ),
    )
    monkeypatch.setattr(
        sway_helper_module,
        "parse_correlation_key",
        lambda _app_id, _app_name: "terminal-1762351323",
    )

    async def _fake_query(_app_name: str, _timestamp: int):
        return {"window_id": None, "correlation_confidence": "none"}

    async def _fake_tmux_context(_pid: int):
        return {
            "tmux_session": None,
            "tmux_window": None,
            "tmux_pane": "%5",
            "pty": "/dev/pts/5",
        }

    async def _fake_tmux_client(_pid: int, *, tmux_ctx=None):
        assert tmux_ctx is not None
        return None

    project_queries: list[str] = []

    def _fake_find_all_terminal_windows(project_name: str):
        project_queries.append(project_name)
        if project_name == "PittampalliOrg/workflow-builder:main":
            return [2218]
        if project_name == "vpittamp/nixos-config:main":
            return [2212]
        return []

    monkeypatch.setattr(
        sway_helper_module,
        "query_daemon_for_window_by_launch_id",
        _fake_query,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "get_tmux_context_for_pid",
        _fake_tmux_context,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "find_window_via_tmux_client",
        _fake_tmux_client,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "_tmux_session_project_hints",
        lambda: {},
    )
    monkeypatch.setattr(
        sway_helper_module,
        "find_all_terminal_windows_for_project",
        _fake_find_all_terminal_windows,
    )
    monkeypatch.setattr(
        sway_helper_module,
        "get_focused_window_info",
        lambda: (None, None),
    )

    window_id = await sway_helper_module.find_window_for_session(1108845)

    assert window_id == 2218
    assert project_queries == ["PittampalliOrg/workflow-builder:main"]
