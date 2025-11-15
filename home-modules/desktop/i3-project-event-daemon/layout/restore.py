"""
Layout Restoration Module

Feature 030: Production Readiness
Task T036: Launch applications with captured commands
Task T037: Implement window swallowing for layout restore
Task T038: Apply geometry and marks after swallow
Task T039: Detect current monitor configuration
Task T040: Adapt layout to different monitor setup
Feature 074: Session Management (T040-T041) - Terminal working directory restoration

Restores saved layouts by:
1. Launching applications
2. Waiting for windows to appear (swallowing)
3. Applying saved geometry and marks
4. Adapting to current monitor configuration
5. Restoring terminal working directories (Feature 074)
"""

import logging
import asyncio
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Set
from datetime import datetime, timedelta

try:
    from .models import LayoutSnapshot, Window, WorkspaceLayout, Monitor, Resolution, Position, RestoreCorrelation
    from .persistence import load_layout
    from .correlation import MarkBasedCorrelator  # Feature 074: T053, US3
    from ..services.terminal_cwd import TerminalCwdTracker  # Feature 074: T040
    from ..services.app_launcher import AppLauncher  # Feature 074: T055A, Feature 057 integration
except ImportError:
    from models import LayoutSnapshot, Window, WorkspaceLayout, Monitor, Resolution, Position, RestoreCorrelation
    from persistence import load_layout
    # Services not available in standalone mode
    TerminalCwdTracker = None
    MarkBasedCorrelator = None
    AppLauncher = None

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

    def __init__(self, i3_connection, project_directory: Optional[Path] = None, mark_manager=None):
        """
        Initialize layout restore

        Args:
            i3_connection: i3ipc connection instance
            project_directory: Project root directory for terminal cwd fallback (Feature 074)
            mark_manager: Optional MarkManager for Feature 076 mark-based detection
        """
        self.i3 = i3_connection
        self.swallow_timeout = 30.0  # seconds
        self.swallow_check_interval = 0.5  # seconds

        # Feature 074: Session Management - Terminal CWD restoration (T040)
        self.terminal_cwd_tracker = TerminalCwdTracker() if TerminalCwdTracker else None
        self.project_directory = project_directory
        if self.terminal_cwd_tracker:
            logger.debug("Initialized TerminalCwdTracker for layout restoration")

        # Feature 074: Session Management - Mark-based correlation for Sway (T053, US3)
        self.mark_correlator = MarkBasedCorrelator(i3_connection) if MarkBasedCorrelator else None
        if self.mark_correlator:
            logger.debug("Initialized MarkBasedCorrelator for Sway window restoration")

        # Feature 074: Session Management - Unified app launcher for wrapper-based restoration (T055A, Feature 057)
        self.app_launcher = AppLauncher() if AppLauncher else None

        # Feature 076: Mark-based app identification - idempotent restore (T021-T022, US2)
        self.mark_manager = mark_manager
        if self.mark_manager:
            logger.debug("Initialized MarkManager for mark-based window detection")
        if self.app_launcher:
            logger.debug("Initialized AppLauncher for wrapper-based window restoration")

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
            "windows_swallowed": 0,  # Deprecated - kept for backward compatibility
            "windows_failed": 0,
            "errors": [],
            "start_time": start_time.isoformat(),
            # Feature 074: Session Management - Mark-based correlation statistics (T057, US3)
            "windows_matched": 0,     # Windows successfully correlated
            "windows_timeout": 0,     # Windows that timed out
            "correlations": [],       # List of RestoreCorrelation objects
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

        # Feature 074 T069-T071 (US4): Restore focused window after all windows correlated
        await self._restore_workspace_focus(workspace_layout, results)

    async def _ensure_workspace(self, workspace_name: str) -> None:
        """
        Ensure workspace exists and focus it

        Args:
            workspace_name: Workspace name
        """
        await self._i3_command(f"workspace {workspace_name}")

    async def _restore_workspace_focus(self, workspace_layout: WorkspaceLayout, results: Dict) -> None:
        """
        Restore focused window in workspace (Feature 074 T069-T071, US4)

        Args:
            workspace_layout: Workspace layout containing windows
            results: Results dictionary containing correlations
        """
        # Find window with focused=True
        focused_window = None
        for window in workspace_layout.windows:
            if hasattr(window, 'focused') and window.focused:
                focused_window = window
                break

        if not focused_window:
            # T070: Fallback - focus first available window
            if workspace_layout.windows:
                logger.debug(f"No focused window marked, focusing first window in workspace {workspace_layout.workspace_num}")
                focused_window = workspace_layout.windows[0]
            else:
                logger.debug(f"No windows in workspace {workspace_layout.workspace_num}, skipping focus restoration")
                return

        # T069: Focus the window using its restoration mark
        restoration_mark = getattr(focused_window, 'restoration_mark', None)
        if restoration_mark:
            # Find the matched window ID from correlations
            window_id = None
            for correlation in results.get("correlations", []):
                if hasattr(correlation, 'restoration_mark') and correlation.restoration_mark == restoration_mark:
                    if correlation.status.value == "matched":
                        window_id = correlation.matched_window_id
                        break

            if window_id:
                try:
                    await self._i3_command(f"[con_id={window_id}] focus")
                    logger.debug(f"Focused window {window_id} in workspace {workspace_layout.workspace_num}")
                except Exception as e:
                    logger.warning(f"Failed to focus window {window_id}: {e}")
            else:
                logger.debug(f"Could not find matched window for focused placeholder in workspace {workspace_layout.workspace_num}")
        else:
            logger.debug(f"No restoration mark for focused window in workspace {workspace_layout.workspace_num}")

    async def _restore_window(
        self,
        window: Window,
        workspace: str,
        results: Dict
    ) -> None:
        """
        Restore a single window (T036-T038, Feature 074: T040, Feature 076: T021-T026)

        Args:
            window: Window to restore
            workspace: Target workspace
            results: Results dictionary
        """
        if not window.launch_command:
            logger.warning(f"No launch command for {window.window_class}, skipping")
            results["windows_failed"] += 1
            return

        # Feature 076 T021-T022, T025, T026: Check for existing window with saved marks (idempotent restore)
        if self.mark_manager and hasattr(window, 'marks_metadata') and window.marks_metadata:
            try:
                # Query for existing windows with matching app name
                from .models import WindowMarkQuery
                query = WindowMarkQuery(
                    app=window.marks_metadata.app,
                    project=window.marks_metadata.project,
                    workspace=int(window.marks_metadata.workspace) if window.marks_metadata.workspace else None
                )
                existing_windows = await self.mark_manager.find_windows(query)

                if existing_windows:
                    # Window already exists - skip launching (T026: logging for mark-based detection)
                    logger.info(
                        f"Feature 076: Window already exists with marks "
                        f"(app={window.marks_metadata.app}, project={window.marks_metadata.project}) "
                        f"- skipping launch (idempotent restore)"
                    )
                    # Track as already present (not counted as launched or failed)
                    if "windows_already_present" not in results:
                        results["windows_already_present"] = 0
                    results["windows_already_present"] += 1
                    return
                else:
                    # No existing window - proceed with launch (T026: logging)
                    logger.debug(
                        f"Feature 076: No existing window found with marks "
                        f"(app={window.marks_metadata.app}, project={window.marks_metadata.project}) "
                        f"- proceeding with launch"
                    )
            except Exception as e:
                # T024: Graceful fallback if mark detection fails
                logger.warning(f"Feature 076: Mark-based detection failed, falling back to launch: {e}")
        elif not hasattr(window, 'marks_metadata') or not window.marks_metadata:
            # T024, T026, T045: Backward compatibility - no marks saved, use old behavior
            logger.warning(
                f"Feature 076: No mark metadata in saved layout for {window.window_class}. "
                f"Layout restoration may be slower and less reliable. "
                f"Consider re-saving this layout with: i3pm layout save <name>"
            )

        # Feature 074: Session Management - Compute launch directory for terminals (T040, US2)
        # REQUIRED field - check for empty Path() sentinel value
        launch_cwd = None
        if self.terminal_cwd_tracker:
            # Check if this is a terminal window
            window_class = getattr(window, 'window_class', None)
            if window_class and self.terminal_cwd_tracker.is_terminal_window(window_class):
                # Use fallback chain: saved cwd → project directory → $HOME
                # window.cwd is REQUIRED (never None), use Path() as sentinel for "no cwd"
                saved_cwd = window.cwd if window.cwd != Path() else None
                launch_cwd = self.terminal_cwd_tracker.get_launch_cwd(
                    saved_cwd=saved_cwd,
                    project_directory=self.project_directory,
                    fallback_home=Path.home()
                )
                logger.debug(f"Terminal {window_class} will launch in: {launch_cwd}")

        # Feature 074: Session Management - Mark-based correlation ONLY (no swallow fallback)
        if not self.mark_correlator:
            logger.error("Mark-based correlator not available - cannot restore windows")
            results["windows_failed"] += 1
            return

        # Use mark-based correlation workflow (REQUIRED - no fallback)
        logger.debug(f"Launching with mark-based correlation: {window.launch_command}" + (f" (cwd={launch_cwd})" if launch_cwd else ""))

        # Generate mark and inject into environment
        mark = self.mark_correlator.generate_restoration_mark()
        window.restoration_mark = mark

        # Feature 074: Session Management - ALWAYS use AppLauncher (no fallback to direct launch)
        if not self.app_launcher:
            logger.error("AppLauncher not available - cannot restore windows")
            results["windows_failed"] += 1
            return

        # Launch via AppLauncher (wrapper system with I3PM_* injection)
        # app_registry_name is REQUIRED field (may be "unknown" for manual launches)
        logger.debug(f"Launching via AppLauncher: {window.app_registry_name} (mark: {mark})")
        process = await self.app_launcher.launch_app(
            app_name=window.app_registry_name,
            project=results.get("project", "global"),
            cwd=launch_cwd,
            restore_mark=mark
        )
        if not process:
            logger.error(f"AppLauncher failed to launch {window.app_registry_name}")
            results["windows_failed"] += 1
            return
        results["windows_launched"] += 1

        # Wait for window and correlate
        correlation = await self.mark_correlator.correlate_window(window, results.get("project", "global"), timeout=self.swallow_timeout)
        results["correlations"].append(correlation)

        # Update statistics based on correlation result (T056, T057)
        if correlation.status.value == "matched":
            results["windows_matched"] += 1
            results["windows_swallowed"] += 1  # Backward compatibility metric
            logger.info(f"Window correlation succeeded for {window.window_class}: window_id={correlation.matched_window_id}")
        elif correlation.status.value == "timeout":
            results["windows_timeout"] += 1
            results["windows_failed"] += 1
            logger.warning(f"Window correlation timed out for {window.window_class}: {correlation.error_message}")
        else:  # failed
            results["windows_failed"] += 1
            logger.error(f"Window correlation failed for {window.window_class}: {correlation.error_message}")

    async def _launch_application(self, command: str, cwd: Optional[Path] = None) -> None:
        """
        Launch application (T036, Feature 074: T041 - with optional cwd)

        Args:
            command: Command to execute
            cwd: Working directory for the process (Feature 074: Terminal CWD restoration)
        """
        try:
            # Feature 074: Session Management - Launch terminals in saved working directory (T041, US2)
            # Convert Path to string for subprocess.Popen
            cwd_str = str(cwd) if cwd else None

            # Launch in background, detached from this process
            subprocess.Popen(
                command,
                shell=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                cwd=cwd_str,  # Feature 074: T041 - Terminal working directory
            )
            # Give app a moment to start
            await asyncio.sleep(0.5)

        except Exception as e:
            logger.error(f"Failed to launch '{command}'" + (f" in {cwd}" if cwd else "") + f": {e}")
            raise

    async def _launch_application_with_env(self, command: str, env: dict, cwd: Optional[Path] = None) -> None:
        """
        Launch application with custom environment (Feature 074: T054, US3)

        Used by mark-based correlation to inject I3PM_RESTORE_MARK environment variable.

        Args:
            command: Command to execute
            env: Environment variables dictionary (includes I3PM_RESTORE_MARK)
            cwd: Working directory for the process (Feature 074: Terminal CWD restoration)
        """
        try:
            # Convert Path to string for subprocess.Popen
            cwd_str = str(cwd) if cwd else None

            # Launch in background with enhanced environment
            subprocess.Popen(
                command,
                shell=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                env=env,  # Feature 074: T054 - Mark-based correlation environment
                cwd=cwd_str,  # Feature 074: T041 - Terminal working directory
            )
            # Give app a moment to start
            await asyncio.sleep(0.5)

        except Exception as e:
            logger.error(f"Failed to launch '{command}' with environment" + (f" in {cwd}" if cwd else "") + f": {e}")
            raise

    # _swallow_window method REMOVED - mark-based correlation replaces swallow mechanism
    # Feature 074: Forward-Only Development - no backward compatibility with old swallow approach

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
        await self._i3_command(f'[con_id="{window_id}"] move to workspace {workspace}')

        # Apply floating state
        if saved_window.floating:
            await self._i3_command(f'[con_id="{window_id}"] floating enable')
        else:
            await self._i3_command(f'[con_id="{window_id}"] floating disable')

        # Apply geometry
        await self._i3_command(
            f'[con_id="{window_id}"] move position {saved_window.geometry.x} {saved_window.geometry.y}'
        )
        await self._i3_command(
            f'[con_id="{window_id}"] resize set {saved_window.geometry.width} {saved_window.geometry.height}'
        )

        # Apply marks
        for mark in saved_window.marks:
            await self._i3_command(f'[con_id="{window_id}"] mark --add {mark}')

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


