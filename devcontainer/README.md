# NixOS Devcontainer

This directory contains the base devcontainer configuration that integrates with NixOS home-manager.

## Structure

- `base/` - Base devcontainer files (Dockerfile, activation scripts)
- `templates/` - Example devcontainer configurations for projects

## Features

- **VS Code Server Compatibility**: Works with VS Code Remote SSH and devcontainers
- **Home-Manager Integration**: Automatically activates your NixOS home configuration
- **Dynamic User Support**: Works with any username (maps to appropriate home config)
- **Persistent Nix Store**: Caches packages between container restarts
- **GitHub Config Support**: Can pull NixOS configuration from GitHub

## Building the Base Image

```bash
cd devcontainer/base
./build-nixos-devcontainer.sh
```

This creates the `nixos-devcontainer:latest` image.

## Usage in Projects

1. Copy the appropriate template from `templates/` to your project's `.devcontainer/` directory
2. Customize the `devcontainer.json` as needed
3. Open in VS Code with the Dev Containers extension

## Environment Variables

- `NIXOS_CONFIG_ACTIVATE` - Set to "true" to activate home-manager on startup
- `NIXOS_CONFIG_GITHUB` - GitHub repo URL for your nixos-config (e.g., https://github.com/vpittamp/nixos-config)
- `NIXOS_PACKAGES` - Package set to use (e.g., "essential", "full")

## Requirements

- Docker
- VS Code with Dev Containers extension
- Your nixos-config repo must have a home configuration for the container user (default: "code")