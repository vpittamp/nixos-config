#!/usr/bin/env bash
# NixOS Emergency Recovery Script
# Use this script when the system fails to boot

set -e

echo "=== NixOS Emergency Recovery Script ==="
echo "This script helps recover from boot failures"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Function to mount NixOS system
mount_nixos() {
  echo "Mounting NixOS filesystems..."
  mount /dev/sda1 /mnt 2>/dev/null || true
  mount /dev/sda2 /mnt/boot 2>/dev/null || true
  mount --bind /dev /mnt/dev 2>/dev/null || true
  mount --bind /proc /mnt/proc 2>/dev/null || true
  mount --bind /sys /mnt/sys 2>/dev/null || true
  mount -t devpts devpts /mnt/dev/pts 2>/dev/null || true
  echo "Filesystems mounted"
}

# Function to enter chroot
enter_chroot() {
  echo "Entering chroot environment..."
  SHELL=$(ls /mnt/nix/store/*bash-interactive*/bin/bash | head -1)
  if [ -z "$SHELL" ]; then
    echo "Error: Could not find bash in /mnt/nix/store"
    exit 1
  fi
  chroot /mnt "$SHELL" -c "
    export PATH=/nix/var/nix/profiles/system/sw/bin:/nix/var/nix/profiles/system/sw/sbin:\$PATH
    echo nameserver 8.8.8.8 > /etc/resolv.conf
    cd /etc/nixos
    bash
  "
}

# Function to rebuild from known good commit
rebuild_safe() {
  echo "Rebuilding from known good commit (before Sept 24, 2025)..."
  SHELL=$(ls /mnt/nix/store/*bash-interactive*/bin/bash | head -1)
  chroot /mnt "$SHELL" -c "
    export PATH=/nix/var/nix/profiles/system/sw/bin:/nix/var/nix/profiles/system/sw/sbin:\$PATH
    echo nameserver 8.8.8.8 > /etc/resolv.conf
    nixos-rebuild boot --flake 'github:vpittamp/nixos-config/0ed1ca9#hetzner' --option sandbox false
  "
}

# Function to check initrd for required modules
check_initrd() {
  echo "Checking initrd for required modules..."
  INITRD=$(ls -t /mnt/boot/EFI/nixos/*initrd* | head -1)
  if [ -f "$INITRD" ]; then
    echo "Checking $INITRD for vfat support..."
    zstd -d "$INITRD" -o /tmp/initrd.img 2>/dev/null || gunzip -c "$INITRD" > /tmp/initrd.img 2>/dev/null
    if cpio -t < /tmp/initrd.img 2>/dev/null | grep -q vfat; then
      echo "✓ vfat module found in initrd"
    else
      echo "✗ WARNING: vfat module NOT found in initrd!"
      echo "  This will cause boot failures!"
    fi
    rm -f /tmp/initrd.img
  fi
}

# Main menu
PS3='Please select recovery option: '
options=(
  "Mount NixOS filesystems"
  "Enter chroot environment"
  "Rebuild from safe commit (recommended)"
  "Check initrd for vfat module"
  "Unmount and reboot"
  "Exit"
)

select opt in "${options[@]}"
do
  case $opt in
    "Mount NixOS filesystems")
      mount_nixos
      ;;
    "Enter chroot environment")
      mount_nixos
      enter_chroot
      ;;
    "Rebuild from safe commit (recommended)")
      mount_nixos
      rebuild_safe
      ;;
    "Check initrd for vfat module")
      check_initrd
      ;;
    "Unmount and reboot")
      echo "Unmounting filesystems..."
      umount /mnt/dev/pts 2>/dev/null || true
      umount /mnt/dev 2>/dev/null || true
      umount /mnt/proc 2>/dev/null || true
      umount /mnt/sys 2>/dev/null || true
      umount /mnt/boot 2>/dev/null || true
      umount /mnt 2>/dev/null || true
      echo "Rebooting..."
      reboot
      ;;
    "Exit")
      break
      ;;
    *) echo "Invalid option $REPLY";;
  esac
done