# API Contracts: Projects Tab Operations

**Feature**: 099-revise-projects-tab
**Date**: 2025-11-28

## Overview

This document defines the API contracts for Projects tab CRUD operations. The primary interface is via CLI commands executed from Bash wrapper scripts, with IPC methods for real-time data streaming.

## CLI Commands (Form Submission)

### Create Worktree

**Command**: `i3pm worktree create <branch> [options]`

**Input**:
```bash
i3pm worktree create "100-new-feature" \
  --name "100-new-feature" \
  --display-name "100 - New Feature" \
  --icon "🌿"
```

**Options**:
| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `<branch>` | string | Yes | Branch name to create/checkout |
| `--from-description` | string | No | Generate branch from feature description |
| `--source` | string | No | Source branch (default: main) |
| `--name` | string | No | Custom worktree directory name |
| `--base-path` | string | No | Base directory for worktree (default: $HOME) |
| `--checkout` | flag | No | Checkout existing branch instead of create |
| `--display-name` | string | No | Custom display name |
| `--icon` | string | No | Project icon (default: 🌿) |

**Success Response** (exit code 0):
```
✓ Generated branch name: 100-new-feature
✓ Git worktree created successfully
✓ Specs directory created for parallel Claude Code sessions
✓ i3pm project created successfully
✓ Directory added to zoxide

Worktree project created:
  🌿 100 - New Feature (100-new-feature)
  Branch: 100-new-feature
  Path: /home/vpittamp/nixos-100-new-feature
  Status: clean
```

**Error Response** (exit code 1):
```
Error: Branch '100-new-feature' already exists
Suggestion: Use --checkout to checkout existing branch, or choose a different name
```

### Remove Worktree

**Command**: `i3pm worktree remove <name> [options]`

**Input**:
```bash
i3pm worktree remove "099-revise-projects-tab" --force
```

**Options**:
| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `<name>` | string | Yes | Project name to remove |
| `--force` | flag | No | Force removal even with uncommitted changes |
| `--delete-remote` | flag | No | Also delete remote branch |

**Success Response** (exit code 0):
```
✓ Git worktree removed: /home/vpittamp/nixos-099-revise-projects-tab
✓ Local branch deleted: 099-revise-projects-tab
✓ Project registration removed
✓ Zoxide entry removed

Worktree '099-revise-projects-tab' removed successfully
```

**Error Response** (exit code 1):
```
Error: Worktree has uncommitted changes
Use --force to remove anyway (changes will be lost)
```

### List Worktrees

**Command**: `i3pm worktree list [parent]`

**Input**:
```bash
i3pm worktree list nixos
```

**Success Response** (exit code 0, JSON format):
```json
[
  {
    "name": "099-revise-projects-tab",
    "display_name": "099 - Revise Projects Tab",
    "branch": "099-revise-projects-tab",
    "path": "/home/vpittamp/nixos-099-revise-projects-tab",
    "parent_repo": "/etc/nixos",
    "git_status": {
      "is_clean": true,
      "ahead_count": 0,
      "behind_count": 0,
      "has_untracked": false
    },
    "created_at": "2025-11-28T17:51:00.000Z",
    "icon": "🌿"
  }
]
```

### Switch Project

**Command**: `i3pm project switch <name>`

**Input**:
```bash
i3pm project switch "099-revise-projects-tab"
```

**Success Response** (exit code 0):
```
Switched to project: 099-revise-projects-tab
Working directory: /home/vpittamp/nixos-099-revise-projects-tab
```

**Error Response** (exit code 1):
```
Error: Project directory does not exist: /home/vpittamp/nixos-099-revise-projects-tab
```

### Update Project

**Command**: `i3pm project update <name> --updates <json>`

**Input**:
```bash
i3pm project update "099-revise-projects-tab" --updates '{
  "display_name": "099 - Projects Tab Enhancement",
  "icon": "🔧"
}'
```

**Success Response** (exit code 0):
```
Project '099-revise-projects-tab' updated successfully
```

