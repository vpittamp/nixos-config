# Unified i3 Project Management UX Design

**Feature**: 019-re-explore-and
**Created**: 2025-10-20
**Status**: Design Proposal

## Executive Summary

This document proposes a unified Terminal User Interface (TUI) that integrates project management, monitoring, and testing into a single cohesive tool: `i3-project` (or `i3pm` for short). The tool provides both **interactive TUI mode** and **CLI command mode** to serve different workflows.

### Current State Analysis

**Existing Tools**:
1. **i3-project-monitor** - Read-only monitoring (live, events, history, tree, diagnose modes) using Rich library
2. **i3-project-test** - Automated testing scenarios and validation
3. **i3-project-{switch,list,current,create}** - Individual CLI commands for CRUD operations
4. **i3-project-daemon-{status,events}** - Daemon inspection tools

**Pain Points**:
- **Fragmented UX**: 10+ separate commands with inconsistent interfaces
- **Manual JSON editing**: Project configuration requires editing `~/.config/i3/projects/{name}.json`
- **No guided workflows**: Creating project with auto-launch requires understanding JSON schema
- **Discovery problem**: New users don't know which command to use for what
- **Monitoring vs Management separation**: Can't edit while monitoring

### Proposed Solution: Unified `i3-project` Tool

**Design Philosophy**:
- **Single entry point**: One command (`i3-project` or `i3pm`) for all operations
- **Context-aware**: Interactive TUI when no args, CLI mode with args
- **Integrated monitoring**: See real-time state while making changes
- **Guided workflows**: Wizards for common tasks (create project, configure auto-launch)
- **Visual feedback**: Rich tables, progress bars, syntax highlighting for configs
- **Backward compatible**: Preserve existing CLI commands as aliases/symlinks

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  i3-project (or i3pm) - Unified Entry Point                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Mode Detection:                                                │
│  - No args → Interactive TUI                                    │
│  - With args → CLI command mode                                 │
│                                                                  │
└────────┬───────────────────────────────────────────┬───────────┘
         │                                            │
         ▼                                            ▼
┌────────────────────────────┐      ┌────────────────────────────┐
│  Interactive TUI Mode      │      │  CLI Command Mode          │
│  (Textual framework)       │      │  (argparse + rich output)  │
├────────────────────────────┤      ├────────────────────────────┤
│                            │      │                            │
│  Screens:                  │      │  Commands:                 │
│  1. Project Browser        │      │  - i3pm list               │
│  2. Project Editor         │      │  - i3pm create <name>      │
│  3. Monitor Dashboard      │      │  - i3pm edit <name>        │
│  4. Event Stream           │      │  - i3pm delete <name>      │
│  5. Configuration Wizard   │      │  - i3pm switch <name>      │
│  6. Layout Manager         │      │  - i3pm save-layout        │
│                            │      │  - i3pm restore-layout     │
└────────────────────────────┘      │  - i3pm monitor [mode]     │
                                    │  - i3pm test [scenario]    │
                                    └────────────────────────────┘
                  │
                  ▼
    ┌──────────────────────────────────┐
    │  Shared Core Library             │
    ├──────────────────────────────────┤
    │  - Project CRUD operations       │
    │  - Daemon IPC client             │
    │  - i3 IPC client (queries)       │
    │  - Config validation             │
    │  - Layout serialization          │
    │  - Window tracking models        │
    └──────────────────────────────────┘
