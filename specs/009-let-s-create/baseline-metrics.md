# Baseline Metrics - Before Migration

**Date**: 2025-10-17
**Branch**: 009-let-s-create
**Commit**: 7a1e86e

## Configuration Files Count

Total configuration files in configurations/:
15

Files:
configurations/base.nix
configurations/container.nix
configurations/hetzner-example.nix
configurations/hetzner-i3.nix
configurations/hetzner-mangowc.nix
configurations/hetzner-minimal.nix
configurations/hetzner.nix
configurations/kubevirt-desktop.nix
configurations/kubevirt-full.nix
configurations/kubevirt-minimal.nix
configurations/kubevirt-optimized.nix
configurations/m1.nix
configurations/vm-hetzner.nix
configurations/vm-minimal.nix
configurations/wsl.nix

## Documentation Files Count

Total documentation files in docs/:
45

## Desktop Module Files

Total desktop modules in modules/desktop/:
13

Files:
modules/desktop/firefox-1password.nix
modules/desktop/firefox-pwa-1password.nix
modules/desktop/firefox-virtual-optimization.nix
modules/desktop/i3wm.nix
modules/desktop/kde-plasma.nix
modules/desktop/kde-plasma-vm.nix
modules/desktop/mangowc.nix
modules/desktop/rdp-display.nix
modules/desktop/remote-access.nix
modules/desktop/wayland-remote-access.nix
modules/desktop/wireless-display.nix
modules/desktop/xrdp.nix
modules/desktop/xrdp-with-sound.nix

## Platform Build Status

- Hetzner (hetzner-i3): ✅ BUILDS
- M1: ⚠️ BUILD ERROR - Missing tailscaleId in panels.nix  
- Container (minimal): ✅ BUILDS

## Build Issue Detected

**M1 Configuration Build Error**:
```
error: attribute 'tailscaleId' missing
at /nix/store/.../home-modules/desktop/project-activities/panels.nix:53:170
```

**Root Cause**: Missing PWA ID definition for Tailscale
**Impact**: M1 configuration cannot build until fixed
**Resolution**: Will be addressed during migration (or fix before migration)

## Target Metrics (Success Criteria)

- Configuration files: ≤12 (30% reduction from current count)
- Documentation files: ≤38 (15% reduction from current count)
- Boot time: <30s to usable i3wm desktop
- Memory usage: 200MB reduction vs KDE Plasma baseline
- Code reuse: ≥80% shared via hetzner-i3.nix inheritance

## Notes

- Baseline established on branch 009-let-s-create
- Hetzner configuration is the working reference (hetzner-i3)
- Container configuration is functional
- M1 configuration has pre-existing build issue to be resolved
