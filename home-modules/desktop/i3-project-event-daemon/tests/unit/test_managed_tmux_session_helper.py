from __future__ import annotations

import os
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


def test_prepare_terminal_term_replaces_linux_term() -> None:
    output = _run_helper_shell(
        f"source {HELPER_PATH}; export TERM=linux; managed_tmux_prepare_terminal_term; printf '%s' \"$TERM\""
    )

    assert output == "xterm-256color"


def test_current_socket_uses_canonical_runtime_path() -> None:
    runtime_dir = "/tmp/i3pm-runtime-managed"
    expected = f"{runtime_dir}/tmux-{os.getuid()}/default"
    output = _run_helper_shell(
        f"export XDG_RUNTIME_DIR={runtime_dir}; export TMUX=/tmp/tmux-{os.getuid()}/default,123,0; source {HELPER_PATH}; managed_tmux_current_socket"
    )

    assert output == expected


def test_prepare_env_exports_canonical_tmux_metadata() -> None:
    runtime_dir = "/tmp/i3pm-runtime-managed"
    expected = f"{runtime_dir}/tmux-{os.getuid()}/default"
    output = _run_helper_shell(
        f"export XDG_RUNTIME_DIR={runtime_dir}; export TMUX=/tmp/tmux-{os.getuid()}/default,123,0; source {HELPER_PATH}; managed_tmux_prepare_env demo-session; printf '%s|%s' \"$I3PM_TMUX_SOCKET\" \"$I3PM_TMUX_SERVER_KEY\""
    )

    assert output == f"{expected}|{expected}"


def test_recreate_reason_detects_server_key_mismatch() -> None:
    output = _run_helper_shell(
        f"""
        source {HELPER_PATH}
        export I3PM_CONTEXT_KEY='ctx'
        export I3PM_TERMINAL_ROLE='project-main'
        export I3PM_TMUX_SERVER_KEY='/expected/socket'
        managed_tmux() {{
            if [[ "$1" == "show-options" && "$2" == "-t" && "$3" == "demo-session" && "$4" == "-qv" ]]; then
                case "$5" in
                    @i3pm_managed) printf '1' ;;
                    @i3pm_context_key) printf 'ctx' ;;
                    @i3pm_terminal_role) printf 'project-main' ;;
                    @i3pm_tmux_server_key) printf '/wrong/socket' ;;
                    @i3pm_schema_version) printf '1' ;;
                esac
                return 0
            fi
            return 1
        }}
        managed_tmux_recreate_reason demo-session
        """
    )

    assert output == "server_key_mismatch:/wrong/socket"


def test_quarantine_session_renames_instead_of_killing(tmp_path) -> None:
    log_path = tmp_path / "tmux.log"
    output = _run_helper_shell(
        f"""
        source {HELPER_PATH}
        managed_tmux() {{
            printf '%s\\n' "$*" >> {log_path}
            return 0
        }}
        quarantine_name="$(managed_tmux_quarantine_session demo-session 'context_mismatch:old')"
        printf '%s' "$quarantine_name"
        """
    )

    assert output.startswith("orphan-demo-session-context_mismatch-old-")
    assert "rename-session -t demo-session" in log_path.read_text()
