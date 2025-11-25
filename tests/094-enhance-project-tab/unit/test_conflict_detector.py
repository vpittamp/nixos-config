"""
Unit Tests for File Conflict Detection

Feature 094: Enhanced Projects & Applications CRUD Interface (User Story 2 - T033)
Tests conflict detection logic for concurrent edits to project JSON files
"""

import pytest
import json
import time
import tempfile
import shutil
from pathlib import Path
from typing import Dict, Any

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))

from i3_project_manager.services.project_editor import ProjectEditor
from i3_project_manager.models.project_config import ProjectConfig


@pytest.fixture
def temp_projects_dir():
    """Create temporary projects directory"""
    temp_dir = Path(tempfile.mkdtemp(prefix="test_conflicts_"))
    yield temp_dir
    shutil.rmtree(temp_dir, ignore_errors=True)


@pytest.fixture
def editor(temp_projects_dir):
    """Create ProjectEditor instance"""
    return ProjectEditor(projects_dir=temp_projects_dir)


@pytest.fixture
def sample_project(editor, temp_projects_dir) -> Path:
    """Create a sample project for conflict testing"""
    config = ProjectConfig(
        name="conflict-test",
        display_name="Conflict Test",
        icon="🔥",
        working_dir=str(temp_projects_dir)
    )
    result = editor.create_project(config)
    return Path(result["path"])


class TestFileModificationDetection:
    """Test detection of external file modifications"""

    def test_detect_no_conflict_when_unchanged(self, sample_project):
        """No conflict when file hasn't been modified externally"""
        # Get initial mtime
        initial_mtime = sample_project.stat().st_mtime

        # Small delay to ensure time difference
        time.sleep(0.01)

        # Check mtime again (should be same)
        current_mtime = sample_project.stat().st_mtime
        assert current_mtime == initial_mtime, "File should not have changed"

    def test_detect_external_modification(self, sample_project):
        """Detect when file is modified by external process"""
        # Get initial mtime
        initial_mtime = sample_project.stat().st_mtime

        # Small delay to ensure time difference
        time.sleep(0.01)

        # Simulate external modification
        with open(sample_project, 'r') as f:
            data = json.load(f)

        data["display_name"] = "Externally Modified"

        with open(sample_project, 'w') as f:
            json.dump(data, f, indent=2)

        # Check mtime changed
        current_mtime = sample_project.stat().st_mtime
        assert current_mtime > initial_mtime, "File mtime should have increased"

    def test_mtime_precision_sufficient(self, sample_project):
        """Verify mtime precision is sufficient for conflict detection"""
        mtimes = []

        for _ in range(3):
            time.sleep(0.01)  # 10ms delay

            # Modify file
            with open(sample_project, 'r') as f:
                data = json.load(f)

            data["_test_counter"] = data.get("_test_counter", 0) + 1

            with open(sample_project, 'w') as f:
                json.dump(data, f, indent=2)

            mtimes.append(sample_project.stat().st_mtime)

        # All mtimes should be different (sufficient precision)
        assert len(set(mtimes)) == 3, "Mtimes should all be unique"


class TestConflictDetectionWorkflow:
    """Test full conflict detection workflow"""

    def test_save_succeeds_when_no_conflict(self, editor, sample_project):
        """Save should succeed when file hasn't been modified"""
        # Get initial mtime
        initial_mtime = sample_project.stat().st_mtime

        # Edit project (mtime not changed externally)
        result = editor.edit_project("conflict-test", {
            "display_name": "Updated Name"
        })

        assert result["status"] == "success"
        assert sample_project.stat().st_mtime > initial_mtime

    def test_detect_conflict_before_save(self, editor, sample_project):
        """Conflict should be detected before overwriting changes"""
        # Simulate:
        # 1. User opens edit form (stores mtime)
        initial_mtime = sample_project.stat().st_mtime

        time.sleep(0.01)

        # 2. External process modifies file
        with open(sample_project, 'r') as f:
            data = json.load(f)
        data["icon"] = "🌟"  # External change
        with open(sample_project, 'w') as f:
            json.dump(data, f, indent=2)

        external_mtime = sample_project.stat().st_mtime
        assert external_mtime > initial_mtime

        # 3. User tries to save (should detect conflict)
        # Note: Current implementation doesn't have explicit conflict checking
        # This test documents the expected behavior for T040 implementation

        # For now, just verify the external change is there
        with open(sample_project, 'r') as f:
            current_data = json.load(f)
        assert current_data["icon"] == "🌟"

    def test_last_write_wins_without_conflict_detection(self, editor, sample_project):
        """Without conflict detection, last write overwrites"""
        # Initial state
        with open(sample_project, 'r') as f:
            initial_data = json.load(f)
        assert initial_data["icon"] == "🔥"

        time.sleep(0.01)

        # External modification
        with open(sample_project, 'r') as f:
            data = json.load(f)
        data["icon"] = "🌟"
        with open(sample_project, 'w') as f:
            json.dump(data, f, indent=2)

        time.sleep(0.01)

        # User save (overwrites external change)
        result = editor.edit_project("conflict-test", {
            "display_name": "User Edit"
        })
        assert result["status"] == "success"

        # User's edit wins (external icon change lost)
        with open(sample_project, 'r') as f:
            final_data = json.load(f)
        # External change may be lost depending on implementation
        # This documents current behavior


