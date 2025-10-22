"""Layout Manager Contract - FR-001 through FR-008

API contract for layout save/restore/delete/export operations with application relaunching.

This contract defines the interface for the LayoutManager service that handles:
- Saving current window layouts with application launch configurations
- Restoring layouts by relaunching missing applications and repositioning windows
- Deleting layouts with user confirmation
- Exporting layouts to JSON files
- Managing auto-launch entries (default application set)
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Dict, Any
import asyncio


@dataclass
class LayoutSaveRequest:
    """Request to save current window layout."""
    project_name: str
    layout_name: str
    capture_launch_commands: bool = True  # Extract launch commands from running windows
    capture_environment: bool = True      # Capture environment variables

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
    relaunch_missing: bool = True         # Launch applications if not running
    reposition_existing: bool = True      # Move existing windows to saved positions
    restore_geometry: bool = True         # Apply saved window sizes
    max_wait_time: float = 30.0           # Maximum time to wait for all windows


@dataclass
class LayoutRestoreResponse:
    """Response from layout restore operation."""
    success: bool
    windows_restored: int
    windows_launched: int
    windows_failed: int
    duration: float                       # Time taken in seconds
    failed_windows: List[str] = None      # Window classes that failed to launch
    error: Optional[str] = None


@dataclass
class LayoutDeleteRequest:
    """Request to delete a saved layout."""
    project_name: str
    layout_name: str
    confirmed: bool = False               # User confirmation flag


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
    include_metadata: bool = True         # Include creation date, window count, etc.


@dataclass
class LayoutExportResponse:
    """Response from layout export operation."""
    success: bool
    export_path: Path
    file_size: int                        # Bytes
    error: Optional[str] = None


@dataclass
class LayoutMetadata:
    """Layout metadata for display in TUI table."""
    layout_name: str
    window_count: int
    workspace_count: int
    saved_at: datetime
    monitor_config: str                   # "single", "dual", "triple"
    total_launch_commands: int


@dataclass
class RestoreAllRequest:
    """Request to launch all auto-launch entries and restore to default positions.

    This is the "Restore All" action that uses auto-launch entries as the
    default application set (per clarification session).
    """
    project_name: str
    use_layout: Optional[str] = None      # If specified, restore to this layout
    only_missing: bool = True             # Only launch apps not already running


@dataclass
class RestoreAllResponse:
    """Response from Restore All operation."""
    success: bool
    apps_launched: int
    apps_already_running: int
    apps_failed: int
    duration: float
    failed_apps: List[str] = None
    error: Optional[str] = None


@dataclass
class CloseAllRequest:
    """Request to close all project-scoped windows."""
    project_name: str
    force: bool = False                   # Force close without confirmation dialogs


@dataclass
class CloseAllResponse:
    """Response from Close All operation."""
    success: bool
    windows_closed: int
    windows_failed: int
    error: Optional[str] = None


class ILayoutManager(ABC):
    """Abstract interface for layout management operations.

    Implements:
    - FR-001: Save current layout with launch commands and environment
    - FR-002: Restore layout by relaunching missing applications
    - FR-003: Restore All action using auto-launch entries
    - FR-004: Close All action for project-scoped windows
    - FR-005: Delete saved layouts with confirmation
    - FR-006: Export layouts to JSON files
    - FR-007: Display layout metadata in table
    - FR-008: Configure auto-launch entries
    """

    @abstractmethod
    async def save_layout(self, request: LayoutSaveRequest) -> LayoutSaveResponse:
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

        Raises:
            ValueError: If layout name invalid or project not found
            IOError: If unable to write layout file

        Performance:
            Must complete within 2 seconds (SC-001 constraint)
        """
        pass

    @abstractmethod
    async def restore_layout(self, request: LayoutRestoreRequest) -> LayoutRestoreResponse:
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

        Raises:
            FileNotFoundError: If layout file not found
            TimeoutError: If window launch exceeds max_wait_time

        Performance:
            Must complete within 2 seconds including relaunching (FR-002)
            Window polling: 100ms interval, 5s default timeout per window
        """
        pass

    @abstractmethod
    async def delete_layout(self, request: LayoutDeleteRequest) -> LayoutDeleteResponse:
        """Delete saved layout.

        Removes layout file from disk and updates project's saved_layouts list.
        Requires user confirmation via request.confirmed flag.

        Args:
            request: Layout delete request with confirmation flag

        Returns:
            LayoutDeleteResponse with success status

        Raises:
            ValueError: If confirmation not provided
            FileNotFoundError: If layout file not found
        """
        pass

    @abstractmethod
    async def export_layout(self, request: LayoutExportRequest) -> LayoutExportResponse:
        """Export layout to user-specified file.

        Copies layout JSON to export path with optional metadata enrichment.

        Args:
            request: Layout export request with export path

        Returns:
            LayoutExportResponse with file size and export path

        Raises:
            IOError: If unable to write to export path
            PermissionError: If export path not writable
        """
        pass

    @abstractmethod
    async def list_layouts(self, project_name: str) -> List[LayoutMetadata]:
        """List all saved layouts for a project.

        Returns layout metadata for display in TUI table (FR-007).

        Args:
            project_name: Project to list layouts for

        Returns:
            List of LayoutMetadata sorted by saved_at (newest first)
        """
        pass

    @abstractmethod
    async def restore_all(self, request: RestoreAllRequest) -> RestoreAllResponse:
        """Launch all auto-launch entries and restore to default positions.

        This implements "Restore All" action (FR-003) which uses auto-launch
        entries as the default application set.

        Args:
            request: Restore All request parameters

        Returns:
            RestoreAllResponse with launch statistics

        Performance:
            Must complete within reasonable time based on app count
            Uses auto-launch retry policy (3 attempts, exponential backoff)
        """
        pass

    @abstractmethod
    async def close_all(self, request: CloseAllRequest) -> CloseAllResponse:
        """Close all project-scoped windows.

        Queries i3 GET_TREE for windows with project mark, then sends
        kill command to each window.

        Args:
            request: Close All request parameters

        Returns:
            CloseAllResponse with close statistics
        """
        pass


class IWindowLauncher(ABC):
    """Abstract interface for launching applications and waiting for windows.

    Used internally by LayoutManager for application relaunching during
    layout restoration.
    """

    @abstractmethod
    async def launch_and_wait(
        self,
        command: str,
        window_class: str,
        workspace: int,
        env: Dict[str, str],
        cwd: Optional[str] = None,
        timeout: float = 5.0,
        max_retries: int = 3,
        retry_delay: float = 1.0
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
        pass


# Example usage in TUI screen

class LayoutManagerScreen:
    """Example TUI screen showing contract usage."""

    def __init__(self, layout_manager: ILayoutManager):
        self.layout_manager = layout_manager

    async def action_save_layout(self, layout_name: str, project_name: str):
        """Handle save layout action."""
        request = LayoutSaveRequest(
            project_name=project_name,
            layout_name=layout_name,
            capture_launch_commands=True,
            capture_environment=True
        )

        try:
            request.validate()
            response = await self.layout_manager.save_layout(request)

            if response.success:
                self.notify(
                    f"Layout '{response.layout_name}' saved with "
                    f"{response.windows_captured} windows",
                    severity="success"
                )
            else:
                self.notify(f"Failed to save layout: {response.error}", severity="error")
        except ValueError as e:
            self.notify(str(e), severity="error")

    async def action_restore_layout(self, layout_name: str, project_name: str):
        """Handle restore layout action."""
        request = LayoutRestoreRequest(
            project_name=project_name,
            layout_name=layout_name,
            relaunch_missing=True,
            reposition_existing=True
        )

        response = await self.layout_manager.restore_layout(request)

        if response.success:
            self.notify(
                f"Layout restored: {response.windows_restored} windows "
                f"({response.windows_launched} launched) in {response.duration:.1f}s",
                severity="success"
            )
        else:
            self.notify(
                f"Layout restore failed: {response.error}\n"
                f"Failed windows: {', '.join(response.failed_windows or [])}",
                severity="error"
            )
