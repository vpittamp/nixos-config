# macOS Darwin Home-Manager Setup Guide

This guide explains how to use the home-manager configuration on macOS (Darwin) with your Apple M1 MacBook Pro (Model: MacBookPro17,1; MYD92LL/A).

## Overview

The Darwin home-manager configuration provides a cross-platform user environment that works on macOS without requiring NixOS. It includes:

- Shell configuration (Bash, Starship prompt)
- Terminal tools (tmux, sesh)
- Development tools (Neovim, Git, SSH)
- AI assistants (Claude Code, Codex, Gemini CLI)
- 1Password integration
- Kubernetes tools (k9s, kubectl)
- Python/UV configuration

## Prerequisites

1. **Install Nix on macOS**: Follow the official Nix installation guide
   ```bash
   sh <(curl -L https://nixos.org/nix/install)
   ```

2. **Enable Flakes**: Add to `~/.config/nix/nix.conf`:
   ```
   experimental-features = nix-command flakes
   ```

3. **Clone this repository** (if not already available):
   ```bash
   git clone https://github.com/vpittamp/nixos-config.git ~/nixos-config
   cd ~/nixos-config
   ```

## Installation

### Option 1: Direct Home-Manager Installation

1. Install home-manager:
   ```bash
   nix run home-manager/master -- init --switch
   ```

2. Apply the Darwin configuration:
   ```bash
   cd /path/to/this/repo
   home-manager switch --flake .#darwin
   ```

### Option 2: Using nix-darwin (Recommended)

