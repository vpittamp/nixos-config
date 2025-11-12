# Quickstart: Interactive Workspace Menu with Keyboard Navigation

**Feature 059** | **Status**: Planning Phase | **Branch**: `059-interactive-workspace-menu`

## Overview

The interactive workspace menu adds arrow key navigation, Enter key workspace switching, and Delete key window closing to the existing Eww workspace preview card (Feature 072). Navigate through workspaces and windows using Up/Down arrows, press Enter to jump to the selected item, and press Delete to close selected windows.

## Quick Keys

| Key Sequence | Action |
|--------------|--------|
| **CapsLock** (M1) / **Ctrl+0** (Hetzner) | Enter workspace mode → See all windows grouped by workspace with selection on first item |
| **Up Arrow** | Move selection up (wraps to last item if at first) |
| **Down Arrow** | Move selection down (wraps to first item if at last) |
| **Enter** | Navigate to selected workspace/window (workspace heading → workspace, window → focus window) |
| **Delete** | Close selected window (no-op on workspace headings) |
| **Type digits** (e.g., `2` then `3`) | Filter to workspace 23 → Selection resets to first item |
| **Escape** | Cancel and close preview card (clear selection) |

## Common Workflows

### Workflow 1: Browse All Windows with Arrow Keys

**Use Case**: "I want to see what windows I have open and navigate through them visually"

**Steps**:
1. Press **CapsLock** (M1) or **Ctrl+0** (Hetzner)
2. Preview card appears showing all workspaces with first item selected (yellow highlight):
   ```
   → WS 1 (3 windows) - HEADLESS-1       ← Selected (yellow)
     • Ghostty
     • Alacritty
     • Code

   WS 3 (2 windows) - HEADLESS-2
     • Firefox
     • Claude (PWA)
   ```
3. Press **Down Arrow** → Selection moves to "Ghostty"
4. Press **Down Arrow** → Selection moves to "Alacritty"
5. Press **Down Arrow** → Selection moves to "Code"
6. Press **Down Arrow** → Selection moves to "WS 3 (2 windows)"
7. Continue pressing **Down** to navigate through all items
8. At last item, press **Down** → Wraps to first item (circular navigation)

**Performance**: <50ms selection update latency per arrow key press

---

### Workflow 2: Navigate to Specific Window

**Use Case**: "I want to jump to my Firefox window on workspace 3"

**Steps**:
1. Press **CapsLock** (M1) or **Ctrl+0** (Hetzner)
2. Press **Down Arrow** repeatedly until "Firefox" is highlighted
3. Press **Enter**
4. Sway switches to workspace 3 AND focuses Firefox window
5. Preview card closes

**Alternative (faster)**:
1. Press **CapsLock**
2. Type **`3`** → Preview filters to workspace 3 only, selection resets to first item
3. Press **Down Arrow** to select Firefox
4. Press **Enter** → Navigate to Firefox

**Performance**: <100ms from Enter press to workspace switch + window focus

---

### Workflow 3: Close Multiple Windows Quickly

**Use Case**: "I want to clean up workspace 5 by closing several windows"

**Steps**:
1. Press **CapsLock**
2. Type **`5`** → Preview filters to workspace 5
3. Press **Down Arrow** to select first window (e.g., "Old Terminal")
4. Press **Delete** → Window closes, preview updates, selection moves to next window
5. Press **Delete** again → Next window closes
6. Continue pressing **Delete** to close more windows
7. Press **Escape** when done → Exit workspace mode

**Performance**: <100ms per window close (if app cooperates), <500ms if app has unsaved changes

**Edge Case - Unsaved Changes**:
- If a window blocks close request (unsaved file in editor), you'll see a notification:
  ```
  ┌────────────────────────────────────────┐
  │ Window Close Blocked                   │
  │ The application may have unsaved       │
  │ changes. Please check the window.      │
  └────────────────────────────────────────┘
  ```
