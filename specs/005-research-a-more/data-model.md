# Data Model: i3wm Desktop Environment Configuration

**Feature**: Lightweight X11 Desktop Environment for Hetzner Cloud
**Branch**: `005-research-a-more`
**Date**: 2025-10-16
**Phase**: 1 - Design

## Overview

This document defines the configuration data model for the i3wm-based desktop environment. All configuration is declarative via NixOS modules - there are no runtime databases or mutable state files (except user-created application data).

## Configuration Entities

### 1. Window Manager Configuration

**Entity**: `services.i3wm`
**Purpose**: Configure i3 window manager behavior, appearance, and keybindings
**Persistence**: NixOS module options → generated `/etc/i3/config`
**Lifetime**: Static (changes require system rebuild)

**Attributes**:

```nix
{
  enable = bool;                    # Enable i3wm
  package = package;                # i3wm package (default: pkgs.i3)

  # Keybindings
  modifier = string;                # Mod key (default: "Mod4" = Super/Windows)
  keybindings = attrsOf string;     # Custom keybindings { "Mod4+Return" = "exec alacritty"; }

  # Workspaces
  workspaces = listOf workspace;    # Workspace definitions (see Workspace entity)
  defaultWorkspace = int;           # Initial workspace (1-10)

  # Appearance
  fonts = listOf string;            # Fonts for window titles/bar
  colors = colorScheme;             # Color scheme (see ColorScheme entity)
  gaps = gapsConfig;                # Window gaps (see GapsConfig entity)
  borders = borderConfig;           # Border configuration (see BorderConfig entity)

  # Bar
  bar = barConfig;                  # Status bar config (see BarConfig entity)

  # Startup
  startup = listOf startupCommand;  # Commands to run on i3 start

  # Extras
  extraPackages = listOf package;   # Additional packages (dmenu, i3status, etc.)
  extraConfig = lines;              # Raw i3 config appended to generated config
}
```

**Example**:
```nix
services.i3wm = {
  enable = true;
  modifier = "Mod4";
  workspaces = [
    { number = 1; name = "Main"; defaultLayout = "tabbed"; }
    { number = 2; name = "Code"; defaultLayout = "default"; }
  ];
  fonts = [ "DejaVu Sans Mono 10" ];
  extraPackages = with pkgs; [ dmenu i3status i3lock rofi ];
};
```

---

### 2. Workspace

**Entity**: Workspace definition
**Purpose**: Configure individual virtual desktops
**Persistence**: Part of i3 configuration
**Lifetime**: Static (changes require rebuild)

**Attributes**:

```nix
{
  number = int;              # Workspace number (1-10)
  name = string;             # Optional workspace name
  defaultLayout = enum;      # "default" | "stacking" | "tabbed"
  output = string;           # Optional monitor assignment (for multi-monitor)
}
```

**Constraints**:
- `number` must be between 1 and 10
- Workspace numbers must be unique
- If `name` omitted, workspace shown as number only

**Example**:
```nix
{
  number = 1;
  name = "Main";
  defaultLayout = "tabbed";
}
```

---

### 3. ColorScheme

**Entity**: i3 color scheme
**Purpose**: Define colors for window borders, bar, etc.
**Persistence**: Generated into i3 config
**Lifetime**: Static

**Attributes**:

```nix
{
  focused = colorSet;           # Focused window colors
  focusedInactive = colorSet;   # Focused but inactive window
  unfocused = colorSet;         # Unfocused windows
  urgent = colorSet;            # Urgent windows
  placeholder = colorSet;       # Placeholder windows
  background = string;          # Background color (hex)
}
```

**ColorSet**:
```nix
{
  border = string;        # Border color (hex)
  background = string;    # Background color (hex)
  text = string;          # Text color (hex)
  indicator = string;     # Split indicator color (hex)
  childBorder = string;   # Child container border (hex)
}
```

**Example**:
```nix
colors = {
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
  background = "#ffffff";
};
```

---

### 4. GapsConfig

**Entity**: Window gap configuration
**Purpose**: Configure spacing between windows (i3-gaps feature)
**Persistence**: Generated into i3 config
**Lifetime**: Static

**Attributes**:

```nix
{
  inner = int;     # Gap between adjacent windows (pixels)
  outer = int;     # Gap between windows and screen edge (pixels)
  smartGaps = bool; # Only show gaps when >1 window visible
  smartBorders = bool; # Only show borders when >1 window visible
}
```

**Example**:
```nix
gaps = {
  inner = 5;
  outer = 5;
  smartGaps = true;
  smartBorders = true;
};
```

---

### 5. BorderConfig

**Entity**: Window border configuration
**Purpose**: Configure window border appearance
**Persistence**: Generated into i3 config
**Lifetime**: Static

**Attributes**:

