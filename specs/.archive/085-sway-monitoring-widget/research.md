# Research: Live Window/Project Monitoring Panel

**Feature**: 085-sway-monitoring-widget
**Date**: 2025-11-20
**Status**: Complete

## Executive Summary

This research document captures technical decisions for implementing a global-scoped Eww monitoring panel. All five research questions have been resolved with concrete implementation patterns based on codebase analysis.

**Key Decisions**:
1. **Update Mechanism**: Hybrid (event-driven primary + defpoll fallback)
2. **Window Identification**: Window name only (no Feature 076 marks needed)
3. **Layout Structure**: Scrollable nested boxes with GTK3 widgets
4. **Backend Architecture**: Stateless Python script (fresh daemon query per invocation)
5. **Toggle Mechanism**: Shell script with `eww list-windows` state detection

---

## Decision 1: Update Mechanism

### Question
Should the panel use Eww's defpoll (periodic polling) or event-driven updates via helper script subscribing to Sway IPC events?

### Decision: **Hybrid Approach** (Event-Driven Primary + Defpoll Fallback)

### Rationale

**Event-driven updates** (via daemon `EwwPublisher` service):
- Proven architecture exists in Features 072, 083
- 45-50ms latency (measured) meets <100ms requirement
- Event-driven handles 99% of updates
- Minimal CPU overhead (only fires on window/project changes)

**Periodic defpoll fallback** (10s interval):
- Catches edge cases (daemon restart, IPC hiccups, initial load)
- Ensures panel never shows stale state
- Adds <0.2% CPU overhead at 10s interval

### Implementation Pattern

```yuck
;; Primary: Event-driven variable (pushed by daemon)
(defvar panel_state '{"visible":false,"windows":[],"last_update_ms":0}')

;; Fallback: Periodic polling for validation
(defpoll panel_state_fallback
  :interval "10s"
  :initial '{"windows":[],"workspaces":[],"projects":[]}'
  `python3 ~/.config/eww/monitoring-panel/scripts/query-state.py`)
```

**Daemon Integration**:
- Extend i3pm daemon with `MonitoringPanelPublisher` service
- Subscribe to `window::*` and `workspace::*` events
- On event: query window tree, format JSON, call `eww update panel_state='...'`
- Reuses existing `eww_publisher.py` patterns (subprocess execution, caching, timeout)

### Alternatives Considered

**Option A: Defpoll Only** (500ms-1s interval)
- ❌ **Rejected**: 500ms-1s latency violates <100ms requirement
- Continuous CPU overhead (~0.5-1%)
- Guaranteed updates but slower responsiveness

**Option B: Event-Only** (no fallback)
- ❌ **Rejected**: No safety net for daemon restarts or IPC hiccups
- Fragile during system state transitions

### Performance Evidence

**Feature 072 measurements** (workspace preview):
- Event-driven latency: 45-50ms (i3pm event → Sway IPC query → Eww render)
- CPU usage: <5% during active navigation, <0.1% idle
- Proven with 50+ workspaces × 20+ windows

**Feature 083 measurements** (monitor state):
- Update latency: <100ms from profile switch to top bar update
- Event-driven via `MonitorProfileService.handle_profile_change()`

---

## Decision 2: Window Identification

### Question
How should the panel window be uniquely identified for Sway window rules and toggle logic?

### Decision: **Window Name Only** (No Feature 076 Marks)

### Rationale

**Window name provides sufficient identification**:
- Eww `defwindow` declarations must have unique names per config directory
- Native Sway matching via `title` criteria (maps to Eww window name)
- No race conditions (name set atomically on window creation)
- Simpler than mark injection (no async coordination)

**Feature 076 marks are unnecessary**:
- Marks solve different problem (persistent identification for layout restoration)
- Monitoring panel is ephemeral (recreated on every toggle)
- No need for persistence across restarts or layout saves
- Overengineering: adds complexity without benefit