- Window remains in preview list (selection stays on that item)
- You can navigate away with arrow keys or manually save/close the app

---

### Workflow 4: Mix Arrow Navigation with Digit Filtering

**Use Case**: "I want to use digits for quick filtering, then arrows for fine-grained selection"

**Steps**:
1. Press **CapsLock**
2. Type **`2`** → Preview shows all workspaces starting with "2" (WS 2, 20-29)
3. Type **`3`** → Preview filters to workspace 23 only, selection resets to first item
4. Press **Down Arrow** → Select second window in workspace 23
5. Press **Enter** → Navigate to that window

**Performance**: <50ms filter update + selection reset per digit typed

---

## Visual Feedback

### Selection Highlight Styles

**Catppuccin Mocha Theme Colors** (from Feature 057):

```scss
// Selected item (active navigation)
.preview-app.selected {
  background: rgba(249, 226, 175, 0.3);  // Yellow (Catppuccin)
  border: 2px solid rgba(249, 226, 175, 0.8);
  box-shadow: 0 0 8px rgba(249, 226, 175, 0.6);
  transition: all 0.2s ease-out;
}

// Selected workspace heading
.workspace-group-header.selected {
  background: rgba(249, 226, 175, 0.2);
  border-left: 4px solid #f9e2af;  // Solid yellow bar
}

// Selected window
.preview-app.selected .preview-app-name {
  color: #f9e2af;  // Catppuccin yellow
  font-weight: 600;
}

// Selected window icon glow
.preview-app.selected .preview-app-icon {
  -gtk-icon-shadow: 0 0 12px rgba(249, 226, 175, 0.9);
}
```

### Preview Card States

**All Windows View** (no digits typed, first item selected):
```
┌──────────────────────────────────────────────────────────────┐
│ Type workspace number to filter, or :project for project    │
│                                                               │
│ → WS 1 (3 windows) - HEADLESS-1              ← Selected      │
│   • Ghostty                                                   │
│   • Alacritty                                                 │
│   • Code                                                      │
│                                                               │
│   WS 3 (2 windows) - HEADLESS-2                              │
│   • Firefox                                                   │
│   • Claude (PWA)                                              │
└──────────────────────────────────────────────────────────────┘
```

**Filtered Workspace View** (digits typed - "23", selection on first item):
```
┌──────────────────────────────────────────────────────────────┐
│ → WS 23 (2 windows)                         ← Selected       │
│                                                               │
│   • Firefox                                                   │
│   • Ghostty                                                   │
└──────────────────────────────────────────────────────────────┘
```

**Window Selected** (arrow navigation to specific window):
```
┌──────────────────────────────────────────────────────────────┐
│   WS 1 (3 windows) - HEADLESS-1                              │
│   • Ghostty                                                   │
│ → • Alacritty                                ← Selected       │
│   • Code                                                      │
└──────────────────────────────────────────────────────────────┘
```

### Selection State Indicators

| Indicator | Meaning |
|-----------|---------|
| **Yellow highlight** | Currently selected item (can press Enter to navigate, Delete to close) |
| **Blue background** (existing) | Focused window (current workspace) |
| **Dimmed text** (existing) | Unfocused windows |
| **Border glow** | Selected item (subtle animation on selection change) |

---

## Configuration

### Enable/Disable Feature

**Location**: `home-modules/desktop/eww-workspace-bar.nix`

```nix
# Feature 059: Interactive workspace menu with arrow key navigation
interactiveMenu = {
  enable = true;                  # Enable arrow navigation
  circularNavigation = true;      # Wrap around at first/last item
  deleteKeyEnabled = true;        # Allow Delete key to close windows
  selectionTimeout = null;        # No timeout (selection persists)
};
```

### Keybindings

**Location**: `home-modules/desktop/sway-keybindings.nix`

