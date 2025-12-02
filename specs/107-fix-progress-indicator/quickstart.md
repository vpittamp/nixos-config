# Quickstart: Fix Progress Indicator Focus State and Event Efficiency

**Feature**: 107-fix-progress-indicator

## What This Feature Does

1. **Focus-aware badge display**: Badges appear dimmed when the window is already focused, bright when attention is needed elsewhere
2. **Faster badge updates**: Hooks use IPC instead of file polling (~50ms vs ~500ms latency)
3. **Lower CPU during animation**: Spinner updates independently from full data refresh (<1% vs 5-10% CPU)

## Prerequisites

- Feature 095 (Visual Notification Badges) must be implemented
- i3pm daemon running: `systemctl status i3-project-daemon.service`
- Monitoring panel available: `Mod+M`

## Testing the Feature

### Test 1: Focus-Aware Badge Display

1. Open monitoring panel (`Mod+M`)
2. Start Claude Code in a terminal: `claude`
3. Submit a prompt and wait for response
4. Badge should appear with full brightness (peach glow)
5. Focus the terminal window
6. Badge should appear dimmed (no glow, reduced opacity)
7. Switch to another window
8. Badge should return to full brightness

**Expected CSS classes**:
- Unfocused + stopped badge: `badge-notification badge-stopped`
- Focused + stopped badge: `badge-notification badge-stopped badge-focused-window`

### Test 2: IPC-Based Badge Creation

1. Check daemon socket exists:
   ```bash
   ls -la /run/i3-project-daemon/ipc.sock
   ```

2. Test IPC client directly:
   ```bash
   badge-ipc get-state
   ```

3. Create badge via IPC:
   ```bash
   # Get focused window ID
   WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | select(.focused? == true) | .id')

   # Create working badge
   badge-ipc create "$WINDOW_ID" "test" --state working

   # Verify in monitoring panel
   ```

4. Measure latency:
   ```bash
   time badge-ipc create "$WINDOW_ID" "test" --state stopped
   # Should be <100ms
   ```

### Test 3: Spinner Animation Performance

1. Start Claude Code task
2. Monitor CPU during "working" state:
   ```bash
   # In another terminal
   htop -p $(pgrep -f "monitoring-data-backend")
   ```

3. CPU should stay below 2% during spinner animation

4. Check spinner variable updates:
   ```bash
   watch -n 0.1 'eww get spinner_frame'
   ```

### Test 4: File Fallback

1. Stop the daemon temporarily:
   ```bash
   sudo systemctl stop i3-project-daemon.service
   ```

2. Trigger Claude Code hook (submit prompt)

3. Check file was created:
   ```bash
   ls -la /run/user/$(id -u)/i3pm-badges/
   cat /run/user/$(id -u)/i3pm-badges/*.json
   ```

4. Restart daemon:
   ```bash
   sudo systemctl start i3-project-daemon.service
   ```

5. Verify badge appears in monitoring panel

## Troubleshooting

### Badge Not Appearing

1. Check daemon status:
   ```bash
   systemctl status i3-project-daemon.service
   journalctl -u i3-project-daemon.service -f
   ```

2. Check hook script execution:
   ```bash
   # Run hook manually
   /etc/nixos/scripts/claude-hooks/prompt-submit-notification.sh
   ```

3. Check badge state:
   ```bash
   badge-ipc get-state
   ```

### Focus State Not Updating

1. Verify `window.focused` in monitoring data:
   ```bash
   eww get monitoring_data | jq '.projects[].windows[] | {title, focused}'
   ```

2. Check CSS class in widget:
   ```bash
   # Inspect Eww widget CSS
   GTK_DEBUG=interactive eww open monitoring-panel
   ```

### High CPU During Animation

1. Verify spinner is decoupled:
   ```bash
   # Spinner should update via defpoll, not deflisten
   eww logs | grep spinner
   ```

2. Check monitoring data refresh rate:
   ```bash
   journalctl --user -u eww-monitoring-panel -f | grep "Sent"
   # Should NOT see rapid updates during animation
   ```

## Verification Commands

```bash
# All-in-one health check
echo "=== Daemon Status ===" && \
systemctl status i3-project-daemon.service --no-pager && \
echo "" && \
echo "=== Socket Check ===" && \
ls -la /run/i3-project-daemon/ipc.sock && \
echo "" && \
echo "=== Badge State ===" && \
badge-ipc get-state && \
echo "" && \
echo "=== Spinner Frame ===" && \
eww get spinner_frame
```

## Performance Metrics

After implementation, these metrics should be achievable:

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Badge appearance latency | <100ms | `time badge-ipc create ...` |
| Focus state update | <100ms | Visual observation |
| CPU during animation | <2% | `htop` during working badge |
| CPU during idle | <0.5% | `htop` with no badges |

## Files Modified

- `scripts/claude-hooks/prompt-submit-notification.sh` - IPC-first with fallback
- `scripts/claude-hooks/stop-notification.sh` - IPC-first with fallback
- `home-modules/desktop/eww-monitoring-panel.nix` - Focus-aware CSS, spinner variable
- `home-modules/tools/i3_project_manager/cli/monitoring_data.py` - Remove spinner from main refresh

## Related Documentation

- [Feature 095 Quickstart](../../095-visual-notification-badges/quickstart.md)
- [Badge IPC Contract](../../095-visual-notification-badges/contracts/badge-ipc.json)
- [CLAUDE.md - Monitoring Panel Section](../../../../CLAUDE.md#live-windowproject-monitoring-panel-features-085-086)
