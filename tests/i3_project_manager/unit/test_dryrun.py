"""Tests for dry-run mode functionality.

T092: Dry-run mode for mutation commands
"""

import pytest
from pathlib import Path

from i3_project_manager.cli.dryrun import (
    DryRunChange,
    DryRunResult,
    DryRunContext,
    dry_run_create_project,
    dry_run_delete_project,
    dry_run_add_class,
    dry_run_add_pattern,
    dry_run_remove_pattern,
)


class TestDryRunChange:
    """Test DryRunChange class."""

    def test_create_action_formatting(self):
        """Verify CREATE action formatting."""
        change = DryRunChange(
            action="create",
            target="project 'nixos'",
            new_value="/etc/nixos"
        )
        assert "[CREATE]" in str(change)
        assert "nixos" in str(change)

    def test_delete_action_formatting(self):
        """Verify DELETE action formatting."""
        change = DryRunChange(
            action="delete",
            target="config file",
            old_value="/path/to/config.json"
        )
        assert "[DELETE]" in str(change)
        assert "config file" in str(change)

    def test_update_action_formatting(self):
        """Verify UPDATE action formatting."""
        change = DryRunChange(
            action="update",
            target="app-classes.json",
            old_value="before",
            new_value="after"
        )
        assert "[UPDATE]" in str(change)
        assert "→" in str(change)

    def test_to_dict_conversion(self):
        """Verify dictionary conversion."""
        change = DryRunChange(
            action="add",
            target="scoped_classes",
            new_value="Code"
        )
        result = change.to_dict()

        assert result["action"] == "add"
        assert result["target"] == "scoped_classes"
        assert result["new_value"] == "Code"


class TestDryRunResult:
    """Test DryRunResult class."""

    def test_add_change(self):
        """Verify adding changes."""
        result = DryRunResult()
        result.add_change("create", "project", new_value="nixos")

        assert len(result.changes) == 1
        assert result.changes[0].action == "create"
        assert result.changes[0].new_value == "nixos"

    def test_add_warning(self):
        """Verify adding warnings."""
        result = DryRunResult()
        result.add_warning("This might take a while")

        assert len(result.warnings) == 1
        assert "take a while" in result.warnings[0]

    def test_set_error(self):
        """Verify setting errors."""
        result = DryRunResult()
        result.set_error("Project already exists")

        assert result.success is False
        assert result.error_message == "Project already exists"

    def test_to_dict_conversion(self):
        """Verify dictionary conversion."""
        result = DryRunResult()
        result.add_change("create", "project", new_value="nixos")
        result.add_warning("Warning message")
        result.set_error("Error message")

        data = result.to_dict()

        assert data["success"] is False
        assert data["error"] == "Error message"
        assert len(data["changes"]) == 1
        assert len(data["warnings"]) == 1

    def test_string_formatting_with_changes(self):
        """Verify string formatting with changes."""
        result = DryRunResult()
        result.add_change("create", "project", new_value="nixos")
        result.add_change("update", "config", old_value="old", new_value="new")

        output = str(result)

        assert "Dry-run mode" in output
        assert "2 change(s)" in output
        assert "[CREATE]" in output
        assert "[UPDATE]" in output

    def test_string_formatting_with_error(self):
        """Verify string formatting with errors."""
        result = DryRunResult()
        result.set_error("Something went wrong")

        output = str(result)

        assert "Would fail" in output
        assert "Something went wrong" in output


class TestDryRunContext:
    """Test DryRunContext class."""

    def test_context_manager(self):
        """Verify context manager usage."""
        with DryRunContext() as ctx:
            ctx.add_change("create", "project", new_value="nixos")
            ctx.add_warning("Test warning")

        assert len(ctx.result.changes) == 1
        assert len(ctx.result.warnings) == 1

    def test_exception_handling(self):
        """Verify exception handling in context."""
        with pytest.raises(ValueError):
            with DryRunContext() as ctx:
                ctx.add_change("create", "project", new_value="test")
                raise ValueError("Test error")

        # Error should be recorded
        assert ctx.result.success is False
        assert "ValueError" in ctx.result.error_message


