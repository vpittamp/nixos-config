# NixOS Configuration - LLM Navigation Guide

## 🚀 Quick Start

### Essential Commands

```bash
# Test configuration changes (ALWAYS RUN BEFORE APPLYING)
sudo nixos-rebuild dry-build --flake .#wsl    # For WSL
sudo nixos-rebuild dry-build --flake .#hetzner # For Hetzner
sudo nixos-rebuild dry-build --flake .#m1 --impure  # For M1 Mac (--impure for firmware)

# Apply configuration changes
sudo nixos-rebuild switch --flake .#wsl    # For WSL
sudo nixos-rebuild switch --flake .#hetzner # For Hetzner
sudo nixos-rebuild switch --flake .#m1 --impure  # For M1 Mac (--impure for firmware)

# Remote build/deploy from Codespace or another machine (requires SSH access)
nixos-rebuild switch --flake .#hetzner --target-host vpittamp@hetzner --use-remote-sudo

# Build container images
nix build .#container-minimal      # Minimal container (~100MB)
nix build .#container-dev          # Development container (~600MB)
```

## 📁 Directory Structure

```
/etc/nixos/
├── flake.nix                    # Entry point - defines all configurations
├── configuration.nix            # Current system configuration (symlink/import)
├── hardware-configuration.nix   # Auto-generated hardware config
│
├── configurations/              # Target-specific configurations
│   ├── base.nix                # Shared base configuration (from Hetzner)
│   ├── hetzner.nix             # Hetzner Cloud server config
│   ├── m1.nix                  # Apple Silicon Mac config
│   ├── wsl.nix                 # Windows Subsystem for Linux config
│   └── container.nix           # Container base configuration
│
├── hardware/                    # Hardware-specific configurations
│   ├── hetzner.nix             # Hetzner virtual hardware
│   └── m1.nix                  # Apple Silicon hardware
│
├── modules/                     # Reusable system modules
│   ├── desktop/
│   │   ├── kde-plasma.nix      # KDE Plasma 6 desktop
│   │   └── remote-access.nix   # RDP/VNC configuration
│   └── services/
│       ├── development.nix     # Dev tools (Docker, K8s, languages)
│       ├── networking.nix      # Network services (SSH, Tailscale)
│       ├── onepassword.nix     # 1Password integration (GUI/CLI)
│       └── container.nix       # Container-specific services
│
├── home-modules/                # User environment (home-manager)
│   ├── ai-assistants/          # Claude, Codex, Gemini CLI tools
│   ├── editors/                # Neovim with lazy.nvim
│   ├── shell/                  # Bash, Starship prompt
│   ├── terminal/               # Tmux, terminal tools
│   └── tools/                  # Git, SSH, developer utilities
│
├── shared/                      # Shared configurations
│   └── package-lists.nix       # Package profiles
│
├── system/                      # System-level packages
│   └── packages.nix            # System packages
│
├── user/                        # User-level packages
│   └── packages.nix            # User packages
│
├── scripts/                     # Utility scripts
└── docs/                        # Additional documentation
```

## 🏗️ Architecture Overview

### Configuration Hierarchy

```
1. Base Configuration (configurations/base.nix)
   ↓ Provides core settings
2. Hardware Module (hardware/*.nix)
   ↓ Adds hardware-specific settings
3. Service Modules (modules/services/*.nix)
   ↓ Adds optional services
4. Desktop Modules (modules/desktop/*.nix)
   ↓ Adds GUI if needed
5. Target Configuration (configurations/*.nix)
   ↓ Combines and customizes
6. Flake Output (flake.nix)
```

### Key Design Principles

1. **Hetzner as Base**: The Hetzner configuration serves as the reference implementation
2. **Modular Composition**: Each target combines only the modules it needs
3. **Override Hierarchy**: Use `lib.mkDefault` for overrideable defaults, `lib.mkForce` for mandatory settings
4. **Single Source of Truth**: Avoid duplication by extracting common patterns into modules

## 🎯 Configuration Targets

### WSL (Windows Subsystem for Linux)

- **Purpose**: Local development on Windows
- **Features**: Docker Desktop integration, VS Code support, 1Password CLI
- **Build**: `sudo nixos-rebuild switch --flake .#wsl`

