# Research: Enhanced Git Worktree Status Indicators

**Feature**: 120-improve-git-changes
**Date**: 2025-12-16

## Research Tasks Completed

### 1. Git Diff Statistics Extraction

**Question**: How to efficiently extract line addition/deletion counts for uncommitted changes?

**Decision**: Use `git diff --numstat` for uncommitted changes and `git diff --numstat --cached` for staged changes.

**Rationale**:
- `--numstat` provides machine-readable output: `additions<TAB>deletions<TAB>filename`
- Single command per worktree (fast, avoids multiple subprocess calls)
- Can be combined: `git diff --numstat HEAD` shows all changes vs HEAD
- Handles binary files gracefully (shows `-` for additions/deletions)

**Alternatives Considered**:
- `git diff --shortstat`: Returns human-readable summary but harder to parse
- `git status --porcelain` with per-file diff: Too slow for many files
- libgit2 bindings: Adds dependency, overkill for this use case

**Implementation**:
```python
def get_diff_stats(worktree_path: str, timeout: float = 2.0) -> tuple[int, int]:
    """Returns (additions, deletions) for all uncommitted changes."""
    result = subprocess.run(
        ["git", "-C", worktree_path, "diff", "--numstat", "HEAD"],
        capture_output=True, text=True, timeout=timeout
    )
    additions = deletions = 0
    for line in result.stdout.strip().split('\n'):
        if line and not line.startswith('-'):  # Skip binary files
            parts = line.split('\t')
            if len(parts) >= 2:
                try:
                    additions += int(parts[0])
                    deletions += int(parts[1])
                except ValueError:
                    pass  # Binary file marker
    return additions, deletions
```

---

### 2. Visual Diff Bar Rendering in Eww

**Question**: How to render a GitHub-style proportional bar in eww/GTK?

**Decision**: Use nested box widgets with dynamic width calculation via CSS flex.

**Rationale**:
- Eww supports GTK CSS flexbox model
- Can calculate proportional widths in yuck expressions
- Consistent with existing eww styling patterns in the codebase

**Implementation Pattern**:
```yuck
;; Diff bar widget - shows proportional green/red bars
(defwidget diff-bar [additions deletions max-width]
  (box :class "diff-bar-container"
       :width max-width
       :visible {(additions + deletions) > 0}
    (box :class "diff-bar-additions"
         :width {additions > 0 ?
                 (max-width * additions / (additions + deletions + 0.001)) : 0})
    (box :class "diff-bar-deletions"
         :width {deletions > 0 ?
                 (max-width * deletions / (additions + deletions + 0.001)) : 0})))
```

**CSS**:
```scss
.diff-bar-container {
  height: 4px;
  border-radius: 2px;
  background: transparent;
  margin-left: 4px;
}
.diff-bar-additions {
  background: #a6e3a1;  // Catppuccin green
  border-radius: 2px 0 0 2px;
}
.diff-bar-deletions {
  background: #f38ba8;  // Catppuccin red
  border-radius: 0 2px 2px 0;
}
```

---

### 3. Status Indicator Priority Ordering

**Question**: How to display multiple status indicators in priority order?

**Decision**: Display all applicable indicators in a single row, ordered left-to-right by priority:
1. Conflicts (⚠) - highest priority, red
2. Dirty (●) - red with file breakdown tooltip
3. Sync (↑N ↓M) - green/yellow
4. Stale (💤) - gray
5. Merged (✓) - teal, lowest priority

**Rationale**:
- User requested "show all applicable states"
- Left-to-right reading order matches urgency (conflicts need immediate attention)
- Consistent with existing indicator placement in codebase

**Implementation**: Each indicator has `:visible` guard, all rendered in order:
```yuck
(box :class "status-indicators"
  ;; Priority 1: Conflicts
  (label :visible {worktree.git_has_conflicts} :class "git-conflict" :text "⚠")
  ;; Priority 2: Dirty
  (label :visible {worktree.git_is_dirty} :class "git-dirty" :text "●")
  ;; Priority 3: Sync
  (label :visible {(worktree.git_ahead ?: 0) > 0} :class "git-sync-ahead"
         :text {"↑" + worktree.git_ahead})
  (label :visible {(worktree.git_behind ?: 0) > 0} :class "git-sync-behind"
         :text {"↓" + worktree.git_behind})
  ;; Priority 4: Stale
  (label :visible {worktree.git_is_stale} :class "badge-stale" :text "💤")
  ;; Priority 5: Merged
  (label :visible {worktree.git_is_merged} :class "badge-merged" :text "✓"))
```

---

### 4. Windows View Project Header Enhancement

**Question**: How to add git status to project headers in windows view?

**Decision**: Extract git status from first associated worktree and display inline in project header.

**Rationale**:
- Project headers currently show only project name and window count
- Worktree projects have git metadata available via `project.worktrees[0]`
- Keeps header compact - only show key indicators (dirty, sync, merged)

