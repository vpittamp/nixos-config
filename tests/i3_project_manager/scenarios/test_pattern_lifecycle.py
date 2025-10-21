"""Integration test for complete pattern lifecycle.

Tests the end-to-end flow: add pattern → match window → classify → save → reload daemon.
This verifies the integration between PatternRule, AppClassConfig, and the daemon system.
"""

import json
import tempfile
from pathlib import Path

import pytest

from i3_project_manager.core.config import AppClassConfig
from i3_project_manager.models.pattern import PatternRule


class TestPatternLifecycle:
    """Integration test for complete pattern lifecycle (FR-132)."""

    def test_add_pattern_classify_and_persist(self):
        """
        Complete workflow: add pattern → classify window → save → reload → verify.

        Steps:
        1. Create AppClassConfig with temp config file
        2. Add a pattern rule (glob:pwa-* → global)
        3. Verify pattern matches target window class
        4. Verify is_scoped() returns False for matched class
        5. Save config to disk
        6. Create new AppClassConfig instance (simulating reload)
        7. Verify pattern persists and still matches
        """
        # Step 1: Create temp config file (will be non-existent for auto-creation)
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=True) as f:
            temp_config_path = Path(f.name)

        try:
            # Step 2: Create AppClassConfig and add pattern
            # File doesn't exist, so load() will create default config
            config = AppClassConfig(config_file=temp_config_path)
            config.load()  # Creates default config

            pattern = PatternRule(
                pattern="glob:pwa-*",
                scope="global",
                priority=100,
                description="All PWAs are global apps",
            )
            config.add_pattern(pattern)

            # Step 3: Verify pattern matches target window class
            assert pattern.matches("pwa-youtube") is True
            assert pattern.matches("pwa-spotify") is True
            assert pattern.matches("firefox") is False

            # Step 4: Verify is_scoped() respects pattern classification
            # pwa-youtube should be classified as global (not scoped)
            assert config.is_scoped("pwa-youtube") is False
            assert config.is_global("pwa-youtube") is True

            # Step 5: Save config to disk
            config.save()

            # Verify file was created
            assert temp_config_path.exists()

            # Verify JSON structure
            with temp_config_path.open("r") as f:
                data = json.load(f)

            assert "class_patterns" in data
            assert len(data["class_patterns"]) >= 1

            # Find our pattern
            pwa_pattern = next(
                (p for p in data["class_patterns"] if p["pattern"] == "glob:pwa-*"),
                None,
            )
            assert pwa_pattern is not None
            assert pwa_pattern["scope"] == "global"
            assert pwa_pattern["priority"] == 100
            assert pwa_pattern["description"] == "All PWAs are global apps"

            # Step 6: Create new AppClassConfig instance (simulating daemon reload)
            config2 = AppClassConfig(config_file=temp_config_path)
            config2.load()

            # Step 7: Verify pattern persists and still matches
            assert len(config2.class_patterns) >= 1

            # Find the pattern again
            pwa_pattern_obj = next(
                (p for p in config2.class_patterns if p.pattern == "glob:pwa-*"),
                None,
            )
            assert pwa_pattern_obj is not None
            assert pwa_pattern_obj.scope == "global"
            assert pwa_pattern_obj.priority == 100

            # Verify matching still works
            assert pwa_pattern_obj.matches("pwa-youtube") is True
            assert config2.is_scoped("pwa-youtube") is False

        finally:
            # Cleanup temp file
            if temp_config_path.exists():
                temp_config_path.unlink()

    def test_pattern_precedence_persists_across_reload(self):
        """
        Verify pattern precedence order persists after save/reload.

        Steps:
        1. Add multiple patterns with different priorities
        2. Verify precedence order (highest priority first)
        3. Save and reload
        4. Verify precedence order still correct
        """
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=True) as f:
            temp_config_path = Path(f.name)

        try:
            config = AppClassConfig(config_file=temp_config_path)
            config.load()

            # Add patterns with different priorities
            pattern1 = PatternRule(pattern="glob:app-*", scope="scoped", priority=50)
            pattern2 = PatternRule(pattern="glob:app-test-*", scope="global", priority=100)
            pattern3 = PatternRule(pattern="glob:app-*", scope="global", priority=10)

            config.add_pattern(pattern1)
            config.add_pattern(pattern2)
            config.add_pattern(pattern3)

            # Verify precedence: pattern2 (100) > pattern1 (50) > pattern3 (10)
            sorted_patterns = config.list_patterns()
            assert sorted_patterns[0].priority == 100
            assert sorted_patterns[1].priority == 50
            assert sorted_patterns[2].priority == 10

            # For "app-test-foo", both pattern1 and pattern2 match
            # But pattern2 has higher priority (100) and says global
            assert config.is_scoped("app-test-foo") is False

            # Save and reload
            config.save()

            config2 = AppClassConfig(config_file=temp_config_path)
            config2.load()

            # Verify precedence still correct after reload
            sorted_patterns2 = config2.list_patterns()
            assert len(sorted_patterns2) == 3
            assert sorted_patterns2[0].priority == 100
            assert sorted_patterns2[1].priority == 50
            assert sorted_patterns2[2].priority == 10

            # Verify matching behavior unchanged
            assert config2.is_scoped("app-test-foo") is False

        finally:
            if temp_config_path.exists():
                temp_config_path.unlink()

    def test_remove_pattern_and_verify_classification_changes(self):
        """
        Test removing a pattern and verifying classification changes accordingly.

        Steps:
        1. Add pattern that marks "test-*" as global
        2. Verify "test-app" is global
        3. Remove pattern
        4. Verify "test-app" now defaults to scoped (unknown defaults to scoped)
        5. Save and reload
        6. Verify pattern removal persists
        """
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=True) as f:
            temp_config_path = Path(f.name)

        try:
            config = AppClassConfig(config_file=temp_config_path)
            config.load()

            # Step 1: Add pattern
            pattern = PatternRule(pattern="glob:test-*", scope="global", priority=50)
            config.add_pattern(pattern)

            # Step 2: Verify classification
            assert config.is_global("test-app") is True
            assert config.is_scoped("test-app") is False

            # Step 3: Remove pattern
            removed = config.remove_pattern("glob:test-*")
            assert removed is True

            # Verify pattern no longer in list
            remaining_patterns = [p for p in config.class_patterns if p.pattern == "glob:test-*"]
            assert len(remaining_patterns) == 0

            # Step 4: Verify classification changed to default (scoped)
            assert config.is_scoped("test-app") is True  # Unknown classes default to scoped
            assert config.is_global("test-app") is False

            # Step 5: Save and reload
            config.save()

            config2 = AppClassConfig(config_file=temp_config_path)
            config2.load()

            # Step 6: Verify pattern removal persists
            test_patterns = [p for p in config2.class_patterns if p.pattern == "glob:test-*"]
            assert len(test_patterns) == 0

            # Verify classification still matches expected behavior
            assert config2.is_scoped("test-app") is True

        finally:
            if temp_config_path.exists():
                temp_config_path.unlink()

    def test_explicit_class_overrides_pattern(self):
        """
        Verify explicit class lists have precedence over patterns.

        Precedence order: explicit scoped_classes > explicit global_classes > patterns > default

        Steps:
        1. Add pattern that matches "Code" as global
        2. Add "Code" to explicit scoped_classes
        3. Verify "Code" is classified as scoped (explicit list wins)
        4. Save and reload
        5. Verify precedence still holds
        """
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=True) as f:
            temp_config_path = Path(f.name)

        try:
            config = AppClassConfig(config_file=temp_config_path)
            config.load()

            # Step 1: Add pattern that marks "TestEditor" as global
            pattern = PatternRule(pattern="TestEditor", scope="global", priority=100)
            config.add_pattern(pattern)

            # Initially "TestEditor" would be classified as global by pattern
            assert config.is_global("TestEditor") is True

            # Step 2: Add "TestEditor" to explicit scoped_classes
            config.add_scoped_class("TestEditor")

            # Step 3: Verify explicit list overrides pattern
            assert config.is_scoped("TestEditor") is True
            assert config.is_global("TestEditor") is False

            # Step 4: Save and reload
            config.save()

            config2 = AppClassConfig(config_file=temp_config_path)
            config2.load()

            # Step 5: Verify precedence still holds after reload
            assert "TestEditor" in config2.scoped_classes
            assert config2.is_scoped("TestEditor") is True

            # Pattern still exists but is overridden
            test_pattern = next(
                (p for p in config2.class_patterns if p.pattern == "TestEditor"), None
            )
            assert test_pattern is not None
            assert test_pattern.scope == "global"  # Pattern says global
            # But explicit list wins
            assert config2.is_scoped("TestEditor") is True

        finally:
            if temp_config_path.exists():
                temp_config_path.unlink()
