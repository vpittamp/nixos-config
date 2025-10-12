# 1Password Password Management

Automated user password synchronization from 1Password to NixOS systems.

## Overview

The `onepassword-password-management` module automatically syncs user passwords from 1Password to NixOS, eliminating the need for hardcoded passwords in configuration files.

**Features:**
- Fetches passwords securely from 1Password using service account
- Automatically generates password hashes using `mkpasswd`
- Syncs passwords on boot and hourly via systemd timer
- Supports multiple users with individual password references
- Falls back to `initialPassword` when 1Password is not configured

## NixOS Configuration (Hetzner, VMs)

### 1. Prerequisites

Ensure you have the 1Password service account configured:

```bash
sudo /etc/nixos/scripts/1password-setup-token.sh
```

This script:
1. Prompts you to sign in to your personal 1Password account
2. Fetches the service account token using the configured secret reference
3. Stores the token securely in `/var/lib/onepassword/service-account-token`

### 2. Create Password in 1Password

Create a password item in 1Password at the path you want to use. For example:
- Vault: `Employee`
- Item: `NixOS User Password`
- Field: `password`

Reference: `op://Employee/NixOS User Password/password`

### 3. Enable in Configuration

Add the module to your configuration and configure users:

```nix
{
  imports = [
    ../modules/services/onepassword-password-management.nix
  ];

  # Enable 1Password password management
  services.onepassword-password-management = {
    enable = true;
    users.vpittamp = {
      enable = true;
      passwordReference = "op://Employee/NixOS User Password/password";
    };
    updateInterval = "hourly";  # Options: hourly, daily, weekly
  };

  # Fallback password for initial setup before 1Password is configured
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";
}
```

### 4. Apply Configuration

```bash
sudo nixos-rebuild switch --flake .#hetzner
```

The module will:
1. Run initial password sync on system activation
2. Create systemd service and timer for ongoing syncs
3. Write password hash to `/run/secrets/vpittamp-password`
4. Configure user to use the password file

### 5. Verify Setup

```bash
# Check if password file was created
ls -l /run/secrets/vpittamp-password

# Check systemd service status
systemctl status onepassword-password-sync.service

# Check systemd timer status
systemctl status onepassword-password-sync.timer

# View sync logs
journalctl -u onepassword-password-sync.service

# Manually trigger sync (optional)
sudo systemctl start onepassword-password-sync.service
```

## macOS Configuration (M1/Intel)

**Important:** macOS uses a completely different user authentication system than Linux. 1Password password management for macOS users is not applicable because:

1. **macOS User Management:** macOS stores user passwords in keychain and uses system APIs for authentication
2. **NixOS Limitations:** NixOS on macOS (via nix-darwin) does not manage macOS user passwords
3. **1Password macOS App:** The 1Password macOS app already provides Touch ID and biometric authentication

### Alternative: 1Password CLI for macOS

On macOS, use 1Password CLI for secret management instead of password syncing:

```bash
# Install 1Password CLI
brew install --cask 1password-cli

# Sign in to your account
op signin

# Fetch secrets in shell scripts
PASSWORD=$(op read "op://Employee/NixOS User Password/password")
```

### Alternative: SSH Agent Integration

For remote access to NixOS machines from macOS, use 1Password's SSH agent:

1. **Enable in 1Password Settings:**
   - Open 1Password → Settings → Developer
   - Enable "Use the SSH agent"
   - Enable "Display key names when authorizing connections"

2. **Configure SSH Config (~/.ssh/config):**
   ```ssh
   Host nixos-hetzner
     HostName <server-ip>
     User vpittamp
     IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
   ```

3. **Store SSH Key in 1Password:**
   - Create new SSH key in 1Password
   - Add to NixOS server's `~/.ssh/authorized_keys`

4. **Connect:**
   ```bash
   ssh nixos-hetzner
   # 1Password will prompt for Touch ID
   ```

## Configuration Reference

### Module Options

```nix
services.onepassword-password-management = {
  enable = true;  # Enable password management

  users = {
    # Per-user configuration
    username = {
      enable = true;
      passwordReference = "op://Vault/Item/field";  # 1Password secret reference
    };
  };

  tokenReference = "op://Employee/Service Account Token/credential";  # Service account token reference
  updateInterval = "hourly";  # Sync frequency: hourly, daily, weekly, or custom systemd timer format
};
```

### Password Reference Format

1Password secret references use the format: `op://Vault/Item/Field`

