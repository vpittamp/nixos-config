"""
Window rule engine for Sway.

Dynamically applies window rules based on window criteria.
"""

import re
import logging
from typing import List, Optional

from i3ipc.aio import Connection, Con

from ..models import WindowRule, WindowCriteria

logger = logging.getLogger(__name__)


class WindowRuleEngine:
    """Applies window rules dynamically via Sway IPC."""

    def __init__(self, sway_connection: Connection = None):
        """
        Initialize window rule engine.

        Args:
            sway_connection: Async i3ipc Connection (created if None)
        """
        self.sway = sway_connection
        self.rules = []

    async def load_rules(self, rules: List[WindowRule]):
        """
        Load window rules into the engine.

        Args:
            rules: List of window rules to apply
        """
        # Sort rules by priority (lower priority applies first)
        self.rules = sorted(rules, key=lambda r: r.priority)
        logger.info(f"Loaded {len(self.rules)} window rules")

    async def apply_rules_to_window(self, window: Con) -> bool:
        """
        Apply matching rules to a window.

        Args:
            window: Sway window container

        Returns:
            True if any rules were applied, False otherwise
        """
        try:
            if self.sway is None:
                self.sway = await Connection(auto_reconnect=True).connect()

            applied_rules = []

            for rule in self.rules:
                if self._window_matches_criteria(window, rule.criteria):
                    await self._apply_rule_actions(window, rule)
                    applied_rules.append(rule.id)

            if applied_rules:
                logger.info(f"Applied rules to window {window.id}: {applied_rules}")
                return True

            return False

        except Exception as e:
            logger.error(f"Failed to apply rules to window {window.id}: {e}")
            return False

    def _window_matches_criteria(self, window: Con, criteria: WindowCriteria) -> bool:
        """
        Check if window matches criteria.

        Args:
            window: Sway window container
            criteria: Window criteria to match

        Returns:
            True if window matches, False otherwise
        """
        # Check app_id (Wayland)
        if criteria.app_id:
            app_id = getattr(window, "app_id", None)
            if not app_id or not re.match(criteria.app_id, app_id):
                return False

        # Check window_class (X11 compatibility)
        if criteria.window_class:
            window_class = getattr(window, "window_class", None)
            if not window_class or not re.match(criteria.window_class, window_class):
                return False

        # Check title
        if criteria.title:
            title = window.name or ""
            if not re.match(criteria.title, title):
                return False

        # Check window_role (X11 compatibility)
        if criteria.window_role:
            window_role = getattr(window, "window_role", None)
            if not window_role or not re.match(criteria.window_role, window_role):
                return False

        return True

    async def _apply_rule_actions(self, window: Con, rule: WindowRule):
        """
        Apply rule actions to a window.

        Args:
            window: Sway window container
            rule: Window rule to apply
        """
        for action in rule.actions:
            try:
                # Build Sway command with window criteria
                command = f"[con_id={window.id}] {action}"
                await self.sway.command(command)
                logger.debug(f"Applied action to window {window.id}: {action}")
            except Exception as e:
                logger.error(f"Failed to apply action '{action}' to window {window.id}: {e}")

    def get_matching_rules(self, window: Con) -> List[WindowRule]:
        """
        Get all rules that would match a window.

        Args:
            window: Sway window container

        Returns:
            List of matching rules
        """
        matching = []
        for rule in self.rules:
            if self._window_matches_criteria(window, rule.criteria):
                matching.append(rule)
        return matching
