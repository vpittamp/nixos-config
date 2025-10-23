"""
Unit tests for i3pm data models

Feature 030: Production Readiness
Task T008: Data model validation tests

Tests Pydantic validation, serialization, and business logic.
"""

import pytest
from datetime import datetime
from pathlib import Path
from uuid import UUID
import tempfile
import os

# Import models from daemon (sys.path is configured in conftest.py)
from layout.models import (
    Project,
    Window,
    WindowGeometry,
    WindowPlaceholder,
    LayoutSnapshot,
    WorkspaceLayout,
    Container,
    Monitor,
    MonitorConfiguration,
    Event,
    ClassificationRule,
    LayoutMode,
    EventSource,
    ScopeType,
    PatternType,
    RuleSource,
    Resolution,
    Position,
)
from pydantic import ValidationError


# ============================================================================
# WindowGeometry Tests
# ============================================================================

def test_window_geometry_valid():
    """Test valid WindowGeometry creation"""
    geo = WindowGeometry(x=0, y=0, width=1920, height=1080)
    assert geo.x == 0
    assert geo.y == 0
    assert geo.width == 1920
    assert geo.height == 1080


def test_window_geometry_negative_dimensions():
    """Test WindowGeometry rejects negative dimensions"""
    with pytest.raises(ValidationError):
        WindowGeometry(x=0, y=0, width=-100, height=1080)

    with pytest.raises(ValidationError):
        WindowGeometry(x=0, y=0, width=1920, height=0)


# ============================================================================
# Project Tests
# ============================================================================

def test_project_valid(tmp_path):
    """Test valid Project creation"""
    project_dir = tmp_path / "test-project"
    project_dir.mkdir()

    project = Project(
        name="test-project",
        display_name="Test Project",
        icon="🧪",
        directory=project_dir,
    )

    assert project.name == "test-project"
    assert project.display_name == "Test Project"
    assert project.icon == "🧪"
    assert project.directory == project_dir.absolute()
    assert isinstance(project.created_at, datetime)
    assert project.scoped_classes == []
    assert project.layout_snapshots == []


def test_project_name_validation():
    """Test Project name must be lowercase alphanumeric with hyphens"""
    with tempfile.TemporaryDirectory() as tmpdir:
        valid_names = ["nixos", "my-project", "project-123", "a"]

        for name in valid_names:
            project = Project(
                name=name,
                display_name="Test",
                directory=Path(tmpdir),
            )
            assert project.name == name

        # Invalid names
        invalid_names = ["MyProject", "project_name", "Project Name", "project.name", ""]

        for name in invalid_names:
            with pytest.raises(ValidationError):
                Project(
                    name=name,
                    display_name="Test",
                    directory=Path(tmpdir),
                )


def test_project_directory_absolute():
    """Test Project directory is always absolute"""
    with tempfile.TemporaryDirectory() as tmpdir:
        rel_path = Path("relative/path")
        os.makedirs(tmpdir + "/relative/path", exist_ok=True)

        project = Project(
            name="test",
            display_name="Test",
            directory=Path(tmpdir) / rel_path,
        )

        assert project.directory.is_absolute()


# ============================================================================
# Window Tests
# ============================================================================

def test_window_valid():
    """Test valid Window creation"""
    window = Window(
        id=12345,
        window_class="Code",
        instance="code",
        title="test.py - Visual Studio Code",
        workspace="1",
        output="eDP-1",
        marks=["project:nixos"],
        floating=False,
        geometry=WindowGeometry(x=0, y=0, width=1920, height=1080),
        pid=5678,
        visible=True,
    )

    assert window.id == 12345
    assert window.window_class == "Code"
    assert window.title == "test.py - Visual Studio Code"
    assert window.marks == ["project:nixos"]


def test_window_get_project_mark():
    """Test extracting project mark from window"""
    window = Window(
        id=1,
        title="Test",
        workspace="1",
        output="eDP-1",
        marks=["project:nixos", "other-mark"],
        geometry=WindowGeometry(x=0, y=0, width=100, height=100),
    )

    assert window.get_project_mark() == "nixos"

    window_no_mark = Window(
        id=2,
        title="Test",
        workspace="1",
        output="eDP-1",
        marks=["other-mark"],
        geometry=WindowGeometry(x=0, y=0, width=100, height=100),
    )

    assert window_no_mark.get_project_mark() is None