## IPC Methods (Daemon Communication)

### worktree.list

**Request**:
```json
{
  "method": "worktree.list",
  "params": {
    "parent_project": "nixos"
  }
}
```

**Response**:
```json
{
  "status": "success",
  "parent": {
    "name": "nixos",
    "directory": "/etc/nixos"
  },
  "worktrees": [
    {
      "name": "099-revise-projects-tab",
      "display_name": "099 - Revise Projects Tab",
      "directory": "/home/vpittamp/nixos-099-revise-projects-tab",
      "icon": "🌿",
      "status": "active",
      "branch_metadata": {
        "number": "099",
        "type": "feature",
        "full_name": "099-revise-projects-tab"
      },
      "git_metadata": {
        "branch": "099-revise-projects-tab",
        "commit": "abc1234",
        "is_clean": true,
        "ahead": 0,
        "behind": 0
      }
    }
  ],
  "count": 1
}
```

### project.refresh

**Request**:
```json
{
  "method": "project.refresh",
  "params": {
    "project_name": "099-revise-projects-tab"
  }
}
```

**Response**:
```json
{
  "status": "success",
  "project_name": "099-revise-projects-tab",
  "fields_updated": ["git_metadata", "branch_metadata"]
}
```

### project.current

**Request**:
```json
{
  "method": "project.current",
  "params": {}
}
```

**Response**:
```json
{
  "status": "success",
  "project": {
    "name": "nixos",
    "display_name": "NixOS Configuration",
    "directory": "/etc/nixos"
  }
}
```

## Monitoring Panel Data Stream

### deflisten Stream

**Source**: `monitoring-data-backend --listen`

**Output Format** (one JSON object per line):
```json
{
  "status": "success",
  "main_projects": [...],
  "worktrees": [...],
  "orphaned_worktrees": [...],
  "active_project": "nixos"
}
```

**Update Events**:
- Project switch (active_project changes)
- Git status change (file modified/committed)
- Worktree created/deleted
- Project metadata updated

## Eww Variable Updates

### Form State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `editing_project_name` | string | Name of project being edited (empty = no edit) |
| `edit_form_display_name` | string | Form input: display name |
| `edit_form_icon` | string | Form input: icon |
| `edit_form_directory` | string | Form display: directory (read-only) |
| `edit_form_scope` | string | Form input: "scoped" or "global" |
| `worktree_form_branch_name` | string | Form input: branch name |
| `worktree_form_path` | string | Form input: worktree path |
| `worktree_form_parent_project` | string | Form context: parent project |

### State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `projects_data` | object | Current projects hierarchy JSON |
| `hover_project_name` | string | Currently hovered project name |
| `json_hover_project` | string | Project showing JSON tooltip |
| `project_creating` | boolean | Create form is open |
| `project_deleting` | boolean | Delete confirmation is active |
| `worktree_delete_confirm` | string | Worktree name awaiting delete confirm |
| `save_in_progress` | boolean | Form submission in progress |

### Notification Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `success_notification` | string | Success message to display |
| `success_notification_visible` | boolean | Show success toast |
| `error_notification` | string | Error message to display |
| `error_notification_visible` | boolean | Show error toast |
| `warning_notification` | string | Warning message to display |
| `warning_notification_visible` | boolean | Show warning toast |

## Error Codes

| Code | Message | Recovery Action |
|------|---------|-----------------|
| `BRANCH_EXISTS` | Branch already exists | Use --checkout or different name |
| `DIR_EXISTS` | Directory already exists | Choose different path |
| `DIR_NOT_FOUND` | Directory does not exist | Verify path or recreate |
| `UNCOMMITTED_CHANGES` | Worktree has uncommitted changes | Use --force or commit first |
| `NOT_WORKTREE` | Not a valid worktree | Check project type |
| `PARENT_NOT_FOUND` | Parent repository not found | Recover orphaned worktree |
| `GIT_ERROR` | Git command failed | Check git output for details |
| `PERMISSION_DENIED` | Insufficient permissions | Check file/directory permissions |
