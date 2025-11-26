# Quickstart: Project & Worktree Management in Monitoring Panel

**Feature**: 096 - Bolster Project & Worktree CRUD Operations
**Date**: 2025-11-26

## Overview

The Monitoring Panel's **Projects tab** provides a graphical interface for managing i3pm projects and Git worktrees. This guide covers all CRUD operations with keyboard shortcuts and visual feedback.

## Accessing the Projects Tab

1. **Open Monitoring Panel**: Press `Mod+M`
2. **Switch to Projects Tab**: Press `Alt+2` or click the "Projects" tab

The Projects tab shows:
- Main projects (parent repositories)
- Worktrees (feature branches) indented under their parent
- Active project indicator (● symbol)
- Remote project indicator (󰒍 symbol)

## Project Operations

### Create New Project

1. Click **"New Project"** button at top of Projects tab
2. Fill in the form:
   - **Name**: Required (lowercase letters, numbers, hyphens)
   - **Display Name**: Optional human-readable name
   - **Icon**: Optional emoji (e.g., 🔥, 📦, 🚀)
   - **Directory**: Required absolute path to project folder
   - **Scope**: "Scoped" (default) or "Global"
3. Click **"Create"** to save
4. ✅ Success: Green notification appears, project added to list
5. ❌ Error: Red error message appears below affected field

**Validation**:
- Name must be unique (no existing project with same name)
- Directory must exist on disk
- Name format: `my-project-123` (lowercase, hyphens, numbers)

### Edit Existing Project

1. Hover over project card to reveal edit button (✏)
2. Click edit button - inline form expands
3. Modify fields:
   - **Display Name**: Change visible name
   - **Icon**: Change emoji
   - **Scope**: Toggle scoped/global
   - **Remote Config**: Configure SSH access (optional)
4. Click **"Save"** to apply changes
5. Click **"Cancel"** to discard changes

**Read-Only Fields**:
- Name (immutable after creation)
- Directory (immutable after creation)

### Delete Project

1. Click delete button (🗑) on project card
2. Confirmation dialog appears with project name
3. Click **"Confirm Delete"** to remove
4. Click **"Cancel"** to abort

**Warning**: Projects with worktrees will show warning before deletion.

## Worktree Operations

### Create New Worktree

1. On a main project (not a worktree), click **"New Worktree"**
2. Fill in the form:
   - **Branch Name**: Git branch to create worktree for
   - **Worktree Path**: Directory path for new worktree
   - **Display Name**: Human-readable name
   - **Icon**: Emoji icon (default: 🌿)
3. Click **"Create"**
4. System will:
   - Validate branch exists in parent repo
   - Execute `git worktree add <path> <branch>`
   - Create project JSON config
   - Add worktree to list under parent

**Not Available For**:
- Remote projects (󰒍 indicator)
- Existing worktrees (only main projects can have worktrees)

### Edit Worktree

1. Click edit button (✏️) on worktree card
2. Editable fields:
   - **Display Name**
   - **Icon**
   - **Scope**
3. Read-only fields (shown as labels):
   - **Branch Name**
   - **Worktree Path**
4. Click **"Save"** or **"Cancel"**

### Delete Worktree

1. Click delete button (🗑️) on worktree card
2. Click again to confirm (button changes to ❗)
3. System will:
   - Execute `git worktree remove <path>`
   - Delete project JSON config
   - Remove from list

**Warning**: If Git worktree has uncommitted changes, you may need to use force delete.

## Visual Feedback

### Loading State

When saving, the save button shows a loading spinner and inputs are disabled to prevent double-submit.

### Success Notification

- Green background notification appears
- Auto-dismisses after 3 seconds
- Form closes automatically
- Project list refreshes immediately

### Error Notification

- Red background notification appears
- Stays visible until manually dismissed
- Specific error message shown
- Form stays open for correction

### Inline Validation

- Validation errors appear below affected fields in red italic text
- Save button is disabled when validation errors exist
- Errors update within 300ms of input change

## Keyboard Navigation

| Key | Action |
|-----|--------|
| `Tab` | Move to next form field |
| `Shift+Tab` | Move to previous form field |
| `Enter` | Submit form (when save button focused) |
| `Escape` | Cancel and close form |

## Remote Project Configuration

For projects on remote hosts (via SSH):

1. Click edit on any project
2. Enable **"Remote Access"** toggle
3. Fill in:
   - **Host**: SSH hostname (e.g., `server.tailnet`)
   - **User**: SSH username
   - **Directory**: Absolute path on remote host
   - **Port**: SSH port (default: 22)
4. Save changes

**Note**: Remote projects cannot have local worktrees.

## Troubleshooting

### "Form won't submit"

- Check for validation errors (red text below fields)
- Ensure required fields are filled
- Verify directory path exists

### "Project not appearing in list"

- Wait 500ms for list refresh
- Manually refresh: `Mod+Shift+M` (exit/enter focus mode)
- Check logs: `journalctl --user -u eww-monitoring-panel -f`

### "Conflict detected" warning

- File was modified externally during edit
- Your changes were still saved
- Warning is informational only

### "Backend unavailable" error

- Check PYTHONPATH is correctly set
- Restart monitoring panel: `systemctl --user restart eww-monitoring-panel`

## CLI Equivalents

All UI operations can also be performed via CLI:

```bash
# List projects
i3pm project list

# Create project
i3pm project create my-project --directory /path/to/dir --display-name "My Project"

# Switch to project
i3pm project switch my-project

# Create worktree
i3pm worktree create feature-branch --from-description "New feature"

# Delete worktree
i3pm worktree remove feature-branch
```

## Related Documentation

- [Feature 085 - Monitoring Panel](../085-sway-monitoring-widget/quickstart.md)
- [Feature 094 - Enhanced CRUD Interface](../094-enhance-project-tab/spec.md)
- [i3pm Commands](../../CLAUDE.md#project-management-workflow-i3pm)
