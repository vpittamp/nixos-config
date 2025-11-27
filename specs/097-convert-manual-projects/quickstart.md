# Quickstart: Git-Based Project Discovery

**Feature**: 097-convert-manual-projects
**Date**: 2025-11-26

## Overview

This feature converts i3pm project management from manual JSON creation to automatic git repository discovery. Instead of running `i3pm project create` for each repository, you can now discover all git repositories in a directory with a single command.

## Quick Commands

### Discover Local Repositories

```bash
# Discover repositories in configured scan paths
i3pm project discover

# Discover repositories in specific paths
i3pm project discover --path ~/projects --path /etc/nixos

# Preview what would be discovered (dry run)
i3pm project discover --dry-run
```

### Include GitHub Repositories

```bash
# Discover local repos AND list GitHub repos
i3pm project discover --github

# List only GitHub repos (no local discovery)
i3pm project list --github
```

### Refresh Git Metadata

```bash
# Refresh git status for all projects
i3pm project refresh

# Refresh specific project
i3pm project refresh nixos
```

### Configure Discovery

```bash
# View current discovery configuration
i3pm config discovery show

# Add a new scan path
i3pm config discovery add-path ~/work

# Remove a scan path
i3pm config discovery remove-path ~/old-projects

# Enable automatic discovery on daemon startup
i3pm config discovery set --auto-discover=true
```

## What Gets Discovered

### Standard Git Repositories
- Directories containing `.git/` directory
- Extracts: branch, commit, remote URL, clean/dirty status
- Creates project with inferred icon based on language

### Git Worktrees
- Directories with `.git` file (not directory)
- Automatically linked to parent repository
- Appears in Projects tab with worktree indicator

### GitHub Repositories (Optional)
- Requires `gh` CLI authenticated
- Lists remote repos not cloned locally
- Shown with "remote" badge in UI

## Projects Tab Enhancements

The monitoring panel Projects tab (Alt+2) now displays:

### Grouping
- **Repositories**: Standard git repos
- **Worktrees**: Feature branches linked to parent repos
- **Remote Only**: GitHub repos not yet cloned

### Git Status Indicators
- **Branch name**: Current branch displayed
- **Modified badge**: Yellow dot if uncommitted changes
- **Ahead/behind**: "3" or "2" count if out of sync with upstream

### Source Type Badge
- : Discovered repository
- : Git worktree
- : GitHub-only (not cloned)
- : Manually created (legacy)

## Workflow Examples

### New Developer Setup

```bash
# Clone your projects repo
git clone git@github.com:myorg/projects.git ~/projects

# Discover all repos in projects directory
i3pm project discover --path ~/projects

# All repos now appear in project switcher (Win+P)
```

### Working with Feature Branches

```bash
# Create worktree using standard git
cd /etc/nixos
git worktree add ../nixos-097-feature 097-feature-branch

# Worktree automatically discovered on next discovery
i3pm project discover

# Or wait for daemon startup (if auto-discover enabled)
```

### Syncing with GitHub

```bash
# See what repos you have on GitHub vs locally
i3pm project discover --github --dry-run

# Discover local repos and show uncloned GitHub repos
i3pm project discover --github
```

## Configuration File

Discovery settings stored in `~/.config/i3/discovery-config.json`:

```json
{
  "scan_paths": [
    "/home/vpittamp/projects",
    "/etc/nixos"
  ],
  "exclude_patterns": [
    "node_modules",
    "vendor",
    ".cache"
  ],
  "auto_discover_on_startup": false,
  "max_depth": 3
}
```

## Edge Cases

### Name Conflicts
If two repos have the same directory name, the second gets a numeric suffix:
- `my-app` (first discovered)
- `my-app-2` (second discovered)

Rename via project edit if desired.

### Missing Repositories
If a repository directory is removed:
- Project marked as "missing" (yellow warning badge)
- Project remains in list until explicitly deleted
- Automatically restored if directory reappears

### Symbolic Links
Symbolic links are resolved to their real path. If two symlinks point to the same repo, only one project is created.

### Submodules
Git submodules are not registered as separate projects. Only top-level repositories are discovered.

## Troubleshooting

### Discovery returns no results

```bash
# Check scan paths exist
ls -la ~/projects /etc/nixos

# Verify git repos exist
find ~/projects -maxdepth 2 -name ".git" -type d

# Check config
i3pm config discovery show
```

### GitHub discovery fails

```bash
# Check gh CLI authentication
gh auth status

# Login if needed
gh auth login
```

### Projects not showing in panel

```bash
# Restart monitoring panel
systemctl --user restart eww-monitoring-panel

# Check daemon connection
i3pm daemon status
```

## Performance Notes

- **Local discovery**: <30 seconds for 50 repositories
- **GitHub listing**: <5 seconds for 100 repos
- **Startup discovery**: Runs async, doesn't block daemon

## Related Commands

- `i3pm project list` - List all projects
- `i3pm project switch <name>` - Switch to project
- `i3pm project delete <name>` - Delete project
- `i3pm worktree list` - List worktrees (existing command)
