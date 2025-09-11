# 1Password Integration Guide

## Overview

This guide covers the complete integration of 1Password into NixOS, providing centralized secret management, SSH key handling, Git commit signing, and credential management across all system configurations.

## Features

- **Centralized Secret Management**: All secrets in one secure location
- **SSH Agent Integration**: Use 1Password as your SSH agent
- **Git Commit Signing**: Sign commits with SSH keys from 1Password
- **Credential Helper**: Automatic authentication for GitHub/GitLab
- **Cross-Platform Support**: Works on desktop (GUI) and headless (CLI) systems
- **Declarative Configuration**: Fully managed through NixOS

## Architecture

The 1Password integration consists of two main components:

1. **System Module** (`modules/services/onepassword.nix`): System-level configuration
2. **Home Module** (`home-modules/tools/onepassword-plugins.nix`): User-level shell plugins

## Installation

### 1. System Configuration

The 1Password module is automatically included in the appropriate configurations:
- ✅ **M1**: Full GUI and CLI support
- ✅ **Hetzner**: Full GUI and CLI support  
- ✅ **WSL**: CLI-only support (no GUI)
- ❌ **Containers**: Not included (minimal environment)

### 2. Initial Setup

After rebuilding your system, complete the 1Password setup:

```bash
# For GUI systems (M1, Hetzner)
# 1Password will auto-start or can be launched from KDE menu

# For CLI-only systems (WSL)
# Sign in via CLI
op signin

# Verify installation
op --version
op vault list
```

## Configuration Details

### System Module Features

The `onepassword.nix` module provides:

```nix
{
  # Automatic GUI detection
  hasGui = config.services.xserver.enable or false;
  
  # Conditional package installation
  environment.systemPackages = [
    _1password        # CLI (always)
    _1password-gui    # GUI (only if desktop available)
  ];
  
  # SSH agent configuration
  environment.sessionVariables = {
    SSH_AUTH_SOCK = "/home/vpittamp/.1password/agent.sock";
  };
}
```

### Home Manager Integration

The home-manager configuration provides:

```nix
{
  # Shell plugins for CLI tools
  programs._1password-shell-plugins = {
    enable = true;
    plugins = [ gh awscli2 ];
  };
  
  # Git configuration
  programs.git = {
    signing.key = "ssh-ed25519 AAAA...";
    signing.signByDefault = true;
    extraConfig.gpg.format = "ssh";
  };
}
```

## SSH Key Management

### Setting Up SSH Agent

1. **Enable SSH Agent in 1Password**:
   - Open 1Password → Settings → Developer
   - Enable "Use the SSH agent"
   - Select which vaults contain SSH keys

2. **Configuration Applied Automatically**:
   ```bash
   # SSH config managed by NixOS
   Host *
     IdentityAgent ~/.1password/agent.sock
     AddKeysToAgent yes
   ```

3. **Test SSH Agent**:
   ```bash
   # List keys available through 1Password
   SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l
   
   # Test connection
   ssh -T git@github.com
   ```

### Creating New SSH Keys

```bash
# Create SSH key in 1Password
op item create --category="SSH Key" \
  --title="GitHub SSH Key" \
  --vault="Personal" \
  --ssh-generate-key=ed25519

# View the public key
op item get "GitHub SSH Key" --fields "public key"
```

## Git Commit Signing

### Setup Process

1. **Create Signing Key**:
   ```bash
   # Create dedicated signing key
   op item create --category="SSH Key" \
     --title="Git Signing Key" \
     --vault="Personal" \
     --ssh-generate-key=ed25519
   ```

2. **Configuration (Automated)**:
   The NixOS configuration automatically sets up:
   - SSH signing format
   - Signing key from 1Password
   - Allowed signers file
   - op-ssh-sign helper

3. **Verify Setup**:
   ```bash
   # Test signing
   git commit -m "Test signed commit"
   
   # Verify signature
   git log --show-signature -1
   ```

## GitHub/GitLab Integration

### GitHub CLI Setup

1. **Create Personal Access Token**:
   ```bash
   # Store token in 1Password
   op item create --category="API Credential" \
     --title="Github Personal Access Token" \
     --vault="Personal" \
     token[concealed]="ghp_..." \
     host="github.com"
   ```

2. **Use with GitHub CLI**:
   ```bash
   # Alias configured automatically
   gh auth status  # Uses 1Password for authentication
   
   # Or manually with token
   GH_TOKEN=$(op item get "Github Personal Access Token" --fields token --reveal) gh repo list
   ```

### Git Credential Helper

