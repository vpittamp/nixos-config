"""
Unit tests for Feature 076 mark models (MarkMetadata, WindowMarkQuery).

Tests cover:
- MarkMetadata serialization/deserialization
- WindowMarkQuery validation
- Custom metadata handling
- Forward compatibility
"""

import pytest
from pydantic import ValidationError

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "layout"))

from models import MarkMetadata, WindowMarkQuery


class TestMarkMetadata:
    """Test MarkMetadata model for Feature 076."""

    def test_basic_mark_creation(self):
        """Test creating basic mark metadata."""
        mark = MarkMetadata(app="terminal")
        assert mark.app == "terminal"
        assert mark.project is None
        assert mark.workspace is None
        assert mark.scope is None
        assert mark.custom is None

    def test_full_mark_creation(self):
        """Test creating mark metadata with all fields."""
        mark = MarkMetadata(
            app="code",
            project="nixos",
            workspace="5",
            scope="scoped",
            custom={"session_id": "abc123"}
        )
        assert mark.app == "code"
        assert mark.project == "nixos"
        assert mark.workspace == "5"
        assert mark.scope == "scoped"
        assert mark.custom == {"session_id": "abc123"}

    def test_app_name_validation(self):
        """Test app name must be kebab-case."""
        # Valid app names
        MarkMetadata(app="terminal")
        MarkMetadata(app="my-app")
        MarkMetadata(app="app123")

        # Invalid app names
        with pytest.raises(ValidationError):
            MarkMetadata(app="MyApp")  # CamelCase
        with pytest.raises(ValidationError):
            MarkMetadata(app="my_app")  # snake_case
        with pytest.raises(ValidationError):
            MarkMetadata(app="-invalid")  # starts with dash

    def test_workspace_validation(self):
        """Test workspace must be numeric string 1-70."""
        # Valid workspaces
        MarkMetadata(app="terminal", workspace="1")
        MarkMetadata(app="terminal", workspace="70")
        MarkMetadata(app="terminal", workspace="42")

        # Invalid workspaces
        with pytest.raises(ValidationError):
            MarkMetadata(app="terminal", workspace="0")  # starts with 0
        with pytest.raises(ValidationError):
            MarkMetadata(app="terminal", workspace="00")  # invalid format

    def test_scope_validation(self):
        """Test scope must be 'scoped' or 'global'."""
        # Valid scopes
        MarkMetadata(app="terminal", scope="scoped")
        MarkMetadata(app="terminal", scope="global")

        # Invalid scopes
        with pytest.raises(ValidationError):
            MarkMetadata(app="terminal", scope="invalid")

    def test_custom_key_validation(self):
        """Test custom keys must be snake_case identifiers."""
        # Valid custom keys
        MarkMetadata(app="terminal", custom={"session_id": "123"})
        MarkMetadata(app="terminal", custom={"my_key": "value"})
        MarkMetadata(app="terminal", custom={"_private": "value"})

        # Invalid custom keys
        with pytest.raises(ValidationError):
            MarkMetadata(app="terminal", custom={"Invalid-Key": "value"})  # kebab-case
        with pytest.raises(ValidationError):
            MarkMetadata(app="terminal", custom={"CamelCase": "value"})  # CamelCase
        with pytest.raises(ValidationError):
            MarkMetadata(app="terminal", custom={"123invalid": "value"})  # starts with digit

    def test_to_sway_marks_basic(self):
        """Test converting basic mark to Sway mark strings."""
        mark = MarkMetadata(app="terminal")
        marks = mark.to_sway_marks()
        assert marks == ["i3pm_app:terminal"]

    def test_to_sway_marks_full(self):
        """Test converting full mark to Sway mark strings."""
        mark = MarkMetadata(
            app="code",
            project="nixos",
            workspace="5",
            scope="scoped"
        )
        marks = mark.to_sway_marks()
        assert "i3pm_app:code" in marks
        assert "i3pm_project:nixos" in marks
        assert "i3pm_ws:5" in marks
        assert "i3pm_scope:scoped" in marks

    def test_to_sway_marks_with_custom(self):
        """Test converting mark with custom metadata to Sway mark strings."""
        mark = MarkMetadata(
            app="terminal",
            custom={"session_id": "abc123", "window_type": "floating"}
        )
        marks = mark.to_sway_marks()
        assert "i3pm_app:terminal" in marks
        assert "i3pm_custom:session_id:abc123" in marks
        assert "i3pm_custom:window_type:floating" in marks

    def test_from_sway_marks_basic(self):
        """Test parsing basic mark from Sway mark strings."""
        marks = ["i3pm_app:terminal"]
        mark = MarkMetadata.from_sway_marks(marks)
        assert mark.app == "terminal"
        assert mark.project is None

    def test_from_sway_marks_full(self):
        """Test parsing full mark from Sway mark strings."""
        marks = [
            "i3pm_app:code",
            "i3pm_project:nixos",
            "i3pm_ws:5",
            "i3pm_scope:scoped"
        ]
        mark = MarkMetadata.from_sway_marks(marks)
        assert mark.app == "code"
        assert mark.project == "nixos"
        assert mark.workspace == "5"
        assert mark.scope == "scoped"

    def test_from_sway_marks_with_custom(self):
        """Test parsing mark with custom metadata from Sway mark strings."""
        marks = [
            "i3pm_app:terminal",
            "i3pm_custom:session_id:abc123",
            "i3pm_custom:window_type:floating"
        ]
        mark = MarkMetadata.from_sway_marks(marks)
        assert mark.app == "terminal"
        assert mark.custom == {
            "session_id": "abc123",
            "window_type": "floating"
        }

    def test_from_sway_marks_ignores_non_i3pm(self):
        """Test that parsing ignores non-i3pm marks (forward compatibility)."""
        marks = [
            "i3pm_app:terminal",
            "some-other-mark",
            "user-defined-mark",
            "i3pm_project:nixos"
        ]
        mark = MarkMetadata.from_sway_marks(marks)
        assert mark.app == "terminal"
        assert mark.project == "nixos"

    def test_roundtrip_serialization(self):
        """Test that mark can be serialized and deserialized."""
        original = MarkMetadata(
            app="code",
            project="nixos",
            workspace="5",
            scope="scoped",
            custom={"session_id": "abc123"}
        )
        marks = original.to_sway_marks()
        restored = MarkMetadata.from_sway_marks(marks)

        assert restored.app == original.app
        assert restored.project == original.project
        assert restored.workspace == original.workspace
        assert restored.scope == original.scope
        assert restored.custom == original.custom


