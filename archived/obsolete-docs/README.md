# Archived Obsolete Documentation

**Date**: 2025-10-17
**Reason**: Documentation and scripts superseded by better alternatives

## Contents

This directory contains obsolete documentation and installation scripts that have been replaced by improved workflows and better-maintained documentation.

### hetzner.md

Talos Linux documentation for creating Kubernetes clusters on Hetzner Cloud.

**Contents:**
- Instructions for uploading Talos ISO images to Hetzner
- Creating Kubernetes control plane and worker nodes
- Configuring Hetzner Cloud Controller Manager
- Load balancer setup for Kubernetes

**Archived because**: This is Talos Linux (Kubernetes-focused) documentation, not relevant to our NixOS deployment. We use NixOS with nixos-anywhere for server deployment.

**Better alternative:** See `docs/HETZNER_NIXOS_INSTALL.md` and `docs/HETZNER_SETUP.md` for current NixOS deployment instructions.

### disk-config-example.nix

Example disko configuration using LVM (Logical Volume Manager).

**Contents:**
- GPT partition table with boot, ESP, and root partitions
- LVM setup with physical volume and volume group
- ext4 filesystem on LVM logical volume

**Archived because**: This is a generic example. We have working disk configuration in `disk-config.nix` (ZFS-based) that's actually used for Hetzner deployment.

**Better alternative:** See `disk-config.nix` in the root directory for the actual configuration used.

### install-nixos.sh

Manual NixOS installation script for Hetzner Cloud.

**Contents:**
- Manual disk partitioning with parted
- ext4 filesystem formatting
- nixos-generate-config
- Simple configuration template with basic networking

**Archived because**: This manual installation process has been replaced by automated nixos-anywhere deployment. The script required manual intervention and was error-prone.

**Better alternative:** See `docs/HETZNER_NIXOS_INSTALL.md` for nixos-anywhere automated deployment instructions.

## Migration Notes

### If You Need Manual Installation

If you need to manually install NixOS (e.g., for troubleshooting or custom setups):

1. Boot the NixOS ISO in Hetzner rescue mode
2. Use disko for automated partitioning: `sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /path/to/disk-config.nix`
3. Follow instructions in `docs/HETZNER_NIXOS_INSTALL.md`

### If You Need Talos/Kubernetes

If you want to deploy Talos Linux for Kubernetes:

1. Follow official Talos documentation: https://www.talos.dev/
2. Refer to Hetzner-specific guides: https://www.talos.dev/latest/talos-guides/install/cloud-platforms/hetzner/

### Recovery

To restore these files (not recommended):

```bash
# Copy files back to root
cp archived/obsolete-docs/hetzner.md .
cp archived/obsolete-docs/disk-config-example.nix .
cp archived/obsolete-docs/install-nixos.sh .
```

## Current Deployment Workflow

The current recommended workflow for Hetzner deployment:

1. **Prepare configuration**: Edit `disk-config.nix` and `configurations/hetzner.nix`
2. **Deploy with nixos-anywhere**:
   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#hetzner \
     --build-on-remote \
     root@<server-ip>
   ```
3. **Configure post-deployment**: SSH into server and customize as needed

See `docs/HETZNER_NIXOS_INSTALL.md` for complete instructions.

## Git History

Full implementation is preserved in git history. To view:

```bash
git log --all --follow -- hetzner.md
git log --all --follow -- disk-config-example.nix
git log --all --follow -- install-nixos.sh
```

**Archival commit**: Feature 009 (KDE Plasma to i3wm migration), Phase 3 cleanup