### Hetzner (Cloud Server)

- **Purpose**: Remote development workstation
- **Features**: Full KDE desktop, RDP access, Tailscale VPN, 1Password GUI
- **Build**: `sudo nixos-rebuild switch --flake .#hetzner`

### M1 (Apple Silicon Mac - Asahi Linux)

- **Purpose**: Native NixOS on Apple hardware
- **Features**: Optimized for ARM64, Apple-specific drivers, Retina display support
- **Build**: `sudo nixos-rebuild switch --flake .#m1 --impure`
- **Note**: Requires `--impure` flag for Asahi firmware access

### Darwin (macOS with nix-darwin)

- **Purpose**: System configuration management for macOS
- **Features**: System packages, macOS preferences, home-manager integration, full dev environment
- **Build**: `sudo darwin-rebuild switch --flake .#darwin`
- **Note**: Replaces standalone home-manager with integrated nix-darwin + home-manager

### Containers

- **Purpose**: Minimal NixOS for Kubernetes/Docker
- **Profiles**: minimal, development, full
- **Build**: `nix build .#container-minimal`

## 📦 Package Management

### Package Profiles

Controlled by environment variables or module imports:

- `minimal` (~100MB): Core utilities only
- `essential` (~275MB): Basic development tools
- `development` (~600MB): Full development environment
- `full` (~1GB): Everything including K8s tools

### Adding Packages

1. **System-wide** - Edit appropriate module in `modules/services/`
2. **User-specific** - Edit `user/packages.nix`
3. **Target-specific** - Add to specific configuration in `configurations/`

## 🌐 PWA Management

### Installing PWAs

```bash
# Install all declared PWAs
pwa-install-all

# Update taskbar with PWA icons
pwa-update-panels

# Get PWA IDs for permanent pinning
pwa-get-ids

# List configured and installed PWAs
pwa-list
```

### Adding New PWAs

1. Edit `home-modules/tools/firefox-pwas-declarative.nix`
2. Add PWA definition with name, URL, and icon
3. Rebuild: `sudo nixos-rebuild switch --flake .#<target>`
4. Install: `pwa-install-all`
5. Update panels: `pwa-update-panels` or update `panels.nix` with IDs

## 🔧 Common Tasks

### Testing Changes

```bash
# ALWAYS test before applying
sudo nixos-rebuild dry-build --flake .#<target>

# Check for errors, then apply
sudo nixos-rebuild switch --flake .#<target>
```

### Building Containers

```bash
# Build specific container profile
nix build .#container-minimal
nix build .#container-dev

# Load into Docker
docker load < result

# Run container
docker run -it nixos-container:latest
```

### Updating Flake Inputs

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
```

## ⚠️ Important Notes

### Recent Updates (2025-09)

- **Migrated M1 MacBook Pro from X11 to Wayland** - Following Asahi Linux recommendations
  - Enabled Wayland in KDE Plasma 6 for better HiDPI and gesture support
  - Removed X11-specific workarounds and touchegg (Wayland has native gestures)
  - Updated environment variables for Wayland compatibility
  - Note: Experimental GPU driver options available if needed (see m1.nix comments)
- **Implemented Declarative PWA System** - Firefox PWAs with KDE integration
  - Declarative PWA configuration in `firefox-pwas-declarative.nix`
  - Automatic taskbar pinning with `panels.nix`
  - Custom icon support in `/etc/nixos/assets/pwa-icons/`
  - Helper commands: `pwa-install-all`, `pwa-update-panels`, `pwa-get-ids`
- Added comprehensive 1Password integration
- Fixed M1 display scaling and memory issues
- Implemented conditional module features (GUI vs headless)
- Added declarative Git signing configuration
- Fixed Hetzner configuration to properly import hardware-configuration.nix
- Re-enabled all home-manager modules after architecture isolation debugging
- Added GitHub CLI to development module

### Recent Consolidation (2024-09)

- Reduced from 46 to ~25 .nix files
- Removed 3,486 lines of duplicate code
- Hetzner configuration now serves as base
- Modular architecture for better maintainability

### Module Conventions

- Use `lib.mkDefault` for overrideable options
- Use `lib.mkForce` only when override is mandatory
- Always test with `dry-build` before applying
- Keep hardware-specific settings in `hardware/` modules

### Troubleshooting

1. **File system errors**: Ensure `hardware-configuration.nix` exists
2. **Package conflicts**: Check for deprecated packages (e.g., mysql → mariadb)
3. **Option deprecations**: Update to new option names (e.g., hardware.opengl → hardware.graphics)
4. **Build failures**: Run with `--show-trace` for detailed errors

## 📚 Additional Documentation

- `README.md` - Project overview and quick start
- `docs/ARCHITECTURE.md` - Detailed architecture documentation
- `docs/PWA_SYSTEM.md` - PWA (Progressive Web App) management system
- `docs/M1_SETUP.md` - Apple Silicon setup and troubleshooting
- `docs/DARWIN_SETUP.md` - macOS Darwin home-manager setup guide
- `docs/ONEPASSWORD.md` - 1Password integration guide
- `docs/ONEPASSWORD_SSH.md` - 1Password SSH and Git authentication guide
- `docs/HETZNER_NIXOS_INSTALL.md` - Hetzner installation guide
- `docs/AVANTE_SETUP.md` - Neovim AI assistant setup
- `docs/MIGRATION.md` - Migration from old structure

## 🔍 Quick Debugging

```bash
# Check current configuration
nixos-rebuild dry-build --flake .#<target> --show-trace

