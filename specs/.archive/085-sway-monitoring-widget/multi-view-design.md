# Multi-View Monitoring Widget Design
**Feature**: 085-sway-monitoring-widget
**Date**: 2025-11-20
**Status**: Design Phase

## Overview

Transform the monitoring widget from a single-view window list into a comprehensive developer tool with multiple views, transient change notifications, and rich UX interactions.

## Views

### 1. Windows View (Current/Enhanced)
**Purpose**: Live window/project state visualization
**Data Source**: `monitoring_data.py` (existing)
**Layout**: Project-based hierarchy with workspace badges
**Features**:
- Transient notification overlay when windows added/removed
- Color-coded project sections
- Expandable project details (click to expand/collapse)
- Window count badges
- Real-time updates via deflisten

### 2. Projects View
**Purpose**: Comprehensive project management overview
**Data Source**: `i3pm project list --json`
**Layout**: Card-based grid or list view
**Features**:
- Project icon, name, display name
- Directory path
- Created/updated timestamps
- Active status indicator (current project highlighted)
- Click to switch projects
- Hover for detailed info tooltip
- Quick actions: switch, open directory, view windows

**Data Structure**:
```json
{
  "projects": [
    {
      "name": "nixos",
      "directory": "/etc/nixos",
      "display_name": "NixOS",
      "icon": "❄️",
      "created_at": "...",
      "updated_at": "...",
      "is_active": true,
      "window_count": 5
    }
  ]
}
```

### 3. Apps/PWAs View
**Purpose**: Application registry browser with configuration details
**Data Source**: App registry data from Nix + runtime state
**Layout**: Searchable list with expandable detail panels
**Features**:
- List all registered apps (regular + PWAs)
- Show: name, display name, workspace, scope, icon
- Expandable detail panel shows:
  - Command + parameters
  - Expected class
  - Monitor role preference
  - Floating size
  - Multi-instance support
  - Nix package
  - Launch count (runtime stat)
  - Currently running instances
- Click app name to launch
- Hover for quick preview
- Filter by scope (scoped/global), type (app/PWA), workspace
- Color coding: PWAs in teal, scoped apps in blue, global in gray

**Data Structure**:
```json
{
  "apps": [
    {
      "name": "terminal",
      "display_name": "Terminal",
      "command": "ghostty",
      "parameters": "-e sesh connect $PROJECT_DIR",
      "scope": "scoped",
      "preferred_workspace": 1,
      "preferred_monitor_role": "primary",
      "icon": "/path/to/icon.svg",
      "multi_instance": true,
      "is_pwa": false,
      "running_instances": 3,
      "window_ids": [123456, 234567, 345678]
    }
  ]
}
```

### 4. Events View
**Purpose**: Live event stream from Sway/i3pm with filtering
**Data Source**: Daemon event stream (Feature 064/065 patterns)
**Layout**: Scrollable log with timestamps and color coding
**Features**:
- Real-time event stream (window, workspace, project, output events)
- Color-coded by type:
  - Window events: blue
  - Workspace events: green
  - Project events: purple
  - Output/monitor events: orange
  - Errors: red
- Timestamp for each event (friendly format)
- Event details: type, window ID, workspace, project
- Filter controls: event type, time range
- Auto-scroll toggle
- Export to JSON button
- Clear log button

**Data Structure**:
```json
{
  "events": [
    {
      "timestamp": 1700000000.123,
      "timestamp_friendly": "Just now",
      "type": "window::new",
      "category": "window",
      "window_id": 123456,
      "app_name": "terminal",
      "workspace": 1,
      "project": "nixos",
      "details": "Terminal launched in nixos project"
    }
  ]
}
```

### 5. Health View
**Purpose**: System diagnostics and health status
**Data Source**: `i3pm diagnose health`, daemon status, monitor status
**Layout**: Dashboard with status cards
**Features**:
- Daemon health status (running, responsive, uptime)
- Connection status (i3pm daemon, Sway IPC)
- Performance metrics (event processing rate, memory usage)
- Monitor configuration status
- Workspace assignment validation
- Error count and recent errors
- Quick actions: restart daemon, reload config, run full diagnosis

**Data Structure**:
```json
{
  "health": {
    "daemon_status": "healthy",
    "daemon_uptime": 3600,
    "daemon_pid": 12345,
    "sway_ipc_connected": true,
    "monitor_count": 3,
    "workspace_count": 7,
    "window_count": 12,
    "project_count": 4,
    "errors_24h": 0,
    "warnings_24h": 2,
    "last_error": null,
    "performance": {
      "avg_event_latency_ms": 15,
      "events_processed_1h": 245,
      "memory_mb": 45
    }
  }
}
```

## Navigation System