```

---

## Interactive TUI Mode Design

### Framework Choice: **Textual**

**Why Textual over Rich alone?**
- Textual is built on Rich (we already use it) but adds interactivity
- Better than alternatives:
  - `curses` - Too low-level, painful API
  - `urwid` - Older, less intuitive
  - `prompt_toolkit` - Great for prompts, but Textual better for full TUI apps
  - `py-cui` - Less mature
- Textual provides:
  - Reactive widgets (auto-update on data changes)
  - CSS-like styling
  - Keyboard/mouse navigation
  - Async-native (works with i3ipc.aio)
  - Built-in widgets: DataTable, Tree, Header, Footer, ListView, Input, Button

### Screen 1: Project Browser (Default Screen)

```
┌─ i3 Project Manager ──────────────────────────────────────────────┐
│ Active: nixos (NixOS) │ 5 windows │ /etc/nixos      [Win+P Switch] │
├───────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Projects:                                                         │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Icon  Name      Display         Directory         Windows  │   │
│  ├────────────────────────────────────────────────────────────┤   │
│  │ [✓]   nixos     NixOS           /etc/nixos             5   │   │
│  │ [ ]   stacks    Stacks          ~/projects/stacks      0   │   │
│  │ [ ]   personal  Personal        ~/personal             2   │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Windows (nixos):                                                  │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Class          Title                    WS    Monitor      │   │
│  ├────────────────────────────────────────────────────────────┤   │
│  │ Code           ~/nixos - VSCode         1     eDP-1        │   │
│  │ Ghostty        bash: /etc/nixos         2     eDP-1        │   │
│  │ Ghostty        nvim flake.nix           2     eDP-1        │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
├───────────────────────────────────────────────────────────────────┤
│ [N]ew  [E]dit  [D]elete  [S]witch  [L]ayout  [M]onitor  [Q]uit   │
└───────────────────────────────────────────────────────────────────┘
```

**Interactions**:
- `↑/↓` - Navigate project list
- `Enter` - Switch to selected project
- `Tab` - Toggle between Projects table and Windows table
- `n` - Create new project (wizard)
- `e` - Edit selected project (open editor screen)
- `d` - Delete project (with confirmation)
- `s` - Switch to project (same as Enter)
- `l` - Open Layout Manager for project
- `m` - Toggle to Monitor Dashboard
- `q` - Quit
- `/` - Search/filter projects

### Screen 2: Project Editor

```
┌─ Edit Project: nixos ─────────────────────────────────────────────┐
│                                                                    │
│  Basic Configuration:                                              │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Name:         nixos                                        │   │
│  │ Display Name: NixOS                                        │   │
│  │ Icon:                                                     │   │
│  │ Directory:    /etc/nixos                        [Browse]  │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Application Classification:                                       │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Scoped (auto-mark):  ☑ VS Code  ☑ Terminals  ☑ Yazi       │   │
│  │ Global (no mark):    ☑ Firefox  ☑ PWAs  ☑ K9s             │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Auto-Launch Configuration:                           [+ Add App] │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ App              Command         Workspace    Monitor      │   │
│  ├────────────────────────────────────────────────────────────┤   │
│  │ VS Code          code .          1 (Main)     Primary      │   │
│  │ Terminal         ghostty         2 (Code)     Primary      │   │
│  │ Terminal         ghostty         2 (Code)     Primary      │   │
│  │ Lazygit          ghostty lazygit 3 (Tools)    Secondary    │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Workspace Preferences:                                            │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ WS 1-2 → Primary    WS 3-5 → Secondary    WS 6-9 → Tertiary│   │
│  │ [Edit Distribution...]                                     │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
├───────────────────────────────────────────────────────────────────┤
│ [S]ave  [C]ancel  [T]est Auto-Launch  [V]alidate                 │
└───────────────────────────────────────────────────────────────────┘
```

**Interactions**:
- `Tab`/`Shift+Tab` - Navigate fields
- `Space` - Toggle checkboxes
- `Enter` - Edit focused field (text input mode)
- `Ctrl+A` - Add auto-launch app (opens wizard)
- `Del` - Remove selected auto-launch app
- `s` - Save changes (validates first)
- `c` - Cancel without saving
- `t` - Test auto-launch (dry-run showing what would launch)
- `v` - Validate config without saving

### Screen 3: Monitor Dashboard (Enhanced i3-project-monitor)

```
┌─ i3 Project System Monitor ───────────────────────────────────────┐
│ Mode: Live │ Project: nixos │ Daemon: ✓ Connected │ Uptime: 2h 34m│
├───────────────────────────────────────────────────────────────────┤
│                                                                    │
│  System State:                                                     │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Total Windows:     18  │  Tracked:    12  │  Global:    6  │   │
│  │ Events Processed: 1,234 │  Errors:      0  │  CPU: <1%    │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Monitors:                                                         │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Name     Resolution    Workspaces        Active WS         │   │
│  ├────────────────────────────────────────────────────────────┤   │
│  │ eDP-1    1920x1080     1, 2              1                 │   │
│  │ HDMI-1   2560x1440     3, 4, 5, 6, 7, 8  4                 │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Recent Events (live):                           [Pause] [Clear]  │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Time      Type           Details                           │   │
│  ├────────────────────────────────────────────────────────────┤   │
│  │ 10:35:12  window::new    class=Code, marked=project:nixos  │   │
│  │ 10:35:11  window::mark   window=94557896564, mark=project… │   │
│  │ 10:35:05  workspace::focus  workspace=1                    │   │
│  │ 10:34:58  tick           payload=project:nixos             │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
├───────────────────────────────────────────────────────────────────┤
│ [B]ack  [E]vents  [H]istory  [T]ree  [D]iagnose  [F]ilter        │
└───────────────────────────────────────────────────────────────────┘
```

**Modes within Monitor** (switchable via keys):
- `Live` - Real-time dashboard (default)
- `Events` - Event stream (scrollable, filterable)
- `History` - Past events with search
- `Tree` - i3 tree inspector (expandable nodes)
- `Diagnose` - Diagnostic snapshot for bug reports

### Screen 4: Layout Manager

```
┌─ Layout Manager: nixos ───────────────────────────────────────────┐
│                                                                    │
│  Current Layout:                          Last Saved: 2025-10-20  │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Monitor: eDP-1 (Primary)                                   │   │
│  │ ├─ Workspace 1: Main                                       │   │
│  │ │  └─ VS Code (code) - ~/nixos/flake.nix  [800x600+0+0]   │   │
│  │ ├─ Workspace 2: Code                                       │   │
│  │ │  ├─ Ghostty (terminal) - bash           [400x600+0+0]   │   │
│  │ │  └─ Ghostty (terminal) - nvim           [400x600+400+0] │   │
│  │                                                             │   │
│  │ Monitor: HDMI-1 (Secondary)                                │   │
│  │ ├─ Workspace 4: Tools                                      │   │
│  │ │  └─ Lazygit (terminal)                  [1280x720+0+0]  │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Saved Layouts:                                      [+ New Save] │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Name             Created       Windows  Workspaces         │   │
│  ├────────────────────────────────────────────────────────────┤   │
│  │ Default          2025-10-18        3         3             │   │
│  │ Full Stack Dev   2025-10-19        7         5             │   │
│  │ Quick Start      2025-10-20        2         1             │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Actions:                                                          │
│  [S]ave Current Layout  [R]estore Selected  [D]elete  [E]xport   │
│                                                                    │
├───────────────────────────────────────────────────────────────────┤
│ [B]ack  [A]uto-Restore: ☑  [C]apture Screenshot                  │
└───────────────────────────────────────────────────────────────────┘
```

**Features**:
- **Current Layout View**: Visual tree of current window arrangement
- **Saved Layouts**: List of previously saved states
- **Save**: Capture current window positions, sizes, workspaces
- **Restore**: Reopen apps in saved configuration
- **Export**: Save layout as JSON for sharing/versioning
- **Auto-Restore**: Toggle whether to restore last layout on project switch

### Screen 5: Configuration Wizard (New Project)

```
┌─ Create New Project ──────────────────────────────────────────────┐
│ Step 1 of 4: Basic Information                      [━━━━━-----] │
├───────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Project Name:                                                     │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ webapp                                                     │   │
│  └────────────────────────────────────────────────────────────┘   │
│  • Lowercase, alphanumeric, hyphens/underscores                   │
│  • Used in commands: i3-project switch webapp                     │
│                                                                    │
│  Display Name:                                                     │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ Web Application                                            │   │
│  └────────────────────────────────────────────────────────────┘   │
│  • Human-readable name shown in UI                                │
│                                                                    │
│  Icon (emoji or Unicode):                                          │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │                                                           │   │
│  └────────────────────────────────────────────────────────────┘   │
│  • [Space] to open emoji picker                                   │
│                                                                    │
│  Project Directory:                                                │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ /home/user/projects/webapp                     [Browse]   │   │
│  └────────────────────────────────────────────────────────────┘   │
│  • Will be created if doesn't exist                               │
│  • Sets $PROJECT_DIR for launched apps                            │
│                                                                    │
├───────────────────────────────────────────────────────────────────┤
│ [N]ext  [C]ancel  [S]kip Setup (create minimal)                  │
└───────────────────────────────────────────────────────────────────┘
```

**Wizard Steps**:
1. **Basic Information** - Name, icon, directory
2. **Application Selection** - Choose scoped apps, global apps
3. **Auto-Launch Setup** - Define apps to launch, workspaces
4. **Review & Create** - Preview JSON, confirm

---

## CLI Command Mode Design

### Subcommand Structure

```bash
i3pm <command> [options]

