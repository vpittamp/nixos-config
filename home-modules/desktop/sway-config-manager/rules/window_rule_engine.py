"""
Window rule engine for Sway.

Dynamically applies window rules based on window criteria.
"""

import re
import logging
from typing import List, Optional, Dict, Any

from i3ipc.aio import Connection, Con

from ..models import WindowRule, WindowCriteria, Project, ProjectWindowRuleOverride

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
        self.active_project = None  # Feature 047 US3: Track active project

    async def load_rules(self, rules: List[WindowRule]):
        """
        Load window rules into the engine.

        Args:
            rules: List of window rules to apply
        """
        # Sort rules by priority (lower priority applies first)
        self.rules = sorted(rules, key=lambda r: r.priority)
        logger.info(f"Loaded {len(self.rules)} window rules")

    def set_active_project(self, project: Optional[Project]):
        """
        Set the active project context for rule resolution.

        Feature 047 User Story 3: Project-aware window rules

        Args:
            project: Active project with potential window rule overrides (None for no project)
        """
        self.active_project = project
        if project:
            logger.info(f"Set active project: {project.name} with {len(project.window_rule_overrides)} overrides")
        else:
            logger.info("Cleared active project context")

    def _apply_project_overrides(self, rules: List[WindowRule]) -> List[WindowRule]:
        """
        Apply project-specific overrides to window rules.

        Feature 047 User Story 3: Project-aware window rule resolution with precedence (project > global)

        Args:
            rules: Global window rules

        Returns:
            Window rules with project overrides applied
        """
        if not self.active_project or not self.active_project.window_rule_overrides:
            return rules

        # Create a map of rule_id -> rule for fast lookup
        rules_map = {rule.id: rule for rule in rules}
        result_rules = []

        # Track which rules have been overridden
        overridden_ids = set()

        # Apply project overrides
        for override in self.active_project.window_rule_overrides:
            if not override.enabled:
                continue

            base_rule_id = override.base_rule_id

            if base_rule_id and base_rule_id in rules_map:
                # Override existing global rule
                base_rule = rules_map[base_rule_id]
                overridden_rule = self._merge_override(base_rule, override.override_properties)
                result_rules.append(overridden_rule)
                overridden_ids.add(base_rule_id)
                logger.debug(f"Applied project override to rule {base_rule_id}")
            elif not base_rule_id:
                # New project-specific rule (no base)
                new_rule = self._create_rule_from_override(override)
                result_rules.append(new_rule)
                logger.debug(f"Created new project-specific rule")

        # Add non-overridden global rules
        for rule in rules:
            if rule.id not in overridden_ids:
                result_rules.append(rule)

        # Re-sort by priority
        result_rules = sorted(result_rules, key=lambda r: r.priority)

        logger.info(
            f"Applied {len(overridden_ids)} project overrides, "
            f"total rules: {len(result_rules)}"
        )

        return result_rules

    def _merge_override(self, base_rule: WindowRule, override_properties: Dict[str, Any]) -> WindowRule:
        """
        Merge override properties into a base rule.

        Args:
            base_rule: Global window rule
            override_properties: Properties to override

        Returns:
            New WindowRule with overrides applied
        """
        # Convert base rule to dict
        rule_dict = base_rule.model_dump()

        # Apply overrides
        for key, value in override_properties.items():
            if key == 'criteria' and isinstance(value, dict):
                # Merge criteria fields
                rule_dict['criteria'].update(value)
            else:
                rule_dict[key] = value

        # Create new rule with merged properties
        return WindowRule(**rule_dict)

    def _create_rule_from_override(self, override: ProjectWindowRuleOverride) -> WindowRule:
        """
        Create a new window rule from a project override.

        Args:
            override: Project window rule override

        Returns:
            WindowRule created from override properties
        """
        # Generate unique ID for project-specific rule
        rule_id = f"project-{self.active_project.name}-{id(override)}"

        # Start with required fields
        rule_data = {
            'id': rule_id,
            'source': 'project',
            'scope': 'project',
            'project_name': self.active_project.name,
        }

        # Add override properties
        rule_data.update(override.override_properties)

        # Ensure criteria exists (default to empty criteria if not provided)
        if 'criteria' not in rule_data:
            rule_data['criteria'] = WindowCriteria()

        # Ensure actions exists
        if 'actions' not in rule_data:
            raise ValueError("Project override must specify actions")

        # Set default priority if not specified
        if 'priority' not in rule_data:
            rule_data['priority'] = 50  # Higher priority than default 100

        return WindowRule(**rule_data)

    async def apply_rules_to_window(self, window: Con) -> bool:
        """
        Apply matching rules to a window.

        Feature 047 User Story 3: Applies project overrides before matching rules

        Args:
            window: Sway window container

        Returns:
            True if any rules were applied, False otherwise
        """
        try:
            if self.sway is None:
                self.sway = await Connection(auto_reconnect=True).connect()

            # Feature 047 US3: Apply project overrides to rules
            active_rules = self._apply_project_overrides(self.rules)

            applied_rules = []

            for rule in active_rules:
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

        Feature 047 User Story 3: Returns rules with project overrides applied

        Args:
            window: Sway window container

        Returns:
            List of matching rules
        """
        # Feature 047 US3: Apply project overrides to rules
        active_rules = self._apply_project_overrides(self.rules)

        matching = []
        for rule in active_rules:
            if self._window_matches_criteria(window, rule.criteria):
                matching.append(rule)
        return matching
