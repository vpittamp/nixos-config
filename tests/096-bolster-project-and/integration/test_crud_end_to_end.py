"""
Feature 096 T028: Integration tests for CRUD operations end-to-end

Tests the full workflow from Python CRUD handler through shell scripts.
These tests verify that the bug fixes in Phase 2 make the entire flow work.
"""

import json
import os
import subprocess
import tempfile
import pytest
from pathlib import Path

# Add parent paths for imports
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools"))

from i3_project_manager.services.project_editor import ProjectEditor


class TestProjectEditEndToEnd:
    """End-to-end tests for project edit workflow (T028)"""

    def test_project_edit_workflow_returns_success(self, temp_projects_dir, sample_project_config):
        """
        Feature 096 T028: Full edit workflow should succeed without conflict

        This tests the complete edit flow:
        1. Create a project file
        2. Edit it via ProjectEditor
        3. Verify success (no false conflict)
        4. Verify data persisted correctly
        """
        # Setup: Create project file
        project_file = temp_projects_dir / f"{sample_project_config['name']}.json"
        with open(project_file, 'w') as f:
            json.dump(sample_project_config, f, indent=2)

        # Act: Edit via ProjectEditor (same as Python CRUD handler)
        editor = ProjectEditor(projects_dir=temp_projects_dir)
        result = editor.edit_project(
            sample_project_config['name'],
            {
                "display_name": "Updated Display Name",
                "icon": "\U0001F680"  # Rocket emoji
            }
        )

        # Assert: Success without conflict
        assert result['status'] == 'success', f"Edit should succeed, got: {result}"
        assert result['conflict'] is False, "No conflict expected for normal edit"

        # Verify: Data persisted to disk
        with open(project_file, 'r') as f:
            saved_data = json.load(f)

        assert saved_data['display_name'] == "Updated Display Name"
        assert saved_data['icon'] == "\U0001F680"
        # Original fields preserved
        assert saved_data['name'] == sample_project_config['name']
        assert saved_data['directory'] == sample_project_config['directory']

    def test_project_edit_validates_input(self, temp_projects_dir, sample_project_config):
        """
        Feature 096 T028: Edit should validate input (icon format, etc.)

        Tests that Pydantic validation catches invalid icons.
        """
        # Setup: Create project file
        project_file = temp_projects_dir / f"{sample_project_config['name']}.json"
        with open(project_file, 'w') as f:
            json.dump(sample_project_config, f, indent=2)

        editor = ProjectEditor(projects_dir=temp_projects_dir)

        # Act & Assert: Invalid icon should raise ValidationError
        with pytest.raises(Exception) as exc_info:
            editor.edit_project(
                sample_project_config['name'],
                {"icon": "invalid-icon-not-emoji"}
            )

        # Pydantic ValidationError expected
        assert "icon" in str(exc_info.value).lower() or "validation" in str(exc_info.value).lower()

    def test_project_edit_handles_nonexistent_project(self, temp_projects_dir):
        """
        Feature 096 T028: Edit should fail gracefully for nonexistent project
        """
        editor = ProjectEditor(projects_dir=temp_projects_dir)

        with pytest.raises(FileNotFoundError):
            editor.edit_project("nonexistent-project", {"display_name": "Test"})

    def test_project_edit_preserves_unmodified_fields(self, temp_projects_dir, sample_project_config):
        """
        Feature 096 T028: Edit should only modify specified fields

        When editing display_name, other fields (icon, directory, scope) should remain unchanged.
        """
        # Setup with all fields
        full_config = {
            **sample_project_config,
            "scope": "global",
            "description": "Test project description"
        }
        project_file = temp_projects_dir / f"{sample_project_config['name']}.json"
        with open(project_file, 'w') as f:
            json.dump(full_config, f, indent=2)

        editor = ProjectEditor(projects_dir=temp_projects_dir)

        # Act: Only update display_name
        result = editor.edit_project(
            sample_project_config['name'],
            {"display_name": "New Name Only"}
        )

        assert result['status'] == 'success'

        # Verify: Other fields unchanged
        with open(project_file, 'r') as f:
            saved_data = json.load(f)

        assert saved_data['display_name'] == "New Name Only"
        assert saved_data['icon'] == sample_project_config['icon']  # Unchanged
        assert saved_data['scope'] == "global"  # Unchanged


