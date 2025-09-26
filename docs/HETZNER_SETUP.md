# Hetzner NixOS Setup with nixos-anywhere

## Overview
This document details the process of setting up a NixOS server on Hetzner Cloud using nixos-anywhere, including the integration of home-manager from our existing configuration.

## Server Information
- **IP Address**: 178.156.202.233
- **Location**: Hetzner Cloud
- **Branch**: `hetzner-nixos-anywhere` (vpittamp/nixos-config)
- **Installation Tool**: nixos-anywhere

## Initial Setup Process

### 1. Repository Preparation
We use a hybrid approach combining nixos-anywhere examples with our custom NixOS configuration:

```bash
# Clone nixos-anywhere-examples for base Hetzner configuration
git clone https://github.com/nix-community/nixos-anywhere-examples.git

# Our custom configuration is in vpittamp/nixos-config
# Branch: hetzner-nixos-anywhere
```

### 2. Remote Installation
The installation was performed using nixos-anywhere:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#hetzner-cloud \
  --target-host root@178.156.202.233
```

### 3. Configuration Repository Setup
After initial installation, we cloned our configuration to `/etc/nixos`:

```bash
ssh root@178.156.202.233
cd /etc
git clone -b hetzner-nixos-anywhere https://github.com/vpittamp/nixos-config.git nixos
cd nixos
```

## Home Manager Integration Issues and Solutions

### Problem 1: Firefox PWA Syntax Error

**Error Message**:
```
error: syntax error, unexpected ';', expecting end of file
at /nix/store/...-source/home-modules/profiles/base-home.nix:106:3
```

**Root Cause**: 
The Firefox Progressive Web Apps (PWAs) module had leftover closing braces after being disabled, causing a syntax error.

**Solution**:
```bash
# Comment out the stray closing braces in base-home.nix
sed -i '105,106s/^/# /' /etc/nixos/home-modules/profiles/base-home.nix
```

**Modified Lines** (base-home.nix:105-106):
```nix
#     pinToTaskbar = true;  # Pin them to KDE taskbar
#   };
```

### Problem 2: Headlamp Plugin Permission Errors

**Error Message**:
```
mkdir: cannot create directory '/home/vpittamp/.config/Headlamp': Permission denied
```

**Root Cause**: 
The Headlamp Kubernetes UI plugin configuration was trying to create directories during activation without proper permissions. The plugin installation process requires write access to user directories which conflicts with home-manager's declarative approach.

**Solution**:
```bash
# Remove existing Headlamp directories
rm -rf /home/vpittamp/.config/Headlamp /home/vpittamp/.local/share/Headlamp

# Comment out Headlamp imports in plasma-home.nix
sed -i 's|^.*headlamp.*$|    # &|' /etc/nixos/home-modules/profiles/plasma-home.nix
```

**Modified Lines** (plasma-home.nix):
```nix
    # ../apps/headlamp.nix
    # ../apps/headlamp-config.nix
```

### Problem 3: Home Directory Ownership Issues

**Error Message**:
```
mkdir: cannot create directory '/home/vpittamp/.config/bat': Permission denied
```

**Root Cause**: 
The home directory and its subdirectories were owned by root instead of the user, preventing home-manager from creating configuration files.

**Solution**:
```bash
# Fix ownership of entire home directory
chown -R vpittamp:users /home/vpittamp
```

### Problem 4: Understanding Service Status

**Initial Concern**:
The home-manager service showed as "inactive (dead)" after activation.

**Resolution**:
This is normal behavior. Home-manager uses a oneshot systemd service that:
1. Runs once to set up the environment
2. Exits with code 0 (SUCCESS)
3. Shows as "inactive (dead)" - this is expected

To verify successful activation:
```bash
systemctl status home-manager-vpittamp.service
# Look for: Main process exited, code=exited, status=0/SUCCESS
```

## Files Modified During Troubleshooting

1. **`/etc/nixos/home-modules/profiles/base-home.nix`**
   - Commented out Firefox PWA configuration remnants (lines 105-106)

2. **`/etc/nixos/home-modules/profiles/plasma-home.nix`**
   - Commented out Headlamp module imports

3. **Home directory permissions**
   - Changed ownership from root to vpittamp for `/home/vpittamp`

## Verification Steps

After applying fixes:

```bash
# Rebuild NixOS configuration
nixos-rebuild switch --flake /etc/nixos#hetzner

# Check home-manager service status
systemctl status home-manager-vpittamp.service

# Verify user can write to home directory
su - vpittamp -c "touch ~/.test && rm ~/.test"
```

## Managed vs Unmanaged Files

### Files Created by External Tools (Acceptable)
- **1Password CLI**: Creates files in `~/.config/op/`
- These don't interfere with home-manager and are acceptable

### Problematic Packages (Temporarily Disabled)
- **Firefox PWAs**: Syntax issues in configuration
- **Headlamp + Plugins**: Permission conflicts during activation

## Lessons Learned

1. **Incremental Approach**: When migrating complex configurations, disable problematic modules first and re-enable incrementally.

2. **Permission Issues**: Always verify home directory ownership before activating home-manager.

3. **Service Status**: Oneshot services showing "inactive (dead)" after SUCCESS is normal behavior.

4. **Configuration Validation**: Use `nixos-rebuild build` to validate configuration before switching.

5. **Module Conflicts**: Some applications (like Headlamp with plugins) may not be fully compatible with home-manager's declarative approach and require special handling.

## Future Improvements

1. **Firefox PWAs**: Properly integrate or fully remove PWA configuration
2. **Headlamp**: Investigate declarative plugin management or containerized deployment
3. **Automation**: Create scripts to automate the initial setup and troubleshooting process

## Related Documentation

- [Plasma Manager Setup](./PLASMA_MANAGER.md)
- [Avante Neovim Setup](./AVANTE_SETUP.md)
- [HomeKit Devices](./HOMEKIT_DEVICES.md)

## Commands Reference

```bash
# SSH to server
ssh root@178.156.202.233

# Rebuild system
nixos-rebuild switch --flake /etc/nixos#hetzner

# Check service logs
journalctl -u home-manager-vpittamp.service -f

# Test configuration without switching
nixos-rebuild build --flake /etc/nixos#hetzner
```