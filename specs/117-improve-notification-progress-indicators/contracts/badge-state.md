# Contract: Badge State File

**Version**: 1.0.0
**Feature**: 117-improve-notification-progress-indicators

## Overview

Badge state files store notification indicator state for Sway windows. Files are the single source of truth for badge state - no IPC or daemon state is authoritative.

## File Location

```
$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json
```

Where:
- `$XDG_RUNTIME_DIR` is typically `/run/user/<uid>`
- `<window_id>` is the Sway container ID (integer)

Example: `/run/user/1000/i3pm-badges/12345.json`

## Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["window_id", "state", "source", "timestamp"],
  "properties": {
    "window_id": {
      "type": "integer",
      "minimum": 1,
      "description": "Sway container ID"
    },
    "state": {
      "type": "string",
      "enum": ["working", "stopped"],
      "description": "Badge visual state"
    },
    "source": {
      "type": "string",
      "minLength": 1,
      "description": "Notification source identifier"
    },
    "timestamp": {
      "type": "number",
      "description": "Unix timestamp (seconds since epoch)"
    },
    "count": {
      "type": "integer",
      "minimum": 1,
      "maximum": 9999,
      "default": 1,
      "description": "Notification count for display"
    }
  },
  "additionalProperties": false
}
```

## States

### Working

Badge indicates active processing. Visual: pulsating spinner animation.

```json
{
  "window_id": 12345,
  "state": "working",
  "source": "claude-code",
  "timestamp": 1734200000.5
}
```

### Stopped

Badge indicates completion awaiting user attention. Visual: bell icon with count.

```json
{
  "window_id": 12345,
  "state": "stopped",
  "source": "claude-code",
  "timestamp": 1734200005.2,
  "count": 1
}
```

## Operations

### Create Badge (Working)

**When**: Claude Code UserPromptSubmit hook fires
**Actor**: `prompt-submit-notification.sh`

```bash
cat > "$BADGE_FILE" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "working",
  "source": "claude-code",
  "timestamp": $(date +%s.%N)
}
EOF
```

### Update Badge (Stopped)

**When**: Claude Code Stop hook fires
**Actor**: `stop-notification.sh`

```bash
cat > "$BADGE_FILE" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "stopped",
  "source": "claude-code",
  "count": 1,
  "timestamp": $(date +%s.%N)
}
EOF
```

### Delete Badge (Focus Dismiss)

**When**: User focuses window with badge (age > 1 second)
**Actor**: i3-project-daemon `handlers.py`

```python
if badge_age > 1.0:
    os.remove(badge_file_path)
```

### Delete Badge (Action Click)

**When**: User clicks notification "Return to Window" action
**Actor**: `swaync-action-callback.sh`

```bash
rm -f "$BADGE_FILE"
```

### Delete Badge (Orphan Cleanup)

**When**: Badge references non-existent window
**Actor**: `monitoring_data.py` during refresh

```python
if window_id not in valid_window_ids:
    os.remove(badge_file_path)
```

## Consumers

### EWW Monitoring Panel

- Watches badge directory via inotify
- Reads all badge files on change
- Updates `has_working_badge` and per-window badge data
- Latency: <15ms from file change to UI update

### i3-project Daemon

- Subscribes to Sway focus events
- On focus: checks for badge, validates age, deletes if appropriate
- Latency: <50ms from focus event to badge deletion

## Error Handling

| Error | Handling |
|-------|----------|
| Malformed JSON | Skip file, log warning |
| Missing required field | Skip file, log warning |
| Invalid window_id | Skip file (orphan cleanup will remove) |
| File permission error | Log error, continue |

## Migration

This contract replaces the previous dual file+IPC approach. No migration needed - badge directory is ephemeral (runtime dir).
