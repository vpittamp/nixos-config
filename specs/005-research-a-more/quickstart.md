# Quick Start Guide: i3wm Desktop Environment on Hetzner Cloud

**Feature**: Lightweight X11 Desktop Environment for Hetzner Cloud
**Branch**: `005-research-a-more`
**Date**: 2025-10-16
**For**: End users and system administrators

## Overview

This guide walks you through setting up and using the i3 window manager on your Hetzner Cloud NixOS server. You'll learn how to configure i3, connect via remote desktop, and use essential keyboard shortcuts for productive workflows.

## Prerequisites

- NixOS 24.11+ installed on Hetzner Cloud server
- SSH access to the server
- macOS, Windows, or Linux client machine for remote desktop
- Basic familiarity with terminal/command line

## Installation

### Step 1: Update Configuration

Edit your Hetzner configuration file:

```bash
cd /etc/nixos
nano configurations/hetzner.nix
```

Add or update the following sections:

```nix
{ config, pkgs, ... }:

{
  # Import the i3wm module
  imports = [
    ./modules/desktop/i3wm.nix
    ./modules/desktop/xrdp.nix
    # ... other imports
  ];

  # Enable i3 window manager
  services.i3wm = {
    enable = true;
    modifier = "Mod4";  # Mod4 = Windows/Super key

    # Configure 4 workspaces
    workspaces = [
      { number = 1; name = "Main"; }
      { number = 2; name = "Code"; }
      { number = 3; name = "Web"; }
      { number = 4; name = "Chat"; }
    ];

    # Appearance
    fonts = [ "DejaVu Sans Mono 10" ];
    gaps = {
      inner = 5;
      outer = 5;
      smartGaps = true;
    };

    # Install essential tools
    extraPackages = with pkgs; [
      rofi           # Application launcher
      i3status       # Status bar
      i3lock         # Screen locker
      nitrogen       # Wallpaper
      dunst          # Notifications
      alacritty      # Terminal
    ];
  };

  # Enable XRDP for remote desktop
  services.xrdp = {
    enable = true;
    port = 3389;
    openFirewall = true;
    defaultWindowManager = "${pkgs.i3}/bin/i3";
    audioRedirection = true;
  };

  # Set i3 as default session
  services.displayManager.defaultSession = "none+i3";

  # Enable PulseAudio for audio
  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
  };

  environment.systemPackages = [ pkgs.pulseaudio-module-xrdp ];
}
```

### Step 2: Test Configuration

Always test before applying:

```bash
sudo nixos-rebuild dry-build --flake .#hetzner
```

If no errors appear, proceed to apply:

```bash
sudo nixos-rebuild switch --flake .#hetzner
```

This will take 5-10 minutes to rebuild and restart services.

### Step 3: Verify Services

Check that XRDP and i3 services are running:

```bash
systemctl status xrdp
systemctl status xrdp-sesman
```

Both should show "active (running)" in green.

## Connecting via Remote Desktop

### From macOS