# Alias for brevity
i3-project <command> [options]
```

**Core Commands**:

```bash
# Project Management
i3pm list                          # List all projects
i3pm create <name>                 # Create project (wizard or flags)
i3pm edit <name>                   # Edit project (opens TUI editor)
i3pm delete <name>                 # Delete project
i3pm show <name>                   # Show project details (JSON)
i3pm validate [name]               # Validate project config(s)

# Project Operations
i3pm switch <name>                 # Switch to project
i3pm clear                         # Clear active project (global mode)
i3pm current                       # Show current active project
i3pm close [name]                  # Close all windows for project

# Layout Management
i3pm save-layout <name>            # Save current layout
i3pm restore-layout <name>         # Restore saved layout
i3pm export-layout <name> <file>   # Export layout to file
i3pm import-layout <file> <name>   # Import layout from file
i3pm list-layouts [project]        # List saved layouts

# Monitoring & Diagnostics
i3pm monitor [mode]                # Open monitor (defaults to live)
i3pm events [--limit N]            # Show recent events
i3pm status                        # Show daemon status
i3pm diagnose                      # Capture diagnostic snapshot

# Testing
i3pm test [scenario]               # Run test scenario(s)
i3pm test suite                    # Run full test suite

# Window Management
i3pm windows [project]             # List windows for project
i3pm mark <window-id> <project>    # Manually mark window
i3pm unmark <window-id>            # Remove project mark

