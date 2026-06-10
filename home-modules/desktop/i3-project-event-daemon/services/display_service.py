"""Display snapshot and mutation service for daemon IPC."""

from __future__ import annotations

import logging
from typing import Any, Awaitable, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


class DisplayService:
    """Own daemon-backed display snapshot, apply, cycle, toggle, and scale operations."""

    def __init__(
        self,
        *,
        notify_state_change: Callable[[str], Awaitable[None]],
        output_configure: Callable[[Dict[str, Any]], Awaitable[Dict[str, Any]]],
    ) -> None:
        self._notify_state_change = notify_state_change
        self._output_configure = output_configure

    @staticmethod
    async def _get_outputs(i3_connection: Any) -> List[Any]:
        if not i3_connection or not getattr(i3_connection, "conn", None):
            raise RuntimeError("Sway connection is unavailable")
        if hasattr(i3_connection, "get_outputs"):
            return list(await i3_connection.get_outputs())
        conn = getattr(i3_connection, "conn", None)
        if hasattr(conn, "get_outputs"):
            return list(await conn.get_outputs())
        raise RuntimeError("Sway output query is unavailable")

    @staticmethod
    def _profile_layout_options(monitor_profile_service: Any) -> Dict[str, Any]:
        profile_name = ""
        layouts: List[str] = []
        layout_options: List[Dict[str, Any]] = []
        if not monitor_profile_service:
            return {
                "profile_name": profile_name,
                "layouts": layouts,
                "layout_options": layout_options,
            }

        try:
            profile_name = str(monitor_profile_service.get_current_profile() or "")
            layouts = list(monitor_profile_service.list_profiles())
            for layout_name in layouts:
                profile = monitor_profile_service.get_profile(layout_name)
                output_names: List[str] = []
                output_count = 0
                description = ""
                default_layout = False
                outputs_detail: List[Dict[str, Any]] = []
                if profile is not None:
                    description = str(getattr(profile, "description", "") or "")
                    default_layout = bool(getattr(profile, "default", False))
                    output_names = list(profile.get_enabled_outputs())
                    output_count = len(output_names)
                    for po in getattr(profile, "outputs", []):
                        pos = getattr(po, "position", None)
                        outputs_detail.append({
                            "name": str(getattr(po, "name", "")),
                            "enabled": bool(getattr(po, "enabled", True)),
                            "scale": float(getattr(po, "scale", None) or 1.0),
                            "x": int(getattr(pos, "x", 0) if pos else 0),
                            "y": int(getattr(pos, "y", 0) if pos else 0),
                            "width": int(getattr(pos, "width", 0) if pos else 0),
                            "height": int(getattr(pos, "height", 0) if pos else 0),
                        })
                layout_options.append({
                    "name": layout_name,
                    "label": layout_name.replace("-", " ").title(),
                    "description": description,
                    "output_names": output_names,
                    "output_count": output_count,
                    "outputs": outputs_detail,
                    "default": default_layout,
                    "current": layout_name == profile_name,
                })
            layout_options.sort(
                key=lambda item: (
                    0 if bool(item.get("current", False)) else 1,
                    0 if bool(item.get("default", False)) else 1,
                    str(item.get("name") or "").casefold(),
                ),
            )
        except Exception:
            profile_name = ""
            layouts = []
            layout_options = []
        return {
            "profile_name": profile_name,
            "layouts": layouts,
            "layout_options": layout_options,
        }

    async def snapshot(
        self,
        *,
        i3_connection: Any,
        monitor_profile_service: Any,
        display_generation: int,
        snapshot_version: int,
    ) -> Dict[str, Any]:
        """Return current output/layout state for QuickShell and CLI consumers."""
        outputs = await self._get_outputs(i3_connection)
        output_states = None
        try:
            from ..output_state_manager import load_output_states
            output_states = load_output_states()
        except Exception:
            output_states = None

        layout = self._profile_layout_options(monitor_profile_service)

        active_outputs: List[Dict[str, Any]] = []
        for output in outputs:
            if str(getattr(output, "name", "")).startswith("__"):
                continue
            name = str(getattr(output, "name", "") or "")
            active = bool(getattr(output, "active", False))
            focused = bool(getattr(output, "focused", False))
            enabled = active
            if output_states is not None:
                try:
                    enabled = bool(output_states.is_output_enabled(name))
                except Exception:
                    enabled = active
            active_outputs.append({
                "name": name,
                "active": active,
                "enabled": enabled,
                "focused": focused,
                "primary": focused,
                "scale": float(getattr(output, "scale", 1.0) or 1.0),
                "rect": {
                    "x": int(getattr(getattr(output, "rect", None), "x", 0) or 0),
                    "y": int(getattr(getattr(output, "rect", None), "y", 0) or 0),
                    "width": int(getattr(getattr(output, "rect", None), "width", 0) or 0),
                    "height": int(getattr(getattr(output, "rect", None), "height", 0) or 0),
                },
            })

        return {
            "current_layout": layout["profile_name"],
            "layouts": layout["layouts"],
            "layout_options": layout["layout_options"],
            "outputs": active_outputs,
            "display_generation": int(display_generation or 0),
            "snapshot_version": int(snapshot_version or 0),
        }

    async def apply(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any,
        monitor_profile_service: Any,
        display_generation: int,
        snapshot_version: int,
    ) -> Dict[str, Any]:
        """Apply a named display layout/profile through the daemon."""
        layout = str(params.get("layout") or params.get("profile") or "").strip()
        if not layout:
            raise ValueError("layout is required")
        if not monitor_profile_service:
            raise RuntimeError("Monitor profile service is unavailable")
        if not i3_connection or not getattr(i3_connection, "conn", None):
            raise RuntimeError("Sway connection is unavailable")

        applied = await monitor_profile_service.handle_profile_change(
            i3_connection.conn,
            layout,
        )
        if not applied:
            raise RuntimeError(f"Failed to apply display layout: {layout}")

        try:
            from ..monitor_profile_service import CURRENT_PROFILE_FILE
            CURRENT_PROFILE_FILE.parent.mkdir(parents=True, exist_ok=True)
            CURRENT_PROFILE_FILE.write_text(layout + "\n", encoding="utf-8")
        except Exception as exc:
            logger.warning("display.apply persisted layout state incompletely: %s", exc)

        await self._notify_state_change("display_layout_changed")
        result = await self.snapshot(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
        result["applied"] = True
        return result

    async def cycle(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any,
        monitor_profile_service: Any,
        display_generation: int,
        snapshot_version: int,
    ) -> Dict[str, Any]:
        """Cycle to the next available display layout/profile."""
        del params
        if not monitor_profile_service:
            raise RuntimeError("Monitor profile service is unavailable")

        layouts = list(monitor_profile_service.list_profiles())
        if not layouts:
            raise RuntimeError("No display layouts are configured")

        current = str(monitor_profile_service.get_current_profile() or "")
        if current in layouts:
            next_index = (layouts.index(current) + 1) % len(layouts)
        else:
            next_index = 0
        return await self.apply(
            {"layout": layouts[next_index]},
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )

    async def toggle_output(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any,
        monitor_profile_service: Any,
        display_generation: int,
        snapshot_version: int,
    ) -> Dict[str, Any]:
        """Toggle an individual output on or off."""
        output_name = str(params.get("output") or "").strip()
        if not output_name:
            raise ValueError("output is required")

        from ..output_state_manager import load_output_states, toggle_output_state, get_enabled_outputs

        enabled_outputs = get_enabled_outputs()
        current_states = load_output_states()
        is_currently_enabled = current_states.is_output_enabled(output_name)

        if is_currently_enabled and len(enabled_outputs) <= 1:
            raise RuntimeError(f"Cannot disable {output_name}: it is the only enabled output")

        new_state = toggle_output_state(output_name)

        result = await self.snapshot(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
        result["toggled_output"] = output_name
        result["toggled_enabled"] = new_state
        return result

    async def set_scale(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any,
        monitor_profile_service: Any,
        display_generation: int,
        snapshot_version: int,
    ) -> Dict[str, Any]:
        """Set the scale factor for an individual output."""
        output_name = str(params.get("output") or "").strip()
        if not output_name:
            raise ValueError("output is required")
        scale = params.get("scale")
        if scale is None:
            raise ValueError("scale is required")
        scale = float(scale)
        if scale <= 0:
            raise ValueError("scale must be positive")

        result = await self._output_configure({"output_name": output_name, "scale": scale})
        if not result.get("success"):
            raise RuntimeError(f"Failed to set scale for {output_name}: {result.get('error', 'unknown')}")

        snapshot = await self.snapshot(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
        snapshot["scaled_output"] = output_name
        snapshot["scaled_value"] = scale
        return snapshot
