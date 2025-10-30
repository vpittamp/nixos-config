"""Appearance manager for Sway.

Generates configuration for gaps and border settings.
"""

import logging
from typing import List

from i3ipc.aio import Connection

from ..models import AppearanceConfig, BorderStyle

logger = logging.getLogger(__name__)


class AppearanceManager:
    """Handles appearance settings (gaps, borders)."""

    def __init__(self, sway_connection: Connection = None):
        self.sway = sway_connection

    def generate_config(self, appearance: AppearanceConfig) -> str:
        """Generate Sway config snippet for appearance settings."""
        lines: List[str] = [
            "# Appearance settings (managed by sway-config-manager)",
            "",
            f"gaps inner {appearance.gaps.inner}",
            f"gaps outer {appearance.gaps.outer}",
            f"smart_gaps {'on' if appearance.gaps.smart_gaps else 'off'}",
            self._border_command("default_border", appearance.borders.default),
            self._border_command("default_floating_border", appearance.borders.floating),
            f"hide_edge_borders {appearance.borders.hide_edge_borders.value}",
        ]

        if appearance.smart_borders is not None:
            lines.append(f"smart_borders {appearance.smart_borders.value}")

        return "\n".join(lines) + "\n"

    async def apply_via_ipc(self, appearance: AppearanceConfig) -> bool:
        """Apply appearance commands directly via Sway IPC."""
        try:
            if self.sway is None:
                self.sway = await Connection(auto_reconnect=True).connect()

            commands = self.generate_config(appearance).strip().split("\n")
            for command in commands:
                if not command or command.startswith("#"):
                    continue
                result = await self.sway.command(command)
                if result[0].error:
                    logger.error("Failed to execute command '%s': %s", command, result[0].error)
                    return False
            return True

        except Exception as exc:  # pragma: no cover - IPC errors handled at runtime
            logger.error("Failed to apply appearance settings via IPC: %s", exc)
            return False

    @staticmethod
    def _border_command(command_name: str, border_config) -> str:
        """Render border command based on style and size."""
        if border_config.style == BorderStyle.PIXEL:
            return f"{command_name} pixel {border_config.size}"
        return f"{command_name} {border_config.style.value}"