1. Install [Microsoft Remote Desktop](https://apps.apple.com/app/microsoft-remote-desktop/id1295203466) from App Store
2. Open the app and click "Add PC"
3. Enter your server hostname or IP address
4. Set port to `3389` (or your custom port)
5. Enter your NixOS username and password
6. Click "Connect"

You should see the i3 desktop with a status bar at the bottom.

### From Windows

1. Press `Win+R` and type `mstsc`
2. Enter server hostname:3389
3. Click "Connect"
4. Enter NixOS username and password
5. Click "OK"

### From Linux

Using FreeRDP:

```bash
xfreerdp /v:<hostname>:3389 /u:<username> /p:<password> /sound:sys:pulse
```

Using Remmina (graphical):

```bash
remmina -c rdp://<username>@<hostname>:3389
```

## Essential i3 Keybindings

**Note**: `Mod` refers to the Windows/Super key (default configuration).

### Application Management

| Keybinding | Action |
|------------|--------|
| `Mod+Return` | Open terminal (Alacritty) |
| `Mod+d` | Open application launcher (dmenu) |
| `Mod+Shift+q` | Close focused window |
| `Mod+Shift+e` | Exit i3 (logout) |

### Window Navigation

| Keybinding | Action |
|------------|--------|
| `Mod+Left/Right/Up/Down` | Focus window in direction |
| `Mod+Shift+Left/Right/Up/Down` | Move window in direction |
| `Mod+f` | Toggle fullscreen |
| `Mod+Shift+Space` | Toggle floating/tiling |

### Workspace Management

| Keybinding | Action |
|------------|--------|
| `Mod+1` through `Mod+9` | Switch to workspace 1-9 |
| `Mod+Shift+1` through `Mod+Shift+9` | Move window to workspace 1-9 |

### Layout Management

| Keybinding | Action |
|------------|--------|
| `Mod+e` | Toggle split layout (horizontal/vertical) |
| `Mod+s` | Stacking layout |
| `Mod+w` | Tabbed layout |

### System

| Keybinding | Action |
|------------|--------|
| `Mod+Shift+c` | Reload i3 configuration |
| `Mod+Shift+r` | Restart i3 (keeps windows open) |
| `Mod+Shift+e` | Exit i3 / logout |

## Common Tasks

### Opening Applications

**Method 1: Using dmenu (keyboard)**
1. Press `Mod+d`
2. Type application name (e.g., "firefox")
3. Press Enter

**Method 2: Using terminal**
1. Press `Mod+Return` to open terminal
2. Type application name and press Enter (e.g., `firefox &`)

### Creating a Workspace Layout

**Scenario**: Split screen with terminal on left, browser on right

1. Press `Mod+1` to go to workspace 1
2. Press `Mod+Return` to open terminal (takes full screen)
3. Press `Mod+h` to split horizontally
4. Press `Mod+d`, type "firefox", press Enter
5. Now you have terminal (left) and Firefox (right)

### Moving Windows Between Workspaces

1. Focus the window you want to move
2. Press `Mod+Shift+2` to move it to workspace 2
3. Press `Mod+2` to follow it to workspace 2

### Taking Screenshots

1. Press `Print Screen` (if configured)
2. Or use terminal: `scrot ~/screenshot.png`
3. Or select area: `scrot -s ~/screenshot.png`

### Locking Screen

1. Press `Mod+l` (if configured)
2. Or from terminal: `i3lock`

## Customizing Your Setup

### Adding Custom Keybindings

Edit `configurations/hetzner.nix`:

```nix
services.i3wm.keybindings = let
  mod = config.services.i3wm.modifier;
in {
  # Custom terminal
  "${mod}+Return" = "exec ${pkgs.alacritty}/bin/alacritty";

  # Custom launcher
  "${mod}+space" = "exec ${pkgs.rofi}/bin/rofi -show drun";

  # Browser
  "${mod}+b" = "exec ${pkgs.firefox}/bin/firefox";

  # Lock screen
  "${mod}+l" = "exec ${pkgs.i3lock}/bin/i3lock -c 000000";

  # Screenshot
  "Print" = "exec ${pkgs.scrot}/bin/scrot ~/screenshot-%Y-%m-%d-%H%M%S.png";
};
```

Rebuild:

```bash
sudo nixos-rebuild switch --flake .#hetzner
```

Reload i3: Press `Mod+Shift+c`

### Changing Colors

Edit `configurations/hetzner.nix`:

```nix
services.i3wm.colors = {
  focused = {
    border = "#4c7899";
    background = "#285577";
    text = "#ffffff";
    indicator = "#2e9ef4";
    childBorder = "#285577";
  };
  unfocused = {
    border = "#333333";
    background = "#222222";
    text = "#888888";
    indicator = "#292d2e";
    childBorder = "#222222";
  };
};
```

### Setting Wallpaper

1. Copy wallpaper to server:
   ```bash
   scp ~/Pictures/wallpaper.png user@server:/home/user/wallpaper.png
   ```

2. Add startup command in configuration:
   ```nix
   services.i3wm.startup = [
     { command = "${pkgs.nitrogen}/bin/nitrogen --set-zoom-fill ~/wallpaper.png"; }
   ];
   ```

3. Rebuild and reconnect

### Configuring Status Bar

Customize what appears in the status bar:

```nix
services.i3wm.bar = {
  enable = true;
  position = "bottom";
  statusCommand = "${pkgs.i3status}/bin/i3status";
  fonts = [ "DejaVu Sans Mono 10" "FontAwesome 10" ];
  workspaceButtons = true;

  colors = {
    background = "#000000";
    statusline = "#ffffff";
    separator = "#666666";
  };
};
```

## Workflow Examples

### Developer Workflow

**Setup**: 4 workspaces organized by task

- **Workspace 1 (Main)**: Terminal with tmux session
- **Workspace 2 (Code)**: Neovim/VS Code in tabbed layout
- **Workspace 3 (Web)**: Firefox for documentation/testing
- **Workspace 4 (Chat)**: Slack/Discord

**Navigation**:
1. `Mod+1`: Check terminal commands
2. `Mod+2`: Edit code
3. `Mod+3`: View docs
4. `Mod+4`: Check messages
5. Repeat throughout day without ever touching mouse

### Multi-Monitor Development (if using multiple monitors)

```nix
services.i3wm.workspaces = [
  { number = 1; name = "Terminal"; output = "HDMI-1"; }
  { number = 2; name = "Editor"; output = "HDMI-1"; }
  { number = 3; name = "Browser"; output = "HDMI-2"; }
  { number = 4; name = "Comms"; output = "HDMI-2"; }
];
```

## Troubleshooting

### Can't Connect via RDP

**Check XRDP service**:
```bash
systemctl status xrdp
```

If not running:
```bash
systemctl restart xrdp
```

**Check firewall**:
```bash
ss -tlnp | grep 3389
```

Should show xrdp listening on port 3389.

**Check user password**:
```bash
sudo passwd <username>  # Reset password if needed
```

### Black Screen After Connection

i3 may not be launching. Check logs:

```bash
journalctl -u xrdp-sesman -n 50
```

Look for errors related to i3 startup.

**Fix**: Ensure `defaultWindowManager` points to i3:
```nix
services.xrdp.defaultWindowManager = "${pkgs.i3}/bin/i3";
```

### Keybindings Don't Work

**Check i3 config**:
```bash
i3 -C -c /etc/i3/config
```

If errors appear, fix configuration syntax in `services.i3wm.keybindings`.

**Reload i3**: Press `Mod+Shift+c` to reload configuration.

### No Audio Redirection

**Check PulseAudio**:
```bash
systemctl --user status pulseaudio
```

**Verify XRDP module loaded**:
```bash
pactl list modules | grep xrdp
```

Should show `module-xrdp-sink` and `module-xrdp-source`.

**Fix**: Ensure PulseAudio XRDP module installed:
```nix
environment.systemPackages = [ pkgs.pulseaudio-module-xrdp ];
```

### Windows Appear in Wrong Workspace

i3 assigns new windows to current workspace. To force specific applications to specific workspaces:

```nix
services.i3wm.extraConfig = ''
  assign [class="Firefox"] 3
  assign [class="Slack"] 4
'';
```

Find window class with:
```bash
xprop | grep WM_CLASS
```
Then click the window.

## Performance Optimization

### For Slow Connections

Reduce color depth and resolution:

```nix
services.xrdp.display = {
  resolution = "1366x768";  # Lower resolution
  colorDepth = 16;           # Reduce to 16-bit
};
```

### For Fast Connections

Increase quality:

```nix
services.xrdp.display = {
  resolution = "2560x1440";  # Higher resolution
  colorDepth = 32;            # Maximum color depth
};
```

## Advanced Configuration

### Auto-Start Applications

Launch applications when i3 starts:

```nix
services.i3wm.startup = [
  # Wallpaper
  { command = "${pkgs.nitrogen}/bin/nitrogen --restore"; }

  # Notification daemon
  { command = "${pkgs.dunst}/bin/dunst"; always = true; }

  # Auto-start Firefox on workspace 3
  {
    command = "i3-msg 'workspace 3; exec ${pkgs.firefox}/bin/firefox'";
    notification = false;
  }
];
```

### Application-Specific Window Rules

Control how applications appear:

```nix
services.i3wm.extraConfig = ''
  # Float all dialogs
  for_window [window_role="pop-up"] floating enable
  for_window [window_role="task_dialog"] floating enable

  # Spotify always on workspace 10
  for_window [class="Spotify"] move to workspace 10

  # Terminals start in tabbed layout
  for_window [class="Alacritty"] layout tabbed
'';
```

### Custom Application Launcher with Rofi

Replace dmenu with rofi for better launcher:

```nix
services.i3wm.keybindings.${mod}+d = "exec ${pkgs.rofi}/bin/rofi -show drun";
```

Configure rofi theme:

```nix
services.i3wm.extraConfig = ''
  exec_always --no-startup-id ${pkgs.rofi}/bin/rofi -config ~/.config/rofi/config.rasi
'';
```

## Migration from KDE Plasma

If you're migrating from KDE Plasma:

### Phase 1: Test i3 Alongside KDE

Keep both window managers temporarily:

```nix
{
  services.i3wm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;  # Keep KDE

  # XRDP will show session choice
  services.xrdp.defaultWindowManager = "${pkgs.i3}/bin/i3";
}
```

At login, you can choose between KDE and i3.

### Phase 2: Remove KDE

Once comfortable with i3:

```nix
{
  services.i3wm.enable = true;
  # Remove: services.xserver.desktopManager.plasma5.enable = true;
}
```

Rebuild to reclaim ~500MB memory.

## Getting Help

### Resources

- **i3 User Guide**: https://i3wm.org/docs/userguide.html
- **i3 FAQ**: https://i3wm.org/docs/faq.html
- **Reddit r/i3wm**: https://reddit.com/r/i3wm
- **Arch Wiki i3**: https://wiki.archlinux.org/title/I3

### Checking i3 Version

```bash
i3 --version
```

### Debugging i3 Issues

View i3 logs:

```bash
cat ~/.local/share/i3/i3-debug.log
```

Enable i3 logging:

```bash
i3 --config /etc/i3/config -V &> ~/i3-debug.log
```

## Next Steps

Once you're comfortable with basic i3 usage:

1. **Explore i3-gaps features**: Enhanced window gaps and aesthetics
2. **Try i3blocks**: More customizable status bar
3. **Set up scratchpad**: Quick access to hidden windows
4. **Configure multi-monitor**: If using multiple displays
5. **Create custom modes**: For specialized workflows (resize mode, etc.)

## Summary

You now have a lightweight, keyboard-driven desktop environment on your Hetzner Cloud server that:

- Uses <50MB RAM (vs 500MB+ for KDE Plasma)
- Provides remote desktop access via XRDP
- Supports 4+ workspaces for organization
- Works entirely via keyboard shortcuts
- Persists sessions across disconnects

Press `Mod+Return` to open a terminal and start exploring!
