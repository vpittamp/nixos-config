# Quickstart: Improve Notification Progress Indicators

**Feature**: 117-improve-notification-progress-indicators
**Date**: 2025-12-14

## Overview

This feature consolidates and simplifies the Claude Code notification system:

1. **Single badge mechanism** - File-only storage (remove IPC dual-write)
2. **Focus-aware dismissal** - Badges clear when you focus the window
3. **Concise notifications** - Just project name, not verbose details
4. **Stale cleanup** - Orphaned badges automatically removed

## Key Files

| File | Purpose |
|------|---------|
| `scripts/claude-hooks/prompt-submit-notification.sh` | Creates "working" badge |
| `scripts/claude-hooks/stop-notification.sh` | Updates to "stopped", sends notification |
| `scripts/claude-hooks/swaync-action-callback.sh` | Handles "Return to Window" action |
| `home-modules/desktop/i3-project-event-daemon/handlers.py` | Focus event handling |
| `home-modules/desktop/i3-project-event-daemon/monitoring_data.py` | Badge cleanup |
| `home-modules/desktop/eww-monitoring-panel.nix` | Badge display in EWW |

## Badge Lifecycle

```
User submits prompt → Working badge appears (spinner)
                            ↓
Claude completes → Stopped badge (bell) + Desktop notification
                            ↓
User focuses window → Badge dismissed (auto)
    OR
User clicks notification → Badge dismissed + Window focused
```

## Testing

### Manual Test: Badge Creation

```bash
# Create test badge
BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
mkdir -p "$BADGE_DIR"

# Get a window ID from Sway
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.focused==true) | .id')

# Create working badge
cat > "$BADGE_DIR/$WINDOW_ID.json" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "working",
  "source": "claude-code",
  "timestamp": $(date +%s)
}
EOF

# Check EWW shows spinner on window
# After ~1 second, focus another window, then focus back
# Badge should be dismissed
```

### Manual Test: Notification Action

```bash
# Create stopped badge and notification
BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.focused==true) | .id')

cat > "$BADGE_DIR/$WINDOW_ID.json" <<EOF
{
  "window_id": $WINDOW_ID,
  "state": "stopped",
  "source": "claude-code",
  "count": 1,
  "timestamp": $(date +%s)
}
EOF

# Simulate notification
notify-send \
    -i "robot" \
    -u normal \
    -w \
    -A "focus=Return to Window" \
    "Claude Code Ready" \
    "📁 test-project"

# Click action button, verify badge clears
```

### Automated Tests

```bash
# Run sway-test suite (after implementation)
sway-test run tests/117-notification-indicators/

# Individual test
sway-test run tests/117-notification-indicators/test_badge_lifecycle.json
```

## Debugging

### Check Badge State

```bash
# List all badges
ls -la "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges/"

# View badge content
cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges/"*.json | jq .
```

### Check EWW State

```bash
# View monitoring data (includes badge info)
monitoring-data-backend --mode windows | jq '.windows[].badge'

# Check has_working_badge
monitoring-data-backend --mode windows | jq '.has_working_badge'
```

### Check Daemon Logs

```bash
# Focus event handling logs
journalctl --user -u i3-project-event-listener -f | grep -i badge

# Hook script logs
journalctl --user -t claude-callback
```

### Clear All Badges (Reset)

```bash
rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges/"*.json
```

## Configuration

### Hook Timeout

In `home-modules/ai-assistants/claude-code.nix`:

```nix
hooks = {
  UserPromptSubmit = [{
    hooks = [{
      type = "command";
      command = "${self}/scripts/claude-hooks/prompt-submit-notification.sh";
      timeout = 3;  # 3 seconds max
    }];
  }];
  Stop = [{
    hooks = [{
      type = "command";
      command = "${self}/scripts/claude-hooks/stop-notification.sh";
      timeout = 3;  # 3 seconds max
    }];
  }];
};
```

### Focus Dismiss Delay

In `handlers.py`, minimum age before focus dismissal:

```python
BADGE_MIN_AGE_FOR_DISMISS = 1.0  # seconds
```

### Stale Badge TTL

In `monitoring_data.py`:

```python
BADGE_MAX_AGE = 300  # 5 minutes
```

## Success Criteria Verification

| Criterion | How to Verify |
|-----------|---------------|
| SC-001: 600ms latency | Time from prompt submit to spinner visible |
| SC-002: 500ms focus dismiss | Time from focus to badge removal |
| SC-003: 30s orphan cleanup | Close window, check badge removed |
| SC-004: 95% action success | Click notification, verify window focus |
| SC-005: Project in notification | Check notification body content |
| SC-006: No stale after 5 min | Run multiple sessions, check panel |
