# NixOS PWA (Progressive Web App) System Documentation

## Overview

This document describes the declarative PWA management system for NixOS with KDE Plasma integration. The system provides automated installation, icon management, and taskbar pinning for web applications as desktop apps using Firefox PWA.

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│  firefox-pwas-declarative.nix  (PWA Declaration)        │
│  - Defines PWAs to install                              │
│  - Provides helper commands                             │
│  - Manages desktop integration                          │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  firefoxpwa (Runtime)                                   │
│  - Installs PWAs with generated ULIDs                   │
│  - Creates desktop files                                │
│  - Manages PWA profiles                                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│  panels.nix (KDE Integration)                           │
│  - Pins PWAs to taskbar                                 │
│  - Configures multi-monitor panels                      │
│  - Manages activity-based desktops                      │
└─────────────────────────────────────────────────────────┘
```

### File Structure

```
/etc/nixos/
├── home-modules/
│   ├── tools/
│   │   └── firefox-pwas-declarative.nix  # PWA declarations & automation
│   └── desktop/
│       └── project-activities/
│           └── panels.nix                 # KDE panel configuration with PWA pins
├── scripts/
│   ├── pwa-update-panels-fixed.sh        # Safe panel status checker
│   └── fix-pwa-icons.sh                  # Icon processing script
├── assets/
│   └── pwa-icons/                        # Custom PWA icons (512x512 PNG)
│       ├── google-ai.png
│       ├── youtube.png
│       ├── gitea.png
│       ├── backstage.png
│       ├── kargo.png
│       ├── argocd.png
│       └── headlamp.png
└── docs/
    └── PWA_SYSTEM.md                      # This documentation
```

## PWA Declaration Format

PWAs are declared in `/etc/nixos/home-modules/tools/firefox-pwas-declarative.nix`:

```nix
{
  name = "AppName";           # Display name (required)
  url = "https://app.com";    # Base URL (required)
  icon = "file:///etc/nixos/assets/pwa-icons/app.png";  # Icon path (required)
  description = "App description";  # Desktop file comment
  categories = "Network;";         # XDG categories
  keywords = "app;web;";           # Search keywords
}
```

## Available Commands

### Installation Commands

| Command | Description | Usage |
|---------|-------------|-------|
| `pwa-install-all` | Install all declared PWAs (idempotent) | Run after adding new PWAs to configuration |
| `pwa-list` | List configured and installed PWAs | Check installation status |
| `pwa-get-ids` | Get PWA IDs for panels.nix | Extract IDs for permanent pinning |

### Panel Management

| Command | Description | Usage |
|---------|-------------|-------|
| `pwa-update-panels` | Check PWA panel status and show required updates | Shows IDs for manual panels.nix update |
| `plasmashell --replace` | Restart Plasma shell | Apply panel changes |

### Maintenance Commands

| Command | Description | Usage |
|---------|-------------|-------|
| `/etc/nixos/scripts/fix-pwa-icons.sh` | Process and fix PWA icons | Run if icons don't display |
| `firefoxpwa profile list` | List installed PWA profiles | Debug PWA issues |
| `kbuildsycoca6 --noincremental` | Rebuild KDE cache | Fix icon visibility |

## Standard Workflow

### 1. Adding a New PWA

```bash
# Step 1: Edit PWA declaration
vim /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix

# Add your PWA to the list:
{
  name = "Claude";
  url = "https://claude.ai";
  icon = "file:///etc/nixos/assets/pwa-icons/claude-symbol.png";
  description = "AI Assistant";
  categories = "Network;Office;";
  keywords = "ai;chat;";
}

# Step 2: Add icon (if using custom)
wget https://commons.wikimedia.org/wiki/Special:FilePath/Claude_AI_symbol.svg -O /tmp/claude.svg
convert /tmp/claude.svg -resize 512x512 /etc/nixos/assets/pwa-icons/claude-symbol.png

# Step 3: Rebuild configuration
sudo nixos-rebuild switch --flake .#hetzner

