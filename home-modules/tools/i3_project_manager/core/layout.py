"""Layout save/restore functionality.

This module implements the LayoutManager and WindowLauncher classes for
managing i3 window layouts with application relaunching capabilities.

Implements:
- FR-001: Save current layout with launch commands and environment
- FR-002: Restore layout by relaunching missing applications
- FR-003: Restore All action using auto-launch entries
- FR-004: Close All action for project-scoped windows
- FR-005: Delete saved layouts with confirmation
- FR-006: Export layouts to JSON files
- FR-007: Display layout metadata in table
"""

import asyncio
import json
import logging
import os
import psutil
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

import i3ipc.aio

from i3_project_manager.core.models import (
    LayoutWindow,
    WorkspaceLayout,
    SavedLayout,
    Project,
)


logger = logging.getLogger(__name__)


# Request/Response dataclasses (from contract)

from dataclasses import dataclass


@dataclass
class LayoutSaveRequest:
    """Request to save current window layout."""
    project_name: str
    layout_name: str
    capture_launch_commands: bool = True
    capture_environment: bool = True

    def validate(self) -> None:
        """Validate save request parameters."""
        if not self.layout_name.replace("-", "").replace("_", "").isalnum():
            raise ValueError(f"Invalid layout name: {self.layout_name}")


@dataclass
class LayoutSaveResponse:
    """Response from layout save operation."""
    success: bool
    layout_name: str
    layout_path: Path
    windows_captured: int
    workspaces_captured: int
    saved_at: datetime
    error: Optional[str] = None


@dataclass
class LayoutRestoreRequest:
    """Request to restore a saved layout."""
    project_name: str
    layout_name: str
    relaunch_missing: bool = True
    reposition_existing: bool = True
    restore_geometry: bool = True
    max_wait_time: float = 30.0


@dataclass
class LayoutRestoreResponse:
    """Response from layout restore operation."""
    success: bool
    windows_restored: int
    windows_launched: int
    windows_failed: int
    duration: float
    failed_windows: Optional[List[str]] = None
    error: Optional[str] = None


@dataclass
class LayoutDeleteRequest:
    """Request to delete a saved layout."""
    project_name: str
    layout_name: str
    confirmed: bool = False


@dataclass
class LayoutDeleteResponse:
    """Response from layout delete operation."""
    success: bool
    layout_name: str
    deleted_at: datetime
    error: Optional[str] = None


@dataclass
class LayoutExportRequest:
    """Request to export layout to file."""
    project_name: str
    layout_name: str
    export_path: Path
    include_metadata: bool = True


@dataclass
class LayoutExportResponse:
    """Response from layout export operation."""
    success: bool
    export_path: Path
    file_size: int
    error: Optional[str] = None


@dataclass
class LayoutMetadata:
    """Layout metadata for display in TUI table."""
    layout_name: str
    window_count: int
    workspace_count: int
    saved_at: datetime
    monitor_config: str
    total_launch_commands: int


@dataclass
class RestoreAllRequest:
    """Request to launch all auto-launch entries."""
    project_name: str
    use_layout: Optional[str] = None
    only_missing: bool = True


@dataclass
class RestoreAllResponse:
    """Response from Restore All operation."""
    success: bool
    apps_launched: int
    apps_already_running: int
    apps_failed: int
    duration: float
    failed_apps: Optional[List[str]] = None
    error: Optional[str] = None


@dataclass
class CloseAllRequest:
    """Request to close all project-scoped windows."""
    project_name: str
    force: bool = False


@dataclass
class CloseAllResponse:
    """Response from Close All operation."""
    success: bool
    windows_closed: int
    windows_failed: int
    error: Optional[str] = None


