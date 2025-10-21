# TUI Wizard Interaction Contract

**Branch**: `020-update-our-spec` | **Date**: 2025-10-21 | **Plan**: [../plan.md](../plan.md)

## Overview

This document specifies the interactive behavior of the classification wizard TUI, including keyboard bindings, visual feedback, and state transitions.

---

## Screen Layout

```
┌─ Classification Wizard ─────────────────────────────────────────────────────────┐
│                                                                                  │
│  Filter: [All ▼]  Sort: [Name ▼]  Selected: 0/52  Changes: 0                    │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │ Name                  Class          Scope         Confidence  Suggestion  │ │
│  ├────────────────────────────────────────────────────────────────────────────┤ │
│  │ Visual Studio Code    Code           scoped        -           -           │ │
│  │ Firefox               firefox        global        -           -           │ │
│  │ YouTube PWA           pwa-youtube    unclassified  95%         global      │ │
│  │ Spotify PWA           pwa-spotify    unclassified  95%         global      │ │
│  │ Ghostty Terminal      Ghostty        unclassified  90%         scoped      │ │
│  │ Neovim                nvim           unclassified  85%         scoped      │ │
│  │ Slack                 Slack          unclassified  70%         global      │ │
│  │ ...                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌─ Details ───────────────────────────────────────────────────────────────────┐ │
│  │ Application: YouTube PWA                                                    │ │
│  │ WM_CLASS:    pwa-youtube                                                    │ │
│  │ Desktop:     /usr/share/applications/youtube-pwa.desktop                    │ │
│  │                                                                             │ │
│  │ Suggestion:  global (95% confidence)                                        │ │
│  │ Reasoning:   Matched pattern rule "glob:pwa-*" with priority 100           │ │
│  │              PWAs are typically global apps accessible across all projects  │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  [s] Scoped  [g] Global  [u] Unclassify  [Space] Select  [A] Accept All        │
│  [R] Reject All  [p] Create Pattern  [Enter] Save  [Esc] Cancel                │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Keyboard Bindings

### Navigation

| Key | Action | Behavior |
|-----|--------|----------|
| `↑` / `k` | Previous row | Move selection up one row, update detail panel |
| `↓` / `j` | Next row | Move selection down one row, update detail panel |
| `Page Up` | Previous page | Scroll up one page (~10 rows) |
| `Page Down` | Next page | Scroll down one page (~10 rows) |
| `Home` | First row | Jump to first row in filtered list |
| `End` | Last row | Jump to last row in filtered list |
| `Tab` | Next widget | Cycle focus: table → filter dropdown → sort dropdown → table |
| `Shift+Tab` | Previous widget | Reverse cycle focus |

**Visual Feedback**:
- Cursor row highlighted with background color
- Detail panel updates in <50ms (SC-026)
- Smooth scrolling (no flicker)

### Classification Actions

| Key | Action | Behavior |
|-----|--------|----------|
| `s` | Classify as Scoped | Mark selected/multi-selected apps as scoped, update Scope column |
| `g` | Classify as Global | Mark selected/multi-selected apps as global, update Scope column |
| `u` | Unclassify | Remove classification from selected/multi-selected apps |
| `Space` | Toggle Selection | Add/remove app from multi-selection set, show checkmark in table |
| `A` | Accept All Suggestions | Accept all suggestions with confidence >= threshold (default 90%) |
| `R` | Reject All Suggestions | Clear all suggestions, mark as unclassified |

**Visual Feedback**:
- Scope column updates immediately (<50ms)
- Changes counter increments
- Selected rows show checkmark icon (☑)
- Undo notification appears briefly: "✓ Classified 3 apps as scoped (Ctrl+Z to undo)"

### Filtering & Sorting

| Key | Action | Behavior |
|-----|--------|----------|
| `f` | Focus Filter | Move focus to filter dropdown, open dropdown menu |
| `o` | Focus Sort | Move focus to sort dropdown, open dropdown menu |
| `Enter` (in dropdown) | Apply Selection | Apply filter/sort, update table, close dropdown |
| `Esc` (in dropdown) | Cancel | Close dropdown without changing filter/sort |

**Filter Options**:
- `All` (default): Show all apps
- `Unclassified`: Show only apps with scope=unclassified
- `Scoped`: Show only apps with scope=scoped
- `Global`: Show only apps with scope=global

**Sort Options**:
- `Name` (default): Sort by app_name alphabetically
- `Class`: Sort by window_class alphabetically
- `Status`: Sort by scope (unclassified → scoped → global)
- `Confidence`: Sort by suggestion_confidence (descending)

### Advanced Actions

| Key | Action | Behavior |
|-----|--------|----------|
| `p` | Create Pattern | Open pattern creation dialog for selected app's window class |
| `d` | Detect WM_CLASS | Launch Xvfb detection for selected app (if undetected) |
| `i` | Inspect Window | Launch window inspector for selected app (if running) |
| `Ctrl+Z` | Undo | Restore previous state from undo stack |
| `Ctrl+Y` | Redo | Restore next state from redo stack (if available) |

**Pattern Creation Dialog**:
```
┌─ Create Pattern Rule ─────────────────────────────────────────┐
│                                                                │
│  Window Class: pwa-youtube                                     │
│                                                                │
│  Pattern:     [glob:pwa-*               ]                      │
│  Scope:       [Global ▼]                                       │
│  Priority:    [100                      ]                      │
│  Description: [All PWAs are global apps ]                      │
│                                                                │
│  Preview: This pattern will match:                             │
│    ✓ pwa-youtube                                               │
│    ✓ pwa-spotify                                               │
│    ✓ pwa-slack                                                 │
│    ✓ pwa-chatgpt                                               │
│    (4 more apps in current list)                               │
│                                                                │
│  [Enter] Create  [Esc] Cancel                                  │
└────────────────────────────────────────────────────────────────┘
```

### Session Actions

| Key | Action | Behavior |
|-----|--------|----------|
| `Enter` | Save & Exit | Write app-classes.json, reload daemon, exit wizard |
| `Esc` | Cancel | Exit wizard without saving (prompt if changes_made=True) |
| `Ctrl+C` | Force Exit | Immediate exit without saving (no prompt) |
| `?` | Help | Show keyboard shortcuts overlay |

**Save Confirmation** (if changes_made=True):
```
┌─ Save Changes? ─────────────────────────────────────┐
│                                                      │
│  You have 12 unsaved classifications.                │
│                                                      │
│  [S] Save & Exit  [D] Discard & Exit  [C] Cancel    │
└──────────────────────────────────────────────────────┘
```

---

## State Transitions

### Initial State

```yaml
wizard_state:
  apps: [52 discovered apps]
  selected_indices: []
  filter_status: "all"
  sort_by: "name"
  undo_stack: []
  changes_made: false

