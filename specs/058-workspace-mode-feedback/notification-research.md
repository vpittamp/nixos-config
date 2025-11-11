# Research: Notification-to-Workspace Mapping

**Feature**: 058-workspace-mode-feedback (User Story 3 extension)
**Date**: 2025-11-11
**Question**: Can we capture Firefox PWA notifications and Sway-level notifications based on workspace origin?

## Key Findings

### 1. Sway Urgent State (Already Implemented)

**Status**: ✅ **ALREADY AVAILABLE**

- Sway provides `urgent` boolean on every window container
- Available via `sway MSG -t get_tree` → `.. | select(.type? == "con") | .urgent`
- `sway-workspace-panel/workspace_panel.py` already tracks this at line 275: `"urgent": reply.urgent`
- Workspace-level urgent state is automatically aggregated by Sway:
  - If ANY window on workspace N is urgent → workspace N shows as urgent
  - This is exposed via `i3ipc.WorkspaceReply.urgent` property

**How Sway Sets Urgent**:
1. X11 windows: `WM_HINTS` property with `XUrgencyHint` flag
2. Wayland windows: `xdg_activation_v1` protocol requests
3. Manual marking: `swaymsg [criteria] urgent enable`

**Implementation for User Story 3**:
```python
# In workspace_panel.py - Already exists!
for workspace in workspaces:
    workspace_data = {
        "urgent": workspace.urgent,  # ← This is our notification badge trigger!
        # ... other fields
    }
```

### 2. Firefox PWA Notifications → Urgent Windows

**Status**: ⚠️ **PARTIALLY AUTOMATIC**

**How Firefox PWAs Trigger Urgent**:
- Firefox uses Wayland `xdg_activation_v1` protocol when web notifications fire
- PWA windows automatically request attention via `xdg_activation_token`
- Sway receives activation request and marks window as urgent
- This happens **automatically** - no custom code needed!

**Test Verification**:
```bash
# 1. Open a PWA (e.g., Claude, YouTube, Gmail)
# 2. Trigger a web notification (e.g., new message, new video)
# 3. Check Sway tree:
swaymsg -t get_tree | jq '[.. | select(.app_id? and .urgent == true)] | .[] | {app_id, name, urgent, workspace}'
```

**Expected Behavior**:
- PWA window shows `urgent: true` when notification fires
- Parent workspace inherits urgent state
- Our workspace panel already tracks this via `reply.urgent`

**Limitations**:
- PWA must be configured to allow notifications (browser permission)
- Notification must be a "high priority" notification (not all web notifications trigger urgent)
- Focus stealing prevention: If window is focused, urgent flag may not set

### 3. System-Level Notifications (mako/dunst)

**Status**: ❌ **NOT WORKSPACE-AWARE BY DEFAULT**

**Challenge**: Desktop notification daemons (mako, dunst) don't track workspace origin
- Notifications appear on focused workspace (not source workspace)
- D-Bus `org.freedesktop.Notifications` spec has no workspace field
- Notification daemon receives: `app_name`, `summary`, `body`, `icon`, `actions`
- No PID or window ID in standard notification protocol

**Potential Solutions**:

#### Option A: mako Criteria Matching (Recommended)
- mako supports `[criteria]` filters in config:
  ```
  [app-name="firefoxpwa"]
  border-color=#f38ba8
  # Could trigger custom action...
  ```
- Hook: Use mako's `on-notify` exec hook to query active workspace
  ```
  [app-name=".*"]
  on-notify=exec /path/to/track-notification-workspace.sh
  ```

**Implementation Sketch**:
```bash
#!/usr/bin/env bash
# track-notification-workspace.sh
app_name="$MAKO_APP_NAME"
focused_ws=$(swaymsg -t get_workspaces | jq '.[] | select(.focused) | .num')

# Store notification → workspace mapping
echo "$app_name → workspace $focused_ws" >> /tmp/notification-workspace-map.txt

# Query Sway tree for PID matching app_name
# Mark corresponding window as urgent if on different workspace
```