```nix
{
  width = int;              # Border width in pixels
  style = enum;             # "normal" | "pixel" | "none"
  hideEdgeBorders = enum;   # "none" | "vertical" | "horizontal" | "both" | "smart"
}
```

**Example**:
```nix
borders = {
  width = 2;
  style = "pixel";
  hideEdgeBorders = "smart";
};
```

---

### 6. BarConfig

**Entity**: i3bar/i3status configuration
**Purpose**: Configure status bar appearance and content
**Persistence**: Generated into i3 config + i3status config
**Lifetime**: Static

**Attributes**:

```nix
{
  enable = bool;                # Enable status bar
  position = enum;              # "top" | "bottom"
  mode = enum;                  # "dock" | "hide" | "invisible"
  statusCommand = string;       # Command to generate bar content (e.g., "i3status")
  fonts = listOf string;        # Bar fonts
  trayOutput = string;          # Monitor for system tray ("primary" | monitor name)
  colors = barColorScheme;      # Bar color scheme
  workspaceButtons = bool;      # Show workspace buttons
  stripWorkspaceNumbers = bool; # Hide workspace numbers, show names only
}
```

**BarColorScheme**:
```nix
{
  background = string;           # Bar background color
  statusline = string;           # Status text color
  separator = string;            # Separator color
  focusedWorkspace = colorSet;   # Focused workspace button colors
  activeWorkspace = colorSet;    # Active but unfocused workspace
  inactiveWorkspace = colorSet;  # Inactive workspace
  urgentWorkspace = colorSet;    # Urgent workspace
  bindingMode = colorSet;        # Binding mode indicator colors
}
```

**Example**:
```nix
bar = {
  enable = true;
  position = "bottom";
  statusCommand = "i3status";
  fonts = [ "DejaVu Sans Mono 10" ];
  workspaceButtons = true;
  colors = {
    background = "#000000";
    statusline = "#ffffff";
    separator = "#666666";
  };
};
```

---

### 7. StartupCommand

**Entity**: Startup command
**Purpose**: Applications/commands to run when i3 starts
**Persistence**: Generated into i3 config
**Lifetime**: Static

**Attributes**:

```nix
{
  command = string;       # Command to execute
  always = bool;          # Run on every i3 restart (not just session start)
  notification = bool;    # Display startup notification
}
```

**Example**:
```nix
startup = [
  { command = "nitrogen --restore"; always = false; notification = false; }
  { command = "dunst"; always = true; notification = false; }
];
```

---

### 8. XRDP Configuration

**Entity**: `services.xrdp`
**Purpose**: Configure XRDP remote desktop server
**Persistence**: NixOS module options → `/etc/xrdp/` configs
**Lifetime**: Static (changes require system rebuild)

**Attributes**:

```nix
{
  enable = bool;                      # Enable XRDP
  port = int;                         # RDP port (default: 3389)
  openFirewall = bool;                # Auto-open firewall port
  defaultWindowManager = string;      # Path to window manager (e.g., "${pkgs.i3}/bin/i3")

  # TLS/SSL
  sslCert = path;                     # TLS certificate path
  sslKey = path;                      # TLS private key path

  # Authentication
  authMethod = enum;                  # "pam" | "password" | "certificate"

  # Session
  sessionPolicy = enum;               # "Default" | "UBD" | "UBI" | "UBC"
  maxSessions = int;                  # Max concurrent sessions

  # Audio
  audioRedirection = bool;            # Enable PulseAudio redirection

  # Extra config
  extraConfig = lines;                # Raw xrdp.ini content
}
```

**Example**:
```nix
services.xrdp = {
  enable = true;
  port = 3389;
  openFirewall = true;
  defaultWindowManager = "${pkgs.i3}/bin/i3";
  authMethod = "pam";
  audioRedirection = true;
};
```

---

### 9. Display Configuration

**Entity**: `services.xserver.displayManager`
**Purpose**: Configure X11 display manager and session
**Persistence**: NixOS module options
**Lifetime**: Static

**Attributes**:

```nix
{
  # Session selection
  defaultSession = string;        # "none+i3" for i3wm without DM

  # Auto-login (optional)
  autoLogin = {
    enable = bool;
    user = string;
  };

  # LightDM (if used)
  lightdm = {
    enable = bool;
    greeters.gtk.enable = bool;
  };
}
```

**Example**:
```nix
services.xserver.displayManager = {
  defaultSession = "none+i3";
  lightdm.enable = false;  # No graphical login for remote-only setup
};
```

---

### 10. Audio Configuration

**Entity**: `hardware.pulseaudio` + `pulseaudio-module-xrdp`
**Purpose**: Configure PulseAudio for local and remote audio
**Persistence**: NixOS module options
**Lifetime**: Static

**Attributes**:

