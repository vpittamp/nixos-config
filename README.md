# NixOS Unified Configuration Architecture

## Overview

This repository contains a unified NixOS configuration system that serves as a single source of truth for:
- **NixOS WSL2** system configuration
- **Docker containers** with customizable package profiles
- **VS Code devcontainers** for development environments
- **Home Manager** user environment configuration

The architecture eliminates configuration drift by using environment variables to control build variants from a single configuration base.

## Architecture Components

### Core Configuration Files

```
/etc/nixos/
├── configuration.nix          # Main NixOS configuration (WSL-aware)
├── configuration-base.nix     # Base configuration shared by containers
├── container-profile.nix      # Container-specific overrides
├── home-vpittamp.nix         # Home Manager user configuration
├── flake.nix                 # Flake definition for reproducible builds
├── flake.lock                # Locked dependencies
└── build-container.sh        # Helper script for building containers
```

### Package Management System

```
/etc/nixos/
├── overlays/
│   └── packages.nix          # Overlay system for package selection
└── packages/
    └── claude-manager-fetchurl.nix  # Custom package definitions
```

## Key Concepts

### 1. Environment Variable Control

The system uses two primary environment variables:

- **`NIXOS_CONTAINER`**: Determines if building for container (non-empty) or WSL (empty)
- **`NIXOS_PACKAGES`**: Controls which package groups to include

```bash
# Build for WSL (default)
nix build .#nixosConfigurations.nixos-wsl

# Build container with essential packages
NIXOS_CONTAINER=1 NIXOS_PACKAGES="essential" nix build .#container

# Build container with full packages
NIXOS_CONTAINER=1 NIXOS_PACKAGES="full" nix build .#container
```

### 2. Package Profiles

The overlay system (`overlays/packages.nix`) defines package groups:

| Profile | Size | Includes |
|---------|------|----------|
| `essential` | ~275MB | Core tools (git, vim, tmux, fzf, ripgrep, etc.) |
| `essential,kubernetes` | ~600MB | Core + K8s tools (kubectl, helm, k9s, argocd) |
| `essential,development` | ~600MB | Core + dev tools (nodejs, deno, docker-compose) |
| `full` | ~1GB | All packages |

### 3. Conditional Configuration

The main `configuration.nix` detects the build mode:

```nix
let
  isContainer = builtins.getEnv "NIXOS_CONTAINER" != "";
in
{
  # Container mode
  boot.isContainer = lib.mkIf isContainer true;
  
  # WSL mode (only when not container)
  wsl = lib.mkIf (!isContainer) {
    enable = true;
    defaultUser = "vpittamp";
    # ... WSL-specific settings
  };
}
```

## Home Manager Integration

### Configuration Structure

Home Manager is integrated through `home-vpittamp.nix`, which includes:

```nix
{
  # Package management using overlay system
  home.packages = let
    overlayPackages = import ./overlays/packages.nix { inherit pkgs lib; };
  in
    overlayPackages.allPackages;

  # Program configurations
  programs = {
    bash = { ... };      # Shell configuration
    git = { ... };       # Git settings
    tmux = { ... };      # Terminal multiplexer
    starship = { ... };  # Shell prompt
    fzf = { ... };       # Fuzzy finder
    zoxide = { ... };    # Smart directory navigation
  };

  # Dotfiles via xdg.configFile
  xdg.configFile = {
    "sesh/sesh.toml" = { ... };  # Session manager config
    # Other dotfiles...
  };
}
```

### Key Features

1. **Unified Package Management**: Packages defined once, used everywhere
2. **Dotfile Management**: Declarative configuration files
3. **Shell Aliases**: Consistent command shortcuts
4. **Program Settings**: Centralized tool configurations

## Building Containers

### Using the Build Script

The `build-container.sh` script simplifies container building:

```bash
# Build standard container
./build-container.sh essential output.tar.gz
./build-container.sh full

# Build devcontainer
./build-container.sh --devcontainer development
./build-container.sh -d -p /my/project full
```

### Manual Building

```bash
# Build container with Nix
cd /etc/nixos
NIXOS_CONTAINER=1 NIXOS_PACKAGES="essential" nix build .#container

# Load into Docker
docker load < result

# Run container
docker run -it nixos-system:latest /bin/bash
```

### Devcontainer Support

The system can create VS Code devcontainers:

1. **Automatic Configuration**: Creates `.devcontainer/devcontainer.json` if missing
2. **VS Code Integration**: Includes recommended extensions and settings
3. **Volume Mounting**: Automatically mounts project directory to `/workspace`

Example devcontainer.json:
```json
{
  "name": "NixOS Development Container",
  "image": "nixos-devcontainer:development",
  "customizations": {
    "vscode": {
      "extensions": [
        "jnoortheen.nix-ide",
        "ms-vscode.cpptools",
        "ms-python.python"
      ]
    }
  },
  "workspaceFolder": "/workspace",
  "remoteUser": "root"
}
```