Examples:
- `op://Employee/NixOS User Password/password`
- `op://Private/My Password/credential`
- `op://Shared/Team Credentials/password`

### Current Configurations

**Hetzner (`configurations/hetzner.nix`):**
```nix
services.onepassword-password-management = {
  enable = true;
  users.vpittamp = {
    enable = true;
    passwordReference = "op://Employee/NixOS User Password/password";
  };
};
```

**KubeVirt VM (`configurations/kubevirt-desktop.nix`):**
```nix
services.onepassword-password-management = {
  enable = true;
  users.nixos = {
    enable = true;
    passwordReference = "op://Employee/NixOS User Password/password";
  };
};
```

## Troubleshooting

### Password Not Syncing

1. **Check service account token:**
   ```bash
   ls -l /var/lib/onepassword/service-account-token
   ```

   If missing, run:
   ```bash
   sudo /etc/nixos/scripts/1password-setup-token.sh
   ```

2. **Check password sync service logs:**
   ```bash
   journalctl -u onepassword-password-sync.service -n 50
   ```

3. **Verify 1Password secret reference:**
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN="$(cat /var/lib/onepassword/service-account-token)"
   op read "op://Employee/NixOS User Password/password"
   ```

### Permission Denied on Login

1. **Check if password file exists:**
   ```bash
   sudo ls -l /run/secrets/vpittamp-password
   ```

2. **Manually trigger sync:**
   ```bash
   sudo systemctl start onepassword-password-sync.service
   ```

3. **Use fallback password:**
   If sync fails, `initialPassword` is still available. Check your configuration for the fallback password.

### Timer Not Running

```bash
# Check timer status
systemctl status onepassword-password-sync.timer

# Enable and start timer
sudo systemctl enable --now onepassword-password-sync.timer

# View timer schedule
systemctl list-timers --all | grep onepassword
```

## Security Considerations

1. **Service Account Token:**
   - Stored in `/var/lib/onepassword/service-account-token` with mode `0600`
   - Only root can read the token
   - Used only for automated secret retrieval

2. **Password Hashes:**
   - Stored in `/run/secrets/<username>-password` with mode `0600`
   - SHA-512 hashed passwords (never plaintext)
   - Ephemeral location (`/run` is tmpfs, cleared on reboot)

3. **Fallback Passwords:**
   - `initialPassword` is used only when password file doesn't exist
   - Allows system recovery if 1Password sync fails
   - Should be changed after initial setup

4. **Network Security:**
   - 1Password CLI uses HTTPS for all API calls
   - Service account tokens have limited permissions
   - Recommended: Use separate service accounts per environment

## Migration Guide

### From Hardcoded Passwords

**Before:**
```nix
users.users.vpittamp = {
  hashedPassword = "$6$rounds=656000$...";  # Hardcoded hash
};
```

**After:**
```nix
services.onepassword-password-management = {
  enable = true;
  users.vpittamp = {
    enable = true;
    passwordReference = "op://Employee/NixOS User Password/password";
  };
};

users.users.vpittamp.initialPassword = lib.mkDefault "nixos";  # Fallback only
```

### From Manual Password Files

**Before:**
```nix
users.users.vpittamp = {
  hashedPasswordFile = "/etc/secrets/vpittamp-password";
};
```

**After:**
```nix
services.onepassword-password-management = {
  enable = true;
  users.vpittamp = {
    enable = true;
    passwordReference = "op://Employee/NixOS User Password/password";
  };
};
```

The module automatically sets `hashedPasswordFile` to `/run/secrets/<username>-password`.

## Implementation Details

### File Locations

- Module: `/etc/nixos/modules/services/onepassword-password-management.nix`
- Service account token: `/var/lib/onepassword/service-account-token`
- Password hashes: `/run/secrets/<username>-password`
- Setup script: `/etc/nixos/scripts/1password-setup-token.sh`

### Systemd Units

- Service: `onepassword-password-sync.service` - Syncs passwords on demand
- Timer: `onepassword-password-sync.timer` - Schedules periodic syncs
- Activation: Runs on system activation to ensure passwords are available at boot

### Dependencies

- `pkgs._1password` - 1Password CLI for secret retrieval
- `pkgs.mkpasswd` - Password hashing utility
- Service account token from `onepassword-automation` module

## Related Documentation

- [1Password CLI Documentation](https://developer.1password.com/docs/cli)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts)
- [NixOS User Management](https://nixos.org/manual/nixos/stable/options.html#opt-users.users)
- [1Password Automation Module](/etc/nixos/modules/services/onepassword-automation.nix)