# Configuration
i3pm config edit                   # Edit app-classes.json
i3pm config validate               # Validate all configs
i3pm config export <dir>           # Export all configs
i3pm config import <dir>           # Import configs
```

**Examples**:

```bash
# Quick project creation via flags
i3pm create myproject \
  --dir ~/projects/myproject \
  --display "My Project" \
  --icon "" \
  --auto-launch "code ." \
  --auto-launch "ghostty" \
  --workspace-dist "1-2:primary,3-5:secondary"

# Scripted workflow
i3pm switch webapp
i3pm restore-layout full-stack-dev
i3pm save-layout before-refactor

# Monitoring during development
i3pm events --follow --filter window

# Diagnostics
i3pm diagnose --output ~/bug-report.json
i3pm test project_lifecycle --verbose
```

---

## Configuration State Format

### Project Configuration (Enhanced)

**File**: `~/.config/i3/projects/{name}.json`

```json
{
  "name": "webapp",
  "display_name": "Web Application",
  "icon": "",
  "directory": "/home/user/projects/webapp",

  "created": "2025-10-20T10:00:00Z",
  "last_active": "2025-10-20T14:30:00Z",
  "last_modified": "2025-10-20T14:30:00Z",

  "auto_launch": {
    "enabled": true,
    "prevent_duplicates": true,
    "apps": [
      {
        "name": "VS Code",
        "command": "code .",
        "workspace": 1,
        "monitor": "primary",
        "delay_ms": 0,
        "env": {
          "VSCODE_WORKSPACE": "${PROJECT_DIR}/.vscode/workspace.code-workspace"
        }
      },
      {
        "name": "Dev Server",
        "command": "ghostty -- npm run dev",
        "workspace": 2,
        "monitor": "primary",
        "delay_ms": 500
      },
      {
        "name": "Logs",
        "command": "ghostty -- tail -f logs/development.log",
        "workspace": 2,
        "monitor": "secondary",
        "delay_ms": 1000
      }
    ]
  },

  "workspace_preferences": {
    "distribution": {
      "primary": [1, 2],
      "secondary": [3, 4, 5],
      "tertiary": [6, 7, 8, 9]
    },
    "auto_reassign_on_monitor_change": true
  },

  "saved_layouts": [
    {
      "name": "default",
      "created": "2025-10-20T10:00:00Z",
      "description": "Initial project layout",
      "auto_restore": true,
      "windows": [
        {
          "class": "Code",
          "title": "${PROJECT_DIR} - Visual Studio Code",
          "workspace": 1,
          "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
          "floating": false
        }
      ]
    }
  ],

  "window_rules": {
    "scoped_classes": ["Code", "Alacritty", "org.kde.ghostty"],
    "global_classes": ["firefox"],
    "custom_marks": []
  }
}
```

### Global App Classification

**File**: `~/.config/i3/app-classes.json`

```json
{
  "version": "1.0",
  "scoped_classes": [
    {
      "class": "Code",
      "display_name": "VS Code",
      "icon": "",
      "default_workspace": 1,
      "auto_mark": true
    },
    {
      "class": "org.kde.ghostty",
      "display_name": "Ghostty Terminal",
      "icon": "",
      "default_workspace": 2,
      "auto_mark": true
    }
  ],
  "global_classes": [
    {
      "class": "firefox",
      "display_name": "Firefox",
      "icon": "",
      "never_mark": true
    }
  ],
  "pwa_classes": [
    {
      "class": "youtube-music",
      "display_name": "YouTube Music",
      "icon": "",
      "scoped": false,
      "never_mark": true
    }
  ]
}
```

### Layout Export Format (Portable)

**File**: `{project}-layout-{name}.json`

```json
{
  "format_version": "1.0",
  "project_name": "webapp",
  "layout_name": "full-stack-dev",
  "created": "2025-10-20T14:30:00Z",
  "created_by": "i3pm v0.2.0",

  "description": "Full stack development environment with 3 monitors",

  "monitors": [
    {
      "index": 0,
      "role": "primary",
      "name_hint": "eDP-1",
      "resolution": "1920x1080",
      "workspaces": [
        {
          "number": 1,
          "name": "Main",
          "windows": [
            {
              "class": "Code",
              "command": "code ${PROJECT_DIR}",
              "title": "Visual Studio Code",
              "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
              "split": "horizontal",
              "percent": 1.0
            }
          ]
        }
      ]
    }
  ],

  "launch_order": [
    "code ${PROJECT_DIR}",
    "ghostty -- npm run dev",
    "firefox http://localhost:3000"
  ],

  "metadata": {
    "tags": ["frontend", "react", "typescript"],
    "notes": "Launch dev server before opening browser"
  }
}
```

---

## Implementation Strategy

### Phase 1: Unified Core Library (Week 1)

**Goal**: Extract common functionality into shared library

```python
# File: i3_project_manager/core/
i3_project_manager/
├── core/
│   ├── __init__.py
│   ├── project.py         # Project CRUD operations
│   ├── daemon_client.py   # Daemon IPC (from monitor)
│   ├── i3_client.py       # i3 IPC queries
│   ├── config.py          # Config validation/loading
│   ├── layout.py          # Layout save/restore
│   └── models.py          # Shared dataclasses
├── cli/
│   ├── __init__.py
│   ├── commands.py        # CLI subcommands
│   └── formatters.py      # Output formatting
├── tui/
│   ├── __init__.py
│   ├── app.py            # Textual app
│   ├── screens/          # TUI screens
│   └── widgets/          # Custom widgets
└── __main__.py           # Entry point
```

**Tasks**:
- [x] Merge `i3_project_monitor/daemon_client.py` into core
- [ ] Create `Project` class with CRUD methods
- [ ] Implement `LayoutManager` for save/restore
- [ ] Add config validation using JSON Schema
- [ ] Write unit tests for core library

### Phase 2: CLI Command Mode (Week 2)

**Goal**: Implement comprehensive CLI with backward compatibility

**Tasks**:
- [ ] Implement all subcommands using argparse
- [ ] Add rich output formatting (tables, progress bars)
- [ ] Create symlinks for backward compat (`i3-project-switch` → `i3pm switch`)
- [ ] Add shell completions (bash, zsh, fish)
- [ ] Write integration tests

**Backward Compatibility**:
```bash
# Keep existing commands as symlinks
/usr/bin/i3-project-switch → i3pm switch
/usr/bin/i3-project-list → i3pm list
/usr/bin/i3-project-current → i3pm current
/usr/bin/i3-project-create → i3pm create

