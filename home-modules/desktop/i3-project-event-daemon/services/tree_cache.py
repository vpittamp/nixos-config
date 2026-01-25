"""
Tree cache service for Feature 091: Optimize i3pm Project Switching Performance.

This service provides caching for Sway tree queries with 100ms TTL to eliminate
duplicate get_tree() calls during project switches.
"""

from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Optional
from datetime import datetime, timedelta

if TYPE_CHECKING:
    from i3ipc.aio import Connection, Con

logger = logging.getLogger(__name__)


class TreeCacheEntry:
    """Cache entry for Sway tree snapshot.

    Attributes:
        tree: The cached Sway tree (Con object)
        cached_at: When the tree was cached
        ttl_ms: Time-to-live in milliseconds
    """

    def __init__(self, tree: Con, ttl_ms: float = 100.0):
        """Initialize cache entry.

        Args:
            tree: Sway tree (Con object from get_tree())
            ttl_ms: Time-to-live in milliseconds (default: 100ms)
        """
        self.tree = tree
        self.cached_at = datetime.now()
        self.ttl_ms = ttl_ms

    @property
    def is_expired(self) -> bool:
        """Check if cache entry has expired."""
        age = (datetime.now() - self.cached_at).total_seconds() * 1000
        return age > self.ttl_ms

    @property
    def age_ms(self) -> float:
        """Get cache entry age in milliseconds."""
        return (datetime.now() - self.cached_at).total_seconds() * 1000


class TreeCacheService:
    """Service for caching Sway tree queries.

    This service eliminates duplicate get_tree() calls by caching the tree with
    a 100ms TTL. During a typical project switch, multiple components may query
    the tree (window filter, workspace assigner, etc.) - caching reduces these
    redundant IPC calls from 2-3 down to 1.

    The cache is automatically invalidated on relevant Sway events:
    - window::close
    - workspace::empty
    - workspace::move

    Example:
        >>> service = TreeCacheService(connection)
        >>> tree = await service.get_tree()  # Cache miss - fetches from Sway
        >>> tree2 = await service.get_tree() # Cache hit (within 100ms)
        >>> assert tree is tree2
    """

    def __init__(self, conn: Connection, ttl_ms: float = 100.0):
        """Initialize the tree cache service.

        Args:
            conn: Active i3ipc Connection instance
            ttl_ms: Cache time-to-live in milliseconds (default: 100ms)
        """
        self.conn = conn
        self.ttl_ms = ttl_ms
        self._cache: Optional[TreeCacheEntry] = None
        self._cache_hits = 0
        self._cache_misses = 0
        self._invalidations = 0

    async def get_tree(self, force_refresh: bool = False) -> Con:
        """Get Sway tree with caching.

        Args:
            force_refresh: If True, bypass cache and fetch fresh tree

        Returns:
            Sway tree (Con object)
        """
        # Check cache validity
        if not force_refresh and self._cache and not self._cache.is_expired:
            self._cache_hits += 1
            logger.debug(
                f"[Feature 091] Tree cache HIT (age: {self._cache.age_ms:.1f}ms, "
                f"hit rate: {self.cache_hit_rate:.1f}%)"
            )
            return self._cache.tree

        # Cache miss - fetch fresh tree
        self._cache_misses += 1
        try:
            tree = await self.conn.get_tree()
        except Exception as e:
            # Connection may be stale - raise with context for better debugging
            logger.error(f"[Feature 091] Tree cache get_tree() failed: {type(e).__name__}: {e}")
            raise ConnectionError(f"Failed to get Sway tree (connection may be stale): {type(e).__name__}: {e}") from e
        self._cache = TreeCacheEntry(tree, ttl_ms=self.ttl_ms)

        logger.debug(
            f"[Feature 091] Tree cache MISS "
            f"(hit rate: {self.cache_hit_rate:.1f}%, total queries: {self.total_queries})"
        )

        return tree

    def invalidate(self, reason: str = "manual") -> None:
        """Invalidate the cache.

        Args:
            reason: Reason for invalidation (for logging)
        """
        if self._cache:
            self._invalidations += 1
            logger.debug(
                f"[Feature 091] Tree cache INVALIDATED (reason: {reason}, "
                f"age: {self._cache.age_ms:.1f}ms)"
            )
            self._cache = None

    def invalidate_on_event(self, event_type: str) -> bool:
        """Check if cache should be invalidated for an event type.

        Args:
            event_type: Sway event type (e.g., "window::close")

        Returns:
            True if cache was invalidated
        """
        # Events that should invalidate the cache
        invalidating_events = {
            "window::close",
            "workspace::empty",
            "workspace::move",
            "window::move",  # Optional: may cause false invalidations
        }

        if event_type in invalidating_events:
            self.invalidate(reason=f"event:{event_type}")
            return True

        return False

    @property
    def cache_hit_rate(self) -> float:
        """Calculate cache hit rate as percentage."""
        total = self._cache_hits + self._cache_misses
        if total == 0:
            return 0.0
        return (self._cache_hits / total) * 100

    @property
    def total_queries(self) -> int:
        """Get total number of tree queries."""
        return self._cache_hits + self._cache_misses

    @property
    def is_cached(self) -> bool:
        """Check if a valid cache entry exists."""
        return self._cache is not None and not self._cache.is_expired

    def get_stats(self) -> dict:
        """Get cache statistics.

        Returns:
            Dictionary with cache performance metrics
        """
        return {
            "cache_hits": self._cache_hits,
            "cache_misses": self._cache_misses,
            "hit_rate_pct": round(self.cache_hit_rate, 2),
            "total_queries": self.total_queries,
            "invalidations": self._invalidations,
            "is_cached": self.is_cached,
            "cache_age_ms": round(self._cache.age_ms, 2) if self._cache else None,
            "ttl_ms": self.ttl_ms,
        }

    def reset_stats(self) -> None:
        """Reset cache statistics (but keep cached tree)."""
        self._cache_hits = 0
        self._cache_misses = 0
        self._invalidations = 0

    def reset_all(self) -> None:
        """Reset cache and statistics."""
        self._cache = None
        self.reset_stats()


# Singleton instance (can be initialized by daemon)
_tree_cache_instance: Optional[TreeCacheService] = None


def get_tree_cache() -> Optional[TreeCacheService]:
    """Get the global tree cache instance.

    Returns:
        TreeCacheService instance or None if not initialized
    """
    return _tree_cache_instance


def initialize_tree_cache(conn: Connection, ttl_ms: float = 100.0) -> TreeCacheService:
    """Initialize the global tree cache instance.

    Args:
        conn: Active i3ipc Connection instance
        ttl_ms: Cache time-to-live in milliseconds

    Returns:
        Initialized TreeCacheService instance
    """
    global _tree_cache_instance
    _tree_cache_instance = TreeCacheService(conn, ttl_ms=ttl_ms)
    logger.info(f"[Feature 091] Tree cache initialized (TTL: {ttl_ms}ms)")
    return _tree_cache_instance