```nix
# Workspace mode keybindings (extend existing mode from Feature 042)
mode "workspace" {
  # Existing digit navigation
  bindsym 0 exec i3pm workspace-mode digit 0
  bindsym 1 exec i3pm workspace-mode digit 1
  # ... digits 2-9 ...

  # NEW: Arrow key navigation (Feature 059)
  bindsym Up exec i3pm workspace-preview nav up
  bindsym Down exec i3pm workspace-preview nav down

  # NEW: Action keys (Feature 059)
  bindsym Return exec i3pm workspace-preview select
  bindsym Delete exec i3pm workspace-preview delete

  # Existing mode exit
  bindsym Escape mode "default"; exec i3pm workspace-mode cancel
}
```

**After editing keybindings**:
```bash
sudo nixos-rebuild switch --flake .#<target>
swaymsg reload  # Reload Sway config
```

### Theme Colors

**Location**: `~/.config/sway/appearance.json` (hot-reloadable)

```json
{
  "preview_card": {
    "selection_background": "rgba(249, 226, 175, 0.3)",
    "selection_border": "rgba(249, 226, 175, 0.8)",
    "selection_glow": "rgba(249, 226, 175, 0.6)",
    "selection_text": "#f9e2af"
  }
}
```

**After editing**:
```bash
swaymsg reload  # Auto-reloads preview card theme
```

---

## Edge Cases

### Typing Digits Resets Selection

**Behavior**: When you type any digit (0-9) in workspace mode, selection resets to the first item in the filtered list.

**Example**:
1. Arrow down to 5th item
2. Type `2` → Preview filters to workspaces starting with "2"
3. Selection jumps back to first item (not 5th)
4. Type `3` → Preview filters to workspace 23
5. Selection resets to first item again

**Rationale**: Digit filtering changes the list contents, so previous selection index may be out of bounds. Resetting to first item provides consistent behavior.

---

### Closing Focused Window

**Behavior**: If you select and close the currently focused window, Sway automatically moves focus to the next window in the workspace (Sway default behavior).

**Example**:
1. On workspace 1 with Firefox focused
2. Enter workspace mode
3. Arrow down to select Firefox
4. Press Delete → Firefox closes
5. Sway auto-focuses Alacritty (next window in workspace 1)
6. Preview updates to remove Firefox from list

**Selection After Close**: Selection moves to the next item in the list (not the newly focused window).

---

### Pressing Enter with No Selection

**Behavior**: If no item is selected (edge case: selection somehow cleared), pressing Enter falls back to Feature 042 digit navigation.

**Example**:
1. Type `23` (workspace digits)
2. Selection cleared by unknown edge case (bug scenario)
3. Press Enter → Navigates to workspace 23 (fallback to accumulated_digits)

**Fallback Logic**: If `selection_index == None` and `accumulated_digits != ""`, use digit navigation. Otherwise, no-op.

---

### Window Close Fails (App Blocks Request)

**Behavior**: If an app blocks the close request (e.g., unsaved file in VS Code), the window does NOT close and you see a notification.

**Example**:
1. Select VS Code window with unsaved file
2. Press Delete
3. After 500ms timeout, notification appears:
   ```
   Window Close Blocked
   The application may have unsaved changes. Please check the window.
   ```
4. Window remains in preview list (selection stays on VS Code)
5. You can navigate away or manually save the file

**Performance**: 500ms timeout (configurable in daemon)

**Error Handling**: Logged as WARNING (not ERROR) - expected behavior

---

### All Windows Closed via Delete Key

**Behavior**: If you close all windows using Delete key, the preview shows an empty state but workspace mode remains active.

**Example**:
1. Enter workspace mode
2. Filter to workspace 5 (2 windows)
3. Delete first window → 1 window remains
4. Delete second window → 0 windows
5. Preview shows:
   ```
   ┌────────────────────────────────────────┐
   │ No windows open in workspace 5         │
   └────────────────────────────────────────┘
   ```
6. Press Escape to exit workspace mode

**No Auto-Exit**: Workspace mode does NOT automatically exit when list becomes empty. User must press Escape.

