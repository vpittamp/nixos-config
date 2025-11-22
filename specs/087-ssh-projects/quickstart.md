# Quickstart Guide: Remote Project Environment Support

**Feature**: 087-ssh-projects | **Created**: 2025-11-22
**Status**: Implementation Planning Phase

## Overview

This feature enables i3pm to manage remote project environments via SSH. You can create projects that automatically launch terminal applications on remote hosts (like your Hetzner Cloud server) while maintaining all the project management workflows you're familiar with.

## What This Feature Provides

✅ **Remote Project Creation**: Define projects that live on remote servers
✅ **Automatic SSH Wrapping**: Terminal apps launch on remote host transparently
✅ **Project Context Preservation**: Scoped windows, workspace assignments work the same
✅ **Connectivity Testing**: Validate SSH access before working

❌ **Not Supported**: GUI applications (VS Code, Firefox) - use VS Code Remote-SSH extension instead

## Prerequisites

Before using remote projects, ensure:

1. **SSH Key Authentication**: Configure SSH keys between local and remote hosts
   ```bash
   # Generate SSH key if needed (on local machine)
   ssh-keygen -t ed25519 -C "your-email@example.com"

   # Copy public key to remote host
   ssh-copy-id vpittamp@hetzner-sway.tailnet

   # Test SSH connection (should not prompt for password)
   ssh vpittamp@hetzner-sway.tailnet 'echo OK'
   ```

2. **Tailscale (Recommended)**: For reliable connectivity
   ```bash
   # Check Tailscale status
   tailscale status | grep hetzner

   # Should show: hetzner-sway.tailnet  online  ...
   ```

3. **Remote Applications**: Ensure terminal apps installed on remote host
   ```bash
   # Check remote applications (run on remote host)
   ssh vpittamp@hetzner-sway.tailnet 'which ghostty lazygit yazi sesh'
   ```

## Quick Start Workflow

### 1. Create a Remote Project

```bash
i3pm project create-remote hetzner-dev \
    --local-dir ~/projects/hetzner-dev \
    --remote-host hetzner-sway.tailnet \
    --remote-user vpittamp \
    --remote-dir /home/vpittamp/dev/my-app
```

**What this does**:
- Creates project definition at `~/.config/i3/projects/hetzner-dev.json`
- Maps local directory `~/projects/hetzner-dev` (for reference, git checkouts)
- Sets remote working directory `/home/vpittamp/dev/my-app` (where apps will run)
- Enables remote mode automatically

**Optional flags**:
- `--port 2222`: Use non-standard SSH port
- `--display-name "Hetzner Development"`: Human-readable name
- `--icon 🌐`: Custom emoji icon

### 2. Switch to Remote Project

```bash
i3pm project switch hetzner-dev
```

**What this does**:
- Sets `hetzner-dev` as active project (same as local projects)
- Daemon updates project context
- Subsequent terminal app launches will use SSH wrapping

### 3. Launch Terminal Applications

Now use your familiar hotkeys - they automatically launch on the remote host:

| Hotkey | App | What Happens |
|--------|-----|--------------|
| `Win+T` | Terminal (ghostty) | Opens terminal via SSH on remote host in `/home/vpittamp/dev/my-app` |
| `Win+G` | Lazygit | Opens lazygit via SSH on remote host |
| `Win+Y` | Yazi | Opens yazi file manager via SSH on remote host |

**Behind the scenes**:
```bash
# What you press: Win+T
# What executes locally:
ghostty -e bash -c "ssh -t vpittamp@hetzner-sway.tailnet 'cd /home/vpittamp/dev/my-app && sesh connect /home/vpittamp/dev/my-app'"
```

### 4. Test Remote Connectivity (Optional)

```bash
i3pm project test-remote hetzner-dev
```

**Output (success)**:
```
✓ SSH Connection: OK (87ms)
✓ Remote Directory: /home/vpittamp/dev/my-app exists
✓ Authentication: SSH key accepted
```

**Output (failure - connection)**:
```
✗ SSH Connection: FAILED
  Error: ssh: connect to host hetzner-sway.tailnet port 22: Connection refused

Troubleshooting suggestions:
  - Check Tailscale is running: tailscale status
  - Verify host is online: ping hetzner-sway.tailnet
  - Check firewall allows SSH (port 22)
```

