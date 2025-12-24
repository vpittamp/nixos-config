# Quickstart: Multiple AI Indicators Per Terminal Window

**Feature**: 136-multiple-indicators
**Date**: 2025-12-24

## Prerequisites

- NixOS system with Sway/Wayland (hetzner-sway configuration)
- Working EWW monitoring panel (`Mod+M` to toggle)
- At least one AI CLI installed (Claude Code, Codex, or Gemini CLI)
- tmux for multi-pane testing

## Test Setup

### 1. Build and Apply Configuration

```bash
# Dry-build first (per Constitution Principle III)
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply if successful
sudo nixos-rebuild switch --flake .#hetzner-sway

# Restart EWW panel to pick up changes
systemctl --user restart eww-monitoring-panel
```

### 2. Restart otel-ai-monitor Service

```bash
# Restart to pick up code changes
systemctl --user restart otel-ai-monitor

# Verify service is running
systemctl --user status otel-ai-monitor
```

## Testing Scenarios

### Scenario 1: Two AI Sessions in One Terminal (P1 Validation)

1. Open a terminal (Ghostty) with tmux:
   ```bash
   tmux new-session -s test
   ```

2. Split horizontally and start AI CLIs:
   ```bash
   # Pane 1 (left)
   claude-code

   # Ctrl+b % to split, then in Pane 2 (right)
   codex
   ```

3. Start both sessions with prompts:
   - In Claude Code: "What is 2+2?"
   - In Codex: "What is 3+3?"

4. **Verify**: Open monitoring panel (`Mod+M`), check the terminal window's row:
   - Should see **two** pulsating indicators (Claude icon + Codex icon)
   - Both should be in "working" state during processing

### Scenario 2: Independent State Transitions

1. With both sessions running from Scenario 1, wait for one to complete
2. **Verify**:
   - Completed session's indicator transitions to "completed" state (green check)
   - Other session remains "working" (pulsating)

### Scenario 3: Overflow Handling (P3 Validation)

1. Create a tmux session with 4+ panes:
   ```bash
   tmux new-session -s overflow-test
   # Split into 4 panes
   tmux split-window -h && tmux split-window -v && tmux select-pane -t 0 && tmux split-window -v
   ```

2. Start AI CLIs in each pane (mix of tools or same tool)

3. **Verify**:
   - First 3 indicators visible
   - "+1 more" badge visible (or "+N more" for more sessions)
   - Hover over count badge shows tooltip with all sessions

### Scenario 4: Tool Type Distinction (P2 Validation)

1. In a split terminal with Claude Code + Codex + Gemini:
   ```bash
   # Pane 1
   claude-code
   # Pane 2
   codex
   # Pane 3
   gemini
   ```

2. **Verify**:
   - Each indicator shows correct tool icon
   - Icons are visually distinguishable (Claude, Codex, Gemini icons)

## Debugging

### Check Session State

```bash
# View raw session list from otel-ai-monitor
cat $XDG_RUNTIME_DIR/otel-ai-sessions.json | jq .

# Check sessions_by_window grouping
cat $XDG_RUNTIME_DIR/otel-ai-sessions.json | jq '.sessions_by_window'
```

### Monitor Telemetry

```bash
# Watch otel-ai-monitor logs
journalctl --user -u otel-ai-monitor -f

# Watch EWW monitoring panel
journalctl --user -u eww-monitoring-panel -f
```

### Verify Window Correlation

```bash
# Get current terminal window ID
swaymsg -t get_tree | jq '.. | objects | select(.focused==true) | .id'

# Check if session is correlated to that window
cat $XDG_RUNTIME_DIR/otel-ai-sessions.json | jq '.sessions[] | select(.window_id == WINDOW_ID)'
```

## Success Criteria

| Test | Expected Result |
|------|-----------------|
| Two AI sessions, one window | Two distinct indicators visible |
| Different tools | Correct icon for each tool type |
| State transition | Indicators update independently |
| 4+ sessions | 3 visible + overflow badge |
| Overflow tooltip | Full list shown on hover |
| Update latency | <2 seconds from state change to UI |

## Rollback

If issues occur:

```bash
# Switch to previous generation
sudo nixos-rebuild switch --rollback

# Or specific generation
sudo nixos-rebuild switch --option system /nix/var/nix/profiles/system-X-link
```
