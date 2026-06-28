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
        run_sway_command: Optional[Callable[[str], Awaitable[Any]]] = None,
        sway_command_succeeded: Optional[Callable[[Any], bool]] = None,
        send_tick_barrier: Optional[Callable[[str], Awaitable[None]]] = None,
        i3_connection: Optional[Callable[[], Any]] = None,
        monitor_profile_service: Optional[Callable[[], Any]] = None,
        display_generation: Optional[Callable[[], int]] = None,
        snapshot_version: Optional[Callable[[], int]] = None,
    ) -> None:
        self._notify_state_change = notify_state_change
        self._run_sway_command = run_sway_command
        self._sway_command_succeeded = sway_command_succeeded
        self._send_tick_barrier = send_tick_barrier
        self._i3_connection = i3_connection
        self._monitor_profile_service = monitor_profile_service
        self._display_generation = display_generation
        self._snapshot_version = snapshot_version

    def _sway_ready(self) -> bool:
        return bool(self._run_sway_command and self._sway_command_succeeded)

    def _context(
        self,
        *,
        i3_connection: Any = None,
        monitor_profile_service: Any = None,
        display_generation: Optional[int] = None,
        snapshot_version: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Return display operation context, preferring explicit test overrides."""
        resolved_i3_connection = i3_connection
        if resolved_i3_connection is None and self._i3_connection is not None:
            resolved_i3_connection = self._i3_connection()

        resolved_monitor_profile_service = monitor_profile_service
        if resolved_monitor_profile_service is None and self._monitor_profile_service is not None:
            resolved_monitor_profile_service = self._monitor_profile_service()

        resolved_display_generation = display_generation
        if resolved_display_generation is None and self._display_generation is not None:
            resolved_display_generation = self._display_generation()

        resolved_snapshot_version = snapshot_version
        if resolved_snapshot_version is None and self._snapshot_version is not None:
            resolved_snapshot_version = self._snapshot_version()

        return {
            "i3_connection": resolved_i3_connection,
            "monitor_profile_service": resolved_monitor_profile_service,
            "display_generation": int(resolved_display_generation or 0),
            "snapshot_version": int(resolved_snapshot_version or 0),
        }

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
        i3_connection: Any = None,
        monitor_profile_service: Any = None,
        display_generation: Optional[int] = None,
        snapshot_version: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Return current output/layout state for QuickShell and CLI consumers."""
        context = self._context(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
        outputs = await self._get_outputs(context["i3_connection"])
        output_states = None
        try:
            from ..output_state_manager import load_output_states
            output_states = load_output_states()
        except Exception:
            output_states = None

        layout = self._profile_layout_options(context["monitor_profile_service"])

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
                # EDID identity so the UI can show friendly names (Verbatim,
                # Samsung, ThinkPad) and resolve role-based presets instead of
                # exposing unstable DP-x connector names.
                "make": str(getattr(output, "make", "") or ""),
                "model": str(getattr(output, "model", "") or ""),
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
            "display_generation": int(context["display_generation"] or 0),
            "snapshot_version": int(context["snapshot_version"] or 0),
        }

    async def apply(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any = None,
        monitor_profile_service: Any = None,
        display_generation: Optional[int] = None,
        snapshot_version: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Apply a named display layout/profile through the daemon."""
        context = self._context(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
        i3_connection = context["i3_connection"]
        monitor_profile_service = context["monitor_profile_service"]
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
            display_generation=context["display_generation"],
            snapshot_version=context["snapshot_version"],
        )
        result["applied"] = True
        return result

    async def cycle(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any = None,
        monitor_profile_service: Any = None,
        display_generation: Optional[int] = None,
        snapshot_version: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Cycle to the next available display layout/profile."""
        del params
        context = self._context(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
        i3_connection = context["i3_connection"]
        monitor_profile_service = context["monitor_profile_service"]
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
            display_generation=context["display_generation"],
            snapshot_version=context["snapshot_version"],
        )

    async def toggle_output(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any = None,
        monitor_profile_service: Any = None,
        display_generation: Optional[int] = None,
        snapshot_version: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Toggle an individual output on or off."""
        context = self._context(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
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
            i3_connection=context["i3_connection"],
            monitor_profile_service=context["monitor_profile_service"],
            display_generation=context["display_generation"],
            snapshot_version=context["snapshot_version"],
        )
        result["toggled_output"] = output_name
        result["toggled_enabled"] = new_state
        return result

    async def set_scale(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any = None,
        monitor_profile_service: Any = None,
        display_generation: Optional[int] = None,
        snapshot_version: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Set the scale factor for an individual output."""
        context = self._context(
            i3_connection=i3_connection,
            monitor_profile_service=monitor_profile_service,
            display_generation=display_generation,
            snapshot_version=snapshot_version,
        )
        output_name = str(params.get("output") or "").strip()
        if not output_name:
            raise ValueError("output is required")
        scale = params.get("scale")
        if scale is None:
            raise ValueError("scale is required")
        scale = float(scale)
        if scale <= 0:
            raise ValueError("scale must be positive")

        result = await self.configure_output({"output_name": output_name, "scale": scale})
        if not result.get("success"):
            raise RuntimeError(f"Failed to set scale for {output_name}: {result.get('error', 'unknown')}")

        snapshot = await self.snapshot(
            i3_connection=context["i3_connection"],
            monitor_profile_service=context["monitor_profile_service"],
            display_generation=context["display_generation"],
            snapshot_version=context["snapshot_version"],
        )
        snapshot["scaled_output"] = output_name
        snapshot["scaled_value"] = scale
        return snapshot

    async def outputs_state(
        self,
        params: Dict[str, Any],
        *,
        i3_connection: Any = None,
    ) -> Dict[str, Any]:
        """Return cached output state with focused-output enrichment when available."""
        from .output_event_service import get_output_event_service

        output_service = get_output_event_service()
        if not output_service:
            return {
                "initialized": False,
                "outputs": {},
                "count": 0,
                "active_count": 0,
            }

        output_name = params.get("output_name")
        cached_outputs = output_service.get_current_state()
        if output_name:
            if output_name in cached_outputs:
                state = cached_outputs[output_name]
                return {
                    "initialized": True,
                    "output_name": output_name,
                    "state": state.to_dict(),
                    "active": state.active,
                }
            return {
                "initialized": True,
                "output_name": output_name,
                "state": None,
                "error": f"Output '{output_name}' not found in cache",
            }

        outputs_dict = {
            name: state.to_dict()
            for name, state in cached_outputs.items()
        }
        active_outputs = output_service.get_active_outputs()
        focused_output = None
        context = self._context(i3_connection=i3_connection)
        try:
            outputs = await self._get_outputs(context["i3_connection"])
            for output in outputs:
                if getattr(output, "focused", False):
                    focused_output = getattr(output, "name", None)
                    break
        except Exception as exc:
            logger.debug("Failed to resolve focused output: %s", exc)

        return {
            "initialized": True,
            "outputs": outputs_dict,
            "count": len(cached_outputs),
            "active_count": len(active_outputs),
            "active_outputs": active_outputs,
            "focused_output": focused_output,
        }

    async def configure_output(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Apply a deterministic output configuration command through the daemon."""
        if not self._sway_ready():
            raise RuntimeError("Sway connection is unavailable")

        output_name = str(params.get("output_name") or "").strip()
        if not output_name:
            raise ValueError("output_name is required")

        enabled = params.get("enabled")
        mode = str(params.get("mode") or "").strip()
        scale = params.get("scale")
        position_x = params.get("position_x")
        position_y = params.get("position_y")

        command_parts = [f"output {output_name}"]
        if enabled is not None:
            command_parts.append("enable" if bool(enabled) else "disable")
        if mode:
            command_parts.append(f"mode {mode}")
        if position_x is not None and position_y is not None:
            command_parts.append(f"position {int(position_x)},{int(position_y)}")
        if scale is not None:
            command_parts.append(f"scale {float(scale)}")

        if len(command_parts) == 1:
            raise ValueError("No output configuration fields were provided")

        command = " ".join(command_parts)
        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        result = await self._run_sway_command(command)
        if not self._sway_command_succeeded(result):
            return {"success": False, "output_name": output_name, "error": f"command_failed:{command}"}
        if self._send_tick_barrier:
            await self._send_tick_barrier(f"i3pm:output-configure:{output_name}")
        return {"success": True, "output_name": output_name, "command": command}

    async def create_virtual_output(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Create a virtual output through the daemon-owned Sway connection."""
        del params
        if not self._sway_ready():
            raise RuntimeError("Sway connection is unavailable")
        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        result = await self._run_sway_command("create_output")
        if not self._sway_command_succeeded(result):
            return {"success": False, "error": "command_failed:create_output"}
        if self._send_tick_barrier:
            await self._send_tick_barrier("i3pm:output-create")
        return {"success": True}

    async def move_workspace_to_output(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Move a workspace to a target output through the daemon."""
        if not self._sway_ready():
            raise RuntimeError("Sway connection is unavailable")

        workspace = params.get("workspace")
        output_name = str(params.get("output_name") or "").strip()
        if workspace is None:
            raise ValueError("workspace is required")
        if not output_name:
            raise ValueError("output_name is required")

        workspace_ref = str(workspace).strip()
        if not workspace_ref:
            raise ValueError("workspace must not be empty")

        assert self._run_sway_command is not None
        assert self._sway_command_succeeded is not None
        focus_command = f"workspace {workspace_ref}"
        result = await self._run_sway_command(focus_command)
        if not self._sway_command_succeeded(result):
            return {
                "success": False,
                "workspace": workspace_ref,
                "output_name": output_name,
                "error": f"command_failed:{focus_command}",
            }

        move_command = f"move workspace to output {output_name}"
        result = await self._run_sway_command(move_command)
        if not self._sway_command_succeeded(result):
            return {
                "success": False,
                "workspace": workspace_ref,
                "output_name": output_name,
                "error": f"command_failed:{move_command}",
            }
        if self._send_tick_barrier:
            await self._send_tick_barrier(f"i3pm:workspace-output:{workspace_ref}:{output_name}")
        return {"success": True, "workspace": workspace_ref, "output_name": output_name}
