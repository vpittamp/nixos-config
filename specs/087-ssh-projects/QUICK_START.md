# Feature 087: Remote Project Support - Quick Start

## Created Sample Project ✅

A sample remote project has been created:

**Project**: `remote-stacks`
- **Name**: Hetzner Stacks
- **Icon**: 📦
- **Local Directory**: `~/stacks`
- **Remote Host**: `hetzner-sway.tailnet`
- **Remote User**: `vpittamp`
- **Remote Directory**: `/home/vpittamp/stacks`

**Config File**: `~/.config/i3/projects/remote-stacks.json`

## Using the Remote Project

### Method 1: Using the Wrapper Script (Recommended for Now)

```bash
# Create new remote projects
./scripts/i3pm-remote project create-remote <name> \
  --local-dir <path> \
  --remote-host <host> \
  --remote-user <user> \
  --remote-dir <path>

# View help
./scripts/i3pm-remote --help
```

### Method 2: Switch to Remote Project (Existing i3pm Command)

```bash
# Switch to the remote project
i3pm project switch remote-stacks

# Verify it's active
i3pm project current

# Now when you launch terminal apps, they'll run on the remote host:
# Win+T → Terminal on hetzner-sway.tailnet:/home/vpittamp/stacks
# Win+G → Lazygit on remote host
# Win+Y → Yazi on remote host
```

### Method 3: Direct Deno CLI

```bash
deno run --allow-read --allow-write --allow-env \
  home-modules/tools/i3pm-cli/main.ts project create-remote <name> \
  --local-dir <path> \
  --remote-host <host> \
  --remote-user <user> \
  --remote-dir <path>
```

## Testing the SSH Wrapping

### 1. Switch to Remote Project
```bash
i3pm project switch remote-stacks
```

### 2. Launch Terminal Manually (to see SSH command)
```bash
# Enable debug mode to see the SSH command
DEBUG=1 app-launcher-wrapper.sh terminal
```

### 3. Check Logs
```bash
# View launcher logs for SSH wrapping
tail -f ~/.local/state/app-launcher.log | grep "Feature 087"
```

Expected log output:
```
[timestamp] DEBUG Feature 087: Remote enabled: true
[timestamp] DEBUG Feature 087: Remote host: vpittamp@hetzner-sway.tailnet:/home/vpittamp/stacks (port 22)
[timestamp] INFO Feature 087: Applying SSH wrapping for remote terminal app
[timestamp] INFO Feature 087: SSH command: ssh -t vpittamp@hetzner-sway.tailnet 'cd /home/vpittamp/stacks && ...'
```

### 4. Test with Keybindings (After NixOS Rebuild)

After running `sudo nixos-rebuild switch --flake .#m1 --impure`:

```bash
# Switch to remote project
i3pm project switch remote-stacks

# Press Win+T → Should open terminal on remote host
# Press Win+G → Should open lazygit on remote host
# Press Win+Y → Should open yazi on remote host
```

## Verifying the Setup

### Check Project JSON
```bash
cat ~/.config/i3/projects/remote-stacks.json | jq .remote
```

Expected output:
```json
{
  "enabled": true,
  "host": "hetzner-sway.tailnet",
  "user": "vpittamp",
  "working_dir": "/home/vpittamp/stacks",
  "port": 22
}
```

### Test SSH Connection Manually
```bash
# Verify you can SSH to the remote host
ssh -t vpittamp@hetzner-sway.tailnet 'cd /home/vpittamp/stacks && pwd'
```

Expected output:
```
/home/vpittamp/stacks
```

### Check if Remote Directory Exists
```bash
ssh vpittamp@hetzner-sway.tailnet 'test -d /home/vpittamp/stacks && echo "Directory exists" || echo "Directory missing"'
```

## Troubleshooting

### Project Created but Can't Switch
- Check if `~/stacks` exists locally: `ls -la ~/stacks`
- If not, create it: `mkdir -p ~/stacks`

### Terminal Doesn't Connect to Remote Host
1. **Check SSH connection**:
   ```bash
   ssh vpittamp@hetzner-sway.tailnet echo "Connection works"
   ```

2. **Verify Tailscale is running**:
   ```bash
   tailscale status | grep hetzner-sway
   ```

3. **Check launcher logs**:
   ```bash
   tail -50 ~/.local/state/app-launcher.log | grep -A 5 "Feature 087"
   ```

4. **Test SSH key authentication**:
   ```bash
   ssh -v vpittamp@hetzner-sway.tailnet
   # Should NOT prompt for password
   ```

### GUI App Rejection
If you try to launch a GUI app (like VS Code) in the remote project, you'll see:
```
Error: Feature 087: Cannot launch GUI application 'code' in remote project 'remote-stacks'.
  Remote projects only support terminal-based applications.

  Workarounds:
  - Use VS Code Remote-SSH extension for GUI editor access
  - Run GUI apps locally in global mode (i3pm project switch --clear)
  - Use VNC/RDP to access full remote desktop (see WayVNC setup)
```

## Next Steps

1. **Deploy Changes**:
   ```bash
   sudo nixos-rebuild switch --flake .#m1 --impure
   ```

2. **Test End-to-End**:
   - Switch to `remote-stacks` project
   - Launch terminal with Win+T
   - Verify it connects to `hetzner-sway.tailnet`
   - Verify working directory is `/home/vpittamp/stacks`

3. **Switch Back to Local**:
   ```bash
   i3pm project switch <local-project-name>
   # Or go to global mode:
   i3pm project clear
   ```

## Creating More Remote Projects

```bash
# Use the wrapper script
./scripts/i3pm-remote project create-remote <name> \
  --local-dir ~/projects/<name> \
  --remote-host hetzner-sway.tailnet \
  --remote-user vpittamp \
  --remote-dir /home/vpittamp/dev/<name> \
  --display-name "My Remote Project" \
  --icon "🚀"
```

## Files Created

- **Project JSON**: `~/.config/i3/projects/remote-stacks.json`
- **Wrapper Script**: `./scripts/i3pm-remote` (temporary, until integrated)

## Documentation

- **Comprehensive Guide**: `CLAUDE.md` (lines 345-456)
- **Implementation Details**: `specs/087-ssh-projects/IMPLEMENTATION_SUMMARY.md`
- **Technical Spec**: `specs/087-ssh-projects/spec.md`
