# Azure CLI Troubleshooting

## Common Issues

### 1. MSAL NormalizedResponse Error

**Error:**
```
AttributeError: Can't get attribute 'NormalizedResponse' on <module 'msal.throttled_http_client'>
```

**Cause:**
This occurs when Azure CLI's cached authentication tokens were created with a newer version of the MSAL (Microsoft Authentication Library) than the current installation. The cache format is incompatible between versions.

**Solution:**
Clear the Azure CLI MSAL cache:

```bash
rm -rf ~/.azure/msal_*
```

Then try logging in again:
```bash
az login
```

### 2. SSL Certificate Errors (Python 3.13)

**Error:**
```
FileNotFoundError: [Errno 2] No such file or directory
```

In the traceback, you'll see references to SSL/certificate loading in the `requests` library.

**Cause:**
Python 3.13 changed how the `requests` library handles SSL certificates, causing Azure CLI from `nixos-unstable` (which uses Python 3.13) to fail.

**Solution:**
Our configuration uses a pinned version of Azure CLI from nixos-24.11 with Python 3.12 to avoid this issue. The package is defined in `packages/azure-cli-bin.nix`.

## Current Configuration

We maintain a custom `azure-cli-bin` package that:
- Uses nixos-24.11 (stable release)
- Provides Azure CLI 2.65.0
- Uses Python 3.12 (not 3.13)
- Includes MSAL 1.31.0

This configuration avoids:
- ✅ Python 3.13 SSL certificate issues
- ✅ MSAL version incompatibilities
- ✅ Breaking changes in unstable nixpkgs

## Version History

| Date | Azure CLI | Python | MSAL | Issues |
|------|-----------|--------|------|--------|
| 2025-10-07 | 2.65.0 | 3.12 | 1.31.0 | ✅ Working |
| 2025-09-07 | 2.60.0 | 3.11 | 1.28.0 | ❌ Cache incompatibility |

## When to Upgrade

Consider upgrading `azure-cli-bin` when:
1. A new stable NixOS release is available (e.g., 25.05)
2. Critical security updates are released for Azure CLI
3. You need features from a newer Azure CLI version

**Important:** After upgrading, all users must clear their Azure CLI cache:
```bash
rm -rf ~/.azure/msal_*
az login
```

## Testing After Changes

After modifying `packages/azure-cli-bin.nix`:

1. Rebuild the system:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

2. Clear the cache:
   ```bash
   rm -rf ~/.azure/msal_*
   ```

3. Test authentication:
   ```bash
   az login
   az account show
   ```

## Related Files

- `packages/azure-cli-bin.nix` - Custom Azure CLI package definition
- `modules/services/development.nix` - References azure-cli-bin
- `system/packages.nix` - Exports azure-cli-bin
