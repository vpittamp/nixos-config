# Data Model: MangoWC Configuration

**Date**: 2025-10-16
**Branch**: `003-create-a-new`

This document defines the configuration data structures for the MangoWC desktop environment on NixOS.

## Overview

The MangoWC configuration system consists of:
1. **NixOS Module Options** - System-level configuration
2. **MangoWC Config Files** - Compositor configuration (config.conf, autostart.sh)
3. **Session State** - Runtime state managed by compositor
4. **Remote Desktop Configuration** - wayvnc and audio setup

## 1. NixOS Module Options

### Primary Module: `modules.desktop.mangowc`

```nix
{ config, lib, pkgs, ... }:

with lib;

{
  options.services.mangowc = {
    enable = mkEnableOption "MangoWC Wayland compositor";

    package = mkOption {
      type = types.package;
      default = pkgs.mangowc;
      description = "MangoWC package to use";
    };

    user = mkOption {
      type = types.str;
      default = "vpittamp";
      description = "User to run MangoWC compositor";
    };

    resolution = mkOption {
      type = types.str;
      default = "1920x1080";
      description = "Virtual display resolution for headless mode";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for MangoWC";
      example = {
        WLR_NO_HARDWARE_CURSORS = "1";
      };
    };

    config = mkOption {
      type = types.lines;
      default = "";
      description = "MangoWC configuration (config.conf content)";
    };

    autostart = mkOption {
      type = types.lines;
      default = "";
      description = "Autostart script content (autostart.sh)";
    };

    workspaces = mkOption {
      type = types.listOf (types.submodule {
        options = {
          id = mkOption {
            type = types.ints.between 1 9;
            description = "Workspace/tag ID (1-9)";
          };
          layout = mkOption {
            type = types.enum [
              "tile" "scroller" "monocle" "grid"
              "deck" "center_tile" "vertical_tile"
              "vertical_grid" "vertical_scroller"
            ];
            default = "tile";
            description = "Default layout for this workspace";
          };
          name = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional workspace name";
          };
        };
      });
      default = [
        { id = 1; layout = "tile"; }
        { id = 2; layout = "scroller"; }
        { id = 3; layout = "monocle"; }
        { id = 4; layout = "tile"; }
        { id = 5; layout = "tile"; }
        { id = 6; layout = "tile"; }
        { id = 7; layout = "tile"; }
        { id = 8; layout = "tile"; }
        { id = 9; layout = "tile"; }
      ];
      description = "Workspace/tag configuration";
    };

    keybindings = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = ''
        Custom keybindings to add/override.
        Format: { "SUPER,Return" = "spawn,foot"; }
      '';
      example = {
        "SUPER,Return" = "spawn,foot";
        "SUPER,d" = "spawn,wmenu-run";
        "ALT,q" = "killclient,";
      };
    };

    appearance = mkOption {
      type = types.submodule {
        options = {
          borderWidth = mkOption {
            type = types.ints.unsigned;
            default = 4;
            description = "Window border width in pixels";
          };
          borderRadius = mkOption {
            type = types.ints.unsigned;
            default = 6;
            description = "Window corner radius in pixels";
          };
          rootColor = mkOption {
            type = types.str;
            default = "0x201b14ff";
            description = "Root/background color (hex RGBA)";
          };
          focusColor = mkOption {
            type = types.str;
            default = "0xc9b890ff";
            description = "Focused window border color (hex RGBA)";
          };
          unfocusedColor = mkOption {
            type = types.str;
            default = "0x444444ff";
            description = "Unfocused window border color (hex RGBA)";
          };
        };
      };
      default = {};
      description = "Visual appearance settings";
    };
  };

  config = mkIf config.services.mangowc.enable {
    # Implementation details...
  };
}
```

### Remote Desktop Module: `modules.desktop.wayland-remote-access`

```nix
options.services.wayvnc = {
  enable = mkEnableOption "WayVNC remote desktop server";

  package = mkOption {
    type = types.package;
    default = pkgs.wayvnc;
    description = "WayVNC package to use";
  };

  user = mkOption {
    type = types.str;
    default = config.services.mangowc.user or "vpittamp";
    description = "User to run wayvnc (should match compositor user)";
  };

  address = mkOption {
    type = types.str;
    default = "0.0.0.0";
    description = "IP address to listen on";
  };

  port = mkOption {
    type = types.port;
    default = 5900;
    description = "VNC port to listen on";
  };

  enablePAM = mkOption {
    type = types.bool;
    default = true;
    description = "Enable PAM authentication (integrates with 1Password)";
  };

  enableAuth = mkOption {
    type = types.bool;
    default = true;
    description = "Enable authentication (requires PAM or password)";
  };

  maxFPS = mkOption {
    type = types.ints.positive;
    default = 120;
    description = "Maximum frame rate for screen capture";
  };

  enableGPU = mkOption {
    type = types.bool;
    default = true;
    description = "Enable GPU-accelerated H.264 encoding (if available)";
  };

  extraConfig = mkOption {
    type = types.lines;
    default = "";
    description = "Additional wayvnc configuration";
  };
};
```

