# Quick Start: NixOS with i3wm Desktop

**Feature**: 009-let-s-create (KDE Plasma → i3wm Migration)
**Date**: 2025-10-17
**Audience**: Developers and system administrators using the migrated configuration

## Overview

This guide provides a quick start for using NixOS with i3wm desktop environment after the KDE Plasma → i3wm migration. The system uses a tiling window manager (i3), keyboard-first workflows, and declarative configuration management.

## Essential Keybindings

**Note**: i3wm uses the Windows/Super key as the modifier (`$mod = Mod4`). Workspace switching uses `Ctrl` for RDP compatibility.

### Core Actions
| Keybinding | Action |
|------------|--------|
| `Win+Return` | Open terminal (Alacritty) |
| `Win+d` | Application launcher (rofi) |
| `Win+v` | Clipboard history (clipcat) |
| `Win+i` | Show keybinding help |

### Quick Launch
| Keybinding | Action |
|------------|--------|
| `Win+c` | Launch VS Code |
| `Win+b` | Launch Firefox |

### Window Management
| Keybinding | Action |
|------------|--------|
| `Win+Shift+q` | Close window |
| `Win+f` | Fullscreen toggle |
| `Win+Shift+Space` | Toggle floating |
| `Win+h` | Split horizontal |
| `Win+Shift+\|` | Split vertical |
| `Win+s` | Stacking layout |
| `Win+w` | Tabbed layout |
| `Win+e` | Toggle split |

### Navigation
| Keybinding | Action |
|------------|--------|
| `Win+Arrows` | Change focus |
| `Win+Shift+Arrows` | Move window |
| `Ctrl+1-9` | Switch workspace (RDP-compatible) |
| `Win+Shift+1-9` | Move window to workspace |

### System
| Keybinding | Action |
|------------|--------|
| `Win+Shift+c` | Reload i3 config |
| `Win+Shift+r` | Restart i3 |
| `Win+Shift+e` | Exit i3 |

## System Configuration

### Building Configurations

```bash
# Test configuration changes (ALWAYS run first)
sudo nixos-rebuild dry-build --flake .#hetzner   # Hetzner Cloud
sudo nixos-rebuild dry-build --flake .#m1 --impure  # M1 Mac (--impure for firmware)
sudo nixos-rebuild dry-build --flake .#container # Container

# Apply configuration changes
sudo nixos-rebuild switch --flake .#hetzner
sudo nixos-rebuild switch --flake .#m1 --impure
sudo nixos-rebuild switch --flake .#container

# Remote deployment (from Codespace or another machine)
nixos-rebuild switch --flake .#hetzner --target-host vpittamp@hetzner --use-remote-sudo
```

### Configuration Structure

```
/etc/nixos/
├── flake.nix                   # System definitions
├── configurations/
│   ├── hetzner-i3.nix         # PRIMARY REFERENCE (Hetzner with i3wm)
│   ├── m1.nix                 # M1 Mac (extends hetzner-i3.nix)
│   ├── container.nix          # Container (extends hetzner-i3.nix)
│   └── base.nix               # Shared base configuration
├── modules/
│   ├── desktop/
│   │   ├── i3wm.nix           # i3 window manager module
│   │   └── xrdp.nix           # Remote desktop
│   └── services/
│       ├── development.nix    # Dev tools
│       ├── networking.nix     # Network services
│       └── onepassword.nix    # 1Password integration
└── home-modules/
    ├── desktop/
    │   ├── i3.nix             # User i3 configuration
    │   └── i3wsr.nix          # Workspace renaming
    └── tools/
        ├── clipcat.nix        # Clipboard manager
        └── firefox-pwas-declarative.nix  # PWA management
```

## Common Workflows

### Adding Packages

```nix
# System-wide packages (edit configurations/<platform>.nix)
environment.systemPackages = with pkgs; [
  neovim
  htop
  # ...
];

# User packages (edit home-vpittamp.nix)
home.packages = with pkgs; [
  ripgrep
  fd
  # ...
];
```

### Clipboard Usage

```bash
# View clipboard history
Win+v (or clipcatctl list)

# Copy text to clipboard
echo "text" | xclip -selection clipboard

# Clear clipboard history
Win+Shift+v (or clipcatctl clear)
```

### Progressive Web Apps (PWAs)

```bash
# List installed PWAs
firefoxpwa profile list
pwa-list

# Install all declared PWAs
pwa-install-all

# Get PWA IDs for configuration
pwa-get-ids

# Launch a PWA
firefoxpwa site launch <id>

# Update workspace names with PWA icons
i3wsr-update-config
systemctl --user restart i3wsr
```

### 1Password Integration

```bash
# Sign in to 1Password
op signin

# List items
op item list

# Retrieve password
op item get "Item Name" --fields password

# SSH with 1Password agent
SSH_AUTH_SOCK=~/.1password/agent.sock ssh user@host

# GitHub CLI with 1Password token
gh auth status  # Uses 1Password automatically
```

### Remote Desktop (Hetzner)

```bash
# Check xrdp status
systemctl status xrdp

# Connect via RDP client
# Address: <hetzner-ip>:3389
# Username: vpittamp
# Password: (from 1Password)

# Multi-session support: Each RDP connection gets independent i3 desktop
# Sessions persist across disconnection
```

