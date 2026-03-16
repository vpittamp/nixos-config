#!/usr/bin/env python3

import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path


def shell_join(parts: list[str]) -> str:
    return " ".join(shlex.quote(str(part)) for part in parts)


def load_spec(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise RuntimeError("remote launch spec must be a JSON object")
    return payload


def write_status(spec: dict, *, status: str, error_code: str = "", error_message: str = "") -> None:
    status_file = Path(str(spec.get("status_file") or "").strip())
    if not status_file:
        return
    status_file.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "launch_id": str(spec.get("launch_id") or "").strip(),
        "launch_kind": str(spec.get("launch_kind") or "").strip(),
        "status": status,
        "error_code": error_code,
        "error_message": error_message,
        "project_name": str(spec.get("project_name") or "").strip(),
        "execution_mode": str(spec.get("execution_mode") or "").strip(),
        "connection_key": str(spec.get("connection_key") or "").strip(),
        "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
        "updated_at": int(time.time()),
    }
    temp_path = status_file.with_suffix(status_file.suffix + ".tmp")
    with open(temp_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temp_path, status_file)


def build_env_prefix(spec: dict) -> list[str]:
    environment = spec.get("environment") or {}
    if not isinstance(environment, dict):
        environment = {}
    env_parts = ["env"]
    for key, value in sorted(environment.items()):
        env_parts.append(f"{str(key)}={str(value)}")
    return env_parts


def build_remote_attach_script(spec: dict, remote_dir: str) -> str:
    remote_attach = spec.get("terminal_launch", {}).get("remote_attach") or {}
    if not isinstance(remote_attach, dict):
        remote_attach = {}
    tmux_session = str(remote_attach.get("tmux_session") or "").strip()
    tmux_window = str(remote_attach.get("tmux_window") or "").strip()
    tmux_pane = str(remote_attach.get("tmux_pane") or "").strip()
    tmux_socket = str(remote_attach.get("tmux_socket") or "").strip()
    if not (tmux_session and tmux_window and tmux_pane):
        raise RuntimeError("remote AI attach requires exact tmux session/window/pane identity")
    tmux_window_index = str(tmux_window).split(":", 1)[0].strip() or str(tmux_window)
    tmux_cmd = f"tmux -S {shlex.quote(tmux_socket)}" if tmux_socket else "tmux"
    script_lines = ["set -euo pipefail"]
    if remote_dir:
        script_lines.append(f"cd {shlex.quote(remote_dir)}")
    script_lines.extend([
        f"{tmux_cmd} has-session -t {shlex.quote(tmux_session)} >/dev/null 2>&1",
        (
            f"{tmux_cmd} list-panes -t {shlex.quote(f'{tmux_session}:{tmux_window_index}')} "
            f"-F '#{{pane_id}}' | grep -Fx {shlex.quote(tmux_pane)} >/dev/null"
        ),
        f"{tmux_cmd} select-window -t {shlex.quote(f'{tmux_session}:{tmux_window_index}')} >/dev/null 2>&1",
        f"{tmux_cmd} select-pane -t {shlex.quote(tmux_pane)} >/dev/null 2>&1",
    ])
    return "\n".join(script_lines)


def build_remote_interactive_invocation(spec: dict) -> tuple[list[str], list[str]]:
    terminal_launch = spec.get("terminal_launch") or {}
    if not isinstance(terminal_launch, dict):
        terminal_launch = {}
    remote = terminal_launch.get("remote") or {}
    if not isinstance(remote, dict):
        remote = {}
    helper_name = str(terminal_launch.get("helper_name") or "project-terminal-launch.sh").strip()
    helper_args = [str(arg) for arg in (terminal_launch.get("helper_args") or [])]
    remote_dir = str(remote.get("remote_dir") or "").strip()
    remote_user = str(remote.get("user") or "").strip()
    remote_host = str(remote.get("host") or "").strip()
    remote_port = int(remote.get("port", 22) or 22)
    if not (remote_host and helper_name):
        raise RuntimeError("remote launch requires a complete SSH destination")

    destination = f"{remote_user}@{remote_host}" if remote_user else remote_host
    env_prefix = build_env_prefix(spec)
    remote_attach = terminal_launch.get("remote_attach") or {}
    if remote_attach:
        preflight_script = build_remote_attach_script(spec, remote_dir)
        attach_script = preflight_script + "\n" + (
            f"exec env TMUX= {'tmux -S ' + shlex.quote(str(remote_attach.get('tmux_socket') or '').strip()) if str(remote_attach.get('tmux_socket') or '').strip() else 'tmux'} "
            f"attach-session -t {shlex.quote(str(remote_attach.get('tmux_session') or '').strip())}"
        )
        return (
            ["ssh", "-tt", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p", str(remote_port), destination,
             "bash", "-lc", attach_script],
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p", str(remote_port), destination,
             "bash", "-lc", preflight_script],
        )

    remote_command = env_prefix + [helper_name, remote_dir, *helper_args]
    remote_script = "set -euo pipefail\n"
    if remote_dir:
        remote_script += f"test -d {shlex.quote(remote_dir)}\n"
    remote_script += f"command -v {shlex.quote(helper_name)} >/dev/null 2>&1\n"
    return (
        ["ssh", "-tt", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p", str(remote_port), destination,
         shell_join(remote_command)],
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p", str(remote_port), destination,
         "bash", "-lc", remote_script],
    )


