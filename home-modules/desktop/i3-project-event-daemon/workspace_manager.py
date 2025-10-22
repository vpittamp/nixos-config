"""Workspace management for multi-monitor support."""

from dataclasses import dataclass
from typing import List, Dict, Optional, Any, Tuple
import logging

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


async def get_monitor_configs(i3) -> List[MonitorConfig]:
    """Get active monitor configurations with role assignments.

    Queries i3 GET_OUTPUTS and assigns roles based on monitor count and primary flag.

    Distribution rules:
    - 1 monitor: all workspaces on primary
    - 2 monitors: WS 1-2 primary, WS 3-9 secondary
    - 3+ monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary

    Args:
        i3: i3ipc.aio.Connection instance

    Returns:
        List of MonitorConfig objects with assigned roles

    Examples:
        >>> async with i3ipc.aio.Connection() as i3:
        ...     monitors = await get_monitor_configs(i3)
        ...     print(len(monitors))
        1
    """
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    if not active_outputs:
        raise RuntimeError("No active outputs found")

    # Assign roles based on count and primary flag
    if len(active_outputs) == 1:
        # Single monitor: everything on primary
        return [MonitorConfig.from_i3_output(active_outputs[0], "primary")]

    elif len(active_outputs) == 2:
        # Dual monitor: primary and secondary
        primary = next((o for o in active_outputs if o.primary), active_outputs[0])
        secondary = next((o for o in active_outputs if o != primary), active_outputs[1])

        return [
            MonitorConfig.from_i3_output(primary, "primary"),
            MonitorConfig.from_i3_output(secondary, "secondary"),
        ]

    else:
        # Triple+ monitor: primary, secondary, tertiary
        primary = next((o for o in active_outputs if o.primary), active_outputs[0])

        # Remaining outputs assigned as secondary, tertiary, etc.
        remaining = [o for o in active_outputs if o != primary]
        secondary = remaining[0] if remaining else None
        tertiary = remaining[1] if len(remaining) > 1 else None

        monitors = [MonitorConfig.from_i3_output(primary, "primary")]

        if secondary:
            monitors.append(MonitorConfig.from_i3_output(secondary, "secondary"))

        if tertiary:
            monitors.append(MonitorConfig.from_i3_output(tertiary, "tertiary"))

        # Additional monitors beyond 3 get "tertiary" role
        for extra in remaining[2:]:
            monitors.append(MonitorConfig.from_i3_output(extra, "tertiary"))

        return monitors


async def assign_workspaces_to_monitors(
    i3,
    monitors: List[MonitorConfig],
    workspace_preferences: Optional[Dict[int, str]] = None,
) -> None:
    """Assign workspaces to monitors based on distribution rules.

    Distribution rules:
    - 1 monitor: WS 1-9 on primary
    - 2 monitors: WS 1-2 on primary, WS 3-9 on secondary
    - 3+ monitors: WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary

    Args:
        i3: i3ipc.aio.Connection instance
        monitors: List of MonitorConfig objects with roles
        workspace_preferences: Optional project-specific workspace preferences

    Examples:
        >>> async with i3ipc.aio.Connection() as i3:
        ...     monitors = await get_monitor_configs(i3)
        ...     await assign_workspaces_to_monitors(i3, monitors)
    """
    # Build role-to-output-name mapping
    role_map = {m.role: m.name for m in monitors}

    # Determine workspace distribution based on monitor count
    monitor_count = len(monitors)

    if monitor_count == 1:
        # All workspaces on primary
        primary_output = role_map["primary"]
        for ws_num in range(1, 10):
            await i3.command(f"workspace {ws_num} output {primary_output}")

    elif monitor_count == 2:
        # WS 1-2 on primary, WS 3-9 on secondary
        primary_output = role_map["primary"]
        secondary_output = role_map["secondary"]

        for ws_num in range(1, 3):
            await i3.command(f"workspace {ws_num} output {primary_output}")

        for ws_num in range(3, 10):
            await i3.command(f"workspace {ws_num} output {secondary_output}")

    else:
        # WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary
        primary_output = role_map["primary"]
        secondary_output = role_map.get("secondary")
        tertiary_output = role_map.get("tertiary")

        for ws_num in range(1, 3):
            await i3.command(f"workspace {ws_num} output {primary_output}")

        if secondary_output:
            for ws_num in range(3, 6):
                await i3.command(f"workspace {ws_num} output {secondary_output}")

        if tertiary_output:
            for ws_num in range(6, 10):
                await i3.command(f"workspace {ws_num} output {tertiary_output}")

    # Apply workspace preferences if provided
    if workspace_preferences:
        for ws_num, preferred_role in workspace_preferences.items():
            if preferred_role in role_map:
                output_name = role_map[preferred_role]
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
