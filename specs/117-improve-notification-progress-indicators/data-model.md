# Data Model: Improve Notification Progress Indicators

**Feature**: 117-improve-notification-progress-indicators
**Date**: 2025-12-14

## Entities

### Badge

Visual notification indicator associated with a Sway window.

**Storage**: File at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| window_id | integer | Yes | Sway container ID (unique key) |
| state | enum | Yes | `"working"` or `"stopped"` |
| source | string | Yes | Notification source (e.g., `"claude-code"`) |
| timestamp | float | Yes | Unix timestamp of badge creation/update |
| count | integer | No | Number of notifications (default: 1, max: 9999) |

**State Machine**:

```
                  prompt-submit
    [No Badge] ───────────────────> [Working]
                                        │
                                        │ stop-hook
                                        ▼
                                    [Stopped]
                                        │
                    ┌───────────────────┴───────────────────┐
                    │ focus window          │ click action  │
                    ▼                       ▼               │
               [No Badge] <──────────────[No Badge] <──────┘
```

**Validation Rules**:
- `window_id` must be > 0
- `state` must be one of: `"working"`, `"stopped"`
- `timestamp` must be valid Unix timestamp
- `count` must be 1-9999 (display as "9+" if > 9)

**Example**:
```json
{
  "window_id": 12345,
  "state": "working",
  "source": "claude-code",
  "timestamp": 1734200000.5
}
```

---

### Window (Reference - from Sway IPC)

Sway container representing a window. Not stored by this feature, but queried from Sway IPC.

| Field | Type | Description |
|-------|------|-------------|
| id | integer | Unique container ID (matches badge window_id) |
| pid | integer | Process ID of window's application |
| app_id | string | Wayland app_id (e.g., "ghostty") |
| focused | boolean | Whether window currently has focus |
| workspace | object | Workspace containing this window |

**Query Method**: `swaymsg -t get_tree`

---

### Hook Event (Conceptual)

Claude Code lifecycle events that trigger badge operations.

| Event | Trigger | Badge Action |
|-------|---------|--------------|
| UserPromptSubmit | User submits prompt | Create/update badge with `state: "working"` |
| Stop | Claude completes, awaits input | Update badge to `state: "stopped"`, send notification |

**Data passed to hooks** (via stdin JSON):
```json
{
  "tool_input": { "command": "..." },
  "tool_name": "Bash",
  "session_id": "..."
}
```

---

### Notification (Transient)

Desktop notification sent via notify-send. Not persisted.

| Field | Type | Description |
|-------|------|-------------|
| title | string | "Claude Code Ready" |
| body | string | Project name or "Awaiting input" |
| icon | string | "robot" |
| urgency | string | "normal" |
| action_id | string | "focus" |
| action_label | string | "Return to Window" |

---

## Relationships

```
┌─────────────────┐       creates/updates        ┌─────────────┐
│   Hook Script   │ ─────────────────────────────│    Badge    │
│  (bash)         │                              │   (file)    │
└─────────────────┘                              └─────────────┘
                                                       │
                                                       │ references
                                                       ▼
┌─────────────────┐       queries                ┌─────────────┐
│   Daemon        │ ─────────────────────────────│   Window    │
│  (Python)       │                              │ (Sway IPC)  │
└─────────────────┘                              └─────────────┘
        │
        │ on focus event
        │ deletes badge if exists + old enough
        ▼
┌─────────────────┐
│   Badge File    │
│   (deleted)     │
└─────────────────┘

┌─────────────────┐       reads/watches          ┌─────────────┐
│   EWW Widget    │ ─────────────────────────────│    Badge    │
│  (yuck/scss)    │    (inotify)                 │   (file)    │
└─────────────────┘                              └─────────────┘
```

## State Transitions

### Badge Lifecycle

| Current State | Event | New State | Action |
|---------------|-------|-----------|--------|
| None | UserPromptSubmit | Working | Create badge file |
| Working | Stop | Stopped | Update badge, send notification |
| Working | UserPromptSubmit | Working | Update timestamp |
| Stopped | UserPromptSubmit | Working | Update state |
| Stopped | Window Focus | None | Delete badge (if age > 1s) |
| Stopped | Action Click | None | Delete badge |
| Any | Window Close | None | Delete badge (orphan cleanup) |
| Any | TTL Expire | None | Delete badge (5 min max) |

### Focus Dismissal Timing

```
Badge Created (timestamp=T)
        │
        │ User switches to other window
        │
        ├──────────────────────────────────────────┐
        │                                          │
        │ User focuses badge window at T+0.5s     │ User focuses badge window at T+2s
        │                                          │
        ▼                                          ▼
  age = 0.5s < 1s                            age = 2s > 1s
  Badge NOT dismissed                        Badge dismissed
  (prevent race condition)                   (normal behavior)
```