### Audio Module Options (extends existing services.pipewire)

```nix
options.services.pipewire.networkAudio = {
  enable = mkEnableOption "PipeWire network audio for remote desktop";

  port = mkOption {
    type = types.port;
    default = 4713;
    description = "PulseAudio protocol port";
  };

  address = mkOption {
    type = types.str;
    default = "0.0.0.0";
    description = "IP address to listen on";
  };
};
```

## 2. MangoWC Configuration Files

### config.conf Structure

```ini
# Window Effects
blur=0
shadows=0
border_radius=6
focused_opacity=1.0
unfocused_opacity=1.0

# Animation Configuration
animations=1
animation_duration_open=400
animation_duration_close=800
animation_curve_open=0.46,1.0,0.29,1

# Layout Settings
new_is_master=1
default_mfact=0.55
default_nmaster=1
smartgaps=0

# Scroller Layout
scroller_structs=20
scroller_default_proportion=0.8
scroller_focus_center=0

# Overview
hotarea_size=10
enable_hotarea=1
overviewgappi=5
overviewgappo=30

# Misc
focus_on_activate=1
sloppyfocus=1
warpcursor=1
focus_cross_monitor=0
cursor_size=24

# Keyboard
repeat_rate=25
repeat_delay=600
numlockon=1
xkb_rules_layout=us

# Appearance
gappih=5
gappiv=5
gappoh=10
gappov=10
borderpx=4
rootcolor=0x201b14ff
bordercolor=0x444444ff
focuscolor=0xc9b890ff

# Tag/Workspace Rules (id:1-9)
tagrule=id:1,layout_name:tile
tagrule=id:2,layout_name:scroller
tagrule=id:3,layout_name:monocle
tagrule=id:4,layout_name:tile
tagrule=id:5,layout_name:tile
tagrule=id:6,layout_name:tile
tagrule=id:7,layout_name:tile
tagrule=id:8,layout_name:tile
tagrule=id:9,layout_name:tile

# Key Bindings
bind=SUPER,r,reload_config
bind=Alt,space,spawn,rofi -show drun
bind=Alt,Return,spawn,foot
bind=SUPER,m,quit
bind=ALT,q,killclient,

# Window focus
bind=ALT,Left,focusdir,left
bind=ALT,Right,focusdir,right
bind=ALT,Up,focusdir,up
bind=ALT,Down,focusdir,down

# Workspace switching (Ctrl+1-9)
bind=Ctrl,1,view,1,0
bind=Ctrl,2,view,2,0
bind=Ctrl,3,view,3,0
bind=Ctrl,4,view,4,0
bind=Ctrl,5,view,5,0
bind=Ctrl,6,view,6,0
bind=Ctrl,7,view,7,0
bind=Ctrl,8,view,8,0
bind=Ctrl,9,view,9,0

# Move window to workspace (Alt+1-9)
bind=Alt,1,tag,1,0
bind=Alt,2,tag,2,0
bind=Alt,3,tag,3,0
bind=Alt,4,tag,4,0
bind=Alt,5,tag,5,0
bind=Alt,6,tag,6,0
bind=Alt,7,tag,7,0
bind=Alt,8,tag,8,0
bind=Alt,9,tag,9,0

# Layout switching
bind=SUPER,n,switch_layout

# Window management
bind=ALT,backslash,togglefloating,
bind=ALT,f,togglefullscreen,
bind=SUPER,i,minimized,
bind=SUPER+SHIFT,I,restore_minimized

# Mouse bindings
mousebind=SUPER,btn_left,moveresize,curmove
mousebind=SUPER,btn_right,moveresize,curresize
```

### autostart.sh Structure

```bash
#!/bin/sh

# Wallpaper
swaybg -i /etc/nixos/assets/wallpapers/default.png &

# Optional: Status bar (waybar)
# waybar -c ~/.config/mango/waybar/config.jsonc &

# Optional: Notification daemon
# mako &

# Optional: Clipboard manager
# wl-paste --watch cliphist store &
```

## 3. Session State

### Managed by MangoWC Compositor

The compositor maintains runtime state including:

- **Window List**: Open windows with properties
  - Position, size
  - Workspace assignment
  - Floating/tiled state
  - Stacking order

- **Workspace State**: For each of 9 workspaces
  - Active layout (tile, scroller, monocle, etc.)
  - Window arrangement
  - Master area configuration (nmaster, mfact)

- **Input State**:
  - Keyboard focus
  - Mouse cursor position
  - Input grab state

- **Clipboard**: Wayland clipboard contents

**Persistence**: Session state persists as long as compositor process runs. State is NOT saved to disk (by design).

### State Files (ephemeral)

Located in `$XDG_RUNTIME_DIR/mango/` (typically `/run/user/1000/mango/`):

