# Boot Failure Recovery Guide

## Issue Summary (September 25, 2025)

### What Happened
The Hetzner NixOS system failed to boot and dropped to emergency mode with the error:
- "Unknown filesystem type 'vfat'"
- System couldn't mount `/boot` partition
- Emergency mode prevented normal operation

### Root Cause
1. **Missing kernel modules in initrd**: The `vfat` filesystem driver was not included in the initial ramdisk
2. **Configuration gap**: `boot.initrd.kernelModules` was empty in `hardware/hetzner.nix`
3. **Garbage collection**: Previous working generations were removed, preventing rollback

### Why It Happened
- The `/boot` partition uses vfat filesystem (standard for UEFI)
- NixOS doesn't automatically detect all required filesystem modules
- Without explicit configuration, vfat wasn't included in initrd
- During boot, the kernel couldn't mount `/boot` without the vfat module

## Prevention Measures Implemented

### 1. Hardware Configuration Fix
**File**: `/etc/nixos/hardware/hetzner.nix`

Added critical kernel modules:
```nix
boot.initrd.kernelModules = [
  "vfat"           # Required for EFI /boot partition
  "nls_cp437"      # Character encoding for FAT
  "nls_iso8859-1"  # ISO character encoding for FAT
];
```

### 2. Boot Safety Module
**File**: `/etc/nixos/modules/boot-safety.nix`

Created comprehensive boot protection:
- Ensures critical filesystem modules are always included
- Keeps more boot generations (10 instead of default)
- Adds filesystem check tools to initrd
- Enables emergency shell on failure

### 3. Emergency Recovery Script
**File**: `/etc/nixos/scripts/emergency-recovery.sh`

Interactive recovery tool that:
- Mounts NixOS filesystems
- Provides chroot environment
- Can rebuild from known good commits
- Verifies initrd contains required modules

## Recovery Procedure

If the system fails to boot again:

### 1. Enable Hetzner Rescue Mode
- Log into Hetzner Cloud Console
- Select your server
- Go to "Rescue" tab
- Enable rescue mode with your SSH key
- Reboot server

### 2. Connect to Rescue System
```bash
ssh root@<server-ip>
# Use the password provided by Hetzner
```

### 3. Run Recovery Script
```bash
# Download the recovery script
curl -O https://raw.githubusercontent.com/vpittamp/nixos-config/main/scripts/emergency-recovery.sh
chmod +x emergency-recovery.sh
./emergency-recovery.sh
```

### 4. Manual Recovery (if script unavailable)
```bash
# Mount filesystems
mount /dev/sda1 /mnt
mount /dev/sda2 /mnt/boot
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount -t devpts devpts /mnt/dev/pts

# Enter chroot
chroot /mnt /nix/store/*bash-interactive*/bin/bash

# Set up environment
export PATH=/nix/var/nix/profiles/system/sw/bin:$PATH
echo nameserver 8.8.8.8 > /etc/resolv.conf

# Rebuild from safe commit
nixos-rebuild boot --flake 'github:vpittamp/nixos-config/0ed1ca9#hetzner' --option sandbox false

# Exit and reboot
exit
umount /mnt/{dev/pts,dev,proc,sys,boot,}
reboot
```

## Verification Steps

### Check Current Configuration
```bash
# Verify vfat module is configured
grep -n "vfat" /etc/nixos/hardware/hetzner.nix

# Check if boot-safety module is imported
grep -n "boot-safety" /etc/nixos/configurations/hetzner.nix
```

### Verify After Rebuild
```bash
# Extract and check initrd for vfat
INITRD=$(ls -t /boot/EFI/nixos/*initrd* | head -1)
zstd -d "$INITRD" -o /tmp/test.img
cpio -t < /tmp/test.img | grep vfat
# Should show: .../kernel/fs/fat/vfat.ko.xz
```

## Best Practices

1. **Always test configuration changes**: Run `nixos-rebuild dry-build` before applying
2. **Keep multiple generations**: Don't aggressively garbage collect
3. **Document hardware requirements**: Explicitly list all required modules
4. **Regular backups**: Keep configuration backed up to GitHub
5. **Test recovery procedures**: Verify you can boot into rescue mode

## Key Commits

- **Last known good**: `0ed1ca9` (Sept 23, 2025)
- **Issue introduced**: After Sept 24, 2025 noon EST
- **Fix applied**: Sept 25, 2025

## Lessons Learned

1. **Explicit is better than implicit**: Always explicitly declare filesystem modules
2. **Test boot changes carefully**: Boot-related changes are critical
3. **Keep rescue procedures ready**: Have recovery scripts prepared
4. **Monitor system generations**: Don't let all working generations get garbage collected

## Additional Resources

- [NixOS Manual - Boot Loader](https://nixos.org/manual/nixos/stable/#ch-boot)
- [Hetzner Rescue System](https://docs.hetzner.com/robot/dedicated-server/troubleshooting/hetzner-rescue-system/)
- [NixOS initrd Documentation](https://nixos.wiki/wiki/Initrd)

---
*Last updated: September 25, 2025*
*Issue resolved and preventive measures implemented*