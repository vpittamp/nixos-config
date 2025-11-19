"""Monitor role resolution logic for Feature 001.

This module resolves logical monitor roles (primary/secondary/tertiary) to
physical output names based on connection order and configuration preferences.
"""

import logging
from typing import List, Dict, Optional
from .models.monitor_config import (
    MonitorRole,
    OutputInfo,
    MonitorRoleConfig,
    MonitorRoleAssignment,
)

logger = logging.getLogger(__name__)


class MonitorRoleResolver:
    """Resolves monitor roles to physical outputs with fallback logic.

    Responsibilities:
    - Map logical roles (primary/secondary/tertiary) to physical outputs
    - Infer monitor roles from workspace numbers when not explicitly configured
    - Apply fallback chain when monitors disconnect: tertiary → secondary → primary
    - Log all role assignments and fallbacks for debugging
    """

    def __init__(self, output_preferences: Optional[Dict[MonitorRole, List[str]]] = None):
        """Initialize monitor role resolver.

        Args:
            output_preferences: Optional mapping of roles to preferred output names
                                (Feature US5 - not implemented in MVP)
        """
        self.output_preferences = output_preferences or {}
        logger.info("MonitorRoleResolver initialized")

    def resolve_role(
        self,
        configs: List[MonitorRoleConfig],
        outputs: List[OutputInfo],
    ) -> Dict[MonitorRole, MonitorRoleAssignment]:
        """Resolve monitor roles to physical outputs.

        Resolution logic:
        1. Filter to active outputs only
        2. Assign roles by connection order (first=primary, second=secondary, third=tertiary)
        3. Apply output preferences if configured (Feature US5)
        4. Return role→output mapping

        Args:
            configs: Application monitor role configurations
            outputs: Physical output information from Sway IPC

        Returns:
            Dict mapping each MonitorRole to its assigned output
        """
        active_outputs = [output for output in outputs if output.active]

        if not active_outputs:
            logger.error("No active outputs available for role assignment")
            return {}

        logger.info(
            f"Resolving monitor roles for {len(active_outputs)} active output(s): "
            f"{[o.name for o in active_outputs]}"
        )

        # Connection order-based role assignment
        role_assignments = self._assign_roles_by_connection_order(active_outputs)

        logger.info(
            f"Monitor role assignments: "
            f"{', '.join([f'{role.value}→{assignment.output}' for role, assignment in role_assignments.items()])}"
        )

        return role_assignments

    def _assign_roles_by_connection_order(
        self,
        outputs: List[OutputInfo],
    ) -> Dict[MonitorRole, MonitorRoleAssignment]:
        """Assign monitor roles based on connection order and output preferences.

        Assignment priority:
        1. Check output_preferences for role-specific output name preferences
        2. Try each preferred output in order (fallback chain within preferences)
        3. If no preferences match, fall back to connection order

        First output = primary, second = secondary, third = tertiary.
        If fewer than 3 outputs, some roles won't be assigned (fallback applies).

        Args:
            outputs: Active outputs in connection order

        Returns:
            Dict mapping roles to outputs
        """
        assignments = {}
        assigned_outputs = set()  # Track which outputs have been assigned

        # Role order for assignment
        role_order = [MonitorRole.PRIMARY, MonitorRole.SECONDARY, MonitorRole.TERTIARY]

        # Phase 1: Assign preferred outputs (Feature US5)
        if self.output_preferences:
            for role in role_order:
                if role in self.output_preferences:
                    preferred_outputs = self.output_preferences[role]

                    # Try each preferred output in order
                    for preferred_name in preferred_outputs:
                        # Check if this output is connected and not already assigned
                        matching_output = next(
                            (o for o in outputs if o.name == preferred_name and o.name not in assigned_outputs),
                            None
                        )

                        if matching_output:
                            assignments[role] = MonitorRoleAssignment(
                                role=role,
                                output=matching_output.name,
                                fallback_applied=False,
                                preferred_output=matching_output.name,
                            )
                            assigned_outputs.add(matching_output.name)
                            logger.info(
                                f"Assigned {role.value} → {matching_output.name} "
                                f"(preferred output, {matching_output.width}×{matching_output.height})"
                            )
                            break
                    else:
                        # No preferred output available
                        logger.warning(
                            f"Preferred outputs for {role.value} not available: "
                            f"{', '.join(preferred_outputs)}"
                        )

        # Phase 2: Assign remaining roles by connection order
        connection_order_outputs = [o for o in outputs if o.name not in assigned_outputs]

        for idx, role in enumerate(role_order):
            # Skip if already assigned via preferences
            if role in assignments:
                continue

            if idx < len(connection_order_outputs):
                output = connection_order_outputs[idx]
                assignments[role] = MonitorRoleAssignment(
                    role=role,
                    output=output.name,
                    fallback_applied=False,
                    preferred_output=None,
                )
                assigned_outputs.add(output.name)
                logger.info(
                    f"Assigned {role.value} → {output.name} "
                    f"(connection order, {output.width}×{output.height})"
                )

        return assignments

    def infer_monitor_role_from_workspace(self, workspace_num: int) -> MonitorRole:
        """Infer monitor role from workspace number.

        Inference rules:
        - WS 1-2: primary
        - WS 3-5: secondary
        - WS 6+: tertiary

        Args:
            workspace_num: Workspace number (1-70)

        Returns:
            Inferred MonitorRole
        """
        if workspace_num <= 2:
            role = MonitorRole.PRIMARY
        elif workspace_num <= 5:
            role = MonitorRole.SECONDARY
        else:
            role = MonitorRole.TERTIARY

        logger.debug(
            f"Inferred monitor role for workspace {workspace_num}: {role.value}"
        )
        return role

    def apply_fallback(
        self,
        role_assignments: Dict[MonitorRole, MonitorRoleAssignment],
        target_role: MonitorRole,
    ) -> Optional[str]:
        """Apply fallback logic when target role is unavailable.

        Fallback chain: tertiary → secondary → primary → None

        Args:
            role_assignments: Current role→output assignments
            target_role: Desired monitor role

        Returns:
            Output name to use, or None if no fallback available
        """
        # Fallback chain
        fallback_chain = {
            MonitorRole.TERTIARY: MonitorRole.SECONDARY,
            MonitorRole.SECONDARY: MonitorRole.PRIMARY,
            MonitorRole.PRIMARY: None,  # Primary has no fallback
        }

        current_role = target_role

        while current_role is not None:
            if current_role in role_assignments:
                assignment = role_assignments[current_role]
                if current_role != target_role:
                    logger.warning(
                        f"Applying fallback: {target_role.value} → {current_role.value} "
                        f"(output: {assignment.output})"
                    )
                return assignment.output

            # Move to next in fallback chain
            current_role = fallback_chain.get(current_role)

        logger.error(
            f"No fallback available for {target_role.value} "
            f"(no active outputs in fallback chain)"
        )
        return None

    def get_output_for_workspace(
        self,
        workspace_num: int,
        role_assignments: Dict[MonitorRole, MonitorRoleAssignment],
        config: Optional[MonitorRoleConfig] = None,
    ) -> Optional[str]:
        """Get output name for a workspace with fallback logic.

        Resolution order:
        1. Use explicit role from config if present
        2. Otherwise infer role from workspace number
        3. Apply fallback if role not available

        Args:
            workspace_num: Workspace number (1-70)
            role_assignments: Current role→output assignments
            config: Optional explicit configuration for this workspace

        Returns:
            Output name to assign workspace to, or None if no outputs available
        """
        # Determine target role
        if config and config.preferred_monitor_role:
            target_role = config.preferred_monitor_role
            logger.debug(
                f"Using explicit monitor role for WS {workspace_num}: "
                f"{target_role.value} (from {config.source})"
            )
        else:
            target_role = self.infer_monitor_role_from_workspace(workspace_num)
            logger.debug(
                f"Using inferred monitor role for WS {workspace_num}: {target_role.value}"
            )

        # Get output with fallback
        output = self.apply_fallback(role_assignments, target_role)

        if output:
            logger.info(
                f"Workspace {workspace_num} → {output} "
                f"(role: {target_role.value}, "
                f"app: {config.app_name if config else 'default'})"
            )
        else:
            logger.error(
                f"No output available for workspace {workspace_num} "
                f"(target role: {target_role.value})"
            )

        return output
