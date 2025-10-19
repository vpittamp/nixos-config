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

### M1 (Apple Silicon Mac)

- **Purpose**: Native NixOS on Apple hardware
- **Features**: Optimized for ARM64, Apple-specific drivers, Retina display support
- **Build**: `sudo nixos-rebuild switch --flake .#m1 --impure`
- **Note**: Requires `--impure` flag for Asahi firmware access

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

## 🎯 Project Management Workflow

### Overview

The i3 window manager includes a project-scoped application workspace management system that allows you to:
- Switch between project contexts (NixOS, Stacks, Personal)
- Automatically show/hide project-specific applications
- Maintain global applications accessible across all projects
- Adapt workspace distribution across multiple monitors

### Quick Reference Keybindings

| Key | Action |
|-----|--------|
| `Win+P` | Open project switcher |
| `Win+Shift+P` | Clear active project (global mode) |
| `Win+C` | Launch VS Code in project context |
| `Win+Return` | Launch Ghostty terminal with sesh session |
| `Win+G` | Launch lazygit in project repository |
| `Win+Y` | Launch yazi file manager in project directory |
| `Win+Shift+M` | Manually trigger monitor detection/reassignment |

### Project-Scoped vs Global Applications

**Project-Scoped** (hidden when switching projects):
- Ghostty terminal (with sesh sessions)
- VS Code (opens project directory)
- Yazi file manager
- Lazygit

**Global** (always visible):
- Firefox browser
- YouTube PWA
- K9s
- Google AI PWA

### Common Workflows

**Start working on a project:**
```bash
# Press Win+P, select project from menu
# Or from command line:
~/.config/i3/scripts/project-set.sh nixos --switch
```

**Check current project:**
```bash
~/.config/i3/scripts/project-current.sh | jq -r '.name'
```

**Return to global mode:**
```bash
# Press Win+Shift+P
# Or from command line:
~/.config/i3/scripts/project-clear.sh
```

### Multi-Monitor Support

Workspaces automatically distribute based on monitor count:
- **1 monitor**: All workspaces on primary
- **2 monitors**: WS 1-2 on primary, WS 3-9 on secondary
- **3+ monitors**: WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary

After connecting/disconnecting monitors, press `Win+Shift+M` to reassign workspaces.

### Troubleshooting

**Applications not opening in project context:**
1. Check active project: `~/.config/i3/scripts/project-current.sh`
2. Verify project directory exists
3. Try clearing and reactivating: `Win+Shift+P` then `Win+P`

**Windows from old project still visible:**
1. Check polybar shows correct project
2. Manually run: `~/.config/i3/scripts/project-switch-hook.sh old_project new_project`

For more details, see the quickstart guide:
```bash
cat /etc/nixos/specs/011-project-scoped-application/quickstart.md
```

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

## 🍎 macOS Darwin Home-Manager

For using this configuration on macOS without NixOS:

```bash
# Apply Darwin home-manager configuration
home-manager switch --flake .#darwin

# Update packages
nix flake update
home-manager switch --flake .#darwin

# Test configuration
home-manager build --flake .#darwin
```

See `docs/DARWIN_SETUP.md` for detailed setup instructions for your M1 MacBook Pro.

---

_Last updated: 2025-10 with Darwin home-manager support_
