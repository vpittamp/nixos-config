# Data Model: Visual Worktree Relationship Map

**Feature**: 111-visual-map-worktrees
**Date**: 2025-12-02

## Entities

### WorktreeRelationship

Represents the git relationship between two branches/worktrees.

```python
from dataclasses import dataclass
from typing import Optional
import time

@dataclass
class WorktreeRelationship:
    """Git relationship between source and target branches."""

    source_branch: str              # Branch being analyzed
    target_branch: str              # Branch to compare against (usually parent)
    merge_base_commit: str          # Common ancestor commit hash (7 chars)
    ahead_count: int                # Commits in source not in target
    behind_count: int               # Commits in target not in source
    is_diverged: bool               # True if both ahead AND behind
    computed_at: int                # Unix timestamp of computation

    def is_stale(self, ttl_seconds: int = 300) -> bool:
        """Check if relationship data is older than TTL."""
        return int(time.time()) - self.computed_at > ttl_seconds

    @property
    def sync_label(self) -> str:
        """Format sync status as display label (e.g., '↑3 ↓2')."""
        parts = []
        if self.ahead_count > 0:
            parts.append(f"↑{self.ahead_count}")
        if self.behind_count > 0:
            parts.append(f"↓{self.behind_count}")
        return " ".join(parts) if parts else ""
```

### WorktreeNode

Visual node representation for the map.

```python
from dataclasses import dataclass, field
from typing import Optional, List
from enum import Enum

class NodeType(Enum):
    MAIN = "main"           # Main/master branch
    FEATURE = "feature"     # Feature branch
    HOTFIX = "hotfix"       # Hotfix branch
    RELEASE = "release"     # Release branch

class NodeStatus(Enum):
    ACTIVE = "active"       # Recent activity
    STALE = "stale"         # No activity 30+ days
    MERGED = "merged"       # Merged into main
    CONFLICT = "conflict"   # Has merge conflicts

@dataclass
class WorktreeNode:
    """Visual representation of a worktree in the map."""

    branch: str                         # Full branch name
    branch_number: Optional[str]        # Extracted number (e.g., "111")
    branch_description: str             # Human-readable description
    qualified_name: str                 # Full qualified name (account/repo:branch)

    # Position (computed by layout algorithm)
    x: float = 0.0
    y: float = 0.0
    layer: int = 0                      # Hierarchical layer (0 = main)

    # Visual properties
    node_type: NodeType = NodeType.FEATURE
    status: NodeStatus = NodeStatus.ACTIVE
    is_dirty: bool = False
    is_active: bool = False             # Currently selected worktree

    # Git metadata
    ahead_of_parent: int = 0
    behind_parent: int = 0
    parent_branch: Optional[str] = None
    last_commit_relative: str = ""
    last_commit_message: str = ""

    # Tooltip content
    @property
    def tooltip(self) -> str:
        """Generate tooltip text for hover display."""
        lines = [
            f"Branch: {self.branch}",
            f"Status: {'Dirty' if self.is_dirty else 'Clean'}",
        ]
        if self.ahead_of_parent or self.behind_parent:
            sync = []
            if self.ahead_of_parent:
                sync.append(f"{self.ahead_of_parent} ahead")
            if self.behind_parent:
                sync.append(f"{self.behind_parent} behind")
            lines.append(f"Sync: {', '.join(sync)}")
        if self.last_commit_relative:
            lines.append(f"Last: {self.last_commit_relative}")
        if self.last_commit_message:
            lines.append(f"Msg: {self.last_commit_message[:40]}...")
        return "\\n".join(lines)
```

### RelationshipEdge

Connection between two nodes in the map.

```python
from dataclasses import dataclass
from enum import Enum

class EdgeType(Enum):
    PARENT_CHILD = "parent_child"   # Direct parent relationship
    MERGED = "merged"               # Branch was merged
    CONFLICT = "conflict"           # Potential merge conflict

@dataclass
class RelationshipEdge:
    """Visual connection between two worktree nodes."""

    source_branch: str              # Parent/source node
    target_branch: str              # Child/target node
    edge_type: EdgeType
    ahead_count: int = 0            # Commits in target not in source
    behind_count: int = 0           # Commits in source not in target
    conflict_files: List[str] = field(default_factory=list)

    @property
    def label(self) -> str:
        """Format edge label for display."""
        if self.edge_type == EdgeType.MERGED:
            return "✓"
        if self.edge_type == EdgeType.CONFLICT:
            return f"⚠ {len(self.conflict_files)}"
        parts = []
        if self.ahead_count:
            parts.append(f"↑{self.ahead_count}")
        if self.behind_count:
            parts.append(f"↓{self.behind_count}")
        return " ".join(parts)

    @property
    def css_class(self) -> str:
        """Get CSS class for edge styling."""
        if self.edge_type == EdgeType.MERGED:
            return "edge-merged"
        if self.edge_type == EdgeType.CONFLICT:
            return "edge-conflict"
        if self.ahead_count and self.behind_count:
            return "edge-diverged"
        return "edge-normal"
```

### WorktreeMap

Complete map data structure.

