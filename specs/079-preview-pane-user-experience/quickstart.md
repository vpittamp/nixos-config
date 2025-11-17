# Quickstart: Preview Pane User Experience

**Feature Branch**: `079-preview-pane-user-experience`
**Date**: 2025-11-16

## Overview

This feature enhances the preview pane user experience for git worktree management with arrow key navigation, numeric prefix filtering, visual hierarchy display, and cross-component integration.

## Key Features

1. **Arrow Key Navigation** - Navigate project list with Up/Down arrows
2. **Backspace Exit** - Exit project mode by deleting ":"
3. **Numeric Prefix Filtering** - Type ":79" to find "079-*" branches
4. **Worktree Hierarchy** - Visual parent-child grouping
5. **Top Bar Enhancement** - Prominent project label with icon
6. **Environment Variables** - Worktree metadata injection
7. **Notification Actions** - Click to navigate to source window

## Usage

### Project Selection

```bash
# Enter workspace mode
<CapsLock>  # M1
<Ctrl+0>    # Hetzner

# Enter project selection mode
:

# Navigate with arrow keys
<Down>      # Next project
<Up>        # Previous project

# Filter by branch number
:79         # Shows 079-* branches
:078        # Shows 078-* branches

# Select project
<Enter>     # Switch to highlighted project

# Cancel
<Escape>    # Exit without selecting
<Backspace> # Delete chars, empty exits mode
```

### Visual Indicators

**Project List Entry**:
```
079 - Preview Pane UX     [selected]
├─ branch icon
├─ branch number prefix
├─ human-readable name
└─ git status (if dirty: ●)
```

**Hierarchy Display**:
```
nixos                     [folder icon]
  ├─ 078 - Eww Preview    [branch icon]
  └─ 079 - Preview Pane   [branch icon] ●
dotfiles                  [folder icon]
```

**Top Bar Label**:
```
[ 079 - Preview Pane UX]  # With accent background
```

### Worktree Commands

```bash
# List all worktrees
i3pm worktree list

# JSON output
[
  {
    "branch": "079-preview-pane-user-experience",
    "path": "/home/vpittamp/nixos-079-...",
    "parent_repo": "nixos",
    "git_status": { "dirty": false, "ahead": 2, "behind": 0 }
  }
]

# Table output
i3pm worktree list --format table

BRANCH       PATH              PARENT   STATUS
079-preview  /home/vpittamp/.. nixos    +2 ↑
078-eww      /home/vpittamp/.. nixos    clean
```

### Environment Variables

When launching apps in worktree context:

```bash
# Existing variables
I3PM_APP_NAME="vscode"
I3PM_PROJECT_NAME="nixos-079-preview-pane"
I3PM_PROJECT_DIR="/home/vpittamp/nixos-079-..."

# NEW variables (Feature 079)
I3PM_IS_WORKTREE="true"
I3PM_PARENT_PROJECT="nixos"
I3PM_BRANCH_TYPE="feature"

# Check in running app
env | grep I3PM_
```

### Notification Navigation

When Claude Code completes:

1. Notification appears with source window info:
   ```
   Claude Code Complete
   Task finished

   Source: nixos:0
   ```

2. Click "Return to Window" button
3. System focuses terminal and selects tmux window

## Configuration

### Keyboard Shortcuts

Already configured in Sway keybindings (no changes needed):

```nix
# home-modules/desktop/sway.nix
bindsym Down exec i3pm-workspace-mode nav down
bindsym Up exec i3pm-workspace-mode nav up
bindsym BackSpace exec i3pm-workspace-mode backspace
```

### Top Bar Styling

The enhanced project label uses Catppuccin Mocha theme:

```scss
.project-label {
  background-color: #fab387;  // Peach accent
  color: #1e1e2e;             // Base dark
  padding: 4px 12px;
  border-radius: 6px;
  font-weight: bold;
}
```

## Troubleshooting

