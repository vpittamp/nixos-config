# TUI Screens Contract: i3pm

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20 | **Phase**: Phase 1 Design
**UX Design**: [../UNIFIED_UX_DESIGN.md](../UNIFIED_UX_DESIGN.md)

## Overview

This document defines all TUI screens, navigation patterns, keyboard shortcuts, and widget contracts for the `i3pm` interactive interface built with Textual framework.

## Screen Navigation

### Navigation Graph

```
┌─────────────────────────────────────────────────────────────┐
│                     Project Browser                          │
│                    (Default/Home Screen)                     │
└────┬──────────┬──────────┬──────────┬───────────────────────┘
     │          │          │          │
     │ [e]dit   │ [m]onitor│ [l]ayout │ [n]ew (wizard)
     ▼          ▼          ▼          ▼
  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────────┐
  │ Editor │ │Monitor │ │Layout  │ │   Wizard   │
  │ Screen │ │Screen  │ │Manager │ │   (4 steps)│
  └────┬───┘ └────┬───┘ └────┬───┘ └─────┬──────┘
       │          │          │            │
       │ [Esc]    │ [Esc]    │ [Esc]      │ [Esc]/Finish
       └──────────┴──────────┴────────────┘
                  │
                  ▼
          Project Browser
```

### Screen Stack Pattern

```python
# Navigate forward
app.push_screen(EditorScreen(project))

# Navigate back
screen.dismiss(result_data)  # Returns to previous screen with data
```

---

## Screen Specifications

### 1. Project Browser Screen

**Purpose**: Default screen for browsing, searching, and selecting projects.

**Layout**:
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ i3pm - Project Manager                              Active: nixos ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ Search: _                                                          ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ NAME      DIRECTORY        APPS  LAYOUTS  MODIFIED               ┃
┃ ❄️ nixos   /etc/nixos       2     3        2h ago          *     ┃
┃   stacks   ~/code/stacks    3     1        1d ago                ┃
┃   personal ~/personal       1     0        5d ago                ┃
┃                                                                    ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [↑↓] Select  [Enter] Switch  [e] Edit  [l] Layouts  [m] Monitor  ┃
┃ [n] New  [d] Delete  [/] Search  [s] Sort  [q] Quit               ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Widgets**:
- `Input#search` - Search/filter input
- `DataTable#projects` - Project list table
- `Static#status` - Status bar (active project indicator)
- `Footer` - Keyboard shortcuts

**Keyboard Shortcuts**:

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate project list |
| `Enter` | Switch to selected project |
| `e` | Edit selected project |
| `l` | Open layout manager for project |
| `m` | Open monitor dashboard |
| `n` | Create new project (wizard) |
| `d` | Delete selected project |
| `/` | Focus search input |
| `Esc` | Clear search |
| `s` | Toggle sort (name/modified/directory) |
| `r` | Reverse sort order |
| `q` | Quit application |
| `Ctrl+C` | Quit application |

**Reactive Attributes**:
```python
class ProjectBrowserScreen(Screen):
    # Auto-updates when daemon state changes
    active_project: reactive[Optional[str]] = reactive(None)
    filter_text: reactive[str] = reactive("")
    sort_by: reactive[str] = reactive("modified")

    def watch_filter_text(self, old: str, new: str) -> None:
        """Re-filter table when search changes."""
        self.refresh_table()
```

**Data Loading**:
- On mount: Load all projects from `~/.config/i3/projects/`
- On focus: Refresh active project from daemon
- Refresh interval: Every 5 seconds (check for external changes)

---

### 2. Project Editor Screen

**Purpose**: Edit project configuration with real-time validation.

**Layout**:
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Edit Project: nixos                                        [✓ Saved] ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                        ┃
┃ Basic Information                                                     ┃
┃   Name:         [nixos                     ]                         ┃
┃   Display Name: [NixOS Configuration       ]                         ┃
┃   Icon:         [❄️                          ]                         ┃
┃   Directory:    [/etc/nixos                ] 📁                       ┃
┃                                                                        ┃
┃ Scoped Applications                                                   ┃
┃   [x] Ghostty                                                         ┃
┃   [x] Code                                                            ┃
┃   [ ] firefox                                                         ┃
┃   [ ] Google-chrome                                                   ┃
┃   [+] Add custom class...                                             ┃
┃                                                                        ┃
┃ Workspace Preferences                                                 ┃
┃   WS 1: [primary   ▼]                                                 ┃
┃   WS 2: [secondary ▼]                                                 ┃
┃   WS 3: [—         ▼]                                                 ┃
┃                                                                        ┃
┃ Auto-Launch (2 apps)                                                  ┃
┃   1. ghostty (workspace 1)                    [Edit] [Delete]        ┃
┃   2. code /etc/nixos (workspace 2)            [Edit] [Delete]        ┃
┃   [+ Add Application]                                                 ┃
┃                                                                        ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Tab] Next Field  [Shift+Tab] Previous  [Ctrl+S] Save  [Esc] Cancel ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Widgets**:
- `Input` fields for name, display name, icon, directory
- `Checkbox` list for scoped applications
- `Select` dropdowns for workspace preferences
- `DataTable` for auto-launch apps
- `Button` widgets for save/cancel

