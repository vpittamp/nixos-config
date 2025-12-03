# Feature 111: Visual Worktree Relationship Map - Service Layer
"""
Service for building and rendering worktree relationship maps.

This module provides:
- compute_hierarchical_layout(): Assign x,y positions to nodes in tree structure
- generate_worktree_map_svg(): Render WorktreeMap as SVG with Catppuccin colors
- build_worktree_map(): Construct complete WorktreeMap from repository data
"""

import subprocess
import time
from typing import Optional, List, Dict, Any
from pathlib import Path

from ..models.worktree_relationship import (
    WorktreeRelationship,
    WorktreeNode,
    WorktreeMap,
    RelationshipEdge,
    NodeType,
    NodeStatus,
    EdgeType,
)
from .git_utils import (
    get_merge_base,
    get_branch_relationship,
    find_likely_parent_branch,
)


# =============================================================================
# Catppuccin Mocha Color Palette
# =============================================================================

CATPPUCCIN_MOCHA = {
    "base": "#1e1e2e",
    "mantle": "#181825",
    "surface0": "#313244",
    "surface1": "#45475a",
    "surface2": "#585b70",
    "text": "#cdd6f4",
    "subtext0": "#a6adc8",
    "subtext1": "#bac2de",
    "mauve": "#cba6f7",
    "blue": "#89b4fa",
    "sapphire": "#74c7ec",
    "teal": "#94e2d5",
    "green": "#a6e3a1",
    "yellow": "#f9e2af",
    "peach": "#fab387",
    "red": "#f38ba8",
    "pink": "#f5c2e7",
    "overlay0": "#6c7086",
}

# Node type to color mapping
NODE_TYPE_COLORS = {
    NodeType.MAIN: CATPPUCCIN_MOCHA["mauve"],
    NodeType.FEATURE: CATPPUCCIN_MOCHA["blue"],
    NodeType.HOTFIX: CATPPUCCIN_MOCHA["peach"],
    NodeType.RELEASE: CATPPUCCIN_MOCHA["green"],
}

# Layout constants
DEFAULT_NODE_RADIUS = 30
DEFAULT_LAYER_HEIGHT = 100
DEFAULT_NODE_SPACING = 80
DEFAULT_MARGIN = 50

# Compact mode layout constants (Feature 111 T073)
COMPACT_NODE_RADIUS = 18
COMPACT_LAYER_HEIGHT = 60
COMPACT_NODE_SPACING = 50
COMPACT_MARGIN = 25
COMPACT_MAX_WIDTH = 300
COMPACT_MAX_HEIGHT = 400


# =============================================================================
# Branch Parsing (T038-T039) - User Story 2
# =============================================================================


def parse_branch_description(branch: str) -> str:
    """Convert branch name to human-readable description.

    Examples:
        - "109-enhance-worktree-ux" -> "Enhance Worktree UX"
        - "hotfix-critical-bug" -> "Critical Bug"
        - "release-v2.0" -> "V2.0"
        - "feature/new-feature" -> "New Feature"
        - "main" -> "Main"

    Args:
        branch: Git branch name

    Returns:
        Human-readable description with title case
    """
    import re

    if not branch:
        return ""

    # Handle main/master branches
    if branch.lower() in ("main", "master"):
        return branch.title()

    # Remove common prefixes
    prefixes_to_strip = ["feature/", "hotfix-", "release-", "fix-", "bugfix-"]
    working = branch
    for prefix in prefixes_to_strip:
        if working.lower().startswith(prefix):
            working = working[len(prefix):]
            break

    # Handle feature/ prefix with slash
    if "/" in working:
        working = working.split("/")[-1]

    # Remove leading number pattern (e.g., "109-" or "111_")
    match = re.match(r"^\d+[-_](.+)$", working)
    if match:
        working = match.group(1)

    # If only numbers remain, return as-is
    if working.isdigit():
        return branch

    # Replace separators with spaces and title case
    result = working.replace("-", " ").replace("_", " ")
    result = result.title()

    return result


