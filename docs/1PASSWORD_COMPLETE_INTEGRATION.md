# 1Password Comprehensive Integration Guide

## Current Status ✅

Your system is already configured with:
- ✅ 1Password desktop app running
- ✅ 1Password CLI integration active  
- ✅ hcloud plugin configured
- ✅ SSH agent using 1Password
- ✅ Git signing configured
- ✅ Firefox extension installed (via policy)

## Setup Remaining Integrations

### 1. GitHub CLI Plugin

**Purpose**: Biometric auth for all `gh` commands (repos, PRs, issues)

**Setup:**
```bash
# Ensure you have a GitHub Personal Access Token in 1Password
# Create item in 1Password:
#   Title: "GitHub CLI" or "GitHub Personal Access Token"
#   Type: API Credential
#   Field: token = ghp_your_token_here

# Initialize the plugin
op plugin init gh

# Follow the prompts:
# 1. Select the "GitHub CLI" item from 1Password
# 2. Choose: "Use as global default on my system"
# 3. Done!
```

**Test:**
```bash
# Reload shell
exec bash

# Test GitHub CLI with 1Password
gh repo list
# Should prompt for biometric auth first time
```

### 2. Argo CD Plugin (Optional)

**Purpose**: Biometric auth for Argo CD operations

**Setup (only if you use Argo CD):**
```bash
# Create item in 1Password:
#   Title: "Argo CD"
#   Type: API Credential  
#   Field: auth token = your_argocd_token

# Initialize the plugin
op plugin init argocd

# Test
argocd app list
```

### 3. Browser Extension Connection

**Verify it's connected:**
1. Open Firefox
2. Click 1Password icon in toolbar
3. Should show: "Connected to 1Password desktop app"
4. If not connected:
   - Open 1Password desktop
   - Settings → Browser
   - Enable "Connect with Firefox"
   
**Test auto-fill:**
1. Go to github.com (or any PWA)
2. Click in username/password field
3. 1Password icon should appear
4. Click to select credential
5. Authenticate with biometric
6. Auto-filled!

### 4. Git with 1Password

**Already configured!** The git.nix changes enable:
- ✅ Automatic commit signing (all commits will be signed)
- ✅ Git credential storage via 1Password
- ✅ No more gh/glab credential helpers needed

**Test:**
```bash
# Go to any git repo
cd /etc/nixos

# Make a test commit
git commit --allow-empty -m "test: 1Password integration"
# Should auto-sign with your SSH key from 1Password

# Push (if you have remote)
git push
# Should use 1Password credential helper
```

## What Was Removed (Duplicates)

### ❌ Removed from git.nix:
- `credential.helper = gh auth git-credential` (replaced with 1Password)
- `credential.helper = glab auth git-credential` (replaced with 1Password)
- `commit.gpgsign = false` (changed to `true`)

### ❌ Removed from onepassword-plugins.nix:
- `gh-direct()` function (redundant - use `gh` directly)
- `gh-auth()` function (replaced by plugin)
- `psql()` function wrapper (use plugin instead)
- `argocd()` function wrapper (use plugin instead)

### ✅ Replaced With:
- Single unified credential helper: `git-credential-1password`
- Automatic commit signing enabled
- Shell plugins for all CLI tools
- Auto-sourcing of ~/.config/op/plugins.sh

## Integration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ 1Password Desktop App (Running)                            │
│  ├─ SSH Agent (~/.1password/agent.sock)                    │
│  ├─ CLI Integration (biometric auth)                       │
│  └─ Browser Integration (auto-fill)                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Shell Plugins (~/.config/op/plugins.sh)                    │
│  ├─ alias hcloud="op plugin run -- hcloud"                │
│  ├─ alias gh="op plugin run -- gh" (to be added)          │
│  └─ alias argocd="op plugin run -- argocd" (to be added)  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Git Integration                                             │
│  ├─ Credential: git-credential-1password                   │
│  ├─ Signing: op-ssh-sign (SSH key from 1Password)         │
│  └─ Sign by default: true                                  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Browser Extension (Firefox)                                 │
│  ├─ Auto-fill for PWAs (GitHub, Azure, Hetzner, etc.)     │
│  ├─ Password generator                                     │
│  └─ Save new credentials                                   │
└─────────────────────────────────────────────────────────────┘
```

## Commands Summary

### Initialize Plugins
```bash
op plugin init gh        # GitHub CLI
op plugin init argocd    # Argo CD (optional)
```

### Test Integrations
```bash
# Shell plugins
hcloud server list       # Hetzner
gh repo list            # GitHub
argocd app list         # Argo CD

# Git
cd /etc/nixos
git commit --allow-empty -m "test"
git log --show-signature -1

# SSH
ssh-add -l              # List keys from 1Password

# Browser
# Open Firefox → visit github.com → test auto-fill
```

### Helper Commands
```bash
op-list                 # List all configured plugins
op-init <plugin>        # Initialize a new plugin
op vault list           # Verify CLI integration
```

## Benefits of This Setup

### Before (Fragmented):
- ❌ gh credential helper for GitHub
- ❌ glab credential helper for GitLab
- ❌ Manual plugin wrappers
- ❌ Commit signing disabled
- ❌ Multiple authentication methods

### After (Unified):
- ✅ One credential helper for everything (1Password)
- ✅ All commits automatically signed
- ✅ Biometric auth for all CLI tools
- ✅ Auto-fill in browser
- ✅ SSH keys from 1Password
- ✅ Consistent authentication everywhere

## Next Steps

1. **Initialize remaining plugins:**
   ```bash
   op plugin init gh
   # And optionally:
   op plugin init argocd
   ```

2. **Reload shell:**
   ```bash
   exec bash
   ```

3. **Test everything:**
   - Run `gh repo list`
   - Test Firefox auto-fill
   - Make a git commit
   - SSH to a server

4. **Remove old credentials (optional cleanup):**
   ```bash
   # Remove old gh auth
   gh auth logout
   
   # Remove old glab auth (if you used it)
   glab auth logout
   ```

All done! You now have a fully integrated 1Password setup.