# ============================================================================
# WindowPlaceholder Tests
# ============================================================================

def test_window_placeholder_valid():
    """Test valid WindowPlaceholder creation"""
    placeholder = WindowPlaceholder(
        window_class="Code",
        instance="code",
        title_pattern=".*Visual Studio Code",
        launch_command="code /tmp/test",
        geometry=WindowGeometry(x=0, y=0, width=1920, height=1080),
        floating=False,
        marks=["project:test"],
    )

    assert placeholder.window_class == "Code"
    assert placeholder.launch_command == "code /tmp/test"


def test_window_placeholder_swallow_criteria():
    """Test generating i3 swallow criteria"""
    placeholder = WindowPlaceholder(
        window_class="Firefox",
        instance="Navigator",
        title_pattern=".*Mozilla Firefox",
        launch_command="firefox",
        geometry=WindowGeometry(x=0, y=0, width=1920, height=1080),
    )

    criteria = placeholder.to_swallow_criteria()

    assert "class" in criteria
    assert "instance" in criteria
    assert "title" in criteria
    assert criteria["class"] == "^Firefox$"
    assert criteria["instance"] == "^Navigator$"
    assert criteria["title"] == ".*Mozilla Firefox"


def test_window_placeholder_invalid_command():
    """Test WindowPlaceholder rejects invalid commands"""
    # Note: This test may need adjustment based on available executables
    with pytest.raises(ValidationError):
        WindowPlaceholder(
            launch_command="nonexistent-command-12345",
            geometry=WindowGeometry(x=0, y=0, width=100, height=100),
        )


# ============================================================================
# WorkspaceLayout Tests
# ============================================================================

def test_workspace_layout_valid():
    """Test valid WorkspaceLayout creation"""
    layout = WorkspaceLayout(
        workspace_num=1,
        workspace_name="1:code",
        output="eDP-1",
        layout_mode=LayoutMode.SPLITH,
        containers=[],
        windows=[],
    )

    assert layout.workspace_num == 1
    assert layout.workspace_name == "1:code"
    assert layout.output == "eDP-1"
    assert layout.layout_mode == LayoutMode.SPLITH


def test_workspace_layout_invalid_workspace_num():
    """Test WorkspaceLayout rejects invalid workspace numbers"""
    with pytest.raises(ValidationError):
        WorkspaceLayout(
            workspace_num=0,  # Must be >= 1
            output="eDP-1",
            layout_mode=LayoutMode.SPLITH,
        )

    with pytest.raises(ValidationError):
        WorkspaceLayout(
            workspace_num=100,  # Must be <= 99
            output="eDP-1",
            layout_mode=LayoutMode.SPLITH,
        )


# ============================================================================
# Monitor Tests
# ============================================================================

def test_monitor_valid():
    """Test valid Monitor creation"""
    monitor = Monitor(
        name="eDP-1",
        active=True,
        primary=True,
        current_workspace="1",
        resolution=Resolution(width=1920, height=1080),
        position=Position(x=0, y=0),
    )

    assert monitor.name == "eDP-1"
    assert monitor.active is True
    assert monitor.primary is True
    assert monitor.resolution.width == 1920


def test_monitor_from_i3_output():
    """Test creating Monitor from i3 output data"""
    i3_output = {
        "name": "eDP-1",
        "active": True,
        "primary": True,
        "current_workspace": "1",
        "rect": {
            "x": 0,
            "y": 0,
            "width": 1920,
            "height": 1080,
        },
    }

    monitor = Monitor.from_i3_output(i3_output)

    assert monitor.name == "eDP-1"
    assert monitor.active is True
    assert monitor.primary is True
    assert monitor.current_workspace == "1"
    assert monitor.resolution.width == 1920
    assert monitor.position.x == 0


# ============================================================================
# MonitorConfiguration Tests
# ============================================================================

def test_monitor_configuration_valid():
    """Test valid MonitorConfiguration creation"""
    config = MonitorConfiguration(
        name="dual-monitor",
        monitors=[
            Monitor(
                name="eDP-1",
                active=True,
                primary=True,
                position=Position(x=0, y=0),
            ),
            Monitor(
                name="HDMI-1",
                active=True,
                primary=False,
                position=Position(x=1920, y=0),
            ),
        ],
        workspace_assignments={
            1: "eDP-1",
            2: "eDP-1",
            3: "HDMI-1",
        },
    )

    assert config.name == "dual-monitor"
    assert len(config.monitors) == 2
    assert config.workspace_assignments[1] == "eDP-1"


