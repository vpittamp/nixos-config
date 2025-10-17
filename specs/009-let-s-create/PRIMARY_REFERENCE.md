# Primary Reference Configuration: hetzner-i3.nix

**Date**: 2025-10-17
**Branch**: 009-let-s-create
**Status**: ✅ VERIFIED AND FUNCTIONAL

## Overview

The `configurations/hetzner-i3.nix` configuration is the **PRIMARY REFERENCE** implementation for this NixOS system. All other platform-specific configurations (M1, container) should derive from and inherit its patterns.

## Why hetzner-i3.nix is the Primary Reference

1. **Complete Feature Set**: Full desktop environment with all integrations
2. **Production Tested**: Currently deployed and actively used
3. **All Integrations Working**:
   - ✅ i3wm tiling window manager
   - ✅ XRDP remote desktop (multi-session X11)
   - ✅ 1Password CLI and desktop app
   - ✅ Firefox PWA support
   - ✅ Clipcat clipboard history
   - ✅ PulseAudio with XRDP audio redirection
   - ✅ Tailscale VPN
   - ✅ Development tools (Docker, languages)

4. **Architecture**: X11-based stack (i3wm + xrdp)
   - Chosen for mature RDP multi-session support
   - Stable clipboard management across RDP sessions
   - Proven compatibility with all tools

## Configuration Structure

```nix
hetzner-i3.nix
├── Base: ./base.nix
├── Hardware: ../disk-config.nix
├── Services:
│   ├── modules/services/development.nix
│   ├── modules/services/networking.nix
│   ├── modules/services/onepassword.nix
│   └── modules/services/onepassword-*.nix
└── Desktop:
    ├── modules/desktop/i3wm.nix
    └── modules/desktop/xrdp.nix
```

## Module Interfaces

### i3wm.nix
- **Option**: `services.i3wm.enable`
- **Package Override**: `services.i3wm.package`
- **Extra Packages**: `services.i3wm.extraPackages`
- **Generates**: `/etc/i3/config`, `/etc/i3status.conf`

### xrdp.nix
- **Option**: `services.xrdp-i3.enable`
- **Port**: `services.xrdp-i3.port` (default: 3389)
- **Firewall**: `services.xrdp-i3.openFirewall`
- **WM**: `services.xrdp-i3.defaultWindowManager`

## Critical Integration Points

### 1Password
- Service: `services.onepassword-automation.enable`
- User: `vpittamp`
- Token: `op://Employee/...`

### Audio (PulseAudio)
```nix
# IMPORTANT: Must disable PipeWire for XRDP audio
services.pipewire.enable = lib.mkForce false;
hardware.pulseaudio.enable = true;
```

### Clipboard (Clipcat)
- i3 keybinding: `Super+v` for clipboard history
- Service: Runs in user session
- Integration: Works with tmux, X11 clipboard

### PWAs (Firefox)
- Tool: `firefoxpwa` CLI
- Home-manager: `home-modules/tools/firefox-pwas-declarative.nix`
- Commands: `pwa-install-all`, `pwa-update-panels`

## Verification Status

All components verified on 2025-10-17:
- ✅ Configuration builds without errors
- ✅ i3 config files generate correctly
- ✅ XRDP service active
- ✅ PulseAudio running
- ✅ 1Password CLI installed and functional
- ✅ Firefox PWA tools available
- ✅ Clipcat integration configured

## Migration Pattern

Other platforms should follow this pattern:

```nix
# configurations/platform.nix
{
  imports = [
    ./hetzner-i3.nix  # Import PRIMARY REFERENCE
    ./platform-hardware.nix
  ];
  
  # Override only platform-specific settings
  networking.hostName = lib.mkForce "platform-name";
  
  # Disable features not needed on this platform
  services.xrdp-i3.enable = lib.mkForce false;  # Example for local desktop
}
```

## Success Criteria Met

From baseline-metrics.md targets:
- ✅ Boot time: <30s to usable desktop
- ✅ Memory: 200MB+ reduction vs KDE Plasma
- ✅ All integrations preserved
- ✅ Multi-session RDP working
- ✅ Code reuse: 80%+ via module composition

## References

- Configuration: `/etc/nixos/configurations/hetzner-i3.nix`
- i3 Module: `/etc/nixos/modules/desktop/i3wm.nix`
- XRDP Module: `/etc/nixos/modules/desktop/xrdp.nix`
- Spec: `/etc/nixos/specs/009-let-s-create/spec.md`
- Plan: `/etc/nixos/specs/009-let-s-create/plan.md`

---

**Last Updated**: 2025-10-17
**Verified By**: Phase 2 Foundational Tasks (T004-T008)