## Flake Structure

The `flake.nix` defines:

### Inputs
```nix
{
  nixpkgs         # Core packages
  nixos-wsl       # WSL support
  home-manager    # User environment
  onepassword-shell-plugins  # 1Password integration
  flake-utils     # Helper utilities
}
```

### Outputs

1. **NixOS Configuration** (`nixosConfigurations.nixos-wsl`)
   - Full WSL2 system configuration
   - Includes Home Manager as a module

2. **Container Package** (`packages.${system}.container`)
   - Builds Docker images from NixOS configuration
   - Uses `configuration-base.nix` + `container-profile.nix`

3. **Development Shells** (`devShells.${system}`)
   - Nix development environments
   - Kubernetes development setup

## Overlay System

The overlay system (`overlays/packages.nix`) provides:

### Package Group Selection
```nix
packageSelection = builtins.getEnv "NIXOS_PACKAGES";
selectedGroups = if packageSelection == "" then [ "essential" ]
                else if packageSelection == "full" then [ "essential" "kubernetes" "development" "extras" ]
                else lib.splitString "," packageSelection;
```

### Custom Package Definitions
- `claude-manager`: Session management tool (fetched from GitHub releases)
- `idpbuilder`: IDP builder tool
- `sesh`: Tmux session manager

### Dynamic Package Inclusion
```nix
essential = with pkgs; [ tmux git vim neovim fzf ripgrep ... ];
kubernetes = if includeGroup "kubernetes" then with pkgs; [ kubectl helm k9s ... ] else [];
development = if includeGroup "development" then with pkgs; [ nodejs deno ... ] else [];
```

## WSL-Specific Features

When running in WSL mode (`!isContainer`):

1. **Docker Desktop Integration**
   - Auto-generated `docker-wrapper.sh` for Docker Desktop proxy
   - Symlinked to `/usr/local/bin/docker`

2. **VS Code Remote Server Fix**
   - Automatic Node.js path correction for VS Code server

3. **Windows Integration**
   - Clipboard integration via `clip.exe`
   - WSL utilities (`wslu`) for Windows interop
   - VS Code launcher wrapper

4. **Mount Configuration**
   - Windows drives mounted at `/mnt`
   - Proper file permissions via metadata

## Usage Examples

### Daily Development (WSL)
```bash
# Rebuild system after configuration changes
sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl

# Update flake inputs
nix flake update

# Check configuration
nix flake check
```

### Container Development
```bash
# Build minimal container for CI/CD
NIXOS_CONTAINER=1 NIXOS_PACKAGES="essential" nix build .#container

# Build development container
./build-container.sh --devcontainer development

# Test container locally
docker run -it -v $(pwd):/workspace nixos-devcontainer:development
```

### Package Management
```bash
# Add packages to essential group in overlays/packages.nix
# Then rebuild:
sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl

# Test different package combinations
NIXOS_PACKAGES="essential,kubernetes" nix build .#container
```

## Benefits of This Architecture

1. **Single Source of Truth**: One configuration for all deployment targets
2. **No Configuration Drift**: Container and WSL use same base configuration
3. **Flexible Package Selection**: Environment variables control what's included
4. **Reproducible Builds**: Flake lock ensures consistent dependencies
5. **Minimal Container Sizes**: From 275MB to 1GB depending on needs
6. **Developer Friendly**: Easy devcontainer creation for VS Code
7. **Declarative Configuration**: Everything defined in Nix, version controlled

## Maintenance

### Adding New Packages
1. Edit `overlays/packages.nix`
2. Add to appropriate group (essential, kubernetes, development, extras)
3. Rebuild and test

### Updating Dependencies
```bash
cd /etc/nixos
nix flake update
sudo nixos-rebuild switch --flake .#nixos-wsl
```

### Creating Custom Packages
1. Add package definition to `/etc/nixos/packages/`
2. Reference in `overlays/packages.nix`
3. Include in appropriate package group

## Troubleshooting

### Container Build Fails
- Check environment variables: `echo $NIXOS_CONTAINER $NIXOS_PACKAGES`
- Verify flake: `nix flake check`
- Build with trace: `nix build .#container --show-trace`

### WSL Integration Issues
- Ensure Docker Desktop is running on Windows
- Check WSL2 is enabled: `wsl --status`
- Verify mount points: `ls /mnt/c`

### Package Not Found
- Verify package is in correct group in `overlays/packages.nix`
- Check environment variable includes the group
- Rebuild with correct profile

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes and test both WSL and container builds
4. Submit pull request with clear description

## License

This configuration is provided as-is for reference and reuse. Adapt as needed for your environment.