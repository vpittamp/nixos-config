# 1Password SSH and Git Integration Guide

## Overview

This guide explains how the 1Password integration works across different environments (M1 Mac, WSL, Hetzner server) and how to resolve common authentication issues.

## Architecture

### Workstations (M1, WSL with GUI)
- **1Password Desktop**: Required and automatically started
- **SSH Agent**: Uses 1Password's agent at `~/.1password/agent.sock`
- **Git Signing**: Enabled via `op-ssh-sign`
- **Credential Helper**: Uses 1Password for GitHub/GitLab authentication

### Headless Servers (Hetzner)
- **1Password Desktop**: Not available
- **SSH Agent**: Falls back to standard SSH agent
- **Git Signing**: Disabled automatically
- **Credential Helper**: Uses OAuth or GitHub CLI tokens

## Configuration Details

### Module Structure

1. **`modules/services/onepassword.nix`**
   - System-level 1Password configuration
   - Detects GUI availability and server environment
   - Conditionally enables desktop integration

2. **`home-modules/tools/git.nix`**
   - Configures git with conditional signing
   - Uses 1Password on workstations, OAuth on servers
   - Automatically detects environment

3. **`home-modules/tools/ssh.nix`**
   - SSH client configuration
   - Uses 1Password agent when available
   - Falls back to standard SSH on servers

4. **`home-modules/tools/ssh-server.nix`**
   - Server-specific SSH configuration
   - Provides instructions for manual key setup
   - Only active on Hetzner server

## Setting Up Authentication

### On Workstations (M1, WSL)

1. **Initial 1Password Setup**
   ```bash
   # 1Password desktop should auto-start
   # If not, start manually:
   1password --silent &
   
   # Sign in to 1Password
   op signin
   ```

2. **Verify SSH Agent**
   ```bash
   # Check agent socket exists
   ls -la ~/.1password/agent.sock
   
   # List available keys
   SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l
   ```

3. **Add SSH Key to GitHub**
   ```bash
   # Get public key from 1Password
   op item get "Git Signing Key" --fields "public key"
   
   # Add to GitHub via CLI
   echo "YOUR_PUBLIC_KEY" | gh ssh-key add --title "Workstation (1Password)"
   ```

### On Headless Servers (Hetzner)

1. **Generate or Import SSH Keys**
   
   Option A: Generate new key
   ```bash
   ssh-keygen -t ed25519 -C "hetzner@$(date +%Y-%m-%d)"
   ```
   
   Option B: Import from 1Password CLI
   ```bash
   # Login to 1Password CLI
   op signin
   
   # Get key from vault
   op item get "GitHub SSH Key" --fields "private key" > ~/.ssh/id_ed25519
   op item get "GitHub SSH Key" --fields "public key" > ~/.ssh/id_ed25519.pub
   chmod 600 ~/.ssh/id_ed25519
   chmod 644 ~/.ssh/id_ed25519.pub
   ```

2. **Add to GitHub**
   ```bash
   # Using GitHub CLI
   gh auth login
   gh ssh-key add ~/.ssh/id_ed25519.pub --title "Hetzner Server"
   ```

3. **Configure Git (No Signing)**
   ```bash
   # Signing is automatically disabled on servers
   # Use HTTPS with GitHub CLI for authentication
   git config --global credential.helper "!gh auth git-credential"
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
2. **Server Detection**: `config.networking.hostName == "nixos-hetzner"`
3. **1Password Availability**: Presence of `~/.1password/agent.sock`

Based on these, it:
- Enables/disables git signing
- Switches between 1Password and standard SSH agents
- Adjusts credential helpers

## Best Practices

1. **Workstations**: Always use 1Password for SSH keys
2. **Servers**: Use GitHub CLI with OAuth tokens
3. **Commits**: Sign on workstations, don't sign on servers
4. **Keys**: Store all keys in 1Password vault
5. **Backups**: Keep encrypted backups of server SSH keys

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