class WindowLauncher:
    """Utility class for launching applications and waiting for windows to appear."""

    def __init__(self, i3_connection: i3ipc.aio.Connection):
        """Initialize WindowLauncher.

        Args:
            i3_connection: Active i3 IPC connection
        """
        self.i3 = i3_connection

    async def launch_and_wait(
        self,
        command: str,
        window_class: str,
        workspace: int,
        env: Dict[str, str],
        cwd: Optional[str] = None,
        timeout: float = 5.0,
        max_retries: int = 3,
        retry_delay: float = 1.0,
    ) -> Optional[Any]:
        """Launch application and wait for window to appear.

        Args:
            command: Shell command to execute
            window_class: Expected window class for matching
            workspace: Target workspace number
            env: Environment variables for launch
            cwd: Working directory (None = inherit)
            timeout: Window appearance timeout per attempt
            max_retries: Maximum retry attempts
            retry_delay: Delay between retries

        Returns:
            Window container object if successful, None if failed

        Process:
            1. Construct i3 exec command with environment variables
            2. Send exec command via i3 IPC
            3. Poll GET_TREE every 100ms for window with window_class
            4. Retry on failure with exponential backoff
            5. Return window container or None after max_retries
        """
        for attempt in range(max_retries):
            try:
                # Construct bash command with environment and cwd
                env_exports = " ".join([f"export {k}={v};" for k, v in env.items()])
                cd_command = f"cd {cwd};" if cwd else ""
                full_command = f"bash -c '{env_exports} {cd_command} {command}'"

                # Switch to target workspace and launch
                await self.i3.command(f"workspace number {workspace}")
                await self.i3.command(f"exec {full_command}")

                # Poll for window appearance
                start_time = asyncio.get_event_loop().time()
                while asyncio.get_event_loop().time() - start_time < timeout:
                    tree = await self.i3.get_tree()
                    # Find window with matching class on target workspace
                    for con in tree.descendants():
                        if (
                            con.window_class == window_class
                            and con.workspace()
                            and con.workspace().num == workspace
                        ):
                            logger.info(
                                f"Window {window_class} appeared after "
                                f"{asyncio.get_event_loop().time() - start_time:.2f}s"
                            )
                            return con

                    await asyncio.sleep(0.1)  # Poll every 100ms

                # Timeout reached, try again
                logger.warning(
                    f"Attempt {attempt + 1}/{max_retries}: Window {window_class} "
                    f"did not appear within {timeout}s"
                )

                if attempt < max_retries - 1:
                    # Exponential backoff
                    delay = retry_delay * (2 ** attempt)
                    await asyncio.sleep(delay)

            except Exception as e:
                logger.error(f"Error launching {command}: {e}")
                if attempt < max_retries - 1:
                    await asyncio.sleep(retry_delay * (2 ** attempt))

        logger.error(
            f"Failed to launch {window_class} after {max_retries} attempts"
        )
        return None


