# PWA Installation Fix - Quick Start Guide

**Feature**: PWA Installation Fix
**Status**: Draft
**Branch**: `001-pwa-installation-fix`

## Overview

This feature fixes the PWA (Progressive Web App) installation system to ensure Firefox PWA desktop files are created correctly and accessible to the Walker/Elephant application launcher.

**Problem**: PWAs declared in `firefox-pwas-declarative.nix` don't appear in Walker launcher because FFPWA-*.desktop files are missing from `~/.local/share/applications/`.

**Solution**: Update PWA installation scripts to create proper FFPWA-*.desktop files and ensure Walker can discover them.

## Quick Commands

```bash
# Install all declared PWAs (creates FFPWA-*.desktop files)
pwa-install-all

# List PWA installation status
pwa-list

# Launch PWA directly (for testing)
firefoxpwa site launch <profile-id>

# Check PWA desktop files exist
ls ~/.local/share/applications/FFPWA-*.desktop

# Restart Elephant launcher to refresh cache
systemctl --user restart elephant

# Monitor PWA launch events
i3pm events --follow
```

## User Workflow

### 1. Declare PWA in Configuration

Edit `/etc/nixos/home-modules/tools/firefox-pwas-declarative.nix`:

```nix
{
  pwas = [
    {
      name = "YouTube";
      url = "https://youtube.com";
      iconPath = "/etc/nixos/assets/pwa-icons/youtube.png";
      categories = ["AudioVideo"];
    }
  ];
}
```

### 2. Configure in Application Registry

Edit `/etc/nixos/home-modules/desktop/app-registry-data.nix`:

```nix
{
  name = "youtube-pwa";
  command = "launch-pwa-by-name";
  parameters = ["youtube-pwa"];
  scope = "global";
  preferred_workspace = 4;
  nix_package = "firefoxpwa";
}
```

### 3. Rebuild and Install

```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch --flake .#hetzner-sway

# Install PWA (creates desktop file)
pwa-install-all

# Verify installation
pwa-list
# Expected output:
# youtube-pwa: INSTALLED (~/.local/share/applications/FFPWA-youtube-01K666N2V6BQMDSBMX3AY74TY7.desktop)
```

### 4. Launch from Walker

```bash
# Open Walker
Meta+D

# Type: youtube
# Press: Return

# Verify window opens on workspace 4
swaymsg -t get_workspaces | jq '.[] | select(.focused==true) | .num'
# Expected: 4
```

### 5. Verify Events

```bash
# Monitor events during launch
i3pm events --follow

# Expected output (table format):
# TIME     TYPE                    WINDOW/APP              WORKSPACE  DETAILS
# ─────────────────────────────────────────────────────────────────────────────
# 09:06:18 win:new                 FFPWA-youtube          ?          #24
# 09:06:18 ws:assign               FFPWA-youtube          → 4         ✓ daemon [nixos]
```

## Troubleshooting

### PWA Not Appearing in Walker

**Symptom**: Typing "youtube" in Walker shows no results.

**Check**:
```bash
# Verify desktop file exists
ls ~/.local/share/applications/FFPWA-*.desktop

# Check Elephant can see the file
systemctl --user status elephant
journalctl --user -u elephant -n 20

# Restart Elephant to refresh cache
systemctl --user restart elephant
```

**Fix**:
1. Run `pwa-install-all` to create desktop files
2. Restart Elephant: `systemctl --user restart elephant`
3. Try launching again from Walker

### PWA Launch Fails

**Symptom**: Walker shows PWA but clicking it does nothing or shows error.

**Check**:
```bash
# Test direct launch
firefoxpwa site launch <profile-id>

# Check launcher logs
tail -f ~/.local/state/app-launcher.log

# Check Elephant logs
journalctl --user -u elephant -f
```

**Fix**:
1. Verify Firefox PWA extension installed: `firefoxpwa --version`
2. Check PWA profile exists: `firefoxpwa site list`
3. Update profile ID in configuration if needed
4. Rebuild: `sudo nixos-rebuild switch --flake .#hetzner-sway`

### Wrong Desktop File Format

**Symptom**: Desktop files exist but have WebApp-*.desktop instead of FFPWA-*.desktop naming.

**Check**:
```bash
# Check desktop file naming
ls ~/.local/share/applications/ | grep -E '(FFPWA|WebApp)'

# Check launch-pwa-by-name script
cat ~/.config/i3/launch-pwa-by-name
# Should look for FFPWA-*.desktop files
```

**Fix**:
1. Remove old WebApp files: `rm ~/.local/share/applications/WebApp-*.desktop`
2. Run `pwa-install-all` to create correct FFPWA files
3. Verify: `ls ~/.local/share/applications/FFPWA-*.desktop`

### Events Not Showing

**Symptom**: PWA launches but `i3pm events` shows no window::new or workspace::assignment events.

**Check**:
```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check daemon logs
sudo journalctl -u i3-project-daemon --since "1 minute ago" | grep -E "window::new|workspace::assignment"

# Test events command
i3pm events --limit 20
```

**Fix**:
1. Restart daemon: `systemctl --user restart i3-project-event-listener`
2. Launch PWA again
3. Check events immediately: `i3pm events --limit 5`

## Testing Checklist

- [ ] PWA declared in `firefox-pwas-declarative.nix`
- [ ] PWA configured in `app-registry-data.nix` with `preferred_workspace`
- [ ] Configuration rebuilt with `sudo nixos-rebuild switch`
- [ ] `pwa-install-all` executed successfully
- [ ] FFPWA-*.desktop file exists in `~/.local/share/applications/`
- [ ] Elephant service restarted
- [ ] PWA appears in Walker search results
- [ ] PWA launches in dedicated window
- [ ] Window appears on configured workspace
- [ ] `i3pm events` shows window::new event
- [ ] `i3pm events` shows workspace::assignment event with correct project context

## Related Features

- **Feature 053**: Workspace Assignment Enhancement - provides event-driven workspace assignment
- **Feature 043**: Walker/Elephant Launcher - application launcher integration
- **Feature 035**: Registry-Centric Architecture - application registry system

## Configuration Files

- `/etc/nixos/home-modules/tools/firefox-pwas-declarative.nix` - PWA declarations
- `/etc/nixos/home-modules/desktop/app-registry-data.nix` - Application registry with workspace assignments
- `~/.local/share/applications/FFPWA-*.desktop` - Generated desktop files
- `~/.local/share/firefoxpwa/profiles/` - PWA profile data
- `~/.config/i3/launch-pwa-by-name` - PWA launcher script

## Logs and Diagnostics

```bash
# Application launcher logs
tail -f ~/.local/state/app-launcher.log

# Elephant service logs
journalctl --user -u elephant -f

# Daemon event logs
sudo journalctl -u i3-project-daemon -f

# Event monitoring
i3pm events --follow

# PWA installation status
pwa-list

# Firefox PWA profiles
firefoxpwa site list
```

## Success Metrics

- ✅ PWA launches from Walker within 2 seconds
- ✅ 100% of declared PWAs show in `pwa-list` as INSTALLED
- ✅ workspace::assignment events visible in `i3pm events` within 100ms of launch
- ✅ PWA workspace assignments work with 100% reliability
- ✅ Desktop files persist across system reboots