**Keyboard Shortcuts**:

| Key | Action |
|-----|--------|
| `Tab` | Next field |
| `Shift+Tab` | Previous field |
| `Ctrl+S` | Save changes |
| `Esc` | Cancel (discard changes) |
| `Space` | Toggle checkbox |

**Validation**:
- Real-time validation on field change
- Display errors inline (red text below field)
- Disable save button if validation fails

**Validation Rules**:
```python
def validate_name(self, value: str) -> str:
    """Validate project name."""
    if not value.replace("-", "").replace("_", "").isalnum():
        raise ValueError("Name must be alphanumeric (with - or _)")
    if Path(f"~/.config/i3/projects/{value}.json").expanduser().exists():
        raise ValueError(f"Project '{value}' already exists")
    return value

def validate_directory(self, value: str) -> Path:
    """Validate directory exists."""
    path = Path(value).expanduser()
    if not path.exists():
        raise ValueError(f"Directory does not exist: {value}")
    return path
```

**Unsaved Changes**:
- Track `unsaved_changes: bool` reactive attribute
- Show confirmation dialog on Esc if unsaved
- Mark screen as "dirty" in status bar

---

### 3. Monitor Dashboard Screen

**Purpose**: Real-time monitoring of daemon, projects, and windows.

**Layout** (Tabbed Interface):
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ i3pm - Monitor                                   Daemon: Running ✓ ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Live] [Events] [History] [Tree]                                   ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                      ┃
┃ Active Project: nixos                                               ┃
┃   Directory: /etc/nixos                                             ┃
┃   Uptime: 2h 34m                                                    ┃
┃                                                                      ┃
┃ Tracked Windows (5)                                                 ┃
┃   ID      CLASS     WORKSPACE  TITLE                               ┃
┃   12345   Ghostty   1          nvim flake.nix                      ┃
┃   12346   Code      2          /etc/nixos - VSCode                 ┃
┃   12347   Ghostty   1          lazygit                             ┃
┃   12348   Code      2          tasks.md                            ┃
┃   12349   Ghostty   3          htop                                ┃
┃                                                                      ┃
┃ Statistics                                                          ┃
┃   Total Windows: 12                                                 ┃
┃   Total Events: 1,234                                               ┃
┃   Event Rate: 2.3/s                                                 ┃
┃                                                                      ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Tab] Switch Tab  [r] Refresh  [Esc] Back                          ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Tabs**:
1. **Live** - Current state (active project, tracked windows, statistics)
2. **Events** - Event stream (real-time daemon events)
3. **History** - Historical events (last 100)
4. **Tree** - i3 window tree inspector

**Keyboard Shortcuts**:

| Key | Action |
|-----|--------|
| `Tab` | Switch to next tab |
| `Shift+Tab` | Switch to previous tab |
| `r` | Force refresh |
| `Esc` | Return to browser |
| `q` | Return to browser |

**Refresh Interval**: 1 second (configurable with `--refresh`)

**Data Sources**:
- Daemon IPC: `/get_status`, `/get_events`
- i3 IPC: `GET_TREE`, `GET_WORKSPACES`

---

### 4. Layout Manager Screen

**Purpose**: Save, restore, and manage project layouts.

**Layout**:
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Layout Manager: nixos                                              ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                      ┃
┃ Saved Layouts (3)                                                   ┃
┃   LAYOUT      WINDOWS  WORKSPACES  SAVED                           ┃
┃ → default     5        1, 2        2025-10-20 14:30                ┃
┃   debugging   8        1, 2, 3     2025-10-18 10:15                ┃
┃   testing     3        1           2025-10-17 09:00                ┃
┃                                                                      ┃
┃ Current Layout Preview                                              ┃
┃   Workspace 1 (primary)                                             ┃
┃     • Ghostty: nvim flake.nix                                       ┃
┃     • Ghostty: lazygit                                              ┃
┃   Workspace 2 (secondary)                                           ┃
┃     • Code: /etc/nixos - VSCode                                     ┃
┃     • Code: tasks.md                                                ┃
┃   Workspace 3 (primary)                                             ┃
┃     • Ghostty: htop                                                 ┃
┃                                                                      ┃
┃ Actions:                                                            ┃
┃   [Save Current] [Restore Selected] [Delete Selected] [Export]     ┃
┃                                                                      ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [↑↓] Select  [s] Save  [r] Restore  [d] Delete  [Esc] Back        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Widgets**:
- `DataTable#layouts` - Saved layouts list
- `RichLog#preview` - Current layout preview
- `Button` widgets for actions

