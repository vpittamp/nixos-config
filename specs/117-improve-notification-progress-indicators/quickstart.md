# Quickstart: Improve Notification Progress Indicators

**Feature**: 117-improve-notification-progress-indicators
**Date**: 2025-12-14
**Updated**: 2025-12-15 (tmux-based detection)

## Overview

This feature implements **tmux-based universal AI assistant detection**:

1. **Universal detection** - Works with both Claude Code and Codex CLI
2. **tmux polling** - Detects AI processes via `tmux list-panes`
3. **Focus-aware dismissal** - Badges clear when you focus the window
4. **Concise notifications** - Just project name, not verbose details
5. **Legacy hook suppression** - Claude Code hooks disabled when tmux monitor active

## Key Files

| File | Purpose |
|------|---------|
| `home-modules/services/tmux-ai-monitor.nix` | **NEW**: systemd service for process monitoring |
| `scripts/tmux-ai-monitor/monitor.sh` | **NEW**: Main polling loop |
| `scripts/tmux-ai-monitor/notify.sh` | **NEW**: Notification sender |
| `home-modules/ai-assistants/claude-code.nix` | **MODIFIED**: Hooks suppressed |
| `home-modules/desktop/i3-project-event-daemon/handlers.py` | Focus event handling (unchanged) |
| `home-modules/desktop/i3-project-event-daemon/monitoring_data.py` | Badge cleanup (unchanged) |

## Badge Lifecycle (tmux-based)

```
AI process detected in tmux pane → Working badge appears (spinner)
                                        ↓
ALL AI processes exit (return to shell) → Stopped badge (bell) + Notification
                                        ↓
User focuses window → Badge dismissed (auto)
    OR
User clicks notification → Badge dismissed + Window focused
```

**Multi-pane behavior**:
- Badge shows "working" if ANY pane has AI assistant running
- Badge shows "stopped" only when ALL panes return to shell

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

### tmux-ai-monitor Service

In `home-modules/services/tmux-ai-monitor.nix`:

```nix
services.tmux-ai-monitor = {
  enable = true;  # Enables monitor, suppresses legacy hooks

  # Polling interval (milliseconds)
  pollInterval = 300;

  # AI processes to detect
  processes = [
    { name = "claude"; title = "Claude Code Ready"; source = "claude-code"; }
    { name = "codex"; title = "Codex Ready"; source = "codex"; }
  ];
};
```

### Legacy Hook Suppression

Hooks are automatically suppressed when `services.tmux-ai-monitor.enable = true`:

```nix
# In claude-code.nix - hooks conditional on monitor NOT being enabled
enableLegacyHooks = !config.services.tmux-ai-monitor.enable;
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
| SC-001: 500ms latency | Time from AI process start to spinner visible |
| SC-002: Works for Claude + Codex | Run both tools, verify badges appear |
| SC-003: 500ms focus dismiss | Time from focus to badge removal |
| SC-004: 30s orphan cleanup | Close window, check badge removed |
| SC-005: 95% action success | Click notification, verify window focus |
| SC-006: Identify assistant | Check notification title shows "Claude Code Ready" or "Codex Ready" |
| SC-007: No stale after 5 min | Run multiple sessions, check panel |
| SC-008: Degraded mode | Stop monitor service, verify system continues |
| SC-009: Hooks suppressed | Verify no hook output in logs when monitor active |

## Monitor Service Management

```bash
# Start/stop the tmux-ai-monitor service
systemctl --user start tmux-ai-monitor
systemctl --user stop tmux-ai-monitor

# View logs
journalctl --user -u tmux-ai-monitor -f

# Check status
systemctl --user status tmux-ai-monitor
```
