# Quickstart Guide: Multi-Session Remote Desktop & Web Application Launcher

**Feature Branch**: `007-add-a-few`
**Date**: 2025-10-16
**Status**: Phase 1

## Overview

This guide provides quickstart instructions for configuring and using the multi-session remote desktop system with i3wm, web application launcher, Alacritty terminal, and clipboard history on NixOS.

---

## Prerequisites

- NixOS system with flake support
- Existing Hetzner or similar configuration as base
- Access to system rebuild capabilities (`sudo nixos-rebuild`)
- Basic familiarity with NixOS modules and home-manager

---

## Quick Setup

### 1. Enable Multi-Session xrdp

**File**: `configurations/hetzner-i3.nix` (or your target configuration)

```nix
{
  imports = [
    ../modules/desktop/xrdp.nix
    ../modules/desktop/i3wm.nix
  ];

  # Enable multi-session xrdp
  services.xrdp = {
    enable = true;
    port = 3389;
    openFirewall = true;
    defaultWindowManager = "i3-xrdp-session";

    audio.enable = true;

    sesman = {
      policy = "UBC";                      # New session per connection
      maxSessions = 5;                     # Support 3-5 concurrent sessions
      killDisconnected = false;            # Keep sessions alive
      disconnectedTimeLimit = 86400;       # 24-hour cleanup (seconds)
      idleTimeLimit = 0;                   # No idle timeout
      x11DisplayOffset = 10;               # Start from :10
    };
  };

  # Use PulseAudio for better xrdp audio support
  services.pipewire.enable = lib.mkForce false;
  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
  };

  # Enable X11
  services.xserver = {
    enable = true;
    windowManager.i3.enable = true;
  };
}
```

### 2. Configure Web Applications

**File**: `home-modules/tools/web-apps-sites.nix`

```nix
{
  programs.webApps = {
    enable = true;
    browser = "ungoogled-chromium";

    applications = {
      gmail = {
        name = "Gmail";
        url = "https://mail.google.com";
        wmClass = "webapp-gmail";
        icon = /etc/nixos/assets/webapp-icons/gmail.png;
        workspace = "2";
        lifecycle = "persistent";
        keywords = [ "email" "mail" "google" ];
      };

      notion = {
        name = "Notion";
        url = "https://www.notion.so";
        wmClass = "webapp-notion";
        workspace = "3";
        keywords = [ "notes" "docs" "wiki" ];
      };

      linear = {
        name = "Linear";
        url = "https://linear.app";
        wmClass = "webapp-linear";
        workspace = "4";
        keywords = [ "issues" "tasks" "project" ];
      };
    };

    i3Integration = {
      autoAssignWorkspace = true;
      floatingMode = false;
    };
  };
}
```

**File**: `home-modules/tools/web-apps-declarative.nix`

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.webApps;

  # Generate launcher script for each web app
  makeLauncher = id: app: pkgs.writeScriptBin "webapp-${id}" ''
    #!/bin/sh
    PROFILE_DIR="$HOME/.local/share/webapps/${app.wmClass}"
    mkdir -p "$PROFILE_DIR"

    exec ${pkgs.ungoogled-chromium}/bin/chromium \
      --user-data-dir="$PROFILE_DIR" \
      --class="${app.wmClass}" \
      --app="${app.url}" \
      ${lib.concatStringsSep " " app.extraBrowserArgs}
  '';

  enabledApps = lib.filterAttrs (id: app: app.enabled) cfg.applications;

in {
  imports = [ ./web-apps-sites.nix ];

  # Install launcher scripts
  home.packages = lib.mapAttrsToList makeLauncher enabledApps;

  # Create desktop entries
  xdg.desktopEntries = lib.mapAttrs (id: app: {
    name = app.name;
    exec = "webapp-${id}";
    icon = if app.icon != null then toString app.icon else "web-browser";
    categories = [ "Network" "WebBrowser" ];
    keywords = [ "web" "app" ] ++ app.keywords;
    terminal = false;
  }) enabledApps;

  # Generate i3wm window rules
  programs.i3.config.window.commands = lib.mapAttrsToList (id: app:
    lib.optionalAttrs (app.workspace != null) {
      criteria.class = "^${app.wmClass}$";
      command = "move to workspace ${app.workspace}";
    }
  ) enabledApps;
}
```

### 3. Enable Clipboard History

**File**: `home-modules/tools/clipcat.nix`

```nix
{ config, lib, pkgs, ... }:

{
  services.clipcat = {
    enable = true;
    package = pkgs.clipcat;

    daemonSettings = {
      daemonize = true;
      max_history = 100;
      history_file_path = "${config.xdg.cacheHome}/clipcat/clipcatd-history";

      watcher = {
        enable_clipboard = true;
        enable_primary = true;
        primary_threshold_ms = 5000;

        # Filter sensitive content
        denied_text_regex_patterns = [
          "^[A-Za-z0-9!@#$%^&*()_+\\-=\\[\\]{}|;:,.<>?]{16,128}$"  # Passwords
          "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b"    # Credit cards
          "-----BEGIN.*PRIVATE KEY-----"                            # SSH keys
          "(?i)(api[_-]?key|token|secret)[\\s:=]+[A-Za-z0-9_\\-]+" # API tokens
        ];

        filter_text_min_length = 1;
        filter_text_max_length = 20000000;
        filter_image_max_size = 5242880;  # 5MB
      };

      capture_image = true;
    };

    menuSettings = {
      finder = "rofi";
      rofi_config_path = "${config.xdg.configHome}/rofi/config.rasi";
    };
  };

  # i3 keybindings
  programs.i3.config.keybindings = {
    "${config.programs.i3.config.modifier}+v" = "exec ${pkgs.clipcat}/bin/clipcat-menu";
    "${config.programs.i3.config.modifier}+Shift+v" = "exec ${pkgs.clipcat}/bin/clipctl clear";
  };

  # Ensure xclip is available for tmux integration
  home.packages = [ pkgs.xclip ];
}
```

### 4. Configure Alacritty Terminal

**File**: `home-modules/terminal/alacritty.nix`

```nix
{ config, lib, pkgs, ... }:

{
  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      font = {
        normal = {
          family = "FiraCode Nerd Font";
          style = "Regular";
        };
        size = 9.0;
      };

      window = {
        padding = { x = 2; y = 2; };
        decorations = "full";
        dynamic_title = true;
      };

      selection.save_to_clipboard = true;
      scrolling.history = 10000;

      # Catppuccin Mocha colors
      colors = {
        primary = {
          background = "#1e1e2e";
          foreground = "#cdd6f4";
        };
        cursor = {
          text = "#1e1e2e";
          cursor = "#f5e0dc";
        };
        normal = {
          black = "#45475a";
          red = "#f38ba8";
          green = "#a6e3a1";
          yellow = "#f9e2af";
          blue = "#89b4fa";
          magenta = "#f5c2e7";
          cyan = "#94e2d5";
          white = "#bac2de";
        };
        bright = {
          black = "#585b70";
          red = "#f38ba8";
          green = "#a6e3a1";
          yellow = "#f9e2af";
          blue = "#89b4fa";
          magenta = "#f5c2e7";
          cyan = "#94e2d5";
          white = "#a6adc8";
        };
      };

      mouse.hide_when_typing = true;
    };
  };

  # Set as default terminal
  home.sessionVariables.TERMINAL = "alacritty";

  # i3 keybindings
  programs.i3.config.keybindings = {
    "${config.programs.i3.config.modifier}+Return" = "exec ${pkgs.alacritty}/bin/alacritty";
    "${config.programs.i3.config.modifier}+Shift+Return" = "exec ${pkgs.alacritty}/bin/alacritty --class floating_terminal";
  };

  programs.i3.config.window.commands = [{
    criteria.class = "floating_terminal";
    command = "floating enable";
  }];
}
```

### 5. Import All Modules

**File**: `home-modules/default.nix` (or your home-manager imports)

```nix
{
  imports = [
    # Existing imports...
    ./tools/clipcat.nix
    ./tools/web-apps-declarative.nix
    ./terminal/alacritty.nix
  ];
}
```

---

## Building and Testing

### 1. Test Configuration

```bash
# Dry-build to check for errors
sudo nixos-rebuild dry-build --flake .#hetzner

# If successful, apply changes
sudo nixos-rebuild switch --flake .#hetzner
```

### 2. Test Multi-Session RDP

**From Device 1:**
```bash
# Connect via Microsoft Remote Desktop to your Hetzner IP
# User: your-username
# Password: your-password
```

**From Device 2:**
```bash
# Connect again from another device
# You should get a NEW session, not disconnect Device 1
```

**Verify Sessions:**
```bash
# On the server
loginctl list-sessions | grep xrdp
# Should show multiple sessions

# Check X11 displays
ps aux | grep Xorg
# Should show multiple Xorg processes on :10, :11, etc.
```

### 3. Test Web Applications

```bash
# Launch rofi
rofi -show drun -show-icons

# Search for "Gmail" or "Notion"
# Press Enter to launch

# Verify separate window
# Check WM_CLASS
xprop | grep WM_CLASS
# Click on the web app window, should show: WM_CLASS(STRING) = "webapp-gmail", "Chromium"
```

### 4. Test Clipboard History

```bash
# Copy some text from Firefox
# Copy different text from VS Code
# Copy text from terminal

# Open clipboard menu
# Press $mod+v (default: Super+v)
# Should see all copied items

# Test paste into different applications
# Clear history: $mod+Shift+v
```

### 5. Test Alacritty Terminal

```bash
# Launch terminal
# Press $mod+Return

# Verify it's Alacritty
echo $TERM
# Should output: xterm-256color

# Test tmux integration
tmux
# Should work seamlessly with existing tmux config

