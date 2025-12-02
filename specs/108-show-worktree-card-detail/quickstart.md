# Quickstart: Enhanced Worktree Card Status Display

**Feature**: 108-show-worktree-card-detail
**Date**: 2025-12-01

## Overview

Enhanced worktree cards in the Projects tab display comprehensive git status at-a-glance:
- **Dirty indicator** (●): Red dot for uncommitted changes
- **Sync status** (↑5 ↓2): Commits ahead/behind remote
- **Merge badge** (✓): Teal badge when merged into main
- **Stale indicator** (💤): Gray icon for inactive worktrees (30+ days)
- **Conflict warning** (⚠): Red warning for merge conflicts

## Usage

### Viewing Worktree Status

1. Open the monitoring panel: `Mod+M`
2. Switch to Projects tab: `Alt+2` (or `2` in focus mode)
3. Expand a repository to see worktree cards

### Visual Indicators

| Indicator | Location | Color | Meaning |
|-----------|----------|-------|---------|
| ● | After branch name | Red (#f38ba8) | Uncommitted changes |
| ↑N | Status badges | Green (#a6e3a1) | N commits to push |
| ↓N | Status badges | Orange (#fab387) | N commits to pull |
| ✓ | Status badges | Teal (#94e2d5) | Branch merged into main |
| 💤 | Status badges | Gray (#6c7086) | No activity in 30+ days |
| ⚠ | Status badges | Red (#f38ba8) | Merge conflicts |

### Tooltip Details

Hover over any status indicator to see detailed breakdown:
- Dirty indicator: "2 staged, 3 modified, 1 untracked"
- Sync indicator: "5 commits to push, 2 commits to pull"
- Branch info: Last commit time and message preview

### Example Card Layout

```
┌─────────────────────────────────────────────────────────┐
│  🌿 099-revise-projects-tab @ abc1234 ● ↑5 ↓2 ✓        │
│     ~/nixos-099-revise-projects-tab                     │
└─────────────────────────────────────────────────────────┘

Legend:
🌿 = Worktree icon
099-revise-projects-tab = Branch name
@ abc1234 = Commit hash
● = Dirty indicator (has uncommitted changes)
↑5 ↓2 = 5 ahead, 2 behind remote
✓ = Merged into main
```

### Status Priority

Multiple indicators can appear simultaneously, ordered by priority:
1. Conflicts (⚠) - highest priority, always visible
2. Dirty (●) - indicates work in progress
3. Sync (↑↓) - shows push/pull needs
4. Merged (✓) - indicates completion
5. Stale (💤) - lowest priority, subtle visual

### Refresh Behavior

Status updates occur:
- When panel is opened (`Mod+M`)
- When Projects tab is selected (`Alt+2`)
- When [Refresh] button is clicked
- Status is NOT continuously polled (performance optimization)

## Troubleshooting

### Status Not Updating

```bash
# Force panel restart
systemctl --user restart eww-monitoring-panel

# Check backend logs
journalctl --user -u eww-monitoring-panel -f
```

### Merge Status Incorrect

The merge check uses `git branch --merged main`:
```bash
# Verify manually
cd /path/to/worktree
git branch --merged main | grep "$(git branch --show-current)"
```

### Stale Detection Issues

Staleness is based on last commit timestamp (30-day threshold):
```bash
# Check last commit time
git log -1 --format="%cr"  # e.g., "45 days ago"
```

## Configuration

### Stale Threshold

The staleness threshold (30 days) is currently hardcoded. Future versions may allow customization via:

```nix
# Hypothetical future config
programs.eww-monitoring-panel = {
  enable = true;
  worktreeStaleThresholdDays = 30;  # Default: 30
};
```

## Performance Notes

- Status queries execute in parallel per worktree
- Target: <50ms per worktree
- Git metadata cached with 5-second TTL
- Merge status is expensive - only checked on panel open/refresh
