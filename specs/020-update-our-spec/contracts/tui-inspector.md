# TUI Inspector Interaction Contract

**Branch**: `020-update-our-spec` | **Date**: 2025-10-21 | **Plan**: [../plan.md](../plan.md)

## Overview

This document specifies the interactive behavior of the window inspector TUI, including window selection modes, property display, live updates, and direct classification actions.

---

## Screen Layout

```
┌─ Window Inspector ──────────────────────────────────────────────────────────────┐
│                                                                                  │
│  Window: nvim /etc/nixos/configuration.nix                                       │
│  Press 'r' to refresh | Press 'l' to toggle live mode | Press '?' for help      │
│                                                                                  │
│  ┌─ Window Properties ─────────────────────────────────────────────────────────┐ │
│  │ Property          Value                                                     │ │
│  ├─────────────────────────────────────────────────────────────────────────────┤ │
│  │ Window ID (con)   94489280512                                               │ │
│  │ WM_CLASS          Ghostty                                                   │ │
│  │ WM_INSTANCE       ghostty                                                   │ │
│  │ Title             nvim /etc/nixos/configuration.nix                         │ │
│  │ Workspace         1                                                         │ │
│  │ Output            eDP-1 (laptop)                                            │ │
│  │ i3 Marks          [nixos]                                                   │ │
│  │ Floating          No                                                        │ │
│  │ Fullscreen        No                                                        │ │
│  │ Focused           Yes                                                       │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌─ Classification Status ─────────────────────────────────────────────────────┐ │
│  │ Current:     scoped                                                         │ │
│  │ Source:      explicit (defined in app-classes.json)                         │ │
│  │ Suggested:   scoped (90% confidence)                                        │ │
│  │                                                                             │ │
│  │ Reasoning:                                                                  │ │
│  │ Terminal emulator - project-scoped by default.                              │ │
│  │ Currently marked with project 'nixos' indicating active project context.    │ │
│  │ Explicit classification in scoped_classes list.                             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌─ Pattern Matches ───────────────────────────────────────────────────────────┐ │
│  │ No pattern rules match this window class.                                   │ │
│  │                                                                             │ │
│  │ Potential patterns:                                                         │ │
│  │   • glob:Ghost* (would match)                                               │ │
│  │   • regex:^Ghostty$ (would match)                                           │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  [s] Mark Scoped  [g] Mark Global  [p] Create Pattern  [r] Refresh             │
│  [l] Live Mode: OFF  [c] Copy Class  [Esc] Exit                                │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Window Selection Modes

### Mode 1: Click Selection (Default)

**Launch**: `i3pm app-classes inspect --click`

**Behavior**:
1. Cursor changes to crosshair (xdotool selectwindow)
2. User clicks any window
3. Inspector launches with selected window properties
4. Live mode disabled by default

**Visual Feedback**:
```
┌─ Select Window ─────────────────────────────┐
│                                              │
│  Click any window to inspect its properties  │
│                                              │
│  Press Escape to cancel                      │
└──────────────────────────────────────────────┘

[Crosshair cursor appears, user clicks window]