def detect_branch_type(branch: str) -> NodeType:
    """Detect branch type from name patterns.

    Detection rules (case-insensitive):
        - "main" or "master" -> MAIN
        - Contains "hotfix" -> HOTFIX
        - Contains "release" or starts with "release-" -> RELEASE
        - Everything else -> FEATURE

    Args:
        branch: Git branch name

    Returns:
        NodeType enum value
    """
    lower = branch.lower()

    # Main/master branches
    if lower in ("main", "master"):
        return NodeType.MAIN

    # Hotfix branches (contains "hotfix")
    if "hotfix" in lower:
        return NodeType.HOTFIX

    # Release branches (contains "release")
    if "release" in lower:
        return NodeType.RELEASE

    # Default to feature
    return NodeType.FEATURE


# =============================================================================
# Layout Algorithm (T021-T023)
# =============================================================================


def compute_hierarchical_layout(map_data: WorktreeMap) -> WorktreeMap:
    """Assign x,y positions to nodes using hierarchical layout.

    Uses a Sugiyama-inspired algorithm:
    1. Assign layers based on parent depth (main = 0, children = 1, etc.)
    2. Position nodes within each layer (centered, evenly spaced)
    3. Adjust canvas dimensions to fit content

    Args:
        map_data: WorktreeMap with nodes and edges but no positions

    Returns:
        Same WorktreeMap with x,y positions computed for all nodes
    """
    if not map_data.nodes:
        return map_data

    # Step 1: Assign layers based on parent relationships
    _assign_layers(map_data)

    # Step 2: Group nodes by layer
    layers: Dict[int, List[WorktreeNode]] = {}
    for node in map_data.nodes:
        if node.layer not in layers:
            layers[node.layer] = []
        layers[node.layer].append(node)

    # Step 3: Calculate canvas dimensions
    max_layer = max(layers.keys()) if layers else 0
    max_nodes_in_layer = max(len(nodes) for nodes in layers.values()) if layers else 1

    # Adjust dimensions based on content
    required_width = max(
        400, max_nodes_in_layer * DEFAULT_NODE_SPACING + 2 * DEFAULT_MARGIN
    )
    required_height = max(
        300, (max_layer + 1) * DEFAULT_LAYER_HEIGHT + 2 * DEFAULT_MARGIN
    )

    map_data.width = int(required_width)
    map_data.height = int(required_height)
    map_data.max_depth = max_layer

    # Step 4: Assign x,y positions within each layer
    for layer_num, nodes in layers.items():
        _position_layer_nodes(nodes, layer_num, map_data.width, map_data.height)

    return map_data


def _assign_layers(map_data: WorktreeMap) -> None:
    """Assign layer numbers to nodes based on parent-child relationships."""
    # Find the main/root node
    main_node = None
    for node in map_data.nodes:
        if node.node_type == NodeType.MAIN or node.branch == map_data.main_branch:
            main_node = node
            main_node.layer = 0
            break

    if not main_node:
        # Fallback: first node is root
        if map_data.nodes:
            map_data.nodes[0].layer = 0
            main_node = map_data.nodes[0]

    # Build parent-child lookup from edges
    children_of: Dict[str, List[str]] = {}
    for edge in map_data.edges:
        if edge.edge_type == EdgeType.PARENT_CHILD:
            if edge.source_branch not in children_of:
                children_of[edge.source_branch] = []
            children_of[edge.source_branch].append(edge.target_branch)

    # BFS to assign layers
    visited = {main_node.branch} if main_node else set()
    queue = [main_node] if main_node else []

    while queue:
        current = queue.pop(0)
        if not current:
            continue

        child_branches = children_of.get(current.branch, [])
        for child_branch in child_branches:
            child_node = map_data.get_node(child_branch)
            if child_node and child_branch not in visited:
                child_node.layer = current.layer + 1
                visited.add(child_branch)
                queue.append(child_node)

    # Assign unvisited nodes (orphans) to layer 1
    for node in map_data.nodes:
        if node.branch not in visited:
            node.layer = 1


def _position_layer_nodes(
    nodes: List[WorktreeNode], layer: int, canvas_width: int, canvas_height: int
) -> None:
    """Position nodes within a single layer.

    Nodes are centered horizontally with even spacing.
    Y position is determined by layer number.
    """
    if not nodes:
        return

    # Y position based on layer
    y = DEFAULT_MARGIN + layer * DEFAULT_LAYER_HEIGHT

    # X positions: center nodes horizontally
    num_nodes = len(nodes)
    total_width = (num_nodes - 1) * DEFAULT_NODE_SPACING if num_nodes > 1 else 0
    start_x = (canvas_width - total_width) / 2

    for i, node in enumerate(nodes):
        node.x = start_x + i * DEFAULT_NODE_SPACING
        node.y = y