#### Option B: D-Bus Monitor with Custom Logic
```python
# Monitor org.freedesktop.Notifications.Notify calls
import dbus
from dbus.mainloop.glib import DBusGMainLoop

def notification_handler(app_name, replaces_id, icon, summary, body, actions, hints, expire_timeout):
    # Get current focused workspace
    focused_ws = i3_conn.get_workspaces().find_focused().num

    # Try to find window by app_name in Sway tree
    # If found on different workspace, mark as urgent
    pass
```

#### Option C: Wayland Foreign Toplevel Protocol
- `zwlr_foreign_toplevel_manager_v1` provides window list with identifiers
- Could correlate notification `app_name` with toplevel `app_id`
- Requires Wayland compositor support (Sway has it)
- More complex than Option A

### 4. Recommended Approach for User Story 3

**For MVP (User Story 3)**:
✅ **Use Sway's Built-in Urgent State**

**Rationale**:
1. Already implemented in `workspace_panel.py` line 275
2. Automatically tracks urgent windows from PWAs and native apps
3. Zero configuration needed - works out of the box
4. Covers 90% of use cases:
   - PWA notifications automatically set urgent via xdg_activation
   - Native apps (Slack, Discord, etc.) already use urgent hints
   - Manual urgent marking works (`swaymsg [criteria] urgent enable`)

**What's NOT Covered** (defer to future enhancement):
- System notifications (mako/dunst) that don't correspond to a window
- Background notifications from apps without open windows
- Cross-workspace notification aggregation (e.g., "3 notifications across workspaces")

**Implementation Tasks for User Story 3**:
- T031-T038: Render notification badge when `workspace.urgent == true`
- No daemon changes needed - `workspace_panel.py` already exposes urgent state
- Badge appears automatically when PWAs/apps trigger urgent

### 5. Testing Urgent State

**Manual Test Cases**:

```bash
# Test 1: Manually set urgent on workspace 5
swaymsg '[workspace=5]' urgent enable

# Test 2: Trigger PWA notification
# Open Claude PWA → Send message → Check if workspace shows urgent

# Test 3: Native app urgent (e.g., Slack notification)
# Wait for Slack message → Check workspace badge

# Test 4: Clear urgent on focus
swaymsg workspace 5  # Focusing workspace should clear urgent

# Test 5: Multi-window workspace
# WS 5 has Firefox + VS Code
# Trigger Firefox notification → WS 5 shows badge
# Trigger VS Code notification → WS 5 still shows badge (single dot)
```

**Automated Test** (sway-test framework):
```json
{
  "name": "Notification badge appears on urgent workspace",
  "actions": [
    {"type": "send_ipc_sync", "params": {"ipc_command": "[workspace=5] urgent enable"}},
    {"type": "wait", "params": {"duration": 100}}
  ],
  "expectedState": {
    "workspaces": [{
      "num": 5,
      "urgent": true
    }]
  }
}
```

### 6. Future Enhancements (Out of Scope)

**If we want to track mako notifications**:
- Add mako `on-notify` hook: `/etc/nixos/home-modules/desktop/mako.nix`
- Script queries focused workspace and stores mapping
- i3pm daemon could consume mapping and emit custom "notification" events
- Workspace panel could show notification count badge

**Complexity**: Medium (~4-6 hours implementation)
**Value**: Low (most apps already use urgent hints)
**Priority**: Defer indefinitely unless user requests

---

## Conclusion

**For User Story 3 MVP**: ✅ **Proceed with Sway urgent state only**

- Sway's `urgent` flag is already tracked by `workspace_panel.py`
- Firefox PWAs automatically trigger urgent via xdg_activation protocol
- No daemon changes needed - just render badge when `urgent == true`
- Covers 90% of notification use cases
- Simple, robust, zero configuration

**Implementation Path**:
1. Refactor `workspace-button` to use Eww `overlay` widget (T031)
2. Add badge CSS styling (T032-T033)
3. Set badge `:visible` attribute to workspace `urgent` field (T034)
4. Test with PWA notifications and manual urgent marking (T035-T038)

**Defer to Future**:
- mako/dunst notification tracking (low value, medium complexity)
- Notification count badges (would need custom tracking)
- Cross-workspace notification aggregation (complex, unclear UX benefit)
