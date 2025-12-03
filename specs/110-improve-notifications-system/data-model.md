# Data Model: Feature 110 - Unified Notification System

**Date**: 2025-12-02
**Status**: Complete

## Entities

### NotificationState

Represents the current notification system state from SwayNC.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `count` | integer | Number of notifications (0-N) | SwayNC `--subscribe` |
| `dnd` | boolean | Do Not Disturb enabled | SwayNC `--subscribe` |
| `visible` | boolean | Control center panel open | SwayNC `--subscribe` |
| `inhibited` | boolean | Notifications inhibited | SwayNC `--subscribe` |

**Computed Fields** (added by Python wrapper):

| Field | Type | Description | Derivation |
|-------|------|-------------|------------|
| `has_unread` | boolean | True if count > 0 | `count > 0` |
| `display_count` | string | Badge display text | `"9+" if count > 9 else str(count)` |

### BadgeState

Represents the visual state of the notification badge in Eww.

| State | Icon | CSS Class | Badge Visible | Animation |
|-------|------|-----------|---------------|-----------|
| `no_notifications` | `󰂜` | `notification-toggle` | No | None |
| `has_unread` | `󰂚` | `notification-toggle notification-has-unread` | Yes | `pulse-unread` |
| `dnd_enabled` | `󰂛` | `notification-toggle notification-dnd` | Optional | None |
| `center_open` | `󰂚` | `notification-toggle notification-toggle-active` | Yes | `pulse-notification` |
| `error` | `󰂜` | `notification-toggle notification-error` | No | None |

### State Transitions

```
                    ┌────────────────────────────────────────┐
                    │                                        │
                    ▼                                        │
    ┌──────────────────────────┐                             │
    │     no_notifications     │◄────────────────────────────┤
    │  icon: 󰂜  badge: hidden  │                             │
    └──────────────────────────┘                             │
              │                                              │
              │ notification arrives (count > 0)             │
              ▼                                              │
    ┌──────────────────────────┐                             │
    │       has_unread         │                             │
    │  icon: 󰂚  badge: [N]     │──── click ────────────────┐ │
    │  animation: pulse-unread │                           │ │
    └──────────────────────────┘                           │ │
              │                                            │ │
              │ all dismissed (count = 0)                  │ │
              │                                            ▼ │
              │                              ┌─────────────────────┐
              └──────────────────────────────│     center_open     │
                                             │  icon: 󰂚  badge: [N]│
                                             │  animation: pulse   │
                                             └─────────────────────┘
                                                       │
                                                       │ close/escape
                                                       │
                                                       ▼
                                             (returns to previous state)


    DND can be enabled from any state:
    ┌──────────────────────────┐
    │      dnd_enabled         │
    │  icon: 󰂛  badge: [N]     │
    │  (overrides other icons) │
    └──────────────────────────┘
```

## Data Flow

```
SwayNC Daemon                   Python Wrapper                    Eww
     │                               │                             │
     │ Event: notification add/remove│                             │
     ├──────────────────────────────►│                             │
     │                               │ Transform + enrich          │
     │ JSON: {count,dnd,visible,...} │                             │
     │                               │ JSON: {count,dnd,visible,   │
     │                               │        has_unread,          │
     │                               │        display_count}       │
     │                               ├────────────────────────────►│
     │                               │                             │
     │                               │                             │ Update widget
     │                               │                             │ (deflisten var)
     │                               │                             │
     │                               │                Click        │
     │                               │◄────────────────────────────┤
     │ toggle-swaync script          │                             │
     │◄──────────────────────────────┤                             │
     │                               │                             │
     │ Panel opens/closes            │                             │
     ├──────────────────────────────►│                             │
     │                               ├────────────────────────────►│
```

## Validation Rules

| Field | Rule | Error Behavior |
|-------|------|----------------|
| `count` | Non-negative integer | Default to 0 |
| `dnd` | Boolean | Default to false |
| `visible` | Boolean | Default to false |
| JSON parse | Valid JSON line | Skip malformed line, log warning |
| Daemon connection | Process alive | Attempt reconnect with backoff |

## Eww Variable Schema

```yuck
;; Variable bound to notification-monitor.py deflisten
(deflisten notification_data
  :initial '{"count":0,"dnd":false,"visible":false,"has_unread":false,"display_count":"0"}'
  `python3 ~/.config/eww/eww-top-bar/scripts/notification-monitor.py`)
```

**Access patterns in Yuck**:
- `notification_data.count` - Raw count (integer)
- `notification_data.dnd` - DND status (boolean)
- `notification_data.visible` - Center open (boolean)
- `notification_data.has_unread` - Has unread (boolean)
- `notification_data.display_count` - Badge text (string: "0"-"9" or "9+")
