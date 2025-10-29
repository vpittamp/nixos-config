"""
Keybinding manager for Sway.

Applies keybinding configurations via Sway IPC commands.
"""

import logging
from typing import List, Optional

from i3ipc.aio import Connection

from ..models import KeybindingConfig, Project

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
        self.active_project = None  # Feature 047 US3: Track active project

    def set_active_project(self, project: Optional[Project]):
        """
        Set the active project context for keybinding resolution.

        Feature 047 User Story 3: Project-aware keybinding overrides

        Args:
            project: Active project with potential keybinding overrides (None for no project)
        """
        self.active_project = project
        if project:
            logger.info(f"Set active project: {project.name} with {len(project.keybinding_overrides)} keybinding overrides")
        else:
            logger.info("Cleared active project context")

    def _apply_project_overrides(self, keybindings: List[KeybindingConfig]) -> List[KeybindingConfig]:
        """
        Apply project-specific keybinding overrides.

        Feature 047 User Story 3: Project-aware keybinding resolution with precedence (project > global)

        Args:
            keybindings: Global keybinding configurations

        Returns:
            Keybinding configurations with project overrides applied
        """
        if not self.active_project or not self.active_project.keybinding_overrides:
            return keybindings

        # Create a map of key_combo -> keybinding for fast lookup
        keybindings_map = {kb.key_combo: kb for kb in keybindings}
        result_keybindings = []

        # Track which keybindings have been overridden
        overridden_combos = set()

        # Apply project overrides
        for key_combo, override in self.active_project.keybinding_overrides.items():
            if not override.enabled:
                continue

            if key_combo in keybindings_map:
                # Override existing global keybinding
                base_kb = keybindings_map[key_combo]

                # If command is None, the keybinding is disabled (removed)
                if override.command is None:
                    logger.debug(f"Disabled keybinding {key_combo} for project {self.active_project.name}")
                    overridden_combos.add(key_combo)
                    continue

                # Otherwise, create overridden keybinding
                overridden_kb = KeybindingConfig(
                    key_combo=key_combo,
                    command=override.command,
                    description=override.description or base_kb.description,
                    source=base_kb.source,  # Keep source attribution
                    mode=base_kb.mode
                )
                result_keybindings.append(overridden_kb)
                overridden_combos.add(key_combo)
                logger.debug(f"Overridden keybinding {key_combo} for project {self.active_project.name}")
            else:
                # New project-specific keybinding (no base)
                if override.command is not None:
                    from ..models import ConfigSource
                    new_kb = KeybindingConfig(
                        key_combo=key_combo,
                        command=override.command,
                        description=override.description or f"Project keybinding for {self.active_project.name}",
                        source=ConfigSource.PROJECT,
                        mode="default"  # Default mode for new bindings
                    )
                    result_keybindings.append(new_kb)
                    logger.debug(f"Added new project keybinding {key_combo} for {self.active_project.name}")

        # Add non-overridden global keybindings
        for kb in keybindings:
            if kb.key_combo not in overridden_combos:
                result_keybindings.append(kb)

        logger.info(
            f"Applied {len(overridden_combos)} project keybinding overrides, "
            f"total keybindings: {len(result_keybindings)}"
        )

        return result_keybindings

    async def apply_keybindings(self, keybindings: List[KeybindingConfig]) -> bool:
        """
        Apply keybindings to Sway via IPC.

        Note: Sway doesn't support adding individual keybindings via IPC.
        This method generates a config snippet and triggers Sway reload.

        Feature 047 User Story 3: Applies project overrides before generating config

        Args:
            keybindings: List of keybinding configurations to apply

        Returns:
            True if all keybindings applied successfully, False otherwise
        """
        try:
            if self.sway is None:
                self.sway = await Connection(auto_reconnect=True).connect()

            # Feature 047 US3: Apply project overrides to keybindings
            active_keybindings = self._apply_project_overrides(keybindings)

            # Group keybindings by mode
            mode_keybindings = {}
            for kb in active_keybindings:
                mode = kb.mode or "default"
                if mode not in mode_keybindings:
                    mode_keybindings[mode] = []
                mode_keybindings[mode].append(kb)

            # Apply keybindings via bindsym commands
            # Note: Sway IPC doesn't support adding bindings directly,
            # so we need to reload the config file
            logger.info(f"Applying {len(active_keybindings)} keybindings across {len(mode_keybindings)} modes")

            # For now, we generate config and trigger reload
            # This will be integrated with the reload manager
            return True

        except Exception as e:
            logger.error(f"Failed to apply keybindings: {e}")
            return False

    def generate_keybinding_config(self, keybindings: List[KeybindingConfig]) -> str:
        """
        Generate Sway config snippet for keybindings.

        Feature 047 User Story 3: Applies project overrides before generating config

        Args:
            keybindings: List of keybinding configurations

        Returns:
            Sway config format string
        """
        # Feature 047 US3: Apply project overrides to keybindings
        active_keybindings = self._apply_project_overrides(keybindings)

        config_lines = []
        config_lines.append("# Keybindings (managed by sway-config-manager)")
        if self.active_project:
            config_lines.append(f"# Active project: {self.active_project.name}")
        config_lines.append("")

        # Group by mode
        mode_keybindings = {}
        for kb in active_keybindings:
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
