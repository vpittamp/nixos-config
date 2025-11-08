"""Hash-based incremental tree differ

This module implements the core diff algorithm using Merkle tree hashing
to achieve <10ms diff computation by skipping unchanged subtrees.

Performance target: 2-8ms for 100-window tree (p95)
"""

import time
from typing import Any, Dict, List, Optional, Set, Tuple

from ..models import (
    ChangeType,
    FieldChange,
    NodeChange,
    TreeDiff,
    TreeSnapshot,
)
from .hasher import (
    compute_content_hash,
    compute_subtree_hash,
    extract_node_id,
    get_node_path,
)
from .cache import HashCache


# Fields that indicate high significance (1.0)
HIGH_SIGNIFICANCE_FIELDS = {
    'focused',  # Focus changes are always significant
    'urgent',  # Urgent flag is important
    'window',  # Window add/remove
    'name',  # Name changes (e.g., workspace switch)
}

# Fields with medium significance (0.5)
MEDIUM_SIGNIFICANCE_FIELDS = {
    'floating',  # Float state change
    'fullscreen',  # Fullscreen state change
    'visible',  # Visibility change
    'layout',  # Layout change
}

# Geometry change threshold (pixels)
GEOMETRY_THRESHOLD = 5  # Ignore changes <5px


def compute_field_significance(field_path: str, old_value: Any, new_value: Any) -> float:
    """
    Compute significance score for a single field change.

    Args:
        field_path: JSONPath to field (e.g., 'rect.x', 'focused')
        old_value: Previous value
        new_value: New value

    Returns:
        Significance score (0.0 to 1.0)
    """
    # Extract field name (last component of path)
    field_name = field_path.split('.')[-1]

    # High significance fields
    if field_name in HIGH_SIGNIFICANCE_FIELDS:
        return 1.0

    # Medium significance fields
    if field_name in MEDIUM_SIGNIFICANCE_FIELDS:
        return 0.5

    # Geometry changes with threshold
    if field_name in ('x', 'y', 'width', 'height'):
        if isinstance(old_value, (int, float)) and isinstance(new_value, (int, float)):
            delta = abs(new_value - old_value)
            if delta < GEOMETRY_THRESHOLD:
                return 0.1  # Below threshold, low significance
            else:
                return 0.5  # Above threshold, medium significance

    # Default: low significance
    return 0.2


def compare_nodes(
    old_node: Dict[str, Any],
    new_node: Dict[str, Any],
    node_path: str = "",
    exclude_fields: Set[str] = None
) -> List[FieldChange]:
    """
    Compare two nodes field-by-field and generate field changes.

    Args:
        old_node: Previous node state
        new_node: New node state
        node_path: Path to this node (for display)
        exclude_fields: Fields to exclude from comparison

    Returns:
        List of field-level changes
    """
    if exclude_fields is None:
        exclude_fields = set()

    changes: List[FieldChange] = []

    # Compare all keys
    all_keys = set(old_node.keys()) | set(new_node.keys())

    for key in all_keys:
        # Skip children and excluded fields
        if key in ('nodes', 'floating_nodes') or key in exclude_fields:
            continue

        old_val = old_node.get(key)
        new_val = new_node.get(key)

        # Skip if unchanged
        if old_val == new_val:
            continue

        # Determine change type
        if old_val is None and new_val is not None:
            change_type = ChangeType.ADDED
        elif old_val is not None and new_val is None:
            change_type = ChangeType.REMOVED
        else:
            change_type = ChangeType.MODIFIED

        # Compute significance
        field_path = f"{node_path}.{key}" if node_path else key
        significance = compute_field_significance(field_path, old_val, new_val)

        changes.append(FieldChange(
            field_path=field_path,
            old_value=old_val,
            new_value=new_val,
            change_type=change_type,
            significance_score=significance
        ))

    return changes


def diff_subtree(
    old_node: Dict[str, Any],
    new_node: Dict[str, Any],
    cache: HashCache,
    exclude_fields: Set[str] = None,
    parent_path: str = ""
) -> List[NodeChange]:
    """
    Recursively diff two subtrees using hash-based pruning.

    This is the core optimization: if subtree hashes match, skip entire subtree.

    Args:
        old_node: Previous subtree root
        new_node: New subtree root
        cache: Hash cache for pruning
        exclude_fields: Fields to exclude
        parent_path: Path to parent node

    Returns:
        List of node-level changes
    """
    node_changes: List[NodeChange] = []

    # Extract node IDs
    old_id = extract_node_id(old_node)
    new_id = extract_node_id(new_node)

    # Compute node path for display
    node_path = get_node_path(new_node, new_node)  # Simplified

    # OPTIMIZATION: Check if subtree hashes match (skip if unchanged)
    old_subtree_hash = cache.get_subtree_hash(old_id)
    new_subtree_hash = compute_subtree_hash(new_node, exclude_fields)

    if old_subtree_hash and old_subtree_hash == new_subtree_hash:
        # Entire subtree unchanged, skip!
        return node_changes

    # Subtree differs, need to check this node and recurse into children

    # Compare this node's fields
    field_changes = compare_nodes(old_node, new_node, node_path, exclude_fields)

    if field_changes:
        # Node has changes, record them
        node_type = new_node.get('type', 'unknown')
        node_changes.append(NodeChange(
            node_id=new_id,
            node_type=node_type,
            change_type=ChangeType.MODIFIED,
            field_changes=field_changes,
            node_path=node_path
        ))

    # Recurse into children
    old_children = old_node.get('nodes', [])
    new_children = new_node.get('nodes', [])
    child_changes = diff_children(old_children, new_children, cache, exclude_fields, node_path)
    node_changes.extend(child_changes)

    # Recurse into floating children
    old_floating = old_node.get('floating_nodes', [])
    new_floating = new_node.get('floating_nodes', [])
    floating_changes = diff_children(old_floating, new_floating, cache, exclude_fields, node_path)
    node_changes.extend(floating_changes)

    return node_changes


