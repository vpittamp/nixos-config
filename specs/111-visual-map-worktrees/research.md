# Research: Visual Worktree Relationship Map

**Feature**: 111-visual-map-worktrees
**Date**: 2025-12-02
**Status**: Complete

## Research Questions

1. How to render visual graphs in Eww (GTK3)?
2. How to detect git branch parent relationships?
3. How to optimize performance for many worktrees?
4. What layout algorithm to use for tree visualization?

---

## 1. Eww Graphics Capabilities

### Decision: Server-side SVG generation displayed via Eww `image` widget

### Rationale

Eww is a GTK3-based widget system that does **not** support native canvas drawing or custom SVG path manipulation. However, it can display pre-rendered SVG images via the `image` widget.

### Capabilities Confirmed

- **SVG Images**: `image` widget with `path`, `image-width`, `image-height`, `fill-svg` for color control
- **Graph Widget**: Built-in but limited to time-series data (not relationship graphs)
- **Transform Widget**: Can rotate, translate, scale content
- **Event Handling**: onclick, onhover, onhoverlost handlers on any widget
- **Overlays**: Box layering with absolute positioning

### Limitations (Hard Constraints)

- No native HTML5-style canvas element
- No SVG path manipulation in widget definitions
- No built-in tree layout algorithms
- Image paths must be absolute (no `~` or `$HOME`)

### Architecture Decision

```
Python Backend (monitoring_data.py)
        ↓
    Generate SVG (layout + render)
        ↓
Save to /tmp/worktree-map-<repo>-<hash>.svg
        ↓
Eww deflisten streams SVG path
        ↓
Eww image widget displays SVG
        ↓
User interacts (click/hover) → Eww handler → i3pm command
```

### Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Server-side SVG | Simple, fits architecture | Extra file I/O | **SELECTED** |
| Eww box composition | Native widgets | Complex for graphs, no lines | Rejected |
| External graph tool | Professional quality | New dependency, not integrated | Rejected |
| WebView embed | Full HTML/CSS/JS | Heavy, security concerns | Rejected |

---

## 2. Git Branch Parent Detection

### Decision: Merge-base distance heuristic with caching

### Rationale

Git does not explicitly track "branched from X" relationships. Detection requires comparing merge-bases between branches and selecting the closest ancestor.

### Implementation Approach

```python
def find_likely_parent_branch(repo_path, target_branch, candidates):
    """
    Determine parent branch using merge-base distance heuristic.
    Branch with smallest commit distance to merge-base = likely parent.
    """
    min_distance = float('inf')
    best_candidate = None

    for candidate in candidates:
        # Count commits from merge-base to target
        result = subprocess.run(
            ["git", "rev-list", "--count", f"{candidate}..{target_branch}"],
            cwd=repo_path, capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            distance = int(result.stdout.strip())
            if distance < min_distance:
                min_distance = distance
                best_candidate = candidate

    return best_candidate
```

### Key Git Commands

| Command | Purpose | Time |
|---------|---------|------|
| `git merge-base A B` | Find common ancestor | 50-100ms |
| `git rev-list --count A..B` | Commits in B not in A | 20-50ms |
| `git rev-list --left-right --count A...B` | Ahead/behind both directions | 30-60ms |
| `git branch --merged main` | Branches merged into main | 50-100ms |

### Divergence Detection

```bash
# Three-dot syntax compares both directions
git rev-list --left-right --count branch-a...branch-b
# Output: "<behind> <ahead>"
# Example: "3 5" = 3 behind, 5 ahead = DIVERGED
```

### Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Merge-base distance | Accurate, git-native | O(n²) complexity | **SELECTED** |
| Branch creation timestamp | O(n) complexity | Fails with rebase/force-push | Rejected |
| Explicit metadata | Zero git overhead | Manual maintenance | Rejected |
| Git reflog parsing | Direct creation info | Reflog may be truncated | Rejected |

---

