# PWA Launcher Integration & Event Logging - Quick Start Guide

**Feature**: PWA Launcher Integration & Event Logging
**Status**: Draft
**Branch**: `054-pwa-launcher-integration`

## Overview

This feature fixes PWA (Progressive Web App) launcher integration to ensure Walker/Elephant can discover and launch the 13 already-installed Firefox PWAs, and adds app launcher event logging to `i3pm events` for full launch visibility.

**Problem**: All 13 PWAs are installed correctly via firefoxpwa (confirmed by `pwa-install-all`), but Walker/Elephant cannot discover or launch them. Additionally, launch attempts are invisible in `i3pm events` making debugging difficult.

**Solution**:
1. Fix desktop file discovery mechanism for Walker/Elephant
2. Ensure `launch-pwa-by-name` correctly maps app names to firefoxpwa profile IDs
3. Add app::launch, app::launch_success, app::launch_failed events to event buffer
4. Display launch events in `i3pm events` command with correlation to window::new events

## Quick Commands

```bash
# Verify PWAs are installed (should show all 13)
pwa-install-all
# Expected: 13 PWAs with "already installed" status

# Test direct PWA launch (bypasses Walker)
firefoxpwa site launch 01K666N2V6BQMDSBMX3AY74TY7  # YouTube

# Check if desktop files are discoverable
find ~/.local/share/applications/ ~/.local/share/i3pm-applications/applications/ -name "*youtube*" -o -name "*FFPWA*" 2>/dev/null

# Monitor launch events in real-time
i3pm events --follow
# Expected events: app::launch → app::launch_success → window::new → workspace::assignment

# Restart Elephant to refresh desktop file cache
systemctl --user restart elephant

# Launch PWA from Walker
# Press Meta+D, type "youtube", press Return
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

### 5. Verify Launch Events (Feature 054 - NEW)

```bash
# Monitor events during launch (run this BEFORE launching from Walker)
i3pm events --follow

# Then launch YouTube from Walker (Meta+D → "youtube" → Return)

# Expected output (table format with NEW launch events):
# TIME     TYPE                    WINDOW/APP              WORKSPACE  DETAILS
# ──────────────────────────────────────────────────────────────────────────────────────
# 09:06:17 app:launch              youtube-pwa            ?          pid=12345
# 09:06:17 app:launch_success      youtube-pwa            ?          exit=0 scope=run-12345
# 09:06:18 win:new                 FFPWA-youtube          ?          #24 (correlated)
# 09:06:18 ws:assign               FFPWA-youtube          → 4         ✓ launch_notif [Priority 0]
```

**New Event Types** (Feature 054):
- `app::launch` - Walker triggers app-launcher-wrapper.sh
- `app::launch_success` - systemd-run started successfully (exit code 0)
- `app::launch_failed` - systemd-run failed (exit code non-zero, includes error message)
- Events include launcher PID and timestamp for correlation with window::new

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

### Pre-Implementation (Current State)
- [X] All 13 PWAs installed via firefoxpwa (confirmed by `pwa-install-all` output)
- [X] PWA profile IDs documented (e.g., YouTube = 01K666N2V6BQMDSBMX3AY74TY7)
- [X] PWAs configured in `app-registry-data.nix` with `preferred_workspace`
- [ ] PWAs appear in Walker search results (FAILING - needs fix)
- [ ] PWAs launch from Walker (FAILING - needs fix)

### Post-Implementation (Feature 054)
- [ ] All 13 PWAs discoverable in Walker search
- [ ] YouTube PWA launches from Walker in <2 seconds
- [ ] YouTube window appears on workspace 4
- [ ] `i3pm events --follow` shows app::launch event when launching from Walker
- [ ] `i3pm events --follow` shows app::launch_success with exit code 0
- [ ] `i3pm events --follow` shows window::new event correlated to app::launch (within 5s)
- [ ] `i3pm events --follow` shows workspace::assignment with Priority 0 (launch_notification)
- [ ] Desktop file discovery command finds all 13 PWA .desktop files
- [ ] `pwa-list` shows 100% match between installed PWAs and discoverable desktop files
- [ ] Failed launch shows app::launch_failed event with error message

## Related Features

- **Feature 053**: Workspace Assignment Enhancement - provides event-driven workspace assignment and event buffer
- **Feature 043**: Walker/Elephant Launcher - provides application launcher service
- **Feature 041**: IPC Launch Context - provides launch notification correlation system
- **Feature 035**: Registry-Centric Architecture - provides application registry and app-launcher-wrapper.sh

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

## Success Metrics (Feature 054)

- ✅ All 13 installed PWAs discoverable in Walker search (100% discovery rate)
- ✅ PWA launches from Walker within 2 seconds (typing → window open)
- ✅ app::launch events visible in `i3pm events` within 50ms of Walker execution
- ✅ app::launch_success events show systemd-run output within 100ms
- ✅ Launch events correlate with window::new events within 5 seconds (95% correlation rate)
- ✅ workspace::assignment shows Priority 0 (launch_notification) for PWA launches
- ✅ Failed launches generate app::launch_failed events with error details
