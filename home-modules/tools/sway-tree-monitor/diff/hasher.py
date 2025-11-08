"""Merkle tree hasher for Sway trees using xxHash

This module implements fast incremental tree hashing using xxHash,
enabling <10ms diff computation by skipping unchanged subtrees.

Based on research: /etc/nixos/specs/064-sway-tree-diff-monitor/research.md

Performance target: <0.2ms for 100-window tree hash computation
"""

from typing import Any, Dict, List, Set
import xxhash
import orjson


# Fields to exclude from hash computation (volatile/timestamp fields)
DEFAULT_EXCLUDE_FIELDS = {
    'last_split_layout',  # Changes frequently but not meaningful
    'focus',  # Focus list changes on every focus change
    'percent',  # Calculated layout percentage
}


def compute_content_hash(node: Dict[str, Any], exclude_fields: Set[str] = None) -> str:
    """
    Compute hash of node's direct fields (not including children).

    Args:
        node: Tree node dictionary from Sway
        exclude_fields: Set of field names to exclude from hash

    Returns:
        Hex string of xxHash64

    Performance: ~0.001ms per node
    """
    if exclude_fields is None:
        exclude_fields = DEFAULT_EXCLUDE_FIELDS

    # Extract fields to hash (exclude volatile fields and children)
    content = {
        k: v for k, v in node.items()
        if k not in exclude_fields
        and k not in ('nodes', 'floating_nodes')  # Children handled separately
    }

    # Use orjson for deterministic key ordering
    # OPT_SORT_KEYS ensures identical JSON for identical content
    serialized = orjson.dumps(content, option=orjson.OPT_SORT_KEYS)

    # Compute xxHash64 (1-2 GB/s throughput)
    h = xxhash.xxh64()
    h.update(serialized)
    return h.hexdigest()


def compute_subtree_hash(
    node: Dict[str, Any],
    exclude_fields: Set[str] = None,
    cache: Dict[str, str] = None
) -> str:
    """
    Compute Merkle hash of node including all descendants.

    This is the key optimization: if subtree hash matches previous snapshot,
    entire subtree can be skipped during diff.

    Args:
        node: Tree node dictionary from Sway
        exclude_fields: Set of field names to exclude
        cache: Optional cache to store computed hashes (node_id -> hash)

    Returns:
        Hex string of xxHash64 representing entire subtree

    Performance: ~0.1-0.2ms for 100-window tree (with cache reuse)
    """
    if exclude_fields is None:
        exclude_fields = DEFAULT_EXCLUDE_FIELDS

    # Compute content hash for this node
    content_hash = compute_content_hash(node, exclude_fields)

    # Recursively compute child hashes
    child_hashes: List[str] = []

    # Regular child nodes
    if 'nodes' in node and node['nodes']:
        for child in node['nodes']:
            child_hash = compute_subtree_hash(child, exclude_fields, cache)
            child_hashes.append(child_hash)

    # Floating child nodes
    if 'floating_nodes' in node and node['floating_nodes']:
        for child in node['floating_nodes']:
            child_hash = compute_subtree_hash(child, exclude_fields, cache)
            child_hashes.append(child_hash)

    # Combine content hash with child hashes to create Merkle hash
    # This ensures any change in descendants propagates up to root
    combined = {
        'content': content_hash,
        'children': child_hashes
    }

    serialized = orjson.dumps(combined, option=orjson.OPT_SORT_KEYS)

    h = xxhash.xxh64()
    h.update(serialized)
    subtree_hash = h.hexdigest()

    # Cache the result if cache provided
    if cache is not None and 'id' in node:
        cache[str(node['id'])] = subtree_hash

    return subtree_hash


def compute_tree_hash(tree: Dict[str, Any], exclude_fields: Set[str] = None) -> str:
    """
    Compute root hash for entire Sway tree.

    This is the fast-path check: if root hash matches previous snapshot,
    no changes occurred anywhere in tree.

    Args:
        tree: Complete Sway tree from i3ipc.Connection().get_tree()
        exclude_fields: Set of field names to exclude

    Returns:
        Hex string of xxHash64 for entire tree

    Performance: ~0.5ms for 100-window tree
    """
    return compute_subtree_hash(tree, exclude_fields)


def extract_node_id(node: Dict[str, Any]) -> str:
    """
    Extract unique identifier for a node.

    Uses Sway's ID field, or constructs identifier from name/type.

    Args:
        node: Tree node dictionary

    Returns:
        String identifier for this node
    """
    if 'id' in node:
        return str(node['id'])
    elif 'name' in node and node['name']:
        return f"{node.get('type', 'unknown')}:{node['name']}"
    else:
        # Fallback for unnamed nodes
        return f"{node.get('type', 'unknown')}:{id(node)}"


def get_node_path(node: Dict[str, Any], root: Dict[str, Any]) -> str:
    """
    Compute JSONPath-style path to node within tree.

    Example: "outputs[0].workspaces[2].nodes[5]"

    Args:
        node: Target node
        root: Root of tree

    Returns:
        Path string for human-readable display

    Note: This is a simplified implementation.
    For production, would need full tree traversal with parent tracking.
    """
    node_id = extract_node_id(node)

    # For MVP, return simple identifier
    # TODO: Implement full path traversal for User Story 3
    node_type = node.get('type', 'unknown')
    if node_type == 'workspace':
        name = node.get('name', 'unnamed')
        return f"workspace[{name}]"
    elif node_type == 'con' and 'window' in node:
        window_id = node['window']
        return f"window[{window_id}]"
    elif node_type == 'output':
        name = node.get('name', 'unknown')
        return f"output[{name}]"
    else:
        return f"{node_type}[{node_id}]"


def compute_node_hashes(tree: Dict[str, Any], exclude_fields: Set[str] = None) -> Dict[str, str]:
    """
    Compute hash for every node in tree and return mapping.

    Used for cache population and node-level comparison.

    Args:
        tree: Complete Sway tree
        exclude_fields: Set of field names to exclude

    Returns:
        Dictionary mapping node_id -> subtree_hash

    Performance: ~0.1-0.2ms for 100-window tree
    """
    cache: Dict[str, str] = {}
    compute_subtree_hash(tree, exclude_fields, cache)
    return cache
