# GitHub Codespaces Git Authentication

This guide explains how Git authentication works in GitHub Codespaces and compares it to our 1Password service account approach.

## How Codespaces Authentication Works

### Automatic GITHUB_TOKEN

GitHub Codespaces provides automatic Git authentication through a built-in `GITHUB_TOKEN` environment variable:

**✅ Benefits:**
- Completely automatic - no setup required
- Refreshed on every codespace creation/restart
- TLS encrypted connections
- Integrated with GitHub CLI (`gh`)
- No credential management needed

**❌ Limitations:**
- **Only works for the repository where the codespace was created**
- No access to other private repositories by default
- Very restrictive permissions (intentional security design)
- Cannot easily switch tokens (gh CLI stays authenticated with GITHUB_TOKEN)
- Temporary - expires when codespace is deleted

### Token Scope

The `GITHUB_TOKEN` permissions depend on your access level:

| Your Access | Token Permissions |
|-------------|-------------------|
| Write access | Read/write to the repository |
| Read-only access | Limited initially, creates fork if you commit |

## Working with Multiple Repositories

If your codespace needs to access multiple private repositories (common in development), you have three options:

### Option 1: Fine-Grained Personal Access Token (GitHub Recommended)

Create a scoped token for specific repositories:

```bash
# 1. Create fine-grained PAT at:
# https://github.com/settings/tokens?type=beta

# 2. Add as Codespaces secret:
# https://github.com/settings/codespaces

# 3. Use in codespace:
git clone https://USERNAME:$GH_TOKEN@github.com/owner/repo.git

# Or with gh CLI:
export GH_TOKEN=$MY_PAT
gh repo clone owner/repo
```

**Pros:**
- Scoped to specific repositories
- Recommended by GitHub
- Works across all codespaces

**Cons:**
- Still uses hardcoded token (in GitHub Secrets)
- Manual token rotation required
- Token visible in Git config after clone

### Option 2: 1Password Service Account (Our Approach)

Use our existing 1Password automation:

```bash
# In codespace, install op CLI and use our .env.container
op run --env-file .env.container -- git clone https://github.com/owner/repo.git
```

**Pros:**
- Centralized secret management (1Password)
- Easy rotation (update in 1Password, no code changes)
- Audit trail of secret access
- Never hardcode tokens
- Works across all environments (local, containers, CI/CD)

**Cons:**
- Requires 1Password CLI installation
- Needs service account token provisioned
- Slightly more setup than GitHub's automatic method

### Option 3: Dev Container Permissions (Codespaces-Specific)

Request additional repository permissions in `devcontainer.json`:

```json
{
  "customizations": {
    "codespaces": {
      "repositories": {
        "owner/repo1": {
          "permissions": {
            "contents": "write"
          }
        },
        "owner/repo2": {
          "permissions": {
            "contents": "read"
          }
        }
      }
    }
  }
}
```

**Pros:**
- Declarative permissions
- Users prompted to authorize on codespace creation
- No manual token management

**Cons:**
- Only works in GitHub Codespaces (not local dev containers)
- Requires users to authorize each time
- Still limited to GitHub repositories

## Recommended Approach by Environment

### For GitHub Codespaces (Working on Our nixos-config)

**Best: Use built-in GITHUB_TOKEN**

The automatic `GITHUB_TOKEN` is sufficient for working on this repository:

```bash
# Just works automatically
git pull
git push
gh pr create
```

**No setup needed!** This is the simplest and most secure option for single-repository work.

### For Codespaces (Multi-Repository Work)

**Best: 1Password Service Account with Secret References**

If your codespace needs to access multiple private repositories:

1. **Install 1Password CLI in codespace:**

```bash
# Add to devcontainer.json or dotfiles
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list

sudo apt update && sudo apt install -y 1password-cli
```

2. **Add service account token as Codespaces secret:**

```bash
# At: https://github.com/settings/codespaces
# Name: OP_SERVICE_ACCOUNT_TOKEN
# Value: (the service account token from 1Password)
```

3. **Use op run for multi-repo Git operations:**

```bash
# Clone with authentication
op run --env-file .env.container -- git clone https://github.com/owner/private-repo.git

# Or start shell with secrets
op run --env-file .env.container -- bash
```

### For Local Dev Containers

**Best: 1Password Service Account with op run**

Use our existing `.env.container` setup:

```bash
# Start dev shell with secrets
./scripts/container-dev-shell

# Or use op run directly
op run --env-file .env.container -- git clone https://github.com/owner/repo.git
```

### For CI/CD (GitHub Actions, GitLab CI, etc.)

**Best: 1Password Service Account in CI Secrets**

```yaml
# GitHub Actions example
- name: Install 1Password CLI
  uses: 1password/install-cli-action@v1

- name: Clone repos with 1Password auth
  env:
    OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
  run: |
    op run --env-file .env.container -- git clone https://github.com/owner/repo.git
```

## Comparison Table

