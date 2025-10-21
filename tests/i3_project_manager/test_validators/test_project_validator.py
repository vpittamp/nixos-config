"""Unit tests for project configuration validator."""

import json
from pathlib import Path

import pytest

from i3_project_manager.validators.project_validator import (
    ProjectValidator,
    ValidationError,
)


class TestProjectValidator:
    """Tests for ProjectValidator."""

    def test_valid_project_passes(self, tmp_path):
        """Test that a valid project passes validation."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project_dict = {
            "name": "test-project",
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty", "Code"],
            "display_name": "Test Project",
            "icon": "🧪",
        }

        validator = ProjectValidator(config_dir=tmp_path / "config")
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) == 0

    def test_missing_required_field_fails(self, tmp_path):
        """Test that missing required fields fail validation."""
        project_dict = {
            "name": "test",
            # Missing: directory, scoped_classes
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) >= 2
        assert any("directory" in e.path for e in errors)
        assert any("scoped_classes" in e.path for e in errors)

    def test_invalid_name_fails(self, tmp_path):
        """Test that invalid project names fail validation."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project_dict = {
            "name": "test@project",  # Invalid character @
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty"],
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) > 0
        assert any("name" in e.path for e in errors)

    def test_nonexistent_directory_fails(self):
        """Test that non-existent directory fails validation."""
        project_dict = {
            "name": "test",
            "directory": "/nonexistent/path",
            "scoped_classes": ["Ghostty"],
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) > 0
        assert any("directory" in e.path for e in errors)

    def test_empty_scoped_classes_fails(self, tmp_path):
        """Test that empty scoped_classes fails validation."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project_dict = {
            "name": "test",
            "directory": str(proj_dir),
            "scoped_classes": [],  # Empty list
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) > 0
        assert any("scoped_classes" in e.path for e in errors)

    def test_invalid_workspace_number_fails(self, tmp_path):
        """Test that invalid workspace numbers fail validation."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project_dict = {
            "name": "test",
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty"],
            "workspace_preferences": {"11": "primary"},  # Invalid: 11 > 10
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) > 0
        assert any("workspace_preferences" in e.path for e in errors)

    def test_invalid_output_role_fails(self, tmp_path):
        """Test that invalid output roles fail validation."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project_dict = {
            "name": "test",
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty"],
            "workspace_preferences": {"1": "invalid"},  # Invalid output role
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) > 0
        assert any("workspace_preferences" in e.path for e in errors)

    def test_invalid_auto_launch_command_fails(self, tmp_path):
        """Test that empty auto-launch command fails validation."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project_dict = {
            "name": "test",
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty"],
            "auto_launch": [{"command": ""}],  # Empty command
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) > 0
        assert any("auto_launch[0].command" in e.path for e in errors)

    def test_invalid_auto_launch_workspace_fails(self, tmp_path):
        """Test that invalid auto-launch workspace fails validation."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project_dict = {
            "name": "test",
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty"],
            "auto_launch": [
                {"command": "ghostty", "workspace": 15}  # Invalid: 15 > 10
            ],
        }

        validator = ProjectValidator()
        errors = validator.validate_project(project_dict, check_uniqueness=False)

        assert len(errors) > 0
        assert any("auto_launch[0].workspace" in e.path for e in errors)

    def test_duplicate_name_fails(self, tmp_path):
        """Test that duplicate project name fails validation."""
        # Create existing project
        config_dir = tmp_path / "config"
        config_dir.mkdir()

        proj_dir = tmp_path / "existing"
        proj_dir.mkdir()

        existing = {
            "name": "existing",
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty"],
        }

        existing_file = config_dir / "existing.json"
        existing_file.write_text(json.dumps(existing))

        # Try to create duplicate
        new_proj_dir = tmp_path / "new"
        new_proj_dir.mkdir()

        project_dict = {
            "name": "existing",  # Duplicate name
            "directory": str(new_proj_dir),
            "scoped_classes": ["Code"],
        }

        validator = ProjectValidator(config_dir=config_dir)
        errors = validator.validate_project(project_dict, check_uniqueness=True)

        assert len(errors) > 0
        assert any("name" in e.path and "already exists" in e.message for e in errors)

    def test_validate_file_success(self, tmp_path):
        """Test validating a file directly."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        config_dir = tmp_path / "config"
        config_dir.mkdir()

        project_dict = {
            "name": "test",
            "directory": str(proj_dir),
            "scoped_classes": ["Ghostty"],
        }

        config_file = config_dir / "test.json"
        config_file.write_text(json.dumps(project_dict))

        validator = ProjectValidator()
        is_valid, errors = validator.validate_file(config_file)

        assert is_valid is True
        assert len(errors) == 0

    def test_validate_file_nonexistent(self, tmp_path):
        """Test validating a non-existent file."""
        config_file = tmp_path / "nonexistent.json"

        validator = ProjectValidator()
        is_valid, errors = validator.validate_file(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert "not found" in errors[0].message

    def test_validate_file_invalid_json(self, tmp_path):
        """Test validating a file with invalid JSON."""
        config_file = tmp_path / "invalid.json"
        config_file.write_text("{ invalid json }")

        validator = ProjectValidator()
        is_valid, errors = validator.validate_file(config_file)

        assert is_valid is False
        assert len(errors) > 0
        assert "Invalid JSON" in errors[0].message

    def test_validate_all_projects(self, tmp_path):
        """Test validating all projects in a directory."""
        config_dir = tmp_path / "config"
        config_dir.mkdir()

        proj1_dir = tmp_path / "proj1"
        proj1_dir.mkdir()
        proj2_dir = tmp_path / "proj2"
        proj2_dir.mkdir()

        # Create valid project
        valid_project = {
            "name": "valid",
            "directory": str(proj1_dir),
            "scoped_classes": ["Ghostty"],
        }
        (config_dir / "valid.json").write_text(json.dumps(valid_project))

        # Create invalid project
        invalid_project = {
            "name": "invalid",
            "directory": "/nonexistent",
            "scoped_classes": ["Code"],
        }
        (config_dir / "invalid.json").write_text(json.dumps(invalid_project))

        validator = ProjectValidator(config_dir=config_dir)
        results = validator.validate_all_projects()

        # Valid project should not be in results
        assert "valid" not in results

        # Invalid project should be in results
        assert "invalid" in results
        assert len(results["invalid"]) > 0

    def test_validation_error_str(self):
        """Test ValidationError string representation."""
        error = ValidationError("name", "Test error message", "error")

        assert "ERROR" in str(error)
        assert "name" in str(error)
        assert "Test error message" in str(error)