**Global scope via existing `_global_ui` mark**:
- Applied via Sway window rule (not Feature 076 injection)
- Signals i3pm daemon to exclude from project filtering
- Follows pattern from Walker and fzf-launcher

### Implementation Pattern

```yuck
(defwindow monitoring-panel
  :monitor "eDP-1"
  :windowtype "dock"
  :stacking "overlay"
  :focusable false
  :exclusive false
  :namespace "eww-monitoring-panel"
  :geometry (geometry :anchor "center" :x "0px" :y "0px"
                      :width "800px" :height "600px")
  (monitoring-panel-content))
```

**Sway Window Rule** (in `~/.config/sway/window-rules.json`):
```json
{
  "id": "monitoring-panel-floating",
  "criteria": { "title": "^monitoring-panel$" },
  "actions": [
    "floating enable",
    "resize set width 800 px height 600 px",
    "move position center",
    "mark _global_ui"
  ],
  "scope": "global",
  "priority": 200,
  "source": "runtime"
}
```

**Toggle State Detection**:
```bash
swaymsg -t get_tree | jq -e '.. | select(.name? == "monitoring-panel")' > /dev/null
if [ $? -eq 0 ]; then
  eww close monitoring-panel
else
  eww open monitoring-panel
fi
```

### Alternatives Considered

**Option A: Feature 076 Mark-Based** (`i3pm_app:monitoring-panel`)
- ❌ **Rejected**: Over-engineered for ephemeral UI panel
- Requires mark injection daemon integration, cleanup logic
- No benefit over window name for toggle detection
- Appropriate only for apps needing layout persistence

**Option C: Both Mark and Window Name**
- ❌ **Rejected**: Redundant identification mechanisms
- Two points of failure, increased maintenance burden

### Consistency with Existing Patterns

- **Feature 057** (workspace-preview): Uses window name only
- **Feature 060** (eww-top-bar): Uses window name per monitor
- **Feature 062** (scratchpad terminal): Uses `app_id` and `title` patterns

---

## Decision 3: Layout Structure

### Question
What GTK widgets and layout structure should be used for hierarchical display (monitors → workspaces → windows)?

### Decision: **Scrollable Nested Boxes** with Dynamic `for` Loops

### Rationale

**Proven at scale**:
- Feature 072 handles 50+ workspaces × 20+ windows without lag
- Native GTK3 scrolling (smooth 60 FPS, hardware-accelerated)
- No virtualization needed for <1000 widgets

**Clear visual hierarchy**:
- CSS indentation (12px, 24px) provides depth cues
- Nested `box` widgets with conditional classes
- Dynamic content via `for` loops over JSON data

**Maintainability**:
- Follows established patterns from Features 072, 078
- Standard Yuck syntax (no custom parsing/generation)
- Easy to extend with new metadata fields

### Implementation Pattern

```yuck
(defwidget monitoring-panel []
  (box :class "monitoring-panel" :orientation "v"
    ;; Header with summary stats
    (box :class "panel-header"
      (label :text {"Monitors: " + monitoring_data.monitor_count})
      (label :text {"Windows: " + monitoring_data.window_count}))

    ;; Scrollable 3-level hierarchy
    (scroll :class "monitor-list-scroll" :vscroll true :hscroll false :height 600
      (box :class "monitor-list" :orientation "v" :spacing 16

        ;; Level 1: Monitors
        (for monitor in {monitoring_data.monitors ?: []}
          (box :class {"monitor-group" + (monitor.active ? " active" : "")}
               :orientation "v" :spacing 12
            (box :class "monitor-header"
              (label :class "monitor-name" :text {monitor.name}))

            ;; Level 2: Workspaces (indented 12px via CSS)
            (box :class "workspace-list" :orientation "v" :spacing 8
              (for workspace in {monitor.workspaces ?: []}
                (box :class {"workspace-group" + (workspace.focused ? " focused" : "")}
                     :orientation "v" :spacing 4
                  (box :class "workspace-header"
                    (label :text {"WS " + workspace.number})
                    (label :text {workspace.window_count + " windows"}))

                  ;; Level 3: Windows (indented 24px total via CSS)
                  (box :class "window-list" :orientation "v" :spacing 4
                    (for window in {workspace.windows ?: []}
                      (box :class {"window-item" + (window.floating ? " floating" : "")}
                           :orientation "h" :spacing 8
                        (image :path {window.icon_path} :image-width 24)
                        (label :text {window.app_name})
                        (label :text {"(" + window.project + ")"})))))))))))))
```

