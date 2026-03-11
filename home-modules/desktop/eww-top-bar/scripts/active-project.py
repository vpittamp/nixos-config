#!/usr/bin/env python3
"""Stream the daemon-backed active i3pm context for the EWW top bar."""

import json
import os
import socket
import sys
import time
from pathlib import Path
from typing import Any, Dict


SOCKET_PATH = (
    Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    / "i3-project-daemon"
    / "ipc.sock"
)


def rpc_call(method: str, params: Dict[str, Any] | None = None) -> Dict[str, Any]:
    request = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
        "id": 1,
    }
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(1.0)
        sock.connect(str(SOCKET_PATH))
        sock.sendall((json.dumps(request) + "\n").encode("utf-8"))
        response = sock.makefile("r", encoding="utf-8").readline()
    payload = json.loads(response or "{}")
    if "error" in payload:
        raise RuntimeError(str(payload["error"]))
    result = payload.get("result")
    return result if isinstance(result, dict) else {}


def parse_project_fields(qualified_name: str) -> Dict[str, Any]:
    project = str(qualified_name or "").strip()
    if not project:
        return {
            "project": "Global",
            "active": False,
            "branch_number": None,
            "icon": "🌐",
            "is_worktree": False,
            "formatted_label": "Global",
            "repo_name": "",
            "branch": "",
        }

    repo_part, branch = (project.split(":", 1) + [""])[:2]
    repo_name = repo_part.split("/")[-1] if repo_part else project
    branch_number = None
    if branch:
        prefix = branch.split("-", 1)[0]
        if prefix.isdigit():
            branch_number = prefix
    if branch_number:
        formatted_label = f"{branch_number} - {repo_name}"
        icon = "🌿"
    else:
        formatted_label = repo_name or branch or project
        icon = "📦" if branch in {"", "main", "master"} else "🌿"
    return {
        "project": project,
        "active": True,
        "branch_number": branch_number,
        "icon": icon,
        "is_worktree": True,
        "formatted_label": formatted_label,
        "repo_name": repo_name,
        "branch": branch,
    }


def build_state(context: Dict[str, Any]) -> Dict[str, Any]:
    qualified_name = str(context.get("qualified_name") or "").strip()
    project_fields = parse_project_fields(qualified_name)
    execution_mode = str(context.get("execution_mode") or "global").strip() or "global"
    remote = context.get("remote") if isinstance(context.get("remote"), dict) else {}
    remote_enabled = execution_mode == "ssh"
    remote_host = str(remote.get("host") or "").strip()
    remote_user = str(remote.get("user") or "").strip()
    remote_port = remote.get("port", 22)
    remote_dir = str(remote.get("remote_dir") or remote.get("working_dir") or "").strip()

    if remote_enabled and remote_host:
        target_short = f"{remote_user}@{remote_host}" if remote_user else remote_host
        target = f"{target_short}:{remote_port}" if str(remote_port) not in {"", "22"} else target_short
    else:
        target = ""
        target_short = ""
        remote_dir = ""

    return {
        **project_fields,
        "remote_enabled": remote_enabled,
        "remote_target": target,
        "remote_target_short": target_short,
        "remote_directory": remote_dir,
        "remote_directory_display": remote_dir.replace(str(Path.home()), "~") if remote_dir else "",
        "execution_mode": execution_mode,
        "host_alias": str(context.get("host_alias") or ("global" if not qualified_name else "")),
        "connection_key": str(context.get("connection_key") or ("global" if not qualified_name else "")),
        "identity_key": str(context.get("identity_key") or ("global:global" if not qualified_name else "")),
        "context_key": str(context.get("context_key") or ""),
    }


def main() -> int:
    last_state: str | None = None
    while True:
        try:
            context = rpc_call("context.get_active")
            state = build_state(context)
        except Exception:
            state = build_state({})

        encoded = json.dumps(state, sort_keys=True)
        if encoded != last_state:
            try:
                print(json.dumps(state), flush=True)
            except BrokenPipeError:
                return 0
            last_state = encoded
        time.sleep(2)


if __name__ == "__main__":
    sys.exit(main())