[Inspector screen loads with window properties]
```

### Mode 2: Focused Window

**Launch**: `i3pm app-classes inspect --focused`

**Behavior**:
1. Query i3 for currently focused window (GET_TREE → find_focused)
2. Inspector launches immediately with focused window properties
3. Live mode enabled by default (updates as focus changes)

**Visual Feedback**:
```
Inspecting focused window: Visual Studio Code
[Inspector screen loads immediately]
```

### Mode 3: By Window ID

**Launch**: `i3pm app-classes inspect 94489280512`

**Behavior**:
1. Look up window by i3 container ID (con_id)
2. Inspector launches with specified window properties
3. Live mode disabled by default (static inspection)

**Visual Feedback**:
```
Inspecting window ID: 94489280512
[Inspector screen loads with window properties]
```

---

## Keyboard Bindings

### Navigation

| Key | Action | Behavior |
|-----|--------|----------|
| `↑` / `k` | Previous row | Scroll property table up |
| `↓` / `j` | Next row | Scroll property table down |
| `Page Up` | Previous page | Scroll up one page |
| `Page Down` | Next page | Scroll down one page |
| `Home` | First row | Jump to first property |
| `End` | Last row | Jump to last property |
| `Tab` | Next section | Cycle focus: Properties → Classification → Patterns → Actions |

### Classification Actions

| Key | Action | Behavior |
|-----|--------|----------|
| `s` | Mark as Scoped | Add window class to scoped_classes, reload daemon |
| `g` | Mark as Global | Add window class to global_classes, reload daemon |
| `u` | Unclassify | Remove window class from app-classes.json, reload daemon |
| `p` | Create Pattern | Open pattern creation dialog with current window class pre-filled |

**Visual Feedback** (after classification):
```
✓ Classified "Ghostty" as scoped

Configuration updated: ~/.config/i3/app-classes.json
Daemon reloaded: i3-project-event-listener (PID 12345)

[Classification Status section updates to show new source]
```

### Inspection Actions

| Key | Action | Behavior |
|-----|--------|----------|
| `r` | Refresh | Re-query i3 for updated window properties (manual refresh) |
| `l` | Toggle Live Mode | Enable/disable automatic updates via i3 event subscriptions |
| `c` | Copy Class | Copy WM_CLASS to clipboard (xclip integration) |
| `w` | Switch Window | Return to window selection (click mode) |

**Live Mode Toggle**:
```
[Press 'l']

Live mode: ON
Subscribed to i3 events: window::title, window::mark, window::move

[Window title changes in real-time]

Window: nvim /etc/nixos/flake.nix  ← Updated automatically
```

### Session Actions

| Key | Action | Behavior |
|-----|--------|----------|
| `Esc` | Exit | Close inspector, return to terminal |
| `Ctrl+C` | Force Exit | Immediate exit (even from live mode) |
| `?` | Help | Show keyboard shortcuts overlay |

---

## Live Mode Behavior

**FR-120**: Subscribe to i3 events and update display in real-time

### Event Subscriptions

When live mode enabled:
```python
i3.on(Event.WINDOW_TITLE, on_window_title_change)
i3.on(Event.WINDOW_MARK, on_window_mark_change)
i3.on(Event.WINDOW_MOVE, on_window_move_change)
i3.on(Event.WINDOW_FOCUS, on_window_focus_change)
```

### Update Behavior

| Event | Property Updated | Visual Feedback |
|-------|------------------|-----------------|
| `window::title` | Title field | Highlight field briefly (200ms yellow flash) |
| `window::mark` | i3 Marks field | Highlight field, update Classification reasoning |
| `window::move` | Workspace, Output | Highlight fields, update workspace/output values |
| `window::focus` | Focused field | Update Yes/No value |

**Performance** (SC-037): Property display in <100ms live mode

```python
async def on_window_title_change(i3, event):
    if event.container.id == inspector.window_id:
        # Update property display in <100ms
        inspector.update_property("Title", event.container.name)
        await inspector.flash_highlight("Title")  # 200ms yellow flash
```

### Live Mode Indicator

```
[Live mode OFF]
[l] Live Mode: OFF  ← Gray, dim

