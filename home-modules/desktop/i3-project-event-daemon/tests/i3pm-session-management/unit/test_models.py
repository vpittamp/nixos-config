"""Unit tests for session management Pydantic models.

Feature 074: Session Management
Tests for extended models: WindowPlaceholder, LayoutSnapshot, RestoreCorrelation, ProjectConfiguration
"""

import pytest
from datetime import datetime
from pathlib import Path
from uuid import UUID
import tempfile
import shutil

from layout.models import (
    WindowPlaceholder,
    WindowGeometry,
    LayoutSnapshot,
    MonitorConfiguration,
    Monitor,
    Resolution,
    Position,
    WorkspaceLayout,
    LayoutMode,
    RestoreCorrelation,
    CorrelationStatus,
)
from models.config import ProjectConfiguration
from models.legacy import DaemonState


# ============================================================================
# WindowPlaceholder Tests (T007-T010, US2, US3)
# ============================================================================

class TestWindowPlaceholder:
    """Test WindowPlaceholder model extensions for session management."""

    def test_basic_placeholder_creation(self):
        """Test basic WindowPlaceholder creation without extensions."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)
        placeholder = WindowPlaceholder(
            window_class="ghostty",
            instance="ghostty",
            launch_command="ghostty",
            geometry=geometry,
        )

        assert placeholder.window_class == "ghostty"
        assert placeholder.cwd is None  # Optional field defaults to None
        assert placeholder.focused is False  # Defaults to False
        assert placeholder.restoration_mark is None
        assert placeholder.app_registry_name is None

    def test_cwd_validation_absolute_path(self):
        """Test cwd field validator requires absolute paths (T008, US2)."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)

        # Valid absolute path
        placeholder = WindowPlaceholder(
            window_class="ghostty",
            launch_command="ghostty",
            geometry=geometry,
            cwd=Path("/etc/nixos"),
        )
        assert placeholder.cwd == Path("/etc/nixos")

        # Invalid relative path should raise ValidationError
        with pytest.raises(ValueError, match="must be absolute"):
            WindowPlaceholder(
                window_class="ghostty",
                launch_command="ghostty",
                geometry=geometry,
                cwd=Path("relative/path"),
            )

    def test_is_terminal_method(self):
        """Test is_terminal() method (T009, US2)."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)

        # Terminal classes
        for terminal_class in ["ghostty", "Alacritty", "kitty", "foot", "WezTerm"]:
            placeholder = WindowPlaceholder(
                window_class=terminal_class,
                launch_command=terminal_class.lower(),
                geometry=geometry,
            )
            assert placeholder.is_terminal() is True, f"{terminal_class} should be recognized as terminal"

        # Non-terminal classes
        for non_terminal_class in ["Code", "firefox", "Chrome"]:
            placeholder = WindowPlaceholder(
                window_class=non_terminal_class,
                launch_command=non_terminal_class.lower(),
                geometry=geometry,
            )
            assert placeholder.is_terminal() is False, f"{non_terminal_class} should not be recognized as terminal"

    def test_get_launch_env_method(self):
        """Test get_launch_env() method generates restoration mark and environment (T010, US3)."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)
        placeholder = WindowPlaceholder(
            window_class="ghostty",
            launch_command="ghostty",
            geometry=geometry,
        )

        env = placeholder.get_launch_env(project="nixos")

        # Check restoration mark was generated
        assert placeholder.restoration_mark is not None
        assert placeholder.restoration_mark.startswith("i3pm-restore-")
        assert len(placeholder.restoration_mark) == 21  # "i3pm-restore-" + 8 hex chars

        # Check environment variables
        assert "I3PM_RESTORE_MARK" in env
        assert env["I3PM_RESTORE_MARK"] == placeholder.restoration_mark
        assert "I3PM_PROJECT" in env
        assert env["I3PM_PROJECT"] == "nixos"

    def test_restoration_mark_persistence(self):
        """Test restoration mark persists across multiple get_launch_env() calls."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)
        placeholder = WindowPlaceholder(
            window_class="ghostty",
            launch_command="ghostty",
            geometry=geometry,
        )

        env1 = placeholder.get_launch_env(project="nixos")
        mark1 = placeholder.restoration_mark

        env2 = placeholder.get_launch_env(project="nixos")
        mark2 = placeholder.restoration_mark

        # Same mark should be reused
        assert mark1 == mark2
        assert env1["I3PM_RESTORE_MARK"] == env2["I3PM_RESTORE_MARK"]

    def test_app_registry_name_field(self):
        """Test app_registry_name field for wrapper-based restoration (T015A, Feature 057)."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)

        placeholder = WindowPlaceholder(
            window_class="ghostty",
            launch_command="ghostty",
            geometry=geometry,
            app_registry_name="scratchpad-terminal",
        )

        assert placeholder.app_registry_name == "scratchpad-terminal"

    def test_focused_field(self):
        """Test focused field for window focus tracking (T007, US4)."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)

        # Unfocused by default
        placeholder1 = WindowPlaceholder(
            window_class="ghostty",
            launch_command="ghostty",
            geometry=geometry,
        )
        assert placeholder1.focused is False

        # Explicitly focused
        placeholder2 = WindowPlaceholder(
            window_class="Code",
            launch_command="code",
            geometry=geometry,
            focused=True,
        )
        assert placeholder2.focused is True


# ============================================================================
# LayoutSnapshot Tests (T011-T013, US1)
# ============================================================================

class TestLayoutSnapshot:
    """Test LayoutSnapshot model extensions for workspace focus tracking."""

    def create_minimal_layout_snapshot(self, name="test", focused_workspace=None):
        """Helper to create minimal valid LayoutSnapshot."""
        monitor = Monitor(
            name="eDP-1",
            active=True,
            primary=True,
            resolution=Resolution(width=1920, height=1080),
            position=Position(x=0, y=0),
        )
        monitor_config = MonitorConfiguration(
            name="single-monitor",
            monitors=[monitor],
            workspace_assignments={1: "eDP-1"},
        )
        workspace_layout = WorkspaceLayout(
            workspace_num=1,
            workspace_name="1",
            output="eDP-1",
            layout_mode=LayoutMode.SPLITH,
            windows=[],
        )

        return LayoutSnapshot(
            name=name,
            project="nixos",
            monitor_config=monitor_config,
            workspace_layouts=[workspace_layout],
            focused_workspace=focused_workspace,
        )

    def test_focused_workspace_field(self):
        """Test focused_workspace field (T011, US1)."""
        layout = self.create_minimal_layout_snapshot(focused_workspace=1)
        assert layout.focused_workspace == 1

    def test_focused_workspace_validation_exists(self):
        """Test focused workspace must exist in workspace_layouts (T012, US1)."""
        # Valid: focused_workspace exists in workspace_layouts
        layout = self.create_minimal_layout_snapshot(focused_workspace=1)
        assert layout.focused_workspace == 1

        # Invalid: focused_workspace doesn't exist in workspace_layouts
        with pytest.raises(ValueError, match="not in layout workspaces"):
            self.create_minimal_layout_snapshot(focused_workspace=5)

    def test_is_auto_save_method(self):
        """Test is_auto_save() method (T013, US5)."""
        # Auto-save layout
        auto_layout = self.create_minimal_layout_snapshot(name="auto-20251114-103000")
        assert auto_layout.is_auto_save() is True

        # Manual layout
        manual_layout = self.create_minimal_layout_snapshot(name="main")
        assert manual_layout.is_auto_save() is False

    def test_get_timestamp_method(self):
        """Test get_timestamp() method (T013, US5)."""
        # Auto-save layout with timestamp
        auto_layout = self.create_minimal_layout_snapshot(name="auto-20251114-103000")
        timestamp = auto_layout.get_timestamp()
        assert timestamp == "20251114-103000"

        # Manual layout returns None
        manual_layout = self.create_minimal_layout_snapshot(name="main")
        timestamp = manual_layout.get_timestamp()
        assert timestamp is None


# ============================================================================
# RestoreCorrelation Tests (T042-T045, US3)
# ============================================================================

class TestRestoreCorrelation:
    """Test RestoreCorrelation model for mark-based window correlation."""

    def create_sample_correlation(self):
        """Helper to create sample RestoreCorrelation."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)
        placeholder = WindowPlaceholder(
            window_class="ghostty",
            launch_command="ghostty",
            geometry=geometry,
        )

        return RestoreCorrelation(
            restoration_mark="i3pm-restore-abc123de",
            placeholder=placeholder,
        )

    def test_correlation_creation(self):
        """Test basic RestoreCorrelation creation (T042, US3)."""
        correlation = self.create_sample_correlation()

        assert isinstance(correlation.correlation_id, UUID)
        assert correlation.restoration_mark == "i3pm-restore-abc123de"
        assert correlation.status == CorrelationStatus.PENDING
        assert isinstance(correlation.started_at, datetime)
        assert correlation.completed_at is None
        assert correlation.matched_window_id is None
        assert correlation.error_message is None

    def test_restoration_mark_validation(self):
        """Test restoration mark pattern validation (T042, US3)."""
        geometry = WindowGeometry(x=0, y=0, width=800, height=600)
        placeholder = WindowPlaceholder(
            window_class="ghostty",
            launch_command="ghostty",
            geometry=geometry,
        )

        # Valid mark
        correlation = RestoreCorrelation(
            restoration_mark="i3pm-restore-abc123de",
            placeholder=placeholder,
        )
        assert correlation.restoration_mark == "i3pm-restore-abc123de"

        # Invalid marks should raise ValidationError
        with pytest.raises(ValueError):
            RestoreCorrelation(
                restoration_mark="invalid-mark",
                placeholder=placeholder,
            )

    def test_mark_matched_method(self):
        """Test mark_matched() method (T044, US3)."""
        correlation = self.create_sample_correlation()

        assert correlation.status == CorrelationStatus.PENDING
        assert correlation.completed_at is None
        assert correlation.matched_window_id is None

        correlation.mark_matched(window_id=12345)

        assert correlation.status == CorrelationStatus.MATCHED
        assert correlation.matched_window_id == 12345
        assert correlation.completed_at is not None

    def test_mark_timeout_method(self):
        """Test mark_timeout() method (T044, US3)."""
        correlation = self.create_sample_correlation()

        correlation.mark_timeout()

        assert correlation.status == CorrelationStatus.TIMEOUT
        assert correlation.completed_at is not None
        assert correlation.error_message is not None
        assert "within timeout" in correlation.error_message

    def test_mark_failed_method(self):
        """Test mark_failed() method (T044, US3)."""
        correlation = self.create_sample_correlation()

        correlation.mark_failed(error="Connection refused")

        assert correlation.status == CorrelationStatus.FAILED
        assert correlation.completed_at is not None
        assert correlation.error_message == "Connection refused"

    def test_elapsed_seconds_property(self):
        """Test elapsed_seconds property (T045, US3)."""
        import time

        correlation = self.create_sample_correlation()

        # Should be close to 0 when just created
        elapsed = correlation.elapsed_seconds
        assert 0 <= elapsed < 0.1

        # Wait a bit
        time.sleep(0.1)
        elapsed = correlation.elapsed_seconds
        assert 0.1 <= elapsed < 0.2

    def test_is_complete_property(self):
        """Test is_complete property (T045, US3)."""
        correlation = self.create_sample_correlation()

        # Initially not complete
        assert correlation.is_complete is False

        # Complete after marking
        correlation.mark_matched(window_id=12345)
        assert correlation.is_complete is True


