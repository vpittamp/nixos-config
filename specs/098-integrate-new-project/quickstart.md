# Quickstart: Worktree-Aware Project Environment Integration

**Feature**: 098-integrate-new-project
**Date**: 2025-11-28

## Overview

Feature 098 integrates worktree/project metadata into the Sway project management workflow, providing automatic environment context for worktree-based development.

## Key Features

- **Automatic Worktree Detection**: Worktree projects get `I3PM_IS_WORKTREE=true`
- **Branch Metadata**: Extract number and type from branch names (e.g., `098-feature-auth`)
- **Parent Project Linking**: Worktrees reference their parent repository project
- **Git Metadata Injection**: Branch, commit, clean status available as environment variables
- **Status Validation**: Prevents switching to projects with missing directories

## Usage

### View Worktree Environment

After switching to a worktree project:

```bash
# In any launched terminal, environment contains:
echo $I3PM_IS_WORKTREE        # true
echo $I3PM_PARENT_PROJECT     # nixos
echo $I3PM_BRANCH_NUMBER      # 098
echo $I3PM_BRANCH_TYPE        # feature
echo $I3PM_FULL_BRANCH_NAME   # 098-integrate-new-project

# Git metadata also available:
echo $I3PM_GIT_BRANCH         # 098-integrate-new-project
echo $I3PM_GIT_COMMIT         # 330b569
echo $I3PM_GIT_IS_CLEAN       # true
echo $I3PM_GIT_AHEAD          # 0
```

### List Worktrees for Parent Project

```bash
i3pm worktree list nixos

# Output:
# Parent: nixos (/etc/nixos)
# Worktrees:
#   097 - Convert Manual Projects (active)
#   098 - Integrate New Project (active)
```

### Refresh Project Metadata

After making commits or changing branches:

```bash
i3pm project refresh nixos-098-integrate-new-project

# Updates git_metadata and branch_metadata without full discovery
```

### Discovery Automatically Populates

```bash
i3pm discover

# Worktrees are detected and:
# - Branch metadata parsed from branch name
# - Parent project resolved to name (not just path)
# - Git metadata extracted (commit, clean status, etc.)
```

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `I3PM_IS_WORKTREE` | "true" if worktree project | `true` |
| `I3PM_PARENT_PROJECT` | Parent project name | `nixos` |
| `I3PM_BRANCH_NUMBER` | Extracted number from branch | `098` |
| `I3PM_BRANCH_TYPE` | Branch type | `feature`, `fix`, `hotfix` |
| `I3PM_FULL_BRANCH_NAME` | Complete branch name | `098-integrate-new-project` |
| `I3PM_GIT_BRANCH` | Current git branch | `098-integrate-new-project` |
| `I3PM_GIT_COMMIT` | Current commit SHA (short) | `330b569` |
| `I3PM_GIT_IS_CLEAN` | No uncommitted changes | `true` or `false` |
| `I3PM_GIT_AHEAD` | Commits ahead of upstream | `0` |
| `I3PM_GIT_BEHIND` | Commits behind upstream | `0` |

## Branch Naming Conventions

The system parses these branch patterns:

| Pattern | Example | number | type |
|---------|---------|--------|------|
| `<number>-<type>-<desc>` | `098-feature-auth` | 098 | feature |
| `<type>-<number>-<desc>` | `fix-123-broken` | 123 | fix |
| `<number>-<desc>` | `078-eww-preview` | 078 | feature |
| `<type>-<desc>` | `hotfix-critical` | - | hotfix |
| Standard | `main`, `develop` | - | - |

## Troubleshooting

### Environment variables not set

```bash
# Check if project is detected as worktree
i3pm project current --json | jq '.source_type'
# Should output: "worktree"

# Check branch metadata was parsed
i3pm project current --json | jq '.branch_metadata'
```

### Parent project not linked

```bash
# Parent must exist as a project first
i3pm project list | grep nixos

# If missing, run discovery on parent repo directory
i3pm discover --scan-path /etc/nixos
```

### Missing project error on switch

```
Cannot switch to project 'old-project': directory does not exist at /path/to/old.
Either restore the directory or delete the project with: i3pm project delete old-project
```

## Technical Details

- Environment injection: `scripts/app-launcher-wrapper.sh`
- Branch parsing: `models/discovery.py:parse_branch_metadata()`
- Parent resolution: `services/project_service.py:_create_from_discovery()`
- Status validation: `ipc_server.py:_switch_project()`

## Related Features

- **Feature 097**: Git-based project discovery (foundation)
- **Feature 079**: Preview pane with branch number display
- **Feature 087**: Remote project SSH wrapping