## Troubleshooting

### i3wm Not Starting

```bash
# Check X11 server logs
journalctl -u display-manager -b

# Check i3 logs
cat ~/.local/share/xorg/Xorg.0.log
cat ~/.i3/i3.log

# Test i3 config syntax
i3 -C
```

### Clipboard Not Working

```bash
# Check clipcat service
systemctl --user status clipcat

# Restart clipcat
systemctl --user restart clipcat

# Verify xclip installed
which xclip xsel
```

### Workspace Names Not Updating (i3wsr)

```bash
# Check i3wsr service
systemctl --user status i3wsr

# Restart i3wsr
systemctl --user restart i3wsr

# Update i3wsr config with current PWAs
i3wsr-update-config
```

### Remote Desktop Connection Issues

```bash
# Check xrdp service
systemctl status xrdp

# Check xrdp logs
journalctl -u xrdp -b

# Verify port open
ss -tlnp | grep 3389

# Test local RDP (from server)
xfreerdp /v:localhost /u:vpittamp
```

### Display Issues (M1 HiDPI)

```bash
# Verify DPI settings
xdpyinfo | grep resolution

# Expected: 180x180 dots per inch

# Check X11 config
cat /etc/X11/xorg.conf.d/*.conf | grep DPI

# Restart X11 session
Win+Shift+r (restart i3)
# Or: sudo systemctl restart display-manager
```

## Development Workflows

### Editing Configuration

```bash
# Edit configuration
vim configurations/hetzner-i3.nix

# Test changes
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner

# Rollback if needed
sudo nixos-rebuild switch --rollback
```

### Updating Flake Inputs

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Rebuild with updated inputs
sudo nixos-rebuild switch --flake .#hetzner
```

### Container Development

```bash
# Build minimal container
nix build .#container-minimal

# Load into Docker
docker load < result

# Run container
docker run -it nixos-container:minimal

# Shell into running container
docker exec -it <container-id> bash
```

## Key Configuration Files

### System-Level (Generated)
- `/etc/i3/config` - i3 window manager configuration
- `/etc/i3status.conf` - Status bar configuration
- `/etc/i3/scripts/show-keybindings.sh` - Keybinding help

### User-Level (Home Manager)
- `~/.config/i3/config` - User-specific i3 overrides
- `~/.config/i3wsr/config.toml` - Workspace renaming rules
- `~/.config/alacritty/alacritty.yml` - Terminal configuration
- `~/.config/tmux/tmux.conf` - Terminal multiplexer

## Performance Monitoring

```bash
# System resource usage
htop
btop  # Better visualization

# Memory usage
free -h

# Disk usage
df -h
du -sh /nix/store

# Boot time analysis
systemd-analyze
systemd-analyze blame

# Service status
systemctl status
systemctl --user status
```

## Helpful Resources

### Documentation
- `CLAUDE.md` - LLM navigation guide (updated for i3wm)
- `docs/ARCHITECTURE.md` - System architecture
- `docs/M1_SETUP.md` - M1-specific setup guide
- `docs/PWA_SYSTEM.md` - PWA management system
- `specs/009-let-s-create/` - Migration planning documents

### Contracts
- `specs/009-let-s-create/contracts/i3wm-module.md` - i3wm module interface
- `specs/009-let-s-create/contracts/platform-config.md` - Platform configuration patterns
- `specs/009-let-s-create/contracts/migration-checklist.md` - Migration validation

### Research
- `specs/009-let-s-create/research.md` - Technology decisions and best practices
- `specs/009-let-s-create/data-model.md` - Configuration entities and relationships

## Quick Reference

### File Locations
| Component | Location |
|-----------|----------|
| System configs | `/etc/nixos/configurations/` |
| Desktop modules | `/etc/nixos/modules/desktop/` |
| Service modules | `/etc/nixos/modules/services/` |
| Home modules | `/etc/nixos/home-modules/` |
| User configs | `~/.config/` |
| Secrets | 1Password (op CLI) |

### Common Commands
| Task | Command |
|------|---------|
| Rebuild | `sudo nixos-rebuild switch --flake .#hetzner` |
| Test build | `sudo nixos-rebuild dry-build --flake .#hetzner` |
| Rollback | `sudo nixos-rebuild switch --rollback` |
| Update inputs | `nix flake update` |
| Garbage collect | `nix-collect-garbage -d` |
| List generations | `sudo nixos-rebuild list-generations` |
| Show flake | `nix flake show` |

### Platform-Specific Notes

**Hetzner (Remote Workstation)**
- Primary reference configuration
- Multi-session RDP via xrdp
- Full desktop environment
- Optimized for remote access

**M1 (Laptop)**
- Extends hetzner-i3.nix
- HiDPI: 180 DPI for Retina display
- X11 (migrated from Wayland)
- Local use case (no remote desktop)
- Requires `--impure` flag for Asahi firmware

**Container (Headless)**
- Extends hetzner-i3.nix with GUI disabled
- Minimal or development package profiles
- No X server, no window manager
- CLI tools only

---

**Last Updated**: 2025-10-17
**Migration Feature**: 009-let-s-create
**Configuration Version**: Post-migration to i3wm