# ============================================================================
# ProjectConfiguration Tests (T014-T015, US5)
# ============================================================================

class TestProjectConfiguration:
    """Test ProjectConfiguration model for per-project session settings."""

    def test_basic_project_configuration(self):
        """Test basic ProjectConfiguration creation (T014, US5)."""
        config = ProjectConfiguration(
            name="nixos",
            directory=Path("/etc/nixos"),
            auto_save=True,
            auto_restore=False,
            max_auto_saves=10,
        )

        assert config.name == "nixos"
        assert config.directory == Path("/etc/nixos").absolute()
        assert config.auto_save is True
        assert config.auto_restore is False
        assert config.default_layout is None
        assert config.max_auto_saves == 10

    def test_get_layouts_dir_method(self):
        """Test get_layouts_dir() method creates directory (T015, US5)."""
        config = ProjectConfiguration(
            name="test-project",
            directory=Path.home(),
            auto_save=True,
        )

        layouts_dir = config.get_layouts_dir()

        expected_dir = Path.home() / ".local/share/i3pm/layouts/test-project"
        assert layouts_dir == expected_dir
        assert layouts_dir.exists()
        assert layouts_dir.is_dir()

        # Cleanup
        shutil.rmtree(layouts_dir)

    def test_get_auto_save_name_method(self):
        """Test get_auto_save_name() method generates timestamp (T015, US5)."""
        config = ProjectConfiguration(
            name="nixos",
            directory=Path.home(),
        )

        auto_save_name = config.get_auto_save_name()

        # Should match format: auto-YYYYMMDD-HHMMSS
        assert auto_save_name.startswith("auto-")
        assert len(auto_save_name) == 20  # "auto-" + 8 digits + "-" + 6 digits

        # Verify format with regex
        import re
        assert re.match(r'^auto-\d{8}-\d{6}$', auto_save_name)

    def test_list_auto_saves_method(self):
        """Test list_auto_saves() method (T015, US5)."""
        config = ProjectConfiguration(
            name="test-list-saves",
            directory=Path.home(),
        )

        layouts_dir = config.get_layouts_dir()

        # Create some fake auto-save files
        (layouts_dir / "auto-20251114-100000.json").touch()
        (layouts_dir / "auto-20251114-110000.json").touch()
        (layouts_dir / "manual.json").touch()

        auto_saves = config.list_auto_saves()

        # Should only return auto-saves, sorted newest first
        assert len(auto_saves) == 2
        assert all("auto-" in str(path) for path in auto_saves)

        # Cleanup
        shutil.rmtree(layouts_dir)

    def test_get_latest_auto_save_method(self):
        """Test get_latest_auto_save() method (T015, US5)."""
        config = ProjectConfiguration(
            name="test-latest-save",
            directory=Path.home(),
        )

        layouts_dir = config.get_layouts_dir()

        # No auto-saves initially
        assert config.get_latest_auto_save() is None

        # Create auto-save files
        (layouts_dir / "auto-20251114-100000.json").touch()
        import time
        time.sleep(0.01)  # Ensure different mtime
        (layouts_dir / "auto-20251114-110000.json").touch()

        latest = config.get_latest_auto_save()

        # Should return the newest without .json extension
        assert latest == "auto-20251114-110000"

        # Cleanup
        shutil.rmtree(layouts_dir)


