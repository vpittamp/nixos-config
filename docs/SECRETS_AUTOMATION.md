# Secrets Automation with 1Password

This document explains how we safely automate access to secrets (like service account tokens) using 1Password's secret reference system.

## Overview

Instead of hardcoding secrets in environment variables or configuration files, we use **1Password secret references** (`op://` URIs) that point to secrets stored in 1Password. The `op` CLI automatically resolves these references at runtime.

## Why This Approach?

### ✅ Benefits

- **Never expose secrets in plaintext** - Secret references are safe to commit to Git
- **Centralized secret management** - All secrets stored in 1Password
- **Auditable access** - 1Password tracks who accesses what
- **Easy rotation** - Update secret in 1Password, no code changes needed
- **Works everywhere** - Local development, containers, CI/CD
- **VS Code integration** - IDE support for autocomplete and validation

### ❌ What We Avoid

- Hardcoded secrets in scripts or config files
- Unencrypted .env files with real values
- Secrets scattered across multiple systems
- Risk of accidentally committing secrets to Git

## Secret Reference Syntax

1Password secret references use this format:

```
op://[vault]/[item]/[field]
op://[vault]/[item]/[section]/[field]
```

### Examples

```bash
# Reference by item name and field
op://CLI/Service Account Auth Token: developer/credential

# Reference by item ID (more stable if item is renamed)
op://CLI/zigifz54v7hsige3cdypqkqbpu/credential

# Reference GitHub token
op://Employee/Github Personal Access Token/token

# Reference with section
op://Employee/AWS/production/access_key
```

## How to Use

### Method 1: op run with .env Files (Recommended)

We provide a `.env.container` file with secret references:

```bash
# View the .env file (safe to display - no real secrets!)
cat .env.container
# Output:
# OP_SERVICE_ACCOUNT_TOKEN=op://CLI/Service Account Auth Token: developer/credential

# Run commands with secrets automatically loaded
op run --env-file .env.container -- git clone https://github.com/vpittamp/private-repo.git

# Start a dev shell with all secrets available
./scripts/container-dev-shell
```

### Method 2: Inline Secret Injection

```bash
# Run a single command with secrets
op run -- sh -c 'echo "Token starts with: ${OP_SERVICE_ACCOUNT_TOKEN:0:10}"'

# Use in scripts
op run --env-file .env.container -- ./scripts/build-container.sh
```

### Method 3: Export for Current Session

```bash
# Load secrets into current shell (temporary, not saved)
eval $(op run --env-file .env.container -- bash -c 'echo export OP_SERVICE_ACCOUNT_TOKEN=$OP_SERVICE_ACCOUNT_TOKEN')

# Now the secret is available in this shell session
echo "Token: ${OP_SERVICE_ACCOUNT_TOKEN:0:10}..."

# Session ends when you close the terminal
```

## VS Code Integration

### Installation

