"""Workspace management for multi-monitor support.

Feature 033: Refactored to use declarative configuration from workspace-monitor-mapping.json
instead of hardcoded distribution rules.

Feature 001: Added monitor role-based workspace assignment using workspace-assignments.json
generated from app-registry-data.nix.
"""

from dataclasses import dataclass
from typing import List, Dict, Optional, Any, Tuple
import json
import logging
from pathlib import Path

from .monitor_config_manager import MonitorConfigManager
from .models import MonitorRole
from .monitor_role_resolver import MonitorRoleResolver
from .models.monitor_config import (
    OutputInfo as OutputInfoV2,
    MonitorRoleConfig,
)

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
    # Use output-states.json to determine which outputs are "active"
    # This works around the limitation that headless outputs can't be disabled via DPMS
    from .output_state_manager import load_output_states
    output_states = load_output_states()

    outputs = await i3.get_outputs()
    active_outputs = [
        o for o in outputs
        if o.active and output_states.is_output_enabled(o.name)
    ]

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
                await i3.command(f"workspace number {ws_num} output {output_name}")

    # Apply workspace preferences from config file
    config = config_manager.load_config()
    for ws_num, role in config.workspace_preferences.items():
        if role.value in role_map:
            output_name = role_map[role.value]
            logger.debug(f"Applying config preference: workspace {ws_num} → {output_name} ({role})")
            await i3.command(f"workspace number {ws_num} output {output_name}")

    # Apply runtime workspace preferences (highest priority, overrides config)
    if workspace_preferences:
        for ws_num, preferred_role in workspace_preferences.items():
            if preferred_role in role_map:
                output_name = role_map[preferred_role]
                logger.debug(f"Applying runtime preference: workspace {ws_num} → {output_name} ({preferred_role})")
                await i3.command(f"workspace number {ws_num} output {output_name}")