table_view:
  cursor_row: 0
  scroll_offset: 0
  visible_rows: 10
```

### Classification State Machine

```
┌──────────────┐
│ Unclassified │
└──────┬───────┘
       │
       ├─── [s] press ───> Scoped
       │
       ├─── [g] press ───> Global
       │
       └─── [A] press ───> (Accept Suggestion) ───> Scoped/Global
                                │
                                └─ if suggestion_confidence >= 90%

┌────────┐                     ┌────────┐
│ Scoped │ <─── [s] press ──── │ Global │
└────┬───┘                     └───┬────┘
     │                             │
     └───── [g] press ─────────────┘
     │                             │
     └───── [u] press ──────> Unclassified
```

### Multi-Selection Workflow

```
1. User: Press Space on row 3
   wizard_state.selected_indices = {3}
   table_view: Show checkmark on row 3

2. User: Press Down arrow (↓)
   table_view.cursor_row = 4
   wizard_state.selected_indices = {3}  # Unchanged

3. User: Press Space on row 4
   wizard_state.selected_indices = {3, 4}
   table_view: Show checkmarks on rows 3, 4

4. User: Press 'g' (classify as global)
   wizard_state.apps[3].current_scope = "global"
   wizard_state.apps[4].current_scope = "global"
   wizard_state.changes_made = True
   wizard_state.selected_indices = {}  # Clear selection
   table_view: Update Scope column for rows 3, 4
   notification: "✓ Classified 2 apps as global"
```

### Undo/Redo Stack

```
1. User: Classify row 3 as global
   wizard_state.undo_stack.append(snapshot_before_change)
   wizard_state.apps[3].current_scope = "global"

2. User: Press Ctrl+Z
   previous_state = wizard_state.undo_stack.pop()
   wizard_state.redo_stack.append(current_state)
   wizard_state = restore_from(previous_state)
   notification: "↶ Undone: Classify as global"

3. User: Press Ctrl+Y
   next_state = wizard_state.redo_stack.pop()
   wizard_state.undo_stack.append(current_state)
   wizard_state = restore_from(next_state)
   notification: "↷ Redone: Classify as global"