# Test clipboard
# Select text in terminal → should auto-copy to clipboard
# Verify with: $mod+v
```

---

## Usage Guide

### Multi-Session Remote Desktop

**Connect from Multiple Devices:**
1. Open Microsoft Remote Desktop on Device 1
2. Connect to server (hostname:3389)
3. Work as normal
4. Open Microsoft Remote Desktop on Device 2
5. Connect to same server → new session created
6. Device 1 remains connected

**Reconnect to Existing Session:**
- Depends on session policy (UBC creates new session per connection)
- To reconnect to specific session, use session management tools (future enhancement)

**Session Cleanup:**
- Sessions automatically cleaned up after 24 hours of disconnection
- Manual cleanup: `loginctl kill-session <session-id>`

### Web Applications

**Launch Applications:**
```bash
# Via rofi
rofi -show drun
# Type application name, press Enter

# Via command line
webapp-gmail
webapp-notion
```

**Add New Applications:**
1. Edit `home-modules/tools/web-apps-sites.nix`
2. Add new entry to `programs.webApps.applications`
3. Rebuild: `sudo nixos-rebuild switch --flake .#hetzner`
4. Application appears in rofi automatically

**Workspace Assignment:**
- Set `workspace` in app definition
- i3wm automatically moves app to workspace on launch

**Browser Extensions:**
- Each web app has separate profile
- 1Password extension works in each profile
- Install extension once per profile (first launch)

### Clipboard History

**Access Clipboard:**
```bash
# Open menu (default: Super+v)
rofi clipboard menu appears
# Navigate with arrow keys
# Press Enter to paste selection
```

**Clear History:**
```bash
# Clear all entries (default: Super+Shift+v)
clipctl clear

# Or disable temporarily
clipctl disable
clipctl enable
```

**Sensitive Content:**
- Passwords, API keys, SSH keys automatically filtered
- Regex patterns configurable in `clipcat.nix`

### Alacritty Terminal

**Launch Terminal:**
```bash
# Standard terminal (tiled)
$mod+Return

# Floating terminal
$mod+Shift+Return
```

**Existing Tools Work:**
- tmux sessions: `tmux` or `tmux attach`
- sesh session manager: works unchanged
- bash configurations: sourced automatically
- Starship prompt: displays correctly

---

## Troubleshooting

### Multi-Session Issues

**Problem**: Second connection disconnects first session

**Solution**: Check `killDisconnected` setting in xrdp configuration:
```bash
cat /etc/xrdp/sesman.ini | grep KillDisconnected
# Should be: KillDisconnected=no
```

**Problem**: Session limit reached

**Solution**:
```bash
# List sessions
loginctl list-sessions

# Kill old sessions
loginctl kill-session <session-id>

# Or increase maxSessions in xrdp config
```

### Web App Issues

**Problem**: Web app doesn't appear in rofi

**Solution**:
```bash
# Verify desktop entry created
ls ~/.local/share/applications/ | grep webapp

# Rebuild rofi cache
rofi -show drun -dump-cache
```

**Problem**: WM_CLASS not unique

**Solution**: Each web app must have unique `wmClass` starting with `webapp-`

### Clipboard Issues

**Problem**: Clipboard history not capturing

**Solution**:
```bash
# Check clipcat daemon running
systemctl --user status clipcat.service

# Restart daemon
systemctl --user restart clipcat.service

# Check clipboard selections enabled
clipctl status
```

**Problem**: Sensitive content captured

**Solution**: Add regex patterns to `denied_text_regex_patterns` in `clipcat.nix`

### Terminal Issues

**Problem**: Alacritty colors wrong in tmux

**Solution**: Verify TERM variables:
```bash
# Outside tmux
echo $TERM  # Should be: xterm-256color

# Inside tmux
echo $TERM  # Should be: tmux-256color
```

**Problem**: Clipboard not working in tmux

**Solution**: Ensure xclip installed and tmux config has clipboard integration:
```nix
home.packages = [ pkgs.xclip ];
```

---

## Advanced Configuration

### Custom Session Policy

For different session behavior, modify `sesman.policy`:
- `Default`: Reconnect to existing session (single-device use)
- `UBC`: New session per connection (recommended multi-device)
- `UBI`: New session per IP address

### Custom Web App Browser Args

```nix
gmail = {
  # ... other settings ...
  extraBrowserArgs = [
    "--disable-notifications"
    "--force-dark-mode"
    "--force-device-scale-factor=1.25"
  ];
};
```

### Custom Clipboard Filters

```nix
services.clipcat.daemonSettings.watcher.denied_text_regex_patterns = [
  # Add custom patterns
  "your-company-api-[A-Za-z0-9]+"  # Company API tokens
  "-----BEGIN CERTIFICATE-----"     # Certificates
];
```

### Custom Alacritty Colors

Replace `colors` section in `alacritty.nix` with your preferred theme.

---

## Next Steps

1. **Phase 2**: Generate `tasks.md` via `/speckit.tasks` command
2. **Implementation**: Execute tasks to build all modules
3. **Testing**: Validate all success criteria (SC-001 through SC-017)
4. **Documentation**: Create detailed docs in `docs/` directory

---

**Quickstart Guide Complete** ✅
All modules configured with practical examples and troubleshooting guidance.
