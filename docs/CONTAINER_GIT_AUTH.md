# Container Git Authentication with 1Password

This guide explains how to use Git authentication in containers using 1Password Service Accounts.

## Why Service Accounts?

Container environments can't use the 1Password desktop app (no GUI), so we use **Service Account tokens** instead:

- ✅ No desktop app required
- ✅ Works in minimal containers
- ✅ Secure and auditable
- ✅ Can be scoped to specific vaults
- ✅ Easy to rotate

## Setup Steps

### 1. Create a Service Account

1. Go to [1Password Service Accounts](https://pittampalli.1password.com/developer/infrastructure/serviceaccounts)
2. Click **Create Service Account**
3. Name it: `Container Git Access` (or similar)
4. Grant **Read** access to the **Employee** vault (or wherever your Git credentials are stored)
5. Copy the token (starts with `ops_...`)
6. **Save the token securely** - it won't be shown again!

### 2. Store the Token Securely

**❌ NEVER hardcode the token in scripts or configuration files!**

We provide three secure methods to manage the service account token:

#### Method 1: 1Password Secret References (RECOMMENDED)

Use 1Password's `op://` secret references to avoid ever exposing the token:

```bash
# Create .env.container file with secret reference (already created in this repo)
cat .env.container
# OP_SERVICE_ACCOUNT_TOKEN=op://CLI/Service Account Auth Token: developer/credential

# Use op run to automatically load the secret
op run --env-file .env.container -- git clone https://github.com/vpittamp/nixos-config.git

# Or start a dev shell with secrets loaded
./scripts/container-dev-shell
```

**Benefits:**
- ✅ Token never appears in plaintext
- ✅ No risk of committing secrets to Git
- ✅ Works with 1Password desktop app or CLI
- ✅ VS Code extension can help manage references

#### Method 2: Manual Environment Variable (Local Testing)

For quick local testing only:

```bash
# Temporarily export in your current shell (not saved to any file)
export OP_SERVICE_ACCOUNT_TOKEN='ops_...'

# Or use op run inline
op run -- sh -c 'export OP_SERVICE_ACCOUNT_TOKEN=$(op item get "Service Account Auth Token: developer" --vault CLI --fields credential); git clone https://github.com/vpittamp/nixos-config.git'
```

#### Method 3: Docker/Kubernetes Secrets

For container deployments:

**Docker:**
```bash
# Use secret reference in .env file
op run --env-file .env.container -- docker run --env-file .env.container mycontainer

# Or pass directly (for CI/CD with secrets management)
docker run -e OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" mycontainer
```

**Kubernetes:**
```yaml
# Create secret from 1Password
apiVersion: v1
kind: Secret
metadata:
  name: op-service-account
type: Opaque
stringData:
  token: ops_...  # Provision from CI/CD secrets or use 1Password Connect
---
# Reference in pod
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    env:
    - name: OP_SERVICE_ACCOUNT_TOKEN
      valueFrom:
        secretKeyRef:
          name: op-service-account
          key: token
```

### 3. Test the Setup

```bash
# Initialize and test
op-sa-init

# Test Git credential access
op-sa-test

# Try cloning a repo
git clone https://github.com/vpittamp/nixos-config.git
```

## How It Works

The container configuration includes a Git credential helper that:

1. Intercepts Git's credential requests
2. Checks for `OP_SERVICE_ACCOUNT_TOKEN` environment variable
3. Uses `op` CLI to fetch credentials from 1Password
4. Returns credentials to Git automatically

### Supported Git Hosts

- **GitHub**: Uses `Github Personal Access Token` from 1Password
- **GitLab**: Uses `GitLab Personal Access Token` from 1Password (if configured)
- **Other**: Falls back to GitHub token

## Container Image Build

When building container images, the service account token is already configured via the NixOS module.

Just ensure the token is available as an environment variable when running the container.

## Troubleshooting

### Error: "OP_SERVICE_ACCOUNT_TOKEN not set"

**Solution**: Export the token in your environment:
```bash
export OP_SERVICE_ACCOUNT_TOKEN='ops_...'
```

### Error: "Failed to authenticate with 1Password"

**Possible causes**:
1. Token is invalid or expired
2. Token doesn't have access to the required vault
3. Item names in 1Password don't match

**Solution**:
- Verify token is correct
- Check vault permissions in service account settings
- Ensure items are named exactly:
  - `Github Personal Access Token` (with fields `username` and `token`)
  - `GitLab Personal Access Token` (optional)

### Git still prompts for credentials

**Possible causes**:
1. Service account token not set
2. Credential helper not configured
3. Using SSH instead of HTTPS URLs

**Solution**:
- Run `op-sa-init` to verify setup
- Check `git config --get credential.helper`
- For SSH, see SSH key section below

## SSH Keys vs HTTPS Tokens

This setup uses **HTTPS with Personal Access Tokens (PAT)**.

If you prefer SSH keys:

1. Generate SSH key in container: `ssh-keygen -t ed25519 -C "vinod@pittampalli.com"`
2. Store private key in 1Password
3. Add public key to GitHub/GitLab
4. Use `git@github.com:...` URLs instead of `https://...`

For SSH keys, see the separate SSH container configuration module.

## Security Best Practices

1. **Minimal Permissions**: Service accounts should have read-only access
2. **Scope to Vaults**: Only grant access to vaults with Git credentials
3. **Rotate Regularly**: Regenerate service account tokens periodically
4. **Never Commit**: Never commit service account tokens to Git
5. **Use Secrets Management**: In production, use proper secrets management (Kubernetes Secrets, AWS Secrets Manager, etc.)
6. **Audit Access**: Review service account usage in 1Password admin console

## Example: Dev Container with Git Auth

```dockerfile
# Dockerfile
FROM nixos/nix:latest

# Your NixOS container configuration will handle the rest
# Just ensure OP_SERVICE_ACCOUNT_TOKEN is set when running

# Run with:
# docker run -e OP_SERVICE_ACCOUNT_TOKEN='ops_...' myimage
```

```bash
# Build and run
docker build -t mynixos .
docker run -it -e OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" mynixos

# Inside container
git clone https://github.com/vpittamp/nixos-config.git
# Credentials automatically fetched from 1Password!
```

## VS Code Integration

The 1Password VS Code extension makes working with secret references even easier:

### Installation

1. Install the [1Password for VS Code extension](https://marketplace.visualstudio.com/items?itemName=1Password.op-vscode)
2. Sign in to 1Password from VS Code
3. The extension will automatically detect `op://` references in your files

### Features

**Secret Reference Autocomplete:**
- Type `op://` and get autocomplete suggestions for vaults, items, and fields
- Hover over secret references to see item details
- Click to open items in 1Password desktop app

**Secret Detection:**
- Automatically detects potential secrets in code
- Suggests saving them to 1Password and replacing with references

**Preview Real Values:**
- Hover over `op://` references to preview actual values (without exposing them in plaintext)
- Inline secret viewing without leaving VS Code

### Using with .env Files

The extension works great with `.env.container`:

1. Open `/etc/nixos/.env.container` in VS Code
2. The extension will underline the `op://` reference
3. Hover to verify it points to the correct item
4. Use `op run` from the integrated terminal

## Helper Scripts

This repository includes helper scripts for working with container secrets:

### container-dev-shell

Start a development shell with all secrets loaded from 1Password:

```bash
./scripts/container-dev-shell
```

This script:
- Loads secrets from `.env.container` using `op run`
- Starts an interactive bash shell
- All commands in the shell have access to the service account token
- Perfect for testing container configurations locally

### Example Workflow

```bash
# Start dev shell with secrets
./scripts/container-dev-shell

# Inside the shell, Git auth works automatically
git clone https://github.com/vpittamp/private-repo.git

# Test container builds
nix build .#container-dev

# Load and test the container
docker load < result
docker run -it nixos-container:latest

# Exit when done
exit
```

## References

- [1Password Service Accounts Documentation](https://developer.1password.com/docs/service-accounts/)
- [1Password Secret References](https://developer.1password.com/docs/cli/secret-references/)
- [1Password for VS Code](https://developer.1password.com/docs/vscode/)
- [Git Credential Helpers](https://git-scm.com/docs/gitcredentials)
- [1Password CLI](https://developer.1password.com/docs/cli/)