## 3. Performance Optimization

### Decision: In-memory cache with 5-minute TTL + lazy computation

### Rationale

For 10 worktrees, merge-base approach requires 45 git calls (~4.5-7 seconds). Caching reduces this to near-zero for interactive use.

### Performance Targets

| Metric | Target | Strategy |
|--------|--------|----------|
| Initial map render | <2 seconds | Async computation |
| Subsequent renders | <100ms | Cache hit |
| Project switch | <500ms | Existing i3pm performance |
| SVG file write | <50ms | /tmp filesystem |

### Caching Strategy

```python
class WorktreeRelationshipCache:
    """In-memory cache with TTL for branch relationships."""

    def __init__(self, ttl_seconds=300):  # 5 minute TTL
        self._cache: Dict[str, WorktreeRelationship] = {}
        self._ttl = ttl_seconds

    def get(self, repo_path, branch_a, branch_b):
        key = f"{repo_path}:{branch_a}~{branch_b}"
        rel = self._cache.get(key)
        if rel and not rel.is_stale(self._ttl):
            return rel
        return None

    def invalidate_repo(self, repo_path):
        """Clear cache on git operations."""
        keys = [k for k in self._cache if k.startswith(repo_path)]
        for k in keys:
            del self._cache[k]
```

### Cache Invalidation Triggers

- Git commit/push/pull detected
- Worktree creation/deletion
- Manual refresh button
- TTL expiration (5 minutes)

### Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| In-memory + TTL | Simple, fast | Lost on restart | **SELECTED** |
| File-based cache | Persistent | I/O overhead | Rejected |
| No cache | Always accurate | 4-7s per render | Rejected |
| Database (SQLite) | Queryable | Over-engineered | Rejected |

---

## 4. Layout Algorithm

### Decision: Hierarchical layer-based layout (Sugiyama-inspired)

### Rationale

The map needs to show main branch at top/center with feature branches arranged by hierarchy depth. Hierarchical layout is standard for git visualizations (GitHub, GitKraken, gitk).

### Layout Algorithm

```python
def compute_hierarchical_layout(worktrees, main_branch="main"):
    """
    Compute x,y positions for worktree nodes using layer assignment.

    Layer 0: main branch
    Layer 1: Branches from main
    Layer 2: Branches from layer 1
    ...
    """
    # Step 1: Assign layers based on branch depth
    layers = defaultdict(list)
    layers[0].append(main_branch)

    for wt in worktrees:
        parent = find_parent_branch(wt.branch)
        parent_layer = get_layer(parent)
        layers[parent_layer + 1].append(wt.branch)

    # Step 2: Compute x positions within each layer
    positions = {}
    for layer_num, branches in layers.items():
        y = layer_num * 80  # 80px vertical spacing
        width = len(branches) * 100  # 100px horizontal spacing
        start_x = (canvas_width - width) / 2  # Center horizontally

        for i, branch in enumerate(branches):
            x = start_x + (i * 100) + 50  # Center of node
            positions[branch] = (x, y)

    return positions
```

### Visual Design

```
                    ┌────────┐
                    │  main  │  Layer 0 (root)
                    └────┬───┘
           ┌─────────────┼─────────────┐
           │             │             │
      ┌────┴───┐   ┌────┴───┐   ┌────┴───┐
      │ 108-*  │   │ 109-*  │   │ 110-*  │  Layer 1
      └────┬───┘   └────────┘   └────────┘
           │
      ┌────┴───┐
      │ 111-*  │  Layer 2 (branched from 108)
      └────────┘
```

### Node Rendering

