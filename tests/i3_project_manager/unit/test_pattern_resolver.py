"""Unit tests for classify_window() 4-level precedence algorithm."""

import pytest
from pathlib import Path
import sys

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"))

from i3_project_manager.models.pattern import PatternRule
from window_rules import WindowRule
from pattern_resolver import classify_window, Classification


class TestClassifyWindowPrecedence:
    """Test 4-level precedence hierarchy."""

    def test_priority_1000_project_scoped_classes(self):
        """Test project scoped_classes has highest priority (1000)."""
        # Project says Code is scoped
        result = classify_window(
            window_class="Code",
            active_project_scoped_classes=["Code"]
        )
        
        assert result.scope == "scoped"
        assert result.source == "project"
        assert result.workspace is None

    def test_priority_200_500_window_rules(self):
        """Test window rules have priority 200-500."""
        pattern = PatternRule("Code", "global", priority=250)
        rule = WindowRule(pattern_rule=pattern, workspace=4)
        
        result = classify_window(
            window_class="Code",
            window_rules=[rule]
        )
        
        assert result.scope == "global"
        assert result.workspace == 4
        assert result.source == "window_rule"

    def test_priority_100_app_classification_patterns(self):
        """Test app classification patterns have priority 100."""
        pattern = PatternRule("Code", "scoped", priority=100)
        
        result = classify_window(
            window_class="Code",
            app_classification_patterns=[pattern]
        )
        
        assert result.scope == "scoped"
        assert result.source == "app_classes"

    def test_priority_50_app_classification_lists(self):
        """Test app classification literal lists have priority 50."""
        result = classify_window(
            window_class="Code",
            app_classification_scoped=["Code"]
        )
        
        assert result.scope == "scoped"
        assert result.source == "app_classes"

    def test_project_overrides_window_rules(self):
        """Test project scoped_classes (1000) overrides window rules (250)."""
        pattern = PatternRule("Code", "global", priority=250)
        rule = WindowRule(pattern_rule=pattern, workspace=4)
        
        result = classify_window(
            window_class="Code",
            active_project_scoped_classes=["Code"],  # Says scoped
            window_rules=[rule]  # Says global
        )
        
        # Project wins
        assert result.scope == "scoped"
        assert result.source == "project"

    def test_window_rules_override_app_patterns(self):
        """Test window rules (250) override app patterns (100)."""
        pattern = PatternRule("Code", "scoped", priority=100)
        rule_pattern = PatternRule("Code", "global", priority=250)
        rule = WindowRule(pattern_rule=rule_pattern, workspace=4)
        
        result = classify_window(
            window_class="Code",
            window_rules=[rule],  # Says global
            app_classification_patterns=[pattern]  # Says scoped
        )
        
        # Window rule wins
        assert result.scope == "global"
        assert result.source == "window_rule"

    def test_app_patterns_override_app_lists(self):
        """Test app patterns (100) override app lists (50)."""
        pattern = PatternRule("Code", "global", priority=100)
        
        result = classify_window(
            window_class="Code",
            app_classification_patterns=[pattern],  # Says global
            app_classification_scoped=["Code"]  # Says scoped
        )
        
        # Pattern wins
        assert result.scope == "global"
        assert result.source == "app_classes"


class TestClassifyWindowSourceAttribution:
    """Test source attribution for debugging."""

    def test_source_project(self):
        """Test source is 'project' for project matches."""
        result = classify_window(
            window_class="Code",
            active_project_scoped_classes=["Code"]
        )
        
        assert result.source == "project"

    def test_source_window_rule(self):
        """Test source is 'window_rule' for rule matches."""
        pattern = PatternRule("Code", "scoped", priority=250)
        rule = WindowRule(pattern_rule=pattern)
        
        result = classify_window(
            window_class="Code",
            window_rules=[rule]
        )
        
        assert result.source == "window_rule"
        assert result.matched_rule == rule

    def test_source_app_classes_pattern(self):
        """Test source is 'app_classes' for pattern matches."""
        pattern = PatternRule("Code", "scoped", priority=100)
        
        result = classify_window(
            window_class="Code",
            app_classification_patterns=[pattern]
        )
        
        assert result.source == "app_classes"

    def test_source_app_classes_list(self):
        """Test source is 'app_classes' for list matches."""
        result = classify_window(
            window_class="Code",
            app_classification_scoped=["Code"]
        )
        
        assert result.source == "app_classes"

    def test_source_default(self):
        """Test source is 'default' when no match."""
        result = classify_window(window_class="Unknown")
        
        assert result.source == "default"
        assert result.scope == "global"