For full system management on macOS, consider using [nix-darwin](https://github.com/LnL7/nix-darwin) which provides NixOS-like system configuration for macOS:

1. Install nix-darwin (see nix-darwin documentation)
2. Integrate this home-manager configuration into your nix-darwin configuration
3. The darwin home-manager config can be imported in your nix-darwin flake

## Configuration Files

### Main Files

- `/etc/nixos/home-darwin.nix` - Main Darwin home-manager configuration
- `/etc/nixos/home-modules/profiles/darwin-home.nix` - Darwin-specific profile
- `/etc/nixos/home-modules/profiles/base-home.nix` - Shared base configuration

### What's Included

The Darwin configuration includes all cross-platform modules:

**Shell & Terminal:**
- Bash with custom configuration
- Starship prompt
- Tmux with enhanced keybindings
- Sesh session manager

**Development Tools:**
- Neovim with lazy.nvim
- Git with 1Password integration
- SSH with 1Password agent
- Direnv for environment management
- FZF for fuzzy finding
- Bat for syntax-highlighted cat

**AI Assistants:**
- Claude Code CLI
- Codex CLI
- Gemini CLI

**Cloud & Kubernetes:**
- kubectl
- k9s terminal UI
- Kubernetes helper scripts

**Other Tools:**
- Yazi file manager
- 1Password CLI and shell plugins
- Docker (requires Docker Desktop)

### What's Excluded (Linux-Only)

The following modules are excluded from the Darwin configuration as they're specific to Linux/KDE:

- KDE Plasma configuration
- Konsole terminal profiles
- KWallet configuration
- Firefox PWA system (Linux-specific implementation)
- XDG portal configurations
- Systemd user services
- RDP/VNC remote access

## Usage

### Switching Configurations

Apply changes after editing:
```bash
home-manager switch --flake .#darwin
```

### Updating Packages

Update flake inputs:
```bash
nix flake update
home-manager switch --flake .#darwin
```

### Testing Changes

Dry-build before applying:
```bash
home-manager build --flake .#darwin
```

## 1Password Integration

The Darwin configuration includes 1Password CLI integration:

1. **Install 1Password**: Download from [1Password website](https://1password.com/downloads/mac/)
2. **Enable 1Password CLI**: In 1Password settings, enable "Developer" → "Command Line Interface"
3. **SSH Agent**: Enable "Developer" → "Use the SSH agent"

The home-manager configuration will automatically configure:
- SSH to use 1Password agent
- Git to use 1Password for signing (if enabled)
- Shell plugins for 1Password CLI

## Customization

### User-Specific Settings

Edit `/etc/nixos/home-darwin.nix` to customize:
- Home directory path (default: `/Users/vpittamp`)
- Username (default: `vpittamp`)

### Adding macOS-Specific Packages

Edit `/etc/nixos/home-modules/profiles/darwin-home.nix` to add macOS-specific packages:

```nix
home.packages = with pkgs; [
  # Add macOS-specific packages here
  rectangle  # Window management
  mas        # Mac App Store CLI
];
```

### Enabling/Disabling Modules

Comment out unwanted imports in `/etc/nixos/home-modules/profiles/darwin-home.nix`:

```nix
imports = [
  # ../tools/docker.nix  # Disable if not using Docker Desktop
  # ../tools/kubernetes-apps.nix  # Disable if not using Kubernetes
];
```

## Architecture Details

### Profile Hierarchy

```
home-darwin.nix (main entry)
├── base-home.nix (shared shell, terminal, editor configs)
└── darwin-home.nix (Darwin-specific overrides)
    ├── Cross-platform tools
    └── Darwin-compatible settings
```

### Platform Detection

Some modules include platform detection:
```nix
# Example from gitkraken.nix
lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  # x86_64-specific configuration
}
```

For Darwin/macOS, use:
```nix
lib.mkIf pkgs.stdenv.isDarwin {
  # macOS-specific configuration
}
```

## Troubleshooting

### Issue: Module imports fail

**Problem**: Import errors about missing NixOS configurations

**Solution**: Ensure you're using the `darwin` home-manager configuration, not the NixOS ones:
```bash
home-manager switch --flake .#darwin  # Correct
home-manager switch --flake .#vpittamp  # Wrong - requires NixOS
```

### Issue: 1Password SSH agent not working

**Problem**: SSH can't find 1Password agent

**Solution**:
1. Verify 1Password SSH agent is enabled in 1Password settings
2. Check the socket path in `~/.ssh/config`:
   ```
   Host *
     IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
   ```

### Issue: Package not available on Darwin

**Problem**: Some Linux packages don't build on macOS

**Solution**: The configuration filters unavailable packages automatically. If you see errors, the package may need to be conditionally included:

```nix
home.packages = lib.optionals pkgs.stdenv.isLinux [
  pkgs.linux-only-package
] ++ [
  pkgs.cross-platform-package
];
```

### Issue: XDG directories not working

**Problem**: XDG base directories behave differently on macOS

**Solution**: macOS uses different paths by default:
- Config: `~/Library/Application Support/` instead of `~/.config/`
- Data: `~/Library/Application Support/` instead of `~/.local/share/`
- Cache: `~/Library/Caches/` instead of `~/.cache/`

The home-manager configuration sets up XDG directories for consistency, but native macOS apps may not respect them.

## Differences from Linux Configuration

| Feature | Linux (NixOS) | Darwin (macOS) |
|---------|---------------|----------------|
| **System Management** | NixOS modules | Homebrew/nix-darwin |
| **Desktop Environment** | KDE Plasma | Native macOS |
| **Terminal** | Konsole | Terminal.app/iTerm2 |
| **Service Management** | systemd | launchd |
| **SSH Agent** | systemd user service | 1Password/macOS keychain |
| **Package Manager** | Nix (system) | Nix + Homebrew |
| **XDG Base Directories** | Native support | Configured via home-manager |

## Next Steps

1. **Install nix-darwin**: For full system management similar to NixOS
2. **Configure Homebrew**: For GUI apps not available in nixpkgs
3. **Set up Mac App Store**: Use `mas` CLI for App Store apps
4. **Customize keybindings**: Adapt from Linux to macOS shortcuts

## Additional Resources

- [nix-darwin Documentation](https://github.com/LnL7/nix-darwin)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix on macOS](https://nixos.org/manual/nix/stable/installation/installing-binary.html#macos-installation)
- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)

## Support

For issues specific to this configuration:
1. Check the main `README.md` and `CLAUDE.md`
2. Review module-specific documentation in `home-modules/`
3. Consult the [nixpkgs manual](https://nixos.org/manual/nixpkgs/stable/) for package-specific issues

---

*Last updated: 2025-10 - Initial Darwin configuration for M1 MacBook Pro*
