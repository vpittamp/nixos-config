"""Unit tests for AppClassification with PatternRule support."""

import pytest
from pathlib import Path
import sys

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
from i3_project_manager.core.models import AppClassification
from i3_project_manager.models.pattern import PatternRule


class TestAppClassificationListFormat:
    """Test AppClassification with List[PatternRule] format."""

    def test_list_format_dict_items(self):
        """Test list of dict items converted to PatternRule."""
        app_class = AppClassification(
            class_patterns=[
                {"pattern": "glob:FFPWA-*", "scope": "global", "priority": 200},
                {"pattern": "Code", "scope": "scoped", "priority": 250}
            ]
        )
        
        assert len(app_class.class_patterns) == 2
        assert all(isinstance(p, PatternRule) for p in app_class.class_patterns)

    def test_list_format_pattern_rule_instances(self):
        """Test list of PatternRule instances preserved."""
        rules = [
            PatternRule("glob:FFPWA-*", "global", priority=200),
            PatternRule("Code", "scoped", priority=250)
        ]
        
        app_class = AppClassification(class_patterns=rules)
        
        assert len(app_class.class_patterns) == 2
        assert app_class.class_patterns[0].pattern == "glob:FFPWA-*"
        assert app_class.class_patterns[1].pattern == "Code"

    def test_list_format_priority_preservation(self):
        """Test priorities are preserved from dict items."""
        app_class = AppClassification(
            class_patterns=[
                {"pattern": "High", "scope": "scoped", "priority": 300},
                {"pattern": "Low", "scope": "scoped", "priority": 50}
            ]
        )
        
        high_pattern = next(p for p in app_class.class_patterns if p.pattern == "High")
        assert high_pattern.priority == 300
        
        low_pattern = next(p for p in app_class.class_patterns if p.pattern == "Low")
        assert low_pattern.priority == 50

    def test_list_format_description_preservation(self):
        """Test descriptions are preserved."""
        app_class = AppClassification(
            class_patterns=[
                {"pattern": "glob:FFPWA-*", "scope": "global", "priority": 200, "description": "Firefox PWAs"}
            ]
        )
        
        assert app_class.class_patterns[0].description == "Firefox PWAs"

    def test_list_format_default_priority(self):
        """Test default priority 100 when not specified."""
        app_class = AppClassification(
            class_patterns=[
                {"pattern": "Test", "scope": "scoped"}  # No priority
            ]
        )
        
        assert app_class.class_patterns[0].priority == 100


class TestAppClassificationEmptyPatterns:
    """Test AppClassification with empty patterns."""

    def test_empty_list(self):
        """Test empty list."""
        app_class = AppClassification(class_patterns=[])
        
        assert app_class.class_patterns == []

    def test_default_value(self):
        """Test default value."""
        app_class = AppClassification()
        
        assert app_class.class_patterns == []


class TestAppClassificationSerialization:
    """Test AppClassification JSON serialization."""

    def test_to_json_with_pattern_list(self):
        """Test serialization with PatternRule list."""
        app_class = AppClassification(
            scoped_classes=["Code"],
            global_classes=["firefox"],
            class_patterns=[
                {"pattern": "glob:FFPWA-*", "scope": "global", "priority": 200, "description": "PWAs"}
            ]
        )
        
        result = app_class.to_json()
        
        assert result["scoped_classes"] == ["Code"]
        assert result["global_classes"] == ["firefox"]
        assert len(result["class_patterns"]) == 1
        assert result["class_patterns"][0]["pattern"] == "glob:FFPWA-*"
        assert result["class_patterns"][0]["priority"] == 200

    def test_from_json_list_format(self):
        """Test deserialization from list format."""
        data = {
            "scoped_classes": ["Code"],
            "global_classes": ["firefox"],
            "class_patterns": [
                {"pattern": "glob:FFPWA-*", "scope": "global", "priority": 200}
            ]
        }
        
        app_class = AppClassification.from_json(data)
        
        assert len(app_class.class_patterns) == 1
        assert app_class.class_patterns[0].pattern == "glob:FFPWA-*"

    def test_roundtrip_serialization(self):
        """Test serialization roundtrip maintains data."""
        original = AppClassification(
            scoped_classes=["Code", "Ghostty"],
            global_classes=["firefox", "mpv"],
            class_patterns=[
                {"pattern": "glob:FFPWA-*", "scope": "global", "priority": 200, "description": "Firefox PWAs"},
                {"pattern": "Code", "scope": "scoped", "priority": 250, "description": "VS Code"}
            ]
        )
        
        # Serialize and deserialize
        data = original.to_json()
        restored = AppClassification.from_json(data)
        
        assert restored.scoped_classes == original.scoped_classes
        assert restored.global_classes == original.global_classes
        assert len(restored.class_patterns) == len(original.class_patterns)
        assert restored.class_patterns[0].pattern == original.class_patterns[0].pattern
        assert restored.class_patterns[0].priority == original.class_patterns[0].priority


class TestAppClassificationValidation:
    """Test AppClassification validation."""

    def test_invalid_pattern_item_type(self):
        """Test invalid pattern item type raises error."""
        with pytest.raises(ValueError, match="Invalid class_patterns item"):
            AppClassification(class_patterns=["invalid string item"])

    def test_mixed_valid_items(self):
        """Test mixing PatternRule instances and dicts works."""
        pattern_instance = PatternRule("Code", "scoped", priority=250)
        pattern_dict = {"pattern": "glob:FFPWA-*", "scope": "global", "priority": 200}
        
        app_class = AppClassification(class_patterns=[pattern_instance, pattern_dict])
        
        assert len(app_class.class_patterns) == 2
        assert all(isinstance(p, PatternRule) for p in app_class.class_patterns)
