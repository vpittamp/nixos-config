# Quickstart: Project-Scoped Scratchpad Terminal

**Feature**: 062-project-scratchpad-terminal
**Last Updated**: 2025-11-05

## Overview

Quick-access floating terminal for each project, toggled via keybinding, with independent command history and automatic working directory setup.

**Use Case**: Instantly access project-specific terminal for git commands, builds, and file inspection without disrupting workspace layout.

---

## Quick Reference

### Keybindings

| Key | Action |
|-----|--------|
| `Mod+Shift+Return` | Toggle scratchpad terminal for current project |

**Behavior**:
- First press: Launch new terminal in project root
- Second press: Hide terminal to scratchpad (keeps running)
- Third press: Show terminal from scratchpad (same state)

### CLI Commands

```bash
# Toggle terminal (same as keybinding)
i3pm scratchpad toggle

# Toggle terminal for specific project
i3pm scratchpad toggle --project nixos

# Launch new terminal (fails if exists)
i3pm scratchpad launch

# Get terminal status
i3pm scratchpad status

# List all scratchpad terminals
i3pm scratchpad status --all

# Close scratchpad terminal
i3pm scratchpad close

# Clean up invalid terminals
i3pm scratchpad cleanup
```

---

## Common Workflows

### Workflow 1: Basic Toggle (Quick Terminal Access)

**Scenario**: You're working in the nixos project and need to run a quick git command.

```bash
# 1. Ensure you're in the right project
i3pm project switch nixos

# 2. Press Mod+Shift+Return (or run command)
i3pm scratchpad toggle
# → Terminal appears centered, floating, in /etc/nixos

# 3. Run your command
cd /etc/nixos
git status
git add .

# 4. Press Mod+Shift+Return again to hide
# → Terminal disappears but process keeps running

# 5. Press Mod+Shift+Return again to restore
# → Same terminal appears, command history intact
```

**Expected Result**:
- Terminal launches in <2 seconds on first press
- Toggle happens in <500ms for existing terminal
- Command history and working directory preserved across hide/show

---

### Workflow 2: Multi-Project Isolation

**Scenario**: You're switching between multiple projects and need independent terminals for each.

```bash
# 1. Switch to first project
i3pm project switch nixos
i3pm scratchpad toggle
# → Terminal opens in /etc/nixos

# 2. Run some commands
echo "Working in nixos" > /tmp/nixos-marker
cd /etc/nixos
ls -la

# 3. Switch to different project
i3pm project switch dotfiles
# → nixos terminal automatically hides

# 4. Toggle scratchpad in new project
i3pm scratchpad toggle
# → NEW terminal opens in /home/user/dotfiles (different process)

# 5. Verify isolation
cat /tmp/nixos-marker
# → File not in history, different terminal session

# 6. Switch back to nixos
i3pm project switch nixos
i3pm scratchpad toggle
# → Original nixos terminal appears, history intact
```

**Expected Result**:
- Each project has independent terminal with separate command history
- Terminals have different PIDs, working directories, processes
- Switching projects doesn't affect terminal state

---

### Workflow 3: Terminal State Persistence

**Scenario**: You start a long-running command, hide the terminal, and come back hours later.

```bash
# 1. Launch terminal and start long-running process
i3pm scratchpad toggle
tail -f /var/log/syslog
# → Watching logs in real-time

# 2. Hide terminal (Mod+Shift+Return)
# → Terminal hidden, tail command still running

# 3. Do other work for 2 hours...

# 4. Show terminal again (Mod+Shift+Return)
# → Terminal appears, tail command still running, showing new log entries

# 5. Verify process still running
ps aux | grep tail
# → Process exists with original PID
```

**Expected Result**:
- Long-running processes continue while terminal hidden
- Command history and session state preserved
- Terminal appears in exact same state as when hidden

---

### Workflow 4: Global Scratchpad Terminal (No Project)