```nix
{
  enable = bool;                # Enable PulseAudio
  package = package;            # PulseAudio package (use pulseaudioFull for XRDP)
  support32Bit = bool;          # Enable 32-bit support

  # Network audio (for non-XRDP remote streaming)
  tcp = {
    enable = bool;
    anonymousClients.allowAll = bool;
  };

  # XRDP module (via environment.systemPackages)
  # pkgs.pulseaudio-module-xrdp must be installed
}
```

**Example**:
```nix
hardware.pulseaudio = {
  enable = true;
  package = pkgs.pulseaudioFull;
  support32Bit = true;
};

environment.systemPackages = [ pkgs.pulseaudio-module-xrdp ];
```

---

## Configuration Flow

```
User edits configurations/hetzner.nix
  ↓
NixOS module system evaluates services.i3wm options
  ↓
modules/desktop/i3wm.nix generates:
  - /etc/i3/config (from options)
  - /etc/i3status.conf (from bar.statusCommand options)
  ↓
modules/desktop/xrdp.nix generates:
  - /etc/xrdp/xrdp.ini
  - /etc/xrdp/sesman.ini
  - /etc/xrdp/startwm.sh (launches i3)
  ↓
nixos-rebuild switch applies changes
  ↓
systemd restarts xrdp.service
  ↓
User connects via RDP → XRDP launches i3 → i3 loads config
```

## State Management

### Immutable State (Declarative)

All configuration files are generated from NixOS options:
- `/etc/i3/config` - Generated from `services.i3wm` options
- `/etc/xrdp/xrdp.ini` - Generated from `services.xrdp` options
- `/etc/i3status.conf` - Generated from `services.i3wm.bar` options

Changes require:
1. Edit `.nix` configuration file
2. Run `nixos-rebuild switch --flake .#hetzner`
3. Restart i3 session (or reboot)

### Mutable State (User Data)

User-modified files (not managed by NixOS):
- `~/.config/i3/config` - User-specific i3 overrides (optional)
- `~/.i3/workspace_*` - i3 workspace layouts saved by user
- Application data in `~/.local/share/`, `~/.config/`, etc.

## Validation Rules

### Workspace Constraints
- Workspace numbers: 1-10 (i3 limitation)
- Workspace numbers must be unique
- At least 4 workspaces required (per FR-003)

### Color Constraints
- All colors in hex format: `#RRGGBB` or `#RRGGBBAA`
- Must provide complete colorSet for each color type

### Port Constraints
- XRDP port: 1-65535 (default: 3389)
- Port must not conflict with other services

### Font Constraints
- Fonts must be available in `pkgs.fonts` or user fonts
- Format: "Font Name Size" (e.g., "DejaVu Sans Mono 10")

## Migration Strategy

### From KDE Plasma to i3wm

**Phase 1: Parallel Deployment**
1. Keep KDE configuration intact
2. Add i3wm module alongside KDE
3. Configure XRDP to offer session choice at login
4. User can test i3 without losing KDE fallback

**Phase 2: Data Migration**
No user data migration needed:
- Application data (browser profiles, editor config) independent of WM
- User files in home directory unchanged
- SSH keys, Git config, 1Password data unaffected

**Phase 3: Cleanup**
1. Validate i3 meets all requirements
2. Remove KDE Plasma module from configuration
3. Set i3 as default and only session
4. Rebuild system

## Security Considerations

### XRDP Authentication
- Use PAM authentication (integrates with system users)
- TLS encryption for RDP protocol (XRDP default)
- Optional: 1Password SSH agent for additional auth layer

### File Permissions
- Generated config files: 0644 (world-readable, root-owned)
- XRDP SSL keys: 0600 (root-only read)
- User i3 config: 0644 (user-owned)

### Network Security
- XRDP port should be firewalled (only allow Tailscale network)
- No password authentication over public internet
- Use Tailscale VPN for remote access

## Testing Strategy

### Configuration Validation
```bash
# Validate i3 config syntax
nix-build -A config.environment.etc."i3/config".source

# Validate NixOS configuration
nixos-rebuild dry-build --flake .#hetzner-i3

# Test in VM before deploying
nixos-rebuild build-vm --flake .#hetzner-i3
```

### Runtime Validation
```bash
# Check i3 config after deployment
i3 -C -c /etc/i3/config

# Check XRDP service status
systemctl status xrdp

# Test XRDP connection (local)
xfreerdp /v:localhost:3389 /u:vpittamp
```

## References

- i3 User Guide: https://i3wm.org/docs/userguide.html
- i3 Configuration Reference: https://i3wm.org/docs/userguide.html#configuring
- NixOS Manual - X11: https://nixos.org/manual/nixos/stable/index.html#sec-x11
- XRDP Configuration: http://xrdp.org/
