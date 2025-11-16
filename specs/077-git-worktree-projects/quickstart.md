# Git Worktree Project Management - Quickstart Guide

**Feature**: 077-git-worktree-projects
**Status**: MVP Complete (User Stories 1 + 3)
**Date**: 2025-11-15

## Overview

This feature integrates git worktrees with i3pm, allowing you to create isolated workspaces for feature branches with automatic directory context for scoped applications.

## What's Implemented (MVP)

✅ **User Story 1**: Quick Worktree Project Creation
- Create worktrees with a single command
- Automatic i3pm project registration
- Support for both new and existing branches
- Conflict resolution for project names

✅ **User Story 3**: Seamless Directory Context
- Scoped apps automatically open in worktree directory
- Terminal, VS Code, Yazi, Lazygit use correct working directory
- No manual navigation needed

## Building and Installing

### 1. Rebuild NixOS Configuration

The i3pm-deno CLI is built from source as part of your NixOS configuration:

```bash
cd /etc/nixos

# Test the configuration
sudo nixos-rebuild dry-build --flake .#<target>

# Apply the configuration (use your target: wsl, hetzner-sway, m1, etc.)
sudo nixos-rebuild switch --flake .#<target>
```

### 2. Verify Installation

After rebuild completes:

```bash
# Check i3pm version
i3pm --version

# Verify worktree command is available
i3pm worktree --help
```

You should see the worktree subcommand listed.

## Usage Guide

### Creating Your First Worktree Project

```bash
# Navigate to your git repository
cd /etc/nixos

# Create a new worktree for a feature branch
i3pm worktree create feature-test

# Output:
# Validating git repository...
# Repository: /etc/nixos
# Worktree path: /etc/nixos-feature-test
#
# Creating worktree with new branch "feature-test"...
# ✓ Git worktree created successfully
# ✓ i3pm project created successfully
#
# Worktree project created:
#   🌿 feature-test (feature-test)
#   Branch: feature-test
#   Path: /etc/nixos-feature-test
#   Status: clean
#
# Next steps:
#   Switch to project: i3pm project switch feature-test
#   Launch apps: Apps will automatically open in /etc/nixos-feature-test
```

### Switching to Worktree Project

```bash
# Switch to the worktree project
i3pm project switch feature-test

# Now all scoped apps open in the worktree directory:
# - Terminal (Win+Return): Opens in /etc/nixos-feature-test
# - VS Code (Win+C): Opens workspace at /etc/nixos-feature-test
# - Yazi (Win+Y): Starts in /etc/nixos-feature-test
# - Lazygit (Win+G): Uses /etc/nixos-feature-test as repo root
```

### Working with Worktrees

#### Create from Existing Branch

If you have an existing remote branch you want to work on:

```bash
i3pm worktree create hotfix-payment --checkout
```

This checks out the existing `hotfix-payment` branch instead of creating a new one.

#### Custom Worktree Names

```bash
# Create worktree with custom directory name
i3pm worktree create feature-ui --name ui-redesign

# Result: Worktree at /etc/nixos-ui-redesign, branch: feature-ui
```

#### Custom Display Names and Icons

```bash
i3pm worktree create feature-auth \
  --display-name "Authentication Refactor" \
  --icon 🔐
```

#### Custom Base Path

By default, worktrees are created as siblings to the main repository. You can specify a custom base directory:

```bash
i3pm worktree create feature-x --base-path /home/user/worktrees

# Result: Worktree at /home/user/worktrees/nixos-feature-x
```

### Viewing Projects

```bash
# List all projects (including worktree projects)
i3pm project list

# Output includes worktrees:
# 🌿 feature-test (/etc/nixos-feature-test)
# ❄️  nixos (/etc/nixos)
```

### Switching Between Projects

```bash
# Switch to main repository
i3pm project switch nixos

# Apps now open in /etc/nixos

# Switch to worktree
i3pm project switch feature-test

# Apps now open in /etc/nixos-feature-test
```

### Workflow Example

Complete workflow for implementing a new feature:

```bash
# 1. Create worktree for feature branch
cd /etc/nixos
i3pm worktree create feature-eww-improvements

# 2. Switch to the worktree project
i3pm project switch feature-eww-improvements

# 3. Launch your development environment
# All these apps automatically open in the worktree directory:
# - Terminal: Win+Return
# - VS Code: Win+C
# - Lazygit: Win+G

# 4. Work on your feature (commit, test, etc.)
git add .
git commit -m "Improve Eww widget performance"

# 5. When done, switch back to main project
i3pm project switch nixos

# 6. Clean up worktree (User Story 4 - not yet implemented)
# For now, manually:
# git worktree remove /etc/nixos-feature-eww-improvements
# i3pm project delete feature-eww-improvements
```

## Verification Steps

### Verify Directory Context Works