# =============================================================================
# SVG Generation (T024-T027)
# =============================================================================


def generate_svg_style() -> str:
    """Generate CSS style block with Catppuccin Mocha colors."""
    return f"""<style>
    .background {{ fill: {CATPPUCCIN_MOCHA['base']}; }}
    .edge {{ stroke: {CATPPUCCIN_MOCHA['overlay0']}; stroke-width: 2; fill: none; }}
    .edge-diverged {{ stroke: {CATPPUCCIN_MOCHA['yellow']}; stroke-dasharray: 5,3; }}
    .edge-merged {{ stroke: {CATPPUCCIN_MOCHA['green']}; stroke-dasharray: 3,3; }}
    .edge-conflict {{ stroke: {CATPPUCCIN_MOCHA['red']}; stroke-dasharray: 5,2; }}
    .node-main {{ fill: {CATPPUCCIN_MOCHA['mauve']}; }}
    .node-feature {{ fill: {CATPPUCCIN_MOCHA['blue']}; }}
    .node-hotfix {{ fill: {CATPPUCCIN_MOCHA['peach']}; }}
    .node-release {{ fill: {CATPPUCCIN_MOCHA['green']}; }}
    .node-active {{ stroke: {CATPPUCCIN_MOCHA['teal']}; stroke-width: 3; }}
    .node-merged {{ opacity: 0.7; }}
    .node-stale {{ opacity: 0.5; }}
    .node-dirty {{ }}
    .node-label {{ fill: {CATPPUCCIN_MOCHA['text']}; font-family: monospace; font-size: 12px; text-anchor: middle; dominant-baseline: central; }}
    .edge-label {{ fill: {CATPPUCCIN_MOCHA['subtext0']}; font-family: monospace; font-size: 10px; text-anchor: middle; }}
    .dirty-indicator {{ fill: {CATPPUCCIN_MOCHA['red']}; }}
    .merged-badge {{ fill: {CATPPUCCIN_MOCHA['green']}; }}
    .merged-check {{ fill: {CATPPUCCIN_MOCHA['base']}; font-size: 10px; text-anchor: middle; dominant-baseline: central; }}
    .stale-badge {{ fill: {CATPPUCCIN_MOCHA['overlay0']}; }}
    .stale-icon {{ font-size: 8px; text-anchor: middle; dominant-baseline: central; }}
    </style>"""


def render_edges(map_data: WorktreeMap) -> str:
    """Render all edges as SVG lines with labels."""
    lines = []

    for edge in map_data.edges:
        source_node = map_data.get_node(edge.source_branch)
        target_node = map_data.get_node(edge.target_branch)

        if not source_node or not target_node:
            continue

        # Determine edge class
        css_class = f"edge {edge.css_class}"

        # Draw line from source to target
        lines.append(
            f'<line class="{css_class}" '
            f'x1="{source_node.x}" y1="{source_node.y + DEFAULT_NODE_RADIUS}" '
            f'x2="{target_node.x}" y2="{target_node.y - DEFAULT_NODE_RADIUS}"/>'
        )

        # Add label at midpoint if there's ahead/behind info
        if edge.label:
            mid_x = (source_node.x + target_node.x) / 2
            mid_y = (source_node.y + target_node.y) / 2
            lines.append(
                f'<text class="edge-label" x="{mid_x}" y="{mid_y}">{edge.label}</text>'
            )

    return "\n    ".join(lines)


