# Contracts: Enable Advanced Hardware Features

**Feature**: 115-enable-advanced-hardware-features
**Date**: 2025-12-13

## Not Applicable

This feature involves NixOS configuration changes rather than API development. Therefore, traditional API contracts (OpenAPI, GraphQL schemas) are not applicable.

## Equivalent Contracts

For NixOS configurations, the equivalent of "contracts" are:

### 1. NixOS Option Types

The NixOS module system enforces type contracts via option declarations:

```nix
# Example from modules/services/bare-metal.nix
options.services.bare-metal = {
  enable = mkEnableOption "bare-metal optimizations";

  enableVirtualization = mkOption {
    type = types.bool;
    default = true;
    description = "Enable KVM virtualization";
  };
};
```

### 2. Build-Time Validation

Configuration contracts are validated at build time:

```bash
# Dry-build validates all configuration options
nixos-rebuild dry-build --flake .#thinkpad
```

### 3. Hardware Detection

Runtime hardware availability is detected via conditional logic:

```nix
# Conditional package installation based on hardware
environment.systemPackages = lib.optionals (config.hardware.nvidia.enable) [
  pkgs.nvtopPackages.nvidia
];
```

## Verification Commands

Instead of API contracts, this feature provides verification commands to validate hardware functionality:

| Feature | Verification Command | Expected Output |
|---------|---------------------|-----------------|
| VA-API | `vainfo` | Lists decoder/encoder profiles |
| NVIDIA | `nvidia-smi` | Shows GPU status |
| Bluetooth | `bluetoothctl devices` | Lists paired devices |
| Webcam | `v4l2-ctl --list-devices` | Shows /dev/videoN |
| Audio | `pw-top` | Shows audio streams |

See `quickstart.md` for complete verification procedures.
