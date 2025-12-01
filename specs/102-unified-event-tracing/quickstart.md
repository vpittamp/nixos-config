# Quickstart: Unified Event Tracing System

**Feature**: 102-unified-event-tracing
**Date**: 2025-11-30

## Overview

Feature 102 unifies the event tracing system, making all i3pm internal events visible in the Log tab alongside raw Sway events, with cross-referencing between Log and Trace views, causality chain visualization, and trace templates for common debugging scenarios.

## Key Changes

### 1. i3pm Events in Log Tab

All i3pm internal events are now visible in the Log tab without starting a trace:

- **Project Events**: `project::switch`, `project::clear`
- **Visibility Events**: `visibility::hidden`, `visibility::shown`, `scratchpad::move`
- **Command Events**: `command::queued`, `command::executed`, `command::result`, `command::batch`
- **Launch Events**: `launch::intent`, `launch::notification`, `launch::env_injected`, `launch::correlated`
- **State Events**: `state::saved`, `state::loaded`, `state::conflict`

### 2. Enhanced Filter Categories

The Log tab filter panel now has 5 categories:

| Category | Event Types |
|----------|-------------|
| Window Events | new, close, focus, blur, move, floating, fullscreen, title, mark, urgent |
| Workspace Events | focus, init, empty, move, rename, urgent, reload |
| Output Events | connected, disconnected, profile_changed |
| **i3pm Events** | project, visibility, command, launch, state, trace |
| System Events | binding, mode, shutdown, tick |

### 3. Cross-Reference Navigation

- **Log → Trace**: Events with active traces show a trace indicator icon. Click to jump to Traces tab.
- **Trace → Log**: Click any trace event to scroll to the corresponding Log entry.

### 4. Causality Chain Visualization

Events with the same `correlation_id` are visually grouped:

```
project::switch (root, 0ms)                    # depth 0
  └─ visibility::hidden (window 1, +15ms)      # depth 1
  └─ visibility::hidden (window 2, +18ms)      # depth 1
  └─ command::batch (+25ms)                    # depth 1
      └─ command::result (+180ms)              # depth 2
```

Hover over any event to highlight the entire chain.

### 5. Trace Templates

Start common debugging traces with one click:

| Template | Description |
|----------|-------------|
| Debug App Launch | Pre-launch trace, lifecycle events, 60s timeout |
| Debug Project Switch | All scoped windows, visibility+command events |
| Debug Focus Chain | Focus/blur events only, focused window |

## Usage Examples

### View i3pm Events

1. Open monitoring panel: `Mod+M`
2. Switch to Log tab: `Alt+4` (or click "Log")
3. Enable "i3pm Events" filter category
4. Perform a project switch: `Mod+P` → select project
5. See `project::switch` event appear in the Log

### Debug a Project Switch

1. Open monitoring panel
2. Switch to Traces tab
3. Click "+" button → Select "Debug Project Switch"
4. Perform the project switch
5. See all visibility::hidden and command::* events in the trace timeline
6. Click any trace event to see corresponding Log entry

### Track a Causality Chain

1. Enable "i3pm Events" in Log tab
2. Perform a project switch
3. Observe grouped events with indentation
4. Hover over any event to highlight the full chain
5. View chain summary: "project::switch → 7 events, 185ms"

### Cross-Reference a Trace

1. Start a trace on a window (right-click context menu)
2. Switch to Log tab
3. See trace indicator (🔍) on events for traced window
4. Click indicator to jump to Traces tab
5. In Traces tab, click event to jump back to Log

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Mod+M` | Toggle monitoring panel |
| `Alt+4` | Switch to Log tab |
| `Alt+3` | Switch to Traces tab |
| `Mod+Shift+M` | Enter focus mode |
| `1-4` (focus mode) | Switch tabs |

## Filter State Variables

For scripting or debugging, the filter state is stored in Eww variables:

```bash
# Check if i3pm events are enabled
eww get filter_i3pm_all

# Enable all i3pm events
eww update filter_i3pm_all=true

# Enable only project events
eww update filter_i3pm_project=true
```

## Performance Considerations

- Log tab updates within 100ms of event receipt
- Event bursts >100/sec are batched with "N events collapsed" indicator
- Causality chains are computed on-demand (hover/click)
- Cross-references are indexed for O(1) lookup

## Troubleshooting

### Events Not Appearing

```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check event buffer
i3pm daemon events --type=project

# Restart monitoring panel
systemctl --user restart eww-monitoring-panel
```

### Trace Template Not Starting

```bash
# List available templates
i3pm traces templates

# Start manually
i3pm traces start --template debug-app-launch --app firefox
```

### Output Events All "unspecified"

Output event detection requires the daemon to have captured previous output state. After daemon restart, the first output event may be "unspecified" until state is cached.

## Related Documentation

- [Spec](./spec.md) - Full feature specification
- [Data Model](./data-model.md) - Entity definitions
- [IPC Methods](./contracts/ipc-methods.md) - API contracts
- [Feature 085](../085-sway-monitoring-widget/quickstart.md) - Monitoring panel basics
- [Feature 101](../101-worktree-click-switch/quickstart.md) - Trace system
