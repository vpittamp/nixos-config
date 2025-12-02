# Research: Enhanced Worktree Card Status Display

**Feature**: 108-show-worktree-card-detail
**Date**: 2025-12-01

## Research Tasks

### 1. Git Commands for New Status Fields

#### 1.1 Merge Status Detection

**Decision**: Use `git branch --merged main` to check if branch is merged

**Rationale**:
- Standard git command for merge detection
- Returns list of branches that have been fully merged into specified branch
- Works correctly with squash merges if merge commit is present
- Fast execution (<10ms per branch)

**Implementation**:
```bash
# Check if current branch is merged into main
git branch --merged main | grep -q "^\s*$(git branch --show-current)\s*$"
# Exit code 0 = merged, 1 = not merged
```

**Alternative considered**: `git log main..HEAD --oneline | wc -l`
- Rejected because: Only detects if commits are ahead, doesn't handle squash merges

#### 1.2 Stale Worktree Detection

**Decision**: Use last commit timestamp from `git log -1 --format=%ct`

**Rationale**:
- Returns Unix epoch timestamp of last commit in the worktree
- Can compare against current time to calculate staleness
- Threshold: 30 days (2,592,000 seconds) as default

**Implementation**:
```bash
# Get last commit timestamp (Unix epoch)
git log -1 --format=%ct
# Returns: 1732924800 (example)

# Calculate days since last commit (in Python)
import time
last_commit = 1732924800
days_ago = (time.time() - last_commit) / 86400
is_stale = days_ago > 30
```

**Alternative considered**: File modification time (mtime)
- Rejected because: Doesn't reflect actual git activity, could be misleading

#### 1.3 Detailed Status Breakdown

**Decision**: Parse `git status --porcelain` output for categorized counts

**Rationale**:
- Already used in existing git_utils.py
- Provides machine-parseable status line by line
- Can categorize: staged (M ), modified ( M), untracked (??)

**Implementation**:
```bash
git status --porcelain
# Output format:
# XY PATH
# X = staged status, Y = working tree status
# M  = staged
#  M = modified (not staged)
# ?? = untracked
# A  = added
# D  = deleted
```

**Counts to extract**:
- staged_count: Lines starting with [MADRC] (not space)
- modified_count: Lines with [MD] in second position
- untracked_count: Lines starting with ??

#### 1.4 Conflict Detection

**Decision**: Check for 'U' status in git status --porcelain

**Rationale**:
- 'U' indicates unmerged paths (conflicts)
- Critical to surface prominently (red warning indicator)

**Implementation**:
```bash
git status --porcelain | grep "^UU\|^AA\|^DD"
# UU = both modified (conflict)
# AA = both added
# DD = both deleted
```

#### 1.5 Last Commit Message Preview

**Decision**: Use `git log -1 --format=%s` for subject line

**Rationale**:
- Subject line (first line) is concise for tooltip
- Combined with relative time for full context

**Implementation**:
```bash
git log -1 --format="%s"
# Returns: "Fix authentication bug"
```

### 2. Existing Infrastructure Analysis

#### 2.1 Current git_utils.py Capabilities

**Existing function**: `get_git_metadata(directory: str) -> Optional[dict]`

Returns:
- `current_branch`: Branch name
- `commit_hash`: Short hash (7 chars)
- `is_clean`: Boolean (no uncommitted changes)
- `has_untracked`: Boolean
- `ahead_count`: Commits ahead of upstream
- `behind_count`: Commits behind upstream
- `remote_url`: Origin remote URL

**Enhancement needed**: Add new fields to this function:
- `is_merged`: Boolean (merged into main)
- `is_stale`: Boolean (no commits in 30+ days)
- `last_commit_timestamp`: Unix epoch
- `last_commit_message`: Subject line
- `staged_count`: Number of staged changes
- `modified_count`: Number of modified files
- `untracked_count`: Number of untracked files
- `has_conflicts`: Boolean

