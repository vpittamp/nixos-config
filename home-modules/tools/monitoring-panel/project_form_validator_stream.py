#!/usr/bin/env python3
"""
Project Form Validation Streaming Service

Feature 094 - T039: Real-time form validation with 300ms debouncing for deflisten
Monitors form state changes and streams validation results to Eww
"""

import asyncio
import json
import sys
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

# Add parent directory (tools) to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from i3_project_manager.services.form_validator import FormValidator


class FormValidationStream:
    """Streams form validation results to Eww deflisten"""

    def __init__(self, eww_config_path: str):
        """
        Initialize validation stream

        Args:
            eww_config_path: Path to Eww configuration directory
        """
        self.eww_config = eww_config_path
        self.validator = FormValidator(debounce_ms=300)
        self.last_form_state: Dict[str, Any] = {}
        self.validation_task: Optional[asyncio.Task] = None

    def get_eww_variable(self, var_name: str) -> str:
        """Get current value of an Eww variable"""
        try:
            result = subprocess.run(
                ["eww", "--config", self.eww_config, "get", var_name],
                capture_output=True,
                text=True,
                timeout=1.0
            )
            if result.returncode == 0:
                return result.stdout.strip()
            return ""
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            return ""

    def get_current_form_state(self) -> Dict[str, Any]:
        """Read current form state from Eww variables"""
        return {
            "name": self.get_eww_variable("editing_project_name"),
            "display_name": self.get_eww_variable("edit_form_display_name"),
            "icon": self.get_eww_variable("edit_form_icon"),
            "working_dir": self.get_eww_variable("edit_form_directory"),
            "scope": self.get_eww_variable("edit_form_scope"),
            "remote": {
                "enabled": self.get_eww_variable("edit_form_remote_enabled") == "true",
                "host": self.get_eww_variable("edit_form_remote_host"),
                "user": self.get_eww_variable("edit_form_remote_user"),
                "working_dir": self.get_eww_variable("edit_form_remote_dir"),
                "port": int(self.get_eww_variable("edit_form_remote_port") or "22")
            }
        }

    def form_state_changed(self, new_state: Dict[str, Any]) -> bool:
        """Check if form state has changed since last validation"""
        return new_state != self.last_form_state

    async def validate_and_emit(self, form_state: Dict[str, Any]) -> None:
        """Validate form and emit result as JSON"""
        # Store state before validation
        self.last_form_state = form_state.copy()

        # Skip validation if no project is being edited
        if not form_state.get("name"):
            self.emit_validation_result({
                "valid": True,
                "editing": False,
                "errors": {},
                "warnings": {},
                "timestamp": datetime.now().isoformat()
            })
            return

        # Validate form data
        validation_state = await self.validator.validate_project_form(
            form_data=form_state,
            form_id="project_edit_form",
            existing_name=form_state.get("name")  # Editing existing project
        )

        # Emit validation result
        self.emit_validation_result({
            "valid": validation_state.valid,
            "editing": True,
            "errors": validation_state.errors,
            "warnings": validation_state.warnings,
            "timestamp": datetime.now().isoformat()
        })

    def emit_validation_result(self, result: Dict[str, Any]) -> None:
        """Emit validation result as JSON line for deflisten"""
        print(json.dumps(result), flush=True)

    async def watch_form_changes(self) -> None:
        """Watch for form state changes and trigger validation"""
        while True:
            try:
                # Get current form state
                current_state = self.get_current_form_state()

                # Check if state changed
                if self.form_state_changed(current_state):
                    # Cancel previous validation if still running
                    if self.validation_task and not self.validation_task.done():
                        self.validation_task.cancel()
                        try:
                            await self.validation_task
                        except asyncio.CancelledError:
                            pass

                    # Start new validation (debounced internally by FormValidator)
                    self.validation_task = asyncio.create_task(
                        self.validate_and_emit(current_state)
                    )

                # Poll every 100ms for changes (validation itself is debounced 300ms)
                await asyncio.sleep(0.1)

            except Exception as e:
                # Emit error state
                self.emit_validation_result({
                    "valid": False,
                    "editing": False,
                    "errors": {"system": f"Validation error: {str(e)}"},
                    "warnings": {},
                    "timestamp": datetime.now().isoformat()
                })
                # Continue watching despite errors
                await asyncio.sleep(1.0)

    async def run(self) -> None:
        """Run the validation stream"""
        # Emit initial state
        self.emit_validation_result({
            "valid": True,
            "editing": False,
            "errors": {},
            "warnings": {},
            "timestamp": datetime.now().isoformat()
        })

        # Start watching for changes
        await self.watch_form_changes()


async def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: project_form_validator_stream.py <eww-config-path>", file=sys.stderr)
        sys.exit(1)

    eww_config_path = sys.argv[1]

    # Create and run validation stream
    stream = FormValidationStream(eww_config_path)
    try:
        await stream.run()
    except KeyboardInterrupt:
        # Graceful shutdown
        pass


if __name__ == "__main__":
    asyncio.run(main())
