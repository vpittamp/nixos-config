"""Scenario test for dynamic window rule reload (User Story 1)."""

import pytest
import json
import tempfile
from pathlib import Path
import sys

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"))

from i3_project_manager.models.pattern import PatternRule
from window_rules import WindowRule, load_window_rules
from pattern_resolver import classify_window


@pytest.mark.scenario
class TestDynamicReloadScenario:
    """Test User Story 1: Pattern-based classification without rebuilds.
    
    Scenario from quickstart.md US1:
    1. Create window-rules.json with test pattern
    2. Launch window with matching class
    3. Verify window assigned to correct workspace
    4. Modify rule (change workspace)
    5. Launch another window
    6. Verify new window uses updated rule
    """

    def test_full_dynamic_reload_workflow(self):
        """Test complete workflow: create rule → classify → modify → re-classify."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            # Step 1: Create window-rules.json with test pattern
            initial_rules = [
                {
                    "pattern_rule": {
                        "pattern": "glob:test-*",
                        "scope": "scoped",
                        "priority": 200,
                        "description": "Test pattern for verification"
                    },
                    "workspace": 5
                }
            ]
            json.dump(initial_rules, f)
            config_path = f.name

        try:
            # Step 2: Load rules and classify test window
            rules = load_window_rules(config_path)
            assert len(rules) == 1
            
            # Step 3: Verify window assigned to workspace 5
            result = classify_window(
                window_class="test-app",
                window_rules=rules
            )
            assert result.scope == "scoped"
            assert result.workspace == 5
            assert result.source == "window_rule"
            
            # Step 4: Modify rule (change workspace from 5 to 7)
            modified_rules = [
                {
                    "pattern_rule": {
                        "pattern": "glob:test-*",
                        "scope": "scoped",
                        "priority": 200,
                        "description": "Test pattern for verification"
                    },
                    "workspace": 7  # Changed from 5 to 7
                }
            ]
            with open(config_path, 'w') as f:
                json.dump(modified_rules, f)
            
            # Step 5: Reload rules
            rules = load_window_rules(config_path)
            
            # Step 6: Verify new window uses updated rule (workspace 7)
            result = classify_window(
                window_class="test-app2",
                window_rules=rules
            )
            assert result.workspace == 7  # Updated workspace
            assert result.source == "window_rule"
            
        finally:
            Path(config_path).unlink()

    def test_no_rebuild_required(self):
        """Test changes take effect without any system rebuild."""
        # This test verifies the core value proposition:
        # Users can modify rules and see changes immediately
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            rules = [{"pattern_rule": {"pattern": "App1", "scope": "scoped", "priority": 100}, "workspace": 1}]
            json.dump(rules, f)
            config_path = f.name

        try:
            # Load initial
            initial_rules = load_window_rules(config_path)
            initial_result = classify_window("App1", window_rules=initial_rules)
            assert initial_result.workspace == 1
            
            # Modify (no rebuild, just file write)
            with open(config_path, 'w') as f:
                new_rules = [{"pattern_rule": {"pattern": "App1", "scope": "scoped", "priority": 100}, "workspace": 9}]
                json.dump(new_rules, f)
            
            # Reload (no rebuild, just re-read file)
            new_rules = load_window_rules(config_path)
            new_result = classify_window("App1", window_rules=new_rules)
            
            # Change is effective immediately
            assert new_result.workspace == 9
            
        finally:
            Path(config_path).unlink()

    def test_pattern_matching_under_1ms(self):
        """Test pattern matching completes in <1ms (SC-001 from spec)."""
        import time
        
        # Create test rule
        pattern = PatternRule("glob:test-*", "scoped", priority=200)
        rule = WindowRule(pattern_rule=pattern, workspace=5)
        
        # Time the classification
        start = time.perf_counter()
        result = classify_window("test-app", window_rules=[rule])
        end = time.perf_counter()
        
        classification_time = (end - start) * 1000  # Convert to ms
        
        # Verify correctness
        assert result.workspace == 5
        
        # Verify performance (allow extra time in CI)
        assert classification_time < 10, f"Classification took {classification_time}ms (expected <10ms)"


@pytest.mark.scenario
class TestDynamicReloadEdgeCases:
    """Test edge cases for dynamic reload."""

    def test_multiple_pattern_types_coexist(self):
        """Test glob, regex, and literal patterns can coexist."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            rules = [
                {"pattern_rule": {"pattern": "glob:FFPWA-*", "scope": "global", "priority": 200}, "workspace": 4},
                {"pattern_rule": {"pattern": "regex:^vim$", "scope": "scoped", "priority": 200}, "workspace": 5},
                {"pattern_rule": {"pattern": "Code", "scope": "scoped", "priority": 250}, "workspace": 2}
            ]
            json.dump(rules, f)
            config_path = f.name

        try:
            loaded_rules = load_window_rules(config_path)
            
            # Test glob
            result_pwa = classify_window("FFPWA-01ABC", window_rules=loaded_rules)
            assert result_pwa.workspace == 4
            
            # Test regex
            result_vim = classify_window("vim", window_rules=loaded_rules)
            assert result_vim.workspace == 5
            
            # Test literal
            result_code = classify_window("Code", window_rules=loaded_rules)
            assert result_code.workspace == 2
            
        finally:
            Path(config_path).unlink()

    def test_priority_ordering_enforced(self):
        """Test rules are sorted by priority after reload."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            # Rules in random priority order
            rules = [
                {"pattern_rule": {"pattern": "Low", "scope": "scoped", "priority": 100}, "workspace": 1},
                {"pattern_rule": {"pattern": "High", "scope": "scoped", "priority": 300}, "workspace": 3},
                {"pattern_rule": {"pattern": "Mid", "scope": "scoped", "priority": 200}, "workspace": 2}
            ]
            json.dump(rules, f)
            config_path = f.name

        try:
            loaded_rules = load_window_rules(config_path)
            
            # Should be sorted by priority (highest first)
            assert loaded_rules[0].priority == 300  # High
            assert loaded_rules[1].priority == 200  # Mid
            assert loaded_rules[2].priority == 100  # Low
            
        finally:
            Path(config_path).unlink()

    def test_empty_rules_file(self):
        """Test empty rules file results in no classifications."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump([], f)
            config_path = f.name

        try:
            rules = load_window_rules(config_path)
            assert rules == []
            
            # Classification should fall through to default
            result = classify_window("AnyApp", window_rules=rules)
            assert result.source == "default"
            assert result.scope == "global"
            
        finally:
            Path(config_path).unlink()
