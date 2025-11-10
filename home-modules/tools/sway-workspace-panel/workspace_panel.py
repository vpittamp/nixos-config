#!/usr/bin/env python3
"""Generate workspace metadata (including SVG icon paths) for the Eww bar."""
from __future__ import annotations

import argparse
import json
import signal
import sys
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

import i3ipc
from xdg.DesktopEntry import DesktopEntry
from xdg.IconTheme import getIconPath

ICON_SEARCH_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]
DESKTOP_DIRS = [
    Path.home() / ".local/share/applications",
    Path("/usr/share/applications"),
]
ICON_EXTENSIONS = (".svg", ".png", ".xpm")


class DesktopIconIndex:
    """Index .desktop entries so we can map windows to themed icons."""

    def __init__(self) -> None:
        self._by_desktop_id: Dict[str, Dict[str, str]] = {}
        self._by_startup_wm: Dict[str, Dict[str, str]] = {}
        self._icon_cache: Dict[str, str] = {}
        self._load()

    def _load(self) -> None:
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
        for key in keys:
            if key in self._by_desktop_id:
                return self._by_desktop_id[key]
        for key in keys:
            if key in self._by_startup_wm:
                return self._by_startup_wm[key]
        return {}


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
        icon_info = icon_index.lookup(app_id=app_id, window_class=window_class, window_instance=window_instance)
        app_name = icon_info.get("name", "") if icon_info else (leaf.name if leaf else "")
        icon_path = icon_info.get("icon", "") if icon_info else ""
        fallback_symbol_source = app_name or (leaf.name if leaf else "") or reply.name
        fallback_symbol = (fallback_symbol_source or "·").strip()[:1].upper() or "·"

        workspace_id = workspace_nodes.get(reply.name).id if reply.name in workspace_nodes else None

        workspace_data = {
            "id": workspace_id,
            "name": reply.name,
            "num": reply.num,
            "numberLabel": str(reply.num) if reply.num >= 0 else reply.name,
            "output": output,
            "focused": reply.focused,
            "visible": reply.visible,
            "urgent": reply.urgent,
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
                    ("empty", format_value(row["isEmpty"])),
                ]
                attr_string = " ".join(
                    f":{key} {value}"
                    for key, value in attrs
                )
                parts.append(f"(workspace-button {attr_string})")

            serialized = "".join(parts)
        if serialized != last_payload:
            print(serialized, flush=True)
            last_payload = serialized

    conn.on("workspace", lambda *_: emit())
    conn.on("window", lambda *_: emit())
    conn.on("binding", lambda *_: emit())

    signal.signal(signal.SIGINT, lambda *_args: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_args: sys.exit(0))

    emit()
    conn.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
