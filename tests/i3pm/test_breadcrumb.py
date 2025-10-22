"""Tests for BreadcrumbWidget component."""

import pytest
from pathlib import Path
import sys

# Add i3pm to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "home-modules" / "tools" / "i3_project_manager"))

from tui.widgets import BreadcrumbWidget, BreadcrumbPath


def test_breadcrumb_path_creation():
    """Test creating breadcrumb path segments."""
    # Simple segment
    segment1 = BreadcrumbPath(label="Projects")
    assert segment1.label == "Projects"
    assert segment1.screen_name is None
    assert segment1.screen_args == {}

    # Clickable segment with navigation
    segment2 = BreadcrumbPath(
        label="NixOS",
        screen_name="project_editor",
        screen_args={"project_name": "nixos"}
    )
    assert segment2.label == "NixOS"
    assert segment2.screen_name == "project_editor"
    assert segment2.screen_args == {"project_name": "nixos"}


def test_breadcrumb_widget_initialization():
    """Test BreadcrumbWidget initialization."""
    # Empty initialization
    breadcrumb = BreadcrumbWidget()
    assert breadcrumb.path == []

    # With initial path
    path = [
        BreadcrumbPath(label="Projects", screen_name="browser"),
        BreadcrumbPath(label="NixOS")
    ]
    breadcrumb = BreadcrumbWidget(initial_path=path)
    assert len(breadcrumb.path) == 2
    assert breadcrumb.path[0].label == "Projects"


def test_breadcrumb_set_path():
    """Test setting breadcrumb path."""
    breadcrumb = BreadcrumbWidget()

    path = [
        BreadcrumbPath(label="Projects"),
        BreadcrumbPath(label="NixOS"),
        BreadcrumbPath(label="Layouts")
    ]

    breadcrumb.set_path(path)
    assert len(breadcrumb.path) == 3
    assert breadcrumb.get_current_segment().label == "Layouts"


def test_breadcrumb_append_segment():
    """Test appending segments to path."""
    breadcrumb = BreadcrumbWidget(
        initial_path=[BreadcrumbPath(label="Projects")]
    )

    breadcrumb.append_segment(BreadcrumbPath(label="NixOS"))
    assert len(breadcrumb.path) == 2

    breadcrumb.append_segment(BreadcrumbPath(label="Edit"))
    assert len(breadcrumb.path) == 3
    assert breadcrumb.get_current_segment().label == "Edit"


def test_breadcrumb_pop_segment():
    """Test removing segments from path."""
    path = [
        BreadcrumbPath(label="Projects"),
        BreadcrumbPath(label="NixOS"),
        BreadcrumbPath(label="Layouts")
    ]
    breadcrumb = BreadcrumbWidget(initial_path=path)

    # Pop last segment
    removed = breadcrumb.pop_segment()
    assert removed.label == "Layouts"
    assert len(breadcrumb.path) == 2
    assert breadcrumb.get_current_segment().label == "NixOS"

    # Pop another
    removed = breadcrumb.pop_segment()
    assert removed.label == "NixOS"
    assert len(breadcrumb.path) == 1

    # Pop last
    removed = breadcrumb.pop_segment()
    assert removed.label == "Projects"
    assert len(breadcrumb.path) == 0

    # Pop from empty
    removed = breadcrumb.pop_segment()
    assert removed is None


def test_breadcrumb_go_to_root():
    """Test resetting to root segment."""
    path = [
        BreadcrumbPath(label="Projects"),
        BreadcrumbPath(label="NixOS"),
        BreadcrumbPath(label="Layouts")
    ]
    breadcrumb = BreadcrumbWidget(initial_path=path)

    breadcrumb.go_to_root()
    assert len(breadcrumb.path) == 1
    assert breadcrumb.path[0].label == "Projects"


def test_breadcrumb_get_current_segment():
    """Test getting current segment."""
    # Empty path
    breadcrumb = BreadcrumbWidget()
    assert breadcrumb.get_current_segment() is None

    # With segments
    path = [
        BreadcrumbPath(label="Projects"),
        BreadcrumbPath(label="NixOS")
    ]
    breadcrumb = BreadcrumbWidget(initial_path=path)
    current = breadcrumb.get_current_segment()
    assert current is not None
    assert current.label == "NixOS"


def test_breadcrumb_path_string_representation():
    """Test string representation of breadcrumb path."""
    segment = BreadcrumbPath(label="Projects", screen_name="browser")
    assert str(segment) == "Projects"
