#!/usr/bin/env python3
"""Generate workspace metadata (including SVG icon paths) for the Eww bar."""
from __future__ import annotations

import argparse
import json
import signal
import socket
import sys
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional

import i3ipc
from xdg.DesktopEntry import DesktopEntry
from xdg.IconTheme import getIconPath

# Feature 058: Import workspace mode models for event handling
try:
    from models import WorkspaceModeEvent, PendingWorkspaceState
except ImportError:
    # Fallback if models not available (shouldn't happen in production)
    WorkspaceModeEvent = None
    PendingWorkspaceState = None

ICON_SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]
DESKTOP_DIRS = [
    Path.home() / ".local/share/i3pm-applications/applications",  # Our app registry desktop files (primary)
    Path.home() / ".local/share/applications",  # PWA desktop files
    Path("/usr/share/applications"),  # System desktop files
]
ICON_EXTENSIONS = (".svg", ".png", ".xpm")
APP_REGISTRY_PATH = Path.home() / ".config/i3/application-registry.json"
PWA_REGISTRY_PATH = Path.home() / ".config/i3/pwa-registry.json"

# Feature 058: Global pending workspace state (thread-safe)
_pending_workspace_lock = threading.Lock()
_pending_workspace_state: Optional[Dict[str, Any]] = None
# Socket path matches systemd socket unit configuration
_daemon_ipc_socket = Path("/run/i3-project-daemon/ipc.sock")


class DesktopIconIndex:
    """Index .desktop entries and app registry so we can map windows to themed icons."""

    def __init__(self) -> None:
        self._by_desktop_id: Dict[str, Dict[str, str]] = {}
        self._by_startup_wm: Dict[str, Dict[str, str]] = {}
        self._by_app_id: Dict[str, Dict[str, str]] = {}
        self._icon_cache: Dict[str, str] = {}
        self._load_app_registry()
        self._load_pwa_registry()
        self._load_desktop_entries()

    def _load_app_registry(self) -> None:
        """Load icons from application-registry.json (primary source)."""
        if not APP_REGISTRY_PATH.exists():
            return
        try:
            with open(APP_REGISTRY_PATH) as f:
                data = json.load(f)
                for app in data.get("applications", []):
                    icon_path = self._resolve_icon(app.get("icon", ""))
                    payload = {
                        "icon": icon_path or "",
                        "name": app.get("display_name", app.get("name", "")),
                    }
                    # Index by name only (NOT expected_class - multiple apps share same class)
                    app_name = app.get("name", "").lower()
                    if app_name:
                        self._by_app_id[app_name] = payload
        except Exception:
            pass

    def _load_pwa_registry(self) -> None:
        """Load icons from pwa-registry.json (for PWAs)."""
        if not PWA_REGISTRY_PATH.exists():
            return
        try:
            with open(PWA_REGISTRY_PATH) as f:
                data = json.load(f)
                for pwa in data.get("pwas", []):
                    icon_path = self._resolve_icon(pwa.get("icon", ""))
                    payload = {
                        "icon": icon_path or "",
                        "name": pwa.get("name", ""),
                    }
                    # Index by ULID-based app_id (e.g., "FFPWA-01JCYF8Z2M")
                    pwa_id = f"ffpwa-{pwa.get('ulid', '')}".lower()
                    if pwa_id:
                        self._by_app_id[pwa_id] = payload
        except Exception:
            pass

    def _load_desktop_entries(self) -> None:
        """Load icons from .desktop files (fallback)."""
        for directory in DESKTOP_DIRS:
            if not directory.exists():
                continue
            for entry_path in directory.glob("*.desktop"):
                try:
                    entry = DesktopEntry(entry_path)
                except Exception:
                    continue
                icon_path = self._resolve_icon(entry.getIcon())
                display_name = entry.getName() or entry_path.stem
                payload = {
                    "icon": icon_path or "",
                    "name": display_name,
                }
                desktop_id = entry_path.stem.lower()
                self._by_desktop_id[desktop_id] = payload
                startup = entry.getStartupWMClass()
                if startup:
                    self._by_startup_wm[startup.lower()] = payload

    def _resolve_icon(self, icon_name: Optional[str]) -> Optional[str]:
        if not icon_name:
            return None
        cache_key = icon_name.lower()
        if cache_key in self._icon_cache:
            cached = self._icon_cache[cache_key]
            return cached or None

        candidate = Path(icon_name)
        if candidate.is_absolute() and candidate.exists():
            resolved = str(candidate)
            self._icon_cache[cache_key] = resolved
            return resolved

        themed = getIconPath(icon_name, 48)
        if themed:
            resolved = str(Path(themed))
            self._icon_cache[cache_key] = resolved
            return resolved

        for directory in ICON_SEARCH_DIRS:
            if not directory.exists():
                continue
            for ext in ICON_EXTENSIONS:
                probe = directory / f"{icon_name}{ext}"
                if probe.exists():
                    resolved = str(probe)
                    self._icon_cache[cache_key] = resolved
                    return resolved

        self._icon_cache[cache_key] = ""
        return None

    def lookup(self, *, app_id: Optional[str], window_class: Optional[str], window_instance: Optional[str]) -> Dict[str, str]:
        keys = [value.lower() for value in [app_id, window_class, window_instance] if value]
        # First priority: app registry (same icons as walker/launcher)
        for key in keys:
            if key in self._by_app_id:
                return self._by_app_id[key]
        # Second priority: desktop file by ID
        for key in keys:
            if key in self._by_desktop_id:
                return self._by_desktop_id[key]
        # Third priority: desktop file by StartupWMClass
        for key in keys:
            if key in self._by_startup_wm:
                return self._by_startup_wm[key]
        return {}


