# Feature 111: Visual Worktree Relationship Map - Data Models
"""
Data models for representing worktree relationships and visual map structure.

These models support the visual map feature by capturing:
- Git relationships between branches (ahead/behind, merge-base)
- Visual node properties (position, type, status)
- Edge representations (parent-child, merged, conflict)
- Complete map structure for SVG generation
"""

from dataclasses import dataclass, field
from typing import Optional, List, Dict
from enum import Enum
import time


# =============================================================================
# Core Relationship Model
# =============================================================================


@dataclass
class WorktreeRelationship:
    """Git relationship between two branches/worktrees.

    Represents the result of comparing two branches using git merge-base
    and rev-list commands to determine ahead/behind counts.

    Attributes:
        source_branch: Branch being analyzed
        target_branch: Branch to compare against (usually parent or main)
        merge_base_commit: Common ancestor commit hash (7 chars)
        ahead_count: Commits in source not in target
        behind_count: Commits in target not in source
        is_diverged: True if both ahead AND behind (needs rebase)
        computed_at: Unix timestamp when relationship was computed
    """

    source_branch: str
    target_branch: str
    merge_base_commit: str
    ahead_count: int
    behind_count: int
    is_diverged: bool
    computed_at: int

    def is_stale(self, ttl_seconds: int = 300) -> bool:
        """Check if relationship data is older than TTL.

        Args:
            ttl_seconds: Time-to-live in seconds (default 5 minutes)

        Returns:
            True if the data is stale and should be recomputed
        """
        return int(time.time()) - self.computed_at > ttl_seconds

    @property
    def sync_label(self) -> str:
        """Format sync status as display label.

        Returns labels like:
        - "↑5" for 5 commits ahead
        - "↓3" for 3 commits behind
        - "↑5 ↓3" for diverged branches
        - "" for branches in sync

        Returns:
            Formatted sync label string
        """
        parts = []
        if self.ahead_count > 0:
            parts.append(f"↑{self.ahead_count}")
        if self.behind_count > 0:
            parts.append(f"↓{self.behind_count}")
        return " ".join(parts) if parts else ""


# =============================================================================
# Visual Node Types and Status
# =============================================================================


class NodeType(Enum):
    """Type of branch/worktree for visual styling.

    Different node types get different colors in the visual map:
    - MAIN: Primary integration target (mauve color)
    - FEATURE: Standard feature branches (blue color)
    - HOTFIX: Emergency fixes (peach/orange color)
    - RELEASE: Release preparation branches (green color)
    """

    MAIN = "main"
    FEATURE = "feature"
    HOTFIX = "hotfix"
    RELEASE = "release"


class NodeStatus(Enum):
    """Current status of a worktree node.

    Status affects visual styling:
    - ACTIVE: Normal appearance, recent activity
    - STALE: Faded appearance, no commits in 30+ days
    - MERGED: Checkmark indicator, already merged to main
    - CONFLICT: Warning indicator, has merge conflicts
    """

    ACTIVE = "active"
    STALE = "stale"
    MERGED = "merged"
    CONFLICT = "conflict"


# =============================================================================
# Visual Node Model
# =============================================================================


@dataclass
class WorktreeNode:
    """Visual representation of a worktree in the map.

    Contains all data needed to render a node in the SVG:
    - Identity (branch name, qualified name)
    - Position (x, y, layer in hierarchy)
    - Visual properties (type, status, dirty flag)
    - Git metadata (ahead/behind, parent, last commit)

    Attributes:
        branch: Full branch name
        branch_number: Extracted number (e.g., "111" from "111-visual-map")
        branch_description: Human-readable description
        qualified_name: Full qualified name (account/repo:branch)
        x: X position in SVG canvas (computed by layout algorithm)
        y: Y position in SVG canvas (computed by layout algorithm)
        layer: Hierarchical layer (0 = main, 1 = direct children, etc.)
        node_type: Type of branch for color coding
        status: Current status for visual indicators
        is_dirty: Has uncommitted changes
        is_active: Currently selected/focused worktree
        ahead_of_parent: Commits ahead of parent branch
        behind_parent: Commits behind parent branch
        parent_branch: Parent branch name
        last_commit_relative: Relative time since last commit
        last_commit_message: Last commit message (for tooltip)
    """

    branch: str
    branch_number: Optional[str]
    branch_description: str
    qualified_name: str

    # Position (computed by layout algorithm)
    x: float = 0.0
    y: float = 0.0
    layer: int = 0

    # Visual properties
    node_type: NodeType = NodeType.FEATURE
    status: NodeStatus = NodeStatus.ACTIVE
    is_dirty: bool = False
    is_active: bool = False

    # Git metadata
    ahead_of_parent: int = 0
    behind_parent: int = 0
    parent_branch: Optional[str] = None
    last_commit_relative: str = ""
    last_commit_message: str = ""

    @property
    def tooltip(self) -> str:
        """Generate tooltip text for hover display.

        Returns:
            Multi-line tooltip string with branch details
        """
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
            msg = (
                self.last_commit_message[:40] + "..."
                if len(self.last_commit_message) > 40
                else self.last_commit_message
            )
            lines.append(f"Msg: {msg}")
        return "\\n".join(lines)


