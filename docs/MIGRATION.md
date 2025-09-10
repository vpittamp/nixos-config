# Migration Guide: From Duplicate Configurations to Modular Architecture

## Overview

This guide documents the major consolidation effort completed in September 2025 that transformed our NixOS configuration from a fragmented, duplicate-heavy structure into a clean, modular architecture.

## Migration Summary

### Before: 46 Files, 3,486 Lines of Duplication
- Separate complete configurations for each platform
- Extensive code duplication across targets
- Difficult to maintain consistency
- No clear inheritance hierarchy

### After: ~25 Files, Modular Architecture
- Single source of truth with modular composition
- 45% reduction in file count
- Clear inheritance and override patterns
- Hetzner configuration as the reference base

## Key Changes

### 1. Directory Structure Reorganization

#### Old Structure
```
/etc/nixos/
├── configuration-hetzner.nix          # Full config
├── configuration-hetzner-desktop.nix  # More full config
├── configuration-m1.nix                # Another full config
├── configuration-wsl.nix               # Yet another full config
├── home-vpittamp.nix                   # Duplicated across platforms
├── home-m1.nix                         # Platform-specific duplicate
└── ... (many more duplicates)
```

#### New Structure
```
/etc/nixos/
├── configurations/          # Target-specific configs
│   ├── base.nix            # Shared base (extracted from Hetzner)
│   ├── hetzner.nix         # Composed from modules
│   ├── m1.nix              # Composed from modules
│   ├── wsl.nix             # Composed from modules
│   └── container.nix       # Minimal container config
├── hardware/               # Hardware-specific modules
│   ├── hetzner.nix        # Cloud VM optimizations
│   └── m1.nix             # Apple Silicon support
├── modules/                # Reusable service modules
│   ├── desktop/           # Desktop environments
│   │   ├── kde-plasma.nix
│   │   └── remote-access.nix
│   └── services/          # System services
│       ├── development.nix
│       ├── networking.nix
│       └── container.nix
└── home-modules/          # Home-manager modules
```

### 2. Configuration Inheritance

The new architecture follows a clear inheritance pattern:

```
Base Configuration (configurations/base.nix)
    ↓ imports
Hardware Module (hardware/*.nix)
    ↓ imports
Service Modules (modules/services/*.nix)
    ↓ imports (optional)
Desktop Modules (modules/desktop/*.nix)
    ↓ composes into
Target Configuration (configurations/*.nix)
```

### 3. Files Removed

The following files were deleted as part of the consolidation:

- `configuration-hetzner.nix` → Replaced by modular `configurations/hetzner.nix`
- `configuration-hetzner-desktop.nix` → Merged into desktop module
- `configuration-m1.nix` → Replaced by modular `configurations/m1.nix`
- `configuration-wsl.nix` → Replaced by modular `configurations/wsl.nix`
- `home-vpittamp.nix` → Moved to `home-manager/vpittamp.nix`
- `home-m1.nix` → Consolidated into single home config
- Various test and backup files

### 4. Package Migrations

#### Qt5 to Qt6
All KDE packages were migrated from Qt5 to Qt6:
```nix
# Old
pkgs.kate
pkgs.xdg-desktop-portal-kde

# New
pkgs.kdePackages.kate
pkgs.kdePackages.xdg-desktop-portal-kde
```

#### MySQL to MariaDB
```nix
# Old
pkgs.mysql

# New
pkgs.mariadb
```

#### Deprecated Options
```nix
# Old
hardware.opengl.driSupport = true;

# New
hardware.graphics.enable = true;
```

## Migration Steps for Existing Systems

### Step 1: Backup Current Configuration
```bash
cd /etc/nixos
git add -A
git commit -m "Backup before migration"
git push
```

### Step 2: Fetch New Configuration
```bash
# Fetch the new modular configuration
git fetch origin main
git checkout main
```

### Step 3: Update Hardware Configuration
```bash
# Generate fresh hardware config
sudo nixos-generate-config

# Compare with the appropriate hardware module
diff hardware-configuration.nix hardware/[your-platform].nix

# Keep generated UUIDs but use module optimizations
```

### Step 4: Choose Your Target
```bash
# For Hetzner Cloud
sudo nixos-rebuild switch --flake .#hetzner

# For Apple Silicon Mac
sudo nixos-rebuild switch --flake .#m1

# For WSL2
sudo nixos-rebuild switch --flake .#wsl

# For containers
nix build .#container-minimal
```

