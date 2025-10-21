"""Unit tests for Classification model."""

import pytest
from pathlib import Path
import sys

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"))
from pattern_resolver import Classification


class TestClassification:
    """Test Classification model."""

    def test_valid_classification_scoped(self):
        """Test creating valid scoped classification."""
        cls = Classification(
            scope="scoped",
            workspace=2,
            source="project"
        )
        
        assert cls.scope == "scoped"
        assert cls.workspace == 2
        assert cls.source == "project"
        assert cls.matched_rule is None

    def test_valid_classification_global(self):
        """Test creating valid global classification."""
        cls = Classification(
            scope="global",
            workspace=None,
            source="default"
        )
        
        assert cls.scope == "global"
        assert cls.workspace is None
        assert cls.source == "default"

    def test_workspace_validation_low(self):
        """Test workspace validation (must be >= 1)."""
        with pytest.raises(ValueError, match="Workspace must be 1-9"):
            Classification(
                scope="scoped",
                workspace=0,
                source="window_rule"
            )

    def test_workspace_validation_high(self):
        """Test workspace validation (must be <= 9)."""
        with pytest.raises(ValueError, match="Workspace must be 1-9"):
            Classification(
                scope="scoped",
                workspace=10,
                source="window_rule"
            )

    def test_valid_workspace_range(self):
        """Test all valid workspace numbers."""
        for ws_num in range(1, 10):
            cls = Classification(
                scope="scoped",
                workspace=ws_num,
                source="window_rule"
            )
            assert cls.workspace == ws_num

    def test_workspace_none_allowed(self):
        """Test workspace can be None."""
        cls = Classification(
            scope="scoped",
            workspace=None,
            source="app_classes"
        )
        
        assert cls.workspace is None

    def test_all_source_types(self):
        """Test all valid source types."""
        valid_sources = ["project", "window_rule", "app_classes", "default"]
        
        for source in valid_sources:
            cls = Classification(
                scope="scoped",
                workspace=None,
                source=source
            )
            assert cls.source == source

    def test_all_scope_types(self):
        """Test all valid scope types."""
        valid_scopes = ["scoped", "global"]
        
        for scope in valid_scopes:
            cls = Classification(
                scope=scope,
                workspace=None,
                source="default"
            )
            assert cls.scope == scope

    def test_to_json_without_matched_rule(self):
        """Test JSON serialization without matched rule."""
        cls = Classification(
            scope="scoped",
            workspace=2,
            source="project"
        )
        
        result = cls.to_json()
        
        assert result == {
            "scope": "scoped",
            "workspace": 2,
            "source": "project"
        }

    def test_to_json_with_matched_rule(self):
        """Test JSON serialization with matched rule."""
        # Import here to avoid circular dependency in test
        sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
        from i3_project_manager.models.pattern import PatternRule
        from window_rules import WindowRule
        
        pattern = PatternRule("Code", "scoped", priority=250)
        rule = WindowRule(pattern_rule=pattern, workspace=2)
        
        cls = Classification(
            scope="scoped",
            workspace=2,
            source="window_rule",
            matched_rule=rule
        )
        
        result = cls.to_json()
        
        assert result["scope"] == "scoped"
        assert result["workspace"] == 2
        assert result["source"] == "window_rule"
        assert result["matched_pattern"] == "Code"

    def test_classification_for_debugging(self):
        """Test classification provides debugging information."""
        cls = Classification(
            scope="global",
            workspace=4,
            source="window_rule"
        )
        
        # Should have clear source attribution
        assert cls.source in ["project", "window_rule", "app_classes", "default"]
        
        # Workspace is clearly defined
        assert isinstance(cls.workspace, int) or cls.workspace is None
        
        # Scope is clearly defined
        assert cls.scope in ["scoped", "global"]
