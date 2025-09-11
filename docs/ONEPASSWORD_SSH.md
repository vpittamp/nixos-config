# 1Password SSH and Git Integration Guide

## Overview

This guide explains how the 1Password integration works across all NixOS environments (M1 Mac, WSL, Hetzner server with KDE) and how to resolve common authentication issues.

## Architecture

All systems use the same 1Password desktop configuration:
- **1Password Desktop**: Required and automatically started with GUI
- **SSH Agent**: Uses 1Password's agent at `~/.1password/agent.sock`
- **Git Signing**: Enabled via `op-ssh-sign`
- **Credential Helper**: Uses 1Password for GitHub/GitLab authentication

### Important Note for Hetzner
The Hetzner server runs full KDE Plasma desktop with xRDP for remote access. 1Password desktop must be started within the desktop session (via RDP), not over SSH.

## Configuration Details

### Module Structure

1. **`modules/services/onepassword.nix`**
   - System-level 1Password configuration
   - Detects GUI availability and server environment
   - Conditionally enables desktop integration

2. **`home-modules/tools/git.nix`**
   - Configures git with SSH signing via 1Password
   - Uses 1Password for credential storage
   - OAuth as fallback authentication

3. **`home-modules/tools/ssh.nix`**
   - SSH client configuration
   - Uses 1Password agent on all systems
   - Supports DevSpace dynamic SSH config

## Setting Up Authentication

### On All Systems (M1, WSL, Hetzner)

1. **Initial 1Password Setup**
   ```bash
   # 1Password desktop should auto-start with GUI session
   # If not, start manually from within desktop session:
   1password --silent &
   
   # Sign in to 1Password (from terminal within desktop)
   op signin
   ```
   
   **Note for Hetzner**: Connect via RDP first to access the desktop session:
   ```bash
   # From your local machine:
   xfreerdp /v:nixos-hetzner /u:vpittamp /p:PASSWORD /size:1920x1080
   # Or use any RDP client to connect to the server
   ```

2. **Configure GitHub CLI with 1Password**
   
   a. Create a GitHub Personal Access Token:
   ```bash
   # Open GitHub settings in browser
   open https://github.com/settings/tokens/new
   # Or navigate manually to Settings → Developer settings → Personal access tokens
   
   # Required scopes:
   # - repo (full control)
   # - workflow (if using Actions)
   # - admin:ssh_signing_key (for SSH key management)
   ```
   
   b. Save token in 1Password:
   ```bash
   # Create a new Login item in 1Password desktop
   # Title: "GitHub CLI"
   # Fields:
   #   - username: your-github-username
   #   - password: your-personal-access-token
   #   - website: https://github.com
   ```
   
   c. Initialize GitHub CLI plugin:
   ```bash
   # Interactive setup (requires desktop session)
   op plugin init gh
   
   # Or configure manually
   gh auth login --with-token < <(op item get "GitHub CLI" --fields password)
   ```

3. **Verify SSH Agent**
   ```bash
   # Ensure SSH_AUTH_SOCK is set
   echo $SSH_AUTH_SOCK  # Should show: /home/vpittamp/.1password/agent.sock
   
   # If not set, reload shell or run:
   export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
   
   # List available keys
   ssh-add -l
   ```

4. **Add SSH Key to GitHub**
   ```bash
   # Get public key from 1Password
   op item get "Git Signing Key" --fields "public key"
   
   # Add to GitHub via CLI
   echo "YOUR_PUBLIC_KEY" | gh ssh-key add --title "Workstation (1Password)"
   
   # Or if GitHub CLI is configured:
   op item get "Git Signing Key" --fields "public key" | gh ssh-key add --title "$(hostname)"
   ```


## Troubleshooting

### Issue: "Permission denied (publickey)" when pushing to GitHub

**Cause**: SSH key not in 1Password or not added to GitHub

**Solution**:
1. Check if key exists in 1Password:
   ```bash
   op item list --categories "SSH Key"
   ```

2. Ensure key is in agent config:
   ```bash
   cat ~/.config/1Password/ssh/agent.toml
   ```

3. Add key to GitHub:
   ```bash
   gh ssh-key list  # Check existing keys
   gh ssh-key add ~/.ssh/id_ed25519.pub
   ```

### Issue: "op-ssh-sign: command not found"

**Cause**: 1Password GUI package not installed

**Solution**:
- On workstations: Ensure `_1password-gui` is in system packages
- On servers: This is expected; signing is disabled

### Issue: Git signing fails with "No SSH private key found"

**Cause**: Mismatch between configured signing key and 1Password vault

**Solution**:
1. Check configured key:
   ```bash
   git config --get user.signingkey
   ```

2. Verify key in 1Password:
   ```bash
   op item get "Git Signing Key" --fields "public key"
   ```

3. Update git config if needed:
   ```bash
   git config --global user.signingkey "ssh-ed25519 YOUR_KEY_HERE"
   ```

### Issue: 1Password won't start over SSH on Hetzner

**Cause**: 1Password requires a display session (X11/Wayland)

**Solution**:
1. Connect to Hetzner via RDP:
   ```bash
   xfreerdp /v:nixos-hetzner /u:vpittamp /size:1920x1080
   ```

2. Once in the desktop session, open a terminal and start 1Password:
   ```bash
   1password --silent &
   ```

3. The agent socket will be created at `~/.1password/agent.sock`

4. After this, SSH connections will work with the running agent

### Issue: 1Password agent not running

**Cause**: 1Password desktop not started or CLI integration disabled

**Solution**:
1. Start 1Password desktop:
   ```bash
   1password --silent &
   ```

2. Enable CLI integration:
   - Open 1Password desktop
   - Settings → Developer
   - Enable "Integrate with 1Password CLI"

3. Verify agent:
   ```bash
   ps aux | grep 1password
   ls -la ~/.1password/agent.sock
   ```

## Environment Detection

The configuration automatically detects:

1. **GUI Availability**: `config.services.xserver.enable`
2. **1Password Availability**: Presence of 1Password GUI package

All systems with GUI (including Hetzner) use the same 1Password configuration for:
- Git signing with SSH keys
- SSH agent for authentication
- Credential helpers for GitHub/GitLab

## Best Practices

1. **All Systems**: Use 1Password for SSH keys
2. **Authentication**: Store all keys in 1Password vault
3. **Commits**: Sign all commits with SSH keys from 1Password
4. **Hetzner Access**: Always start 1Password from within RDP session
5. **Backups**: 1Password syncs keys across devices automatically

## Quick Commands Reference

```bash
# Check 1Password status
op vault list

# List SSH keys in 1Password
op item list --categories "SSH Key"

# Test GitHub SSH connection
ssh -T git@github.com

# Check git signing config
git config --get gpg.format
git config --get user.signingkey
git config --get gpg.ssh.program

# Temporarily disable signing for one commit
git -c commit.gpgsign=false commit -m "message"

# Use GitHub CLI for HTTPS push
git push https://$(gh auth token)@github.com/user/repo.git
```

## Related Documentation

- [1Password SSH Agent Docs](https://developer.1password.com/docs/ssh/)
- [GitHub SSH Key Setup](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [Git SSH Signing](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)