# ============================================================================
# Feature 075: Idempotent Layout Restoration (MVP)
# ============================================================================

async def restore_workflow(
    layout: LayoutSnapshot,
    project: str,
    i3_connection,
) -> "RestoreResult":  # type: ignore
    """Restore layout using app-registry-based detection (idempotent).

    Feature 075: T010-T015 (User Story 1 - Idempotent App Restoration)

    This is the simplified MVP approach that replaces mark-based correlation:
    1. Detect currently running apps (T012)
    2. Filter layout to skip already-running apps (T011)
    3. Launch missing apps sequentially (T013)
    4. Focus saved workspace (T014)
    5. Build RestoreResult with metrics (T015)

    Args:
        layout: LayoutSnapshot loaded from JSON
        project: Current project name (e.g., "nixos")
        i3_connection: i3ipc connection for workspace focusing

    Returns:
        RestoreResult with apps_already_running, apps_launched, apps_failed, elapsed_seconds

    Example:
        >>> layout = load_layout("main", "nixos")
        >>> result = await restore_workflow(layout, "nixos", conn)
        >>> print(result.status)  # "success" or "partial" or "failed"
        >>> print(result.apps_launched)  # ["code", "lazygit"]
    """
    from .auto_restore import detect_running_apps
    from .models import RestoreResult, SavedWindow
    from ..services.app_launcher import AppLauncher
    import time

    start_time = time.time()

    # T012: Detect currently running apps (O(W) where W = window count)
    running_apps = await detect_running_apps()
    logger.info(f"restore_workflow: detected {len(running_apps)} running apps: {sorted(running_apps)}")

    # T011: Filter layout windows - skip already-running, collect missing
    apps_already_running = []
    apps_to_launch = []

    for ws_layout in layout.workspace_layouts:
        for window_data in ws_layout.windows:
            # Parse as SavedWindow (supports both dict and WindowPlaceholder formats)
            if isinstance(window_data, dict):
                # Add workspace from parent workspace_layout (not stored in individual windows)
                # Use 'workspace_num' alias for Pydantic v2 (alias is required when passing dict)
                window_data_with_ws = {**window_data, 'workspace_num': ws_layout.workspace_num}
                logger.debug(f"DEBUG: Creating SavedWindow with keys: {list(window_data_with_ws.keys())}")
                saved_window = SavedWindow(**window_data_with_ws)
            else:
                # Already a WindowPlaceholder or SavedWindow - extract app_registry_name
                if hasattr(window_data, 'app_registry_name'):
                    saved_window = SavedWindow(
                        app_registry_name=window_data.app_registry_name,
                        workspace_num=ws_layout.workspace_num,  # Use alias name for Pydantic v2
                        cwd=window_data.cwd if hasattr(window_data, 'cwd') else None,
                        focused=window_data.focused if hasattr(window_data, 'focused') else False,
                    )
                else:
                    logger.warning(f"Window missing app_registry_name: {window_data}")
                    continue

            app_name = saved_window.app_registry_name

            # Set-based membership test (O(1))
            if app_name in running_apps:
                apps_already_running.append(app_name)
                logger.debug(f"✓ {app_name} already running - skip")
            else:
                apps_to_launch.append(saved_window)
                logger.debug(f"→ {app_name} missing - will launch")

    # T013: Launch missing apps sequentially via AppLauncher
    launcher = AppLauncher()
    apps_launched = []
    apps_failed = []

    for saved_window in apps_to_launch:
        app_name = saved_window.app_registry_name
        workspace = saved_window.workspace
        cwd = saved_window.cwd

        try:
            logger.info(f"Launching {app_name} on workspace {workspace} (cwd: {cwd or 'N/A'})")

            # Launch via unified app launcher (Feature 057 wrapper-based system)
            await launcher.launch_app(
                app_name=app_name,
                workspace=workspace,
                cwd=cwd,
                project=project,
            )

            apps_launched.append(app_name)
            logger.info(f"✓ Successfully launched {app_name}")

        except Exception as e:
            apps_failed.append(app_name)
            logger.error(f"✗ Failed to launch {app_name}: {e}")

    # T014: Focus saved workspace
    try:
        focused_ws = layout.focused_workspace
        await i3_connection.command(f'workspace number {focused_ws}')
        logger.info(f"Focused workspace {focused_ws}")
    except Exception as e:
        logger.warning(f"Failed to focus workspace {layout.focused_workspace}: {e}")

    # T015: Build RestoreResult with metrics
    elapsed_seconds = time.time() - start_time

    # Determine status
    if apps_failed:
        if apps_launched or apps_already_running:
            status = "partial"  # Some succeeded, some failed
        else:
            status = "failed"  # All failed
    else:
        status = "success"  # No failures

    result = RestoreResult(
        status=status,
        apps_already_running=apps_already_running,
        apps_launched=apps_launched,
        apps_failed=apps_failed,
        elapsed_seconds=elapsed_seconds,
    )

    logger.info(
        f"Restore complete: {status} ({result.success_rate:.1f}% success rate) - "
        f"{len(apps_already_running)} skipped, {len(apps_launched)} launched, "
        f"{len(apps_failed)} failed in {elapsed_seconds:.2f}s"
    )

    return result
