# Quick Start: OpenTelemetry AI Assistant Monitoring

**Feature**: 123-otel-tracing
**Date**: 2025-12-16

## Overview

This feature provides real-time monitoring of Claude Code and Codex CLI sessions using native OpenTelemetry telemetry. The system displays working/completed states in the EWW top bar and sends desktop notifications when AI tasks complete.

## Prerequisites

- NixOS with home-manager
- Sway window manager with EWW
- Claude Code 2.x+ or Codex CLI 0.70+
- SwayNC for notifications

## Quick Enable

Add to your home configuration (e.g., `hetzner.nix`):

```nix
{
  imports = [
    ./services/otel-ai-monitor.nix
  ];

  services.otel-ai-monitor.enable = true;
}
```

Rebuild:
```bash
sudo nixos-rebuild switch --flake .#hetzner-sway
```

## Verify Installation

1. **Check service is running**:
   ```bash
   systemctl --user status otel-ai-monitor
   ```

2. **Check OTLP receiver is listening**:
   ```bash
   curl -s http://localhost:4318/health
   # Should return: {"status": "ok"}
   ```

3. **Test with Claude Code**:
   ```bash
   # Start Claude Code - should see indicator in top bar
   claude

   # Submit a prompt - indicator should show "working"
   # When complete - notification appears, indicator shows "completed"
   ```

## UI Elements

### Top Bar Indicator

| Icon | State | Meaning |
|------|-------|---------|
| (empty) | No sessions | No AI assistants active |
| 󰚩 (spinning) | Working | AI is processing |
| 󰄬 (check) | Completed | AI finished, awaiting acknowledgment |

### Monitoring Panel (Mod+M)

The AI Sessions tab shows:
- Active sessions with tool type (Claude/Codex)
- Current state (working/completed)
- Project context if available
- Token usage (if P3 metrics enabled)

### Desktop Notifications

When AI completes:
- Notification title: "Claude Code Ready" or "Codex Ready"
- Body: Project name or "Task completed"
- Actions:
  - Click → Focus terminal
  - Dismiss → Clear indicator

## Troubleshooting

### No indicator appearing

1. **Check telemetry is enabled**:
   ```bash
   # Claude Code
   echo $CLAUDE_CODE_ENABLE_TELEMETRY  # Should be "1"

   # Codex CLI
   grep -A5 '\[otel\]' ~/.codex/config.toml
   ```

2. **Check service logs**:
   ```bash
   journalctl --user -u otel-ai-monitor -f
   ```

3. **Verify EWW is consuming the stream**:
   ```bash
   # Check the named pipe exists
   ls -la $XDG_RUNTIME_DIR/otel-ai-monitor.pipe
   ```

### Indicator stuck on "working"

The completion detection uses a 3-second quiet period. If the AI is still sending events, it remains in "working" state.

Force reset:
```bash
systemctl --user restart otel-ai-monitor
```

### Notifications not appearing

1. **Check SwayNC is running**:
   ```bash
   systemctl --user status swaync
   ```

2. **Check notification delivery**:
   ```bash
   notify-send "Test" "Testing notifications"
   ```

## Configuration Options

```nix
services.otel-ai-monitor = {
  enable = true;

  # OTLP receiver port (default: 4318)
  port = 4318;

  # Quiet period for completion detection (default: 3 seconds)
  completionQuietPeriodSec = 3;

  # Session expiry timeout (default: 300 seconds / 5 minutes)
  sessionTimeoutSec = 300;

  # Enable desktop notifications (default: true)
  enableNotifications = true;
};
```

## Removing Legacy Components

This feature replaces:
- `services.tmux-ai-monitor` - Remove from config
- `scripts/claude-hooks/stop-notification.sh` - Auto-removed
- Badge file system (`$XDG_RUNTIME_DIR/i3pm-badges/`) - No longer used

After enabling `otel-ai-monitor`, remove legacy references:

```nix
# REMOVE these lines:
# services.tmux-ai-monitor.enable = true;
```

## Architecture

```
Claude Code ─┐                                      ┌─► EWW Top Bar
             ├──► OTLP Receiver ──► JSON stream ───┤
Codex CLI ───┘         │                            └─► Monitoring Panel
                       │
                       └──► Desktop Notifications
```

All communication is event-driven (no polling).

## Related Documentation

- [Feature Specification](./spec.md)
- [Implementation Plan](./plan.md)
- [Research Notes](./research.md)
- [Data Model](./data-model.md)
