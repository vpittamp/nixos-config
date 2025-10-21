"""Unit tests for core data models."""

import json
import tempfile
from datetime import datetime
from pathlib import Path

import pytest

from i3_project_manager.core.models import (
    AppClassification,
    AutoLaunchApp,
    LayoutWindow,
    Project,
    SavedLayout,
    TUIState,
    WorkspaceLayout,
)


class TestAutoLaunchApp:
    """Tests for AutoLaunchApp dataclass."""

    def test_create_valid_app(self):
        """Test creating a valid auto-launch app."""
        app = AutoLaunchApp(
            command="ghostty",
            workspace=1,
            env={"SESH_DEFAULT": "nixos"},
            wait_for_mark="project:nixos",
        )
        assert app.command == "ghostty"
        assert app.workspace == 1
        assert app.wait_timeout == 5.0  # default

    def test_empty_command_fails(self):
        """Test that empty command raises ValueError."""
        with pytest.raises(ValueError, match="command cannot be empty"):
            AutoLaunchApp(command="")

    def test_invalid_workspace_fails(self):
        """Test that invalid workspace raises ValueError."""
        with pytest.raises(ValueError, match="Workspace must be 1-10"):
            AutoLaunchApp(command="ghostty", workspace=11)

    def test_invalid_timeout_fails(self):
        """Test that invalid timeout raises ValueError."""
        with pytest.raises(ValueError, match="Timeout must be"):
            AutoLaunchApp(command="ghostty", wait_timeout=0.05)

    def test_to_json_round_trip(self):
        """Test serialization and deserialization."""
        app = AutoLaunchApp(command="code /etc/nixos", workspace=2)
        json_data = app.to_json()
        restored = AutoLaunchApp.from_json(json_data)

        assert restored.command == app.command
        assert restored.workspace == app.workspace

    def test_get_full_env(self, tmp_path):
        """Test environment variable generation."""
        # Create a temporary project
        proj_dir = tmp_path / "test-project"
        proj_dir.mkdir()

        project = Project(
            name="test",
            directory=proj_dir,
            scoped_classes=["Ghostty"],
        )

        app = AutoLaunchApp(
            command="ghostty",
            env={"CUSTOM": "value"},
        )

        env = app.get_full_env(project)

        assert env["PROJECT_NAME"] == "test"
        assert env["I3_PROJECT"] == "test"
        assert env["PROJECT_DIR"] == str(proj_dir)
        assert env["CUSTOM"] == "value"


