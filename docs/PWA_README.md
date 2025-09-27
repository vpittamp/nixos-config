# Firefox PWA Management System for NixOS

A comprehensive system for managing Progressive Web Apps (PWAs) in Firefox on NixOS with KDE Plasma integration.

## Overview

This system allows you to:
- Install web applications as standalone PWAs using Firefox
- Automatically pin PWAs to the KDE Plasma taskbar
- Manage custom icons for better visual identification
- Configure PWAs through a centralized JSON configuration
- Add new PWAs with a simple command-line interface

## Components

### Core Files

- **`/etc/nixos/configs/pwas.json`** - Central configuration file containing all PWA definitions
- **`/etc/nixos/scripts/pwa-taskbar-pin.sh`** - Pins configured PWAs to the KDE taskbar
- **`/etc/nixos/scripts/add-pwa.sh`** - CLI tool for adding new PWAs
- **`/etc/nixos/scripts/update-pwa-icons.sh`** - Downloads and installs proper icons for PWAs

### PWA Locations

- **Desktop Files**: `~/.local/share/applications/FFPWA-*.desktop`
- **Icons**: `~/.local/share/icons/hicolor/[size]/apps/FFPWA-*.png`
- **Firefox Profiles**: `~/.local/share/firefoxpwa/profiles/`
- **KDE Configuration**: `~/.config/plasma-org.kde.plasma.desktop-appletsrc`

## Installation

### Prerequisites

Ensure your NixOS configuration includes:
```nix
programs.firefox = {
  enable = true;
  nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
};

environment.systemPackages = with pkgs; [
  firefoxpwa
  imagemagick  # For icon conversion
  jq           # For JSON processing
];
```

### Initial Setup