def read_i3pm_app_name(pid: Optional[int]) -> Optional[str]:
    """Read I3PM_APP_NAME from process environment (Feature 057 window matching)."""
    if pid is None or pid <= 0:
        return None
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            environ_bytes = f.read()
            environ_vars = environ_bytes.split(b'\0')
            for var in environ_vars:
                if var.startswith(b'I3PM_APP_NAME='):
                    app_name = var.split(b'=', 1)[1].decode('utf-8', errors='ignore')
                    return app_name.strip() if app_name else None
    except (FileNotFoundError, PermissionError, OSError):
        pass
    return None


def pick_leaf(workspace_node: Optional[i3ipc.con.Con]) -> Optional[i3ipc.con.Con]:
    if workspace_node is None:
        return None
    leaves = [leaf for leaf in workspace_node.leaves() if leaf.type == "con"]
    if not leaves:
        return None
    focused = [leaf for leaf in leaves if leaf.focused]
    if focused:
        return focused[0]
    return sorted(leaves, key=lambda leaf: (leaf.rect.y, leaf.rect.x))[0]


def build_workspace_payload(
    conn: i3ipc.Connection,
    icon_index: DesktopIconIndex,
    managed_outputs: Optional[List[str]] = None,
) -> Dict[str, Any]:
    tree = conn.get_tree()
    workspace_nodes = {ws.name: ws for ws in tree.workspaces()}

    outputs_payload: Dict[str, List[Dict[str, Any]]] = {}
    if managed_outputs:
        for output in managed_outputs:
            outputs_payload[output] = []

    for reply in conn.get_workspaces():
        output = reply.output or "__UNKNOWN__"
        outputs_payload.setdefault(output, [])
        node = workspace_nodes.get(reply.name)
        leaf = pick_leaf(node)
        app_id = leaf.app_id if leaf else None
        window_class = leaf.window_class if leaf else None
        window_instance = getattr(leaf, "window_instance", None) if leaf else None

        # Feature 057: Read I3PM_APP_NAME from process environment for accurate window matching
        # This handles terminal apps (lazygit, yazi, btop launched via ghostty) and all other apps
        i3pm_app_name = None
        if leaf and hasattr(leaf, 'pid') and leaf.pid:
            i3pm_app_name = read_i3pm_app_name(leaf.pid)
            if i3pm_app_name:
                import sys
                print(f"DEBUG: WS {reply.num} PID {leaf.pid} -> I3PM_APP_NAME={i3pm_app_name}", file=sys.stderr, flush=True)

        # Priority: I3PM_APP_NAME > app_id > window_class > window_instance
        # I3PM_APP_NAME provides accurate app identification for all launcher-launched apps
        if i3pm_app_name:
            icon_info = icon_index.lookup(app_id=i3pm_app_name, window_class=None, window_instance=None)
            if icon_info:
                print(f"DEBUG: I3PM match - {i3pm_app_name} -> icon={icon_info.get('icon')}", file=sys.stderr, flush=True)
        else:
            icon_info = icon_index.lookup(app_id=app_id, window_class=window_class, window_instance=window_instance)
            if icon_info:
                print(f"DEBUG: Fallback match - app_id={app_id} -> icon={icon_info.get('icon')}", file=sys.stderr, flush=True)
        app_name = icon_info.get("name", "") if icon_info else (leaf.name if leaf else "")
        icon_path = icon_info.get("icon", "") if icon_info else ""
        fallback_symbol_source = app_name or (leaf.name if leaf else "") or reply.name
        fallback_symbol = (fallback_symbol_source or "·").strip()[:1].upper() or "·"

        workspace_id = workspace_nodes.get(reply.name).id if reply.name in workspace_nodes else None

        # Feature 058: Check if this workspace is pending navigation target
        is_pending = False
        with _pending_workspace_lock:
            if _pending_workspace_state:
                pending_num = _pending_workspace_state.get("workspace_number")
                pending_output = _pending_workspace_state.get("target_output")
                ws_num_match = pending_num == reply.num
                output_match = pending_output == output
                is_pending = ws_num_match and output_match
                # Debug: Always log when checking workspace 5
                if reply.num == 5:
                    print(f"DEBUG BUILD WS5: pending_num={pending_num}, reply.num={reply.num}, match={ws_num_match}", file=sys.stderr, flush=True)
                    print(f"DEBUG BUILD WS5: pending_output={pending_output}, output={output}, match={output_match}", file=sys.stderr, flush=True)
                    print(f"DEBUG BUILD WS5: is_pending={is_pending}", file=sys.stderr, flush=True)
                if is_pending:
                    print(f"DEBUG BUILD: WS {reply.num} IS PENDING (output={output})", file=sys.stderr, flush=True)

        workspace_data = {
            "id": workspace_id,
            "name": reply.name,
            "num": reply.num,
            "numberLabel": str(reply.num) if reply.num >= 0 else reply.name,
            "output": output,
            "focused": reply.focused,
            "visible": reply.visible,
            "urgent": reply.urgent,
            "pending": is_pending,  # Feature 058: Pending highlight state
            "appName": app_name,
            "appId": app_id or window_class or "",
            "iconPath": icon_path,
            "iconFallback": fallback_symbol,
            "isEmpty": leaf is None,
        }
        outputs_payload[output].append(workspace_data)

    for workspaces in outputs_payload.values():
        workspaces.sort(key=lambda ws: ((ws["num"] if ws["num"] >= 0 else 999), ws["name"]))

    return {
        "workspaces": outputs_payload,
        "generatedAt": time.time(),
    }


