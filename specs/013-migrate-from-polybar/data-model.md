# Phase 1: Data Model

**Feature**: Migrate from Polybar to i3 Native Status Bar
**Date**: 2025-10-19
**Purpose**: Define entities, state, and configuration structures

## Overview

This document defines the data structures and state management for the i3bar + i3blocks system. Unlike application data models, this focuses on configuration entities and runtime state.

## Configuration Entities

### 1. Bar Configuration

Represents the i3bar instance configuration.

**Attributes**:
- `position`: String - Bar position on screen ("top" | "bottom")
- `status_command`: String - Command to generate status output (path to i3blocks)
- `workspace_buttons`: Boolean - Show workspace buttons (always true)
- `binding_mode_indicator`: Boolean - Show mode indicator (true for resize mode, etc.)
- `font`: String - Font family and size ("FiraCode Nerd Font 10")
- `colors`: Color Scheme (see below)

**Relationships**:
- Has one Color Scheme
- Managed by i3 window manager
- One instance per monitor/output

**Validation Rules**:
- `position` must be "top" or "bottom"
- `status_command` must be executable path
- `font` must be installed on system

**Nix Representation**:
```nix
{
  position = "bottom";
  statusCommand = "${pkgs.i3blocks}/bin/i3blocks -c ${i3blocksConfig}";
  workspaceButtons = true;
  mode = "dock";  # Always visible, not hide mode
  fonts = {
    names = [ "FiraCode Nerd Font" ];
    size = 10.0;
  };
  colors = {
    # See Color Scheme entity
  };
}
```

---

### 2. Color Scheme

Catppuccin Mocha color palette for i3bar.

