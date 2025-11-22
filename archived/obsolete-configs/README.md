# Archived NixOS Configurations

Configurations moved here are no longer actively used but preserved for historical reference.

## hetzner.nix
- **Archived**: 2025-11-22
- **Reason**: Replaced by Sway/Wayland (Feature 045)
- **Active Replacement**: configurations/hetzner-sway.nix
- **Description**: Original i3wm + X11 + xrdp configuration for Hetzner Cloud
- **Last Active**: Prior to Feature 045 (X11 → Wayland migration)

This configuration used i3 tiling window manager with xrdp for remote desktop access. It was replaced by hetzner-sway.nix which uses Sway (Wayland compositor) with WayVNC for remote access, providing better performance and modern display protocol support.
