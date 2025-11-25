# Quickstart: Real-Time Event Log and Activity Stream

**Feature**: 092-logs-events-tab
**Date**: 2025-11-23
**Status**: Implementation Ready

## Overview

This feature adds a "Logs" tab to the Eww monitoring panel that displays real-time Sway window manager events (window creation, focus changes, workspace switches) with enriched metadata from the i3pm daemon.

---

## Quick Start

### 1. Enable the Feature

The Logs tab will be automatically included when you enable the eww-monitoring-panel module:

```nix
# File: /etc/nixos/home-vpittamp.nix (or your home-manager config)
programs.eww-monitoring-panel.enable = true;
```

### 2. Rebuild Configuration

```bash
# Test configuration
sudo nixos-rebuild dry-build --flake .#<target>

# Apply changes
sudo nixos-rebuild switch --flake .#<target>
```

### 3. Open Monitoring Panel

```bash
# Toggle panel visibility
Mod+M    # Default keybinding

# Or use explicit command
toggle-monitoring-panel
```

### 4. Switch to Logs Tab

Once the panel is open:
- Press `5` or `Alt+5` to switch to Logs tab
- Or click the "Logs" tab button in the header

---

## Usage Examples

### View Real-Time Events

Simply have the Logs tab open - events will stream automatically:

```
[10:34:12] 󰖲 window::new
  terminal-nixos-123 | nixos | WS 1

[10:34:15] 󰋁 window::focus
  code-nixos-456 | nixos | WS 2

[10:34:20] 󱂬 workspace::focus
  1 → 3 | HEADLESS-1
```

### Filter by Event Type

Click filter buttons to show only specific event types:

- **All**: Show all events (default)
- **Window**: Show only window:: events (new, close, focus, move)
- **Workspace**: Show only workspace:: events (focus, init, empty)
- **Output**: Show only output:: events (monitor changes)

### Search Events

Type in the search box to filter events by text:

```
Search: "firefox"
→ Shows only events involving Firefox windows

Search: "nixos"
→ Shows only events in the nixos project

Search: "workspace 3"
→ Shows only events related to workspace 3
```

### Pause/Resume Stream

To freeze the event view for reading:

```bash
# Click "Pause" button in UI
# Or use keyboard shortcut (if configured)
```

Events continue to buffer in the background (up to 500 events). Click "Resume" to see buffered events.

### Clear Event History

To clear all events and start fresh:

```bash
# Click "Clear" button in UI
```

---

## Event Types Reference

### Window Events

| Event | Icon | Description | Example |
|-------|------|-------------|---------|
| window::new | 󰖲 | New window created | Terminal launched in project |
| window::close | 󰖶 | Window closed | Firefox tab closed |
| window::focus | 󰋁 | Focus changed | Switched from VS Code to terminal |
| window::move | 󰁔 | Window moved to workspace | Moved terminal from WS 1 to WS 2 |
| window::floating | 󰉈 | Float state changed | Dialog became floating |

### Workspace Events

| Event | Icon | Description | Example |
|-------|------|-------------|---------|
| workspace::focus | 󱂬 | Workspace changed | Switched from WS 1 to WS 3 |
| workspace::init | 󰐭 | New workspace created | First window on WS 5 |
| workspace::empty | 󰭀 | Workspace became empty | Last window closed on WS 2 |
| workspace::move | 󰁔 | Workspace moved | WS 3 moved to different output |

### Output Events

| Event | Icon | Description | Example |
|-------|------|-------------|---------|
| output::unspecified | 󰍹 | Monitor changed | HEADLESS-2 connected |

---

## Keyboard Shortcuts

### In Monitoring Panel

| Key | Action |
|-----|--------|
| `5` or `Alt+5` | Switch to Logs tab |
| `Escape` or `q` | Close panel |
| `j` / `↓` | Scroll down (focus mode) |
| `k` / `↑` | Scroll up (focus mode) |

### Panel Visibility

| Key | Action |
|-----|--------|
| `Mod+M` | Toggle panel visibility |
| `Mod+Shift+M` | Enter focus mode (keyboard navigation) |

---

## Troubleshooting

### Events Not Appearing

**Symptom**: Logs tab is open but no events appear

**Diagnosis**:
```bash
# Check if backend service is running
systemctl --user status eww-monitoring-panel

# Check backend logs
journalctl --user -u eww-monitoring-panel -f
```

**Fix**:
```bash
# Restart backend service
systemctl --user restart eww-monitoring-panel
```

### Missing Event Enrichment

**Symptom**: Events show but no project names or app names

**Diagnosis**:
```bash
# Check if i3pm daemon is running
systemctl status i3-project-daemon

# Test daemon connectivity
i3pm daemon status
```

**Fix**:
```bash
# Start i3pm daemon (system service)
sudo systemctl start i3-project-daemon

# Or restart if already running
sudo systemctl restart i3-project-daemon
```

### Slow Event Display

**Symptom**: Events appear with >1 second delay

**Diagnosis**:
```bash
# Check backend performance logs
journalctl --user -u eww-monitoring-panel --since "1 minute ago" | grep "latency"
```

**Fix**:
```bash
# Reduce event buffer size (edit configuration)
# File: home-modules/desktop/eww-monitoring-panel.nix
# Find: EVENT_BUFFER_SIZE = 500
# Change to: EVENT_BUFFER_SIZE = 250

# Rebuild and restart
sudo nixos-rebuild switch --flake .#<target>
systemctl --user restart eww-monitoring-panel
```

### Panel Won't Open

**Symptom**: `Mod+M` does nothing

