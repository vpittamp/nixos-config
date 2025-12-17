# Quickstart: eBPF-Based AI Agent Process Monitor

**Feature**: 119-explore-ebpf-monitor
**Date**: 2025-12-16

## Prerequisites

- NixOS with kernel 5.2+ (preferably 6.x for full BTF support)
- Sway window manager
- tmux terminal multiplexer
- Ghostty terminal emulator
- Claude Code and/or Codex CLI installed

## Quick Setup

### 1. Enable in NixOS Configuration

Add to your `configuration.nix`:

```nix
{
  # Enable eBPF AI monitor
  services.ebpf-ai-monitor = {
    enable = true;
    user = "your-username";  # Required: user to monitor
  };
}
```

### 2. Rebuild and Activate

```bash
# Test the configuration first (ALWAYS)
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply if successful
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### 3. Verify Service Running

```bash
# Check service status
sudo systemctl status ebpf-ai-monitor

# View logs
sudo journalctl -u ebpf-ai-monitor -f
```

## Configuration Options

```nix
services.ebpf-ai-monitor = {
  enable = true;                    # Required
  user = "vpittamp";                # Required: user to monitor

  # Optional settings
  processes = ["claude" "codex"];   # Process names to monitor (default)
  waitThreshold = 1000;             # ms before "waiting" state (default: 1000)
  logLevel = "info";                # debug, info, warn, error (default: info)
};
```

## Verifying Operation

### 1. Start an AI Session

```bash
# In a Ghostty terminal with tmux
tmux new-session -s test
claude  # or codex
```

### 2. Submit a Prompt

Type a prompt and press Enter. The monitor should:
- Detect the "claude" process
- Track it as "working"
- Create a badge file

### 3. Check Badge Files

```bash
# List badge files
ls -la "$XDG_RUNTIME_DIR/i3pm-badges/"

# View badge content
cat "$XDG_RUNTIME_DIR/i3pm-badges/"*.json | jq
```

### 4. Wait for Completion

When Claude finishes and waits for input:
- Badge state changes to "stopped"
- Desktop notification appears
- EWW panel shows attention indicator

## Troubleshooting

### Service Won't Start

```bash
# Check for errors
sudo journalctl -u ebpf-ai-monitor -n 50 --no-pager

# Verify BCC is available
which bpftrace
python3 -c "from bcc import BPF; print('BCC OK')"

# Check kernel support
uname -r  # Should be 5.2+
cat /boot/config-$(uname -r) | grep CONFIG_BPF
```

### No Events Detected

```bash
# Run bpftrace manually to test
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_read /args->fd == 0/ { printf("%s\n", comm); }'

# Then run claude in another terminal and verify output
```

### Badge Files Not Appearing

```bash
# Check badge directory exists
ls -la "$XDG_RUNTIME_DIR/i3pm-badges/"

# Check file permissions
stat "$XDG_RUNTIME_DIR/i3pm-badges/"

# Verify service is running as root
ps aux | grep ebpf-ai-monitor
```

### Notifications Not Working

```bash
# Test notify-send directly
notify-send "Test" "This is a test notification"

# Check SwayNC is running
systemctl --user status swaync

# Check D-Bus connection
dbus-send --print-reply --dest=org.freedesktop.Notifications \
  /org/freedesktop/Notifications org.freedesktop.Notifications.GetCapabilities
```

## Uninstalling

To disable the service:

```nix
{
  services.ebpf-ai-monitor.enable = false;
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#hetzner-sway
```

## Related Documentation

- [Feature Specification](./spec.md)
- [Implementation Plan](./plan.md)
- [Research Notes](./research.md)
- [Data Model](./data-model.md)
- [Badge State Contract](./contracts/badge-state.json)

## Support

For issues:
1. Check logs: `sudo journalctl -u ebpf-ai-monitor -f`
2. Verify prerequisites above
3. Open issue with log output and system info (`uname -a`, `nixos-version`)