[Live mode ON]
[l] Live Mode: ON   ← Green, animated dot • pulsing
```

---

## Property Display Format

### Standard Properties

| Property | i3 IPC Source | Display Format |
|----------|---------------|----------------|
| Window ID | `container.id` | `94489280512` (decimal) |
| WM_CLASS | `container.window_class` | `Ghostty` (or `None` if unavailable) |
| WM_INSTANCE | `container.window_instance` | `ghostty` (or `None` if unavailable) |
| Title | `container.name` | Full window title (truncated if >80 chars) |
| Workspace | `container.workspace().name` | `1` (workspace number/name) |
| Output | `container.workspace().ipc_data['output']` | `eDP-1 (laptop)` (output name + alias) |
| i3 Marks | `container.marks` | `[nixos, urgent]` (list of marks) |
| Floating | `container.floating` | `Yes` / `No` |
| Fullscreen | `container.fullscreen_mode` | `Yes` / `No` |
| Focused | `container.focused` | `Yes` / `No` |

### Classification Properties

| Property | Source | Display Format |
|----------|--------|----------------|
| Current | Determined by classification logic | `scoped`, `global`, or `unclassified` |
| Source | How classification determined | `explicit`, `pattern: <pattern>`, `heuristic`, or `-` |
| Suggested | Suggestion algorithm | `scoped (90%)`, `global (85%)`, or `-` |
| Reasoning | Classification explanation | Multi-line text explanation |

**Example Reasoning**:
```
Terminal emulator - project-scoped by default.
Currently marked with project 'nixos' indicating active project context.
Explicit classification in scoped_classes list.
```

### Pattern Matches

Shows all pattern rules that match current window class:

```
Pattern Matches (2):

Pattern              Scope    Priority  Description
──────────────────  ───────  ────────  ────────────────────────
glob:Ghost*          scoped   50        Ghostty terminal variants
regex:^[A-Z][a-z]+$  scoped   10        Capitalized single words

No matches: This window does not match any patterns.

Potential patterns: (suggestions)
  • glob:Ghost* (would match)
  • regex:^Ghostty$ (would match)
```

---

## Pattern Creation Dialog

**Launched by**: Press 'p' in inspector

```
┌─ Create Pattern Rule ─────────────────────────────────────────┐
│                                                                │
│  Current Window Class: Ghostty                                 │
│                                                                │
│  Pattern:     [glob:Ghostty            ]                       │
│  Scope:       [Scoped ▼]                                       │
│  Priority:    [50                      ]                       │
│  Description: [Ghostty terminal        ]                       │
│                                                                │
│  Preview:                                                      │
│    ✓ Matches current window: Ghostty                           │
│    ✓ Would classify as: scoped                                 │
│                                                                │
│  Test against other windows:                                   │
│    ✓ Ghostty (this window)                                     │
│    ✗ firefox                                                   │
│    ✗ Code                                                      │
│    ✗ pwa-youtube                                               │
│                                                                │
│  [Enter] Create  [Esc] Cancel                                  │
└────────────────────────────────────────────────────────────────┘
```

**Validation**:
- Pattern syntax validated in real-time
- Preview shows if pattern matches current window
- Test results show matches against all known window classes
- Duplicate pattern detection (same raw pattern already exists)

---

## Error Handling

### Window Not Found

```
┌─ Error ───────────────────────────────────────────────┐
│                                                        │
│  Window not found: 94489280512                         │
│                                                        │
│  Possible reasons:                                     │
│  • Window was closed                                   │
│  • Invalid window ID                                   │
│  • i3 IPC connection error                             │
│                                                        │
│  Remediation:                                          │
│  • Use --click mode to select a visible window         │
│  • Use --focused mode to inspect focused window        │
│  • Check i3 connection: i3-msg -t get_tree             │
│                                                        │
│  [R] Retry  [W] Select Another Window  [C] Cancel      │
└────────────────────────────────────────────────────────┘
```

### i3 IPC Connection Error

```
┌─ Error ───────────────────────────────────────────────┐
│                                                        │
│  Failed to connect to i3 IPC socket:                   │
│  Connection refused                                    │
│                                                        │
│  Remediation:                                          │
│  • Ensure i3 window manager is running                 │
│  • Check I3SOCK environment variable                   │
│  • Verify socket permissions: ls -l $I3SOCK            │
│                                                        │
│  [R] Retry  [C] Cancel                                 │
└────────────────────────────────────────────────────────┘
```

### Classification Error

```
┌─ Error ───────────────────────────────────────────────┐
│                                                        │
│  Failed to save classification:                        │
│  Permission denied: ~/.config/i3/app-classes.json      │
│                                                        │
│  Remediation:                                          │
│  • Check file permissions:                             │
│    ls -l ~/.config/i3/app-classes.json                 │
│  • Create directory if missing:                        │
│    mkdir -p ~/.config/i3/                              │
│  • Fix permissions:                                    │
│    chmod 644 ~/.config/i3/app-classes.json             │
│                                                        │
│  [R] Retry  [C] Cancel                                 │
└────────────────────────────────────────────────────────┘
```

---

## Performance Requirements

**SC-037**: Property display in <100ms live mode

| Operation | Target Time | Implementation |
|-----------|-------------|----------------|
| Window selection | <200ms | xdotool selectwindow (external binary) |
| Property query | <100ms | Single i3 GET_TREE call, cached result |
| Live update | <100ms | i3 event subscription (push-based, not polling) |
| Classification action | <200ms | Write config + daemon reload |
| Pattern creation preview | <200ms | Pattern matching against known classes |

**Memory Usage**: <50MB (single window inspection, no bulk data)

---

## Testing Contracts

**pytest-textual Integration**:

```python
async def test_inspector_click_mode():
    """Test click mode window selection."""
    # Mock xdotool selectwindow to return known window ID
    with patch('subprocess.run') as mock_run:
        mock_run.return_value = CompletedProcess(
            args=['xdotool', 'selectwindow'],
            returncode=0,
            stdout='94489280512'
        )

        async with InspectorApp().run_test() as pilot:
            # Verify window properties displayed
            assert pilot.app.window_id == 94489280512
            assert pilot.app.query_one("#window-class").renderable == "Ghostty"

