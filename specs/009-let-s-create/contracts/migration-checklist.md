# Contract: Migration Validation Checklist

**Feature**: 009-let-s-create
**Type**: Validation Contract
**Version**: 1.0.0
**Last Updated**: 2025-10-17

## Purpose

This checklist provides step-by-step validation for the KDE Plasma to i3wm migration. Each platform must pass all applicable checks before marking the migration as complete.

## Pre-Migration Validation

### ✅ Prerequisites
- [ ] Git repository is clean (no uncommitted changes) or changes are backed up
- [ ] Current system configuration builds successfully
- [ ] All background bash shells from previous testing are terminated
- [ ] User data backed up (optional, NixOS enables rollback)

### ✅ Research Complete
- [ ] research.md created with all technology decisions documented
- [ ] data-model.md defines all configuration entities
- [ ] contracts/ directory contains module and platform contracts
- [ ] No "NEEDS CLARIFICATION" items remain in Technical Context

---

## Platform Migration Checklist

Complete this checklist for each platform being migrated.

### Platform: _____________ (hetzner / m1 / container)

## Phase 1: Configuration Refactoring

### ✅ Remove Obsolete Imports
- [ ] Remove `../modules/desktop/kde-plasma.nix` from imports
- [ ] Remove `../modules/desktop/kde-plasma-vm.nix` from imports (if present)
- [ ] Remove `../modules/desktop/mangowc.nix` from imports (if present)
- [ ] Remove `../modules/desktop/wayland-remote-access.nix` from imports (if M1)
- [ ] Remove `inputs.plasma-manager.homeModules.plasma-manager` from home-manager imports

### ✅ Add New Imports
- [ ] Add `./hetzner-i3.nix` to imports list (or confirm already present for hetzner)
- [ ] Verify hardware module still imported (../hardware/<platform>.nix)
- [ ] Verify base.nix or parent config imported

### ✅ Remove Duplicate Configuration
- [ ] Compare current config to hetzner-i3.nix
- [ ] Remove duplicated package lists
- [ ] Remove duplicated service configuration
- [ ] Remove duplicated environment variables
- [ ] Keep only platform-specific settings

### ✅ Document Overrides
- [ ] Every `lib.mkForce` has a comment explaining why it's mandatory
- [ ] Platform-specific overrides are minimal (<20% of total config)
- [ ] Hostname is set with `lib.mkForce` (platform identity)

## Phase 2: Build Validation

### ✅ Dry Build Test
```bash
nixos-rebuild dry-build --flake .#<platform>
# For M1: nixos-rebuild dry-build --flake .#m1 --impure
```
- [ ] Build completes without errors
- [ ] No deprecation warnings related to KDE/Plasma
- [ ] Build time < 5 minutes

### ✅ Closure Verification
```bash
# Check for KDE/Plasma packages in closure
nix-store -q --tree $(readlink ./result) | grep -i kde
nix-store -q --tree $(readlink ./result) | grep -i plasma
```
- [ ] No KDE/Plasma packages in closure
- [ ] i3, rofi, alacritty, clipcat present in closure

### ✅ Configuration Size
```bash
# Count unique lines in platform config (excluding comments/imports)
grep -v "^[[:space:]]*#" configurations/<platform>.nix | grep -v "^[[:space:]]*$" | grep -v "import" | wc -l
```
- [ ] Platform config < 300 lines (target: ~150-200 for derived configs)
- [ ] Estimated code reuse > 80% (compared to hetzner-i3.nix baseline)

## Phase 3: Deployment and Boot Testing

### ✅ Apply Configuration
```bash
sudo nixos-rebuild switch --flake .#<platform>
# For M1: sudo nixos-rebuild switch --flake .#m1 --impure
```
- [ ] Rebuild completes successfully
- [ ] System switches to new generation
- [ ] No critical errors in rebuild output

### ✅ Reboot and Boot Validation
```bash
sudo reboot
```
- [ ] System boots without errors
- [ ] Boot time to login prompt < 30 seconds
- [ ] No systemd service failures
- [ ] X11 server starts (for GUI platforms)
- [ ] i3wm starts and displays (for GUI platforms)

### ✅ Display and Graphics
- [ ] Display resolution correct
- [ ] HiDPI scaling correct (M1: 1.75x or 180 DPI)
- [ ] Fonts render clearly
- [ ] Cursor size appropriate
- [ ] No screen tearing or graphics artifacts

## Phase 4: Functional Validation

