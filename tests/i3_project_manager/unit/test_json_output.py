"""Tests for JSON output functionality.

T091: JSON output format for all CLI commands
"""

import pytest
import json
from datetime import datetime
from pathlib import Path

from i3_project_manager.cli.output import (
    OutputFormatter,
    ProjectJSONEncoder,
    format_project_list_json,
    format_project_json,
    format_switch_result_json,
    format_daemon_status_json,
)


class TestOutputFormatter:
    """Test OutputFormatter class."""

    def test_json_mode_success(self, capsys):
        """Verify JSON mode outputs valid JSON."""
        fmt = OutputFormatter(json_mode=True)
        fmt.print_success("Operation completed")
        fmt.output()

        captured = capsys.readouterr()
        result = json.loads(captured.out)

        assert result["status"] == "success"
        assert result["message"] == "Operation completed"

    def test_json_mode_error(self, capsys):
        """Verify JSON mode outputs errors with remediation."""
        fmt = OutputFormatter(json_mode=True)
        fmt.print_error("Something went wrong", "Try this fix")
        fmt.output()

        captured = capsys.readouterr()
        result = json.loads(captured.out)

        assert result["status"] == "error"
        assert result["message"] == "Something went wrong"
        assert result["remediation"] == "Try this fix"

    def test_json_mode_custom_data(self, capsys):
        """Verify custom data can be added to JSON output."""
        fmt = OutputFormatter(json_mode=True)
        fmt.set_result(project="nixos", elapsed_ms=42.5)
        fmt.output()

        captured = capsys.readouterr()
        result = json.loads(captured.out)

        assert result["project"] == "nixos"
        assert result["elapsed_ms"] == 42.5

    def test_rich_mode_does_not_output_json(self, capsys):
        """Verify rich mode does not output JSON."""
        fmt = OutputFormatter(json_mode=False)
        fmt.print_success("Operation completed")
        fmt.output()

        captured = capsys.readouterr()
        # Should contain colored text, not JSON
        assert "✓" in captured.out or "Operation completed" in captured.out
        # Should not be valid JSON
        with pytest.raises(json.JSONDecodeError):
            json.loads(captured.out)


class TestProjectJSONEncoder:
    """Test custom JSON encoder."""

    def test_encode_datetime(self):
        """Verify datetime encoding."""
        dt = datetime(2025, 10, 21, 12, 30, 45)
        encoded = json.dumps({"time": dt}, cls=ProjectJSONEncoder)
        result = json.loads(encoded)

        assert result["time"] == "2025-10-21T12:30:45"

    def test_encode_path(self):
        """Verify Path encoding."""
        path = Path("/etc/nixos")
        encoded = json.dumps({"dir": path}, cls=ProjectJSONEncoder)
        result = json.loads(encoded)

        assert result["dir"] == "/etc/nixos"

    def test_encode_object_with_to_dict(self):
        """Verify object with to_dict method."""
        class CustomObject:
            def to_dict(self):
                return {"key": "value"}

        obj = CustomObject()
        encoded = json.dumps({"obj": obj}, cls=ProjectJSONEncoder)
        result = json.loads(encoded)

        assert result["obj"]["key"] == "value"


class TestFormatFunctions:
    """Test formatting helper functions."""

    def test_format_switch_result_success(self):
        """Verify switch result formatting."""
        result = format_switch_result_json(
            project_name="nixos",
            success=True,
            elapsed_ms=42.5,
            no_launch=False
        )

        assert result["status"] == "success"
        assert result["project"] == "nixos"
        assert result["elapsed_ms"] == 42.5
        assert "error" not in result

    def test_format_switch_result_error(self):
        """Verify switch error formatting."""
        result = format_switch_result_json(
            project_name="nixos",
            success=False,
            elapsed_ms=10.0,
            error_msg="Project not found"
        )

        assert result["status"] == "error"
        assert result["project"] == "nixos"
        assert result["error"] == "Project not found"

    def test_format_daemon_status(self):
        """Verify daemon status formatting."""
        status = {
            "active_project": "nixos",
            "tracked_windows": 5,
            "total_windows": 10,
            "event_count": 100,
            "event_rate": 1.5,
            "uptime_seconds": 3600,
            "error_count": 2,
        }

        result = format_daemon_status_json(status)

        assert result["status"] == "running"
        assert result["active_project"] == "nixos"
        assert result["tracked_windows"] == 5
        assert result["event_rate"] == 1.5  # Rounded


class MockProject:
    """Mock project object for testing."""

    def __init__(self, name: str):
        self.name = name
        self.display_name = f"{name.capitalize()} Project"
        self.directory = Path(f"/home/user/{name}")
        self.icon = "📁"
        self.scoped_classes = ["Code", "Ghostty"]
        self.created_at = datetime(2025, 1, 1, 0, 0, 0)
        self.modified_at = datetime(2025, 10, 21, 12, 0, 0)
        self.workspace_preferences = {}
        self.auto_launch = []
        self.saved_layouts = []


class TestProjectFormatting:
    """Test project-specific formatting."""

    def test_format_project_json(self):
        """Verify single project formatting."""
        project = MockProject("nixos")
        result = format_project_json(project, is_active=True, window_count=3)

        assert result["name"] == "nixos"
        assert result["display_name"] == "Nixos Project"
        assert result["directory"] == "/home/user/nixos"
        assert result["icon"] == "📁"
        assert result["is_active"] is True
        assert result["window_count"] == 3
        assert "scoped_classes" in result

    def test_format_project_list_json(self):
        """Verify project list formatting."""
        projects = [MockProject("nixos"), MockProject("stacks")]
        result = format_project_list_json(projects, current="nixos")

        assert result["total"] == 2
        assert result["current"] == "nixos"
        assert len(result["projects"]) == 2
        assert result["projects"][0]["is_current"] is True
        assert result["projects"][1]["is_current"] is False