class TestProject:
    """Tests for Project dataclass."""

    def test_create_valid_project(self, tmp_path):
        """Test creating a valid project."""
        proj_dir = tmp_path / "nixos"
        proj_dir.mkdir()

        project = Project(
            name="nixos",
            directory=proj_dir,
            display_name="NixOS Config",
            icon="❄️",
            scoped_classes=["Ghostty", "Code"],
        )

        assert project.name == "nixos"
        assert project.display_name == "NixOS Config"
        assert project.icon == "❄️"
        assert len(project.scoped_classes) == 2

    def test_display_name_defaults_to_name(self, tmp_path):
        """Test that display_name defaults to name."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project = Project(
            name="test",
            directory=proj_dir,
            scoped_classes=["Ghostty"],
        )

        assert project.display_name == "test"

    def test_invalid_name_fails(self, tmp_path):
        """Test that non-alphanumeric names fail."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        with pytest.raises(ValueError, match="must be alphanumeric"):
            Project(
                name="test@project",
                directory=proj_dir,
                scoped_classes=["Ghostty"],
            )

    def test_missing_directory_fails(self):
        """Test that non-existent directory fails."""
        with pytest.raises(ValueError, match="does not exist"):
            Project(
                name="test",
                directory="/nonexistent/path",
                scoped_classes=["Ghostty"],
            )

    def test_empty_scoped_classes_fails(self, tmp_path):
        """Test that empty scoped_classes fails."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        with pytest.raises(ValueError, match="at least one scoped"):
            Project(
                name="test",
                directory=proj_dir,
                scoped_classes=[],
            )

    def test_invalid_workspace_number_fails(self, tmp_path):
        """Test that invalid workspace numbers fail."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        with pytest.raises(ValueError, match="Workspace number must be 1-10"):
            Project(
                name="test",
                directory=proj_dir,
                scoped_classes=["Ghostty"],
                workspace_preferences={11: "primary"},
            )

    def test_invalid_output_role_fails(self, tmp_path):
        """Test that invalid output roles fail."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        with pytest.raises(ValueError, match="Invalid output role"):
            Project(
                name="test",
                directory=proj_dir,
                scoped_classes=["Ghostty"],
                workspace_preferences={1: "invalid"},
            )

    def test_to_json_round_trip(self, tmp_path):
        """Test project serialization and deserialization."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        project = Project(
            name="test",
            directory=proj_dir,
            scoped_classes=["Ghostty"],
            workspace_preferences={1: "primary", 2: "secondary"},
        )

        json_data = project.to_json()
        restored = Project.from_json(json_data)

        assert restored.name == project.name
        assert restored.directory == project.directory
        assert restored.scoped_classes == project.scoped_classes
        assert restored.workspace_preferences == project.workspace_preferences

    def test_save_and_load(self, tmp_path):
        """Test saving and loading project from disk."""
        proj_dir = tmp_path / "nixos"
        proj_dir.mkdir()

        config_dir = tmp_path / "config"
        config_dir.mkdir()

        project = Project(
            name="nixos",
            directory=proj_dir,
            scoped_classes=["Ghostty", "Code"],
        )

        # Save
        project.save(config_dir)

        # Verify file exists
        config_file = config_dir / "nixos.json"
        assert config_file.exists()

        # Load
        loaded = Project.load("nixos", config_dir)
        assert loaded.name == project.name
        assert loaded.directory == project.directory

    def test_load_nonexistent_fails(self, tmp_path):
        """Test loading non-existent project fails."""
        config_dir = tmp_path / "config"
        config_dir.mkdir()

        with pytest.raises(FileNotFoundError, match="Project not found"):
            Project.load("nonexistent", config_dir)

    def test_list_all(self, tmp_path):
        """Test listing all projects."""
        # Create project directories
        proj1_dir = tmp_path / "proj1"
        proj1_dir.mkdir()
        proj2_dir = tmp_path / "proj2"
        proj2_dir.mkdir()

        config_dir = tmp_path / "config"
        config_dir.mkdir()

        # Create projects
        proj1 = Project(name="proj1", directory=proj1_dir, scoped_classes=["Ghostty"])
        proj2 = Project(name="proj2", directory=proj2_dir, scoped_classes=["Code"])

        proj1.save(config_dir)
        proj2.save(config_dir)

        # List all
        projects = Project.list_all(config_dir)
        assert len(projects) == 2
        assert any(p.name == "proj1" for p in projects)
        assert any(p.name == "proj2" for p in projects)

    def test_list_all_empty_dir(self, tmp_path):
        """Test listing projects from empty directory."""
        config_dir = tmp_path / "config"
        config_dir.mkdir()

        projects = Project.list_all(config_dir)
        assert projects == []

    def test_list_all_nonexistent_dir(self, tmp_path):
        """Test listing projects from non-existent directory."""
        config_dir = tmp_path / "nonexistent"

        projects = Project.list_all(config_dir)
        assert projects == []

    def test_delete(self, tmp_path):
        """Test deleting a project."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()
        config_dir = tmp_path / "config"
        config_dir.mkdir()

        project = Project(name="test", directory=proj_dir, scoped_classes=["Ghostty"])
        project.save(config_dir)

        # Verify exists
        assert (config_dir / "test.json").exists()

        # Delete
        project.delete(config_dir)

        # Verify deleted
        assert not (config_dir / "test.json").exists()


class TestLayoutWindow:
    """Tests for LayoutWindow dataclass."""

    def test_create_valid_window(self):
        """Test creating a valid layout window."""
        window = LayoutWindow(
            window_class="Ghostty",
            window_title="nvim test.py",
            launch_command="ghostty",
        )

        assert window.window_class == "Ghostty"
        assert window.window_title == "nvim test.py"

    def test_empty_class_fails(self):
        """Test that empty window class fails."""
        with pytest.raises(ValueError, match="class cannot be empty"):
            LayoutWindow(window_class="")

    def test_invalid_split_fails(self):
        """Test that invalid split orientation fails."""
        with pytest.raises(ValueError, match="Invalid split"):
            LayoutWindow(window_class="Ghostty", split_before="diagonal")


class TestWorkspaceLayout:
    """Tests for WorkspaceLayout dataclass."""

    def test_create_valid_workspace(self):
        """Test creating a valid workspace layout."""
        ws = WorkspaceLayout(
            number=1,
            output_role="primary",
            windows=[
                LayoutWindow(window_class="Ghostty", launch_command="ghostty")
            ],
        )

        assert ws.number == 1
        assert ws.output_role == "primary"
        assert len(ws.windows) == 1

    def test_invalid_workspace_number_fails(self):
        """Test that invalid workspace number fails."""
        with pytest.raises(ValueError, match="Workspace number must be 1-10"):
            WorkspaceLayout(number=11)

    def test_invalid_output_role_fails(self):
        """Test that invalid output role fails."""
        with pytest.raises(ValueError, match="Invalid output role"):
            WorkspaceLayout(number=1, output_role="invalid")


class TestSavedLayout:
    """Tests for SavedLayout dataclass."""

    def test_create_valid_layout(self):
        """Test creating a valid saved layout."""
        layout = SavedLayout(
            project_name="nixos",
            layout_name="default",
            workspaces=[WorkspaceLayout(number=1)],
        )

        assert layout.project_name == "nixos"
        assert layout.layout_name == "default"
        assert len(layout.workspaces) == 1

    def test_invalid_version_fails(self):
        """Test that invalid version fails."""
        with pytest.raises(ValueError, match="Unsupported layout version"):
            SavedLayout(layout_version="2.0", project_name="test")

    def test_invalid_layout_name_fails(self):
        """Test that invalid layout name fails."""
        with pytest.raises(ValueError, match="alphanumeric"):
            SavedLayout(project_name="test", layout_name="test@layout")

    def test_save_and_load(self, tmp_path):
        """Test saving and loading layout."""
        layout_dir = tmp_path / "layouts"
        layout_dir.mkdir()

        layout = SavedLayout(
            project_name="nixos",
            layout_name="default",
            workspaces=[WorkspaceLayout(number=1)],
        )

        # Save
        layout.save(layout_dir)

        # Verify file exists
        layout_file = layout_dir / "nixos" / "default.json"
        assert layout_file.exists()

        # Load
        loaded = SavedLayout.load("nixos", "default", layout_dir)
        assert loaded.project_name == layout.project_name
        assert loaded.layout_name == layout.layout_name

    def test_list_for_project(self, tmp_path):
        """Test listing layouts for a project."""
        layout_dir = tmp_path / "layouts"
        layout_dir.mkdir()

        # Create multiple layouts
        layout1 = SavedLayout(project_name="nixos", layout_name="default")
        layout2 = SavedLayout(project_name="nixos", layout_name="debugging")

        layout1.save(layout_dir)
        layout2.save(layout_dir)

        # List
        layouts = SavedLayout.list_for_project("nixos", layout_dir)
        assert len(layouts) == 2
        assert "default" in layouts
        assert "debugging" in layouts


class TestAppClassification:
    """Tests for AppClassification dataclass."""

    def test_create_default(self):
        """Test creating default app classification."""
        app_class = AppClassification()
        assert isinstance(app_class.scoped_classes, list)
        assert isinstance(app_class.global_classes, list)

    def test_is_scoped_global_class(self):
        """Test that global classes are not scoped."""
        app_class = AppClassification(
            scoped_classes=["Ghostty"],
            global_classes=["firefox"],
        )

        assert not app_class.is_scoped("firefox")

    def test_is_scoped_scoped_class(self):
        """Test that scoped classes are scoped."""
        app_class = AppClassification(
            scoped_classes=["Ghostty"],
            global_classes=["firefox"],
        )

        assert app_class.is_scoped("Ghostty")

    def test_is_scoped_pattern_match(self):
        """Test pattern matching for scoping."""
        app_class = AppClassification(
            class_patterns={"pwa-": "global", "terminal": "scoped"}
        )

        assert not app_class.is_scoped("pwa-youtube")
        assert app_class.is_scoped("terminal-app")

    def test_is_scoped_project_override(self, tmp_path):
        """Test project-specific scoped classes."""
        proj_dir = tmp_path / "test"
        proj_dir.mkdir()

        app_class = AppClassification(global_classes=["firefox"])

        # Project overrides global classification
        project = Project(
            name="test",
            directory=proj_dir,
            scoped_classes=["firefox"],  # Override global
        )

        assert app_class.is_scoped("firefox", project)

    def test_save_and_load(self, tmp_path):
        """Test saving and loading app classification."""
        config_file = tmp_path / "app-classes.json"

        app_class = AppClassification(
            scoped_classes=["Ghostty"],
            global_classes=["firefox"],
        )

        # Save
        app_class.save(config_file)
        assert config_file.exists()

        # Load
        loaded = AppClassification.load(config_file)
        assert loaded.scoped_classes == app_class.scoped_classes
        assert loaded.global_classes == app_class.global_classes

    def test_load_creates_default_if_missing(self, tmp_path):
        """Test that loading creates default if file missing."""
        config_file = tmp_path / "app-classes.json"

        loaded = AppClassification.load(config_file)
        assert isinstance(loaded, AppClassification)
        assert len(loaded.scoped_classes) > 0  # Has defaults


class TestTUIState:
    """Tests for TUIState dataclass."""

    def test_create_default_state(self):
        """Test creating default TUI state."""
        state = TUIState()
        assert state.active_screen == "browser"
        assert state.daemon_connected is False
        assert state.active_project is None

    def test_push_pop_screen(self):
        """Test screen navigation."""
        state = TUIState()
        assert state.active_screen == "browser"

        # Push editor
        state.push_screen("editor")
        assert state.active_screen == "editor"
        assert state.screen_history == ["browser"]

        # Push monitor
        state.push_screen("monitor")
        assert state.active_screen == "monitor"
        assert state.screen_history == ["browser", "editor"]

        # Pop back to editor
        result = state.pop_screen()
        assert result == "editor"
        assert state.active_screen == "editor"

        # Pop back to browser
        result = state.pop_screen()
        assert result == "browser"
        assert state.active_screen == "browser"

        # Pop with empty history
        result = state.pop_screen()
        assert result is None

    def test_reset_filters(self):
        """Test resetting browser filters."""
        state = TUIState(
            filter_text="nixos",
            sort_by="name",
            sort_descending=False,
        )

        state.reset_filters()

        assert state.filter_text == ""
        assert state.sort_by == "modified"
        assert state.sort_descending is True
