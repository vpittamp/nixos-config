# Contract: Eww Deflisten - Notification Monitor

**Version**: 1.0.0
**Date**: 2025-12-02

## Overview

This contract defines the JSON schema for the notification monitor streaming output consumed by Eww's `deflisten` mechanism.

## Source

**Script**: `~/.config/eww/eww-top-bar/scripts/notification-monitor.py`
**Protocol**: Line-delimited JSON to stdout
**Trigger**: SwayNC daemon events (notification add/remove/dismiss, DND toggle, panel toggle)

## Schema

### NotificationDataOutput

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "NotificationDataOutput",
  "description": "Notification state for Eww top bar badge widget",
  "type": "object",
  "required": ["count", "dnd", "visible", "has_unread", "display_count"],
  "properties": {
    "count": {
      "type": "integer",
      "minimum": 0,
      "description": "Number of notifications in SwayNC"
    },
    "dnd": {
      "type": "boolean",
      "description": "Do Not Disturb mode enabled"
    },
    "visible": {
      "type": "boolean",
      "description": "Notification center panel is open"
    },
    "inhibited": {
      "type": "boolean",
      "description": "Notifications are inhibited by an application"
    },
    "has_unread": {
      "type": "boolean",
      "description": "Computed: count > 0"
    },
    "display_count": {
      "type": "string",
      "pattern": "^([0-9]|9\\+)$",
      "description": "Badge display text: '0'-'9' or '9+' for overflow"
    }
  },
  "additionalProperties": false
}
```

### Examples

**No notifications**:
```json
{"count": 0, "dnd": false, "visible": false, "inhibited": false, "has_unread": false, "display_count": "0"}
```

**3 notifications**:
```json
{"count": 3, "dnd": false, "visible": false, "inhibited": false, "has_unread": true, "display_count": "3"}
```

**15 notifications (overflow)**:
```json
{"count": 15, "dnd": false, "visible": false, "inhibited": false, "has_unread": true, "display_count": "9+"}
```

**DND enabled with notifications**:
```json
{"count": 5, "dnd": true, "visible": false, "inhibited": false, "has_unread": true, "display_count": "5"}
```

**Control center open**:
```json
{"count": 2, "dnd": false, "visible": true, "inhibited": false, "has_unread": true, "display_count": "2"}
```

## Eww Consumer

```yuck
;; Deflisten variable definition
(deflisten notification_data
  :initial '{"count":0,"dnd":false,"visible":false,"inhibited":false,"has_unread":false,"display_count":"0"}'
  `python3 ~/.config/eww/eww-top-bar/scripts/notification-monitor.py`)

;; Widget consuming the data
(defwidget notification-badge []
  (box :class {notification_data.has_unread ? "notification-has-unread" : "notification-empty"}
    (label :text {notification_data.display_count})
    (label :class "icon" :text {notification_data.dnd ? "󰂛" : notification_data.has_unread ? "󰂚" : "󰂜"})))
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| SwayNC daemon not running | Script exits, Eww uses `:initial` value |
| SwayNC daemon restarts | Script reconnects automatically |
| Malformed JSON from SwayNC | Skip line, log to stderr |
| Script crashes | Eww uses last valid value, systemd restarts script |

## Versioning

- **1.0.0** (2025-12-02): Initial schema with count, dnd, visible, has_unread, display_count
