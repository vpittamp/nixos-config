# Window Inspector - User Guide

**Part of T097: User guide documentation**

The Window Inspector is a real-time TUI for inspecting window properties, classification status, and pattern matches.

## Table of Contents

- [Overview](#overview)
- [Launching the Inspector](#launching-the-inspector)
- [Interface Layout](#interface-layout)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Inspection Modes](#inspection-modes)
- [Classification Actions](#classification-actions)
- [Live Mode](#live-mode)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

### What is the Window Inspector?

The Window Inspector provides a real-time view of:
- Window properties (WM_CLASS, title, workspace, etc.)
- Current classification (scoped, global, unclassified)
- Classification source (explicit list, pattern, or suggestion)
- Pattern matches and reasoning
- i3 metadata (marks, focused status, floating, etc.)

### When to Use It

- **Debugging**: Check why a window isn't classifying correctly
- **Discovery**: Find window class names for new apps
- **Verification**: Confirm classification after changes
- **Learning**: Understand how pattern matching works

## Launching the Inspector

### Click Mode (Default)

Select a window by clicking:

```bash
i3pm app-classes inspect

# Or with the --click flag
i3pm app-classes inspect --click
```

After running, click on any visible window to inspect it.

### Focused Mode

Inspect the currently focused window:

```bash
i3pm app-classes inspect --focused
```

### By Window ID

Inspect a specific window by i3 container ID:

```bash
# Get window ID first
i3pm windows

# Then inspect
i3pm app-classes inspect 94489280512
```

### With Live Mode

Start inspector with live updates enabled:

```bash
i3pm app-classes inspect --focused --live
```

## Interface Layout

The inspector has a 3-panel layout:

```
┌─────────────────────────────────────────────────────────────┐
│ Window Inspector                                            │
├──────────────────────────────┬──────────────────────────────┤
│                              │                              │
│   Window Properties (60%)    │  Classification Status (40%) │
│                              │                              │
│   Property         Value     │  Current: SCOPED             │
│   ─────────────────────────  │  Source: pattern             │
│   Window ID        94489280  │                              │
│   WM_CLASS         Code      │  Suggested: scoped (95%)     │
│   Title            file.py   │  Reasoning: Code editor...   │
│   Workspace        1         │                              │
│   ...                        ├──────────────────────────────┤
│                              │                              │
│                              │  Pattern Matches (40%)       │
│                              │                              │
│                              │  Matching patterns (2):      │
│                              │    • glob:Code*              │
│                              │    • regex:^Code.*$          │
│                              │                              │
├──────────────────────────────┴──────────────────────────────┤
│ Ready • Use keyboard shortcuts to inspect and classify      │
│ s:Scoped g:Global u:Unclassify p:Pattern r:Refresh l:Live  │
└─────────────────────────────────────────────────────────────┘
```

### Left Panel: Window Properties

Shows all window metadata:
- **Window ID**: i3 container ID
- **WM_CLASS**: Window class name
- **Instance**: WM_INSTANCE value
- **Title**: Window title
- **Workspace**: Current workspace number
- **Output**: Monitor/output name
- **Focused**: Is this window focused?
- **Floating**: Is window floating?
- **Fullscreen**: Is window fullscreen?
- **i3 Marks**: Any i3 marks on the window

### Right Top: Classification Status

Shows classification information:
- **Current**: Current classification (scoped/global/unclassified)
- **Source**: How it was classified (explicit/pattern/suggestion)
- **Suggested**: ML suggestion if available
- **Confidence**: Suggestion confidence percentage
- **Reasoning**: Explanation of classification

### Right Bottom: Pattern Matches

Shows matching pattern rules:
- List of all patterns that match this window class
- If no patterns match, shows suggestions for creating patterns

## Keyboard Shortcuts

### Classification

| Key | Action | Description |
|-----|--------|-------------|
| `s` | Mark as Scoped | Add to scoped_classes list |
| `g` | Mark as Global | Add to global_classes list |
| `u` | Unclassify | Remove from all lists |
| `p` | Create Pattern | Create pattern rule dialog |

### Navigation

| Key | Action | Description |
|-----|--------|-------------|
| `r` | Refresh | Reload window properties |
| `l` | Toggle Live Mode | Enable/disable auto-updates |
| `c` | Copy Class | Copy WM_CLASS to clipboard |
| `Esc` | Exit | Close inspector |

### Mouse

- Scroll within panels
- Click to focus panel (for future multi-window support)

## Inspection Modes

### Click Mode

**Best for**: Identifying unknown windows

**Usage**:
```bash
i3pm app-classes inspect
# Click on the window you want to inspect
```

**Advantages**:
- Visual window selection
- No need to know window class
- Works with any visible window

**Limitations**:
- Requires X11 (uses xdotool)
- Must have a visible window to click

### Focused Mode

**Best for**: Quick checks of current window

**Usage**:
```bash
i3pm app-classes inspect --focused
```

**Advantages**:
- Instant inspection (no clicking)
- Works in scripts
- Great for debugging focus issues

**Limitations**:
- Only inspects focused window
- Can't inspect windows on other workspaces

### By ID Mode

**Best for**: Scripting and automation

**Usage**:
```bash
# Get window ID
WINDOW_ID=$(i3pm windows --json | jq '.[0].id')

# Inspect by ID
i3pm app-classes inspect "$WINDOW_ID"
```

**Advantages**:
- Precise targeting
- Scriptable
- Works with hidden windows

**Limitations**:
- Need to know window ID
- More complex to use

## Classification Actions

### Mark as Scoped (s)

Adds window class to `scoped_classes` list.

**Effect**: Windows of this class will be:
- Hidden when switching to other projects
- Shown when switching back to their project
- Automatically marked with project context

**Example**:
1. Inspect a Code window
2. Press `s`
3. Result: `Code` added to scoped_classes
4. All VS Code windows now project-specific

### Mark as Global (g)

Adds window class to `global_classes` list.

**Effect**: Windows of this class will be:
- Visible in all projects
- Never hidden during project switches
- Accessible from any project context

**Example**:
1. Inspect a Firefox window
2. Press `g`
3. Result: `firefox` added to global_classes
4. Browser visible in all projects

### Unclassify (u)

Removes window class from all lists.

**Effect**: Windows of this class will:
- Return to unclassified status
- Not be hidden or shown during switches
- Remain visible but without project context

**Use case**: Undo accidental classification

### Create Pattern (p)

Opens dialog to create a pattern rule.

**Workflow**:
1. Press `p` in inspector
2. Pattern dialog appears with suggestions:
   - `glob:ClassName*`
   - `regex:^ClassName$`
   - Literal `ClassName`
3. Choose or edit pattern
4. Select scope (scoped/global)
5. Pattern created and applied

**Example**:
1. Inspect `pwa-youtube`
2. Press `p`
3. Use suggested `glob:pwa-*`
4. Choose `global`
5. All PWAs now classified as global

## Live Mode

### What is Live Mode?

Live mode subscribes to i3 events and updates properties in real-time as they change.

### Enabling Live Mode

```bash
# Start with live mode
i3pm app-classes inspect --focused --live

# Or toggle within inspector
# Press 'l' to enable/disable
```

### What Gets Updated?

- ✅ Window title (when it changes)
- ✅ i3 marks (when added/removed)
- ✅ Focused status (when focus changes)
- ✅ Workspace (when moved)

**Note**: WM_CLASS doesn't change once a window is created.

### Visual Feedback

Changed properties flash yellow for 200ms to show updates.

### Status Bar Indicator

```
● Live Mode ON • Properties update automatically
```

vs

```
○ Live Mode OFF • Press 'l' to enable live updates
```

### Use Cases

1. **Debugging window title changes**: Watch a browser tab title update
2. **Verifying mark assignment**: See marks appear as daemon assigns them
3. **Monitoring focus**: Track which window is focused
4. **Workspace tracking**: Watch window move between workspaces

## Examples

### Example 1: Find Unknown Window Class

**Scenario**: New app installed, need to classify it.

```bash
# Launch inspector
i3pm app-classes inspect

# Click on the unknown window
# (Inspector opens showing all properties)

# Check WM_CLASS field
# Example: "new-app-v2"

# Press 's' to mark as scoped
# Or 'g' to mark as global
```

### Example 2: Verify Pattern Matching

**Scenario**: Created pattern `glob:pwa-*`, need to verify it works.

```bash
# Inspect a PWA
i3pm app-classes inspect --focused

# Check "Pattern Matches" panel
# Should show: "Matching patterns (1): • glob:pwa-*"

# Check "Classification Status"
# Should show: "Source: pattern (glob:pwa-*)"
```

### Example 3: Debug Misclassified Window

**Scenario**: Window is classified wrong, find out why.

```bash
# Inspect the window
i3pm app-classes inspect --click
# (Click on misclassified window)

# Check Classification Status panel:
# - Current: Shows actual classification
# - Source: Shows why (explicit/pattern/suggestion)
# - Suggested: Shows what it should be

# If source is "pattern", check Pattern Matches
# If wrong pattern is matching, adjust priorities

# Fix by:
# 1. Press 'u' to unclassify
# 2. Press 's' or 'g' for correct classification
# OR
# 3. Adjust pattern priorities externally
```

### Example 4: Monitor Window Changes

**Scenario**: App changes title based on content, want to monitor.

```bash
# Launch with live mode
i3pm app-classes inspect --focused --live

# Do something that changes window title
# (e.g., open different file in editor)

# Watch "Title" field update in real-time
# (flashes yellow when changed)

# Switch to different window
# Watch "Focused" field change
```

### Example 5: Copy Class for Scripting

**Scenario**: Need window class for a script.

```bash
# Inspect window
i3pm app-classes inspect --focused

# Press 'c' to copy WM_CLASS
# Paste into script: Ctrl+V
```

## Troubleshooting

### Inspector Won't Launch

**Symptom**: `i3pm app-classes inspect` fails with error.

**Solutions**:

1. **Check xdotool installation** (for click mode):
   ```bash
   which xdotool
   # Should output: /nix/store/.../bin/xdotool
   ```

2. **Use focused mode** instead:
   ```bash
   i3pm app-classes inspect --focused
   ```

3. **Check i3 connection**:
   ```bash
   i3-msg -t get_tree > /dev/null
   # Should succeed with no output
   ```

### Click Selection Doesn't Work

**Symptom**: Clicking window doesn't open inspector.

**Solutions**:

1. **Use focused mode**:
   ```bash
   i3pm app-classes inspect --focused
   ```

2. **Try by-ID mode**:
   ```bash
   i3pm windows  # Get ID
   i3pm app-classes inspect <window-id>
   ```

3. **Check xdotool**:
   ```bash
   xdotool selectwindow  # Should let you click a window
   ```

### Properties Not Updating in Live Mode

**Symptom**: Live mode enabled but changes not showing.

**Solutions**:

1. **Press 'r' to force refresh**:
   Manually refresh if auto-update seems stuck

2. **Toggle live mode**:
   ```
   Press 'l' twice (off then on)
   ```

3. **Check daemon is running**:
   ```bash
   systemctl --user status i3-project-event-listener
   ```

4. **Restart inspector**:
   Exit and relaunch with `--live` flag

### Classification Action Doesn't Apply

**Symptom**: Press 's' or 'g' but classification doesn't change.

**Solutions**:

1. **Check daemon reloaded**:
   ```bash
   systemctl --user restart i3-project-event-listener
   ```

2. **Verify config file**:
   ```bash
   cat ~/.config/i3/app-classes.json
   # Check that class was added
   ```

3. **Reload project**:
   ```bash
   i3pm switch <current-project>
   ```

### Wrong Pattern Matching

**Symptom**: Pattern Matches panel shows unexpected pattern.

**Solutions**:

1. **Check pattern priority**:
   ```bash
   i3pm app-classes list-patterns
   # Higher priority patterns match first
   ```

2. **Test pattern separately**:
   ```bash
   i3pm app-classes test-pattern "pattern" "WM_CLASS"
   ```

3. **Remove conflicting pattern**:
   ```bash
   i3pm app-classes remove-pattern "wrong-pattern"
   ```

## Best Practices

### 1. Use Inspector Before Creating Patterns

Always inspect first to see actual window class:

```bash
# Don't guess the class name
# Instead:
i3pm app-classes inspect --click
# Then create pattern based on actual WM_CLASS
```

### 2. Verify After Classification

After classifying, verify it worked:

```bash
i3pm app-classes check <class-name>
```

### 3. Use Live Mode for Debugging

When troubleshooting, enable live mode:

```bash
i3pm app-classes inspect --focused --live
```

### 4. Copy Classes for Scripts

Use 'c' to copy exact class names for automation:

```bash
# In inspector: press 'c'
# In script: Ctrl+V to paste exact name
```

## Related Guides

- [Pattern Rules](USER_GUIDE_PATTERN_RULES.md) - Creating pattern rules
- [Classification Wizard](USER_GUIDE_WIZARD.md) - Bulk classification
- [Xvfb Detection](USER_GUIDE_XVFB.md) - Detecting window classes

---

**Last updated**: 2025-10-21 (T097 implementation)