def subscribe_to_workspace_mode_events(emit_callback: Callable[[], None], managed_output: Optional[str] = None) -> None:
    """Subscribe to workspace mode events from i3pm daemon (Feature 058: T010-T011).

    Runs in background thread, updates global pending workspace state.

    Args:
        emit_callback: Function to call when pending state changes (triggers UI update)
        managed_output: Output name to filter events (only update if pending workspace targets this output)
    """
    global _pending_workspace_state

    if not _daemon_ipc_socket.exists():
        print(f"Warning: Daemon IPC socket not found at {_daemon_ipc_socket}, workspace mode events disabled", file=sys.stderr)
        return

    try:
        # Connect to daemon IPC socket
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(str(_daemon_ipc_socket))
        sock_file = sock.makefile('rw')

        # Subscribe to workspace_mode events
        subscribe_request = {
            "jsonrpc": "2.0",
            "method": "subscribe",
            "params": {"event_types": ["workspace_mode"]},
            "id": 1
        }
        sock_file.write(json.dumps(subscribe_request) + "\n")
        sock_file.flush()

        # Read subscription response
        response_line = sock_file.readline()
        if response_line:
            response = json.loads(response_line)
            if response.get("result") != "subscribed":
                print(f"Warning: Failed to subscribe to workspace_mode events: {response}", file=sys.stderr)
                return

        # Event loop: read incoming workspace_mode events
        while True:
            line = sock_file.readline()
            if not line:
                break

            try:
                event = json.loads(line)

                # Check if this is a workspace_mode event
                if event.get("method") == "event" and event.get("params", {}).get("type") == "workspace_mode":
                    # Event structure: event["params"]["payload"] contains event_type and pending_workspace
                    event_payload = event["params"].get("payload", {})
                    event_type = event_payload.get("event_type")
                    pending_workspace = event_payload.get("pending_workspace")

                    print(f"DEBUG: Received workspace_mode event: type={event_type}, pending_ws={pending_workspace}, output={managed_output}", file=sys.stderr, flush=True)

                    # Update global pending workspace state (thread-safe)
                    with _pending_workspace_lock:
                        if pending_workspace:
                            # Filter by output if specified
                            if managed_output and pending_workspace.get("target_output") != managed_output:
                                # Pending workspace is for different output, clear our state
                                print(f"DEBUG: Clearing pending (different output): target={pending_workspace.get('target_output')}, managed={managed_output}", file=sys.stderr, flush=True)
                                _pending_workspace_state = None
                            else:
                                # Update pending workspace state
                                print(f"DEBUG: Setting pending workspace: {pending_workspace}", file=sys.stderr, flush=True)
                                _pending_workspace_state = pending_workspace
                        else:
                            # Clear pending state (cancel, enter, or invalid workspace)
                            print(f"DEBUG: Clearing pending (event type: {event_type})", file=sys.stderr, flush=True)
                            _pending_workspace_state = None

                    # Trigger UI update
                    emit_callback()

            except (json.JSONDecodeError, KeyError) as e:
                print(f"Warning: Failed to parse workspace_mode event: {e}", file=sys.stderr)
                continue

    except (ConnectionRefusedError, FileNotFoundError) as e:
        print(f"Warning: Could not connect to daemon IPC socket: {e}, workspace mode events disabled", file=sys.stderr)
    except Exception as e:
        print(f"Error in workspace_mode event subscription: {e}", file=sys.stderr)
    finally:
        try:
            sock.close()
        except:
            pass


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Emit workspace state for the Eww status bar")
    parser.add_argument(
        "--outputs",
        nargs="*",
        default=None,
        help="Explicit list of outputs to include in JSON payload (default: discover from Sway)",
    )
    parser.add_argument(
        "--output",
        dest="single_output",
        help="Render a single output (used with --format=yuck)",
    )
    parser.add_argument(
        "--format",
        choices=["json", "yuck"],
        default="json",
        help="Output format (json emits structured data, yuck streams widget snippets)",
    )
    args = parser.parse_args(argv)

    if args.single_output and args.outputs:
        parser.error("--output and --outputs cannot be combined")

    if args.format == "yuck" and not args.single_output:
        parser.error("--format=yuck requires --output")

    icon_index = DesktopIconIndex()
    conn = i3ipc.Connection()

    managed_outputs: Optional[List[str]]
    if args.single_output is not None:
        managed_outputs = [args.single_output]
    else:
        managed_outputs = args.outputs

    last_payload = ""

    def emit(_: Any = None) -> None:
        nonlocal last_payload
        payload = build_workspace_payload(conn, icon_index, managed_outputs=managed_outputs)
        if args.format == "json":
            serialized = json.dumps(payload, separators=(",", ":"))
        else:
            output_key = args.single_output  # validated earlier
            rows = payload["workspaces"].get(output_key, [])

            def format_value(value: Any) -> str:
                if isinstance(value, bool):
                    return "true" if value else "false"
                return json.dumps(value, separators=(",", ":"))

            parts = []
            for row in rows:
                attrs = [
                    ("number_label", format_value(row["numberLabel"])),
                    ("workspace_name", format_value(row["name"])),
                    ("app_name", format_value(row["appName"])),
                    ("icon_path", format_value(row["iconPath"])),
                    ("icon_fallback", format_value(row["iconFallback"])),
                    ("workspace_id", format_value(row["id"] or 0)),
                    ("focused", format_value(row["focused"])),
                    ("visible", format_value(row["visible"])),
                    ("urgent", format_value(row["urgent"])),
                    ("pending", format_value(row["pending"])),  # Feature 058: Pending highlight
                    ("empty", format_value(row["isEmpty"])),
                ]
                attr_string = " ".join(
                    f":{key} {value}"
                    for key, value in attrs
                )
                parts.append(f"(workspace-button {attr_string})")

            # Wrap in a box container so eww's (literal :content) gets a single element
            serialized = f"(box :orientation \"h\" :spacing 3 {''.join(parts)})"
        if serialized != last_payload:
            print(serialized, flush=True)
            last_payload = serialized

    conn.on("workspace", lambda *_: emit())
    conn.on("window", lambda *_: emit())
    conn.on("binding", lambda *_: emit())

    # Feature 058: Start workspace mode event subscription thread
    ipc_thread = threading.Thread(
        target=subscribe_to_workspace_mode_events,
        args=(emit, args.single_output),
        daemon=True,  # Daemon thread will exit when main thread exits
        name="workspace-mode-ipc"
    )
    ipc_thread.start()

    signal.signal(signal.SIGINT, lambda *_args: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_args: sys.exit(0))

    emit()
    conn.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
