from __future__ import annotations

import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[5]
HELPER_PATH = REPO_ROOT / "scripts" / "managed-tmux-session.sh"


def _run_helper_shell(script: str) -> str:
    result = subprocess.run(
        ["bash", "-lc", script],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def test_prepare_terminal_term_replaces_dumb_term() -> None:
    output = _run_helper_shell(
        f"source {HELPER_PATH}; export TERM=dumb; managed_tmux_prepare_terminal_term; printf '%s' \"$TERM\""
    )

    assert output == "xterm-256color"


def test_prepare_terminal_term_preserves_existing_term() -> None:
    output = _run_helper_shell(
        f"source {HELPER_PATH}; export TERM=tmux-256color; managed_tmux_prepare_terminal_term; printf '%s' \"$TERM\""
    )

    assert output == "tmux-256color"