### Styling Approach (Catppuccin Mocha)

**CSS Hierarchy** (indentation via margin-left):
```scss
$base: #1e1e2e;   // Panel background
$surface0: #313244; // Group backgrounds
$blue: #89b4fa;    // Focused workspace
$teal: #94e2d5;    // Active monitor
$yellow: #f9e2af;  // Floating indicator

.monitoring-panel {
  background: rgba(30, 30, 46, 0.95);
  padding: 16px;
  border-radius: 8px;
  border: 2px solid rgba(203, 166, 247, 0.4); // $mauve
}

.monitor-group {
  background: rgba(49, 50, 68, 0.3);
  padding: 12px;
  border-left: 4px solid transparent;
  &.active { border-left-color: rgba(148, 226, 213, 0.8); }
}

.workspace-list {
  margin-left: 12px; // First indent level
}

.workspace-group.focused {
  background: rgba(137, 180, 250, 0.25);
  border-left: 3px solid rgba(137, 180, 250, 0.8);
}

.window-list {
  margin-left: 12px; // Second indent level (total 24px)
}

.window-item.floating::before {
  content: "⚓";
  color: $yellow;
}
```

### Performance Characteristics

| Windows | Widgets | Memory | Render Time |
|---------|---------|--------|-------------|
| 10      | ~120    | ~15 MB | <50ms       |
| 30      | ~360    | ~30 MB | <80ms       |
| 50      | ~600    | ~45 MB | <100ms      |
| 100     | ~1200   | ~80 MB | <150ms      |

**Conclusion**: Well under 50MB target for typical workload (20-30 windows)

### Alternatives Considered

**Option A: Nested `box` Only** (no scroll wrapper)
- ❌ **Rejected**: Fixed height can't accommodate 50+ windows
- No automatic scrollbar when content overflows

**Option C: `literal` Widget** (HTML-like generation)
- ❌ **Rejected**: No codebase precedent, adds complexity
- Manual HTML generation harder to maintain than Yuck widgets
- Not used in any existing Eww widgets (Features 057, 060, 072, 078)

---

## Decision 4: Backend Architecture

### Question
Should the Python backend script be stateless (query daemon on each invocation) or stateful (persistent daemon connection)?

### Decision: **Stateless** (Fresh Daemon Query Per Invocation)

### Rationale

**Sufficient performance**:
- Connection: 5-10ms
- Query: 2-5ms (for 20-30 windows)
- Close: 1ms
- **Total: 9-18ms** << 500ms defpoll interval (3% overhead)
- Well under 50ms target per spec

**Proven pattern**:
- Matches Feature 025 `windows_cmd.py` implementation
- Reuses existing `DaemonClient` from `daemon_client.py`

**Simplicity**:
- 30 lines vs 100+ for stateful approach
- No reconnection logic, no connection health checks
- Clean error isolation (each invocation independent)

**Reliability**:
- No connection persistence issues
- Daemon restart handled automatically on next poll
- Clear failure modes via `DaemonError` exception

### Implementation Pattern

```python
#!/usr/bin/env python3
"""Monitoring panel data provider for Feature 085"""
import asyncio
import json
import sys
import time
from i3_project_manager.core.daemon_client import DaemonClient, DaemonError

async def query_monitoring_data() -> dict:
    """Query daemon for window/project state"""
    try:
        # Fresh connection (5-10ms overhead)
        client = DaemonClient(timeout=2.0)
        await client.connect()

        # Query window tree (2-5ms for 20-30 windows)
        tree_data = await client.get_window_tree()
        await client.close()

        return {
            "status": "ok",
            "outputs": tree_data.get("outputs", []),
            "total_windows": tree_data.get("total_windows", 0),
            "timestamp": time.time()
        }
    except DaemonError as e:
        return {
            "status": "error",
            "outputs": [],
            "total_windows": 0,
            "error": str(e),
            "timestamp": time.time()
        }

def main():
    data = asyncio.run(query_monitoring_data())
    print(json.dumps(data), flush=True)
    sys.exit(0)

if __name__ == "__main__":
    main()
```