def render_nodes(map_data: WorktreeMap) -> str:
    """Render all nodes as SVG circles with labels."""
    elements = []

    for node in map_data.nodes:
        # Determine node class
        type_class = f"node-{node.node_type.value}"
        active_class = "node-active" if node.is_active else ""
        # Feature 111 T062: Add merged class for visual differentiation
        merged_class = "node-merged" if node.status == NodeStatus.MERGED else ""
        # Feature 111 T068: Add stale class for faded appearance
        stale_class = "node-stale" if node.status == NodeStatus.STALE else ""
        css_class = f"{type_class} {active_class} {merged_class} {stale_class}".strip()

        # Draw circle
        elements.append(
            f'<circle class="{css_class}" '
            f'cx="{node.x}" cy="{node.y}" r="{DEFAULT_NODE_RADIUS}"/>'
        )

        # Draw label (branch number or abbreviated name)
        label = node.branch_number if node.branch_number else node.branch[:8]
        elements.append(
            f'<text class="node-label" x="{node.x}" y="{node.y}">{label}</text>'
        )

        # Feature 111 T062: Draw merged indicator (checkmark badge)
        if node.status == NodeStatus.MERGED:
            check_x = node.x + DEFAULT_NODE_RADIUS - 6
            check_y = node.y - DEFAULT_NODE_RADIUS + 6
            elements.append(
                f'<circle class="merged-badge" '
                f'cx="{check_x}" cy="{check_y}" r="7"/>'
            )
            elements.append(
                f'<text class="merged-check" x="{check_x}" y="{check_y + 1}">✓</text>'
            )

        # Feature 111 T069: Draw stale indicator (clock/sleep badge)
        if node.status == NodeStatus.STALE:
            stale_x = node.x + DEFAULT_NODE_RADIUS - 6
            stale_y = node.y - DEFAULT_NODE_RADIUS + 6
            elements.append(
                f'<circle class="stale-badge" '
                f'cx="{stale_x}" cy="{stale_y}" r="7"/>'
            )
            elements.append(
                f'<text class="stale-icon" x="{stale_x}" y="{stale_y + 1}">💤</text>'
            )

        # Draw dirty indicator (small red circle)
        if node.is_dirty:
            indicator_x = node.x + DEFAULT_NODE_RADIUS - 5
            indicator_y = node.y - DEFAULT_NODE_RADIUS + 5
            elements.append(
                f'<circle class="dirty-indicator" '
                f'cx="{indicator_x}" cy="{indicator_y}" r="5"/>'
            )

    return "\n    ".join(elements)


def generate_worktree_map_svg(
    map_data: WorktreeMap, output_path: Optional[str] = None, compact_mode: bool = False
) -> str:
    """Generate complete SVG from WorktreeMap data.

    Args:
        map_data: WorktreeMap with positioned nodes and edges
        output_path: Optional file path to write SVG
        compact_mode: If True, use compact rendering (Feature 111 T074)

    Returns:
        SVG string content
    """
    # Feature 111 T074: Delegate to compact generator if requested
    if compact_mode:
        return generate_compact_svg(map_data, output_path)

    svg_parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {map_data.width} {map_data.height}" '
        f'width="{map_data.width}" height="{map_data.height}">',
        generate_svg_style(),
        f'<rect class="background" width="{map_data.width}" height="{map_data.height}"/>',
        "<!-- Edges -->",
        render_edges(map_data),
        "<!-- Nodes -->",
        render_nodes(map_data),
        "</svg>",
    ]

    svg_content = "\n".join(svg_parts)

    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            f.write(svg_content)
        map_data.svg_path = output_path

    return svg_content


def render_edges_compact(map_data: WorktreeMap) -> str:
    """Render all edges as SVG lines for compact mode (no labels)."""
    lines = []

    for edge in map_data.edges:
        source_node = map_data.get_node(edge.source_branch)
        target_node = map_data.get_node(edge.target_branch)

        if not source_node or not target_node:
            continue

        # Determine edge class
        css_class = f"edge {edge.css_class}"

        # Draw line from source to target (using compact node radius)
        lines.append(
            f'<line class="{css_class}" '
            f'x1="{source_node.x}" y1="{source_node.y + COMPACT_NODE_RADIUS}" '
            f'x2="{target_node.x}" y2="{target_node.y - COMPACT_NODE_RADIUS}"/>'
        )
        # Note: No edge labels in compact mode to save space

    return "\n    ".join(lines)


