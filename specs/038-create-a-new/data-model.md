# Data Model: Window State Preservation

**Feature**: 038 - Window State Preservation Across Project Switches
**Date**: 2025-10-25
**Status**: Complete

## Overview

This document defines the extended data model for window state persistence, adding geometry and scratchpad origin tracking to the existing `window-workspace-map.json` schema.

## WindowState Entity

**Storage**: `~/.config/i3/window-workspace-map.json`

**Schema Version**: 1.1 (Feature 038 extension)

### Fields

#### Existing Fields (Feature 037)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `workspace_number` | int | Yes | Workspace number (1-70, or -1 for scratchpad) |
| `floating` | bool | Yes | Floating state (true=floating, false=tiled) |
| `project_name` | str | Yes | Project name from I3PM_PROJECT_NAME env var |
| `app_name` | str | Yes | Application name (from registry or window class) |
| `window_class` | str | Yes | Window class from i3 WM_CLASS property |
| `last_seen` | float | Yes | Unix timestamp of last state update |

#### New Fields (Feature 038)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `geometry` | object \| null | Yes | Window geometry for floating windows, null for tiled |
| `geometry.x` | int | Conditional | X position in pixels (required if geometry not null) |
| `geometry.y` | int | Conditional | Y position in pixels (required if geometry not null) |
| `geometry.width` | int | Conditional | Width in pixels (required if geometry not null) |
| `geometry.height` | int | Conditional | Height in pixels (required if geometry not null) |
| `original_scratchpad` | bool | Yes | True if window was in scratchpad before project filtering |

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "version": {
      "type": "string",
      "description": "Schema version"
    },
    "last_updated": {
      "type": "number",
      "description": "Unix timestamp of last map update"
    },
    "windows": {
      "type": "object",
      "patternProperties": {
        "^[0-9]+$": {
          "type": "object",
          "properties": {
            "workspace_number": {
              "type": "integer",
              "minimum": -1,
              "maximum": 70,
              "description": "Workspace number or -1 for scratchpad"
            },
            "floating": {
              "type": "boolean",
              "description": "True if window is floating, false if tiled"
            },
            "project_name": {
              "type": "string",
              "description": "Project name from I3PM environment"
            },
            "app_name": {
              "type": "string",
              "description": "Application name"
            },
            "window_class": {
              "type": "string",
              "description": "Window class from WM_CLASS"
            },
            "last_seen": {
              "type": "number",
              "description": "Unix timestamp of last state update"
            },
            "geometry": {
              "oneOf": [
                {
                  "type": "null",
                  "description": "Null for tiled windows"
                },
                {
                  "type": "object",
                  "properties": {
                    "x": {
                      "type": "integer",
                      "minimum": 0,
                      "description": "X position in pixels"
                    },
                    "y": {
                      "type": "integer",
                      "minimum": 0,
                      "description": "Y position in pixels"
                    },
                    "width": {
                      "type": "integer",
                      "minimum": 1,
                      "description": "Width in pixels"
                    },
                    "height": {
                      "type": "integer",
                      "minimum": 1,
                      "description": "Height in pixels"
                    }
                  },
                  "required": ["x", "y", "width", "height"],
                  "description": "Geometry for floating windows"
                }
              ]
            },
            "original_scratchpad": {
              "type": "boolean",
              "default": false,
              "description": "True if window was in scratchpad before project filtering"
            }
          },
          "required": [
            "workspace_number",
            "floating",
            "project_name",
            "app_name",
            "window_class",
            "last_seen",
            "geometry",
            "original_scratchpad"
          ]
        }
      }
    }
  },
  "required": ["version", "last_updated", "windows"]
}
```

### Example Documents

#### Tiled Window (VSCode on workspace 2)
```json
{
  "94481823794032": {
    "workspace_number": 2,
    "floating": false,
    "project_name": "nixos",
    "app_name": "vscode",
    "window_class": "Code",
    "last_seen": 1761432863.7027514,
    "geometry": null,
    "original_scratchpad": false
  }
}
```

#### Floating Window (Calculator at position 100,200)
```json
{
  "94481823123456": {
    "workspace_number": 3,
    "floating": true,
    "project_name": "nixos",
    "app_name": "calculator",
    "window_class": "Gnome-calculator",
    "last_seen": 1761432900.1234567,
    "geometry": {
      "x": 100,
      "y": 200,
      "width": 400,
      "height": 300
    },
    "original_scratchpad": false
  }
}
```

#### Scratchpad Window (Notes app manually scratchpadded)
```json
{
  "94481823987654": {
    "workspace_number": -1,
    "floating": true,
    "project_name": "nixos",
    "app_name": "notes",
    "window_class": "Gnote",
    "last_seen": 1761432950.9876543,
    "geometry": {
      "x": 500,
      "y": 100,
      "width": 600,
      "height": 800
    },
    "original_scratchpad": true
  }
}
```

## Validation Rules

### Constraint: Geometry Consistency

**Rule**: `geometry` MUST be null for tiled windows, object for floating windows

**Validation Logic**:
```python
def validate_geometry_consistency(window_state: dict) -> bool:
    """Validate geometry field matches floating state."""
    floating = window_state.get("floating", False)
    geometry = window_state.get("geometry")

    if floating:
        # Floating windows SHOULD have geometry (but null is acceptable for old data)
        return geometry is None or (
            isinstance(geometry, dict) and
            all(k in geometry for k in ["x", "y", "width", "height"])
        )
    else:
        # Tiled windows MUST have null geometry
        return geometry is None
