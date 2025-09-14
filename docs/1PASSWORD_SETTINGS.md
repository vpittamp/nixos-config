# 1Password Settings Configuration

## Overview

1Password uses authenticated settings with HMAC tags to prevent tampering. This means settings cannot be fully configured declaratively through NixOS configuration files.

## Manual Configuration Required

The following settings must be configured manually through the 1Password GUI:

### Essential Settings

1. **CLI Integration** (Required for `op` command)
   - Open 1Password desktop app
   - Navigate to: Settings → Developer
   - Enable: "Integrate with 1Password CLI"
   - This allows the `op` command-line tool to communicate with the desktop app

2. **System Authentication** (Required for biometric/password unlock)
   - Navigate to: Settings → Security  
   - Enable: "Unlock using system authentication service"
   - This allows using system authentication (including KDE Wallet) instead of master password

3. **SSH Agent** (Optional, for Git authentication)
   - Navigate to: Settings → Developer
   - Enable: "Use SSH agent"
   - This allows using 1Password for SSH key management

## Settings Persistence

**Good news**: These settings persist across NixOS rebuilds!

- Settings are stored in: `~/.config/1Password/settings/settings.json`
- The file includes HMAC authentication tags that verify integrity
- Since it's in your home directory, it survives system rebuilds
- Settings are tied to your 1Password account, not the system

## Settings File Structure

```json
{
  "version": 1,
  "developers.cliSharedLockState.enabled": true,
  "security.authenticatedUnlock.enabled": true,
  "security.authenticatedUnlock.method": "systemAuthentication",
  "authTags": {
    // HMAC tags for each setting - DO NOT MODIFY
    "developers.cliSharedLockState.enabled": "YNC9lM0d82oPFywriRwYEP2NE/b1OxKJb1a0CARfwRA",
    "security.authenticatedUnlock.enabled": "fry5OQptry5wHJjTzdg7LcHUO3AmQ2QalPhBHMhd/6A"
  }
}
```

## Why Can't We Set These Declaratively?

1. **Security**: 1Password uses HMAC authentication tags to prevent unauthorized modification
2. **Account-specific**: Tags are generated using your account key
3. **Tamper protection**: Modified settings without valid tags are automatically reset

## Verification

To verify settings are enabled:

```bash
# Check CLI integration
op whoami

# Check if settings file exists
cat ~/.config/1Password/settings/settings.json | jq .

# Check specific settings
grep "cliSharedLockState" ~/.config/1Password/settings/settings.json
```

## Automation Attempts

We've configured the NixOS module to:
1. Create necessary directories
2. Display setup instructions on first run
3. Check for CLI integration on each activation

But the actual settings must be toggled manually in the GUI for security reasons.

## Related Files

- `/etc/nixos/home-modules/tools/onepassword.nix` - Main 1Password configuration
- `/etc/nixos/home-modules/tools/onepassword-autostart.nix` - Autostart service
- `/etc/nixos/home-modules/tools/onepassword-plugins.nix` - Shell plugin integration
- `~/.config/1Password/settings/settings.json` - Actual settings (user-managed)