# Or keep as separate scripts that call i3pm
```

### Phase 3: Interactive TUI (Week 3-4)

**Goal**: Build Textual-based interactive UI

**Tasks**:
- [ ] Implement Project Browser screen
- [ ] Implement Project Editor screen
- [ ] Integrate Monitor Dashboard (migrate i3-project-monitor)
- [ ] Implement Layout Manager screen
- [ ] Add Configuration Wizard
- [ ] Implement keyboard navigation
- [ ] Add theme support (dark/light)
- [ ] Write TUI acceptance tests

### Phase 4: Layout Management (Week 5)

**Goal**: Implement layout save/restore functionality

**Tasks**:
- [ ] Implement layout capture (query i3 tree, serialize)
- [ ] Implement layout restore (parse, launch apps, position windows)
- [ ] Add layout diff/compare
- [ ] Support layout export/import
- [ ] Add layout templates (common setups)

### Phase 5: Integration & Polish (Week 6)

**Goal**: Integrate all components, polish UX

**Tasks**:
- [ ] Integrate testing framework into TUI
- [ ] Add real-time validation in editors
- [ ] Implement undo/redo for config changes
- [ ] Add keyboard shortcuts cheat sheet (accessible via `?`)
- [ ] Write comprehensive user documentation
- [ ] Create video demo/tutorial

---

## User Experience Workflows

### Workflow 1: Create New Project (Interactive)

```bash
$ i3pm
# Opens TUI, press 'n' for New Project