def diff_children(
    old_children: List[Dict[str, Any]],
    new_children: List[Dict[str, Any]],
    cache: HashCache,
    exclude_fields: Set[str] = None,
    parent_path: str = ""
) -> List[NodeChange]:
    """
    Diff two lists of child nodes, detecting additions/removals/changes.

    Args:
        old_children: Previous children list
        new_children: New children list
        cache: Hash cache
        exclude_fields: Fields to exclude
        parent_path: Path to parent

    Returns:
        List of node changes
    """
    node_changes: List[NodeChange] = []

    # Build ID maps for fast lookup
    old_map = {extract_node_id(n): n for n in old_children}
    new_map = {extract_node_id(n): n for n in new_children}

    old_ids = set(old_map.keys())
    new_ids = set(new_map.keys())

    # Detect removed nodes
    removed_ids = old_ids - new_ids
    for node_id in removed_ids:
        old_node = old_map[node_id]
        node_path = get_node_path(old_node, old_node)
        node_type = old_node.get('type', 'unknown')

        node_changes.append(NodeChange(
            node_id=node_id,
            node_type=node_type,
            change_type=ChangeType.REMOVED,
            field_changes=[],
            node_path=node_path
        ))

    # Detect added nodes
    added_ids = new_ids - old_ids
    for node_id in added_ids:
        new_node = new_map[node_id]
        node_path = get_node_path(new_node, new_node)
        node_type = new_node.get('type', 'unknown')

        node_changes.append(NodeChange(
            node_id=node_id,
            node_type=node_type,
            change_type=ChangeType.ADDED,
            field_changes=[],
            node_path=node_path
        ))

    # Compare existing nodes
    common_ids = old_ids & new_ids
    for node_id in common_ids:
        old_node = old_map[node_id]
        new_node = new_map[node_id]

        # Recursively diff subtree
        subtree_changes = diff_subtree(old_node, new_node, cache, exclude_fields, parent_path)
        node_changes.extend(subtree_changes)

    return node_changes


def compute_diff(
    before: TreeSnapshot,
    after: TreeSnapshot,
    cache: HashCache,
    diff_id: int,
    exclude_fields: Set[str] = None
) -> TreeDiff:
    """
    Compute diff between two tree snapshots.

    This is the main entry point for diff computation.

    Args:
        before: Previous snapshot
        after: New snapshot
        cache: Hash cache for optimization
        diff_id: Unique ID for this diff
        exclude_fields: Fields to exclude from comparison

    Returns:
        TreeDiff object with all changes

    Performance: 2-8ms for 100-window tree (target: <10ms p95)
    """
    start_time = time.time()

    # FAST PATH: Check if root hashes match
    if before.root_hash == after.root_hash:
        # No changes at all!
        computation_time_ms = (time.time() - start_time) * 1000
        return TreeDiff(
            diff_id=diff_id,
            before_snapshot_id=before.snapshot_id,
            after_snapshot_id=after.snapshot_id,
            node_changes=[],
            computation_time_ms=computation_time_ms
        )

    # Root hashes differ, need to compute detailed diff
    node_changes = diff_subtree(
        before.tree_data,
        after.tree_data,
        cache,
        exclude_fields
    )

    computation_time_ms = (time.time() - start_time) * 1000

    diff = TreeDiff(
        diff_id=diff_id,
        before_snapshot_id=before.snapshot_id,
        after_snapshot_id=after.snapshot_id,
        node_changes=node_changes,
        computation_time_ms=computation_time_ms
    )

    return diff


class TreeDiffer:
    """
    Stateful tree differ with hash caching.

    Maintains hash cache across multiple diff operations for
    optimal performance.
    """

    def __init__(self, cache_ttl_seconds: float = 60.0):
        """
        Initialize tree differ.

        Args:
            cache_ttl_seconds: TTL for hash cache (default: 60s)
        """
        self.cache = HashCache(max_age_seconds=cache_ttl_seconds)
        self.exclude_fields = {
            'last_split_layout',
            'focus',
            'percent',
        }
        self._diff_counter = 0

    def compute_diff(self, before: TreeSnapshot, after: TreeSnapshot) -> TreeDiff:
        """
        Compute diff between snapshots.

        Args:
            before: Previous snapshot
            after: New snapshot

        Returns:
            TreeDiff with all changes
        """
        self._diff_counter += 1
        return compute_diff(
            before,
            after,
            self.cache,
            self._diff_counter,
            self.exclude_fields
        )

    def cleanup_cache(self) -> int:
        """
        Manually trigger cache cleanup.

        Returns:
            Number of expired entries removed
        """
        return self.cache.cleanup_expired()

    def stats(self) -> Dict[str, Any]:
        """
        Get differ statistics.

        Returns:
            Dictionary with metrics
        """
        return {
            'diffs_computed': self._diff_counter,
            'cache': self.cache.stats(),
        }
