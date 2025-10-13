# macOS Darwin Quick Start

Quick reference for using the Darwin home-manager configuration on your M1 MacBook Pro.

## Prerequisites

```bash
# Install Nix (if not already installed)
sh <(curl -L https://nixos.org/nix/install)

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

## Installation

```bash
# Clone this repository (if needed)
git clone https://github.com/vpittamp/nixos-config.git ~/nixos-config
cd ~/nixos-config

# Apply the Darwin home-manager configuration
nix run home-manager/master -- switch --flake .#darwin
```

## Daily Usage

```bash
# Update and switch configuration
cd ~/nixos-config
nix flake update
home-manager switch --flake .#darwin

# Test before applying
home-manager build --flake .#darwin

# Check what will change
home-manager switch --flake .#darwin --dry-run
```

## What You Get

✅ **Shell & Terminal**
- Bash with custom prompt (Starship)
- Tmux with enhanced keybindings
- Sesh session manager

✅ **Development Tools**
- Neovim with lazy.nvim
- Git + SSH with 1Password
- Direnv, FZF, Bat

✅ **AI Assistants**
- Claude Code CLI
- Codex CLI
- Gemini CLI

✅ **Cloud Tools**
- kubectl, k9s
- Docker (via Docker Desktop)

❌ **Not Included (Linux-Only)**
- KDE Plasma desktop
- Konsole terminal
- Linux-specific GUI tools

## Customization

Edit files in this order:

1. **User settings**: `/etc/nixos/home-darwin.nix`
2. **Darwin profile**: `/etc/nixos/home-modules/profiles/darwin-home.nix`
3. **Module configs**: `/etc/nixos/home-modules/*/`

## Troubleshooting

**Problem**: "error: attribute 'osConfig' missing"
**Solution**: You're using the wrong profile. Use `--flake .#darwin` not `--flake .#vpittamp`

**Problem**: 1Password SSH not working
**Solution**: Enable SSH agent in 1Password → Settings → Developer → SSH agent

**Problem**: Package not available
**Solution**: Package may be Linux-only. Add to `home.packages` with platform check:
```nix
lib.optionals pkgs.stdenv.isLinux [ pkgs.linux-only-package ]
```

## Next Steps

1. **Install 1Password**: Download from 1password.com/downloads/mac
2. **Set up SSH**: Enable 1Password SSH agent
3. **Configure Git**: Verify 1Password integration
4. **Install Docker Desktop**: If using Docker/Kubernetes tools

## Full Documentation

See `/etc/nixos/docs/DARWIN_SETUP.md` for complete details.

---

*Apple M1 MacBook Pro (MacBookPro17,1; MYD92LL/A)*
