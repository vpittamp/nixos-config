# M1 vs Hetzner-Sway Configuration Comparison Report
Generated: 2025-10-31

## Executive Summary

Both M1 MacBook Pro and Hetzner Cloud Server configurations are now **fully aligned** on Sway/Wayland with dynamic configuration management (Feature 047). The configurations are clean, with only expected platform-specific differences (physical displays vs headless).

### Key Finding
**All keybindings are now dynamically managed through Feature 047 (sway-config-manager)** - there are no static keybinding files in home-manager. Both platforms use the same configuration approach.

---

## 1. System-Level Configuration (System Services)

### M1 MacBook Pro (`configurations/m1.nix`)
**File**: `/etc/nixos/configurations/m1.nix` (355 lines)

**Key System Imports**:
```
- ./base.nix (shared)
- ../modules/assertions/m1-check.nix
- ../hardware/m1.nix
- ../modules/desktop/sway.nix (system-level Sway)
- ../modules/services/development.nix
- ../modules/services/networking.nix
- ../modules/services/onepassword.nix
- ../modules/services/i3-project-daemon.nix ✓ (Feature 037)
- ../modules/services/onepassword-automation.nix
- ../modules/services/onepassword-password-management.nix
- ../modules/services/speech-to-text-safe.nix
- ../modules/desktop/firefox-1password.nix
- ../modules/desktop/firefox-pwa-1password.nix
```

**Services Configuration**:
- `services.sway.enable = true` (Wayland compositor)
- `services.greetd` (Wayland login manager with tuigreet)
- `services.i3ProjectDaemon.enable = true` (Feature 037)
- `services.speech-to-text` (enabled)
- `services.tailscale.enable = true`

**Platform-Specific Hardware**:
- Single physical display: eDP-1 (Retina 3024x1890 @ 2x scale)
- Touchpad: Natural scrolling, tap-to-click, clickfinger (Apple-style)
- WiFi: BCM4378 with power management workaround
- GPU: Apple Silicon with Asahi driver support
- Display Manager: `greetd` with auto-login

---

### Hetzner Cloud (`configurations/hetzner-sway.nix`)
**File**: `/etc/nixos/configurations/hetzner-sway.nix` (243 lines)

**Key System Imports**:
```
- ./base.nix (shared)
- ../disk-config.nix
- ../modules/assertions/hetzner-check.nix
- (modulesPath + "/profiles/qemu-guest.nix")
- ../modules/services/development.nix
- ../modules/services/networking.nix
- ../modules/services/onepassword.nix
- ../modules/services/i3-project-daemon.nix ✓ (Feature 037)
- ../modules/services/keyd.nix (CapsLock → F9 mapping)
- ../modules/desktop/sway.nix (system-level Sway)
- ../modules/desktop/wayvnc.nix (VNC server module)
- ../modules/services/onepassword-automation.nix
- ../modules/services/onepassword-password-management.nix
- ../modules/services/speech-to-text-safe.nix
- ../modules/services/tailscale-audio.nix
```

**Services Configuration**:
- `programs.sway.enable = true` (Wayland compositor)
- `services.wayvnc.enable = true` (VNC server)
- `services.greetd` (Wayland login with headless environment variables)
- `services.i3ProjectDaemon.enable = true` (Feature 037)
- `services.tailscale.enable = true`

**Platform-Specific**:
- Headless Wayland: 3 virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3)
- WLR environment variables for headless operation
- VNC servers on ports 5900, 5901, 5902
- Software rendering (pixman) + GTK4 Cairo (GSK_RENDERER=cairo)
- No input devices (WLR_LIBINPUT_NO_DEVICES=1)
- Tailscale audio streaming to remote sink

---

## 2. Home-Manager Configuration (User Environment)

### M1 MacBook Pro (`home-vpittamp.nix`)
**File**: `/etc/nixos/home-vpittamp.nix` (79 lines)

**Home-Manager Imports**:
```
- ./home-modules/profiles/base-home.nix (shared base)
- ./home-modules/desktop/sway.nix (home-manager Sway config)
- ./home-modules/desktop/swaybar.nix (status bar)
- ./home-modules/desktop/sway-config-manager.nix (Feature 047)
- ./home-modules/profiles/declarative-cleanup.nix
- ./home-modules/desktop/i3-project-daemon.nix (home-manager daemon)
- ./home-modules/tools/i3pm-deno.nix (CLI tool)
- ./home-modules/tools/i3pm-diagnostic.nix (diagnostics)
- ./home-modules/desktop/walker.nix (app launcher)
- ./home-modules/desktop/app-registry.nix
- ./home-modules/tools/app-launcher.nix
- ./home-modules/tools/i3pm-workspace-mode-wrapper.nix (Feature 042)
```

