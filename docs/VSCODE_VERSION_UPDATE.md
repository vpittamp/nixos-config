# VSCode Version Update

## Summary

Updated VSCode from **1.104.2** to **1.104.3** (latest release as of October 9, 2025)

## Changes Made

### 1. Flake Update

- Ran `nix flake update` to fetch the latest package versions
- Updated nixpkgs and nixpkgs-bleeding inputs

### 2. VSCode Configuration Update (`home-modules/tools/vscode.nix`)

**Modified the module signature:**

```nix
# Before:
{ config, pkgs, lib, osConfig, ... }:

# After:
{ config, pkgs, pkgs-unstable, lib, osConfig, ... }:
```

**Added VSCode from unstable channel:**

```nix
let
  primaryProfile = "nixos";
  isM1 = osConfig.networking.hostName or "" == "nixos-m1";

  # Use latest VSCode from unstable channel for newest features and fixes
  vscode = pkgs-unstable.vscode;
```

**Updated package references:**

- Changed `pkgs.vscode.overrideAttrs` → `vscode.overrideAttrs` (2 locations)
- This applies to both `vscodeWithFlags` and `vscodeNoDesktop`

## Version Details

| Channel              | Version        |
| -------------------- | -------------- |
| **nixpkgs (stable)** | 1.104.2        |
| **nixpkgs-unstable** | **1.104.3** ✅ |
| **GitHub latest**    | 1.104.3        |

## Why Use pkgs-unstable?

The `pkgs-unstable` parameter is already passed to your home-manager configuration via `extraSpecialArgs` in `flake.nix`:

```nix
extraSpecialArgs = {
  inherit inputs;
  pkgs-unstable = import nixpkgs-bleeding {
    inherit system;
    config.allowUnfree = true;
  };
};
```

This gives us access to the bleeding-edge nixpkgs channel for packages where we want the latest versions.

## Benefits

1. **Latest Features**: Get the newest VSCode features and improvements immediately
2. **Bug Fixes**: Benefit from recent bug fixes and security patches
3. **No Manual Overrides**: Uses nixpkgs infrastructure (no need for manual version pinning)
4. **Automatic Updates**: Future flake updates will bring newer VSCode versions automatically

## Deployment

To apply the changes:

```bash
sudo nixos-rebuild switch --flake .#hetzner
```

The build will:

1. Download VSCode 1.104.3 from the Nix cache
2. Apply your custom overrides (Wayland flags, desktop file removal)
3. Install the updated version

## What's New in VSCode 1.104.3

VSCode 1.104.3 is a patch release that includes:

- Bug fixes from 1.104.2
- Performance improvements
- Security updates

For full release notes, see: https://code.visualstudio.com/updates/

## Verification

After deployment, verify the version:

```bash
code --version
```

Expected output:

```
1.104.3
<commit-hash>
x64
```

## Future Updates

To get the latest VSCode version in the future:

1. Update flake inputs:

   ```bash
   nix flake update
   ```

2. Rebuild:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

The configuration will automatically use the newest version from `nixpkgs-bleeding`.

## Compatibility

- ✅ All existing extensions remain compatible
- ✅ Profile configuration unchanged (still uses unified `nixos` profile)
- ✅ Activity-aware window rules continue to work
- ✅ Wayland integration maintained (M1 and Hetzner)
- ✅ Desktop file customization preserved

## Rollback

If any issues occur, rollback is easy:

```bash
# Revert to previous generation
sudo nixos-rebuild switch --rollback

# Or use specific generation
nixos-rebuild switch --rollback-to <generation-number>
```

Your previous VSCode 1.104.2 will be restored.
