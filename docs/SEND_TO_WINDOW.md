# FZF Send to Window

## Overview

A new FZF launcher that allows you to select a command and send it to a terminal in another workspace. The command is automatically typed and executed in the target window.

## Keybinding

**`Mod4+Ctrl+d`** - Open FZF launcher to send commands to workspace 4

## How It Works

1. Press `Mod4+Ctrl+d` to open the launcher
2. Type or select a command (same interface as regular FZF launcher)
3. Press `Enter` to send the selected command OR `Ctrl+Space` to send exactly what you typed
4. The launcher:
   - Switches to workspace 4
   - Finds the terminal window
   - Types the command
   - Presses Enter to execute it
   - Shows a notification confirming the command was sent

## Technical Implementation

### Protocol Used: i3-msg + xdotool

After testing various approaches, we chose this combination because:

- **i3-msg**: Native i3 tool for workspace management and window querying
- **xdotool**: Reliable X11 tool for simulating keyboard input
- **Why this works**: Most reliable method for sending text to terminals

### How It Works Internally

```bash
# 1. Query i3 for windows in target workspace
i3-msg -t get_tree | jq '...'

# 2. Focus the target workspace
i3-msg "workspace number 4"

# 3. Type the command
xdotool type --clearmodifiers "command here"

# 4. Execute it
xdotool key Return
```

## Use Cases

### Remote Command Execution
```
Mod4+Ctrl+d → type "ssh server.com" → Enter
```
Command is sent to workspace 4 terminal and executed

### Starting Long-Running Processes
```
Mod4+Ctrl+d → type "npm run dev" → Enter
```
Start a dev server in workspace 4 while working in another workspace

### Running Tests
```
Mod4+Ctrl+d → type "pytest tests/" → Enter
```
Execute tests in dedicated terminal workspace

## Configuration

### Default Target Workspace

Currently hardcoded to workspace 4. To change, edit `/etc/nixos/scripts/fzf-send-to-window.sh`:

```bash
TARGET_WORKSPACE="${1:-4}"  # Change 4 to your preferred workspace
```

### Custom Keybinding

Edit `/etc/nixos/home-modules/desktop/i3.nix`:

```nix
bindsym $mod+Ctrl+d exec ${pkgs.xterm}/bin/xterm -name fzf-launcher -fa 'Monospace' -fs 12 -e /etc/nixos/scripts/fzf-send-to-window.sh
```

## Testing

### Test Script

A test script is available for debugging:

```bash
/etc/nixos/scripts/test-send-to-window.sh "echo 'Hello World'" 4
```

This will:
- Show detailed debug output
- Send the command to workspace 4
- Report success/failure

## Limitations

1. **Terminal Detection**: Currently finds the first window in the target workspace
2. **Single Target**: Only sends to one workspace at a time
3. **No Multi-Select**: Can only send one command at a time

## Future Enhancements

Possible improvements:

1. **Dynamic Workspace Selection**: Use FZF to select target workspace
2. **Window Selection**: Choose specific window if multiple exist
3. **Command History**: Remember recently sent commands
4. **Tmux Integration**: Send to specific tmux pane instead of window
5. **Command Templates**: Pre-defined command templates with variables

## Files

| File | Purpose |
|------|---------|
| `scripts/fzf-send-to-window.sh` | Main launcher script |
| `scripts/test-send-to-window.sh` | Testing/debugging script |
| `home-modules/desktop/i3.nix` | Keybinding configuration |
| `docs/SEND_TO_WINDOW.md` | This documentation |

## Comparison with Background Commands

| Feature | Send to Window | Background Commands |
|---------|---------------|---------------------|
| **Keybinding** | `Mod4+Ctrl+d` | `Mod4+Shift+d` then `Ctrl+B` |
| **Execution** | In visible terminal | Hidden background process |
| **Output** | Visible in terminal | Saved to file + notification |
| **Use Case** | Interactive commands | Long-running builds/deploys |
| **Notification** | Confirmation only | On completion with status |

---

_Last updated: 2025-10-18_
