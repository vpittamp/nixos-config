# Contract: Hook IPC Integration

**Feature**: 107-fix-progress-indicator | **Version**: 1.0.0

## Overview

Defines the integration pattern for Claude Code hooks to communicate with the daemon via IPC, with file-based fallback for reliability.

## Hook Communication Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                   Hook Script Execution                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Check IPC socket exists:                                     │
│     /run/i3-project-daemon/ipc.sock                              │
│                                                                  │
│  2. If socket exists:                                            │
│     └─► badge-ipc create $WINDOW_ID $SOURCE                      │
│         └─► On success: exit 0                                   │
│         └─► On failure: continue to fallback                     │
│                                                                  │
│  3. Fallback (file-based):                                       │
│     └─► Write $XDG_RUNTIME_DIR/i3pm-badges/$WINDOW_ID.json       │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## IPC Socket Path

| Environment | Socket Path |
|-------------|-------------|
| System service | `/run/i3-project-daemon/ipc.sock` |
| User service (fallback) | `/run/user/$UID/i3pm-daemon.sock` |

## Badge IPC Commands

### create_badge

Used by `UserPromptSubmit` hook and `Stop` hook:

```bash
# UserPromptSubmit - create "working" badge
badge-ipc create $WINDOW_ID claude-code --state working

# Stop - transition to "stopped" badge
badge-ipc create $WINDOW_ID claude-code --state stopped
```

### JSON-RPC Request

```json
{
  "jsonrpc": "2.0",
  "method": "create_badge",
  "params": {
    "window_id": 12345,
    "source": "claude-code",
    "state": "working"
  },
  "id": 1
}
```

### JSON-RPC Response

```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "badge": {
      "window_id": 12345,
      "count": 1,
      "timestamp": 1732450000.5,
      "source": "claude-code",
      "state": "working"
    }
  },
  "id": 1
}
```

## Fallback File Format

When IPC fails, hooks write to filesystem:

**Path**: `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`

**Content**:
```json
{
  "window_id": 12345,
  "state": "working",
  "source": "claude-code",
  "count": "1",
  "timestamp": 1732450000
}
```

## Hook Script Template

```bash
#!/usr/bin/env bash
# Feature 107: IPC-first hook with file fallback

set -euo pipefail
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Get terminal window ID (tmux-aware)
WINDOW_ID=$(get_terminal_window_id)  # existing function

# Determine state from hook context
STATE="${1:-stopped}"  # "working" for UserPromptSubmit, "stopped" for Stop

# Try IPC first (fast path)
IPC_SOCKET="/run/i3-project-daemon/ipc.sock"
if [ -S "$IPC_SOCKET" ]; then
    if /etc/nixos/scripts/claude-hooks/badge-ipc-client.sh \
        create "$WINDOW_ID" "claude-code" --state "$STATE" >/dev/null 2>&1; then
        exit 0  # Success via IPC
    fi
fi

# Fallback to file-based (reliability path)
BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
mkdir -p "$BADGE_STATE_DIR"
cat > "$BADGE_STATE_DIR/$WINDOW_ID.json" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "$STATE",
  "source": "claude-code",
  "count": "1",
  "timestamp": $(date +%s)
}
EOF

exit 0
```

## Timeout Constraints

| Hook Type | Max Timeout | IPC Budget | Fallback Budget |
|-----------|-------------|------------|-----------------|
| UserPromptSubmit | 3s | 500ms | 2.5s |
| Stop | 3s | 500ms | 2.5s |

If IPC takes >500ms, hook should abort IPC and use file fallback.

## Error Handling

| Error Condition | Action |
|-----------------|--------|
| Socket not found | Use file fallback |
| IPC timeout (>500ms) | Abort IPC, use file fallback |
| IPC returns error | Log warning, use file fallback |
| File write fails | Log error, exit non-zero |

## Daemon Cleanup

Daemon periodically checks for orphaned badge files:

1. On startup: Load all badge files → merge with IPC state
2. Every 5 minutes: Remove files for non-existent windows
3. On window close event: Delete badge file if exists
