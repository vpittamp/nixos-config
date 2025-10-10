# Hetzner Cloud CLI with 1Password Integration

**Status**: ✅ Configured
**Last Updated**: 2025-10-10
**Approach**: Official 1Password Shell Plugin

## Overview

The Hetzner Cloud CLI (`hcloud`) is configured to authenticate via 1Password shell plugins, providing secure biometric authentication for all hcloud operations including remote server reboots.

## Architecture

### How It Works

1. **1Password Plugin System**
   - `op plugin init hcloud` creates configuration in `~/.config/op/plugins/hcloud.json`
   - Generates alias in `~/.config/op/plugins.sh`
   - Stores reference to 1Password item (not the token itself)

2. **Home-Manager Integration**
   - `onepassword-plugins.nix` sources `~/.config/op/plugins.sh` in bash initExtra
   - NO direct .bashrc modification (declarative approach)
   - Plugin state managed by `op plugin init`, not by Nix

3. **Runtime Behavior**
   - Running `hcloud` command triggers `op plugin run -- hcloud`
   - 1Password prompts for biometric authentication
   - Token retrieved from vault and injected as `HCLOUD_TOKEN` environment variable
   - Command executes with authenticated token

## Setup (Already Complete ✅)

### Initial Configuration (One-Time)

```bash
# Initialize the hcloud plugin
op plugin init hcloud

# Follow prompts:
# 1. Select: "Hetzner Cloud API (CLI)" item from 1Password
# 2. Choose: "Use as global default on my system"
```

### What Gets Created

```bash
~/.config/op/
├── plugins/
│   ├── hcloud.json           # Plugin configuration
│   └── used_items/           # Plugin usage tracking
└── plugins.sh                # Shell aliases (sourced by home-manager)
```

## Best Practices ✅

### ✅ Correct Approach (What We Did)

1. **Declarative Home-Manager Configuration**
   ```nix
   # onepassword-plugins.nix
   programs.bash.initExtra = ''
     # Source 1Password shell plugins
     if [ -f "$HOME/.config/op/plugins.sh" ]; then
       source "$HOME/.config/op/plugins.sh"
     fi
   '';
   ```

2. **Plugin State Management**
   - Plugin configuration in `~/.config/op/plugins/` (user state)
   - Home-manager only sources the generated file
   - Separation of concerns: Nix manages config loading, 1Password manages secrets

3. **No Direct .bashrc Modification**
   - Home-manager controls bash configuration
   - Plugin files are user state, not system configuration

### ❌ Anti-Patterns (Avoided)

1. **Hardcoding tokens in Nix**
   ```nix
   # DON'T DO THIS
   sessionVariables.HCLOUD_TOKEN = "secret-token-here";
   ```

2. **Direct .bashrc modification**
   ```bash
   # DON'T DO THIS (what 1Password docs suggest)
   echo "source ~/.config/op/plugins.sh" >> ~/.bashrc
   ```

3. **Manual token retrieval functions**
   ```bash
   # DON'T DO THIS (old approach)
   hcloud() {
     HCLOUD_TOKEN=$(op read ...) command hcloud "$@"
   }
   ```

## Usage

### Daily Operations

```bash
# List servers (prompts for biometric auth)
hcloud server list

# Reboot server
hcloud server reboot nixos-hetzner

# Power operations
hcloud server poweroff nixos-hetzner
hcloud server poweron nixos-hetzner

# Get server details
hcloud server describe nixos-hetzner
```

### From Remote Machine

The same plugin can be configured on your local laptop:

```bash
# On your MacBook/laptop
op plugin init hcloud

# Then control Hetzner servers remotely
hcloud server reboot nixos-hetzner
```

## Reboot Workflow

### Recommended: Remote Reboot via hcloud

```bash
# From your local machine (laptop, etc.)
hcloud server reboot nixos-hetzner
```

