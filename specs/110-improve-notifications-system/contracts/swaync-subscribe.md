# Contract: SwayNC Subscribe Event Stream

**Version**: 1.0.0
**Date**: 2025-12-02

## Overview

Documents the upstream SwayNC `--subscribe` event stream format that the notification monitor consumes.

## Source

**Command**: `swaync-client --subscribe`
**Protocol**: Line-delimited JSON to stdout
**Upstream**: [SwayNotificationCenter](https://github.com/ErikReider/SwayNotificationCenter)

## Schema

### SwayNCSubscribeEvent

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "SwayNCSubscribeEvent",
  "description": "Event emitted by swaync-client --subscribe",
  "type": "object",
  "required": ["count", "dnd", "visible", "inhibited"],
  "properties": {
    "count": {
      "type": "integer",
      "minimum": 0,
      "description": "Number of notifications currently in SwayNC"
    },
    "dnd": {
      "type": "boolean",
      "description": "Do Not Disturb mode is enabled"
    },
    "visible": {
      "type": "boolean",
      "description": "Notification control center panel is visible"
    },
    "inhibited": {
      "type": "boolean",
      "description": "Notifications are inhibited by an application"
    }
  },
  "additionalProperties": false
}
```

## Example Events

**Initial state (on subscribe)**:
```json
{ "count": 2, "dnd": false, "visible": false, "inhibited": false }
```

**New notification arrives**:
```json
{ "count": 3, "dnd": false, "visible": false, "inhibited": false }
```

**Notification dismissed**:
```json
{ "count": 2, "dnd": false, "visible": false, "inhibited": false }
```

**DND toggled on**:
```json
{ "count": 2, "dnd": true, "visible": false, "inhibited": false }
```

**Control center opened**:
```json
{ "count": 2, "dnd": false, "visible": true, "inhibited": false }
```

**All notifications cleared**:
```json
{ "count": 0, "dnd": false, "visible": true, "inhibited": false }
```

## Event Triggers

| Action | Event Emitted |
|--------|---------------|
| `notify-send "Title" "Body"` | count increments |
| User dismisses notification | count decrements |
| `swaync-client --close-all` | count becomes 0 |
| `swaync-client --toggle-dnd` | dnd toggles |
| `swaync-client --toggle-panel` | visible toggles |
| `swaync-client --open-panel` | visible becomes true |
| `swaync-client --close-panel` | visible becomes false |
| App adds inhibitor | inhibited may change |

## Comparison: --subscribe vs --subscribe-waybar

| Field | `--subscribe` | `--subscribe-waybar` |
|-------|---------------|----------------------|
| `count` | Integer | N/A |
| `text` | N/A | String (count) |
| `dnd` | Boolean | N/A |
| `visible` | Boolean | N/A |
| `alt` | N/A | "notification" or "none" |
| `tooltip` | N/A | Human-readable message |
| `class` | N/A | CSS class name |

**Decision**: Use `--subscribe` for richer data (dnd, visible fields).

## Reliability

- SwayNC emits initial state immediately on subscribe
- Events are emitted synchronously on state change
- No heartbeat/keepalive (connection status inferred from process)
- Daemon restart terminates the subscribe process

## Version Compatibility

- Schema stable since SwayNC 0.8+
- `inhibited` field added in SwayNC 0.9+
- Tested with nixpkgs version (as of 2025-12)