**Scenario**: You need a quick terminal when not in any specific project.

```bash
# 1. Clear current project (enter global mode)
i3pm project clear

# 2. Toggle scratchpad terminal
i3pm scratchpad toggle
# → Terminal opens in home directory (~)

# 3. Run commands
cd ~
ls -la

# 4. Switch to a project
i3pm project switch nixos
# → Global terminal stays hidden (not affected by project switches)

# 5. Toggle project-specific terminal
i3pm scratchpad toggle
# → NEW nixos terminal opens (separate from global)

# 6. Return to global mode and toggle
i3pm project clear
i3pm scratchpad toggle
# → Original global terminal appears
```

**Expected Result**:
- Global terminal persists across all project switches
- Project-specific terminals are independent from global terminal
- Can have both global and project terminals simultaneously

---

## Diagnostic Commands

### Check Terminal Status

```bash
# Status for current project
i3pm scratchpad status
# Output:
# Project: nixos
# Status: hidden
# PID: 123456
# Window ID: 94489280339584
# Working Dir: /etc/nixos
# Created: 2025-11-05 14:30:00
# Last Shown: 2025-11-05 14:35:00

# Status for all terminals
i3pm scratchpad status --all
# Output:
# 2 scratchpad terminal(s) tracked:
#
# Project: nixos
#   Status: hidden
#   PID: 123456
#   Window ID: 94489280339584
#   Working Dir: /etc/nixos
#
# Project: dotfiles
#   Status: visible
#   PID: 123457
#   Window ID: 94489280339600
#   Working Dir: /home/user/dotfiles
```

### Verify Terminal Exists

```bash
# Check if terminal process is running
ps aux | grep alacritty | grep $(i3pm scratchpad status | grep PID | awk '{print $2}')

# Check if window is marked in Sway
swaymsg -t get_marks | grep scratchpad:nixos

# Check window state via i3pm
i3pm diagnose window <window-id>
```

### Clean Up Dead Terminals

```bash
# Remove invalid terminals from daemon state
i3pm scratchpad cleanup
# Output:
# Cleaned up 1 invalid terminal(s)
# Remaining: 2 valid terminal(s)
# Projects cleaned: old-project
```

---

## Troubleshooting

### Terminal Won't Launch

**Symptom**: Pressing keybinding does nothing, no terminal appears.

**Diagnosis**:
```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check daemon logs
journalctl --user -u i3-project-event-listener -f

# Test CLI directly
i3pm scratchpad toggle
# → Check for error messages
```

**Solutions**:
1. Restart daemon: `systemctl --user restart i3-project-event-listener`
2. Verify Alacritty installed: `which alacritty`
3. Check project configuration: `i3pm project current`

---

### Terminal Not Hiding/Showing

**Symptom**: Toggle keybinding doesn't hide or show existing terminal.

**Diagnosis**:
```bash
# Check terminal status
i3pm scratchpad status

# Verify window mark exists
swaymsg -t get_marks | grep scratchpad

# Check Sway tree for window
swaymsg -t get_tree | jq '..|.marks?|select(.!=null)'
```

**Solutions**:
1. Validate terminal: `i3pm scratchpad status` (should show valid state)
2. Close and relaunch: `i3pm scratchpad close && i3pm scratchpad toggle`
3. Clean up invalid terminals: `i3pm scratchpad cleanup`

---

### Wrong Working Directory

**Symptom**: Terminal opens in home directory instead of project root.

**Diagnosis**:
```bash
# Check project configuration
i3pm project show nixos

# Verify working directory setting
i3pm scratchpad status | grep "Working Dir"

# Check environment variables in terminal
echo $I3PM_WORKING_DIR
```

**Solutions**:
1. Verify project root directory set correctly: `i3pm project show <project>`
2. Relaunch terminal: `i3pm scratchpad close && i3pm scratchpad toggle`
3. Check daemon logs for errors: `journalctl --user -u i3-project-event-listener | grep scratchpad`

