"""Floating window management for Feature 001.

This module manages declarative floating window configuration, including:
- Size preset to pixel dimension mapping
- Sway for_window rule generation
- Centered positioning on monitor
- Project filtering integration (scope field)
- Window tracking via Sway marks
"""

from typing import Optional, Tuple, Dict, List
import logging
from dataclasses import dataclass

from i3ipc.aio import Connection, Con
from models.floating_config import (
    FloatingWindowConfig,
    FloatingSize,
    Scope,
    FLOATING_SIZE_DIMENSIONS,
    get_floating_dimensions,
)

logger = logging.getLogger(__name__)


@dataclass
class FloatingRule:
    """A Sway for_window rule for floating windows."""

    app_id: str
    floating: bool
    width: Optional[int] = None
    height: Optional[int] = None
    centered: bool = True
    mark: Optional[str] = None

    def to_sway_command(self) -> str:
        """Generate Sway for_window rule command.

        Returns:
            str: Sway IPC command string for for_window rule

        Example:
            >>> rule = FloatingRule(app_id="btop", floating=True, width=1200, height=800)
            >>> rule.to_sway_command()
            '[app_id="btop"] floating enable, resize set 1200 800, move position center, mark floating:btop'
        """
        commands = []

        # Floating mode
        if self.floating:
            commands.append("floating enable")

        # Size (if specified)
        if self.width and self.height:
            commands.append(f"resize set {self.width} {self.height}")

        # Positioning (centered if specified)
        if self.centered:
            commands.append("move position center")

        # Mark for tracking (if specified)
        if self.mark:
            commands.append(f"mark {self.mark}")

        # Build full command
        criteria = f'[app_id="{self.app_id}"]'
        command_str = ", ".join(commands)
        return f"{criteria} {command_str}"


