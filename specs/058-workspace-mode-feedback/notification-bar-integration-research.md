# Research: Notification Bar Integration with Eww

**Feature**: 058-workspace-mode-feedback
**Date**: 2025-11-11
**Question**: Should we integrate notification daemon more tightly with our Eww workspace bar?

## Current Setup

### What We Have

**Notification Daemon**: SwayNC (Sway Notification Center)
- Running as systemd service: `systemd.user.services.swaync`
- Config: `~/.config/swaync/config.json`
- Styling: `~/.config/swaync/style.css`
- D-Bus service: `org.freedesktop.Notifications`

**Status Bar**: Eww Workspace Bar
- Custom Python-based workspace panel
- Shows workspace buttons with icons
- **NEW (Feature 058)**: Shows urgent badges on workspace buttons
- Location: `home-modules/desktop/eww-workspace-bar.nix`

**Current Notification Flow**:
```
PWA/App notification fires
    ↓
SwayNC receives via D-Bus (org.freedesktop.Notifications)
    ↓
SwayNC displays toast notification (top-right corner)
    ↓
Firefox PWA triggers xdg_activation_v1 (Wayland protocol)
    ↓
Sway marks window as URGENT
    ↓
Our Eww bar shows red badge on workspace button ✅
```

**What Works Well**:
- SwayNC handles all desktop notifications
- Toast notifications appear in top-right corner
- SwayNC control center (`swaync-client -t`) shows notification history
- Our Eww bar shows workspace-level urgent badges (Feature 058)

---

## Research: Notification + Bar Integration Options

### Option 1: Keep Current Separation (Recommended)

**Status**: This is what we currently have

**Pros**:
- ✅ Clean separation of concerns
- ✅ SwayNC is mature, feature-rich notification daemon
- ✅ Our Eww bar focuses on workspace management
- ✅ Urgent badges already provide workspace-level awareness
- ✅ No overlap - SwayNC shows notification content, Eww shows workspace state
- ✅ Both systems work independently and reliably

**Cons**:
- Notifications appear in separate UI (SwayNC toast) vs workspace bar
- No notification count indicator in Eww bar

**When to use**: If workspace urgent badges are sufficient for awareness

---

### Option 2: Add SwayNC Widget to Eww Bar

**Approach**: Add a clickable SwayNC indicator to our Eww workspace bar

**Implementation**:
```yuck
;; In eww.yuck
(defpoll swaync_count :interval "1s"
  "swaync-client -c")  ; Get notification count

(defpoll swaync_dnd :interval "1s"
  "swaync-client -D")  ; Get DND status

(defwidget swaync-indicator []
  (button
    :class "swaync-button"
    :onclick "sleep 0.1 && swaync-client -t -sw"  ; Toggle control center (with sleep fix)
    :onrightclick "sleep 0.1 && swaync-client -d -sw"  ; Toggle DND
    (box
      (label :text {swaync_dnd == "true" ? "🔕" : "🔔"})
      (label :text {swaync_count > 0 ? swaync_count : ""}))))
```

**CSS Styling**:
```scss
.swaync-button {
  background: rgba(30, 30, 46, 0.3);
  padding: 3px 8px;
  border-radius: 4px;
  border: 1px solid rgba(108, 112, 134, 0.3);
}

.swaync-button:hover {
  background: rgba(137, 180, 250, 0.15);
}
```

**Pros**:
- ✅ Notification count visible in bar
- ✅ One-click access to notification center
- ✅ DND toggle integrated
- ✅ Low implementation effort (~30 minutes)
- ✅ Keeps SwayNC's full functionality

**Cons**:
- ⚠️ Requires `sleep 0.1` workaround (known SwayNC/Waybar issue)
- ⚠️ Polling every 1s adds minor overhead
- ⚠️ Emoji icon less polished than SVG

**Best Practices** (from Waybar integration):
- Always add `sleep 0.1` before `swaync-client` commands (prevents click blocking)
- Use `-sw` flag to subscribe to updates for real-time changes
- Poll interval 1-5s is typical

**When to use**: If you want notification count/DND status visible in bar

---

### Option 3: End - Native Eww Notification Daemon

**Project**: https://github.com/lucalabs-de/end
**Status**: Third-party project, written in Haskell

**What it is**: Replaces SwayNC entirely, renders notifications as Eww widgets

**How it works**:
```yuck
;; In eww.yuck
(defvar end-notifications "")  ; Required variable

(defwindow notifications
  :monitor 0
  :geometry (geometry :anchor "top right"
                       :x "10px"
                       :y "50px")
  (box :orientation "v"
       :space-evenly false
       (literal :content end-notifications)))
```

**Configuration** (`~/.config/end/config.toml`):
```toml
eww-default-notification-key = "notification"  # Widget name
eww-window = "notifications"  # Window to render in
max-notifications = 5
notification-orientation = "v"  # vertical stack

[timeouts]
low = 3000
normal = 5000
critical = 0  # Never timeout
```

**Pros**:
- ✅ Native Eww integration (notifications ARE Eww widgets)
- ✅ Full control over notification appearance
- ✅ Consistent styling with workspace bar
- ✅ Can display notifications inline or in separate window
- ✅ Custom widgets per notification urgency level

