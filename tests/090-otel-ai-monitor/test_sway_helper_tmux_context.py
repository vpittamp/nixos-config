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
        "/dev/pts/4\tother/main\t0:bash\t%4\t0\t111\tbash\t0\t0\n"
        "/dev/pts/5\tworkflow-builder/main\t1:node\t%5\t1\t1234\tnode\t1\t0\n"
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
    assert context["tmux_socket"] == "/tmp/tmux-1000/default"
    assert context["tmux_server_key"] == "/tmp/tmux-1000/default"
    assert context["tmux_resolution_source"] == "discovered"


@pytest.mark.asyncio
async def test_list_tmux_panes_falls_back_to_alternate_socket(monkeypatch):
    fake_output = (
        "/dev/pts/5\tworkflow-builder/main\t1:node\t%5\t1\t1234\tnode\t1\t0\n"
    ).encode("utf-8")

    async def _fake_create_subprocess_exec(*args, **_kwargs):
        if args[:3] == ("tmux", "-S", "/tmp/tmux-1000/default"):
            return _FakeProc(stdout=fake_output, returncode=0)
        return _FakeProc(stdout=b"", returncode=1)

    monkeypatch.setattr(
        sway_helper_module,
        "_tmux_socket_candidates",
        lambda: ["/run/user/1000/tmux-1000/default", "/tmp/tmux-1000/default"],
    )
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

    panes = await sway_helper_module.list_tmux_panes()

    assert panes == [
        {
            "tmux_session": "workflow-builder/main",
            "tmux_window": "1:node",
            "tmux_pane": "%5",
            "tmux_socket": "/tmp/tmux-1000/default",
            "tmux_server_key": "/tmp/tmux-1000/default",
            "tmux_resolution_source": "discovered",
            "pane_index": "1",
            "pane_pid": 1234,
            "pane_title": "node",
            "pane_active": True,
            "window_active": False,
            "pty": "/dev/pts/5",
        }
    ]


def test_list_tmux_panes_sync_falls_back_to_alternate_socket(monkeypatch):
    fake_output = (
        "/dev/pts/2\tvpittamp/nixos-config/main\t0:main\t%12\t0\t1114052\tryzen\t1\t1\n"
    )

    class _FakeSyncProc:
        def __init__(self, stdout: str, returncode: int = 0):
            self.stdout = stdout
            self.returncode = returncode

    def _fake_run(args, **_kwargs):
        if args[:3] == ["tmux", "-S", "/tmp/tmux-1000/default"]:
            return _FakeSyncProc(stdout=fake_output, returncode=0)
        return _FakeSyncProc(stdout="", returncode=1)

    monkeypatch.setattr(
        sway_helper_module,
        "_tmux_socket_candidates",
        lambda: ["/run/user/1000/tmux-1000/default", "/tmp/tmux-1000/default"],
    )
    monkeypatch.setattr(sway_helper_module.subprocess, "run", _fake_run)

    panes = sway_helper_module.list_tmux_panes_sync()

    assert panes == [
        {
            "tmux_session": "vpittamp/nixos-config/main",
            "tmux_window": "0:main",
            "tmux_pane": "%12",
            "tmux_socket": "/tmp/tmux-1000/default",
            "tmux_server_key": "/tmp/tmux-1000/default",
            "tmux_resolution_source": "discovered",
            "pane_index": "0",
            "pane_pid": 1114052,
            "pane_title": "ryzen",
            "pane_active": True,
            "window_active": True,
            "pty": "/dev/pts/2",
        }
    ]