**Home-Manager Location**: Flake.nix line 141
```nix
users.vpittamp = {
  imports = [
    ./home-vpittamp.nix
    inputs.plasma-manager.homeModules.plasma-manager
  ];
};
```

---

### Hetzner Cloud (`home-modules/hetzner-sway.nix`)
**File**: `/etc/nixos/home-modules/hetzner-sway.nix` (51 lines)

**Home-Manager Imports**:
```
- ./profiles/base-home.nix (shared base)
- ./profiles/declarative-cleanup.nix
- ./desktop/sway.nix (home-manager Sway config)
- ./desktop/swaybar.nix (status bar)
- ./desktop/sway-config-manager.nix (Feature 047)
- ./tools/i3pm-deno.nix (CLI tool)
- ./tools/i3pm-diagnostic.nix (diagnostics)
- ./tools/i3pm-workspace-mode-wrapper.nix (Feature 042)
- ./desktop/walker.nix (app launcher)
- ./desktop/app-registry.nix
- ./tools/app-launcher.nix
```

**Home-Manager Location**: Flake.nix line 211
```nix
users.vpittamp = {
  imports = [
    ./home-modules/hetzner-sway.nix
  ];
};
```

---

## 3. Sway Configuration Files (Feature 047 - Dynamic Management)

### All Keybindings Are Now Dynamic

**Static Files (Nix-Managed)**:
```
✓ /etc/nixos/home-modules/desktop/sway.nix
  - System UI window rules (walker, fzf, floating terminal)
  - Output and input configuration (touchpad, keyboard)
  - Workspace assignments (platform-specific)
  - Static startup commands
  - Workspace mode definitions (embedded for Sway mode limitation)

✓ /etc/nixos/modules/desktop/sway.nix
  - System-level Sway service configuration
  - Wayland environment variables
  - PipeWire audio configuration
```

**Dynamic Files (Feature 047 - User-Editable)**:
```
Location: ~/.config/sway/

✓ keybindings.toml (PRIMARY - user editable, hot-reloadable)
  - ALL application keybindings
  - Window management keybindings
  - Workspace navigation
  - Project switching
  - Source: /etc/nixos/home-modules/desktop/sway-default-keybindings.toml

✓ appearance-generated.conf (auto-generated from appearance.json)
  - Colors, fonts, borders
  - Auto-updated by sway-config-manager daemon

✓ keybindings-generated.conf (auto-generated from keybindings.toml)
  - Compiled Sway syntax
  - Auto-updated by sway-config-manager daemon

✓ window-rules.json
  - User window rules (floating, sizing, positioning)
  - Scratchpad configuration

✓ workspace-assignments.json
  - Project-specific workspace assignments
  - Auto-applied per-project

✓ modes.conf
  - Workspace mode definitions (Feature 042)
  - Stored but included from sway.nix (hardcoded due to Sway limitation)
```

**Default Template Files** (in Nix store, copied to ~/.config on first run):
```
✓ ~/.local/share/sway-config-manager/templates/keybindings.toml
✓ ~/.local/share/sway-config-manager/templates/appearance.json
✓ ~/.local/share/sway-config-manager/templates/window-rules.json
✓ ~/.local/share/sway-config-manager/templates/workspace-assignments.json
```

---

## 4. Keybinding Configuration Management

### Keybindings Delivery Method

**M1 & Hetzner-Sway (IDENTICAL)**:

1. **Default Keybindings** (Feature 047):
   - File: `/etc/nixos/home-modules/desktop/sway-default-keybindings.toml`
   - Copied to: `~/.config/sway/keybindings.toml` on first daemon run
   - User can edit without rebuild

2. **Dynamic Compilation**:
   - sway-config-manager daemon watches `~/.config/sway/keybindings.toml`
   - Compiles to: `~/.config/sway/keybindings-generated.conf`
   - Generates Sway `bindsym` commands automatically

3. **Workspace Mode Keybindings**:
   - Definition location: `sway-config-manager.nix` lines 48-98 (modesConfContents)
   - Stored in: `~/.config/sway/modes.conf`
   - **Included directly in sway.nix extraConfig** (not via sway-config-manager)
   - Reason: Sway cannot include mode definitions from external files

4. **Platform-Specific Keybindings** (sway.nix extraConfig):
   ```
   M1 MacBook Pro:
   - CapsLock (bindcode 66) → workspace goto mode "→ WS"
   - Shift+CapsLock (bindcode 66 with Shift) → move mode "⇒ WS"
   
   Hetzner Cloud:
   - Control+0 → workspace goto mode "→ WS"
   - Control+Shift+0 → move mode "⇒ WS"
   ```

---

## 5. Feature Comparison

