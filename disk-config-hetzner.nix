# Disko configuration for Hetzner Cloud servers
# This configuration automates disk partitioning for NixOS installation
# Usage: nix run github:nix-community/disko -- --mode disko /path/to/this/file

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Hetzner typically uses /dev/sda, but can be /dev/vda on some instances
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            # EFI System Partition (512MB)
            ESP = {
              priority = 1;
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                  "umask=0077"
                ];
              };
            };
            
            # Swap partition (8GB)
            swap = {
              priority = 2;
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = false;
                resumeDevice = true;
              };
            };
            
            # Root partition (remaining space)
            root = {
              priority = 3;
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "defaults"
                  "noatime"
                  "nodiratime"
                ];
              };
            };
          };
        };
      };
    };
  };
}