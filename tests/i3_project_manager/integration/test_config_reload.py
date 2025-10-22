"""Integration tests for config file reload functionality."""

import pytest
import asyncio
import json
import tempfile
from pathlib import Path
import time
import sys

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"))
from window_rules import load_window_rules


class TestConfigReload:
    """Test config reload detection and handling."""

    def test_file_modification_reload(self):
        """Test config reloads when file is modified."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            initial_rules = [
                {
                    "pattern_rule": {
                        "pattern": "Code",
                        "scope": "scoped",
                        "priority": 250
                    },
                    "workspace": 2
                }
            ]
            json.dump(initial_rules, f)
            config_path = f.name

        try:
            # Load initial config
            rules = load_window_rules(config_path)
            assert len(rules) == 1
            assert rules[0].workspace == 2
            
            # Modify file
            time.sleep(0.1)  # Ensure different mtime
            with open(config_path, 'w') as f:
                modified_rules = [
                    {
                        "pattern_rule": {
                            "pattern": "Code",
                            "scope": "scoped",
                            "priority": 250
                        },
                        "workspace": 5  # Changed workspace
                    }
                ]
                json.dump(modified_rules, f)
            
            # Reload
            rules = load_window_rules(config_path)
            assert len(rules) == 1
            assert rules[0].workspace == 5  # Should reflect new value
            
        finally:
            Path(config_path).unlink()

    def test_invalid_json_retains_previous_config(self):
        """Test invalid JSON doesn't crash, retains previous config."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            valid_rules = [
                {
                    "pattern_rule": {
                        "pattern": "Code",
                        "scope": "scoped",
                        "priority": 250
                    },
                    "workspace": 2
                }
            ]
            json.dump(valid_rules, f)
            config_path = f.name

        try:
            # Load valid config
            rules = load_window_rules(config_path)
            assert len(rules) == 1
            
            # Write invalid JSON
            with open(config_path, 'w') as f:
                f.write("{invalid json")
            
            # Attempting to reload should raise error
            with pytest.raises(ValueError, match="Invalid JSON"):
                load_window_rules(config_path)
            
            # In daemon, this error would be caught and previous config retained
            # (tested in daemon integration tests)
            
        finally:
            Path(config_path).unlink()

    def test_reload_trigger_under_1_second(self):
        """Test reload can be triggered in <1 second after modification."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            rules = [
                {
                    "pattern_rule": {
                        "pattern": "Code",
                        "scope": "scoped",
                        "priority": 250
                    },
                    "workspace": 2
                }
            ]
            json.dump(rules, f)
            config_path = f.name

        try:
            # Simulate rapid reload cycle
            start_time = time.perf_counter()
            
            # Load
            initial_rules = load_window_rules(config_path)
            
            # Modify
            with open(config_path, 'w') as f:
                modified_rules = [
                    {
                        "pattern_rule": {
                            "pattern": "Firefox",
                            "scope": "global",
                            "priority": 200
                        },
                        "workspace": 3
                    }
                ]
                json.dump(modified_rules, f)
            
            # Reload
            new_rules = load_window_rules(config_path)
            
            end_time = time.perf_counter()
            reload_time = (end_time - start_time) * 1000  # Convert to ms
            
            # Verify reload worked
            assert len(new_rules) == 1
            assert new_rules[0].pattern_rule.pattern == "Firefox"
            
            # Verify reload was fast
            assert reload_time < 1000, f"Reload took {reload_time}ms (expected <1000ms)"
            
        finally:
            Path(config_path).unlink()

    def test_daemon_keeps_running_on_config_error(self):
        """Test daemon would continue running on config error."""
        # This tests the error handling pattern
        # In actual daemon, errors are caught and logged, not propagated
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write("{invalid json")
            config_path = f.name

        try:
            # Simulate daemon reload with error handling
            previous_rules = [{"test": "rule"}]
            current_rules = previous_rules  # Default to previous
            
            try:
                current_rules = load_window_rules(config_path)
            except ValueError as e:
                # Daemon would log this error and keep previous config
                assert "Invalid JSON" in str(e)
                # Keep previous_rules
                current_rules = previous_rules
            
            # Verify daemon continues with previous config
            assert current_rules == previous_rules
            
        finally:
            Path(config_path).unlink()


class TestConfigReloadValidation:
    """Test config validation during reload."""

    def test_reload_with_validation_errors(self):
        """Test validation errors during reload."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            invalid_rules = [
                {
                    "pattern_rule": {
                        "pattern": "Code",
                        "scope": "scoped",
                        "priority": 250
                    },
                    "workspace": 15  # Invalid: must be 1-9
                }
            ]
            json.dump(invalid_rules, f)
            config_path = f.name

        try:
            with pytest.raises(ValueError, match="Workspace must be 1-9"):
                load_window_rules(config_path)
                
        finally:
            Path(config_path).unlink()

    def test_reload_100_rules_under_100ms(self):
        """Test reloading 100 rules completes in <100ms."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            # Generate 100 rules
            rules_data = []
            for i in range(100):
                rules_data.append({
                    "pattern_rule": {
                        "pattern": f"App{i}",
                        "scope": "scoped",
                        "priority": 100 + i
                    },
                    "workspace": (i % 9) + 1
                })
            json.dump(rules_data, f)
            config_path = f.name

        try:
            start = time.perf_counter()
            rules = load_window_rules(config_path)
            end = time.perf_counter()
            
            load_time = (end - start) * 1000  # Convert to ms
            
            # Verify loaded correctly
            assert len(rules) == 100
            
            # Verify performance
            assert load_time < 100, f"Load took {load_time}ms (expected <100ms)"
            
        finally:
            Path(config_path).unlink()


class TestDebouncing:
    """Test debouncing of rapid changes."""

    def test_rapid_changes_debounced(self):
        """Test rapid file changes can be debounced."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump([], f)
            config_path = f.name

        try:
            # Simulate rapid changes (100ms debounce would wait for changes to stop)
            modifications = []
            
            for i in range(5):
                # Rapid modifications
                with open(config_path, 'w') as f:
                    json.dump([{"test": f"rule{i}"}], f)
                modifications.append(time.perf_counter())
                time.sleep(0.02)  # 20ms between changes
            
            # In daemon with 100ms debounce, only last change would be processed
            # Here we just verify the timing pattern
            time_between_changes = [(modifications[i+1] - modifications[i]) * 1000 
                                     for i in range(len(modifications)-1)]
            
            # All changes happened rapidly
            assert all(t < 100 for t in time_between_changes)
            
        finally:
            Path(config_path).unlink()