### Arrow Keys Not Working

```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Check event delivery
journalctl --user -u i3-project-event-listener -f | grep "nav"

# Verify mode
i3pm workspace-mode state
# Should show: mode=project_list
```

### Backspace Not Exiting Mode

```bash
# Check accumulated chars
i3pm workspace-mode state
# accumulated_chars should be empty after backspace

# Verify event emission
journalctl --user -u sway-workspace-panel -f | grep "exit_mode"
```

### Branch Numbers Not Displaying

```bash
# Check project JSON structure
cat ~/.config/i3/projects/*.json | jq '.worktree.branch'

# Verify regex extraction
python3 -c "
import re
branch = '079-preview-pane-user-experience'
match = re.match(r'^(\d+)-', branch)
print(match.group(1) if match else 'No match')
"
# Output: 079
```

### Top Bar Not Updating

```bash
# Restart top bar service
systemctl --user restart eww-top-bar

# Check active project script
~/.config/eww-top-bar/scripts/active-project.py

# Verify eww variable
eww state | grep active_project
```

### Notification Actions Not Working

```bash
# Test notify-send actions
notify-send -w -A "test=Test" "Title" "Body"
# Click button, should output "test"

# Check tmux session
tmux display-message -p "#{session_name}:#{window_index}"
# Output: nixos:0
```

## Testing

### Unit Tests

```bash
# Arrow key navigation
pytest tests/079-preview-pane-user-experience/test_arrow_navigation.py

# Numeric prefix filtering
pytest tests/079-preview-pane-user-experience/test_numeric_prefix_filter.py

# All tests
pytest tests/079-preview-pane-user-experience/
```

### Integration Tests

```bash
# Project selection workflow
sway-test run tests/sway-tests/079-project-selection.json

# Worktree list command
i3pm worktree list | jq .
```

### Manual Testing Checklist

- [ ] Arrow Down moves selection to next project
- [ ] Arrow Up moves selection to previous project
- [ ] Selection wraps at boundaries (circular)
- [ ] Typing ":79" filters to "079-*" branches
- [ ] Backspace removes filter characters
- [ ] Backspace on ":" exits to workspace mode
- [ ] Enter switches to selected project
- [ ] Branch numbers display in project list
- [ ] Worktrees appear nested under parent
- [ ] Top bar shows branch number + name
- [ ] Top bar has accent color background
- [ ] Environment variables include I3PM_IS_WORKTREE
- [ ] Notification includes tmux session:window
- [ ] Clicking notification focuses correct window

## Performance Expectations

| Operation | Target | Measurement |
|-----------|--------|-------------|
| Arrow key response | <50ms | Key press to visual update |
| Numeric filter | <100ms | Input to sorted results |
| Project switch | <500ms | Selection to focus change |
| Top bar update | <500ms | Switch to label change |
| Notification click | <500ms | Click to window focus |

## Related Features

- **Feature 078**: Enhanced project selection with fuzzy matching
- **Feature 060**: Eww top bar implementation
- **Feature 057**: Unified bar system theming
- **Feature 042**: Event-driven workspace mode navigation

## Architecture

```
User Input (Arrow/Backspace)
        ↓
Sway Keybinding (sway.nix)
        ↓
i3pm-workspace-mode.sh (JSON-RPC)
        ↓
workspace_mode.py (State Management)
        ↓
Event Broadcast (project_mode.nav)
        ↓
workspace-preview-daemon (Event Router)
        ↓
NavigationHandler (Mode Dispatch)
        ↓
FilterState (Navigation Logic)
        ↓
Eww Variable Update
        ↓
Project List Widget (Visual Update)
```

## Summary

This feature transforms project selection from a search-only interface to a fully navigable, hierarchical view with deterministic filtering. Users can quickly find projects by branch number, navigate with familiar arrow key patterns, and receive contextual feedback through enhanced visual indicators across all Eww components.
