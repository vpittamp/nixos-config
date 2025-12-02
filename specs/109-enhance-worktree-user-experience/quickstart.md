# Quickstart: Enhanced Worktree User Experience

**Feature**: 109-enhance-worktree-user-experience
**Date**: 2025-12-02

## Overview

This feature enhances the Eww monitoring panel's worktree management to provide an exceptional parallel development experience with:
- Fast worktree switching (<500ms)
- Deep lazygit integration with view-specific launch
- Keyboard-first navigation
- Comprehensive status visibility

## Prerequisites

- NixOS with Sway compositor
- Eww monitoring panel enabled (`programs.eww-monitoring-panel.enable = true`)
- i3pm daemon running
- lazygit 0.40+ installed

## Quick Commands

### Panel Navigation

| Key | Action |
|-----|--------|
| `Mod+M` | Toggle monitoring panel |
| `Mod+Shift+M` | Enter focus mode |
| `Alt+2` | Switch to Projects tab |

### Focus Mode (Projects Tab)

| Key | Action |
|-----|--------|
| `j` / `↓` | Navigate down |
| `k` / `↑` | Navigate up |
| `Enter` | Switch to selected worktree |
| `c` | Create new worktree |
| `d` | Delete worktree |
| `g` | Open lazygit for worktree |
| `t` | Open terminal in worktree |
| `e` | Open VS Code in worktree |
| `r` | Refresh git status |
| `Escape` | Exit focus mode |

### CLI Commands

```bash
# Worktree operations
i3pm worktree list nixos              # List worktrees for repo
i3pm worktree create 110-new-feature  # Create worktree
i3pm worktree remove 110-new-feature  # Delete worktree

# Project switching
i3pm project switch nixos:109-enhance-worktree-user-experience

# Lazygit launch
worktree-lazygit /path/to/worktree status  # Open with status view
worktree-lazygit /path/to/worktree branch  # Open with branches view
```

## Status Indicators

| Indicator | Meaning | Action |
|-----------|---------|--------|
| ● (red) | Uncommitted changes | Press `g` to commit |
| ↑3 | 3 commits ahead of remote | Press `g` then push |
| ↓2 | 2 commits behind remote | Press `g` then pull |
| ⚠ | Merge conflicts | Press `g` to resolve |
| 💤 | Stale (30+ days inactive) | Consider deleting |
| ✓ | Merged to main | Safe to delete |

## Typical Workflow

### Starting New Feature

1. Open monitoring panel: `Mod+M`
2. Go to Projects tab: `Alt+2`
3. Navigate to repository
4. Press `c` to create worktree
5. Enter branch name: `110-new-feature`
6. Press `Enter` to create
7. Worktree appears in list with ● indicator (new, no commits)

### Switching Between Features

1. Open monitoring panel: `Mod+M`
2. Enter focus mode: `Mod+Shift+M`
3. Navigate with `j`/`k`
4. Press `Enter` on target worktree
5. Context switches in <500ms

### Committing Changes

1. See ● indicator on worktree
2. Press `g` to open lazygit
3. Stage files with `space`
4. Commit with `c`
5. Push with `P`
6. Exit lazygit with `q`
7. Status updates in panel within 2 seconds

### Cleaning Up Merged Feature

1. See ✓ indicator (merged)
2. Navigate to worktree
3. Press `d` to delete
4. Confirm deletion
5. Worktree removed from panel

## Lazygit Integration

### View Selection

The panel intelligently selects the lazygit view based on context:

| Context | View Opened | Reason |
|---------|-------------|--------|
| Dirty worktree | Status | Ready to stage/commit |
| Behind remote | Branches | Ready to pull |
| Has conflicts | Status | Conflict markers visible |
| Default | Status | General purpose |

### Manual View Selection

From the action menu (hover over worktree):
- Click "Git" → Opens status view
- Click "Commit" → Opens status view
- Click "Sync" → Opens branches view
- Click "Resolve" → Opens status view

### Command Format

```bash
# Pattern: lazygit --path <worktree-path> <view>
lazygit --path /home/user/repo/109-feature status
lazygit --path /home/user/repo/109-feature branch
lazygit --path /home/user/repo/109-feature log
lazygit --path /home/user/repo/109-feature stash
```

## Troubleshooting

### Panel Not Updating

```bash
# Restart the monitoring panel
systemctl --user restart eww-monitoring-panel

# Check for errors
journalctl --user -u eww-monitoring-panel --since "5 minutes ago"
```

### Lazygit Opens Wrong Directory

```bash
# Verify worktree path
i3pm worktree list nixos

# Test manual launch
lazygit --path /full/path/to/worktree status
```

### Worktree Creation Fails

```bash
# Check if branch exists
git branch -a | grep feature-name

# Check if directory conflicts
ls -la ~/repos/vpittamp/nixos-config/

# Create manually to see error
git worktree add ../feature-name -b feature-name
```

### Slow Switching (>500ms)

```bash
# Check daemon performance
i3pm daemon status

# Restart daemon
systemctl --user restart i3-project-event-listener

# Check for large git repos
time git status  # Should be <100ms
```

## Configuration

### Enable in NixOS

```nix
# home.nix or home-vpittamp.nix
{
  programs.eww-monitoring-panel = {
    enable = true;
    # Feature 109 enhancements are automatically included
  };
}
```

### Customize Keyboard Shortcuts

Keyboard shortcuts are defined in `eww-monitoring-panel.nix` and can be customized by editing the focus mode handlers.

### Worktree Directory Structure

Worktrees are created as siblings to the main repository:

```
~/repos/vpittamp/
├── nixos-config/              # Main repo (main branch)
├── nixos-config/109-enhance/  # Worktree (feature branch)
├── nixos-config/110-feature/  # Another worktree
└── nixos-config/111-bugfix/   # Another worktree
```

## Performance Targets

| Operation | Target | Measured |
|-----------|--------|----------|
| Worktree switch | <500ms | TBD |
| Status refresh | <2s | TBD |
| Panel interaction | <100ms | TBD |
| Lazygit launch | <1s | TBD |
| Worktree creation | <5s | TBD |

## Related Documentation

- [Feature Spec](./spec.md)
- [Implementation Plan](./plan.md)
- [Research](./research.md)
- [Data Model](./data-model.md)
- [Lazygit Context Contract](./contracts/lazygit-context.json)
- [Worktree Actions Contract](./contracts/worktree-actions.json)
