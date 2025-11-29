# Quick Start: Projects Tab CRUD Enhancement

**Feature**: 099-revise-projects-tab
**Date**: 2025-11-28

## Overview

The Projects tab in the Eww monitoring widget provides complete CRUD (Create, Read, Update, Delete) functionality for git projects and worktrees. This guide covers usage and troubleshooting.

## Opening the Projects Tab

**Show Panel**: `Mod+M`
**Enter Focus Mode**: `Mod+Shift+M`
**Switch to Projects Tab**: `Alt+2` (or `2` in focus mode)

## Viewing Projects

### Hierarchical View

The Projects tab displays:

1. **Repository Projects** (📦) - Main git repositories with expandable worktree lists
2. **Worktree Projects** (🌿) - Feature branch worktrees nested under parents
3. **Orphaned Worktrees** (⚠️) - Worktrees whose parent is not registered

### Status Indicators

| Indicator | Meaning |
|-----------|---------|
| ● (blue) | Active project |
| ● (red) | Uncommitted changes |
| ↑3 | 3 commits ahead of remote |
| ↓2 | 2 commits behind remote |
| ⚠️ | Directory missing or orphaned |
| 󰒍 | Remote SSH project |

### Expanding/Collapsing

- Click on a repository project to expand/collapse its worktree list
- Collapsed repositories show worktree count badge (e.g., "5 worktrees")
- Dirty indicator bubbles up to collapsed parent

## Creating Worktrees

### From Repository Project

1. Hover over a repository project
2. Click **[+ New Worktree]** button
3. Fill in the form:
   - **Branch Name** (required): e.g., `100-new-feature`
   - **Display Name** (optional): Human-readable name
   - **Icon** (optional): Emoji icon (default: 🌿)
4. Click **[Create]**

### CLI Alternative

```bash
# Create worktree from feature description
i3pm worktree create --from-description "Add user authentication"

# Create worktree with explicit branch
i3pm worktree create 100-feature-auth

# Create worktree for existing branch
i3pm worktree create 100-feature-auth --checkout
```

## Editing Projects

### Inline Edit Form

1. Hover over any project
2. Click **[Edit]** button (󰏫)
3. Modify fields:
   - **Display Name**: How the project appears in the UI
   - **Icon**: Emoji or icon name
   - **Scope**: "Scoped" (apps hidden on switch) or "Global" (always visible)
4. Click **[Save]**

### Read-Only Fields

For worktrees, these fields cannot be changed:
- Branch name
- Worktree path
- Parent project

## Deleting Worktrees

### Two-Stage Confirmation

1. Hover over a worktree
2. Click **[Delete]** button (󰆴)
3. Button changes to **[❗]** - "Click again to confirm"
4. Click again within 5 seconds to confirm

### Dirty Worktree Warning

If the worktree has uncommitted changes:
- Warning dialog appears
- Choose **[Cancel]** to abort
- Choose **[Force Delete]** to remove anyway

### CLI Alternative

```bash
# Remove worktree (will prompt if dirty)
i3pm worktree remove 099-revise-projects-tab

# Force remove with uncommitted changes
i3pm worktree remove 099-revise-projects-tab --force

# Also delete remote branch
i3pm worktree remove 099-revise-projects-tab --delete-remote
```

## Switching Projects

### Single Click Switch

- Click anywhere on a project row (except action buttons)
- Active indicator (● blue) moves to the selected project
- Scoped applications will use the new project's directory

### Keyboard Navigation (Focus Mode)

1. Enter focus mode: `Mod+Shift+M`
2. Use `j`/`k` or `↓`/`↑` to navigate
3. Press `Enter` to switch to highlighted project
4. Press `Escape` to exit focus mode

### CLI Alternative

```bash
# Switch to worktree
i3pm project switch 099-revise-projects-tab

# Switch to parent repository
i3pm project switch nixos

# Clear project (global mode)
i3pm project clear
```

## Refreshing Data

### Refresh All

Click the **[Refresh]** button in the Projects tab header to:
- Re-scan all project directories
- Update git metadata (branch, status, ahead/behind)
- Detect new/removed worktrees

### CLI Alternative

```bash
# Refresh specific project
i3pm project refresh 099-revise-projects-tab

# List worktrees for parent
i3pm worktree list nixos
```

## Handling Orphaned Worktrees

When a parent repository is deleted but worktrees remain:

1. Orphaned worktrees appear in the "Orphaned" section
2. Click **[Recover]** to:
   - Discover the bare repository
   - Register it as a new Repository Project
   - Re-link the worktree to the parent
3. Or click **[Delete]** to clean up the orphaned entry

## Troubleshooting

### Panel Not Updating

```bash
# Restart monitoring panel service
systemctl --user restart eww-monitoring-panel

# Check for errors
journalctl --user -u eww-monitoring-panel --since "5 minutes ago"
```

### Worktree Creation Fails

```bash
# Check if branch exists
git branch -a | grep <branch-name>

# Check if directory exists
ls -la ~/nixos-<branch-name>

# Verify git repository
cd /etc/nixos && git status
```

### Git Status Not Accurate

```bash
# Force refresh
i3pm project refresh <project-name>

# Check daemon is running
systemctl --user status i3-project-event-listener
```

### Forms Not Saving

```bash
# Check for validation errors in form
# Look for red error messages below input fields

# Check save script logs
tail -f ~/.local/state/project-crud.log

# Verify project JSON
cat ~/.config/i3/projects/<name>.json | jq .
```

## Key Bindings Reference

| Key | Action |
|-----|--------|
| `Mod+M` | Toggle panel visibility |
| `Mod+Shift+M` | Enter/exit focus mode |
| `Alt+2` | Switch to Projects tab |
| `2` (focus mode) | Switch to Projects tab |
| `j`/`↓` | Navigate down |
| `k`/`↑` | Navigate up |
| `Enter` | Select item / switch project |
| `h`/`←` | Collapse / go back |
| `l`/`→` | Expand / enter |
| `Escape` | Exit focus mode |

## Performance

- Discovery and display: <3 seconds for 50+ projects
- Worktree creation: <30 seconds (includes git operations)
- Project switching: <500ms active indicator update
- Git status refresh: <2 seconds