# Step 4: Install PWA
pwa-install-all

# Step 5: Update panels for permanent pinning
pwa-update-panels  # Shows current status and IDs
# Copy the suggested panel configuration
vim /etc/nixos/home-modules/desktop/project-activities/panels.nix
# Update the appropriate machine's IDs (hetznerIds or m1Ids)
sudo nixos-rebuild switch --flake .#hetzner
```

### 2. Removing a PWA

```bash
# Step 1: Uninstall PWA
firefoxpwa site uninstall <PWA_ID>

# Step 2: Remove from declaration
vim /etc/nixos/home-modules/tools/firefox-pwas-declarative.nix
# Remove the PWA entry

# Step 3: Update panels.nix
vim /etc/nixos/home-modules/desktop/project-activities/panels.nix
# Remove the PWA ID and launcher entry

# Step 4: Rebuild
sudo nixos-rebuild switch --flake .#hetzner
```

### 3. Updating PWA Icons

```bash
# Replace icon file
cp new-icon.png /etc/nixos/assets/pwa-icons/app.png

# Process icons
/etc/nixos/scripts/fix-pwa-icons.sh

# Rebuild KDE cache
kbuildsycoca6 --noincremental

# Restart plasma if needed
plasmashell --replace
```

## Technical Details

### PWA ID System

- IDs are ULIDs (Universally Unique Lexicographically Sortable Identifiers)
- Format: 26-character string (e.g., `01K65QHPR1G9PYP1FTNPV7XJ8B`)
- Generated when PWA is installed
- Stable per installation but unique across machines
- Used in desktop files: `FFPWA-{ID}.desktop`

### Desktop File Locations

- **User desktop files**: `~/.local/share/applications/FFPWA-*.desktop`
- **Icon directories**: `~/.local/share/icons/hicolor/{size}x{size}/apps/FFPWA-*.png`
- **PWA profiles**: `~/.local/share/firefoxpwa/profiles/`
- **KDE panel config**: `~/.config/plasma-org.kde.plasma.desktop-appletsrc`

### Panel Configuration Structure

The `panels.nix` file defines:

1. **Primary Panel** (Containment 410, Screen 0):
   - Application launcher
   - Task manager with pinned apps
   - System tray
   - Clock

2. **Secondary Panels** (Containments 429/431, Screens 1/2):
   - Task manager (current screen only)
   - Activity switcher

### Icon Requirements

- **Format**: PNG (preferred) or SVG
- **Size**: 512x512 pixels minimum
- **Location**: `/etc/nixos/assets/pwa-icons/`
- **Processing**: Automatically resized to multiple sizes (16-512px)

## Troubleshooting

### Common Issues

#### PWAs Not Installing
```bash
# Check firefoxpwa is available
which firefoxpwa

# Check for errors
pwa-install-all 2>&1 | grep -i error

# Manual install attempt
firefoxpwa site install <manifest_url>
```

#### Icons Not Displaying
```bash
# Fix icon processing
/etc/nixos/scripts/fix-pwa-icons.sh

# Clear caches
rm -rf ~/.cache/icon-cache.kcache
kbuildsycoca6 --noincremental

# Check desktop file
cat ~/.local/share/applications/FFPWA-*.desktop | grep Icon
```

#### Taskbar Pins Lost
```bash
# Check current status and get IDs
pwa-update-panels

# The command will show the exact panel configuration needed
# Copy the suggested IDs to panels.nix
vim /etc/nixos/home-modules/desktop/project-activities/panels.nix

# Rebuild to apply permanent pins
sudo nixos-rebuild switch --flake .#hetzner
```

#### Panel Configuration Corrupted
```bash
# Stop plasma
kquitapp5 plasmashell

# Restore from home-manager
rm ~/.config/plasma-org.kde.plasma.desktop-appletsrc
sudo nixos-rebuild switch --flake .#hetzner

