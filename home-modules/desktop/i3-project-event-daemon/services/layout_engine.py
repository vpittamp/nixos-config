"""
Layout capture and restore engine for window management.

Feature 058: Python Backend Consolidation - User Story 2
Provides layout operations using direct i3ipc.aio library calls.
"""

import logging
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
import os

from ..models.layout import Layout, WindowSnapshot
from ..window_environment_bridge import get_window_app_info

logger = logging.getLogger(__name__)


class LayoutError(Exception):
    """Layout operation error."""
    pass


class LayoutEngine:
    """Service for capturing and restoring window layouts."""

    def __init__(self, i3_connection, config_dir: Optional[Path] = None):
        """
        Initialize layout engine.

        Args:
            i3_connection: ResilientI3Connection instance for i3 IPC queries
            config_dir: Base configuration directory (defaults to ~/.config/i3)
        """
        self.i3_connection = i3_connection

        # Determine config directory
        if config_dir is None:
            home = Path(os.environ.get("HOME", "/home/user"))
            config_dir = home / ".config" / "i3"

        self.layouts_dir = config_dir / "layouts"
        self.layouts_dir.mkdir(parents=True, exist_ok=True)

    def _get_layout_path(self, project_name: str, layout_name: Optional[str] = None) -> Path:
        """Get path to layout file."""
        name = layout_name or project_name
        return self.layouts_dir / f"{project_name}-{name}.json"

    async def capture_layout(
        self,
        project_name: str,
        layout_name: Optional[str] = None
    ) -> Tuple[Layout, List[str]]:
        """
        Capture current window layout.

        Args:
            project_name: Project to save layout for
            layout_name: Custom layout name (defaults to project_name)

        Returns:
            Tuple of (Layout object, list of warning messages)

        Raises:
            LayoutError: If i3 IPC query fails or no windows found
        """
        warnings = []

        try:
            # Query i3 window tree via i3ipc
            if not self.i3_connection or not self.i3_connection.is_connected:
                raise LayoutError("i3 IPC connection not available")

            tree = await self.i3_connection.conn.get_tree()

            # Extract all leaf windows
            all_windows = self._extract_windows(tree)
            logger.info(f"Found {len(all_windows)} total windows in tree")

            # Capture snapshots with environment data
            snapshots: List[WindowSnapshot] = []

            for window in all_windows:
                # Skip windows without valid window ID
                if not window.window or window.window <= 0:
                    continue

                # Get window environment via bridge
                app_info = await get_window_app_info(window)

                if not app_info:
                    # No I3PM environment - skip (likely global or non-registry app)
                    logger.debug(
                        f"Skipping window {window.id} ({window.window_class}) - "
                        f"no I3PM environment"
                    )
                    continue

                app_id = app_info.get("app_id")
                app_name = app_info.get("app_name")

                if not app_id or not app_name:
                    warnings.append(
                        f"Window {window.id} missing app_id or app_name in environment"
                    )
                    continue

                # Get workspace info
                workspace = window.workspace()
                workspace_num = workspace.num if workspace else 1
                output_name = workspace.ipc_data.get('output') if workspace else "unknown"

                # Get window geometry
                rect = window.rect
                is_floating = window.floating not in ('auto_off', 'user_off')

                # Create snapshot
                snapshot = WindowSnapshot(
                    window_id=window.id,
                    app_id=app_id,
                    app_name=app_name,
                    window_class=window.window_class or "",
                    title=window.name or "",
                    workspace=workspace_num,
                    output=output_name,
                    rect={
                        'x': rect.x,
                        'y': rect.y,
                        'width': rect.width,
                        'height': rect.height
                    },
                    floating=is_floating,
                    focused=window.focused
                )

                snapshots.append(snapshot)
                logger.info(
                    f"Captured {app_name} ({app_id}) on workspace {workspace_num}"
                )

            if not snapshots:
                raise LayoutError("No windows with I3PM environment found to capture")

            # Create layout object
            layout = Layout(
                project_name=project_name,
                layout_name=layout_name or project_name,
                timestamp=datetime.now(),
                windows=snapshots
            )

            logger.info(
                f"Layout captured: {layout.project_name}/{layout.layout_name} "
                f"with {len(snapshots)} windows"
            )

            return layout, warnings

        except Exception as e:
            logger.error(f"Failed to capture layout: {e}", exc_info=True)
            raise LayoutError(f"Layout capture failed: {e}")

    def _extract_windows(self, node, workspace_num: Optional[int] = None) -> List[Any]:
        """
        Recursively extract leaf windows from i3 tree.

        Args:
            node: i3ipc tree node
            workspace_num: Current workspace number (tracked during traversal)

        Returns:
            List of window containers
        """
        windows = []

        # Track workspace number
        if node.type == "workspace":
            workspace_num = node.num

        # Check if this is a leaf window
        if node.window and node.window > 0:
            windows.append(node)

        # Recursively process children
        if hasattr(node, 'nodes'):
            for child in node.nodes:
                windows.extend(self._extract_windows(child, workspace_num))

        if hasattr(node, 'floating_nodes'):
            for child in node.floating_nodes:
                windows.extend(self._extract_windows(child, workspace_num))

        return windows

    async def restore_layout(
        self,
        project_name: str,
        layout_name: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Restore windows to saved layout positions.

        Args:
            project_name: Project to restore layout for
            layout_name: Layout name (defaults to project_name)

        Returns:
            Dictionary with:
                - restored: Number of windows successfully restored
                - missing: List of windows that couldn't be matched
                - total: Total windows in layout

        Raises:
            LayoutError: If layout file not found or restoration fails
        """
        # Load layout from file
        layout_path = self._get_layout_path(project_name, layout_name)

        try:
            layout = Layout.load_from_file(layout_path)
        except FileNotFoundError:
            raise LayoutError(
                f"Layout '{layout_name or project_name}' not found for project '{project_name}'"
            )

        # Get current window tree
        if not self.i3_connection or not self.i3_connection.is_connected:
            raise LayoutError("i3 IPC connection not available")

        tree = await self.i3_connection.conn.get_tree()
        all_windows = self._extract_windows(tree)

        # Build map of current windows by app_id
        current_windows = {}
        for window in all_windows:
            app_info = await get_window_app_info(window)
            if app_info and app_info.get("app_id"):
                current_windows[app_info["app_id"]] = window

        # Restore each window in layout
        restored_count = 0
        missing_windows = []

        for snapshot in layout.windows:
            window = current_windows.get(snapshot.app_id)

            if not window:
                # Window not currently open
                missing_windows.append({
                    "app_id": snapshot.app_id,
                    "app_name": snapshot.app_name,
                    "workspace": snapshot.workspace
                })
                logger.warning(
                    f"Window not found for restore: {snapshot.app_name} ({snapshot.app_id})"
                )
                continue

            try:
                # Move to workspace
                await window.command(f"move to workspace number {snapshot.workspace}")

                # Restore floating state
                if snapshot.floating:
                    await window.command("floating enable")
                    # Restore geometry for floating windows
                    await window.command(
                        f"resize set {snapshot.rect['width']} {snapshot.rect['height']}"
                    )
                    await window.command(
                        f"move position {snapshot.rect['x']} {snapshot.rect['y']}"
                    )
                else:
                    await window.command("floating disable")

                # Restore focus if it was focused
                if snapshot.focused:
                    await window.command("focus")

                restored_count += 1
                logger.info(
                    f"Restored {snapshot.app_name} to workspace {snapshot.workspace}"
                )

            except Exception as e:
                logger.error(
                    f"Failed to restore window {snapshot.app_id}: {e}",
                    exc_info=True
                )
                missing_windows.append({
                    "app_id": snapshot.app_id,
                    "app_name": snapshot.app_name,
                    "workspace": snapshot.workspace,
                    "error": str(e)
                })

        return {
            "restored": restored_count,
            "missing": missing_windows,
            "total": len(layout.windows)
        }

    def save_layout(self, layout: Layout) -> Path:
        """
        Save layout to file.

        Args:
            layout: Layout object to save

        Returns:
            Path to saved file

        Raises:
            LayoutError: If file write fails
        """
        layout_path = self._get_layout_path(layout.project_name, layout.layout_name)

        try:
            layout.save_to_file(layout_path)
            logger.info(f"Layout saved to {layout_path}")
            return layout_path
        except Exception as e:
            raise LayoutError(f"Failed to save layout: {e}")

    def list_layouts(self, project_name: str) -> List[Dict[str, Any]]:
        """
        List all saved layouts for a project.

        Args:
            project_name: Project to list layouts for

        Returns:
            List of layout metadata dictionaries
        """
        layouts = []
        pattern = f"{project_name}-*.json"

        for layout_file in self.layouts_dir.glob(pattern):
            try:
                layout = Layout.load_from_file(layout_file)
                layouts.append({
                    "layout_name": layout.layout_name,
                    "timestamp": layout.timestamp.isoformat(),
                    "windows_count": len(layout.windows),
                    "file_path": str(layout_file)
                })
            except Exception as e:
                logger.warning(f"Failed to load layout {layout_file}: {e}")
                continue

        return layouts

    def delete_layout(self, project_name: str, layout_name: str) -> bool:
        """
        Delete a saved layout.

        Args:
            project_name: Project name
            layout_name: Layout to delete

        Returns:
            True if deleted, False if not found

        Raises:
            LayoutError: If file deletion fails
        """
        layout_path = self._get_layout_path(project_name, layout_name)

        if not layout_path.exists():
            return False

        try:
            layout_path.unlink()
            logger.info(f"Deleted layout {project_name}/{layout_name}")
            return True
        except Exception as e:
            raise LayoutError(f"Failed to delete layout: {e}")