# =============================================================================
# Edge Types and Model
# =============================================================================


class EdgeType(Enum):
    """Type of relationship edge between nodes.

    Edge types determine visual styling:
    - PARENT_CHILD: Solid line (direct parent relationship)
    - MERGED: Dashed line with checkmark (branch was merged)
    - CONFLICT: Red dashed line (potential merge conflict)
    """

    PARENT_CHILD = "parent_child"
    MERGED = "merged"
    CONFLICT = "conflict"


@dataclass
class RelationshipEdge:
    """Visual connection between two worktree nodes.

    Represents an edge in the graph with:
    - Source and target branch references
    - Type of relationship
    - Ahead/behind counts for labels
    - Conflict file list (if applicable)

    Attributes:
        source_branch: Parent/source node branch name
        target_branch: Child/target node branch name
        edge_type: Type of relationship
        ahead_count: Commits in target not in source
        behind_count: Commits in source not in target
        conflict_files: List of files with potential conflicts
    """

    source_branch: str
    target_branch: str
    edge_type: EdgeType
    ahead_count: int = 0
    behind_count: int = 0
    conflict_files: List[str] = field(default_factory=list)

    @property
    def label(self) -> str:
        """Format edge label for display.

        Returns:
            Label string (e.g., "↑5 ↓3", "✓", or "⚠ 3")
        """
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
        """Get CSS class for edge styling.

        Returns:
            CSS class name for SVG styling
        """
        if self.edge_type == EdgeType.MERGED:
            return "edge-merged"
        if self.edge_type == EdgeType.CONFLICT:
            return "edge-conflict"
        if self.ahead_count and self.behind_count:
            return "edge-diverged"
        return "edge-normal"


# =============================================================================
# Complete Map Model
# =============================================================================


@dataclass
class WorktreeMap:
    """Complete visual map of worktree relationships.

    Contains all data needed to render the full SVG visualization:
    - Repository identification
    - List of nodes (worktrees)
    - List of edges (relationships)
    - Layout metadata (dimensions, settings)

    Attributes:
        repository: Repository qualified name (account/repo)
        nodes: List of WorktreeNode instances
        edges: List of RelationshipEdge instances
        main_branch: Name of the main/master branch
        svg_path: Path to generated SVG file (set after generation)
        computed_at: Unix timestamp when map was computed
        width: SVG canvas width in pixels
        height: SVG canvas height in pixels
        max_depth: Maximum layer depth for hierarchy
    """

    repository: str
    nodes: List[WorktreeNode] = field(default_factory=list)
    edges: List[RelationshipEdge] = field(default_factory=list)
    main_branch: str = "main"
    svg_path: Optional[str] = None
    computed_at: int = 0

    # Layout metadata
    width: int = 400
    height: int = 600
    max_depth: int = 5

    def get_node(self, branch: str) -> Optional[WorktreeNode]:
        """Get node by branch name.

        Args:
            branch: Branch name to find

        Returns:
            WorktreeNode if found, None otherwise
        """
        for node in self.nodes:
            if node.branch == branch:
                return node
        return None

    def get_children(self, branch: str) -> List[WorktreeNode]:
        """Get all direct children of a branch.

        Args:
            branch: Parent branch name

        Returns:
            List of child WorktreeNode instances
        """
        children = []
        for edge in self.edges:
            if (
                edge.source_branch == branch
                and edge.edge_type == EdgeType.PARENT_CHILD
            ):
                node = self.get_node(edge.target_branch)
                if node:
                    children.append(node)
        return children

    def to_svg_data(self) -> Dict:
        """Export data for SVG generation.

        Returns:
            Dictionary with all data needed for SVG rendering
        """
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