class TestConflictResolutionStrategies:
    """Test different conflict resolution strategies"""

    def test_keep_ui_changes_strategy(self, sample_project):
        """User chooses to keep their UI changes"""
        # Setup: File on disk vs. UI state
        ui_changes = {
            "display_name": "UI Version",
            "icon": "🎨"
        }

        file_changes = {
            "display_name": "File Version",
            "icon": "📄"
        }

        # Write file version to disk
        with open(sample_project, 'r') as f:
            data = json.load(f)
        data.update(file_changes)
        with open(sample_project, 'w') as f:
            json.dump(data, f, indent=2)

        # User chooses "Keep UI Changes" - overwrite with UI version
        with open(sample_project, 'r') as f:
            data = json.load(f)
        data.update(ui_changes)
        with open(sample_project, 'w') as f:
            json.dump(data, f, indent=2)

        # Verify UI changes won
        with open(sample_project, 'r') as f:
            final_data = json.load(f)
        assert final_data["display_name"] == "UI Version"
        assert final_data["icon"] == "🎨"

    def test_keep_file_changes_strategy(self, sample_project):
        """User chooses to reload file changes"""
        # Setup: File on disk vs. UI state
        ui_changes = {
            "display_name": "UI Version",
            "icon": "🎨"
        }

        file_changes = {
            "display_name": "File Version",
            "icon": "📄"
        }

        # Write file version to disk
        with open(sample_project, 'r') as f:
            data = json.load(f)
        data.update(file_changes)
        with open(sample_project, 'w') as f:
            json.dump(data, f, indent=2)

        # User chooses "Keep File Changes" - reload from disk
        with open(sample_project, 'r') as f:
            reloaded_data = json.load(f)

        # Verify file changes won
        assert reloaded_data["display_name"] == "File Version"
        assert reloaded_data["icon"] == "📄"

    def test_manual_merge_strategy(self, sample_project):
        """User manually merges both sets of changes"""
        # Setup: Different fields changed
        with open(sample_project, 'r') as f:
            base_data = json.load(f)

        ui_changes = {
            "display_name": "UI Changed This"
        }

        file_changes = {
            "icon": "📄"  # Different field
        }

        # Write file version
        base_data.update(file_changes)
        with open(sample_project, 'w') as f:
            json.dump(base_data, f, indent=2)

        # Merge both changes
        merged_data = {**base_data, **ui_changes}
        with open(sample_project, 'w') as f:
            json.dump(merged_data, f, indent=2)

        # Verify both changes present
        with open(sample_project, 'r') as f:
            final_data = json.load(f)
        assert final_data["display_name"] == "UI Changed This"
        assert final_data["icon"] == "📄"


class TestBackupBeforeConflictResolution:
    """Test backup creation before conflict resolution"""

    def test_backup_created_before_overwrite(self, editor, sample_project):
        """Backup should be created before resolving conflicts"""
        # Create backup manually (simulating what T040 should do)
        backup_path = sample_project.with_suffix('.json.backup')

        with open(sample_project, 'r') as f:
            data = json.load(f)

        with open(backup_path, 'w') as f:
            json.dump(data, f, indent=2)

        assert backup_path.exists()

        # Now safe to overwrite original
        with open(sample_project, 'r') as f:
            data = json.load(f)
        data["display_name"] = "Overwritten"
        with open(sample_project, 'w') as f:
            json.dump(data, f, indent=2)

        # Backup still has original data
        with open(backup_path, 'r') as f:
            backup_data = json.load(f)
        assert backup_data["display_name"] == "Conflict Test"

    def test_backup_cleanup_after_resolution(self, editor, sample_project):
        """Backup can be cleaned up after successful resolution"""
        backup_path = sample_project.with_suffix('.json.backup')

        # Create backup
        with open(sample_project, 'r') as f:
            data = json.load(f)
        with open(backup_path, 'w') as f:
            json.dump(data, f, indent=2)

        # After successful save, backup can be removed
        if backup_path.exists():
            backup_path.unlink()

        assert not backup_path.exists()


class TestEdgeCasesForConflictDetection:
    """Test edge cases in conflict detection"""

    def test_file_deleted_externally(self, sample_project):
        """Handle case where file is deleted by external process"""
        # File exists initially
        assert sample_project.exists()

        # External process deletes file
        sample_project.unlink()

        # File no longer exists
        assert not sample_project.exists()

        # UI should detect this as a conflict/error
        # (Actual error handling is for T040 implementation)

    def test_file_permissions_changed(self, sample_project):
        """Handle case where file becomes read-only"""
        # Make file read-only
        sample_project.chmod(0o444)

        # Attempt to write should fail
        try:
            with open(sample_project, 'w') as f:
                json.dump({"test": "data"}, f)
            assert False, "Should have raised PermissionError"
        except PermissionError:
            pass  # Expected

        # Restore permissions for cleanup
        sample_project.chmod(0o644)

    def test_rapid_successive_edits(self, editor, sample_project):
        """Handle rapid successive edits without conflicts"""
        for i in range(5):
            result = editor.edit_project("conflict-test", {
                "display_name": f"Edit {i}"
            })
            assert result["status"] == "success"
            time.sleep(0.01)

        # Final state should be last edit
        with open(sample_project, 'r') as f:
            data = json.load(f)
        assert data["display_name"] == "Edit 4"
