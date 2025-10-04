# SSH Agent Forwarding for Remote Git Operations

## Overview

SSH agent forwarding allows you to use your **local machine's** 1Password SSH agent when SSH'd into a remote NixOS machine. This enables git operations (push, pull, etc.) on the remote machine using your local 1Password credentials.

## How It Works

```
┌─────────────────┐     SSH with -A      ┌──────────────────┐
│  Local Machine  │ ─────────────────────>│  Remote Machine  │
│                 │                       │  (nixos-hetzner) │
│  1Password App  │  <── Agent Socket ──  │                  │
│  SSH Agent      │      Forwarded        │  Git Operations  │
└─────────────────┘                       └──────────────────┘
```

1. Your local machine runs 1Password desktop app with SSH agent
2. You SSH to remote machine with agent forwarding enabled (`ssh -A`)
3. Remote machine uses the forwarded agent for SSH operations
4. Git push/pull work transparently using your local 1Password keys

## Configuration

### Server Side (Already Configured)

**File:** `modules/services/networking.nix`

```nix
services.openssh.extraConfig = ''
  # SSH Agent Forwarding - allows remote git operations with local 1Password agent
  AllowAgentForwarding yes

  # Allow Unix domain socket forwarding for agent
  StreamLocalBindUnlink yes
'';
```

**Applies to:** All configurations (hetzner, m1, wsl)

### Client Side (Already Configured)

**File:** `home-modules/tools/ssh.nix`

```ssh
# Tailscale hosts - agent forwarding enabled
Host nixos-* *.tail*.ts.net
  User vpittamp
  IdentityAgent ~/.1password/agent.sock
  ForwardAgent yes
```

**Applies to:** All Tailscale hosts (nixos-hetzner, nixos-wsl, nixos-m1)

### Environment Variable Handling (Already Configured)

**File:** `home-modules/tools/onepassword-env.nix`

The configuration automatically detects if an SSH agent is forwarded:

```bash
# Only set local 1Password agent if not already forwarded
if [ -z "$SSH_AUTH_SOCK" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
  export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
fi
```

## Usage

### From Your Local Machine

**Automatic forwarding (Tailscale hosts):**
```bash
# Agent forwarding is automatic for Tailscale hosts
ssh nixos-hetzner

# Verify agent is forwarded
ssh-add -l
# Should show your local 1Password keys
```

**Manual forwarding (other hosts):**
```bash
# Use -A flag to enable agent forwarding
ssh -A user@hostname

# Or add to ~/.ssh/config:
Host myserver
  ForwardAgent yes
```

### On Remote Machine

Once SSH'd in with agent forwarding:

```bash
# Check agent is available
echo $SSH_AUTH_SOCK
# Should show: /tmp/ssh-XXXXXX/agent.XXXX (forwarded)
# NOT: ~/.1password/agent.sock (local)

# List available keys
ssh-add -l
# Shows your local 1Password keys

# Git operations work transparently
cd /path/to/repo
git pull
git push  # Uses forwarded 1Password keys!
```

## Verification

### Test Agent Forwarding

```bash
# From local machine, SSH to remote
ssh nixos-hetzner

# On remote machine, test agent
ssh-add -l
# Expected: Lists your local 1Password SSH keys

# Test GitHub SSH
ssh -T git@github.com
# Expected: "Hi <username>! You've successfully authenticated..."

# Test git push
cd /etc/nixos
git push
# Expected: Push succeeds using your local 1Password keys
```

## Security Considerations

### ✅ Safe Practices

- **Trust the remote host** - Only forward to machines you control
- **Use Tailscale** - VPN ensures encrypted connection
- **Short-lived sessions** - Agent forwarding only lasts during SSH session
- **No credential storage** - Keys never leave your local machine

### ⚠️ Risks (Mitigated)

- **Socket hijacking** - If remote host is compromised, attacker could use agent
  - **Mitigation:** Only forward to trusted machines (your NixOS systems)
- **Agent abuse** - Root on remote host could access forwarded agent
  - **Mitigation:** Don't forward to shared/multi-user systems

### 🔒 Best Practices

1. **Only enable ForwardAgent for trusted hosts:**
   ```ssh
   # Good: Specific trusted hosts
   Host nixos-hetzner
     ForwardAgent yes

   # Bad: All hosts
   Host *
     ForwardAgent yes  # Don't do this!
   ```

2. **Use Tailscale** - Ensures private, encrypted connections

3. **Monitor SSH keys** - `ssh-add -l` to verify what's accessible

4. **Use per-session forwarding** - Prefer `ssh -A` over config when testing

## Troubleshooting

### Agent Not Forwarded

**Symptom:** `ssh-add -l` shows "Could not open a connection to your authentication agent"

**Solutions:**
1. Ensure you're using `-A` flag: `ssh -A nixos-hetzner`
2. Verify server config: `grep AllowAgentForwarding /etc/ssh/sshd_config`
3. Check client config: `grep ForwardAgent ~/.ssh/config`
4. Rebuild if needed: `sudo nixos-rebuild switch --flake .#hetzner`

### Wrong Agent Used

**Symptom:** `$SSH_AUTH_SOCK` points to `~/.1password/agent.sock` (local, not forwarded)

**Solution:** The environment config should auto-detect. If not:
```bash
# Manually unset local agent in SSH session
unset SSH_AUTH_SOCK
# SSH will use the forwarded agent
```

### Git Push Fails

**Symptom:** "Permission denied (publickey)"

**Debug:**
```bash
# Check which agent is active
echo $SSH_AUTH_SOCK
# Should be /tmp/ssh-XXXXXX/agent.XXXX (forwarded)

# List available keys
ssh-add -l
# Should show your GitHub key

# Test GitHub connection
ssh -vT git@github.com
# Look for "Offering public key" with your key
```

## Alternative: Without Agent Forwarding

If you prefer not to use agent forwarding:

### Option 1: GitHub Personal Access Token

```bash
# Use HTTPS with token instead of SSH
git remote set-url origin https://github.com/user/repo.git

# Configure credential helper
git config --global credential.helper 'cache --timeout=3600'

# On first push, enter token as password
# Token stored in cache for 1 hour
```

### Option 2: Separate SSH Key on Server

```bash
# Generate key on server
ssh-keygen -t ed25519 -C "server-key"

# Add to GitHub as separate key
cat ~/.ssh/id_ed25519.pub
# Add to GitHub Settings > SSH Keys

# Configure git
git config --global core.sshCommand "ssh -i ~/.ssh/id_ed25519"
```

## Current Status

✅ **Fully Configured** - Agent forwarding works out of the box for:
- nixos-hetzner (via Tailscale)
- nixos-wsl (via Tailscale)
- nixos-m1 (via Tailscale)

**Usage:**
```bash
ssh nixos-hetzner  # Agent automatically forwarded
cd /etc/nixos
git push           # Works with local 1Password keys!
```

## References

- [OpenSSH Agent Forwarding](https://www.ssh.com/academy/ssh/agent)
- [1Password SSH Agent](https://developer.1password.com/docs/ssh/)
- [GitHub SSH Authentication](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