```python
from dataclasses import dataclass, field
from typing import List, Dict, Optional

@dataclass
class WorktreeMap:
    """Complete visual map of worktree relationships."""

    repository: str                     # Repository qualified name (account/repo)
    nodes: List[WorktreeNode] = field(default_factory=list)
    edges: List[RelationshipEdge] = field(default_factory=list)
    main_branch: str = "main"
    svg_path: Optional[str] = None      # Path to generated SVG file
    computed_at: int = 0                # Timestamp of computation

    # Layout metadata
    width: int = 400
    height: int = 600
    max_depth: int = 5                  # Maximum layer depth

    def get_node(self, branch: str) -> Optional[WorktreeNode]:
        """Get node by branch name."""
        for node in self.nodes:
            if node.branch == branch:
                return node
        return None

    def get_children(self, branch: str) -> List[WorktreeNode]:
        """Get all direct children of a branch."""
        return [
            self.get_node(edge.target_branch)
            for edge in self.edges
            if edge.source_branch == branch and edge.edge_type == EdgeType.PARENT_CHILD
        ]

    def to_svg_data(self) -> Dict:
        """Export data for SVG generation."""
        return {
            "repository": self.repository,
            "width": self.width,
            "height": self.height,
            "nodes": [
                {
                    "branch": n.branch,
                    "x": n.x,
                    "y": n.y,
                    "type": n.node_type.value,
                    "status": n.status.value,
                    "is_dirty": n.is_dirty,
                    "is_active": n.is_active,
                    "label": n.branch_number or n.branch[:8],
                    "tooltip": n.tooltip,
                    "qualified_name": n.qualified_name,
                }
                for n in self.nodes
            ],
            "edges": [
                {
                    "source": e.source_branch,
                    "target": e.target_branch,
                    "label": e.label,
                    "css_class": e.css_class,
                }
                for e in self.edges
            ],
        }
```

### WorktreeRelationshipCache

In-memory cache for computed relationships.

```python
from dataclasses import dataclass, field
from typing import Dict, Optional
from pathlib import Path
import time

@dataclass
class WorktreeRelationshipCache:
    """In-memory cache for branch relationships with TTL."""

    ttl_seconds: int = 300              # 5 minute default TTL
    _cache: Dict[str, WorktreeRelationship] = field(default_factory=dict)

    def _make_key(self, repo_path: str, branch_a: str, branch_b: str) -> str:
        """Generate cache key from repo and branches."""
        normalized_path = str(Path(repo_path).resolve())
        return f"{normalized_path}:{branch_a}~{branch_b}"

    def get(self, repo_path: str, branch_a: str, branch_b: str) -> Optional[WorktreeRelationship]:
        """Get cached relationship if not stale."""
        key = self._make_key(repo_path, branch_a, branch_b)
        rel = self._cache.get(key)
        if rel and not rel.is_stale(self.ttl_seconds):
            return rel
        return None

    def set(self, repo_path: str, branch_a: str, branch_b: str, rel: WorktreeRelationship):
        """Cache a relationship."""
        key = self._make_key(repo_path, branch_a, branch_b)
        rel.computed_at = int(time.time())
        self._cache[key] = rel

    def invalidate_repo(self, repo_path: str):
        """Clear all cached relationships for a repository."""
        normalized = str(Path(repo_path).resolve())
        keys_to_delete = [k for k in self._cache if k.startswith(normalized)]
        for k in keys_to_delete:
            del self._cache[k]

    def clear(self):
        """Clear entire cache."""
        self._cache.clear()
```

## Entity Relationships

```
WorktreeMap (1)
    │
    ├──── nodes: WorktreeNode (many)
    │         │
    │         └──── parent_branch → WorktreeNode.branch
    │
    └──── edges: RelationshipEdge (many)
              │
              ├──── source_branch → WorktreeNode.branch
              └──── target_branch → WorktreeNode.branch

WorktreeRelationshipCache (1)
    │
    └──── _cache: WorktreeRelationship (many)
                  │
                  ├──── source_branch
                  └──── target_branch
```

## State Transitions

### WorktreeNode.status

```
ACTIVE ──────────────────────────────────────► STALE
  │                   (30+ days no commits)
  │
  ├──────────────────────────────────────────► MERGED
  │               (merged into main)
  │
  └──────────────────────────────────────────► CONFLICT
                  (merge conflicts detected)
```

### RelationshipEdge.edge_type

```
PARENT_CHILD ────────────────────────────────► MERGED
                    (branch merged)

PARENT_CHILD ────────────────────────────────► CONFLICT
                (conflict files detected)
```

## Validation Rules

### WorktreeNode

- `branch` must not be empty
- `branch_number` if present must be 2-4 digits
- `x` and `y` must be non-negative
- `layer` must be 0-5 (max depth)
- `qualified_name` must match pattern `account/repo:branch`

### RelationshipEdge

- `source_branch` and `target_branch` must not be equal
- `ahead_count` and `behind_count` must be non-negative
- `conflict_files` must be valid file paths

### WorktreeMap

- `nodes` must contain at least one node (main branch)
- Each edge must reference existing nodes
- `width` and `height` must be positive
- No cycles in parent-child edges
