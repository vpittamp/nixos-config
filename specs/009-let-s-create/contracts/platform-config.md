# Contract: Platform Configuration Extension

**Pattern**: Configuration Inheritance
**Primary Reference**: `configurations/hetzner-i3.nix`
**Version**: 1.0.0
**Status**: Active
**Last Updated**: 2025-10-17

## Purpose

This contract defines how platform configurations extend the primary reference configuration (hetzner-i3.nix) to achieve 80%+ code reuse while supporting platform-specific customization.

## Inheritance Pattern

### Standard Structure

```nix
# configurations/<platform>.nix
{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ./hetzner-i3.nix  # PRIMARY REFERENCE (required)
    # Platform-specific modules
    ../hardware/<platform>.nix  # Hardware configuration
    # Platform-specific inputs (e.g., nixos-apple-silicon for M1)
  ];

  # Platform-specific overrides (minimal, <20% of configuration)
  networking.hostName = lib.mkForce "<platform-hostname>";

  # Hardware-specific settings
  # Use lib.mkForce for mandatory overrides
  # Use lib.mkDefault for overrideable defaults
  # Document every lib.mkForce with rationale comment

  # Platform-specific packages (additions only, not replacements)
  environment.systemPackages = with pkgs; [
    # Additional platform-specific tools
  ];
}
```

## Override Priority Rules

### When to Use `lib.mkDefault`
- Overrideable defaults that child configs may override
- Hardware settings with platform-specific optimizations
- Optional features that may vary by platform

**Example**:
```nix
powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";  # M1 may override
services.xserver.dpi = lib.mkDefault 96;  # M1 overrides for HiDPI
```

### When to Use `lib.mkForce`
- Mandatory platform-specific settings that must not be overridden
- Display server choice (X11 vs Wayland, though now standardized on X11)
- Hardware-dependent configuration (firmware paths, kernel modules)
- Platform identity (hostname)

**Example**:
```nix
networking.hostName = lib.mkForce "nixos-m1";  # Mandatory platform identity
services.xserver.dpi = lib.mkForce 180;  # Mandatory for M1 Retina display
services.xrdp-i3.enable = lib.mkForce false;  # Mandatory: no remote desktop on laptop

# ALWAYS document lib.mkForce usage
# Rationale: M1 laptop doesn't need remote desktop; primary use case is local GUI
```

### When to Use Normal Assignment
- New options not defined in parent config
- Platform-specific additions (not overrides)
- Hardware-specific kernel parameters

**Example**:
```nix
boot.kernelParams = [ "brcmfmac.feature_disable=0x82000" ];  # M1 WiFi fix
swapDevices = [ { device = "/var/lib/swapfile"; size = 8192; } ];  # M1 swap
```

## Platform-Specific Customization Points

### Required Overrides (All Platforms)
1. `networking.hostName` - Unique hostname for each platform
2. `system.stateVersion` - NixOS version for initial install (may differ per platform)

### Common Customization Points

#### M1 Platform
- **DPI Settings**: Override for Retina display (180 DPI)
- **Firmware Paths**: Asahi firmware location (impure, /boot/asahi)
- **WiFi Configuration**: BCM4378 workarounds
- **Swap Configuration**: 8GB swap file for memory pressure relief
- **Remote Desktop**: Disable xrdp (laptop use case)

#### Container Platform
- **GUI Disable**: Disable i3wm and X server entirely
- **Package Profile**: Use "minimal" or "essential" instead of "development"
- **Service Reduction**: Disable non-essential services

## Shared Configuration (From hetzner-i3.nix)

The following configuration is shared across all platforms (DO NOT DUPLICATE):

### Desktop Environment
- i3 window manager configuration
- X11 server base settings
- Essential desktop packages (rofi, alacritty, firefox)
- Clipboard manager (clipcat)

### Services
- Development tools (modules/services/development.nix)
- Networking services (modules/services/networking.nix, Tailscale)
- 1Password integration (modules/services/onepassword.nix)

### User Environment
- Home-manager integration
- User package lists
- Shell configuration (bash, starship)
- Terminal configuration (tmux, alacritty)

### Core Functionality
- i3 keybindings (see i3wm-module.md contract)
- PWA support (firefoxpwa)
- Workspace management (i3wsr via home-manager)

## Validation Requirements

### Build-Time Validation
```bash
# Each platform must build successfully
nixos-rebuild dry-build --flake .#hetzner
nixos-rebuild dry-build --flake .#m1 --impure  # --impure for firmware
nixos-rebuild dry-build --flake .#container
```

### Code Reuse Measurement
```bash
# Estimate: Count lines unique to platform vs total lines
# Target: <20% unique lines per platform (<< 80% shared)

# Hetzner-i3 total lines
wc -l configurations/hetzner-i3.nix

# M1 unique lines (excluding imports)
grep -v "import" configurations/m1.nix | wc -l
```

### Integration Validation
- Platform configuration imports PRIMARY reference
- All critical integrations work (1Password, PWAs, clipboard, terminal)
- No configuration duplication across platforms
- Platform overrides are documented

## Anti-Patterns (DO NOT DO)

### ❌ Duplicating Desktop Configuration
```nix
# BAD: Duplicating i3 config in m1.nix
services.i3wm = {
  enable = true;
  extraPackages = [ ... ];  # Already defined in hetzner-i3.nix
};
```

### ❌ Overriding Without Justification
```nix
# BAD: Overriding without comment explaining necessity
services.xserver.dpi = lib.mkForce 180;  # No explanation why
```

### ❌ Excessive Overrides
```nix
# BAD: Too many overrides indicate poor abstraction
# If >50% of parent config is overridden, reconsider inheritance approach
```

### ❌ Importing Multiple References
```nix
# BAD: Importing multiple reference configurations
imports = [
  ./hetzner-i3.nix
  ./container.nix  # NO! Each platform should import ONE reference
];
```

## Migration Checklist (Per Platform)

For each platform being migrated:

- [ ] Remove old desktop module imports (KDE Plasma, Wayland)
- [ ] Add import of hetzner-i3.nix
- [ ] Remove duplicated configuration (compare to hetzner-i3.nix)
- [ ] Keep only platform-specific overrides
- [ ] Document all `lib.mkForce` usage with comments
- [ ] Test build: `nixos-rebuild dry-build --flake .#<platform>`
- [ ] Verify no KDE packages in closure: `nix-store -q --tree result | grep -i kde`
- [ ] Test boot to i3wm desktop (<30 seconds)
- [ ] Validate all critical integrations work

## Platform Compatibility Matrix

| Platform | Inherits Primary | Status | Notes |
|----------|------------------|--------|-------|
| hetzner | N/A (IS primary) | ✅ Active | Reference configuration |
| m1 | ✅ Yes | 🔄 Needs Refactor | Currently imports base.nix + KDE; needs hetzner-i3.nix import |
| container | ✅ Yes | 🔄 Needs Refactor | Should import hetzner-i3.nix + disable GUI |

## Version History

- **1.0.0** (2025-10-17): Initial contract for configuration inheritance pattern
  - Defined inheritance structure and override rules
  - Documented customization points per platform
  - Specified anti-patterns and validation requirements

## See Also

- `contracts/i3wm-module.md` - i3wm module interface contract
- `contracts/migration-checklist.md` - Migration validation checklist
- `research.md` - Configuration inheritance best practices
