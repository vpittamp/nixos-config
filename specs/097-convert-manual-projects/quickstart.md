# Quickstart: Git-Centric Project and Worktree Management

**Feature**: 097-convert-manual-projects
**Date**: 2025-11-28 (Major revision for git-centric architecture)

## Overview

This feature redesigns i3pm project management around git's native architecture. The key insight is that `bare_repo_path` (GIT_COMMON_DIR) is the canonical identifier that groups all related worktrees.

**Architecture Vision**: Git is the source of truth. Projects are grouped by their shared bare repository path.

## Key Concepts

### Three Project Types

| Type | Description | Example |
|------|-------------|---------|
| **Repository** | Primary entry for a bare repo (ONE per repo) | "nixos" → /etc/nixos |
| **Worktree** | Feature branch linked to a Repository | "097-feature" → /home/user/nixos-097-feature |
| **Standalone** | Non-git directory or simple repo | "notes" → /home/user/notes |

### Relationship Model

```
Bare Repo: /home/user/nixos-config.git
    │
    ├── Repository Project: "nixos" → /etc/nixos (main branch)
    │       ├── Worktree: "097-feature" → /home/user/nixos-097-feature
    │       ├── Worktree: "087-ssh" → /home/user/nixos-087-ssh
    │       └── Worktree: "085-widget" → /home/user/nixos-085-widget
```

## Quick Commands

### Discover and Register a Project

```bash
# Discover from current directory
i3pm project discover

# Discover specific path
i3pm project discover --path /etc/nixos

# With custom name and icon
i3pm project discover --path ~/my-app --name "My App" --icon "🚀"
```

### Create a Worktree

```bash
# Create new branch and worktree
i3pm worktree create 098-new-feature

# Checkout existing branch as worktree
i3pm worktree create hotfix-payment --checkout

# Custom directory name
i3pm worktree create feature-ui --name ui-work
```

### Delete a Worktree

```bash
# Remove worktree (confirmation required)
i3pm worktree remove 097-feature

# Force remove (has uncommitted changes)
i3pm worktree remove 097-feature --force
```

### Refresh Git Metadata

```bash
# Refresh all projects
i3pm project refresh --all

# Refresh specific project
i3pm project refresh nixos
```

### List Projects with Hierarchy

```bash
# Default hierarchical view
i3pm project list

# JSON output for scripting
i3pm project list --json
```

Output:
```
Repository Projects:
▼ 🔧 nixos (5 worktrees)
    ├─ 🌿 097-feature ● (dirty)
    ├─ 🌿 087-ssh-keys
    └─ 🌿 085-widget

Standalone Projects:
  📁 notes

Orphaned Worktrees:
  ⚠️ 042-old-feature (parent missing)
```

## Monitoring Panel (Projects Tab)

Access via **Alt+2** when panel is visible (**Mod+M** to toggle panel).

### Panel Features

- **Hierarchical Display**: Repository Projects are expandable containers
- **Worktree Nesting**: Worktrees appear indented under parent
- **Worktree Count**: Shows "(5 worktrees)" badge on collapsed parent
- **Dirty Bubble-up**: If any worktree is dirty, parent shows aggregate indicator

### Panel Actions

| Button | Action |
|--------|--------|
| **[+ Create]** | Create new worktree (on Repository Projects) |
| **[Switch]** | Switch to project |
| **[Delete]** | Delete worktree (with confirmation) |
| **[Refresh]** | Refresh git metadata |
| **[Recover]** | Restore orphaned worktree (creates Repository Project) |

### Visual Indicators

- **●** (yellow dot): Uncommitted changes (dirty)
- **⚠** (warning): Orphaned worktree or missing directory
- **▼/►**: Expand/collapse worktree list

## Workflow Examples

### Setting Up a New Repository Project

```bash
# Navigate to main repository
cd /etc/nixos

# Discover and register as Repository Project
i3pm project discover

# Output: Created repository project "nixos"
#         bare_repo_path: /home/user/nixos-config.git
```

### Creating a Feature Branch Worktree

```bash
# From any worktree of the repository
i3pm worktree create 098-new-feature

# Automatically:
# 1. Creates git worktree at /home/user/nixos-098-new-feature
# 2. Registers Worktree Project linked to parent "nixos"
# 3. Shows in panel under nixos hierarchy

# Switch to the new worktree
i3pm project switch 098-new-feature
```

### Finishing Work on a Worktree

```bash
# Merge your changes (in main worktree)
cd /etc/nixos
git merge 098-new-feature

# Delete the worktree
i3pm worktree remove 098-new-feature

# Automatically:
# 1. Runs git worktree remove
# 2. Deletes project JSON file
# 3. Updates panel hierarchy
```

### Recovering an Orphaned Worktree

```bash
# If parent Repository Project was deleted, worktree shows as orphaned

# From panel: Click [Recover] on orphaned worktree
# OR from CLI:
i3pm project discover --path /home/user/nixos-097-feature

# Creates new Repository Project from bare_repo_path
# Re-parents the orphaned worktree automatically
```

## How It Works

### bare_repo_path Discovery

When you run `i3pm project discover` or `i3pm worktree create`:

```bash
# Git command used internally
git rev-parse --git-common-dir
# Returns: /home/user/nixos-config.git (for all worktrees of this repo)
```

This path is the **canonical identifier** that groups all related projects.

### Project Type Determination

1. **Not a git repo?** → Standalone (if `--standalone` flag used)
2. **Has a Repository Project with same bare_repo_path?** → Worktree
3. **First project for this bare_repo_path?** → Repository

### Orphan Detection

On every panel refresh:
1. Find all `source_type: repository` projects
2. Get their `bare_repo_path` values
3. For each `source_type: worktree` project, check if its `bare_repo_path` matches any repository
4. No match? → Mark as `status: orphaned`

## Edge Cases

### Name Conflicts
If two repos have the same directory name, the second gets a numeric suffix:
- `my-app` (first discovered)
- `my-app-2` (second discovered)

### Missing Repositories
If a repository directory is removed:
- Project marked as `status: missing`
- Remains in list until explicitly deleted
- Automatically restored if directory reappears

### One Repository Project per Bare Repo
- Enforced constraint: Cannot create duplicate Repository Projects
- If you try to discover a path that already has a Repository Project, it creates a Worktree instead

## Troubleshooting

### Project Not Discovered

```bash
# Check if path is a git repo
git -C /path/to/repo rev-parse --git-common-dir

# Check existing projects with same bare_repo_path
i3pm project list --json | jq '.[] | select(.bare_repo_path)'
```

### Worktree Not Linked to Parent

```bash
# Check bare_repo_path matches
i3pm project list --json | jq '.[] | {name, bare_repo_path}'

# If bare_repo_path differs, the projects won't be grouped
```

### Panel Not Showing Hierarchy

```bash
# Restart monitoring panel
systemctl --user restart eww-monitoring-panel

# Check daemon for project data
i3pm daemon status
```

## Performance Notes

- **Worktree creation**: <10 seconds (git operation + project registration)
- **Worktree deletion**: <5 seconds (git operation + project deletion)
- **Metadata refresh**: <2 seconds per project
- **Panel update**: <200ms after project changes

## Related Commands

| Command | Description |
|---------|-------------|
| `i3pm project list` | List all projects with hierarchy |
| `i3pm project switch <name>` | Switch to project |
| `i3pm project discover` | Discover and register project |
| `i3pm project refresh` | Refresh git metadata |
| `i3pm worktree create` | Create new worktree |
| `i3pm worktree remove` | Delete worktree |
| `i3pm worktree list` | List worktrees for current repo |