The configuration provides multiple credential helpers:
1. OAuth (primary)
2. 1Password op-ssh-sign
3. GitHub CLI plugin
4. GitLab CLI plugin

## Shell Plugin Usage

### Available Plugins

Configured plugins in `onepassword-plugins.nix`:
- `gh` - GitHub CLI
- `awscli2` - AWS CLI
- Additional plugins can be added as needed

### Using Plugins

```bash
# GitHub CLI (automatic with alias)
gh repo list

# AWS CLI
op plugin run -- aws s3 ls

# Direct 1Password CLI usage
op run -- <command>
```

## Troubleshooting

### Common Issues

#### 1. SSH Agent Not Working

**Problem**: `Could not open a connection to your authentication agent`

**Solution**:
```bash
# Check agent socket exists
ls -la ~/.1password/agent.sock

# Ensure 1Password is running
systemctl --user status onepassword-gui

# Manually set socket
export SSH_AUTH_SOCK=~/.1password/agent.sock
```

#### 2. Git Signing Fails

**Problem**: `error: 1Password: no ssh public key file found`

**Solution**:
```bash
# Verify signing key exists
op item list --categories "SSH Key"

# Check Git config
git config --list | grep signing

# Ensure allowed_signers file exists
cat ~/.config/git/allowed_signers
```

#### 3. GUI Scaling Issues (M1)

**Problem**: 1Password GUI has incorrect scaling

**Solution**: Use the alternative desktop entry:
```bash
# Launch with manual scaling
env QT_SCALE_FACTOR=0.75 1password
```

#### 4. Biometric Authentication

**Note**: Touch ID is not supported on Linux. Use system password authentication instead.

### Debug Commands

```bash
# Check 1Password status
op signin status

# List available vaults
op vault list

# Test SSH agent
SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l

# Verify Git configuration
git config --list | grep -E "(credential|signing|gpg)"

# Check installed components
which op
which op-ssh-sign
```

## Security Best Practices

1. **Vault Organization**:
   - Keep SSH keys in dedicated vault
   - Separate production and development credentials
   - Use descriptive names for keys

2. **Access Control**:
   - Enable biometric unlock where available
   - Use strong master password
   - Configure auto-lock timeout

3. **Key Rotation**:
   - Regularly rotate SSH keys
   - Update Git signing keys periodically
   - Revoke unused credentials

4. **Backup Strategy**:
   - Enable 1Password cloud sync
   - Export emergency kit
   - Keep offline backup of critical keys

## Advanced Configuration

### Custom Vault Selection

```nix
# In home-modules/tools/onepassword-plugins.nix
environment.etc."1password-ssh-agent.toml" = {
  text = ''
    [[ssh-keys]]
    vault = "Development"
    
    [[ssh-keys]]
    vault = "Production"
    account = "work"
  '';
};
```

### Multiple Account Support

```bash
# Switch between accounts
op signin --account personal
op signin --account work

# Use specific account
op --account work item list
```

### Scripting with 1Password

```bash
#!/usr/bin/env bash
# Example: Deploy script using 1Password secrets

# Get database password
DB_PASS=$(op item get "Production DB" --fields password)

# Get API key
API_KEY=$(op item get "Deploy API" --fields credential)

# Use in deployment
deploy --db-pass "$DB_PASS" --api-key "$API_KEY"
```

## Platform-Specific Notes

### WSL (Windows Subsystem for Linux)

- GUI components disabled automatically
- Use Windows 1Password app for vault management
- CLI fully functional for secret retrieval

### Containers

- Not included by default (minimal environment)
- Can be added if needed for specific use cases
- Consider using secrets mounting instead

### Remote Servers (Hetzner)

- Full GUI support over RDP
- SSH agent forwarding configured
- Accessible via Tailscale VPN

## Migration from Other Tools

### From ssh-agent

```bash
# Export existing keys (do this before migration)
ssh-add -L > ~/old-ssh-keys.pub

# Import into 1Password manually or via CLI
# Then update SSH config to use 1Password agent
```

### From GPG Signing

```bash
# Update Git config
git config --global gpg.format ssh
git config --global user.signingkey "ssh-ed25519 YOUR_KEY"
```

## References

- [1Password Developer Documentation](https://developer.1password.com/)
- [1Password CLI Reference](https://developer.1password.com/docs/cli/)
- [SSH Agent Documentation](https://developer.1password.com/docs/ssh/)
- [Git Signing Guide](https://developer.1password.com/docs/ssh/git-commit-signing/)

---

**Last Updated**: September 2025  
**Configuration Version**: NixOS 24.11