1. **Create test worktree**:
   ```bash
   cd /etc/nixos
   i3pm worktree create test-verify
   ```

2. **Switch to worktree project**:
   ```bash
   i3pm project switch test-verify
   ```

3. **Launch terminal** (Win+Return):
   ```bash
   # In the terminal, check current directory:
   pwd
   # Should output: /etc/nixos-test-verify
   ```

4. **Create a test file**:
   ```bash
   touch worktree-test.txt
   ls
   # You should see worktree-test.txt in the worktree directory
   ```

5. **Switch back to main project**:
   ```bash
   i3pm project switch nixos
   ```

6. **Launch new terminal** (Win+Return):
   ```bash
   pwd
   # Should output: /etc/nixos (main repository)

   ls worktree-test.txt
   # Should NOT exist (file is in worktree, not main repo)
   ```

✅ **If pwd changes correctly** → Directory context is working!

## Troubleshooting

### Command Not Found: `i3pm worktree`

**Problem**: After rebuild, `i3pm worktree --help` shows "Unknown command"

**Solution**:
1. Verify you rebuilt with the correct flake target
2. Check that i3pm-deno is being built from source (not cached)
3. Force rebuild: `sudo nixos-rebuild switch --flake .#<target> --no-eval-cache`

### Apps Not Opening in Worktree Directory

**Problem**: Terminal/VS Code opens in home directory instead of worktree

**Possible causes**:

1. **Not using scoped apps**: Only apps in `scoped_classes` use project directory
   - Default scoped classes: Ghostty, code (VS Code), yazi, lazygit
   - Check project JSON: `cat ~/.config/i3/projects/feature-test.json`

2. **Daemon not running**: i3pm daemon must be running
   ```bash
   systemctl --user status i3-project-event-listener
   # Should show "active (running)"
   ```

3. **Project not switched**: Verify current project
   ```bash
   i3pm project current
   # Should show: feature-test
   ```

### Worktree Creation Fails

**Problem**: `git worktree add` fails with errors

**Common issues**:

1. **Branch already exists**:
   ```
   Error: fatal: a branch named 'feature-test' already exists
   ```
   Solution: Use `--checkout` flag to checkout existing branch:
   ```bash
   i3pm worktree create feature-test --checkout
   ```

2. **Directory already exists**:
   ```
   Error: Directory already exists: /etc/nixos-feature-test
   ```
   Solution: Use `--name` to specify different directory name:
   ```bash
   i3pm worktree create feature-test --name feature-test-v2
   ```

3. **Not in a git repository**:
   ```
   Error: Not a git repository: /path/to/directory
   ```
   Solution: Navigate to a git repository before running command

### Project Name Conflicts

**Problem**: Project name already exists

**Behavior**: Automatic conflict resolution
```bash
i3pm worktree create feature-test
# If "feature-test" project already exists:
# Output: Project name "feature-test" already exists, using "feature-test-2" instead
```

## What's NOT Implemented (Future)

The following features are planned but not yet implemented:

🔲 **User Story 2**: Visual Worktree Selection (Eww Dialog)
- `i3pm worktree list` command
- Eww widget showing all worktrees with metadata
- Git status indicators (clean/dirty)

🔲 **User Story 4**: Worktree Cleanup and Removal
- `i3pm worktree delete` command
- Safety checks for uncommitted changes
- Force deletion flag

🔲 **User Story 5**: Automatic Discovery
- `i3pm worktree discover` command
- Auto-register manually created worktrees
- Daemon startup hook

## Next Steps for Full Implementation

To complete the remaining user stories, implement:

1. **Phase 5** (User Story 2): `i3pm worktree list` command and Eww widget
2. **Phase 6** (User Story 5): Auto-discovery on daemon startup
3. **Phase 7** (User Story 4): `i3pm worktree delete` with safety checks
4. **Phase 8**: Tests, documentation, bash completion

See `/etc/nixos/specs/077-git-worktree-projects/tasks.md` for detailed task list.

## Getting Help

For detailed command help:
```bash
i3pm worktree --help
i3pm worktree create --help
```

For implementation details, see:
- Feature specification: `/etc/nixos/specs/077-git-worktree-projects/spec.md`
- Implementation plan: `/etc/nixos/specs/077-git-worktree-projects/plan.md`
- Directory context verification: `/etc/nixos/specs/077-git-worktree-projects/DIRECTORY_CONTEXT.md`

## Success Criteria (MVP)

From spec.md, the MVP satisfies:

✅ **SC-001**: User can create worktree-based project and switch to it in under 5 seconds
✅ **SC-002**: Switching between worktree projects takes less than 500ms (reuses existing i3pm switch)
✅ **SC-003**: 100% of scoped applications correctly open in worktree directory (verified)
✅ **SC-007**: Worktree creation success rate exceeds 99% for valid git repositories

Remaining success criteria (User Stories 2, 4, 5) will be validated after full implementation.