class TestWindowMarkQuery:
    """Test WindowMarkQuery model for Feature 076."""

    def test_basic_query_creation(self):
        """Test creating basic query."""
        query = WindowMarkQuery(app="terminal")
        assert query.app == "terminal"
        assert query.project is None

    def test_full_query_creation(self):
        """Test creating query with all filters."""
        query = WindowMarkQuery(
            app="code",
            project="nixos",
            workspace=5,
            scope="scoped",
            custom_key="session_id",
            custom_value="abc123"
        )
        assert query.app == "code"
        assert query.project == "nixos"
        assert query.workspace == 5
        assert query.scope == "scoped"
        assert query.custom_key == "session_id"
        assert query.custom_value == "abc123"

    def test_workspace_validation(self):
        """Test workspace must be 1-70."""
        # Valid workspaces
        WindowMarkQuery(app="terminal", workspace=1)
        WindowMarkQuery(app="terminal", workspace=70)

        # Invalid workspaces
        with pytest.raises(ValidationError):
            WindowMarkQuery(app="terminal", workspace=0)
        with pytest.raises(ValidationError):
            WindowMarkQuery(app="terminal", workspace=71)

    def test_custom_value_requires_key(self):
        """Test custom_value requires custom_key."""
        # Valid: key and value together
        WindowMarkQuery(app="terminal", custom_key="session_id", custom_value="123")

        # Valid: key without value
        WindowMarkQuery(app="terminal", custom_key="session_id")

        # Invalid: value without key
        with pytest.raises(ValidationError):
            WindowMarkQuery(app="terminal", custom_value="123")

    def test_is_empty(self):
        """Test is_empty property."""
        # Empty query
        query = WindowMarkQuery()
        assert query.is_empty is True

        # Non-empty queries
        assert WindowMarkQuery(app="terminal").is_empty is False
        assert WindowMarkQuery(project="nixos").is_empty is False
        assert WindowMarkQuery(workspace=5).is_empty is False
        assert WindowMarkQuery(scope="scoped").is_empty is False
        assert WindowMarkQuery(custom_key="session_id").is_empty is False

    def test_to_sway_marks(self):
        """Test converting query to Sway mark strings."""
        query = WindowMarkQuery(
            app="code",
            project="nixos",
            workspace=5,
            scope="scoped",
            custom_key="session_id",
            custom_value="abc123"
        )
        marks = query.to_sway_marks()
        assert "i3pm_app:code" in marks
        assert "i3pm_project:nixos" in marks
        assert "i3pm_ws:5" in marks
        assert "i3pm_scope:scoped" in marks
        assert "i3pm_custom:session_id:abc123" in marks

    def test_to_sway_marks_custom_key_without_value(self):
        """Test query with custom_key but no custom_value."""
        query = WindowMarkQuery(app="terminal", custom_key="session_id")
        marks = query.to_sway_marks()
        assert "i3pm_app:terminal" in marks
        assert "i3pm_custom:session_id:" in marks  # Match any value for this key


