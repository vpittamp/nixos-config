# Research: Enhanced Project Selection in Eww Preview Dialog

**Branch**: `078-eww-preview-improvement` | **Date**: 2025-11-16

## Executive Summary

This research consolidates technical decisions for enhancing the Eww preview dialog's project selection mode. Key decisions include: priority-based fuzzy matching algorithm (extends existing `_fuzzy_match_project`), Pydantic models for project metadata, index-based selection state for arrow navigation, and hierarchical Eww widget rendering for project list display.

---

## 1. Fuzzy Matching Algorithm

### Decision
Extend the existing priority-based matching algorithm in `workspace_mode.py:358` with word-boundary scoring and match highlighting.

### Rationale
The current `_fuzzy_match_project()` uses simple priority matching (exact > prefix > substring). This needs enhancement to:
- Support multi-word matching (e.g., "age-fra" matches "agent-framework")
- Handle digit-prefixed names (e.g., "078" matches "078-eww-preview-improvement")
- Return all matches with scores for list display (not just best match)
- Provide match positions for UI highlighting

### Algorithm Design

```python
def fuzzy_match_projects(query: str, projects: List[ProjectMetadata]) -> List[ScoredMatch]:
    """
    Priority scoring (higher is better):
    1. Exact match: 1000 points
    2. Prefix match: 500 points + (len(query) / len(name)) * 100
    3. Word-boundary match: 300 points + consecutive word bonus
    4. Substring match: 100 points + position penalty
    5. No match: 0 points (excluded from results)
    """
```

### Alternatives Considered

1. **fzf/fzy algorithms**: More sophisticated but adds complexity. Current use case (100 projects max) doesn't require O(n log n) optimizations.

2. **Levenshtein distance**: Good for typo tolerance but doesn't respect word boundaries. "nix" would match "unix" better than "nixos" due to edit distance.

3. **TF-IDF scoring**: Overkill for short project names. Designed for document search, not small string matching.

**Selected**: Priority-based with word-boundary awareness - balances accuracy and simplicity.

---

## 2. Project Metadata Enrichment

### Decision
Load complete project metadata from JSON files at startup, refresh on file change, enrich with live git status on demand.

### Rationale
Current project files already contain:
- `name`, `display_name`, `directory`, `icon`
- Optional `worktree` object with `branch`, `commit_hash`, `is_clean`, `ahead_count`, `behind_count`, `repository_path`

Additional enrichment needed:
- Root vs worktree classification (check if `worktree` field exists)
- Parent project resolution (map `repository_path` to another project)
- Missing directory detection (`os.path.exists(directory)`)
- Relative time formatting (human-readable "2h ago", "3 days ago")

### Data Loading Strategy

```python
class ProjectService:
    def __init__(self):
        self._project_cache: Dict[str, ProjectMetadata] = {}
        self._last_modified: Dict[str, float] = {}

    async def load_all_projects(self) -> List[ProjectMetadata]:
        """Load from ~/.config/i3/projects/*.json"""
        project_dir = Path.home() / ".config" / "i3" / "projects"
        projects = []
        for json_file in project_dir.glob("*.json"):
            if self._needs_reload(json_file):
                project = await self._load_project_file(json_file)
                projects.append(project)
        return sorted(projects, key=lambda p: p.last_modified, reverse=True)
```

### Alternatives Considered

1. **Query git status live on each render**: Too slow (100-500ms per project). Would violate 50ms filter response time constraint.

2. **Store all metadata in daemon memory**: Current approach - keeps data fresh via file watching.

3. **Use SQLite for project database**: Adds complexity. JSON files already work, used by i3pm CLI.

**Selected**: JSON file cache with file-watching refresh - maintains compatibility with existing i3pm tools.

---

## 3. Selection State Management

### Decision
Extend existing `SelectionManager` pattern with index-based project list navigation.

### Rationale
The workspace-preview-daemon already uses `SelectionManager` for window navigation (Feature 073). This pattern supports:
- Circular navigation (wrap at boundaries)
- Multiple selection modes (workspace_heading vs window)
- State serialization for Eww variable updates

For project list:
- Simpler than window navigation (flat list, no hierarchy)
- Index-based selection with highlight tracking
- Manual navigation (arrows) takes precedence over filter-based selection

### Implementation Pattern

