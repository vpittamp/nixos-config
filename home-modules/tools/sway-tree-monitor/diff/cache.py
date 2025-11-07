"""Hash cache for incremental tree diffing

This module provides a TTL-based cache for node hashes to enable
fast incremental diffing between consecutive tree snapshots.

Memory budget: ~12 KB for 200 windows (~50 bytes per node)
TTL: 60 seconds (prevent stale hashes)
"""

import time
from typing import Dict, Optional, Tuple

from ..models import NodeFingerprint


class HashCache:
    """
    Maintains node hashes between snapshots for fast comparison.

    Memory: ~50 bytes per node
    - 200 windows × 50 bytes = 10 KB
    - ~30 containers × 50 bytes = 1.5 KB
    Total: ~12 KB (negligible)

    TTL: 60 seconds (prevent stale hashes)
    """

    def __init__(self, max_age_seconds: float = 60.0):
        """
        Initialize hash cache.

        Args:
            max_age_seconds: TTL for cached hashes (default: 60s)
        """
        self.fingerprints: Dict[str, NodeFingerprint] = {}
        self.max_age = max_age_seconds
        self._last_cleanup = time.time()
        self._cleanup_interval = 10.0  # Cleanup every 10 seconds

    def get(self, node_id: str) -> Optional[Tuple[str, str]]:
        """
        Retrieve cached hashes for a node.

        Args:
            node_id: Unique node identifier

        Returns:
            Tuple of (content_hash, subtree_hash) if found and not expired,
            None otherwise
        """
        fp = self.fingerprints.get(node_id)
        if fp is None:
            return None

        # Check if expired
        if (time.time() - fp.timestamp) >= self.max_age:
            # Expired, remove and return None
            del self.fingerprints[node_id]
            return None

        return (fp.content_hash, fp.subtree_hash)

    def get_subtree_hash(self, node_id: str) -> Optional[str]:
        """
        Retrieve cached subtree hash for fast comparison.

        Args:
            node_id: Unique node identifier

        Returns:
            Subtree hash if found and not expired, None otherwise
        """
        result = self.get(node_id)
        return result[1] if result else None

    def get_content_hash(self, node_id: str) -> Optional[str]:
        """
        Retrieve cached content hash.

        Args:
            node_id: Unique node identifier

        Returns:
            Content hash if found and not expired, None otherwise
        """
        result = self.get(node_id)
        return result[0] if result else None

    def update(self, node_id: str, content_hash: str, subtree_hash: str) -> None:
        """
        Update cache with new hashes for a node.

        Args:
            node_id: Unique node identifier
            content_hash: Hash of node's direct fields
            subtree_hash: Merkle hash including descendants
        """
        self.fingerprints[node_id] = NodeFingerprint(
            node_id=node_id,
            content_hash=content_hash,
            subtree_hash=subtree_hash,
            timestamp=time.time()
        )

        # Opportunistic cleanup if interval elapsed
        self._opportunistic_cleanup()

    def update_batch(self, hashes: Dict[str, Tuple[str, str]]) -> None:
        """
        Batch update multiple nodes at once.

        More efficient than individual updates when populating cache
        from a full tree traversal.

        Args:
            hashes: Dictionary mapping node_id -> (content_hash, subtree_hash)
        """
        timestamp = time.time()
        for node_id, (content_hash, subtree_hash) in hashes.items():
            self.fingerprints[node_id] = NodeFingerprint(
                node_id=node_id,
                content_hash=content_hash,
                subtree_hash=subtree_hash,
                timestamp=timestamp
            )

        self._opportunistic_cleanup()

    def invalidate(self, node_id: str) -> None:
        """
        Remove a node from cache (force recomputation on next access).

        Args:
            node_id: Unique node identifier
        """
        self.fingerprints.pop(node_id, None)

    def clear(self) -> None:
        """Clear entire cache"""
        self.fingerprints.clear()

    def cleanup_expired(self) -> int:
        """
        Remove all expired fingerprints.

        Returns:
            Number of expired entries removed
        """
        now = time.time()
        expired = [
            node_id for node_id, fp in self.fingerprints.items()
            if (now - fp.timestamp) >= self.max_age
        ]
        for node_id in expired:
            del self.fingerprints[node_id]

        self._last_cleanup = now
        return len(expired)

    def _opportunistic_cleanup(self) -> None:
        """
        Perform cleanup if interval has elapsed.

        Called automatically during updates to prevent unbounded growth.
        """
        if (time.time() - self._last_cleanup) >= self._cleanup_interval:
            self.cleanup_expired()

    def size(self) -> int:
        """
        Get current cache size (number of nodes).

        Returns:
            Number of cached nodes
        """
        return len(self.fingerprints)

    def memory_bytes(self) -> int:
        """
        Estimate memory usage in bytes.

        Rough approximation: 50 bytes per fingerprint

        Returns:
            Estimated memory usage in bytes
        """
        return self.size() * 50

    def stats(self) -> Dict[str, any]:
        """
        Get cache statistics.

        Returns:
            Dictionary with cache metrics
        """
        now = time.time()
        ages = [now - fp.timestamp for fp in self.fingerprints.values()]

        return {
            'size': self.size(),
            'memory_bytes': self.memory_bytes(),
            'memory_kb': self.memory_bytes() / 1024,
            'max_age_seconds': self.max_age,
            'avg_age_seconds': sum(ages) / len(ages) if ages else 0,
            'oldest_age_seconds': max(ages) if ages else 0,
        }
