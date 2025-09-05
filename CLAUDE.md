# NixOS Configuration - LLM Navigation Guide

## 🚀 Quick Start

### Essential Commands
```bash
# Test configuration changes (ALWAYS RUN BEFORE APPLYING)
cd /etc/nixos && sudo nixos-rebuild dry-build

# Apply configuration changes
sudo nixos-rebuild switch

# Build container image
cd /etc/nixos && nix build .#container

# Install home-manager configuration in container
home-manager switch --flake github:PittampalliOrg/nix-config#container-essential
```

### Key Files
- `configuration.nix` - Main NixOS system configuration
- `home-vpittamp.nix` - User environment (works in WSL & containers)
- `flake.nix` - Reproducible builds & container definitions
- `container-services.nix` - SSH, VS Code Server, Nix helpers
- `shared/package-lists.nix` - Package profiles (minimal/essential/full)

## 📁 Directory Structure

```
/etc/nixos/                      # Root configuration directory
├── configuration.nix            # Main system config (imports container-profile if needed)
├── container-base.nix           # Base container configuration
├── container-profile.nix        # Container-specific overrides
├── container-services.nix       # Consolidated container services (SSH, VS Code, Nix)
├── flake.nix                    # Flake with WSL & container outputs
├── home-vpittamp.nix            # Unified home-manager config
├── home-modules/                # Modular home-manager configurations
│   ├── ai-assistants/           # Claude Code, Codex, Gemini CLI
│   ├── editors/                 # Neovim with lazy.nvim (runtime plugins)
│   ├── shell/                   # Bash, Starship prompt
│   ├── terminal/                # Tmux, Sesh
│   └── tools/                   # Git, SSH, Bat, Direnv, FZF, Yazi
├── shared/                      # Shared utilities
│   └── package-lists.nix        # Package profile definitions
├── system/                      # System-level packages
│   └── packages.nix             # System packages (Docker, K8s, dev tools)
└── user/                        # User-level packages
    └── packages.nix             # User packages (CLI tools, utilities)
```

## 🎯 Architecture Overview

### Unified Configuration
- **Single source**: Same configuration for WSL and containers
- **Environment detection**: Automatically adapts based on context
- **No sudo required**: Home-manager works in restricted containers
- **Runtime plugins**: Neovim uses lazy.nvim (no Nix plugin builds)

### Package Profiles
Controlled by `NIXOS_PACKAGES` environment variable:
- `minimal` (~100MB): Core utilities only
- `essential` (~275MB): Development basics
- `development` (~600MB): Full dev tools
- `full` (~1GB): Everything including K8s tools

### Container vs WSL Mode
- **WSL**: Full system with Docker Desktop integration
- **Container**: Minimal base with selected packages
- Detection: `isContainer = builtins.getEnv "NIXOS_CONTAINER" != "";`

## 📝 Common Tasks

### Adding Packages

1. **For all environments** - Edit `user/packages.nix`:
```nix
utilityTools = with pkgs; [
  existing-package
  your-new-package  # Add here
];
```

2. **For containers only** - Edit `container-profile.nix`:
```nix
environment.systemPackages = lib.mkForce (with pkgs; [
  # ... existing packages
  your-new-package
]);
```

3. **For home-manager** - Edit relevant module in `home-modules/`:
```nix
home.packages = with pkgs; [
  your-new-package
];
```

### Testing Changes
```bash
# ALWAYS test before applying
cd /etc/nixos && sudo nixos-rebuild dry-build

# Check for errors, then apply
sudo nixos-rebuild switch
```

### Building Containers
```bash
# Build with specific profile
NIXOS_CONTAINER=1 NIXOS_PACKAGES="essential" nix build .#container

# Load into Docker
docker load < result

# Run container
docker run -it nixos-container:latest
```

## ⚠️ Important Context

### Recent Cleanup (Sep 2025)
- Reduced from 48 to 24 .nix files
- Removed 2,674 lines of unused code
- Consolidated container services into single file
- Deleted: devcontainer/, scripts/, overlays/, packages/

### Design Decisions
1. **No Nix plugins**: Use lazy.nvim for runtime loading
2. **No colors module**: Catppuccin Mocha embedded directly
3. **Unified home-manager**: Same config for WSL & containers
4. **Minimal container base**: Only essential packages

### Key Modules
- **container-services.nix**: Merged SSH + VS Code + Nix helpers
- **shared/package-lists.nix**: Central package profile logic
- **home-modules/**: Modular user environment configs

## 🔧 Best Practices

### DO:
- ✅ Always run `nixos-rebuild dry-build` before applying changes
- ✅ Test in container before applying to WSL
- ✅ Use package profiles for size control
- ✅ Keep configurations modular
- ✅ Commit working configurations

### DON'T:
- ❌ Modify without testing
- ❌ Add packages requiring sudo in containers
- ❌ Use Nix plugin system (use lazy.nvim)
- ❌ Create duplicate configurations
- ❌ Ignore build warnings

## 🎭 Working with Home-Manager

### In Containers
```bash
# Install from GitHub (no sudo needed)
home-manager switch --flake github:PittampalliOrg/nix-config#container-essential

# Or for development profile
home-manager switch --flake github:PittampalliOrg/nix-config#container-development
```

### In WSL
```bash
# Already integrated via configuration.nix
sudo nixos-rebuild switch
```

## 📊 Container Profiles

| Profile | Command | Size | Includes |
|---------|---------|------|----------|
| Minimal | `container-minimal` | ~100MB | Core utils |
| Essential | `container-essential` | ~275MB | Dev basics |
| Development | `container-development` | ~600MB | Node, Python, Go |
| AI Tools | `container-ai` | ~400MB | Essential + AI assistants |

## 🔍 Debugging

### Check current environment
```bash
# In container
echo $NIXOS_PACKAGES
echo $CONTAINER_PROFILE

# Check if in container
[[ -f /.dockerenv ]] && echo "In container" || echo "Not in container"
```

### View package list
```bash
# System packages
nix-store -q --requisites /run/current-system | wc -l

# User packages
home-manager packages | grep -c '^'
```

## 📚 Additional Documentation

- `docs/README.md` - Detailed architecture overview
- `docs/ARCHITECTURE.md` - System diagrams and flows
- GitHub: https://github.com/PittampalliOrg/nix-config

---
*Last updated: September 2025 after major cleanup (48→24 files)*