| Feature | M1 | Hetzner-Sway | Aligned? |
|---------|----|--------------|---------:|
| **Desktop Environment** | Sway/Wayland | Sway/Wayland | ✓ Yes |
| **Keybinding Management** | Feature 047 (dynamic) | Feature 047 (dynamic) | ✓ Yes |
| **Window Manager** | Sway (same as hetzner) | Sway (same as M1) | ✓ Yes |
| **Project Daemon** | Feature 037 (system service) | Feature 037 (system service) | ✓ Yes |
| **Application Launcher** | Walker | Walker | ✓ Yes |
| **Workspace Mode** | Feature 042 (CapsLock) | Feature 042 (Ctrl+0) | ✓ Yes |
| **Config Manager** | Feature 047 (sway-config-manager) | Feature 047 (sway-config-manager) | ✓ Yes |
| **Status Bar** | swaybar (event-driven) | swaybar (event-driven) | ✓ Yes |
| **Display Setup** | Physical (1-2 monitors) | Headless (3 virtual via VNC) | ✓ Platform-specific |
| **Input Devices** | Touchpad, Keyboard | None (VNC) | ✓ Platform-specific |
| **Audio** | Local PipeWire | Tailscale RTP streaming | ✓ Platform-specific |
| **Remote Access** | RustDesk | WayVNC (VNC) | ✓ Platform-specific |

---

## 6. Legacy & Backup Files That Can Be Removed

### Backup Files (Safe to Delete)
```
✓ /etc/nixos/configurations/hetzner-sway.nix.backup-20251029-143249
  - Created during recent edit (2025-10-29)
  - Can be safely removed

✓ /etc/nixos/home-modules/desktop/sway.nix.backup-20251029-143249
  - Created during recent edit (2025-10-29)
  - Can be safely removed

✓ /etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py.backup-before-037
  - Legacy daemon backup before Feature 037
  - Superseded by system service
  - Can be safely removed

✓ /etc/nixos/home-modules/tools/i3pm-deno/src/commands/rules.ts.backup
  - Deno CLI tool backup
  - Can be safely removed
```

### Legacy i3 Configuration Files (Superseded by Sway)
```
✓ /etc/nixos/home-modules/desktop/i3.nix
  - DISABLED in home-vpittamp.nix (commented out, lines 15-18)
  - Superseded by sway.nix
  - Safe to keep (disabled) or remove
  - No active M1 users migrated from i3

✓ /etc/nixos/home-modules/desktop/i3wsr.nix
  - DISABLED (dynamic workspace naming for i3)
  - Superseded by Sway + i3bar
  - Safe to remove

✓ /etc/nixos/home-modules/desktop/i3bar.nix
  - DISABLED (i3bar with event-driven status)
  - Superseded by swaybar.nix
  - Safe to remove
```

### Home-Manager i3 Project Daemon (Superseded by System Service)
```
✓ /etc/nixos/home-modules/desktop/i3-project-daemon.nix
  - DISABLED in home-modules (home-manager version)
  - System service version is primary (configurations/m1.nix, configurations/hetzner-sway.nix)
  - Note: home-vpittamp.nix still imports this (line 21) - imports BUT disables it
  - Recommendation: Remove import and file entirely
```

---

## 7. Configuration Alignment Issues & Recommendations

### Issue 1: M1 Home-Manager Still Imports Old i3 Project Daemon
**Current State** (`home-vpittamp.nix` lines 20-22):
```nix
# Project management (works with both i3 and Sway)
./home-modules/desktop/i3-project-daemon.nix   # Feature 015: Event-driven daemon
```

**But it's disabled in the module itself** (`home-vpittamp.nix` lines 40-44):
```nix
services.i3ProjectEventListener = {
  enable = false;  # Disabled - using system service instead
};
```

**Recommendation**: Remove the import entirely since:
- System service is primary (configurations/m1.nix, configurations/hetzner-sway.nix)
- The module is explicitly disabled
- Hetzner-sway.nix doesn't import this at all

**Action**: Delete line 21 from `home-vpittamp.nix`

---

### Issue 2: Home-Manager Naming Inconsistency
**M1**: Uses `home-vpittamp.nix` at repository root
**Hetzner-Sway**: Uses `home-modules/hetzner-sway.nix`

**Current Alignment**:
- M1 imports a traditional base (base-home.nix) then Sway overrides
- Hetzner-sway imports a clean flat structure

**Options**:
1. **Recommended**: Keep as-is - M1 will eventually get a home-modules/m1.nix similar to hetzner-sway
2. Alternative: Rename home-vpittamp.nix to home-modules/m1.nix for consistency

---

### Issue 3: Keybinding Platform Differences Are Platform-Specific
**M1**: CapsLock for workspace mode (bindcode 66)
**Hetzner**: Control+0 for workspace mode

**Status**: ✓ Correct and intentional
- M1 has physical CapsLock available
- Hetzner Cloud VNC doesn't reliably transmit special keys
- Both use Feature 042 daemon IPC for workspace mode