```python
class ProjectSelectionManager:
    def __init__(self):
        self._projects: List[ProjectListItem] = []
        self._selected_index: int = 0
        self._user_navigated: bool = False  # Track if user used arrows

    def update_projects(self, projects: List[ProjectListItem]):
        """Update project list from filter results."""
        self._projects = projects
        if not self._user_navigated:
            self._selected_index = 0  # Auto-select best match
        else:
            self._clamp_selection()  # Keep within bounds

    def navigate_down(self) -> ProjectListItem:
        """Move selection down with wrap-around."""
        self._user_navigated = True
        self._selected_index = (self._selected_index + 1) % len(self._projects)
        return self._projects[self._selected_index]

    def get_selected_project(self) -> Optional[ProjectListItem]:
        """Get currently selected project (None if empty list)."""
        if not self._projects:
            return None
        return self._projects[self._selected_index]
```

### Alternatives Considered

1. **Name-based selection**: Store selected project name instead of index. Problem: When filtering changes the list, maintaining selection by name requires search.

2. **No selection state**: Always execute on best match. Problem: User can't browse alternatives.

3. **Cursor position in filter string**: Track character position. Problem: Conflates text editing with list navigation.

**Selected**: Index-based with user-navigation tracking - simple, efficient, matches existing patterns.

---

## 4. IPC Event Protocol

### Decision
Extend `project_mode` events to include full project list with match scores and selection state.

### Rationale
Current `project_mode` events (workspace_mode.py:962) emit:
```json
{
  "type": "project_mode",
  "payload": {
    "event_type": "char|execute|cancel",
    "accumulated_chars": "nix",
    "matched_project": "nixos",
    "project_icon": "❄️"
  }
}
```

Enhanced events need:
```json
{
  "type": "project_mode",
  "payload": {
    "event_type": "char|nav|execute|cancel",
    "accumulated_chars": "nix",
    "selected_index": 0,
    "projects": [
      {
        "name": "nixos",
        "display_name": "NixOS",
        "icon": "❄️",
        "is_worktree": false,
        "parent_project": null,
        "git_status": null,
        "last_modified": "2025-11-16T12:03:00Z",
        "match_score": 500,
        "match_positions": [0, 1, 2],
        "directory_exists": true
      }
    ]
  }
}
```

### Event Flow

1. **User types ":"** → `enter` event with all projects (sorted by recency)
2. **User types "n"** → `char` event with filtered projects (sorted by match score)
3. **User presses Down** → `nav` event with updated selected_index
4. **User presses Enter** → `execute` event (daemon performs switch)
5. **User presses Escape** → `cancel` event (closes dialog without action)

### Alternatives Considered

1. **Render projects in workspace-preview-daemon**: Daemon would query projects directly. Problem: Violates separation of concerns - daemon is rendering layer, not data layer.

2. **Stream projects one at a time**: Send individual project updates. Problem: Adds complexity for small data set (100 projects < 10KB JSON).

3. **Use separate IPC channel for project data**: Maintain state in parallel. Problem: Synchronization complexity.

**Selected**: Full project list in event payload - simple, atomic, consistent with existing patterns.

---

## 5. Eww Widget Rendering

### Decision
Add project list widget type to existing `workspace-preview-card` with scrollable container and item template.

### Rationale
Current eww-workspace-bar.nix:186 already has:
```yuck
(box :class "project-preview"
     :visible {workspace_preview_data.type == "project"}
  ;; Current: single match display
)
```

Enhancement needs:
- Scrollable container for 50+ projects
- Item template with icon, name, badges, metadata
- Selection highlight (current selected_index)
- Empty state ("No matching projects")

### Widget Structure

```yuck
(box :class "project-preview"
     :visible {workspace_preview_data.type == "project_list"}
  (box :class "preview-header"
    (label :text ":${workspace_preview_data.accumulated_chars}"))

  (scroll :vscroll true :height 400
    (box :orientation "v" :spacing 4
      (for project in workspace_preview_data.projects
        (box :class "project-item ${project.selected ? 'selected' : ''}"
          (label :class "project-icon" :text project.icon)
          (box :orientation "v"
            (label :class "project-name" :text project.display_name)
            (box :class "project-badges"
              (label :visible project.is_worktree :text "🌿 worktree")
              (label :visible {project.parent_project != null}
                     :text "← ${project.parent_project}")
              (label :visible {!project.directory_exists} :text "⚠️ missing"))))))))
```

### Alternatives Considered

1. **Use GTK ListBox for native scrolling**: Requires Eww primitives. Current scroll widget suffices.

2. **Lazy load project items**: Only render visible items. Overkill for 100 items.

3. **Separate Eww window for project picker**: Break out of workspace preview. Problem: Inconsistent UX, additional window management.

**Selected**: Inline scroll container with item template - consistent with existing preview patterns.

---

## 6. Git Status Indicators

### Decision
Show commit status (clean/dirty) and sync status (ahead/behind) using emoji badges for immediate visual recognition.

### Rationale
Worktree metadata already includes:
- `is_clean`: Boolean for uncommitted changes
- `has_untracked`: Boolean for untracked files
- `ahead_count`: Integer for unpushed commits
- `behind_count`: Integer for unpulled commits

