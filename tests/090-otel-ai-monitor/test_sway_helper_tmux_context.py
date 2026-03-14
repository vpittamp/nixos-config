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