---

### Arrow Navigation in Project Mode

**Behavior**: Typing `:` switches to project mode. Arrow keys are NOT supported in project mode (Feature 059 scope limitation).

**Example**:
1. Enter workspace mode
2. Type `:` → Switches to project search mode
3. Press Down Arrow → No effect (project mode uses fuzzy text search only)
4. Type `nix` → Fuzzy matches projects
5. Press Enter → Switches to matched project

**Future Enhancement**: Project mode arrow navigation could be added in a separate feature (not in Feature 059 scope).

---

### Rapid Arrow Key Presses (>10/sec)

**Behavior**: Selection updates are debounced to prevent flicker and excessive CPU usage.

**Example**:
1. Hold Down Arrow for 2 seconds (~20 presses)
2. Daemon processes events with <50ms latency each
3. Preview updates smoothly without lag or flicker

**Performance**: <50ms per selection update (no batching needed for 50 items)

---

### Empty Workspace List (No Windows Open)

**Behavior**: If no windows are open across any workspace, the preview shows an empty state and arrow navigation is disabled.

**Example**:
1. Close all windows on all workspaces
2. Enter workspace mode
3. Preview shows:
   ```
   ┌────────────────────────────────────────┐
   │ No windows open                        │
   └────────────────────────────────────────┘
   ```
4. Press Down Arrow → No effect (list is empty, selection remains None)
5. Press Escape to exit

---

## Performance Metrics

| Operation | Target | Typical | Worst Case | Notes |
|-----------|--------|---------|------------|-------|
| Mode entry → Preview visible | <150ms | ~50-80ms | ~120ms | From Feature 072 |
| Arrow key → Selection update | <50ms | ~20-30ms | ~45ms | Includes JSON emission |
| Selection update → Visual feedback | <30ms | ~15-20ms | ~25ms | GTK CSS re-render |
| **Total: Arrow key → Visual highlight** | **<80ms** | **~35-50ms** | **~70ms** | End-to-end latency |
| Enter key → Workspace switch | <100ms | ~50-70ms | ~90ms | Sway IPC command |
| Delete key → Window close (success) | <100ms | ~60-80ms | ~95ms | Cooperative close |
| Delete key → Window close (timeout) | <500ms | ~500ms | ~500ms | App blocks close |
| Digit typed → Filter update | <50ms | ~25-35ms | ~45ms | Includes selection reset |
| Escape → Preview hidden | <50ms | ~15-25ms | ~40ms | Mode exit |

---

## Troubleshooting

### Preview card doesn't appear

**Check daemon status**:
```bash
systemctl --user status i3-project-event-listener
systemctl --user status workspace-preview-daemon
```

**Restart daemons**:
```bash
systemctl --user restart i3-project-event-listener
systemctl --user restart workspace-preview-daemon
```

**Check logs**:
```bash
journalctl --user -u workspace-preview-daemon -f
```

---

### Arrow keys don't move selection

**Verify keybindings loaded**:
```bash
swaymsg -t get_binding_modes | jq '.modes.workspace'
```

**Expected output** (should include Up/Down bindings):
```json
{
  "Up": "exec i3pm workspace-preview nav up",
  "Down": "exec i3pm workspace-preview nav down",
  ...
}
```

**Reload Sway config**:
```bash
swaymsg reload
```

---

### Selection highlight doesn't appear

**Check Eww CSS loaded**:
```bash
cat ~/.config/eww/eww.scss | grep ".preview-app.selected"
```

**Expected**: Should show yellow highlight styles

**Restart Eww**:
```bash
eww kill
eww daemon  # Restarts in background
```

---

### Delete key doesn't close window

**Check daemon logs for errors**:
```bash
journalctl --user -u workspace-preview-daemon | grep -i "delete"
```

