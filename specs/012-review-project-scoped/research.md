# Research: i3-Native Dynamic Project Workspace Management

**Date**: 2025-10-19
**Feature**: 012-review-project-scoped

## Overview

This document consolidates research findings for implementing i3-native dynamic project workspace management. The goal is to replace static NixOS project configuration with runtime-configurable projects using i3's built-in features.

## Research Areas

### 1. i3 Marks System

**Decision**: Use i3 native marks in format `project:PROJECT_NAME`

**Rationale**:
- i3 marks are persistent across i3 restarts (stored in i3's internal state)
- Marks can be queried via IPC GET_TREE command
- Marks enable precise window selection with criteria syntax `[con_mark="mark_name"]`
- Multiple marks can be applied to same window (allows combining project marks with other categorization)
- No custom window tracking database required

**Implementation Details**:
```bash
# Mark a window with project association
i3-msg "[id=$WINDOW_ID] mark project:nixos"

# Select all windows with specific mark
i3-msg '[con_mark="project:nixos"] move scratchpad'

# Query marks via IPC
i3-msg -t get_tree | jq '.. | select(.marks? | contains(["project:nixos"]))'
```

**Alternatives Considered**:
- **Custom window property**: Rejected because requires window manager modifications
- **WM_CLASS matching**: Rejected because same application can belong to different projects
- **PID tracking**: Rejected because PIDs are not persistent across application restarts
- **External database**: Rejected because adds complexity and sync issues with i3 state

**Best Practices**:
- Mark windows immediately after launch (within application wrapper script)
- Use namespaced mark format to avoid conflicts with user-defined marks
- Check for existing marks before adding to prevent duplicates
- Clean up marks when project is deleted (optional, orphaned marks don't harm)

### 2. i3 Layout Restoration with `append_layout`

**Decision**: Use i3's native `append_layout` command with JSON layout files

**Rationale**:
- i3 supports loading workspace layouts from JSON files since v4.8 (2014)
- Layout files can specify placeholder windows with "swallows" criteria for automatic window assignment
- Layouts can include window geometry, split directions, and marks
- Compatible with existing i3 tooling (`i3-save-tree` for exporting current layouts)

**Implementation Details**:
```bash
# Save current workspace layout
i3-save-tree --workspace 2 > ~/.config/i3/projects/nixos-ws2.json

# Load layout on workspace (before launching applications)
i3-msg 'workspace 2; append_layout ~/.config/i3/projects/nixos.json'

# Launch applications - i3 automatically assigns them to placeholders
code ~/code/nixos
```

**JSON Layout Schema Example**:
```json
{
    "border": "pixel",
    "floating": "auto_off",
    "layout": "splith",
    "percent": 0.5,
    "type": "con",
    "marks": ["project:nixos"],
    "nodes": [
        {
            "swallows": [
                {
                    "class": "^Code$",
                    "instance": "^code$"
                }
            ]
        }
    ]
}
```

**Alternatives Considered**:
- **Manual window positioning**: Rejected because requires complex IPC scripting
- **Custom layout manager**: Rejected because duplicates i3 functionality
- **Tmux sessions only**: Rejected because doesn't handle GUI applications

**Best Practices**:
- Use `i3-save-tree` as starting point, then simplify JSON manually
- Include only essential properties (swallows, marks, geometry)
- Test layouts with `append_layout` before integrating into project switcher
- Provide graceful fallback if layout file is missing (simple workspace assignment)

### 3. i3 IPC Tick Events for Synchronization

**Decision**: Use i3 tick events to notify polybar and other subscribers of project changes

**Rationale**:
- i3 tick events available since v4.15 (2017)
- Event-driven architecture eliminates file polling
- Polybar and custom scripts can subscribe via IPC socket
- Payload can contain arbitrary JSON data

**Implementation Details**:
```bash
# Send tick event from project switch script
i3-msg -t send_tick -m 'project:nixos'

# Polybar module subscribes to tick events (in polybar config)
# Requires custom module script that listens to i3 IPC
```

**Event Subscription in Python**:
```python
import i3ipc

i3 = i3ipc.Connection()

def on_tick(i3, event):
    if event.payload.startswith('project:'):
        project_name = event.payload.replace('project:', '')
        # Update polybar display
        print(f" {project_name}", flush=True)

i3.on('tick', on_tick)
i3.main()
```

**Alternatives Considered**:
- **File watching with inotify**: Rejected because adds complexity for something i3 provides natively
- **Polling active-project file**: Rejected because inefficient and causes update lag
- **D-Bus signals**: Rejected because requires additional service, i3 IPC is simpler

**Best Practices**:
- Use consistent payload format: `project:NAME` or `project:none`
- Keep payload small (<256 bytes recommended)
- Handle tick events asynchronously in subscribers
- Test event delivery with `i3-msg -t subscribe -m '["tick"]'`

### 4. Window ID Retrieval for Mark Assignment

**Decision**: Retrieve window ID immediately after application launch using `xdotool` or i3 window events

**Rationale**:
- Applications don't return their window ID when launched
- Window ID needed to apply marks immediately after launch
- Multiple approaches available depending on reliability needs

**Implementation Options**:

**Option A: xdotool with window search**
```bash
# Launch application in background
code ~/project/nixos &
APP_PID=$!

# Wait for window to appear (poll with timeout)
for i in {1..20}; do
    WINDOW_ID=$(xdotool search --pid $APP_PID 2>/dev/null | head -1)
    [[ -n "$WINDOW_ID" ]] && break
    sleep 0.1
done

# Mark window
i3-msg "[id=$WINDOW_ID] mark project:nixos"
```

**Option B: i3 window event subscription**
```python
# More reliable but requires daemon/async handling
import i3ipc
i3 = i3ipc.Connection()

def on_window_new(i3, event):
    if event.container.window_class == "Code":
        event.container.command('mark project:nixos')

i3.on('window::new', on_window_new)
```

**Option C: i3 swallows with layout**
```json
{
    "swallows": [{
        "class": "^Code$"
    }],
    "marks": ["project:nixos"]
}
```
When application launches, i3 automatically assigns it to placeholder and applies mark.

**Decision**: Use Option C (swallows) when project has layout file, fallback to Option A (xdotool) for simple launches

**Alternatives Considered**:
- **Window title matching**: Rejected because titles change frequently
- **wmctrl**: Rejected because xdotool is more widely used and better maintained
- **Manual user marking**: Rejected because defeats automation purpose

**Best Practices**:
- Set reasonable timeout (2 seconds) for window appearance
- Handle case where window never appears (app crash, user cancellation)
- Use window class matching for reliability (WM_CLASS property)
- Test with different application startup times

### 5. Project JSON Schema Design

**Decision**: Extend i3 layout schema with custom top-level properties for project metadata

**Rationale**:
- Maintain compatibility with `append_layout` command for workspace restoration
- Add custom properties for project management (name, directory, icon)
- Single file per project for simplicity
- JSON is human-readable and editable

**Schema Structure**:
```json
{
  "$schema": "https://i3wm.org/docs/layout-saving.html",
  "project": {
    "name": "nixos",
    "displayName": "NixOS Configuration",
    "icon": "",
    "directory": "/etc/nixos"
  },
  "workspaces": {
    "2": {
      "layout": { /* i3 layout JSON */ },
      "launchCommands": [
        "code /etc/nixos",
        "alacritty --working-directory /etc/nixos"
      ]
    }
  },
  "workspaceOutputs": {
    "2": "HDMI-1",
    "1": "eDP-1"
  },
  "appClasses": [
    "Code",
    "Ghostty",
    "lazygit",
    "yazi"
  ]
}
```

**Validation Requirements**:
- `project.name` must match filename (nixos.json → name: "nixos")
- `project.directory` must be absolute path
- Workspace numbers in range 1-10 (i3 default)
- Layout must follow i3 JSON schema

**Alternatives Considered**:
- **Separate metadata + layout files**: Rejected because increases file count
- **YAML format**: Rejected because i3 uses JSON, conversion adds complexity
- **TOML format**: Rejected for same reason as YAML
- **Embedded in i3 config**: Rejected because prevents runtime creation

**Best Practices**:
- Validate JSON with `jq` before loading
- Provide example project JSON in repository
- Document schema in quickstart guide
- Include optional fields with sensible defaults

### 6. Application Classification Configuration

**Decision**: Runtime JSON file `~/.config/i3/app-classes.json` mapping WM_CLASS to project scope

**Rationale**:
- Different users may have different preferences for which apps are project-scoped
- No rebuild required to change classification
- Simple JSON structure for easy editing

**Configuration Format**:
```json
{
  "classes": [
    {
      "class": "Code",
      "scoped": true,
      "workspace": 2,
      "description": "VS Code editor"
    },
    {
      "class": "Ghostty",
      "scoped": true,
      "workspace": 1,
      "description": "Terminal emulator"
    },
    {
      "class": "Firefox",
      "scoped": false,
      "description": "Web browser (global)"
    }
  ]
}
```

**Default Behavior** (when file missing or class not defined):
- Terminals (Ghostty, Alacritty, etc.): scoped
- IDEs (Code, IntelliJ, etc.): scoped
- File managers (yazi, ranger, etc.): scoped
- Browsers (Firefox, Chromium): global
- Communication (Slack, Discord): global

**Alternatives Considered**:
- **Hardcoded in scripts**: Rejected because not user-configurable
- **Per-project classification**: Rejected because same app shouldn't change behavior across projects
- **Regex patterns**: Considered but rejected for initial version (can add later)

**Best Practices**:
- Read file on each application launch (no caching needed, launches are infrequent)
- Provide comprehensive defaults in NixOS module
- Allow user to override by creating custom app-classes.json
- Document common WM_CLASS values for popular applications

### 7. Multi-Monitor Workspace Distribution

**Decision**: Use i3 native `workspace X output Y` commands specified in project JSON

**Rationale**:
- i3 handles monitor detection and workspace assignment natively
- Workspace output assignment persists until changed
- i3 gracefully handles disconnected monitors (falls back to available output)

**Implementation**:
```bash
# Read workspace outputs from project JSON
OUTPUTS=$(jq -r '.workspaceOutputs | to_entries | .[] | "workspace \(.key) output \(.value)"' project.json)

# Apply output assignments
echo "$OUTPUTS" | while read -r cmd; do
    i3-msg "$cmd"
done
```

**Fallback Behavior**:
- If output not specified in JSON: i3 uses default distribution
- If specified output disconnected: i3 places workspace on available output
- If project JSON lacks `workspaceOutputs`: skip output assignment entirely

**Alternatives Considered**:
- **Automatic detection**: Rejected because user preferences vary
- **xrandr scripting**: Rejected because i3 provides native support
- **Static i3 config**: Rejected because defeats per-project customization

**Best Practices**:
- Make workspace output assignments optional in project JSON
- Document output names for common setups (eDP-1, HDMI-1, DP-1)
- Test behavior when monitors are connected/disconnected
- Provide manual reassignment command: Win+Shift+M

## Technology Stack Summary

**Required Packages** (all already in NixOS configuration):
- i3wm >= 4.15 (tick events support)
- jq >= 1.6 (JSON parsing)
- rofi (project switcher UI)
- bash >= 5.0 (script runtime)
- xdotool (window ID retrieval)
- polybar or i3status (optional, for status display)

**Optional Enhancements**:
- python3-i3ipc (for robust event-driven window tracking)
- i3-save-tree (for exporting workspace layouts)
- shellcheck (for script validation)

## Implementation Approach Summary

Based on research findings:

1. **Project Storage**: Individual JSON files in `~/.config/i3/projects/` following extended i3 layout schema
2. **Window Association**: i3 marks in format `project:NAME`
3. **Visibility Management**: Native i3 scratchpad commands with mark criteria
4. **Layout Restoration**: i3 `append_layout` command for workspace structure
5. **Event Synchronization**: i3 tick events for real-time updates
6. **Application Classification**: Runtime JSON config with sensible defaults
7. **Multi-Monitor Support**: i3 workspace output assignments

All technical dependencies are met. No NEEDS CLARIFICATION items remaining.

## References

- [i3 User's Guide - Marks](https://i3wm.org/docs/userguide.html#vim_like_marks)
- [i3 Layout Saving](https://i3wm.org/docs/layout-saving.html)
- [i3 IPC Interface](https://i3wm.org/docs/ipc.html)
- [i3ipc-python Documentation](https://i3ipc-python.readthedocs.io/)
- [rofi Documentation](https://github.com/davatorium/rofi)
- [xdotool Manual](https://github.com/jordansissel/xdotool)