### Tab Bar Design
- Horizontal tab bar at top of panel
- Icons + labels for each view
- Active tab highlighted (blue/teal border)
- Hover effect on inactive tabs
- Keyboard shortcuts (Alt+1-5)

**Tab Icons**:
- Windows: 󰖯 (window grid)
- Projects: 󱂬 (folder tree)
- Apps: 󰀻 (app grid)
- Events:  (activity/pulse)
- Health:  (heart/health)

### View Switching
- Click tab to switch view
- Smooth fade transition (200ms)
- Preserve scroll position per view
- Keyboard navigation:
  - Alt+1: Windows
  - Alt+2: Projects
  - Alt+3: Apps
  - Alt+4: Events
  - Alt+5: Health
  - Alt+Left/Right: Previous/Next tab

## Transient Change Notifications

### Window Add/Remove Indicator
**Trigger**: When window count changes
**Display**: Floating pill/badge at bottom-right of panel
**Content**: "+AppName" (green) or "-AppName" (red)
**Duration**: 3 seconds, then fade out (500ms fade)
**Stacking**: Multiple changes stack vertically (max 3 visible)
**Animation**: Slide in from right, pulse once, fade out

**Visual Design**:
```
┌─────────────────────┐
│ +Terminal          │  (green background, white text)
└─────────────────────┘
```

**Implementation**:
- Backend tracks previous window list
- On change, emit notification event
- Frontend displays notification overlay
- Auto-remove after timeout

## UX Interactions

### Hover Effects
- Apps view: Show quick info tooltip (workspace, scope, command)
- Projects view: Show directory path and window count
- Events view: Expand event details
- Tabs: Highlight and show keyboard shortcut

### Click Actions
- Apps: Click to launch or focus running instance
- Projects: Click to switch project
- Events: Click event to copy details to clipboard
- Expandable sections: Click to toggle expand/collapse

### Search/Filter
- Apps view: Search by name, filter by workspace/scope
- Events view: Filter by type, time range
- Projects view: Search by name/directory

## Backend Architecture

### Data Query Modes
```python
def query_monitoring_data(mode: str = "windows"):
    """
    Query data for different views.

    Modes:
    - windows: Current window/project hierarchy (existing)
    - projects: Full project list with stats
    - apps: App registry with runtime state
    - events: Recent event stream
    - health: System diagnostics
    """
```

### Event Change Detection
```python
# Track previous state
prev_window_ids = set()
curr_window_ids = set(window.id for window in windows)

# Detect changes
added = curr_window_ids - prev_window_ids
removed = prev_window_ids - curr_window_ids

# Emit notifications
for window_id in added:
    emit_notification(f"+{window.app_name}", "green")
for window_id in removed:
    emit_notification(f"-{window.app_name}", "red")
```

## Frontend Architecture

### Widget Structure
```yuck
(defwindow monitoring-panel
  ;; Tab bar
  (box :class "tabs"
    (button :class "tab ${current_view == 'windows' ? 'active' : ''}"
            :onclick "set-view windows" "󰖯 Windows")
    (button :class "tab ${current_view == 'projects' ? 'active' : ''}"
            :onclick "set-view projects" "󱂬 Projects")
    ;; ... other tabs
  )

  ;; View container (dynamic content)
  (box :class "view-container"
    (revealer :reveal {current_view == "windows"}
      (windows-view))
    (revealer :reveal {current_view == "projects"}
      (projects-view))
    ;; ... other views
  )

  ;; Notification overlay
  (box :class "notifications"
    (for notif in notifications
      (notification-pill :notif notif))))
```

### State Management
```bash
# Eww variables
(defvar current_view "windows")
(defvar notifications [])

# Deflisten for each view
(deflisten windows_data :initial "{}"
  `monitoring_data.py --mode windows --listen`)
(deflisten projects_data :initial "{}"
  `monitoring_data.py --mode projects`)
# ... other data sources
```

## Performance Considerations

- **Lazy loading**: Only query data for active view
- **Event throttling**: Batch rapid changes (max 10 notifications/sec)
- **Memory**: Limit event log to 500 entries
- **Updates**: Windows view real-time, others refresh every 5s or on-demand

## Implementation Phases

### Phase 1: Core Multi-View (Current Focus)
- Tab navigation system
- Windows view (existing + enhancements)
- Projects view
- View switching logic

### Phase 2: Transient Notifications
- Window change detection
- Notification overlay system
- Animation/fade logic

### Phase 3: Apps View
- App registry data query
- App list rendering
- Expandable detail panels
- Launch integration

### Phase 4: Events & Health
- Events view with live stream
- Health view with diagnostics
- Filter controls

### Phase 5: Polish & UX
- Hover effects
- Smooth transitions
- Keyboard navigation
- Search/filter functionality
