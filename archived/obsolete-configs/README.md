# Archived Obsolete Configurations

**Date**: 2025-10-17
**Reason**: KDE Plasma to i3wm migration (Feature 009)

## Contents

This directory contains platform configurations that are no longer in use.

### hetzner-mangowc.nix
**Purpose**: Hetzner Cloud server with MangoWC Wayland compositor experiment
**Archived because**: Wayland compositor experiment discontinued, migrating to i3wm + X11

### wsl.nix
**Purpose**: Windows Subsystem for Linux development environment
**Archived because**: WSL environment no longer in active use

## Recovery

If you need to restore these configurations:

1. Copy back to configurations/:
   ```bash
   cp archived/obsolete-configs/<file> configurations/
   ```

2. Add to flake.nix nixosConfigurations:
   ```nix
   hetzner-mangowc = lib.nixosSystem {
     system = "x86_64-linux";
     modules = [ ./configurations/hetzner-mangowc.nix ];
   };
   ```

3. Rebuild: `nixos-rebuild switch --flake .#<config-name>`

## Git History

Full implementation is preserved in git history. Search for commits before branch 009-let-s-create.
