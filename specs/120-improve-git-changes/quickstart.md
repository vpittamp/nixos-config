# Quickstart: Enhanced Git Worktree Status Indicators

**Feature**: 120-improve-git-changes
**Date**: 2025-12-16

## Overview

This feature enhances the eww monitoring panel to show comprehensive git status information for worktrees, including diff statistics, in both the Windows view project headers and Worktree cards.

## Key Components

### 1. Git Status Display

**Worktree Cards** show all status indicators in priority order:
- ⚠ Conflicts (red) - highest priority
- ● Dirty (red) - has uncommitted changes
- ↑N ↓M Sync (green/yellow) - commits ahead/behind
- 💤 Stale (gray) - no activity 30+ days
- ✓ Merged (teal) - branch merged into main

**Diff Bar** shows line additions (green) and deletions (red) as proportional bar:
```
██████░░░ +245 -67
```

**Project Headers** (Windows view) show compact git status:
```
project-name ● ↑2 ↓1 ✓  [3]
             │  │   │   └── window count
             │  │   └────── merged indicator
             │  └────────── sync status
             └───────────── dirty indicator
```

### 2. Files to Modify

| File | Changes |
|------|---------|
| `home-modules/tools/i3_project_manager/services/git_utils.py` | Add `get_diff_stats()` function |
| `home-modules/tools/i3_project_manager/cli/monitoring_data.py` | Add diff fields, header status |
| `home-modules/desktop/eww-monitoring-panel.nix` | Update widgets and CSS |

### 3. Testing

**Manual Testing**:
```bash
# Open monitoring panel
# Press Mod+M

# Make changes in a worktree
cd ~/projects/my-worktree
echo "test" >> test.txt

# Observe:
# - Dirty indicator appears (●)
# - Diff bar shows +1 -0
# - Tooltip shows file breakdown
```

**Unit Tests**:
```bash
# Run diff stats tests
pytest tests/120-improve-git-changes/unit/

# Run with verbose output
pytest -v tests/120-improve-git-changes/
```

### 4. Configuration

No new configuration required. Feature uses existing:
- **Polling interval**: 10 seconds (from clarifications)
- **Git timeout**: 2 seconds (from clarifications)
- **Color scheme**: Catppuccin Mocha (existing)

### 5. Troubleshooting

**Indicators not showing?**
1. Check git status manually: `git status`
2. Verify worktree is tracked: `i3pm worktree list`
3. Check panel logs: `journalctl --user -u eww-monitoring-panel`

**Diff bar empty?**
1. Ensure changes exist: `git diff --stat`
2. Check timeout: Large repos may timeout (2s limit)
3. "?" indicator means git command failed

**Performance issues?**
1. Check worktree count: `i3pm worktree list | wc -l`
2. Consider reducing polling: Edit `eww-monitoring-panel.nix`
3. Large repos: Diff stats may be slow, will timeout gracefully

## Visual Reference

### Worktree Card (Dirty + Behind)

```
┌─────────────────────────────────────────────┐
│ 120  120-feature-name @ a1b2c3d             │
│      ● ↓2 ████░░ +45 -12                    │
│      2h ago - Fix: component update         │
└─────────────────────────────────────────────┘
```

### Worktree Card (Clean + Merged)

```
┌─────────────────────────────────────────────┐
│ 118  118-old-feature @ d4e5f6g              │
│      ✓ 💤                                   │
│      45 days ago - Complete feature         │
└─────────────────────────────────────────────┘
```

### Project Header (Windows View)

```
┌─────────────────────────────────────────────┐
│ 󱂬 nixos-config ● ↑3  [5]                   │
│   ├─ Ghostty: ~/projects/nixos             │
│   ├─ VS Code: feature-120                  │
│   └─ ...                                   │
└─────────────────────────────────────────────┘
```

## API Changes

### New Fields in Worktree JSON

```json
{
  "git_additions": 45,
  "git_deletions": 12,
  "git_diff_total": 57,
  "git_additions_display": "+45",
  "git_deletions_display": "-12",
  "git_diff_tooltip": "+45 additions, -12 deletions"
}
```

### New Fields in Project JSON

```json
{
  "header_git_dirty": true,
  "header_git_ahead": 3,
  "header_git_behind": 0,
  "header_git_merged": false,
  "header_git_has_conflicts": false,
  "header_git_additions": 45,
  "header_git_deletions": 12
}
```