async def assign_workspaces_with_monitor_roles(
    i3,
    config_path: Optional[Path] = None
) -> None:
    """Assign workspaces to monitors using Feature 001 monitor role system.

    Feature 001: This function uses workspace-assignments.json (generated from
    app-registry-data.nix) to determine workspace→monitor assignments based on
    app preferences with monitor roles (primary/secondary/tertiary).

    This is the primary assignment mechanism for Feature 001 and operates
    independently from the legacy Feature 049 workspace-monitor-mapping.json.

    Args:
        i3: i3ipc.aio.Connection instance
        config_path: Optional path to workspace-assignments.json (defaults to ~/.config/sway/workspace-assignments.json)

    Raises:
        FileNotFoundError: workspace-assignments.json doesn't exist
        json.JSONDecodeError: Invalid JSON syntax
        ValueError: Invalid configuration data

    Examples:
        >>> async with i3ipc.aio.Connection() as i3:
        ...     await assign_workspaces_with_monitor_roles(i3)
    """
    # Load workspace-assignments.json (Feature 001)
    if config_path is None:
        config_path = Path.home() / ".config" / "sway" / "workspace-assignments.json"

    if not config_path.exists():
        logger.warning(
            f"Feature 001 workspace assignments not found: {config_path}\n"
            f"Run 'sudo nixos-rebuild switch' to generate from app-registry-data.nix"
        )
        return

    logger.info(f"[Feature 001] Loading workspace assignments from {config_path}")

    with open(config_path) as f:
        data = json.load(f)

    # Validate version
    version = data.get("version")
    if version != "1.0":
        raise ValueError(f"Unsupported workspace-assignments.json version: {version} (expected 1.0)")

    # Parse assignments
    assignments_data = data.get("assignments", [])
    if not assignments_data:
        logger.warning("[Feature 001] No workspace assignments found in configuration")
        return

    # Convert to MonitorRoleConfig models
    configs = []
    for item in assignments_data:
        try:
            # Support both "workspace" (legacy) and "workspace_number" (current) formats
            workspace = item.get("workspace_number") or item.get("workspace")
            if workspace is None:
                logger.error(f"[Feature 001] Missing workspace for {item.get('app_name')}")
                continue

            config = MonitorRoleConfig(
                app_name=item["app_name"],
                preferred_workspace=workspace,
                preferred_monitor_role=item.get("monitor_role"),  # May be None (inferred)
                source=item.get("source", "nix")
            )
            configs.append(config)
        except Exception as e:
            logger.error(f"[Feature 001] Failed to parse assignment for {item.get('app_name')}: {e}")
            continue

    logger.info(f"[Feature 001] Loaded {len(configs)} workspace assignments")

    # Parse output_preferences for deterministic role→output mapping
    # Without this, the daemon falls back to connection order which can vary
    output_preferences_raw = data.get("output_preferences", {})
    output_preferences = {}
    if output_preferences_raw:
        from .models import MonitorRole
        role_mapping = {
            "primary": MonitorRole.PRIMARY,
            "secondary": MonitorRole.SECONDARY,
            "tertiary": MonitorRole.TERTIARY,
        }
        for role_name, output_list in output_preferences_raw.items():
            if role_name in role_mapping and isinstance(output_list, list):
                output_preferences[role_mapping[role_name]] = output_list
        logger.info(
            f"[Feature 001] Loaded output preferences: "
            f"{', '.join([f'{k.value}→{v}' for k, v in output_preferences.items()])}"
        )

    # Get active outputs from Sway IPC
    # Use output-states.json to determine which outputs are "active"
    # This works around the limitation that headless outputs can't be disabled via DPMS
    from .output_state_manager import load_output_states
    output_states = load_output_states()

    outputs_raw = await i3.get_outputs()
    active_outputs_raw = [
        o for o in outputs_raw
        if o.active and output_states.is_output_enabled(o.name)
    ]

    if not active_outputs_raw:
        logger.error("[Feature 001] No active outputs found - cannot assign workspaces")
        return

    # Convert to Feature 001 OutputInfo models
    outputs = [
        OutputInfoV2(
            name=o.name,
            active=o.active,
            width=o.rect.width,
            height=o.rect.height,
            scale=getattr(o, 'scale', 1.0)
        )
        for o in active_outputs_raw
    ]

    logger.info(
        f"[Feature 001] Found {len(outputs)} active output(s): "
        f"{', '.join([o.name for o in outputs])}"
    )

    # Initialize MonitorRoleResolver with output preferences for deterministic mapping
    resolver = MonitorRoleResolver(output_preferences=output_preferences)

    # Resolve monitor roles to physical outputs
    role_assignments = resolver.resolve_role(configs, outputs)

    if not role_assignments:
        logger.error("[Feature 001] Failed to resolve monitor role assignments")
        return

    # Group assignments by workspace number with conflict detection (Feature 001 US3: T042-T043)
    workspace_to_config: Dict[int, MonitorRoleConfig] = {}
    for config in configs:
        ws_num = config.preferred_workspace

        # Feature 001 T043: Detect and log duplicate workspace assignments
        if ws_num in workspace_to_config:
            existing = workspace_to_config[ws_num]
            logger.warning(
                f"[Feature 001] Workspace {ws_num} conflict detected: "
                f"'{existing.app_name}' (source: {existing.source}) "
                f"→ OVERRIDDEN BY '{config.app_name}' (source: {config.source})"
            )

            # Feature 001 T042: PWA preference priority (PWA > app)
            # PWAs from pwa-sites.nix override apps from app-registry-data.nix
            if config.source == "pwa-sites" and existing.source == "app-registry":
                logger.info(
                    f"[Feature 001] PWA preference applied: '{config.app_name}' "
                    f"overrides '{existing.app_name}' on workspace {ws_num}"
                )

        # Last one wins (PWAs override apps since they're processed after)
        workspace_to_config[ws_num] = config

    # Apply workspace→output assignments via Sway IPC
    assignments_applied = 0
    for ws_num, config in sorted(workspace_to_config.items()):
        output_name = resolver.get_output_for_workspace(
            workspace_num=ws_num,
            role_assignments=role_assignments,
            config=config
        )

        if output_name:
            try:
                # Set preferred output for this workspace
                await i3.command(f"workspace number {ws_num} output {output_name}")
                assignments_applied += 1
                logger.debug(
                    f"[Feature 001] Assigned workspace {ws_num} → {output_name} "
                    f"(app: {config.app_name}, source: {config.source})"
                )
            except Exception as e:
                logger.error(
                    f"[Feature 001] Failed to assign workspace {ws_num} to {output_name}: {e}"
                )
        else:
            logger.warning(
                f"[Feature 001] No output available for workspace {ws_num} "
                f"(app: {config.app_name})"
            )

    logger.info(
        f"[Feature 001] Applied {assignments_applied}/{len(workspace_to_config)} "
        f"workspace→output assignments"
    )

    # Feature 001 T036: Persist MonitorStateV2
    await persist_monitor_state_v2(
        role_assignments=role_assignments,
        workspace_assignments=workspace_to_config,
        resolver=resolver
    )