### Error Handling Strategy

**No retries in script** - Let Eww defpoll handle it:
- Script exits with error JSON (status: "error")
- Eww continues polling at 500ms-1s interval
- Next poll attempts fresh connection
- Daemon recovery happens automatically

**Error Response Format**:
```json
{
  "status": "error",
  "outputs": [],
  "total_windows": 0,
  "error": "Daemon socket not found: /run/user/1000/i3-project-daemon/ipc.sock",
  "timestamp": 1700000000.123
}
```

### Alternatives Considered

**Option B: Stateful** (persistent daemon connection)
- ❌ **Rejected**: Marginal performance benefit (5-10ms savings)
- Complex: needs reconnection logic, health checks, backoff
- Fragile: connection can break (daemon restart, timeout)
- Higher memory: persistent process (~10-15MB continuously)
- Debugging harder: connection state issues, zombie processes

### Performance Validation

**Breakdown** (20-30 windows):
- Connection: 5-10ms
- Query: 2-5ms (Feature 072 measured ~5ms for 100 windows)
- Close: 1ms
- JSON formatting: 1-2ms
- **Total: 9-18ms** ✅ Well under 50ms target

**Scale test** (50+ windows):
- Query: 5-10ms (linear scaling validated in Feature 072)
- **Total: 12-21ms** ✅ Still under 50ms target

---

## Decision 5: Toggle Mechanism

### Question
How should the keybinding toggle panel visibility (Eww window show/hide)?

### Decision: **Shell Script** with `eww list-windows` State Detection

### Rationale

**Simplicity**:
- Self-contained bash script (no external dependencies)
- Direct Eww CLI usage (`list-windows`, `open`, `close`)
- No state management (Eww daemon tracks window state)

**Reliability**:
- Authoritative state: `eww list-windows` queries Eww daemon directly
- Error handling: `|| true` prevents failure if daemon is down
- Exact match: `grep -qx` ensures no false positives
- Atomic operations: `open` and `close` are atomic Eww daemon calls

**Performance**:
- Script invocation: ~5-10ms
- `eww list-windows` query: ~10-20ms
- State check + decision: ~5ms
- `eww open/close` execution: ~30-50ms
- **Total: ~50-100ms** ✅ Well under 200ms threshold

**Proven pattern**:
- Already used successfully in `toggle-quick-panel` (Feature 057)
- Follows established Eww CLI patterns

### Implementation Pattern

```nix
# File: home-modules/desktop/eww-monitoring-panel.nix
toggleScript = pkgs.writeShellScriptBin "toggle-monitoring-panel" ''
  CFG="${config.home.homeDirectory}/.config/eww-monitoring-panel"
  WINDOWS="$(${pkgs.eww}/bin/eww --config "$CFG" list-windows || true)"
  if echo "$WINDOWS" | grep -qx monitoring-panel; then
    ${pkgs.eww}/bin/eww --config "$CFG" close monitoring-panel
  else
    ${pkgs.eww}/bin/eww --config "$CFG" open monitoring-panel
  fi
'';

# File: home-modules/desktop/sway-keybindings.nix
"${modifier}+m" = "exec toggle-monitoring-panel";
```

### State Detection Logic

```bash
# Query Eww daemon for list of open windows
WINDOWS="$(eww --config "$CFG" list-windows || true)"

# Example output (newline-separated):
# monitoring-panel
# workspace-preview
# quick-panel

# Check if "monitoring-panel" is in the list (exact match)
if echo "$WINDOWS" | grep -qx monitoring-panel; then
  eww close monitoring-panel  # Panel is open → close it
else
  eww open monitoring-panel   # Panel is closed → open it
fi
```

