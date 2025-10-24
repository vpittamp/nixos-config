"""Monitor configuration manager for workspace-to-monitor mapping.

This module provides configuration file loading, validation, and workspace
distribution logic for the declarative workspace-to-monitor mapping system.
"""

import json
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from pydantic import ValidationError

from .models import (
    ConfigValidationResult,
    MonitorConfig,
    MonitorRole,
    ValidationIssue,
    WorkspaceMonitorConfig,
)

logger = logging.getLogger(__name__)


class MonitorConfigManager:
    """Manages workspace-to-monitor configuration.

    Handles loading, validation, and querying of the declarative configuration
    file that defines workspace distribution across monitors.
    """

    DEFAULT_CONFIG_PATH = Path.home() / ".config" / "i3" / "workspace-monitor-mapping.json"

    def __init__(self, config_path: Optional[Path] = None):
        """Initialize config manager.

        Args:
            config_path: Path to configuration file. Defaults to ~/.config/i3/workspace-monitor-mapping.json
        """
        self.config_path = config_path or self.DEFAULT_CONFIG_PATH
        self._config: Optional[WorkspaceMonitorConfig] = None
        self._last_load_time: float = 0

    def load_config(self, force_reload: bool = False) -> WorkspaceMonitorConfig:
        """Load configuration from file.

        Args:
            force_reload: Force reload even if config is already loaded

        Returns:
            Parsed and validated configuration

        Raises:
            FileNotFoundError: Config file doesn't exist
            json.JSONDecodeError: Invalid JSON syntax
            ValidationError: Configuration validation failed
        """
        import time

        current_time = time.time()

        # Return cached config if available and not forcing reload
        if self._config and not force_reload and (current_time - self._last_load_time) < 1.0:
            return self._config

        logger.info(f"Loading monitor configuration from {self.config_path}")

        if not self.config_path.exists():
            raise FileNotFoundError(
                f"Configuration file not found: {self.config_path}\n"
                f"Run 'i3pm monitors config init' to create a default configuration."
            )

        with open(self.config_path) as f:
            data = json.load(f)

        # Validate with Pydantic
        self._config = WorkspaceMonitorConfig.model_validate(data)
        self._last_load_time = current_time

        logger.info("Configuration loaded successfully")
        logger.debug(f"Config: {self._config.model_dump_json(indent=2)}")

        return self._config

    @staticmethod
    def validate_config_file(config_path: Path) -> ConfigValidationResult:
        """Validate configuration file and return structured result.

        Args:
            config_path: Path to configuration file

        Returns:
            Validation result with issues and parsed config
        """
        issues: List[ValidationIssue] = []

        # Check file exists
        if not config_path.exists():
            issues.append(ValidationIssue(
                severity="error",
                field="<root>",
                message=f"Configuration file not found: {config_path}"
            ))
            return ConfigValidationResult(valid=False, issues=issues)

        # Parse JSON
        try:
            with open(config_path) as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            issues.append(ValidationIssue(
                severity="error",
                field="<root>",
                message=f"Invalid JSON: {e.msg} at line {e.lineno}"
            ))
            return ConfigValidationResult(valid=False, issues=issues)

        # Validate with Pydantic
        try:
            config = WorkspaceMonitorConfig.model_validate(data)
        except ValidationError as e:
            for error in e.errors():
                issues.append(ValidationIssue(
                    severity="error",
                    field=".".join(str(loc) for loc in error["loc"]),
                    message=error["msg"]
                ))
            return ConfigValidationResult(valid=False, issues=issues)

        # Logical validation
        issues.extend(MonitorConfigManager._validate_distribution_logic(config))
        issues.extend(MonitorConfigManager._validate_workspace_preferences(config))

        has_errors = any(issue.severity == "error" for issue in issues)
        return ConfigValidationResult(
            valid=not has_errors,
            issues=issues,
            config=config if not has_errors else None
        )

    @staticmethod
    def _validate_distribution_logic(config: WorkspaceMonitorConfig) -> List[ValidationIssue]:
        """Validate distribution rules for logical consistency.

        Args:
            config: Configuration to validate

        Returns:
            List of validation issues
        """
        issues = []

        # Check for duplicate workspace assignments
        for monitor_count in ["one_monitor", "two_monitors", "three_monitors"]:
            dist = getattr(config.distribution, monitor_count)
            all_workspaces = dist.primary + dist.secondary + dist.tertiary

            if len(all_workspaces) != len(set(all_workspaces)):
                duplicates = [ws for ws in all_workspaces if all_workspaces.count(ws) > 1]
                issues.append(ValidationIssue(
                    severity="error",
                    field=f"distribution.{monitor_count.replace('_', '-')}",
                    message=f"Duplicate workspace assignments: {set(duplicates)}"
                ))

        return issues

    @staticmethod
    def _validate_workspace_preferences(config: WorkspaceMonitorConfig) -> List[ValidationIssue]:
        """Validate workspace preferences for conflicts.

        Args:
            config: Configuration to validate

        Returns:
            List of validation issues (warnings only)
        """
        issues = []

        # Warn if workspace preference conflicts with default distribution
        for ws_num, role in config.workspace_preferences.items():
            for monitor_count in ["one_monitor", "two_monitors", "three_monitors"]:
                dist = getattr(config.distribution, monitor_count)
                role_workspaces = getattr(dist, role)

                if ws_num not in role_workspaces:
                    issues.append(ValidationIssue(
                        severity="warning",
                        field=f"workspace_preferences.{ws_num}",
                        message=(
                            f"Workspace {ws_num} assigned to '{role}' but not in "
                            f"{monitor_count}.{role} distribution. Explicit preference takes precedence."
                        )
                    ))

        return issues

    def get_workspace_distribution(self, monitor_count: int) -> Dict[MonitorRole, List[int]]:
        """Get workspace distribution for a specific monitor count.

        Args:
            monitor_count: Number of active monitors (1, 2, or 3+)

        Returns:
            Dictionary mapping role to workspace numbers
        """
        config = self.load_config()

        # Determine which distribution to use
        if monitor_count == 1:
            dist = config.distribution.one_monitor
        elif monitor_count == 2:
            dist = config.distribution.two_monitors
        else:  # 3 or more
            dist = config.distribution.three_monitors

        # Convert to dict mapping role to workspaces
        return {
            MonitorRole.PRIMARY: dist.primary,
            MonitorRole.SECONDARY: dist.secondary,
            MonitorRole.TERTIARY: dist.tertiary,
        }

    def resolve_workspace_target_role(
        self,
        workspace_num: int,
        monitor_count: int
    ) -> Optional[MonitorRole]:
        """Resolve target role for a workspace number.

        Args:
            workspace_num: Workspace number
            monitor_count: Number of active monitors

        Returns:
            Target role for this workspace, or None if not configured
        """
        config = self.load_config()

        # Check explicit preferences first
        if workspace_num in config.workspace_preferences:
            return config.workspace_preferences[workspace_num]

        # Fall back to distribution rules
        distribution = self.get_workspace_distribution(monitor_count)

        for role, workspaces in distribution.items():
            if workspace_num in workspaces:
                return role

        # Workspace not explicitly configured
        return None

    def assign_monitor_roles(
        self,
        active_monitors: List[MonitorConfig]
    ) -> Dict[str, MonitorRole]:
        """Assign roles to active monitors based on configuration.

        Args:
            active_monitors: List of active monitors from i3 IPC

        Returns:
            Dictionary mapping output name to role
        """
        config = self.load_config()
        output_to_role: Dict[str, MonitorRole] = {}

        # Sort monitors: primary first, then by name
        sorted_monitors = sorted(
            active_monitors,
            key=lambda m: (not m.primary, m.name)
        )

        # Try to match preferred outputs first
        assigned_roles: set[MonitorRole] = set()

        for role in [MonitorRole.PRIMARY, MonitorRole.SECONDARY, MonitorRole.TERTIARY]:
            if role in config.output_preferences:
                preferred_outputs = config.output_preferences[role]

                # Try each preferred output in order
                for output_name in preferred_outputs:
                    if any(m.name == output_name and m.active for m in active_monitors):
                        if role not in assigned_roles:
                            output_to_role[output_name] = role
                            assigned_roles.add(role)
                            break

        # Assign remaining roles to unassigned monitors
        available_roles = [
            MonitorRole.PRIMARY,
            MonitorRole.SECONDARY,
            MonitorRole.TERTIARY
        ]

        unassigned_monitors = [
            m for m in sorted_monitors
            if m.name not in output_to_role
        ]

        for monitor, role in zip(unassigned_monitors, available_roles):
            if role not in assigned_roles:
                output_to_role[monitor.name] = role
                assigned_roles.add(role)

        return output_to_role

    def get_config_summary(self) -> str:
        """Get human-readable configuration summary.

        Returns:
            Multi-line string summary
        """
        config = self.load_config()

        lines = [
            f"Configuration: {self.config_path}",
            f"Version: {config.version}",
            f"Auto-reassign: {config.enable_auto_reassign}",
            f"Debounce: {config.debounce_ms}ms",
            "",
            "Distribution Rules:",
        ]

        for monitor_count_name, dist in [
            ("1 monitor", config.distribution.one_monitor),
            ("2 monitors", config.distribution.two_monitors),
            ("3 monitors", config.distribution.three_monitors),
        ]:
            lines.append(f"  {monitor_count_name}:")
            if dist.primary:
                lines.append(f"    Primary:   {dist.primary}")
            if dist.secondary:
                lines.append(f"    Secondary: {dist.secondary}")
            if dist.tertiary:
                lines.append(f"    Tertiary:  {dist.tertiary}")

        if config.workspace_preferences:
            lines.append("")
            lines.append("Workspace Preferences:")
            for ws, role in sorted(config.workspace_preferences.items()):
                lines.append(f"  Workspace {ws}: {role}")

        if config.output_preferences:
            lines.append("")
            lines.append("Output Preferences:")
            for role, outputs in config.output_preferences.items():
                lines.append(f"  {role}: {outputs}")

        return "\n".join(lines)
