"""Unit tests for WindowRule model."""

import pytest
from pathlib import Path
import json
import tempfile
import sys

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"))

from i3_project_manager.models.pattern import PatternRule
from window_rules import WindowRule, load_window_rules


class TestWindowRule:
    """Test WindowRule model."""

    def test_valid_window_rule(self):
        """Test creating valid window rule."""
        pattern = PatternRule("glob:FFPWA-*", "global", priority=200)
        rule = WindowRule(pattern_rule=pattern, workspace=4)
        
        assert rule.pattern_rule.pattern == "glob:FFPWA-*"
        assert rule.workspace == 4
        assert rule.scope == "global"
        assert rule.priority == 200

    def test_workspace_validation_low(self):
        """Test workspace validation (must be >= 1)."""
        pattern = PatternRule("Code", "scoped", priority=250)
        
        with pytest.raises(ValueError, match="Workspace must be 1-9"):
            WindowRule(pattern_rule=pattern, workspace=0)

    def test_workspace_validation_high(self):
        """Test workspace validation (must be <= 9)."""
        pattern = PatternRule("Code", "scoped", priority=250)
        
        with pytest.raises(ValueError, match="Workspace must be 1-9"):
            WindowRule(pattern_rule=pattern, workspace=10)

    def test_valid_workspace_range(self):
        """Test all valid workspace numbers."""
        pattern = PatternRule("Test", "scoped", priority=100)
        
        for ws_num in range(1, 10):
            rule = WindowRule(pattern_rule=pattern, workspace=ws_num)
            assert rule.workspace == ws_num

    def test_invalid_modifier(self):
        """Test modifier validation."""
        pattern = PatternRule("Test", "scoped", priority=100)
        
        with pytest.raises(ValueError, match="Invalid modifier"):
            WindowRule(pattern_rule=pattern, modifier="INVALID")

    def test_valid_modifiers(self):
        """Test all valid modifiers."""
        pattern = PatternRule("Test", "scoped", priority=100)
        valid_modifiers = ["GLOBAL", "DEFAULT", "ON_CLOSE", "TITLE"]
        
        for modifier in valid_modifiers:
            rule = WindowRule(pattern_rule=pattern, modifier=modifier)
            assert rule.modifier == modifier

    def test_blacklist_without_global(self):
        """Test blacklist requires GLOBAL modifier."""
        pattern = PatternRule("Test", "scoped", priority=100)
        
        with pytest.raises(ValueError, match="Blacklist only valid with GLOBAL"):
            WindowRule(pattern_rule=pattern, blacklist=["URxvt"])

    def test_blacklist_with_global(self):
        """Test blacklist with GLOBAL modifier."""
        pattern = PatternRule("glob:*", "global", priority=10)
        rule = WindowRule(
            pattern_rule=pattern,
            modifier="GLOBAL",
            blacklist=["URxvt", "Alacritty"]
        )
        
        assert rule.blacklist == ["URxvt", "Alacritty"]

    def test_matches_basic(self):
        """Test basic pattern matching."""
        pattern = PatternRule("Code", "scoped", priority=250)
        rule = WindowRule(pattern_rule=pattern, workspace=2)
        
        assert rule.matches("Code") is True
        assert rule.matches("Firefox") is False

    def test_matches_glob_pattern(self):
        """Test glob pattern matching."""
        pattern = PatternRule("glob:FFPWA-*", "global", priority=200)
        rule = WindowRule(pattern_rule=pattern, workspace=4)
        
        assert rule.matches("FFPWA-01K665SPD8EPMP3JTW02JM1M0Z") is True
        assert rule.matches("Firefox") is False

    def test_matches_with_blacklist(self):
        """Test matching with blacklist exclusion."""
        pattern = PatternRule("glob:*", "global", priority=10)
        rule = WindowRule(
            pattern_rule=pattern,
            modifier="GLOBAL",
            blacklist=["URxvt", "Alacritty"]
        )
        
        assert rule.matches("Code") is True
        assert rule.matches("URxvt") is False  # Blacklisted
        assert rule.matches("Alacritty") is False  # Blacklisted

    def test_priority_property(self):
        """Test priority property delegates to pattern_rule."""
        pattern = PatternRule("Test", "scoped", priority=300)
        rule = WindowRule(pattern_rule=pattern)
        
        assert rule.priority == 300

    def test_scope_property(self):
        """Test scope property delegates to pattern_rule."""
        pattern = PatternRule("Test", "global", priority=100)
        rule = WindowRule(pattern_rule=pattern)
        
        assert rule.scope == "global"

    def test_to_json_minimal(self):
        """Test JSON serialization with minimal fields."""
        pattern = PatternRule("Code", "scoped", priority=250)
        rule = WindowRule(pattern_rule=pattern)
        
        result = rule.to_json()
        
        assert result["pattern_rule"]["pattern"] == "Code"
        assert result["pattern_rule"]["scope"] == "scoped"
        assert result["pattern_rule"]["priority"] == 250
        assert "workspace" not in result
        assert "command" not in result

    def test_to_json_full(self):
        """Test JSON serialization with all fields."""
        pattern = PatternRule("glob:FFPWA-*", "global", priority=200, description="Firefox PWAs")
        rule = WindowRule(
            pattern_rule=pattern,
            workspace=4,
            command="floating enable",
            modifier="GLOBAL",
            blacklist=["URxvt"]
        )
        
        result = rule.to_json()
        
        assert result["pattern_rule"]["pattern"] == "glob:FFPWA-*"
        assert result["workspace"] == 4
        assert result["command"] == "floating enable"
        assert result["modifier"] == "GLOBAL"
        assert result["blacklist"] == ["URxvt"]

    def test_from_json(self):
        """Test JSON deserialization."""
        data = {
            "pattern_rule": {
                "pattern": "Code",
                "scope": "scoped",
                "priority": 250,
                "description": "VS Code editor"
            },
            "workspace": 2
        }
        
        rule = WindowRule.from_json(data)
        
        assert rule.pattern_rule.pattern == "Code"
        assert rule.pattern_rule.scope == "scoped"
        assert rule.workspace == 2

    def test_from_json_missing_pattern_rule(self):
        """Test deserialization fails without pattern_rule."""
        data = {"workspace": 2}
        
        with pytest.raises(ValueError, match="Missing required 'pattern_rule'"):
            WindowRule.from_json(data)

    def test_roundtrip_serialization(self):
        """Test serialization roundtrip."""
        pattern = PatternRule("title:^Yazi:.*", "scoped", priority=300, description="Yazi file manager")
        original = WindowRule(
            pattern_rule=pattern,
            workspace=5,
            command="focus"
        )
        
        data = original.to_json()
        restored = WindowRule.from_json(data)
        
        assert restored.pattern_rule.pattern == original.pattern_rule.pattern
        assert restored.workspace == original.workspace
        assert restored.command == original.command