| Element | Size | Color (Catppuccin Mocha) |
|---------|------|--------------------------|
| Main node | 60px circle | Mauve (#cba6f7) |
| Feature node | 50px circle | Blue (#89b4fa) |
| Merged node | 50px circle, dashed | Teal (#94e2d5) |
| Dirty indicator | 8px dot | Red (#f38ba8) |
| Stale node | 50% opacity | Gray (#6c7086) |

### Edge Rendering

| Relationship | Style | Label |
|--------------|-------|-------|
| Parent-child | Solid line | - |
| Ahead only | Arrow → | ↑N |
| Behind only | Arrow ← | ↓N |
| Diverged | Double arrow ↔ | ↑N ↓M |
| Merged | Dashed line | ✓ |

### Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Hierarchical (Sugiyama) | Standard, clear | Complex algorithm | **SELECTED** |
| Radial (center main) | Compact | Poor for deep trees | Rejected |
| Force-directed | Organic | Non-deterministic | Rejected |
| Linear timeline | Simplest | Doesn't show hierarchy | Rejected |

---

## 5. SVG Library Selection

### Decision: Direct string construction (no library dependency)

### Rationale

For simple tree graphs with 10-20 nodes, a full SVG library is overkill. Direct string construction is faster, has no dependencies, and produces identical output.

### Implementation

```python
def generate_worktree_map_svg(worktrees, width=400, height=600):
    """Generate SVG string for worktree relationship map."""

    svg_parts = [
        f'<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">',
        '<style>',
        '.main { fill: #cba6f7; stroke: #94e2d5; stroke-width: 2; }',
        '.feature { fill: #89b4fa; stroke: #74c7ec; stroke-width: 1; }',
        '.merged { fill: #94e2d5; stroke-dasharray: 4; }',
        '.stale { opacity: 0.5; }',
        '.edge { stroke: #45475a; stroke-width: 1; fill: none; }',
        '.label { fill: #cdd6f4; font-size: 12px; font-family: monospace; }',
        '.indicator { fill: #f38ba8; }',
        '</style>',
    ]

    positions = compute_hierarchical_layout(worktrees)

    # Draw edges first (behind nodes)
    for wt in worktrees:
        parent = find_parent_branch(wt.branch)
        if parent in positions:
            x1, y1 = positions[parent]
            x2, y2 = positions[wt.branch]
            svg_parts.append(f'<path d="M{x1} {y1+25} L{x2} {y2-25}" class="edge"/>')
            # Add ahead/behind label on edge
            mid_x, mid_y = (x1 + x2) / 2, (y1 + y2) / 2
            label = format_sync_label(wt.ahead, wt.behind)
            if label:
                svg_parts.append(f'<text x="{mid_x}" y="{mid_y}" class="label">{label}</text>')

    # Draw nodes
    for wt in worktrees:
        x, y = positions[wt.branch]
        node_class = get_node_class(wt)
        svg_parts.append(f'<circle cx="{x}" cy="{y}" r="25" class="{node_class}"/>')
        svg_parts.append(f'<text x="{x}" y="{y+4}" class="label" text-anchor="middle">{wt.branch_number or wt.branch[:8]}</text>')

        # Dirty indicator
        if wt.is_dirty:
            svg_parts.append(f'<circle cx="{x+20}" cy="{y-20}" r="4" class="indicator"/>')

    svg_parts.append('</svg>')
    return '\n'.join(svg_parts)
```

### Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Direct strings | Zero deps, fast | Manual escaping | **SELECTED** |
| drawsvg library | Clean API, active | New dependency | Alternative |
| svgwrite library | Mature | Unmaintained | Rejected |
| Graphviz DOT | Professional layout | System dependency | Rejected |

---

## 6. Eww Integration Pattern

### Decision: New tab in Projects view with toggle between list/map

### Rationale

Users should be able to choose their preferred view. The map is complementary to the existing list view, not a replacement.

### Widget Structure

```lisp
;; Projects tab content with view toggle
(defwidget projects-tab []
  (box :orientation "v" :space-evenly false
    ;; View toggle header
    (box :class "view-toggle" :halign "center"
      (button :class {projects_view_mode == "list" ? "active" : ""}
              :onclick "eww update projects_view_mode='list'"
              "List")
      (button :class {projects_view_mode == "map" ? "active" : ""}
              :onclick "eww update projects_view_mode='map'"
              "Map"))

    ;; Conditional content
    (box :visible {projects_view_mode == "list"}
      (projects-list-view))
    (box :visible {projects_view_mode == "map"}
      (projects-map-view))))

;; Map view widget
(defwidget projects-map-view []
  (box :class "worktree-map" :orientation "v"
    (image :path {worktree_map_svg_path}
           :image-width 400
           :image-height 600)
    (box :class "map-legend"
      (label :text "● Dirty  ↑ Ahead  ↓ Behind  ✓ Merged"))))
```

### Data Flow

```
deflisten monitoring_projects_data
        ↓
Parse JSON → Extract worktree relationships
        ↓
Generate SVG → Write to /tmp/worktree-map-<hash>.svg
        ↓
defpoll worktree_map_svg_path (reads path from monitoring data)
        ↓
Eww image widget displays SVG
```

### Click Handling

Since Eww's image widget doesn't support click coordinates, use an overlay approach:

```lisp
;; Overlay invisible click targets over SVG
(overlay
  (image :path {worktree_map_svg_path} ...)
  (box :class "click-layer"
    ;; Position buttons at computed node locations
    (for node in {worktree_nodes}
      (button :class "invisible-click"
              :style "position: absolute; left: ${node.x}px; top: ${node.y}px;"
              :onclick "i3pm project switch ${node.qualified_name}"
              :tooltip "${node.tooltip}"))))
```

---

## 7. Conflict Detection

### Decision: File path overlap heuristic (not content diff)

### Rationale

Content-level merge simulation is expensive (~1-5s per pair). File path overlap provides a fast approximation: if two branches modify the same files, they likely conflict.

### Implementation

```python
def detect_potential_conflicts(repo_path, branch_a, branch_b, base_branch="main"):
    """
    Detect potential merge conflicts between two branches.
    Returns list of overlapping file paths.
    """
    # Get files changed in branch_a vs main
    result_a = subprocess.run(
        ["git", "diff", "--name-only", f"{base_branch}...{branch_a}"],
        cwd=repo_path, capture_output=True, text=True, timeout=5
    )
    files_a = set(result_a.stdout.strip().split('\n')) if result_a.returncode == 0 else set()

    # Get files changed in branch_b vs main
    result_b = subprocess.run(
        ["git", "diff", "--name-only", f"{base_branch}...{branch_b}"],
        cwd=repo_path, capture_output=True, text=True, timeout=5
    )
    files_b = set(result_b.stdout.strip().split('\n')) if result_b.returncode == 0 else set()

    # Intersection = potential conflicts
    return files_a & files_b
```

### Visualization

When conflicts detected, draw a red dashed edge between the conflicting worktrees in the map.

---

## Summary

| Question | Decision | Key Rationale |
|----------|----------|---------------|
| Eww graphics | Server-side SVG + image widget | Eww can't draw, but can display images |
| Branch parents | Merge-base distance heuristic | Git-native, accurate |
| Performance | In-memory cache, 5-min TTL | 99% cache hits for interactive use |
| Layout | Hierarchical (Sugiyama-inspired) | Standard for git visualizations |
| SVG library | Direct string construction | Zero dependencies, sufficient for scope |
| Eww integration | New tab with list/map toggle | Complementary views |
| Conflict detection | File path overlap | Fast approximation |

---

## References

- [Eww Widget Documentation](https://elkowar.github.io/eww/widgets.html)
- [Git merge-base documentation](https://git-scm.com/docs/git-merge-base)
- [Sugiyama Framework (Wikipedia)](https://en.wikipedia.org/wiki/Layered_graph_drawing)
- [D3.js Hierarchy](https://github.com/d3/d3-hierarchy)
- Feature 108: Worktree card status display
- Feature 109: Enhanced worktree user experience