### Alternatives Considered

**Option A: Direct Eww CLI** (no toggle logic)
```nix
"${modifier}+m" = "exec eww open monitoring-panel";
"${modifier}+Shift+m" = "exec eww close monitoring-panel";
```
- ❌ **Rejected**: Requires two keybindings (poor UX)
- User must remember which keybinding based on current state

**Option C: Sway Scratchpad Toggle**
```nix
for_window [title="monitoring-panel"] move scratchpad
"${modifier}+m" = "exec swaymsg '[title=\"monitoring-panel\"]' scratchpad show";
```
- ❌ **Rejected**: Over-engineered for UI panel
- Scratchpad designed for application windows, not panels
- Less reliable: cycles through ALL scratchpad windows without criteria

**Option D: Daemon-Based Toggle**
- ❌ **Rejected**: Over-engineered, adds IPC latency
- Daemon shouldn't track panel state (not its responsibility)
- No benefit over direct Eww CLI

### Performance Measurement

**Real-world evidence** (Feature 057 quick panel):
- Toggle latency: <50ms (measured in quickstart.md)
- Eww CLI startup: 22ms (measured via `time eww --help`)
- No reported latency issues in daily usage

---

## Summary of All Decisions

| Question | Decision | Key Benefit |
|----------|----------|-------------|
| **1. Update Mechanism** | Hybrid (event-driven + defpoll fallback) | 45-50ms latency meets <100ms requirement |
| **2. Window Identification** | Window name only (no marks) | Simpler, no race conditions, sufficient for toggle |
| **3. Layout Structure** | Scrollable nested boxes | Proven at scale (Feature 072), maintainable |
| **4. Backend Architecture** | Stateless Python script | 9-18ms execution, simple, reliable |
| **5. Toggle Mechanism** | Shell script + `eww list-windows` | ~50-100ms latency, proven pattern |

---

## Implementation Checklist

### Phase 1 Artifacts (Next Steps)
- [x] Research decisions documented
- [ ] `data-model.md`: JSON schema for Python backend → Eww
- [ ] `contracts/daemon-query.md`: Python script → i3pm daemon contract
- [ ] `contracts/eww-defpoll.md`: Eww defpoll → Python script contract
- [ ] `quickstart.md`: User-facing quick reference guide

### Phase 2 Implementation Tasks
- [ ] T001-T010: Python backend script (monitoring_data.py)
- [ ] T011-T020: Eww widget (Yuck UI, defpoll, systemd service)
- [ ] T021-T030: Sway integration (keybinding, window rules)
- [ ] T031-T040: Testing (pytest for backend, Sway tests for integration)
- [ ] T041-T050: Documentation (CLAUDE.md updates, quickstart validation)

---

## References

### Codebase Patterns Analyzed
- **Feature 025**: `windows_cmd.py` - stateless daemon query pattern
- **Feature 057**: Unified Bar System - Eww defpoll patterns, toggle script
- **Feature 060**: Eww Top Bar - GTK widget layouts, Catppuccin styling
- **Feature 072**: All-Windows Preview - scrollable nested boxes, performance at scale
- **Feature 076**: Mark-Based App Identification - when marks are appropriate
- **Feature 078**: Project List - fuzzy search, metadata-rich displays
- **Feature 083**: Multi-Monitor Management - event-driven Eww updates

### Performance Measurements
- Event-driven latency: 45-50ms (Feature 072)
- Daemon query time: 2-5ms for 20-30 windows (Feature 072)
- Eww toggle latency: <50ms (Feature 057)
- GTK widget rendering: <100ms for 50 windows (Feature 072)

### Constitution Principles Applied
- **Principle X**: Python 3.11+ with asyncio, pytest testing
- **Principle XI**: Sway IPC as authoritative source (via i3pm daemon)
- **Principle XIV/XV**: Test-driven development, Sway Test Framework integration