**Output (failure - directory)**:
```
✓ SSH Connection: OK (92ms)
✗ Remote Directory: /home/vpittamp/dev/my-app does not exist

Troubleshooting suggestions:
  - Create directory: ssh vpittamp@hetzner-sway.tailnet 'mkdir -p /home/vpittamp/dev/my-app'
  - Or clone project: ssh vpittamp@hetzner-sway.tailnet 'git clone <repo> /home/vpittamp/dev/my-app'
```

## Managing Remote Projects

### Convert Existing Project to Remote

```bash
# You have an existing local project "my-app"
i3pm project list | grep my-app

# Add remote configuration
i3pm project set-remote my-app \
    --host hetzner-sway.tailnet \
    --user vpittamp \
    --working-dir /home/vpittamp/dev/my-app
```

**What this preserves**:
- All existing project metadata (name, display_name, icon)
- Scoped window classes
- Workspace assignments

### Revert Remote Project to Local

```bash
i3pm project unset-remote hetzner-dev
```

**What this does**:
- Removes `remote` configuration from project JSON
- Project reverts to local-only mode
- All other project settings preserved

### Update Remote Configuration

```bash
# Change remote host
i3pm project set-remote hetzner-dev \
    --host new-server.tailnet \
    --user deploy \
    --working-dir /opt/app

# Change only port
i3pm project set-remote hetzner-dev \
    --host hetzner-sway.tailnet \
    --user vpittamp \
    --working-dir /home/vpittamp/dev/my-app \
    --port 2222
```

**Note**: `set-remote` requires all mandatory fields (`--host`, `--user`, `--working-dir`) even if only updating one field.

## Common Workflows

### Development on Remote Server

**Scenario**: You want to develop on powerful Hetzner server from M1 MacBook

```bash
# 1. Create remote project
i3pm project create-remote hetzner-dev \
    --local-dir ~/projects/hetzner-dev \
    --remote-host hetzner-sway.tailnet \
    --remote-user vpittamp \
    --remote-dir /home/vpittamp/dev/my-app

# 2. Test connectivity
i3pm project test-remote hetzner-dev

# 3. Switch to project
i3pm project switch hetzner-dev

# 4. Launch terminal (Win+T)
# Terminal opens on remote host in /home/vpittamp/dev/my-app

# 5. Work as normal - all terminal apps execute remotely
# - Win+G: Lazygit on remote
# - Win+Y: Yazi on remote
# - Commands in terminal: Execute on remote

# 6. Switch back to local project when done
i3pm project switch local-project
```

### Mixed Local + Remote Workflow

**Scenario**: VS Code locally, terminal tools remotely

```bash
# 1. Create remote project with only terminal apps scoped
i3pm project create-remote hetzner-dev \
    --local-dir ~/projects/hetzner-dev \
    --remote-host hetzner-sway.tailnet \
    --remote-user vpittamp \
    --remote-dir /home/vpittamp/dev/my-app

# 2. Edit project JSON to exclude VS Code from scoped_classes
# File: ~/.config/i3/projects/hetzner-dev.json
{
  "name": "hetzner-dev",
  "scoped_classes": ["Ghostty"],  # Only terminal scoped, VS Code not scoped
  "remote": {
    "enabled": true,
    "host": "hetzner-sway.tailnet",
    "user": "vpittamp",
    "working_dir": "/home/vpittamp/dev/my-app"
  }
}

# 3. Use VS Code Remote-SSH extension manually
code --remote ssh-remote+hetzner-sway.tailnet /home/vpittamp/dev/my-app

# 4. Terminal apps (Win+T, Win+G, Win+Y) execute on remote via i3pm
```

## Troubleshooting

### "Cannot connect to remote host"

**Symptoms**: `i3pm project test-remote` fails with connection error

**Check**:
1. Tailscale running: `tailscale status`
2. Host reachable: `ping hetzner-sway.tailnet`
3. SSH port open: `nc -zv hetzner-sway.tailnet 22`
4. Manual SSH works: `ssh vpittamp@hetzner-sway.tailnet 'echo OK'`

**Fix**:
```bash
# Start Tailscale if not running
sudo systemctl start tailscaled

# Check firewall on remote host
ssh vpittamp@hetzner-sway.tailnet 'sudo ufw status'
```

### "SSH authentication failed"

**Symptoms**: Connection refused with "Permission denied (publickey)"

**Check**:
1. SSH key exists locally: `ls ~/.ssh/id_ed25519.pub`
2. SSH key added to remote: `ssh vpittamp@hetzner-sway.tailnet 'cat ~/.ssh/authorized_keys'`
3. SSH agent has key: `ssh-add -l`