---

## 8. Recommended Cleanup Actions

### Priority 1: Remove Old Backups (Safe)
```bash
rm /etc/nixos/configurations/hetzner-sway.nix.backup-20251029-143249
rm /etc/nixos/home-modules/desktop/sway.nix.backup-20251029-143249
rm /etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py.backup-before-037
rm /etc/nixos/home-modules/tools/i3pm-deno/src/commands/rules.ts.backup
```

### Priority 2: Remove Old i3 Configuration (Deprecated)
```bash
# After verifying no other files reference these:
rm /etc/nixos/home-modules/desktop/i3.nix
rm /etc/nixos/home-modules/desktop/i3wsr.nix
rm /etc/nixos/home-modules/desktop/i3bar.nix
rm /etc/nixos/home-modules/desktop/i3-project-daemon.nix
```

### Priority 3: Clean Home-Manager Imports
**File**: `/etc/nixos/home-vpittamp.nix`

Remove line 21:
```diff
- ./home-modules/desktop/i3-project-daemon.nix   # Feature 015: Event-driven daemon
```

Delete the entire block (lines 40-45):
```diff
- # Feature 015: i3 project event listener daemon
- # NOTE: Disabled in favor of system service (Feature 037 - cross-namespace /proc access)
- # System service configured in configurations/hetzner.nix: services.i3ProjectDaemon.enable
- services.i3ProjectEventListener = {
-   enable = false;  # Disabled - using system service instead
- };
```

### Priority 4: Optional - Align Home-Manager Naming
**Option A** (Recommended - future-proof):
Create `/etc/nixos/home-modules/m1.nix` with M1-specific imports
Update flake.nix to reference `./home-modules/m1.nix`
Delete `./home-vpittamp.nix`

**Option B** (Minimal change):
Keep `home-vpittamp.nix` as-is
Document in CLAUDE.md as M1-specific entry point

---

## 9. Configuration Verification Checklist

### ✓ Verified Alignments

- [x] Both platforms use Sway/Wayland (not mixed with i3/X11)
- [x] Both use Feature 047 for keybinding management
- [x] Both use Feature 042 for workspace mode navigation
- [x] Both use Feature 037 system daemon for project management
- [x] Both use sway-config-manager for dynamic configuration
- [x] Both use Walker as application launcher
- [x] Platform-specific differences are documented and intentional:
  - Display setup (physical vs headless)
  - Input devices (touchpad vs none)
  - Audio (local vs Tailscale)
  - Remote access (RustDesk vs WayVNC)
  - Workspace mode trigger (CapsLock vs Ctrl+0)

### Keybinding Differences

**No user-visible differences** - both use the same default keybindings from:
```
/etc/nixos/home-modules/desktop/sway-default-keybindings.toml
```

Platform-specific triggers:
- M1: CapsLock (bindcode 66) or Mod+; (fallback)
- Hetzner: Ctrl+0 (VNC-friendly)

Both compile to identical Sway commands via Feature 047 daemon.

---

## 10. Files That Can Now Be Removed (Summary)

**Safe to Delete**:
1. `hetzner-sway.nix.backup-20251029-143249` (backup from recent edit)
2. `sway.nix.backup-20251029-143249` (backup from recent edit)
3. `i3-project-event-daemon/daemon.py.backup-before-037` (superseded)
4. `i3pm-deno/src/commands/rules.ts.backup` (superseded)
5. `home-modules/desktop/i3.nix` (superseded by Sway)
6. `home-modules/desktop/i3wsr.nix` (superseded by Sway)
7. `home-modules/desktop/i3bar.nix` (superseded by swaybar)
8. `home-modules/desktop/i3-project-daemon.nix` (use system service instead)

**Should Simplify** (remove unused imports):
- Remove line 21 from `home-vpittamp.nix` (i3-project-daemon import)
- Remove lines 40-45 from `home-vpittamp.nix` (disabled service block)

---

## 11. Final Status

### Alignment Level: **EXCELLENT** ✓

Both M1 MacBook Pro and Hetzner Cloud configurations are:
- Using identical window manager (Sway/Wayland)
- Using identical keybinding management system (Feature 047)
- Using identical project management (Feature 037 system daemon)
- Using identical application launcher (Walker)
- Using identical workspace mode (Feature 042)

**Only platform-specific differences are intentional and well-documented**:
- Hardware/display configuration (physical vs headless)
- Input devices (touchpad vs none)
- Audio routing (local vs Tailscale)
- Remote access method (RustDesk vs WayVNC)

### Codebase Cleanliness: **GOOD** (can improve slightly)

Minor issues:
- Backup files from 2025-10-29 can be removed
- Old i3 configuration files are deprecated and can be removed
- M1 home-manager still imports the disabled i3 project daemon (clean up)

No critical alignment issues.

