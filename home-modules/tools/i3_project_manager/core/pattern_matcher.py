"""Pattern matching engine with performance optimization.

This module provides the PatternMatcher class which handles efficient
pattern-based window class classification with LRU caching.
"""

from functools import lru_cache
from typing import List, Optional

from ..models.pattern import PatternRule


class PatternMatcher:
    """High-performance pattern matching engine for window classes.

    Uses LRU caching to achieve <1ms matching performance even with 100+ patterns.
    Patterns are sorted by priority (descending) and matched with short-circuit
    evaluation (first match wins).

    Attributes:
        patterns: List of PatternRule objects sorted by priority descending

    Examples:
        >>> from i3_project_manager.models.pattern import PatternRule
        >>> patterns = [
        ...     PatternRule("glob:pwa-*", "global", priority=100),
        ...     PatternRule("regex:^vim$", "scoped", priority=50),
        ... ]
        >>> matcher = PatternMatcher(patterns)
        >>> matcher.match("pwa-youtube")
        'global'
        >>> matcher.match("vim")
        'scoped'
        >>> matcher.match("unknown-app")
        None
    """

    def __init__(self, patterns: List[PatternRule]):
        """Initialize pattern matcher with sorted patterns.

        Args:
            patterns: List of PatternRule objects (will be sorted by priority)
        """
        # Sort patterns by priority descending (highest priority first)
        self.patterns = sorted(patterns, key=lambda p: p.priority, reverse=True)

        # Convert patterns to tuple for hashability (required for lru_cache)
        self._patterns_tuple = tuple(self.patterns)

        # Create cached matching function
        self._match_impl = self._create_cached_matcher()

    def _create_cached_matcher(self):
        """Create LRU cached matching function.

        Returns:
            Cached function that matches window class against patterns
        """

        @lru_cache(maxsize=1024)
        def _match_impl(window_class: str, patterns_snapshot: tuple) -> Optional[str]:
            """Cached implementation of pattern matching.

            Args:
                window_class: Window class string to match
                patterns_snapshot: Tuple of patterns (for cache key)

            Returns:
                "scoped" or "global" if pattern matches, None if no match
            """
            # Short-circuit evaluation - return on first match
            for pattern in patterns_snapshot:
                if pattern.matches(window_class):
                    return pattern.scope

            return None

        return _match_impl

    def match(self, window_class: str) -> Optional[str]:
        """Match window class against patterns with LRU caching.

        Patterns are evaluated in priority order (highest first).
        First matching pattern wins (short-circuit evaluation).

        Args:
            window_class: Window class string to match (e.g., "pwa-youtube")

        Returns:
            "scoped" or "global" if pattern matches, None if no match

        Examples:
            >>> matcher = PatternMatcher([
            ...     PatternRule("glob:pwa-*", "global", priority=100),
            ...     PatternRule("glob:pwa-youtube", "scoped", priority=50),
            ... ])
            >>> matcher.match("pwa-youtube")
            'global'

        Performance:
            With LRU cache (maxsize=1024), typical lookup is O(1).
            Cache misses perform O(n) pattern matching where n is number of patterns.
            Target: <1ms even with 100+ patterns (FR-078, SC-025).
        """
        return self._match_impl(window_class, self._patterns_tuple)

    def clear_cache(self):
        """Clear the LRU cache.

        Call this after updating the patterns list to ensure fresh matching.
        """
        self._match_impl.cache_clear()

    def get_cache_info(self):
        """Get LRU cache statistics.

        Returns:
            CacheInfo namedtuple with hits, misses, maxsize, currsize

        Examples:
            >>> matcher = PatternMatcher([PatternRule("glob:test*", "scoped", priority=50)])
            >>> matcher.match("test-app")
            'scoped'
            >>> info = matcher.get_cache_info()
            >>> info.hits  # Number of cache hits
            0
            >>> info.misses  # Number of cache misses
            1
        """
        return self._match_impl.cache_info()