async def test_inspector_classify_scoped():
    """Test classifying window as scoped via 's' key."""
    async with InspectorApp(window_id=94489280512).run_test() as pilot:
        # Press 's' to classify as scoped
        await pilot.press("s")

        # Verify configuration updated
        config = load_app_classes()
        assert "Ghostty" in config["scoped_classes"]

        # Verify classification status updated
        assert pilot.app.query_one("#current-scope").renderable == "scoped"

async def test_inspector_live_mode():
    """Test live mode event subscriptions."""
    async with InspectorApp(window_id=94489280512).run_test() as pilot:
        # Enable live mode
        await pilot.press("l")
        assert pilot.app.live_mode is True

        # Simulate i3 window title change event
        event = MagicMock()
        event.container.id = 94489280512
        event.container.name = "nvim /etc/nixos/flake.nix"

        await pilot.app.on_window_title_change(None, event)

        # Verify title updated
        assert pilot.app.query_one("#window-title").renderable == "nvim /etc/nixos/flake.nix"
```

---

## Accessibility

**Keyboard-Only Navigation**: All functionality accessible via keyboard (no mouse except initial window selection in click mode)

**Screen Reader Hints**:
- Property table: `"Window ID: 94489280512, WM_CLASS: Ghostty, Title: nvim configuration.nix"`
- Buttons: `"Press S to mark as scoped, G to mark as global, P to create pattern"`
- Live mode: `"Live mode enabled, properties will update automatically"`

**High Contrast Mode**: Respect terminal color scheme (no hard-coded colors)

---

## i3 Keybinding Example

**User Story 4**: "press Win+I, click the window"

```i3config
# Add to ~/.config/i3/config
bindsym $mod+i exec --no-startup-id i3pm app-classes inspect --click
bindsym $mod+Shift+i exec --no-startup-id i3pm app-classes inspect --focused
```

After pressing Win+I:
1. Cursor changes to crosshair
2. User clicks any window
3. Inspector launches with window properties
4. User can classify (s/g), create pattern (p), or copy class (c)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Phase**: 1 (Contracts) - COMPLETE