### ✅ Core Window Manager Functions
- [ ] `Win+Return` opens terminal (alacritty)
- [ ] `Win+d` opens application launcher (rofi)
- [ ] `Win+v` opens clipboard history (clipcat)
- [ ] `Ctrl+1-9` switches workspaces
- [ ] `Win+Shift+1-9` moves windows to workspaces
- [ ] `Win+f` toggles fullscreen
- [ ] `Win+h` splits horizontal
- [ ] `Win+Shift+|` splits vertical
- [ ] `Win+Shift+Space` toggles floating
- [ ] Window focus with arrow keys works
- [ ] Window movement with Shift+arrows works

### ✅ Applications and Tools
- [ ] Terminal (alacritty) launches and renders correctly
- [ ] Firefox launches and displays web pages
- [ ] VS Code launches (if installed)
- [ ] 1Password desktop app launches and unlocks (GUI platforms)
- [ ] 1Password CLI works: `op signin` (all platforms)
- [ ] SSH agent works with 1Password: `SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l`

### ✅ Progressive Web Apps (PWAs)
```bash
firefoxpwa profile list
```
- [ ] PWAs are listed
- [ ] PWAs launch from command line: `firefoxpwa site launch <id>`
- [ ] PWA windows appear with correct class (FFPWA-<id>)
- [ ] i3wsr renames workspaces with PWA icons
- [ ] PWAs work with 1Password browser extension

### ✅ Clipboard Integration
```bash
# Test clipboard workflow
echo "test clipboard entry" | xclip -selection clipboard
clipcatctl list
```
- [ ] Clipboard content captured
- [ ] `Win+v` shows clipboard history in rofi
- [ ] Selecting entry pastes correctly
- [ ] `Win+Shift+v` clears clipboard history

### ✅ Workspace Management (i3wsr)
```bash
systemctl --user status i3wsr
```
- [ ] i3wsr service running
- [ ] Workspaces rename dynamically based on window class
- [ ] Icons appear for applications (Firefox: , VS Code: , Terminal: )
- [ ] PWA icons appear in workspace names

### ✅ Remote Desktop (Hetzner Only)
```bash
systemctl status xrdp
```
- [ ] xrdp service running
- [ ] RDP connection successful from remote client
- [ ] Multiple concurrent sessions work (test 2-3 connections)
- [ ] Each session has independent i3 desktop
- [ ] Clipboard works across RDP
- [ ] Sessions persist across disconnection

## Phase 5: Performance Validation

### ✅ Resource Usage
```bash
# Measure memory usage after login (no apps running)
free -h

# Check idle CPU usage
top -bn1 | head -20
```
- [ ] Idle memory usage reduced by 200MB vs baseline (KDE Plasma)
- [ ] Memory usage < 500MB at idle (target: 300-400MB)
- [ ] CPU idle < 5% (no runaway processes)

### ✅ Boot Performance
```bash
systemd-analyze
systemd-analyze blame | head -20
```
- [ ] Total boot time < 30 seconds
- [ ] i3wm startup < 5 seconds
- [ ] No services taking > 10 seconds to start

## Phase 6: Documentation Validation

### ✅ Configuration Documentation
- [ ] Platform config has header comment explaining purpose
- [ ] All `lib.mkForce` usage documented with comments
- [ ] Platform-specific settings have explanatory comments
- [ ] Imports list is documented

### ✅ README and CLAUDE.md Updates
- [ ] CLAUDE.md updated with i3wm references (remove KDE Plasma)
- [ ] Quick start commands reference i3wm desktop
- [ ] PWA commands documented in i3wm context
- [ ] Platform-specific notes updated (M1 DPI, remote desktop on Hetzner)

### ✅ Architecture Documentation
- [ ] docs/ARCHITECTURE.md updated to reflect hetzner-i3.nix as primary reference
- [ ] Configuration hierarchy diagram updated
- [ ] Module list updated (remove KDE modules, keep i3wm)

---

## Platform-Specific Checklists

### M1 Platform Additional Checks

#### ✅ M1 Hardware and Display
- [ ] WiFi working (BCM4378 with brcmfmac kernel param)
- [ ] Touchpad working with natural scrolling
- [ ] Retina display at correct DPI (180)
- [ ] External display support (if applicable)
- [ ] Asahi firmware loaded from /boot/asahi

#### ✅ M1 X11 Migration
- [ ] X11 server running (not Wayland)
- [ ] `$DISPLAY` environment variable set
- [ ] `$WAYLAND_DISPLAY` not set
- [ ] XWayland applications render correctly
- [ ] No Wayland session errors in logs