# List available configurations
nix flake show

# Check flake inputs
nix flake metadata

# Evaluate specific option
nix eval .#nixosConfigurations.<target>.config.<option>
```

## 🔐 1Password Commands

```bash
# Sign in to 1Password
op signin

# List vaults
op vault list

# List items
op item list

# Create SSH key
op item create --category="SSH Key" --title="My Key" --vault="Personal" --ssh-generate-key=ed25519

# Test SSH agent
SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l

# Use GitHub CLI with 1Password
gh auth status  # Uses 1Password token automatically
```

## 🍎 macOS Darwin (nix-darwin)

### nix-darwin System Management

For managing macOS system configuration with nix-darwin:

```bash
# Test configuration (dry-run)
nix run nix-darwin -- build --flake .#darwin

# Apply Darwin system configuration
sudo darwin-rebuild switch --flake .#darwin

# List generations
darwin-rebuild --list-generations

# Rollback to previous generation
darwin-rebuild rollback

# Update flake inputs
nix flake update
sudo darwin-rebuild switch --flake .#darwin
```

### What nix-darwin Manages

- **System Packages**: Installed in `/run/current-system/sw/bin`
- **macOS System Preferences**: Dock, Finder, keyboard, trackpad settings
- **SSH Configuration**: System-wide SSH config with 1Password integration
- **Home-Manager Integration**: User-level dotfiles and packages
- **Fonts**: System fonts (Nerd Fonts for terminals)

### Darwin-Specific Features

- **PATH**: System packages in `/run/current-system/sw/bin`, user packages in `/etc/profiles/per-user/$USER/bin`
- **1Password SSH**: Uses macOS-specific socket path (`~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`)
- **Git Signing**: Uses 1Password.app bundle for `op-ssh-sign` on Darwin
- **Development Tools**: Full dev environment (compilers, K8s tools, cloud CLIs)
- **Docker**: Works with Docker Desktop (install separately)

### Troubleshooting Darwin

**PATH not including system packages:**
- Reload shell: `exec bash -l`
- Check PATH: `echo $PATH | tr ':' '\n' | grep run`
- Verify packages: `ls /run/current-system/sw/bin`

**SSH config errors (spaces in path):**
- 1Password path must be quoted in SSH config
- Fixed automatically in `home-modules/tools/ssh.nix`

**Git signing fails:**
- On Darwin, uses `/Applications/1Password.app/Contents/MacOS/op-ssh-sign`
- Verify: `git config --get gpg.ssh.program`
- Test: `git commit --allow-empty -m "test" --gpg-sign`

**Colors not showing in terminal:**
- Check TERM: `echo $TERM` (should be `tmux-256color` or `xterm-256color`)
- Test colors: `tput colors` (should show 256)
- Verify Starship: `which starship && starship --version`

See `docs/DARWIN_SETUP.md` for detailed setup instructions.

---

_Last updated: 2025-10 with nix-darwin system management_
