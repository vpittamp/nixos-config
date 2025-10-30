"""
Sway Configuration Manager Daemon

Main daemon for dynamic Sway configuration management.
Handles configuration loading, validation, and hot-reload.
"""
# Module can be run with: python -m sway_config_manager

import asyncio
import logging
import signal
import sys
from pathlib import Path
from typing import Optional

from i3ipc.aio import Connection

from sway_config_manager.config import ConfigLoader, ConfigValidator, ConfigMerger, RollbackManager
from sway_config_manager.config.reload_manager import ReloadManager
from sway_config_manager.config.file_watcher import FileWatcher
from sway_config_manager.config.version_manager import VersionManager
from sway_config_manager.rules import (
    AppearanceManager,
    KeybindingManager,
    WindowRuleEngine,
    WorkspaceAssignmentHandler,
)
from sway_config_manager.ipc_server import IPCServer
from sway_config_manager.state import ConfigurationState

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SwayConfigDaemon:
    """Main daemon for Sway configuration management."""

    def __init__(self, config_dir: Optional[Path] = None):
        """
        Initialize Sway configuration daemon.

        Args:
            config_dir: Configuration directory (defaults to ~/.config/sway)
        """
        if config_dir is None:
            config_dir = Path.home() / ".config" / "sway"

        self.config_dir = config_dir
        self.sway: Optional[Connection] = None
        self.running = False

        # Initialize components
        self.loader = ConfigLoader(config_dir)
        self.validator = ConfigValidator(config_dir / "schemas")
        self.merger = ConfigMerger()
        self.rollback = RollbackManager(config_dir)
        self.version_manager = VersionManager(config_dir)  # Feature 047 T042
        self.state = ConfigurationState()

        # Initialize rule engines
        self.keybinding_manager = KeybindingManager()
        self.window_rule_engine = WindowRuleEngine()
        self.workspace_handler = WorkspaceAssignmentHandler()
        self.appearance_manager = AppearanceManager()
        self.appearance_config = None

        # Reload manager and file watcher
        self.reload_manager: Optional[ReloadManager] = None
        self.file_watcher: Optional[FileWatcher] = None

        # IPC server
        self.ipc_server: Optional[IPCServer] = None

        # Feature 047 US3: Active project context
        self.active_project = None
        self.projects_dir = config_dir.parent / "i3" / "projects"

    async def start(self):
        """Start the daemon."""
        logger.info("Starting Sway Configuration Manager Daemon")

        try:
            # Connect to Sway
            self.sway = await Connection(auto_reconnect=True).connect()
            logger.info("Connected to Sway IPC")

            # Share connection with rule engines
            self.keybinding_manager.sway = self.sway
            self.window_rule_engine.sway = self.sway
            self.workspace_handler.sway = self.sway
            self.appearance_manager.sway = self.sway

            # Initialize reload manager
            self.reload_manager = ReloadManager(self)

            # Load initial configuration
            await self.load_configuration()

            # Start file watcher
            self.file_watcher = FileWatcher(
                config_dir=self.config_dir,
                reload_callback=self._on_config_file_changed,
                debounce_ms=500
            )
            self.file_watcher.start()
            self.state.file_watcher_active = True

            # Start IPC server
            self.ipc_server = IPCServer(self)
            await self.ipc_server.start()

            # Subscribe to Sway events
            await self._subscribe_events()

            self.running = True
            logger.info("Daemon started successfully")

            # Main event loop
            await self._run_event_loop()

        except Exception as e:
            logger.error(f"Failed to start daemon: {e}")
            raise

    async def stop(self):
        """Stop the daemon."""
        logger.info("Stopping daemon...")
        self.running = False

        if self.file_watcher:
            self.file_watcher.stop()
            self.state.file_watcher_active = False

        if self.ipc_server:
            await self.ipc_server.stop()

        if self.sway:
            await self.sway.main_quit()

        logger.info("Daemon stopped")

    async def load_configuration(self):
        """Load and apply configuration."""
        try:
            logger.info("Loading configuration...")

            # Load configurations
            keybindings = self.loader.load_keybindings_toml()
            window_rules = self.loader.load_window_rules_json()
            workspace_assignments = self.loader.load_workspace_assignments_json()
            appearance_config = self.loader.load_appearance_json()

            # Validate
            errors = self.validator.validate_semantics(
                keybindings, window_rules, workspace_assignments, appearance_config
            )

            if errors:
                self.state.validation_errors = errors
                logger.warning(f"Configuration has {len(errors)} validation errors")
                for error in errors:
                    logger.warning(f"  {error.file_path}: {error.message}")
                return False

            # Merge (for now, just use runtime config; Nix integration comes later)
            merged_keybindings = self.merger.merge_keybindings([], keybindings)
            merged_rules = self.merger.merge_window_rules([], window_rules)
            merged_assignments = self.merger.merge_workspace_assignments([], workspace_assignments)
            self.appearance_config = appearance_config

            # Apply to rule engines
            await self.window_rule_engine.load_rules(merged_rules)
            await self.workspace_handler.load_assignments(merged_assignments)

            # Feature 047 US3: Load active project and set context
            await self.load_active_project()

            # Generate and apply keybindings (via config file)
            # This will be integrated with reload manager in Phase 3

            # Update state
            self.state.config_load_timestamp = asyncio.get_event_loop().time()
            self.state.validation_errors = []

            logger.info("Configuration loaded successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            return False

    async def load_active_project(self):
        """
        Load active project from i3pm active-project.json.

        Feature 047 User Story 3: Query active project and apply project-specific rules
        """
        try:
            import json
            from .models import Project

            # Read active project file from i3pm
            active_project_file = self.config_dir.parent / "i3" / "active-project.json"

            if not active_project_file.exists():
                logger.debug("No active project file found")
                self.active_project = None
                self.window_rule_engine.set_active_project(None)
                self.keybinding_manager.set_active_project(None)
                return

            with open(active_project_file, 'r') as f:
                active_data = json.load(f)

            project_name = active_data.get("name")
            if not project_name:
                logger.debug("Active project file is empty")
                self.active_project = None
                self.window_rule_engine.set_active_project(None)
                self.keybinding_manager.set_active_project(None)
                return

            # Load project configuration
            project_file = self.projects_dir / f"{project_name}.json"
            if not project_file.exists():
                logger.warning(f"Project file not found: {project_file}")
                self.active_project = None
                self.window_rule_engine.set_active_project(None)
                self.keybinding_manager.set_active_project(None)
                return

            with open(project_file, 'r') as f:
                project_data = json.load(f)

            # Parse project with Pydantic
            self.active_project = Project(**project_data)

            # Set project context in rule engines
            self.window_rule_engine.set_active_project(self.active_project)
            self.keybinding_manager.set_active_project(self.active_project)

            logger.info(f"Loaded active project: {self.active_project.name}")

        except Exception as e:
            logger.error(f"Failed to load active project: {e}")
            self.active_project = None
            self.window_rule_engine.set_active_project(None)
            self.keybinding_manager.set_active_project(None)

    async def _subscribe_events(self):
        """Subscribe to Sway events."""
        # Subscribe to window events for dynamic rule application
        self.sway.on('window::new', self._on_window_new)
        self.sway.on('output', self._on_output_change)

        logger.info("Subscribed to Sway events")

    async def _on_window_new(self, sway, event):
        """
        Handle window::new event.

        Feature 047 User Story 3: Applies project-specific rules dynamically
        """
        try:
            window = event.container
            logger.debug(f"New window: {window.id} ({window.app_id or window.window_class})")

            # Feature 047 US3: Ensure active project is loaded before applying rules
            # This handles cases where project switches while daemon is running
            await self.load_active_project()

            # Apply window rules (project context is set in window_rule_engine)
            await self.window_rule_engine.apply_rules_to_window(window)

        except Exception as e:
            logger.error(f"Error handling window::new event: {e}")

    async def _on_output_change(self, sway, event):
        """Handle output change event."""
        try:
            logger.info("Output configuration changed")

            # Reapply workspace assignments
            await self.workspace_handler.handle_output_change()

        except Exception as e:
            logger.error(f"Error handling output change: {e}")

    async def _on_config_file_changed(self, files: list):
        """
        Handle configuration file change event from file watcher.

        Args:
            files: List of changed file paths
        """
        try:
            logger.info(f"Configuration files changed: {len(files)} files")

            if self.reload_manager:
                result = await self.reload_manager.reload_configuration(
                    validate_only=False,
                    skip_commit=False,
                    files=files
                )

                if result["success"]:
                    logger.info("Configuration auto-reloaded successfully")
                else:
                    logger.error(f"Configuration auto-reload failed: {result.get('errors')}")
            else:
                logger.warning("Reload manager not initialized")

        except Exception as e:
            logger.error(f"Error handling config file change: {e}")

    async def _run_event_loop(self):
        """Run main event loop."""
        try:
            await self.sway.main()
        except asyncio.CancelledError:
            logger.info("Event loop cancelled")
        except Exception as e:
            logger.error(f"Event loop error: {e}")


async def main():
    """Main entry point."""
    daemon = SwayConfigDaemon()

    # Setup signal handlers
    loop = asyncio.get_event_loop()

    def signal_handler():
        logger.info("Received shutdown signal")
        asyncio.create_task(daemon.stop())

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, signal_handler)

    try:
        await daemon.start()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
