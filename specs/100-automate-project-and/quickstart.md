# Quick Start: Structured Git Repository Management

**Feature**: 100-automate-project-and

## Overview

This feature organizes git repositories using a structured directory layout with bare repositories and sibling worktrees, optimized for parallel Claude Code development.

## Directory Structure

```
~/repos/
├── vpittamp/                       # Personal GitHub account
│   └── nixos/                      # Repository container
│       ├── .bare/                  # Bare git database
│       ├── .git                    # Pointer: "gitdir: ./.bare"
│       ├── main/                   # Main branch worktree
│       └── 100-feature/            # Feature worktree
└── PittampalliOrg/                 # Work organization
    └── api/
        ├── .bare/
        ├── .git
        ├── main/
        └── hotfix/
```

## Setup

### 1. Configure Accounts

```bash
# Add your personal account
i3pm account add vpittamp ~/repos/vpittamp --default

# Add work organization
i3pm account add PittampalliOrg ~/repos/PittampalliOrg

# Verify configuration
i3pm account list
```

### 2. Clone Repositories

```bash
# Clone with bare repo + main worktree setup
i3pm clone git@github.com:vpittamp/nixos.git

# Structure created:
# ~/repos/vpittamp/nixos/.bare/
# ~/repos/vpittamp/nixos/.git
# ~/repos/vpittamp/nixos/main/

# Clone work repo
i3pm clone git@github.com:PittampalliOrg/api.git
```

### 3. Create Feature Worktrees

```bash
# Navigate to any worktree in the repo
cd ~/repos/vpittamp/nixos/main

# Create a feature worktree
i3pm worktree create 100-automate-project

# Worktree created at:
# ~/repos/vpittamp/nixos/100-automate-project/

# List all worktrees
i3pm worktree list
```

## Commands Reference

### Account Management

```bash
i3pm account list                    # List configured accounts
i3pm account add <name> <path>       # Add new account
i3pm account add <name> <path> --default  # Add as default account
i3pm account add <name> <path> --ssh-host github-work  # Custom SSH host
```

### Repository Operations

```bash
i3pm clone <url>                     # Clone with bare setup
i3pm repo list                       # List all repositories
i3pm repo list --account vpittamp    # Filter by account
i3pm repo get vpittamp/nixos         # Get repo details
i3pm discover                        # Scan and refresh all repos
```

### Worktree Operations

```bash
i3pm worktree create <branch>        # Create feature worktree
i3pm worktree create <branch> --from main  # Specify base branch
i3pm worktree list                   # List worktrees for current repo
i3pm worktree list vpittamp/nixos    # List for specific repo
i3pm worktree remove <branch>        # Remove worktree
i3pm worktree remove <branch> --force  # Force remove (ignores dirty)
```

## Parallel Development Workflow

### Running Multiple Claude Code Instances

```bash
# Terminal 1: Work on feature 100
cd ~/repos/vpittamp/nixos/100-feature
claude

# Terminal 2: Work on feature 101
cd ~/repos/vpittamp/nixos/101-bugfix
claude

# Terminal 3: Review PR
cd ~/repos/vpittamp/nixos/review
git fetch && git checkout origin/pr-123
claude
```

### Comparing Changes

```bash
# Compare feature with main
cd ~/repos/vpittamp/nixos
diff -r main/src 100-feature/src

# Or use git diff across worktrees
git -C main diff HEAD..100-feature
```

### Switching Context

```bash
# Just change directories - no git checkout needed!
cd ../main           # Switch to main
cd ../100-feature    # Switch to feature
cd ../review         # Switch to review
```

## Project Naming

| Type | Format | Example |
|------|--------|---------|
| Repository | `<account>/<repo>` | `vpittamp/nixos` |
| Worktree | `<account>/<repo>:<branch>` | `vpittamp/nixos:100-feature` |
| Main worktree | `<account>/<repo>:main` | `vpittamp/nixos:main` |

## Integration with i3pm

### Project Switching

```bash
# Switch to a worktree project
i3pm project switch vpittamp/nixos:100-feature

# Launch apps in project context
i3pm app launch terminal  # Opens in worktree directory
```

### Monitoring Panel

The Projects tab in the monitoring panel (`Mod+M` → `Alt+2`) shows:
- Repositories grouped by account
- Worktrees nested under their repository
- Git status indicators (dirty, ahead/behind)
- Active project highlighting

## Troubleshooting

### "Not in a repository context"

```bash
# Run from within a worktree directory
cd ~/repos/vpittamp/nixos/main
i3pm worktree create 100-feature  # Works!
```

### "Repository already exists"

```bash
# Check existing repo
ls ~/repos/vpittamp/nixos

# If corrupted, remove and re-clone
rm -rf ~/repos/vpittamp/nixos
i3pm clone git@github.com:vpittamp/nixos.git
```

### "Worktree has uncommitted changes"

```bash
# Option 1: Commit or stash changes
cd ~/repos/vpittamp/nixos/100-feature
git stash

# Option 2: Force remove
i3pm worktree remove 100-feature --force
```

### Refresh After Manual Changes

```bash
# If you manually created worktrees with git
i3pm discover  # Rescans all repos and worktrees
```

## Migration from Old Project System

The new system replaces manual project registration. To migrate:

1. Configure accounts with `i3pm account add`
2. Clone repos into new structure with `i3pm clone`
3. Old `~/.config/i3/projects/*.json` files can be removed
4. Run `i3pm discover` to register all new repos

Old projects in scattered directories will not be discovered - re-clone them into the structured layout.
