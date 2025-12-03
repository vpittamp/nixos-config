# Research: Feature 110 - Unified Notification System

**Date**: 2025-12-02
**Status**: Complete

## Research Questions

### 1. SwayNC Subscribe API Format

**Question**: What format does `swaync-client --subscribe` output?

**Finding**: SwayNC provides two subscribe modes:

```bash
# Standard subscribe (our choice)
swaync-client --subscribe
# Output: { "count": 2, "dnd": false, "visible": false, "inhibited": false }

# Waybar format
swaync-client --subscribe-waybar
# Output: {"text": "2", "alt": "notification", "tooltip": "2 Notifications", "class": "notification"}
```

**Decision**: Use `--subscribe` (standard format) - it provides:
- `count`: Number of notifications (integer)
- `dnd`: Do Not Disturb status (boolean)
- `visible`: Control center visibility (boolean)
- `inhibited`: Inhibitor status (boolean)

**Rationale**: Standard format provides all fields we need for FR-001 through FR-005. The waybar format is designed for waybar's specific JSON protocol and lacks the `visible` field.

---

### 2. Streaming Pattern for Eww

**Question**: What pattern should the notification monitor use for real-time updates?

**Finding**: Feature 085 established the `deflisten` pattern for event-driven Eww updates:

```python
# From monitoring_data.py
async def stream_mode():
    """Stream mode: Subscribe to events and output JSON on changes."""
    async with I3Connection() as conn:
        # Subscribe to events
        conn.on('window', on_event)
        conn.on('workspace', on_event)
        await conn.main()
```

For SwayNC, the approach is simpler - `swaync-client --subscribe` already streams JSON:

```python
# Proposed notification-monitor.py
import subprocess
import sys

proc = subprocess.Popen(
    ['swaync-client', '--subscribe'],
    stdout=subprocess.PIPE,
    text=True
)
for line in proc.stdout:
    # Transform to match expected format
    data = json.loads(line)
    output = {
        "count": data.get("count", 0),
        "dnd": data.get("dnd", False),
        "visible": data.get("visible", False),
        "has_unread": data.get("count", 0) > 0
    }
    print(json.dumps(output), flush=True)
```

**Decision**: Use Python subprocess wrapper around `swaync-client --subscribe` for:
1. Transform/enrich output (add `has_unread` computed field)
2. Handle reconnection on daemon restart
3. Graceful degradation on daemon unavailability

**Rationale**: Matches established patterns while keeping implementation simple.

---

### 3. Badge Display Overflow Handling

**Question**: How should the badge handle high notification counts?

**Finding**: Common patterns from research:
- iOS: Shows "99+" for counts > 99
- Android: Shows "9+" for counts > 9 (compact)
- macOS Dock: Shows "9+" for counts > 9
- Most desktop Linux tools: No cap (leads to overflow)

**Decision**: Cap display at "9+" (9 or more shows "9+")

**Rationale**:
- Matches FR-007 from spec
- "9+" fits cleanly in badge width (~16px)
- Full count available in tooltip (FR-009)
- Aligns with mobile platform conventions

---

### 4. CSS Animation for Pulsing Glow

**Question**: What CSS pattern achieves the pulsing glow effect?

**Finding**: Existing pattern from `eww.scss.nix` for monitoring toggle:

```scss
@keyframes pulse-notification {
  0%, 100% {
    box-shadow: 0 0 12px rgba(137, 180, 250, 0.5);
  }
  50% {
    box-shadow: 0 0 18px rgba(137, 180, 250, 0.7);
  }
}

.notification-toggle-active {
  animation: pulse-notification 3s ease-in-out infinite;
}
```

**Decision**: Use same pattern with adjusted colors:
- Badge glow: Red/peach gradient (`#f38ba8`, `#fab387`)
- Active state: Blue glow (`#89b4fa`)
- Animation: 2s cycle (slightly faster for urgency)

**Rationale**: Consistent with existing Eww styling patterns.

---

### 5. Error State Handling

**Question**: How should the widget behave when SwayNC daemon is unavailable?

**Finding**: Feature 085 monitoring panel handles daemon unavailability by:
1. Showing "Connecting..." state initially
2. Auto-reconnecting with exponential backoff
3. Showing "Disconnected" after max retries

**Decision**: For notification badge:
1. Show muted/inactive icon when daemon unavailable (hide badge)
2. Auto-reconnect when daemon becomes available
3. Log connection issues to journal (not visible in UI)

**Rationale**: Notifications are non-critical - silent degradation is appropriate.

---

### 6. Icon Selection

**Question**: Which Nerd Font icons represent notification states best?

**Finding**: Nerd Font bell icons:
- `󰂚` (nf-md-bell) - Bell with content/active
- `󰂜` (nf-md-bell_outline) - Empty bell
- `󰂛` (nf-md-bell_off) - Bell with slash (DND)
- `󰂞` (nf-md-bell_ring) - Ringing bell (new notification)

**Decision**:
- No notifications: `󰂜` (outline)
- Has notifications: `󰂚` (filled)
- DND enabled: `󰂛` (slash)
- Control center open: Use active styling (glow) with filled icon

**Rationale**: Consistent with standard notification iconography.

---

## Alternative Approaches Evaluated

### Alternative 1: Pure Polling (defpoll)

**Rejected**: Would require polling SwayNC state every N seconds. Violates FR-012 (event-driven) and wastes CPU.

### Alternative 2: End-rs (Eww-native notifications)

**Rejected**: Would replace SwayNC entirely with a custom Rust daemon. Too complex for badge display; SwayNC already provides rich notification management.

### Alternative 3: D-Bus Direct Subscription

**Rejected**: `swaync-client --subscribe` already provides the event stream we need. D-Bus subscription adds complexity without benefit.

### Alternative 4: Waybar Integration

**Rejected**: Already have Eww top bar (Feature 060). Adding Waybar would violate modular composition principles and introduce a second bar system.

---

## Implementation Summary

| Component | Approach | Rationale |
|-----------|----------|-----------|
| Event source | `swaync-client --subscribe` | Native streaming, no custom daemon needed |
| Eww integration | `deflisten` with Python wrapper | Transform output, handle reconnection |
| Badge display | "9+" cap | Mobile convention, fits width |
| Animation | CSS keyframes (2s pulse) | Matches existing patterns |
| Error handling | Silent degradation | Non-critical feature |
| Icons | Nerd Font bell variants | Standard iconography |

---

## Dependencies Confirmed

- **SwayNC**: Version in nixpkgs has `--subscribe` flag (verified via CLI test)
- **Eww**: `deflisten` supported (used in Feature 085)
- **Python**: 3.11+ in path (verified)
- **Nerd Fonts**: JetBrainsMono Nerd Font installed (in current config)