1. Install the [1Password for VS Code extension](https://marketplace.visualstudio.com/items?itemName=1Password.op-vscode)
2. The extension is already recommended in `.vscode/extensions.json`
3. Sign in to 1Password from VS Code

### Features

**Autocomplete:**
- Type `op://` and get autocomplete for vaults, items, and fields
- Tab completion for all components of secret references

**Validation:**
- Underlines `op://` references in files
- Hover to verify they point to valid items
- Red squiggles if reference is invalid

**Preview:**
- Hover over references to see real values (without exposing in plaintext)
- Click to open item in 1Password app

**Secret Detection:**
- Automatically detects hardcoded secrets in code
- Offers to save to 1Password and replace with reference

### Usage in VS Code

1. Open `.env.container` in VS Code
2. Place cursor after `op://`
3. Use autocomplete to select vault → item → field
4. Hover to verify the reference is correct
5. Use integrated terminal: `op run --env-file .env.container -- <command>`

## Container Deployments

### Docker

```bash
# Build container
nix build .#container-dev

# Load into Docker
docker load < result

# Run with secrets (using op run)
op run --env-file .env.container -- docker run -e OP_SERVICE_ACCOUNT_TOKEN nixos-container:latest

# Or in docker-compose.yml
# Use op run to start compose with secrets injected
op run --env-file .env.container -- docker-compose up
```

### Kubernetes

For Kubernetes, you have two options:

**Option 1: 1Password Kubernetes Operator**

Install the official operator to sync secrets from 1Password to Kubernetes Secrets.

**Option 2: External Secrets Provisioning**

Use your CI/CD system to provision secrets:

```yaml
# In CI/CD pipeline (GitHub Actions, GitLab CI, etc.)
# Use op CLI to fetch secret and create K8s secret
apiVersion: v1
kind: Secret
metadata:
  name: service-account-token
type: Opaque
stringData:
  token: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}  # Provisioned by CI/CD
```

## Helper Scripts

### container-dev-shell

Start a development shell with all secrets loaded:

```bash
./scripts/container-dev-shell
```

This script:
- Loads secrets from `.env.container` using `op run`
- Starts an interactive bash shell
- All commands have access to secrets
- Exits cleanly when you type `exit`

**Example session:**

```bash
$ ./scripts/container-dev-shell
🔐 Loading secrets from 1Password...
📁 Using env file: /etc/nixos/.env.container

✅ Secrets loaded successfully!

Environment variables:
  OP_SERVICE_ACCOUNT_TOKEN: ops_eyJzaW...

You can now use Git and other tools that need 1Password authentication.
Type 'exit' to leave this shell.

$ git clone https://github.com/vpittamp/private-repo.git
# Works! Credentials fetched from 1Password automatically

$ exit
```

## Security Best Practices

### ✅ Do This

1. **Use secret references everywhere** - Never hardcode secrets
2. **Commit .env files with references** - They're safe (no real secrets)
3. **Use service accounts for automation** - Follow principle of least privilege
4. **Scope vault access** - Service accounts should only access needed vaults
5. **Rotate secrets regularly** - Update in 1Password, no code changes needed
6. **Use 1Password audit logs** - Monitor secret access

### ❌ Never Do This

1. **Don't hardcode secrets in scripts** - Use `op://` references instead
2. **Don't commit .env files with real secrets** - Use references only
3. **Don't use personal accounts for automation** - Create service accounts
4. **Don't grant broad vault access** - Scope to specific vaults only
5. **Don't share service account tokens** - Create separate tokens per use case

## Getting Secret References

### Method 1: 1Password Desktop App

1. Open item in 1Password
2. Click the field you want to reference
3. Click "Copy Secret Reference" from the menu
4. Paste into your .env file

### Method 2: 1Password VS Code Extension

1. Type `op://` in VS Code
2. Use autocomplete to build the reference
3. Extension validates it in real-time

### Method 3: 1Password CLI

```bash
# List vaults
op vault list

# List items in a vault
op item list --vault CLI

# Get item details
op item get "Service Account Auth Token: developer" --vault CLI --format json

# The secret reference format is:
# op://CLI/Service Account Auth Token: developer/credential
```

### Method 4: Manual Construction

If you know the vault, item, and field names:

```
op://[vault name]/[item name]/[field name]
```

## How It Works

### op run Command Flow

1. `op run` scans the environment and command arguments
2. Finds all `op://` secret references
3. Authenticates to 1Password (using desktop app or service account)
4. Resolves each reference by fetching the secret value
5. Creates a subprocess with secrets injected as environment variables
6. Runs your command in that subprocess
7. Secrets are available only for the duration of the subprocess
8. Secrets are masked in output by default (use `--no-masking` to see them)

### Authentication Methods

**Desktop App (Local Development):**
- `op run` uses 1Password desktop app for authentication
- You stay signed in to 1Password on your machine
- Biometric unlock if enabled

**Service Account (Containers/CI):**
- Set `OP_SERVICE_ACCOUNT_TOKEN` environment variable
- Service account token authenticates `op` CLI
- No desktop app needed

## Troubleshooting

### Error: "Secret reference not found"

**Cause:** Item, vault, or field doesn't exist or you don't have access

**Solution:**
1. Verify the reference in 1Password desktop app
2. Check vault permissions
3. Use VS Code extension to validate reference
4. Check for typos in item/field names

### Error: "You are not currently signed in"

**Cause:** Not authenticated to 1Password

**Solution:**
```bash
# For desktop app users
op signin

# For service account users
export OP_SERVICE_ACCOUNT_TOKEN='ops_...'
```

### Secrets not loading in containers

**Cause:** Service account token not available

**Solution:**
1. Ensure `OP_SERVICE_ACCOUNT_TOKEN` is set
2. Verify service account has vault access
3. Check token hasn't expired
4. Test with: `op whoami`

## Examples

### Git Clone with Authentication

```bash
# Using op run
op run --env-file .env.container -- git clone https://github.com/vpittamp/private-repo.git
```

### Build and Deploy Container

```bash
# Build container with secrets
op run --env-file .env.container -- nix build .#container-dev

# Load and run
docker load < result
op run --env-file .env.container -- docker run -it nixos-container:latest
```

### Run Tests with API Keys

```bash
# Add API key reference to .env.container
echo "API_KEY=op://Employee/My API/token" >> .env.container

# Run tests with secret available
op run --env-file .env.container -- npm test
```

### CI/CD Pipeline

```yaml
# GitHub Actions example
name: Deploy
on: push

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install 1Password CLI
        uses: 1password/install-cli-action@v1

      - name: Load secrets and deploy
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          op run --env-file .env.container -- ./scripts/deploy.sh
```

## References

- [1Password Secret References Documentation](https://developer.1password.com/docs/cli/secret-references/)
- [1Password CLI Environment Variables](https://developer.1password.com/docs/cli/secrets-environment-variables/)
- [1Password for VS Code](https://developer.1password.com/docs/vscode/)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [Container Git Auth Guide](./CONTAINER_GIT_AUTH.md)
