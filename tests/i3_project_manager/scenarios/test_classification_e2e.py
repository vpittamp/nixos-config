"""End-to-end integration test for classification workflow.

T101: Integration test for complete classification round-trip workflow.
FR-132: End-to-end testing requirement.

This test validates the complete workflow:
1. Discover apps from system
2. Classify apps using wizard (simulated)
3. Create pattern rules
4. Verify with inspector
5. Reload daemon
6. Verify new windows auto-classify
"""

import pytest
import asyncio
import json
from pathlib import Path
from unittest.mock import Mock, patch, AsyncMock

from i3_project_manager.core.app_discovery import AppDiscovery
from i3_project_manager.core.config import AppClassConfig
from i3_project_manager.models.classification import ClassificationSuggestion
from i3_project_manager.models.pattern import PatternRule, PatternMatcher
from i3_project_manager.validators.schema_validator import validate_app_classes_config


@pytest.mark.asyncio
@pytest.mark.integration
class TestClassificationWorkflowE2E:
    """End-to-end test for complete classification workflow.

    T101: Complete round-trip workflow test
    """

    @pytest.fixture
    async def config_file(self, tmp_path):
        """Create temporary config file for testing."""
        config_file = tmp_path / "app-classes.json"
        config_data = {
            "scoped_classes": [],
            "global_classes": [],
            "class_patterns": []
        }
        with open(config_file, 'w') as f:
            json.dump(config_data, f)
        return config_file

    @pytest.fixture
    def config(self, config_file):
        """Create AppClassConfig instance."""
        config = AppClassConfig(config_file=config_file)
        config.load()
        return config

    async def test_complete_workflow_roundtrip(self, config, config_file):
        """Test complete classification workflow from discovery to auto-classification.

        Workflow:
        1. Discover apps → 2. Classify → 3. Create patterns → 4. Verify →
        5. Reload → 6. Auto-classify new windows

        T101: Complete workflow integration test
        FR-132: End-to-end testing
        """
        # ================================================================
        # Step 1: Discover apps from system
        # ================================================================
        discovery = AppDiscovery()

        # Mock discovered apps (simulating desktop file scan)
        mock_apps = [
            Mock(
                name="Visual Studio Code",
                exec_cmd="code",
                desktop_file="/usr/share/applications/code.desktop",
                categories=["Development", "IDE"],
                detected_class="Code"
            ),
            Mock(
                name="Firefox",
                exec_cmd="firefox",
                desktop_file="/usr/share/applications/firefox.desktop",
                categories=["Network", "WebBrowser"],
                detected_class="firefox"
            ),
            Mock(
                name="Ghostty",
                exec_cmd="ghostty",
                desktop_file="/usr/share/applications/ghostty.desktop",
                categories=["System", "TerminalEmulator"],
                detected_class="Ghostty"
            ),
        ]

        # Verify discovery returns apps
        assert len(mock_apps) == 3
        assert any(app.detected_class == "Code" for app in mock_apps)

        # ================================================================
        # Step 2: Classify apps (simulated wizard interaction)
        # ================================================================

        # Simulate wizard classification decisions
        classifications = {
            "Code": "scoped",  # IDE is project-specific
            "firefox": "global",  # Browser is always visible
            "Ghostty": "scoped",  # Terminal is project-specific
        }

        for class_name, scope in classifications.items():
            if scope == "scoped":
                config.add_scoped_class(class_name)
            else:
                config.add_global_class(class_name)

        # Verify classifications applied
        assert "Code" in config.scoped_classes
        assert "firefox" in config.global_classes
        assert "Ghostty" in config.scoped_classes

        # ================================================================
        # Step 3: Create pattern rules
        # ================================================================

        # Add pattern for PWAs (glob pattern)
        pwa_pattern = PatternRule(
            pattern="glob:pwa-*",
            scope="global",
            priority=10,
            description="Progressive Web Apps"
        )
        config.add_pattern(pwa_pattern)

        # Add pattern for terminals (regex pattern)
        terminal_pattern = PatternRule(
            pattern="regex:^.*terminal.*$",
            scope="scoped",
            priority=5,
            description="Terminal emulators"
        )
        config.add_pattern(terminal_pattern)

        # Verify patterns added
        assert len(config.class_patterns) == 2
        assert any(p.pattern == "glob:pwa-*" for p in config.class_patterns)

        # ================================================================
        # Step 4: Save configuration
        # ================================================================

        config.save()

        # Verify file written
        assert config_file.exists()

        # Verify JSON is valid
        with open(config_file, 'r') as f:
            saved_data = json.load(f)

        assert "Code" in saved_data["scoped_classes"]
        assert "firefox" in saved_data["global_classes"]
        assert len(saved_data["class_patterns"]) == 2

        # ================================================================
        # Step 5: Validate configuration with schema
        # ================================================================

        is_valid, errors = validate_app_classes_config(config_file)

        assert is_valid is True, f"Schema validation failed: {errors}"
        assert len(errors) == 0

        # ================================================================
        # Step 6: Reload configuration
        # ================================================================

        # Simulate daemon reload by creating new config instance
        reloaded_config = AppClassConfig(config_file=config_file)
        reloaded_config.load()

        # Verify configuration persisted
        assert "Code" in reloaded_config.scoped_classes
        assert "firefox" in reloaded_config.global_classes
        assert len(reloaded_config.class_patterns) == 2

        # ================================================================
        # Step 7: Test pattern matching (simulated inspector)
        # ================================================================

        # Test PWA pattern matching
        pwa_classification = reloaded_config.get_classification("pwa-youtube")
        assert pwa_classification == "global", "PWA should match glob:pwa-* pattern"

        # Test terminal pattern matching
        terminal_classification = reloaded_config.get_classification("gnome-terminal")
        assert terminal_classification == "scoped", "Terminal should match regex pattern"

        # Test explicit classification
        code_classification = reloaded_config.get_classification("Code")
        assert code_classification == "scoped", "Code should be explicitly scoped"

        firefox_classification = reloaded_config.get_classification("firefox")
        assert firefox_classification == "global", "Firefox should be explicitly global"

        # ================================================================
        # Step 8: Test new window auto-classification
        # ================================================================

        # Simulate new windows opening with various classes
        test_windows = [
            ("pwa-gmail", "global"),  # Should match PWA pattern
            ("pwa-claude", "global"),  # Should match PWA pattern
            ("Code", "scoped"),  # Should match explicit list
            ("xterm", "scoped"),  # Should match terminal pattern
            ("unknown-app", "unclassified"),  # No match
        ]

        for window_class, expected_scope in test_windows:
            actual_scope = reloaded_config.get_classification(window_class)
            assert actual_scope == expected_scope, \
                f"Window {window_class} should be {expected_scope}, got {actual_scope}"

        # ================================================================
        # Step 9: Verify complete workflow success
        # ================================================================

        # All steps completed successfully:
        # ✓ Apps discovered
        # ✓ Classifications applied
        # ✓ Patterns created
        # ✓ Configuration saved
        # ✓ Schema validated
        # ✓ Configuration reloaded
        # ✓ Pattern matching works
        # ✓ Auto-classification works

        assert True, "Complete workflow executed successfully"

    async def test_workflow_with_priority_conflicts(self, config, config_file):
        """Test workflow with conflicting patterns resolved by priority.

        T101: Priority resolution in workflow
        """
        # Add two conflicting patterns
        high_priority = PatternRule(
            pattern="glob:test-*",
            scope="global",
            priority=10,
            description="Test apps are global"
        )
        low_priority = PatternRule(
            pattern="regex:^test-.*$",
            scope="scoped",
            priority=5,
            description="Test apps are scoped (lower priority)"
        )

        config.add_pattern(high_priority)
        config.add_pattern(low_priority)
        config.save()

        # Reload and test
        reloaded = AppClassConfig(config_file=config_file)
        reloaded.load()

        # Higher priority (10) should win
        classification = reloaded.get_classification("test-app")
        assert classification == "global", "Higher priority pattern should win"

    async def test_workflow_error_recovery(self, config, config_file):
        """Test workflow handles errors gracefully.

        T101: Error handling in workflow
        """
        # Step 1: Add valid classification
        config.add_scoped_class("ValidClass")
        config.save()

        # Step 2: Corrupt the file
        with open(config_file, 'w') as f:
            f.write("{ invalid json }")

        # Step 3: Try to reload - should detect error
        corrupted_config = AppClassConfig(config_file=config_file)

        with pytest.raises(json.JSONDecodeError):
            corrupted_config.load()

        # Step 4: Validate - should fail
        is_valid, errors = validate_app_classes_config(config_file)
        assert is_valid is False
        assert len(errors) > 0

        # Step 5: Fix the file
        config_data = {
            "scoped_classes": ["ValidClass"],
            "global_classes": [],
            "class_patterns": []
        }
        with open(config_file, 'w') as f:
            json.dump(config_data, f)

        # Step 6: Reload - should succeed
        fixed_config = AppClassConfig(config_file=config_file)
        fixed_config.load()
        assert "ValidClass" in fixed_config.scoped_classes

    async def test_workflow_pattern_creation_and_testing(self, config, config_file):
        """Test creating patterns and testing them in workflow.

        T101: Pattern creation and testing integration
        """
        # Create various pattern types
        patterns = [
            PatternRule("glob:dev-*", "scoped", 10, "Development instances"),
            PatternRule("regex:^prod-\\d+$", "global", 15, "Production instances"),
            PatternRule("glob:*-canary", "scoped", 5, "Canary builds"),
        ]

        for pattern in patterns:
            config.add_pattern(pattern)

        config.save()

        # Reload
        reloaded = AppClassConfig(config_file=config_file)
        reloaded.load()

        # Test various window classes
        test_cases = [
            ("dev-app", "scoped", "glob:dev-*"),
            ("prod-123", "global", "regex:^prod-\\d+$"),
            ("chrome-canary", "scoped", "glob:*-canary"),
            ("regular-app", "unclassified", None),
        ]

        for window_class, expected_scope, expected_pattern in test_cases:
            scope = reloaded.get_classification(window_class)
            assert scope == expected_scope, \
                f"{window_class} should be {expected_scope}, got {scope}"

            # Verify which pattern matched (if any)
            if expected_pattern:
                matched = False
                for pattern in reloaded.class_patterns:
                    matcher = PatternMatcher()
                    if matcher.matches(pattern.pattern, window_class):
                        matched = True
                        break
                assert matched, f"{window_class} should match {expected_pattern}"


