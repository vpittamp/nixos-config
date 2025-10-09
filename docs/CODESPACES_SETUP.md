# GitHub Codespaces Setup with NixOS Configuration

This guide explains how to set up your NixOS home-manager configuration in GitHub Codespaces.

## Quick Start

### Initial Setup (Automated)

```bash
# Download and run the setup script
curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/main/scripts/codespaces-setup.sh | bash
```

### Manual Setup

If you prefer to run commands manually:

```bash
# 1. Clean up any existing nix profile packages
nix profile remove home-manager-path 2>/dev/null || true

# 2. Activate home-manager
home-manager switch --flake github:vpittamp/nixos-config#code --impure

# 3. Reload your shell
source ~/.profile
# or just open a new terminal
```

## Common Issues

### Error: "An existing package already provides the following file"

**Cause:** A package (like `helm`, `kubectl`, or `az`) was already installed via `nix profile install`, which conflicts with home-manager.

**Solution:**
```bash
# Remove all nix profile packages
nix profile list
nix profile remove home-manager-path

# Or remove specific package by index
nix profile remove 0  # where 0 is the index from 'nix profile list'

# Then retry home-manager activation
home-manager switch --flake github:vpittamp/nixos-config#code --impure
```

### Error: "bash: /home/code/.nix-profile/bin/starship: No such file or directory"

**Cause:** Your shell is trying to use starship before home-manager has installed it.

**Solution:**
```bash
# Temporarily disable starship in your current shell
unset STARSHIP_SHELL

# Then run home-manager activation
home-manager switch --flake github:vpittamp/nixos-config#code --impure

# Restart your shell
exec bash
```

## What Gets Installed

After home-manager activation, you'll have access to:

### Kubernetes Tools
- `kubectl` - Kubernetes CLI
- `helm` - Helm package manager (v3.19.0)
- `k9s` - Terminal UI for Kubernetes
- `idpbuilder` - IDP builder (x86_64 only)

### Cloud Tools
- `az` - Azure CLI (v2.65.0)

### Development Tools
- `git`, `gh` - Git and GitHub CLI
- `tmux`, `sesh` - Terminal multiplexing
- `neovim` - Text editor with full config
- `fzf`, `ripgrep`, `fd`, `bat` - CLI utilities
- `jq`, `yq` - JSON/YAML processing
- `gum` - Shell script UI builder

### AI Assistants
- `claude-code` - Claude Code CLI
- `codex` - Codex CLI
- `gemini` - Gemini CLI

### Shell Environment
- Starship prompt
- Bash with custom configuration
- Direnv for project environments
- Custom aliases and functions

## Verifying Installation

```bash
# Check Kubernetes tools
kubectl version --client
helm version
k9s version
idpbuilder version

# Check cloud tools
az --version

# Check shell tools
tmux -V
nvim --version
starship --version
```

## Updating Configuration

To update your Codespaces environment after pulling config changes:

```bash
# If you used the automated setup script
curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/main/scripts/codespaces-setup.sh | bash

# Or manually
home-manager switch --flake github:vpittamp/nixos-config#code --impure
```

## Using Local Configuration

If you've cloned the nixos-config repo into your Codespace:

```bash
cd /workspaces/nixos-config
home-manager switch --flake .#code --impure
```

## Best Practices

1. **Always use the setup script for fresh Codespaces** - It handles cleanup automatically
2. **Don't use `nix profile install`** - Let home-manager manage all packages
3. **Use `--impure` flag** - Required for flake evaluation in Codespaces
4. **Restart your shell after activation** - Ensures all environment changes take effect

## Troubleshooting

### Profile Conflicts

If you keep getting profile conflicts:

```bash
# Nuclear option - remove entire profile
rm -rf ~/.nix-profile
nix profile list  # Should show empty or error

# Then run home-manager
home-manager switch --flake github:vpittamp/nixos-config#code --impure
```

### Missing Commands

If commands aren't in PATH after activation:

```bash
# Reload shell environment
source ~/.profile
source ~/.bashrc

# Or restart shell
exec bash
```

### Flake Evaluation Errors

If you get flake evaluation errors:

```bash
# Make sure you're using --impure flag
home-manager switch --flake github:vpittamp/nixos-config#code --impure

# If that doesn't work, try updating nix
nix upgrade-nix
```

## Container Profile

The `code` profile is optimized for containers and includes:
- Minimal system overhead
- Essential development tools
- No GUI applications
- Container-safe configurations (no 1Password, no KDE-specific tools)

See `home-modules/profiles/container-home.nix` for details.

## Related Documentation

- [Architecture Overview](ARCHITECTURE.md)
- [Container Configuration](../configurations/container.nix)
- [User Packages](../user/packages.nix)
- [Main README](../README.md)

---

*Last updated: 2025-10 with Kubernetes tools migration*
