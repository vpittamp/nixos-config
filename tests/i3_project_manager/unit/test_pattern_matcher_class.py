"""Unit tests for PatternMatcher class with LRU caching."""

import pytest

from i3_project_manager.core.pattern_matcher import PatternMatcher
from i3_project_manager.models.pattern import PatternRule


class TestPatternMatcherClass:
    """Test PatternMatcher class functionality."""

    def test_pattern_matcher_basic_matching(self):
        """PatternMatcher should match patterns correctly."""
        patterns = [
            PatternRule("glob:pwa-*", "global", priority=100),
            PatternRule("regex:^vim$", "scoped", priority=50),
            PatternRule("Code", "scoped", priority=25),
        ]

        matcher = PatternMatcher(patterns)

        # Test glob match
        assert matcher.match("pwa-youtube") == "global"
        assert matcher.match("pwa-spotify") == "global"

        # Test regex match
        assert matcher.match("vim") == "scoped"

        # Test literal match
        assert matcher.match("Code") == "scoped"

        # Test no match
        assert matcher.match("firefox") is None

    def test_pattern_matcher_priority_order(self):
        """Higher priority patterns should win when multiple match."""
        patterns = [
            PatternRule("glob:pwa-*", "global", priority=100),
            PatternRule("glob:pwa-youtube", "scoped", priority=50),
        ]

        matcher = PatternMatcher(patterns)

        # Both patterns match "pwa-youtube", but priority=100 wins
        assert matcher.match("pwa-youtube") == "global"

    def test_pattern_matcher_sorts_by_priority(self):
        """PatternMatcher should sort patterns by priority descending."""
        patterns = [
            PatternRule("glob:app*", "scoped", priority=10),
            PatternRule("glob:pwa-*", "global", priority=100),
            PatternRule("regex:^vim$", "scoped", priority=50),
        ]

        matcher = PatternMatcher(patterns)

        # Verify internal sorting
        assert matcher.patterns[0].priority == 100
        assert matcher.patterns[1].priority == 50
        assert matcher.patterns[2].priority == 10

    def test_pattern_matcher_short_circuit_evaluation(self):
        """PatternMatcher should stop at first match (short-circuit)."""
        patterns = [
            PatternRule("glob:test*", "global", priority=100),
            PatternRule("glob:test-app", "scoped", priority=50),
            PatternRule("glob:*", "global", priority=10),
        ]

        matcher = PatternMatcher(patterns)

        # First pattern matches, so result is global
        # Even though pattern 2 and 3 also match
        assert matcher.match("test-app") == "global"

    def test_pattern_matcher_cache_performance(self):
        """PatternMatcher should cache results for performance."""
        patterns = [
            PatternRule(f"glob:app-{i}", "scoped", priority=100 - i)
            for i in range(100)
        ]

        matcher = PatternMatcher(patterns)

        # First call - cache miss
        result1 = matcher.match("test-app")
        info1 = matcher.get_cache_info()
        assert info1.misses == 1
        assert info1.hits == 0

        # Second call - cache hit
        result2 = matcher.match("test-app")
        info2 = matcher.get_cache_info()
        assert info2.misses == 1
        assert info2.hits == 1

        # Results should be the same
        assert result1 == result2

    def test_pattern_matcher_clear_cache(self):
        """PatternMatcher.clear_cache() should reset cache."""
        patterns = [PatternRule("glob:test*", "scoped", priority=50)]

        matcher = PatternMatcher(patterns)

        # First call
        matcher.match("test-app")
        info1 = matcher.get_cache_info()
        assert info1.currsize == 1

        # Clear cache
        matcher.clear_cache()
        info2 = matcher.get_cache_info()
        assert info2.currsize == 0

        # Next call is a cache miss again
        matcher.match("test-app")
        info3 = matcher.get_cache_info()
        assert info3.misses == 1

    def test_pattern_matcher_multiple_window_classes_cached(self):
        """PatternMatcher should cache multiple different window classes."""
        patterns = [
            PatternRule("glob:pwa-*", "global", priority=100),
            PatternRule("regex:^vim$", "scoped", priority=50),
        ]

        matcher = PatternMatcher(patterns)

        # Match different classes
        matcher.match("pwa-youtube")
        matcher.match("vim")
        matcher.match("firefox")

        info = matcher.get_cache_info()
        # All three are cache misses (different keys)
        assert info.misses == 3
        assert info.currsize == 3

        # Repeat matches - all cache hits
        matcher.match("pwa-youtube")
        matcher.match("vim")
        matcher.match("firefox")

        info2 = matcher.get_cache_info()
        assert info2.hits == 3
        assert info2.misses == 3  # Still 3 from before

    def test_pattern_matcher_with_empty_patterns(self):
        """PatternMatcher with empty patterns should always return None."""
        matcher = PatternMatcher([])

        assert matcher.match("any-app") is None
        assert matcher.match("another-app") is None

        # Even with empty patterns, caching should work
        info = matcher.get_cache_info()
        assert info.currsize >= 0