| Method | Setup Effort | Multi-Repo | Rotation | Audit | Works Offline |
|--------|-------------|------------|----------|-------|---------------|
| `GITHUB_TOKEN` (Codespaces) | None | ❌ No | ✅ Auto | ✅ Yes | ❌ No |
| Fine-grained PAT | Low | ✅ Yes | ❌ Manual | ⚠️ Limited | ✅ Yes |
| 1Password Service Account | Medium | ✅ Yes | ✅ Easy | ✅ Comprehensive | ✅ Yes (with cached auth) |
| Dev Container Permissions | Low | ⚠️ GitHub only | ✅ Auto | ✅ Yes | ❌ No |

## Simplified Recommendation

### Single Repository Work (This nixos-config)

**Just use GitHub Codespaces' automatic `GITHUB_TOKEN`** - no setup needed!

```bash
# Everything works automatically in codespace
git status
git pull
git push
gh pr create
```

### Multiple Repositories or Local Dev

**Use our 1Password automation:**

```bash
# In codespace or container
op run --env-file .env.container -- git clone https://github.com/owner/other-repo.git

# Or start a dev shell
./scripts/container-dev-shell
```

## devcontainer.json Configuration

To set up Codespaces with 1Password CLI pre-installed:

```json
{
  "name": "NixOS Development",
  "image": "nixos/nix:latest",

  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },

  "postCreateCommand": "bash .devcontainer/setup.sh",

  "customizations": {
    "vscode": {
      "extensions": [
        "1Password.op-vscode",
        "jnoortheen.nix-ide"
      ]
    }
  },

  "remoteEnv": {
    "OP_SERVICE_ACCOUNT_TOKEN": "${localEnv:OP_SERVICE_ACCOUNT_TOKEN}"
  }
}
```

Create `.devcontainer/setup.sh`:

```bash
#!/bin/bash
# Install 1Password CLI
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  tee /etc/apt/sources.list.d/1password.list

apt update && apt install -y 1password-cli

# Verify installation
op --version
```

## Best Practices

### ✅ Do This

1. **For single-repo Codespaces**: Trust GitHub's automatic `GITHUB_TOKEN`
2. **For multi-repo work**: Use 1Password service account with secret references
3. **Store service account token** in GitHub Codespaces Secrets (not in code)
4. **Use `op run`** to inject secrets only when needed
5. **Install 1Password VS Code extension** for easy secret reference management

### ❌ Avoid This

1. **Don't hardcode tokens** in devcontainer.json or scripts
2. **Don't commit .env files** with real token values (use secret references only)
3. **Don't manually update** `GITHUB_TOKEN` in Codespaces (it's managed by GitHub)
4. **Don't clone with embedded tokens** like `https://user:token@github.com/...` (visible in git config)

## Troubleshooting

### "Permission denied" when cloning other repos in Codespace

**Cause:** `GITHUB_TOKEN` only has access to the codespace's repository

**Solution:** Use one of the multi-repo methods above (1Password or fine-grained PAT)

### "Secret reference not found" when using op run

**Cause:** Service account token not set or doesn't have vault access

**Solution:**
```bash
# Verify token is set
echo ${OP_SERVICE_ACCOUNT_TOKEN:0:10}...

# Test authentication
op whoami

# Verify vault access
op vault list
```

### GitHub CLI keeps using GITHUB_TOKEN instead of my PAT

**Cause:** Codespaces gh CLI is hardcoded to use `GITHUB_TOKEN`

**Solution:** Use `GH_TOKEN` environment variable instead:
```bash
export GH_TOKEN=$MY_FINE_GRAINED_PAT
gh repo clone owner/repo
```

## Example Workflows

### Codespace for nixos-config (Single Repo)

```bash
# No setup needed - everything works automatically!
git clone https://github.com/vpittamp/nixos-config.git
cd nixos-config
git checkout -b feature-branch
# Make changes
git commit -am "Add feature"
git push
gh pr create
```

### Codespace with Multiple Private Repos

```bash
# 1. Ensure OP_SERVICE_ACCOUNT_TOKEN is in Codespaces secrets
# 2. Install op CLI (via dotfiles or postCreateCommand)

# 3. Use op run for multi-repo operations
op run --env-file .env.container -- bash -c '
  git clone https://github.com/vpittamp/nixos-config.git
  git clone https://github.com/vpittamp/private-project.git
  git clone https://github.com/company/internal-tools.git
'

# Or start an interactive shell
op run --env-file .env.container -- bash
```

## References

- [GitHub Codespaces Security](https://docs.github.com/en/codespaces/reference/security-in-github-codespaces)
- [Troubleshooting Repository Authentication](https://docs.github.com/en/codespaces/troubleshooting/troubleshooting-authentication-to-a-repository)
- [Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [Sharing Git Credentials with Containers](https://code.visualstudio.com/remote/advancedcontainers/sharing-git-credentials)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [Container Git Auth Guide](./CONTAINER_GIT_AUTH.md)
- [Secrets Automation Guide](./SECRETS_AUTOMATION.md)
