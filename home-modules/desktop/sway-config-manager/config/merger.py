"""
Configuration merger for Sway configurations.

Merges configurations from multiple sources with precedence:
1. Nix base configuration (lowest priority)
2. Runtime user configuration (medium priority)
3. Project-specific overrides (highest priority)
"""

from typing import Dict, List, Any, Optional
import logging

from ..models import KeybindingConfig, WindowRule, WorkspaceAssignment, ConfigSource

logger = logging.getLogger(__name__)


class ConfigMerger:
    """Merges configuration from multiple sources with precedence rules."""

    def __init__(self):
        """Initialize configuration merger."""
        self.conflicts = []

    def merge_keybindings(
        self,
        nix_keybindings: List[KeybindingConfig],
        runtime_keybindings: List[KeybindingConfig],
        project_keybindings: Optional[List[KeybindingConfig]] = None
    ) -> List[KeybindingConfig]:
        """
        Merge keybindings from multiple sources.

        Precedence: Project > Runtime > Nix

        Args:
            nix_keybindings: Keybindings from Nix base config
            runtime_keybindings: Keybindings from runtime TOML
            project_keybindings: Project-specific keybinding overrides

        Returns:
            Merged list of keybindings with highest precedence winning
        """
        self.conflicts = []
        keybinding_map: Dict[str, KeybindingConfig] = {}

        # Apply in order of precedence (lowest to highest)
        for kb in nix_keybindings:
            keybinding_map[kb.key_combo] = kb

        for kb in runtime_keybindings:
            if kb.key_combo in keybinding_map:
                self.conflicts.append({
                    "type": "keybinding",
                    "key": kb.key_combo,
                    "sources": [keybinding_map[kb.key_combo].source, kb.source],
                    "resolution": "runtime"
                })
                logger.warning(f"Keybinding conflict for '{kb.key_combo}': Nix vs Runtime, using Runtime")
            keybinding_map[kb.key_combo] = kb

        if project_keybindings:
            for kb in project_keybindings:
                if kb.key_combo in keybinding_map:
                    self.conflicts.append({
                        "type": "keybinding",
                        "key": kb.key_combo,
                        "sources": [keybinding_map[kb.key_combo].source, kb.source],
                        "resolution": "project"
                    })
                    logger.warning(f"Keybinding conflict for '{kb.key_combo}': {keybinding_map[kb.key_combo].source} vs Project, using Project")
                keybinding_map[kb.key_combo] = kb

        return list(keybinding_map.values())

    def merge_window_rules(
        self,
        nix_rules: List[WindowRule],
        runtime_rules: List[WindowRule],
        project_rules: Optional[List[WindowRule]] = None
    ) -> List[WindowRule]:
        """
        Merge window rules from multiple sources.

        Rules are applied by priority value (higher = later application).
        Project rules have highest priority boost.

        Args:
            nix_rules: Window rules from Nix base config
            runtime_rules: Window rules from runtime JSON
            project_rules: Project-specific window rule overrides

        Returns:
            Merged list of window rules sorted by priority
        """
        all_rules = []

        # Nix rules keep their priority
        all_rules.extend(nix_rules)

        # Runtime rules keep their priority
        all_rules.extend(runtime_rules)

        # Project rules get priority boost to ensure they apply last
        if project_rules:
            for rule in project_rules:
                # Boost project rule priority by 1000 to ensure it applies after global rules
                rule.priority += 1000
                all_rules.append(rule)

        # Sort by priority (lower priority applies first)
        all_rules.sort(key=lambda r: r.priority)

        return all_rules

    def merge_workspace_assignments(
        self,
        nix_assignments: List[WorkspaceAssignment],
        runtime_assignments: List[WorkspaceAssignment]
    ) -> List[WorkspaceAssignment]:
        """
        Merge workspace assignments from multiple sources.

        Precedence: Runtime > Nix

        Args:
            nix_assignments: Workspace assignments from Nix base config
            runtime_assignments: Workspace assignments from runtime JSON

        Returns:
            Merged list of workspace assignments
        """
        assignment_map: Dict[int, WorkspaceAssignment] = {}

        # Apply Nix assignments first
        for assignment in nix_assignments:
            assignment_map[assignment.workspace_number] = assignment

        # Runtime assignments override
        for assignment in runtime_assignments:
            if assignment.workspace_number in assignment_map:
                self.conflicts.append({
                    "type": "workspace_assignment",
                    "workspace": assignment.workspace_number,
                    "sources": [assignment_map[assignment.workspace_number].source, assignment.source],
                    "resolution": "runtime"
                })
                logger.warning(f"Workspace assignment conflict for WS{assignment.workspace_number}: Nix vs Runtime, using Runtime")
            assignment_map[assignment.workspace_number] = assignment

        return list(assignment_map.values())

    def get_conflicts(self) -> List[Dict[str, Any]]:
        """
        Get list of configuration conflicts detected during merge.

        Returns:
            List of conflict dictionaries with type, key, sources, resolution
        """
        return self.conflicts

    def clear_conflicts(self):
        """Clear recorded conflicts."""
        self.conflicts = []