### Step 5: Verify Services
```bash
# Check system status
systemctl status

# Verify key services
systemctl status sshd
systemctl status display-manager  # If using desktop
systemctl status xrdp            # If using remote desktop
```

## Common Migration Issues

### Issue 1: Conflicting Options
**Problem**: Options defined in multiple places with different values

**Solution**: Use override priorities:
```nix
# In your target configuration
networking.hostName = lib.mkForce "my-hostname";
```

### Issue 2: Missing Packages
**Problem**: Package that was in old config is missing

**Solution**: Add to appropriate module:
- System-wide: Add to `modules/services/development.nix`
- User-specific: Add to `home-modules/`
- Platform-specific: Add to target configuration with `lib.mkForce`

### Issue 3: Build Failures
**Problem**: Build fails with "attribute not found"

**Solution**: Check for package renames:
- Qt5 packages → `kdePackages.*`
- mysql → mariadb
- Hardware options may have changed

### Issue 4: Home-Manager Conflicts
**Problem**: Home-manager configuration conflicts with system

**Solution**: Ensure home-manager is integrated properly in flake:
```nix
home-manager.nixosModules.home-manager
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.vpittamp = import ../home-manager/vpittamp.nix;
}
```

## Benefits of New Architecture

### 1. Reduced Maintenance
- Single place to update common functionality
- Changes propagate to all targets automatically
- Less chance of configuration drift

### 2. Clear Override Hierarchy
```nix
lib.mkDefault  # Lowest priority - easily overridden
(no modifier)  # Normal priority
lib.mkForce    # Highest priority - forces value
```

### 3. Platform Flexibility
Each platform can:
- Import only needed modules
- Override specific settings
- Add platform-specific packages
- Maintain unique hardware configurations

### 4. Better Testing
```bash
# Test changes without applying
sudo nixos-rebuild dry-build --flake .#target

# Build in VM for testing
nixos-rebuild build-vm --flake .#target
```

## Rollback Procedure

If issues occur after migration:

### Immediate Rollback
```bash
# Roll back to previous generation
sudo nixos-rebuild switch --rollback
```

### Git Rollback
```bash
# Revert to old configuration
git checkout <old-commit>
sudo nixos-rebuild switch
```

### Selective Rollback
```bash
# Keep new structure but revert specific module
git checkout <old-commit> -- modules/problematic-module.nix
sudo nixos-rebuild switch --flake .#target
```

## Future Considerations

### Planned Improvements
1. **Secrets Management**: Integration with sops-nix or agenix
2. **CI/CD Pipeline**: Automated testing of configurations
3. **Custom Overlays**: Organization-specific package modifications
4. **Multi-user Support**: Per-user home-manager configurations

### Best Practices Going Forward
1. **Always test changes**: Use `dry-build` before applying
2. **Use modules**: Don't add to target configs unless platform-specific
3. **Document overrides**: Comment why `lib.mkForce` is used
4. **Maintain hierarchy**: Respect the module inheritance pattern
5. **Version control**: Commit working configurations immediately

## Module Development Guide

### Creating a New Module
```nix
# modules/services/my-service.nix
{ config, lib, pkgs, ... }:
{
  # Module options (optional)
  options.services.myService = {
    enable = lib.mkEnableOption "my service";
  };

  # Module configuration
  config = lib.mkIf config.services.myService.enable {
    environment.systemPackages = with pkgs; [
      # packages
    ];
    
    # Other configuration
  };
}
```

### Adding to Target
```nix
# configurations/hetzner.nix
{
  imports = [
    ./base.nix
    ../modules/services/my-service.nix  # Add here
  ];
  
  services.myService.enable = true;  # Enable if needed
}
```

## Conclusion

This migration represents a significant improvement in maintainability and clarity. The modular architecture provides:

- **45% reduction** in file count
- **Clear separation** of concerns
- **Single source of truth** for common functionality
- **Platform flexibility** without duplication
- **Easier testing** and deployment

For questions or issues with the migration, refer to:
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Technical deep dive
- [README.md](../README.md) - Project overview
- [CLAUDE.md](../CLAUDE.md) - LLM navigation guide

---

*Migration completed: September 2025*  
*Previous structure: 46 files, fragmented*  
*New structure: ~25 files, modular*  
*Code reduction: 3,486 lines eliminated*