class TestProjectCreateEndToEnd:
    """End-to-end tests for project create workflow (T040)"""

    def test_project_create_workflow(self, temp_projects_dir):
        """
        Feature 096 T040: Full create workflow should succeed

        Tests creating a new project via ProjectEditor.
        """
        from i3_project_manager.models.project_config import ProjectConfig

        # Create a valid directory for the project
        project_dir = temp_projects_dir / "new-project-dir"
        project_dir.mkdir(parents=True, exist_ok=True)

        # Create project config
        config = ProjectConfig(
            name="new-test-project",
            display_name="New Test Project",
            icon="\U0001F4C2",  # Open folder emoji
            working_dir=str(project_dir),
            scope="scoped"
        )

        editor = ProjectEditor(projects_dir=temp_projects_dir)

        # Act: Create project
        result = editor.create_project(config)

        # Assert: Success
        assert result['status'] == 'success'
        assert result['project_name'] == "new-test-project"

        # Verify: File exists with correct content
        project_file = temp_projects_dir / "new-test-project.json"
        assert project_file.exists()

        with open(project_file, 'r') as f:
            saved_data = json.load(f)

        assert saved_data['name'] == "new-test-project"
        assert saved_data['display_name'] == "New Test Project"
        assert saved_data['icon'] == "\U0001F4C2"

    def test_project_create_rejects_duplicate_name(self, temp_projects_dir, sample_project_config):
        """
        Feature 096 T040: Create should reject duplicate project names
        """
        from i3_project_manager.models.project_config import ProjectConfig

        # Setup: Create existing project
        project_file = temp_projects_dir / f"{sample_project_config['name']}.json"
        with open(project_file, 'w') as f:
            json.dump(sample_project_config, f, indent=2)

        # Try to create project with same name
        project_dir = temp_projects_dir / "another-dir"
        project_dir.mkdir(parents=True, exist_ok=True)

        config = ProjectConfig(
            name=sample_project_config['name'],  # Duplicate name
            display_name="Duplicate Project",
            icon="\U0001F4C1",
            working_dir=str(project_dir),
            scope="scoped"
        )

        editor = ProjectEditor(projects_dir=temp_projects_dir)

        # Act & Assert: Should raise ValueError for duplicate
        with pytest.raises(ValueError) as exc_info:
            editor.create_project(config)

        assert "already exists" in str(exc_info.value)


class TestProjectDeleteEndToEnd:
    """End-to-end tests for project delete workflow (T055)"""

    def test_project_delete_workflow(self, temp_projects_dir, sample_project_config):
        """
        Feature 096 T055: Full delete workflow should succeed
        """
        # Setup: Create project file
        project_file = temp_projects_dir / f"{sample_project_config['name']}.json"
        with open(project_file, 'w') as f:
            json.dump(sample_project_config, f, indent=2)

        editor = ProjectEditor(projects_dir=temp_projects_dir)

        # Act: Delete project
        result = editor.delete_project(sample_project_config['name'])

        # Assert: Success
        assert result['status'] == 'success'

        # Verify: File deleted
        assert not project_file.exists()

        # Verify: Backup created
        backup_file = project_file.with_suffix('.json.deleted')
        assert backup_file.exists()

    def test_project_delete_handles_nonexistent(self, temp_projects_dir):
        """
        Feature 096 T055: Delete should fail gracefully for nonexistent project
        """
        editor = ProjectEditor(projects_dir=temp_projects_dir)

        with pytest.raises(FileNotFoundError):
            editor.delete_project("nonexistent-project")