**Attributes**:
- `background`: Hex Color - Bar background (#1e1e2e)
- `statusline`: Hex Color - Text color for status (#cdd6f4)
- `separator`: Hex Color - Block separator color (#6c7086)
- `focused_workspace`: Workspace Colors - Currently focused workspace
- `active_workspace`: Workspace Colors - Visible on other monitor
- `inactive_workspace`: Workspace Colors - Not visible
- `urgent_workspace`: Workspace Colors - Has urgent window

**Workspace Colors** (composite):
- `border`: Hex Color - Workspace button border
- `background`: Hex Color - Button background
- `text`: Hex Color - Button text

**Catppuccin Mapping**:
```nix
# Extracted from Catppuccin Mocha palette
base       = "#1e1e2e";  # Background
text       = "#cdd6f4";  # Foreground
lavender   = "#b4befe";  # Primary accent
blue       = "#89b4fa";  # Secondary accent
red        = "#f38ba8";  # Alert/urgent
surface0   = "#313244";  # Subtle background
surface1   = "#45475a";  # Focused background
overlay0   = "#6c7086";  # Disabled/separator
subtext0   = "#bac2de";  # Dimmed text
```

**i3bar Colors Configuration**:
```nix
colors = {
  background = "#1e1e2e";
  statusline = "#cdd6f4";
  separator  = "#6c7086";
  
  focused_workspace  = {
    border = "#b4befe";
    background = "#45475a";
    text = "#cdd6f4";
  };
  active_workspace   = {
    border = "#89b4fa";
    background = "#313244";
    text = "#cdd6f4";
  };
  inactive_workspace = {
    border = "#313244";
    background = "#1e1e2e";
    text = "#bac2de";
  };
  urgent_workspace   = {
    border = "#f38ba8";
    background = "#f38ba8";
    text = "#1e1e2e";
  };
};
```

---

### 3. Status Block

Represents a single information block in the status bar.

**Attributes**:
- `full_text`: String - Text to display
- `short_text`: String (optional) - Abbreviated text for narrow spaces
- `color`: Hex Color - Text color
- `background`: Hex Color (optional) - Block background
- `border`: Hex Color (optional) - Block border
- `border_top`/`border_bottom`/`border_left`/`border_right`: Integer (optional) - Border width
- `min_width`: Integer|String (optional) - Minimum block width
- `align`: String (optional) - Text alignment ("left"|"center"|"right")
- `separator`: Boolean - Show separator after block
- `separator_block_width`: Integer - Separator width in pixels
- `markup`: String - Markup format ("none"|"pango")
- `urgent`: Boolean - Urgent state (red color)

**Block Types** (by content):
1. **CPU Block**: Displays CPU usage percentage
2. **Memory Block**: Displays memory usage percentage
3. **Network Block**: Displays network status (up/down, SSID)
4. **DateTime Block**: Displays current date and time
5. **Project Block**: Displays active project name/icon

**JSON Protocol Format**:
```json
{
  "full_text": "CPU: 25%",
  "color": "#cdd6f4",
  "separator": true,
  "separator_block_width": 15,
  "markup": "none"
}
```

**State Transitions**:
- Normal → Urgent: When value exceeds threshold
- Urgent → Normal: When value returns to normal
- Empty → Populated: When data becomes available
- Populated → Empty: When data unavailable (error state)

---

### 4. i3blocks Configuration

Configuration file for i3blocks status command.

**Global Properties**:
- `separator_block_width`: Integer - Default separator width (15)
- `markup`: String - Default markup format ("pango" for rich text)
- `interval`: Integer - Default update interval (5 seconds)

**Block Definitions**:
Each block has:
- `command`: String - Script path to execute
- `interval`: Integer|"once"|"persist" - Update frequency
  - Integer: Seconds between updates
  - "once": Run once at startup
  - "persist": Long-running process
- `signal`: Integer (optional) - SIGRTMIN+N for manual updates
- `color`: Hex Color (optional) - Default text color
- `label`: String (optional) - Prefix text

**Example Configuration**:
```ini
# Global properties
separator_block_width=15
markup=pango

# CPU block
[cpu]
command=/home/user/.config/i3blocks/scripts/cpu.sh
interval=5
color=#cdd6f4
label=CPU:

# Project block (signal-based)
[project]
command=/home/user/.config/i3blocks/scripts/project.sh
interval=once
signal=10
color=#b4befe
```

**Nix Generation**:
```nix
xdg.configFile."i3blocks/config".text = ''
  separator_block_width=15
  markup=pango
  
  [cpu]
  command=${cpuScript}
  interval=5
  color=#cdd6f4
  
  [memory]
  command=${memoryScript}
  interval=5
  color=#cdd6f4
  
  [network]
  command=${networkScript}
  interval=10
  color=#cdd6f4
  
  [project]
  command=${projectScript}
  interval=once
  signal=10
  color=#b4befe
  
  [datetime]
  command=${datetimeScript}
  interval=60
  color=#cdd6f4
'';
```

---

## State Entities

### 5. Project State

Represents the currently active project context.

**Storage**: `~/.config/i3/active-project` (JSON file)

**Attributes**:
- `name`: String - Project identifier (e.g., "nixos", "stacks")
- `display_name`: String - Human-readable name (e.g., "NixOS")
- `icon`: String - Unicode emoji or Nerd Font icon (e.g., "")
- `directory`: String - Project root directory path
- `timestamp`: Integer - Unix timestamp of last activation

**JSON Structure**:
```json
{
  "name": "nixos",
  "display_name": "NixOS",
  "icon": "",
  "directory": "/etc/nixos",
  "timestamp": 1729353600
}
```

**State Transitions**:
1. **No Project** (null state):
   - File doesn't exist or is empty
   - Display: Generic indicator or nothing
   
2. **Active Project**:
   - File contains valid JSON
   - Display: `{icon} {display_name}`
   
3. **Invalid State**:
   - File exists but malformed JSON
   - Display: Error indicator or fallback

**Update Mechanism**:
- Written by `i3-project-switch` command
- Read by `project.sh` i3blocks script
- Signals i3blocks (SIGRTMIN+10) after write
- No polling required (signal-driven)

---

### 6. Workspace State

Represents i3 workspace information (queried via IPC).

**Source**: i3 IPC GET_WORKSPACES message

**Attributes** (from i3):
- `num`: Integer - Workspace number (-1 for named workspaces)
- `name`: String - Workspace name/label
- `visible`: Boolean - Currently visible on some output
- `focused`: Boolean - Currently has keyboard focus
- `urgent`: Boolean - Contains urgent window
- `rect`: Rectangle - Workspace geometry
- `output`: String - Monitor/output name (e.g., "rdp0")

**Managed By**: i3 window manager (not our code)

**Accessed Via**: i3bar automatically via IPC (no manual queries needed)

**Display Mapping**:
- Focused workspace → focused_workspace colors
- Visible (other monitor) → active_workspace colors
- Not visible → inactive_workspace colors
- Urgent flag → urgent_workspace colors

**No Persistence**: Workspace state is ephemeral, managed entirely by i3 in memory.

---

### 7. System Metrics

Real-time system information displayed in status blocks.

**CPU Usage**:
- **Source**: `/proc/stat` or `mpstat` command
- **Value**: Percentage (0-100)
- **Update**: Every 5 seconds
- **Thresholds**: >80% = warning color (#f9e2af), >95% = urgent (#f38ba8)

**Memory Usage**:
- **Source**: `/proc/meminfo` or `free` command
- **Value**: Percentage (0-100)
- **Calculation**: (Total - Available) / Total * 100
- **Update**: Every 5 seconds
- **Thresholds**: >80% = warning, >95% = urgent

**Network Status**:
- **Source**: `ip link` or `/sys/class/net/{interface}/operstate`
- **Value**: Interface name + status ("wlan0: up" or "disconnected")
- **Update**: Every 10 seconds
- **States**: up (green #a6e3a1), down (red #f38ba8)

**Date/Time**:
- **Source**: `date` command
- **Format**: "YYYY-MM-DD HH:MM" (ISO 8601 style)
- **Update**: Every 60 seconds
- **No thresholds**: Always normal color

**Ephemeral State**: All metrics are computed on-demand, no persistence.

---

## Configuration File Locations

### Generated by Home-Manager

| File | Purpose | Generator |
|------|---------|-----------|
| `~/.config/i3/config` | i3 configuration with bar {} block | xsession.windowManager.i3.config |
| `~/.config/i3blocks/config` | i3blocks configuration | xdg.configFile."i3blocks/config".text |
| `~/.config/i3blocks/scripts/*.sh` | Status block scripts | home.file with executable=true |

### User State (Not Managed)

| File | Purpose | Writer |
|------|---------|--------|
| `~/.config/i3/active-project` | Project context state | i3-project-switch command |

---

## Data Flow

### Startup Flow

```
1. i3 starts (from .xsession or systemd)
   ↓
2. i3 parses config, finds bar {} block
   ↓
3. i3 spawns i3bar process (one per output)
   ↓
4. i3bar starts status_command (i3blocks)
   ↓
5. i3blocks reads config, runs each block script
   ↓
6. Each script outputs JSON to stdout
   ↓
7. i3blocks aggregates and sends to i3bar
   ↓
8. i3bar displays blocks in status area
   ↓
9. i3bar queries i3 via IPC for workspace state
   ↓
10. i3bar displays workspace buttons
```

### Runtime Update Flow

**Periodic Updates** (CPU, memory, network, time):
```
1. i3blocks interval timer expires
   ↓
2. i3blocks runs block script
   ↓
3. Script queries system (proc, commands)
   ↓
4. Script outputs new JSON
   ↓
5. i3blocks updates i3bar
   ↓
6. i3bar redraws status section
```

**Signal-Based Updates** (project indicator):
```
1. User runs: i3-project-switch nixos
   ↓
2. Script writes ~/.config/i3/active-project
   ↓
3. Script sends: pkill -RTMIN+10 i3blocks
   ↓
4. i3blocks receives signal
   ↓
5. i3blocks runs project block script
   ↓
6. Script reads active-project file
   ↓
7. Script outputs JSON with project name
   ↓
8. i3blocks updates i3bar
   ↓
9. i3bar displays new project indicator
```

**Workspace Updates** (i3 events):
```
1. User switches workspace (Mod+1)
   ↓
2. i3 handles workspace switch
   ↓
3. i3 sends workspace event via IPC
   ↓
4. i3bar subscribed to workspace events
   ↓
5. i3bar receives event notification
   ↓
6. i3bar queries GET_WORKSPACES
   ↓
7. i3bar updates workspace button display
   ↓
8. Change visible within ~100ms
```

---

## Validation Rules

### Bar Configuration Validation

- ✅ `position` in ["top", "bottom"]
- ✅ `status_command` path exists and is executable
- ✅ Font family installed on system
- ✅ All color values are valid hex codes (#RRGGBB)

### i3blocks Configuration Validation

- ✅ All script paths exist and are executable
- ✅ Intervals are positive integers or special keywords
- ✅ Signal numbers are 1-31 (SIGRTMIN+0 to SIGRTMIN+31)
- ✅ Color values are valid hex codes

### Project State Validation

- ✅ File contains valid JSON
- ✅ Required fields present (name, display_name)
- ✅ Directory path exists (warning if not, doesn't block)
- ✅ Timestamp is valid Unix epoch

### Status Block Output Validation

- ✅ Output is valid JSON or plain text
- ✅ Color values are valid hex codes
- ✅ Script execution time <100ms (performance)
- ✅ Script doesn't hang (has timeout)

---

## Summary

**Configuration Entities**:
1. Bar Configuration (i3bar settings)
2. Color Scheme (Catppuccin Mocha)
3. Status Block (individual info block)
4. i3blocks Configuration (status command settings)

**State Entities**:
5. Project State (active project context)
6. Workspace State (managed by i3, queried via IPC)
7. System Metrics (CPU, memory, network, time)

**Key Principles**:
- Configuration is declarative (generated by Nix)
- State is minimal (only project context persisted)
- Data flow is event-driven (signals, IPC events)
- Updates are efficient (no polling except system metrics)
