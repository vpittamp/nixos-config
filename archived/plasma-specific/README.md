# Archived Plasma-Specific Modules

**Date**: 2025-10-17
**Reason**: KDE Plasma to i3wm migration (Feature 009)

## Contents

This directory contains modules that were specific to KDE Plasma and are no longer relevant after migrating to i3wm.

### desktop/project-activities/
KDE Activities integration system that provided:
- Activity management with keyboard shortcuts (Meta+1-4)
- Activity-specific panels and desktop widgets
- Automatic window assignment to activities
- Activity-aware application launchers
- PWA integration with activity taskbars

**Archived because**: i3wm doesn't have a concept of "activities". Users should use i3wm workspaces (Ctrl+1-9) instead.

### desktop/activity-aware-apps-native.nix
Application launchers that opened in activity-specific directories:
- konsole-activity - Terminal in activity directory
- code-activity - VS Code in activity directory
- dolphin-activity - File manager in activity directory
- yakuake-activity - Drop-down terminal with activity awareness
- KWin window rules for activity assignment

**Archived because**: i3wm uses simpler workspace model. Users can manually organize projects by directory.

### desktop/kde-plasma.nix
Complete KDE Plasma 6 desktop environment configuration:
- X11 and Wayland display server setup
- SDDM display manager
- Plasma 6 desktop environment
- Touchegg gesture support for X11
- PipeWire/PulseAudio configuration
- KDE applications (Kate, Konsole, Dolphin, etc.)
- Clipboard management (Klipper)
- Hardware acceleration and Bluetooth

**Archived because**: Hetzner migrating to i3wm + X11 for better remote access compatibility. M1 still uses this module.

### desktop/kde-plasma-vm.nix
KDE Plasma optimizations for virtual machines:
- Virtual display driver configuration
- VM-specific graphics settings
- Performance tuning for virtualized environments

**Archived because**: No longer needed for i3wm setup on Hetzner.

### desktop/wayland-remote-access.nix
Wayland-specific remote access configuration:
- Wayland compositor settings for RDP
- Screen sharing and remote desktop protocols for Wayland

**Archived because**: i3wm uses X11, not Wayland. XRDP works natively with X11.

### home-modules/plasma-config.nix
KDE Plasma home-manager configuration:
- Plasma desktop settings and theming
- Window rules and keyboard shortcuts
- Application preferences
- Kwin compositor settings

**Archived because**: Home-manager configuration specific to KDE Plasma, not needed for i3wm.

### home-modules/plasma-sync.nix
Plasma configuration synchronization:
- Automated backup/restore of Plasma settings
- Declarative plasma configuration management

**Archived because**: Plasma-specific synchronization not applicable to i3wm.

### home-modules/plasma-snapshot-analysis.nix
Plasma configuration analysis tool:
- Snapshot and diff Plasma configuration files
- Debug declarative plasma configuration

**Archived because**: Debugging tool for Plasma configuration, not needed for i3wm.

### home-modules/touchpad-gestures.nix
Touchpad gesture configuration:
- Touchegg configuration for X11 gesture support
- Wayland has native gesture support

**Archived because**: i3wm module handles gesture configuration directly if needed.

## Migration Notes

**For users who relied on project activities:**

### What Changed?
- **Activities → Workspaces**: Use i3wm workspaces (Ctrl+1-9) instead of KDE activities
- **Activity-aware launchers → Manual organization**: Organize projects in directories
- **Auto window assignment → Manual workspace assignment**: Move windows with Super+Shift+1-9

### What Still Works?
✅ Firefox PWAs (via firefox-pwas-declarative.nix) ✅ Clipboard management (clipcat)
✅ Tmux session management (sesh - now using zoxide for directory navigation)
✅ Remote desktop (xrdp)
✅ 1Password integration

### Recommended Alternatives
- **Directory navigation**: Use `zoxide` + `sesh` for quick project switching
- **Session management**: Use tmux sessions (sesh integrates with tmux)
- **Workspace organization**: Manually assign applications to workspaces with Super+Shift+1-9
- **PWA management**: Firefox PWAs still work, just launch them normally

## Recovery

If you need to restore this functionality (e.g., switching back to KDE Plasma):

### For Project Activities (home-manager):

1. Copy modules back to their original locations:
   ```bash
   cp -r archived/plasma-specific/desktop/project-activities home-modules/desktop/
   cp archived/plasma-specific/desktop/activity-aware-apps-native.nix home-modules/desktop/
   ```

2. Uncomment imports in `home-modules/profiles/plasma-home.nix`:
   ```nix
   ../desktop/project-activities
   ../desktop/activity-aware-apps-native.nix
   ```

3. Restore sesh.nix activity integration (see git history for original version)

4. Rebuild system

### For KDE Plasma Desktop (system-level):

1. Copy desktop modules back:
   ```bash
   cp archived/plasma-specific/desktop/kde-plasma.nix modules/desktop/
   cp archived/plasma-specific/desktop/kde-plasma-vm.nix modules/desktop/
   cp archived/plasma-specific/desktop/wayland-remote-access.nix modules/desktop/
   ```

2. Update `configurations/hetzner.nix` imports (around line 25):
   ```nix
   ../modules/desktop/kde-plasma.nix
   ../modules/desktop/remote-access.nix  # May need to restore this too
   ```

3. Re-enable plasma-home in `home-vpittamp.nix`:
   ```nix
   ./home-modules/profiles/plasma-home.nix
   ```

4. Rebuild system

## Git History

Full implementation is preserved in git history. Key commits:
- Initial implementation: [search git log for "project-activities"]
- Removal: Branch 009-let-s-create