**Verify Sway IPC works**:
```bash
# Get a window container ID
swaymsg -t get_tree | jq '.. | select(.type? == "con" and .name? != null) | {id, name}' | head -5

# Try manual kill (replace 123 with actual ID)
swaymsg '[con_id=123] kill'
```

---

### Selection moves but CSS doesn't update

**Check Eww deflisten connection**:
```bash
ps aux | grep "eww.*deflisten.*workspace_preview"
```

**Restart workspace panel**:
```bash
systemctl --user restart sway-workspace-panel
```

---

### Close timeout notification appears for all windows

**Possible causes**:
1. Daemon timeout set too low (should be 500ms)
2. Sway IPC slow (check system load)
3. Windows actually have unsaved changes

**Check timeout setting**:
```bash
grep -r "timeout_ms" ~/.config/i3/workspace-preview-daemon
```

**Expected**: `timeout_ms=500`

---

## CLI Commands

### Check preview daemon status
```bash
systemctl --user status workspace-preview-daemon
```

### Monitor preview daemon events
```bash
journalctl --user -u workspace-preview-daemon -f
```

### Test Sway IPC kill command
```bash
# Get window IDs
swaymsg -t get_tree | jq '.. | select(.type? == "con") | {id, name}' | head

# Kill window by ID (replace 12345)
swaymsg '[con_id=12345] kill'
```

### Manually trigger workspace mode
```bash
i3pm workspace-mode digit 5    # Type digit "5"
i3pm workspace-preview nav down # Arrow down
i3pm workspace-preview select   # Press Enter
i3pm workspace-preview delete   # Press Delete
i3pm workspace-mode cancel      # Press Escape
```

---

## Integration with Existing Features

### Feature 042: Event-Driven Workspace Mode

**Preserved Behavior**:
- CapsLock/Ctrl+0 enters workspace mode ✅
- Digit accumulation (e.g., "2" → "23") ✅
- Enter executes navigation ✅
- Escape cancels without navigation ✅

**Enhanced Behavior**:
- Mode entry shows preview with selection on first item (new)
- Arrow keys navigate through items (new)
- Enter key respects selection if present, falls back to digits otherwise (new)

---

### Feature 057: Unified Bar System

**Preserved Behavior**:
- Catppuccin Mocha theme colors ✅
- Preview card rendering ✅
- Hot-reloadable appearance.json ✅

**Enhanced Behavior**:
- `.preview-app.selected` CSS class for arrow navigation highlight (new)
- Selection state in JSON output (new field)

---

### Feature 072: Unified Workspace Switcher

**Preserved Behavior**:
- All-windows preview on mode entry ✅
- Digit filtering to specific workspace ✅
- Project mode with `:` prefix ✅

**Enhanced Behavior**:
- Selection state tracked across all navigation modes (new)
- Arrow navigation in all_windows mode (new)
- Delete key closes selected windows (new)

---

## Related Documentation

- **Feature 042**: Event-Driven Workspace Mode (`specs/042-event-driven-workspace-mode/quickstart.md`)
- **Feature 057**: Unified Bar System (`specs/057-unified-bar-system/quickstart.md`)
- **Feature 072**: Unified Workspace Switcher (`specs/072-unified-workspace-switcher/quickstart.md`)
- **Data Model**: `specs/059-interactive-workspace-menu/data-model.md`
- **Research**: `specs/059-interactive-workspace-menu/research.md`
- **Contracts**: `specs/059-interactive-workspace-menu/contracts/`

---

## Implementation Status

| User Story | Priority | Status |
|------------|----------|--------|
| **US1**: Navigate window list with arrow keys | P1 | 📝 Planning |
| **US2**: Navigate to selected workspace | P2 | 📝 Planning |
| **US3**: Close selected window | P3 | 📝 Planning |
| **US4**: Visual selection feedback | P2 | 📝 Planning |

**Next Steps**: Run `/speckit.tasks` to generate implementation tasks.

---

**Last Updated**: 2025-11-12
**Maintainer**: Claude Code
**Status**: Planning Phase Complete
