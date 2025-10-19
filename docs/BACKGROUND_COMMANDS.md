# Background Command Execution with Notifications

## Overview

The FZF launcher (`Mod4+Shift+d`) now supports running long-running commands in the background with desktop notifications when they complete.

## How It Works

1. Open the FZF launcher with `Mod4+Shift+d`
2. Type or select a command (e.g., `sudo nixos-rebuild switch --flake .#hetzner`)
3. Press **Ctrl+B** to run it in the background
4. The launcher closes immediately
5. You get a notification when the command completes (success or failure)

## Keybindings in FZF Launcher

| Key | Action |
|-----|--------|
| `Enter` | Execute command normally (foreground) |
| `Ctrl+Space` | Execute exactly what you typed (foreground) |
| `Ctrl+B` | Run command in **BACKGROUND** with notification |
| `Tab` | Replace query with selected item |

## Viewing Command Output

### Quick Access Commands

```bash
# View the most recent background command output
bglast

# View all background command history
bglog
```

### What You Get

**On Success:**
- ✓ Green notification: "Command Completed"
- Shows command that ran
- Click notification or use `bglast` to view full output

**On Failure:**
- ✗ Red notification: "Command Failed (exit code)"
- Shows last 5 lines of error output
- Notification stays visible until dismissed
- Use `bglast` to view full output

## Example Use Cases

### NixOS Rebuild
```
Mod4+Shift+d → type "sudo nixos-rebuild switch --flake .#hetzner" → Ctrl+B
```

### Docker Build
```
Mod4+Shift+d → type "docker build -t myapp ." → Ctrl+B
```

### Long Test Suite
```
Mod4+Shift+d → type "pytest tests/" → Ctrl+B
```

## Technical Details

### Components

- **dunst** - Lightweight notification daemon (Catppuccin Mocha theme)
- **run-background-command.sh** - Executes commands and manages notifications
- **fzf-launcher.sh** - Enhanced with Ctrl+B support

### Output Files

- Command output: `/tmp/bg-command.XXXXXX` (temporary files)
- Command history: `~/.cache/bg-commands.log`

### Logs

All background commands are logged with timestamps:
```
[2025-01-15 14:30:00] Running: sudo nixos-rebuild switch --flake .#hetzner
[2025-01-15 14:32:15] Completed with exit code: 0
[2025-01-15 14:32:15] Output file: /tmp/bg-command.abc123
```

## Customization

### Notification Settings

Edit `home-modules/desktop/dunst.nix` to customize:
- Notification position
- Timeout duration
- Colors and styling
- Sound alerts (if desired)

### Auto-cleanup

By default, output files are kept for manual review. To enable auto-cleanup after 24 hours, uncomment in `scripts/run-background-command.sh`:

```bash
# Uncomment to auto-delete output after 24 hours
sleep 86400 && rm -f "$OUTPUT_FILE" &
```

## Troubleshooting

### Notifications Not Appearing

1. Check dunst service:
   ```bash
   systemctl --user status dunst
   ```

2. Test notification manually:
   ```bash
   notify-send "Test" "This is a test notification"
   ```

3. Restart dunst:
   ```bash
   systemctl --user restart dunst
   ```

### Command Not Running

1. Check the background command log:
   ```bash
   bglog
   ```

2. Verify the command works when run directly in a terminal

## Integration

This feature integrates seamlessly with:
- **i3 window manager** - Mod4+Shift+d launcher
- **FZF** - Fuzzy command search
- **Dunst** - Native i3 notification daemon
- **Tmux** - Commands can access tmux sessions
- **Bash aliases** - `bglast` and `bglog` shortcuts

---

_Last updated: 2025-01-15_