**Advantages:**
- No RDP hang issues (you're not connected when reboot happens)
- Works from anywhere
- Secure (1Password biometric auth)
- Can verify server status before/after

### Alternative: Delayed Reboot from RDP

```bash
# From within RDP session
reboot-delayed   # 10-second countdown
```

Gives you time to disconnect RDP before reboot initiates.

## Security Model

### What's Stored Where

```
1Password Vault (Encrypted)
└── Hetzner Cloud API (CLI)
    └── token: hxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

~/.config/op/plugins/hcloud.json (Plain Text)
└── Reference to 1Password item
    ✅ NO secrets stored here
    ✅ Only item path: "Hetzner Cloud API (CLI)"

Environment (Runtime Only)
└── HCLOUD_TOKEN (Injected by op plugin run)
    ⏱️  Exists only during command execution
    🔒 Never written to disk
```

### Security Features

1. **Biometric Authentication**
   - Touch ID / Face ID / System password required
   - No persistent tokens in environment
   - Auto-locks after configured timeout

2. **No Plaintext Secrets**
   - Token never stored in config files
   - Not in environment variables (except during execution)
   - Not in shell history

3. **Audit Trail**
   - 1Password tracks all secret access
   - Can review usage in 1Password app

## Troubleshooting

### Plugin Not Working

```bash
# Check if plugin is initialized
ls ~/.config/op/plugins/hcloud.json

# Verify alias exists
grep hcloud ~/.config/op/plugins.sh

# Test plugin manually
op plugin run -- hcloud version
```

### Re-initialize Plugin

```bash
# Clear existing configuration
op plugin clear hcloud --all

# Re-initialize
op plugin init hcloud
```

### Check 1Password Item

```bash
# Verify the item exists
op item get "Hetzner Cloud API (CLI)"

# List all items
op item list
```

## Files Involved

### System Configuration (Managed by Nix)

- `/etc/nixos/home-modules/tools/onepassword-plugins.nix`
  - Sources `~/.config/op/plugins.sh`
  - Provides helper functions (`op-init`, `op-list`, etc.)

- `/etc/nixos/home-modules/shell/bash.nix`
  - Includes `reboot-delayed` and `reboot-now` aliases

### User State (Managed by 1Password)

- `~/.config/op/plugins.sh`
  - Generated by `op plugin init`
  - Contains: `alias hcloud="op plugin run -- hcloud"`

- `~/.config/op/plugins/hcloud.json`
  - Plugin configuration
  - References 1Password item

### 1Password Vault

- Item: "Hetzner Cloud API (CLI)"
  - Field: `token` (the actual API token)
  - Category: API Credential

## Helper Commands

### Provided by onepassword-plugins.nix

```bash
# Initialize a plugin
op-init hcloud

# List all plugins
op-list

# Inspect plugin configuration
op-inspect hcloud

# Clear plugin credentials
op-clear hcloud --all

# Shortened hcloud command
hc server list
```

## Migration Notes

### From Manual Token Approach

If you were previously using manual token retrieval:

```bash
# Old approach (removed)
hcloud() {
  HCLOUD_TOKEN=$(op read ...) command hcloud "$@"
}

# New approach (automatic)
# Just use: hcloud server list
# Plugin handles authentication automatically
```

### Adding to New Machine

```bash
# 1. Ensure 1Password CLI is configured
op whoami

# 2. Initialize hcloud plugin
op plugin init hcloud

# 3. Done! Home-manager will source it automatically
```

## References

- [1Password Shell Plugins Documentation](https://developer.1password.com/docs/cli/shell-plugins/)
- [hcloud Plugin Specific Docs](https://developer.1password.com/docs/cli/shell-plugins/hcloud/)
- [1Password CLI Reference](https://developer.1password.com/docs/cli/)

## See Also

- [ONEPASSWORD.md](./ONEPASSWORD.md) - 1Password integration overview
- [ONEPASSWORD_SSH.md](./ONEPASSWORD_SSH.md) - SSH key management with 1Password
- [CLAUDE.md](../CLAUDE.md) - Project overview and quick commands