#### 2.2 Current monitoring_data.py Worktree Data

**Existing fields in worktree objects** (lines 1635-1647):
```python
wt["git_is_dirty"] = not wt.get("is_clean", True)
wt["git_dirty_indicator"] = "●" if wt["git_is_dirty"] else ""
wt["git_ahead"] = wt.get("ahead", 0)
wt["git_behind"] = wt.get("behind", 0)
wt["git_sync_indicator"] = " ".join(sync_parts)  # "↑5 ↓2"
```

**Enhancement needed**: Add computed fields for UI:
- `git_is_merged`: Boolean
- `git_merged_indicator`: "✓ merged" or ""
- `git_is_stale`: Boolean
- `git_stale_indicator`: "💤" or ""
- `git_last_commit_relative`: "2h ago", "3 days ago"
- `git_last_commit_message`: Subject line (truncated to 50 chars)
- `git_status_tooltip`: Multi-line status breakdown
- `git_has_conflicts`: Boolean
- `git_conflict_indicator`: "⚠" or ""

#### 2.3 Current Eww Widget Structure

**discovered-worktree-card widget** (lines 4189-4270):

Current indicators shown:
- `worktree-branch`: Branch name
- `worktree-commit`: Short commit hash
- `git-dirty`: Red dot for dirty state
- `git-sync`: "↑5 ↓2" for ahead/behind

**Enhancement needed**: Add new indicator labels to the status row:
- `git-merged-badge`: Green "✓ merged" badge
- `git-stale-indicator`: Faded/gray "💤" icon
- `git-conflict-indicator`: Red "⚠" warning

### 3. Catppuccin Mocha Color Assignments

**Decision**: Use existing theme colors from eww-monitoring-panel.nix

| Status | Color Variable | Hex Value | Visual |
|--------|----------------|-----------|--------|
| Dirty | `red` | #f38ba8 | Red dot (●) |
| Clean | (none) | - | No indicator |
| Ahead | `green` | #a6e3a1 | Green ↑N |
| Behind | `peach` | #fab387 | Orange ↓N |
| Merged | `teal` | #94e2d5 | Teal badge |
| Stale | `overlay0` | #6c7086 | Gray/faded |
| Conflicts | `red` | #f38ba8 | Red ⚠ |

**Rationale**: Consistent with existing monitoring panel styling, uses semantic colors already defined

### 4. Performance Considerations

**Decision**: Batch git commands per worktree, cache aggressively

**Rationale**:
- Each worktree requires ~5 git commands for full status
- At 20 worktrees = 100 subprocess calls
- Target: <50ms per worktree = 1 second total

**Implementation strategy**:
1. Run git commands in parallel per worktree (asyncio.gather)
2. Cache git metadata with 5-second TTL (avoid repeated queries during rapid refreshes)
3. Merge status check is expensive - run only on panel open, not on every poll

**Alternative considered**: Single git command with all data
- Rejected because: No single git command provides all needed fields

### 5. Tooltip Content Format

**Decision**: Multi-line markdown-style tooltip

**Rationale**:
- Eww tooltips support multi-line text
- Provides details without cluttering the card

**Format**:
```
Branch: 099-feature-name
Commit: abc1234 (2h ago)
Status: 3 modified, 1 untracked
Sync: 5 commits to push, 2 to pull
Merged: ✓ merged into main
```

## Summary of Decisions

| Topic | Decision |
|-------|----------|
| Merge detection | `git branch --merged main` |
| Staleness threshold | 30 days since last commit |
| Status breakdown | Parse `git status --porcelain` |
| Conflict detection | Check for 'U' status codes |
| Commit preview | `git log -1 --format=%s` (subject) |
| Color scheme | Catppuccin Mocha (existing) |
| Performance | Parallel execution, 5s TTL cache |
| Tooltip format | Multi-line with status breakdown |