async def persist_monitor_state_v2(
    role_assignments: Dict,
    workspace_assignments: Dict[int, MonitorRoleConfig],
    resolver: MonitorRoleResolver,
) -> None:
    """Persist MonitorStateV2 with fallback metadata (Feature 001: T036).

    Writes current monitor role assignments and workspace assignments to
    ~/.config/sway/monitor-state.json for state recovery and debugging.

    Args:
        role_assignments: Dict[MonitorRole, MonitorRoleAssignment] from resolver
        workspace_assignments: Dict[int, MonitorRoleConfig] mapping workspace → config
        resolver: MonitorRoleResolver instance for output resolution
    """
    try:
        from .models.monitor_config import MonitorStateV2, WorkspaceAssignment

        # Build monitor_roles dict (role name → output name)
        monitor_roles_dict = {
            role.value: assignment.output
            for role, assignment in role_assignments.items()
        }

        # Build workspaces dict (workspace num → WorkspaceAssignment)
        workspaces_dict = {}
        for ws_num, config in workspace_assignments.items():
            output = resolver.get_output_for_workspace(
                workspace_num=ws_num,
                role_assignments=role_assignments,
                config=config
            )

            if output:
                # Determine monitor role (explicit or inferred)
                monitor_role = config.preferred_monitor_role
                if monitor_role is None:
                    monitor_role = resolver.infer_monitor_role_from_workspace(ws_num)

                workspaces_dict[ws_num] = WorkspaceAssignment(
                    workspace_num=ws_num,
                    output=output,
                    monitor_role=monitor_role,
                    app_name=config.app_name,
                    source=config.source
                )

        # Create MonitorStateV2 model
        state = MonitorStateV2(
            monitor_roles=monitor_roles_dict,
            workspaces=workspaces_dict
        )

        # Write to ~/.config/sway/monitor-state.json
        state_path = Path.home() / ".config" / "sway" / "monitor-state.json"
        state_path.parent.mkdir(parents=True, exist_ok=True)

        with open(state_path, "w") as f:
            # Use model_dump_json for Pydantic v2 compatibility
            if hasattr(state, 'model_dump_json'):
                f.write(state.model_dump_json(indent=2))
            else:
                f.write(state.json(indent=2))  # Fallback for Pydantic v1

        logger.info(
            f"[Feature 001] Persisted MonitorStateV2 to {state_path} "
            f"({len(monitor_roles_dict)} roles, {len(workspaces_dict)} workspaces)"
        )

    except Exception as e:
        logger.error(f"[Feature 001] Failed to persist MonitorStateV2: {e}")