**Cons**:
- ❌ Immature project (less than 100 GitHub stars)
- ❌ Haskell dependency (adds complexity to NixOS config)
- ❌ Less feature-rich than SwayNC (no control center, history, etc.)
- ❌ Requires rewriting notification styling from scratch
- ❌ No DND mode, no notification actions UI
- ❌ Potentially less stable than SwayNC

**When to use**: If you want notifications to BE part of your Eww setup, and willing to trade features for consistency

---

### Option 4: Custom D-Bus Listener in Eww Bar

**Approach**: Add a Python script that listens to D-Bus notifications and updates an Eww variable

**Implementation Sketch**:
```python
#!/usr/bin/env python3
# ~/.config/eww/scripts/notification-listener.py
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

notification_count = 0

def notification_handler(app_name, replaces_id, icon, summary, body, actions, hints, expire_timeout):
    global notification_count
    notification_count += 1
    print(notification_count, flush=True)  # Eww reads stdout

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
bus.add_signal_receiver(
    notification_handler,
    dbus_interface="org.freedesktop.Notifications",
    signal_name="Notify"
)

loop = GLib.MainLoop()
loop.run()
```

**Eww Integration**:
```yuck
(deflisten notification_count
  :initial "0"
  "~/.config/eww/scripts/notification-listener.py")

(defwidget notification-indicator []
  (label :text {notification_count > 0 ? "🔔 ${notification_count}" : ""}))
```

**Pros**:
- ✅ Real-time updates (no polling)
- ✅ Lightweight (single Python script)
- ✅ Can coexist with SwayNC
- ✅ Full control over what data is displayed

**Cons**:
- ⚠️ Requires custom Python script
- ⚠️ Doesn't provide notification content (just count)
- ⚠️ Still need SwayNC or another daemon to display actual notifications
- ⚠️ More complex than Option 2 (polling)

**When to use**: If you want real-time notification count without polling, but keep SwayNC for display

---

## Comparison Matrix

| Feature | Current | Option 2: SwayNC Widget | Option 3: End | Option 4: D-Bus Listener |
|---------|---------|-------------------------|---------------|--------------------------|
| **Notification Count in Bar** | ❌ | ✅ | ✅ | ✅ |
| **Workspace Urgent Badges** | ✅ (Feature 058) | ✅ | ✅ | ✅ |
| **Toast Notifications** | ✅ (SwayNC) | ✅ (SwayNC) | ✅ (Eww) | ✅ (SwayNC) |
| **Notification History** | ✅ (SwayNC) | ✅ (SwayNC) | ❌ | ✅ (SwayNC) |
| **DND Mode** | ✅ (SwayNC) | ✅ (SwayNC) | ❌ | ✅ (SwayNC) |
| **Notification Actions** | ✅ (SwayNC) | ✅ (SwayNC) | ⚠️ (Limited) | ✅ (SwayNC) |
| **Styling Consistency** | ⚠️ (Separate) | ⚠️ (Separate) | ✅ (Unified Eww) | ⚠️ (Separate) |
| **Implementation Effort** | ✅ (Done) | 30 min | 2-4 hours | 1-2 hours |
| **Maintenance Burden** | ✅ (Low) | ✅ (Low) | ⚠️ (Medium) | ⚠️ (Medium) |
| **Maturity** | ✅ (Stable) | ✅ (Stable) | ⚠️ (Beta) | ✅ (Stable libs) |

---

## Recommendations

### Short-Term (Recommended): Option 2 - Add SwayNC Widget

**Why**:
1. ✅ **Minimal risk** - SwayNC continues to work, we just add a widget
2. ✅ **Quick win** - 30 minutes implementation
3. ✅ **User benefit** - See notification count at a glance
4. ✅ **DND toggle** - Right-click to toggle Do Not Disturb
5. ✅ **Proven pattern** - Waybar users do this successfully

**Implementation Plan**:
1. Add `defpoll` for `swaync-client -c` (notification count)
2. Add `defpoll` for `swaync-client -D` (DND status)
3. Create `swaync-indicator` widget with bell icon + count
4. Add CSS styling matching workspace buttons
5. Include `sleep 0.1` fix in click handlers

**Where to add**: Right side of workspace bar, after workspace buttons

**Example Visual**:
```
[WS 1] [WS 2] [WS 3] ... [WS 52] [WS 53]    [🔔 3]
                                              ↑ New SwayNC widget
```

### Medium-Term (Optional): Option 4 - D-Bus Listener

**When**: If polling SwayNC every 1s becomes a performance concern (unlikely)

**Why**:
- More efficient (event-driven vs polling)
- Still keeps SwayNC for full notification management
- Can capture additional metadata (app_name, urgency, etc.)

### Long-Term (Not Recommended): Option 3 - End

**Why not**:
- SwayNC is mature and feature-complete
- End is immature and missing features (history, DND, actions)
- Haskell dependency adds complexity
- No clear user benefit over SwayNC + Eww widget

