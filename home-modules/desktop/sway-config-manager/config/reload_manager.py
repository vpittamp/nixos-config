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
        self.rollback_start_time: Optional[float] = None  # Feature 047 US4: T046 rollback logging

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
            # Exception occurred - rollback (Feature 047 US4: T045, T046)
            logger.error(f"Transaction failed: {exc_val}")

            if self.previous_commit:
                # Feature 047 US4: T046 - Enhanced rollback logging
                import time
                self.rollback_start_time = time.time()

                # Get current commit to log the change
                try:
                    current_version = self.reload_manager.rollback.get_active_version()
                    current_hash = current_version.commit_hash[:8] if current_version else "unknown"
                except Exception:
                    current_hash = "unknown"

                logger.info(f"Rolling back configuration:")
                logger.info(f"  From: {current_hash}")
                logger.info(f"  To:   {self.previous_commit[:8]}")

                # Perform rollback
                success = self.reload_manager.rollback.rollback_to_commit(self.previous_commit)

                # Calculate rollback duration
                rollback_duration_ms = int((time.time() - self.rollback_start_time) * 1000)

                if success:
                    logger.info(f"Rollback successful (duration: {rollback_duration_ms}ms)")
                    logger.info(f"Configuration restored to previous working state")

                    # Try to get file changes from git diff
                    try:
                        import subprocess
                        result = subprocess.run(
                            ["git", "diff", "--name-only", self.previous_commit, "HEAD"],
                            cwd=self.reload_manager.config_dir,
                            capture_output=True,
                            text=True,
                            check=False
                        )
                        if result.returncode == 0 and result.stdout:
                            changed_files = result.stdout.strip().split("\n")
                            logger.info(f"Files restored: {', '.join(changed_files)}")
                    except Exception as e:
                        logger.debug(f"Could not get file diff: {e}")
                else:
                    logger.error(f"Rollback failed after {rollback_duration_ms}ms - manual intervention required")
                    logger.error(f"Manual rollback: cd ~/.config/sway && git checkout {self.previous_commit[:8]}")

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
        self.version_manager = daemon.version_manager  # Feature 047 US4
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
        - Feature 047 US3: Project override validation

        Phase 2: Apply
        - Merge configurations
        - Apply to rule engines
        - Feature 047 US3: Reload active project context
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

            # Feature 047 US3: Validate project overrides if active project exists
            if self.daemon.active_project:
                project_errors = self.validator.validate_project_overrides(
                    self.daemon.active_project,
                    window_rules,
                    keybindings
                )
                errors.extend(project_errors)
                if project_errors:
                    logger.warning(f"Project override validation found {len(project_errors)} errors")

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
                # Feature 047 US3: Reload active project context
                # This ensures project overrides are fresh before applying rules
                await self.daemon.load_active_project()

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
                    # Feature 047 US4: T045 - This exception triggers automatic rollback via transaction context
                    raise Exception("Sway config reload failed - configuration will be rolled back to previous version")

                # Commit to git (Feature 047 US4: Auto-commit on successful reload)
                if not skip_commit:
                    from datetime import datetime
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

                    # Generate descriptive commit message
                    file_list = files if files else ["all changed files"]
                    files_desc = ", ".join(file_list[:3])
                    if len(file_list) > 3:
                        files_desc += f" (+{len(file_list) - 3} more)"

                    commit_message = f"Configuration reload: {timestamp}\n\nFiles: {files_desc}\nStatus: Success"

                    commit_hash = self.rollback.commit_config_changes(
                        message=commit_message,
                        files=files
                    )
                    self.daemon.state.active_config_version = commit_hash

                    # Feature 047 US4: Update version tracking
                    self.version_manager.update_active_version(
                        commit_hash=commit_hash,
                        message=commit_message,
                        author="sway-config-daemon"
                    )

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