# Restart plasma
plasmashell --replace
```

### Debug Commands

```bash
# List all PWA desktop files
ls -la ~/.local/share/applications/FFPWA-*.desktop

# Check PWA profiles
firefoxpwa profile list

# View panel configuration
grep "launchers=" ~/.config/plasma-org.kde.plasma.desktop-appletsrc

# Check systemd service
systemctl --user status manage-pwas.service

# View installation logs
journalctl --user -u manage-pwas.service
```

## Configuration Reference

### Currently Configured PWAs

| Name | URL | Purpose |
|------|-----|---------|
| Google AI | https://www.google.com/search?udm=50 | Google AI mode search |
| YouTube | https://www.youtube.com | Video platform |
| Gitea | https://gitea.cnoe.localtest.me:8443 | Git repository |
| Backstage | https://backstage-dev.cnoe.localtest.me:8443 | Developer portal |
| Kargo | https://kargo.cnoe.localtest.me:8443 | GitOps promotion |
| ArgoCD | https://argocd.cnoe.localtest.me:8443 | Continuous delivery |
| Headlamp | https://headlamp.cnoe.localtest.me:8443 | Kubernetes dashboard |

### Environment Variables

The system respects standard XDG variables:
- `XDG_DATA_HOME` (default: `~/.local/share`)
- `XDG_CONFIG_HOME` (default: `~/.config`)
- `XDG_CACHE_HOME` (default: `~/.cache`)

## Multi-Machine Configuration

Since PWA IDs are unique per machine installation, the system supports different IDs for Hetzner and M1:

### Setting Up PWAs on Multiple Machines

1. **Install PWAs on Hetzner**:
   ```bash
   ssh nixos-hetzner
   pwa-install-all
   pwa-get-ids  # Copy these IDs
   ```

2. **Update panels.nix with Hetzner IDs**:
   ```nix
   hetznerIds = {
     googleId = "01K665SPD8EPMP3JTW02JM1M0Z";
     # ... paste other IDs
   };
   ```

3. **Install PWAs on M1**:
   ```bash
   ssh nixos-m1
   pwa-install-all
   pwa-get-ids  # Copy these IDs
   ```

4. **Update panels.nix with M1 IDs**:
   ```nix
   m1Ids = {
     googleId = "01K6XXXXXXXXXXXXXXXXXX";  # M1's unique ID
     # ... paste other IDs
   };
   ```

5. **Rebuild both systems**:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner  # On Hetzner
   sudo nixos-rebuild switch --flake .#m1       # On M1
   ```

The configuration automatically detects the hostname and uses the appropriate IDs.

## Best Practices

1. **Always use custom icons** - Default favicons are often low quality
2. **Test PWA installation** - Run `pwa-install-all` before rebuilding panels
3. **Keep machine IDs separate** - Don't mix Hetzner and M1 PWA IDs
4. **Document both sets of IDs** - Update panels.nix when installing on new machines
5. **Use meaningful names** - PWA names should be clear and consistent
6. **Regular maintenance** - Run `pwa-list` periodically to check status
7. **Use safe panel updates** - The `pwa-update-panels` command only shows status, never modifies read-only files
8. **Always rebuild after panel changes** - Panel configuration is managed by home-manager and requires rebuild

## Migration from Old System

If migrating from the old imperative PWA system:

1. **Remove old PWAs**: `firefoxpwa profile remove 00000000000000000000000000`
2. **Clean desktop files**: `rm ~/.local/share/applications/pwa-*.desktop`
3. **Clear old scripts**: Remove any manual PWA installation scripts
4. **Install fresh**: Run `pwa-install-all` with new system

## Related Documentation

- [Firefox PWA Documentation](https://github.com/filips123/PWAsForFirefox)
- [KDE Panel Configuration](https://userbase.kde.org/Plasma/Panels)
- [Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
- [NixOS Home Manager](https://github.com/nix-community/home-manager)

---

*System Version: 2.1 (Declarative with safe panel updates)*
*Last Updated: 2025-09-27*
*Maintainer: NixOS Configuration*