async def force_move_existing_workspaces(
    i3,
    config_path: Optional[Path] = None
) -> Dict[str, Any]:
    """Force-move existing workspaces to their configured outputs.

    Unlike assign_workspaces_with_monitor_roles which only sets preferred output
    for future switches, this function actually moves existing workspaces that
    are on the wrong output to their correct output.

    This is useful when:
    - Workspaces were created before monitor assignments were configured
    - Monitor role mapping changed and existing workspaces need to move
    - After a nixos-rebuild to apply new workspace-assignments.json

    Args:
        i3: i3ipc.aio.Connection instance
        config_path: Optional path to workspace-assignments.json

    Returns:
        Dict with 'moved' (list of moved workspaces), 'skipped', 'errors' counts
    """
    from .models import MonitorRole
    from .models.monitor_config import MonitorRoleConfig

    result = {
        "moved": [],
        "skipped": 0,
        "errors": 0,
        "total": 0,
    }

    # Load workspace-assignments.json
    if config_path is None:
        config_path = Path.home() / ".config" / "sway" / "workspace-assignments.json"

    if not config_path.exists():
        logger.warning(f"Force-move: workspace-assignments.json not found: {config_path}")
        return result

    with open(config_path) as f:
        data = json.load(f)

    # Parse output_preferences
    output_preferences_raw = data.get("output_preferences", {})
    output_preferences = {}
    if output_preferences_raw:
        role_mapping = {
            "primary": MonitorRole.PRIMARY,
            "secondary": MonitorRole.SECONDARY,
            "tertiary": MonitorRole.TERTIARY,
        }
        for role_name, output_list in output_preferences_raw.items():
            if role_name in role_mapping and isinstance(output_list, list):
                output_preferences[role_mapping[role_name]] = output_list

    # Build workspace → target output mapping
    # Use workspace number rules: WS 1-2 → primary, WS 3-5 → secondary, WS 6+ → tertiary
    # This ensures ALL workspaces get a target output, not just those with explicit assignments
    def get_target_output_for_workspace(ws_num: int) -> Optional[str]:
        """Determine target output for a workspace based on number rules."""
        if ws_num <= 2:
            role = MonitorRole.PRIMARY
        elif ws_num <= 5:
            role = MonitorRole.SECONDARY
        else:
            role = MonitorRole.TERTIARY

        if role in output_preferences and output_preferences[role]:
            return output_preferences[role][0]
        return None

    # Also build explicit assignments from config (these override the default rules)
    assignments_data = data.get("assignments", [])
    explicit_workspace_to_output = {}

    for item in assignments_data:
        workspace = item.get("workspace_number") or item.get("workspace")
        if workspace is None:
            continue

        monitor_role_str = item.get("monitor_role")
        if monitor_role_str:
            role_mapping = {
                "primary": MonitorRole.PRIMARY,
                "secondary": MonitorRole.SECONDARY,
                "tertiary": MonitorRole.TERTIARY,
            }
            monitor_role = role_mapping.get(monitor_role_str)
            if monitor_role and monitor_role in output_preferences:
                target_outputs = output_preferences[monitor_role]
                if target_outputs:
                    explicit_workspace_to_output[workspace] = target_outputs[0]

    if not output_preferences:
        logger.warning("Force-move: No output_preferences found - cannot determine target outputs")
        return result

    # Get current workspaces from Sway
    workspaces = await i3.get_workspaces()

    # Check each existing workspace
    for ws in workspaces:
        ws_num = ws.num
        current_output = ws.output

        # First check explicit assignment, then fall back to workspace number rules
        target_output = explicit_workspace_to_output.get(ws_num) or get_target_output_for_workspace(ws_num)

        if not target_output:
            result["skipped"] += 1
            logger.debug(f"Force-move: No target output for WS {ws_num}, skipping")
            continue

        result["total"] += 1

        if current_output == target_output:
            result["skipped"] += 1
            logger.debug(f"Force-move: WS {ws_num} already on correct output {target_output}")
            continue

        # Need to move this workspace
        try:
            # Focus the workspace, then move it to target output
            await i3.command(f"workspace number {ws_num}")
            await i3.command(f"move workspace to output {target_output}")

            result["moved"].append({
                "workspace": ws_num,
                "from": current_output,
                "to": target_output,
            })
            logger.info(
                f"Force-move: Moved workspace {ws_num} from {current_output} → {target_output}"
            )
        except Exception as e:
            result["errors"] += 1
            logger.error(f"Force-move: Failed to move workspace {ws_num}: {e}")

    logger.info(
        f"Force-move complete: {len(result['moved'])} moved, "
        f"{result['skipped']} skipped, {result['errors']} errors"
    )

    return result


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
        # Use output-states.json to determine which outputs are "active"
        from .output_state_manager import load_output_states
        output_states = load_output_states()
        active_outputs = {
            o.name for o in outputs
            if o.active and output_states.is_output_enabled(o.name)
        }

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