**Keyboard Shortcuts**:

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate layout list |
| `s` | Save current layout (prompt for name) |
| `r` | Restore selected layout |
| `d` | Delete selected layout |
| `e` | Export selected layout |
| `i` | Import layout from file |
| `Enter` | Restore selected layout |
| `Esc` | Return to browser |

**Save Layout Dialog**:
```
┌────────────────────────────────────┐
│ Save Layout                         │
├────────────────────────────────────┤
│ Layout Name: [________]            │
│                                     │
│ Capture:                            │
│   [x] Workspace 1 (2 windows)      │
│   [x] Workspace 2 (3 windows)      │
│   [x] Workspace 3 (1 window)       │
│                                     │
│   [Save] [Cancel]                  │
└────────────────────────────────────┘
```

**Restore Confirmation**:
```
┌────────────────────────────────────┐
│ Restore Layout: default             │
├────────────────────────────────────┤
│ This will launch 5 applications.   │
│                                     │
│ [x] Close existing project windows │
│                                     │
│   [Restore] [Cancel]               │
└────────────────────────────────────┘
```

---

### 5. Project Wizard Screen (4 Steps)

**Purpose**: Guided project creation with validation.

**Step 1: Basic Information**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 1 of 4: Basic Information                    ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                      ┃
┃ Project Name                                                        ┃
┃   [nixos__________]                                                 ┃
┃   Alphanumeric with - or _ only                                     ┃
┃                                                                      ┃
┃ Display Name (optional)                                             ┃
┃   [NixOS Configuration]                                             ┃
┃                                                                      ┃
┃ Icon (optional emoji)                                               ┃
┃   [❄️]                                                                ┃
┃                                                                      ┃
┃ Project Directory                                                   ┃
┃   [/etc/nixos_____] 📁                                              ┃
┃   ✓ Directory exists                                                ┃
┃                                                                      ┃
┃                                                                      ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Tab] Next Field  [Enter] Next Step  [Esc] Cancel                  ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Step 2: Application Selection**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 2 of 4: Application Selection                ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                      ┃
┃ Select applications to scope to this project:                       ┃
┃                                                                      ┃
┃ Terminal Applications                                               ┃
┃   [x] Ghostty                                                       ┃
┃   [ ] Alacritty                                                     ┃
┃   [ ] Kitty                                                         ┃
┃                                                                      ┃
┃ Editors                                                             ┃
┃   [x] Code (Visual Studio Code)                                     ┃
┃   [ ] neovide                                                       ┃
┃                                                                      ┃
┃ Browsers                                                            ┃
┃   [ ] firefox                                                       ┃
┃   [ ] Google-chrome                                                 ┃
┃                                                                      ┃
┃ Custom Class                                                        ┃
┃   [Add custom...___]                                                ┃
┃                                                                      ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Space] Toggle  [↑↓] Navigate  [Enter] Next  [Esc] Back            ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Step 3: Auto-Launch Configuration**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 3 of 4: Auto-Launch (Optional)               ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                      ┃
┃ Configure applications to launch automatically:                     ┃
┃                                                                      ┃
┃ Application 1                                                       ┃
┃   Command:   [ghostty________]                                      ┃
┃   Workspace: [1_]  (1-10, or blank for any)                        ┃
┃                                                                      ┃
┃ Application 2                                                       ┃
┃   Command:   [code /etc/nixos_]                                     ┃
┃   Workspace: [2_]                                                   ┃
┃                                                                      ┃
┃ [+ Add Another Application]                                         ┃
┃ [- Remove Last Application]                                         ┃
┃                                                                      ┃
┃ [Skip this step]                                                    ┃
┃                                                                      ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Tab] Next Field  [Enter] Next  [s] Skip  [Esc] Back               ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Step 4: Review & Create**
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Create Project - Step 4 of 4: Review                               ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                      ┃
┃ Project: nixos                                                      ┃
┃   Display Name: NixOS Configuration                                ┃
┃   Icon: ❄️                                                           ┃
┃   Directory: /etc/nixos                                             ┃
┃                                                                      ┃
┃ Scoped Applications (2):                                            ┃
┃   • Ghostty                                                         ┃
┃   • Code                                                            ┃
┃                                                                      ┃
┃ Auto-Launch (2):                                                    ┃
┃   1. ghostty (workspace 1)                                          ┃
┃   2. code /etc/nixos (workspace 2)                                  ┃
┃                                                                      ┃
┃ Configuration will be saved to:                                     ┃
┃   ~/.config/i3/projects/nixos.json                                  ┃
┃                                                                      ┃
┃   [Create Project] [Edit] [Cancel]                                 ┃
┃                                                                      ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ [Enter] Create  [e] Edit  [Esc] Cancel                             ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Wizard Navigation**:

