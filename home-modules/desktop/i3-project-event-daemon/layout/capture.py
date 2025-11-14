"""
Layout Capture Module

Feature 030: Production Readiness
Task T030: Capture current layout via i3 GET_TREE

Captures complete window layout from i3 including:
- Window hierarchy (outputs → workspaces → windows)
- Window geometry and properties
- Window marks and project associations
- Monitor configuration
- Terminal working directories (Feature 074: T036-T037)
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
    from ..services.terminal_cwd import TerminalCwdTracker  # Feature 074: T036
except ImportError:
    from models import (
        LayoutSnapshot, WorkspaceLayout, Window, WindowGeometry,
        Monitor, MonitorConfiguration
    )
    from launch_commands import discover_launch_command
    # Services not available in standalone mode
    TerminalCwdTracker = None

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

        # Feature 074: Session Management - Terminal CWD tracking (T036)
        self.terminal_cwd_tracker = TerminalCwdTracker() if TerminalCwdTracker else None
        if self.terminal_cwd_tracker:
            logger.debug("Initialized TerminalCwdTracker for layout capture")

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

        # Capture workspace layouts (Feature 074: T037 - async for terminal cwd capture)
        workspace_layouts = await self._capture_workspace_layouts(tree, workspaces, outputs)

        # Feature 074: Capture focused workspace (REQUIRED field - no Optional)
        focused_workspace = self._get_focused_workspace(tree)
        # Fallback to 1 if no focused workspace found
        if focused_workspace is None:
            logger.warning("No focused workspace found, defaulting to 1")
            focused_workspace = 1

        # Create snapshot
        snapshot = LayoutSnapshot(
            name=name,
            project=project or "global",
            created_at=datetime.now(),
            monitor_config=monitor_config,
            workspace_layouts=workspace_layouts,
            focused_workspace=focused_workspace,  # Feature 074: REQUIRED field
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

    async def _capture_workspace_layouts(
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

            # Feature 074 T067 (US4): Detect focused window in workspace
            focused_window_id = self._find_focused_window_in_workspace(ws_node)

            # Capture windows in this workspace (Feature 074: T037 - async for terminal cwd)
            windows = await self._capture_windows_in_workspace(ws_node, focused_window_id)

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

    def _find_focused_window_in_workspace(self, workspace_node) -> Optional[int]:
        """
        Find the focused window ID in a workspace (Feature 074 T067, US4)

        Args:
            workspace_node: Workspace tree node

        Returns:
            Window ID (node.id) of focused window, or None if no focus
        """
        # Recursively search for the node with focused=True
        def find_focused_recursive(node):
            if hasattr(node, 'focused') and node.focused:
                # If this is a window node (has window/id), return its ID
                if hasattr(node, 'id'):
                    return node.id

            # Check children
            if hasattr(node, 'nodes') and node.nodes:
                for child in node.nodes:
                    result = find_focused_recursive(child)
                    if result:
                        return result

            # Check floating nodes
            if hasattr(node, 'floating_nodes') and node.floating_nodes:
                for child in node.floating_nodes:
                    result = find_focused_recursive(child)
                    if result:
                        return result

            return None

        focused_id = find_focused_recursive(workspace_node)
        if focused_id:
            logger.debug(f"Found focused window in workspace {workspace_node.name}: {focused_id}")
        return focused_id

    def _get_focused_workspace(self, tree) -> Optional[int]:
        """
        Find the currently focused workspace number (Feature 074 - REQUIRED field)

        Args:
            tree: i3 window tree

        Returns:
            Workspace number (1-70) or None if no focused workspace found
        """
        def find_focused_workspace_recursive(node):
            # Check if this is a workspace node with focused=True
            if hasattr(node, 'type') and node.type == 'workspace':
                if hasattr(node, 'focused') and node.focused:
                    # Extract workspace number from name like "1" or "1:terminal"
                    try:
                        ws_num = int(node.name.split(':')[0])
                        return ws_num
                    except (ValueError, IndexError, AttributeError):
                        return None

            # Check children
            if hasattr(node, 'nodes') and node.nodes:
                for child in node.nodes:
                    result = find_focused_workspace_recursive(child)
                    if result:
                        return result

            # Check floating nodes
            if hasattr(node, 'floating_nodes') and node.floating_nodes:
                for child in node.floating_nodes:
                    result = find_focused_workspace_recursive(child)
                    if result:
                        return result

            return None

        focused_ws = find_focused_workspace_recursive(tree)
        if focused_ws:
            logger.debug(f"Found focused workspace: {focused_ws}")
        else:
            logger.warning("No focused workspace found in tree")
        return focused_ws

    async def _capture_windows_in_workspace(self, workspace_node, focused_window_id: Optional[int] = None) -> List:
        """
        Capture all windows in a workspace

        Args:
            workspace_node: Workspace tree node
            focused_window_id: ID of focused window in this workspace (Feature 074 T068, US4)

        Returns:
            List of WindowPlaceholder objects for layout restoration
        """
        windows = []

        # Find all leaf nodes (actual windows)
        leaf_nodes = self._find_leaf_nodes(workspace_node)

        for node in leaf_nodes:
            # Skip nodes without window_class/app_id (containers, etc.)
            # Sway uses app_id, i3 uses window_class
            window_class = getattr(node, 'window_class', None) or getattr(node, 'app_id', None)
            if not window_class:
                continue

            # Create Window object (Feature 074: T037 - async for terminal cwd capture)
            # Feature 074 T068 (US4): Pass focused status
            is_focused = (focused_window_id is not None and hasattr(node, 'id') and node.id == focused_window_id)
            window = await self._create_window_from_node(node, is_focused=is_focused)
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

        # If node has window property, it's a leaf (i3/X11)
        # In Sway, windows have pid and app_id instead of window ID
        is_leaf = False
        if hasattr(node, 'window') and node.window and node.window > 0:
            is_leaf = True
        elif hasattr(node, 'pid') and node.pid and (hasattr(node, 'app_id') or hasattr(node, 'window_class')):
            # Sway: has pid and either app_id or window_class
            is_leaf = True

        if is_leaf:
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

    async def _create_window_from_node(self, node, is_focused: bool = False):
        """
        Create WindowPlaceholder object from i3 tree node

        Args:
            node: i3 window node
            is_focused: Whether this window is focused in its workspace (Feature 074 T068, US4)

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
            # Sway uses app_id, i3 uses window_class
            window_class = getattr(node, 'window_class', None) or getattr(node, 'app_id', None) or "unknown"
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

            # Feature 074: launch_command is no longer required - we use AppLauncher with app_registry_name
            # Just log a debug message if not found, but don't skip the window
            if not launch_command:
                logger.debug(f"No launch command discovered for {window_class} (will use AppLauncher for restoration)")

            # Feature 074: Session Management - Capture terminal working directory (T037, US2)
            # REQUIRED field - use Path() for non-terminals or failed captures
            cwd = Path()  # Default to empty Path (sentinel value)
            if self.terminal_cwd_tracker and pid:
                # Check if this is a terminal window
                if self.terminal_cwd_tracker.is_terminal_window(window_class):
                    try:
                        terminal_cwd = await self.terminal_cwd_tracker.get_terminal_cwd(pid)
                        if terminal_cwd:
                            cwd = terminal_cwd
                            logger.debug(f"Captured terminal cwd for {window_class} (PID {pid}): {cwd}")
                        else:
                            logger.debug(f"Could not capture cwd for terminal {window_class} (PID {pid}), using Path()")
                    except Exception as e:
                        logger.warning(f"Error capturing terminal cwd for PID {pid}: {e}, using Path()")
                        # Keep cwd = Path()

            # Feature 074: Session Management - Capture app registry name from I3PM_APP_NAME (T037A, Feature 057 integration)
            # REQUIRED field - use "unknown" for manual launches or failed captures
            app_registry_name = "unknown"  # Default sentinel value
            if pid:
                try:
                    environ_path = Path(f"/proc/{pid}/environ")
                    if environ_path.exists():
                        # Read environment variables (null-separated)
                        environ_data = environ_path.read_bytes()
                        environ_dict = {}
                        for entry in environ_data.split(b'\0'):
                            if b'=' in entry:
                                key, value = entry.split(b'=', 1)
                                environ_dict[key.decode('utf-8', errors='ignore')] = value.decode('utf-8', errors='ignore')

                        # Extract I3PM_APP_NAME
                        captured_app_name = environ_dict.get('I3PM_APP_NAME')
                        if captured_app_name and captured_app_name.strip():
                            app_registry_name = captured_app_name
                            logger.debug(f"Captured I3PM_APP_NAME for {window_class} (PID {pid}): {app_registry_name}")
                        else:
                            logger.debug(f"No I3PM_APP_NAME found for {window_class} (PID {pid}), using 'unknown'")

                except Exception as e:
                    logger.debug(f"Could not read environ for PID {pid}: {e}, using 'unknown'")
                    # Keep app_registry_name = "unknown"

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
                cwd=cwd,  # Feature 074: T037 - Terminal working directory (REQUIRED)
                app_registry_name=app_registry_name,  # Feature 074: T037A - App registry name (REQUIRED)
                focused=is_focused,  # Feature 074: T068 - Focused window per workspace (REQUIRED)
                restoration_mark="i3pm-restore-00000000",  # Feature 074: Placeholder - will be replaced during restore (REQUIRED)
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
