"""Workspace management for multi-monitor support.

Feature 033: Refactored to use declarative configuration from workspace-monitor-mapping.json
instead of hardcoded distribution rules.
"""

from dataclasses import dataclass
from typing import List, Dict, Optional, Any, Tuple
import logging

from .monitor_config_manager import MonitorConfigManager
from .models import MonitorRole

logger = logging.getLogger(__name__)


@dataclass
class MonitorConfig:
    """Monitor configuration from i3 IPC.

    Attributes:
        name: Output name (e.g., "DP-1", "HDMI-1")
        rect: Rectangle dict with x, y, width, height
        active: Whether output is currently active
        primary: Whether output is marked as primary
        role: Assigned role (primary, secondary, tertiary)

    Examples:
        >>> rect = {"x": 0, "y": 0, "width": 1920, "height": 1080}
        >>> monitor = MonitorConfig("DP-1", rect, True, True, "primary")
        >>> monitor.name
        'DP-1'
        >>> monitor.role
        'primary'
    """

    name: str
    rect: Dict[str, int]
    active: bool
    primary: bool
    role: str

    def __post_init__(self):
        """Validate monitor configuration."""
        valid_roles = ["primary", "secondary", "tertiary"]
        if self.role not in valid_roles:
            raise ValueError(
                f"Invalid role: {self.role}. "
                f"Must be one of: {', '.join(valid_roles)}"
            )

        # Validate rect structure
        required_keys = ["x", "y", "width", "height"]
        if not all(key in self.rect for key in required_keys):
            raise ValueError(
                f"Rect must contain keys: {', '.join(required_keys)}"
            )

    @classmethod
    def from_i3_output(cls, output: Any, role: str) -> "MonitorConfig":
        """Create from i3ipc.aio.OutputReply object.

        Args:
            output: i3 output reply object from GET_OUTPUTS
            role: Assigned role for this monitor

        Returns:
            MonitorConfig instance

        Examples:
            >>> # Assuming output is i3ipc.aio.OutputReply object
            >>> monitor = MonitorConfig.from_i3_output(output, "primary")
            >>> monitor.active
            True
        """
        return cls(
            name=output.name,
            rect={
                "x": output.rect.x,
                "y": output.rect.y,
                "width": output.rect.width,
                "height": output.rect.height,
            },
            active=output.active,
            primary=output.primary,
            role=role,
        )

    def to_json(self) -> dict:
        """Serialize to JSON-compatible dict."""
        return {
            "name": self.name,
            "rect": self.rect,
            "active": self.active,
            "primary": self.primary,
            "role": self.role,
        }


async def get_monitor_configs(
    i3,
    config_manager: Optional[MonitorConfigManager] = None
) -> List[MonitorConfig]:
    """Get active monitor configurations with role assignments.

    Feature 033: Now uses MonitorConfigManager for role assignment based on
    declarative configuration (output_preferences) instead of hardcoded rules.

    Args:
        i3: i3ipc.aio.Connection instance
        config_manager: Optional MonitorConfigManager instance (creates new if None)

    Returns:
        List of MonitorConfig objects with assigned roles

    Examples:
        >>> async with i3ipc.aio.Connection() as i3:
        ...     monitors = await get_monitor_configs(i3)
        ...     print(len(monitors))
        1
    """
    # Get active outputs from i3
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    if not active_outputs:
        raise RuntimeError("No active outputs found")

    # Use config manager to assign roles (Feature 033)
    if config_manager is None:
        config_manager = MonitorConfigManager()

    # Convert i3 outputs to Pydantic MonitorConfig models for role assignment
    from .models import MonitorConfig as PydanticMonitorConfig
    pydantic_monitors = [
        PydanticMonitorConfig.from_i3_output(o)
        for o in active_outputs
    ]

    # Get role assignments from config
    role_assignments = config_manager.assign_monitor_roles(pydantic_monitors)

    # Build MonitorConfig (dataclass) list with assigned roles
    monitors = []
    for output in active_outputs:
        role = role_assignments.get(output.name, MonitorRole.PRIMARY).value
        monitors.append(MonitorConfig.from_i3_output(output, role))

    return monitors