| Key | Action |
|-----|--------|
| `Enter` | Next step (if validation passes) |
| `Esc` | Previous step (or cancel on step 1) |
| `Ctrl+Enter` | Skip to review step |
| `e` | Edit specific step from review |

**Validation**:
- Each step validates before allowing navigation to next
- Show inline errors below invalid fields
- Disable "Next" button if validation fails

**Completion**:
- On "Create Project" button click: save to disk, return to browser
- Show success notification: "✓ Created project: nixos"
- Auto-select newly created project in browser

---

## Common UI Patterns

### Confirmation Dialogs

```python
@dataclass
class ConfirmDialog(Screen):
    """Standard confirmation dialog."""

    title: str
    message: str
    confirm_label: str = "Confirm"
    cancel_label: str = "Cancel"

    def on_mount(self) -> None:
        """Build dialog."""
        # Show modal overlay with buttons

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button click."""
        if event.button.id == "confirm":
            self.dismiss(True)
        else:
            self.dismiss(False)
```

**Usage**:
```python
confirmed = await self.app.push_screen_wait(
    ConfirmDialog(
        title="Delete Project",
        message=f"Delete project '{name}'? This will also delete 2 saved layouts.",
        confirm_label="Delete",
        cancel_label="Cancel"
    )
)

if confirmed:
    # Delete project
```

### Loading Indicators

```python
class LayoutManagerScreen(Screen):
    """Layout manager with async loading."""

    async def restore_layout(self, layout_name: str) -> None:
        """Restore layout with loading indicator."""
        # Show loading overlay
        self.show_loading("Restoring layout...")

        # Run async operation
        result = await self._restore_layout_async(layout_name)

        # Hide loading
        self.hide_loading()

        # Show result
        if result.success:
            self.notify(f"✓ Layout restored: {layout_name}")
        else:
            self.notify(f"✗ Failed to restore layout: {result.error}", severity="error")
```

### Notifications

```python
# Success notification (green, 3 seconds)
self.notify("✓ Project saved", severity="information")

# Error notification (red, persistent until dismissed)
self.notify("✗ Directory does not exist", severity="error", timeout=None)

# Warning notification (yellow, 5 seconds)
self.notify("⚠ Layout has unsaved changes", severity="warning", timeout=5)
```

---

## Performance Targets

| Operation | Target | Implementation |
|-----------|--------|----------------|
| Keyboard response | <50ms | Textual reactive updates |
| Screen transition | <100ms | Screen stack navigation |
| Data refresh | <200ms | Async i3/daemon queries |
| Table filter | <50ms | In-memory filtering |
| Validation | <100ms | Synchronous validation |

---

## Accessibility

- **Keyboard-Only Navigation**: All features accessible via keyboard
- **Screen Reader Support**: Use Textual's semantic widgets
- **Color Contrast**: Follow Textual's default theme (accessible contrast ratios)
- **Focus Indicators**: Clear visual focus indicators on all widgets

---

## Testing Strategy

### Snapshot Tests

```python
# tests/test_tui/test_browser.py
async def test_browser_screen_render(snap_compare):
    """Test project browser renders correctly."""
    app = I3PMApp()

    async with app.run_test() as pilot:
        assert await snap_compare(app, "browser_initial.svg")
```

### Integration Tests

```python
# tests/test_tui/test_wizard.py
@pytest.mark.asyncio
async def test_wizard_complete_flow():
    """Test full wizard flow."""
    app = I3PMApp()

    async with app.run_test() as pilot:
        # Open wizard
        await pilot.press("n")

        # Step 1: Basic info
        await pilot.press(*"nixos")
        await pilot.press("tab")
        await pilot.press(*"/etc/nixos")
        await pilot.press("enter")

        # ... continue through steps

        # Verify project created
        assert Path("~/.config/i3/projects/nixos.json").expanduser().exists()
```

---

## Summary

**Total Screens**: 5 (Browser, Editor, Monitor, Layout Manager, Wizard)
**Total Keyboard Shortcuts**: 50+ across all screens
**Navigation Pattern**: Screen stack with dismiss/callback
**Refresh Strategy**: Reactive attributes + async workers
**Performance**: All targets <200ms

**Next Steps**:
1. Create daemon IPC contract
2. Create config schema
3. Implement TUI screens in `tui/screens/`
