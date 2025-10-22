"""Unit tests for PatternMatcher reuse with WindowRule."""

import pytest
from pathlib import Path
import sys
import time

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"))

from i3_project_manager.models.pattern import PatternRule
from window_rules import WindowRule


class TestPatternMatcherReuse:
    """Test existing PatternMatcher works with WindowRule."""

    def test_window_rule_uses_pattern_rule(self):
        """Test WindowRule reuses PatternRule.matches()."""
        pattern = PatternRule("glob:FFPWA-*", "global", priority=200)
        rule = WindowRule(pattern_rule=pattern)
        
        # WindowRule.matches() should delegate to PatternRule.matches()
        assert rule.matches("FFPWA-01ABC") is True
        assert rule.matches("Firefox") is False

    def test_glob_pattern_matching(self):
        """Test glob patterns work through WindowRule."""
        pattern = PatternRule("glob:pwa-*", "global", priority=200)
        rule = WindowRule(pattern_rule=pattern)
        
        assert rule.matches("pwa-youtube") is True
        assert rule.matches("pwa-gmail") is True
        assert rule.matches("firefox") is False

    def test_regex_pattern_matching(self):
        """Test regex patterns work through WindowRule."""
        pattern = PatternRule("regex:^(neo)?vim$", "scoped", priority=200)
        rule = WindowRule(pattern_rule=pattern)
        
        assert rule.matches("vim") is True
        assert rule.matches("neovim") is True
        assert rule.matches("gvim") is False

    def test_literal_pattern_matching(self):
        """Test literal patterns work through WindowRule."""
        pattern = PatternRule("Code", "scoped", priority=250)
        rule = WindowRule(pattern_rule=pattern)
        
        assert rule.matches("Code") is True
        assert rule.matches("code") is False
        assert rule.matches("VSCode") is False

    def test_multiple_patterns(self):
        """Test multiple WindowRules with different pattern types."""
        rules = [
            WindowRule(PatternRule("glob:FFPWA-*", "global", 200)),
            WindowRule(PatternRule("regex:^vim$", "scoped", 200)),
            WindowRule(PatternRule("Code", "scoped", 250))
        ]
        
        # Test each pattern type
        assert rules[0].matches("FFPWA-01ABC") is True
        assert rules[1].matches("vim") is True
        assert rules[2].matches("Code") is True


class TestPatternMatcherPerformance:
    """Test pattern matching performance with many rules."""

    def test_performance_100_rules_cached(self):
        """Test classification with 100 rules is fast (<1ms cached)."""
        # Create 100 window rules
        rules = []
        for i in range(100):
            pattern = PatternRule(f"App{i}", "scoped", priority=100 + i)
            rules.append(WindowRule(pattern_rule=pattern, workspace=(i % 9) + 1))
        
        # Test window class
        test_class = "App50"
        
        # First match (uncached)
        start = time.perf_counter()
        result = None
        for rule in rules:
            if rule.matches(test_class):
                result = rule
                break
        end = time.perf_counter()
        
        first_match_time = (end - start) * 1000  # Convert to ms
        
        # Second match (should be faster due to any caching)
        start = time.perf_counter()
        result = None
        for rule in rules:
            if rule.matches(test_class):
                result = rule
                break
        end = time.perf_counter()
        
        second_match_time = (end - start) * 1000  # Convert to ms
        
        # Should find the match
        assert result is not None
        assert result.pattern_rule.pattern == "App50"
        
        # Performance should be reasonable (allow more time in CI)
        assert first_match_time < 10, f"First match took {first_match_time}ms (expected <10ms)"
        assert second_match_time < 10, f"Second match took {second_match_time}ms (expected <10ms)"

    def test_performance_sorted_by_priority(self):
        """Test rules sorted by priority for efficient matching."""
        # Create rules with varying priorities
        rules = [
            WindowRule(PatternRule("glob:*", "global", priority=10), workspace=9),  # Catch-all
            WindowRule(PatternRule("Code", "scoped", priority=300), workspace=2),  # Specific
            WindowRule(PatternRule("glob:C*", "scoped", priority=200), workspace=3)  # Mid-priority
        ]
        
        # Sort by priority (highest first)
        sorted_rules = sorted(rules, key=lambda r: r.priority, reverse=True)
        
        # Verify sort order
        assert sorted_rules[0].priority == 300
        assert sorted_rules[1].priority == 200
        assert sorted_rules[2].priority == 10
        
        # Matching "Code" should hit highest priority first
        for rule in sorted_rules:
            if rule.matches("Code"):
                matched_rule = rule
                break
        
        assert matched_rule.priority == 300
        assert matched_rule.workspace == 2


class TestPatternMatcherValidation:
    """Test pattern validation through WindowRule."""

    def test_invalid_regex_pattern(self):
        """Test invalid regex raises error."""
        with pytest.raises(ValueError, match="Invalid regex pattern"):
            PatternRule("regex:[invalid(", "scoped", priority=100)

    def test_empty_pattern(self):
        """Test empty pattern raises error."""
        with pytest.raises(ValueError, match="Pattern cannot be empty"):
            PatternRule("", "scoped", priority=100)

    def test_negative_priority(self):
        """Test negative priority raises error."""
        with pytest.raises(ValueError, match="Priority must be non-negative"):
            PatternRule("Test", "scoped", priority=-1)


class TestPatternRuleCaching:
    """Test PatternRule frozen dataclass for caching."""

    def test_pattern_rule_is_frozen(self):
        """Test PatternRule is immutable (frozen)."""
        pattern = PatternRule("Code", "scoped", priority=250)
        
        # Should not be able to modify
        with pytest.raises(Exception):  # FrozenInstanceError
            pattern.pattern = "NewPattern"

    def test_pattern_rule_hashable(self):
        """Test PatternRule is hashable for caching."""
        pattern = PatternRule("Code", "scoped", priority=250)
        
        # Should be hashable (frozen dataclass)
        pattern_hash = hash(pattern)
        assert isinstance(pattern_hash, int)
        
        # Can be used in sets/dicts
        pattern_set = {pattern}
        assert pattern in pattern_set

    def test_same_patterns_equal(self):
        """Test identical patterns are equal."""
        pattern1 = PatternRule("Code", "scoped", priority=250)
        pattern2 = PatternRule("Code", "scoped", priority=250)
        
        assert pattern1 == pattern2
        assert hash(pattern1) == hash(pattern2)