---

### Multiple Terminals for Same Project

**Symptom**: Multiple Alacritty windows open for same project instead of single scratchpad terminal.

**Diagnosis**:
```bash
# Check tracked terminals
i3pm scratchpad status --all

# Check for unmarked Alacritty windows
swaymsg -t get_tree | jq '..|select(.app_id=="Alacritty")|.marks'
```

**Solutions**:
1. Close extra terminals manually (regular Alacritty windows, not scratchpad)
2. Ensure keybinding is `Mod+Shift+Return` (not `Mod+Return` for regular terminal)
3. Verify scratchpad terminal is marked: `swaymsg -t get_marks | grep scratchpad`

---

### Terminal Process Zombie (Dead but Tracked)

**Symptom**: Status shows terminal exists but window won't appear.

**Diagnosis**:
```bash
# Check process is running
ps aux | grep <pid-from-status>

# Validate terminal
i3pm scratchpad status
# → Should show process_running: false if dead
```

**Solutions**:
1. Run cleanup: `i3pm scratchpad cleanup` (removes dead terminals)
2. Manual removal and relaunch: `i3pm scratchpad close && i3pm scratchpad toggle`

---

## Advanced Usage

### Using with tmux/sesh

Scratchpad terminals work seamlessly with tmux session management:

```bash
# Launch scratchpad terminal
i3pm scratchpad toggle

# Inside terminal: attach to tmux session
tmux attach -t nixos-dev
# or
sesh attach nixos-dev

# Hide terminal (Mod+Shift+Return)
# → tmux session continues running in background

# Show terminal later
# → tmux session still attached and running
```

### Integration with Project Switcher

Scratchpad terminals are project-aware and integrate with project switching:

```bash
# Switch project and immediately open terminal
i3pm project switch nixos && i3pm scratchpad toggle

# Bind to custom keybinding (in sway config)
bindsym $mod+t exec "i3pm project switch nixos && i3pm scratchpad toggle"
```

### Programmatic Terminal Control

Access scratchpad terminals via JSON-RPC:

```bash
# Using i3pm daemon JSON-RPC API
echo '{"jsonrpc":"2.0","id":1,"method":"scratchpad.toggle","params":{}}' | \
  nc -U /run/user/$(id -u)/i3-project-daemon.sock
```

See `contracts/scratchpad-rpc.json` for full API specification.

---

## Configuration

### Keybinding Customization

Edit Sway configuration to change keybinding:

```bash
# File: ~/.config/sway/keybindings.toml (hot-reloadable)
# or home-modules/desktop/sway.nix (requires rebuild)

# Change scratchpad toggle key
bindsym $mod+Shift+Return exec i3pm scratchpad toggle

# Alternative: use different key
bindsym $mod+grave exec i3pm scratchpad toggle  # Mod+` (backtick)
bindsym Control+Alt+t exec i3pm scratchpad toggle  # Ctrl+Alt+T
```

After editing `keybindings.toml`, reload Sway configuration:
```bash
swaymsg reload  # <100ms hot-reload
```

For NixOS module changes, rebuild configuration:
```bash
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### Terminal Dimensions

**Current**: Hardcoded 1400x850 pixels, centered on display.

**Future**: Will be configurable via daemon config file (not yet implemented).

---

## Performance Expectations

| Operation | Expected Time | Measured (Target) |
|-----------|---------------|-------------------|
| Toggle existing terminal (show/hide) | <500ms | <100ms (typical) |
| Launch new terminal | <2s | <1s (typical) |
| Daemon event processing | <100ms | <50ms (typical) |
| Status query | <100ms | <20ms (typical) |

**Notes**:
- First launch slower due to Alacritty process startup
- Subsequent toggles are fast (process already running)
- Performance may vary based on system load

---

## Service Management

### Daemon Control

Scratchpad terminal functionality is provided by the i3pm daemon:

