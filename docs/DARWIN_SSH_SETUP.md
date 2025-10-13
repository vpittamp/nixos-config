# macOS Darwin SSH Setup Guide

This guide explains how to enable SSH access to your M1 MacBook Pro.

## Quick Setup

Run this script on your Mac to enable SSH and check the configuration:

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/vpittamp/nixos-config/main/scripts/setup-macos-ssh.sh | bash

# Or if you have the repo cloned:
/etc/nixos/scripts/setup-macos-ssh.sh
```

## Manual Setup Steps

### 1. Enable SSH Server (Remote Login)

**Via GUI:**
1. Open **System Settings** (System Preferences on older macOS)
2. Go to **General** → **Sharing**
3. Toggle **Remote Login** to **On**
4. Click the info icon (ⓘ) to see which users can connect

**Via Command Line:**
```bash
sudo systemsetup -setremotelogin on
```

### 2. Check SSH Service Status

```bash
# Check if SSH daemon is running
sudo launchctl list | grep sshd

# You should see something like:
# -	0	com.openssh.sshd
```

### 3. Get Your Connection Information

```bash
# Get your Mac's hostname
hostname

# Get your local IP address
ipconfig getifaddr en0  # WiFi
# or
ipconfig getifaddr en1  # Ethernet

# Get your username
whoami
```

### 4. Set Up SSH Keys (Recommended)

**On the CLIENT machine** (the machine you'll SSH FROM):

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy your public key to the Mac
ssh-copy-id vinodpittampalli@<mac-ip-address>

# Test the connection
ssh vinodpittampalli@<mac-ip-address>
```

**Manual key setup** (if ssh-copy-id doesn't work):

On the client machine:
```bash
# Display your public key
cat ~/.ssh/id_ed25519.pub
```

On your Mac:
```bash
# Create .ssh directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add the public key to authorized_keys
echo "ssh-ed25519 AAAAC3NzaC1lZDI1... your_email@example.com" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 5. Using 1Password SSH Keys

Since your home-manager configuration includes 1Password SSH integration, you can use SSH keys stored in 1Password:

**On your Mac** (if 1Password is set up):
```bash
# Check if 1Password SSH agent is working
ssh-add -l

# This should show keys from 1Password
```

**From another machine**:
You can use the same 1Password SSH keys if 1Password is installed and configured there too.

## SSH Configuration

The default macOS SSH configuration (`/etc/ssh/sshd_config`) allows:
- ✅ Password authentication (for initial setup)
- ✅ Public key authentication (recommended)
- ❌ Root login (disabled by default)

### Recommended Security Settings

For better security, you may want to disable password authentication after setting up SSH keys:

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Find and set:
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no

# Restart SSH service
sudo launchctl stop com.openssh.sshd
sudo launchctl start com.openssh.sshd
```

## Firewall Configuration

Check if the macOS firewall is blocking SSH:

```bash
# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Allow SSH through firewall (if needed)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/sbin/sshd
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/sbin/sshd
```

Or via GUI:
1. **System Settings** → **Network** → **Firewall**
2. Click **Options**
3. Ensure SSH or "Remote Login" is allowed

## Troubleshooting

### Can't Connect - Connection Refused

```bash
# On Mac: Check if SSH is running
sudo launchctl list | grep sshd

# If not running, start it
sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
```

### Can't Connect - Permission Denied

```bash
# On Mac: Check authorized_keys permissions
ls -la ~/.ssh/
# Should show:
# drwx------  (700) for .ssh directory
# -rw-------  (600) for authorized_keys file

# Fix permissions if needed
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Connection Works But Closes Immediately

This might be a shell configuration issue. Check:

```bash
# On Mac: Check if your shell works
echo $SHELL
$SHELL --version

# Test your bash configuration
bash --norc

# If that works, there's an issue in ~/.bashrc or ~/.bash_profile
```

### Can't Find Mac's IP Address

```bash
# Try all network interfaces
ifconfig | grep "inet " | grep -v 127.0.0.1

# Or use the GUI:
# Option+Click the WiFi icon in menu bar
```

## Tailscale (VPN) Access

If you're using Tailscale (configured in your NixOS setup), you can SSH over Tailscale:

```bash
# On Mac: Install and start Tailscale
# https://tailscale.com/download/mac

# From another Tailscale device:
ssh vinodpittampalli@<mac-hostname>.tail-scale.ts.net
```

## Connection from WSL/Hetzner

Once SSH is set up, you can connect from your other machines:

**From WSL:**
```bash
# Using local network
ssh vinodpittampalli@<mac-ip>

# Using Tailscale (recommended)
ssh vinodpittampalli@<mac-hostname>
```

**From Hetzner:**
```bash
# Over Tailscale (recommended for security)
ssh vinodpittampalli@<mac-hostname>

# Direct (only if Mac has public IP, not recommended)
ssh vinodpittampalli@<public-ip>
```

## SSH Config File

Add this to `~/.ssh/config` on client machines for easier access:

```ssh-config
# macOS M1 MacBook Pro
Host mac
    HostName <mac-ip-or-tailscale-hostname>
    User vinodpittampalli
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ForwardAgent yes

# Over Tailscale
Host mac-ts
    HostName <mac-hostname>.tail-scale.ts.net
    User vinodpittampalli
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
```

Then connect simply with:
```bash
ssh mac
# or
ssh mac-ts
```

## Home-Manager Integration

Your home-manager configuration already includes SSH client configuration at:
- `/etc/nixos/home-modules/tools/ssh.nix`

The SSH server setup on macOS is handled by macOS itself (not home-manager), but the client configuration will work once home-manager is installed.

## Security Best Practices

1. ✅ Use SSH keys instead of passwords
2. ✅ Use 1Password SSH agent for key management
3. ✅ Disable password authentication after key setup
4. ✅ Use Tailscale for remote access (encrypted tunnel)
5. ✅ Keep macOS and SSH updated
6. ⚠️ Don't expose SSH directly to the internet without additional security

---

*Last updated: 2025-10-13*