1. **Install Firefox PWA Extension**:
   - Open Firefox
   - Install the [PWA for Firefox](https://addons.mozilla.org/en-US/firefox/addon/pwas-for-firefox/) extension
   - The native messaging host should already be configured via NixOS

2. **Verify Installation**:
   ```bash
   firefoxpwa --version
   firefoxpwa runtime --version
   ```

## Usage

### Adding a New PWA

#### Method 1: Using the Add Script (Recommended)

```bash
# Basic usage - auto-detects icon and pins to taskbar
/etc/nixos/scripts/add-pwa.sh -n "Slack" -u "https://app.slack.com" -p

# Full example with all options
/etc/nixos/scripts/add-pwa.sh \
  -n "Discord" \
  -u "https://discord.com/app" \
  -d "Voice and text chat" \
  -i "https://discord.com/assets/favicon.ico" \
  -c "Network,Chat" \
  -k "gaming,voice,chat" \
  -p \
  -a "Personal"
```

**Options**:
- `-n, --name` - PWA name (required)
- `-u, --url` - Web app URL (required)
- `-d, --description` - App description
- `-i, --icon` - Icon URL (auto-detected if not provided)
- `-c, --categories` - Comma-separated categories
- `-k, --keywords` - Comma-separated keywords
- `-p, --pin` - Pin to taskbar after installation
- `-a, --activity` - KDE activity/workspace (default: all)
- `-h, --help` - Show help message

#### Method 2: Manual Configuration

1. **Edit `/etc/nixos/configs/pwas.json`**:
   ```json
   {
     "name": "Spotify",
     "url": "https://open.spotify.com",
     "description": "Music streaming service",
     "icon_url": "https://open.spotify.com/favicon.ico",
     "categories": ["AudioVideo", "Music"],
     "keywords": ["music", "streaming", "audio"],
     "custom_id": "spotify",
     "pin": true,
     "activities": "Personal"
   }
   ```

2. **Install the PWA**:
   ```bash
   firefoxpwa site install "https://open.spotify.com"
   ```

3. **Update the icon**:
   ```bash
   /etc/nixos/scripts/update-pwa-icons.sh "Spotify"
   ```

4. **Pin to taskbar** (if `pin: true`):
   ```bash
   /etc/nixos/scripts/pwa-taskbar-pin.sh
   ```

### Managing Existing PWAs

#### List Installed PWAs
```bash
firefoxpwa site list
```

#### Update Icons
```bash
# Update a specific PWA icon
/etc/nixos/scripts/update-pwa-icons.sh "ChatGPT"

# Update all PWA icons
/etc/nixos/scripts/update-pwa-icons.sh all
```

#### Remove a PWA
```bash
# Uninstall the PWA
firefoxpwa site uninstall [site-id]

# Remove from configuration
# Edit /etc/nixos/configs/pwas.json and remove the entry
```

#### Re-pin All PWAs to Taskbar
```bash
/etc/nixos/scripts/pwa-taskbar-pin.sh
```

## Current PWAs

The system comes pre-configured with these PWAs:

| Name | URL | Pinned | Activity |
|------|-----|--------|----------|
| Claude | https://claude.ai | ✓ | All |
| ChatGPT | https://chatgpt.com | ✓ | All |
| Google Gemini | https://gemini.google.com | ✓ | All |
| GitHub | https://github.com | ✓ | Development |
| Gmail | https://mail.google.com | ✓ | All |
| ArgoCD | https://argocd.jasonmadigan.dev | ✗ | Development |
| Backstage | https://demo.backstage.io | ✗ | Development |
| YouTube | https://youtube.com | ✓ | Personal |

## Icon Management

### Icon Storage Structure
Icons are stored in multiple sizes for optimal display:
```
~/.local/share/icons/hicolor/
├── 16x16/apps/FFPWA-*.png
├── 24x24/apps/FFPWA-*.png
├── 32x32/apps/FFPWA-*.png
├── 48x48/apps/FFPWA-*.png
├── 64x64/apps/FFPWA-*.png
├── 128x128/apps/FFPWA-*.png
├── 256x256/apps/FFPWA-*.png
└── 512x512/apps/FFPWA-*.png
```

### Fixing Icon Issues

If icons appear as blue squares or are missing:

1. **Update specific icon**:
   ```bash
   /etc/nixos/scripts/update-pwa-icons.sh "AppName"
   ```

2. **Rebuild icon cache**:
   ```bash
   kbuildsycoca6
   ```

3. **Restart Plasma** (if needed):
   ```bash
   kquitapp5 plasmashell && kstart5 plasmashell
   ```

4. **Or simply log out and back in**

## Troubleshooting

### PWA Not Installing

**Problem**: `firefoxpwa site install` fails

**Solutions**:
- Ensure Firefox PWA extension is installed and enabled
- Check that native messaging host is configured:
  ```bash
  ls ~/.mozilla/native-messaging-hosts/firefoxpwa.json
  ```
- Verify firefoxpwa is in PATH:
  ```bash
  which firefoxpwa
  ```

### Icons Not Displaying

**Problem**: PWAs show blue squares instead of proper icons

**Solutions**:
1. Run icon update script:
   ```bash
   /etc/nixos/scripts/update-pwa-icons.sh all
   ```
2. Clear icon cache and rebuild:
   ```bash
   rm -rf ~/.cache/icon-cache.kcache
   kbuildsycoca6
   ```
3. Log out and back in

### PWA Not Pinning to Taskbar

**Problem**: Running pin script doesn't add PWAs to taskbar

**Solutions**:
- Ensure the PWA is actually installed:
  ```bash
  firefoxpwa site list
  ```
- Check desktop file exists:
  ```bash
  ls ~/.local/share/applications/FFPWA-*.desktop
  ```
- Verify `pin: true` in `/etc/nixos/configs/pwas.json`
- Run the pin script with sudo if needed:
  ```bash
  sudo /etc/nixos/scripts/pwa-taskbar-pin.sh
  ```

### Finding PWA IDs

To find the internal ID of an installed PWA:
```bash
# List all PWAs with their IDs
for file in ~/.local/share/applications/FFPWA-*.desktop; do
    id=$(basename "$file" | sed 's/FFPWA-//' | sed 's/.desktop//')
    name=$(grep "^Name=" "$file" | cut -d= -f2)
    echo "$name: $id"
done
```

## Advanced Configuration

### KDE Activities Support

PWAs can be assigned to specific KDE Activities:
```json
{
  "name": "Work App",
  "activities": "Work",  // Single activity
  // or
  "activities": "all",   // All activities
  // or
  "activities": "Development,Work"  // Multiple activities
}
```

### Custom Categories

Available categories for `.desktop` files:
- `AudioVideo` - Media applications
- `Development` - Programming tools
- `Education` - Learning applications
- `Game` - Games
- `Graphics` - Image/design tools
- `Network` - Internet applications
- `Office` - Productivity tools
- `Settings` - Configuration tools
- `System` - System utilities
- `Utility` - General utilities

### Batch Operations

Add multiple PWAs from a list:
```bash
#!/bin/bash
# Example: batch-add-pwas.sh

pwas=(
  "Notion|https://notion.so"
  "Linear|https://linear.app"
  "Figma|https://figma.com"
)

for pwa in "${pwas[@]}"; do
  IFS='|' read -r name url <<< "$pwa"
  /etc/nixos/scripts/add-pwa.sh -n "$name" -u "$url" -p
  firefoxpwa site install "$url"
done

/etc/nixos/scripts/update-pwa-icons.sh all
```

## File Format Reference

### pwas.json Structure
```json
{
  "pwas": [
    {
      "name": "Required - Display name",
      "url": "Required - Full URL",
      "description": "Optional - Description",
      "icon_url": "Optional - Icon URL",
      "categories": ["Array", "of", "categories"],
      "keywords": ["search", "keywords"],
      "custom_id": "optional-custom-id",
      "pin": true,  // Pin to taskbar
      "activities": "all"  // KDE activities
    }
  ],
  "settings": {
    "icon_sizes": [16, 32, 48, 64, 128, 256],
    "auto_pin_taskbar": true,
    "activities": {
      "enabled": true,
      "default": "all",
      "available": ["all", "Development", "Personal", "Work"]
    }
  }
}
```

## Tips and Best Practices

1. **Icon URLs**: Use high-resolution icons when possible (512x512 or SVG)
2. **Naming**: Use consistent, descriptive names for PWAs
3. **Categories**: Assign appropriate categories for better organization
4. **Activities**: Use KDE Activities to separate work/personal apps
5. **Backup**: Keep a backup of `/etc/nixos/configs/pwas.json`
6. **Testing**: Test PWA installation manually before adding to configuration
7. **Updates**: Periodically run icon updates to refresh cached icons

## Contributing

To improve this system:
1. Scripts are located in `/etc/nixos/scripts/`
2. Configuration schema is in `/etc/nixos/configs/pwas.json`
3. Test changes with `--dry-run` flags where available
4. Document any new features or options

## License

Part of the NixOS configuration - see main repository for license details.

---
*Last updated: September 2025*