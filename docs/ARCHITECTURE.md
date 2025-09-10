# NixOS Configuration Architecture

## Overview

This document describes the technical architecture of our modular NixOS configuration system, which supports multiple deployment targets while maintaining a single source of truth.

## Core Design Principles

### 1. Modular Composition
Instead of maintaining separate, complete configurations for each platform, we use a modular approach where:
- Common functionality is extracted into reusable modules
- Platform-specific configurations compose these modules
- Override mechanisms allow customization without duplication

### 2. Hetzner as Reference
The Hetzner configuration serves as our reference implementation because:
- It represents a full-featured NixOS installation
- It includes both server and desktop components
- It's deployed on standard x86_64 hardware
- It provides a complete development environment

### 3. Inheritance Hierarchy
Configuration follows a clear inheritance pattern:
```
Base Configuration
    ↓
Hardware Modules
    ↓
Service Modules
    ↓
Desktop Modules (optional)
    ↓
Target Configuration
```

## Module Structure

### Base Configuration (`configurations/base.nix`)
Provides fundamental settings shared across all targets:
- Core system packages
- Nix configuration (flakes, garbage collection)
- Basic networking
- User accounts
- Time zone and locale
- SSH configuration

### Hardware Modules (`hardware/`)
Platform-specific hardware configuration:

#### `hardware/hetzner.nix`
- QEMU/KVM virtualization support
- VirtIO drivers
- Cloud-optimized kernel parameters
- Virtual display configuration

#### `hardware/m1.nix`
- Apple Silicon specific drivers
- ARM64 optimizations
- Apple hardware integration

### Service Modules (`modules/services/`)

#### `development.nix`
Development tools and environments:
- Docker and container tools
- Programming languages (Node.js, Python, Go, Rust)
- Cloud CLIs (AWS, Azure, GCP)
- Database clients
- Build tools

#### `networking.nix`
Network services and tools:
- Tailscale VPN
- SSH hardening
- Firewall configuration
- Network diagnostic tools

#### `container.nix`
Container-specific services:
- VS Code Server support
- Nix development helpers
- Minimal service configuration

### Desktop Modules (`modules/desktop/`)

#### `kde-plasma.nix`
Full KDE Plasma 6 desktop:
- Wayland session
- KDE applications
- Display manager (SDDM)
- Audio (PipeWire)

#### `remote-access.nix`
Remote desktop capabilities:
- xrdp for RDP access
- VNC server
- Audio redirection
- Clipboard sharing

## Target Configurations

### WSL (`configurations/wsl.nix`)
Optimized for Windows Subsystem for Linux:
```nix
imports = [
  ./base.nix
  ../modules/services/development.nix
  ../home-manager/vpittamp.nix
];
```
- No desktop environment
- Docker Desktop integration
- VS Code Remote support
- Windows interop

### Hetzner (`configurations/hetzner.nix`)
Full-featured cloud workstation:
```nix
imports = [
  ./base.nix
  ../hardware/hetzner.nix
  ../modules/desktop/kde-plasma.nix
  ../modules/desktop/remote-access.nix
  ../modules/services/development.nix
  ../modules/services/networking.nix
];
```
- Complete desktop environment
- Remote access capabilities
- Full development stack

### M1 (`configurations/m1.nix`)
Apple Silicon optimized:
```nix
imports = [
  ./base.nix
  ../hardware/m1.nix
  ../modules/desktop/kde-plasma.nix
  ../modules/services/development.nix
];
```
- Native Apple hardware support
- ARM64 optimizations
- Local desktop environment

### Container (`configurations/container.nix`)
Minimal container base:
```nix
imports = [
  ../modules/services/container.nix
];
```
- Minimal footprint
- VS Code Server support
- Package profiles for size control

## Package Management

### Package Profiles
Defined in `shared/package-lists.nix`:

```nix
{
  minimal = [ /* ~100MB: core utilities */ ];
  essential = minimal ++ [ /* ~275MB: + dev basics */ ];
  development = essential ++ [ /* ~600MB: + languages */ ];
  full = development ++ [ /* ~1GB: + everything */ ];
}
```

### Package Hierarchy
1. **System packages** (`system/packages.nix`) - System-wide tools
2. **User packages** (`user/packages.nix`) - User-specific tools
3. **Module packages** - Defined within each module
4. **Override packages** - Platform-specific additions

