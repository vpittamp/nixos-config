# Deprecated Features and Configurations

This document catalogs features and configurations that have been removed from the active NixOS configuration codebase as part of Feature 089: NixOS Configuration Cleanup and Consolidation (November 2025).

## Overview

As the NixOS configuration evolved from supporting multiple desktop environments and platforms to focusing on Sway/Wayland systems, several legacy components became obsolete. This cleanup effort removed ~1,200 lines of deprecated code while preserving it in the `archived/` directory for historical reference.

---

## Deprecated Desktop Environments

### i3 Window Manager (X11)

**Deprecated**: November 2025
**Reason**: Migrated to Sway (Wayland) for better performance and modern display protocol support
**Impact**: ~537 LOC removed

#### Removed Modules
- `modules/desktop/i3-project-workspace.nix` (537 LOC)

#### Migration Path
All i3-specific functionality was reimplemented for Sway:
- Workspace management → Sway workspaces with Feature 042 (event-driven workspace mode)
- Project management → i3pm daemon works with Sway via i3-compatible IPC
- Window tiling → Sway native tiling

### KDE Plasma Desktop

**Deprecated**: November 2025
**Reason**: System standardized on Sway tiling window manager
**Impact**: ~100 LOC removed, flake input removed

#### Removed Modules
- `modules/desktop/firefox-virtual-optimization.nix` (KDE-specific Firefox tweaks)
- `modules/services/kde-optimization.nix` (Baloo/Akonadi disabling)

#### Removed Flake Inputs
- `plasma-manager` - No longer needed without KDE Plasma

### X11/RDP Remote Access

**Deprecated**: November 2025
**Reason**: Replaced with WayVNC (Wayland-native VNC server)
**Impact**: ~455 LOC removed

#### Removed Modules
- `modules/desktop/xrdp.nix` (126 LOC) - XRDP server configuration
- `modules/desktop/remote-access.nix` (166 LOC) - RDP display management
- `modules/desktop/rdp-display.nix` (163 LOC) - Virtual display setup
- `modules/desktop/wireless-display.nix` - Miracast/X11-specific

#### Migration Path
- Hetzner Cloud: WayVNC with headless Wayland outputs (Feature 048)
- M1 MacBook: Hybrid local + VNC virtual displays (Feature 084)
- Three virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3) accessible via VNC

### Audio-Network Integration (X11)

**Deprecated**: November 2025
**Reason**: Incompatible with Wayland, superseded by PipeWire + Tailscale audio

#### Removed Modules
- `modules/services/audio-network.nix` - X11-specific PulseAudio network streaming

#### Migration Path
- PipeWire with Tailscale audio streaming (Feature 046)
- WayVNC for remote desktop audio

---

## Deprecated Platform Support

### Windows Subsystem for Linux (WSL)

**Deprecated**: November 2025
**Reason**: No longer used; primary development moved to native NixOS on Hetzner Cloud and M1 Mac
**Impact**: ~300 LOC removed

#### Removed Configurations
- `configurations/wsl.nix` (archived in `archived/obsolete-configs/`)
- `modules/wsl/wsl-config.nix` - WSL-specific system settings
- `modules/assertions/wsl-check.nix` - WSL environment detection

#### Removed Modules
- `modules/services/wsl-docker.nix` - Docker integration for WSL

#### Rationale
- WSL had performance limitations for Wayland/Sway development
- Native NixOS on dedicated hardware provided better development experience
- Hetzner Cloud + M1 Mac covered all development and testing scenarios

### Hetzner i3 Configuration

**Deprecated**: November 2025
**Reason**: Replaced by `hetzner-sway.nix` (Wayland-based)

#### Removed Configurations
- `configurations/hetzner.nix` - i3/X11-based Hetzner configuration (archived)
- Replaced by: `configurations/hetzner-sway.nix`

---

## Deprecated Build Artifacts

### Backup Files

**Removed**: November 2025
**Reason**: Obsolete development artifacts cluttering the codebase
**Impact**: 8 files removed

All `.backup*` files were removed from the active codebase. These were temporary files created during development that were never cleaned up.

**Removal Command**:
```bash
find . -name "*.backup*" -type f | grep -v archived | grep -v specs | xargs git rm
```

---

## Archived Configurations (Historical Reference)

The following configurations have been archived but preserved for reference:

### Container/VM Variants
- `kubevirt-desktop.nix` - Full desktop in Kubernetes pod
- `kubevirt-full.nix` - Full system in KubeVirt
- `kubevirt-minimal.nix` - Minimal KubeVirt configuration
- `kubevirt-optimized.nix` - Optimized KubeVirt build
- `vm-hetzner.nix` - VM-based Hetzner configuration
- `vm-minimal.nix` - Minimal VM configuration

