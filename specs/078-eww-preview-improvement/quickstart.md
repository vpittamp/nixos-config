# Quick Start: Enhanced Project Selection in Eww Preview Dialog

**Feature**: `078-eww-preview-improvement` | **Date**: 2025-11-16

## Overview

Switch between projects instantly using fuzzy search and keyboard navigation. Activate project mode by typing ":", see all your projects with worktree relationships and git status, filter by typing, and switch with Enter.

---

## Basic Usage

### Activate Project Selection

1. Enter workspace mode: **CapsLock** (M1) or **Ctrl+0** (Hetzner)
2. Type **:** to enter project selection mode
3. See your complete project list

### Quick Project Switch (3 keystrokes)

```
CapsLock → : → n → Enter
```
Switches to "nixos" project (prefix match)

```
CapsLock → : → 0 → 7 → 8 → Enter
```
Switches to "078-eww-preview-improvement" (digit prefix)

### Fuzzy Search

Type any characters to filter:

| Input | Matches |
|-------|---------|
| `nix` | nixos, nixos-worktree |
| `078` | 078-eww-preview-improvement |
| `age` | agent-framework |
| `eww` | 078-eww-preview-improvement |
| `dap` | dapr |

Best match is automatically highlighted at the top.

### Keyboard Navigation

| Key | Action |
|-----|--------|
| **↓** / **↑** | Navigate through project list |
| **Enter** | Switch to highlighted project |
| **Escape** | Cancel and close dialog |
| **Backspace** | Remove last typed character |

Arrow navigation wraps around (bottom → top, top → bottom).

---

## Understanding the Project List

### Project Entry Layout

```
🌿  eww preview improvement         2h ago
    worktree ← nixos  ✓ clean
```

**Components**:
- **Icon**: Project emoji (🌿, ❄️, 🌳, etc.)
- **Display Name**: Human-readable name
- **Relative Time**: Last activity (2h ago, 3d ago, 1mo ago)
- **Type Badge**: "worktree" for git worktrees, none for root projects
- **Parent Relationship**: "← nixos" shows parent repository
- **Git Status**: ✓ clean, ✗ dirty, ↑3 ahead, ↓2 behind

### Root vs Worktree Projects

**Root Project** (no worktree badge):
```
❄️  NixOS                           3d ago
    root project
```

**Worktree** (has parent relationship):
```
🌿  eww preview improvement         2h ago
    worktree ← nixos  ✓ clean ↑2
```

Shows: This is a worktree created from "nixos" repository, it's clean (no uncommitted changes), and it's 2 commits ahead of remote.

### Git Status Indicators

| Indicator | Meaning |
|-----------|---------|
| ✓ | Clean - no uncommitted changes |
| ✗ | Dirty - has uncommitted changes |
| ↑N | N commits ahead of remote (needs push) |
| ↓N | N commits behind remote (needs pull) |

### Warning Indicators

| Indicator | Meaning |
|-----------|---------|
| ⚠️ missing | Project directory doesn't exist |
| ⚠️ orphaned | Parent repository was deleted |

---

## Example Workflows

### Workflow 1: Quick Context Switch

**Scenario**: You're in "nixos" project and need to work on agent-framework.

```
CapsLock → : → age → Enter
```
- Shows project list filtered to "agent-framework"
- Automatically highlights best match
- Enter switches project immediately

**Result**: VS Code, terminal, and yazi switch to agent-framework context.

### Workflow 2: Browse All Projects

**Scenario**: Want to see all projects and their status.

```
CapsLock → : → ↓ → ↓ → Enter
```
- Project list shows all 8 projects sorted by recency
- Navigate down to see each project's status
- Enter switches to selected project

### Workflow 3: Find Feature Branch

**Scenario**: Need to switch to feature branch "078-eww-preview-improvement".

```
CapsLock → : → 078 → Enter
```
OR
```
CapsLock → : → eww → Enter
```
- Both patterns find the same project
- Digits and hyphens are searchable
- First match is automatically selected

### Workflow 4: Cancel Operation

**Scenario**: Accidentally entered project mode.

```
CapsLock → : → Escape
```
- Closes project list dialog
- No project switch occurs
- Returns to previous workspace mode view

---

## Advanced Tips

### Efficient Filtering Patterns

1. **Use unique prefixes**: "dap" for "dapr", "age" for "agent-framework"
2. **Use feature numbers**: "078" instead of typing full name
3. **Skip hyphens**: "ewwpreview" matches "eww-preview-improvement"
4. **Word boundaries**: "pre-imp" matches "preview-improvement"

### Visual Cues

- **Yellow highlight**: Currently selected project
- **Match positions**: Characters that matched are underlined
- **Scroll indicator**: Shows position in long lists (50+ projects)
- **Count display**: "3 of 8 projects" shows filter results

### Performance Expectations

- Filter response: <50ms for 100 projects
- Arrow key navigation: <16ms (single frame)
- Project switch: <500ms (daemon processing)
- List rendering: Smooth scroll for 50+ items

---

## Troubleshooting

### Project List Not Showing

1. Verify workspace mode activated:
   ```bash
   i3pm daemon status
   ```

2. Check projects exist:
   ```bash
   ls ~/.config/i3/projects/
   ```

3. Restart workspace-preview-daemon:
   ```bash
   systemctl --user restart sway-workspace-panel
   ```

### Wrong Git Status

Git status is cached from project creation. To refresh:

```bash
# Switch to project directory
cd /home/vpittamp/nixos-078-eww-preview-improvement

# Update project metadata
i3pm project update --git-status
```

### Missing Project Directory

If you see "⚠️ missing" indicator:

1. Project directory was moved or deleted
2. Update project path:
   ```bash
   i3pm project edit <name> --directory /new/path
   ```

3. Or remove stale project:
   ```bash
   i3pm project remove <name>
   ```

### No Projects Found

If list is empty:

1. Create first project:
   ```bash
   i3pm project create --name "myproject" --directory /path/to/project
   ```

2. Or create from git repository:
   ```bash
   i3pm worktree create --from-description "my feature"
   ```

---

## Integration with Other Features

### Works With

- **Feature 042**: Workspace mode activation (CapsLock/Ctrl+0)
- **Feature 072**: All-windows preview (toggle between views)
- **Feature 073**: Keyboard hints (shows available actions)
- **Feature 076**: Mark-based identification (preserves window marks on switch)

### Project Switch Effects

When you switch projects:

1. **Scoped apps** hide (VS Code, terminal, yazi, lazygit)
2. **Global apps** remain visible (Firefox, PWAs)
3. **Environment variables** update (I3PM_PROJECT_NAME, etc.)
4. **Workspace focus** changes to project's primary workspace
5. **Layout restoration** optional (via `i3pm layout restore`)

---

## Quick Reference Card

```
Activate:    CapsLock (M1) / Ctrl+0 (Hetzner)
Project Mode: :
Filter:      Type any characters
Navigate:    ↑ / ↓ arrows
Select:      Enter
Cancel:      Escape
Clear Filter: Backspace (multiple times)

Visual:
🌿 = Worktree
❄️ = Root project
✓  = Git clean
✗  = Git dirty
↑N = N commits ahead
↓N = N commits behind
⚠️  = Warning (missing/orphaned)
```

---

## Next Steps

After mastering basic usage:

1. **Customize project icons**: Edit `~/.config/i3/projects/<name>.json`
2. **Create worktrees**: `i3pm worktree create --from-description "..."`
3. **Save layouts**: `i3pm layout save main` (per-project window arrangements)
4. **Explore diagnostics**: `i3pm diagnose health` for system status