**When to reconsider**:
- If End project matures significantly
- If you want notifications to visually match Eww bar exactly
- If SwayNC has compatibility issues (none currently)

---

## Implementation: Option 2 (SwayNC Widget)

### Step 1: Add Eww Widget

**Location**: `home-modules/desktop/eww-workspace-bar.nix`

**Add to `ewwYuck`**:
```nix
ewwYuck = ''
${workspaceMarkupDefs}

; SwayNC notification indicator (Feature 058 enhancement)
(defpoll swaync_count :interval "2s"
  "${pkgs.swaynotificationcenter}/bin/swaync-client -c")

(defpoll swaync_dnd :interval "2s"
  "${pkgs.swaynotificationcenter}/bin/swaync-client -D")

(defwidget swaync-indicator []
  (button
    :class {
      "swaync-button "
      + (swaync_dnd == "true" ? "dnd-active " : "")
      + (swaync_count > 0 ? "has-notifications" : "no-notifications")
    }
    :tooltip {
      swaync_dnd == "true"
        ? "Do Not Disturb (${swaync_count} notifications)"
        : (swaync_count > 0 ? "${swaync_count} notification(s)" : "No notifications")
    }
    :onclick "sleep 0.1 && ${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw"
    :onrightclick "sleep 0.1 && ${pkgs.swaynotificationcenter}/bin/swaync-client -d -sw"
    (box :class "swaync-pill" :orientation "h" :space-evenly false :spacing 3
      (label :class "swaync-icon" :text {swaync_dnd == "true" ? "🔕" : "🔔"})
      (label :class "swaync-count" :text {swaync_count > 0 ? swaync_count : ""}))))

(defwidget workspace-button [number_label workspace_name app_name icon_path icon_fallback workspace_id focused visible urgent pending empty]
  ; ... existing widget ...
)

(defwidget workspace-strip [output_label markup_var]
  (box :class "workspace-bar"
    (label :class "workspace-output" :text output_label)
    (box :class "workspace-strip"
         :orientation "h"
         :halign "center"
          :spacing 3
      (literal :content markup_var))
    (swaync-indicator)))  ; Add indicator to right side

; ... window blocks ...
'';
```

### Step 2: Add CSS Styling

**Add to `ewwScss`**:
```scss
/* SwayNC indicator (Feature 058 enhancement) */
.swaync-button {
  background: rgba(30, 30, 46, 0.3);
  padding: 3px 8px;
  margin-left: 8px;
  border-radius: 4px;
  border: 1px solid rgba(108, 112, 134, 0.3);
  transition: all 0.2s;
}

.swaync-button:hover {
  background: rgba(137, 180, 250, 0.15);
  border: 1px solid rgba(137, 180, 250, 0.4);
}

.swaync-button.has-notifications {
  background: rgba(137, 180, 250, 0.25);
  border: 1px solid rgba(137, 180, 250, 0.5);
}

.swaync-button.dnd-active {
  background: rgba(249, 226, 175, 0.25);  /* Yellow for DND */
  border: 1px solid rgba(249, 226, 175, 0.6);
}

.swaync-pill {
  margin: 0;
  padding: 0;
}

.swaync-icon {
  font-size: 11pt;
}

.swaync-count {
  font-size: 9pt;
  font-weight: 600;
  color: $blue;
  min-width: 12px;
}

.swaync-button.dnd-active .swaync-count {
  color: $yellow;
}
```

### Step 3: Test

```bash
# Rebuild
sudo nixos-rebuild switch --flake .#hetzner-sway

# Restart Eww
systemctl --user restart eww-workspace-bar

# Test notification
notify-send "Test" "This is a test notification"

# Check count appears in bar
# Click bell icon → SwayNC control center opens
# Right-click bell icon → DND mode toggles
```

---

## Conclusion

**Recommendation**: Implement **Option 2 (SwayNC Widget)** as a short-term enhancement

**Rationale**:
1. ✅ Low risk, high value
2. ✅ Quick implementation (30 minutes)
3. ✅ Proven pattern from Waybar community
4. ✅ Keeps SwayNC's full feature set
5. ✅ Complements existing urgent badges (Feature 058)

**Defer**:
- Option 3 (End): Project too immature, SwayNC is better
- Option 4 (D-Bus Listener): Unnecessary complexity for polling concern that doesn't exist

**Current Status**: Our workspace urgent badges (Feature 058) already provide excellent workspace-level notification awareness. Adding a SwayNC widget gives us system-level notification count/DND status, completing the picture.

---

## Future Enhancements (Out of Scope)

**Per-Workspace Notification Counts**:
- Track which workspace has pending notifications
- Show count badge on workspace button (separate from urgent state)
- Requires custom D-Bus listener + state tracking

**Notification Preview on Hover**:
- Hover workspace button → show notification preview tooltip
- Requires reading SwayNC's notification database
- Medium complexity, unclear user benefit

**Inline Notification Stream**:
- Show mini notification cards in bar
- Like agnoster theme's git status inline
- High complexity, questionable UX in compact bar

**Conclusion**: SwayNC widget provides 80% of value with 20% of effort. Ship it.