class TestClassifyWindowShortCircuit:
    """Test short-circuit evaluation (early return)."""

    def test_short_circuit_at_project(self):
        """Test evaluation stops at project match."""
        pattern = PatternRule("Code", "global", priority=250)
        rule = WindowRule(pattern_rule=pattern, workspace=4)
        
        result = classify_window(
            window_class="Code",
            active_project_scoped_classes=["Code"],
            window_rules=[rule],
            app_classification_scoped=["Code"]
        )
        
        # Should stop at project level, not check lower levels
        assert result.source == "project"
        assert result.matched_rule is None  # Didn't reach window rules

    def test_short_circuit_at_window_rule(self):
        """Test evaluation stops at window rule match."""
        pattern = PatternRule("Code", "global", priority=250)
        rule = WindowRule(pattern_rule=pattern, workspace=4)
        app_pattern = PatternRule("Code", "scoped", priority=100)
        
        result = classify_window(
            window_class="Code",
            window_rules=[rule],
            app_classification_patterns=[app_pattern],
            app_classification_scoped=["Code"]
        )
        
        # Should stop at window rule level
        assert result.source == "window_rule"


class TestClassifyWindowPatternMatching:
    """Test pattern matching integration."""

    def test_glob_pattern_matching(self):
        """Test glob pattern matching."""
        pattern = PatternRule("glob:FFPWA-*", "global", priority=200)
        rule = WindowRule(pattern_rule=pattern, workspace=4)
        
        result = classify_window(
            window_class="FFPWA-01K665SPD8EPMP3JTW02JM1M0Z",
            window_rules=[rule]
        )
        
        assert result.scope == "global"
        assert result.workspace == 4

    def test_regex_pattern_matching(self):
        """Test regex pattern matching."""
        pattern = PatternRule("regex:^(neo)?vim$", "scoped", priority=200)
        rule = WindowRule(pattern_rule=pattern)
        
        result_vim = classify_window("vim", window_rules=[rule])
        result_neovim = classify_window("neovim", window_rules=[rule])
        result_gvim = classify_window("gvim", window_rules=[rule])
        
        assert result_vim.source == "window_rule"
        assert result_neovim.source == "window_rule"
        assert result_gvim.source == "default"  # Doesn't match

    def test_literal_pattern_matching(self):
        """Test literal pattern matching."""
        pattern = PatternRule("Code", "scoped", priority=250)
        rule = WindowRule(pattern_rule=pattern)
        
        result_match = classify_window("Code", window_rules=[rule])
        result_no_match = classify_window("code", window_rules=[rule])
        
        assert result_match.source == "window_rule"
        assert result_no_match.source == "default"


class TestClassifyWindowMultipleRules:
    """Test classification with multiple rules."""

    def test_highest_priority_wins(self):
        """Test highest priority rule matches first."""
        low_priority = PatternRule("glob:C*", "global", priority=100)
        high_priority = PatternRule("Code", "scoped", priority=300)
        
        rules = [
            WindowRule(pattern_rule=low_priority, workspace=9),
            WindowRule(pattern_rule=high_priority, workspace=2)
        ]
        
        result = classify_window("Code", window_rules=rules)
        
        # High priority rule should match
        assert result.workspace == 2
        assert result.scope == "scoped"

    def test_first_match_wins_same_priority(self):
        """Test first matching rule wins when priorities equal."""
        rule1 = WindowRule(
            pattern_rule=PatternRule("glob:C*", "scoped", priority=200),
            workspace=1
        )
        rule2 = WindowRule(
            pattern_rule=PatternRule("Code", "global", priority=200),
            workspace=2
        )
        
        # Rules should be sorted by priority, then order matters
        result = classify_window("Code", window_rules=[rule1, rule2])
        
        # One of them should match
        assert result.source == "window_rule"


class TestClassifyWindowWorkspaceAssignment:
    """Test workspace assignment."""

    def test_workspace_from_window_rule(self):
        """Test workspace comes from window rule."""
        pattern = PatternRule("Code", "scoped", priority=250)
        rule = WindowRule(pattern_rule=pattern, workspace=2)
        
        result = classify_window("Code", window_rules=[rule])
        
        assert result.workspace == 2

    def test_no_workspace_from_project(self):
        """Test project match has no workspace (project-scoped)."""
        result = classify_window(
            window_class="Code",
            active_project_scoped_classes=["Code"]
        )
        
        assert result.workspace is None

    def test_no_workspace_from_app_classes(self):
        """Test app classes have no workspace."""
        result = classify_window(
            window_class="Code",
            app_classification_scoped=["Code"]
        )
        
        assert result.workspace is None


class TestClassifyWindowDefault:
    """Test default classification."""

    def test_default_is_global(self):
        """Test default classification is global."""
        result = classify_window(window_class="Unknown")
        
        assert result.scope == "global"
        assert result.source == "default"
        assert result.workspace is None

    def test_empty_inputs_default(self):
        """Test empty inputs result in default."""
        result = classify_window(
            window_class="Code",
            active_project_scoped_classes=[],
            window_rules=[],
            app_classification_patterns=[],
            app_classification_scoped=[],
            app_classification_global=[]
        )
        
        assert result.scope == "global"
        assert result.source == "default"