**Implementation**:
```yuck
(defwidget project-header [project]
  (box :class "project-header"
    (label :class "project-name" :text {project.name})
    ;; Git status (only for worktree projects)
    (box :class "project-git-status"
         :visible {(project.worktrees ?: []) != []}
      (label :visible {project.worktrees[0].git_is_dirty ?: false}
             :class "git-dirty-small" :text "●")
      (label :visible {(project.worktrees[0].git_ahead ?: 0) > 0}
             :class "git-sync-small"
             :text {"↑" + (project.worktrees[0].git_ahead ?: 0)})
      (label :visible {(project.worktrees[0].git_behind ?: 0) > 0}
             :class "git-sync-small"
             :text {"↓" + (project.worktrees[0].git_behind ?: 0)})
      (label :visible {project.worktrees[0].git_is_merged ?: false}
             :class "badge-merged-small" :text "✓"))
    (label :class "window-count" :text {project.window_count})))
```

---

### 5. Git Command Timeout Strategy

**Question**: How to handle git command timeouts without blocking UI?

**Decision**: 2-second timeout per git command, display "?" status on failure.

**Rationale**:
- 2 seconds is enough for typical operations even on large repos
- Prevents UI freeze on network-mounted repos or git lock contention
- "?" indicator clearly communicates unknown state

**Implementation**:
```python
def get_git_status_safe(worktree_path: str) -> dict:
    """Get git status with timeout handling."""
    try:
        # All git operations with 2s timeout
        status = get_git_metadata(worktree_path, timeout=2.0)
        diff_stats = get_diff_stats(worktree_path, timeout=2.0)
        return {
            **status,
            "git_additions": diff_stats[0],
            "git_deletions": diff_stats[1],
            "git_status_error": False
        }
    except subprocess.TimeoutExpired:
        return {
            "git_status_error": True,
            "git_error_indicator": "?",
            "git_error_tooltip": "Git status timed out"
        }
    except Exception as e:
        return {
            "git_status_error": True,
            "git_error_indicator": "?",
            "git_error_tooltip": f"Git error: {str(e)}"
        }
```

---

### 6. Polling vs Event-Driven Updates

**Question**: Should git status use polling or event-driven updates?

**Decision**: 10-second polling interval (as specified in clarifications).

**Rationale**:
- File system events (inotify) on .git directories can be noisy (thousands of events during operations)
- 10-second polling balances freshness with CPU/IO cost
- Consistent with existing monitoring panel polling strategy
- Event-driven would require complex debouncing logic

**Implementation**: Existing `defpoll` mechanism in eww:
```yuck
(defpoll monitoring_data :interval "10s"
  :run-while panel_visible
  `python3 -m i3_project_manager.cli.monitoring_data`)
```

---

### 7. Large Repository Performance

**Question**: How to handle repositories with thousands of changed files?

**Decision**: Cap line counts at 9999, cap file counts at 999 with "+" indicator.

**Rationale**:
- Prevents UI overflow
- "+9999" clearly indicates "many" without exact count
- Keeps widget width predictable

**Implementation**:
```python
def format_count(count: int, max_display: int = 9999) -> str:
    """Format count with cap for display."""
    if count > max_display:
        return f"+{max_display}"
    return str(count)
```

---

## Best Practices Applied

### Eww Widget Development

1. **Use ternary guards for visibility**: `(label :visible {condition} ...)`
2. **Default to empty/false for optional fields**: `{field ?: default}`
3. **Keep tooltips informative**: Include actionable context
4. **Use consistent color semantics**: Red=error/dirty, Green=success/ahead, Yellow=warning/behind, Teal=info/merged

### Python Git Integration

1. **Always use timeout**: Prevents blocking on slow operations
2. **Use `-C` flag**: Avoids changing working directory
3. **Parse porcelain output**: Machine-readable, stable across versions
4. **Handle binary files**: Check for `-` in numstat output

### CSS/SCSS in Eww

1. **Use Catppuccin Mocha palette**: Consistent with existing styling
2. **Small indicators**: 10-11px font for inline badges
3. **Spacing**: 4px margins between indicators
4. **Border radius**: 2px for small elements, 4px for containers

---

## Dependencies Confirmed

| Dependency | Version | Status | Notes |
|------------|---------|--------|-------|
| Python | 3.11+ | ✅ Available | Per constitution |
| eww | 0.4+ | ✅ Available | Already installed |
| git | 2.x | ✅ Available | System package |
| Pydantic | 2.x | ✅ Available | Already in use |

## Risks Identified

| Risk | Impact | Mitigation |
|------|--------|------------|
| Git lock contention | Medium | 2-second timeout, graceful degradation |
| Large diff stats | Low | Cap at 9999, visual bar normalizes |
| UI clutter with many indicators | Medium | Compact layout, tooltip for details |
| Slow polling on many worktrees | Low | Parallel processing, <50ms per worktree target |
