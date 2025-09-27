# Hetzner NixOS Migration Plan

## Current Status
- Base system working with nixos-anywhere
- Using GRUB bootloader (required for nixos-anywhere compatibility)
- Disk configuration from nixos-anywhere

## Safe Modules (Currently Active)
- ✅ base.nix
- ✅ QEMU guest optimizations
- ✅ Basic networking (DHCP)
- ✅ SSH access

## Phase 1: Core Services (Add First) ✅ COMPLETED
- [x] services/development.nix
- [x] services/networking.nix
- [x] services/onepassword.nix (without automation initially)

## Phase 2: Desktop Environment ✅ COMPLETED
- [x] desktop/kde-plasma.nix
- [x] desktop/kde-multi-panel.nix
- [x] desktop/remote-access.nix
- [x] desktop/xrdp-with-sound.nix
- [x] desktop/rdp-display.nix

## Phase 3: Browser Integration
- [ ] desktop/firefox-1password.nix
- [ ] desktop/chromium-1password.nix

## Phase 4: Development Tools
- [ ] kubernetes/agentgateway.nix
- [ ] peripherals/logitech-mx-master3.nix

## Modules to Avoid (Caused Issues)
- ❌ boot-safety.nix (conflicts with nixos-anywhere disk layout)
- ❌ cluster-certificates.nix (caused infinite restart loop)
- ❌ speech-to-text.nix (caused emergency mode)
- ❌ firefoxpwa modules (until tested separately)
- ❌ hardware/hetzner.nix (conflicts with nixos-anywhere disk setup)

## Testing Process
1. Add one module at a time
2. Build locally first: `nixos-rebuild build --flake .#hetzner`
3. If build succeeds, test on VM
4. Monitor system logs for errors
5. Only proceed to next module if system is stable

## Rollback Strategy
- Keep this branch separate from main
- Tag each successful addition
- Can always redeploy with nixos-anywhere if needed