def build_remote_command_dispatch(spec: dict) -> tuple[list[str], str]:
    terminal_launch = spec.get("terminal_launch") or {}
    if not isinstance(terminal_launch, dict):
        terminal_launch = {}
    remote = terminal_launch.get("remote") or {}
    if not isinstance(remote, dict):
        remote = {}
    tmux_session_name = str(terminal_launch.get("tmux_session_name") or spec.get("tmux_session_name") or "").strip()
    helper_args = [str(arg) for arg in (terminal_launch.get("helper_args") or [])]
    remote_dir = str(remote.get("remote_dir") or spec.get("project_directory") or "").strip()
    remote_user = str(remote.get("user") or "").strip()
    remote_host = str(remote.get("host") or "").strip()
    remote_port = int(remote.get("port", 22) or 22)
    environment = spec.get("environment") or {}
    if not isinstance(environment, dict):
        environment = {}
    if not (tmux_session_name and helper_args and remote_dir and remote_host):
        raise RuntimeError("remote scoped command dispatch requires exact tmux session and SSH profile")

    destination = f"{remote_user}@{remote_host}" if remote_user else remote_host
    tmux_socket = str(environment.get("I3PM_TMUX_SOCKET") or "").strip()
    tmux_cmd = f"tmux -S {shlex.quote(tmux_socket)}" if tmux_socket else "tmux"
    window_name = Path(str(helper_args[0])).name[:24] or "cmd"
    command_string = shell_join(helper_args)
    script_lines = ["set -euo pipefail"]
    for key, value in sorted(environment.items()):
        if not str(key).startswith("I3PM_"):
            continue
        script_lines.append(
            f"{tmux_cmd} set-environment -t {shlex.quote(tmux_session_name)} {shlex.quote(str(key))} {shlex.quote(str(value))}"
        )
    script_lines.append(f"{tmux_cmd} has-session -t {shlex.quote(tmux_session_name)} >/dev/null 2>&1")
    script_lines.append(
        f"{tmux_cmd} new-window -t {shlex.quote(tmux_session_name)} -c {shlex.quote(remote_dir)} -n {shlex.quote(window_name)} \"exec {command_string}\""
    )
    remote_script = "\n".join(script_lines)
    return (
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p", str(remote_port), destination,
         "bash", "-lc", remote_script],
        remote_script,
    )


def fail_with_prompt(spec: dict, *, error_code: str, error_message: str) -> int:
    write_status(spec, status="failed", error_code=error_code, error_message=error_message)
    print(f"[i3pm] {error_message}", file=sys.stderr)
    if sys.stdin.isatty():
        try:
            input("[i3pm] Press Enter to close...")
        except EOFError:
            pass
    return 1


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: project-remote-launch.py <spec-path>", file=sys.stderr)
        return 2

    spec_path = Path(sys.argv[1])
    spec = load_spec(spec_path)
    launch_kind = str(spec.get("launch_kind") or "").strip()

    try:
        if launch_kind == "open_scoped_command":
            write_status(spec, status="connecting_remote")
            command, _preflight = build_remote_command_dispatch(spec)
            result = subprocess.run(command, check=False, text=True, capture_output=True)
            if result.returncode != 0:
                return fail_with_prompt(
                    spec,
                    error_code="remote_tmux_command_failed",
                    error_message=str(result.stderr or result.stdout or "Remote tmux command failed").strip(),
                )
            write_status(spec, status="running")
            return 0

        write_status(spec, status="connecting_remote")
        command, preflight_command = build_remote_interactive_invocation(spec)
        preflight_result = subprocess.run(preflight_command, check=False, text=True, capture_output=True)
        if preflight_result.returncode != 0:
            return fail_with_prompt(
                spec,
                error_code="remote_target_unavailable",
                error_message=str(preflight_result.stderr or preflight_result.stdout or "Remote target is unavailable").strip(),
            )

        write_status(spec, status="attaching_tmux" if launch_kind == "attach_ai_session" else "running")
        os.execvp(command[0], command)
    except Exception as exc:
        return fail_with_prompt(
            spec,
            error_code="remote_launcher_failed",
            error_message=str(exc),
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
