# NixOS VM Setup on Apple Silicon Mac

## Quick Start with UTM

### 1. Install UTM
```bash
brew install --cask utm
# Or download from https://mac.getutm.app
```

### 2. Download NixOS ISO
Download the **AArch64** ISO for Apple Silicon:
https://nixos.org/download#nixos-iso

Choose: `Minimal ISO image (aarch64-linux)`

### 3. Create VM in UTM

1. Open UTM → Create New VM → Virtualize
2. Select "Linux" 
3. Browse and select the NixOS ISO
4. Configure:
   - Memory: 4096 MB (minimum, 8192 MB recommended)
   - Storage: 32 GB (minimum, 64 GB recommended)
   - Enable "Share Network with Host"
   - Enable "Clipboard Sharing"

### 4. Install NixOS

Boot the VM and run:

```bash
# Partition disk (assuming /dev/vda)
sudo parted /dev/vda -- mklabel gpt
sudo parted /dev/vda -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/vda -- set 1 esp on
sudo parted /dev/vda -- mkpart primary 512MiB 100%

# Format partitions
sudo mkfs.fat -F32 -n BOOT /dev/vda1
sudo mkfs.ext4 -L nixos /dev/vda2

# Mount partitions
sudo mount /dev/vda2 /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/vda1 /mnt/boot

# Generate hardware configuration
sudo nixos-generate-config --root /mnt

# Clone your configuration
sudo git clone https://github.com/vpittamp/nixos-config /mnt/etc/nixos-custom

# Copy M1 configuration as base
sudo cp -r /mnt/etc/nixos-custom/* /mnt/etc/nixos/

# Install NixOS with M1 configuration
sudo nixos-install --flake /mnt/etc/nixos#m1

# Set root password when prompted
# Reboot
sudo reboot
```

### 5. Post-Installation

After reboot, login as root and:

```bash
# Set user password
passwd vpittamp

# Switch to your user
su - vpittamp

# Clone your configuration
git clone https://github.com/vpittamp/nixos-config ~/nixos-config

# Apply home-manager configuration
home-manager switch --flake ~/nixos-config#vpittamp

# Test SSH from your Mac
ssh vpittamp@<vm-ip>
```

### 6. Find VM IP Address

In the VM:
```bash
ip addr show | grep "inet "
# Look for IP on eth0 or ens interface
```

### 7. SSH from macOS

```bash
# Add to ~/.ssh/config on your Mac
Host nixos-vm
    HostName <vm-ip>
    User vpittamp
    ForwardAgent yes
    ForwardX11 yes

# Then connect
ssh nixos-vm
```

## Tips

- **Performance**: Enable virtualization features in UTM settings
- **Shared Folders**: UTM supports sharing folders between host and VM
- **Snapshots**: Take snapshots before major changes
- **Clipboard**: Install `spice-vdagent` for clipboard sharing (already in config)
- **Resolution**: For HiDPI displays, adjust display scaling in UTM

## Alternative: Headless VM

For a minimal headless setup:
1. Create a custom configuration that doesn't import the desktop module
2. Import only the base and development modules
3. Manage entirely via SSH

## Using with VS Code

1. Install "Remote - SSH" extension on your Mac
2. Connect to `nixos-vm` via SSH
3. VS Code will automatically set up remote development