class FloatingWindowManager:
    """Manages floating window configuration and Sway integration.

    This class handles:
    1. Loading floating window configurations from app registry
    2. Mapping size presets to pixel dimensions
    3. Generating Sway for_window rules
    4. Applying centered positioning
    5. Integrating with project filtering (scope field)
    6. Tracking windows via Sway marks

    Example usage:
        >>> manager = FloatingWindowManager(conn)
        >>> await manager.load_configurations()
        >>> rules = manager.generate_sway_rules()
        >>> await manager.apply_rules()
    """

    def __init__(self, conn: Connection):
        """Initialize floating window manager.

        Args:
            conn: Async i3ipc Connection for Sway IPC
        """
        self.conn = conn
        self.configs: Dict[str, FloatingWindowConfig] = {}
        self._window_marks: Dict[int, str] = {}  # container_id -> mark

    def add_configuration(self, config: FloatingWindowConfig) -> None:
        """Add a floating window configuration.

        Args:
            config: FloatingWindowConfig with app_name, floating, size, scope
        """
        self.configs[config.app_name] = config
        logger.debug(
            f"Added floating config for {config.app_name}: "
            f"floating={config.floating}, size={config.floating_size}, scope={config.scope.value}"
        )

    def load_configurations(self, configs: List[FloatingWindowConfig]) -> None:
        """Load multiple floating window configurations.

        Args:
            configs: List of FloatingWindowConfig objects
        """
        for config in configs:
            self.add_configuration(config)

        logger.info(f"Loaded {len(configs)} floating window configurations")

    def get_dimensions(self, app_name: str) -> Optional[Tuple[int, int]]:
        """Get pixel dimensions for an app's floating size preset.

        Args:
            app_name: Application identifier

        Returns:
            Tuple[int, int]: (width, height) in pixels, or None for natural size
        """
        config = self.configs.get(app_name)
        if not config or not config.floating:
            return None

        return get_floating_dimensions(config.floating_size)

    def generate_sway_rules(self) -> List[FloatingRule]:
        """Generate Sway for_window rules for all floating configurations.

        Returns:
            List[FloatingRule]: Rules ready for Sway IPC application
        """
        rules = []

        for app_name, config in self.configs.items():
            if not config.floating:
                continue

            dimensions = get_floating_dimensions(config.floating_size)
            width, height = dimensions if dimensions else (None, None)

            rule = FloatingRule(
                app_id=app_name,
                floating=True,
                width=width,
                height=height,
                centered=True,
                mark=f"floating:{app_name}"
            )

            rules.append(rule)
            logger.debug(
                f"Generated floating rule for {app_name}: "
                f"{width}×{height if dimensions else 'natural size'}"
            )

        return rules

    async def apply_rules(self) -> int:
        """Apply floating window rules to Sway via IPC.

        Returns:
            int: Number of rules successfully applied

        Note:
            This sends for_window commands directly to Sway.
            For persistent rules, they should be written to window-rules.json
            and loaded via Feature 047's dynamic config system.
        """
        rules = self.generate_sway_rules()
        applied = 0

        for rule in rules:
            try:
                command = rule.to_sway_command()
                result = await self.conn.command(f"for_window {command}")

                if result[0].success:
                    applied += 1
                    logger.debug(f"Applied floating rule: {command}")
                else:
                    logger.error(
                        f"Failed to apply floating rule for {rule.app_id}: "
                        f"{result[0].error}"
                    )
            except Exception as e:
                logger.error(f"Error applying floating rule for {rule.app_id}: {e}")

        logger.info(f"Applied {applied}/{len(rules)} floating window rules")
        return applied

    def get_rule_for_window(self, app_name: str) -> Optional[FloatingRule]:
        """Get the floating rule for a specific window.

        Args:
            app_name: Application identifier

        Returns:
            FloatingRule or None if not configured for floating
        """
        config = self.configs.get(app_name)
        if not config or not config.floating:
            return None

        dimensions = get_floating_dimensions(config.floating_size)
        width, height = dimensions if dimensions else (None, None)

        return FloatingRule(
            app_id=app_name,
            floating=True,
            width=width,
            height=height,
            centered=True,
            mark=f"floating:{app_name}"
        )

    async def apply_to_window(self, container_id: int, app_name: str) -> bool:
        """Apply floating configuration to a specific window.

        Args:
            container_id: Sway container ID
            app_name: Application identifier

        Returns:
            bool: True if successfully applied, False otherwise
        """
        rule = self.get_rule_for_window(app_name)
        if not rule:
            return False

        try:
            # Get window container
            tree = await self.conn.get_tree()
            window = tree.find_by_id(container_id)
            if not window:
                logger.warning(f"Window {container_id} not found")
                return False

            # Apply floating
            await self.conn.command(f'[con_id={container_id}] floating enable')

            # Apply size if specified
            if rule.width and rule.height:
                await self.conn.command(
                    f'[con_id={container_id}] resize set {rule.width} {rule.height}'
                )

            # Center window
            if rule.centered:
                await self.conn.command(f'[con_id={container_id}] move position center')

            # Apply mark
            if rule.mark:
                await self.conn.command(f'[con_id={container_id}] mark {rule.mark}')
                self._window_marks[container_id] = rule.mark

            logger.info(
                f"Applied floating config to window {container_id} ({app_name}): "
                f"{rule.width}×{rule.height if rule.width else 'natural'}"
            )
            return True

        except Exception as e:
            logger.error(f"Error applying floating config to window {container_id}: {e}")
            return False

    def is_floating_window(self, app_name: str) -> bool:
        """Check if an application is configured for floating.

        Args:
            app_name: Application identifier

        Returns:
            bool: True if configured as floating window
        """
        config = self.configs.get(app_name)
        return config is not None and config.floating

    def get_scope(self, app_name: str) -> Optional[Scope]:
        """Get the project filtering scope for an application.

        Args:
            app_name: Application identifier

        Returns:
            Scope: SCOPED or GLOBAL, or None if not configured
        """
        config = self.configs.get(app_name)
        return config.scope if config else None

    def should_filter_by_project(self, app_name: str) -> bool:
        """Determine if window should be filtered by project scope.

        Args:
            app_name: Application identifier

        Returns:
            bool: True if window is SCOPED (hide on project switch),
                  False if GLOBAL (always visible)
        """
        scope = self.get_scope(app_name)
        return scope == Scope.SCOPED if scope else True  # Default to SCOPED

    def get_window_mark(self, container_id: int) -> Optional[str]:
        """Get the Sway mark for a tracked floating window.

        Args:
            container_id: Sway container ID

        Returns:
            str: Mark name (e.g., "floating:btop") or None
        """
        return self._window_marks.get(container_id)

    def track_window(self, container_id: int, app_name: str) -> None:
        """Track a floating window by its Sway mark.

        Args:
            container_id: Sway container ID
            app_name: Application identifier
        """
        mark = f"floating:{app_name}"
        self._window_marks[container_id] = mark
        logger.debug(f"Tracking floating window {container_id} with mark {mark}")

    def untrack_window(self, container_id: int) -> None:
        """Stop tracking a floating window.

        Args:
            container_id: Sway container ID
        """
        if container_id in self._window_marks:
            mark = self._window_marks.pop(container_id)
            logger.debug(f"Untracked floating window {container_id} (mark: {mark})")

    def generate_window_rules_json(self) -> List[Dict]:
        """Generate window rules for Feature 047's window-rules.json format.

        Returns:
            List[Dict]: Window rules in JSON-serializable format

        Example output:
            [
                {
                    "criteria": {"app_id": "btop"},
                    "actions": {
                        "floating": True,
                        "resize": {"width": 1200, "height": 800},
                        "position": "center",
                        "mark": "floating:btop"
                    }
                }
            ]
        """
        rules = []

        for app_name, config in self.configs.items():
            if not config.floating:
                continue

            dimensions = get_floating_dimensions(config.floating_size)

            rule = {
                "criteria": {"app_id": app_name},
                "actions": {
                    "floating": True,
                    "position": "center",
                    "mark": f"floating:{app_name}"
                }
            }

            # Add resize if dimensions specified
            if dimensions:
                width, height = dimensions
                rule["actions"]["resize"] = {"width": width, "height": height}

            rules.append(rule)

        logger.debug(f"Generated {len(rules)} window rules for window-rules.json")
        return rules