def render_nodes_compact(map_data: WorktreeMap) -> str:
    """Render all nodes as SVG circles with abbreviated labels for compact mode.

    Feature 111 T073: Uses smaller node radius and shorter labels.
    """
    elements = []

    for node in map_data.nodes:
        # Determine node class
        type_class = f"node-{node.node_type.value}"
        active_class = "node-active" if node.is_active else ""
        merged_class = "node-merged" if node.status == NodeStatus.MERGED else ""
        stale_class = "node-stale" if node.status == NodeStatus.STALE else ""
        css_class = f"{type_class} {active_class} {merged_class} {stale_class}".strip()

        # Draw smaller circle
        elements.append(
            f'<circle class="{css_class}" '
            f'cx="{node.x}" cy="{node.y}" r="{COMPACT_NODE_RADIUS}"/>'
        )

        # Draw abbreviated label (max 5 chars for compact)
        if node.branch_number:
            label = node.branch_number
        else:
            # Abbreviate to first 5 chars
            label = node.branch[:5]
        elements.append(
            f'<text class="node-label compact-label" x="{node.x}" y="{node.y}">{label}</text>'
        )

        # Status indicators with smaller badges
        badge_radius = 5
        badge_x = node.x + COMPACT_NODE_RADIUS - 4
        badge_y = node.y - COMPACT_NODE_RADIUS + 4

        # Draw merged indicator (smaller checkmark badge)
        if node.status == NodeStatus.MERGED:
            elements.append(
                f'<circle class="merged-badge" '
                f'cx="{badge_x}" cy="{badge_y}" r="{badge_radius}"/>'
            )
            elements.append(
                f'<text class="merged-check compact-check" x="{badge_x}" y="{badge_y + 1}">✓</text>'
            )

        # Draw stale indicator (smaller)
        if node.status == NodeStatus.STALE:
            elements.append(
                f'<circle class="stale-badge" '
                f'cx="{badge_x}" cy="{badge_y}" r="{badge_radius}"/>'
            )
            elements.append(
                f'<text class="stale-icon compact-icon" x="{badge_x}" y="{badge_y + 1}">💤</text>'
            )

        # Draw dirty indicator (smaller red circle)
        if node.is_dirty:
            indicator_x = node.x + COMPACT_NODE_RADIUS - 3
            indicator_y = node.y - COMPACT_NODE_RADIUS + 3
            elements.append(
                f'<circle class="dirty-indicator" '
                f'cx="{indicator_x}" cy="{indicator_y}" r="3"/>'
            )

    return "\n    ".join(elements)


def compute_compact_layout(map_data: WorktreeMap) -> WorktreeMap:
    """Compute layout for compact mode with tighter spacing.

    Feature 111 T073: Uses smaller dimensions and spacing for panel view.
    """
    if not map_data.nodes:
        return map_data

    # Step 1: Assign layers (same algorithm as default)
    _assign_layers(map_data)

    # Step 2: Group nodes by layer
    layers: Dict[int, List[WorktreeNode]] = {}
    for node in map_data.nodes:
        if node.layer not in layers:
            layers[node.layer] = []
        layers[node.layer].append(node)

    # Step 3: Calculate compact canvas dimensions
    max_layer = max(layers.keys()) if layers else 0
    max_nodes_in_layer = max(len(nodes) for nodes in layers.values()) if layers else 1

    # Use compact constants, constrained to max panel size
    required_width = min(
        COMPACT_MAX_WIDTH,
        max(200, max_nodes_in_layer * COMPACT_NODE_SPACING + 2 * COMPACT_MARGIN)
    )
    required_height = min(
        COMPACT_MAX_HEIGHT,
        max(150, (max_layer + 1) * COMPACT_LAYER_HEIGHT + 2 * COMPACT_MARGIN)
    )

    map_data.width = int(required_width)
    map_data.height = int(required_height)
    map_data.max_depth = max_layer

    # Step 4: Assign x,y positions within each layer (compact spacing)
    for layer_num, nodes in layers.items():
        _position_layer_nodes_compact(nodes, layer_num, map_data.width, map_data.height)

    return map_data


