# NixOS Modular Configuration

A comprehensive, modular NixOS configuration supporting multiple platforms: WSL2, Hetzner Cloud, Apple Silicon Macs, and containers.

## 🎯 Overview

This repository contains a unified NixOS configuration that has been carefully architected to:
- **Eliminate duplication** through modular design
- **Support multiple platforms** with platform-specific optimizations
- **Provide consistent development environments** across all targets
- **Enable quick deployment** with pre-configured profiles

## 🚀 Quick Start

### Prerequisites
- NixOS installed (or WSL2 with NixOS)
- Git for cloning the repository
- Basic familiarity with Nix/NixOS

### Installation

1. **Clone the repository:**
```bash
git clone https://github.com/vpittamp/nixos-config /etc/nixos
cd /etc/nixos
```

2. **Choose your target platform:**

#### For WSL2 (Windows)
```bash
# Test the configuration
sudo nixos-rebuild dry-build --flake .#wsl

# Apply the configuration
sudo nixos-rebuild switch --flake .#wsl
```

#### For Hetzner Cloud
```bash
# Test the configuration
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply the configuration
sudo nixos-rebuild switch --flake .#hetzner
```

#### For Apple Silicon Mac
```bash
# Test the configuration (--impure required for firmware)
sudo nixos-rebuild dry-build --flake .#m1 --impure

# Apply the configuration
sudo nixos-rebuild switch --flake .#m1 --impure
```
> **Note**: The `--impure` flag is required for M1 builds to access Asahi Linux firmware.

#### For Containers
```bash
# Build minimal container
nix build .#container-minimal

# Load into Docker
docker load < result
```

## 🏗️ Architecture

The configuration follows a modular, hierarchical design:

```
┌─────────────────────────────────────┐
│          flake.nix                  │  ← Entry point
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│     configurations/*.nix            │  ← Target configs
│  (hetzner, m1, wsl, container)      │
└──────────────┬──────────────────────┘
               │ imports
┌──────────────▼──────────────────────┐
│     configurations/base.nix         │  ← Shared base
└──────────────┬──────────────────────┘
               │ imports
┌──────────────▼──────────────────────┐
│       hardware/*.nix                │  ← Hardware specs
└──────────────┬──────────────────────┘
               │ imports
┌──────────────▼──────────────────────┐
│      modules/services/*.nix         │  ← Services
│      modules/desktop/*.nix          │  ← Desktop envs
└─────────────────────────────────────┘
```

### Key Directories

- **`configurations/`** - Platform-specific configurations
- **`hardware/`** - Hardware-specific settings
- **`modules/`** - Reusable system modules
- **`home-modules/`** - User environment configuration (home-manager)
- **`shared/`** - Shared utilities and package lists
- **`scripts/`** - Utility and installation scripts
- **`docs/`** - Additional documentation

## 📦 Features

### Platform Support
- ✅ **WSL2** - Full integration with Windows, Docker Desktop support
- ✅ **Hetzner Cloud** - Remote workstation with KDE Plasma desktop
- ✅ **Apple Silicon** - Native NixOS on M1/M2 Macs
- ✅ **Containers** - Minimal NixOS for Docker/Kubernetes

### Development Tools
- **Languages**: Node.js, Python, Go, Rust, C/C++
- **Containers**: Docker, Kubernetes (kubectl, helm, k9s)
- **Cloud**: AWS CLI, Azure CLI, Google Cloud SDK, Terraform
- **Databases**: PostgreSQL, MariaDB, Redis, MongoDB tools
- **Editors**: Neovim with extensive configuration

### Desktop Environment (Hetzner/M1)
- KDE Plasma 6 with Wayland
- Remote access via RDP (xrdp)
- Tailscale VPN for secure connectivity
- Full development environment

### KDE Plasma Workflow
- System-level display manager, Qt/GPU services, and remote access live under `modules/desktop/kde-plasma.nix`, keeping session-critical pieces in the NixOS layer while user customisations stay in Home Manager, mirroring the approach recommended in the NixOS KDE guide. citeturn0search0
- User-scoped Plasma state is managed declaratively via Home Manager and `plasma-manager`, with `programs.plasma.overrideConfig = true;` so KDE rewrites its config at login instead of diverging per machine. Apply changes with `nix run home-manager/master -- switch --flake .#vpittamp`. citeturn0search1turn0search4
- To capture new tweaks made in a live session before refactoring them into modules, run `./scripts/plasma-rc2nix.sh > plasma-export.nix`. The helper wraps `plasma-manager rc2nix`, giving you a clean starting point for further declarative edits. citeturn0search4

### AI Assistant Integration
- Claude CLI (`claude-cli`)
- GitHub Copilot CLI (`gh copilot`)
- Gemini CLI
- Avante.nvim for in-editor AI assistance

### Security & Authentication
- **1Password Integration**: Centralized secret management
  - CLI and GUI support (GUI on desktop systems only)
  - SSH agent for key management
  - Git commit signing with SSH keys
  - GitHub/GitLab credential management
  - Automatic biometric authentication (where supported)

## 🔧 Configuration

### Adding Packages

1. **System-wide packages**: Edit the appropriate module in `modules/services/`
2. **User packages**: Edit `user/packages.nix`
3. **Platform-specific**: Add to the specific configuration in `configurations/`

### Testing Changes

Always test before applying:
```bash
sudo nixos-rebuild dry-build --flake .#<target>
```

### Updating Dependencies

```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
```

## 📚 Documentation

- **[CLAUDE.md](./CLAUDE.md)** - LLM-optimized navigation guide
- **[docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)** - Detailed architecture documentation
- **[docs/M1_SETUP.md](./docs/M1_SETUP.md)** - Apple Silicon setup guide and troubleshooting
- **[docs/ONEPASSWORD.md](./docs/ONEPASSWORD.md)** - 1Password integration guide
- **[docs/HETZNER_NIXOS_INSTALL.md](./docs/HETZNER_NIXOS_INSTALL.md)** - Hetzner installation guide
- **[docs/MIGRATION.md](./docs/MIGRATION.md)** - Migration from old structure
- **[docs/AVANTE_SETUP.md](./docs/AVANTE_SETUP.md)** - AI assistant setup for Neovim

## 🤝 Contributing

Contributions are welcome! Please:
1. Test changes with `nixos-rebuild dry-build`
2. Follow the existing modular structure
3. Document any new modules or features
4. Keep platform-specific code in appropriate directories

## 📄 License

This project is open source and available under the MIT License.

## 🙏 Acknowledgments

- NixOS community for the excellent documentation
- nixos-wsl project for WSL integration
- nixos-apple-silicon project for M1 support

---

**Repository**: [github.com/vpittamp/nixos-config](https://github.com/vpittamp/nixos-config)  
**Author**: Vinod Pittampalli  
**Last Updated**: September 2025
