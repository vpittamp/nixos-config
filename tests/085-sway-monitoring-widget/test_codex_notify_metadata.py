"""Regression tests for Codex notify hook session metadata bridge."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
NOTIFY_SCRIPT = REPO_ROOT / "scripts" / "codex-hooks" / "notify.js"
NODE = shutil.which("node")


@pytest.mark.skipif(NODE is None, reason="node is required")
def test_notify_writes_codex_session_metadata(tmp_path: Path) -> None:
    payload = json.dumps(
        {
            "type": "agent-turn-complete",
            "thread-id": "conv-test-123",
            "last-assistant-message": "done",
        }
    )

    env = os.environ.copy()
    env.update(
        {
            "XDG_RUNTIME_DIR": str(tmp_path),
            # Keep forward target invalid so the hook remains fully local in test.
            "CODEX_OTEL_INTERCEPTOR_HOST": "127.0.0.1",
            "CODEX_OTEL_INTERCEPTOR_PORT": "9",
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
            "I3PM_PROJECT_PATH": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "TMUX_SESSION": "nixos",
            "TMUX_WINDOW": "1",
            "TMUX_PANE": "%3",
            "TTY": "/dev/pts/7",
        }
    )

    subprocess.run([NODE, str(NOTIFY_SCRIPT), payload], check=True, cwd=REPO_ROOT, env=env)

    files = list(tmp_path.glob("codex-session-*.json"))
    assert len(files) == 1
    data = json.loads(files[0].read_text(encoding="utf-8"))
    assert data["sessionId"] == "conv-test-123"
    assert isinstance(data["pid"], int)
    assert data["pid"] > 1
    assert data["projectName"] == "vpittamp/nixos-config:main"
    assert data["projectPath"] == "/home/vpittamp/repos/vpittamp/nixos-config/main"
    assert data["tmuxSession"] == "nixos"
    assert data["tmuxWindow"] == "1"
    assert data["tmuxPane"] == "%3"
    assert data["pty"] == "/dev/pts/7"


@pytest.mark.skipif(NODE is None, reason="node is required")
def test_notify_without_thread_id_does_not_write_metadata(tmp_path: Path) -> None:
    payload = json.dumps(
        {
            "type": "agent-turn-complete",
            "last-assistant-message": "done",
        }
    )

    env = os.environ.copy()
    env.update(
        {
            "XDG_RUNTIME_DIR": str(tmp_path),
            "CODEX_OTEL_INTERCEPTOR_HOST": "127.0.0.1",
            "CODEX_OTEL_INTERCEPTOR_PORT": "9",
        }
    )

    subprocess.run([NODE, str(NOTIFY_SCRIPT), payload], check=True, cwd=REPO_ROOT, env=env)
    assert list(tmp_path.glob("codex-session-*.json")) == []