```

**Enforcement**: Validation is advisory only - daemon will handle inconsistencies gracefully

### Constraint: Workspace Number Range

**Rule**: `workspace_number` MUST be -1 (scratchpad) or 1-70 (workspace)

**Validation Logic**:
```python
def validate_workspace_number(workspace_number: int) -> bool:
    """Validate workspace number is in valid range."""
    return workspace_number == -1 or (1 <= workspace_number <= 70)
```

**Enforcement**: Invalid workspace numbers default to workspace 1 on restoration

### Constraint: Geometry Values

**Rule**: All geometry values MUST be non-negative integers

**Validation Logic**:
```python
def validate_geometry_values(geometry: dict) -> bool:
    """Validate geometry values are positive integers."""
    if not geometry:
        return True

    return all(
        isinstance(geometry.get(k), int) and geometry.get(k) >= 0
        for k in ["x", "y", "width", "height"]
    )
```

**Enforcement**: Invalid geometry is ignored, window restored without geometry

## State Transitions

### Transition Diagram

```
┌─────────────────┐
│ Window Created  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│ First Project Switch    │
│ (Capture Initial State) │
└────────┬────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Window Tracked in Map    │◄────┐
└────────┬─────────────────┘     │
         │                        │
         │ Project Switch (Hide)  │
         │                        │
         ▼                        │
┌──────────────────────────┐     │
│ Capture Current State    │     │
│ - Workspace              │     │
│ - Floating               │     │
│ - Geometry (if floating) │     │
│ - Scratchpad origin      │     │
└────────┬─────────────────┘     │
         │                        │
         ▼                        │
┌──────────────────────────┐     │
│ Move to Scratchpad       │     │
└────────┬─────────────────┘     │
         │                        │
         │ Project Switch (Show)  │
         │                        │
         ▼                        │
┌──────────────────────────┐     │
│ Load Saved State         │     │
└────────┬─────────────────┘     │
         │                        │
         ▼                        │
┌──────────────────────────┐     │
│ Restore to Workspace     │     │
│ + Restore Floating State │     │
│ + Restore Geometry       │     │
└────────┬─────────────────┘     │
         │                        │
         └────────────────────────┘
```

### State Transition Events

**Event 1: Window Created**
- **Trigger**: i3 window::new event
- **State Before**: Window doesn't exist in map
- **State After**: Window exists but not yet tracked
- **Action**: None (wait for first project switch)

**Event 2: First Project Switch (Hide)**
- **Trigger**: User switches away from window's project
- **State Before**: Window visible, not in map
- **State After**: Window in scratchpad, initial state captured in map
- **Action**: Query i3 for workspace, floating, geometry; save to map; move to scratchpad

**Event 3: Project Switch (Show)**
- **Trigger**: User switches to window's project
- **State Before**: Window in scratchpad, state in map
- **State After**: Window visible on workspace, state unchanged in map
- **Action**: Load state from map; move to workspace; restore floating + geometry

**Event 4: Project Switch (Hide Again)**
- **Trigger**: User switches away from window's project
- **State Before**: Window visible on workspace, old state in map
- **State After**: Window in scratchpad, updated state in map
- **Action**: Query i3 for current workspace, floating, geometry; update map; move to scratchpad

**Event 5: Window Manually Moved**
- **Trigger**: User moves window to different workspace while visible
- **State Before**: Window on workspace A, map shows workspace A
- **State After**: Window on workspace B, map still shows workspace A
- **Action**: None until next hide event (then map updates to workspace B)

**Event 6: Window Toggled Floating**
- **Trigger**: User toggles floating while window visible
- **State Before**: Window tiled, map shows floating=false
- **State After**: Window floating, map still shows floating=false
- **Action**: None until next hide event (then map updates floating + captures geometry)

## Backward Compatibility

### Missing Fields Handling

**Strategy**: Use Python dict.get() with default values

```python
# Loading window state with backward compatibility
window_state = window_map.get(str(window_id), {})

# Feature 037 fields (always present)
workspace_number = window_state.get("workspace_number", 1)
floating = window_state.get("floating", False)
project_name = window_state.get("project_name", "")
app_name = window_state.get("app_name", "")
window_class = window_state.get("window_class", "")
last_seen = window_state.get("last_seen", time.time())

# Feature 038 fields (may be missing in old files)
geometry = window_state.get("geometry", None)  # Default: None
original_scratchpad = window_state.get("original_scratchpad", False)  # Default: False
```

### Migration Path

**No explicit migration required**:
1. Old JSON files load successfully with defaults for new fields
2. First hide event after daemon restart captures new fields
3. After one full cycle of project switches, all windows have complete state

**Schema Version**: Not incremented - Feature 038 is backward-compatible extension

## Performance Considerations

### Storage

**Current File Size** (typical):
- ~15 windows × ~150 bytes/window = ~2.25 KB

**After Feature 038**:
- ~15 windows × ~200 bytes/window = ~3 KB
- **Increase**: ~750 bytes (~33% larger)
- **Impact**: Negligible (still <5 KB total)

### Read/Write Performance

**Read Performance**:
- Python JSON parsing: ~1ms for 3 KB file
- Dict lookups: O(1) per window
- **Total**: <2ms for typical workload

**Write Performance**:
- JSON serialization: ~1ms for 3 KB file
- File write: ~1ms (cached, async flush)
- **Total**: <2ms for typical workload

### Memory Usage

**In-Memory Map**:
- ~15 windows × ~300 bytes (Python dict overhead) = ~4.5 KB
- **Impact**: Negligible (<0.01% of daemon memory)

## Summary

**Schema Extension**: 2 new fields (`geometry`, `original_scratchpad`)
**Backward Compatibility**: Automatic via dict.get() defaults
**Validation**: Advisory only, graceful handling of invalid data
**Performance**: Negligible impact (~33% file size increase, <2ms read/write)
**Storage**: Single JSON file, extended schema, no migration required