```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Restart daemon
systemctl --user restart i3-project-event-listener

# View daemon logs
journalctl --user -u i3-project-event-listener -f

# Enable daemon auto-start (should be enabled by default)
systemctl --user enable i3-project-event-listener
```

### Daemon Diagnostics

```bash
# Check daemon health
i3pm daemon status

# Monitor daemon events
i3pm daemon events --type=window

# Diagnostic capture (includes scratchpad state)
i3pm diagnose health --json > /tmp/i3pm-diag.json
```

---

## Testing

### Manual Testing

Follow user story acceptance scenarios from spec:

**Test 1: First-time launch**
1. Switch to project: `i3pm project switch nixos`
2. Press `Mod+Shift+Return`
3. Verify terminal opens floating, centered, in project root
4. Verify mark exists: `swaymsg -t get_marks | grep scratchpad:nixos`

**Test 2: Toggle hide/show**
1. Press `Mod+Shift+Return` (hide)
2. Verify terminal disappears
3. Verify process still running: `ps aux | grep alacritty`
4. Press `Mod+Shift+Return` (show)
5. Verify same terminal appears (check PID matches)

**Test 3: Multi-project isolation**
1. Create terminal in project A: `i3pm project switch nixos && i3pm scratchpad toggle`
2. Run command: `echo test-nixos > /tmp/marker`
3. Switch to project B: `i3pm project switch dotfiles && i3pm scratchpad toggle`
4. Verify different terminal: `cat /tmp/marker` (should not exist or error)
5. Check different PID: `i3pm scratchpad status` (compare PIDs)

### Automated Testing

Run test suite:

```bash
# Unit tests
pytest tests/unit/test_scratchpad_manager.py -v

# Integration tests
pytest tests/integration/test_terminal_lifecycle.py -v

# End-to-end user workflow tests (requires Sway session)
pytest tests/scenarios/test_user_workflows.py -v

# All tests
pytest tests/ -v
```

**Test Requirements**:
- Active Sway session
- i3pm daemon running
- ydotool installed for keyboard simulation
- pytest and pytest-asyncio installed

---

## FAQ

**Q: Can I have multiple scratchpad terminals per project?**
A: No, the current design supports one terminal per project. This is intentional to keep the workflow simple.

**Q: What happens to scratchpad terminals when I restart Sway?**
A: Scratchpad terminals do NOT persist across Sway restarts. This is acceptable for the quick-access use case. If you need persistent sessions, use tmux/sesh inside the terminal.

**Q: Can I use a different terminal emulator?**
A: No, the current implementation only supports Alacritty. This is a constraint for simplicity.

**Q: Does the scratchpad terminal interfere with project window filtering?**
A: No, scratchpad terminals are marked with `scratchpad:` prefix and are explicitly excluded from project window filtering logic (different mark namespace).

**Q: Can I customize terminal size?**
A: Not yet. Terminal dimensions are hardcoded to 1400x850. Future versions may support configuration.

**Q: How do I delete a scratchpad terminal permanently?**
A: Close the terminal: `i3pm scratchpad close` or manually close the window (Mod+Shift+Q when focused).

---

## Related Documentation

- [Feature Specification](./spec.md) - Detailed requirements and user stories
- [Implementation Plan](./plan.md) - Technical architecture and design decisions
- [Data Model](./data-model.md) - Entity schemas and state management
- [JSON-RPC Contract](./contracts/scratchpad-rpc.json) - API specification
- [CLAUDE.md](../../CLAUDE.md) - Project-wide LLM navigation guide

---

## Support

For issues or questions:
1. Check daemon logs: `journalctl --user -u i3-project-event-listener -f`
2. Run diagnostics: `i3pm diagnose health`
3. Consult troubleshooting section above
4. Review feature specification for expected behavior

**Feedback**: Report issues via project issue tracker (see CLAUDE.md for details)