def _position_layer_nodes_compact(
    nodes: List[WorktreeNode], layer: int, canvas_width: int, canvas_height: int
) -> None:
    """Position nodes within a single layer using compact spacing."""
    if not nodes:
        return

    # Y position based on layer (compact spacing)
    y = COMPACT_MARGIN + layer * COMPACT_LAYER_HEIGHT

    # X positions: center nodes horizontally (compact spacing)
    num_nodes = len(nodes)
    total_width = (num_nodes - 1) * COMPACT_NODE_SPACING if num_nodes > 1 else 0
    start_x = (canvas_width - total_width) / 2

    for i, node in enumerate(nodes):
        node.x = start_x + i * COMPACT_NODE_SPACING
        node.y = y


def generate_compact_svg(
    map_data: WorktreeMap, output_path: Optional[str] = None
) -> str:
    """Generate compact SVG optimized for panel view.

    Feature 111 T073: Creates a smaller, more condensed visualization
    suitable for the monitoring panel sidebar. Uses:
    - Smaller node radius (18px vs 30px)
    - Tighter spacing between layers
    - Abbreviated labels (branch number or first 5 chars)
    - No edge labels
    - Maximum dimensions constrained to 300x400px

    Args:
        map_data: WorktreeMap with nodes and edges
        output_path: Optional file path to write SVG

    Returns:
        SVG string content in compact format
    """
    # Recompute layout with compact dimensions
    compact_map = compute_compact_layout(map_data)

    # Add compact-specific CSS
    compact_style = generate_svg_style() + """
    .compact-label { font-size: 9px; }
    .compact-check { font-size: 7px; }
    .compact-icon { font-size: 6px; }
    """

    svg_parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {compact_map.width} {compact_map.height}" '
        f'width="{compact_map.width}" height="{compact_map.height}">',
        compact_style,
        f'<rect class="background" width="{compact_map.width}" height="{compact_map.height}"/>',
        "<!-- Edges (compact) -->",
        render_edges_compact(compact_map),
        "<!-- Nodes (compact) -->",
        render_nodes_compact(compact_map),
        "</svg>",
    ]

    svg_content = "\n".join(svg_parts)

    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            f.write(svg_content)
        compact_map.svg_path = output_path

    return svg_content


# =============================================================================
# Map Building (T028)
# =============================================================================


