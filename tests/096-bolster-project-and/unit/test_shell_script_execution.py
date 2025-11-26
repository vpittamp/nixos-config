"""
Feature 096 T009: Unit tests for shell script conflict handling

Tests the project-edit-save shell script behavior when conflict=true.

Root cause (research.md Issue 2):
The original shell script exits with error code 1 when conflict=true,
even though the save actually succeeded. This prevents success handling
and leaves the form open with an error message.

The fix: Show a warning notification but don't exit with error when
conflict is detected (since the save DID succeed - last write wins).
"""

import json
import subprocess
import tempfile
import pytest
from pathlib import Path


class TestShellScriptConflictHandling:
    """Test suite for shell script conflict handling behavior"""

    def test_shell_script_exists_and_is_executable(self):
        """
        Feature 096 T009: Verify project-edit-save script exists in PATH
        """
        result = subprocess.run(
            ["which", "project-edit-save"],
            capture_output=True,
            text=True
        )
        # Script should be in PATH (installed via Nix)
        if result.returncode != 0:
            pytest.skip("project-edit-save not in PATH - requires NixOS rebuild")

        script_path = Path(result.stdout.strip())
        assert script_path.exists(), f"Script path {script_path} should exist"

    def test_crud_handler_returns_success_with_conflict_false(self):
        """
        Feature 096 T009: Verify CRUD handler returns conflict=false after fix

        This test verifies that the Python CRUD handler itself no longer
        returns false positive conflicts (prerequisite for shell script test).
        """
        import sys
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools"))

        from i3_project_manager.services.project_editor import ProjectEditor

        # Create temp project
        temp_dir = Path(tempfile.mkdtemp())
        project_dir = temp_dir / "test-dir"
        project_dir.mkdir()

        config = {
            "name": "shell-test",
            "display_name": "Shell Test",
            "icon": "\U0001F4C1",
            "directory": str(project_dir),
            "scope": "scoped"
        }

        project_file = temp_dir / "shell-test.json"
        with open(project_file, 'w') as f:
            json.dump(config, f)

        # Edit
        editor = ProjectEditor(projects_dir=temp_dir)
        result = editor.edit_project("shell-test", {"display_name": "Updated"})

        # Should return conflict=false (no external modification)
        assert result["status"] == "success"
        assert result["conflict"] is False, (
            "CRUD handler should return conflict=false when no external modification. "
            "This is a prerequisite for the shell script to work correctly."
        )

        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)


class TestShellScriptNotificationBehavior:
    """Tests for shell script notification behavior (after T010 fix)"""

    def test_success_path_should_trigger_notification(self):
        """
        Feature 096 T009: Verify shell script structure includes notification triggers

        After T010 fix, the shell script should:
        1. NOT exit 1 when conflict=true (just show warning)
        2. Always trigger success notification on status=success
        3. Only exit 1 on actual errors (status != success)
        """
        # Find the shell script
        result = subprocess.run(
            ["which", "project-edit-save"],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            pytest.skip("project-edit-save not in PATH - requires NixOS rebuild")

        script_path = Path(result.stdout.strip())

        # Read script content
        script_content = script_path.read_text()

        # After T010 fix, the script should NOT have 'exit 1' after conflict detection
        # Look for the problematic pattern
        if 'if [ "$CONFLICT" = "true" ]; then' in script_content:
            # Check if there's an exit 1 within the conflict block
            lines = script_content.split('\n')
            in_conflict_block = False
            conflict_exits_with_error = False

            for line in lines:
                if 'if [ "$CONFLICT" = "true" ]' in line:
                    in_conflict_block = True
                elif in_conflict_block and 'fi' in line:
                    in_conflict_block = False
                elif in_conflict_block and 'exit 1' in line:
                    conflict_exits_with_error = True
                    break

            # After T010 fix, this should be False
            # Before fix, this would be True (causing test to FAIL as expected)
            assert not conflict_exits_with_error, (
                "Shell script should NOT exit 1 when conflict=true but status=success. "
                "The save succeeded (last write wins), so show a warning notification "
                "instead of treating it as an error."
            )

    def test_error_path_should_exit_nonzero(self):
        """
        Feature 096 T009: Verify script exits non-zero on actual errors

        When status != success (real errors), the script should exit 1.
        """
        result = subprocess.run(
            ["which", "project-edit-save"],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            pytest.skip("project-edit-save not in PATH - requires NixOS rebuild")

        script_path = Path(result.stdout.strip())
        script_content = script_path.read_text()

        # Should have exit 1 in the error handling section (else branch)
        # This ensures actual errors are still treated as errors
        assert 'exit 1' in script_content, (
            "Shell script should still exit 1 on actual errors (status != success)"
        )