Visual indicators:
- ✓ Clean (green checkmark)
- ✗ Dirty (red X)
- ↑N Ahead by N commits
- ↓N Behind by N commits

### Badge Rendering

```yuck
(box :class "git-status-badges"
  (label :visible project.is_clean :class "clean" :text "✓")
  (label :visible {!project.is_clean} :class "dirty" :text "✗")
  (label :visible {project.ahead_count > 0}
         :text "↑${project.ahead_count}")
  (label :visible {project.behind_count > 0}
         :text "↓${project.behind_count}"))
```

### Alternatives Considered

1. **Traffic light colors only**: Less informative, accessibility concerns.

2. **Full status text ("2 ahead, 1 behind")**: Too verbose for list view.

3. **Hover tooltip for details**: Eww doesn't support hover tooltips well.

**Selected**: Emoji + number badges - compact, universal, colorblind-friendly.

---

## 7. Relative Time Formatting

### Decision
Use standard relative time library (humanize or custom) for "2h ago", "3 days ago" formatting.

### Rationale
Project metadata includes `last_modified` timestamp (ISO 8601). Users need quick understanding of project activity without parsing dates.

### Implementation

```python
def format_relative_time(timestamp: datetime) -> str:
    """Format timestamp as relative time string."""
    now = datetime.now(timezone.utc)
    delta = now - timestamp

    if delta.seconds < 60:
        return "just now"
    elif delta.seconds < 3600:
        minutes = delta.seconds // 60
        return f"{minutes}m ago"
    elif delta.seconds < 86400:
        hours = delta.seconds // 3600
        return f"{hours}h ago"
    elif delta.days < 30:
        return f"{delta.days}d ago"
    else:
        months = delta.days // 30
        return f"{months}mo ago"
```

### Alternatives Considered

1. **Absolute timestamps**: "2025-11-16 12:03" - hard to parse quickly.

2. **Full text**: "2 hours ago" - takes more space.

3. **Time-based badges only**: Drop exact times. Loses precision.

**Selected**: Abbreviated relative time (2h, 3d, 1mo) - compact and scannable.

---

## 8. Performance Considerations

### Decision
Pre-compute all project metadata on daemon startup, lazy-refresh on file change, cache filter results.

### Rationale
Performance requirements:
- <50ms filter response for 100 projects
- <16ms arrow navigation (single frame)
- <100ms IPC event propagation

Bottlenecks:
- JSON file loading: ~1-5ms per file
- Git status checking: ~100-500ms per repo (expensive!)
- Fuzzy matching: ~0.1ms per project
- JSON serialization: ~5ms for 100 projects

### Optimization Strategy

1. **Startup**: Load all project JSON files, cache in memory
2. **File change**: inotify watch on `~/.config/i3/projects/`, reload changed files
3. **Git status**: Use cached worktree metadata from JSON (already populated at project creation)
4. **Filtering**: Pre-sort projects by recency, filter in memory
5. **IPC**: Single atomic event with full project list (avoid multiple round-trips)

### Alternatives Considered

1. **Lazy loading**: Load projects on first access. Problem: First filter would be slow.

2. **Background worker**: Separate thread for file I/O. Adds complexity for minimal gain.

3. **Debounce filter events**: Wait 100ms after last keystroke. Reduces responsiveness.

**Selected**: Eager loading with file-watch refresh - predictable performance, simple architecture.

---

## Dependencies and External Requirements

### Python Packages (already available via home-manager)
- `pydantic`: Data validation (existing dependency)
- `watchdog` or `inotify`: File change detection (may need to add)
- Standard library: `datetime`, `pathlib`, `json`, `asyncio`

### Eww Primitives
- `scroll`: Scrollable container (native widget)
- `box`: Layout container (existing usage)
- `label`: Text display (existing usage)
- `for`: List iteration (existing usage)

### No New External Dependencies
- Fuzzy matching: Custom Python implementation
- Git status: Read from existing JSON metadata
- Relative time: Simple Python datetime math

---

## Risk Assessment

### Low Risk
- Fuzzy matching algorithm: Simple, well-understood, easy to test
- Eww widget extension: Incremental addition to existing template
- Selection state: Follows established pattern

### Medium Risk
- File watching for project changes: inotify edge cases, NFS mounts
- Performance with 100+ projects: May need pagination if list grows
- IPC payload size: 100 projects × 200 bytes = 20KB (within limits)

### Mitigation
- Add unit tests for all fuzzy matching edge cases
- Profile filtering with 100+ mock projects
- Monitor IPC latency in production environment
- Fallback to pagination if performance degrades
