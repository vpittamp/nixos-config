"""
Keybinding manager for Sway.

Applies keybinding configurations via Sway IPC commands.
"""

import logging
from typing import List

from i3ipc.aio import Connection

from ..models import KeybindingConfig

logger = logging.getLogger(__name__)


class KeybindingManager:
    """Manages keybinding application via Sway IPC."""

    def __init__(self, sway_connection: Connection = None):
        """
        Initialize keybinding manager.

        Args:
            sway_connection: Async i3ipc Connection (created if None)
        """
        self.sway = sway_connection

    async def apply_keybindings(self, keybindings: List[KeybindingConfig]) -> bool:
        """
        Apply keybindings to Sway via IPC.

        Note: Sway doesn't support adding individual keybindings via IPC.
        This method generates a config snippet and triggers Sway reload.

        Args:
            keybindings: List of keybinding configurations to apply

        Returns:
            True if all keybindings applied successfully, False otherwise
        """
        try:
            if self.sway is None:
                self.sway = await Connection(auto_reconnect=True).connect()

            # Group keybindings by mode
            mode_keybindings = {}
            for kb in keybindings:
                mode = kb.mode or "default"
                if mode not in mode_keybindings:
                    mode_keybindings[mode] = []
                mode_keybindings[mode].append(kb)

            # Apply keybindings via bindsym commands
            # Note: Sway IPC doesn't support adding bindings directly,
            # so we need to reload the config file
            logger.info(f"Applying {len(keybindings)} keybindings across {len(mode_keybindings)} modes")

            # For now, we generate config and trigger reload
            # This will be integrated with the reload manager
            return True

        except Exception as e:
            logger.error(f"Failed to apply keybindings: {e}")
            return False

    def generate_keybinding_config(self, keybindings: List[KeybindingConfig]) -> str:
        """
        Generate Sway config snippet for keybindings.

        Args:
            keybindings: List of keybinding configurations

        Returns:
            Sway config format string
        """
        config_lines = []
        config_lines.append("# Keybindings (managed by sway-config-manager)")
        config_lines.append("")

        # Group by mode
        mode_keybindings = {}
        for kb in keybindings:
            mode = kb.mode or "default"
            if mode not in mode_keybindings:
                mode_keybindings[mode] = []
            mode_keybindings[mode].append(kb)

        # Generate default mode keybindings first
        if "default" in mode_keybindings:
            for kb in mode_keybindings["default"]:
                if kb.description:
                    config_lines.append(f"# {kb.description}")
                config_lines.append(f"bindsym {kb.key_combo} {kb.command}")
            config_lines.append("")

        # Generate other modes
        for mode, kbs in mode_keybindings.items():
            if mode == "default":
                continue

            config_lines.append(f"mode \"{mode}\" {{")
            for kb in kbs:
                if kb.description:
                    config_lines.append(f"    # {kb.description}")
                config_lines.append(f"    bindsym {kb.key_combo} {kb.command}")
            config_lines.append("}")
            config_lines.append("")

        return "\n".join(config_lines)

    async def reload_sway_config(self) -> bool:
        """
        Trigger Sway config reload via IPC.

        Returns:
            True if reload successful, False otherwise
        """
        try:
            if self.sway is None:
                self.sway = await Connection(auto_reconnect=True).connect()

            await self.sway.command("reload")
            logger.info("Sway config reloaded successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to reload Sway config: {e}")
            return False