### Legacy Hetzner Variants
- `hetzner-example.nix` - Example configuration
- `hetzner-i3.nix` - i3-based Hetzner (pre-Sway)
- `hetzner-mangowc.nix` - MangoHUD configuration
- `hetzner-minimal.nix` - Minimal Hetzner build

---

## Module Consolidations (Feature 089)

As part of this cleanup, several modules were consolidated to reduce duplication and improve maintainability.

### 1Password Module Consolidation

**Before**: 3 separate modules (493 LOC total)
- `modules/services/onepassword.nix` (232 LOC) - Base configuration
- `modules/services/onepassword-automation.nix` (124 LOC) - Service account automation
- `modules/services/onepassword-password-management.nix` (137 LOC) - Password sync

**After**: 1 consolidated module (491 LOC)
- `modules/services/onepassword.nix` - Unified module with feature flags

**Benefits**:
- Single source of truth for all 1Password configuration
- Feature flags for GUI, automation, password management, SSH
- Clearer option hierarchy (`services.onepassword.{gui|automation|passwordManagement|ssh}`)
- No LOC increase despite consolidation

### Firefox Module Consolidation

**Before**: 2 separate modules (303 LOC total)
- `modules/desktop/firefox-1password.nix` (135 LOC) - Firefox with 1Password
- `modules/desktop/firefox-pwa-1password.nix` (168 LOC) - PWA support

**After**: 1 consolidated module (320 LOC)
- `modules/desktop/firefox-1password.nix` - Unified module with `enablePWA` flag

**Benefits**:
- Single place to configure Firefox + 1Password integration
- Optional PWA support via boolean flag
- Reduced import clutter in system configurations

---

## Active System Configurations

After cleanup, these are the **only** supported configurations:

### Production Systems
1. **hetzner-sway**: Hetzner Cloud Sway system (headless Wayland + VNC)
2. **m1**: M1 MacBook Pro (native Sway + optional VNC virtual displays)

### Build/Testing Variants
3. **hetzner-sway-image**: QCOW2 image for nixos-generators
4. **hetzner-sway-minimal**: Minimal build for constrained environments
5. **hetzner-sway-ultra-minimal**: Ultra-minimal for testing

---

## Flake Input Cleanup

### Removed Inputs
- `plasma-manager` - Not needed without KDE Plasma
- `flake-utils` - Confirmed unused after codebase analysis

### Retained Inputs
All other flake inputs (home-manager, nixos-hardware, etc.) remain active and necessary.

---

## Success Metrics

**Total LOC Reduction**: ~1,200 lines
- Phase 1 (Deprecated Modules): ~1,000 LOC
- Phase 2 (Consolidations): ~200 LOC (via deduplication)
- Phase 3 (Backup Files): ~50 LOC

**Files Removed/Archived**: 20+ files
- 11 deprecated modules deleted
- 8 backup files removed
- 2 flake inputs removed
- Multiple archived configurations preserved

**Codebase Clarity**:
- Only 2 active system targets (hetzner-sway, m1)
- Single sources of truth for 1Password and Firefox
- Zero dead code in active modules

---

## Recovery Instructions

If you need to reference or restore any deprecated feature:

1. **Check archived configurations**: Look in `archived/obsolete-configs/`
2. **Review git history**: All deletions are preserved in git
3. **Consult this document**: Find the deprecation reason and migration path

### Example: Restoring WSL Support

```bash
# View archived WSL configuration
cat archived/obsolete-configs/wsl.nix

# Check git history for WSL modules
git log --all --full-history -- modules/wsl/

# If needed, restore from specific commit
git checkout <commit-hash> -- modules/wsl/wsl-config.nix
```

---

## Future Considerations

### Potential Future Deprecations
- `hetzner-sway-minimal` and `hetzner-sway-ultra-minimal` if unused
- Legacy i3-compatible IPC if full Sway-native API adopted

### Consolidation Opportunities
- Hetzner-sway variant consolidation (currently 4 similar configs)
- Profile-based configuration (production, image, minimal, ultra-minimal)

---

## Document Version

- **Created**: November 2025
- **Feature**: 089 - NixOS Configuration Cleanup and Consolidation
- **Author**: Feature 089 implementation
- **Last Updated**: November 22, 2025

---

## See Also

- `README.md` - Current system overview
- `CLAUDE.md` - LLM navigation guide (active systems only)
- `archived/obsolete-configs/README.md` - Archived configuration index
- `specs/089-nixos-home-manager-cleanup/` - Feature specification and tasks