- `wayland-1` - Wayland socket file
- `wayland-1.lock` - Socket lock file
- IPC socket (if MangoWC IPC enabled)

These files are automatically created/destroyed with compositor lifecycle.

## 4. Remote Desktop Configuration

### wayvnc Configuration File

Located at `/etc/wayvnc/config`:

```ini
address=0.0.0.0
port=5900
enable_auth=true
enable_pam=true

# Optional TLS encryption
# certificate_file=/path/to/cert.pem
# private_key_file=/path/to/key.pem

# Performance tuning
# xkb_layout=us
# xkb_variant=
```

### PipeWire Audio Configuration

PipeWire network audio module configuration (via NixOS):

```nix
services.pipewire.extraConfig.pipewire = {
  "context.modules" = [
    {
      name = "libpipewire-module-protocol-pulse";
      args = {
        "server.address" = [ "tcp:0.0.0.0:4713" ];
        "pulse.min.req" = "256/48000";      # Low latency
        "pulse.min.quantum" = "256/48000";
      };
    }
  ];
};
```

## 5. User Customization

### Home-Manager Configuration (optional)

Users can override system defaults via home-manager:

```nix
# home-modules/tools/mangowc-config.nix
{ config, pkgs, ... }:

{
  home.file.".config/mango/config.conf".text = ''
    # User-specific overrides
    # These take precedence over /etc/mangowc/config.conf
  '';

  home.file.".config/mango/autostart.sh" = {
    executable = true;
    text = ''
      #!/bin/sh
      # User-specific autostart commands
    '';
  };
}
```

## 6. Environment Variables

### Compositor Environment

Set by systemd service:

```bash
# Headless backend (no physical display)
WLR_BACKENDS=headless

# Disable input device requirement
WLR_LIBINPUT_NO_DEVICES=1

# Virtual display configuration
WLR_HEADLESS_OUTPUTS=1

# Display resolution
WLR_OUTPUT_MODE=1920x1080

# Wayland socket
WAYLAND_DISPLAY=wayland-1

# XDG directories
XDG_RUNTIME_DIR=/run/user/1000
XDG_CONFIG_HOME=$HOME/.config

# MangoWC config path
MANGOWC_CONFIG_DIR=/etc/mangowc
```

### wayvnc Environment

```bash
WAYLAND_DISPLAY=wayland-1
XDG_RUNTIME_DIR=/run/user/1000
```

## 7. Firewall Rules

### Required Ports

```nix
networking.firewall = {
  allowedTCPPorts = [
    5900   # VNC (wayvnc)
    4713   # PulseAudio/PipeWire network protocol
  ];
};
```

## 8. Data Flow

```
┌─────────────────┐
│  VNC Client     │
│  (TigerVNC,     │
│   RealVNC)      │
└────────┬────────┘
         │ Port 5900 (video/input)
         │ Port 4713 (audio)
         ↓
┌─────────────────┐
│  Hetzner Cloud  │
│  NixOS Server   │
├─────────────────┤
│                 │
│  ┌───────────┐  │
│  │  wayvnc   │  │ ← VNC server
│  └─────┬─────┘  │
│        │        │
│  ┌─────↓─────┐  │
│  │  MangoWC  │  │ ← Wayland compositor
│  │ Compositor│  │   (wlroots headless)
│  └─────┬─────┘  │
│        │        │
│  ┌─────↓─────┐  │
│  │ PipeWire  │  │ ← Audio system
│  └───────────┘  │
│                 │
│  ┌───────────┐  │
│  │Applications│  │ ← foot, firefox, etc.
│  └───────────┘  │
└─────────────────┘
```

### Authentication Flow

```
1. VNC Client connects to port 5900
2. wayvnc requests authentication
3. PAM authenticates against system (1Password-backed)
4. On success, screen capture begins
5. Input events forwarded to MangoWC compositor
6. Audio streams via separate PipeWire connection (port 4713)
```

## 9. Configuration Validation

### NixOS Module Assertions

```nix
config = mkIf config.services.mangowc.enable {
  assertions = [
    {
      assertion = config.services.wayvnc.enable -> config.services.mangowc.enable;
      message = "wayvnc requires MangoWC compositor to be enabled";
    }
    {
      assertion = all (ws: ws.id >= 1 && ws.id <= 9) config.services.mangowc.workspaces;
      message = "Workspace IDs must be between 1 and 9";
    }
    {
      assertion = config.services.mangowc.user != "root";
      message = "MangoWC should not run as root";
    }
  ];
};
```

## Summary

The MangoWC data model consists of:

1. **NixOS Options**: Declarative configuration via module system
2. **Config Files**: Generated from NixOS options
3. **Runtime State**: Managed by compositor (ephemeral)
4. **Remote Access**: wayvnc + PipeWire network audio
5. **User Overrides**: Optional home-manager customization

All configuration is declarative and reproducible via NixOS rebuild.