#### ✅ M1 Services
- [ ] RustDesk remote access working (if enabled)
- [ ] Tailscale VPN connected
- [ ] Home Assistant accessible (if running)
- [ ] Speech-to-text service working (if enabled)

### Container Platform Additional Checks

#### ✅ Container Configuration
- [ ] i3wm module disabled
- [ ] X11 server disabled
- [ ] Package profile set to "minimal" or "essential"
- [ ] Container image size < 600MB (development) or < 100MB (minimal)

#### ✅ Container Build
```bash
nix build .#container-minimal
docker load < result
docker run -it nixos-container:minimal
```
- [ ] Container builds successfully
- [ ] Container image loads into Docker
- [ ] Container starts and runs bash shell
- [ ] Essential tools available (git, vim, tmux)

---

## Post-Migration Cleanup Checklist

### ✅ Remove Obsolete Modules
- [ ] Delete `modules/desktop/kde-plasma.nix`
- [ ] Delete `modules/desktop/kde-plasma-vm.nix`
- [ ] Delete `modules/desktop/mangowc.nix`
- [ ] Delete `modules/desktop/wayland-remote-access.nix`

### ✅ Remove Obsolete Configurations
- [ ] Delete `configurations/hetzner.nix` (old KDE config)
- [ ] Delete `configurations/hetzner-mangowc.nix`
- [ ] Delete `configurations/wsl.nix` (if obsolete)
- [ ] Evaluate and remove `configurations/kubevirt-*.nix` if not in use
- [ ] Evaluate and remove `configurations/vm-*.nix` if experimental only

### ✅ Remove Obsolete Documentation
- [ ] Delete `docs/PLASMA_CONFIG_STRATEGY.md`
- [ ] Delete `docs/PLASMA_MANAGER.md`
- [ ] Delete `docs/IPHONE_KDECONNECT_GUIDE.md`

### ✅ Remove Obsolete Home Modules
- [ ] Delete `home-modules/desktop/plasma-config.nix`
- [ ] Delete `home-modules/desktop/plasma-sync.nix`
- [ ] Delete `home-modules/desktop/plasma-snapshot-analysis.nix`
- [ ] Delete `home-modules/desktop/touchpad-gestures.nix` (Wayland-specific)
- [ ] Delete `home-modules/desktop/activity-aware-apps-native.nix` (if KDE-specific)

### ✅ Update Flake Configuration
- [ ] Remove plasma-manager input from flake.nix (if no longer used)
- [ ] Remove mangowc input from flake.nix
- [ ] Update flake.nix comments to reference i3wm as standard desktop
- [ ] Update nixosConfigurations entries (remove hetzner-kde, etc.)

---

## Success Criteria Validation

Verify all success criteria from spec.md are met:

### ✅ Measurable Outcomes
- [ ] SC-001: Configuration file count reduced by 30% (17→12 or fewer)
- [ ] SC-002: Documentation file count reduced by 15% (45→38 or fewer)
- [ ] SC-003: All configs build without errors in < 5 minutes
- [ ] SC-004: Boot time to usable i3wm desktop < 30 seconds (Hetzner)
- [ ] SC-005: Memory usage reduced by 200MB vs KDE Plasma baseline
- [ ] SC-006: All critical integrations functional (1Password, PWAs, clipboard, terminal)
- [ ] SC-007: M1 X11 with functional HiDPI scaling
- [ ] SC-008: No KDE/Plasma packages in nix-store for any config
- [ ] SC-009: 80%+ code reuse from hetzner-i3.nix across platforms
- [ ] SC-010: Developer can rebuild any config from scratch in < 10 minutes using updated docs

---

## Rollback Procedure

If migration fails validation, roll back to previous configuration:

```bash
# Option 1: Switch to previous generation
sudo nixos-rebuild switch --rollback

# Option 2: Select specific generation
sudo nixos-rebuild list-generations
sudo nixos-rebuild switch --switch-generation <number>

# Option 3: Revert git commits
git log --oneline -10
git revert <commit-hash>
sudo nixos-rebuild switch --flake .#<platform>
```

---

## Sign-Off

### Platform Migration Complete: _____________ (hetzner / m1 / container)

**Date Completed**: _____________
**Tested By**: _____________
**Validation Result**: ☐ Pass / ☐ Fail / ☐ Pass with known issues

**Known Issues**:
-
-

**Follow-Up Tasks**:
-
-

---

## See Also

- `contracts/i3wm-module.md` - i3wm module interface specification
- `contracts/platform-config.md` - Platform configuration extension pattern
- `spec.md` - Feature specification with success criteria
- `research.md` - Technology decisions and best practices
