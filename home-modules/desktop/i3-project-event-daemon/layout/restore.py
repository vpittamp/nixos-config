"""
Layout Restoration Module

Feature 030: Production Readiness
Task T036: Launch applications with captured commands
Task T037: Implement window swallowing for layout restore
Task T038: Apply geometry and marks after swallow
Task T039: Detect current monitor configuration
Task T040: Adapt layout to different monitor setup

Restores saved layouts by:
1. Launching applications
2. Waiting for windows to appear (swallowing)
3. Applying saved geometry and marks
4. Adapting to current monitor configuration
"""

import logging
import asyncio
import subprocess
from typing import List, Dict, Optional, Set
from datetime import datetime, timedelta

try:
    from .models import LayoutSnapshot, Window, WorkspaceLayout, Monitor, Resolution, Position
    from .persistence import load_layout
except ImportError:
    from models import LayoutSnapshot, Window, WorkspaceLayout, Monitor, Resolution, Position
    from persistence import load_layout

logger = logging.getLogger(__name__)


class LayoutRestore:
    """
    Restores window layouts

    Process:
    1. Detect current monitor configuration (T039)
    2. Adapt layout to monitors (T040)
    3. Launch applications (T036)
    4. Wait for windows to appear (T037)
    5. Apply geometry and marks (T038)
    """

    def __init__(self, i3_connection):
        """
        Initialize layout restore

        Args:
            i3_connection: i3ipc connection instance
        """
        self.i3 = i3_connection
        self.swallow_timeout = 30.0  # seconds
        self.swallow_check_interval = 0.5  # seconds

    async def restore_layout(
        self,
        snapshot: LayoutSnapshot,
        adapt_monitors: bool = True,
    ) -> Dict[str, any]:
        """
        Restore layout from snapshot

        Args:
            snapshot: LayoutSnapshot to restore
            adapt_monitors: Adapt layout to current monitors (default: True)

        Returns:
            Dictionary with restoration results
        """
        logger.info(f"Restoring layout: {snapshot.name}")

        start_time = datetime.now()
        results = {
            "success": True,
            "windows_launched": 0,
            "windows_swallowed": 0,
            "windows_failed": 0,
            "errors": [],
            "start_time": start_time.isoformat(),
        }

        try:
            # T039: Detect current monitor configuration
            current_monitors = await self._detect_monitor_configuration()

            # T040: Adapt layout to monitors
            if adapt_monitors:
                snapshot = self._adapt_layout_to_monitors(snapshot, current_monitors)

            # Process each workspace
            for workspace_layout in snapshot.workspace_layouts:
                await self._restore_workspace(workspace_layout, results)

            # Calculate duration
            duration = (datetime.now() - start_time).total_seconds()
            results["duration_seconds"] = duration

            logger.info(
                f"Layout restore completed: {results['windows_launched']} launched, "
                f"{results['windows_swallowed']} swallowed, {results['windows_failed']} failed"
            )

        except Exception as e:
            results["success"] = False
            results["errors"].append(str(e))
            logger.error(f"Layout restore failed: {e}")

        return results

    async def _detect_monitor_configuration(self) -> List[Monitor]:
        """
        Detect current monitor configuration (T039)

        Returns:
            List of Monitor objects representing current setup
        """
        outputs = await self._get_outputs()
        monitors = []

        for output in outputs:
            # Skip inactive outputs
            if not getattr(output, 'active', True):
                continue

            # Skip special outputs
            if output.name in ['xroot', '__i3']:
                continue

            # Extract rect values
            rect_width = output.rect['width'] if hasattr(output.rect, '__getitem__') else output.rect.width
            rect_height = output.rect['height'] if hasattr(output.rect, '__getitem__') else output.rect.height
            rect_x = output.rect['x'] if hasattr(output.rect, '__getitem__') else output.rect.x
            rect_y = output.rect['y'] if hasattr(output.rect, '__getitem__') else output.rect.y

            monitor = Monitor(
                name=output.name,
                active=getattr(output, 'active', True),
                primary=getattr(output, 'primary', False),
                current_workspace=getattr(output, 'current_workspace', None),
                resolution=Resolution(width=rect_width, height=rect_height),
                position=Position(x=rect_x, y=rect_y),
            )
            monitors.append(monitor)

        logger.info(f"Detected {len(monitors)} monitors: {[m.name for m in monitors]}")

        return monitors

    def _adapt_layout_to_monitors(
        self,
        snapshot: LayoutSnapshot,
        current_monitors: List[Monitor]
    ) -> LayoutSnapshot:
        """
        Adapt layout to current monitor configuration (T040)

        Strategies:
        1. Same monitors: Use saved positions
        2. Fewer monitors: Collapse to primary
        3. More monitors: Distribute workspaces
        4. Different resolution: Scale geometry

        Args:
            snapshot: Original layout snapshot
            current_monitors: Current monitor configuration

        Returns:
            Adapted LayoutSnapshot
        """
        saved_monitors = snapshot.monitor_config.monitors

        logger.info(
            f"Adapting layout: {len(saved_monitors)} saved monitors → "
            f"{len(current_monitors)} current monitors"
        )

        # Feature 033: Use declarative workspace-to-monitor distribution
        # This ensures restored workspaces go to the correct monitors according to config
        workspace_to_output = self._get_workspace_distribution(current_monitors)

        # Build output name mapping for backwards compatibility
        output_mapping = self._build_output_mapping(saved_monitors, current_monitors)

        # Adapt workspace layouts
        adapted_workspaces = []
        for ws_layout in snapshot.workspace_layouts:
            # Feature 033: Determine target output from workspace-to-monitor config
            # Falls back to output_mapping if workspace not in distribution
            new_output = workspace_to_output.get(
                ws_layout.workspace_num,
                output_mapping.get(ws_layout.output, current_monitors[0].name if current_monitors else "unknown")
            )

            # Get monitor for scaling
            saved_monitor = next((m for m in saved_monitors if m.name == ws_layout.output), None)
            current_monitor = next((m for m in current_monitors if m.name == new_output), None)

            # Adapt windows
            adapted_windows = []
            for window in ws_layout.windows:
                adapted_window = self._adapt_window_geometry(
                    window,
                    saved_monitor,
                    current_monitor
                )
                adapted_windows.append(adapted_window)

            # Create adapted workspace layout
            adapted_ws = WorkspaceLayout(
                workspace_num=ws_layout.workspace_num,
                workspace_name=ws_layout.workspace_name,
                output=new_output,
                layout_mode=ws_layout.layout_mode,
                containers=ws_layout.containers,
                windows=adapted_windows,
            )
            adapted_workspaces.append(adapted_ws)

        # Update snapshot
        snapshot.workspace_layouts = adapted_workspaces

        return snapshot

    def _get_workspace_distribution(
        self,
        current_monitors: List[Monitor]
    ) -> Dict[int, str]:
        """
        Get workspace-to-output mapping from Feature 033 configuration

        Uses MonitorConfigManager to determine which output each workspace
        should be placed on based on the declarative distribution rules.

        Args:
            current_monitors: Current monitor configuration

        Returns:
            Dictionary mapping workspace_num → output_name
        """
        workspace_to_output = {}

        try:
            # Import Feature 033 components
            from ..monitor_config_manager import MonitorConfigManager
            from ..workspace_manager import get_monitor_configs

            # Load configuration
            config_manager = MonitorConfigManager()
            config = config_manager.load_config()

            # Get monitor configurations with assigned roles (async call wrapped)
            # Note: We can't use await here since this is a sync method
            # So we'll use a simplified version that just assigns roles based on config

            # Assign monitor roles based on primary flag and output_preferences
            monitor_roles = config_manager.assign_monitor_roles(current_monitors)

            # Get workspace distribution for current monitor count
            distribution = config_manager.get_workspace_distribution(len(current_monitors))

            # Build workspace → output mapping
            for role, workspace_nums in distribution.items():
                # Find output with this role
                output_name = monitor_roles.get(role)
                if output_name:
                    for ws_num in workspace_nums:
                        workspace_to_output[ws_num] = output_name

            # Apply workspace_preferences overrides
            for ws_num, role in config.workspace_preferences.items():
                output_name = monitor_roles.get(role)
                if output_name:
                    workspace_to_output[ws_num] = output_name

            logger.info(
                f"Feature 033: Mapped {len(workspace_to_output)} workspaces "
                f"using declarative distribution ({len(current_monitors)} monitors)"
            )

        except Exception as e:
            logger.warning(f"Could not load workspace distribution from Feature 033: {e}")
            logger.info("Falling back to legacy output mapping")

        return workspace_to_output

    def _build_output_mapping(
        self,
        saved_monitors: List[Monitor],
        current_monitors: List[Monitor]
    ) -> Dict[str, str]:
        """
        Build mapping from saved output names to current output names

        Args:
            saved_monitors: Saved monitor configuration
            current_monitors: Current monitor configuration

        Returns:
            Dictionary mapping saved output → current output
        """
        mapping = {}

        if not current_monitors:
            return mapping

        # Primary monitor mapping
        saved_primary = next((m for m in saved_monitors if m.primary), None)
        current_primary = next((m for m in current_monitors if m.primary), None) or current_monitors[0]

        if saved_primary:
            mapping[saved_primary.name] = current_primary.name

        # Try to match by position
        for saved_mon in saved_monitors:
            if saved_mon.name in mapping:
                continue

            # Find current monitor at similar position
            for current_mon in current_monitors:
                if current_mon.name not in mapping.values():
                    # Simple position matching (left, right, etc.)
                    if saved_mon.position.x == current_mon.position.x and saved_mon.position.y == current_mon.position.y:
                        mapping[saved_mon.name] = current_mon.name
                        break

        # Fallback: Map remaining to available monitors
        available_monitors = [m for m in current_monitors if m.name not in mapping.values()]
        for saved_mon in saved_monitors:
            if saved_mon.name not in mapping and available_monitors:
                mapping[saved_mon.name] = available_monitors.pop(0).name

        # Final fallback: Map to primary
        for saved_mon in saved_monitors:
            if saved_mon.name not in mapping:
                mapping[saved_mon.name] = current_primary.name

        return mapping

    def _adapt_window_geometry(
        self,
        window: Window,
        saved_monitor: Optional[Monitor],
        current_monitor: Optional[Monitor]
    ) -> Window:
        """
        Adapt window geometry to current monitor

        Args:
            window: Original window
            saved_monitor: Monitor window was on
            current_monitor: Current monitor

        Returns:
            Window with adapted geometry
        """
        if not saved_monitor or not current_monitor:
            return window

        # Calculate scaling factors
        width_scale = current_monitor.resolution.width / saved_monitor.resolution.width
        height_scale = current_monitor.resolution.height / saved_monitor.resolution.height

        # Scale geometry
        new_geometry = window.geometry.model_copy()
        new_geometry.width = int(window.geometry.width * width_scale)
        new_geometry.height = int(window.geometry.height * height_scale)
        new_geometry.x = int(window.geometry.x * width_scale) + current_monitor.position.x
        new_geometry.y = int(window.geometry.y * height_scale) + current_monitor.position.y

        # Create adapted window
        adapted = window.model_copy()
        adapted.geometry = new_geometry

        return adapted

    async def _restore_workspace(
        self,
        workspace_layout: WorkspaceLayout,
        results: Dict
    ) -> None:
        """
        Restore windows for a workspace

        Args:
            workspace_layout: Workspace layout to restore
            results: Results dictionary to update
        """
        workspace_id = f"{workspace_layout.workspace_num}: {workspace_layout.workspace_name}" if workspace_layout.workspace_name else str(workspace_layout.workspace_num)
        logger.info(f"Restoring workspace {workspace_id}: {len(workspace_layout.windows)} windows")

        # Ensure workspace exists and focus it
        await self._ensure_workspace(workspace_id)

        # Launch and restore each window
        for window in workspace_layout.windows:
            try:
                await self._restore_window(window, workspace_id, results)
            except Exception as e:
                logger.error(f"Failed to restore window {window.window_class}: {e}")
                results["windows_failed"] += 1
                results["errors"].append(f"{window.window_class}: {e}")

    async def _ensure_workspace(self, workspace_name: str) -> None:
        """
        Ensure workspace exists and focus it

        Args:
            workspace_name: Workspace name
        """
        await self._i3_command(f"workspace {workspace_name}")

    async def _restore_window(
        self,
        window: Window,
        workspace: str,
        results: Dict
    ) -> None:
        """
        Restore a single window (T036-T038)

        Args:
            window: Window to restore
            workspace: Target workspace
            results: Results dictionary
        """
        if not window.launch_command:
            logger.warning(f"No launch command for {window.window_class}, skipping")
            results["windows_failed"] += 1
            return

        # T036: Launch application
        logger.debug(f"Launching: {window.launch_command}")
        await self._launch_application(window.launch_command)
        results["windows_launched"] += 1

        # T037: Wait for window to appear (swallow)
        swallowed_window = await self._swallow_window(window.window_class)

        if not swallowed_window:
            logger.warning(f"Failed to swallow window: {window.window_class}")
            results["windows_failed"] += 1
            return

        results["windows_swallowed"] += 1

        # T038: Apply geometry and marks
        await self._apply_window_properties(swallowed_window, window, workspace)

    async def _launch_application(self, command: str) -> None:
        """
        Launch application (T036)

        Args:
            command: Command to execute
        """
        try:
            # Launch in background, detached from this process
            subprocess.Popen(
                command,
                shell=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            # Give app a moment to start
            await asyncio.sleep(0.5)

        except Exception as e:
            logger.error(f"Failed to launch '{command}': {e}")
            raise

    async def _swallow_window(self, window_class: str) -> Optional[any]:
        """
        Wait for window to appear (T037)

        Args:
            window_class: Expected window class

        Returns:
            Window object or None if timeout
        """
        logger.debug(f"Waiting for window: {window_class}")

        start_time = datetime.now()
        timeout = timedelta(seconds=self.swallow_timeout)

        while datetime.now() - start_time < timeout:
            # Get current windows
            tree = await self._get_tree()
            windows = self._find_windows_in_tree(tree)

            # Look for matching window class
            for win in windows:
                if hasattr(win, 'window_class') and win.window_class == window_class:
                    logger.debug(f"Window swallowed: {window_class}")
                    return win

            # Wait before checking again
            await asyncio.sleep(self.swallow_check_interval)

        logger.warning(f"Window swallow timeout: {window_class}")
        return None

    async def _apply_window_properties(
        self,
        i3_window: any,
        saved_window: Window,
        workspace: str
    ) -> None:
        """
        Apply saved properties to window (T038)

        Args:
            i3_window: i3 window object
            saved_window: Saved window properties
            workspace: Target workspace
        """
        window_id = i3_window.window if hasattr(i3_window, 'window') else i3_window.id

        # Move to correct workspace
        await self._i3_command(f'[id="{window_id}"] move to workspace {workspace}')

        # Apply floating state
        if saved_window.floating:
            await self._i3_command(f'[id="{window_id}"] floating enable')
        else:
            await self._i3_command(f'[id="{window_id}"] floating disable')

        # Apply geometry
        await self._i3_command(
            f'[id="{window_id}"] move position {saved_window.geometry.x} {saved_window.geometry.y}'
        )
        await self._i3_command(
            f'[id="{window_id}"] resize set {saved_window.geometry.width} {saved_window.geometry.height}'
        )

        # Apply marks
        for mark in saved_window.marks:
            await self._i3_command(f'[id="{window_id}"] mark --add {mark}')

        logger.debug(f"Applied properties to window: {saved_window.window_class}")

    def _find_windows_in_tree(self, tree) -> List:
        """Find all windows in tree"""
        windows = []

        def traverse(node):
            if hasattr(node, 'window') and node.window and node.window > 0:
                windows.append(node)
            if hasattr(node, 'nodes'):
                for child in node.nodes:
                    traverse(child)
            if hasattr(node, 'floating_nodes'):
                for child in node.floating_nodes:
                    traverse(child)

        traverse(tree)
        return windows

    async def _get_tree(self):
        """Get i3 tree"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.get_tree()
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'get_tree'):
                return self.i3.get_tree()
            else:
                return await self.i3.get_tree()

    async def _get_outputs(self):
        """Get i3 outputs"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.get_outputs()
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'get_outputs'):
                return self.i3.get_outputs()
            else:
                return await self.i3.get_outputs()

    async def _i3_command(self, command: str):
        """Execute i3 command"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.command(command)
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'command'):
                return self.i3.command(command)
            else:
                return await self.i3.command(command)


async def restore_layout(
    i3_connection,
    name: str,
    project: str = "global",
    adapt_monitors: bool = True,
) -> Dict[str, any]:
    """
    Convenience function to restore layout

    Args:
        i3_connection: i3ipc connection
        name: Layout name
        project: Project name
        adapt_monitors: Adapt to current monitors

    Returns:
        Restoration results dictionary
    """
    # Load layout
    snapshot = load_layout(name, project)
    if not snapshot:
        raise ValueError(f"Layout not found: {name} (project: {project})")

    # Restore
    restore = LayoutRestore(i3_connection)
    return await restore.restore_layout(snapshot, adapt_monitors=adapt_monitors)