**Fix**:
```bash
# Copy SSH key to remote
ssh-copy-id vpittamp@hetzner-sway.tailnet

# Or manually add key
cat ~/.ssh/id_ed25519.pub | ssh vpittamp@hetzner-sway.tailnet 'cat >> ~/.ssh/authorized_keys'
```

### "Remote directory does not exist"

**Symptoms**: `test-remote` shows directory missing warning

**Fix**:
```bash
# Create directory on remote
ssh vpittamp@hetzner-sway.tailnet 'mkdir -p /home/vpittamp/dev/my-app'

# Or clone git repository
ssh vpittamp@hetzner-sway.tailnet 'git clone https://github.com/user/repo.git /home/vpittamp/dev/my-app'
```

### "Terminal app opens locally instead of remotely"

**Symptoms**: Terminal launches in local directory, not remote

**Check**:
1. Project is active: `i3pm project current`
2. Remote enabled: `cat ~/.config/i3/projects/hetzner-dev.json | jq '.remote.enabled'`
3. App launcher logs: `tail -f ~/.local/state/app-launcher.log | grep "Feature 087"`

**Fix**:
```bash
# Verify project configuration
i3pm project current --json | jq '.remote'

# Should show:
{
  "enabled": true,
  "host": "hetzner-sway.tailnet",
  "user": "vpittamp",
  "working_dir": "/home/vpittamp/dev/my-app",
  "port": 22
}

# Restart daemon if needed
systemctl --user restart i3-project-event-listener
```

### "Cannot launch VS Code / GUI apps"

**Error**: "Cannot launch GUI application 'vscode' in remote project. Remote projects only support terminal-based applications."

**This is expected** - GUI apps cannot be launched via simple SSH wrapping.

**Workarounds**:
1. **Use VS Code Remote-SSH extension**: Best solution for remote development
   ```bash
   code --remote ssh-remote+hetzner-sway.tailnet /home/vpittamp/dev/my-app
   ```

2. **Launch GUI apps locally**: Switch to local project or exclude from scoped_classes

3. **Use VNC for full remote desktop**: Connect to Hetzner via VNC, run entire i3pm session remotely

## Configuration Reference

### Project JSON Format (Remote)

```json
{
  "name": "hetzner-dev",
  "directory": "/home/vpittamp/projects/hetzner-dev",
  "display_name": "Hetzner Development",
  "icon": "🌐",
  "created_at": "2025-11-22T10:00:00.000Z",
  "updated_at": "2025-11-22T10:00:00.000Z",
  "scoped_classes": ["Ghostty"],
  "remote": {
    "enabled": true,
    "host": "hetzner-sway.tailnet",
    "user": "vpittamp",
    "working_dir": "/home/vpittamp/dev/my-app",
    "port": 22
  }
}
```

### SSH Configuration (Recommended)

Add to `~/.ssh/config` for optimal experience:

```
Host hetzner-sway.tailnet
    User vpittamp
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes
```

**Benefits**:
- No need to specify user in every command
- SSH agent forwarding (access local SSH keys remotely)
- Keep-alive prevents connection drops
- Compression speeds up terminal I/O

## What's Next?

After setting up remote projects:

1. **Create layouts**: `i3pm layout save main` (works with remote projects)
2. **Use scratchpad terminal**: `Win+Return` opens project-scoped terminal on remote
3. **Switch between local and remote**: `i3pm project switch <name>` transitions seamlessly

## Limitations

**Not Supported**:
- ❌ GUI applications (requires X11 forwarding, out of scope)
- ❌ Automatic SSH key distribution (manual setup required)
- ❌ Automatic remote directory creation (manual `mkdir` required)
- ❌ File synchronization between local and remote (use git/rsync)
- ❌ SSH password authentication (key-based only)

**Performance**:
- Remote terminal launch: 1-3 seconds (SSH connection + command execution)
- Local terminal launch: <500ms
- Network latency dependent (Tailscale typically <50ms on same continent)

## Related Documentation

- SSH Key Setup: `docs/SSH_KEY_SETUP.md` (if exists)
- Tailscale Configuration: `docs/TAILSCALE.md` (if exists)
- Project Management: Run `i3pm project --help` for full CLI reference
- Troubleshooting: `docs/TROUBLESHOOTING.md` (if exists)

## Support

For issues or questions:
1. Check logs: `tail -f ~/.local/state/app-launcher.log | grep "Feature 087"`
2. Test manually: `ssh vpittamp@hetzner-sway.tailnet 'cd /path && command'`
3. Validate project JSON: `jq . ~/.config/i3/projects/<name>.json`