## Home Manager Integration

Home-manager configuration is modular:
```
home-modules/
├── ai-assistants/   # AI CLI tools
├── editors/         # Neovim configuration
├── shell/           # Shell environment
├── terminal/        # Terminal tools
└── tools/           # Development utilities
```

Each module can be:
- Enabled/disabled independently
- Overridden per-platform
- Extended with additional configuration

## Override Mechanisms

### Priority Levels
NixOS uses priority levels for option resolution:

1. **`lib.mkDefault`** - Lowest priority, easily overridden
```nix
networking.hostName = lib.mkDefault "nixos";
```

2. **Normal assignment** - Standard priority
```nix
networking.hostName = "my-host";
```

3. **`lib.mkForce`** - Highest priority, forces value
```nix
networking.hostName = lib.mkForce "forced-name";
```

### Module Composition
Modules are composed using imports:
```nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ./base-module.nix
    ./extension-module.nix
  ];
  
  # Override specific options
  services.someService.enable = lib.mkForce false;
}
```

## Flake Structure

The `flake.nix` serves as the entry point:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    home-manager.url = "github:nix-community/home-manager";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      wsl = mkSystem { /* ... */ };
      hetzner = mkSystem { /* ... */ };
      m1 = mkSystem { /* ... */ };
    };
    
    packages = {
      container-minimal = mkContainer { /* ... */ };
      container-dev = mkContainer { /* ... */ };
    };
  };
}
```

## Build Process

### Configuration Resolution
1. Flake evaluates the target configuration
2. Imports are processed recursively
3. Options are merged with priority resolution
4. Final configuration is generated
5. Nix builds the system

### Optimization Strategies
- **Lazy evaluation** - Only evaluate what's needed
- **Shared derivations** - Reuse common build outputs
- **Binary caches** - Use pre-built packages when available
- **Minimal rebuilds** - Only rebuild changed components

## Testing Strategy

### Dry Builds
Always test with dry-build first:
```bash
sudo nixos-rebuild dry-build --flake .#<target>
```

### Staged Deployment
1. Test in container
2. Deploy to development environment
3. Deploy to production

### Rollback Capability
NixOS provides automatic rollback:
```bash
sudo nixos-rebuild switch --rollback
```

## Security Considerations

### SSH Hardening
- Key-only authentication by default
- Rate limiting
- Fail2ban integration

### Firewall
- Default deny policy
- Explicit port allowlisting
- Per-service rules

### Secret Management
- No secrets in configuration
- Environment variables for sensitive data
- Integration with secret management tools

## Performance Optimization

### Package Profiles
Choose appropriate profile for use case:
- Containers: `minimal` or `essential`
- Development: `development`
- Full workstation: `full`

### Service Management
- Disable unnecessary services
- Use systemd socket activation
- Lazy service startup

### Storage Optimization
- Garbage collection configured
- Store optimization scheduled
- Binary cache usage

## Future Enhancements

### Planned Improvements
1. **Secrets management** - Integration with sops-nix or agenix
2. **CI/CD pipeline** - Automated testing and deployment
3. **Custom packages** - Organization-specific tools
4. **Multi-user support** - Per-user configurations

### Extensibility Points
- Custom modules in `modules/custom/`
- Override sets in `overlays/`
- Local packages in `packages/`
- Scripts in `scripts/`

## Troubleshooting

### Common Issues

#### Module Conflicts
**Problem**: Option defined in multiple places
**Solution**: Use `lib.mkForce` or reorganize modules

#### Missing Dependencies
**Problem**: Package not found
**Solution**: Check nixpkgs version, add to appropriate module

#### Hardware Mismatch
**Problem**: Hardware configuration doesn't match system
**Solution**: Regenerate with `nixos-generate-config`

### Debug Commands
```bash
# Show configuration evaluation
nix eval .#nixosConfigurations.<target>.config.<option>

# Trace option definition
nixos-option <option>

# Show derivation details
nix show-derivation /run/current-system

# Check flake inputs
nix flake metadata
```

## Conclusion

This architecture provides:
- **Maintainability** through modular design
- **Flexibility** through composition and overrides
- **Consistency** through shared base configuration
- **Scalability** through clear extension points

The modular approach significantly reduces code duplication while allowing platform-specific customization where needed.