```

---

## Performance Requirements

**FR-109, SC-026**: All TUI operations must complete in <50ms

| Operation | Target Time | Implementation |
|-----------|-------------|----------------|
| Keystroke response | <50ms | Async event handlers, no blocking I/O |
| Detail panel update | <50ms | Reactive data binding (Textual reactive) |
| Filter/sort | <100ms | In-memory sorting, virtualized table |
| Undo/redo | <50ms | Restore from JSON snapshot |
| Pattern creation preview | <200ms | Pattern matching against visible apps only |

**FR-109**: Memory usage <100MB with 1000+ apps

| Component | Memory Budget | Implementation |
|-----------|---------------|----------------|
| App data | ~200KB (1000 apps × 200 bytes) | Dataclass instances |
| Textual framework | ~50MB | Base TUI framework overhead |
| Undo stack | ~10MB (50 snapshots × 200KB) | JSON state snapshots |
| Table rendering | ~5MB | Virtualized (renders ~50 visible rows, not all 1000) |
| **Total** | **~65MB** | Well under 100MB budget ✅ |

---

## Visual Feedback Requirements

**SC-026**: <50ms keyboard response time

**Color Coding**:
- Unclassified: Yellow/amber highlight
- Scoped: Blue highlight
- Global: Green highlight
- Selected: Checkmark icon (☑) prefix

**Confidence Indicators**:
- High (90-100%): Green dot •
- Medium (70-89%): Yellow dot •
- Low (0-69%): Red dot •
- No suggestion: Gray dash -

**Live Counters**:
- Selected: `Selected: 3/52` (updates on Space press)
- Changes: `Changes: 12` (updates on classification action)
- Filter: `Filter: Unclassified (15)` (shows count in parentheses)

---

## Error Handling

**Configuration Write Error**:
```
┌─ Error ──────────────────────────────────────────────┐
│                                                       │
│  Failed to save app-classes.json:                    │
│  Permission denied: /home/user/.config/i3/           │
│                                                       │
│  Remediation:                                         │
│  • Check file permissions: ls -l ~/.config/i3/       │
│  • Create directory: mkdir -p ~/.config/i3/          │
│                                                       │
│  [R] Retry  [C] Cancel                                │
└───────────────────────────────────────────────────────┘
```

**Daemon Reload Error**:
```
┌─ Warning ─────────────────────────────────────────────┐
│                                                        │
│  Configuration saved but daemon reload failed:         │
│  i3-project-event-listener not running                 │
│                                                        │
│  Remediation:                                          │
│  • Start daemon: systemctl --user start \             │
│    i3-project-event-listener                           │
│  • Check status: systemctl --user status \            │
│    i3-project-event-listener                           │
│                                                        │
│  [OK] Continue                                         │
└────────────────────────────────────────────────────────┘
```

**Xvfb Detection Failed** (during 'd' action):
```
┌─ Detection Failed ────────────────────────────────────┐
│                                                        │
│  Xvfb detection failed for Slack:                      │
│  Process timed out after 10 seconds                    │
│                                                        │
│  Suggestions:                                          │
│  • Increase timeout: --timeout=30                      │
│  • Try manual classification instead                   │
│  • Check if app requires display manager               │
│                                                        │
│  [R] Retry  [S] Skip  [C] Cancel                       │
└────────────────────────────────────────────────────────┘
```

---

## Testing Contracts

**pytest-textual Integration**:

```python
async def test_wizard_classify_scoped():
    """Test classifying app as scoped via 's' key."""
    async with WizardApp().run_test() as pilot:
        # Navigate to first unclassified app
        await pilot.press("down", "down", "down")

        # Classify as scoped
        await pilot.press("s")

        # Verify scope column updated
        table = pilot.app.query_one("#app-table", DataTable)
        assert table.get_cell_at((3, 2)) == "scoped"

        # Verify changes counter incremented
        assert pilot.app.wizard_state.changes_made is True

async def test_wizard_multi_select():
    """Test multi-selection workflow."""
    async with WizardApp().run_test() as pilot:
        # Select rows 3 and 4
        await pilot.press("down", "down", "down", "space")  # Row 3
        await pilot.press("down", "space")  # Row 4

        # Classify both as global
        await pilot.press("g")

        # Verify both apps updated
        assert pilot.app.wizard_state.apps[3].current_scope == "global"
        assert pilot.app.wizard_state.apps[4].current_scope == "global"

        # Verify selection cleared
        assert pilot.app.wizard_state.selected_indices == set()

async def test_wizard_undo():
    """Test undo/redo functionality."""
    async with WizardApp().run_test() as pilot:
        # Make a change
        await pilot.press("s")  # Classify first app as scoped

        # Undo
        await pilot.press("ctrl+z")

        # Verify state restored
        assert pilot.app.wizard_state.apps[0].current_scope == "unclassified"

        # Redo
        await pilot.press("ctrl+y")

        # Verify change reapplied
        assert pilot.app.wizard_state.apps[0].current_scope == "scoped"
```

---

## Accessibility

**Keyboard-Only Navigation**: All functionality accessible via keyboard (no mouse required)

**Screen Reader Hints**:
- Table cells: `<app_name>, <window_class>, <scope>, <confidence>% confidence, suggested <suggestion>`
- Buttons: `"Press S for Scoped, G for Global, U for Unclassify"`
- Notifications: `"Classified 3 apps as global, Ctrl Z to undo"`

**High Contrast Mode**: Respect terminal color scheme (no hard-coded colors)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Phase**: 1 (Contracts) - IN PROGRESS
