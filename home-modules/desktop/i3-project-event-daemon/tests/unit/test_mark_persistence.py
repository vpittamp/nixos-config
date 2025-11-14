"""
Unit tests for Feature 076 mark persistence.

Tests cover:
- WindowPlaceholder with marks_metadata
- JSON serialization of marks_metadata
- Backward compatibility
"""

import pytest
import json
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "layout"))

from models import WindowPlaceholder, MarkMetadata


class TestMarkPersistence:
    """Test mark persistence for WindowPlaceholder (Feature 076)."""

    def test_window_placeholder_with_marks(self):
        """Test WindowPlaceholder with marks_metadata field."""
        mark_metadata = MarkMetadata(
            app="terminal",
            project="nixos",
            workspace="1",
            scope="scoped"
        )

        placeholder = WindowPlaceholder(
            window_class="Ghostty",
            instance="ghostty",
            title_pattern="Terminal",
            launch_command="ghostty",
            geometry={"x": 0, "y": 0, "width": 800, "height": 600},
            marks=[],
            floating=False,
            cwd=Path("/home/user/projects/nixos"),
            app_registry_name="terminal",
            focused=True,
            restoration_mark="i3pm-restore-12345678",
            marks_metadata=mark_metadata
        )

        assert placeholder.marks_metadata is not None
        assert placeholder.marks_metadata.app == "terminal"
        assert placeholder.marks_metadata.project == "nixos"

    def test_window_placeholder_without_marks(self):
        """Test WindowPlaceholder without marks (backward compatibility)."""
        placeholder = WindowPlaceholder(
            window_class="Ghostty",
            instance="ghostty",
            title_pattern="Terminal",
            launch_command="ghostty",
            geometry={"x": 0, "y": 0, "width": 800, "height": 600},
            marks=[],
            floating=False,
            cwd=Path("/home/user"),
            app_registry_name="terminal",
            focused=True,
            restoration_mark="i3pm-restore-12345678"
        )

        assert placeholder.marks_metadata is None

    def test_marks_serialization(self):
        """Test marks_metadata serializes to JSON correctly."""
        mark_metadata = MarkMetadata(
            app="code",
            project="nixos",
            workspace="2",
            scope="scoped",
            custom={"session_id": "abc123"}
        )

        placeholder = WindowPlaceholder(
            window_class="Code",
            instance="code",
            title_pattern="VS Code",
            launch_command="code",
            geometry={"x": 0, "y": 0, "width": 1200, "height": 800},
            marks=[],
            floating=False,
            cwd=Path("/home/user/projects/nixos"),
            app_registry_name="code",
            focused=True,
            restoration_mark="i3pm-restore-87654321",
            marks_metadata=mark_metadata
        )

        # Serialize to dict
        placeholder_dict = placeholder.model_dump(mode='python')

        # Verify marks_metadata is in serialized data
        assert 'marks_metadata' in placeholder_dict
        assert placeholder_dict['marks_metadata']['app'] == 'code'
        assert placeholder_dict['marks_metadata']['project'] == 'nixos'
        assert placeholder_dict['marks_metadata']['workspace'] == '2'
        assert placeholder_dict['marks_metadata']['custom'] == {"session_id": "abc123"}

    def test_json_roundtrip(self):
        """Test WindowPlaceholder can be serialized to JSON and back."""
        mark_metadata = MarkMetadata(
            app="lazygit",
            project="nixos",
            workspace="3",
            scope="scoped"
        )

        placeholder = WindowPlaceholder(
            window_class="lazygit",
            instance="lazygit",
            title_pattern="lazygit",
            launch_command="lazygit",
            geometry={"x": 0, "y": 0, "width": 1000, "height": 700},
            marks=[],
            floating=True,
            cwd=Path("/home/user/projects/nixos"),
            app_registry_name="lazygit",
            focused=False,
            restoration_mark="i3pm-restore-abcdefgh",
            marks_metadata=mark_metadata
        )

        # Serialize to JSON string
        placeholder_dict = placeholder.model_dump(mode='python')
        json_str = json.dumps(placeholder_dict, default=str, indent=2)

        # Deserialize from JSON
        restored_dict = json.loads(json_str)
        restored_placeholder = WindowPlaceholder(**restored_dict)

        # Verify marks_metadata survived roundtrip
        assert restored_placeholder.marks_metadata is not None
        assert restored_placeholder.marks_metadata.app == "lazygit"
        assert restored_placeholder.marks_metadata.project == "nixos"
        assert restored_placeholder.marks_metadata.workspace == "3"

    def test_backward_compatibility_no_marks(self):
        """Test WindowPlaceholder without marks_metadata field (backward compatibility)."""
        # Simulate old window data without marks_metadata
        old_window_dict = {
            "window_class": "Ghostty",
            "instance": "ghostty",
            "title_pattern": "Terminal",
            "launch_command": "ghostty",
            "geometry": {"x": 0, "y": 0, "width": 800, "height": 600},
            "marks": [],
            "floating": False,
            "cwd": "/home/user",
            "app_registry_name": "terminal",
            "focused": True,
            "restoration_mark": "i3pm-restore-12345678"
            # Note: no marks_metadata field
        }

        # Should parse without errors
        placeholder = WindowPlaceholder(**old_window_dict)

        # marks_metadata should be None for old layouts
        assert placeholder.marks_metadata is None
        assert placeholder.app_registry_name == "terminal"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