# ============================================================================
# DaemonState Tests (T016-T020, T060-T064, US1, US4)
# ============================================================================

class TestDaemonState:
    """Test DaemonState extensions for focus tracking."""

    def test_project_focused_workspace_field(self):
        """Test project_focused_workspace field (T016, US1)."""
        state = DaemonState()

        assert state.project_focused_workspace == {}

        # Add focus tracking
        state.project_focused_workspace["nixos"] = 3
        assert state.project_focused_workspace["nixos"] == 3

    def test_workspace_focused_window_field(self):
        """Test workspace_focused_window field (T060, US4)."""
        state = DaemonState()

        assert state.workspace_focused_window == {}

        # Add focus tracking
        state.workspace_focused_window[3] = 12345
        assert state.workspace_focused_window[3] == 12345

    def test_get_focused_workspace_method(self):
        """Test get_focused_workspace() method (T017, US1)."""
        state = DaemonState()

        # No focus history initially
        assert state.get_focused_workspace("nixos") is None

        # Set focus
        state.set_focused_workspace("nixos", 3)
        assert state.get_focused_workspace("nixos") == 3

    def test_set_focused_workspace_method(self):
        """Test set_focused_workspace() method (T018, US1)."""
        state = DaemonState()

        state.set_focused_workspace("nixos", 5)
        assert state.project_focused_workspace["nixos"] == 5

        # Update existing
        state.set_focused_workspace("nixos", 7)
        assert state.project_focused_workspace["nixos"] == 7

    def test_get_focused_window_method(self):
        """Test get_focused_window() method (T061, US4)."""
        state = DaemonState()

        # No focus history initially
        assert state.get_focused_window(3) is None

        # Set focus
        state.set_focused_window(3, 12345)
        assert state.get_focused_window(3) == 12345

    def test_set_focused_window_method(self):
        """Test set_focused_window() method (T062, US4)."""
        state = DaemonState()

        state.set_focused_window(3, 12345)
        assert state.workspace_focused_window[3] == 12345

        # Update existing
        state.set_focused_window(3, 67890)
        assert state.workspace_focused_window[3] == 67890

    def test_to_json_serialization(self):
        """Test to_json() serializes focus dictionaries (T019, T063, US1, US4)."""
        state = DaemonState()
        state.active_project = "nixos"
        state.set_focused_workspace("nixos", 3)
        state.set_focused_workspace("dotfiles", 5)
        state.set_focused_window(3, 12345)
        state.set_focused_window(5, 67890)

        json_data = state.to_json()

        assert "project_focused_workspace" in json_data
        assert json_data["project_focused_workspace"]["nixos"] == 3
        assert json_data["project_focused_workspace"]["dotfiles"] == 5

        assert "workspace_focused_window" in json_data
        # Workspace numbers are stringified in JSON
        assert json_data["workspace_focused_window"]["3"] == 12345
        assert json_data["workspace_focused_window"]["5"] == 67890

    def test_from_json_deserialization(self):
        """Test from_json() deserializes focus dictionaries (T020, T064, US1, US4)."""
        json_data = {
            "active_project": "nixos",
            "project_focused_workspace": {
                "nixos": 3,
                "dotfiles": 5,
            },
            "workspace_focused_window": {
                "3": 12345,
                "5": 67890,
            },
            "start_time": "2025-11-14T10:30:00",
            "event_count": 100,
            "error_count": 0,
        }

        state = DaemonState.from_json(json_data)

        assert state.active_project == "nixos"
        assert state.get_focused_workspace("nixos") == 3
        assert state.get_focused_workspace("dotfiles") == 5
        assert state.get_focused_window(3) == 12345
        assert state.get_focused_window(5) == 67890
        assert state.event_count == 100


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