def _get_all_branches(repo_path: str) -> List[str]:
    """Get all local branches in the repository."""
    try:
        result = subprocess.run(
            ["git", "branch", "--format=%(refname:short)"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return [b.strip() for b in result.stdout.strip().split("\n") if b.strip()]
    except (subprocess.TimeoutExpired, OSError):
        pass
    return []


def _get_worktrees(repo_path: str) -> List[Dict[str, str]]:
    """Get list of worktrees with paths and branches.

    Feature 111 T084: Includes path validation to detect orphaned worktrees.
    """
    try:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return []

        worktrees = []
        current = {}

        for line in result.stdout.split("\n"):
            if line.startswith("worktree "):
                if current:
                    worktrees.append(current)
                current = {"path": line[9:].strip()}
            elif line.startswith("branch refs/heads/"):
                current["branch"] = line[18:].strip()
            elif line == "bare":
                current["bare"] = True

        if current and "bare" not in current:
            worktrees.append(current)

        # Feature 111 T084: Validate worktree paths and mark orphans
        for wt in worktrees:
            path = wt.get("path", "")
            if path and not Path(path).exists():
                wt["orphaned"] = True

        return worktrees
    except (subprocess.TimeoutExpired, OSError):
        pass
    return []


def _detect_main_branch(repo_path: str, branches: List[str]) -> str:
    """Detect the main branch (main or master)."""
    if "main" in branches:
        return "main"
    if "master" in branches:
        return "master"
    # Fallback: first branch
    return branches[0] if branches else "main"


def _extract_branch_number(branch: str) -> Optional[str]:
    """Extract branch number from name (e.g., '111' from '111-feature')."""
    import re

    # Pattern: starts with digits, optionally followed by dash
    match = re.match(r"^(\d+)", branch)
    if match:
        return match.group(1)
    return None


def _is_repo_dirty(repo_path: str) -> bool:
    """Check if repository has uncommitted changes."""
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        return bool(result.stdout.strip())
    except (subprocess.TimeoutExpired, OSError):
        return False


def _get_last_commit_timestamp(repo_path: str, branch: str) -> int:
    """Get Unix timestamp of last commit on a branch.

    Feature 111 T067: Used for staleness detection.

    Args:
        repo_path: Path to git repository
        branch: Branch name

    Returns:
        Unix timestamp of last commit, or 0 if unavailable
    """
    try:
        result = subprocess.run(
            ["git", "log", "-1", "--format=%ct", branch],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return int(result.stdout.strip())
    except (subprocess.TimeoutExpired, OSError, ValueError):
        pass
    return 0


def _get_current_branch(repo_path: str) -> Optional[str]:
    """Get current checked out branch."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        pass
    return None


def _is_branch_merged(repo_path: str, branch: str, into_branch: str) -> bool:
    """Check if a branch has been fully merged into another branch.

    Feature 111 T059: Detect merged branches for visual indicators.

    Args:
        repo_path: Path to git repository
        branch: Branch to check
        into_branch: Target branch to check against

    Returns:
        True if branch is fully merged into target
    """
    try:
        # Branch is merged if merge-base equals branch tip
        result = subprocess.run(
            ["git", "merge-base", "--is-ancestor", branch, into_branch],
            cwd=repo_path,
            capture_output=True,
            timeout=5,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def build_worktree_map(repo_path: str) -> Optional[WorktreeMap]:
    """Build complete WorktreeMap from repository data.

    Discovers worktrees, computes branch relationships, and creates
    a positioned map ready for SVG rendering.

    Args:
        repo_path: Path to git repository

    Returns:
        WorktreeMap with nodes, edges, and positions, or None if invalid repo
    """
    # Validate repo path
    if not Path(repo_path).exists():
        return None

    # Get all branches
    branches = _get_all_branches(repo_path)
    if not branches:
        return None

    # Detect main branch
    main_branch = _detect_main_branch(repo_path, branches)

    # Get worktrees for path info
    worktrees = _get_worktrees(repo_path)
    worktree_paths = {wt.get("branch", ""): wt.get("path", "") for wt in worktrees}

    # Get current branch for active state
    current_branch = _get_current_branch(repo_path)

    # Check if dirty (applies to current worktree)
    is_dirty = _is_repo_dirty(repo_path)

    # Build nodes
    nodes = []
    for branch in branches:
        # Feature 111 T059: Detect merged status
        is_merged = False
        if branch != main_branch:
            is_merged = _is_branch_merged(repo_path, branch, main_branch)

        # Feature 111 T067: Detect staleness based on last commit age
        last_commit_ts = _get_last_commit_timestamp(repo_path, branch)
        activity = calculate_activity_level(last_commit_ts)
        is_stale = activity["is_stale"]

        # Determine node status: MERGED > STALE > ACTIVE
        if is_merged:
            status = NodeStatus.MERGED
        elif is_stale:
            status = NodeStatus.STALE
        else:
            status = NodeStatus.ACTIVE

        node = WorktreeNode(
            branch=branch,
            branch_number=_extract_branch_number(branch),
            branch_description=parse_branch_description(branch),  # Feature 111 US2: Human-readable
            qualified_name=f"{Path(repo_path).name}:{branch}",
            node_type=detect_branch_type(branch),  # Feature 111 US2: Use public function
            status=status,  # Feature 111 T059/T067
            is_active=branch == current_branch,
            is_dirty=is_dirty if branch == current_branch else False,
        )
        nodes.append(node)

    # Build edges with parent-child relationships
    edges = []
    for node in nodes:
        if node.branch == main_branch:
            continue

        # Find likely parent (most likely main for feature branches)
        parent = find_likely_parent_branch(
            repo_path, node.branch, [main_branch] + branches
        )
        if parent and parent != node.branch:
            node.parent_branch = parent

            # Get relationship details
            rel = get_branch_relationship(repo_path, node.branch, parent)
            ahead = rel.get("ahead", 0) if rel else 0
            behind = rel.get("behind", 0) if rel else 0

            # Feature 111 T059: Use MERGED edge type for merged branches
            edge_type = EdgeType.MERGED if node.status == NodeStatus.MERGED else EdgeType.PARENT_CHILD

            edge = RelationshipEdge(
                source_branch=parent,
                target_branch=node.branch,
                edge_type=edge_type,
                ahead_count=ahead,
                behind_count=behind,
            )
            edges.append(edge)

            # Update node with ahead/behind
            node.ahead_of_parent = ahead
            node.behind_parent = behind

    # Create map
    map_data = WorktreeMap(
        repository=Path(repo_path).name,
        nodes=nodes,
        edges=edges,
        main_branch=main_branch,
        computed_at=int(time.time()),
    )

    # Compute layout
    map_data = compute_hierarchical_layout(map_data)

    return map_data


# =============================================================================
# Click Overlay Data (T046-T047 - User Story 3: Interactive Navigation)
# =============================================================================


def generate_click_overlay_data(map_data: WorktreeMap) -> List[Dict[str, Any]]:
    """Generate click overlay data for Eww interactive map.

    Converts WorktreeMap nodes into a list of dictionaries suitable for
    Eww overlay widgets, enabling click-to-switch functionality.

    Args:
        map_data: WorktreeMap with positioned nodes

    Returns:
        List of dicts with: x, y, radius, qualified_name, tooltip, label,
        type, is_active, is_dirty, branch
    """
    if not map_data.nodes:
        return []

    result = []
    for node in map_data.nodes:
        # Build tooltip with branch info and sync status
        tooltip_parts = [node.branch]
        if node.ahead_of_parent or node.behind_parent:
            sync = []
            if node.ahead_of_parent:
                sync.append(f"↑{node.ahead_of_parent}")
            if node.behind_parent:
                sync.append(f"↓{node.behind_parent}")
            tooltip_parts.append(" ".join(sync))
        tooltip = " | ".join(tooltip_parts) if len(tooltip_parts) > 1 else tooltip_parts[0]

        # Label: prefer branch number, fall back to abbreviated name
        label = node.branch_number if node.branch_number else node.branch[:8]

        overlay_data = {
            "x": node.x,
            "y": node.y,
            "radius": DEFAULT_NODE_RADIUS,
            "qualified_name": node.qualified_name,
            "tooltip": tooltip,
            "label": label,
            "type": node.node_type.value,
            "is_active": node.is_active,
            "is_dirty": node.is_dirty,
            "branch": node.branch,
        }
        result.append(overlay_data)

    return result


# =============================================================================
# Activity Level (T065-T070 - User Story 5: Activity Heatmap)
# =============================================================================

# Constants for activity level calculation
STALE_THRESHOLD_DAYS = 30
SECONDS_PER_DAY = 86400
MIN_OPACITY = 0.5
MAX_OPACITY = 1.0


def calculate_activity_level(last_commit_timestamp: int) -> dict:
    """Calculate activity level and opacity based on last commit age.

    Feature 111 T066: Returns opacity between 0.5 and 1.0 where:
    - 1.0 = very recent activity (today)
    - 0.5 = stale branch (30+ days without commits)

    Uses linear interpolation between MIN_OPACITY and MAX_OPACITY
    over the STALE_THRESHOLD_DAYS period.

    Args:
        last_commit_timestamp: Unix timestamp of last commit

    Returns:
        Dict with:
        - opacity: Float 0.5-1.0 for visual rendering
        - is_stale: True if 30+ days without commits
        - days_since_commit: Number of days since last commit
    """
    now = int(time.time())

    # Handle edge cases
    if last_commit_timestamp <= 0:
        return {
            "opacity": MIN_OPACITY,
            "is_stale": True,
            "days_since_commit": 999,  # Very old
        }

    if last_commit_timestamp > now:
        # Future timestamp - treat as fresh
        return {
            "opacity": MAX_OPACITY,
            "is_stale": False,
            "days_since_commit": 0,
        }

    # Calculate days since last commit
    seconds_since = now - last_commit_timestamp
    days_since = seconds_since / SECONDS_PER_DAY

    # Check staleness
    is_stale = days_since >= STALE_THRESHOLD_DAYS

    # Calculate opacity with linear interpolation
    if days_since >= STALE_THRESHOLD_DAYS:
        opacity = MIN_OPACITY
    else:
        # Linear: 1.0 at 0 days, 0.5 at 30 days
        fade_amount = (days_since / STALE_THRESHOLD_DAYS) * (MAX_OPACITY - MIN_OPACITY)
        opacity = MAX_OPACITY - fade_amount

    return {
        "opacity": opacity,
        "is_stale": is_stale,
        "days_since_commit": int(days_since),
    }
