"""
Configuration reload orchestrator with two-phase commit.

Provides atomic configuration reload with validation and rollback.
"""

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


class ConfigTransaction:
    """
    Context manager for atomic configuration transactions.

    Ensures all-or-nothing configuration application with automatic rollback on failure.
    """

    def __init__(self, reload_manager):
        """
        Initialize configuration transaction.

        Args:
            reload_manager: ReloadManager instance
        """
        self.reload_manager = reload_manager
        self.success = False
        self.previous_commit: Optional[str] = None

    async def __aenter__(self):
        """Enter transaction context."""
        # Save current commit for rollback
        try:
            version = self.reload_manager.rollback.get_active_version()
            if version:
                self.previous_commit = version.commit_hash
        except Exception as e:
            logger.warning(f"Could not save current commit for rollback: {e}")

        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Exit transaction context."""
        if exc_type is not None:
            # Exception occurred - rollback
            logger.error(f"Transaction failed: {exc_val}")

            if self.previous_commit:
                logger.info(f"Rolling back to commit {self.previous_commit[:8]}")
                success = self.reload_manager.rollback.rollback_to_commit(self.previous_commit)

                if success:
                    logger.info("Rollback successful")
                else:
                    logger.error("Rollback failed - manual intervention required")

            return False  # Don't suppress exception

        return True


class ReloadManager:
    """Orchestrates configuration reload with two-phase commit."""

    def __init__(self, daemon):
        """
        Initialize reload manager.

        Args:
            daemon: SwayConfigDaemon instance
        """
        self.daemon = daemon
        self.loader = daemon.loader
        self.validator = daemon.validator
        self.merger = daemon.merger
        self.rollback = daemon.rollback
        self.config_dir = daemon.config_dir

    @asynccontextmanager
    async def transaction(self):
        """
        Create configuration transaction context.

        Yields:
            ConfigTransaction instance
        """
        tx = ConfigTransaction(self)
        async with tx:
            yield tx

    async def reload_configuration(
        self,
        validate_only: bool = False,
        skip_commit: bool = False,
        files: Optional[list] = None
    ) -> dict:
        """
        Reload configuration with two-phase commit.

        Phase 1: Validate
        - Load configuration files
        - Structural validation (JSON Schema)
        - Semantic validation (Sway IPC queries)
        - Conflict detection

        Phase 2: Apply
        - Merge configurations
        - Apply to rule engines
        - Reload Sway config
        - Commit to git

        Args:
            validate_only: Only validate, don't apply
            skip_commit: Don't commit changes to git
            files: Optional list of specific files to reload

        Returns:
            Result dictionary with success status and details
        """
        result = {
            "success": False,
            "phase": None,
            "errors": [],
            "warnings": [],
            "applied": False
        }

        try:
            # Phase 1: Validation
            result["phase"] = "validation"
            logger.info("Phase 1: Validating configuration")

            # Load configurations
            keybindings = self.loader.load_keybindings_toml()
            window_rules = self.loader.load_window_rules_json()
            workspace_assignments = self.loader.load_workspace_assignments_json()

            # Validate
            errors = self.validator.validate_semantics(
                keybindings, window_rules, workspace_assignments
            )

            if errors:
                result["errors"] = [e.dict() for e in errors]
                logger.error(f"Validation failed with {len(errors)} errors")
                return result

            # Merge configurations
            merged_keybindings = self.merger.merge_keybindings([], keybindings)
            merged_rules = self.merger.merge_window_rules([], window_rules)
            merged_assignments = self.merger.merge_workspace_assignments([], workspace_assignments)

            # Check for conflicts
            conflicts = self.merger.get_conflicts()
            if conflicts:
                result["warnings"] = conflicts
                logger.warning(f"Found {len(conflicts)} configuration conflicts")

            if validate_only:
                result["success"] = True
                result["phase"] = "validation_only"
                return result

            # Phase 2: Apply
            result["phase"] = "apply"
            logger.info("Phase 2: Applying configuration")

            async with self.transaction():
                # Apply to rule engines
                await self.daemon.window_rule_engine.load_rules(merged_rules)
                await self.daemon.workspace_handler.load_assignments(merged_assignments)

                # Generate keybinding config
                kb_config = self.daemon.keybinding_manager.generate_keybinding_config(merged_keybindings)

                # Write to config file (will be included in Sway config)
                kb_file = self.config_dir / "keybindings-generated.conf"
                with open(kb_file, "w") as f:
                    f.write(kb_config)

                # Reload Sway config
                reload_success = await self.daemon.keybinding_manager.reload_sway_config()

                if not reload_success:
                    raise Exception("Sway config reload failed")

                # Commit to git
                if not skip_commit:
                    commit_hash = self.rollback.commit_config_changes(
                        message="Configuration reload",
                        files=files
                    )
                    self.daemon.state.active_config_version = commit_hash
                    logger.info(f"Committed configuration: {commit_hash[:8]}")

                # Update state
                import asyncio
                self.daemon.state.config_load_timestamp = asyncio.get_event_loop().time()
                self.daemon.state.validation_errors = []
                self.daemon.state.reload_count += 1
                self.daemon.state.last_reload_success = True

                result["success"] = True
                result["applied"] = True
                result["phase"] = "complete"

                logger.info("Configuration reloaded successfully")

        except Exception as e:
            logger.error(f"Configuration reload failed: {e}")
            result["success"] = False
            result["errors"].append({"message": str(e)})
            self.daemon.state.last_reload_success = False

        return result

    async def validate_no_input_disruption(self) -> bool:
        """
        Validate that reload won't disrupt active user input.

        Checks for:
        - Active keyboard/mouse grabs
        - Focused input fields
        - Active modal dialogs

        Returns:
            True if safe to reload, False otherwise
        """
        # TODO: Implement input disruption check
        # For now, assume it's safe
        return True