class TestLoadWindowRules:
    """Test window rules loading."""

    def test_load_from_file(self):
        """Test loading window rules from file."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            rules_data = [
                {
                    "pattern_rule": {
                        "pattern": "glob:FFPWA-*",
                        "scope": "global",
                        "priority": 200
                    },
                    "workspace": 4
                },
                {
                    "pattern_rule": {
                        "pattern": "Code",
                        "scope": "scoped",
                        "priority": 250
                    },
                    "workspace": 2
                }
            ]
            json.dump(rules_data, f)
            config_path = f.name

        try:
            rules = load_window_rules(config_path)
            
            # Should be sorted by priority (highest first)
            assert len(rules) == 2
            assert rules[0].priority == 250  # Code (higher priority)
            assert rules[1].priority == 200  # FFPWA
        finally:
            Path(config_path).unlink()

    def test_load_nonexistent_file(self):
        """Test loading from non-existent file returns empty list."""
        rules = load_window_rules("/tmp/nonexistent-window-rules.json")
        
        assert rules == []

    def test_load_invalid_json(self):
        """Test loading invalid JSON raises error."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write("{invalid json")
            config_path = f.name

        try:
            with pytest.raises(ValueError, match="Invalid JSON"):
                load_window_rules(config_path)
        finally:
            Path(config_path).unlink()

    def test_load_non_array_json(self):
        """Test loading non-array JSON raises error."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump({"not": "an array"}, f)
            config_path = f.name

        try:
            with pytest.raises(ValueError, match="must be a JSON array"):
                load_window_rules(config_path)
        finally:
            Path(config_path).unlink()

    def test_priority_sorting(self):
        """Test rules are sorted by priority."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            rules_data = [
                {"pattern_rule": {"pattern": "Low", "scope": "scoped", "priority": 100}, "workspace": 1},
                {"pattern_rule": {"pattern": "High", "scope": "scoped", "priority": 300}, "workspace": 3},
                {"pattern_rule": {"pattern": "Mid", "scope": "scoped", "priority": 200}, "workspace": 2}
            ]
            json.dump(rules_data, f)
            config_path = f.name

        try:
            rules = load_window_rules(config_path)
            
            # Sorted by priority descending
            assert rules[0].pattern_rule.pattern == "High"  # 300
            assert rules[1].pattern_rule.pattern == "Mid"   # 200
            assert rules[2].pattern_rule.pattern == "Low"   # 100
        finally:
            Path(config_path).unlink()