**Diagnosis**:
```bash
# Check if Eww is running
ps aux | grep eww

# Check Eww logs
journalctl --user -u eww-monitoring-panel --since "5 minutes ago"
```

**Fix**:
```bash
# Ensure Eww is enabled
# File: /etc/nixos/home-vpittamp.nix
programs.eww-monitoring-panel.enable = true;

# Rebuild and restart
sudo nixos-rebuild switch --flake .#<target>
systemctl --user restart eww-monitoring-panel
```

---

## Advanced Usage

### Manual Backend Query

Query events without the UI:

```bash
# One-shot query (current buffer state)
python3 -m i3_project_manager.cli.monitoring_data --mode events

# Stream events to terminal
python3 -m i3_project_manager.cli.monitoring_data --mode events --listen | jq
```

### Filter Events Programmatically

Use `jq` to filter JSON output:

```bash
# Show only window events
monitoring-data-backend --mode events --listen | \
  jq 'select(.events[].category == "window")'

# Show events for specific project
monitoring-data-backend --mode events --listen | \
  jq 'select(.events[].enrichment.project_name == "nixos")'
```

### Capture Event History

Save events to file for analysis:

```bash
# Capture 100 events to file
monitoring-data-backend --mode events --listen | \
  head -n 100 > events.jsonl

# Analyze with jq
cat events.jsonl | jq -s '.[].events[]'
```

---

## Configuration

### Event Buffer Size

Default: 500 events (FIFO eviction when full)

```nix
# File: home-modules/desktop/eww-monitoring-panel.nix
# Search for: EVENT_BUFFER_SIZE = 500
# Modify to desired size (100-1000 recommended)
```

### Event Batching Window

Default: 100ms debounce

```nix
# File: home-modules/tools/i3_project_manager/cli/monitoring_data.py
# Search for: BATCH_WINDOW_MS = 100
# Modify to desired milliseconds (50-500 range)
```

### Event Type Visibility

Hide specific event types from UI:

```yuck
; File: home-modules/desktop/eww-monitoring-panel.nix (Yuck section)
; Modify filter logic in logs-view widget:
(for event in {events_data.events}
  (box
    :visible {(event.event_type != "window::title")  ; Hide title change events
              && event_filter_matches(event)}
    (event-card :event event)))
```

---

## Performance Characteristics

### Normal Operation

- Event display latency: <100ms
- Filter response time: <200ms
- Memory usage: ~1MB for 500-event buffer
- CPU usage: <5% (single core)

### High Event Volume (50+ events/second)

- Event batching activates (100ms window)
- UI maintains 30fps rendering
- No dropped events (buffer overflow → FIFO eviction)

### Resource Limits

- Maximum buffer size: 500 events (~500KB)
- Maximum enrichment latency: 20ms per event
- Auto-reconnection: 5s maximum downtime

---

## Integration with Other Features

### Feature 085 (Monitoring Panel)

Logs tab shares the same panel UI:
- Consistent theme (Catppuccin Mocha)
- Unified keybindings (`Alt+1-5` for tabs)
- Same deflisten architecture

### Feature 088 (Health Tab)

Event log can diagnose health issues:
- See when services restart (window::close → window::new for service windows)
- Detect workspace assignment failures
- Monitor output connection changes

### Feature 091 (Performance Optimization)

Event log shows performance improvements:
- Project switch now generates fewer events (<10 vs 20+)
- Faster event throughput due to parallel command execution

---

## FAQ

**Q: Why do some events not have enrichment data?**
A: If the i3pm daemon is unavailable, events show raw Sway data without project associations or app names. Check `i3pm daemon status` to diagnose.

**Q: Can I export event history?**
A: Yes, use `monitoring-data-backend --mode events --listen > events.log` to capture events to file. Stop with Ctrl+C when done.

**Q: How far back does event history go?**
A: The buffer retains the last 500 events (configurable). Older events are automatically evicted (FIFO). For long-term history, use `sway-tree-monitor` (Feature 064) or system journal.

**Q: Can I filter multiple event types?**
A: Currently, only one event type filter can be active at a time. Use the search box for more specific filtering (e.g., search "window" to show all window:: events).

**Q: Why does the scroll position reset when new events arrive?**
A: This is "sticky scroll" behavior - if you're at the bottom of the list, it auto-scrolls to show new events. Scroll up to read history, and auto-scroll will pause.

**Q: Can I customize event icons?**
A: Yes, modify the `EVENT_ICONS` dictionary in `monitoring_data.py`. Use Nerd Fonts icons for best compatibility.

---

## Next Steps

After implementing this feature:

1. **Test with typical workflows**: Project switching, window management, workspace navigation
2. **Verify performance**: Check event latency and UI responsiveness during high activity
3. **Customize as needed**: Adjust buffer size, batching window, or filter defaults
4. **Consider extensions**:
   - Event export to file (FR-021 - future enhancement)
   - Advanced filtering (date ranges, combined filters)
   - Event replay (playback mode for debugging)

For detailed implementation guidance, see:
- `plan.md` - Implementation plan
- `research.md` - Technical research and decisions
- `data-model.md` - Data structures and schemas
- `contracts/backend-frontend-api.md` - API specification

---

## Support

For issues or questions:

1. Check logs: `journalctl --user -u eww-monitoring-panel -f`
2. Verify daemon: `i3pm daemon status`
3. Test backend: `monitoring-data-backend --mode events`
4. Review spec: `specs/092-logs-events-tab/`

---

**Feature Status**: Ready for implementation (Phase 2 planning complete)
**Next Phase**: `/speckit.tasks` to generate task breakdown