[Wizard appears]
Step 1/4: Basic Information
  Name: myproject
  Display: My Project
  Icon:  (picker opens)
  Dir: ~/projects/myproject [Created ✓]

Step 2/4: Application Selection
  Scoped: ☑ VS Code  ☑ Terminals
  Global: ☑ Firefox  ☑ PWAs

Step 3/4: Auto-Launch Setup
  [Table with + button]
  Add: VS Code → WS 1 → Primary
  Add: Terminal → WS 2 → Primary

Step 4/4: Review
  [Shows generated JSON]
  Validation: ✓ All checks passed

[S]ave → Project created!
[Auto-switch to myproject? Y/n] y
```

### Workflow 2: Save and Restore Layout

```bash
# User has 5 windows open, wants to save configuration
$ i3pm
# Press 'l' for Layout Manager

[Layout Manager screen]
Current Layout:
  - WS 1: VS Code (main.ts)
  - WS 2: Terminal (dev server), Terminal (logs)
  - WS 4: Firefox (localhost:3000)

[S]ave Current Layout
  Name: full-stack-dev
  Description: Dev server + editor + browser
  Auto-restore on switch: ☑

Saved! ✓

# Next day, switch back to project
$ i3pm switch webapp
# Auto-restore prompt appears (if configured)
Restore layout "full-stack-dev"? [Y/n] y
Launching 3 applications...
  ✓ VS Code (WS 1)
  ✓ Terminal - dev server (WS 2)
  ✓ Firefox (WS 4)
Done!
```

### Workflow 3: Monitor While Editing

```bash
$ i3pm
# Split screen view (future enhancement)

┌─ Projects ─────────┬─ Monitor (Live) ──────────┐
│ [✓] nixos          │ Events (last 10):         │
│ [ ] webapp         │ 10:35 window::new Code    │
│                    │ 10:34 tick project:nixos  │
│ [E]dit nixos       │                           │
│                    │ Daemon: ✓ 2h uptime       │
│ [Editing...]       │ CPU: <1%                  │
│ Auto-launch:       │                           │
│ + code .    WS1    │                           │
│ + ghostty   WS2    │                           │
│                    │                           │
│ [S]ave [T]est      │ [P]ause [F]ilter          │
└────────────────────┴───────────────────────────┘
```

---

## Decision: Integrate or Separate?

### Recommendation: **Unified Tool with Mode Separation**

**Rationale**:
1. **Single Entry Point** - Easier discovery, less cognitive load
2. **Shared Code** - No duplication, consistent behavior
3. **Smooth Transitions** - Can jump from CLI to TUI and back
4. **Backward Compat** - Keep existing commands as thin wrappers

**Architecture**:
```
i3pm (main entry point)
├─ Mode: Interactive TUI (no args)
│  └─ Can spawn CLI commands internally
│  └─ Can switch to monitoring mode
│
├─ Mode: CLI (with args)
│  └─ Can launch TUI for complex operations
│  └─ Monitoring commands open TUI temporarily
│
└─ Backward compat symlinks
   ├─ i3-project-switch → i3pm switch
   ├─ i3-project-monitor → i3pm monitor
   └─ i3-project-test → i3pm test
```

**Benefits**:
- Users learn one tool (`i3pm`) instead of 10+ commands
- Monitoring integrated into management (edit + monitor simultaneously)
- Testing accessible from TUI (test config changes immediately)
- Consistent output formatting (Rich) across all modes

---

## Next Steps

1. **Update Specification** - Add UX requirements to spec.md
2. **Create Prototypes** - Mock TUI screens in Textual
3. **Gather Feedback** - Test wireframes with users
4. **Implement Core** - Build shared library first
5. **Iterate** - Release CLI mode, then TUI, then integration

**Questions for You**:
1. Do you prefer `i3pm` or `i3-project` as the main command name?
2. Should we keep all existing commands or deprecate some?
3. What's your priority: CLI improvements or TUI implementation?
4. Any specific TUI features you want to see first?

---

**Version**: 0.1.0 (Draft)
**Last Updated**: 2025-10-20