async def assign_workspaces_to_monitors(
    i3,
    monitors: List[MonitorConfig],
    workspace_preferences: Optional[Dict[int, str]] = None,
    config_manager: Optional[MonitorConfigManager] = None,
) -> None:
    """Assign workspaces to monitors based on declarative configuration.

    Feature 033: Now uses workspace-monitor-mapping.json configuration instead
    of hardcoded distribution rules. Respects workspace_preferences from config
    file and optional runtime overrides.

    Args:
        i3: i3ipc.aio.Connection instance
        monitors: List of MonitorConfig objects with roles
        workspace_preferences: Optional runtime workspace preferences (overrides config)
        config_manager: Optional MonitorConfigManager instance (creates new if None)

    Examples:
        >>> async with i3ipc.aio.Connection() as i3:
        ...     monitors = await get_monitor_configs(i3)
        ...     await assign_workspaces_to_monitors(i3, monitors)
    """
    # Build role-to-output-name mapping
    role_map = {m.role: m.name for m in monitors}

    # Load configuration (Feature 033)
    if config_manager is None:
        config_manager = MonitorConfigManager()

    # Get workspace distribution from config
    monitor_count = len(monitors)
    distribution = config_manager.get_workspace_distribution(monitor_count)

    # Apply distribution rules from config
    for role, workspace_nums in distribution.items():
        if role.value in role_map:
            output_name = role_map[role.value]
            for ws_num in workspace_nums:
                logger.debug(f"Assigning workspace {ws_num} to {output_name} ({role.value})")
                await i3.command(f"workspace {ws_num} output {output_name}")

    # Apply workspace preferences from config file
    config = config_manager.load_config()
    for ws_num, role in config.workspace_preferences.items():
        if role.value in role_map:
            output_name = role_map[role.value]
            logger.debug(f"Applying config preference: workspace {ws_num} → {output_name} ({role})")
            await i3.command(f"workspace {ws_num} output {output_name}")

    # Apply runtime workspace preferences (highest priority, overrides config)
    if workspace_preferences:
        for ws_num, preferred_role in workspace_preferences.items():
            if preferred_role in role_map:
                output_name = role_map[preferred_role]
                logger.debug(f"Applying runtime preference: workspace {ws_num} → {output_name} ({preferred_role})")
                await i3.command(f"workspace {ws_num} output {output_name}")


async def validate_target_workspace(
    conn,
    workspace: int,
) -> Tuple[bool, str]:
    """Validate that target workspace exists on an active output.

    Feature 024: Multi-monitor workspace validation

    Queries i3 GET_WORKSPACES and GET_OUTPUTS to verify the target workspace
    is assigned to an active output. This prevents assigning windows to
    workspaces on disconnected monitors.

    Args:
        conn: i3ipc.aio.Connection instance
        workspace: Target workspace number (1-9)

    Returns:
        Tuple of (valid: bool, error_message: str)
        - (True, "") if workspace is valid and on active output
        - (False, error_msg) if workspace is invalid or on inactive output

    Examples:
        >>> async with i3ipc.aio.Connection() as conn:
        ...     valid, error = await validate_target_workspace(conn, 2)
        ...     if valid:
        ...         print("Workspace 2 is valid")
    """
    try:
        # Query workspace assignments
        workspaces = await conn.get_workspaces()
        outputs = await conn.get_outputs()

        # Build set of active output names
        active_outputs = {o.name for o in outputs if o.active}

        if not active_outputs:
            return (False, "No active outputs detected")

        # Find workspace assignment
        workspace_info = next(
            (ws for ws in workspaces if ws.num == workspace),
            None
        )

        # If workspace doesn't exist yet, it's valid (will be created on current output)
        if not workspace_info:
            logger.debug(
                f"Workspace {workspace} doesn't exist yet, will be created on current output"
            )
            return (True, "")

        # Check if workspace's output is active
        if workspace_info.output not in active_outputs:
            error_msg = (
                f"Workspace {workspace} is on inactive output '{workspace_info.output}'. "
                f"Active outputs: {', '.join(active_outputs)}"
            )
            logger.warning(error_msg)
            return (False, error_msg)

        # Workspace is on active output
        logger.debug(
            f"Workspace {workspace} is valid (on active output '{workspace_info.output}')"
        )
        return (True, "")

    except Exception as e:
        error_msg = f"Error validating workspace {workspace}: {e}"
        logger.error(error_msg)
        return (False, error_msg)