class TestDryRunHelpers:
    """Test dry-run helper functions."""

    def test_create_project_success(self, tmp_path):
        """Verify dry-run create project success."""
        directory = tmp_path / "nixos"
        directory.mkdir()

        result = dry_run_create_project(
            name="nixos",
            directory=directory,
            display_name="NixOS Config",
            icon="❄️",
            scoped_classes=["Code", "Ghostty"]
        )

        assert result.success is True
        assert len(result.changes) >= 2
        assert any("create" in c.action for c in result.changes)

    def test_create_project_directory_not_exists(self, tmp_path):
        """Verify dry-run create project with missing directory."""
        directory = tmp_path / "nonexistent"

        result = dry_run_create_project(
            name="nixos",
            directory=directory,
            display_name="NixOS Config",
            icon="❄️",
            scoped_classes=["Code"]
        )

        assert result.success is False
        assert "does not exist" in result.error_message

    def test_delete_project_success(self, tmp_path):
        """Verify dry-run delete project success."""
        config_file = tmp_path / "nixos.json"
        layouts = ["/path/to/layout1.json", "/path/to/layout2.json"]

        result = dry_run_delete_project(
            name="nixos",
            project_exists=True,
            config_file=config_file,
            saved_layouts=layouts,
            delete_layouts=True
        )

        assert result.success is True
        assert any("delete" in c.action for c in result.changes)
        assert len(result.warnings) > 0  # Warning about layouts

    def test_delete_project_not_exists(self, tmp_path):
        """Verify dry-run delete non-existent project."""
        config_file = tmp_path / "nixos.json"

        result = dry_run_delete_project(
            name="nixos",
            project_exists=False,
            config_file=config_file,
            saved_layouts=[],
            delete_layouts=False
        )

        assert result.success is False
        assert "not found" in result.error_message

    def test_add_class_new(self):
        """Verify dry-run add new class."""
        result = dry_run_add_class(
            class_name="Code",
            scope="scoped",
            already_classified=False
        )

        assert result.success is True
        assert any("add" in c.action for c in result.changes)
        assert any("scoped_classes" in c.target for c in result.changes)

    def test_add_class_already_exists(self):
        """Verify dry-run add already classified class."""
        result = dry_run_add_class(
            class_name="Code",
            scope="scoped",
            already_classified=True,
            current_scope="scoped"
        )

        assert result.success is False
        assert "already in" in result.error_message

    def test_add_class_move_scope(self):
        """Verify dry-run move class between scopes."""
        result = dry_run_add_class(
            class_name="Code",
            scope="global",
            already_classified=True,
            current_scope="scoped"
        )

        assert result.success is True
        assert len(result.warnings) > 0  # Warning about moving
        assert any("remove" in c.action for c in result.changes)
        assert any("add" in c.action for c in result.changes)

    def test_add_pattern_new(self):
        """Verify dry-run add new pattern."""
        result = dry_run_add_pattern(
            pattern="glob:pwa-*",
            scope="global",
            priority=10,
            description="PWA applications",
            pattern_exists=False
        )

        assert result.success is True
        assert any("add" in c.action for c in result.changes)
        assert any("pattern rule" in c.target for c in result.changes)

    def test_add_pattern_already_exists(self):
        """Verify dry-run add existing pattern."""
        result = dry_run_add_pattern(
            pattern="glob:pwa-*",
            scope="global",
            priority=0,
            description="",
            pattern_exists=True
        )

        assert result.success is False
        assert "already exists" in result.error_message

    def test_remove_pattern_exists(self):
        """Verify dry-run remove existing pattern."""
        result = dry_run_remove_pattern(
            pattern="glob:pwa-*",
            pattern_exists=True
        )

        assert result.success is True
        assert any("remove" in c.action for c in result.changes)

    def test_remove_pattern_not_exists(self):
        """Verify dry-run remove non-existent pattern."""
        result = dry_run_remove_pattern(
            pattern="glob:nonexistent-*",
            pattern_exists=False
        )

        assert result.success is False
        assert "not found" in result.error_message