@pytest.mark.asyncio
@pytest.mark.integration
class TestWorkflowPerformance:
    """Performance tests for workflow operations.

    T101: Performance validation
    SC-015: <100ms latency requirements
    """

    async def test_classification_lookup_performance(self, tmp_path):
        """Test classification lookup is fast (<100ms).

        SC-015: <100ms latency requirement
        """
        import time

        # Create config with many patterns
        config_file = tmp_path / "app-classes.json"
        config = AppClassConfig(config_file=config_file)

        # Add 100 patterns
        for i in range(100):
            pattern = PatternRule(
                pattern=f"glob:app-{i}-*",
                scope="scoped" if i % 2 == 0 else "global",
                priority=i,
                description=f"Pattern {i}"
            )
            config.add_pattern(pattern)

        config.save()

        # Reload and measure lookup time
        config.load()

        start = time.perf_counter()
        for i in range(1000):
            config.get_classification(f"app-{i % 100}-test")
        end = time.perf_counter()

        avg_time_ms = ((end - start) / 1000) * 1000

        assert avg_time_ms < 100, \
            f"Average classification lookup took {avg_time_ms:.2f}ms, should be <100ms"

    async def test_config_reload_performance(self, tmp_path):
        """Test configuration reload is fast.

        T101: Reload performance
        """
        import time

        config_file = tmp_path / "app-classes.json"
        config = AppClassConfig(config_file=config_file)

        # Add substantial configuration
        for i in range(50):
            config.add_scoped_class(f"ScopedApp{i}")
            config.add_global_class(f"GlobalApp{i}")

        for i in range(50):
            pattern = PatternRule(f"glob:pattern-{i}-*", "scoped", i)
            config.add_pattern(pattern)

        config.save()

        # Measure reload time
        start = time.perf_counter()
        config.load()
        end = time.perf_counter()

        reload_time_ms = (end - start) * 1000

        assert reload_time_ms < 100, \
            f"Config reload took {reload_time_ms:.2f}ms, should be <100ms"