def test_monitor_configuration_invalid_assignment():
    """Test MonitorConfiguration rejects unknown output assignments"""
    with pytest.raises(ValidationError):
        MonitorConfiguration(
            name="test",
            monitors=[
                Monitor(
                    name="eDP-1",
                    active=True,
                    primary=True,
                    position=Position(x=0, y=0),
                ),
            ],
            workspace_assignments={
                1: "eDP-1",
                2: "UNKNOWN-OUTPUT",  # This output doesn't exist in monitors
            },
        )


# ============================================================================
# Event Tests
# ============================================================================

def test_event_valid():
    """Test valid Event creation"""
    event = Event(
        source=EventSource.I3,
        event_type="window",
        data={"change": "new", "container": {"id": 12345}},
    )

    assert isinstance(event.event_id, UUID)
    assert event.source == EventSource.I3
    assert event.event_type == "window"
    assert isinstance(event.timestamp, datetime)
    assert event.data["change"] == "new"


def test_event_correlation():
    """Test event correlation"""
    event1 = Event(
        source=EventSource.PROC,
        event_type="process_spawn",
        data={"pid": 12345},
    )

    event2 = Event(
        source=EventSource.I3,
        event_type="window",
        data={"pid": 12345},
    )

    event2.correlate_with(event1, confidence=0.95)

    assert event2.correlation_id == event1.event_id
    assert event2.confidence_score == 0.95


def test_event_confidence_score_validation():
    """Test Event confidence score must be 0.0-1.0"""
    with pytest.raises(ValidationError):
        Event(
            source=EventSource.I3,
            event_type="window",
            data={},
            confidence_score=1.5,  # Invalid: > 1.0
        )

    with pytest.raises(ValidationError):
        Event(
            source=EventSource.I3,
            event_type="window",
            data={},
            confidence_score=-0.1,  # Invalid: < 0.0
        )


# ============================================================================
# ClassificationRule Tests
# ============================================================================

def test_classification_rule_valid():
    """Test valid ClassificationRule creation"""
    rule = ClassificationRule(
        pattern=r"^Firefox$",
        scope_type=ScopeType.GLOBAL,
        priority=50,
        pattern_type=PatternType.CLASS,
        source=RuleSource.SYSTEM,
    )

    assert rule.pattern == r"^Firefox$"
    assert rule.scope_type == ScopeType.GLOBAL
    assert rule.priority == 50


def test_classification_rule_invalid_regex():
    """Test ClassificationRule rejects invalid regex patterns"""
    with pytest.raises(ValidationError):
        ClassificationRule(
            pattern=r"[invalid(regex",  # Unclosed bracket
            scope_type=ScopeType.SCOPED,
        )


def test_classification_rule_matches_window():
    """Test ClassificationRule.matches() method"""
    rule = ClassificationRule(
        pattern=r"^Code$",
        scope_type=ScopeType.SCOPED,
        pattern_type=PatternType.CLASS,
    )

    window_match = Window(
        id=1,
        window_class="Code",
        title="test.py",
        workspace="1",
        output="eDP-1",
        geometry=WindowGeometry(x=0, y=0, width=100, height=100),
    )

    window_no_match = Window(
        id=2,
        window_class="Firefox",
        title="test",
        workspace="1",
        output="eDP-1",
        geometry=WindowGeometry(x=0, y=0, width=100, height=100),
    )

    assert rule.matches(window_match) is True
    assert rule.matches(window_no_match) is False


def test_classification_rule_title_pattern():
    """Test ClassificationRule matching window title"""
    rule = ClassificationRule(
        pattern=r".*Visual Studio Code",
        scope_type=ScopeType.SCOPED,
        pattern_type=PatternType.TITLE,
    )

    window = Window(
        id=1,
        window_class="Code",
        title="test.py - Visual Studio Code",
        workspace="1",
        output="eDP-1",
        geometry=WindowGeometry(x=0, y=0, width=100, height=100),
    )

    assert rule.matches(window) is True
