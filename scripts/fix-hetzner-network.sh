#!/usr/bin/env bash
# Fix Hetzner network configuration

echo "Checking network interfaces..."
ip a

echo "Finding primary network interface..."
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip link | grep -E "^[0-9]+: en" | awk -F': ' '{print $2}' | head -1)
fi

echo "Primary interface detected: $INTERFACE"

# Create a temporary network fix
cat > /tmp/network-fix.nix <<EOF
{ config, lib, pkgs, ... }:
{
  networking = {
    useDHCP = false;
    interfaces.\${INTERFACE} = {
      useDHCP = true;
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };
  
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;  # Temporarily enable for access
    };
  };
}
EOF

echo "Applying network fix..."
nixos-rebuild switch --impure -I nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos

echo "Starting SSH service..."
systemctl restart sshd

echo "Network configuration status:"
ip addr show $INTERFACE
systemctl status sshd

echo "Setting up Tailscale..."
tailscale up