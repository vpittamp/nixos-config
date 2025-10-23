"""
Layout Capture Module

Feature 030: Production Readiness
Task T030: Capture current layout via i3 GET_TREE

Captures complete window layout from i3 including:
- Window hierarchy (outputs → workspaces → windows)
- Window geometry and properties
- Window marks and project associations
- Monitor configuration
"""

import logging
from typing import List, Optional, Dict, Any
from datetime import datetime
from pathlib import Path

try:
    from .models import (
        LayoutSnapshot, WorkspaceLayout, Window, WindowGeometry,
        Monitor, MonitorConfiguration
    )
    from .launch_commands import discover_launch_command
except ImportError:
    from models import (
        LayoutSnapshot, WorkspaceLayout, Window, WindowGeometry,
        Monitor, MonitorConfiguration
    )
    from launch_commands import discover_launch_command

logger = logging.getLogger(__name__)


class LayoutCapture:
    """
    Captures window layout from i3

    Queries i3 IPC for:
    - Window tree (GET_TREE)
    - Workspace list (GET_WORKSPACES)
    - Output/monitor list (GET_OUTPUTS)

    Converts to LayoutSnapshot model for persistence.
    """

    def __init__(self, i3_connection):
        """
        Initialize layout capture

        Args:
            i3_connection: i3ipc connection instance
        """
        self.i3 = i3_connection

    async def capture_current_layout(
        self,
        name: str,
        project: Optional[str] = None,
    ) -> LayoutSnapshot:
        """
        Capture current window layout from i3

        Args:
            name: Name for this layout snapshot
            project: Associated project name (optional)

        Returns:
            LayoutSnapshot with complete layout data
        """
        logger.info(f"Capturing layout snapshot: {name}")

        # Query i3 for current state
        tree = await self._get_tree()
        workspaces = await self._get_workspaces()
        outputs = await self._get_outputs()

        # Capture monitor configuration
        monitor_config = self._capture_monitor_config(outputs)

        # Capture workspace layouts
        workspace_layouts = self._capture_workspace_layouts(tree, workspaces, outputs)

        # Create snapshot
        snapshot = LayoutSnapshot(
            name=name,
            project=project or "global",
            created_at=datetime.now(),
            monitor_config=monitor_config,
            workspace_layouts=workspace_layouts,
            metadata={
                "total_windows": sum(len(ws.windows) for ws in workspace_layouts),
                "total_workspaces": len(workspace_layouts),
                "total_monitors": len(monitor_config.monitors),
                "capture_timestamp": datetime.now().isoformat(),
            }
        )

        logger.info(
            f"Captured layout: {len(workspace_layouts)} workspaces, "
            f"{snapshot.metadata['total_windows']} windows"
        )

        return snapshot

    async def _get_tree(self):
        """Get i3 window tree"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.get_tree()
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'get_tree'):
                # Sync i3ipc
                return self.i3.get_tree()
            else:
                # Async i3ipc
                return await self.i3.get_tree()

    async def _get_workspaces(self):
        """Get i3 workspace list"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.get_workspaces()
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'get_workspaces'):
                # Sync i3ipc
                return self.i3.get_workspaces()
            else:
                # Async i3ipc
                return await self.i3.get_workspaces()

    async def _get_outputs(self):
        """Get i3 output list"""
        # ResilientI3Connection wrapper - access .conn for actual i3ipc connection
        if hasattr(self.i3, 'conn') and self.i3.conn:
            return await self.i3.conn.get_outputs()
        else:
            # Direct i3ipc connection (fallback for testing)
            if hasattr(self.i3, 'get_outputs'):
                # Sync i3ipc
                return self.i3.get_outputs()
            else:
                # Async i3ipc
                return await self.i3.get_outputs()

    def _capture_monitor_config(self, outputs: List) -> MonitorConfiguration:
        """
        Capture monitor configuration from i3 outputs

        Args:
            outputs: List of i3 output objects

        Returns:
            MonitorConfiguration with all active monitors
        """
        monitors = []

        for output in outputs:
            # Skip inactive outputs
            if not getattr(output, 'active', True):
                continue

            # Skip special outputs
            if output.name in ['xroot', '__i3']:
                continue

            # Extract rect values (support both dict and object access)
            rect = output.rect
            if hasattr(rect, '__getitem__'):
                width, height, x, y = rect['width'], rect['height'], rect['x'], rect['y']
            else:
                width, height, x, y = rect.width, rect.height, rect.x, rect.y

            from .models import Resolution, Position

            monitor = Monitor(
                name=output.name,
                active=getattr(output, 'active', True),
                primary=getattr(output, 'primary', False),
                current_workspace=getattr(output, 'current_workspace', None),
                resolution=Resolution(width=width, height=height),
                position=Position(x=x, y=y),
            )
            monitors.append(monitor)

        # Build workspace assignments from current monitor states
        workspace_assignments = {}
        for output in outputs:
            if not getattr(output, 'active', True):
                continue
            if output.name in ['xroot', '__i3']:
                continue
            # Get current workspace on this output (if any)
            current_ws = getattr(output, 'current_workspace', None)
            if current_ws:
                # Extract workspace number from name like "1" or "1:terminal"
                try:
                    ws_num = int(current_ws.split(':')[0])
                    workspace_assignments[ws_num] = output.name
                except (ValueError, IndexError):
                    pass

        # Generate a name based on number of monitors
        config_name = f"{len(monitors)}-monitor-config"

        return MonitorConfiguration(
            name=config_name,
            monitors=monitors,
            workspace_assignments=workspace_assignments
        )

    def _capture_workspace_layouts(
        self,
        tree,
        workspaces: List,
        outputs: List
    ) -> List[WorkspaceLayout]:
        """
        Capture layout for each workspace

        Args:
            tree: i3 window tree
            workspaces: List of workspace objects
            outputs: List of output objects

        Returns:
            List of WorkspaceLayout objects
        """
        workspace_layouts = []

        # Build workspace -> output mapping
        ws_to_output = {}
        for ws in workspaces:
            ws_to_output[ws.name] = ws.output

        # Find all workspace nodes in tree
        workspace_nodes = self._find_workspaces_in_tree(tree)

        for ws_node in workspace_nodes:
            ws_name = ws_node.name

            # Get output for this workspace
            output_name = ws_to_output.get(ws_name, "unknown")

            # Parse workspace number and name (format: "1" or "1:terminal")
            try:
                ws_parts = ws_name.split(':', 1)
                ws_num = int(ws_parts[0])
                ws_display_name = ws_parts[1] if len(ws_parts) > 1 else ""
            except (ValueError, IndexError):
                logger.warning(f"Skipping workspace with invalid name: {ws_name}")
                continue

            # Capture windows in this workspace
            windows = self._capture_windows_in_workspace(ws_node)

            # Get layout mode from workspace node
            layout_mode_str = getattr(ws_node, 'layout', 'splith')
            from .models import LayoutMode
            try:
                layout_mode = LayoutMode(layout_mode_str)
            except ValueError:
                layout_mode = LayoutMode.SPLITH

            # Include all workspaces (even empty ones for MVP)
            layout = WorkspaceLayout(
                workspace_num=ws_num,
                workspace_name=ws_display_name,
                output=output_name,
                layout_mode=layout_mode,
                windows=windows,
            )
            workspace_layouts.append(layout)

        return workspace_layouts

    def _find_workspaces_in_tree(self, node, workspaces=None) -> List:
        """
        Recursively find all workspace nodes in tree

        Args:
            node: Current tree node
            workspaces: Accumulated workspace list

        Returns:
            List of workspace nodes
        """
        if workspaces is None:
            workspaces = []

        # Check if this node is a workspace
        node_type = getattr(node, 'type', None)
        if node_type == 'workspace':
            workspaces.append(node)

        # Recurse into children
        if hasattr(node, 'nodes') and node.nodes:
            for child in node.nodes:
                self._find_workspaces_in_tree(child, workspaces)

        # Also check floating nodes
        if hasattr(node, 'floating_nodes') and node.floating_nodes:
            for child in node.floating_nodes:
                self._find_workspaces_in_tree(child, workspaces)

        return workspaces

    def _capture_windows_in_workspace(self, workspace_node) -> List:
        """
        Capture all windows in a workspace

        Args:
            workspace_node: Workspace tree node

        Returns:
            List of WindowPlaceholder objects for layout restoration
        """
        windows = []

        # Find all leaf nodes (actual windows)
        leaf_nodes = self._find_leaf_nodes(workspace_node)

        for node in leaf_nodes:
            # Skip nodes without window_class (containers, etc.)
            if not hasattr(node, 'window_class') or not node.window_class:
                continue

            # Create Window object
            window = self._create_window_from_node(node)
            if window:
                windows.append(window)

        return windows

    def _find_leaf_nodes(self, node, leaves=None) -> List:
        """
        Recursively find all leaf nodes (windows)

        Args:
            node: Current tree node
            leaves: Accumulated leaf list

        Returns:
            List of leaf nodes
        """
        if leaves is None:
            leaves = []

        # If node has window property, it's a leaf
        if hasattr(node, 'window') and node.window and node.window > 0:
            leaves.append(node)
            return leaves

        # Recurse into children
        if hasattr(node, 'nodes') and node.nodes:
            for child in node.nodes:
                self._find_leaf_nodes(child, leaves)

        # Also check floating nodes
        if hasattr(node, 'floating_nodes') and node.floating_nodes:
            for child in node.floating_nodes:
                self._find_leaf_nodes(child, leaves)

        return leaves

    def _create_window_from_node(self, node):
        """
        Create WindowPlaceholder object from i3 tree node

        Args:
            node: i3 window node

        Returns:
            WindowPlaceholder object or None if invalid
        """
        try:
            # Extract geometry
            rect = node.rect
            geometry = WindowGeometry(
                x=rect['x'] if hasattr(rect, '__getitem__') else rect.x,
                y=rect['y'] if hasattr(rect, '__getitem__') else rect.y,
                width=rect['width'] if hasattr(rect, '__getitem__') else rect.width,
                height=rect['height'] if hasattr(rect, '__getitem__') else rect.height,
            )

            # Extract marks
            marks = list(node.marks) if hasattr(node, 'marks') and node.marks else []

            # Determine if floating
            floating = False
            if hasattr(node, 'floating'):
                floating_str = node.floating
                floating = floating_str not in ['auto_off', 'no']

            # Discover launch command (T032, T033)
            window_class = getattr(node, 'window_class', None) or "unknown"
            window_instance = getattr(node, 'window_instance', None)
            if not window_instance:
                window_instance = window_class.lower() if window_class != "unknown" else None
            pid = getattr(node, 'pid', None)
            title = getattr(node, 'name', '')

            launch_command = discover_launch_command(
                window_class=window_class,
                window_instance=window_instance,
                pid=pid,
            )

            # If no launch command could be discovered, skip this window
            if not launch_command:
                logger.warning(f"Could not discover launch command for {window_class}")
                return None

            # Create WindowPlaceholder object for restoration
            from .models import WindowPlaceholder
            placeholder = WindowPlaceholder(
                window_class=window_class if window_class != "unknown" else None,
                instance=window_instance,
                title_pattern=title if title else None,
                launch_command=launch_command,
                geometry=geometry,
                marks=marks,
                floating=floating,
            )

            return placeholder

        except Exception as e:
            logger.warning(f"Failed to create window placeholder from node: {e}")
            return None


async def capture_layout(
    i3_connection,
    name: str,
    project: Optional[str] = None,
) -> LayoutSnapshot:
    """
    Convenience function to capture current layout

    Args:
        i3_connection: i3ipc connection
        name: Layout snapshot name
        project: Associated project name

    Returns:
        LayoutSnapshot
    """
    capture = LayoutCapture(i3_connection)
    return await capture.capture_current_layout(name=name, project=project)
