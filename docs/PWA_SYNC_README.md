# PWA Sync - Unified Declarative PWA Management

A comprehensive, idempotent PWA management system for NixOS that ensures your Firefox PWAs are always in sync with your declarative configuration.

## Features

- **Idempotent Operations**: Run multiple times safely - only applies necessary changes
- **Declarative Configuration**: Define all PWAs in `/etc/nixos/configs/pwas.json`
- **Smart Icon Management**: Downloads icons with automatic fallback URLs
- **Taskbar Integration**: Automatically pins PWAs to KDE Plasma taskbar
- **Efficient**: Only processes changes, skips already configured PWAs
- **Dry-run Mode**: Preview changes before applying them

## Installation

The script is installed at:
```
/etc/nixos/scripts/pwa-sync.sh
```

## Usage

### Basic Commands

```bash
# Sync PWAs from configuration (default)
/etc/nixos/scripts/pwa-sync.sh

# Show currently installed PWAs
/etc/nixos/scripts/pwa-sync.sh status

# Preview changes without applying
/etc/nixos/scripts/pwa-sync.sh dry-run

# Show help
/etc/nixos/scripts/pwa-sync.sh help
```

### Environment Variables

```bash
# Use custom config file
PWA_CONFIG=~/my-pwas.json /etc/nixos/scripts/pwa-sync.sh

# Enable verbose output
VERBOSE=true /etc/nixos/scripts/pwa-sync.sh

# Dry run mode via environment
DRY_RUN=true /etc/nixos/scripts/pwa-sync.sh
```

## Configuration Format

Edit `/etc/nixos/configs/pwas.json`:

```json
{
  "pwas": [
    {
      "name": "App Name",
      "url": "https://app.example.com",
      "description": "App description",
      "icon_url": "https://app.example.com/icon.png",
      "icon_fallbacks": [
        "https://app.example.com/favicon.ico",
        "https://cdn.example.com/app-icon.svg"
      ],
      "pin": true,
      "categories": ["Development", "Office"],
      "keywords": ["example", "app"],
      "activities": "all"
    }
  ]
}
```

### Configuration Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name for the PWA |
| `url` | Yes | URL of the web application |
| `description` | No | Description of the app |
| `icon_url` | No | Primary icon URL |
| `icon_fallbacks` | No | Array of fallback icon URLs |
| `pin` | No | Pin to taskbar (true/false) |
| `categories` | No | Desktop file categories |
| `keywords` | No | Search keywords |
| `activities` | No | KDE activities assignment |

## How It Works

1. **Detection Phase**
   - Reads configuration from JSON
   - Queries `firefoxpwa profile list` for installed PWAs
   - Compares URLs to determine what needs to be done

2. **Installation Phase**
   - Installs missing PWAs using `firefoxpwa site install`
   - Uses custom name, icon, and description if provided
   - Completely idempotent - safe to run multiple times

3. **Icon Management**
   - Downloads icons from primary URL
   - Falls back to alternative URLs if primary fails
   - Converts icons to PNG format
   - Installs in multiple sizes (16x16 to 512x512)
   - Updates KDE icon cache

4. **Taskbar Integration**
   - Checks plasma configuration
   - Adds PWA desktop files to launcher
   - Only modifies if not already pinned

## Examples

### Add a New PWA

1. Edit `/etc/nixos/configs/pwas.json` to add your PWA
2. Run sync:
   ```bash
   /etc/nixos/scripts/pwa-sync.sh
   ```

### Update Icons for All PWAs

```bash
# The sync command will update icons automatically
/etc/nixos/scripts/pwa-sync.sh
```

### Check What Would Change

```bash
/etc/nixos/scripts/pwa-sync.sh dry-run
```

### Restore After System Restart

Simply run:
```bash
/etc/nixos/scripts/pwa-sync.sh
```

This will:
- Verify all PWAs are installed
- Restore any missing icons
- Re-pin to taskbar if needed

## Integration with NixOS

Add to your NixOS configuration for automatic setup:

```nix
# In your configuration.nix or home-manager config
systemd.user.services.pwa-sync = {
  description = "Sync Firefox PWAs";
  after = [ "graphical-session.target" ];
  wantedBy = [ "default.target" ];
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/pwa-sync.sh";
    StandardOutput = "journal";
    StandardError = "journal";
  };
};

# Optional: Run on login
systemd.user.timers.pwa-sync = {
  description = "Sync PWAs on login";
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnStartupSec = "30s";
    OnUnitActiveSec = "1h";
  };
};
```

## Troubleshooting

### Icons Not Showing

1. Check icon URLs are accessible:
   ```bash
   curl -I https://your-icon-url.png
   ```

2. Update icon cache manually:
   ```bash
   kbuildsycoca6
   kquitapp5 plasmashell && kstart5 plasmashell
   ```

### PWA Not Installing

1. Verify URL is correct and accessible
2. Check firefoxpwa is working:
   ```bash
   firefoxpwa --version
   firefoxpwa profile list
   ```

3. Try manual installation to see errors:
   ```bash
   firefoxpwa site install "https://app.url"
   ```

### Taskbar Pinning Not Working

1. Ensure Plasma config exists:
   ```bash
   ls -la ~/.config/plasma-org.kde.plasma.desktop-appletsrc
   ```

2. Check desktop file was created:
   ```bash
   ls ~/.local/share/applications/FFPWA-*.desktop
   ```

## Advantages Over Previous Scripts

1. **True Idempotency**: Uses `firefoxpwa profile list` to check actual installed state
2. **No Hardcoded IDs**: PWA IDs are discovered dynamically
3. **Efficient**: Only processes what needs to be changed
4. **Robust Error Handling**: Continues on individual failures
5. **Better Icon Support**: Automatic fallbacks and format conversion
6. **Clear Output**: Shows exactly what's happening at each step
7. **Dry-run Support**: Test changes before applying

## Files and Locations

- **Configuration**: `/etc/nixos/configs/pwas.json`
- **Script**: `/etc/nixos/scripts/pwa-sync.sh`
- **PWA Profiles**: `~/.local/share/firefoxpwa/profiles/`
- **Desktop Files**: `~/.local/share/applications/FFPWA-*.desktop`
- **Icons**: `~/.local/share/icons/hicolor/*/apps/FFPWA-*.png`
- **Plasma Config**: `~/.config/plasma-org.kde.plasma.desktop-appletsrc`

---
*Last updated: September 2025*