class TestUnifiedMarkFormat:
    """Test Feature 103 unified mark format SCOPE:APP:PROJECT:WINDOW_ID."""

    def test_to_unified_mark_basic(self):
        """Test converting to unified mark string."""
        mark = MarkMetadata(app="terminal", project="nixos", scope="scoped")
        unified = mark.to_unified_mark(12345)
        assert unified == "scoped:terminal:nixos:12345"

    def test_to_unified_mark_global(self):
        """Test converting global scope to unified mark."""
        mark = MarkMetadata(app="firefox", scope="global")
        unified = mark.to_unified_mark(99999)
        assert unified == "global:firefox:global:99999"

    def test_to_unified_mark_defaults(self):
        """Test unified mark with default scope and project."""
        mark = MarkMetadata(app="code")
        unified = mark.to_unified_mark(54321)
        assert unified == "scoped:code:global:54321"

    def test_from_unified_mark_basic(self):
        """Test parsing unified mark string."""
        mark = MarkMetadata.from_unified_mark("scoped:terminal:nixos:12345")
        assert mark is not None
        assert mark.app == "terminal"
        assert mark.project == "nixos"
        assert mark.scope == "scoped"

    def test_from_unified_mark_global_project(self):
        """Test parsing unified mark with 'global' project."""
        mark = MarkMetadata.from_unified_mark("global:firefox:global:99999")
        assert mark is not None
        assert mark.app == "firefox"
        assert mark.project is None  # "global" becomes None
        assert mark.scope == "global"

    def test_from_unified_mark_qualified_project(self):
        """Test parsing unified mark with qualified project name (contains colon)."""
        mark = MarkMetadata.from_unified_mark("scoped:terminal:vpittamp/nixos-config:main:12345")
        assert mark is not None
        assert mark.app == "terminal"
        assert mark.project == "vpittamp/nixos-config:main"
        assert mark.scope == "scoped"

    def test_from_unified_mark_invalid_format(self):
        """Test that invalid formats return None."""
        # Wrong prefix
        assert MarkMetadata.from_unified_mark("invalid:terminal:nixos:12345") is None
        # Too few parts
        assert MarkMetadata.from_unified_mark("scoped:terminal:12345") is None
        # Non-numeric window_id
        assert MarkMetadata.from_unified_mark("scoped:terminal:nixos:notanumber") is None

    def test_from_sway_marks_prefers_unified(self):
        """Test that from_sway_marks prefers unified format over legacy."""
        marks = [
            "i3pm_app:oldapp",
            "i3pm_project:oldproject",
            "scoped:newapp:newproject:12345"
        ]
        mark = MarkMetadata.from_sway_marks(marks)
        assert mark.app == "newapp"
        assert mark.project == "newproject"

    def test_unified_roundtrip(self):
        """Test roundtrip: metadata -> unified mark -> metadata."""
        original = MarkMetadata(app="code", project="nixos", scope="scoped")
        window_id = 54321
        unified = original.to_unified_mark(window_id)
        restored = MarkMetadata.from_unified_mark(unified)

        assert restored is not None
        assert restored.app == original.app
        assert restored.project == original.project
        assert restored.scope == original.scope


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