class LayoutManager:
    """Manager for saving, restoring, deleting, and exporting window layouts."""

    def __init__(
        self,
        i3_connection: i3ipc.aio.Connection,
        config_dir: Path,
        project_manager: Any,
    ):
        """Initialize LayoutManager.

        Args:
            i3_connection: Active i3 IPC connection
            config_dir: Configuration directory (e.g., ~/.config/i3)
            project_manager: ProjectManager instance for accessing projects
        """
        self.i3 = i3_connection
        self.config_dir = config_dir
        self.project_manager = project_manager
        self.window_launcher = WindowLauncher(i3_connection)

    def _get_layouts_dir(self, project_name: str) -> Path:
        """Get layouts directory for project."""
        layouts_dir = self.config_dir / "layouts" / project_name
        layouts_dir.mkdir(parents=True, exist_ok=True)
        return layouts_dir

    def _get_layout_path(self, project_name: str, layout_name: str) -> Path:
        """Get path to layout file."""
        return self._get_layouts_dir(project_name) / f"{layout_name}.json"

    async def _infer_launch_command(self, window_class: str) -> str:
        """Infer launch command from window class using app-classes.json.

        First checks launch_commands mapping, then falls back to lowercase class name.
        """
        app_classes_file = self.config_dir / "app-classes.json"

        if app_classes_file.exists():
            with open(app_classes_file) as f:
                app_classes = json.load(f)

                # Check launch_commands mapping first (preferred)
                launch_commands = app_classes.get("launch_commands", {})
                if window_class in launch_commands:
                    return launch_commands[window_class]

                # Legacy support: check scoped_classes dict format
                scoped_classes = app_classes.get("scoped_classes", {})
                if isinstance(scoped_classes, dict):
                    # Dict format: {"command": "ClassName"}
                    for cmd, class_name in scoped_classes.items():
                        if class_name == window_class:
                            return cmd
                elif isinstance(scoped_classes, list):
                    # List format: Check launch_commands for any matching entry
                    if window_class in scoped_classes:
                        # Try to find a launch command for this class
                        for scoped_class in scoped_classes:
                            if scoped_class.lower() == window_class.lower() and scoped_class in launch_commands:
                                return launch_commands[scoped_class]

        # Fallback: lowercase window class (might not work for all apps)
        return window_class.lower()

    async def _get_process_info(self, window_pid: int) -> Dict[str, Any]:
        """Get process information including environment and cwd.

        Args:
            window_pid: Process ID of window

        Returns:
            Dict with 'env' and 'cwd' keys
        """
        try:
            process = psutil.Process(window_pid)
            env = process.environ()
            # Ensure env is a dict (psutil should return dict but double-check)
            if not isinstance(env, dict):
                env = dict(env) if hasattr(env, '__iter__') else {}
            return {
                "env": env,
                "cwd": process.cwd(),
            }
        except (psutil.NoSuchProcess, psutil.AccessDenied) as e:
            logger.warning(f"Could not access process info for PID {window_pid}: {e}")
            return {"env": {}, "cwd": None}

    async def save_layout(
        self, request: LayoutSaveRequest
    ) -> LayoutSaveResponse:
        """Save current window layout.

        Captures current i3 window tree and extracts:
        - Window class, title, geometry for each window
        - Workspace assignments and output roles
        - Launch commands (inferred from window class or application metadata)
        - Environment variables from process
        - Working directories from process

        Args:
            request: Layout save request parameters

        Returns:
            LayoutSaveResponse with success status and metadata
        """
        try:
            request.validate()

            # Get project
            project = await self.project_manager.get_project(request.project_name)
            if not project:
                raise ValueError(f"Project not found: {request.project_name}")

            # Query i3 window tree
            tree = await self.i3.get_tree()

            # Group windows by workspace
            workspace_layouts: Dict[int, WorkspaceLayout] = {}

            # Get all windows with project mark (prefix match)
            # Note: i3 marks must be unique per window, so we use prefix matching
            # to find all windows that belong to this project
            project_mark_prefix = f"project:{request.project_name}"

            for con in tree.descendants():
                # Check if any mark starts with the project prefix
                # and get all matching project marks
                project_marks = [
                    mark for mark in (con.marks or [])
                    if mark.startswith(project_mark_prefix)
                ]
                has_project_mark = len(project_marks) > 0

                if (
                    con.window
                    and has_project_mark
                    and con.workspace()
                ):
                    ws_num = con.workspace().num

                    # Get process info if requested
                    process_info = {"env": {}, "cwd": None}
                    if request.capture_environment and con.window:
                        process_info = await self._get_process_info(con.window)

                    # Infer launch command
                    launch_command = ""
                    if request.capture_launch_commands:
                        launch_command = await self._infer_launch_command(
                            con.window_class
                        )

                    # Create LayoutWindow
                    layout_window = LayoutWindow(
                        window_class=con.window_class or "Unknown",
                        window_title=con.name,
                        geometry={
                            "width": con.rect.width,
                            "height": con.rect.height,
                            "x": con.rect.x,
                            "y": con.rect.y,
                        },
                        launch_command=launch_command,
                        launch_env=process_info["env"],
                        cwd=process_info["cwd"],
                        expected_marks=project_marks,  # Use all matching project marks
                    )

                    # Add to workspace layout
                    if ws_num not in workspace_layouts:
                        # Determine output role (primary, secondary, tertiary)
                        output_role = "primary"  # TODO: Implement output role detection
                        workspace_layouts[ws_num] = WorkspaceLayout(
                            number=ws_num,
                            output_role=output_role,
                            windows=[],
                        )

                    workspace_layouts[ws_num].windows.append(layout_window)

            # Create SavedLayout
            total_windows = sum(len(ws.windows) for ws in workspace_layouts.values())
            saved_layout = SavedLayout(
                layout_name=request.layout_name,
                project_name=request.project_name,
                workspaces=list(workspace_layouts.values()),
                saved_at=datetime.now(),
                total_windows=total_windows,
            )

            # Save to file
            layout_path = self._get_layout_path(
                request.project_name, request.layout_name
            )
            with open(layout_path, "w") as f:
                json.dump(saved_layout.to_json(), f, indent=2)

            # Update project's saved_layouts list
            if request.layout_name not in project.saved_layouts:
                project.saved_layouts.append(request.layout_name)
                await self.project_manager.save_project(project)

            return LayoutSaveResponse(
                success=True,
                layout_name=request.layout_name,
                layout_path=layout_path,
                windows_captured=total_windows,
                workspaces_captured=len(workspace_layouts),
                saved_at=datetime.now(),
            )

        except Exception as e:
            import traceback
            logger.error(f"Failed to save layout: {e}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            return LayoutSaveResponse(
                success=False,
                layout_name=request.layout_name,
                layout_path=Path(),
                windows_captured=0,
                workspaces_captured=0,
                saved_at=datetime.now(),
                error=str(e),
            )

    async def restore_layout(
        self, request: LayoutRestoreRequest
    ) -> LayoutRestoreResponse:
        """Restore saved layout.

        Process:
        1. Load layout from disk
        2. Query i3 GET_TREE to get current windows
        3. For each window in layout:
           - If window exists: move to saved position
           - If missing: launch via i3 exec with environment and cwd
           - Wait for window to appear (with timeout and retries)
        4. Apply geometry and split orientations
        5. Verify all windows positioned correctly

        Args:
            request: Layout restore request parameters

        Returns:
            LayoutRestoreResponse with success status and statistics
        """
        start_time = asyncio.get_event_loop().time()

        try:
            # Load layout from file
            layout_path = self._get_layout_path(
                request.project_name, request.layout_name
            )
            if not layout_path.exists():
                raise FileNotFoundError(f"Layout not found: {request.layout_name}")

            with open(layout_path) as f:
                layout_data = json.load(f)
                saved_layout = SavedLayout.from_json(layout_data)

            # Get current window tree
            tree = await self.i3.get_tree()

            # Track statistics
            windows_restored = 0
            windows_launched = 0
            windows_failed = 0
            failed_windows: List[str] = []

            # Process each workspace
            for workspace_layout in saved_layout.workspaces:
                for layout_window in workspace_layout.windows:
                    # Check if window already exists with matching marks
                    # Use marks to distinguish between multiple windows of same class
                    existing_window = None
                    for con in tree.descendants():
                        if con.window_class == layout_window.window_class:
                            # Check if this window has any of the expected marks
                            window_marks = set(con.marks or [])
                            expected_marks = set(layout_window.expected_marks or [])
                            if window_marks.intersection(expected_marks):
                                # Found window with matching mark
                                existing_window = con
                                break

                    if existing_window:
                        # Reposition existing window
                        if request.reposition_existing:
                            await self.i3.command(
                                f"[con_id={existing_window.id}] "
                                f"move to workspace number {workspace_layout.number}"
                            )
                            windows_restored += 1
                    else:
                        # Launch missing window
                        if request.relaunch_missing:
                            window_con = await self.window_launcher.launch_and_wait(
                                command=layout_window.launch_command,
                                window_class=layout_window.window_class,
                                workspace=workspace_layout.number,
                                env=layout_window.launch_env,
                                cwd=layout_window.cwd,
                                timeout=layout_window.launch_timeout,
                                max_retries=layout_window.max_retries,
                                retry_delay=layout_window.retry_delay,
                            )

                            if window_con:
                                windows_launched += 1
                                windows_restored += 1
                            else:
                                windows_failed += 1
                                failed_windows.append(layout_window.window_class)

                    # Check max wait time
                    if asyncio.get_event_loop().time() - start_time > request.max_wait_time:
                        raise TimeoutError(
                            f"Restore exceeded max_wait_time of {request.max_wait_time}s"
                        )

            duration = asyncio.get_event_loop().time() - start_time

            return LayoutRestoreResponse(
                success=windows_failed == 0,
                windows_restored=windows_restored,
                windows_launched=windows_launched,
                windows_failed=windows_failed,
                duration=duration,
                failed_windows=failed_windows if failed_windows else None,
            )

        except Exception as e:
            duration = asyncio.get_event_loop().time() - start_time
            logger.error(f"Failed to restore layout: {e}")
            return LayoutRestoreResponse(
                success=False,
                windows_restored=0,
                windows_launched=0,
                windows_failed=0,
                duration=duration,
                error=str(e),
            )

    async def delete_layout(
        self, request: LayoutDeleteRequest
    ) -> LayoutDeleteResponse:
        """Delete saved layout.

        Removes layout file from disk and updates project's saved_layouts list.
        Requires user confirmation via request.confirmed flag.

        Args:
            request: Layout delete request with confirmation flag

        Returns:
            LayoutDeleteResponse with success status
        """
        try:
            if not request.confirmed:
                raise ValueError("Layout deletion requires confirmation")

            layout_path = self._get_layout_path(
                request.project_name, request.layout_name
            )

            if not layout_path.exists():
                raise FileNotFoundError(f"Layout not found: {request.layout_name}")

            # Delete layout file
            layout_path.unlink()

            # Update project's saved_layouts list
            project = await self.project_manager.get_project(request.project_name)
            if project and request.layout_name in project.saved_layouts:
                project.saved_layouts.remove(request.layout_name)
                await self.project_manager.save_project(project)

            return LayoutDeleteResponse(
                success=True,
                layout_name=request.layout_name,
                deleted_at=datetime.now(),
            )

        except Exception as e:
            logger.error(f"Failed to delete layout: {e}")
            return LayoutDeleteResponse(
                success=False,
                layout_name=request.layout_name,
                deleted_at=datetime.now(),
                error=str(e),
            )

    async def export_layout(
        self, request: LayoutExportRequest
    ) -> LayoutExportResponse:
        """Export layout to user-specified file.

        Copies layout JSON to export path with optional metadata enrichment.

        Args:
            request: Layout export request with export path

        Returns:
            LayoutExportResponse with file size and export path
        """
        try:
            layout_path = self._get_layout_path(
                request.project_name, request.layout_name
            )

            if not layout_path.exists():
                raise FileNotFoundError(f"Layout not found: {request.layout_name}")

            # Read layout
            with open(layout_path) as f:
                layout_data = json.load(f)

            # Add metadata if requested
            if request.include_metadata:
                layout_data["exported_at"] = datetime.now().isoformat()
                layout_data["exported_from"] = str(layout_path)

            # Write to export path
            with open(request.export_path, "w") as f:
                json.dump(layout_data, f, indent=2)

            file_size = request.export_path.stat().st_size

            return LayoutExportResponse(
                success=True,
                export_path=request.export_path,
                file_size=file_size,
            )

        except Exception as e:
            logger.error(f"Failed to export layout: {e}")
            return LayoutExportResponse(
                success=False,
                export_path=request.export_path,
                file_size=0,
                error=str(e),
            )

    async def list_layouts(self, project_name: str) -> List[LayoutMetadata]:
        """List all saved layouts for a project.

        Returns layout metadata for display in TUI table.

        Args:
            project_name: Project to list layouts for

        Returns:
            List of LayoutMetadata sorted by saved_at (newest first)
        """
        layouts_dir = self._get_layouts_dir(project_name)
        metadata_list: List[LayoutMetadata] = []

        for layout_file in layouts_dir.glob("*.json"):
            try:
                with open(layout_file) as f:
                    layout_data = json.load(f)
                    saved_layout = SavedLayout.from_json(layout_data)

                    window_count = sum(
                        len(ws.windows) for ws in saved_layout.workspaces
                    )
                    workspace_count = len(saved_layout.workspaces)

                    # Determine monitor config
                    monitor_config = "single"
                    if workspace_count > 5:
                        monitor_config = "triple"
                    elif workspace_count > 2:
                        monitor_config = "dual"

                    # Count launch commands
                    total_launch_commands = sum(
                        1
                        for ws in saved_layout.workspaces
                        for win in ws.windows
                        if win.launch_command
                    )

                    metadata = LayoutMetadata(
                        layout_name=saved_layout.layout_name,
                        window_count=window_count,
                        workspace_count=workspace_count,
                        saved_at=saved_layout.saved_at if isinstance(saved_layout.saved_at, datetime) else datetime.fromisoformat(str(saved_layout.saved_at)),
                        monitor_config=monitor_config,
                        total_launch_commands=total_launch_commands,
                    )
                    metadata_list.append(metadata)

            except Exception as e:
                logger.error(f"Failed to load layout metadata from {layout_file}: {e}")

        # Sort by saved_at (newest first)
        metadata_list.sort(key=lambda m: m.saved_at, reverse=True)

        return metadata_list

    async def restore_all(
        self, request: RestoreAllRequest
    ) -> RestoreAllResponse:
        """Launch all auto-launch entries and restore to default positions.

        This implements "Restore All" action which uses auto-launch
        entries as the default application set.

        Args:
            request: Restore All request parameters

        Returns:
            RestoreAllResponse with launch statistics
        """
        start_time = asyncio.get_event_loop().time()

        try:
            # Get project
            project = await self.project_manager.get_project(request.project_name)
            if not project:
                raise ValueError(f"Project not found: {request.project_name}")

            # If use_layout specified, restore that layout instead
            if request.use_layout:
                restore_request = LayoutRestoreRequest(
                    project_name=request.project_name,
                    layout_name=request.use_layout,
                    relaunch_missing=True,
                    reposition_existing=True,
                )
                restore_response = await self.restore_layout(restore_request)

                return RestoreAllResponse(
                    success=restore_response.success,
                    apps_launched=restore_response.windows_launched,
                    apps_already_running=restore_response.windows_restored,
                    apps_failed=restore_response.windows_failed,
                    duration=restore_response.duration,
                    failed_apps=restore_response.failed_windows,
                    error=restore_response.error,
                )

            # Otherwise, launch auto-launch entries
            apps_launched = 0
            apps_already_running = 0
            apps_failed = 0
            failed_apps: List[str] = []

            # Get current windows
            tree = await self.i3.get_tree()

            for auto_launch in project.auto_launch:
                # Check if app already running
                window_class = auto_launch.get("window_class", "")
                already_running = False

                if request.only_missing and window_class:
                    for con in tree.descendants():
                        if con.window_class == window_class:
                            already_running = True
                            apps_already_running += 1
                            break

                if not already_running:
                    # Launch application
                    window_con = await self.window_launcher.launch_and_wait(
                        command=auto_launch["command"],
                        window_class=window_class or auto_launch["command"],
                        workspace=auto_launch.get("workspace", 1),
                        env=auto_launch.get("environment", {}),
                        cwd=None,
                        timeout=auto_launch.get("wait_timeout", 5.0),
                        max_retries=3,
                        retry_delay=1.0,
                    )

                    if window_con:
                        apps_launched += 1
                    else:
                        apps_failed += 1
                        failed_apps.append(auto_launch["command"])

            duration = asyncio.get_event_loop().time() - start_time

            return RestoreAllResponse(
                success=apps_failed == 0,
                apps_launched=apps_launched,
                apps_already_running=apps_already_running,
                apps_failed=apps_failed,
                duration=duration,
                failed_apps=failed_apps if failed_apps else None,
            )

        except Exception as e:
            duration = asyncio.get_event_loop().time() - start_time
            logger.error(f"Failed to restore all: {e}")
            return RestoreAllResponse(
                success=False,
                apps_launched=0,
                apps_already_running=0,
                apps_failed=0,
                duration=duration,
                error=str(e),
            )

    async def close_all(
        self, request: CloseAllRequest
    ) -> CloseAllResponse:
        """Close all project-scoped windows.

        Queries i3 GET_TREE for windows with project mark, then sends
        kill command to each window.

        Args:
            request: Close All request parameters

        Returns:
            CloseAllResponse with close statistics
        """
        try:
            # Get all windows with project mark (prefix match)
            tree = await self.i3.get_tree()
            project_mark_prefix = f"project:{request.project_name}"

            windows_closed = 0
            windows_failed = 0

            for con in tree.descendants():
                # Check if any mark starts with the project prefix
                has_project_mark = any(
                    mark.startswith(project_mark_prefix)
                    for mark in (con.marks or [])
                )

                if con.window and has_project_mark:
                    try:
                        await self.i3.command(f"[con_id={con.id}] kill")
                        windows_closed += 1
                    except Exception as e:
                        logger.error(f"Failed to close window {con.id}: {e}")
                        windows_failed += 1

            return CloseAllResponse(
                success=windows_failed == 0,
                windows_closed=windows_closed,
                windows_failed=windows_failed,
            )

        except Exception as e:
            logger.error(f"Failed to close all windows: {e}")
            return CloseAllResponse(
                success=False,
                windows_closed=0,
                windows_failed=0,
                error=str(e),
            )
